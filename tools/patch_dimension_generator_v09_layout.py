from pathlib import Path
import re

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

if 'DimensionGenerator V0.8' not in text:
    raise RuntimeError('Expected DimensionGenerator V0.8 as patch base')

text = text.replace('DimensionGenerator V0.8', 'DimensionGenerator V0.9')
text = text.replace(
    'V0.8: safe PIPE/FLANGE centerlines are ensured inside DimensionGenerator before directional fitting-center dimensions; attachments deferred.',
    'V0.9: native physical chain sets + reference fitting dimensions + cleaned dimension tiers; attachments deferred.')

# Add global vertical envelope overall after per-chain overall creation.
needle = '''        Dim overallCount As Integer = _\n            CreateOverallDimensionsV01( _\n                sheet, _\n                chainRequests)\n'''
replacement = '''        Dim overallCount As Integer = _\n            CreateOverallDimensionsV01( _\n                sheet, _\n                chainRequests)\n\n        overallCount += _\n            CreateGlobalVerticalFlangeOverallV09( _\n                sheet, _\n                view, _\n                nodes)\n'''
if 'CreateGlobalVerticalFlangeOverallV09' not in text:
    if needle not in text:
        raise RuntimeError('Main overall insertion point not found')
    text = text.replace(needle, replacement, 1)


def replace_function(name, replacement):
    global text
    rx = re.compile(r'Function\s+' + re.escape(name) + r'\s*\(.*?\nEnd Function', re.S | re.I)
    m = rx.search(text)
    if not m:
        raise RuntimeError('Function not found: ' + name)
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


replace_function('BuildChainRequestsV01', r'''Function BuildChainRequestsV01( _
    view As DrawingView, _
    componentDimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain), _
    allAnchors As List(Of AutoDimAnchorV01)) As List(Of AutoChainRequestV01)

    Dim result As New List(Of AutoChainRequestV01)
    Dim alignedLevel As Integer = 0

    For Each chain As StraightChain In chains

        Dim dimensionsOnChain As New List(Of DimensionRecord)
        For Each d As DimensionRecord In componentDimensions
            If d.ChainIndex = chain.Index Then dimensionsOnChain.Add(d)
        Next

        If dimensionsOnChain.Count = 0 Then Continue For

        Dim request As New AutoChainRequestV01
        request.Chain = chain
        request.Name = "RUN " & chain.Index.ToString()

        For Each d As DimensionRecord In dimensionsOnChain
            AddAnchorToChainRequestV01( _
                request, _
                GetOrAddAnchorV01( _
                    allAnchors, view, d.X1, d.Y1, d.Z1))

            AddAnchorToChainRequestV01( _
                request, _
                GetOrAddAnchorV01( _
                    allAnchors, view, d.X2, d.Y2, d.Z2))

            If IsReferenceDimensionTypeV09(d.DimensionType) Then
                AddReferenceSegmentV09(request, d)
            End If
        Next

        SortChainAnchorsV01(request)
        If request.Anchors.Count < 2 Then Continue For

        Dim firstAnchor As AutoDimAnchorV01 = request.Anchors.Item(0)
        Dim lastAnchor As AutoDimAnchorV01 = _
            request.Anchors.Item(request.Anchors.Count - 1)

        request.DimensionType = _
            ChooseDimensionTypeV01( _
                firstAnchor.SheetPoint, _
                lastAnchor.SheetPoint)

        Dim rightX As Double = view.Left + view.Width
        Dim bottomY As Double = view.Top - view.Height

        If request.DimensionType = DimensionTypeEnum.kHorizontalDimensionType Then
            ' Primary chain close to the view; overall one clean tier below.
            request.PlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    (firstAnchor.SheetPoint.X + lastAnchor.SheetPoint.X) / 2.0, _
                    bottomY - 0.65)

            request.OverallPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    request.PlacementPoint.X, _
                    bottomY - 1.35)

        ElseIf request.DimensionType = DimensionTypeEnum.kVerticalDimensionType Then
            ' All partial vertical dimensions share one inner tier.
            request.PlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    rightX + 0.65, _
                    (firstAnchor.SheetPoint.Y + lastAnchor.SheetPoint.Y) / 2.0)

            request.OverallPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    rightX + 1.40, _
                    request.PlacementPoint.Y)

        Else
            alignedLevel += 1

            Dim midX As Double = _
                (firstAnchor.SheetPoint.X + lastAnchor.SheetPoint.X) / 2.0
            Dim midY As Double = _
                (firstAnchor.SheetPoint.Y + lastAnchor.SheetPoint.Y) / 2.0

            Dim dx As Double = lastAnchor.SheetPoint.X - firstAnchor.SheetPoint.X
            Dim dy As Double = lastAnchor.SheetPoint.Y - firstAnchor.SheetPoint.Y
            Dim length2d As Double = Math.Sqrt(dx * dx + dy * dy)
            If length2d < 0.001 Then Continue For

            Dim nx As Double = -dy / length2d
            Dim ny As Double = dx / length2d
            Dim offset As Double = 0.85 + (alignedLevel - 1) * 0.60

            request.PlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    midX + nx * offset, _
                    midY + ny * offset)

            request.OverallPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    midX + nx * (offset + 0.70), _
                    midY + ny * (offset + 0.70))
        End If

        result.Add(request)
    Next

    Return result
End Function''')


replace_function('CreateChainDimensionsV01', r'''Function CreateChainDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests
        If request Is Nothing OrElse request.Anchors.Count < 2 Then Continue For

        Dim i As Integer = 0
        While i < request.Anchors.Count - 1

            Dim a As AutoDimAnchorV01 = request.Anchors.Item(i)
            Dim b As AutoDimAnchorV01 = request.Anchors.Item(i + 1)

            ' Keep centerline intents OUT of native chain sets.  Build a real
            ' chain from each contiguous block of actual projected geometry.
            If a.Intent IsNot Nothing AndAlso b.Intent IsNot Nothing Then

                Dim startIndex As Integer = i
                Dim endIndex As Integer = i + 1

                While endIndex < request.Anchors.Count - 1 AndAlso _
                      request.Anchors.Item(endIndex + 1).Intent IsNot Nothing
                    endIndex += 1
                End While

                created += _
                    CreatePhysicalChainGroupV09( _
                        sheet, request, startIndex, endIndex)

                i = endIndex
            Else
                created += _
                    CreateIntervalDimensionV09( _
                        sheet, request, i, i + 1)
                i += 1
            End If
        End While
    Next

    Return created
End Function''')


replace_function('CreateOverallDimensionsV01', r'''Function CreateOverallDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests
        If request.Anchors.Count <= 2 Then Continue For

        ' Do not show fitting-centre vertical subtotals such as 193 / 320.
        ' V0.9 adds one clean flange-to-flange vertical envelope overall instead.
        If request.DimensionType = DimensionTypeEnum.kVerticalDimensionType AndAlso _
           RequestContainsFittingCenterV09(request) Then
            Continue For
        End If

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

            If intent1 Is Nothing OrElse intent2 Is Nothing Then Continue For

            Dim dimObj As LinearGeneralDimension = _
                sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                    request.OverallPlacementPoint, _
                    intent1, intent2, request.DimensionType)

            Try : dimObj.Precision = 0 : Catch : End Try
            TagAutoObjectV01(dimObj)
            created += 1

        Catch ex As Exception
            Logger.Error( _
                "Overall dimension failed for " & request.Name & _
                ": " & ex.Message)
        End Try
    Next

    Return created
End Function''')


# Add helper block before the existing attachment plan builder.
marker = 'Function BuildAttachmentPlanV01( _'
if marker not in text:
    raise RuntimeError('BuildAttachmentPlanV01 marker not found')

helpers = r'''

' ===================================================================
' V0.9 DIMENSION PRESENTATION RULES
' ===================================================================

Function IsReferenceDimensionTypeV09(dimensionType As String) As Boolean
    If String.IsNullOrWhiteSpace(dimensionType) Then Return False

    Dim t As String = dimensionType.Trim().ToUpperInvariant()
    Return _
        t.StartsWith("TEE_") OrElse _
        t.StartsWith("ELBOW_") OrElse _
        t.StartsWith("REDUCER_")
End Function


Sub AddReferenceSegmentV09( _
    request As AutoChainRequestV01, _
    d As DimensionRecord)

    If request Is Nothing OrElse d Is Nothing Then Exit Sub

    Dim r As New AutoReferenceSegmentV09
    r.X1 = d.X1 : r.Y1 = d.Y1 : r.Z1 = d.Z1
    r.X2 = d.X2 : r.Y2 = d.Y2 : r.Z2 = d.Z2
    r.DimensionType = d.DimensionType
    request.ReferenceSegments.Add(r)
End Sub


Function IsReferencePairV09( _
    request As AutoChainRequestV01, _
    a As AutoDimAnchorV01, _
    b As AutoDimAnchorV01) As Boolean

    If request Is Nothing OrElse a Is Nothing OrElse b Is Nothing Then Return False

    For Each r As AutoReferenceSegmentV09 In request.ReferenceSegments
        Dim directMatch As Boolean = _
            Dist3D(a.X, a.Y, a.Z, r.X1, r.Y1, r.Z1) < 0.2 AndAlso _
            Dist3D(b.X, b.Y, b.Z, r.X2, r.Y2, r.Z2) < 0.2

        Dim reverseMatch As Boolean = _
            Dist3D(a.X, a.Y, a.Z, r.X2, r.Y2, r.Z2) < 0.2 AndAlso _
            Dist3D(b.X, b.Y, b.Z, r.X1, r.Y1, r.Z1) < 0.2

        If directMatch OrElse reverseMatch Then Return True
    Next

    Return False
End Function


Sub ApplyReferenceDisplayV09(dimObj As LinearGeneralDimension)
    If dimObj Is Nothing Then Exit Sub

    Try
        Dim ft As String = dimObj.Text.FormattedText
        If String.IsNullOrEmpty(ft) Then Exit Sub

        If Not ft.TrimStart().StartsWith("(") Then
            dimObj.Text.FormattedText = "(" & ft & ")"
        End If

        Try
            If Not dimObj.AttributeSets.NameIsUsed("AutoReferenceDimension") Then
                dimObj.AttributeSets.Add("AutoReferenceDimension")
            End If
        Catch
        End Try
    Catch ex As Exception
        Logger.Error("Reference display formatting failed: " & ex.Message)
    End Try
End Sub


Function CreatePhysicalChainGroupV09( _
    sheet As Sheet, _
    request As AutoChainRequestV01, _
    startIndex As Integer, _
    endIndex As Integer) As Integer

    If endIndex <= startIndex Then Return 0

    Try
        Dim intents As ObjectCollection = _
            ThisApplication.TransientObjects.CreateObjectCollection()

        For i As Integer = startIndex To endIndex
            Dim anchor As AutoDimAnchorV01 = request.Anchors.Item(i)
            If anchor.Intent Is Nothing Then Return 0
            intents.Add(anchor.Intent)
        Next

        Dim dimSet As ChainDimensionSet = _
            sheet.DrawingDimensions.ChainDimensionSets.Add( _
                intents, request.PlacementPoint, request.DimensionType)

        Try : dimSet.Precision = 0 : Catch : End Try
        TagAutoObjectV01(dimSet)

        Dim expected As Integer = endIndex - startIndex
        Dim memberCount As Integer = dimSet.Members.Count
        Dim limit As Integer = Math.Min(expected, memberCount)

        For m As Integer = 1 To limit
            Dim a As AutoDimAnchorV01 = request.Anchors.Item(startIndex + m - 1)
            Dim b As AutoDimAnchorV01 = request.Anchors.Item(startIndex + m)

            If IsReferencePairV09(request, a, b) Then
                ApplyReferenceDisplayV09(dimSet.Members.Item(m))
            End If
        Next

        Logger.Info( _
            "CHAIN_NATIVE " & request.Name & _
            " | anchors=" & (endIndex - startIndex + 1).ToString())

        Return 1

    Catch ex As Exception
        Logger.Error( _
            "Physical chain group failed for " & request.Name & _
            ": " & ex.Message & " | individual fallback")

        Dim fallback As Integer = 0
        For i As Integer = startIndex To endIndex - 1
            fallback += CreateIntervalDimensionV09(sheet, request, i, i + 1)
        Next
        Return fallback
    End Try
End Function


Function CreateIntervalDimensionV09( _
    sheet As Sheet, _
    request As AutoChainRequestV01, _
    firstIndex As Integer, _
    secondIndex As Integer) As Integer

    Try
        Dim a As AutoDimAnchorV01 = request.Anchors.Item(firstIndex)
        Dim b As AutoDimAnchorV01 = request.Anchors.Item(secondIndex)

        Dim intent1 As GeometryIntent = _
            ResolveAnchorIntentForDimensionV07( _
                sheet, a, request.DimensionType)

        Dim intent2 As GeometryIntent = _
            ResolveAnchorIntentForDimensionV07( _
                sheet, b, request.DimensionType)

        If intent1 Is Nothing OrElse intent2 Is Nothing Then Return 0

        Dim textPoint As Point2d = request.PlacementPoint.Copy()

        If request.DimensionType = DimensionTypeEnum.kHorizontalDimensionType Then
            textPoint.X = (a.SheetPoint.X + b.SheetPoint.X) / 2.0
        ElseIf request.DimensionType = DimensionTypeEnum.kVerticalDimensionType Then
            textPoint.Y = (a.SheetPoint.Y + b.SheetPoint.Y) / 2.0
        Else
            textPoint.X = (a.SheetPoint.X + b.SheetPoint.X) / 2.0
            textPoint.Y = (a.SheetPoint.Y + b.SheetPoint.Y) / 2.0
        End If

        Dim dimObj As LinearGeneralDimension = _
            sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                textPoint, intent1, intent2, request.DimensionType)

        Try : dimObj.Precision = 0 : Catch : End Try
        TagAutoObjectV01(dimObj)

        If IsReferencePairV09(request, a, b) Then
            ApplyReferenceDisplayV09(dimObj)
        End If

        Return 1

    Catch ex As Exception
        Logger.Error( _
            "Interval dimension failed for " & request.Name & _
            ": " & ex.Message)
        Return 0
    End Try
End Function


Function RequestContainsFittingCenterV09( _
    request As AutoChainRequestV01) As Boolean

    If request Is Nothing Then Return False
    For Each a As AutoDimAnchorV01 In request.Anchors
        If a.IsFittingCenter Then Return True
    Next
    Return False
End Function


Function CreateGlobalVerticalFlangeOverallV09( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord)) As Integer

    If sheet Is Nothing OrElse view Is Nothing OrElse nodes Is Nothing Then Return 0

    Dim topNode As NodeRecord = Nothing
    Dim bottomNode As NodeRecord = Nothing
    Dim topPoint As Point2d = Nothing
    Dim bottomPoint As Point2d = Nothing

    For Each n As NodeRecord In nodes
        If n Is Nothing OrElse n.ComponentType <> "FLANGE" OrElse _
           Not n.HasOuterAnchor OrElse n.Occurrence Is Nothing Then
            Continue For
        End If

        Try
            Dim modelPoint As Inventor.Point = _
                ThisApplication.TransientGeometry.CreatePoint( _
                    n.OuterX / 10.0, n.OuterY / 10.0, n.OuterZ / 10.0)

            Dim p As Point2d = view.ModelToSheetSpace(modelPoint)
            If p Is Nothing Then Continue For

            If topPoint Is Nothing OrElse p.Y > topPoint.Y Then
                topPoint = p : topNode = n
            End If

            If bottomPoint Is Nothing OrElse p.Y < bottomPoint.Y Then
                bottomPoint = p : bottomNode = n
            End If
        Catch
        End Try
    Next

    If topNode Is Nothing OrElse bottomNode Is Nothing OrElse _
       topNode Is bottomNode OrElse topPoint Is Nothing OrElse bottomPoint Is Nothing Then
        Return 0
    End If

    If Math.Abs(topPoint.Y - bottomPoint.Y) < 0.50 Then Return 0

    Dim intentTop As GeometryIntent = _
        FindOccurrenceDrawingIntentV031( _
            sheet, view, topNode.Occurrence, topPoint)

    Dim intentBottom As GeometryIntent = _
        FindOccurrenceDrawingIntentV031( _
            sheet, view, bottomNode.Occurrence, bottomPoint)

    If intentTop Is Nothing OrElse intentBottom Is Nothing Then Return 0

    Try
        Dim rightX As Double = view.Left + view.Width
        Dim placement As Point2d = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                rightX + 1.45, _
                (topPoint.Y + bottomPoint.Y) / 2.0)

        Dim dimObj As LinearGeneralDimension = _
            sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                placement, _
                intentTop, _
                intentBottom, _
                DimensionTypeEnum.kVerticalDimensionType)

        Try : dimObj.Precision = 0 : Catch : End Try
        TagAutoObjectV01(dimObj)

        Logger.Info( _
            "OVERALL_VERTICAL_FLANGE " & _
            topNode.Code & " -> " & bottomNode.Code)

        Return 1
    Catch ex As Exception
        Logger.Error("Global vertical flange overall failed: " & ex.Message)
        Return 0
    End Try
End Function


'''

if 'Function IsReferenceDimensionTypeV09' not in text:
    text = text.replace(marker, helpers + marker, 1)

# Extend chain request data model with reference segment metadata.
rx = re.compile(r'Class\s+AutoChainRequestV01\b.*?\nEnd Class', re.S | re.I)
m = rx.search(text)
if not m:
    raise RuntimeError('AutoChainRequestV01 class not found')
block = m.group(0)
if 'ReferenceSegments' not in block:
    block = block.replace(
        '    Public Anchors As New List(Of AutoDimAnchorV01)\n',
        '    Public Anchors As New List(Of AutoDimAnchorV01)\n    Public ReferenceSegments As New List(Of AutoReferenceSegmentV09)\n')
    text = text[:m.start()] + block + text[m.end():]

# Add reference-segment class immediately before AutoChainRequestV01.
if 'Class AutoReferenceSegmentV09' not in text:
    class_marker = 'Class AutoChainRequestV01'
    ref_class = r'''Class AutoReferenceSegmentV09
    Public X1 As Double
    Public Y1 As Double
    Public Z1 As Double
    Public X2 As Double
    Public Y2 As Double
    Public Z2 As Double
    Public DimensionType As String = ""
End Class


'''
    if class_marker not in text:
        raise RuntimeError('AutoChainRequestV01 class marker not found')
    text = text.replace(class_marker, ref_class + class_marker, 1)

# Static safety checks for the intended architecture.
assert 'Function IsReferenceDimensionTypeV09' in text
assert 't.StartsWith("TEE_")' in text
assert 't.StartsWith("ELBOW_")' in text
assert 't.StartsWith("REDUCER_")' in text
assert 'CHAIN_NATIVE' in text
assert 'CreateGlobalVerticalFlangeOverallV09' in text
assert 'RequestContainsFittingCenterV09' in text

path.write_text(text, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator to V0.9 layout/reference rules.')
