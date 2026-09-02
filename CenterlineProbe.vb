AddReference "System.Windows.Forms.dll"

Imports System
Imports System.Collections.Generic
Imports System.Windows.Forms

' ============================================================================
' CENTERLINE PROBE V0.1
' ----------------------------------------------------------------------------
' PURPOSE
'   Isolate Inventor drawing centerline creation from DimensionGenerator.
'
' TEST MODES
'   1 = MANUAL BISECTOR
'       Preselect exactly TWO projected straight silhouette lines.
'       Calls Centerlines.AddBisector only on those two user-selected lines.
'
'   2 = AUTO PIPE BISECTOR
'       Preselect ONE straight projected pipe silhouette line.
'       The rule finds the containing assembly occurrence, searches only that
'       occurrence's projected curves for the best parallel opposite line,
'       highlights the pair, asks for confirmation, then calls AddBisector.
'
'   3 = AUTO FLANGE BISECTOR
'       Same controlled occurrence-only test as mode 2.  Use it after the
'       pipe test succeeds, by selecting one straight projected flange line.
'
'   4 = REGULAR CENTERLINE FROM TWO CROSS-LINES
'       Preselect TWO projected straight end/cross lines at different stations.
'       Uses the MIDPOINT of each real projected line and Centerlines.Add.
'       This does NOT call AddBisector.  It is the fallback experiment if
'       AddBisector itself proves unstable in Inventor 2026.3.
'
' IMPORTANT
'   - No sketches.
'   - No dimensions.
'   - No automated-centerline command.
'   - No elbow centerline generation.
'   - This rule only tests native drawing Centerline creation.
' ============================================================================

Sub Main()

    Try
        If ThisApplication.ActiveDocument.DocumentType <> _
           DocumentTypeEnum.kDrawingDocumentObject Then

            MessageBox.Show( _
                "Run CenterlineProbe from an Inventor drawing.", _
                "Centerline Probe")
            Exit Sub
        End If

        Dim drawDoc As DrawingDocument = _
            CType(ThisApplication.ActiveDocument, DrawingDocument)

        Dim sheet As Sheet = drawDoc.ActiveSheet

        Dim modeText As String = _
            Microsoft.VisualBasic.Interaction.InputBox( _
                "Centerline Probe V0.1" & vbCrLf & vbCrLf & _
                "1 = Manual bisector: select TWO parallel projected lines" & vbCrLf & _
                "2 = Auto PIPE: select ONE pipe silhouette line" & vbCrLf & _
                "3 = Auto FLANGE: select ONE flange straight line" & vbCrLf & _
                "4 = Safe regular centerline: select TWO cross/end lines" & vbCrLf & vbCrLf & _
                "Start with MODE 1.", _
                "Centerline Probe", _
                "1")

        If String.IsNullOrWhiteSpace(modeText) Then Exit Sub

        Dim mode As Integer = 0
        If Not Integer.TryParse(modeText.Trim(), mode) Then
            MessageBox.Show("Enter 1, 2, 3, or 4.", "Centerline Probe")
            Exit Sub
        End If

        Select Case mode
            Case 1
                RunManualBisectorProbe(drawDoc, sheet)

            Case 2
                RunAutoOccurrenceBisectorProbe(drawDoc, sheet, "PIPE")

            Case 3
                RunAutoOccurrenceBisectorProbe(drawDoc, sheet, "FLANGE")

            Case 4
                RunRegularCenterlineProbe(drawDoc, sheet)

            Case Else
                MessageBox.Show("Enter 1, 2, 3, or 4.", "Centerline Probe")
        End Select

    Catch ex As Exception
        Logger.Error("CenterlineProbe fatal: " & ex.ToString())
        MessageBox.Show( _
            "CenterlineProbe failed:" & vbCrLf & vbCrLf & ex.Message, _
            "Centerline Probe")
    End Try

End Sub


' ============================================================================
' MODE 1 - TWO USER-SELECTED PARALLEL LINES -> AddBisector
' ============================================================================

Sub RunManualBisectorProbe( _
    drawDoc As DrawingDocument, _
    sheet As Sheet)

    Dim selected As List(Of DrawingCurveSegment) = _
        GetSelectedStraightSegments(drawDoc)

    If selected.Count <> 2 Then
        MessageBox.Show( _
            "MODE 1 requires exactly TWO projected straight lines selected." & _
            vbCrLf & vbCrLf & _
            "Select the two opposite pipe silhouette lines, then run again.", _
            "Centerline Probe")
        Exit Sub
    End If

    Dim a As DrawingCurveSegment = selected.Item(0)
    Dim b As DrawingCurveSegment = selected.Item(1)

    If a.Parent.Parent IsNot b.Parent.Parent Then
        MessageBox.Show( _
            "The two lines belong to different drawing views.", _
            "Centerline Probe")
        Exit Sub
    End If

    Dim alignment As Double = SegmentParallelAlignment(a, b)
    Dim offset As Double = ParallelLineSeparation(a, b)

    Logger.Info( _
        "MODE1 manual pair | alignment=" & NumCL(alignment) & _
        " | separation=" & NumCL(offset) & _
        " | lengthA=" & NumCL(SegmentLength(a)) & _
        " | lengthB=" & NumCL(SegmentLength(b)))

    If alignment < 0.995 Then
        MessageBox.Show( _
            "The selected lines are not parallel enough." & vbCrLf & _
            "Alignment = " & NumCL(alignment), _
            "Centerline Probe")
        Exit Sub
    End If

    If offset < 0.01 Then
        MessageBox.Show( _
            "The selected lines are effectively coincident. Select opposite silhouettes.", _
            "Centerline Probe")
        Exit Sub
    End If

    Dim answer As DialogResult = _
        MessageBox.Show( _
            "About to call Inventor Centerlines.AddBisector on ONLY the two lines you selected." & _
            vbCrLf & vbCrLf & _
            "Alignment: " & NumCL(alignment) & vbCrLf & _
            "Line separation: " & NumCL(offset) & " cm on sheet" & vbCrLf & vbCrLf & _
            "Continue?", _
            "Centerline Probe - MODE 1", _
            MessageBoxButtons.YesNo, _
            MessageBoxIcon.Warning)

    If answer <> DialogResult.Yes Then Exit Sub

    CreateBisectorFromSegments(sheet, a, b, "MANUAL")
End Sub


' ============================================================================
' MODE 2 / 3 - ONE SELECTED LINE -> SAME OCCURRENCE PARALLEL PAIR
' ============================================================================

Sub RunAutoOccurrenceBisectorProbe( _
    drawDoc As DrawingDocument, _
    sheet As Sheet, _
    requestedKind As String)

    Dim selected As List(Of DrawingCurveSegment) = _
        GetSelectedStraightSegments(drawDoc)

    If selected.Count <> 1 Then
        MessageBox.Show( _
            "MODE " & If(requestedKind = "PIPE", "2", "3") & _
            " requires exactly ONE projected straight line selected." & vbCrLf & vbCrLf & _
            "Select one visible silhouette line on the " & requestedKind & ".", _
            "Centerline Probe")
        Exit Sub
    End If

    Dim seed As DrawingCurveSegment = selected.Item(0)
    Dim view As DrawingView = seed.Parent.Parent

    Dim occurrence As ComponentOccurrence = _
        GetContainingOccurrence(seed.Parent)

    If occurrence Is Nothing Then
        MessageBox.Show( _
            "Could not resolve the selected projected line back to an assembly occurrence." & _
            vbCrLf & _
            "Try MODE 1 first on two manually selected lines.", _
            "Centerline Probe")
        Exit Sub
    End If

    Dim companion As DrawingCurveSegment = _
        FindBestParallelCompanion(view, occurrence, seed)

    If companion Is Nothing Then
        MessageBox.Show( _
            "No suitable parallel opposite projected line was found in occurrence:" & _
            vbCrLf & occurrence.Name, _
            "Centerline Probe")
        Exit Sub
    End If

    Dim alignment As Double = SegmentParallelAlignment(seed, companion)
    Dim offset As Double = ParallelLineSeparation(seed, companion)
    Dim overlap As Double = AxisOverlapRatio(seed, companion)

    Logger.Info( _
        "AUTO " & requestedKind & _
        " occurrence=" & occurrence.Name & _
        " | alignment=" & NumCL(alignment) & _
        " | separation=" & NumCL(offset) & _
        " | overlap=" & NumCL(overlap) & _
        " | seedLength=" & NumCL(SegmentLength(seed)) & _
        " | mateLength=" & NumCL(SegmentLength(companion)))

    ' Highlight exactly the pair that the rule intends to bisect.
    Try
        drawDoc.SelectSet.Clear()
        drawDoc.SelectSet.Select(seed)
        drawDoc.SelectSet.Select(companion)
    Catch
    End Try

    Dim answer As DialogResult = _
        MessageBox.Show( _
            "AUTO " & requestedKind & " candidate pair has been highlighted." & _
            vbCrLf & vbCrLf & _
            "Occurrence: " & occurrence.Name & vbCrLf & _
            "Alignment: " & NumCL(alignment) & vbCrLf & _
            "Separation: " & NumCL(offset) & " cm on sheet" & vbCrLf & _
            "Axial overlap: " & NumCL(overlap) & vbCrLf & vbCrLf & _
            "Check visually that these are the TWO opposite silhouette lines." & _
            vbCrLf & _
            "Press Yes only if the highlighted pair is correct.", _
            "Centerline Probe - AUTO " & requestedKind, _
            MessageBoxButtons.YesNo, _
            MessageBoxIcon.Warning)

    If answer <> DialogResult.Yes Then Exit Sub

    CreateBisectorFromSegments(sheet, seed, companion, "AUTO_" & requestedKind)
End Sub


' ============================================================================
' MODE 4 - TWO CROSS/END LINES -> MIDPOINTS -> Centerlines.Add
' This deliberately avoids AddBisector.
' ============================================================================

Sub RunRegularCenterlineProbe( _
    drawDoc As DrawingDocument, _
    sheet As Sheet)

    Dim selected As List(Of DrawingCurveSegment) = _
        GetSelectedStraightSegments(drawDoc)

    If selected.Count <> 2 Then
        MessageBox.Show( _
            "MODE 4 requires exactly TWO projected straight CROSS/END lines." & _
            vbCrLf & vbCrLf & _
            "Their midpoints must both lie on the desired pipe axis." & vbCrLf & _
            "Example: select the pipe's left end-face line and right end-face line.", _
            "Centerline Probe")
        Exit Sub
    End If

    Dim a As DrawingCurveSegment = selected.Item(0)
    Dim b As DrawingCurveSegment = selected.Item(1)

    If a.Parent.Parent IsNot b.Parent.Parent Then
        MessageBox.Show("The two lines belong to different views.", "Centerline Probe")
        Exit Sub
    End If

    Dim alignment As Double = SegmentParallelAlignment(a, b)

    If alignment < 0.98 Then
        MessageBox.Show( _
            "For MODE 4 the two end/cross lines should be parallel." & vbCrLf & _
            "Alignment = " & NumCL(alignment), _
            "Centerline Probe")
        Exit Sub
    End If

    Dim answer As DialogResult = _
        MessageBox.Show( _
            "MODE 4 does NOT use AddBisector." & vbCrLf & vbCrLf & _
            "It will create a native Inventor regular centerline through the MIDPOINTS " & _
            "of the two selected projected lines using Centerlines.Add." & vbCrLf & vbCrLf & _
            "Continue?", _
            "Centerline Probe - MODE 4", _
            MessageBoxButtons.YesNo, _
            MessageBoxIcon.Information)

    If answer <> DialogResult.Yes Then Exit Sub

    Try
        Dim intentA As GeometryIntent = _
            sheet.CreateGeometryIntent( _
                a.Parent, _
                PointIntentEnum.kMidPointIntent)

        Dim intentB As GeometryIntent = _
            sheet.CreateGeometryIntent( _
                b.Parent, _
                PointIntentEnum.kMidPointIntent)

        Dim entities As ObjectCollection = _
            ThisApplication.TransientObjects.CreateObjectCollection()

        entities.Add(intentA)
        entities.Add(intentB)

        Logger.Info("MODE4 immediately before Centerlines.Add")

        Dim cl As Centerline = _
            sheet.Centerlines.Add(entities)

        Logger.Info("MODE4 Centerlines.Add returned successfully")

        TagProbeCenterline(cl, "REGULAR_MIDPOINT")

        MessageBox.Show( _
            "SUCCESS: regular native centerline created without AddBisector.", _
            "Centerline Probe")

    Catch ex As Exception
        Logger.Error("MODE4 Centerlines.Add failed: " & ex.ToString())
        MessageBox.Show( _
            "MODE 4 failed:" & vbCrLf & vbCrLf & ex.Message, _
            "Centerline Probe")
    End Try
End Sub


' ============================================================================
' NATIVE BISECTOR CALL - ONLY PLACE AddBisector EXISTS IN THIS FILE
' ============================================================================

Sub CreateBisectorFromSegments( _
    sheet As Sheet, _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment, _
    source As String)

    Try
        Dim intentA As GeometryIntent = _
            sheet.CreateGeometryIntent(a.Parent)

        Dim intentB As GeometryIntent = _
            sheet.CreateGeometryIntent(b.Parent)

        Logger.Info(source & " immediately before Centerlines.AddBisector")

        Dim cl As Centerline = _
            sheet.Centerlines.AddBisector( _
                intentA, _
                intentB)

        Logger.Info(source & " Centerlines.AddBisector returned successfully")

        TagProbeCenterline(cl, source)

        MessageBox.Show( _
            "SUCCESS: native bisector centerline created." & vbCrLf & _
            "Source: " & source, _
            "Centerline Probe")

    Catch ex As Exception
        Logger.Error(source & " AddBisector failed: " & ex.ToString())
        MessageBox.Show( _
            "AddBisector returned an exception:" & vbCrLf & vbCrLf & ex.Message, _
            "Centerline Probe")
    End Try
End Sub


' ============================================================================
' SELECTION / OCCURRENCE HELPERS
' ============================================================================

Function GetSelectedStraightSegments( _
    drawDoc As DrawingDocument) As List(Of DrawingCurveSegment)

    Dim result As New List(Of DrawingCurveSegment)

    For Each selectedObject As Object In drawDoc.SelectSet
        If TypeOf selectedObject Is DrawingCurveSegment Then
            Dim seg As DrawingCurveSegment = _
                CType(selectedObject, DrawingCurveSegment)

            If IsStraightVisibleSegment(seg) Then
                result.Add(seg)
            End If
        End If
    Next

    Return result
End Function


Function GetContainingOccurrence( _
    curve As DrawingCurve) As ComponentOccurrence

    If curve Is Nothing Then Return Nothing

    Try
        Dim modelGeometry As Object = curve.ModelGeometry

        If modelGeometry Is Nothing Then Return Nothing

        If TypeOf modelGeometry Is EdgeProxy Then
            Return CType(modelGeometry, EdgeProxy).ContainingOccurrence
        End If

        ' Some projected entities can resolve as other proxy types.
        ' Use late binding only for the read-only ContainingOccurrence property.
        Try
            Dim occurrence As Object = _
                Microsoft.VisualBasic.CallByName( _
                    modelGeometry, _
                    "ContainingOccurrence", _
                    Microsoft.VisualBasic.CallType.Get)

            Return TryCast(occurrence, ComponentOccurrence)
        Catch
        End Try

    Catch ex As Exception
        Logger.Error("GetContainingOccurrence: " & ex.Message)
    End Try

    Return Nothing
End Function


Function FindBestParallelCompanion( _
    view As DrawingView, _
    occurrence As ComponentOccurrence, _
    seed As DrawingCurveSegment) As DrawingCurveSegment

    Dim curves As DrawingCurvesEnumerator = Nothing

    Try
        curves = view.DrawingCurves(occurrence)
    Catch ex As Exception
        Logger.Error("DrawingCurves(occurrence) failed: " & ex.Message)
        Return Nothing
    End Try

    If curves Is Nothing Then Return Nothing

    Dim best As DrawingCurveSegment = Nothing
    Dim bestScore As Double = Double.MaxValue
    Dim seedLength As Double = SegmentLength(seed)

    For Each curve As DrawingCurve In curves
        For Each candidate As DrawingCurveSegment In curve.Segments

            If candidate Is seed Then Continue For
            If Not IsStraightVisibleSegment(candidate) Then Continue For

            Dim alignment As Double = _
                SegmentParallelAlignment(seed, candidate)

            If alignment < 0.995 Then Continue For

            Dim separation As Double = _
                ParallelLineSeparation(seed, candidate)

            If separation < 0.02 Then Continue For

            Dim overlap As Double = _
                AxisOverlapRatio(seed, candidate)

            If overlap < 0.45 Then Continue For

            Dim candidateLength As Double = SegmentLength(candidate)
            If seedLength < 0.0001 OrElse candidateLength < 0.0001 Then Continue For

            Dim lengthRatioError As Double = _
                Math.Abs(candidateLength - seedLength) / _
                Math.Max(candidateLength, seedLength)

            ' Prefer nearly identical, strongly overlapping parallel silhouettes.
            ' Separation itself is not minimized strongly because it represents
            ' the physical pipe/flange width we are trying to bisect.
            Dim score As Double = _
                (1.0 - alignment) * 100.0 + _
                (1.0 - overlap) * 5.0 + _
                lengthRatioError * 3.0

            If score < bestScore Then
                bestScore = score
                best = candidate
            End If

        Next
    Next

    If best IsNot Nothing Then
        Logger.Info("Best parallel companion score=" & NumCL(bestScore))
    End If

    Return best
End Function


Function IsStraightVisibleSegment( _
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

        Return SegmentLength(seg) > 0.02

    Catch
        Return False
    End Try
End Function


' ============================================================================
' 2D GEOMETRY HELPERS
' ============================================================================

Function SegmentLength( _
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


Function SegmentParallelAlignment( _
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


Function ParallelLineSeparation( _
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


Function AxisOverlapRatio( _
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

    Dim overlap As Double = Math.Max(0, Math.Min(a1, b1) - Math.Max(a0, b0))
    Dim denom As Double = Math.Min(a1 - a0, b1 - b0)

    If denom < 0.000001 Then Return 0
    Return overlap / denom
End Function


' ============================================================================
' TAGGING / FORMAT HELPERS
' ============================================================================

Sub TagProbeCenterline( _
    cl As Centerline, _
    source As String)

    If cl Is Nothing Then Exit Sub

    Try
        Dim tags As AttributeSet = _
            cl.AttributeSets.Add("CenterlineProbe")
        tags.Add("Source", ValueTypeEnum.kStringType, source)
    Catch
    End Try
End Sub


Function NumCL(value As Double) As String
    Return value.ToString("0.###", Globalization.CultureInfo.InvariantCulture)
End Function
