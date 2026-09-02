AddReference "System.Windows.Forms.dll"

Imports System
Imports System.Collections.Generic
Imports System.Globalization
Imports System.Text.RegularExpressions
Imports System.Windows.Forms

' ============================================================================
' CENTERLINE GENERATOR V0.1
' ----------------------------------------------------------------------------
' PURPOSE
'   Create native Inventor drawing centerlines across one spool drawing view,
'   using ONLY the two automatic cases already proven safe in CenterlineProbe:
'
'       PIPE   -> opposite projected silhouette lines -> AddBisector
'       FLANGE -> opposite projected silhouette lines -> AddBisector
'
' SAFETY RULES
'   - No elbow geometry is ever passed to AddBisector.
'   - No tee geometry is passed to AddBisector in V0.1.
'   - Both lines must belong to the SAME occurrence.
'   - The occurrence 3D port axis is projected into the drawing view first.
'   - Only projected lines parallel to that known axis are eligible.
'   - No dimensions are created here.
'   - No centerline intersection intent is created here.
'   - No centerline StartPoint/EndPoint modification is done here.
'
' WORKFLOW
'   1. Run this rule on the drawing view.
'   2. Verify the PIPE and FLANGE centerlines visually.
'   3. DimensionGenerator will later reuse these native centerlines.
' ============================================================================

Sub Main()

    Try
        If ThisApplication.ActiveDocument.DocumentType <> _
           DocumentTypeEnum.kDrawingDocumentObject Then

            MessageBox.Show( _
                "Run CenterlineGenerator from an Inventor drawing.", _
                "Centerline Generator")
            Exit Sub
        End If

        Dim drawDoc As DrawingDocument = _
            CType(ThisApplication.ActiveDocument, DrawingDocument)

        Dim sheet As Sheet = drawDoc.ActiveSheet

        If sheet.DrawingViews.Count = 0 Then
            MessageBox.Show("The active sheet has no drawing views.", "Centerline Generator")
            Exit Sub
        End If

        Dim view As DrawingView = GetTargetView(drawDoc, sheet)
        If view Is Nothing Then
            MessageBox.Show("Could not determine the target drawing view.", "Centerline Generator")
            Exit Sub
        End If

        Dim descriptor As DocumentDescriptor = view.ReferencedDocumentDescriptor
        If descriptor Is Nothing OrElse descriptor.ReferenceMissing Then
            MessageBox.Show("The selected view has no resolved model reference.", "Centerline Generator")
            Exit Sub
        End If

        Dim asmDoc As AssemblyDocument = _
            TryCast(descriptor.ReferencedDocument, AssemblyDocument)

        If asmDoc Is Nothing Then
            MessageBox.Show("CenterlineGenerator currently expects an assembly drawing view.", "Centerline Generator")
            Exit Sub
        End If

        Dim answer As DialogResult = _
            MessageBox.Show( _
                "CenterlineGenerator V0.1 will create centerlines ONLY for PIPE and FLANGE occurrences." & _
                vbCrLf & vbCrLf & _
                "It uses the same occurrence-only AddBisector method that passed CenterlineProbe modes 2 and 3." & _
                vbCrLf & vbCrLf & _
                "Existing centerlines created by this rule will be removed and regenerated." & _
                vbCrLf & vbCrLf & _
                "Continue?", _
                "Centerline Generator", _
                MessageBoxButtons.YesNo, _
                MessageBoxIcon.Information)

        If answer <> DialogResult.Yes Then Exit Sub

        DeletePreviousGeneratorCenterlines(sheet)

        Dim occurrences As ComponentOccurrencesEnumerator = _
            asmDoc.ComponentDefinition.Occurrences.AllLeafOccurrences

        Dim pipeAttempts As Integer = 0
        Dim flangeAttempts As Integer = 0
        Dim created As Integer = 0
        Dim skipped As Integer = 0

        For Each occ As ComponentOccurrence In occurrences

            If occ Is Nothing Then Continue For

            Try
                If occ.Suppressed Then Continue For
            Catch
            End Try

            Dim kind As String = GuessOccurrenceType(occ)

            If kind <> "PIPE" AndAlso kind <> "FLANGE" Then
                Continue For
            End If

            If kind = "PIPE" Then
                pipeAttempts += 1
            Else
                flangeAttempts += 1
            End If

            Dim axis As Axis2DRecord = _
                GetPrimaryProjectedPortAxis(view, occ)

            If axis Is Nothing Then
                Logger.Info("CENTERLINE SKIP " & occ.Name & " | no visible projected port axis")
                skipped += 1
                Continue For
            End If

            Dim pair As LinePairRecord = _
                FindSafeOccurrencePair(view, occ, axis)

            If pair Is Nothing Then
                Logger.Info( _
                    "CENTERLINE SKIP " & occ.Name & _
                    " | no safe same-occurrence silhouette pair" & _
                    " | axis=" & NumCL(axis.UX) & "," & NumCL(axis.UY))
                skipped += 1
                Continue For
            End If

            Logger.Info( _
                "CENTERLINE PAIR " & kind & _
                " | " & occ.Name & _
                " | axis=" & NumCL(axis.UX) & "," & NumCL(axis.UY) & _
                " | alignment=" & NumCL(pair.Alignment) & _
                " | separation=" & NumCL(pair.Separation) & _
                " | overlap=" & NumCL(pair.Overlap) & _
                " | score=" & NumCL(pair.Score))

            If CreateOccurrenceBisector(sheet, occ, kind, pair) Then
                created += 1
            Else
                skipped += 1
            End If

        Next

        drawDoc.Update2(True)

        MessageBox.Show( _
            "CenterlineGenerator V0.1 finished." & vbCrLf & vbCrLf & _
            "View: " & view.Name & vbCrLf & _
            "Pipe occurrences checked: " & pipeAttempts.ToString() & vbCrLf & _
            "Flange occurrences checked: " & flangeAttempts.ToString() & vbCrLf & _
            "Centerlines created: " & created.ToString() & vbCrLf & _
            "Skipped: " & skipped.ToString() & vbCrLf & vbCrLf & _
            "No tee or elbow centerlines were generated.", _
            "Centerline Generator")

    Catch ex As Exception
        Logger.Error("CenterlineGenerator fatal: " & ex.ToString())
        MessageBox.Show( _
            "CenterlineGenerator failed:" & vbCrLf & vbCrLf & ex.Message, _
            "Centerline Generator")
    End Try

End Sub


' ============================================================================
' TARGET VIEW
' ============================================================================

Function GetTargetView( _
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


' ============================================================================
' OCCURRENCE CLASSIFICATION
' ============================================================================

Function GuessOccurrenceType(occ As ComponentOccurrence) As String

    Dim partNumber As String = ""
    Dim description As String = ""

    Try
        Dim doc As Document = occ.Definition.Document
        partNumber = GetIPropertyCL(doc, "Design Tracking Properties", "Part Number")
        description = GetIPropertyCL(doc, "Design Tracking Properties", "Description")
    Catch
    End Try

    Dim text As String = _
        (partNumber & " " & description & " " & occ.Name).ToLowerInvariant()

    If Regex.IsMatch(text, "\bflange\b") Then Return "FLANGE"
    If Regex.IsMatch(text, "\b(pipe|tube)\b") Then Return "PIPE"
    If Regex.IsMatch(text, "\btee\b") Then Return "TEE"
    If Regex.IsMatch(text, "\b(elbow|bend)\b") Then Return "ELBOW"

    Return "OTHER"
End Function


Function GetIPropertyCL( _
    doc As Document, _
    propertySetName As String, _
    propertyName As String) As String

    Try
        Return _
            doc.PropertySets _
               .Item(propertySetName) _
               .Item(propertyName) _
               .Value.ToString().Trim()
    Catch
        Return ""
    End Try
End Function


' ============================================================================
' KNOWN 3D PORT AXIS -> 2D DRAWING AXIS
' ============================================================================

Function GetPrimaryProjectedPortAxis( _
    view As DrawingView, _
    occ As ComponentOccurrence) As Axis2DRecord

    Dim axes As New List(Of Axis2DRecord)

    Try
        For Each body As SurfaceBody In occ.SurfaceBodies
            For Each face As Face In body.Faces

                If face.SurfaceType <> SurfaceTypeEnum.kPlaneSurface Then
                    Continue For
                End If

                Dim circularEdge As Edge = Nothing

                For Each edge As Edge In face.Edges
                    Try
                        If edge.GeometryType = CurveTypeEnum.kCircleCurve Then
                            circularEdge = edge
                            Exit For
                        End If
                    Catch
                    End Try
                Next

                If circularEdge Is Nothing Then Continue For

                Dim plane As Inventor.Plane = Nothing
                Try
                    plane = CType(face.Geometry, Inventor.Plane)
                Catch
                    Continue For
                End Try

                Dim circle As Inventor.Circle = Nothing
                Try
                    circle = CType(circularEdge.Geometry, Inventor.Circle)
                Catch
                    Continue For
                End Try

                Dim nx As Double = plane.Normal.X
                Dim ny As Double = plane.Normal.Y
                Dim nz As Double = plane.Normal.Z

                Try
                    If face.IsParamReversed Then
                        nx *= -1.0
                        ny *= -1.0
                        nz *= -1.0
                    End If
                Catch
                End Try

                Dim p0 As Inventor.Point = _
                    ThisApplication.TransientGeometry.CreatePoint( _
                        circle.Center.X, _
                        circle.Center.Y, _
                        circle.Center.Z)

                Dim p1 As Inventor.Point = _
                    ThisApplication.TransientGeometry.CreatePoint( _
                        circle.Center.X + nx * 10.0, _
                        circle.Center.Y + ny * 10.0, _
                        circle.Center.Z + nz * 10.0)

                Dim s0 As Point2d = view.ModelToSheetSpace(p0)
                Dim s1 As Point2d = view.ModelToSheetSpace(p1)

                Dim ux As Double = s1.X - s0.X
                Dim uy As Double = s1.Y - s0.Y
                Dim length As Double = Math.Sqrt(ux * ux + uy * uy)

                ' Axis nearly normal to this drawing view.
                If length < 0.02 Then Continue For

                ux /= length
                uy /= length

                NormalizeDirectionSignCL(ux, uy)

                Dim duplicate As Boolean = False
                For Each existing As Axis2DRecord In axes
                    Dim alignment As Double = _
                        Math.Abs(existing.UX * ux + existing.UY * uy)
                    If alignment > 0.995 Then
                        duplicate = True
                        Exit For
                    End If
                Next

                If Not duplicate Then
                    Dim axis As New Axis2DRecord
                    axis.UX = ux
                    axis.UY = uy
                    axes.Add(axis)
                End If

            Next
        Next

    Catch ex As Exception
        Logger.Error("GetPrimaryProjectedPortAxis " & occ.Name & ": " & ex.Message)
    End Try

    If axes.Count = 0 Then Return Nothing

    ' PIPE and FLANGE should have one principal port axis in a useful side view.
    ' If several candidates survive, choose the direction that has the strongest
    ' safe silhouette pair in the occurrence.
    Dim bestAxis As Axis2DRecord = Nothing
    Dim bestScore As Double = Double.MaxValue

    For Each axis As Axis2DRecord In axes
        Dim pair As LinePairRecord = FindSafeOccurrencePair(view, occ, axis)
        If pair IsNot Nothing AndAlso pair.Score < bestScore Then
            bestScore = pair.Score
            bestAxis = axis
        End If
    Next

    If bestAxis IsNot Nothing Then Return bestAxis
    Return axes.Item(0)
End Function


Sub NormalizeDirectionSignCL( _
    ByRef ux As Double, _
    ByRef uy As Double)

    If ux < -0.000001 OrElse _
       (Math.Abs(ux) <= 0.000001 AndAlso uy < 0) Then
        ux *= -1.0
        uy *= -1.0
    End If
End Sub


' ============================================================================
' EXACT SAME SAFE OCCURRENCE-ONLY PRINCIPLE AS CENTERLINE PROBE
' ============================================================================

Function FindSafeOccurrencePair( _
    view As DrawingView, _
    occ As ComponentOccurrence, _
    axis As Axis2DRecord) As LinePairRecord

    If axis Is Nothing Then Return Nothing

    Dim curves As DrawingCurvesEnumerator = Nothing

    Try
        curves = view.DrawingCurves(occ)
    Catch ex As Exception
        Logger.Error("DrawingCurves(" & occ.Name & ") failed: " & ex.Message)
        Return Nothing
    End Try

    If curves Is Nothing Then Return Nothing

    Dim lines As New List(Of DrawingCurveSegment)

    For Each curve As DrawingCurve In curves
        For Each seg As DrawingCurveSegment In curve.Segments
            If Not IsStraightVisibleSegmentCL(seg) Then Continue For

            Dim alignmentToAxis As Double = _
                SegmentAxisAlignmentCL(seg, axis.UX, axis.UY)

            If alignmentToAxis < 0.995 Then Continue For

            lines.Add(seg)
        Next
    Next

    If lines.Count < 2 Then Return Nothing

    Dim best As LinePairRecord = Nothing

    For i As Integer = 0 To lines.Count - 2
        For j As Integer = i + 1 To lines.Count - 1

            Dim a As DrawingCurveSegment = lines.Item(i)
            Dim b As DrawingCurveSegment = lines.Item(j)

            Dim alignment As Double = SegmentParallelAlignmentCL(a, b)
            If alignment < 0.995 Then Continue For

            Dim separation As Double = ParallelLineSeparationCL(a, b)
            If separation < 0.02 Then Continue For

            Dim overlap As Double = AxisOverlapRatioCL(a, b)
            If overlap < 0.45 Then Continue For

            Dim lengthA As Double = SegmentLengthCL(a)
            Dim lengthB As Double = SegmentLengthCL(b)
            If lengthA < 0.02 OrElse lengthB < 0.02 Then Continue For

            Dim lengthRatioError As Double = _
                Math.Abs(lengthA - lengthB) / Math.Max(lengthA, lengthB)

            ' Same philosophy as the successful CenterlineProbe auto modes:
            ' very parallel + strong overlap + similar lengths.
            ' A small reward for long lines makes PIPE silhouettes win over
            ' tiny detail/end lines when several pairs are possible.
            Dim averageLength As Double = (lengthA + lengthB) / 2.0

            Dim score As Double = _
                (1.0 - alignment) * 100.0 + _
                (1.0 - overlap) * 5.0 + _
                lengthRatioError * 3.0 - _
                Math.Min(averageLength, 20.0) * 0.02

            If best Is Nothing OrElse score < best.Score Then
                best = New LinePairRecord
                best.A = a
                best.B = b
                best.Alignment = alignment
                best.Separation = separation
                best.Overlap = overlap
                best.Score = score
            End If

        Next
    Next

    Return best
End Function


Function IsStraightVisibleSegmentCL( _
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

        Return SegmentLengthCL(seg) > 0.02

    Catch
        Return False
    End Try
End Function


Function SegmentAxisAlignmentCL( _
    seg As DrawingCurveSegment, _
    ux As Double, _
    uy As Double) As Double

    Dim sx As Double = seg.EndPoint.X - seg.StartPoint.X
    Dim sy As Double = seg.EndPoint.Y - seg.StartPoint.Y
    Dim sl As Double = Math.Sqrt(sx * sx + sy * sy)

    If sl < 0.000001 Then Return 0

    sx /= sl
    sy /= sl

    Return Math.Abs(sx * ux + sy * uy)
End Function


Function SegmentParallelAlignmentCL( _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment) As Double

    Dim aux As Double = a.EndPoint.X - a.StartPoint.X
    Dim auy As Double = a.EndPoint.Y - a.StartPoint.Y
    Dim bux As Double = b.EndPoint.X - b.StartPoint.X
    Dim buy As Double = b.EndPoint.Y - b.StartPoint.Y

    Dim al As Double = Math.Sqrt(aux * aux + auy * auy)
    Dim bl As Double = Math.Sqrt(bux * bux + buy * buy)

    If al < 0.000001 OrElse bl < 0.000001 Then Return 0

    aux /= al
    auy /= al
    bux /= bl
    buy /= bl

    Return Math.Abs(aux * bux + auy * buy)
End Function


Function ParallelLineSeparationCL( _
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


Function AxisOverlapRatioCL( _
    a As DrawingCurveSegment, _
    b As DrawingCurveSegment) As Double

    Dim ux As Double = a.EndPoint.X - a.StartPoint.X
    Dim uy As Double = a.EndPoint.Y - a.StartPoint.Y
    Dim l As Double = Math.Sqrt(ux * ux + uy * uy)

    If l < 0.000001 Then Return 0

    ux /= l
    uy /= l

    Dim a0 As Double = a.StartPoint.X * ux + a.StartPoint.Y * uy
    Dim a1 As Double = a.EndPoint.X * ux + a.EndPoint.Y * uy
    Dim b0 As Double = b.StartPoint.X * ux + b.StartPoint.Y * uy
    Dim b1 As Double = b.EndPoint.X * ux + b.EndPoint.Y * uy

    If a1 < a0 Then
        Dim t As Double = a0
        a0 = a1
        a1 = t
    End If

    If b1 < b0 Then
        Dim t As Double = b0
        b0 = b1
        b1 = t
    End If

    Dim overlap As Double = _
        Math.Max(0, Math.Min(a1, b1) - Math.Max(a0, b0))

    Dim denom As Double = Math.Min(a1 - a0, b1 - b0)
    If denom < 0.000001 Then Return 0

    Return overlap / denom
End Function


Function SegmentLengthCL(seg As DrawingCurveSegment) As Double

    If seg Is Nothing OrElse _
       seg.StartPoint Is Nothing OrElse _
       seg.EndPoint Is Nothing Then
        Return 0
    End If

    Dim dx As Double = seg.EndPoint.X - seg.StartPoint.X
    Dim dy As Double = seg.EndPoint.Y - seg.StartPoint.Y

    Return Math.Sqrt(dx * dx + dy * dy)
End Function


' ============================================================================
' NATIVE CENTERLINE CREATION
' ============================================================================

Function CreateOccurrenceBisector( _
    sheet As Sheet, _
    occ As ComponentOccurrence, _
    kind As String, _
    pair As LinePairRecord) As Boolean

    If pair Is Nothing OrElse pair.A Is Nothing OrElse pair.B Is Nothing Then
        Return False
    End If

    Try
        Dim intentA As GeometryIntent = _
            sheet.CreateGeometryIntent(pair.A.Parent)

        Dim intentB As GeometryIntent = _
            sheet.CreateGeometryIntent(pair.B.Parent)

        Logger.Info("ADD_BISECTOR BEGIN " & kind & " | " & occ.Name)

        Dim cl As Centerline = _
            sheet.Centerlines.AddBisector(intentA, intentB)

        Logger.Info("ADD_BISECTOR RETURN " & kind & " | " & occ.Name)

        If cl Is Nothing Then Return False

        TagGeneratorCenterline(cl, occ, kind)
        Return True

    Catch ex As Exception
        Logger.Error( _
            "AddBisector exception " & kind & _
            " | " & occ.Name & _
            " | " & ex.Message)
        Return False
    End Try
End Function


Sub TagGeneratorCenterline( _
    cl As Centerline, _
    occ As ComponentOccurrence, _
    kind As String)

    If cl Is Nothing Then Exit Sub

    Try
        Dim tags As AttributeSet = _
            cl.AttributeSets.Add("AutoSpoolCenterline")

        tags.Add("Occurrence", ValueTypeEnum.kStringType, occ.Name)
        tags.Add("ComponentType", ValueTypeEnum.kStringType, kind)
        tags.Add("GeneratorVersion", ValueTypeEnum.kStringType, "0.1")
    Catch
    End Try
End Sub


Sub DeletePreviousGeneratorCenterlines(sheet As Sheet)

    Try
        For i As Integer = sheet.Centerlines.Count To 1 Step -1
            Dim cl As Centerline = sheet.Centerlines.Item(i)

            Try
                Dim tags As AttributeSet = _
                    cl.AttributeSets.Item("AutoSpoolCenterline")

                If tags IsNot Nothing Then
                    cl.Delete()
                End If
            Catch
            End Try
        Next
    Catch
    End Try
End Sub


' ============================================================================
' DATA / FORMAT
' ============================================================================

Class Axis2DRecord
    Public UX As Double
    Public UY As Double
End Class


Class LinePairRecord
    Public A As DrawingCurveSegment = Nothing
    Public B As DrawingCurveSegment = Nothing
    Public Alignment As Double
    Public Separation As Double
    Public Overlap As Double
    Public Score As Double
End Class


Function NumCL(value As Double) As String
    Return value.ToString("0.###", CultureInfo.InvariantCulture)
End Function
