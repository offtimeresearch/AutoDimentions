from pathlib import Path

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

# ---------------------------------------------------------------------------
# Version strings / status.
# ---------------------------------------------------------------------------
text = text.replace('DimensionGenerator V0.7.2', 'DimensionGenerator V0.8')
text = text.replace('V0.7.2: centerline preservation diagnostics enabled; fitting centers still use ONE existing directional centerline; attachments deferred.',
                    'V0.8: safe PIPE/FLANGE centerlines are ensured inside DimensionGenerator before directional fitting-center dimensions; attachments deferred.')

# ---------------------------------------------------------------------------
# Main: create/reuse safe centerlines immediately after old auto dimensions
# are removed, before any fitting-center intent is resolved.
# ---------------------------------------------------------------------------
needle = '''        DeletePreviousAutoDimensionsV01(sheet)\n\n        Logger.Info( _\n            "CENTERLINE_COUNT AFTER_CLEANUP=" & _\n            sheet.Centerlines.Count.ToString())\n'''
replacement = '''        DeletePreviousAutoDimensionsV01(sheet)\n\n        Logger.Info( _\n            "CENTERLINE_COUNT AFTER_CLEANUP=" & _\n            sheet.Centerlines.Count.ToString())\n\n        Dim integratedCenterlineCount As Integer = _\n            EnsureSafeSpoolCenterlinesV08( _\n                sheet, _\n                view, _\n                nodes)\n\n        drawDoc.Update2(True)\n\n        Logger.Info( _\n            "CENTERLINE_INTEGRATED ensured=" & _\n            integratedCenterlineCount.ToString() & _\n            " | sheet total=" & _\n            sheet.Centerlines.Count.ToString())\n'''

if 'CENTERLINE_INTEGRATED ensured=' not in text:
    if needle not in text:
        raise RuntimeError('Could not locate post-cleanup insertion point')
    text = text.replace(needle, replacement, 1)

# ---------------------------------------------------------------------------
# Safe centerline creation helpers.
# Reuses the already-proven CenterlineGenerator V0.2 mechanism:
# real topology-known port faces -> midpoint/center point intents ->
# sheet.Centerlines.Add(ObjectCollection).
# ---------------------------------------------------------------------------
marker = 'Function ResolveProjectedAnchorsV03( _'
if marker not in text:
    raise RuntimeError('Could not locate ResolveProjectedAnchorsV03 marker')

helpers = r'''

' ===================================================================
' V0.8 INTEGRATED SAFE PIPE / FLANGE CENTERLINES
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
        "CENTERLINE_INTEGRATED begin | existing=" & _
        sheet.Centerlines.Count.ToString())

    For Each node As NodeRecord In nodes

        If node Is Nothing OrElse node.Occurrence Is Nothing Then
            Continue For
        End If

        If node.ComponentType <> "PIPE" AndAlso _
           node.ComponentType <> "FLANGE" Then
            Continue For
        End If

        If HasIntegratedCenterlineV08( _
            sheet, _
            node.OccurrenceName, _
            node.ComponentType) Then

            Logger.Info( _
                "CENTERLINE_INTEGRATED reuse " & _
                node.ComponentType & " | " & node.OccurrenceName)

            ensured += 1
            Continue For
        End If

        Dim pair As PortPairV08 = _
            FindBestPortPairV08( _
                view, _
                node.Ports)

        If pair Is Nothing Then
            Logger.Info( _
                "CENTERLINE_INTEGRATED skip " & _
                node.ComponentType & " | " & node.OccurrenceName & _
                " | no safe coaxial port pair")
            Continue For
        End If

        Logger.Info( _
            "CENTERLINE_PORT_PAIR " & node.ComponentType & _
            " | " & node.OccurrenceName & _
            " | faces=" & pair.A.FaceIndex.ToString() & _
            "," & pair.B.FaceIndex.ToString() & _
            " | axial_mm=" & Num(pair.AxialDistance) & _
            " | lateral_mm=" & Num(pair.LateralDistance))

        Dim intentA As GeometryIntent = _
            FindPortPointIntentV08( _
                sheet, view, node.Occurrence, pair.A)

        Dim intentB As GeometryIntent = _
            FindPortPointIntentV08( _
                sheet, view, node.Occurrence, pair.B)

        If intentA Is Nothing OrElse intentB Is Nothing Then
            Logger.Error( _
                "CENTERLINE_INTEGRATED missing port point intent " & _
                node.ComponentType & " | " & node.OccurrenceName)
            Continue For
        End If

        Try
            Dim points As ObjectCollection = _
                ThisApplication.TransientObjects.CreateObjectCollection()

            points.Add(intentA)
            points.Add(intentB)

            Logger.Info( _
                "CENTERLINES_ADD BEGIN " & _
                node.ComponentType & " | " & node.OccurrenceName)

            Dim cl As Centerline = _
                sheet.Centerlines.Add(points)

            Logger.Info( _
                "CENTERLINES_ADD RETURN " & _
                node.ComponentType & " | " & node.OccurrenceName)

            If cl Is Nothing Then Continue For

            TagIntegratedCenterlineV08( _
                cl, _
                node.OccurrenceName, _
                node.ComponentType, _
                pair)

            ensured += 1

        Catch ex As Exception
            Logger.Error( _
                "CENTERLINE_INTEGRATED Centerlines.Add failed " & _
                node.ComponentType & " | " & node.OccurrenceName & _
                " | " & ex.Message)
        End Try

    Next

    Logger.Info( _
        "CENTERLINE_INTEGRATED end | ensured=" & _
        ensured.ToString() & _
        " | total=" & sheet.Centerlines.Count.ToString())

    Return ensured
End Function


Function HasIntegratedCenterlineV08( _
    sheet As Sheet, _
    occurrenceName As String, _
    componentType As String) As Boolean

    If sheet Is Nothing Then Return False

    Try
        For i As Integer = 1 To sheet.Centerlines.Count

            Dim cl As Centerline = sheet.Centerlines.Item(i)
            If cl Is Nothing Then Continue For

            Try
                Dim tags As AttributeSet = _
                    cl.AttributeSets.Item("AutoSpoolCenterline")

                Dim owner As String = _
                    CStr(tags.Item("Occurrence").Value)

                Dim kind As String = _
                    CStr(tags.Item("ComponentType").Value)

                If owner = occurrenceName AndAlso kind = componentType Then
                    Return True
                End If
            Catch
            End Try
        Next
    Catch
    End Try

    Return False
End Function


Function FindBestPortPairV08( _
    view As DrawingView, _
    ports As List(Of PortRecord)) As PortPairV08

    If view Is Nothing OrElse ports Is Nothing OrElse ports.Count < 2 Then
        Return Nothing
    End If

    Dim best As PortPairV08 = Nothing
    Dim bestScore As Double = -Double.MaxValue

    For i As Integer = 0 To ports.Count - 2
        For j As Integer = i + 1 To ports.Count - 1

            Dim a As PortRecord = ports.Item(i)
            Dim b As PortRecord = ports.Item(j)

            If a Is Nothing OrElse b Is Nothing Then Continue For
            If a.ModelFace Is Nothing OrElse b.ModelFace Is Nothing Then Continue For

            Dim normalAlignment As Double = _
                Math.Abs( _
                    a.NX * b.NX + _
                    a.NY * b.NY + _
                    a.NZ * b.NZ)

            If normalAlignment < 0.98 Then Continue For

            Dim dx As Double = b.X - a.X
            Dim dy As Double = b.Y - a.Y
            Dim dz As Double = b.Z - a.Z

            Dim total As Double = _
                Math.Sqrt(dx * dx + dy * dy + dz * dz)

            If total < 0.5 Then Continue For

            Dim axial As Double = _
                Math.Abs( _
                    dx * a.NX + _
                    dy * a.NY + _
                    dz * a.NZ)

            If axial < 0.5 Then Continue For

            Dim lateral2 As Double = total * total - axial * axial
            If lateral2 < 0 Then lateral2 = 0

            Dim lateral As Double = Math.Sqrt(lateral2)

            ' Topology data is in mm.  Keep the same 1 mm coaxial limit that
            ' proved reliable in the standalone centerline generator.
            If lateral > 1.0 Then Continue For

            Dim sheetA As Point2d = ProjectPortCenterV08(view, a)
            Dim sheetB As Point2d = ProjectPortCenterV08(view, b)

            If sheetA Is Nothing OrElse sheetB Is Nothing Then Continue For

            Dim sdx As Double = sheetB.X - sheetA.X
            Dim sdy As Double = sheetB.Y - sheetA.Y
            Dim sheetDistance As Double = Math.Sqrt(sdx * sdx + sdy * sdy)

            ' Port axis effectively normal to this drawing view.
            If sheetDistance < 0.03 Then Continue For

            Dim minRadius As Double = Math.Min(a.Radius, b.Radius)

            ' Prefer large real coaxial circular faces, then axial separation.
            ' This suppresses flange bolt-hole candidates.
            Dim score As Double = _
                minRadius * 1000.0 + _
                axial * 10.0 + _
                sheetDistance - _
                lateral * 1000.0 + _
                normalAlignment

            If best Is Nothing OrElse score > bestScore Then
                bestScore = score
                best = New PortPairV08
                best.A = a
                best.B = b
                best.NormalAlignment = normalAlignment
                best.AxialDistance = axial
                best.LateralDistance = lateral
                best.SheetDistance = sheetDistance
                best.Score = score
            End If

        Next
    Next

    Return best
End Function


Function ProjectPortCenterV08( _
    view As DrawingView, _
    port As PortRecord) As Point2d

    If view Is Nothing OrElse port Is Nothing Then Return Nothing

    Try
        Dim modelPoint As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                port.X / 10.0, _
                port.Y / 10.0, _
                port.Z / 10.0)

        Return view.ModelToSheetSpace(modelPoint)
    Catch
        Return Nothing
    End Try
End Function


Function FindPortPointIntentV08( _
    sheet As Sheet, _
    view As DrawingView, _
    occurrence As ComponentOccurrence, _
    port As PortRecord) As GeometryIntent

    If sheet Is Nothing OrElse view Is Nothing OrElse _
       occurrence Is Nothing OrElse port Is Nothing Then
        Return Nothing
    End If

    Dim target As Point2d = ProjectPortCenterV08(view, port)
    If target Is Nothing Then Return Nothing

    ' First choice: drawing curves produced specifically by the real port face.
    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(port.ModelFace)

        Dim faceIntent As GeometryIntent = _
            BestPortPointIntentFromCurvesV08( _
                sheet, curves, target, 0.30)

        If faceIntent IsNot Nothing Then
            Logger.Info( _
                "PORT_INTENT FACE | " & occurrence.Name & _
                " | face=" & port.FaceIndex.ToString())
            Return faceIntent
        End If
    Catch ex As Exception
        Logger.Info( _
            "PORT_INTENT face lookup fallback | " & occurrence.Name & _
            " | face=" & port.FaceIndex.ToString() & _
            " | " & ex.Message)
    End Try

    ' Conservative fallback: only projected curves from the SAME occurrence.
    Try
        Dim occurrenceCurves As DrawingCurvesEnumerator = _
            view.DrawingCurves(occurrence)

        Dim fallbackIntent As GeometryIntent = _
            BestPortPointIntentFromCurvesV08( _
                sheet, occurrenceCurves, target, 0.18)

        If fallbackIntent IsNot Nothing Then
            Logger.Info( _
                "PORT_INTENT OCCURRENCE_FALLBACK | " & occurrence.Name & _
                " | face=" & port.FaceIndex.ToString())
            Return fallbackIntent
        End If
    Catch ex As Exception
        Logger.Error( _
            "PORT_INTENT occurrence lookup failed | " & occurrence.Name & _
            " | " & ex.Message)
    End Try

    Return Nothing
End Function


Function BestPortPointIntentFromCurvesV08( _
    sheet As Sheet, _
    curves As DrawingCurvesEnumerator, _
    target As Point2d, _
    maxDistance As Double) As GeometryIntent

    If sheet Is Nothing OrElse curves Is Nothing OrElse target Is Nothing Then
        Return Nothing
    End If

    Dim bestCurve As DrawingCurve = Nothing
    Dim bestIntentType As Integer = 0
    Dim bestDistance As Double = maxDistance

    For Each curve As DrawingCurve In curves
        Try
            If curve.CurveType = CurveTypeEnum.kLineSegmentCurve AndAlso _
               curve.StartPoint IsNot Nothing AndAlso _
               curve.EndPoint IsNot Nothing Then

                Dim mx As Double = _
                    (curve.StartPoint.X + curve.EndPoint.X) / 2.0
                Dim my As Double = _
                    (curve.StartPoint.Y + curve.EndPoint.Y) / 2.0

                Dim dx As Double = mx - target.X
                Dim dy As Double = my - target.Y
                Dim d As Double = Math.Sqrt(dx * dx + dy * dy)

                If d <= bestDistance Then
                    bestDistance = d
                    bestCurve = curve
                    bestIntentType = 1
                End If

            ElseIf _
                (curve.CurveType = CurveTypeEnum.kCircleCurve OrElse _
                 curve.CurveType = CurveTypeEnum.kCircularArcCurve OrElse _
                 curve.CurveType = CurveTypeEnum.kEllipseFullCurve OrElse _
                 curve.CurveType = CurveTypeEnum.kEllipticalArcCurve) AndAlso _
                 curve.CenterPoint IsNot Nothing Then

                Dim dx As Double = curve.CenterPoint.X - target.X
                Dim dy As Double = curve.CenterPoint.Y - target.Y
                Dim d As Double = Math.Sqrt(dx * dx + dy * dy)

                If d <= bestDistance Then
                    bestDistance = d
                    bestCurve = curve
                    bestIntentType = 2
                End If
            End If
        Catch
        End Try
    Next

    If bestCurve Is Nothing Then Return Nothing

    Try
        If bestIntentType = 1 Then
            Return _
                sheet.CreateGeometryIntent( _
                    bestCurve, _
                    PointIntentEnum.kMidPointIntent)
        End If

        If bestIntentType = 2 Then
            Return _
                sheet.CreateGeometryIntent( _
                    bestCurve, _
                    PointIntentEnum.kCenterPointIntent)
        End If
    Catch ex As Exception
        Logger.Error( _
            "CENTERLINE_INTEGRATED port point intent failed: " & ex.Message)
    End Try

    Return Nothing
End Function


Sub TagIntegratedCenterlineV08( _
    cl As Centerline, _
    occurrenceName As String, _
    componentType As String, _
    pair As PortPairV08)

    If cl Is Nothing Then Exit Sub

    Try
        Dim tags As AttributeSet = Nothing

        Try
            tags = cl.AttributeSets.Item("AutoSpoolCenterline")
        Catch
            tags = cl.AttributeSets.Add("AutoSpoolCenterline")
        End Try

        Try : tags.Add("Occurrence", ValueTypeEnum.kStringType, occurrenceName) : Catch : End Try
        Try : tags.Add("ComponentType", ValueTypeEnum.kStringType, componentType) : Catch : End Try
        Try : tags.Add("GeneratorVersion", ValueTypeEnum.kStringType, "0.8") : Catch : End Try
        Try : tags.Add("Method", ValueTypeEnum.kStringType, "REGULAR_PORT_POINTS") : Catch : End Try
        Try : tags.Add("FaceA", ValueTypeEnum.kIntegerType, pair.A.FaceIndex) : Catch : End Try
        Try : tags.Add("FaceB", ValueTypeEnum.kIntegerType, pair.B.FaceIndex) : Catch : End Try
    Catch
    End Try
End Sub


Class PortPairV08
    Public A As PortRecord = Nothing
    Public B As PortRecord = Nothing
    Public NormalAlignment As Double
    Public AxialDistance As Double
    Public LateralDistance As Double
    Public SheetDistance As Double
    Public Score As Double
End Class

'''

if 'Function EnsureSafeSpoolCenterlinesV08' not in text:
    text = text.replace(marker, helpers + marker, 1)

# Static sanity checks for the integrated active path.
assert 'EnsureSafeSpoolCenterlinesV08' in text
assert 'CENTERLINE_INTEGRATED ensured=' in text
assert 'sheet.Centerlines.Add(points)' in text
assert 'REGULAR_PORT_POINTS' in text

# The new helper block itself must never use AddBisector or centerline intersections.
start = text.index("Function EnsureSafeSpoolCenterlinesV08")
end = text.index("Function ResolveProjectedAnchorsV03", start)
block = text[start:end]
assert 'AddBisector' not in block
assert 'CreateGeometryIntent(cl,' not in block
assert 'CreateGeometryIntent( _\n                                cl,' not in block

path.write_text(text, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator to V0.8 integrated safe centerlines.')
