AddReference "System.Windows.Forms.dll"

Imports System
Imports System.Collections.Generic
Imports System.Windows.Forms

' ============================================================================
' CENTERLINE DIMENSION PROBE V0.1
' ----------------------------------------------------------------------------
' PURPOSE
'   Test whether Inventor can safely use ONE EXISTING native Centerline as a
'   GeometryIntent in a normal linear drawing dimension.
'
' IMPORTANT
'   - This rule does NOT create centerlines.
'   - This rule does NOT create centerline/centerline intersection intents.
'   - This rule does NOT create chain dimensions.
'   - This rule creates only ONE GeneralDimension per run.
'
' HOW TO USE
'   Preselect exactly:
'     1) ONE existing native Centerline
'     2) ONE real projected straight DrawingCurveSegment
'
'   Then choose:
'     H = horizontal dimension
'     V = vertical dimension
'
' EXAMPLE HORIZONTAL TEST
'   Select a vertical projected flange/end face line and a vertical native
'   centerline. The resulting horizontal dimension should measure X spacing.
'
' EXAMPLE VERTICAL TEST
'   Select a horizontal projected flange/end face line and a horizontal native
'   centerline. The resulting vertical dimension should measure Y spacing.
' ============================================================================

Sub Main()

    Try
        If ThisApplication.ActiveDocument.DocumentType <> _
           DocumentTypeEnum.kDrawingDocumentObject Then

            MessageBox.Show( _
                "Run CenterlineDimensionProbe from an Inventor drawing.", _
                "Centerline Dimension Probe")
            Exit Sub
        End If

        Dim drawDoc As DrawingDocument = _
            CType(ThisApplication.ActiveDocument, DrawingDocument)

        Dim sheet As Sheet = drawDoc.ActiveSheet

        Dim selectedCenterline As Centerline = Nothing
        Dim selectedSegment As DrawingCurveSegment = Nothing
        Dim centerlineCount As Integer = 0
        Dim segmentCount As Integer = 0

        For Each selectedObject As Object In drawDoc.SelectSet

            If TypeOf selectedObject Is Centerline Then
                selectedCenterline = CType(selectedObject, Centerline)
                centerlineCount += 1
            ElseIf TypeOf selectedObject Is DrawingCurveSegment Then
                Dim seg As DrawingCurveSegment = _
                    CType(selectedObject, DrawingCurveSegment)

                If IsStraightVisibleSegmentProbe(seg) Then
                    selectedSegment = seg
                    segmentCount += 1
                End If
            End If

        Next

        If centerlineCount <> 1 OrElse segmentCount <> 1 Then
            MessageBox.Show( _
                "Select exactly ONE existing centerline and ONE projected straight line." & _
                vbCrLf & vbCrLf & _
                "Selected centerlines: " & centerlineCount.ToString() & vbCrLf & _
                "Selected straight projected lines: " & segmentCount.ToString(), _
                "Centerline Dimension Probe")
            Exit Sub
        End If

        Dim direction As String = _
            Microsoft.VisualBasic.Interaction.InputBox( _
                "Enter H for a horizontal dimension or V for a vertical dimension.", _
                "Centerline Dimension Probe", _
                "H")

        If String.IsNullOrWhiteSpace(direction) Then Exit Sub
        direction = direction.Trim().ToUpperInvariant()

        Dim dimType As DimensionTypeEnum
        If direction = "H" Then
            dimType = DimensionTypeEnum.kHorizontalDimensionType
        ElseIf direction = "V" Then
            dimType = DimensionTypeEnum.kVerticalDimensionType
        Else
            MessageBox.Show("Enter only H or V.", "Centerline Dimension Probe")
            Exit Sub
        End If

        Dim clAngle As String = DescribeCenterlineDirectionProbe(selectedCenterline)
        Dim segAngle As String = DescribeSegmentDirectionProbe(selectedSegment)

        Logger.Info( _
            "CENTERLINE_DIM_PROBE selection" & _
            " | requested=" & direction & _
            " | centerline=" & clAngle & _
            " | projectedLine=" & segAngle)

        Dim answer As DialogResult = _
            MessageBox.Show( _
                "About to create ONE linear dimension using:" & vbCrLf & vbCrLf & _
                "• one existing native centerline" & vbCrLf & _
                "• one real projected drawing line" & vbCrLf & _
                "• no intersection intent" & vbCrLf & _
                "• no centerline creation" & vbCrLf & vbCrLf & _
                "Dimension direction: " & direction & vbCrLf & _
                "Centerline direction: " & clAngle & vbCrLf & _
                "Projected line direction: " & segAngle & vbCrLf & vbCrLf & _
                "Continue?", _
                "Centerline Dimension Probe", _
                MessageBoxButtons.YesNo, _
                MessageBoxIcon.Warning)

        If answer <> DialogResult.Yes Then Exit Sub

        Logger.Info("CENTERLINE_DIM_PROBE before CreateGeometryIntent(projected line)")
        Dim lineIntent As GeometryIntent = _
            sheet.CreateGeometryIntent(selectedSegment.Parent)
        Logger.Info("CENTERLINE_DIM_PROBE projected line intent created")

        Logger.Info("CENTERLINE_DIM_PROBE before CreateGeometryIntent(centerline)")
        Dim centerlineIntent As GeometryIntent = _
            sheet.CreateGeometryIntent(selectedCenterline)
        Logger.Info("CENTERLINE_DIM_PROBE centerline intent created")

        Dim textOrigin As Point2d = _
            GetDimensionPlacementProbe( _
                selectedSegment, _
                selectedCenterline, _
                dimType)

        Logger.Info("CENTERLINE_DIM_PROBE immediately before GeneralDimensions.AddLinear")

        Dim dimObj As LinearGeneralDimension = _
            sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                textOrigin, _
                lineIntent, _
                centerlineIntent, _
                dimType)

        Logger.Info("CENTERLINE_DIM_PROBE AddLinear returned successfully")

        Try
            dimObj.Precision = 0
        Catch
        End Try

        Try
            Dim tags As AttributeSet = _
                dimObj.AttributeSets.Add("CenterlineDimensionProbe")
            tags.Add("Direction", ValueTypeEnum.kStringType, direction)
        Catch
        End Try

        drawDoc.Update2(True)

        MessageBox.Show( _
            "SUCCESS: Inventor created a linear dimension to ONE existing centerline.", _
            "Centerline Dimension Probe")

    Catch ex As Exception
        Logger.Error("CENTERLINE_DIM_PROBE exception: " & ex.ToString())
        MessageBox.Show( _
            "CenterlineDimensionProbe returned an exception:" & vbCrLf & vbCrLf & _
            ex.Message, _
            "Centerline Dimension Probe")
    End Try

End Sub


Function IsStraightVisibleSegmentProbe( _
    seg As DrawingCurveSegment) As Boolean

    If seg Is Nothing Then Return False

    Try
        If seg.GeometryType <> Curve2dTypeEnum.kLineSegmentCurve2d Then
            Return False
        End If

        If seg.StartPoint Is Nothing OrElse seg.EndPoint Is Nothing Then
            Return False
        End If

        If Not seg.Visible Then Return False
        If seg.HiddenLine Then Return False

        Return SegmentLengthProbe(seg) > 0.02
    Catch
        Return False
    End Try
End Function


Function SegmentLengthProbe( _
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


Function DescribeSegmentDirectionProbe( _
    seg As DrawingCurveSegment) As String

    If seg Is Nothing Then Return "UNKNOWN"

    Dim dx As Double = Math.Abs(seg.EndPoint.X - seg.StartPoint.X)
    Dim dy As Double = Math.Abs(seg.EndPoint.Y - seg.StartPoint.Y)

    If dx > dy * 5.0 Then Return "HORIZONTAL"
    If dy > dx * 5.0 Then Return "VERTICAL"
    Return "ANGLED"
End Function


Function DescribeCenterlineDirectionProbe( _
    cl As Centerline) As String

    If cl Is Nothing OrElse _
       cl.StartPoint Is Nothing OrElse _
       cl.EndPoint Is Nothing Then
        Return "UNKNOWN"
    End If

    Dim dx As Double = Math.Abs(cl.EndPoint.X - cl.StartPoint.X)
    Dim dy As Double = Math.Abs(cl.EndPoint.Y - cl.StartPoint.Y)

    If dx > dy * 5.0 Then Return "HORIZONTAL"
    If dy > dx * 5.0 Then Return "VERTICAL"
    Return "ANGLED"
End Function


Function GetDimensionPlacementProbe( _
    seg As DrawingCurveSegment, _
    cl As Centerline, _
    dimType As DimensionTypeEnum) As Point2d

    Dim sx As Double = _
        (seg.StartPoint.X + seg.EndPoint.X) / 2.0
    Dim sy As Double = _
        (seg.StartPoint.Y + seg.EndPoint.Y) / 2.0

    Dim cx As Double = _
        (cl.StartPoint.X + cl.EndPoint.X) / 2.0
    Dim cy As Double = _
        (cl.StartPoint.Y + cl.EndPoint.Y) / 2.0

    If dimType = DimensionTypeEnum.kHorizontalDimensionType Then
        Return _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                (sx + cx) / 2.0, _
                Math.Min(sy, cy) - 1.0)
    End If

    Return _
        ThisApplication.TransientGeometry.CreatePoint2d( _
            Math.Max(sx, cx) + 1.0, _
            (sy + cy) / 2.0)
End Function
