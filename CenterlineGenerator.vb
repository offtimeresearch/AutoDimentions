AddReference "System.Windows.Forms.dll"

Imports System
Imports System.Collections.Generic
Imports System.Globalization
Imports System.Text.RegularExpressions
Imports System.Windows.Forms

' ============================================================================
' CENTERLINE GENERATOR V0.2
' ----------------------------------------------------------------------------
' PURPOSE
'   Create native Inventor drawing centerlines for straight PIPE and FLANGE
'   occurrences using TWO REAL topology-known port points and Centerlines.Add.
'
' WHY V0.2
'   - CenterlineProbe proved Centerlines.Add is stable in the user's Inventor.
'   - No AddBisector is used anywhere in this file.
'   - No silhouette-line pair guessing is used.
'   - No centerline/centerline intersection intent is created.
'   - No elbow or tee geometry is used to create centerlines.
'
' METHOD
'   1. Find real planar circular port faces on a PIPE / FLANGE occurrence.
'   2. Choose two coaxial, axis-aligned, well-separated port faces.
'   3. Resolve each port to a real drawing point intent:
'        line projection   -> midpoint intent
'        circle/ellipse    -> center-point intent
'   4. Pass those TWO point intents to Sheet.Centerlines.Add.
'
' NOTES
'   - For pipes this normally uses the two end-port faces.
'   - For flanges it normally uses the two farthest coaxial circular faces.
'   - Candidate selection strongly prefers the largest circular radius so bolt
'     holes do not win over the actual pipe/flange bore/OD axis.
'   - DimensionGenerator remains independent from centerline creation.
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
            MessageBox.Show( _
                "CenterlineGenerator currently expects an assembly drawing view.", _
                "Centerline Generator")
            Exit Sub
        End If

        Dim answer As DialogResult = _
            MessageBox.Show( _
                "CenterlineGenerator V0.2 will regenerate centerlines ONLY for PIPE and FLANGE occurrences." & _
                vbCrLf & vbCrLf & _
                "V0.2 uses two real projected port points + Centerlines.Add." & vbCrLf & _
                "It does NOT use AddBisector or elbow/tee geometry." & _
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

            Dim ports As List(Of PortCandidateCL) = _
                GetPortCandidatesCL(occ)

            If ports.Count < 2 Then
                Logger.Info( _
                    "CENTERLINE SKIP " & kind & " | " & occ.Name & _
                    " | usable circular port faces=" & ports.Count.ToString())
                skipped += 1
                Continue For
            End If

            Dim pair As PortPairCL = _
                FindBestPortPairCL(view, ports)

            If pair Is Nothing Then
                Logger.Info( _
                    "CENTERLINE SKIP " & kind & " | " & occ.Name & _
                    " | no coaxial visible real-port pair")
                skipped += 1
                Continue For
            End If

            Logger.Info( _
                "CENTERLINE PORT_PAIR " & kind & " | " & occ.Name & _
                " | faceA=" & pair.A.FaceIndex.ToString() & _
                " faceB=" & pair.B.FaceIndex.ToString() & _
                " | radiusA_cm=" & NumCL(pair.A.Radius) & _
                " radiusB_cm=" & NumCL(pair.B.Radius) & _
                " | axial_cm=" & NumCL(pair.AxialDistance) & _
                " | lateral_cm=" & NumCL(pair.LateralDistance) & _
                " | sheetSpan_cm=" & NumCL(pair.SheetDistance))

            Dim intentA As GeometryIntent = _
                FindPortPointIntentCL(sheet, view, occ, pair.A)

            Dim intentB As GeometryIntent = _
                FindPortPointIntentCL(sheet, view, occ, pair.B)

            If intentA Is Nothing OrElse intentB Is Nothing Then
                Logger.Error( _
                    "CENTERLINE SKIP " & kind & " | " & occ.Name & _
                    " | real port point intent missing")
                skipped += 1
                Continue For
            End If

            If CreateRegularPortCenterlineCL( _
                sheet, occ, kind, pair, intentA, intentB) Then

                created += 1
            Else
                skipped += 1
            End If

        Next

        Try
            drawDoc.Update2(True)
        Catch
            Try : drawDoc.Update() : Catch : End Try
        End Try

        MessageBox.Show( _
            "CenterlineGenerator V0.2 finished." & vbCrLf & vbCrLf & _
            "View: " & view.Name & vbCrLf & _
            "Pipe occurrences checked: " & pipeAttempts.ToString() & vbCrLf & _
            "Flange occurrences checked: " & flangeAttempts.ToString() & vbCrLf & _
            "Centerlines created: " & created.ToString() & vbCrLf & _
            "Skipped: " & skipped.ToString() & vbCrLf & vbCrLf & _
            "No tee or elbow centerlines were generated.", _
            "Centerline Generator")

    Catch ex As Exception
        Logger.Error("CenterlineGenerator V0.2 fatal: " & ex.ToString())
        MessageBox.Show( _
            "CenterlineGenerator V0.2 failed:" & vbCrLf & vbCrLf & ex.Message, _
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
' REAL PORT FACE SCAN
' ============================================================================

Function GetPortCandidatesCL( _
    occ As ComponentOccurrence) As List(Of PortCandidateCL)

    Dim result As New List(Of PortCandidateCL)
    Dim faceIndex As Integer = 0

    Try
        For Each body As SurfaceBody In occ.SurfaceBodies
            For Each face As Face In body.Faces

                faceIndex += 1

                If face.SurfaceType <> SurfaceTypeEnum.kPlaneSurface Then
                    Continue For
                End If

                Dim biggestCircle As Inventor.Circle = Nothing

                For Each edge As Edge In face.Edges
                    Try
                        If edge.GeometryType <> CurveTypeEnum.kCircleCurve Then
                            Continue For
                        End If

                        Dim circle As Inventor.Circle = _
                            CType(edge.Geometry, Inventor.Circle)

                        If biggestCircle Is Nothing OrElse _
                           circle.Radius > biggestCircle.Radius Then
                            biggestCircle = circle
                        End If
                    Catch
                    End Try
                Next

                If biggestCircle Is Nothing Then Continue For

                Dim plane As Inventor.Plane = Nothing
                Try
                    plane = CType(face.Geometry, Inventor.Plane)
                Catch
                    Continue For
                End Try

                Dim p As New PortCandidateCL
                p.FaceIndex = faceIndex
                p.ModelFace = face

                ' Occurrence proxy geometry is in assembly database units (cm).
                p.X = biggestCircle.Center.X
                p.Y = biggestCircle.Center.Y
                p.Z = biggestCircle.Center.Z
                p.Radius = biggestCircle.Radius

                p.NX = plane.Normal.X
                p.NY = plane.Normal.Y
                p.NZ = plane.Normal.Z

                Try
                    If face.IsParamReversed Then
                        p.NX *= -1.0
                        p.NY *= -1.0
                        p.NZ *= -1.0
                    End If
                Catch
                End Try

                Normalize3CL(p.NX, p.NY, p.NZ)

                If VectorLength3CL(p.NX, p.NY, p.NZ) < 0.5 Then
                    Continue For
                End If

                AddPortCandidateIfUniqueCL(result, p)

            Next
        Next

    Catch ex As Exception
        Logger.Error("Port scan failed for " & occ.Name & ": " & ex.Message)
    End Try

    Return result
End Function


Sub AddPortCandidateIfUniqueCL( _
    ports As List(Of PortCandidateCL), _
    candidate As PortCandidateCL)

    For i As Integer = 0 To ports.Count - 1
        Dim existing As PortCandidateCL = ports.Item(i)

        Dim d As Double = _
            Dist3CL( _
                existing.X, existing.Y, existing.Z, _
                candidate.X, candidate.Y, candidate.Z)

        Dim dot As Double = _
            Math.Abs( _
                existing.NX * candidate.NX + _
                existing.NY * candidate.NY + _
                existing.NZ * candidate.NZ)

        ' Same physical station/axis: keep the face with the largest circular
        ' radius. This suppresses duplicate annular faces and bolt-hole details.
        If d < 0.01 AndAlso dot > 0.995 Then
            If candidate.Radius > existing.Radius Then
                ports.Item(i) = candidate
            End If
            Exit Sub
        End If
    Next

    ports.Add(candidate)
End Sub


' ============================================================================
' CHOOSE TWO COAXIAL REAL PORTS
' ============================================================================

Function FindBestPortPairCL( _
    view As DrawingView, _
    ports As List(Of PortCandidateCL)) As PortPairCL

    If ports Is Nothing OrElse ports.Count < 2 Then Return Nothing

    Dim best As PortPairCL = Nothing
    Dim bestScore As Double = -Double.MaxValue

    For i As Integer = 0 To ports.Count - 2
        For j As Integer = i + 1 To ports.Count - 1

            Dim a As PortCandidateCL = ports.Item(i)
            Dim b As PortCandidateCL = ports.Item(j)

            Dim normalAlignment As Double = _
                Math.Abs(a.NX * b.NX + a.NY * b.NY + a.NZ * b.NZ)

            If normalAlignment < 0.98 Then Continue For

            Dim dx As Double = b.X - a.X
            Dim dy As Double = b.Y - a.Y
            Dim dz As Double = b.Z - a.Z
            Dim total As Double = Math.Sqrt(dx * dx + dy * dy + dz * dz)

            If total < 0.05 Then Continue For

            Dim axial As Double = _
                Math.Abs(dx * a.NX + dy * a.NY + dz * a.NZ)

            If axial < 0.05 Then Continue For

            Dim lateral2 As Double = total * total - axial * axial
            If lateral2 < 0 Then lateral2 = 0
            Dim lateral As Double = Math.Sqrt(lateral2)

            ' 0.10 cm = 1 mm. Real pipe/flange ports should be essentially
            ' coaxial, so reject offset bolt-hole or unrelated circular faces.
            If lateral > 0.10 Then Continue For

            Dim sheetA As Point2d = ProjectPortCenterCL(view, a)
            Dim sheetB As Point2d = ProjectPortCenterCL(view, b)
            If sheetA Is Nothing OrElse sheetB Is Nothing Then Continue For

            Dim sheetDistance As Double = _
                Distance2CL(sheetA.X, sheetA.Y, sheetB.X, sheetB.Y)

            ' Axis is effectively normal to this drawing view.
            If sheetDistance < 0.03 Then Continue For

            Dim minRadius As Double = Math.Min(a.Radius, b.Radius)

            ' Primary preference: large circular geometry (real bore/OD rather
            ' than bolt holes). Secondary preference: long real axial span.
            Dim score As Double = _
                minRadius * 1000.0 + _
                axial * 10.0 + _
                sheetDistance - _
                lateral * 1000.0 + _
                normalAlignment

            If best Is Nothing OrElse score > bestScore Then
                bestScore = score
                best = New PortPairCL
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


Function ProjectPortCenterCL( _
    view As DrawingView, _
    port As PortCandidateCL) As Point2d

    If view Is Nothing OrElse port Is Nothing Then Return Nothing

    Try
        Dim modelPoint As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                port.X, port.Y, port.Z)

        Return view.ModelToSheetSpace(modelPoint)
    Catch
        Return Nothing
    End Try
End Function


' ============================================================================
' REAL DRAWING POINT INTENT FOR A PORT
' ============================================================================

Function FindPortPointIntentCL( _
    sheet As Sheet, _
    view As DrawingView, _
    occ As ComponentOccurrence, _
    port As PortCandidateCL) As GeometryIntent

    If sheet Is Nothing OrElse view Is Nothing OrElse _
       occ Is Nothing OrElse port Is Nothing Then
        Return Nothing
    End If

    Dim target As Point2d = ProjectPortCenterCL(view, port)
    If target Is Nothing Then Return Nothing

    ' First choice: drawing curves generated specifically from the real model
    ' face that topology identified as the port face.
    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(port.ModelFace)

        Dim intent As GeometryIntent = _
            BestPointIntentFromCurvesCL(sheet, curves, target, 0.30)

        If intent IsNot Nothing Then
            Logger.Info( _
                "PORT_INTENT FACE | " & occ.Name & _
                " | face=" & port.FaceIndex.ToString())
            Return intent
        End If
    Catch ex As Exception
        Logger.Info( _
            "PORT_INTENT face lookup fallback | " & occ.Name & _
            " face=" & port.FaceIndex.ToString() & _
            " | " & ex.Message)
    End Try

    ' Conservative fallback: only curves belonging to the SAME occurrence,
    ' and only point intents close to the topology-projected port center.
    Try
        Dim occurrenceCurves As DrawingCurvesEnumerator = _
            view.DrawingCurves(occ)

        Dim fallback As GeometryIntent = _
            BestPointIntentFromCurvesCL(sheet, occurrenceCurves, target, 0.18)

        If fallback IsNot Nothing Then
            Logger.Info( _
                "PORT_INTENT OCCURRENCE_FALLBACK | " & occ.Name & _
                " | face=" & port.FaceIndex.ToString())
            Return fallback
        End If
    Catch ex As Exception
        Logger.Error( _
            "PORT_INTENT occurrence lookup failed | " & occ.Name & _
            " | " & ex.Message)
    End Try

    Return Nothing
End Function


Function BestPointIntentFromCurvesCL( _
    sheet As Sheet, _
    curves As DrawingCurvesEnumerator, _
    target As Point2d, _
    maxDistance As Double) As GeometryIntent

    If curves Is Nothing OrElse target Is Nothing Then Return Nothing

    Dim bestCurve As DrawingCurve = Nothing
    Dim bestIntentType As Integer = 0
    Dim bestDistance As Double = maxDistance

    For Each curve As DrawingCurve In curves

        Try
            If curve.CurveType = CurveTypeEnum.kLineSegmentCurve AndAlso _
               curve.StartPoint IsNot Nothing AndAlso _
               curve.EndPoint IsNot Nothing Then

                Dim mx As Double = (curve.StartPoint.X + curve.EndPoint.X) / 2.0
                Dim my As Double = (curve.StartPoint.Y + curve.EndPoint.Y) / 2.0
                Dim d As Double = Distance2CL(mx, my, target.X, target.Y)

                If d <= bestDistance Then
                    bestDistance = d
                    bestCurve = curve
                    bestIntentType = 1   ' midpoint of a real line
                End If

            ElseIf _
                (curve.CurveType = CurveTypeEnum.kCircleCurve OrElse _
                 curve.CurveType = CurveTypeEnum.kCircularArcCurve OrElse _
                 curve.CurveType = CurveTypeEnum.kEllipseFullCurve OrElse _
                 curve.CurveType = CurveTypeEnum.kEllipticalArcCurve) AndAlso _
                 curve.CenterPoint IsNot Nothing Then

                Dim d As Double = _
                    Distance2CL( _
                        curve.CenterPoint.X, curve.CenterPoint.Y, _
                        target.X, target.Y)

                If d <= bestDistance Then
                    bestDistance = d
                    bestCurve = curve
                    bestIntentType = 2   ' center of real circular/elliptic curve
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
        Logger.Error("Creating real port point intent failed: " & ex.Message)
    End Try

    Return Nothing
End Function


' ============================================================================
' NATIVE REGULAR CENTERLINE - PROVEN MODE-4 MECHANISM
' ============================================================================

Function CreateRegularPortCenterlineCL( _
    sheet As Sheet, _
    occ As ComponentOccurrence, _
    kind As String, _
    pair As PortPairCL, _
    intentA As GeometryIntent, _
    intentB As GeometryIntent) As Boolean

    If sheet Is Nothing OrElse occ Is Nothing OrElse pair Is Nothing OrElse _
       intentA Is Nothing OrElse intentB Is Nothing Then
        Return False
    End If

    Try
        Dim points As ObjectCollection = _
            ThisApplication.TransientObjects.CreateObjectCollection()

        points.Add(intentA)
        points.Add(intentB)

        Logger.Info("CENTERLINES_ADD BEGIN " & kind & " | " & occ.Name)

        Dim cl As Centerline = _
            sheet.Centerlines.Add(points)

        Logger.Info("CENTERLINES_ADD RETURN " & kind & " | " & occ.Name)

        If cl Is Nothing Then Return False

        TagGeneratorCenterline(cl, occ, kind, pair)
        Return True

    Catch ex As Exception
        Logger.Error( _
            "Centerlines.Add exception " & kind & _
            " | " & occ.Name & _
            " | " & ex.Message)
        Return False
    End Try
End Function


Sub TagGeneratorCenterline( _
    cl As Centerline, _
    occ As ComponentOccurrence, _
    kind As String, _
    pair As PortPairCL)

    If cl Is Nothing Then Exit Sub

    Try
        Dim tags As AttributeSet = Nothing

        Try
            tags = cl.AttributeSets.Item("AutoSpoolCenterline")
        Catch
            tags = cl.AttributeSets.Add("AutoSpoolCenterline")
        End Try

        Try : tags.Add("Occurrence", ValueTypeEnum.kStringType, occ.Name) : Catch : End Try
        Try : tags.Add("ComponentType", ValueTypeEnum.kStringType, kind) : Catch : End Try
        Try : tags.Add("GeneratorVersion", ValueTypeEnum.kStringType, "0.2") : Catch : End Try
        Try : tags.Add("Method", ValueTypeEnum.kStringType, "REGULAR_PORT_POINTS") : Catch : End Try
        Try : tags.Add("FaceA", ValueTypeEnum.kIntegerType, pair.A.FaceIndex) : Catch : End Try
        Try : tags.Add("FaceB", ValueTypeEnum.kIntegerType, pair.B.FaceIndex) : Catch : End Try
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
' MATH / DATA
' ============================================================================

Sub Normalize3CL( _
    ByRef x As Double, _
    ByRef y As Double, _
    ByRef z As Double)

    Dim l As Double = VectorLength3CL(x, y, z)
    If l < 0.0000001 Then Exit Sub

    x /= l
    y /= l
    z /= l
End Sub


Function VectorLength3CL( _
    x As Double, _
    y As Double, _
    z As Double) As Double

    Return Math.Sqrt(x * x + y * y + z * z)
End Function


Function Dist3CL( _
    x1 As Double, y1 As Double, z1 As Double, _
    x2 As Double, y2 As Double, z2 As Double) As Double

    Dim dx As Double = x2 - x1
    Dim dy As Double = y2 - y1
    Dim dz As Double = z2 - z1
    Return Math.Sqrt(dx * dx + dy * dy + dz * dz)
End Function


Function Distance2CL( _
    x1 As Double, y1 As Double, _
    x2 As Double, y2 As Double) As Double

    Dim dx As Double = x2 - x1
    Dim dy As Double = y2 - y1
    Return Math.Sqrt(dx * dx + dy * dy)
End Function


Class PortCandidateCL
    Public FaceIndex As Integer
    Public ModelFace As Object = Nothing

    Public X As Double
    Public Y As Double
    Public Z As Double

    Public NX As Double
    Public NY As Double
    Public NZ As Double

    Public Radius As Double
End Class


Class PortPairCL
    Public A As PortCandidateCL = Nothing
    Public B As PortCandidateCL = Nothing

    Public NormalAlignment As Double
    Public AxialDistance As Double
    Public LateralDistance As Double
    Public SheetDistance As Double
    Public Score As Double
End Class


Function NumCL(value As Double) As String
    Return value.ToString("0.###", CultureInfo.InvariantCulture)
End Function
