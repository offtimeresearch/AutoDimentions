from pathlib import Path

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

start_marker = "' ===================================================================\n' V0.8 INTEGRATED SAFE PIPE / FLANGE CENTERLINES\n' ===================================================================\n\nFunction EnsureSafeSpoolCenterlinesV08( _"
end_marker = "\n\nFunction HasIntegratedCenterlineV08( _"

start = text.find(start_marker)
if start < 0:
    raise RuntimeError('V0.8 centerline block start not found')
end = text.find(end_marker, start)
if end < 0:
    raise RuntimeError('HasIntegratedCenterlineV08 marker not found')

new_block = r''' ' ===================================================================
' V0.13 UNIQUE / VIEW-LOCAL PIPE + FLANGE CENTER AXES
'
' PRODUCTION SAFETY RULES:
' - Centerlines.Add from TWO real port point intents only.
' - NEVER AddBisector here.
' - One projected axis at most for coincident/collinear PIPE + FLANGE axes.
' - PIPE wins over an overlapping FLANGE axis.
' - FLANGE candidate must follow the projected port normal; a face-direction
'   / perpendicular axis is rejected.
' - Only AutoSpoolCenterline objects are removed during normalization.
' - Manual/template centerlines are never deleted.
' - New tags include ViewName so future multi-view cleanup is safer.
' ===================================================================

Function EnsureSafeSpoolCenterlinesV08( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord)) As Integer

    Dim ensured As Integer = 0

    If sheet Is Nothing OrElse view Is Nothing OrElse nodes Is Nothing Then
        Return ensured
    End If

    Logger.Info( _
        "CENTERLINE_V013 begin | existing=" & _
        sheet.Centerlines.Count.ToString() & _
        " | view=" & view.Name)

    ' Old generator versions could leave one short axis per PIPE and FLANGE.
    ' Remove only redundant/wrong AUTO axes belonging to this selected view.
    NormalizeGeneratedCenterlinesV013(sheet, view, nodes)

    Dim candidates As New List(Of AxisCandidateV013)

    For Each node As NodeRecord In nodes

        If node Is Nothing OrElse node.Occurrence Is Nothing Then Continue For

        If node.ComponentType <> "PIPE" AndAlso _
           node.ComponentType <> "FLANGE" Then
            Continue For
        End If

        Dim pair As PortPairV08 = _
            FindBestPortPairV08(view, node.Ports)

        If pair Is Nothing Then
            Logger.Info( _
                "CENTERLINE_V013 skip " & node.ComponentType & _
                " | " & node.OccurrenceName & _
                " | no safe coaxial projected port pair")
            Continue For
        End If

        Dim candidate As AxisCandidateV013 = _
            BuildAxisCandidateV013(view, node, pair)

        If candidate Is Nothing Then Continue For

        candidates.Add(candidate)
    Next

    SortAxisCandidatesV013(candidates)

    For Each candidate As AxisCandidateV013 In candidates

        ' Reuse an existing native axis on the same mathematical line.
        ' This is what removes PIPE/FLANGE overlap: PIPE candidates are sorted
        ' first, so a flange on the same route simply reuses that axis.
        Dim existing As Centerline = _
            FindEquivalentCenterAxisV013( _
                sheet, view, candidate)

        If existing IsNot Nothing Then
            Logger.Info( _
                "CENTERLINE_V013 reuse unique axis | " & _
                candidate.Node.ComponentType & " | " & _
                candidate.Node.OccurrenceName)
            ensured += 1
            Continue For
        End If

        Dim intentA As GeometryIntent = _
            FindPortPointIntentV08( _
                sheet, view, candidate.Node.Occurrence, candidate.Pair.A)

        Dim intentB As GeometryIntent = _
            FindPortPointIntentV08( _
                sheet, view, candidate.Node.Occurrence, candidate.Pair.B)

        If intentA Is Nothing OrElse intentB Is Nothing Then
            Logger.Error( _
                "CENTERLINE_V013 missing port point intent | " & _
                candidate.Node.ComponentType & " | " & _
                candidate.Node.OccurrenceName)
            Continue For
        End If

        Try
            Dim points As ObjectCollection = _
                ThisApplication.TransientObjects.CreateObjectCollection()

            points.Add(intentA)
            points.Add(intentB)

            Logger.Info( _
                "CENTERLINE_V013 ADD BEGIN | " & _
                candidate.Node.ComponentType & " | " & _
                candidate.Node.OccurrenceName)

            Dim cl As Centerline = sheet.Centerlines.Add(points)

            Logger.Info( _
                "CENTERLINE_V013 ADD RETURN | " & _
                candidate.Node.ComponentType & " | " & _
                candidate.Node.OccurrenceName)

            If cl Is Nothing Then Continue For

            ' Guard against Inventor returning an unexpected axis.  This also
            ' eliminates the unwanted line running along a flange face.
            If Not CenterlineMatchesCandidateV013( _
                cl, candidate, 0.04) Then

                Logger.Error( _
                    "CENTERLINE_V013 rejected created axis direction | " & _
                    candidate.Node.ComponentType & " | " & _
                    candidate.Node.OccurrenceName)

                Try : cl.Delete() : Catch : End Try
                Continue For
            End If

            ' A port-point centerline should remain local to the selected view.
            ' Reject a pathological line that extends beyond the view envelope.
            If Not CenterlineInsideSelectedViewV013(cl, view, 0.35) Then
                Logger.Error( _
                    "CENTERLINE_V013 rejected axis crossing view boundary | " & _
                    candidate.Node.ComponentType & " | " & _
                    candidate.Node.OccurrenceName)
                Try : cl.Delete() : Catch : End Try
                Continue For
            End If

            TagIntegratedCenterlineV013( _
                cl, view, candidate)

            ensured += 1

        Catch ex As Exception
            Logger.Error( _
                "CENTERLINE_V013 Centerlines.Add failed | " & _
                candidate.Node.ComponentType & " | " & _
                candidate.Node.OccurrenceName & " | " & ex.Message)
        End Try
    Next

    ' One final pass catches legacy duplicates that may only become obvious
    ' after the preferred PIPE axis has been created.
    NormalizeGeneratedCenterlinesV013(sheet, view, nodes)

    Logger.Info( _
        "CENTERLINE_V013 end | ensured/reused=" & _
        ensured.ToString() & _
        " | sheet total=" & sheet.Centerlines.Count.ToString())

    Return ensured
End Function


Class AxisCandidateV013
    Public Node As NodeRecord = Nothing
    Public Pair As PortPairV08 = Nothing
    Public A As Point2d = Nothing
    Public B As Point2d = Nothing
    Public UX As Double
    Public UY As Double
    Public Length As Double
End Class


Function BuildAxisCandidateV013( _
    view As DrawingView, _
    node As NodeRecord, _
    pair As PortPairV08) As AxisCandidateV013

    If view Is Nothing OrElse node Is Nothing OrElse pair Is Nothing OrElse _
       pair.A Is Nothing OrElse pair.B Is Nothing Then Return Nothing

    Dim a As Point2d = ProjectPortCenterV08(view, pair.A)
    Dim b As Point2d = ProjectPortCenterV08(view, pair.B)

    If a Is Nothing OrElse b Is Nothing Then Return Nothing

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)

    If l < 0.03 Then Return Nothing

    Dim ux As Double = dx / l
    Dim uy As Double = dy / l

    ' Critical flange rule: the center axis must be NORMAL to the flange face.
    ' A candidate running along/across the flange face is rejected before any
    ' native Centerline is created.
    If node.ComponentType = "FLANGE" Then
        Dim nux As Double = 0
        Dim nuy As Double = 0

        If Not ProjectPortNormalDirectionV013( _
            view, pair.A, nux, nuy) Then

            Logger.Info( _
                "CENTERLINE_V013 FLANGE skip face-on/non-projecting axis | " & _
                node.OccurrenceName)
            Return Nothing
        End If

        Dim normalAlignment As Double = _
            Math.Abs(ux * nux + uy * nuy)

        If normalAlignment < 0.98 Then
            Logger.Error( _
                "CENTERLINE_V013 FLANGE reject perpendicular/face axis | " & _
                node.OccurrenceName & _
                " | alignment=" & Num(normalAlignment))
            Return Nothing
        End If
    End If

    Dim result As New AxisCandidateV013
    result.Node = node
    result.Pair = pair
    result.A = a
    result.B = b
    result.UX = ux
    result.UY = uy
    result.Length = l
    Return result
End Function


Function ProjectPortNormalDirectionV013( _
    view As DrawingView, _
    port As PortRecord, _
    ByRef ux As Double, _
    ByRef uy As Double) As Boolean

    ux = 0 : uy = 0
    If view Is Nothing OrElse port Is Nothing Then Return False

    Try
        Dim p0 As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                port.X / 10.0, _
                port.Y / 10.0, _
                port.Z / 10.0)

        ' 100 mm along the actual model port normal.
        Dim p1 As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                (port.X + port.NX * 100.0) / 10.0, _
                (port.Y + port.NY * 100.0) / 10.0, _
                (port.Z + port.NZ * 100.0) / 10.0)

        Dim s0 As Point2d = view.ModelToSheetSpace(p0)
        Dim s1 As Point2d = view.ModelToSheetSpace(p1)

        ux = s1.X - s0.X
        uy = s1.Y - s0.Y
        Dim l As Double = Math.Sqrt(ux * ux + uy * uy)

        If l < 0.02 Then Return False

        ux /= l : uy /= l
        Return True
    Catch
        ux = 0 : uy = 0
        Return False
    End Try
End Function


Sub SortAxisCandidatesV013( _
    candidates As List(Of AxisCandidateV013))

    If candidates Is Nothing Then Exit Sub

    For i As Integer = 0 To candidates.Count - 2
        For j As Integer = i + 1 To candidates.Count - 1
            If AxisCandidateBeforeV013( _
                candidates.Item(j), candidates.Item(i)) Then

                Dim tmp As AxisCandidateV013 = candidates.Item(i)
                candidates.Item(i) = candidates.Item(j)
                candidates.Item(j) = tmp
            End If
        Next
    Next
End Sub


Function AxisCandidateBeforeV013( _
    a As AxisCandidateV013, _
    b As AxisCandidateV013) As Boolean

    If a Is Nothing Then Return False
    If b Is Nothing Then Return True

    Dim aPipe As Boolean = a.Node IsNot Nothing AndAlso _
        a.Node.ComponentType = "PIPE"
    Dim bPipe As Boolean = b.Node IsNot Nothing AndAlso _
        b.Node.ComponentType = "PIPE"

    ' PIPE owns a coincident route axis; FLANGE is only a fallback axis source.
    If aPipe <> bPipe Then Return aPipe

    ' For same component class keep the longest visible projected source first.
    Return a.Length > b.Length
End Function


Function FindEquivalentCenterAxisV013( _
    sheet As Sheet, _
    view As DrawingView, _
    candidate As AxisCandidateV013) As Centerline

    If sheet Is Nothing OrElse view Is Nothing OrElse candidate Is Nothing Then
        Return Nothing
    End If

    Try
        ' Prefer our own generated axis first.
        For pass As Integer = 1 To 2
            For i As Integer = 1 To sheet.Centerlines.Count
                Dim cl As Centerline = sheet.Centerlines.Item(i)
                If cl Is Nothing Then Continue For
                If Not CenterlineBelongsToViewV013(cl, view) Then Continue For

                Dim generated As Boolean = IsGeneratedSpoolCenterlineV013(cl)
                If pass = 1 AndAlso Not generated Then Continue For
                If pass = 2 AndAlso generated Then Continue For

                If CenterlineMatchesCandidateV013( _
                    cl, candidate, 0.025) Then
                    Return cl
                End If
            Next
        Next
    Catch
    End Try

    Return Nothing
End Function


Function CenterlineMatchesCandidateV013( _
    cl As Centerline, _
    candidate As AxisCandidateV013, _
    lineTolerance As Double) As Boolean

    If cl Is Nothing OrElse candidate Is Nothing OrElse _
       candidate.A Is Nothing OrElse candidate.B Is Nothing Then Return False

    Try
        Dim a As Point2d = cl.StartPoint
        Dim b As Point2d = cl.EndPoint
        If a Is Nothing OrElse b Is Nothing Then Return False

        Dim dx As Double = b.X - a.X
        Dim dy As Double = b.Y - a.Y
        Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
        If l < 0.001 Then Return False

        Dim alignment As Double = _
            Math.Abs( _
                (dx / l) * candidate.UX + _
                (dy / l) * candidate.UY)

        If alignment < 0.995 Then Return False

        If DistancePointToInfiniteLineV03( _
            candidate.A, a, b) > lineTolerance Then Return False

        If DistancePointToInfiniteLineV03( _
            candidate.B, a, b) > lineTolerance Then Return False

        Return True
    Catch
        Return False
    End Try
End Function


Function CenterlinesSameAxisV013( _
    a As Centerline, _
    b As Centerline, _
    lineTolerance As Double) As Boolean

    If a Is Nothing OrElse b Is Nothing Then Return False

    Try
        Dim adx As Double = a.EndPoint.X - a.StartPoint.X
        Dim ady As Double = a.EndPoint.Y - a.StartPoint.Y
        Dim bdx As Double = b.EndPoint.X - b.StartPoint.X
        Dim bdy As Double = b.EndPoint.Y - b.StartPoint.Y

        Dim al As Double = Math.Sqrt(adx * adx + ady * ady)
        Dim bl As Double = Math.Sqrt(bdx * bdx + bdy * bdy)
        If al < 0.001 OrElse bl < 0.001 Then Return False

        Dim alignment As Double = _
            Math.Abs((adx * bdx + ady * bdy) / (al * bl))
        If alignment < 0.995 Then Return False

        Dim bMid As Point2d = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                (b.StartPoint.X + b.EndPoint.X) / 2.0, _
                (b.StartPoint.Y + b.EndPoint.Y) / 2.0)

        Return _
            DistancePointToInfiniteLineV03( _
                bMid, a.StartPoint, a.EndPoint) <= lineTolerance
    Catch
        Return False
    End Try
End Function


Sub NormalizeGeneratedCenterlinesV013( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord))

    If sheet Is Nothing OrElse view Is Nothing Then Exit Sub

    Dim removedWrong As Integer = 0
    Dim removedDuplicate As Integer = 0

    ' First remove AUTO flange axes that do not follow the actual flange port
    ' normal.  This specifically cleans old perpendicular/face-direction axes.
    Try
        For i As Integer = sheet.Centerlines.Count To 1 Step -1
            Dim cl As Centerline = sheet.Centerlines.Item(i)
            If cl Is Nothing OrElse _
               Not IsGeneratedSpoolCenterlineV013(cl) OrElse _
               Not CenterlineBelongsToViewV013(cl, view) Then Continue For

            Dim kind As String = CenterlineTagV013(cl, "ComponentType")
            If kind <> "FLANGE" Then Continue For

            Dim owner As String = CenterlineTagV013(cl, "Occurrence")
            Dim node As NodeRecord = FindNodeByOccurrenceV013(nodes, owner)

            If node Is Nothing Then Continue For

            Dim pair As PortPairV08 = FindBestPortPairV08(view, node.Ports)
            Dim candidate As AxisCandidateV013 = _
                BuildAxisCandidateV013(view, node, pair)

            If candidate Is Nothing OrElse _
               Not CenterlineMatchesCandidateV013( _
                    cl, candidate, 0.05) Then

                Try
                    cl.Delete()
                    removedWrong += 1
                    Logger.Info( _
                        "CENTERLINE_V013 removed wrong FLANGE face/perpendicular axis | " & _
                        owner)
                Catch
                End Try
            End If
        Next
    Catch ex As Exception
        Logger.Error( _
            "CENTERLINE_V013 flange cleanup failed | " & ex.Message)
    End Try

    ' Then collapse AUTO centerlines on the same projected infinite line.
    ' Prefer PIPE over FLANGE; otherwise keep the longer native centerline.
    Dim changed As Boolean = True
    While changed
        changed = False

        Try
            For i As Integer = 1 To sheet.Centerlines.Count - 1
                Dim a As Centerline = sheet.Centerlines.Item(i)
                If a Is Nothing OrElse _
                   Not IsGeneratedSpoolCenterlineV013(a) OrElse _
                   Not CenterlineBelongsToViewV013(a, view) Then Continue For

                For j As Integer = i + 1 To sheet.Centerlines.Count
                    Dim b As Centerline = sheet.Centerlines.Item(j)
                    If b Is Nothing OrElse _
                       Not IsGeneratedSpoolCenterlineV013(b) OrElse _
                       Not CenterlineBelongsToViewV013(b, view) Then Continue For

                    If Not CenterlinesSameAxisV013(a, b, 0.025) Then Continue For

                    Dim keepA As Boolean = PreferFirstGeneratedAxisV013(a, b)
                    Dim loser As Centerline = If(keepA, b, a)

                    Try
                        loser.Delete()
                        removedDuplicate += 1
                        changed = True
                        Logger.Info( _
                            "CENTERLINE_V013 removed overlapping AUTO axis")
                    Catch
                    End Try

                    Exit For
                Next

                If changed Then Exit For
            Next
        Catch
        End Try
    End While

    Logger.Info( _
        "CENTERLINE_V013 normalize | removedWrong=" & _
        removedWrong.ToString() & _
        " | removedDuplicate=" & removedDuplicate.ToString())
End Sub


Function PreferFirstGeneratedAxisV013( _
    a As Centerline, _
    b As Centerline) As Boolean

    Dim typeA As String = CenterlineTagV013(a, "ComponentType")
    Dim typeB As String = CenterlineTagV013(b, "ComponentType")

    If typeA = "PIPE" AndAlso typeB <> "PIPE" Then Return True
    If typeB = "PIPE" AndAlso typeA <> "PIPE" Then Return False

    Return CenterlineLengthV013(a) >= CenterlineLengthV013(b)
End Function


Function CenterlineLengthV013(cl As Centerline) As Double
    If cl Is Nothing Then Return 0
    Try
        Dim dx As Double = cl.EndPoint.X - cl.StartPoint.X
        Dim dy As Double = cl.EndPoint.Y - cl.StartPoint.Y
        Return Math.Sqrt(dx * dx + dy * dy)
    Catch
        Return 0
    End Try
End Function


Function IsGeneratedSpoolCenterlineV013( _
    cl As Centerline) As Boolean

    If cl Is Nothing Then Return False
    Try
        Dim tags As AttributeSet = _
            cl.AttributeSets.Item("AutoSpoolCenterline")
        Return tags IsNot Nothing
    Catch
        Return False
    End Try
End Function


Function CenterlineTagV013( _
    cl As Centerline, _
    tagName As String) As String

    If cl Is Nothing Then Return ""
    Try
        Return _
            CStr( _
                cl.AttributeSets _
                  .Item("AutoSpoolCenterline") _
                  .Item(tagName).Value)
    Catch
        Return ""
    End Try
End Function


Function CenterlineBelongsToViewV013( _
    cl As Centerline, _
    view As DrawingView) As Boolean

    If cl Is Nothing OrElse view Is Nothing Then Return False

    Dim taggedView As String = CenterlineTagV013(cl, "ViewName")
    If Not String.IsNullOrWhiteSpace(taggedView) Then
        Return taggedView = view.Name
    End If

    ' Legacy V0.8 tags had no ViewName.  Migrate conservatively by accepting
    ' only a centerline whose midpoint lies inside this view envelope.
    Try
        Dim mx As Double = (cl.StartPoint.X + cl.EndPoint.X) / 2.0
        Dim my As Double = (cl.StartPoint.Y + cl.EndPoint.Y) / 2.0
        Dim leftX As Double = view.Left
        Dim rightX As Double = view.Left + view.Width
        Dim bottomY As Double = view.Top - view.Height
        Dim topY As Double = view.Top
        Const margin As Double = 0.30

        Return _
            mx >= leftX - margin AndAlso mx <= rightX + margin AndAlso _
            my >= bottomY - margin AndAlso my <= topY + margin
    Catch
        Return False
    End Try
End Function


Function CenterlineInsideSelectedViewV013( _
    cl As Centerline, _
    view As DrawingView, _
    margin As Double) As Boolean

    If cl Is Nothing OrElse view Is Nothing Then Return False

    Try
        Dim leftX As Double = view.Left - margin
        Dim rightX As Double = view.Left + view.Width + margin
        Dim bottomY As Double = view.Top - view.Height - margin
        Dim topY As Double = view.Top + margin

        Return _
            PointInsideBoxV013(cl.StartPoint, leftX, rightX, bottomY, topY) AndAlso _
            PointInsideBoxV013(cl.EndPoint, leftX, rightX, bottomY, topY)
    Catch
        Return False
    End Try
End Function


Function PointInsideBoxV013( _
    p As Point2d, _
    leftX As Double, _
    rightX As Double, _
    bottomY As Double, _
    topY As Double) As Boolean

    If p Is Nothing Then Return False
    Return _
        p.X >= leftX AndAlso p.X <= rightX AndAlso _
        p.Y >= bottomY AndAlso p.Y <= topY
End Function


Function FindNodeByOccurrenceV013( _
    nodes As List(Of NodeRecord), _
    occurrenceName As String) As NodeRecord

    If nodes Is Nothing OrElse String.IsNullOrWhiteSpace(occurrenceName) Then
        Return Nothing
    End If

    For Each node As NodeRecord In nodes
        If node IsNot Nothing AndAlso _
           node.OccurrenceName = occurrenceName Then Return node
    Next

    Return Nothing
End Function


Sub TagIntegratedCenterlineV013( _
    cl As Centerline, _
    view As DrawingView, _
    candidate As AxisCandidateV013)

    If cl Is Nothing OrElse view Is Nothing OrElse candidate Is Nothing OrElse _
       candidate.Node Is Nothing OrElse candidate.Pair Is Nothing Then Exit Sub

    Try
        Dim tags As AttributeSet = Nothing
        Try
            tags = cl.AttributeSets.Item("AutoSpoolCenterline")
        Catch
            tags = cl.AttributeSets.Add("AutoSpoolCenterline")
        End Try

        Try : tags.Add("Occurrence", ValueTypeEnum.kStringType, candidate.Node.OccurrenceName) : Catch : End Try
        Try : tags.Add("ComponentType", ValueTypeEnum.kStringType, candidate.Node.ComponentType) : Catch : End Try
        Try : tags.Add("ViewName", ValueTypeEnum.kStringType, view.Name) : Catch : End Try
        Try : tags.Add("GeneratorVersion", ValueTypeEnum.kStringType, "0.13") : Catch : End Try
        Try : tags.Add("Method", ValueTypeEnum.kStringType, "UNIQUE_REGULAR_PORT_AXIS") : Catch : End Try
        Try : tags.Add("FaceA", ValueTypeEnum.kIntegerType, candidate.Pair.A.FaceIndex) : Catch : End Try
        Try : tags.Add("FaceB", ValueTypeEnum.kIntegerType, candidate.Pair.B.FaceIndex) : Catch : End Try
    Catch
    End Try
End Sub
'''

# Keep a clean leading apostrophe after raw-string indentation.
new_block = new_block.lstrip()
text = text[:start] + new_block + text[end:]

text = text.replace(
    'Logger.Info("V0.12.1: vertical chain and vertical overall share the same collision-selected side; true reference members preserved; attachments deferred.")',
    'Logger.Info("V0.13: unique view-local center axes; overlapping PIPE/FLANGE axes collapsed; perpendicular flange-face axes rejected; V0.12.1 dimension/layout rules preserved; attachments deferred.")',
    1,
)
text = text.replace('"DimensionGenerator V0.12.1")', '"DimensionGenerator V0.13")', 1)
text = text.replace('"DimensionGenerator V0.12.1 failed:"', '"DimensionGenerator V0.13 failed:"', 1)

path.write_text(text, encoding='utf-8')
print('Patched DimensionGenerator.vb to V0.13 unique center axes')
