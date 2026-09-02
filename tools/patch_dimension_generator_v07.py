from pathlib import Path
import re

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

# Version / user-facing status.
text = text.replace('DIMENSION GENERATOR V0.6.3.1 - STABLE PROJECTED CURVES + CHAINS',
                    'DIMENSION GENERATOR V0.7 - DIRECTIONAL CENTERLINE DATUMS + SAFE CHAINS')
text = text.replace('DimensionGenerator V0.6.3.1', 'DimensionGenerator V0.7')
text = text.replace(
    'Logger.Info("V0.6.3.1 stable mode: projected-curve chains enabled; fitting-center and attachment dimensions deferred.")',
    'Logger.Info("V0.7: projected-curve chains enabled; fitting centers use ONE existing perpendicular centerline; attachment dimensions remain deferred.")')
text = text.replace(
    '"Projected semantic anchors: " & _',
    '"Semantic anchors ready (physical or directional center): " & _')

# DimensionGenerator must never delete centerlines created by CenterlineGenerator.
old_centerline_delete = '''    Try\n        For i As Integer = sheet.Centerlines.Count To 1 Step -1\n            If IsAutoTaggedV01(sheet.Centerlines.Item(i)) Then\n                sheet.Centerlines.Item(i).Delete()\n            End If\n        Next\n    Catch\n    End Try\n\n'''
if old_centerline_delete in text:
    text = text.replace(old_centerline_delete,
                        "    ' V0.7: centerlines belong to CenterlineGenerator and are never deleted here.\n\n")


def replace_function(name: str, replacement: str):
    global text
    pattern = re.compile(r'Function\s+' + re.escape(name) + r'\s*\(.*?\nEnd Function', re.S)
    m = pattern.search(text)
    if not m:
        raise RuntimeError(f'Function not found: {name}')
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


replace_function('ResolveProjectedAnchorsV03', r'''Function ResolveProjectedAnchorsV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchors As List(Of AutoDimAnchorV01)) As Integer

    Dim unresolved As Integer = 0

    For Each anchor As AutoDimAnchorV01 In anchors

        anchor.Intent = _
            ResolveProjectedIntentV03( _
                sheet, view, nodes, anchor)

        If anchor.Intent IsNot Nothing Then
            Continue For
        End If

        Dim nearNode As NodeRecord = _
            FindReferenceNodeAtPointV03( _
                nodes, anchor.X, anchor.Y, anchor.Z, 1.0)

        ' TEE / ELBOW centres are theoretical points.  Do NOT manufacture an
        ' intersection GeometryIntent.  Mark them as directional datums; the
        ' actual dimension direction later chooses ONE existing centerline.
        If nearNode IsNot Nothing AndAlso _
           (nearNode.ComponentType = "TEE" OrElse _
            nearNode.ComponentType = "ELBOW") Then

            anchor.IsFittingCenter = True
            anchor.FittingCode = nearNode.Code
            anchor.FittingType = nearNode.ComponentType
            anchor.SourceDescription = _
                nearNode.Code & " DIRECTIONAL CENTERLINE DATUM"

            Logger.Info( _
                "CENTER_ANCHOR READY " & _
                nearNode.Code & "/" & nearNode.ComponentType & _
                " | center will use one perpendicular existing centerline")

            Continue For
        End If

        unresolved += 1

        Dim semanticName As String = "UNKNOWN"
        If nearNode IsNot Nothing Then
            semanticName = _
                nearNode.Code & "/" & nearNode.ComponentType & "/" & nearNode.ReferenceType
        End If

        Logger.Error( _
            "No projected geometry for semantic anchor " & semanticName & _
            " at model mm (" & _
            Num(anchor.X) & ", " & Num(anchor.Y) & ", " & Num(anchor.Z) & ")")

    Next

    Return unresolved
End Function''')

replace_function('ResolveFittingCenterIntentV04', r'''Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' V0.7 SAFETY: never create or consume a centerline intersection here.
    ' Fitting-centre anchors are marked in ResolveProjectedAnchorsV03 and the
    ' dimension direction later resolves ONE perpendicular native centerline.
    Return Nothing
End Function


Function ResolveAnchorIntentForDimensionV07( _
    sheet As Sheet, _
    anchor As AutoDimAnchorV01, _
    dimensionType As DimensionTypeEnum) As GeometryIntent

    If anchor Is Nothing Then Return Nothing

    If anchor.Intent IsNot Nothing Then
        Return anchor.Intent
    End If

    If Not anchor.IsFittingCenter Then Return Nothing

    If dimensionType = DimensionTypeEnum.kHorizontalDimensionType Then
        If anchor.HorizontalDimensionIntent IsNot Nothing Then
            Return anchor.HorizontalDimensionIntent
        End If

        Dim verticalAxis As Centerline = _
            FindDirectionalCenterlineDatumV07( _
                sheet, anchor.SheetPoint, True)

        If verticalAxis Is Nothing Then
            Logger.Error( _
                "CENTER_DATUM missing vertical axis for horizontal dimension | " & _
                anchor.FittingCode & "/" & anchor.FittingType)
            Return Nothing
        End If

        Try
            anchor.HorizontalDimensionIntent = _
                sheet.CreateGeometryIntent(verticalAxis)

            Logger.Info( _
                "CENTER_DATUM " & anchor.FittingCode & "/" & anchor.FittingType & _
                " | horizontal dimension -> ONE vertical centerline")

            Return anchor.HorizontalDimensionIntent
        Catch ex As Exception
            Logger.Error( _
                "CENTER_DATUM vertical centerline intent failed for " & _
                anchor.FittingCode & ": " & ex.Message)
            Return Nothing
        End Try
    End If

    If dimensionType = DimensionTypeEnum.kVerticalDimensionType Then
        If anchor.VerticalDimensionIntent IsNot Nothing Then
            Return anchor.VerticalDimensionIntent
        End If

        Dim horizontalAxis As Centerline = _
            FindDirectionalCenterlineDatumV07( _
                sheet, anchor.SheetPoint, False)

        If horizontalAxis Is Nothing Then
            Logger.Error( _
                "CENTER_DATUM missing horizontal axis for vertical dimension | " & _
                anchor.FittingCode & "/" & anchor.FittingType)
            Return Nothing
        End If

        Try
            anchor.VerticalDimensionIntent = _
                sheet.CreateGeometryIntent(horizontalAxis)

            Logger.Info( _
                "CENTER_DATUM " & anchor.FittingCode & "/" & anchor.FittingType & _
                " | vertical dimension -> ONE horizontal centerline")

            Return anchor.VerticalDimensionIntent
        Catch ex As Exception
            Logger.Error( _
                "CENTER_DATUM horizontal centerline intent failed for " & _
                anchor.FittingCode & ": " & ex.Message)
            Return Nothing
        End Try
    End If

    Logger.Info( _
        "CENTER_DATUM aligned fitting-center dimension deferred for " & _
        anchor.FittingCode & "/" & anchor.FittingType)

    Return Nothing
End Function


Function FindDirectionalCenterlineDatumV07( _
    sheet As Sheet, _
    target As Point2d, _
    wantVerticalAxis As Boolean) As Centerline

    If sheet Is Nothing OrElse target Is Nothing Then Return Nothing

    Dim best As Centerline = Nothing
    Dim bestScore As Double = Double.MaxValue

    Try
        For i As Integer = 1 To sheet.Centerlines.Count

            Dim cl As Centerline = sheet.Centerlines.Item(i)
            If cl Is Nothing Then Continue For

            Dim a As Point2d = Nothing
            Dim b As Point2d = Nothing

            Try
                a = cl.StartPoint
                b = cl.EndPoint
            Catch
                Continue For
            End Try

            If a Is Nothing OrElse b Is Nothing Then Continue For

            Dim dx As Double = b.X - a.X
            Dim dy As Double = b.Y - a.Y
            Dim length As Double = Math.Sqrt(dx * dx + dy * dy)
            If length < 0.001 Then Continue For

            Dim ux As Double = dx / length
            Dim uy As Double = dy / length

            Dim orientation As Double
            If wantVerticalAxis Then
                orientation = Math.Abs(uy)
            Else
                orientation = Math.Abs(ux)
            End If

            ' Horizontal dimensions need a near-vertical datum; vertical
            ' dimensions need a near-horizontal datum.
            If orientation < 0.96 Then Continue For

            Dim axisDistance As Double = _
                DistancePointToInfiniteLineV03(target, a, b)

            ' 0.18 cm = 1.8 mm on the sheet.  The topology-projected fitting
            ' centre should lie essentially on the correct pipe/flange axis.
            If axisDistance > 0.18 Then Continue For

            Dim tagBonus As Double = 0
            Try
                Dim tags As AttributeSet = _
                    cl.AttributeSets.Item("AutoSpoolCenterline")
                If tags IsNot Nothing Then tagBonus = -0.02
            Catch
            End Try

            Dim score As Double = _
                axisDistance + _
                (1.0 - orientation) * 0.20 + _
                tagBonus

            If best Is Nothing OrElse score < bestScore Then
                best = cl
                bestScore = score
            End If
        Next
    Catch ex As Exception
        Logger.Error("CENTER_DATUM centerline scan failed: " & ex.Message)
        Return Nothing
    End Try

    Return best
End Function''')

replace_function('CreateChainDimensionsV01', r'''Function CreateChainDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests

        If request.Anchors.Count < 2 Then Continue For

        Dim usesDirectionalCenter As Boolean = False

        Try
            Dim intents As ObjectCollection = _
                ThisApplication.TransientObjects.CreateObjectCollection()

            For Each anchor As AutoDimAnchorV01 In request.Anchors

                If anchor.IsFittingCenter Then
                    usesDirectionalCenter = True
                End If

                Dim resolvedIntent As GeometryIntent = _
                    ResolveAnchorIntentForDimensionV07( _
                        sheet, anchor, request.DimensionType)

                If resolvedIntent IsNot Nothing Then
                    intents.Add(resolvedIntent)
                End If
            Next

            If intents.Count < 2 Then Continue For

            ' ChainDimensionSet + centerline GeometryIntent is not yet proven
            ' in this Inventor build.  Keep native chain sets for pure projected
            ' geometry, and use the already-proven AddLinear path when a fitting
            ' center is involved. CenterlineChainProbe validates the final step.
            If usesDirectionalCenter Then
                Logger.Info( _
                    "CENTER_CHAIN SAFE_FALLBACK " & request.Name & _
                    " | using individual linear dimensions until chain probe passes")

                created += _
                    CreateIndividualChainFallbackV02( _
                        sheet, _
                        request)

                Continue For
            End If

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
End Function''')

replace_function('CreateIndividualChainFallbackV02', r'''Function CreateIndividualChainFallbackV02( _
    sheet As Sheet, _
    request As AutoChainRequestV01) As Integer

    Dim created As Integer = 0

    If request Is Nothing OrElse request.Anchors.Count < 2 Then
        Return created
    End If

    For i As Integer = 0 To request.Anchors.Count - 2

        Try
            Dim a As AutoDimAnchorV01 = request.Anchors.Item(i)
            Dim b As AutoDimAnchorV01 = request.Anchors.Item(i + 1)

            Dim intent1 As GeometryIntent = _
                ResolveAnchorIntentForDimensionV07( _
                    sheet, a, request.DimensionType)

            Dim intent2 As GeometryIntent = _
                ResolveAnchorIntentForDimensionV07( _
                    sheet, b, request.DimensionType)

            If intent1 Is Nothing OrElse intent2 Is Nothing Then
                Continue For
            End If

            Dim textPoint As Point2d = _
                request.PlacementPoint.Copy()

            If request.DimensionType = _
               DimensionTypeEnum.kHorizontalDimensionType Then

                textPoint.X = _
                    (a.SheetPoint.X + b.SheetPoint.X) / 2.0

            ElseIf request.DimensionType = _
                   DimensionTypeEnum.kVerticalDimensionType Then

                textPoint.Y = _
                    (a.SheetPoint.Y + b.SheetPoint.Y) / 2.0

            Else

                textPoint.X = _
                    (a.SheetPoint.X + b.SheetPoint.X) / 2.0
                textPoint.Y = _
                    (a.SheetPoint.Y + b.SheetPoint.Y) / 2.0
            End If

            Dim dimObj As LinearGeneralDimension = _
                sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                    textPoint, _
                    intent1, _
                    intent2, _
                    request.DimensionType)

            Try
                dimObj.Precision = 0
            Catch
            End Try

            TagAutoObjectV01(dimObj)
            created += 1

        Catch ex As Exception
            Logger.Error( _
                "Individual chain fallback failed for " & _
                request.Name & _
                " member " & _
                (i + 1).ToString() & _
                ": " & _
                ex.Message)
        End Try

    Next

    Return created
End Function''')

replace_function('CreateOverallDimensionsV01', r'''Function CreateOverallDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests

        If request.Anchors.Count <= 2 Then Continue For

        Try
            Dim firstAnchor As AutoDimAnchorV01 = request.Anchors.Item(0)
            Dim lastAnchor As AutoDimAnchorV01 = _
                request.Anchors.Item(request.Anchors.Count - 1)

            Dim intent1 As GeometryIntent = _
                ResolveAnchorIntentForDimensionV07( _
                    sheet, firstAnchor, request.DimensionType)

            Dim intent2 As GeometryIntent = _
                ResolveAnchorIntentForDimensionV07( _
                    sheet, lastAnchor, request.DimensionType)

            If intent1 Is Nothing OrElse intent2 Is Nothing Then
                Continue For
            End If

            Dim dimObj As LinearGeneralDimension = _
                sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                    request.OverallPlacementPoint, _
                    intent1, _
                    intent2, _
                    request.DimensionType)

            Try
                dimObj.Precision = 0
            Catch
            End Try

            TagAutoObjectV01(dimObj)
            created += 1

        Catch ex As Exception
            Logger.Error( _
                "Overall dimension failed for " & _
                request.Name & _
                ": " & _
                ex.Message)
        End Try

    Next

    Return created
End Function''')

# Expand the anchor record with direction-specific centerline intent caches.
old_anchor = '''Class AutoDimAnchorV01\n    Public X As Double\n    Public Y As Double\n    Public Z As Double\n    Public SheetPoint As Point2d = Nothing\n    Public Intent As GeometryIntent = Nothing\n    Public SourceDescription As String = ""\nEnd Class'''
new_anchor = '''Class AutoDimAnchorV01\n    Public X As Double\n    Public Y As Double\n    Public Z As Double\n    Public SheetPoint As Point2d = Nothing\n\n    ' Physical projected-curve intent.\n    Public Intent As GeometryIntent = Nothing\n\n    ' Theoretical TEE / ELBOW centers are direction dependent.\n    Public IsFittingCenter As Boolean = False\n    Public FittingCode As String = ""\n    Public FittingType As String = ""\n    Public HorizontalDimensionIntent As GeometryIntent = Nothing\n    Public VerticalDimensionIntent As GeometryIntent = Nothing\n\n    Public SourceDescription As String = ""\nEnd Class'''
if old_anchor not in text:
    raise RuntimeError('AutoDimAnchorV01 class block not found')
text = text.replace(old_anchor, new_anchor)

path.write_text(text, encoding='utf-8')
print('DimensionGenerator.vb patched to V0.7')
