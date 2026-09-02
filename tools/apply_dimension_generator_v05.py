#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DIMENSION GENERATOR V0.4 - PROJECTED CURVES + CONTROLLED BISECTORS + CHAINS',
              'DIMENSION GENERATOR V0.5 - TOPOLOGY-GUIDED BISECTORS + CHAINS')
s = s.replace('"DimensionGenerator V0.4"', '"DimensionGenerator V0.5"')
s = s.replace('"DimensionGenerator V0.4 failed:"', '"DimensionGenerator V0.5 failed:"')
s = s.replace('V0.4 staged mode: attachment dimensions remain deferred until normal spool chains/centerlines are verified.',
              'V0.5 staged mode: attachment dimensions remain deferred until topology-guided fitting centerlines are verified.')

# Improve unresolved logging so we can see which semantic fitting is missing.
old_log = '''        If anchor.Intent Is Nothing Then
            unresolved += 1
            Logger.Error( _
                "No projected geometry for semantic anchor at model mm (" & _
                Num(anchor.X) & ", " & Num(anchor.Y) & ", " & Num(anchor.Z) & ")")
        End If'''
new_log = '''        If anchor.Intent Is Nothing Then
            unresolved += 1

            Dim nearNode As NodeRecord = _
                FindReferenceNodeAtPointV03( _
                    nodes, anchor.X, anchor.Y, anchor.Z, 1.0)

            Dim semanticName As String = "UNKNOWN"
            If nearNode IsNot Nothing Then
                semanticName = _
                    nearNode.Code & "/" & nearNode.ComponentType & "/" & nearNode.ReferenceType
            End If

            Logger.Error( _
                "No projected geometry for semantic anchor " & semanticName & _
                " at model mm (" & _
                Num(anchor.X) & ", " & Num(anchor.Y) & ", " & Num(anchor.Z) & ")")
        End If'''
if old_log in s:
    s = s.replace(old_log, new_log)

# Replace fitting centre resolver to use topology-guided axis bisectors.
start = s.index('Function ResolveFittingCenterIntentV04(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_resolver = r'''Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' ===============================================================
    ' V0.5
    ' Use the fitting's USED topology port axes to tell Inventor which
    ' centreline directions we actually need.  For each visible axis we
    ' search the fitting + directly connected occurrences for the two
    ' projected silhouette lines parallel to that axis and create the
    ' native Inventor Centerline using Centerlines.AddBisector.
    ' ===============================================================

    Dim centerlines As List(Of Centerline) = _
        CreateTopologyGuidedBisectorsV05( _
            sheet, _
            view, _
            node, _
            target)

    If centerlines.Count >= 2 Then
        For i As Integer = 0 To centerlines.Count - 2
            For j As Integer = i + 1 To centerlines.Count - 1

                If CenterlinesParallelV03( _
                    centerlines.Item(i), _
                    centerlines.Item(j)) Then
                    Continue For
                End If

                Try
                    Return _
                        sheet.CreateGeometryIntent( _
                            centerlines.Item(i), _
                            centerlines.Item(j))
                Catch ex As Exception
                    Logger.Error( _
                        "Centerline intersection intent failed for " & _
                        node.Code & ": " & ex.Message)
                End Try
            Next
        Next
    End If

    If centerlines.Count = 1 Then
        Try
            Return sheet.CreateGeometryIntent(centerlines.Item(0))
        Catch ex As Exception
            Logger.Error( _
                "Single centerline intent failed for " & _
                node.Code & ": " & ex.Message)
        End Try
    End If

    Return Nothing
End Function'''
s = s[:start] + new_resolver + s[end:]

# Replace V0.4 generic bisector creation with topology-axis-guided search.
start = s.index('Function CreateControlledBisectorsV04(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_bisectors = r'''Function CreateTopologyGuidedBisectorsV05( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As List(Of Centerline)

    Dim result As New List(Of Centerline)

    If node Is Nothing OrElse _
       node.Occurrence Is Nothing OrElse _
       target Is Nothing Then
        Return result
    End If

    Dim axes As List(Of AxisDirectionV05) = _
        GetVisibleTopologyAxesV05( _
            view, _
            node, _
            target)

    Logger.Info( _
        "Centerline search " & node.Code & _
        " visible topology axes=" & axes.Count.ToString())

    If axes.Count = 0 Then Return result

    Dim occurrences As New List(Of ComponentOccurrence)
    occurrences.Add(node.Occurrence)

    For Each neighbour As NodeRecord In node.Neighbours
        If neighbour IsNot Nothing AndAlso _
           neighbour.Occurrence IsNot Nothing Then

            Dim alreadyAdded As Boolean = False
            For Each existing As ComponentOccurrence In occurrences
                If existing Is neighbour.Occurrence Then
                    alreadyAdded = True
                    Exit For
                End If
            Next

            If Not alreadyAdded Then
                occurrences.Add(neighbour.Occurrence)
            End If
        End If
    Next

    For Each axis As AxisDirectionV05 In axes

        Dim pair As AxisLinePairV05 = _
            FindBestSilhouettePairForAxisV05( _
                view, _
                occurrences, _
                target, _
                axis.UX, _
                axis.UY)

        If pair Is Nothing Then
            Logger.Error( _
                "No silhouette pair found for " & node.Code & _
                " axis=" & Num(axis.UX) & "," & Num(axis.UY))
            Continue For
        End If

        Try
            Dim intentA As GeometryIntent = _
                sheet.CreateGeometryIntent(pair.A)
            Dim intentB As GeometryIntent = _
                sheet.CreateGeometryIntent(pair.B)

            Dim cl As Centerline = _
                sheet.Centerlines.AddBisector( _
                    intentA, _
                    intentB)

            If cl Is Nothing Then Continue For

            Dim clx As Double = cl.EndPoint.X - cl.StartPoint.X
            Dim cly As Double = cl.EndPoint.Y - cl.StartPoint.Y
            Dim clLength As Double = Math.Sqrt(clx * clx + cly * cly)

            If clLength < 0.0001 Then
                Try : cl.Delete() : Catch : End Try
                Continue For
            End If

            clx /= clLength : cly /= clLength

            Dim directionAlignment As Double = _
                Math.Abs(clx * axis.UX + cly * axis.UY)

            Dim centreError As Double = _
                DistancePointToInfiniteLineV03( _
                    target, _
                    cl.StartPoint, _
                    cl.EndPoint)

            If directionAlignment < 0.96 OrElse _
               centreError > 0.16 Then

                Logger.Error( _
                    "Rejected bisector for " & node.Code & _
                    " alignment=" & Num(directionAlignment) & _
                    " centreError=" & Num(centreError))

                Try : cl.Delete() : Catch : End Try
                Continue For
            End If

            TagAutoObjectV01(cl)
            result.Add(cl)

            Logger.Info( _
                "Created topology-guided bisector for " & _
                node.Code & _
                " axis=" & Num(axis.UX) & "," & Num(axis.UY) & _
                " pairScore=" & Num(pair.Score))

        Catch ex As Exception
            Logger.Error( _
                "AddBisector failed for " & _
                node.Code & _
                " axis=" & Num(axis.UX) & "," & Num(axis.UY) & _
                ": " & ex.Message)
        End Try

    Next

    Return result
End Function


Function GetVisibleTopologyAxesV05( _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As List(Of AxisDirectionV05)

    Dim result As New List(Of AxisDirectionV05)

    If node Is Nothing Then Return result

    For Each port As PortRecord In node.Ports

        If Not port.Used Then Continue For

        Dim p0 As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                node.RefX / 10.0, _
                node.RefY / 10.0, _
                node.RefZ / 10.0)

        Dim p1 As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                (node.RefX + port.NX * 100.0) / 10.0, _
                (node.RefY + port.NY * 100.0) / 10.0, _
                (node.RefZ + port.NZ * 100.0) / 10.0)

        Dim s0 As Point2d = view.ModelToSheetSpace(p0)
        Dim s1 As Point2d = view.ModelToSheetSpace(p1)

        Dim ux As Double = s1.X - s0.X
        Dim uy As Double = s1.Y - s0.Y
        Dim l As Double = Math.Sqrt(ux * ux + uy * uy)

        ' Port axis nearly normal to the drawing view: no useful 2D centreline.
        If l < 0.02 Then Continue For

        ux /= l : uy /= l

        ' Normalise sign so opposite port normals collapse to one axis.
        If ux < -0.0001 OrElse _
           (Math.Abs(ux) <= 0.0001 AndAlso uy < 0) Then
            ux *= -1.0
            uy *= -1.0
        End If

        Dim duplicate As Boolean = False
        For Each existing As AxisDirectionV05 In result
            Dim dot As Double = _
                Math.Abs(existing.UX * ux + existing.UY * uy)
            If dot > 0.97 Then
                duplicate = True
                Exit For
            End If
        Next

        If Not duplicate Then
            Dim a As New AxisDirectionV05
            a.UX = ux
            a.UY = uy
            result.Add(a)
        End If

    Next

    Return result
End Function


Function FindBestSilhouettePairForAxisV05( _
    view As DrawingView, _
    occurrences As List(Of ComponentOccurrence), _
    target As Point2d, _
    axisUX As Double, _
    axisUY As Double) As AxisLinePairV05

    Dim lines As New List(Of DrawingCurve)

    For Each occ As ComponentOccurrence In occurrences
        Try
            Dim curves As DrawingCurvesEnumerator = _
                view.DrawingCurves(occ)

            If curves Is Nothing Then Continue For

            For Each c As DrawingCurve In curves
                If c.CurveType <> CurveTypeEnum.kLineSegmentCurve Then
                    Continue For
                End If

                If c.StartPoint Is Nothing OrElse c.EndPoint Is Nothing Then
                    Continue For
                End If

                Dim dx As Double = c.EndPoint.X - c.StartPoint.X
                Dim dy As Double = c.EndPoint.Y - c.StartPoint.Y
                Dim l As Double = Math.Sqrt(dx * dx + dy * dy)

                If l < 0.10 Then Continue For

                dx /= l : dy /= l

                Dim alignment As Double = _
                    Math.Abs(dx * axisUX + dy * axisUY)

                If alignment < 0.96 Then Continue For

                lines.Add(c)
            Next

        Catch ex As Exception
            Logger.Error( _
                "DrawingCurves occurrence scan failed for centerline pair: " & _
                occ.Name & ": " & ex.Message)
        End Try
    Next

    Dim best As AxisLinePairV05 = Nothing
    Dim bestScore As Double = Double.MaxValue

    For i As Integer = 0 To lines.Count - 2
        For j As Integer = i + 1 To lines.Count - 1

            Dim a As DrawingCurve = lines.Item(i)
            Dim b As DrawingCurve = lines.Item(j)

            If Not DrawingLinesParallelV03(a, b) Then Continue For

            Dim da As Double = _
                SignedDistanceToLineV03( _
                    target, a.StartPoint, a.EndPoint)
            Dim db As Double = _
                SignedDistanceToLineV03( _
                    target, b.StartPoint, b.EndPoint)

            ' Correct pipe silhouettes must sit on opposite sides of axis.
            If da * db >= 0 Then Continue For

            Dim absA As Double = Math.Abs(da)
            Dim absB As Double = Math.Abs(db)
            Dim separation As Double = absA + absB

            If separation < 0.04 Then Continue For

            Dim symmetryError As Double = Math.Abs(absA - absB)
            Dim symmetryTolerance As Double = _
                Math.Max(0.10, separation * 0.28)

            If symmetryError > symmetryTolerance Then Continue For

            Dim segA As Double = _
                DistancePointToSegmentV03( _
                    target, a.StartPoint, a.EndPoint)
            Dim segB As Double = _
                DistancePointToSegmentV03( _
                    target, b.StartPoint, b.EndPoint)

            ' Allow the selected neighbour pipe lines to terminate near the
            ' fitting centre rather than requiring the centre to lie within
            ' the finite line segment itself.
            Dim endpointPenaltyA As Double = Math.Max(0.0, segA - absA)
            Dim endpointPenaltyB As Double = Math.Max(0.0, segB - absB)

            If endpointPenaltyA > 0.90 OrElse endpointPenaltyB > 0.90 Then
                Continue For
            End If

            Dim score As Double = _
                symmetryError * 4.0 + _
                endpointPenaltyA + _
                endpointPenaltyB + _
                separation * 0.02

            If score < bestScore Then
                bestScore = score
                best = New AxisLinePairV05
                best.A = a
                best.B = b
                best.Score = score
            End If

        Next
    Next

    Return best
End Function


Class AxisDirectionV05
    Public UX As Double
    Public UY As Double
End Class


Class AxisLinePairV05
    Public A As DrawingCurve = Nothing
    Public B As DrawingCurve = Nothing
    Public Score As Double
End Class'''
s = s[:start] + new_bisectors + s[end:]

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.5 topology-guided centerline search')
