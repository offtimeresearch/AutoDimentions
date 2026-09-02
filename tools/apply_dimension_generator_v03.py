#!/usr/bin/env python3
from pathlib import Path
import re

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

# Version labels.
s = s.replace('DIMENSION GENERATOR V0.2 - DRAWING API LAYER', 'DIMENSION GENERATOR V0.3 - PROJECTED DRAWING GEOMETRY LAYER')
s = s.replace('DimensionGenerator V0.2', 'DimensionGenerator V0.3')

# Preserve the actual model face behind every detected semantic port.
s = s.replace('p.FaceIndex = faceCounter\n', 'p.FaceIndex = faceCounter\n                    p.ModelFace = face\n', 1)

# Preserve the selected outer flange port/face object.
s = s.replace('flange.OuterFaceIndex = bestPort.FaceIndex\n', 'flange.OuterFaceIndex = bestPort.FaceIndex\n    flange.OuterPort = bestPort\n', 1)

# Data classes: keep real model geometry handles.
s = s.replace('Public OuterFaceIndex As Integer = 0\n', 'Public OuterFaceIndex As Integer = 0\n    Public OuterPort As PortRecord = Nothing\n', 1)
s = s.replace('Public FaceIndex As Integer\n', 'Public FaceIndex As Integer\n    Public ModelFace As Object = Nothing\n', 1)

# Main: resolve semantic anchors against real projected curves/centerlines, no sketch.
old_main = '''        Dim anchorSketch As DrawingSketch = _
            CreateAnchorSketchV01( _
                sheet, _
                allAnchors)


        Dim chainCount As Integer = _'''
new_main = '''        Dim unresolvedAnchors As Integer = _
            ResolveProjectedAnchorsV03( _
                sheet, _
                view, _
                nodes, _
                allAnchors)

        Logger.Info( _
            "Projected semantic anchors: " & _
            (allAnchors.Count - unresolvedAnchors).ToString() & _
            "/" & allAnchors.Count.ToString())


        Dim chainCount As Integer = _'''
if old_main not in s:
    raise SystemExit('main anchor-sketch block not found')
s = s.replace(old_main, new_main, 1)

old_hide = '''        Try
            anchorSketch.Visible = False
        Catch
        End Try


        drawDoc.Update2(True)'''
if old_hide not in s:
    raise SystemExit('anchorSketch hide block not found')
s = s.replace(old_hide, '        drawDoc.Update2(True)', 1)

# Remove old hidden sketch if left from V0.1/V0.2, and delete only our tagged centerlines.
needle = '''    Try
        Dim oldSketch As DrawingSketch = _
            sheet.Sketches.Item("AUTO_DIM_ANCHORS")
        oldSketch.Delete()
    Catch
    End Try

End Sub'''
replacement = '''    Try
        Dim oldSketch As DrawingSketch = _
            sheet.Sketches.Item("AUTO_DIM_ANCHORS")
        oldSketch.Delete()
    Catch
    End Try

    Try
        For i As Integer = sheet.Centerlines.Count To 1 Step -1
            If IsAutoTaggedV01(sheet.Centerlines.Item(i)) Then
                sheet.Centerlines.Item(i).Delete()
            End If
        Next
    Catch
    End Try

End Sub'''
if needle not in s:
    raise SystemExit('delete previous block not found')
s = s.replace(needle, replacement, 1)

# Replace sketch anchor implementation with projected-geometry resolver.
rx = re.compile(r'''Function CreateAnchorSketchV01\(.*?End Function\n\n\nFunction CreateAnchorIntentV02\(.*?End Function''', re.S)
new_funcs = r'''Function ResolveProjectedAnchorsV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchors As List(Of AutoDimAnchorV01)) As Integer

    ' Create native Inventor centerlines from the actual projected view.
    ' These are not sketch entities; they are sheet Centerline objects.
    CreateAutomatedCenterlinesV03(sheet, view)

    Dim unresolved As Integer = 0

    For Each anchor As AutoDimAnchorV01 In anchors

        anchor.Intent = _
            ResolveProjectedIntentV03( _
                sheet, view, nodes, anchor)

        If anchor.Intent Is Nothing Then
            unresolved += 1
            Logger.Error( _
                "No projected geometry for semantic anchor at model mm (" & _
                Num(anchor.X) & ", " & Num(anchor.Y) & ", " & Num(anchor.Z) & ")")
        End If

    Next

    Return unresolved
End Function


Sub CreateAutomatedCenterlinesV03( _
    sheet As Sheet, _
    view As DrawingView)

    Try
        Dim settings As AutomatedCenterlineSettings = Nothing
        view.GetAutomatedCenterlineSettings(settings)

        settings.ApplyToCylinders = True
        settings.ProjectionParallelAxis = True
        settings.ProjectionNormalAxis = True

        ' Keep the command focused on piping axes, not bolt holes/patterns.
        settings.ApplyToHoles = False
        settings.ApplyToCircularPatterns = False
        settings.ApplyToRectangularPatterns = False
        settings.ApplyToPunches = False
        settings.ApplyToFillets = False
        settings.ApplyToSketches = False
        settings.ApplyToWorkFeatures = False

        Dim created As ObjectsEnumerator = _
            view.SetAutomatedCenterlineSettings(settings)

        If created IsNot Nothing Then
            For i As Integer = 1 To created.Count
                Dim obj As Object = created.Item(i)
                If TypeOf obj Is Centerline Then
                    TagAutoObjectV01(obj)
                End If
            Next
        End If

    Catch ex As Exception
        Logger.Error("Automated centerline command failed: " & ex.Message)
    End Try
End Sub


Function ResolveProjectedIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchor As AutoDimAnchorV01) As GeometryIntent

    ' 1) Preferred path: a semantic topology point that is a real model
    '    port/face is dimensioned directly to its projected DrawingCurve.
    Dim port As PortRecord = _
        FindPortAtModelPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.6)

    If port IsNot Nothing AndAlso port.ModelFace IsNot Nothing Then
        Dim faceIntent As GeometryIntent = _
            FindFaceDrawingIntentV03( _
                sheet, view, port.ModelFace, anchor.SheetPoint)

        If faceIntent IsNot Nothing Then
            anchor.SourceDescription = _
                port.Owner.Code & " FACE " & port.FaceIndex.ToString()
            Return faceIntent
        End If
    End If

    ' 2) Theoretical fitting centres (tee/elbow) are referenced through
    '    true Inventor Centerline objects made from projected view geometry.
    Dim refNode As NodeRecord = _
        FindReferenceNodeAtPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.8)

    If refNode IsNot Nothing Then
        EnsureBisectorCenterlinesForNodeV03( _
            sheet, view, refNode, anchor.SheetPoint)

        Dim centreIntent As GeometryIntent = _
            FindCenterlineIntentAtPointV03( _
                sheet, view, anchor.SheetPoint)

        If centreIntent IsNot Nothing Then
            anchor.SourceDescription = refNode.Code & " CENTERLINE"
            Return centreIntent
        End If
    End If

    ' 3) Attachment axis intersections normally land on native centre lines.
    Dim anyCenterIntent As GeometryIntent = _
        FindCenterlineIntentAtPointV03( _
            sheet, view, anchor.SheetPoint)

    If anyCenterIntent IsNot Nothing Then
        anchor.SourceDescription = "PROJECTED CENTERLINE"
        Return anyCenterIntent
    End If

    ' 4) Attachment bases lie on the visible cylindrical silhouette rather
    '    than on a planar port face.  Snap only when a real drawing curve is
    '    very close to the semantic projected point.
    Dim nearCurve As GeometryIntent = _
        FindNearestViewCurveIntentV03( _
            sheet, view, anchor.SheetPoint, 0.12)

    If nearCurve IsNot Nothing Then
        anchor.SourceDescription = "PROJECTED VIEW CURVE"
        Return nearCurve
    End If

    Return Nothing
End Function


Function FindPortAtModelPointV03( _
    nodes As List(Of NodeRecord), _
    x As Double, y As Double, z As Double, _
    toleranceMm As Double) As PortRecord

    Dim best As PortRecord = Nothing
    Dim bestD As Double = toleranceMm

    For Each n As NodeRecord In nodes
        For Each p As PortRecord In n.Ports
            Dim d As Double = Dist3D(x, y, z, p.X, p.Y, p.Z)
            If d <= bestD Then
                bestD = d
                best = p
            End If
        Next
    Next

    Return best
End Function


Function FindReferenceNodeAtPointV03( _
    nodes As List(Of NodeRecord), _
    x As Double, y As Double, z As Double, _
    toleranceMm As Double) As NodeRecord

    Dim best As NodeRecord = Nothing
    Dim bestD As Double = toleranceMm

    For Each n As NodeRecord In nodes
        Dim d As Double = _
            Dist3D(x, y, z, n.RefX, n.RefY, n.RefZ)
        If d <= bestD Then
            bestD = d
            best = n
        End If
    Next

    Return best
End Function


Function FindFaceDrawingIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    modelFace As Object, _
    target As Point2d) As GeometryIntent

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(modelFace)

        If curves Is Nothing OrElse curves.Count = 0 Then
            Return Nothing
        End If

        Dim best As DrawingCurve = Nothing
        Dim bestScore As Double = Double.MaxValue

        For Each c As DrawingCurve In curves
            Dim score As Double = _
                DrawingCurveDistanceV03(c, target)

            If score < bestScore Then
                bestScore = score
                best = c
            End If
        Next

        If best Is Nothing Then Return Nothing

        If best.CurveType = CurveTypeEnum.kCircleCurve OrElse _
           best.CurveType = CurveTypeEnum.kCircularArcCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipseFullCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipticalArcCurve Then

            Return _
                sheet.CreateGeometryIntent( _
                    best, _
                    PointIntentEnum.kCenterPointIntent)
        End If

        ' For an edge-on planar port face this is the actual projected
        ' face line.  A no-point intent is exactly what a linear/chain
        ' dimension expects for a datum line.
        Return sheet.CreateGeometryIntent(best)

    Catch ex As Exception
        Logger.Error("DrawingCurves(face) failed: " & ex.Message)
        Return Nothing
    End Try
End Function


Function FindNearestViewCurveIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    target As Point2d, _
    maxDistance As Double) As GeometryIntent

    Try
        Dim curves As DrawingCurvesEnumerator = view.DrawingCurves
        If curves Is Nothing Then Return Nothing

        Dim best As DrawingCurve = Nothing
        Dim bestD As Double = maxDistance

        For Each c As DrawingCurve In curves
            Dim d As Double = DrawingCurveDistanceV03(c, target)
            If d <= bestD Then
                bestD = d
                best = c
            End If
        Next

        If best Is Nothing Then Return Nothing

        If best.CurveType = CurveTypeEnum.kLineSegmentCurve Then
            Return sheet.CreateGeometryIntent(best, target)
        End If

        If best.CenterPoint IsNot Nothing AndAlso _
           SheetPointDistanceV03(best.CenterPoint, target) <= maxDistance Then
            Return sheet.CreateGeometryIntent(best, PointIntentEnum.kCenterPointIntent)
        End If

        Return sheet.CreateGeometryIntent(best, target)

    Catch
        Return Nothing
    End Try
End Function


Function DrawingCurveDistanceV03( _
    curve As DrawingCurve, _
    target As Point2d) As Double

    Try
        If curve.CurveType = CurveTypeEnum.kLineSegmentCurve AndAlso _
           curve.StartPoint IsNot Nothing AndAlso _
           curve.EndPoint IsNot Nothing Then

            Return _
                DistancePointToSegmentV03( _
                    target, curve.StartPoint, curve.EndPoint)
        End If

        If curve.CenterPoint IsNot Nothing Then
            Return SheetPointDistanceV03(target, curve.CenterPoint)
        End If

        Dim best As Double = Double.MaxValue
        If curve.StartPoint IsNot Nothing Then
            best = Math.Min(best, SheetPointDistanceV03(target, curve.StartPoint))
        End If
        If curve.EndPoint IsNot Nothing Then
            best = Math.Min(best, SheetPointDistanceV03(target, curve.EndPoint))
        End If
        If curve.MidPoint IsNot Nothing Then
            best = Math.Min(best, SheetPointDistanceV03(target, curve.MidPoint))
        End If
        Return best
    Catch
        Return Double.MaxValue
    End Try
End Function


Function DistancePointToSegmentV03( _
    p As Point2d, _
    a As Point2d, _
    b As Point2d) As Double

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim len2 As Double = dx * dx + dy * dy

    If len2 < 0.0000001 Then
        Return SheetPointDistanceV03(p, a)
    End If

    Dim t As Double = _
        ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / len2

    If t < 0 Then t = 0
    If t > 1 Then t = 1

    Dim q As Point2d = _
        ThisApplication.TransientGeometry.CreatePoint2d( _
            a.X + t * dx, a.Y + t * dy)

    Return SheetPointDistanceV03(p, q)
End Function


Function DistancePointToInfiniteLineV03( _
    p As Point2d, _
    a As Point2d, _
    b As Point2d) As Double

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return Double.MaxValue

    Return _
        Math.Abs( _
            dx * (a.Y - p.Y) - _
            (a.X - p.X) * dy) / l
End Function


Function SignedDistanceToLineV03( _
    p As Point2d, _
    a As Point2d, _
    b As Point2d) As Double

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return 0

    Return _
        (dx * (p.Y - a.Y) - dy * (p.X - a.X)) / l
End Function


Function SheetPointDistanceV03(a As Point2d, b As Point2d) As Double
    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Return Math.Sqrt(dx * dx + dy * dy)
End Function


Function CenterlineNearPointV03( _
    centerline As Centerline, _
    view As DrawingView, _
    target As Point2d, _
    tolerance As Double) As Boolean

    Try
        Dim mx As Double = (centerline.StartPoint.X + centerline.EndPoint.X) / 2.0
        Dim my As Double = (centerline.StartPoint.Y + centerline.EndPoint.Y) / 2.0
        Dim rightX As Double = view.Left + view.Width
        Dim bottomY As Double = view.Top - view.Height

        If mx < view.Left - 0.2 OrElse mx > rightX + 0.2 OrElse _
           my < bottomY - 0.2 OrElse my > view.Top + 0.2 Then
            Return False
        End If

        Return _
            DistancePointToInfiniteLineV03( _
                target, centerline.StartPoint, centerline.EndPoint) <= tolerance
    Catch
        Return False
    End Try
End Function


Function FindCenterlineIntentAtPointV03( _
    sheet As Sheet, _
    view As DrawingView, _
    target As Point2d) As GeometryIntent

    Dim near As New List(Of Centerline)

    For i As Integer = 1 To sheet.Centerlines.Count
        Dim cl As Centerline = sheet.Centerlines.Item(i)
        If CenterlineNearPointV03(cl, view, target, 0.10) Then
            near.Add(cl)
        End If
    Next

    If near.Count >= 2 Then
        For i As Integer = 0 To near.Count - 2
            For j As Integer = i + 1 To near.Count - 1
                If Not CenterlinesParallelV03(near.Item(i), near.Item(j)) Then
                    Try
                        Return _
                            sheet.CreateGeometryIntent( _
                                near.Item(i), _
                                near.Item(j))
                    Catch
                    End Try
                End If
            Next
        Next
    End If

    If near.Count > 0 Then
        Try
            Return sheet.CreateGeometryIntent(near.Item(0), target)
        Catch
            Return sheet.CreateGeometryIntent(near.Item(0))
        End Try
    End If

    Return Nothing
End Function


Function CenterlinesParallelV03(a As Centerline, b As Centerline) As Boolean
    Try
        Dim ax As Double = a.EndPoint.X - a.StartPoint.X
        Dim ay As Double = a.EndPoint.Y - a.StartPoint.Y
        Dim bx As Double = b.EndPoint.X - b.StartPoint.X
        Dim by As Double = b.EndPoint.Y - b.StartPoint.Y
        Dim al As Double = Math.Sqrt(ax * ax + ay * ay)
        Dim bl As Double = Math.Sqrt(bx * bx + by * by)
        If al < 0.0001 OrElse bl < 0.0001 Then Return True
        Dim dot As Double = Math.Abs((ax * bx + ay * by) / (al * bl))
        Return dot > 0.995
    Catch
        Return True
    End Try
End Function


Sub EnsureBisectorCenterlinesForNodeV03( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d)

    If node Is Nothing OrElse node.Occurrence Is Nothing Then Exit Sub

    ' If the Automated Centerline command already created two useful axes,
    ' do not add anything else.
    Dim existing As Integer = 0
    For i As Integer = 1 To sheet.Centerlines.Count
        If CenterlineNearPointV03( _
            sheet.Centerlines.Item(i), view, target, 0.10) Then
            existing += 1
        End If
    Next
    If existing >= 2 Then Exit Sub

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(node.Occurrence)
        If curves Is Nothing Then Exit Sub

        Dim lines As New List(Of DrawingCurve)
        For Each c As DrawingCurve In curves
            If c.CurveType = CurveTypeEnum.kLineSegmentCurve AndAlso _
               c.StartPoint IsNot Nothing AndAlso _
               c.EndPoint IsNot Nothing Then
                lines.Add(c)
            End If
        Next

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

                If da * db >= 0 Then Continue For
                If Math.Abs(Math.Abs(da) - Math.Abs(db)) > 0.12 Then Continue For
                If Math.Abs(da) + Math.Abs(db) < 0.08 Then Continue For

                Try
                    Dim ia As GeometryIntent = sheet.CreateGeometryIntent(a)
                    Dim ib As GeometryIntent = sheet.CreateGeometryIntent(b)
                    Dim cl As Centerline = _
                        sheet.Centerlines.AddBisector(ia, ib)

                    If CenterlineNearPointV03(cl, view, target, 0.10) Then
                        TagAutoObjectV01(cl)
                        existing += 1
                    Else
                        cl.Delete()
                    End If
                Catch
                End Try

                If existing >= 2 Then Exit Sub
            Next
        Next

    Catch ex As Exception
        Logger.Error( _
            "Bisector centerline generation failed for " & _
            node.Code & ": " & ex.Message)
    End Try
End Sub


Function DrawingLinesParallelV03(a As DrawingCurve, b As DrawingCurve) As Boolean
    Try
        Dim ax As Double = a.EndPoint.X - a.StartPoint.X
        Dim ay As Double = a.EndPoint.Y - a.StartPoint.Y
        Dim bx As Double = b.EndPoint.X - b.StartPoint.X
        Dim by As Double = b.EndPoint.Y - b.StartPoint.Y
        Dim al As Double = Math.Sqrt(ax * ax + ay * ay)
        Dim bl As Double = Math.Sqrt(bx * bx + by * by)
        If al < 0.0001 OrElse bl < 0.0001 Then Return False
        Dim dot As Double = Math.Abs((ax * bx + ay * by) / (al * bl))
        Return dot > 0.995
    Catch
        Return False
    End Try
End Function'''

s2, n = rx.subn(new_funcs, s, count=1)
if n != 1:
    raise SystemExit(f'anchor implementation replacement count={n}')
s = s2

# Every dimension set now consumes already-resolved real drawing intents.
s = s.replace('CreateAnchorIntentV02(sheet, anchor)', 'anchor.Intent')
s = s.replace('CreateAnchorIntentV02(sheet, firstAnchor)', 'firstAnchor.Intent')
s = s.replace('CreateAnchorIntentV02(sheet, lastAnchor)', 'lastAnchor.Intent')
s = s.replace('CreateAnchorIntentV02(sheet, plan.Datum)', 'plan.Datum.Intent')
s = s.replace('CreateAnchorIntentV02(sheet, request.A)', 'request.A.Intent')
s = s.replace('CreateAnchorIntentV02(sheet, request.B)', 'request.B.Intent')

# Skip unresolved semantic anchors instead of sending Nothing into Inventor.
s = s.replace('''            For Each anchor As AutoDimAnchorV01 In request.Anchors
                intents.Add( _
                    anchor.Intent)
            Next

            Dim dimSet As ChainDimensionSet''', '''            For Each anchor As AutoDimAnchorV01 In request.Anchors
                If anchor.Intent IsNot Nothing Then
                    intents.Add(anchor.Intent)
                End If
            Next

            If intents.Count < 2 Then Continue For

            Dim dimSet As ChainDimensionSet''', 1)

# Overall dimension guard.
s = s.replace('''            Dim intent1 As GeometryIntent = _
                firstAnchor.Intent
            Dim intent2 As GeometryIntent = _
                lastAnchor.Intent

            Dim dimObj As LinearGeneralDimension''', '''            If firstAnchor.Intent Is Nothing OrElse _
               lastAnchor.Intent Is Nothing Then
                Continue For
            End If

            Dim intent1 As GeometryIntent = firstAnchor.Intent
            Dim intent2 As GeometryIntent = lastAnchor.Intent

            Dim dimObj As LinearGeneralDimension''', 1)

# Attachment baseline/rise guards and direct intents.
s = s.replace('''            intents.Add( _
                plan.Datum.Intent)

            For Each anchor As AutoDimAnchorV01 In plan.StationAnchors
                intents.Add( _
                    anchor.Intent)
            Next

            Dim baselineSet As BaselineDimensionSet''', '''            If plan.Datum.Intent IsNot Nothing Then
                intents.Add(plan.Datum.Intent)
            End If

            For Each anchor As AutoDimAnchorV01 In plan.StationAnchors
                If anchor.Intent IsNot Nothing Then
                    intents.Add(anchor.Intent)
                End If
            Next

            If intents.Count < 2 Then
                Throw New Exception("Not enough projected geometry intents for attachment baseline.")
            End If

            Dim baselineSet As BaselineDimensionSet''', 1)

s = s.replace('''        Try
            Dim intent1 As GeometryIntent = _
                request.A.Intent
            Dim intent2 As GeometryIntent = _
                request.B.Intent

            Dim dimObj As LinearGeneralDimension''', '''        Try
            If request.A.Intent Is Nothing OrElse _
               request.B.Intent Is Nothing Then
                Continue For
            End If

            Dim intent1 As GeometryIntent = request.A.Intent
            Dim intent2 As GeometryIntent = request.B.Intent

            Dim dimObj As LinearGeneralDimension''', 1)

# Anchor data no longer has any sketch geometry.
s = s.replace('''    Public SheetPoint As Point2d = Nothing
    Public Entity As SketchLine = Nothing
End Class''', '''    Public SheetPoint As Point2d = Nothing
    Public Intent As GeometryIntent = Nothing
    Public SourceDescription As String = ""
End Class''', 1)

# Individual chain fallback must also use resolved projected intents.
s = s.replace('CreateAnchorIntentV02(sheet, a)', 'a.Intent')
s = s.replace('CreateAnchorIntentV02(sheet, b)', 'b.Intent')

# Ensure the source contains no active anchor sketch creation.
if 'CreateAnchorSketchV01(' in s:
    raise SystemExit('CreateAnchorSketchV01 still present')
if 'CreateAnchorIntentV02(' in s:
    raise SystemExit('CreateAnchorIntentV02 still present')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.3 projected drawing geometry')
