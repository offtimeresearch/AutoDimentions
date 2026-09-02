AddReference "System.Windows.Forms.dll"

Imports System
Imports System.Collections.Generic
Imports System.Windows.Forms

' ============================================================================
' CENTERLINE CHAIN PROBE V0.1
' ----------------------------------------------------------------------------
' PURPOSE
'   Test whether Inventor safely accepts ONE existing native Centerline inside
'   a native ChainDimensionSet together with real projected drawing lines.
'
' HOW TO USE
'   Preselect exactly:
'     - ONE existing native Centerline
'     - TWO or more real projected straight DrawingCurveSegments
'
'   For H: choose vertical datum lines + a vertical centerline.
'   For V: choose horizontal datum lines + a horizontal centerline.
'
' The rule sorts the selected datums by X for H or Y for V, then creates ONE
' ChainDimensionSet.  It never creates or modifies a centerline and never makes
' a centerline-centerline intersection intent.
' ============================================================================

Sub Main()

    Try
        If ThisApplication.ActiveDocument.DocumentType <> _
           DocumentTypeEnum.kDrawingDocumentObject Then

            MessageBox.Show( _
                "Run CenterlineChainProbe from an Inventor drawing.", _
                "Centerline Chain Probe")
            Exit Sub
        End If

        Dim drawDoc As DrawingDocument = _
            CType(ThisApplication.ActiveDocument, DrawingDocument)

        Dim sheet As Sheet = drawDoc.ActiveSheet

        Dim centerline As Centerline = Nothing
        Dim centerlineCount As Integer = 0
        Dim segments As New List(Of DrawingCurveSegment)

        For Each selectedObject As Object In drawDoc.SelectSet

            If TypeOf selectedObject Is Centerline Then
                centerline = CType(selectedObject, Centerline)
                centerlineCount += 1

            ElseIf TypeOf selectedObject Is DrawingCurveSegment Then
                Dim seg As DrawingCurveSegment = _
                    CType(selectedObject, DrawingCurveSegment)

                If IsStraightVisibleSegmentCCP(seg) Then
                    segments.Add(seg)
                End If
            End If
        Next

        If centerlineCount <> 1 OrElse segments.Count < 2 Then
            MessageBox.Show( _
                "Select exactly ONE native centerline and at least TWO projected straight lines." & _
                vbCrLf & vbCrLf & _
                "Centerlines selected: " & centerlineCount.ToString() & vbCrLf & _
                "Straight projected lines selected: " & segments.Count.ToString(), _
                "Centerline Chain Probe")
            Exit Sub
        End If

        Dim direction As String = _
            Microsoft.VisualBasic.Interaction.InputBox( _
                "Enter H for horizontal chain or V for vertical chain.", _
                "Centerline Chain Probe", _
                "H")

        If String.IsNullOrWhiteSpace(direction) Then Exit Sub
        direction = direction.Trim().ToUpperInvariant()

        Dim dimType As DimensionTypeEnum
        If direction = "H" Then
            dimType = DimensionTypeEnum.kHorizontalDimensionType
        ElseIf direction = "V" Then
            dimType = DimensionTypeEnum.kVerticalDimensionType
        Else
            MessageBox.Show("Enter only H or V.", "Centerline Chain Probe")
            Exit Sub
        End If

        Dim datums As New List(Of ChainDatumProbe)

        For Each seg As DrawingCurveSegment In segments
            Dim d As New ChainDatumProbe
            d.GeometryObject = seg.Parent
            d.X = (seg.StartPoint.X + seg.EndPoint.X) / 2.0
            d.Y = (seg.StartPoint.Y + seg.EndPoint.Y) / 2.0
            d.Label = "PROJECTED_LINE"
            datums.Add(d)
        Next

        Dim clDatum As New ChainDatumProbe
        clDatum.GeometryObject = centerline
        clDatum.X = (centerline.StartPoint.X + centerline.EndPoint.X) / 2.0
        clDatum.Y = (centerline.StartPoint.Y + centerline.EndPoint.Y) / 2.0
        clDatum.Label = "CENTERLINE"
        datums.Add(clDatum)

        SortDatumsCCP(datums, direction)

        Dim intents As ObjectCollection = _
            ThisApplication.TransientObjects.CreateObjectCollection()

        For Each datum As ChainDatumProbe In datums
            Logger.Info( _
                "CENTERLINE_CHAIN_PROBE intent " & datum.Label & _
                " | x=" & datum.X.ToString("0.###") & _
                " | y=" & datum.Y.ToString("0.###"))

            Dim intent As GeometryIntent = _
                sheet.CreateGeometryIntent(datum.GeometryObject)

            intents.Add(intent)
        Next

        Dim placement As Point2d = GetPlacementCCP(datums, direction)

        Dim answer As DialogResult = _
            MessageBox.Show( _
                "About to create ONE native ChainDimensionSet containing:" & vbCrLf & vbCrLf & _
                "• one existing native centerline" & vbCrLf & _
                "• " & segments.Count.ToString() & " projected drawing lines" & vbCrLf & _
                "• no centerline intersection" & vbCrLf & _
                "• no centerline creation/modification" & vbCrLf & vbCrLf & _
                "Continue?", _
                "Centerline Chain Probe", _
                MessageBoxButtons.YesNo, _
                MessageBoxIcon.Warning)

        If answer <> DialogResult.Yes Then Exit Sub

        Logger.Info("CENTERLINE_CHAIN_PROBE immediately before ChainDimensionSets.Add")

        Dim dimSet As ChainDimensionSet = _
            sheet.DrawingDimensions.ChainDimensionSets.Add( _
                intents, _
                placement, _
                dimType)

        Logger.Info("CENTERLINE_CHAIN_PROBE ChainDimensionSets.Add returned successfully")

        Try
            dimSet.Precision = 0
        Catch
        End Try

        Try
            Dim tags As AttributeSet = _
                dimSet.AttributeSets.Add("CenterlineChainProbe")
            tags.Add("Direction", ValueTypeEnum.kStringType, direction)
        Catch
        End Try

        drawDoc.Update2(True)

        MessageBox.Show( _
            "SUCCESS: native chain dimension accepted the existing centerline.", _
            "Centerline Chain Probe")

    Catch ex As Exception
        Logger.Error("CENTERLINE_CHAIN_PROBE exception: " & ex.ToString())
        MessageBox.Show( _
            "CenterlineChainProbe returned an exception:" & vbCrLf & vbCrLf & _
            ex.Message, _
            "Centerline Chain Probe")
    End Try

End Sub


Function IsStraightVisibleSegmentCCP( _
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

        Dim dx As Double = seg.EndPoint.X - seg.StartPoint.X
        Dim dy As Double = seg.EndPoint.Y - seg.StartPoint.Y
        Return Math.Sqrt(dx * dx + dy * dy) > 0.02
    Catch
        Return False
    End Try
End Function


Sub SortDatumsCCP( _
    datums As List(Of ChainDatumProbe), _
    direction As String)

    For i As Integer = 0 To datums.Count - 2
        For j As Integer = i + 1 To datums.Count - 1

            Dim swapNeeded As Boolean
            If direction = "H" Then
                swapNeeded = datums.Item(j).X < datums.Item(i).X
            Else
                swapNeeded = datums.Item(j).Y < datums.Item(i).Y
            End If

            If swapNeeded Then
                Dim tmp As ChainDatumProbe = datums.Item(i)
                datums.Item(i) = datums.Item(j)
                datums.Item(j) = tmp
            End If
        Next
    Next
End Sub


Function GetPlacementCCP( _
    datums As List(Of ChainDatumProbe), _
    direction As String) As Point2d

    Dim minX As Double = Double.MaxValue
    Dim maxX As Double = Double.MinValue
    Dim minY As Double = Double.MaxValue
    Dim maxY As Double = Double.MinValue

    For Each d As ChainDatumProbe In datums
        minX = Math.Min(minX, d.X)
        maxX = Math.Max(maxX, d.X)
        minY = Math.Min(minY, d.Y)
        maxY = Math.Max(maxY, d.Y)
    Next

    If direction = "H" Then
        Return _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                (minX + maxX) / 2.0, _
                minY - 1.2)
    End If

    Return _
        ThisApplication.TransientGeometry.CreatePoint2d( _
            maxX + 1.2, _
            (minY + maxY) / 2.0)
End Function


Class ChainDatumProbe
    Public GeometryObject As Object = Nothing
    Public X As Double
    Public Y As Double
    Public Label As String = ""
End Class
