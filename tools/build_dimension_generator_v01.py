#!/usr/bin/env python3
from pathlib import Path

SRC = Path('TopologyExtractor.vb')
DST = Path('DimensionGenerator.vb')

src = SRC.read_text(encoding='utf-8')

main_start = src.index('Sub Main()')
scan_marker = "' ===================================================================\n' SCAN ASSEMBLY"
scan_start = src.index(scan_marker)

new_main = r'''Sub Main()

    Try

        If ThisApplication.ActiveDocument.DocumentType <> _
           DocumentTypeEnum.kDrawingDocumentObject Then

            MessageBox.Show( _
                "Run DimensionGenerator from an Inventor drawing.", _
                "Auto Dimensions")

            Exit Sub

        End If


        Dim drawDoc As DrawingDocument = _
            CType( _
                ThisApplication.ActiveDocument, _
                DrawingDocument)

        Dim sheet As Sheet = drawDoc.ActiveSheet


        If sheet.DrawingViews.Count = 0 Then

            MessageBox.Show( _
                "The active sheet has no drawing views.", _
                "Auto Dimensions")

            Exit Sub

        End If


        Dim view As DrawingView = _
            GetTargetDrawingViewV01( _
                drawDoc, _
                sheet)


        If view Is Nothing Then

            MessageBox.Show( _
                "Could not determine the drawing view to dimension.", _
                "Auto Dimensions")

            Exit Sub

        End If


        Dim descriptor As DocumentDescriptor = _
            view.ReferencedDocumentDescriptor


        If descriptor Is Nothing OrElse _
           descriptor.ReferenceMissing Then

            MessageBox.Show( _
                "The selected drawing view has no resolved model reference.", _
                "Auto Dimensions")

            Exit Sub

        End If


        Dim modelObject As Object = _
            descriptor.ReferencedDocument

        Dim asmDoc As AssemblyDocument = _
            TryCast( _
                modelObject, _
                AssemblyDocument)


        If asmDoc Is Nothing Then

            MessageBox.Show( _
                "DimensionGenerator V0.1 currently expects an assembly drawing view.", _
                "Auto Dimensions")

            Exit Sub

        End If


        ' =============================================================
        ' REUSE THE PROVEN GEOMETRY / TOPOLOGY ENGINE IN MEMORY ONLY.
        ' NO CSV, SVG OR OTHER OUTPUT FILES ARE CREATED BY THIS RULE.
        ' =============================================================

        Dim nodes As List(Of NodeRecord) = _
            ScanAssembly(asmDoc)

        AssignDisplayCodes(nodes)

        Dim edges As List(Of EdgeRecord) = _
            DetectConnections(nodes)

        ComputeReferencePoints( _
            nodes, _
            edges)

        Dim primitives As List(Of PrimitiveSegment) = _
            BuildManufacturingPrimitives( _
                nodes, _
                edges)

        Dim componentDimensions As List(Of DimensionRecord) = _
            BuildComponentDimensions( _
                nodes, _
                edges)

        Dim chains As List(Of StraightChain) = _
            BuildStraightChains(primitives)

        AssignDimensionsToChains( _
            componentDimensions, _
            chains)

        Dim attachments As List(Of AttachmentRecordV09) = _
            DetectAttachmentsV09( _
                nodes, _
                edges, _
                chains)


        ' =============================================================
        ' BUILD DRAWING-DIMENSION PLAN.
        ' =============================================================

        DeletePreviousAutoDimensionsV01(sheet)

        Dim allAnchors As New List(Of AutoDimAnchorV01)

        Dim chainRequests As List(Of AutoChainRequestV01) = _
            BuildChainRequestsV01( _
                view, _
                componentDimensions, _
                chains, _
                allAnchors)

        Dim attachmentPlan As AutoAttachmentPlanV01 = _
            BuildAttachmentPlanV01( _
                view, _
                attachments, _
                allAnchors)


        If allAnchors.Count = 0 Then

            MessageBox.Show( _
                "No dimensionable semantic anchors were found in this view.", _
                "Auto Dimensions")

            Exit Sub

        End If


        Dim anchorSketch As DrawingSketch = _
            CreateAnchorSketchV01( _
                sheet, _
                allAnchors)


        Dim chainCount As Integer = _
            CreateChainDimensionsV01( _
                sheet, _
                chainRequests)

        Dim overallCount As Integer = _
            CreateOverallDimensionsV01( _
                sheet, _
                chainRequests)

        Dim attachmentCount As Integer = _
            CreateAttachmentDimensionsV01( _
                sheet, _
                attachmentPlan)


        Try
            anchorSketch.Visible = False
        Catch
        End Try


        drawDoc.Update2(True)


        MessageBox.Show( _
            "Auto dimensions created." & vbCrLf & vbCrLf & _
            "View: " & view.Name & vbCrLf & _
            "Chain sets: " & chainCount.ToString() & vbCrLf & _
            "Overall dimensions: " & overallCount.ToString() & vbCrLf & _
            "Attachment dimensions/sets: " & attachmentCount.ToString(), _
            "DimensionGenerator V0.1")


    Catch ex As Exception

        MessageBox.Show( _
            "DimensionGenerator V0.1 failed:" & vbCrLf & vbCrLf & _
            ex.Message, _
            "Auto Dimensions")

        Logger.Error(ex.ToString())

    End Try

End Sub
'''

src = src[:main_start] + new_main + '\n\n' + src[scan_start:]

# Keep the actual occurrence reference so later revisions can resolve real drawing curves/faces.
src = src.replace(
    '            node.OccurrenceName = occ.Name\n',
    '            node.OccurrenceName = occ.Name\n            node.Occurrence = occ\n',
    1,
)

src = src.replace(
    'Class NodeRecord\n\n    Public OccurrenceName As String = ""\n',
    'Class NodeRecord\n\n    Public OccurrenceName As String = ""\n    Public Occurrence As ComponentOccurrence = Nothing\n',
    1,
)

insert_marker = "' ===================================================================\n' V0.9 ATTACHMENT-AWARE EXTRACTION / SCHEMATIC"
insert_at = src.index(insert_marker)

helpers = r'''
' ===================================================================
' DIMENSION GENERATOR V0.1 - DRAWING API LAYER
' ===================================================================

Function GetTargetDrawingViewV01( _
    drawDoc As DrawingDocument, _
    sheet As Sheet) As DrawingView

    Try
        For Each selected As Object In drawDoc.SelectSet

            If TypeOf selected Is DrawingView Then
                Return CType(selected, DrawingView)
            End If

            If TypeOf selected Is DrawingCurveSegment Then
                Dim seg As DrawingCurveSegment = _
                    CType(selected, DrawingCurveSegment)
                Return seg.Parent.Parent
            End If

        Next
    Catch
    End Try

    If sheet.DrawingViews.Count > 0 Then
        Return sheet.DrawingViews.Item(1)
    End If

    Return Nothing
End Function


Sub DeletePreviousAutoDimensionsV01(sheet As Sheet)

    Try
        Dim chainSets As ChainDimensionSets = _
            sheet.DrawingDimensions.ChainDimensionSets

        For i As Integer = chainSets.Count To 1 Step -1
            If IsAutoTaggedV01(chainSets.Item(i)) Then
                chainSets.Item(i).Delete()
            End If
        Next
    Catch
    End Try

    Try
        Dim baselineSets As BaselineDimensionSets = _
            sheet.DrawingDimensions.BaselineDimensionSets

        For i As Integer = baselineSets.Count To 1 Step -1
            If IsAutoTaggedV01(baselineSets.Item(i)) Then
                baselineSets.Item(i).Delete()
            End If
        Next
    Catch
    End Try

    Try
        Dim generalDimensions As GeneralDimensions = _
            sheet.DrawingDimensions.GeneralDimensions

        For i As Integer = generalDimensions.Count To 1 Step -1
            If IsAutoTaggedV01(generalDimensions.Item(i)) Then
                generalDimensions.Item(i).Delete()
            End If
        Next
    Catch
    End Try

    Try
        Dim oldSketch As DrawingSketch = _
            sheet.Sketches.Item("AUTO_DIM_ANCHORS")
        oldSketch.Delete()
    Catch
    End Try

End Sub


Function IsAutoTaggedV01(obj As Object) As Boolean
    Try
        Dim tag As AttributeSet = _
            obj.AttributeSets.Item("AutoDimensions")
        Return tag IsNot Nothing
    Catch
        Return False
    End Try
End Function


Sub TagAutoObjectV01(obj As Object)
    Try
        If Not IsAutoTaggedV01(obj) Then
            obj.AttributeSets.Add("AutoDimensions")
        End If
    Catch
    End Try
End Sub


Function BuildChainRequestsV01( _
    view As DrawingView, _
    componentDimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain), _
    allAnchors As List(Of AutoDimAnchorV01)) As List(Of AutoChainRequestV01)

    Dim result As New List(Of AutoChainRequestV01)

    Dim horizontalLevel As Integer = 0
    Dim verticalLevel As Integer = 0
    Dim alignedLevel As Integer = 0

    For Each chain As StraightChain In chains

        Dim dimensionsOnChain As New List(Of DimensionRecord)

        For Each d As DimensionRecord In componentDimensions
            If d.ChainIndex = chain.Index Then
                dimensionsOnChain.Add(d)
            End If
        Next

        If dimensionsOnChain.Count = 0 Then
            Continue For
        End If

        Dim request As New AutoChainRequestV01
        request.Chain = chain
        request.Name = "RUN " & chain.Index.ToString()

        For Each d As DimensionRecord In dimensionsOnChain
            AddAnchorToChainRequestV01( _
                request, _
                GetOrAddAnchorV01( _
                    allAnchors, view, _
                    d.X1, d.Y1, d.Z1))

            AddAnchorToChainRequestV01( _
                request, _
                GetOrAddAnchorV01( _
                    allAnchors, view, _
                    d.X2, d.Y2, d.Z2))
        Next

        SortChainAnchorsV01(request)

        If request.Anchors.Count < 2 Then
            Continue For
        End If

        Dim firstAnchor As AutoDimAnchorV01 = request.Anchors.Item(0)
        Dim lastAnchor As AutoDimAnchorV01 = _
            request.Anchors.Item(request.Anchors.Count - 1)

        request.DimensionType = _
            ChooseDimensionTypeV01( _
                firstAnchor.SheetPoint, _
                lastAnchor.SheetPoint)

        Dim rightX As Double = view.Left + view.Width
        Dim bottomY As Double = view.Top - view.Height

        If request.DimensionType = _
           DimensionTypeEnum.kHorizontalDimensionType Then

            horizontalLevel += 1

            request.PlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    (firstAnchor.SheetPoint.X + lastAnchor.SheetPoint.X) / 2.0, _
                    bottomY - 0.8 - (horizontalLevel - 1) * 0.65)

            request.OverallPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    request.PlacementPoint.X, _
                    request.PlacementPoint.Y - 0.75)

        ElseIf request.DimensionType = _
               DimensionTypeEnum.kVerticalDimensionType Then

            verticalLevel += 1

            request.PlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    rightX + 0.8 + (verticalLevel - 1) * 0.65, _
                    (firstAnchor.SheetPoint.Y + lastAnchor.SheetPoint.Y) / 2.0)

            request.OverallPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    request.PlacementPoint.X + 0.75, _
                    request.PlacementPoint.Y)

        Else

            alignedLevel += 1

            Dim midX As Double = _
                (firstAnchor.SheetPoint.X + lastAnchor.SheetPoint.X) / 2.0
            Dim midY As Double = _
                (firstAnchor.SheetPoint.Y + lastAnchor.SheetPoint.Y) / 2.0

            Dim dx As Double = _
                lastAnchor.SheetPoint.X - firstAnchor.SheetPoint.X
            Dim dy As Double = _
                lastAnchor.SheetPoint.Y - firstAnchor.SheetPoint.Y
            Dim length2d As Double = Math.Sqrt(dx * dx + dy * dy)

            If length2d < 0.001 Then
                Continue For
            End If

            Dim nx As Double = -dy / length2d
            Dim ny As Double = dx / length2d
            Dim offset As Double = 0.9 + (alignedLevel - 1) * 0.65

            request.PlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    midX + nx * offset, _
                    midY + ny * offset)

            request.OverallPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    midX + nx * (offset + 0.75), _
                    midY + ny * (offset + 0.75))

        End If

        result.Add(request)

    Next

    Return result
End Function


Sub AddAnchorToChainRequestV01( _
    request As AutoChainRequestV01, _
    anchor As AutoDimAnchorV01)

    For Each existing As AutoDimAnchorV01 In request.Anchors
        If Dist3D( _
            existing.X, existing.Y, existing.Z, _
            anchor.X, anchor.Y, anchor.Z) < 0.1 Then
            Exit Sub
        End If
    Next

    request.Anchors.Add(anchor)
End Sub


Sub SortChainAnchorsV01(request As AutoChainRequestV01)

    If request.Chain Is Nothing OrElse request.Anchors.Count < 2 Then
        Exit Sub
    End If

    For i As Integer = 0 To request.Anchors.Count - 2
        For j As Integer = i + 1 To request.Anchors.Count - 1

            Dim ti As Double = _
                ChainParameterV01( _
                    request.Chain, _
                    request.Anchors.Item(i))

            Dim tj As Double = _
                ChainParameterV01( _
                    request.Chain, _
                    request.Anchors.Item(j))

            If tj < ti Then
                Dim temp As AutoDimAnchorV01 = request.Anchors.Item(i)
                request.Anchors.Item(i) = request.Anchors.Item(j)
                request.Anchors.Item(j) = temp
            End If
        Next
    Next
End Sub


Function ChainParameterV01( _
    chain As StraightChain, _
    anchor As AutoDimAnchorV01) As Double

    Dim dx As Double = chain.X2 - chain.X1
    Dim dy As Double = chain.Y2 - chain.Y1
    Dim dz As Double = chain.Z2 - chain.Z1
    Dim length As Double = Math.Sqrt(dx * dx + dy * dy + dz * dz)

    If length < 0.001 Then Return 0

    dx /= length : dy /= length : dz /= length

    Return _
        (anchor.X - chain.X1) * dx + _
        (anchor.Y - chain.Y1) * dy + _
        (anchor.Z - chain.Z1) * dz
End Function


Function GetOrAddAnchorV01( _
    allAnchors As List(Of AutoDimAnchorV01), _
    view As DrawingView, _
    x As Double, _
    y As Double, _
    z As Double) As AutoDimAnchorV01

    For Each existing As AutoDimAnchorV01 In allAnchors
        If Dist3D( _
            existing.X, existing.Y, existing.Z, _
            x, y, z) < 0.05 Then
            Return existing
        End If
    Next

    Dim anchor As New AutoDimAnchorV01
    anchor.X = x : anchor.Y = y : anchor.Z = z

    Dim modelPoint As Inventor.Point = _
        ThisApplication.TransientGeometry.CreatePoint( _
            x / 10.0, _
            y / 10.0, _
            z / 10.0)

    anchor.SheetPoint = _
        view.ModelToSheetSpace(modelPoint)

    allAnchors.Add(anchor)
    Return anchor
End Function


Function ChooseDimensionTypeV01( _
    a As Point2d, _
    b As Point2d) As DimensionTypeEnum

    Dim dx As Double = Math.Abs(b.X - a.X)
    Dim dy As Double = Math.Abs(b.Y - a.Y)

    If dx > dy * 8.0 Then
        Return DimensionTypeEnum.kHorizontalDimensionType
    End If

    If dy > dx * 8.0 Then
        Return DimensionTypeEnum.kVerticalDimensionType
    End If

    Return DimensionTypeEnum.kAlignedDimensionType
End Function


Function CreateAnchorSketchV01( _
    sheet As Sheet, _
    allAnchors As List(Of AutoDimAnchorV01)) As DrawingSketch

    Dim sketch As DrawingSketch = sheet.Sketches.Add()
    sketch.Name = "AUTO_DIM_ANCHORS"

    sketch.Edit()

    For Each anchor As AutoDimAnchorV01 In allAnchors
        anchor.Entity = _
            sketch.SketchPoints.Add( _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    anchor.SheetPoint.X, _
                    anchor.SheetPoint.Y), _
                False)
    Next

    sketch.ExitEdit()
    Return sketch
End Function


Function CreateChainDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests

        If request.Anchors.Count < 2 Then Continue For

        Try
            Dim intents As ObjectCollection = _
                ThisApplication.TransientObjects.CreateObjectCollection()

            For Each anchor As AutoDimAnchorV01 In request.Anchors
                intents.Add( _
                    sheet.CreateGeometryIntent(anchor.Entity))
            Next

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
                "Chain dimension failed for " & _
                request.Name & _
                ": " & _
                ex.Message)
        End Try

    Next

    Return created
End Function


Function CreateOverallDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests

        ' If there are only two anchors, the chain already represents
        ' a single dimension and an identical overall would be redundant.
        If request.Anchors.Count <= 2 Then Continue For

        Try
            Dim firstAnchor As AutoDimAnchorV01 = request.Anchors.Item(0)
            Dim lastAnchor As AutoDimAnchorV01 = _
                request.Anchors.Item(request.Anchors.Count - 1)

            Dim intent1 As GeometryIntent = _
                sheet.CreateGeometryIntent(firstAnchor.Entity)
            Dim intent2 As GeometryIntent = _
                sheet.CreateGeometryIntent(lastAnchor.Entity)

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
End Function


Function BuildAttachmentPlanV01( _
    view As DrawingView, _
    attachments As List(Of AttachmentRecordV09), _
    allAnchors As List(Of AutoDimAnchorV01)) As AutoAttachmentPlanV01

    Dim plan As New AutoAttachmentPlanV01

    If attachments Is Nothing OrElse attachments.Count = 0 Then
        Return plan
    End If

    Dim datumAttachment As AttachmentRecordV09 = attachments.Item(0)

    plan.Datum = _
        GetOrAddAnchorV01( _
            allAnchors, view, _
            datumAttachment.DatumX, _
            datumAttachment.DatumY, _
            datumAttachment.DatumZ)

    For Each a As AttachmentRecordV09 In attachments

        Dim baseAnchor As AutoDimAnchorV01 = _
            GetOrAddAnchorV01( _
                allAnchors, view, _
                a.BaseX, a.BaseY, a.BaseZ)

        Dim terminalAnchor As AutoDimAnchorV01 = _
            GetOrAddAnchorV01( _
                allAnchors, view, _
                a.TerminalX, a.TerminalY, a.TerminalZ)

        Dim projectedRise As Double = _
            SheetDistanceV01( _
                baseAnchor.SheetPoint, _
                terminalAnchor.SheetPoint)

        ' If the branch is almost normal to the sheet it belongs to
        ' another projected view; do not dimension its rise here.
        If projectedRise < 0.15 Then
            Continue For
        End If

        Dim stationAnchor As AutoDimAnchorV01 = _
            GetOrAddAnchorV01( _
                allAnchors, view, _
                a.AxisPointX, a.AxisPointY, a.AxisPointZ)

        plan.StationAnchors.Add(stationAnchor)

        Dim riseRequest As New AutoLinearRequestV01
        riseRequest.A = baseAnchor
        riseRequest.B = terminalAnchor
        riseRequest.DimensionType = _
            ChooseDimensionTypeV01( _
                baseAnchor.SheetPoint, _
                terminalAnchor.SheetPoint)

        Dim dx As Double = terminalAnchor.SheetPoint.X - baseAnchor.SheetPoint.X
        Dim dy As Double = terminalAnchor.SheetPoint.Y - baseAnchor.SheetPoint.Y
        Dim l As Double = Math.Sqrt(dx * dx + dy * dy)

        If l > 0.001 Then
            Dim nx As Double = -dy / l
            Dim ny As Double = dx / l
            riseRequest.TextPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    (baseAnchor.SheetPoint.X + terminalAnchor.SheetPoint.X) / 2.0 + nx * 0.45, _
                    (baseAnchor.SheetPoint.Y + terminalAnchor.SheetPoint.Y) / 2.0 + ny * 0.45)
        Else
            riseRequest.TextPoint = terminalAnchor.SheetPoint.Copy()
        End If

        plan.RiseRequests.Add(riseRequest)

    Next

    If plan.StationAnchors.Count > 0 Then

        SortAttachmentStationsV01( _
            datumAttachment, _
            plan.StationAnchors)

        Dim farAnchor As AutoDimAnchorV01 = _
            plan.StationAnchors.Item( _
                plan.StationAnchors.Count - 1)

        plan.StationDimensionType = _
            ChooseDimensionTypeV01( _
                plan.Datum.SheetPoint, _
                farAnchor.SheetPoint)

        If plan.StationDimensionType = _
           DimensionTypeEnum.kHorizontalDimensionType Then

            plan.StationPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    view.Position.X, _
                    view.Top + 1.1)

        ElseIf plan.StationDimensionType = _
               DimensionTypeEnum.kVerticalDimensionType Then

            plan.StationPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    view.Left - 1.1, _
                    view.Position.Y)

        Else

            plan.StationPlacementPoint = _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    view.Left - 1.0, _
                    view.Top + 1.0)

        End If

    End If

    Return plan
End Function


Sub SortAttachmentStationsV01( _
    datumAttachment As AttachmentRecordV09, _
    anchors As List(Of AutoDimAnchorV01))

    For i As Integer = 0 To anchors.Count - 2
        For j As Integer = i + 1 To anchors.Count - 1

            Dim ai As AutoDimAnchorV01 = anchors.Item(i)
            Dim aj As AutoDimAnchorV01 = anchors.Item(j)

            Dim ti As Double = _
                (ai.X - datumAttachment.DatumX) * datumAttachment.MainUX + _
                (ai.Y - datumAttachment.DatumY) * datumAttachment.MainUY + _
                (ai.Z - datumAttachment.DatumZ) * datumAttachment.MainUZ

            Dim tj As Double = _
                (aj.X - datumAttachment.DatumX) * datumAttachment.MainUX + _
                (aj.Y - datumAttachment.DatumY) * datumAttachment.MainUY + _
                (aj.Z - datumAttachment.DatumZ) * datumAttachment.MainUZ

            If tj < ti Then
                Dim temp As AutoDimAnchorV01 = anchors.Item(i)
                anchors.Item(i) = anchors.Item(j)
                anchors.Item(j) = temp
            End If
        Next
    Next
End Sub


Function CreateAttachmentDimensionsV01( _
    sheet As Sheet, _
    plan As AutoAttachmentPlanV01) As Integer

    Dim created As Integer = 0

    If plan Is Nothing Then Return created

    If plan.Datum IsNot Nothing AndAlso _
       plan.StationAnchors.Count > 0 Then

        Try
            Dim intents As ObjectCollection = _
                ThisApplication.TransientObjects.CreateObjectCollection()

            intents.Add( _
                sheet.CreateGeometryIntent(plan.Datum.Entity))

            For Each anchor As AutoDimAnchorV01 In plan.StationAnchors
                intents.Add( _
                    sheet.CreateGeometryIntent(anchor.Entity))
            Next

            Dim baselineSet As BaselineDimensionSet = _
                sheet.DrawingDimensions.BaselineDimensionSets.Add( _
                    intents, _
                    plan.StationPlacementPoint, _
                    plan.StationDimensionType)

            Try
                baselineSet.Precision = 0
            Catch
            End Try

            TagAutoObjectV01(baselineSet)
            created += 1

        Catch ex As Exception
            Logger.Error( _
                "Attachment station baseline set failed: " & _
                ex.Message)
        End Try

    End If

    For Each request As AutoLinearRequestV01 In plan.RiseRequests

        Try
            Dim intent1 As GeometryIntent = _
                sheet.CreateGeometryIntent(request.A.Entity)
            Dim intent2 As GeometryIntent = _
                sheet.CreateGeometryIntent(request.B.Entity)

            Dim dimObj As LinearGeneralDimension = _
                sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                    request.TextPoint, _
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
                "Attachment rise dimension failed: " & _
                ex.Message)
        End Try

    Next

    Return created
End Function


Function SheetDistanceV01(a As Point2d, b As Point2d) As Double
    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Return Math.Sqrt(dx * dx + dy * dy)
End Function


Class AutoDimAnchorV01
    Public X As Double
    Public Y As Double
    Public Z As Double
    Public SheetPoint As Point2d = Nothing
    Public Entity As SketchPoint = Nothing
End Class


Class AutoChainRequestV01
    Public Name As String = ""
    Public Chain As StraightChain = Nothing
    Public Anchors As New List(Of AutoDimAnchorV01)
    Public DimensionType As DimensionTypeEnum
    Public PlacementPoint As Point2d = Nothing
    Public OverallPlacementPoint As Point2d = Nothing
End Class


Class AutoLinearRequestV01
    Public A As AutoDimAnchorV01 = Nothing
    Public B As AutoDimAnchorV01 = Nothing
    Public DimensionType As DimensionTypeEnum
    Public TextPoint As Point2d = Nothing
End Class


Class AutoAttachmentPlanV01
    Public Datum As AutoDimAnchorV01 = Nothing
    Public StationAnchors As New List(Of AutoDimAnchorV01)
    Public StationDimensionType As DimensionTypeEnum
    Public StationPlacementPoint As Point2d = Nothing
    Public RiseRequests As New List(Of AutoLinearRequestV01)
End Class


'''

src = src[:insert_at] + helpers + src[insert_at:]

# This file is a drawing-dimension rule. It deliberately does not call any
# CSV/SVG writers even though some copied helper code remains below for now.
src = src.replace(
    "AUTOSPOOL - SINGLE SPOOL TOPOLOGY / DIMENSION VERIFIER V0.4",
    "AUTOSPOOL - DRAWING DIMENSION GENERATOR V0.1",
)

DST.write_text(src, encoding='utf-8', newline='\n')
print(f'Wrote {DST} ({len(src.splitlines())} lines)')
