from pathlib import Path
import re

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

if 'DimensionGenerator V0.10' not in text:
    raise RuntimeError('Expected DimensionGenerator V0.10 as patch base')

text = text.replace('DimensionGenerator V0.10', 'DimensionGenerator V0.11')
text = text.replace(
    'V0.10: true Inventor reference dimensions + explicit drawing-view selection + increased annotation spacing; attachments deferred.',
    'V0.11: true reference-member mapping + one global native vertical chain + improved vertical spacing; attachments deferred.')

# ---------------------------------------------------------------------------
# Reference segments also remember projected coordinates.  This lets a global
# vertical chain use either TEE or ELBOW center at the same Y datum without
# depending on identical 3D points.
# ---------------------------------------------------------------------------
text = text.replace(
    'AddReferenceSegmentV09(request, d)',
    'AddReferenceSegmentV09(request, d, view)')

# Build one global vertical chain after ordinary requests are identified.
needle = '''        result.Add(request)\n    Next\n\n    Return result\nEnd Function\n\n\nSub AddAnchorToChainRequestV01'''
replacement = '''        result.Add(request)\n    Next\n\n    MergeGlobalVerticalChainV011( _\n        view, _\n        componentDimensions, _\n        allAnchors, _\n        result)\n\n    Return result\nEnd Function\n\n\nSub AddAnchorToChainRequestV01'''
if 'MergeGlobalVerticalChainV011' not in text:
    if needle not in text:
        raise RuntimeError('BuildChainRequests return point not found')
    text = text.replace(needle, replacement, 1)

# More room on the right for the true global vertical chain.
text = text.replace('rightX + 1.00, _\n                    (firstAnchor.SheetPoint.Y + lastAnchor.SheetPoint.Y) / 2.0)',
                    'rightX + 1.35, _\n                    (firstAnchor.SheetPoint.Y + lastAnchor.SheetPoint.Y) / 2.0)')
text = text.replace('rightX + 1.85, _\n                    request.PlacementPoint.Y)',
                    'rightX + 2.55, _\n                    request.PlacementPoint.Y)')
text = text.replace('rightX + 1.45, _\n                (topPoint.Y + bottomPoint.Y) / 2.0)',
                    'rightX + 2.55, _\n                (topPoint.Y + bottomPoint.Y) / 2.0)')


def replace_function(name, replacement):
    global text
    rx = re.compile(r'Function\s+' + re.escape(name) + r'\s*\(.*?\nEnd Function', re.S | re.I)
    m = rx.search(text)
    if not m:
        raise RuntimeError('Function not found: ' + name)
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


def replace_sub(name, replacement):
    global text
    rx = re.compile(r'Sub\s+' + re.escape(name) + r'\s*\(.*?\nEnd Sub', re.S | re.I)
    m = rx.search(text)
    if not m:
        raise RuntimeError('Sub not found: ' + name)
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


replace_sub('AddReferenceSegmentV09', r'''Sub AddReferenceSegmentV09( _
    request As AutoChainRequestV01, _
    d As DimensionRecord, _
    view As DrawingView)

    If request Is Nothing OrElse d Is Nothing Then Exit Sub

    Dim r As New AutoReferenceSegmentV09
    r.X1 = d.X1 : r.Y1 = d.Y1 : r.Z1 = d.Z1
    r.X2 = d.X2 : r.Y2 = d.Y2 : r.Z2 = d.Z2
    r.DimensionType = d.DimensionType

    If view IsNot Nothing Then
        Try
            Dim p1 As Inventor.Point = _
                ThisApplication.TransientGeometry.CreatePoint( _
                    d.X1 / 10.0, d.Y1 / 10.0, d.Z1 / 10.0)
            Dim p2 As Inventor.Point = _
                ThisApplication.TransientGeometry.CreatePoint( _
                    d.X2 / 10.0, d.Y2 / 10.0, d.Z2 / 10.0)

            Dim s1 As Point2d = view.ModelToSheetSpace(p1)
            Dim s2 As Point2d = view.ModelToSheetSpace(p2)

            r.SheetX1 = s1.X : r.SheetY1 = s1.Y
            r.SheetX2 = s2.X : r.SheetY2 = s2.Y
            r.HasSheetPoints = True
        Catch
        End Try
    End If

    request.ReferenceSegments.Add(r)
End Sub''')


replace_function('IsReferencePairV09', r'''Function IsReferencePairV09( _
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

        ' Global vertical chain can merge fitting centers that have different
        ' model X coordinates but the same projected Y datum.
        If r.HasSheetPoints AndAlso a.SheetPoint IsNot Nothing AndAlso _
           b.SheetPoint IsNot Nothing Then

            If request.DimensionType = DimensionTypeEnum.kVerticalDimensionType Then
                Dim ad As Boolean = _
                    Math.Abs(a.SheetPoint.Y - r.SheetY1) < 0.02 AndAlso _
                    Math.Abs(b.SheetPoint.Y - r.SheetY2) < 0.02
                Dim ar As Boolean = _
                    Math.Abs(a.SheetPoint.Y - r.SheetY2) < 0.02 AndAlso _
                    Math.Abs(b.SheetPoint.Y - r.SheetY1) < 0.02
                If ad OrElse ar Then Return True
            ElseIf request.DimensionType = DimensionTypeEnum.kHorizontalDimensionType Then
                Dim ad As Boolean = _
                    Math.Abs(a.SheetPoint.X - r.SheetX1) < 0.02 AndAlso _
                    Math.Abs(b.SheetPoint.X - r.SheetX2) < 0.02
                Dim ar As Boolean = _
                    Math.Abs(a.SheetPoint.X - r.SheetX2) < 0.02 AndAlso _
                    Math.Abs(b.SheetPoint.X - r.SheetX1) < 0.02
                If ad OrElse ar Then Return True
            End If
        End If
    Next

    Return False
End Function''')


replace_function('CreateChainDimensionsV01', r'''Function CreateChainDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests
        If request Is Nothing OrElse request.Anchors.Count < 2 Then Continue For

        If request.Name = "GLOBAL VERTICAL V011" Then
            created += CreateFullDirectionalChainV011(sheet, request)
            Continue For
        End If

        Dim i As Integer = 0
        While i < request.Anchors.Count - 1

            Dim a As AutoDimAnchorV01 = request.Anchors.Item(i)
            Dim b As AutoDimAnchorV01 = request.Anchors.Item(i + 1)

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


replace_function('CreatePhysicalChainGroupV09', r'''Function CreatePhysicalChainGroupV09( _
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

        ' Inventor does not guarantee Members are returned in the same order as
        ' the input intents.  Match each reference interval by its actual member
        ' geometry instead of using member index.  This fixes the left flange
        ' 15 being marked reference while TEE 356 stayed normal.
        ApplyReferenceMembersByGeometryV011( _
            dimSet, request, startIndex, endIndex)

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
End Function''')


# ---------------------------------------------------------------------------
# Add the V0.11 global vertical-chain + member-matching helpers before the
# V0.9 presentation section.
# ---------------------------------------------------------------------------
marker = "' ===================================================================\n' V0.9 DIMENSION PRESENTATION RULES"
if marker not in text:
    raise RuntimeError('V0.9 presentation marker not found')

helpers = r'''
' ===================================================================
' V0.11 GLOBAL VERTICAL CHAIN + REFERENCE MEMBER MATCHING
' ===================================================================

Sub MergeGlobalVerticalChainV011( _
    view As DrawingView, _
    componentDimensions As List(Of DimensionRecord), _
    allAnchors As List(Of AutoDimAnchorV01), _
    requests As List(Of AutoChainRequestV01))

    If view Is Nothing OrElse componentDimensions Is Nothing OrElse _
       allAnchors Is Nothing OrElse requests Is Nothing Then Exit Sub

    Dim globalRequest As New AutoChainRequestV01
    globalRequest.Name = "GLOBAL VERTICAL V011"
    globalRequest.DimensionType = DimensionTypeEnum.kVerticalDimensionType

    For Each d As DimensionRecord In componentDimensions
        Try
            Dim p1 As Inventor.Point = _
                ThisApplication.TransientGeometry.CreatePoint( _
                    d.X1 / 10.0, d.Y1 / 10.0, d.Z1 / 10.0)
            Dim p2 As Inventor.Point = _
                ThisApplication.TransientGeometry.CreatePoint( _
                    d.X2 / 10.0, d.Y2 / 10.0, d.Z2 / 10.0)

            Dim s1 As Point2d = view.ModelToSheetSpace(p1)
            Dim s2 As Point2d = view.ModelToSheetSpace(p2)

            If ChooseDimensionTypeV01(s1, s2) <> _
               DimensionTypeEnum.kVerticalDimensionType Then
                Continue For
            End If

            Dim a As AutoDimAnchorV01 = _
                GetOrAddAnchorV01( _
                    allAnchors, view, d.X1, d.Y1, d.Z1)
            Dim b As AutoDimAnchorV01 = _
                GetOrAddAnchorV01( _
                    allAnchors, view, d.X2, d.Y2, d.Z2)

            AddVerticalDatumAnchorV011(globalRequest, a)
            AddVerticalDatumAnchorV011(globalRequest, b)

            If IsReferenceDimensionTypeV09(d.DimensionType) Then
                AddReferenceSegmentV09(globalRequest, d, view)
            End If
        Catch
        End Try
    Next

    If globalRequest.Anchors.Count < 3 Then Exit Sub

    SortVerticalAnchorsV011(globalRequest.Anchors)

    Dim rightX As Double = view.Left + view.Width
    Dim minY As Double = globalRequest.Anchors.Item(0).SheetPoint.Y
    Dim maxY As Double = globalRequest.Anchors.Item(globalRequest.Anchors.Count - 1).SheetPoint.Y

    globalRequest.PlacementPoint = _
        ThisApplication.TransientGeometry.CreatePoint2d( _
            rightX + 1.35, (minY + maxY) / 2.0)

    globalRequest.OverallPlacementPoint = _
        ThisApplication.TransientGeometry.CreatePoint2d( _
            rightX + 2.55, (minY + maxY) / 2.0)

    ' Remove per-route vertical requests.  Their datums are now represented by
    ' one native right-side chain: top 15 / TEE / ELBOW / bottom 15.
    For i As Integer = requests.Count - 1 To 0 Step -1
        If requests.Item(i).DimensionType = _
           DimensionTypeEnum.kVerticalDimensionType Then
            requests.RemoveAt(i)
        End If
    Next

    requests.Add(globalRequest)

    Logger.Info( _
        "GLOBAL_VERTICAL_CHAIN planned | datums=" & _
        globalRequest.Anchors.Count.ToString())
End Sub


Sub AddVerticalDatumAnchorV011( _
    request As AutoChainRequestV01, _
    anchor As AutoDimAnchorV01)

    If request Is Nothing OrElse anchor Is Nothing OrElse _
       anchor.SheetPoint Is Nothing Then Exit Sub

    ' Vertical chain needs unique Y datums only.  TEE and ELBOW theoretical
    ' centers can be at different X but share the same main-run Y coordinate.
    For Each existing As AutoDimAnchorV01 In request.Anchors
        If existing.SheetPoint IsNot Nothing AndAlso _
           Math.Abs(existing.SheetPoint.Y - anchor.SheetPoint.Y) < 0.015 Then
            Exit Sub
        End If
    Next

    request.Anchors.Add(anchor)
End Sub


Sub SortVerticalAnchorsV011(anchors As List(Of AutoDimAnchorV01))
    For i As Integer = 0 To anchors.Count - 2
        For j As Integer = i + 1 To anchors.Count - 1
            If anchors.Item(j).SheetPoint.Y < anchors.Item(i).SheetPoint.Y Then
                Dim tmp As AutoDimAnchorV01 = anchors.Item(i)
                anchors.Item(i) = anchors.Item(j)
                anchors.Item(j) = tmp
            End If
        Next
    Next
End Sub


Function CreateFullDirectionalChainV011( _
    sheet As Sheet, _
    request As AutoChainRequestV01) As Integer

    If sheet Is Nothing OrElse request Is Nothing OrElse _
       request.Anchors.Count < 2 Then Return 0

    Try
        Dim intents As ObjectCollection = _
            ThisApplication.TransientObjects.CreateObjectCollection()

        For Each anchor As AutoDimAnchorV01 In request.Anchors
            Dim intent As GeometryIntent = _
                ResolveAnchorIntentForDimensionV07( _
                    sheet, anchor, request.DimensionType)

            If intent Is Nothing Then
                Throw New Exception( _
                    "Missing vertical datum intent at sheet Y=" & _
                    Num(anchor.SheetPoint.Y))
            End If

            intents.Add(intent)
        Next

        Logger.Info( _
            "GLOBAL_VERTICAL_CHAIN immediately before ChainDimensionSets.Add" & _
            " | intents=" & intents.Count.ToString())

        Dim dimSet As ChainDimensionSet = _
            sheet.DrawingDimensions.ChainDimensionSets.Add( _
                intents, request.PlacementPoint, request.DimensionType)

        Try : dimSet.Precision = 0 : Catch : End Try
        TagAutoObjectV01(dimSet)

        ApplyReferenceMembersByGeometryV011( _
            dimSet, request, 0, request.Anchors.Count - 1)

        Logger.Info( _
            "GLOBAL_VERTICAL_CHAIN created | members=" & _
            dimSet.Members.Count.ToString())

        Return 1

    Catch ex As Exception
        Logger.Error( _
            "GLOBAL_VERTICAL_CHAIN failed: " & ex.Message & _
            " | individual fallback")

        Dim fallback As Integer = 0
        For i As Integer = 0 To request.Anchors.Count - 2
            fallback += CreateIntervalDimensionV09(sheet, request, i, i + 1)
        Next
        Return fallback
    End Try
End Function


Sub ApplyReferenceMembersByGeometryV011( _
    dimSet As ChainDimensionSet, _
    request As AutoChainRequestV01, _
    startIndex As Integer, _
    endIndex As Integer)

    If dimSet Is Nothing OrElse request Is Nothing Then Exit Sub

    For i As Integer = startIndex To endIndex - 1
        Dim a As AutoDimAnchorV01 = request.Anchors.Item(i)
        Dim b As AutoDimAnchorV01 = request.Anchors.Item(i + 1)

        If Not IsReferencePairV09(request, a, b) Then Continue For

        Dim expectedA As GeometryIntent = _
            ResolveAnchorIntentForDimensionV07( _
                dimSet.Parent.Parent, a, request.DimensionType)
        Dim expectedB As GeometryIntent = _
            ResolveAnchorIntentForDimensionV07( _
                dimSet.Parent.Parent, b, request.DimensionType)

        ' Parent traversal above is not guaranteed in every Inventor release.
        ' If it cannot be used, compare members to the already-resolved anchor
        ' intents directly below.
        If expectedA Is Nothing Then expectedA = GetResolvedAnchorIntentV011(a, request.DimensionType)
        If expectedB Is Nothing Then expectedB = GetResolvedAnchorIntentV011(b, request.DimensionType)

        For m As Integer = 1 To dimSet.Members.Count
            Dim member As LinearGeneralDimension = _
                TryCast(dimSet.Members.Item(m), LinearGeneralDimension)
            If member Is Nothing Then Continue For

            If LinearDimensionMatchesIntentsV011( _
                member, expectedA, expectedB) Then

                ApplyReferenceDisplayV09(member)
                Logger.Info( _
                    "REFERENCE_MEMBER matched geometry | interval=" & _
                    (i + 1).ToString())
                Exit For
            End If
        Next
    Next
End Sub


Function GetResolvedAnchorIntentV011( _
    anchor As AutoDimAnchorV01, _
    dimensionType As DimensionTypeEnum) As GeometryIntent

    If anchor Is Nothing Then Return Nothing
    If anchor.Intent IsNot Nothing Then Return anchor.Intent

    If dimensionType = DimensionTypeEnum.kHorizontalDimensionType Then
        Return anchor.HorizontalDimensionIntent
    End If

    If dimensionType = DimensionTypeEnum.kVerticalDimensionType Then
        Return anchor.VerticalDimensionIntent
    End If

    Return Nothing
End Function


Function LinearDimensionMatchesIntentsV011( _
    member As LinearGeneralDimension, _
    expectedA As GeometryIntent, _
    expectedB As GeometryIntent) As Boolean

    If member Is Nothing OrElse expectedA Is Nothing OrElse expectedB Is Nothing Then
        Return False
    End If

    Try
        Dim m1 As GeometryIntent = member.IntentOne
        Dim m2 As GeometryIntent = member.IntentTwo
        If m1 Is Nothing OrElse m2 Is Nothing Then Return False

        Return _
            (GeometryIntentEquivalentV011(m1, expectedA) AndAlso _
             GeometryIntentEquivalentV011(m2, expectedB)) OrElse _
            (GeometryIntentEquivalentV011(m1, expectedB) AndAlso _
             GeometryIntentEquivalentV011(m2, expectedA))
    Catch
        Return False
    End Try
End Function


Function GeometryIntentEquivalentV011( _
    a As GeometryIntent, _
    b As GeometryIntent) As Boolean

    If a Is Nothing OrElse b Is Nothing Then Return False

    Try
        If a Is b Then Return True
    Catch
    End Try

    Try
        Dim pa As Point2d = a.PointOnSheet
        Dim pb As Point2d = b.PointOnSheet
        If pa IsNot Nothing AndAlso pb IsNot Nothing Then
            If SheetPointDistanceV03(pa, pb) < 0.01 Then Return True
        End If
    Catch
    End Try

    Try
        Dim ga As Object = a.Geometry
        Dim gb As Object = b.Geometry
        If ga Is Nothing OrElse gb Is Nothing Then Return False
        If ga Is gb Then Return True

        If TypeOf ga Is DrawingCurve AndAlso TypeOf gb Is DrawingCurve Then
            Return DrawingCurvesEquivalentV011( _
                CType(ga, DrawingCurve), CType(gb, DrawingCurve))
        End If

        If TypeOf ga Is Centerline AndAlso TypeOf gb Is Centerline Then
            Return CenterlinesEquivalentV011( _
                CType(ga, Centerline), CType(gb, Centerline))
        End If
    Catch
    End Try

    Return False
End Function


Function DrawingCurvesEquivalentV011( _
    a As DrawingCurve, _
    b As DrawingCurve) As Boolean

    If a Is Nothing OrElse b Is Nothing Then Return False

    Try
        If a.StartPoint IsNot Nothing AndAlso a.EndPoint IsNot Nothing AndAlso _
           b.StartPoint IsNot Nothing AndAlso b.EndPoint IsNot Nothing Then

            Dim direct As Boolean = _
                SheetPointDistanceV03(a.StartPoint, b.StartPoint) < 0.01 AndAlso _
                SheetPointDistanceV03(a.EndPoint, b.EndPoint) < 0.01
            Dim reverse As Boolean = _
                SheetPointDistanceV03(a.StartPoint, b.EndPoint) < 0.01 AndAlso _
                SheetPointDistanceV03(a.EndPoint, b.StartPoint) < 0.01

            If direct OrElse reverse Then Return True
        End If

        If a.CenterPoint IsNot Nothing AndAlso b.CenterPoint IsNot Nothing Then
            Return SheetPointDistanceV03(a.CenterPoint, b.CenterPoint) < 0.01
        End If
    Catch
    End Try

    Return False
End Function


Function CenterlinesEquivalentV011( _
    a As Centerline, _
    b As Centerline) As Boolean

    If a Is Nothing OrElse b Is Nothing Then Return False

    Try
        Dim direct As Boolean = _
            SheetPointDistanceV03(a.StartPoint, b.StartPoint) < 0.01 AndAlso _
            SheetPointDistanceV03(a.EndPoint, b.EndPoint) < 0.01
        Dim reverse As Boolean = _
            SheetPointDistanceV03(a.StartPoint, b.EndPoint) < 0.01 AndAlso _
            SheetPointDistanceV03(a.EndPoint, b.StartPoint) < 0.01
        Return direct OrElse reverse
    Catch
        Return False
    End Try
End Function


'''
text = text.replace(marker, helpers + marker, 1)

# The helper above should not try to infer a Sheet from ChainDimensionSet parent
# traversal.  Use already-resolved anchor intents only; ResolveProjectedAnchors
# and the full directional chain resolve them before reference matching.
text = re.sub(
    r'''        Dim expectedA As GeometryIntent = _\n            ResolveAnchorIntentForDimensionV07\( _\n                dimSet\.Parent\.Parent, a, request\.DimensionType\)\n        Dim expectedB As GeometryIntent = _\n            ResolveAnchorIntentForDimensionV07\( _\n                dimSet\.Parent\.Parent, b, request\.DimensionType\)\n\n        ' Parent traversal above is not guaranteed in every Inventor release\.\n        ' If it cannot be used, compare members to the already-resolved anchor\n        ' intents directly below\.\n        If expectedA Is Nothing Then expectedA = GetResolvedAnchorIntentV011\(a, request\.DimensionType\)\n        If expectedB Is Nothing Then expectedB = GetResolvedAnchorIntentV011\(b, request\.DimensionType\)''',
    '''        Dim expectedA As GeometryIntent = _\n            GetResolvedAnchorIntentV011(a, request.DimensionType)\n        Dim expectedB As GeometryIntent = _\n            GetResolvedAnchorIntentV011(b, request.DimensionType)''',
    text)

# Data class additions.
old_class = '''Class AutoReferenceSegmentV09\n    Public X1 As Double\n    Public Y1 As Double\n    Public Z1 As Double\n    Public X2 As Double\n    Public Y2 As Double\n    Public Z2 As Double\n    Public DimensionType As String = ""\nEnd Class'''
new_class = '''Class AutoReferenceSegmentV09\n    Public X1 As Double\n    Public Y1 As Double\n    Public Z1 As Double\n    Public X2 As Double\n    Public Y2 As Double\n    Public Z2 As Double\n    Public SheetX1 As Double\n    Public SheetY1 As Double\n    Public SheetX2 As Double\n    Public SheetY2 As Double\n    Public HasSheetPoints As Boolean = False\n    Public DimensionType As String = ""\nEnd Class'''
if old_class not in text:
    raise RuntimeError('AutoReferenceSegmentV09 class not found')
text = text.replace(old_class, new_class, 1)

path.write_text(text, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator to V0.11')
