#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DIMENSION GENERATOR V0.5.1 - STABLE PROJECTED CURVES + CHAINS',
              'DIMENSION GENERATOR V0.6 - SAFE STRAIGHT-COMPONENT CENTER AXES + CHAINS')
s = s.replace('"DimensionGenerator V0.5.1"', '"DimensionGenerator V0.6"')
s = s.replace('"DimensionGenerator V0.5.1 failed:"', '"DimensionGenerator V0.6 failed:"')
s = s.replace('V0.5.1 stable mode: chains enabled; centerline-dependent and attachment dimensions deferred.',
              'V0.6: chains enabled; center axes come only from straight PIPE/TEE/FLANGE geometry; attachments remain deferred.')

# Replace the deliberately-disabled production center resolver with the new safe
# architecture proven by CenterlineProbe: AddBisector ONLY receives two visible,
# parallel straight segments from ONE occurrence.  No elbow curves are bisected.
start = s.index('Function ResolveFittingCenterIntentV04(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_resolver = r'''Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' ===============================================================
    ' V0.6 SAFE CENTER-AXIS ARCHITECTURE
    '
    ' Proven by CenterlineProbe:
    '   * AddBisector is stable when both projected straight lines are
    '     a known-good parallel silhouette pair from ONE occurrence.
    '
    ' Therefore:
    '   TEE   -> derive run + branch axes from the TEE straight lines.
    '   ELBOW -> NEVER bisect elbow geometry.  For each elbow port,
    '            use the connected straight PIPE / TEE / FLANGE axis.
    '            Extend those native centerlines through the theoretical
    '            elbow centre and use their intersection.
    ' ===============================================================

    If node Is Nothing OrElse target Is Nothing Then Return Nothing

    Dim axes As New List(Of Centerline)

    If node.ComponentType = "TEE" Then

        Dim directions As List(Of AxisDirectionV06) = _
            GetNodePortDirectionsV06(view, node)

        For Each direction As AxisDirectionV06 In directions
            Dim cl As Centerline = _
                GetOrCreateOccurrenceAxisV06( _
                    sheet, _
                    view, _
                    node.Occurrence, _
                    direction.UX, _
                    direction.UY, _
                    target, _
                    node.Code & "_TEE")

            AddCenterlineIfUniqueV06(axes, cl)
            If axes.Count >= 2 Then Exit For
        Next

    ElseIf node.ComponentType = "ELBOW" Then

        For Each elbowPort As PortRecord In node.Ports

            If Not elbowPort.Used Then Continue For

            Dim direction As AxisDirectionV06 = _
                ProjectPortAxisV06( _
                    view, _
                    node, _
                    elbowPort)

            If direction Is Nothing Then Continue For

            Dim straightNode As NodeRecord = _
                FindStraightNeighbourForPortV06( _
                    node, _
                    elbowPort)

            If straightNode Is Nothing OrElse _
               straightNode.Occurrence Is Nothing Then

                Logger.Error( _
                    "No straight axis source found for elbow " & _
                    node.Code & _
                    " port face " & _
                    elbowPort.FaceIndex.ToString())
                Continue For
            End If

            Dim cl As Centerline = _
                GetOrCreateOccurrenceAxisV06( _
                    sheet, _
                    view, _
                    straightNode.Occurrence, _
                    direction.UX, _
                    direction.UY, _
                    target, _
                    node.Code & "_FROM_" & straightNode.Code)

            AddCenterlineIfUniqueV06(axes, cl)
            If axes.Count >= 2 Then Exit For
        Next

    Else
        Return Nothing
    End If

    If axes.Count < 2 Then
        Logger.Error( _
            "Only " & axes.Count.ToString() & _
            " safe center axis/axes resolved for " & _
            node.Code & "/" & node.ComponentType)
        Return Nothing
    End If

    For i As Integer = 0 To axes.Count - 2
        For j As Integer = i + 1 To axes.Count - 1

            If CenterlinesParallelV03( _
                axes.Item(i), _
                axes.Item(j)) Then
                Continue For
            End If

            ExtendCenterlineThroughPointV06( _
                axes.Item(i), _
                target, _
                0.40)

            ExtendCenterlineThroughPointV06( _
                axes.Item(j), _
                target, _
                0.40)

            Try
                Dim pointIntent As GeometryIntent = _
                    sheet.CreateGeometryIntent( _
                        axes.Item(i), _
                        axes.Item(j))

                If pointIntent IsNot Nothing Then
                    Logger.Info( _
                        "Resolved fitting center from safe straight axes: " & _
                        node.Code & "/" & node.ComponentType)
                    Return pointIntent
                End If

            Catch ex As Exception
                Logger.Error( _
                    "Centerline intersection intent failed for " & _
                    node.Code & ": " & ex.Message)
            End Try
        Next
    Next

    Return Nothing
End Function'''
s = s[:start] + new_resolver + s[end:]

# Insert V0.6 helpers before the old experimental V0.5 helper block.  The old
# helpers remain in the file but are no longer called by production logic.
marker = 'Function CreateTopologyGuidedBisectorsV05('
insert_at = s.index(marker)
helpers = r'''

' ===================================================================
' V0.6 SAFE STRAIGHT-COMPONENT CENTER AXES
' ===================================================================

Function GetNodePortDirectionsV06( _
    view As DrawingView, _
    node As NodeRecord) As List(Of AxisDirectionV06)

    Dim result As New List(Of AxisDirectionV06)

    If node Is Nothing Then Return result

    For Each p As PortRecord In node.Ports
        If Not p.Used Then Continue For

        Dim direction As AxisDirectionV06 = _
            ProjectPortAxisV06(view, node, p)

        If direction Is Nothing Then Continue For

        Dim duplicate As Boolean = False
        For Each existing As AxisDirectionV06 In result
            Dim dot As Double = _
                Math.Abs( _
                    existing.UX * direction.UX + _
                    existing.UY * direction.UY)

            If dot > 0.98 Then
                duplicate = True
                Exit For
            End If
        Next

        If Not duplicate Then result.Add(direction)
    Next

    Return result
End Function


Function ProjectPortAxisV06( _
    view As DrawingView, _
    node As NodeRecord, _
    port As PortRecord) As AxisDirectionV06

    If view Is Nothing OrElse _
       node Is Nothing OrElse _
       port Is Nothing Then
        Return Nothing
    End If

    Try
        Dim basePoint As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                port.X / 10.0, _
                port.Y / 10.0, _
                port.Z / 10.0)

        Dim directionPoint As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                (port.X + port.NX * 100.0) / 10.0, _
                (port.Y + port.NY * 100.0) / 10.0, _
                (port.Z + port.NZ * 100.0) / 10.0)

        Dim a As Point2d = view.ModelToSheetSpace(basePoint)
        Dim b As Point2d = view.ModelToSheetSpace(directionPoint)

        Dim ux As Double = b.X - a.X
        Dim uy As Double = b.Y - a.Y
        Dim l As Double = Math.Sqrt(ux * ux + uy * uy)

        If l < 0.02 Then Return Nothing

        ux /= l : uy /= l

        If ux < -0.0001 OrElse _
           (Math.Abs(ux) <= 0.0001 AndAlso uy < 0) Then
            ux *= -1.0
            uy *= -1.0
        End If

        Dim result As New AxisDirectionV06
        result.UX = ux
        result.UY = uy
        Return result

    Catch ex As Exception
        Logger.Error( _
            "ProjectPortAxisV06 failed for " & _
            node.Code & ": " & ex.Message)
        Return Nothing
    End Try
End Function


Function FindStraightNeighbourForPortV06( _
    elbow As NodeRecord, _
    elbowPort As PortRecord) As NodeRecord

    If elbow Is Nothing OrElse elbowPort Is Nothing Then Return Nothing

    Dim best As NodeRecord = Nothing
    Dim bestScore As Double = Double.MaxValue

    For Each neighbour As NodeRecord In elbow.Neighbours

        If neighbour Is Nothing Then Continue For
        If neighbour.ComponentType = "ELBOW" Then Continue For
        If neighbour.Occurrence Is Nothing Then Continue For

        If Not IsStraightAxisSourceTypeV06(neighbour.ComponentType) Then
            Continue For
        End If

        For Each p As PortRecord In neighbour.Ports

            Dim alignment As Double = _
                Math.Abs( _
                    elbowPort.NX * p.NX + _
                    elbowPort.NY * p.NY + _
                    elbowPort.NZ * p.NZ)

            If alignment < 0.90 Then Continue For

            Dim dx As Double = p.X - elbowPort.X
            Dim dy As Double = p.Y - elbowPort.Y
            Dim dz As Double = p.Z - elbowPort.Z

            Dim totalDistance As Double = _
                Math.Sqrt(dx * dx + dy * dy + dz * dz)

            Dim axial As Double = _
                Math.Abs( _
                    dx * elbowPort.NX + _
                    dy * elbowPort.NY + _
                    dz * elbowPort.NZ)

            Dim lateral2 As Double = _
                totalDistance * totalDistance - axial * axial
            If lateral2 < 0 Then lateral2 = 0

            Dim lateral As Double = Math.Sqrt(lateral2)
            If lateral > 2.0 Then Continue For

            Dim score As Double = _
                totalDistance + _
                lateral * 10.0 + _
                (1.0 - alignment) * 100.0

            If score < bestScore Then
                bestScore = score
                best = neighbour
            End If
        Next
    Next

    Return best
End Function


Function IsStraightAxisSourceTypeV06( _
    componentType As String) As Boolean

    Return _
        componentType = "PIPE" OrElse _
        componentType = "TEE" OrElse _
        componentType = "FLANGE" OrElse _
        componentType = "REDUCER" OrElse _
        componentType = "VALVE" OrElse _
        componentType = "COUPLING_SOCKET"
End Function


Function GetOrCreateOccurrenceAxisV06( _
    sheet As Sheet, _
    view As DrawingView, _
    occurrence As ComponentOccurrence, _
    desiredUX As Double, _
    desiredUY As Double, _
    target As Point2d, _
    sourceName As String) As Centerline

    If occurrence Is Nothing OrElse target Is Nothing Then Return Nothing

    Dim l As Double = _
        Math.Sqrt( _
            desiredUX * desiredUX + _
            desiredUY * desiredUY)

    If l < 0.0001 Then Return Nothing

    desiredUX /= l : desiredUY /= l

    Dim existing As Centerline = _
        FindExistingAxisCenterlineV06( _
            sheet, _
            occurrence.Name, _
            desiredUX, _
            desiredUY)

    If existing IsNot Nothing Then
        ExtendCenterlineThroughPointV06(existing, target, 0.40)
        Return existing
    End If

    Dim pair As AxisSegmentPairV06 = _
        FindBestAxisPairOnOccurrenceV06( _
            view, _
            occurrence, _
            desiredUX, _
            desiredUY, _
            target)

    If pair Is Nothing Then
        Logger.Error( _
            "No safe same-occurrence silhouette pair for " & _
            occurrence.Name & _
            " axis=" & Num(desiredUX) & "," & Num(desiredUY))
        Return Nothing
    End If

    Try
        Dim intentA As GeometryIntent = _
            sheet.CreateGeometryIntent(pair.A.Parent)

        Dim intentB As GeometryIntent = _
            sheet.CreateGeometryIntent(pair.B.Parent)

        Logger.Info( _
            "Safe AddBisector " & occurrence.Name & _
            " axis=" & Num(desiredUX) & "," & Num(desiredUY) & _
            " alignment=" & Num(pair.Alignment) & _
            " overlap=" & Num(pair.Overlap) & _
            " centerError=" & Num(pair.CenterError))

        Dim cl As Centerline = _
            sheet.Centerlines.AddBisector( _
                intentA, _
                intentB)

        If cl Is Nothing Then Return Nothing

        TagAxisCenterlineV06( _
            cl, _
            occurrence.Name, _
            desiredUX, _
            desiredUY, _
            sourceName)

        ExtendCenterlineThroughPointV06(cl, target, 0.40)

        Logger.Info( _
            "Created safe straight-component centerline from " & _
            occurrence.Name & _
            " for " & sourceName)

        Return cl

    Catch ex As Exception
        Logger.Error( _
            "Safe AddBisector failed for " & _
            occurrence.Name & ": " & ex.Message)
        Return Nothing
    End Try
End Function


Function FindBestAxisPairOnOccurrenceV06( _
    view As DrawingView, _
    occurrence As ComponentOccurrence, _
    desiredUX As Double, _
    desiredUY As Double, _
    target As Point2d) As AxisSegmentPairV06

    Dim curves As DrawingCurvesEnumerator = Nothing

    Try
        curves = view.DrawingCurves(occurrence)
    Catch ex As Exception
        Logger.Error( _
            "DrawingCurves(occurrence) failed for axis source " & _
            occurrence.Name & ": " & ex.Message)
        Return Nothing
    End Try

    If curves Is Nothing Then Return Nothing

    Dim segments As New List(Of DrawingCurveSegment)

    For Each curve As DrawingCurve In curves
        For Each seg As DrawingCurveSegment In curve.Segments
            If Not IsStraightVisibleSegmentV06(seg) Then Continue For

            Dim alignmentToAxis As Double = _
                SegmentDirectionAlignmentV06( _
                    seg, _
                    desiredUX, _
                    desiredUY)

            If alignmentToAxis >= 0.995 Then
                segments.Add(seg)
            End If
        Next
    Next

    If segments.Count < 2 Then Return Nothing

    Dim best As AxisSegmentPairV06 = Nothing
    Dim bestScore As Double = Double.MaxValue

    For i As Integer = 0 To segments.Count - 2
        For j As Integer = i + 1 To segments.Count - 1

            Dim a As DrawingCurveSegment = segments.Item(i)
            Dim b As DrawingCurveSegment = segments.Item(j)

            Dim alignment As Double = _
                SegmentParallelAlignmentV06(a, b)
            If alignment < 0.995 Then Continue For

            Dim separation As Double = _
                ParallelLineSeparationV06(a, b)
            If separation < 0.02 Then Continue For

            Dim overlap As Double = _
                AxisOverlapRatioV06(a, b)
            If overlap < 0.45 Then Continue For

            Dim lenA As Double = SegmentLengthV06(a)
            Dim lenB As Double = SegmentLengthV06(b)
            If lenA < 0.0001 OrElse lenB < 0.0001 Then Continue For

            Dim lengthRatioError As Double = _
                Math.Abs(lenA - lenB) / Math.Max(lenA, lenB)

            Dim centerError As Double = _
                PairMidlineDistanceV06( _
                    a, _
                    b, _
                    target)

            ' Strong safety filter: the bisector's infinite line must pass
            ' very close to the semantic center we are trying to resolve.
            If centerError > 0.20 Then Continue For

            Dim score As Double = _
                (1.0 - alignment) * 100.0 + _
                (1.0 - overlap) * 5.0 + _
                lengthRatioError * 3.0 + _
                centerError * 20.0

            If score < bestScore Then
                bestScore = score
                best = New AxisSegmentPairV06
                best.A = a
                best.B = b
                best.Alignment = alignment
                best.Separation = separation
                best.Overlap = overlap
                best.CenterError = centerError
                best.Score = score
            End If
        Next
    Next

    Return best
End Function


Function IsStraightVisibleSegmentV06( _
    seg As DrawingCurveSegment) As Boolean

    If seg Is Nothing Then Return False

    Try
        If seg.GeometryType <> _
           Curve2dTypeEnum.kLineSegmentCurve2d Then
            Return False
        End If

        If seg.StartPoint Is Nothing OrElse _
           seg.EndPoint Is Nothing Then
            Return False
        End If

        If Not seg.Visible Then Return False
        If seg.HiddenLine Then Return False

        Return SegmentLengthV06(seg) > 0.02

    Catch
        Return False
    End Try
End Function


Function SegmentLengthV06( _
    seg As DrawingCurveSegment) As Double

    If seg Is Nothing OrElse _
       seg.StartPoint Is Nothing OrElse _
       seg.EndPoint Is Nothing Then
        Return 0
    End If

    Dim dx As Double = seg.EndPoint.X - seg.StartPoint.X
    Dim dy As Double = seg.EndPoint.Y - seg.StartPoint.Y
    Return Math.Sqrt(dx * dx + dy * dy)
End Function


Function SegmentDirectionAlignmentV06( _
    seg As DrawingCurveSegment, _
    ux As Double, _
    uy As Double) As Double

    Dim dx As Double = seg.EndPoint.X - seg.StartPoint.X
    Dim dy As Double = seg.EndPoint.Y - seg.StartPoint.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return 0

    dx /= l : dy /= l
    Return Math.Abs(dx * ux + dy * uy)
End Function


Function SegmentParallelAlignmentV06( _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment) As Double

    Dim aux As Double = a.EndPoint.X - a.StartPoint.X
    Dim auy As Double = a.EndPoint.Y - a.StartPoint.Y
    Dim bux As Double = b.EndPoint.X - b.StartPoint.X
    Dim buy As Double = b.EndPoint.Y - b.StartPoint.Y

    Dim al As Double = Math.Sqrt(aux * aux + auy * auy)
    Dim bl As Double = Math.Sqrt(bux * bux + buy * buy)
    If al < 0.000001 OrElse bl < 0.000001 Then Return 0

    aux /= al : auy /= al
    bux /= bl : buy /= bl
    Return Math.Abs(aux * bux + auy * buy)
End Function


Function ParallelLineSeparationV06( _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment) As Double

    Dim dx As Double = a.EndPoint.X - a.StartPoint.X
    Dim dy As Double = a.EndPoint.Y - a.StartPoint.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return 0

    Dim mx As Double = (b.StartPoint.X + b.EndPoint.X) / 2.0
    Dim my As Double = (b.StartPoint.Y + b.EndPoint.Y) / 2.0

    Return _
        Math.Abs( _
            dx * (a.StartPoint.Y - my) - _
            (a.StartPoint.X - mx) * dy) / l
End Function


Function AxisOverlapRatioV06( _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment) As Double

    Dim ux As Double = a.EndPoint.X - a.StartPoint.X
    Dim uy As Double = a.EndPoint.Y - a.StartPoint.Y
    Dim l As Double = Math.Sqrt(ux * ux + uy * uy)
    If l < 0.000001 Then Return 0

    ux /= l : uy /= l

    Dim a0 As Double = a.StartPoint.X * ux + a.StartPoint.Y * uy
    Dim a1 As Double = a.EndPoint.X * ux + a.EndPoint.Y * uy
    Dim b0 As Double = b.StartPoint.X * ux + b.StartPoint.Y * uy
    Dim b1 As Double = b.EndPoint.X * ux + b.EndPoint.Y * uy

    If a1 < a0 Then
        Dim t As Double = a0 : a0 = a1 : a1 = t
    End If
    If b1 < b0 Then
        Dim t As Double = b0 : b0 = b1 : b1 = t
    End If

    Dim overlap As Double = _
        Math.Max( _
            0, _
            Math.Min(a1, b1) - Math.Max(a0, b0))

    Dim denom As Double = Math.Min(a1 - a0, b1 - b0)
    If denom < 0.000001 Then Return 0

    Return overlap / denom
End Function


Function PairMidlineDistanceV06( _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment, _
    target As Point2d) As Double

    Dim amx As Double = (a.StartPoint.X + a.EndPoint.X) / 2.0
    Dim amy As Double = (a.StartPoint.Y + a.EndPoint.Y) / 2.0
    Dim bmx As Double = (b.StartPoint.X + b.EndPoint.X) / 2.0
    Dim bmy As Double = (b.StartPoint.Y + b.EndPoint.Y) / 2.0

    Dim mx As Double = (amx + bmx) / 2.0
    Dim my As Double = (amy + bmy) / 2.0

    Dim dx As Double = a.EndPoint.X - a.StartPoint.X
    Dim dy As Double = a.EndPoint.Y - a.StartPoint.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return Double.MaxValue

    Return _
        Math.Abs( _
            dx * (my - target.Y) - _
            (mx - target.X) * dy) / l
End Function


Sub ExtendCenterlineThroughPointV06( _
    cl As Centerline, _
    target As Point2d, _
    margin As Double)

    If cl Is Nothing OrElse target Is Nothing Then Exit Sub

    Try
        Dim a As Point2d = cl.StartPoint
        Dim b As Point2d = cl.EndPoint

        Dim ux As Double = b.X - a.X
        Dim uy As Double = b.Y - a.Y
        Dim l As Double = Math.Sqrt(ux * ux + uy * uy)
        If l < 0.000001 Then Exit Sub

        ux /= l : uy /= l

        Dim targetDistance As Double = _
            Math.Abs( _
                ux * (a.Y - target.Y) - _
                (a.X - target.X) * uy)

        If targetDistance > 0.22 Then
            Logger.Error( _
                "Refused centerline extension: target is " & _
                Num(targetDistance) & _
                " cm away from axis")
            Exit Sub
        End If

        Dim tA As Double = 0
        Dim tB As Double = _
            (b.X - a.X) * ux + _
            (b.Y - a.Y) * uy
        Dim tTarget As Double = _
            (target.X - a.X) * ux + _
            (target.Y - a.Y) * uy

        Dim tMin As Double = Math.Min(Math.Min(tA, tB), tTarget) - margin
        Dim tMax As Double = Math.Max(Math.Max(tA, tB), tTarget) + margin

        cl.StartPoint = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                a.X + ux * tMin, _
                a.Y + uy * tMin)

        cl.EndPoint = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                a.X + ux * tMax, _
                a.Y + uy * tMax)

    Catch ex As Exception
        Logger.Error("Centerline extension failed: " & ex.Message)
    End Try
End Sub


Sub AddCenterlineIfUniqueV06( _
    list As List(Of Centerline), _
    cl As Centerline)

    If cl Is Nothing Then Exit Sub

    For Each existing As Centerline In list
        If existing Is cl Then Exit Sub

        Try
            Dim ax As Double = existing.EndPoint.X - existing.StartPoint.X
            Dim ay As Double = existing.EndPoint.Y - existing.StartPoint.Y
            Dim bx As Double = cl.EndPoint.X - cl.StartPoint.X
            Dim by As Double = cl.EndPoint.Y - cl.StartPoint.Y

            Dim al As Double = Math.Sqrt(ax * ax + ay * ay)
            Dim bl As Double = Math.Sqrt(bx * bx + by * by)
            If al < 0.0001 OrElse bl < 0.0001 Then Continue For

            Dim dot As Double = _
                Math.Abs( _
                    (ax / al) * (bx / bl) + _
                    (ay / al) * (by / bl))

            If dot > 0.98 Then Exit Sub
        Catch
        End Try
    Next

    list.Add(cl)
End Sub


Sub TagAxisCenterlineV06( _
    cl As Centerline, _
    occurrenceName As String, _
    ux As Double, _
    uy As Double, _
    sourceName As String)

    If cl Is Nothing Then Exit Sub

    TagAutoObjectV01(cl)

    Try
        Dim tags As AttributeSet = Nothing

        Try
            tags = cl.AttributeSets.Item("AutoAxisV06")
        Catch
            tags = cl.AttributeSets.Add("AutoAxisV06")
        End Try

        Try : tags.Add("Owner", ValueTypeEnum.kStringType, occurrenceName) : Catch : End Try
        Try : tags.Add("UX", ValueTypeEnum.kDoubleType, ux) : Catch : End Try
        Try : tags.Add("UY", ValueTypeEnum.kDoubleType, uy) : Catch : End Try
        Try : tags.Add("Source", ValueTypeEnum.kStringType, sourceName) : Catch : End Try
    Catch
    End Try
End Sub


Function FindExistingAxisCenterlineV06( _
    sheet As Sheet, _
    occurrenceName As String, _
    ux As Double, _
    uy As Double) As Centerline

    Try
        For Each cl As Centerline In sheet.Centerlines

            Dim tags As AttributeSet = Nothing
            Try
                tags = cl.AttributeSets.Item("AutoAxisV06")
            Catch
                Continue For
            End Try

            Dim owner As String = ""
            Dim ex As Double = 0
            Dim ey As Double = 0

            Try : owner = CStr(tags.Item("Owner").Value) : Catch : Continue For : End Try
            Try : ex = CDbl(tags.Item("UX").Value) : Catch : Continue For : End Try
            Try : ey = CDbl(tags.Item("UY").Value) : Catch : Continue For : End Try

            If owner <> occurrenceName Then Continue For

            Dim el As Double = Math.Sqrt(ex * ex + ey * ey)
            If el < 0.0001 Then Continue For
            ex /= el : ey /= el

            Dim dot As Double = Math.Abs(ex * ux + ey * uy)
            If dot > 0.98 Then Return cl
        Next
    Catch
    End Try

    Return Nothing
End Function


Class AxisDirectionV06
    Public UX As Double
    Public UY As Double
End Class


Class AxisSegmentPairV06
    Public A As DrawingCurveSegment = Nothing
    Public B As DrawingCurveSegment = Nothing
    Public Alignment As Double
    Public Separation As Double
    Public Overlap As Double
    Public CenterError As Double
    Public Score As Double
End Class


'''
s = s[:insert_at] + helpers + s[insert_at:]

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.6 safe straight-component center axes')
