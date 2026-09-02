#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DIMENSION GENERATOR V0.3.1 - SAFE PROJECTED CURVES ONLY',
              'DIMENSION GENERATOR V0.4 - PROJECTED CURVES + CONTROLLED BISECTORS + CHAINS')
s = s.replace('"DimensionGenerator V0.3.1"', '"DimensionGenerator V0.4"')
s = s.replace('"DimensionGenerator V0.3.1 failed:"', '"DimensionGenerator V0.4 failed:"')
s = s.replace('"Projected-curve linear dimensions: " & chainCount.ToString() & vbCrLf & _',
              '"Chain dimension sets / fallback dims: " & chainCount.ToString() & vbCrLf & _')

# Replace only the conservative V0.3.1 resolver.  Port/face anchors continue to
# use the already-proven real projected curves.  Only unresolved TEE/ELBOW
# reference centres are allowed to create controlled native bisector centerlines.
start = s.index('Function ResolveProjectedIntentV03(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_resolver = r'''Function ResolveProjectedIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchor As AutoDimAnchorV01) As GeometryIntent

    ' ===============================================================
    ' V0.4 CONTROLLED RESOLUTION
    '
    ' 1) Real port/face anchors -> ACTUAL projected DrawingCurve.
    ' 2) TEE / ELBOW theoretical centre -> create at most two native
    '    AddBisector centerlines from opposite parallel projected lines
    '    of THAT occurrence only, then use their intersection.
    '
    ' NO automated-centerline command and NO global centerline search.
    ' ===============================================================

    Dim port As PortRecord = _
        FindPortAtModelPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.6)

    If port IsNot Nothing AndAlso _
       port.Owner IsNot Nothing AndAlso _
       port.Owner.Occurrence IsNot Nothing Then

        Dim projectedIntent As GeometryIntent = _
            FindOccurrenceDrawingIntentV031( _
                sheet, _
                view, _
                port.Owner.Occurrence, _
                anchor.SheetPoint)

        If projectedIntent IsNot Nothing Then
            anchor.SourceDescription = _
                port.Owner.Code & " PROJECTED CURVE NEAR FACE " & _
                port.FaceIndex.ToString()
            Return projectedIntent
        End If
    End If

    Dim refNode As NodeRecord = _
        FindReferenceNodeAtPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.8)

    If refNode Is Nothing Then Return Nothing

    If refNode.ComponentType <> "TEE" AndAlso _
       refNode.ComponentType <> "ELBOW" Then
        Return Nothing
    End If

    Dim centreIntent As GeometryIntent = _
        ResolveFittingCenterIntentV04( _
            sheet, _
            view, _
            refNode, _
            anchor.SheetPoint)

    If centreIntent IsNot Nothing Then
        anchor.SourceDescription = _
            refNode.Code & " NATIVE BISECTOR CENTERLINE"
    End If

    Return centreIntent
End Function'''
s = s[:start] + new_resolver + s[end:]

# Insert controlled bisector helpers immediately before FindPortAtModelPointV03.
insert_at = s.index('Function FindPortAtModelPointV03(')
helpers = r'''

Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    Dim centerlines As List(Of Centerline) = _
        CreateControlledBisectorsV04( _
            sheet, _
            view, _
            node, _
            target)

    If centerlines.Count >= 2 Then
        Try
            If Not CenterlinesParallelV03( _
                centerlines.Item(0), _
                centerlines.Item(1)) Then

                ' Sheet.CreateGeometryIntent supports an intersecting geometry
                ' as the Intent argument.  This gives a true centre point at
                ' the intersection of the two native Inventor centerlines.
                Return _
                    sheet.CreateGeometryIntent( _
                        centerlines.Item(0), _
                        centerlines.Item(1))
            End If
        Catch ex As Exception
            Logger.Error( _
                "Centerline intersection intent failed for " & _
                node.Code & ": " & ex.Message)
        End Try
    End If

    If centerlines.Count >= 1 Then
        Try
            ' One bisector is still useful as a datum line for a dimension
            ' normal to that axis.
            Return sheet.CreateGeometryIntent(centerlines.Item(0))
        Catch ex As Exception
            Logger.Error( _
                "Centerline intent failed for " & _
                node.Code & ": " & ex.Message)
        End Try
    End If

    Return Nothing
End Function


Function CreateControlledBisectorsV04( _
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

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(node.Occurrence)

        If curves Is Nothing OrElse curves.Count < 2 Then
            Return result
        End If

        Dim lines As New List(Of DrawingCurve)

        For Each c As DrawingCurve In curves
            If c.CurveType <> CurveTypeEnum.kLineSegmentCurve Then
                Continue For
            End If

            If c.StartPoint Is Nothing OrElse c.EndPoint Is Nothing Then
                Continue For
            End If

            Dim lineLength As Double = _
                SheetPointDistanceV03( _
                    c.StartPoint, _
                    c.EndPoint)

            ' Ignore tiny seam/detail lines.  We want the two opposite
            ' silhouette lines defining a pipe/fitting axis.
            If lineLength < 0.12 Then Continue For

            lines.Add(c)
        Next

        If lines.Count < 2 Then Return result

        Dim candidates As New List(Of BisectorCandidateV04)

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

                ' The semantic fitting centre must lie between the two lines.
                If da * db >= 0 Then Continue For

                Dim absA As Double = Math.Abs(da)
                Dim absB As Double = Math.Abs(db)
                Dim separation As Double = absA + absB

                If separation < 0.05 Then Continue For

                ' Centre should be approximately midway between silhouettes.
                Dim symmetryError As Double = Math.Abs(absA - absB)
                Dim symmetryTolerance As Double = _
                    Math.Max(0.08, separation * 0.20)

                If symmetryError > symmetryTolerance Then Continue For

                ' Reject parallel lines whose finite segments are nowhere near
                ' this fitting centre, even though their infinite lines pass it.
                Dim segA As Double = _
                    DistancePointToSegmentV03( _
                        target, a.StartPoint, a.EndPoint)
                Dim segB As Double = _
                    DistancePointToSegmentV03( _
                        target, b.StartPoint, b.EndPoint)

                If segA > absA + 0.40 OrElse _
                   segB > absB + 0.40 Then
                    Continue For
                End If

                Dim ux As Double = a.EndPoint.X - a.StartPoint.X
                Dim uy As Double = a.EndPoint.Y - a.StartPoint.Y
                Dim ul As Double = Math.Sqrt(ux * ux + uy * uy)
                If ul < 0.0001 Then Continue For
                ux /= ul : uy /= ul

                ' Direction sign is irrelevant for grouping.
                If ux < -0.0001 OrElse _
                   (Math.Abs(ux) <= 0.0001 AndAlso uy < 0) Then
                    ux *= -1.0
                    uy *= -1.0
                End If

                Dim candidate As New BisectorCandidateV04
                candidate.A = a
                candidate.B = b
                candidate.UX = ux
                candidate.UY = uy
                candidate.Score = _
                    symmetryError + _
                    (segA - absA) + _
                    (segB - absB)

                candidates.Add(candidate)
            Next
        Next

        SortBisectorCandidatesV04(candidates)

        Dim usedUX As New List(Of Double)
        Dim usedUY As New List(Of Double)

        For Each candidate As BisectorCandidateV04 In candidates

            Dim duplicateDirection As Boolean = False

            For k As Integer = 0 To usedUX.Count - 1
                Dim directionDot As Double = _
                    Math.Abs( _
                        candidate.UX * usedUX.Item(k) + _
                        candidate.UY * usedUY.Item(k))

                If directionDot > 0.96 Then
                    duplicateDirection = True
                    Exit For
                End If
            Next

            If duplicateDirection Then Continue For

            Try
                Dim intentA As GeometryIntent = _
                    sheet.CreateGeometryIntent(candidate.A)
                Dim intentB As GeometryIntent = _
                    sheet.CreateGeometryIntent(candidate.B)

                Dim cl As Centerline = _
                    sheet.Centerlines.AddBisector( _
                        intentA, _
                        intentB)

                If cl Is Nothing Then Continue For

                ' Validate before accepting it.  If Inventor created a
                ' bisector that does not pass through the semantic centre,
                ' remove it immediately.
                Dim centreError As Double = _
                    DistancePointToInfiniteLineV03( _
                        target, _
                        cl.StartPoint, _
                        cl.EndPoint)

                If centreError > 0.12 Then
                    Try
                        cl.Delete()
                    Catch
                    End Try
                    Continue For
                End If

                TagAutoObjectV01(cl)
                result.Add(cl)
                usedUX.Add(candidate.UX)
                usedUY.Add(candidate.UY)

                Logger.Info( _
                    "Created controlled bisector for " & _
                    node.Code & _
                    " direction=" & _
                    Num(candidate.UX) & "," & Num(candidate.UY))

                ' An elbow/tee centre requires at most two independent axes.
                If result.Count >= 2 Then Exit For

            Catch ex As Exception
                Logger.Error( _
                    "AddBisector failed for " & _
                    node.Code & ": " & ex.Message)
            End Try
        Next

    Catch ex As Exception
        Logger.Error( _
            "Controlled centerline search failed for " & _
            node.Code & ": " & ex.Message)
    End Try

    Return result
End Function


Sub SortBisectorCandidatesV04( _
    candidates As List(Of BisectorCandidateV04))

    For i As Integer = 0 To candidates.Count - 2
        For j As Integer = i + 1 To candidates.Count - 1
            If candidates.Item(j).Score < candidates.Item(i).Score Then
                Dim temp As BisectorCandidateV04 = candidates.Item(i)
                candidates.Item(i) = candidates.Item(j)
                candidates.Item(j) = temp
            End If
        Next
    Next
End Sub


Class BisectorCandidateV04
    Public A As DrawingCurve = Nothing
    Public B As DrawingCurve = Nothing
    Public UX As Double
    Public UY As Double
    Public Score As Double
End Class

'''
s = s[:insert_at] + helpers + s[insert_at:]

# Re-enable Inventor's native ChainDimensionSet now that all intents are either
# proven projected DrawingCurves or tightly controlled native Centerlines.
chain_start = s.index('Function CreateChainDimensionsV01(')
chain_end = s.index('\nEnd Function', chain_start) + len('\nEnd Function')
new_chain = r'''Function CreateChainDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests

        If request.Anchors.Count < 2 Then Continue For

        Try
            Dim intents As ObjectCollection = _
                ThisApplication.TransientObjects.CreateObjectCollection()

            For Each anchor As AutoDimAnchorV01 In request.Anchors
                If anchor.Intent IsNot Nothing Then
                    intents.Add(anchor.Intent)
                End If
            Next

            If intents.Count < 2 Then Continue For

            Dim dimSet As ChainDimensionSet = _
                sheet.DrawingDimensions.ChainDimensionSets.Add( _
                    intents, _
                    request.PlacementPoint, _
                    request.DimensionType)

            Try
                dimSet.Precision = 0
            Catch
            End Try

            TagAutoObjectV01(dimSet)
            created += 1

        Catch ex As Exception
            Logger.Error( _
                "Chain dimension set failed for " & _
                request.Name & _
                ": " & _
                ex.Message & _
                " | using individual fallback")

            created += _
                CreateIndividualChainFallbackV02( _
                    sheet, _
                    request)
        End Try

    Next

    Return created
End Function'''
s = s[:chain_start] + new_chain + s[chain_end:]

# Attachments stay deferred for this stage; first verify normal spool centreline
# and chain behaviour without widening the test surface.
s = s.replace('V0.3.1 safe mode: attachment dimensions deferred until native centerlines are re-enabled.',
              'V0.4 staged mode: attachment dimensions remain deferred until normal spool chains/centerlines are verified.')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.4 controlled centerlines + native chains')
