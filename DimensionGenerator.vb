AddReference "System.Windows.Forms.dll"

Imports System
Imports System.Text
Imports System.Text.RegularExpressions
Imports System.Collections.Generic
Imports System.Globalization
Imports System.Windows.Forms


Sub Main()

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


        Dim unresolvedAnchors As Integer = _
            ResolveProjectedAnchorsV03( _
                sheet, _
                view, _
                nodes, _
                allAnchors)

        Logger.Info( _
            "Projected semantic anchors: " & _
            (allAnchors.Count - unresolvedAnchors).ToString() & _
            "/" & allAnchors.Count.ToString())


        Dim chainCount As Integer = _
            CreateChainDimensionsV01( _
                sheet, _
                chainRequests)

        Dim overallCount As Integer = _
            CreateOverallDimensionsV01( _
                sheet, _
                chainRequests)

        Dim attachmentCount As Integer = 0
        Logger.Info("V0.5 staged mode: attachment dimensions remain deferred until topology-guided fitting centerlines are verified.")


        drawDoc.Update2(True)


        MessageBox.Show( _
            "Auto dimensions created." & vbCrLf & vbCrLf & _
            "View: " & view.Name & vbCrLf & _
            "Chain dimension sets / fallback dims: " & chainCount.ToString() & vbCrLf & _
            "Overall dimensions: " & overallCount.ToString() & vbCrLf & _
            "Attachment dimensions/sets: " & attachmentCount.ToString(), _
            "DimensionGenerator V0.5")


    Catch ex As Exception

        MessageBox.Show( _
            "DimensionGenerator V0.5 failed:" & vbCrLf & vbCrLf & _
            ex.Message, _
            "Auto Dimensions")

        Logger.Error(ex.ToString())

    End Try

End Sub


' ===================================================================
' SCAN ASSEMBLY
' ===================================================================

Function ScanAssembly( _
    asmDoc As AssemblyDocument) As List(Of NodeRecord)


    Dim result As New List(Of NodeRecord)

    Dim occurrences As ComponentOccurrencesEnumerator = _
        asmDoc.ComponentDefinition.Occurrences.AllLeafOccurrences


    For Each occ As ComponentOccurrence In occurrences

        Try

            If occ.Suppressed Then
                Continue For
            End If


            Dim node As New NodeRecord

            node.OccurrenceName = occ.Name
            node.Occurrence = occ


            Dim refDoc As Document = Nothing


            Try
                refDoc = occ.Definition.Document
            Catch
            End Try


            If refDoc IsNot Nothing Then

                node.PartNumber = _
                    GetIProperty( _
                        refDoc, _
                        "Design Tracking Properties", _
                        "Part Number")

                node.Description = _
                    GetIProperty( _
                        refDoc, _
                        "Design Tracking Properties", _
                        "Description")

            End If


            node.ComponentType = _
                GuessComponentType( _
                    node.PartNumber, _
                    node.Description, _
                    node.OccurrenceName)


            ' -------------------------------------------------------
            ' Occurrence center.
            ' Inventor database geometry length = cm.
            ' Convert to mm.
            ' -------------------------------------------------------

            Dim rb As Box = occ.RangeBox


            node.X = _
                ((rb.MinPoint.X + rb.MaxPoint.X) / 2.0) * 10.0

            node.Y = _
                ((rb.MinPoint.Y + rb.MaxPoint.Y) / 2.0) * 10.0

            node.Z = _
                ((rb.MinPoint.Z + rb.MaxPoint.Z) / 2.0) * 10.0


            ' -------------------------------------------------------
            ' Candidate piping ports:
            ' planar face + circular boundary
            ' -------------------------------------------------------

            Dim faceCounter As Integer = 0


            For Each body As SurfaceBody In occ.SurfaceBodies

                For Each face As Face In body.Faces

                    faceCounter += 1


                    If face.SurfaceType <> _
                       SurfaceTypeEnum.kPlaneSurface Then

                        Continue For
                    End If


                    Dim biggestCircle As Inventor.Circle = Nothing
                    Dim circularEdgeCount As Integer = 0


                    For Each edge As Edge In face.Edges

                        Try

                            If edge.GeometryType = _
                               CurveTypeEnum.kCircleCurve Then


                                circularEdgeCount += 1


                                Dim circle As Inventor.Circle = _
                                    CType( _
                                        edge.Geometry, _
                                        Inventor.Circle)


                                If biggestCircle Is Nothing Then

                                    biggestCircle = circle

                                ElseIf circle.Radius > _
                                       biggestCircle.Radius Then

                                    biggestCircle = circle

                                End If

                            End If

                        Catch
                        End Try

                    Next


                    If biggestCircle Is Nothing Then
                        Continue For
                    End If


                    Dim plane As Inventor.Plane = Nothing


                    Try

                        plane = _
                            CType( _
                                face.Geometry, _
                                Inventor.Plane)

                    Catch

                        Continue For

                    End Try


                    Dim p As New PortRecord

                    p.Owner = node
                    p.FaceIndex = faceCounter
                    p.ModelFace = face

                    p.X = biggestCircle.Center.X * 10.0
                    p.Y = biggestCircle.Center.Y * 10.0
                    p.Z = biggestCircle.Center.Z * 10.0

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


                    p.Radius = biggestCircle.Radius * 10.0
                    p.CircularEdges = circularEdgeCount


                    Try

                        p.FaceArea = _
                            face.Evaluator.Area * 100.0

                    Catch

                        p.FaceArea = 0

                    End Try


                    AddPortIfUnique(node.Ports, p)

                Next

            Next


            result.Add(node)


        Catch ex As Exception

            Logger.Error( _
                "Component scan error: " & _
                occ.Name & _
                " : " & _
                ex.Message)

        End Try

    Next


    Return result

End Function



' ===================================================================
' CONNECTION DETECTION
' ===================================================================

Function DetectConnections( _
    nodes As List(Of NodeRecord)) As List(Of EdgeRecord)


    Dim directTolerance As Double = 1.0
    Dim flangeSearchDistance As Double = 60.0
    Dim lateralTolerance As Double = 2.0
    Dim minimumNormalAlignment As Double = 0.90


    Dim result As New List(Of EdgeRecord)

    Dim nonFlangePorts As New List(Of PortRecord)


    For Each n As NodeRecord In nodes

        If n.ComponentType <> "FLANGE" Then

            For Each p As PortRecord In n.Ports
                nonFlangePorts.Add(p)
            Next

        End If

    Next


    ' ===============================================================
    ' PASS 1 - DIRECT PORT TO PORT
    ' ===============================================================

    For i As Integer = 0 To nonFlangePorts.Count - 1

        For j As Integer = i + 1 To nonFlangePorts.Count - 1


            Dim a As PortRecord = _
                nonFlangePorts.Item(i)

            Dim b As PortRecord = _
                nonFlangePorts.Item(j)


            If a.Owner Is b.Owner Then
                Continue For
            End If


            If HasConnection( _
                result, _
                a.Owner, _
                b.Owner) Then

                Continue For
            End If


            Dim portDistance As Double = _
                Dist3D( _
                    a.X, a.Y, a.Z, _
                    b.X, b.Y, b.Z)


            If portDistance > directTolerance Then
                Continue For
            End If


            Dim normalDotValue As Double = _
                NormalDot(a, b)


            If normalDotValue > -minimumNormalAlignment Then
                Continue For
            End If


            AddConnection( _
                result, _
                a, _
                b, _
                "DIRECT", _
                portDistance)

        Next

    Next


    ' ===============================================================
    ' PASS 2 - FLANGE ASSOCIATION
    '
    ' The nearest flange candidate is ONLY used to associate the
    ' flange with the host port.
    '
    ' We then separately calculate the true OUTER flange face.
    ' ===============================================================

    For Each hostNode As NodeRecord In nodes


        If hostNode.ComponentType = "FLANGE" Then
            Continue For
        End If


        For Each hostPort As PortRecord In hostNode.Ports


            If hostPort.Used Then
                Continue For
            End If


            Dim bestFlange As NodeRecord = Nothing
            Dim bestFlangePort As PortRecord = Nothing
            Dim bestScore As Double = Double.MaxValue


            For Each flangeNode As NodeRecord In nodes


                If flangeNode.ComponentType <> "FLANGE" Then
                    Continue For
                End If


                If flangeNode.Neighbours.Count > 0 Then
                    Continue For
                End If


                For Each flangePort As PortRecord In flangeNode.Ports


                    Dim dx As Double = _
                        flangePort.X - hostPort.X

                    Dim dy As Double = _
                        flangePort.Y - hostPort.Y

                    Dim dz As Double = _
                        flangePort.Z - hostPort.Z


                    Dim totalDistance As Double = _
                        Math.Sqrt( _
                            dx * dx + _
                            dy * dy + _
                            dz * dz)


                    If totalDistance > flangeSearchDistance Then
                        Continue For
                    End If


                    Dim axialDistance As Double = _
                        Math.Abs( _
                            dx * hostPort.NX + _
                            dy * hostPort.NY + _
                            dz * hostPort.NZ)


                    Dim lateralSquared As Double = _
                        totalDistance * totalDistance - _
                        axialDistance * axialDistance


                    If lateralSquared < 0 Then
                        lateralSquared = 0
                    End If


                    Dim lateralDistance As Double = _
                        Math.Sqrt(lateralSquared)


                    If lateralDistance > lateralTolerance Then
                        Continue For
                    End If


                    Dim alignment As Double = _
                        Math.Abs( _
                            NormalDot( _
                                hostPort, _
                                flangePort))


                    If alignment < minimumNormalAlignment Then
                        Continue For
                    End If


                    Dim score As Double = _
                        totalDistance + _
                        lateralDistance * 10.0 + _
                        (1.0 - alignment) * 100.0


                    If score < bestScore Then

                        bestScore = score
                        bestFlange = flangeNode
                        bestFlangePort = flangePort

                    End If

                Next

            Next


            If bestFlange IsNot Nothing AndAlso _
               bestFlangePort IsNot Nothing Then


                Dim connectionDistance As Double = _
                    Dist3D( _
                        hostPort.X, _
                        hostPort.Y, _
                        hostPort.Z, _
                        bestFlangePort.X, _
                        bestFlangePort.Y, _
                        bestFlangePort.Z)


                AddConnection( _
                    result, _
                    hostPort, _
                    bestFlangePort, _
                    "FLANGED_END", _
                    connectionDistance)


                ' ---------------------------------------------------
                ' CRITICAL FIX:
                '
                ' Determine flange OUTWARD direction from the host
                ' occurrence toward the flange occurrence, then choose
                ' the farthest coaxial flange face in that direction.
                '
                ' This correctly selects e.g. the 15 mm outer face,
                ' instead of the misleading nearest 5 mm internal face.
                ' ---------------------------------------------------

                FindFlangeOuterAnchor( _
                    bestFlange, _
                    hostNode, _
                    hostPort, _
                    bestFlangePort)

            End If

        Next

    Next


    Return result

End Function



' ===================================================================
' CORRECT FLANGE OUTER FACE
' ===================================================================

Sub FindFlangeOuterAnchor( _
    flange As NodeRecord, _
    hostNode As NodeRecord, _
    hostPort As PortRecord, _
    connectionFace As PortRecord)


    ' ---------------------------------------------------------------
    ' Host port axis.
    ' ---------------------------------------------------------------

    Dim ax As Double = hostPort.NX
    Dim ay As Double = hostPort.NY
    Dim az As Double = hostPort.NZ


    Dim axisLength As Double = _
        Math.Sqrt( _
            ax * ax + _
            ay * ay + _
            az * az)


    If axisLength < 0.000001 Then
        Exit Sub
    End If


    ax /= axisLength
    ay /= axisLength
    az /= axisLength


    ' ---------------------------------------------------------------
    ' Decide which sign of the host axis points outward into flange.
    '
    ' Use HOST OCCURRENCE CENTER -> FLANGE OCCURRENCE CENTER.
    '
    ' This is the key correction.
    ' ---------------------------------------------------------------

    Dim hfx As Double = flange.X - hostNode.X
    Dim hfy As Double = flange.Y - hostNode.Y
    Dim hfz As Double = flange.Z - hostNode.Z


    Dim outwardDot As Double = _
        hfx * ax + _
        hfy * ay + _
        hfz * az


    If outwardDot < 0 Then

        ax *= -1.0
        ay *= -1.0
        az *= -1.0

    End If


    Dim bestPort As PortRecord = Nothing
    Dim bestSignedDistance As Double = Double.MinValue


    For Each candidate As PortRecord In flange.Ports


        ' Same flange axis.
        Dim alignment As Double = _
            Math.Abs( _
                candidate.NX * ax + _
                candidate.NY * ay + _
                candidate.NZ * az)


        If alignment < 0.90 Then
            Continue For
        End If


        Dim dx As Double = candidate.X - hostPort.X
        Dim dy As Double = candidate.Y - hostPort.Y
        Dim dz As Double = candidate.Z - hostPort.Z


        Dim signedDistance As Double = _
            dx * ax + _
            dy * ay + _
            dz * az


        ' Must be on outward side, allowing tiny modelling noise.
        If signedDistance < -1.0 Then
            Continue For
        End If


        Dim totalSquared As Double = _
            dx * dx + _
            dy * dy + _
            dz * dz

        Dim lateralSquared As Double = _
            totalSquared - _
            signedDistance * signedDistance


        If lateralSquared < 0 Then
            lateralSquared = 0
        End If


        Dim lateralDistance As Double = _
            Math.Sqrt(lateralSquared)


        If lateralDistance > 2.5 Then
            Continue For
        End If


        If signedDistance > bestSignedDistance Then

            bestSignedDistance = signedDistance
            bestPort = candidate

        End If

    Next


    If bestPort Is Nothing Then
        bestPort = connectionFace
    End If


    flange.HasOuterAnchor = True

    flange.InnerFaceIndex = connectionFace.FaceIndex
    flange.OuterFaceIndex = bestPort.FaceIndex
    flange.OuterPort = bestPort

    flange.OuterX = bestPort.X
    flange.OuterY = bestPort.Y
    flange.OuterZ = bestPort.Z

    flange.OuterOffset = _
        Dist3D( _
            hostPort.X, hostPort.Y, hostPort.Z, _
            bestPort.X, bestPort.Y, bestPort.Z)


    flange.FlangeHostCode = hostNode.Code

    flange.HostPortX = hostPort.X
    flange.HostPortY = hostPort.Y
    flange.HostPortZ = hostPort.Z

End Sub



' ===================================================================
' ADD CONNECTION
' ===================================================================

Sub AddConnection( _
    edges As List(Of EdgeRecord), _
    portA As PortRecord, _
    portB As PortRecord, _
    connectionType As String, _
    connectionDistance As Double)


    If HasConnection( _
        edges, _
        portA.Owner, _
        portB.Owner) Then

        Exit Sub
    End If


    Dim e As New EdgeRecord

    e.A = portA.Owner
    e.B = portB.Owner

    e.PortA = portA
    e.PortB = portB

    e.ConnectionType = connectionType
    e.ConnectionDistance = connectionDistance


    edges.Add(e)


    portA.Owner.Neighbours.Add(portB.Owner)
    portB.Owner.Neighbours.Add(portA.Owner)

    portA.Used = True
    portB.Used = True

End Sub



' ===================================================================
' REFERENCE POINTS
' ===================================================================

Sub ComputeReferencePoints( _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord))


    For Each n As NodeRecord In nodes


        If n.ComponentType = "FLANGE" AndAlso _
           n.HasOuterAnchor Then

            n.RefX = n.OuterX
            n.RefY = n.OuterY
            n.RefZ = n.OuterZ

            n.ReferenceType = "FLANGE_OUTER_FACE"

            Continue For
        End If


        Dim activePorts As List(Of PortRecord) = _
            GetUsedPorts(n, edges)


        ' -----------------------------------------------------------
        ' ELBOW center = intersection of its two connection axes.
        ' -----------------------------------------------------------

        If n.ComponentType = "ELBOW" AndAlso _
           activePorts.Count >= 2 Then


            Dim p1 As PortRecord = activePorts.Item(0)
            Dim p2 As PortRecord = activePorts.Item(1)


            Dim ix As Double = 0
            Dim iy As Double = 0
            Dim iz As Double = 0
            Dim separation As Double = 0


            If ClosestAxisIntersection( _
                p1, _
                p2, _
                ix, iy, iz, _
                separation) Then


                If separation <= 3.0 Then

                    n.RefX = ix
                    n.RefY = iy
                    n.RefZ = iz

                    n.ReferenceType = "ELBOW_CENTER"

                    Continue For

                End If

            End If

        End If


        ' -----------------------------------------------------------
        ' TEE center.
        '
        ' Identify the most-opposed port pair as run ports.
        ' The remaining non-collinear port is branch.
        ' -----------------------------------------------------------

        If n.ComponentType = "TEE" AndAlso _
           activePorts.Count >= 3 Then


            Dim runA As PortRecord = Nothing
            Dim runB As PortRecord = Nothing

            FindMostOpposedPortPair( _
                activePorts, _
                runA, _
                runB)


            Dim branchPort As PortRecord = Nothing


            For Each p As PortRecord In activePorts

                If p Is runA OrElse p Is runB Then
                    Continue For
                End If

                branchPort = p
                Exit For

            Next


            If runA IsNot Nothing AndAlso _
               branchPort IsNot Nothing Then


                Dim ix As Double = 0
                Dim iy As Double = 0
                Dim iz As Double = 0
                Dim separation As Double = 0


                If ClosestAxisIntersection( _
                    runA, _
                    branchPort, _
                    ix, iy, iz, _
                    separation) Then


                    If separation <= 3.0 Then

                        n.RefX = ix
                        n.RefY = iy
                        n.RefZ = iz

                        n.ReferenceType = "TEE_CENTER"

                        Continue For

                    End If

                End If

            End If


            ' Fallback for equal tee:
            ' midpoint of opposed run faces.
            If runA IsNot Nothing AndAlso _
               runB IsNot Nothing Then


                n.RefX = (runA.X + runB.X) / 2.0
                n.RefY = (runA.Y + runB.Y) / 2.0
                n.RefZ = (runA.Z + runB.Z) / 2.0

                n.ReferenceType = "TEE_CENTER_MIDPOINT"

                Continue For

            End If

        End If


        ' -----------------------------------------------------------
        ' Fallback.
        ' -----------------------------------------------------------

        n.RefX = n.X
        n.RefY = n.Y
        n.RefZ = n.Z

        n.ReferenceType = "OCCURRENCE_CENTER"

    Next

End Sub



' ===================================================================
' BUILD MANUFACTURING PRIMITIVES
' ===================================================================

Function BuildManufacturingPrimitives( _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord)) As List(Of PrimitiveSegment)


    Dim result As New List(Of PrimitiveSegment)


    For Each n As NodeRecord In nodes


        Dim activePorts As List(Of PortRecord) = _
            GetUsedPorts(n, edges)


        Select Case n.ComponentType


            Case "FLANGE"

                If n.HasOuterAnchor Then


                    Dim hostPort As PortRecord = _
                        GetHostSidePortForFlange( _
                            n, _
                            edges)


                    If hostPort IsNot Nothing Then


                        result.Add( _
                            New PrimitiveSegment( _
                                n, _
                                "FLANGE", _
                                hostPort.X, _
                                hostPort.Y, _
                                hostPort.Z, _
                                n.OuterX, _
                                n.OuterY, _
                                n.OuterZ))

                    End If

                End If


            Case "PIPE", _
                 "REDUCER", _
                 "VALVE", _
                 "COUPLING_SOCKET", _
                 "OTHER"


                If activePorts.Count >= 2 Then


                    Dim a As PortRecord = Nothing
                    Dim b As PortRecord = Nothing


                    FindFarthestPortPair( _
                        activePorts, _
                        a, _
                        b)


                    If a IsNot Nothing AndAlso _
                       b IsNot Nothing Then


                        result.Add( _
                            New PrimitiveSegment( _
                                n, _
                                n.ComponentType, _
                                a.X, a.Y, a.Z, _
                                b.X, b.Y, b.Z))

                    End If

                End If


            Case "TEE"


                For Each p As PortRecord In activePorts


                    result.Add( _
                        New PrimitiveSegment( _
                            n, _
                            "TEE_LEG", _
                            n.RefX, _
                            n.RefY, _
                            n.RefZ, _
                            p.X, _
                            p.Y, _
                            p.Z))

                Next


            Case "ELBOW"


                For Each p As PortRecord In activePorts


                    result.Add( _
                        New PrimitiveSegment( _
                            n, _
                            "ELBOW_RADIAL", _
                            n.RefX, _
                            n.RefY, _
                            n.RefZ, _
                            p.X, _
                            p.Y, _
                            p.Z))

                Next

        End Select

    Next


    Return result

End Function



' ===================================================================
' COMPONENT DIMENSIONS
' ===================================================================

Function BuildComponentDimensions( _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord)) As List(Of DimensionRecord)


    Dim result As New List(Of DimensionRecord)


    For Each n As NodeRecord In nodes


        Dim activePorts As List(Of PortRecord) = _
            GetUsedPorts(n, edges)


        Select Case n.ComponentType


            Case "FLANGE"

                If n.HasOuterAnchor Then


                    Dim hostPort As PortRecord = _
                        GetHostSidePortForFlange( _
                            n, _
                            edges)


                    If hostPort IsNot Nothing Then


                        AddDimension( _
                            result, _
                            n.Code & " FLANGE", _
                            n.Code, _
                            "FLANGE_THICKNESS", _
                            hostPort.X, _
                            hostPort.Y, _
                            hostPort.Z, _
                            n.OuterX, _
                            n.OuterY, _
                            n.OuterZ, _
                            "COMPONENT")

                    End If

                End If


            Case "PIPE"


                If activePorts.Count >= 2 Then


                    Dim a As PortRecord = Nothing
                    Dim b As PortRecord = Nothing


                    FindFarthestPortPair( _
                        activePorts, _
                        a, _
                        b)


                    If a IsNot Nothing AndAlso _
                       b IsNot Nothing Then


                        AddDimension( _
                            result, _
                            n.Code & " PIPE", _
                            n.Code, _
                            "PIPE_LENGTH", _
                            a.X, a.Y, a.Z, _
                            b.X, b.Y, b.Z, _
                            "COMPONENT")

                    End If

                End If


            Case "REDUCER"


                If activePorts.Count >= 2 Then


                    Dim a As PortRecord = Nothing
                    Dim b As PortRecord = Nothing


                    FindFarthestPortPair( _
                        activePorts, _
                        a, _
                        b)


                    If a IsNot Nothing AndAlso _
                       b IsNot Nothing Then


                        AddDimension( _
                            result, _
                            n.Code & " REDUCER", _
                            n.Code, _
                            "REDUCER_FACE_TO_FACE", _
                            a.X, a.Y, a.Z, _
                            b.X, b.Y, b.Z, _
                            "COMPONENT")

                    End If

                End If


            Case "TEE"


                If activePorts.Count >= 2 Then


                    Dim runA As PortRecord = Nothing
                    Dim runB As PortRecord = Nothing


                    FindMostOpposedPortPair( _
                        activePorts, _
                        runA, _
                        runB)


                    If runA IsNot Nothing AndAlso _
                       runB IsNot Nothing Then


                        AddDimension( _
                            result, _
                            n.Code & " TEE RUN", _
                            n.Code, _
                            "TEE_RUN_FACE_TO_FACE", _
                            runA.X, runA.Y, runA.Z, _
                            runB.X, runB.Y, runB.Z, _
                            "COMPONENT")

                    End If


                    For Each p As PortRecord In activePorts


                        If p Is runA OrElse p Is runB Then
                            Continue For
                        End If


                        AddDimension( _
                            result, _
                            n.Code & " TEE BRANCH", _
                            n.Code, _
                            "TEE_CENTER_TO_BRANCH_FACE", _
                            n.RefX, n.RefY, n.RefZ, _
                            p.X, p.Y, p.Z, _
                            "COMPONENT")

                    Next

                End If


            Case "ELBOW"


                For i As Integer = 0 To activePorts.Count - 1


                    Dim p As PortRecord = _
                        activePorts.Item(i)


                    AddDimension( _
                        result, _
                        n.Code & " ELBOW R" & _
                        (i + 1).ToString(), _
                        n.Code, _
                        "ELBOW_CENTER_TO_PORT", _
                        n.RefX, n.RefY, n.RefZ, _
                        p.X, p.Y, p.Z, _
                        "COMPONENT")

                Next


            Case "VALVE", _
                 "COUPLING_SOCKET"


                If activePorts.Count >= 2 Then


                    Dim a As PortRecord = Nothing
                    Dim b As PortRecord = Nothing


                    FindFarthestPortPair( _
                        activePorts, _
                        a, _
                        b)


                    If a IsNot Nothing AndAlso _
                       b IsNot Nothing Then


                        AddDimension( _
                            result, _
                            n.Code & " " & n.ComponentType, _
                            n.Code, _
                            n.ComponentType & "_FACE_TO_FACE", _
                            a.X, a.Y, a.Z, _
                            b.X, b.Y, b.Z, _
                            "COMPONENT")

                    End If

                End If

        End Select

    Next


    Return result

End Function



Sub AddDimension( _
    list As List(Of DimensionRecord), _
    label As String, _
    ownerCode As String, _
    dimensionType As String, _
    ax As Double, _
    ay As Double, _
    az As Double, _
    bx As Double, _
    by As Double, _
    bz As Double, _
    category As String)


    Dim d As New DimensionRecord

    d.Label = label
    d.OwnerCode = ownerCode
    d.DimensionType = dimensionType
    d.Category = category

    d.X1 = ax
    d.Y1 = ay
    d.Z1 = az

    d.X2 = bx
    d.Y2 = by
    d.Z2 = bz

    d.Value = _
        Dist3D( _
            ax, ay, az, _
            bx, by, bz)


    list.Add(d)

End Sub



' ===================================================================
' BUILD MAXIMAL STRAIGHT CHAINS
' ===================================================================

Function BuildStraightChains( _
    segments As List(Of PrimitiveSegment)) As List(Of StraightChain)


    Dim result As New List(Of StraightChain)

    Dim visited As New HashSet(Of Integer)


    For i As Integer = 0 To segments.Count - 1


        If visited.Contains(i) Then
            Continue For
        End If


        Dim queue As New Queue(Of Integer)
        Dim indices As New List(Of Integer)


        queue.Enqueue(i)
        visited.Add(i)


        While queue.Count > 0


            Dim current As Integer = queue.Dequeue()

            indices.Add(current)


            For j As Integer = 0 To segments.Count - 1


                If visited.Contains(j) Then
                    Continue For
                End If


                If SegmentsConnectCollinear( _
                    segments.Item(current), _
                    segments.Item(j)) Then


                    visited.Add(j)
                    queue.Enqueue(j)

                End If

            Next

        End While


        Dim chain As New StraightChain

        chain.Index = result.Count + 1


        For Each idx As Integer In indices

            chain.Segments.Add( _
                segments.Item(idx))

        Next


        ComputeChainExtremes(chain)


        result.Add(chain)

    Next


    Return result

End Function



Function SegmentsConnectCollinear( _
    a As PrimitiveSegment, _
    b As PrimitiveSegment) As Boolean


    If Not SegmentsShareEndpoint(a, b, 0.5) Then
        Return False
    End If


    Dim adx As Double = a.X2 - a.X1
    Dim ady As Double = a.Y2 - a.Y1
    Dim adz As Double = a.Z2 - a.Z1

    Dim bdx As Double = b.X2 - b.X1
    Dim bdy As Double = b.Y2 - b.Y1
    Dim bdz As Double = b.Z2 - b.Z1


    Dim al As Double = _
        Math.Sqrt( _
            adx * adx + _
            ady * ady + _
            adz * adz)

    Dim bl As Double = _
        Math.Sqrt( _
            bdx * bdx + _
            bdy * bdy + _
            bdz * bdz)


    If al < 0.001 OrElse bl < 0.001 Then
        Return False
    End If


    Dim dotValue As Double = _
        Math.Abs( _
            (adx * bdx + _
             ady * bdy + _
             adz * bdz) / _
            (al * bl))


    Return dotValue >= 0.999

End Function



Function SegmentsShareEndpoint( _
    a As PrimitiveSegment, _
    b As PrimitiveSegment, _
    tolerance As Double) As Boolean


    If Dist3D( _
        a.X1, a.Y1, a.Z1, _
        b.X1, b.Y1, b.Z1) <= tolerance Then

        Return True
    End If


    If Dist3D( _
        a.X1, a.Y1, a.Z1, _
        b.X2, b.Y2, b.Z2) <= tolerance Then

        Return True
    End If


    If Dist3D( _
        a.X2, a.Y2, a.Z2, _
        b.X1, b.Y1, b.Z1) <= tolerance Then

        Return True
    End If


    If Dist3D( _
        a.X2, a.Y2, a.Z2, _
        b.X2, b.Y2, b.Z2) <= tolerance Then

        Return True
    End If


    Return False

End Function



Sub ComputeChainExtremes( _
    chain As StraightChain)


    Dim points As New List(Of Point3DRecord)


    For Each s As PrimitiveSegment In chain.Segments

        points.Add( _
            New Point3DRecord( _
                s.X1, s.Y1, s.Z1))

        points.Add( _
            New Point3DRecord( _
                s.X2, s.Y2, s.Z2))

    Next


    Dim best As Double = -1


    For i As Integer = 0 To points.Count - 2

        For j As Integer = i + 1 To points.Count - 1


            Dim a As Point3DRecord = points.Item(i)
            Dim b As Point3DRecord = points.Item(j)


            Dim d As Double = _
                Dist3D( _
                    a.X, a.Y, a.Z, _
                    b.X, b.Y, b.Z)


            If d > best Then

                best = d

                chain.X1 = a.X
                chain.Y1 = a.Y
                chain.Z1 = a.Z

                chain.X2 = b.X
                chain.Y2 = b.Y
                chain.Z2 = b.Z

            End If

        Next

    Next


    chain.Length = Math.Max(best, 0)

End Sub



Function BuildOverallDimensions( _
    chains As List(Of StraightChain)) As List(Of DimensionRecord)


    Dim result As New List(Of DimensionRecord)


    For Each chain As StraightChain In chains


        ' -----------------------------------------------------------
        ' Only useful as an OVERALL when the straight chain consists
        ' of more than one manufacturing primitive.
        ' -----------------------------------------------------------

        If chain.Segments.Count <= 1 Then
            Continue For
        End If


        Dim d As New DimensionRecord

        d.Label = _
            "RUN " & _
            chain.Index.ToString() & _
            " OVERALL"

        d.OwnerCode = "RUN" & chain.Index.ToString()
        d.DimensionType = "STRAIGHT_RUN_OVERALL"
        d.Category = "OVERALL"

        d.ChainIndex = chain.Index

        d.X1 = chain.X1
        d.Y1 = chain.Y1
        d.Z1 = chain.Z1

        d.X2 = chain.X2
        d.Y2 = chain.Y2
        d.Z2 = chain.Z2

        d.Value = chain.Length


        result.Add(d)

    Next


    Return result

End Function



Sub AssignDimensionsToChains( _
    dimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain))


    For Each d As DimensionRecord In dimensions


        d.ChainIndex = 0


        For Each chain As StraightChain In chains


            If PointOnInfiniteLine( _
                d.X1, d.Y1, d.Z1, _
                chain.X1, chain.Y1, chain.Z1, _
                chain.X2, chain.Y2, chain.Z2, _
                0.75) AndAlso _
               PointOnInfiniteLine( _
                d.X2, d.Y2, d.Z2, _
                chain.X1, chain.Y1, chain.Z1, _
                chain.X2, chain.Y2, chain.Z2, _
                0.75) Then


                d.ChainIndex = chain.Index
                Exit For

            End If

        Next

    Next

End Sub



Function PointOnInfiniteLine( _
    px As Double, _
    py As Double, _
    pz As Double, _
    ax As Double, _
    ay As Double, _
    az As Double, _
    bx As Double, _
    by As Double, _
    bz As Double, _
    tolerance As Double) As Boolean


    Dim dx As Double = bx - ax
    Dim dy As Double = by - ay
    Dim dz As Double = bz - az


    Dim length As Double = _
        Math.Sqrt( _
            dx * dx + _
            dy * dy + _
            dz * dz)


    If length < 0.001 Then
        Return False
    End If


    dx /= length
    dy /= length
    dz /= length


    Dim vx As Double = px - ax
    Dim vy As Double = py - ay
    Dim vz As Double = pz - az


    Dim projection As Double = _
        vx * dx + _
        vy * dy + _
        vz * dz


    Dim cx As Double = ax + projection * dx
    Dim cy As Double = ay + projection * dy
    Dim cz As Double = az + projection * dz


    Dim perpendicular As Double = _
        Dist3D( _
            px, py, pz, _
            cx, cy, cz)


    Return perpendicular <= tolerance

End Function



' ===================================================================
' COMPLETE CSV
' ===================================================================

Sub WriteCompleteCsv( _
    assemblyName As String, _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord), _
    primitives As List(Of PrimitiveSegment), _
    componentDimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain), _
    overallDimensions As List(Of DimensionRecord), _
    graphGroups As Integer, _
    unresolved As List(Of String), _
    outputFile As String)


    Dim writer As New System.IO.StreamWriter( _
        outputFile, _
        False, _
        Encoding.UTF8)


    Try

        writer.WriteLine( _
            "RecordType," & _
            "Assembly," & _
            "Code," & _
            "OwnerCode," & _
            "Occurrence," & _
            "ComponentType," & _
            "PartNumber," & _
            "Description," & _
            "FaceIndex," & _
            "X_mm," & _
            "Y_mm," & _
            "Z_mm," & _
            "NX," & _
            "NY," & _
            "NZ," & _
            "Radius_mm," & _
            "Used," & _
            "ConnectedTo," & _
            "ConnectionType," & _
            "TopologyGap_mm," & _
            "ReferenceType," & _
            "ReferenceX_mm," & _
            "ReferenceY_mm," & _
            "ReferenceZ_mm," & _
            "FlangeInnerFace," & _
            "FlangeOuterFace," & _
            "FlangeOuterX_mm," & _
            "FlangeOuterY_mm," & _
            "FlangeOuterZ_mm," & _
            "Value_mm," & _
            "FromX_mm," & _
            "FromY_mm," & _
            "FromZ_mm," & _
            "ToX_mm," & _
            "ToY_mm," & _
            "ToZ_mm," & _
            "ChainIndex," & _
            "Notes")


        ' -----------------------------------------------------------
        ' Assembly summary
        ' -----------------------------------------------------------

        writer.WriteLine( _
            Csv("ASSEMBLY") & "," & _
            Csv(assemblyName) & "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            "," & _
            "," & "," & "," & _
            "," & "," & "," & _
            "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            Csv("") & "," & _
            "," & _
            Csv("") & "," & _
            "," & "," & "," & _
            "," & "," & _
            "," & "," & "," & _
            "," & _
            "," & "," & "," & _
            "," & "," & "," & _
            "," & _
            Csv( _
                "Components=" & nodes.Count.ToString() & _
                "; Connections=" & edges.Count.ToString() & _
                "; GraphGroups=" & graphGroups.ToString() & _
                "; Unresolved=" & _
                String.Join(";", unresolved.ToArray())))


        ' -----------------------------------------------------------
        ' Components + ports
        ' -----------------------------------------------------------

        For Each n As NodeRecord In nodes


            writer.WriteLine( _
                Csv("COMPONENT") & "," & _
                Csv(assemblyName) & "," & _
                Csv(n.Code) & "," & _
                Csv(n.Code) & "," & _
                Csv(n.OccurrenceName) & "," & _
                Csv(n.ComponentType) & "," & _
                Csv(n.PartNumber) & "," & _
                Csv(n.Description) & "," & _
                "," & _
                Num(n.X) & "," & _
                Num(n.Y) & "," & _
                Num(n.Z) & "," & _
                "," & "," & "," & _
                "," & _
                Csv("") & "," & _
                Csv(String.Join(";", GetNeighbourCodes(n).ToArray())) & "," & _
                Csv("") & "," & _
                "," & _
                Csv(n.ReferenceType) & "," & _
                Num(n.RefX) & "," & _
                Num(n.RefY) & "," & _
                Num(n.RefZ) & "," & _
                If(n.InnerFaceIndex > 0, n.InnerFaceIndex.ToString(), "") & "," & _
                If(n.OuterFaceIndex > 0, n.OuterFaceIndex.ToString(), "") & "," & _
                If(n.HasOuterAnchor, Num(n.OuterX), "") & "," & _
                If(n.HasOuterAnchor, Num(n.OuterY), "") & "," & _
                If(n.HasOuterAnchor, Num(n.OuterZ), "") & "," & _
                If(n.HasOuterAnchor, Num(n.OuterOffset), "") & "," & _
                "," & "," & "," & _
                "," & "," & "," & _
                "," & _
                Csv( _
                    "Degree=" & _
                    n.Neighbours.Count.ToString()))


            For Each p As PortRecord In n.Ports


                writer.WriteLine( _
                    Csv("PORT") & "," & _
                    Csv(assemblyName) & "," & _
                    Csv(n.Code) & "," & _
                    Csv(n.Code) & "," & _
                    Csv(n.OccurrenceName) & "," & _
                    Csv(n.ComponentType) & "," & _
                    Csv(n.PartNumber) & "," & _
                    Csv(n.Description) & "," & _
                    p.FaceIndex.ToString() & "," & _
                    Num(p.X) & "," & _
                    Num(p.Y) & "," & _
                    Num(p.Z) & "," & _
                    Num(p.NX) & "," & _
                    Num(p.NY) & "," & _
                    Num(p.NZ) & "," & _
                    Num(p.Radius) & "," & _
                    Csv(If(p.Used, "YES", "NO")) & "," & _
                    Csv("") & "," & _
                    Csv("") & "," & _
                    "," & _
                    Csv("") & "," & _
                    "," & "," & "," & _
                    "," & "," & "," & "," & "," & _
                    "," & _
                    "," & "," & "," & _
                    "," & "," & "," & _
                    "," & _
                    Csv( _
                        "CircularEdges=" & _
                        p.CircularEdges.ToString() & _
                        "; FaceArea_mm2=" & _
                        Num(p.FaceArea)))

            Next

        Next


        ' -----------------------------------------------------------
        ' Connections
        ' -----------------------------------------------------------

        For Each e As EdgeRecord In edges


            writer.WriteLine( _
                Csv("CONNECTION") & "," & _
                Csv(assemblyName) & "," & _
                Csv(e.A.Code & "-" & e.B.Code) & "," & _
                Csv("") & "," & _
                Csv("") & "," & _
                Csv("") & "," & _
                Csv("") & "," & _
                Csv("") & "," & _
                "," & _
                Num(e.PortA.X) & "," & _
                Num(e.PortA.Y) & "," & _
                Num(e.PortA.Z) & "," & _
                Num(e.PortA.NX) & "," & _
                Num(e.PortA.NY) & "," & _
                Num(e.PortA.NZ) & "," & _
                "," & _
                Csv("") & "," & _
                Csv(e.B.Code) & "," & _
                Csv(e.ConnectionType) & "," & _
                Num(e.ConnectionDistance) & "," & _
                Csv("") & "," & _
                "," & "," & "," & _
                "," & "," & "," & "," & "," & _
                "," & _
                "," & "," & "," & _
                "," & "," & "," & _
                "," & _
                Csv( _
                    "PortA_Face=" & e.PortA.FaceIndex.ToString() & _
                    "; PortB_Face=" & e.PortB.FaceIndex.ToString()))

        Next


        ' -----------------------------------------------------------
        ' Primitive skeleton
        ' -----------------------------------------------------------

        For Each p As PrimitiveSegment In primitives


            writer.WriteLine( _
                Csv("PRIMITIVE") & "," & _
                Csv(assemblyName) & "," & _
                Csv(p.Owner.Code & "-" & p.Kind) & "," & _
                Csv(p.Owner.Code) & "," & _
                Csv(p.Owner.OccurrenceName) & "," & _
                Csv(p.Owner.ComponentType) & "," & _
                Csv(p.Owner.PartNumber) & "," & _
                Csv(p.Owner.Description) & "," & _
                "," & _
                "," & "," & "," & _
                "," & "," & "," & _
                "," & _
                Csv("") & "," & _
                Csv("") & "," & _
                Csv(p.Kind) & "," & _
                "," & _
                Csv("") & "," & _
                "," & "," & "," & _
                "," & "," & "," & "," & "," & _
                Num(p.Length) & "," & _
                Num(p.X1) & "," & _
                Num(p.Y1) & "," & _
                Num(p.Z1) & "," & _
                Num(p.X2) & "," & _
                Num(p.Y2) & "," & _
                Num(p.Z2) & "," & _
                "," & _
                Csv("Manufacturing skeleton segment"))

        Next


        ' -----------------------------------------------------------
        ' Component dimensions
        ' -----------------------------------------------------------

        For Each d As DimensionRecord In componentDimensions


            WriteDimensionCsvRow( _
                writer, _
                assemblyName, _
                "COMPONENT_DIMENSION", _
                d)

        Next


        ' -----------------------------------------------------------
        ' Overall dimensions
        ' -----------------------------------------------------------

        For Each d As DimensionRecord In overallDimensions


            WriteDimensionCsvRow( _
                writer, _
                assemblyName, _
                "OVERALL_DIMENSION", _
                d)

        Next


        writer.Flush()


    Finally

        writer.Close()

    End Try

End Sub



Sub WriteDimensionCsvRow( _
    writer As System.IO.StreamWriter, _
    assemblyName As String, _
    recordType As String, _
    d As DimensionRecord)


    writer.WriteLine( _
        Csv(recordType) & "," & _
        Csv(assemblyName) & "," & _
        Csv(d.Label) & "," & _
        Csv(d.OwnerCode) & "," & _
        Csv("") & "," & _
        Csv("") & "," & _
        Csv("") & "," & _
        Csv("") & "," & _
        "," & _
        "," & "," & "," & _
        "," & "," & "," & _
        "," & _
        Csv("") & "," & _
        Csv("") & "," & _
        Csv(d.DimensionType) & "," & _
        "," & _
        Csv(d.Category) & "," & _
        "," & "," & "," & _
        "," & "," & "," & "," & "," & _
        Num(d.Value) & "," & _
        Num(d.X1) & "," & _
        Num(d.Y1) & "," & _
        Num(d.Z1) & "," & _
        Num(d.X2) & "," & _
        Num(d.Y2) & "," & _
        Num(d.Z2) & "," & _
        d.ChainIndex.ToString() & "," & _
        Csv(""))

End Sub



' ===================================================================
' CLEAN CANONICAL SCHEMATIC
' ===================================================================

Sub GenerateVerificationSvg( _
    assemblyName As String, _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord), _
    primitives As List(Of PrimitiveSegment), _
    componentDimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain), _
    overallDimensions As List(Of DimensionRecord), _
    graphGroups As Integer, _
    unresolved As List(Of String), _
    outputFile As String)


    Dim canvasWidth As Double = 1600
    Dim canvasHeight As Double = 1050


    Dim svg As New StringBuilder


    svg.AppendLine( _
        "<svg xmlns=""http://www.w3.org/2000/svg"" " & _
        "width=""" & Num(canvasWidth) & """ " & _
        "height=""" & Num(canvasHeight) & """ " & _
        "viewBox=""0 0 1600 1050"">")


    svg.AppendLine( _
        "<rect x=""1"" y=""1"" width=""1598"" height=""1048"" " & _
        "fill=""white"" stroke=""black"" stroke-width=""2""/>")


    svg.AppendLine( _
        "<text x=""40"" y=""44"" " & _
        "font-family=""Arial"" font-size=""25"" font-weight=""bold"">" & _
        XmlText(assemblyName) & _
        "</text>")


    svg.AppendLine( _
        "<text x=""40"" y=""72"" " & _
        "font-family=""Arial"" font-size=""14"">" & _
        XmlText( _
            "Components=" & nodes.Count.ToString() & _
            "   Connections=" & edges.Count.ToString() & _
            "   GraphGroups=" & graphGroups.ToString() & _
            "   Unresolved=" & _
            String.Join(",", unresolved.ToArray())) & _
        "</text>")


    svg.AppendLine( _
        "<text x=""40"" y=""96"" " & _
        "font-family=""Arial"" font-size=""12"">" & _
        "Component dimensions + maximal straight-run overall dimensions extracted from model geometry." & _
        "</text>")


    ' ===============================================================
    ' Main schematic panel
    ' ===============================================================

    Dim panelX As Double = 30
    Dim panelY As Double = 120
    Dim panelW As Double = 1540
    Dim panelH As Double = 760


    svg.AppendLine( _
        "<rect x=""" & Num(panelX) & _
        """ y=""" & Num(panelY) & _
        """ width=""" & Num(panelW) & _
        """ height=""" & Num(panelH) & _
        """ fill=""none"" stroke=""black"" stroke-width=""1.5""/>")


    svg.AppendLine( _
        "<text x=""" & Num(panelX + 14) & _
        """ y=""" & Num(panelY + 27) & _
        """ font-family=""Arial"" font-size=""16"" font-weight=""bold"">" & _
        "CANONICAL MANUFACTURING SCHEMATIC" & _
        "</text>")


    Dim transform As SchematicTransform = _
        BuildCanonicalTransform( _
            nodes, _
            primitives, _
            chains, _
            panelX + 90, _
            panelY + 95, _
            panelW - 180, _
            panelH - 190)


    ' ===============================================================
    ' Draw manufacturing geometry
    ' ===============================================================

    DrawManufacturingGeometry( _
        svg, _
        nodes, _
        edges, _
        primitives, _
        transform)


    ' ===============================================================
    ' Component labels
    ' ===============================================================

    DrawComponentLabels( _
        svg, _
        nodes, _
        edges, _
        transform)


    ' ===============================================================
    ' Dimensions
    ' ===============================================================

    DrawAllDimensions( _
        svg, _
        componentDimensions, _
        chains, _
        overallDimensions, _
        transform)


    ' ===============================================================
    ' Bottom extracted dimension table
    ' ===============================================================

    DrawDimensionSummaryTable( _
        svg, _
        componentDimensions, _
        overallDimensions, _
        50, _
        910)


    svg.AppendLine("</svg>")


    System.IO.File.WriteAllText( _
        outputFile, _
        svg.ToString(), _
        Encoding.UTF8)

End Sub



' ===================================================================
' BUILD CANONICAL 2D BASIS
'
' Primary U axis = longest straight chain.
'
' Secondary V axis:
' prefer a non-collinear TEE branch so branch direction is visually
' meaningful.  Otherwise use any non-collinear primitive.
'
' This makes a planar spool like:
'
'             branch
'               |
' flange--pipe--tee----elbow
'                         |
'                       flange
'
' appear in the natural fabrication orientation.
' ===================================================================

Function BuildCanonicalTransform( _
    nodes As List(Of NodeRecord), _
    primitives As List(Of PrimitiveSegment), _
    chains As List(Of StraightChain), _
    x As Double, _
    y As Double, _
    w As Double, _
    h As Double) As SchematicTransform


    Dim t As New SchematicTransform


    ' ---------------------------------------------------------------
    ' Find longest straight chain.
    ' ---------------------------------------------------------------

    Dim longest As StraightChain = Nothing


    For Each c As StraightChain In chains

        If longest Is Nothing OrElse _
           c.Length > longest.Length Then

            longest = c

        End If

    Next


    Dim ux As Double = 1
    Dim uy As Double = 0
    Dim uz As Double = 0


    Dim originX As Double = 0
    Dim originY As Double = 0
    Dim originZ As Double = 0


    If longest IsNot Nothing AndAlso _
       longest.Length > 0.001 Then


        ' -----------------------------------------------------------
        ' Prefer a flange outer endpoint as LEFT/start of main chain.
        ' -----------------------------------------------------------

        Dim aIsFlange As Boolean = _
            IsFlangeOuterPoint( _
                nodes, _
                longest.X1, _
                longest.Y1, _
                longest.Z1)

        Dim bIsFlange As Boolean = _
            IsFlangeOuterPoint( _
                nodes, _
                longest.X2, _
                longest.Y2, _
                longest.Z2)


        If bIsFlange AndAlso Not aIsFlange Then

            originX = longest.X2
            originY = longest.Y2
            originZ = longest.Z2

            ux = longest.X1 - longest.X2
            uy = longest.Y1 - longest.Y2
            uz = longest.Z1 - longest.Z2

        Else

            originX = longest.X1
            originY = longest.Y1
            originZ = longest.Z1

            ux = longest.X2 - longest.X1
            uy = longest.Y2 - longest.Y1
            uz = longest.Z2 - longest.Z1

        End If

    ElseIf primitives.Count > 0 Then


        Dim s As PrimitiveSegment = _
            primitives.Item(0)


        originX = s.X1
        originY = s.Y1
        originZ = s.Z1

        ux = s.X2 - s.X1
        uy = s.Y2 - s.Y1
        uz = s.Z2 - s.Z1

    End If


    NormalizeVector(ux, uy, uz)


    ' ---------------------------------------------------------------
    ' Find a meaningful secondary direction.
    ' Prefer TEE branch not collinear with U.
    ' ---------------------------------------------------------------

    Dim sx As Double = 0
    Dim sy As Double = 0
    Dim sz As Double = 0

    Dim foundSecondary As Boolean = False


    For Each s As PrimitiveSegment In primitives


        If s.Owner.ComponentType <> "TEE" Then
            Continue For
        End If


        Dim dx As Double = s.X2 - s.X1
        Dim dy As Double = s.Y2 - s.Y1
        Dim dz As Double = s.Z2 - s.Z1


        Dim dl As Double = _
            Math.Sqrt( _
                dx * dx + _
                dy * dy + _
                dz * dz)


        If dl < 0.001 Then
            Continue For
        End If


        dx /= dl
        dy /= dl
        dz /= dl


        Dim dotValue As Double = _
            Math.Abs( _
                dx * ux + _
                dy * uy + _
                dz * uz)


        If dotValue < 0.90 Then

            sx = dx
            sy = dy
            sz = dz

            foundSecondary = True
            Exit For

        End If

    Next


    If Not foundSecondary Then


        For Each s As PrimitiveSegment In primitives


            Dim dx As Double = s.X2 - s.X1
            Dim dy As Double = s.Y2 - s.Y1
            Dim dz As Double = s.Z2 - s.Z1


            Dim dl As Double = _
                Math.Sqrt( _
                    dx * dx + _
                    dy * dy + _
                    dz * dz)


            If dl < 0.001 Then
                Continue For
            End If


            dx /= dl
            dy /= dl
            dz /= dl


            Dim dotValue As Double = _
                Math.Abs( _
                    dx * ux + _
                    dy * uy + _
                    dz * uz)


            If dotValue < 0.90 Then

                sx = dx
                sy = dy
                sz = dz

                foundSecondary = True
                Exit For

            End If

        Next

    End If


    ' ---------------------------------------------------------------
    ' If entire spool is straight, manufacture an arbitrary
    ' perpendicular V.
    ' ---------------------------------------------------------------

    If Not foundSecondary Then


        If Math.Abs(ux) < 0.8 Then

            sx = 1
            sy = 0
            sz = 0

        Else

            sx = 0
            sy = 1
            sz = 0

        End If

    End If


    ' ---------------------------------------------------------------
    ' Plane normal N = secondary x U.
    ' Then V = U x N.
    '
    ' This makes V point approximately in secondary direction.
    ' ---------------------------------------------------------------

    Dim nx As Double = _
        sy * uz - _
        sz * uy

    Dim ny As Double = _
        sz * ux - _
        sx * uz

    Dim nz As Double = _
        sx * uy - _
        sy * ux


    NormalizeVector(nx, ny, nz)


    Dim vx As Double = _
        uy * nz - _
        uz * ny

    Dim vy As Double = _
        uz * nx - _
        ux * nz

    Dim vz As Double = _
        ux * ny - _
        uy * nx


    NormalizeVector(vx, vy, vz)


    t.OriginX = originX
    t.OriginY = originY
    t.OriginZ = originZ

    t.UX = ux
    t.UY = uy
    t.UZ = uz

    t.VX = vx
    t.VY = vy
    t.VZ = vz


    ' ---------------------------------------------------------------
    ' Fit all primitive endpoints + references in panel.
    ' ---------------------------------------------------------------

    Dim samplePoints As New List(Of Point3DRecord)


    For Each s As PrimitiveSegment In primitives

        samplePoints.Add( _
            New Point3DRecord( _
                s.X1, s.Y1, s.Z1))

        samplePoints.Add( _
            New Point3DRecord( _
                s.X2, s.Y2, s.Z2))

    Next


    For Each n As NodeRecord In nodes

        samplePoints.Add( _
            New Point3DRecord( _
                n.RefX, _
                n.RefY, _
                n.RefZ))

    Next


    Dim minU As Double = Double.MaxValue
    Dim maxU As Double = Double.MinValue

    Dim minV As Double = Double.MaxValue
    Dim maxV As Double = Double.MinValue


    For Each p As Point3DRecord In samplePoints


        Dim pu As Double = 0
        Dim pv As Double = 0


        ProjectToCanonical( _
            t, _
            p.X, p.Y, p.Z, _
            pu, pv)


        If pu < minU Then minU = pu
        If pu > maxU Then maxU = pu

        If pv < minV Then minV = pv
        If pv > maxV Then maxV = pv

    Next


    If samplePoints.Count = 0 Then

        minU = 0
        maxU = 1
        minV = 0
        maxV = 1

    End If


    Dim rangeU As Double = maxU - minU
    Dim rangeV As Double = maxV - minV


    If rangeU < 1 Then rangeU = 1
    If rangeV < 1 Then rangeV = 1


    ' Leave plenty of space for dimensions.
    Dim geometryW As Double = w * 0.82
    Dim geometryH As Double = h * 0.68


    Dim scaleU As Double = geometryW / rangeU
    Dim scaleV As Double = geometryH / rangeV


    t.Scale = Math.Min(scaleU, scaleV)


    Dim usedW As Double = rangeU * t.Scale
    Dim usedH As Double = rangeV * t.Scale


    t.ScreenOriginX = _
        x + _
        (w - usedW) / 2.0 - _
        minU * t.Scale

    t.ScreenOriginY = _
        y + _
        (h - usedH) / 2.0 + _
        maxV * t.Scale


    Return t

End Function



Function IsFlangeOuterPoint( _
    nodes As List(Of NodeRecord), _
    x As Double, _
    y As Double, _
    z As Double) As Boolean


    For Each n As NodeRecord In nodes


        If n.ComponentType <> "FLANGE" OrElse _
           Not n.HasOuterAnchor Then

            Continue For
        End If


        If Dist3D( _
            x, y, z, _
            n.OuterX, n.OuterY, n.OuterZ) <= 0.5 Then

            Return True

        End If

    Next


    Return False

End Function



Sub ProjectToCanonical( _
    t As SchematicTransform, _
    x As Double, _
    y As Double, _
    z As Double, _
    ByRef u As Double, _
    ByRef v As Double)


    Dim dx As Double = x - t.OriginX
    Dim dy As Double = y - t.OriginY
    Dim dz As Double = z - t.OriginZ


    u = _
        dx * t.UX + _
        dy * t.UY + _
        dz * t.UZ

    v = _
        dx * t.VX + _
        dy * t.VY + _
        dz * t.VZ

End Sub



Function MapCanonicalPoint( _
    t As SchematicTransform, _
    x As Double, _
    y As Double, _
    z As Double) As SvgPoint


    Dim u As Double = 0
    Dim v As Double = 0


    ProjectToCanonical( _
        t, _
        x, y, z, _
        u, v)


    Return _
        New SvgPoint( _
            t.ScreenOriginX + _
            u * t.Scale, _
            t.ScreenOriginY - _
            v * t.Scale)

End Function



' ===================================================================
' DRAW MANUFACTURING GEOMETRY
' ===================================================================

Sub DrawManufacturingGeometry( _
    svg As StringBuilder, _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord), _
    primitives As List(Of PrimitiveSegment), _
    transform As SchematicTransform)


    ' ---------------------------------------------------------------
    ' Generic straight primitives except flange and elbow radial.
    ' ---------------------------------------------------------------

    For Each p As PrimitiveSegment In primitives


        If p.Kind = "FLANGE" Then
            Continue For
        End If


        If p.Kind = "ELBOW_RADIAL" Then
            Continue For
        End If


        Dim a As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                p.X1, p.Y1, p.Z1)

        Dim b As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                p.X2, p.Y2, p.Z2)


        svg.AppendLine( _
            "<line x1=""" & Num(a.X) & _
            """ y1=""" & Num(a.Y) & _
            """ x2=""" & Num(b.X) & _
            """ y2=""" & Num(b.Y) & _
            """ stroke=""black"" stroke-width=""5"" stroke-linecap=""round""/>")

    Next


    ' ---------------------------------------------------------------
    ' Flanges = two short perpendicular face lines separated by the
    ' extracted flange thickness.
    ' ---------------------------------------------------------------

    For Each n As NodeRecord In nodes


        If n.ComponentType <> "FLANGE" OrElse _
           Not n.HasOuterAnchor Then

            Continue For
        End If


        Dim hostPort As PortRecord = _
            GetHostSidePortForFlange( _
                n, _
                edges)


        If hostPort Is Nothing Then
            Continue For
        End If


        Dim innerP As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                hostPort.X, _
                hostPort.Y, _
                hostPort.Z)

        Dim outerP As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                n.OuterX, _
                n.OuterY, _
                n.OuterZ)


        svg.AppendLine( _
            "<line x1=""" & Num(innerP.X) & _
            """ y1=""" & Num(innerP.Y) & _
            """ x2=""" & Num(outerP.X) & _
            """ y2=""" & Num(outerP.Y) & _
            """ stroke=""black"" stroke-width=""4""/>")


        DrawPerpendicularFaceLine( _
            svg, _
            innerP, _
            outerP, _
            innerP, _
            42)


        DrawPerpendicularFaceLine( _
            svg, _
            innerP, _
            outerP, _
            outerP, _
            54)

    Next


    ' ---------------------------------------------------------------
    ' Elbow arcs.
    ' ---------------------------------------------------------------

    For Each n As NodeRecord In nodes


        If n.ComponentType <> "ELBOW" Then
            Continue For
        End If


        Dim ports As List(Of PortRecord) = _
            GetUsedPorts(n, edges)


        If ports.Count < 2 Then
            Continue For
        End If


        Dim p1 As PortRecord = ports.Item(0)
        Dim p2 As PortRecord = ports.Item(1)


        DrawElbowArc( _
            svg, _
            n, _
            p1, _
            p2, _
            transform)

    Next


    ' ---------------------------------------------------------------
    ' Terminal caps for non-flange endpoints.
    ' ---------------------------------------------------------------

    For Each n As NodeRecord In nodes


        If n.Neighbours.Count <> 1 Then
            Continue For
        End If


        If n.ComponentType = "FLANGE" Then
            Continue For
        End If


        Dim active As List(Of PortRecord) = _
            GetUsedPorts(n, edges)


        If active.Count = 0 Then
            Continue For
        End If


        ' Choose unused geometric port farthest from used port if known.
        Dim endPoint As Point3DRecord = Nothing


        If active.Count >= 2 Then

            ' Endpoint component can still have two used ports in odd cases.
            endPoint = _
                New Point3DRecord( _
                    n.RefX, n.RefY, n.RefZ)

        Else

            Dim used As PortRecord = active.Item(0)
            Dim best As PortRecord = Nothing
            Dim bestD As Double = -1


            For Each candidate As PortRecord In n.Ports


                Dim d As Double = _
                    Dist3D( _
                        used.X, used.Y, used.Z, _
                        candidate.X, candidate.Y, candidate.Z)


                If d > bestD Then

                    bestD = d
                    best = candidate

                End If

            Next


            If best IsNot Nothing Then

                endPoint = _
                    New Point3DRecord( _
                        best.X, best.Y, best.Z)

            End If

        End If


        If endPoint IsNot Nothing Then


            Dim ep As SvgPoint = _
                MapCanonicalPoint( _
                    transform, _
                    endPoint.X, _
                    endPoint.Y, _
                    endPoint.Z)


            Dim np As SvgPoint = _
                MapCanonicalPoint( _
                    transform, _
                    n.Neighbours.Item(0).RefX, _
                    n.Neighbours.Item(0).RefY, _
                    n.Neighbours.Item(0).RefZ)


            DrawPerpendicularEndCap( _
                svg, _
                ep, _
                np, _
                34)

        End If

    Next

End Sub



Sub DrawPerpendicularFaceLine( _
    svg As StringBuilder, _
    axisA As SvgPoint, _
    axisB As SvgPoint, _
    center As SvgPoint, _
    length As Double)


    Dim dx As Double = axisB.X - axisA.X
    Dim dy As Double = axisB.Y - axisA.Y


    Dim dl As Double = _
        Math.Sqrt( _
            dx * dx + _
            dy * dy)


    If dl < 0.001 Then
        Exit Sub
    End If


    dx /= dl
    dy /= dl


    Dim nx As Double = -dy
    Dim ny As Double = dx


    Dim half As Double = length / 2.0


    svg.AppendLine( _
        "<line x1=""" & Num(center.X - nx * half) & _
        """ y1=""" & Num(center.Y - ny * half) & _
        """ x2=""" & Num(center.X + nx * half) & _
        """ y2=""" & Num(center.Y + ny * half) & _
        """ stroke=""black"" stroke-width=""4""/>")

End Sub



Sub DrawPerpendicularEndCap( _
    svg As StringBuilder, _
    endPoint As SvgPoint, _
    towardPoint As SvgPoint, _
    length As Double)


    DrawPerpendicularFaceLine( _
        svg, _
        endPoint, _
        towardPoint, _
        endPoint, _
        length)

End Sub



Sub DrawElbowArc( _
    svg As StringBuilder, _
    elbow As NodeRecord, _
    port1 As PortRecord, _
    port2 As PortRecord, _
    transform As SchematicTransform)


    ' ===============================================================
    ' V0.8 - THIN 90 DEGREE ELBOW SYMBOL
    '
    ' This is intentionally NOT a pipe profile and NOT a curved
    ' centerline.  The verification schematic uses a simple routing
    ' symbol:
    '
    '        -----------+
    '                   |
    '                   |
    '
    ' The corner is the extracted elbow reference point: the
    ' intersection of the two port axes.  This keeps the schematic
    ' visually close to fabrication-style routing while dimensions
    ' continue to use the real extracted 305 mm geometry.
    ' ===============================================================

    Dim corner As SvgPoint = _
        MapCanonicalPoint( _
            transform, _
            elbow.RefX, _
            elbow.RefY, _
            elbow.RefZ)

    Dim a As SvgPoint = _
        MapCanonicalPoint( _
            transform, _
            port1.X, _
            port1.Y, _
            port1.Z)

    Dim b As SvgPoint = _
        MapCanonicalPoint( _
            transform, _
            port2.X, _
            port2.Y, _
            port2.Z)


    svg.AppendLine( _
        "<path d=""M " & _
        Num(a.X) & " " & Num(a.Y) & _
        " L " & _
        Num(corner.X) & " " & Num(corner.Y) & _
        " L " & _
        Num(b.X) & " " & Num(b.Y) & _
        """ fill=""none"" stroke=""black"" stroke-width=""3"" " & _
        "stroke-linejoin=""miter"" stroke-linecap=""square""/>")

End Sub



' ===================================================================
' COMPONENT LABELS
' ===================================================================

Sub DrawComponentLabels( _
    svg As StringBuilder, _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord), _
    transform As SchematicTransform)


    ' Labels are deliberately kept away from the dimension zones.
    ' For elbows, place E1 near the ACTUAL DRAWN ARC instead of at the
    ' theoretical tangent-intersection / bend-center reference point.

    For Each n As NodeRecord In nodes


        Dim p As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                n.RefX, _
                n.RefY, _
                n.RefZ)


        Dim labelX As Double = p.X + 10
        Dim labelY As Double = p.Y - 14
        Dim anchor As String = "start"


        If n.ComponentType = "PIPE" Then

            labelX = p.X
            labelY = p.Y - 16
            anchor = "middle"

        ElseIf n.ComponentType = "TEE" Then

            labelX = p.X + 12
            labelY = p.Y - 14
            anchor = "start"

        ElseIf n.ComponentType = "ELBOW" Then

            ' V0.8: elbow is drawn as a thin 90-degree routing symbol.
            ' Keep the label beside its extracted corner/reference point.
            labelX = p.X + 14
            labelY = p.Y - 14
            anchor = "start"

        ElseIf n.ComponentType = "FLANGE" Then

            ' Place flange labels on the geometry side, not on the
            ' dimension side.  Use neighbour direction to determine
            ' whether the flange axis is mainly horizontal or vertical.
            If n.Neighbours.Count > 0 Then

                Dim q As SvgPoint = _
                    MapCanonicalPoint( _
                        transform, _
                        n.Neighbours.Item(0).RefX, _
                        n.Neighbours.Item(0).RefY, _
                        n.Neighbours.Item(0).RefZ)

                Dim dx As Double = p.X - q.X
                Dim dy As Double = p.Y - q.Y

                If Math.Abs(dx) >= Math.Abs(dy) Then

                    labelX = p.X
                    labelY = p.Y - 18
                    anchor = "middle"

                Else

                    labelX = p.X - 16
                    labelY = p.Y + 4
                    anchor = "end"

                End If

            Else

                labelX = p.X
                labelY = p.Y - 18
                anchor = "middle"

            End If

        End If


        svg.AppendLine( _
            "<text x=""" & Num(labelX) & _
            """ y=""" & Num(labelY) & _
            """ text-anchor=""" & anchor & _
            """ font-family=""Arial"" font-size=""13"" font-weight=""bold"" " & _
            "style=""paint-order:stroke;stroke:white;stroke-width:5px;stroke-linejoin:round"">" & _
            XmlText(n.Code) & _
            "</text>")

    Next

End Sub


' ===================================================================
' DIMENSION DRAWING
' ===================================================================

Sub DrawAllDimensions( _
    svg As StringBuilder, _
    componentDimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain), _
    overallDimensions As List(Of DimensionRecord), _
    transform As SchematicTransform)


    Dim longestChainIndex As Integer = 0
    Dim longestLength As Double = -1


    For Each c As StraightChain In chains

        If c.Length > longestLength Then

            longestLength = c.Length
            longestChainIndex = c.Index

        End If

    Next


    For Each chain As StraightChain In chains


        Dim chainA As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                chain.X1, _
                chain.Y1, _
                chain.Z1)

        Dim chainB As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                chain.X2, _
                chain.Y2, _
                chain.Z2)


        Dim normalX As Double = 0
        Dim normalY As Double = 0


        ChooseDimensionNormal( _
            chainA, _
            chainB, _
            chain.Index = longestChainIndex, _
            normalX, _
            normalY)


        ' -----------------------------------------------------------
        ' Level 1: component / fabrication dimensions.
        ' Main run dimensions sit below the spool.  Secondary vertical
        ' runs sit to the right.  Extra spacing keeps 178/193 and
        ' 305/320 visually separate.
        ' -----------------------------------------------------------

        Dim componentOffset As Double = 46.0

        If chain.Index = longestChainIndex Then
            componentOffset = 42.0
        End If


        For Each d As DimensionRecord In componentDimensions

            If d.ChainIndex <> chain.Index Then
                Continue For
            End If

            DrawOneDimension( _
                svg, _
                d, _
                transform, _
                normalX, _
                normalY, _
                componentOffset, _
                False)

        Next


        ' -----------------------------------------------------------
        ' Level 2/3: overall run dimensions.
        ' Main 1276 is farthest from the geometry; secondary 193/320
        ' are pushed far enough away from their component dimensions.
        ' -----------------------------------------------------------

        Dim overallOffset As Double = 98.0

        If chain.Index = longestChainIndex Then
            overallOffset = 96.0
        End If


        For Each d As DimensionRecord In overallDimensions

            If d.ChainIndex <> chain.Index Then
                Continue For
            End If

            DrawOneDimension( _
                svg, _
                d, _
                transform, _
                normalX, _
                normalY, _
                overallOffset, _
                True)

        Next

    Next


    ' Any component dimension not assigned to a straight chain.
    For Each d As DimensionRecord In componentDimensions

        If d.ChainIndex <> 0 Then
            Continue For
        End If

        Dim a As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                d.X1, d.Y1, d.Z1)

        Dim b As SvgPoint = _
            MapCanonicalPoint( _
                transform, _
                d.X2, d.Y2, d.Z2)

        Dim nx As Double = 0
        Dim ny As Double = 0

        ChooseDimensionNormal(a, b, False, nx, ny)

        DrawOneDimension( _
            svg, _
            d, _
            transform, _
            nx, ny, _
            46.0, _
            False)

    Next

End Sub


Sub ChooseDimensionNormal( _
    a As SvgPoint, _
    b As SvgPoint, _
    isLongestMainRun As Boolean, _
    ByRef nx As Double, _
    ByRef ny As Double)


    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y


    Dim dl As Double = _
        Math.Sqrt( _
            dx * dx + _
            dy * dy)


    If dl < 0.001 Then

        nx = 0
        ny = 1

        Exit Sub

    End If


    dx /= dl
    dy /= dl


    nx = -dy
    ny = dx


    ' ---------------------------------------------------------------
    ' Primary longest run:
    ' always place dimensions below the main run.
    ' ---------------------------------------------------------------

    If isLongestMainRun Then


        If ny < 0 Then

            nx *= -1
            ny *= -1

        End If


        Exit Sub

    End If


    ' ---------------------------------------------------------------
    ' Secondary near-vertical runs:
    ' put dimensions to the right.
    ' ---------------------------------------------------------------

    If Math.Abs(dy) > Math.Abs(dx) Then


        If nx < 0 Then

            nx *= -1
            ny *= -1

        End If


    Else

        ' Other secondary horizontal runs: below.
        If ny < 0 Then

            nx *= -1
            ny *= -1

        End If

    End If

End Sub



Sub DrawOneDimension( _
    svg As StringBuilder, _
    d As DimensionRecord, _
    transform As SchematicTransform, _
    nx As Double, _
    ny As Double, _
    offset As Double, _
    isOverall As Boolean)


    Dim a As SvgPoint = _
        MapCanonicalPoint( _
            transform, _
            d.X1, d.Y1, d.Z1)

    Dim b As SvgPoint = _
        MapCanonicalPoint( _
            transform, _
            d.X2, d.Y2, d.Z2)


    Dim da As New SvgPoint( _
        a.X + nx * offset, _
        a.Y + ny * offset)

    Dim db As New SvgPoint( _
        b.X + nx * offset, _
        b.Y + ny * offset)


    Dim lineDX As Double = db.X - da.X
    Dim lineDY As Double = db.Y - da.Y

    Dim pixelLength As Double = _
        Math.Sqrt( _
            lineDX * lineDX + _
            lineDY * lineDY)


    If pixelLength < 0.001 Then
        Exit Sub
    End If


    Dim ux As Double = lineDX / pixelLength
    Dim uy As Double = lineDY / pixelLength


    Dim extensionOvershoot As Double = 7.0

    Dim daExt As New SvgPoint( _
        da.X + nx * extensionOvershoot, _
        da.Y + ny * extensionOvershoot)

    Dim dbExt As New SvgPoint( _
        db.X + nx * extensionOvershoot, _
        db.Y + ny * extensionOvershoot)


    ' Extension lines deliberately overshoot the dimension line a little,
    ' closer to conventional fabrication drawing practice.
    svg.AppendLine( _
        "<line x1=""" & Num(a.X) & _
        """ y1=""" & Num(a.Y) & _
        """ x2=""" & Num(daExt.X) & _
        """ y2=""" & Num(daExt.Y) & _
        """ stroke=""black"" stroke-width=""0.8""/>")

    svg.AppendLine( _
        "<line x1=""" & Num(b.X) & _
        """ y1=""" & Num(b.Y) & _
        """ x2=""" & Num(dbExt.X) & _
        """ y2=""" & Num(dbExt.Y) & _
        """ stroke=""black"" stroke-width=""0.8""/>")


    Dim strokeWidth As Double = 1.0
    If isOverall Then strokeWidth = 1.5


    svg.AppendLine( _
        "<line x1=""" & Num(da.X) & _
        """ y1=""" & Num(da.Y) & _
        """ x2=""" & Num(db.X) & _
        """ y2=""" & Num(db.Y) & _
        """ stroke=""black"" stroke-width=""" & _
        Num(strokeWidth) & """/>")


    DrawDimensionTick(svg, da, db)
    DrawDimensionTick(svg, db, da)


    Dim textX As Double = (da.X + db.X) / 2.0
    Dim textY As Double = (da.Y + db.Y) / 2.0 - 6.0


    ' Short dimensions such as the 15 mm flange thickness cannot fit
    ' between the extension lines at normal schematic scale.  Put their
    ' text just outside the measured segment instead of stacking it on
    ' the flange symbol or another dimension.
    If pixelLength < 58.0 Then

        textX = db.X + ux * 28.0
        textY = db.Y + uy * 28.0 - 5.0

    End If


    Dim angle As Double = _
        Math.Atan2(lineDY, lineDX) * _
        180.0 / Math.PI

    If angle > 90 Then angle -= 180
    If angle < -90 Then angle += 180


    Dim textValue As String = _
        Math.Round(d.Value, 1) _
            .ToString( _
                "0.#", _
                CultureInfo.InvariantCulture)


    ' White text halo guarantees readability when dimensions cross the
    ' schematic or when several short dimensions are close together.
    svg.AppendLine( _
        "<text x=""" & Num(textX) & _
        """ y=""" & Num(textY) & _
        """ text-anchor=""middle"" " & _
        "font-family=""Arial"" font-size=""" & _
        If(isOverall, "15", "13") & _
        """ font-weight=""" & _
        If(isOverall, "bold", "normal") & _
        """ style=""paint-order:stroke;stroke:white;stroke-width:6px;stroke-linejoin:round"" " & _
        "transform=""rotate(" & _
        Num(angle) & " " & _
        Num(textX) & " " & _
        Num(textY) & ")"">" & _
        XmlText(textValue) & _
        "</text>")

End Sub


Sub DrawDimensionTick( _
    svg As StringBuilder, _
    atPoint As SvgPoint, _
    toward As SvgPoint)


    Dim dx As Double = toward.X - atPoint.X
    Dim dy As Double = toward.Y - atPoint.Y


    Dim dl As Double = _
        Math.Sqrt( _
            dx * dx + _
            dy * dy)


    If dl < 0.001 Then
        Exit Sub
    End If


    dx /= dl
    dy /= dl


    Dim nx As Double = -dy
    Dim ny As Double = dx


    Dim half As Double = 6


    svg.AppendLine( _
        "<line x1=""" & Num(atPoint.X - nx * half) & _
        """ y1=""" & Num(atPoint.Y - ny * half) & _
        """ x2=""" & Num(atPoint.X + nx * half) & _
        """ y2=""" & Num(atPoint.Y + ny * half) & _
        """ stroke=""black"" stroke-width=""1""/>")

End Sub



' ===================================================================
' DIMENSION SUMMARY TABLE
' ===================================================================

Sub DrawDimensionSummaryTable( _
    svg As StringBuilder, _
    componentDimensions As List(Of DimensionRecord), _
    overallDimensions As List(Of DimensionRecord), _
    x As Double, _
    y As Double)


    svg.AppendLine( _
        "<text x=""" & Num(x) & _
        """ y=""" & Num(y) & _
        """ font-family=""Arial"" font-size=""14"" font-weight=""bold"">" & _
        "EXTRACTED DIMENSIONS" & _
        "</text>")


    Dim cursorX As Double = x
    Dim cursorY As Double = y + 24


    For Each d As DimensionRecord In componentDimensions


        svg.AppendLine( _
            "<text x=""" & Num(cursorX) & _
            """ y=""" & Num(cursorY) & _
            """ font-family=""Arial"" font-size=""11"">" & _
            XmlText( _
                d.Label & _
                " = " & _
                FormatMm(d.Value)) & _
            "</text>")


        cursorY += 18


        If cursorY > 1020 Then

            cursorX += 260
            cursorY = y + 24

        End If

    Next


    cursorX += 320
    cursorY = y + 24


    For Each d As DimensionRecord In overallDimensions


        svg.AppendLine( _
            "<text x=""" & Num(cursorX) & _
            """ y=""" & Num(cursorY) & _
            """ font-family=""Arial"" font-size=""12"" font-weight=""bold"">" & _
            XmlText( _
                d.Label & _
                " = " & _
                FormatMm(d.Value)) & _
            "</text>")


        cursorY += 20

    Next

End Sub



' ===================================================================
' PORT / NODE HELPERS
' ===================================================================

Function GetHostSidePortForFlange( _
    flange As NodeRecord, _
    edges As List(Of EdgeRecord)) As PortRecord


    For Each e As EdgeRecord In edges


        If e.A Is flange Then

            Return e.PortB

        ElseIf e.B Is flange Then

            Return e.PortA

        End If

    Next


    Return Nothing

End Function



Function GetUsedPorts( _
    node As NodeRecord, _
    edges As List(Of EdgeRecord)) As List(Of PortRecord)


    Dim result As New List(Of PortRecord)


    For Each e As EdgeRecord In edges


        If e.A Is node Then

            AddPortReferenceIfMissing( _
                result, _
                e.PortA)

        ElseIf e.B Is node Then

            AddPortReferenceIfMissing( _
                result, _
                e.PortB)

        End If

    Next


    Return result

End Function



Sub AddPortReferenceIfMissing( _
    list As List(Of PortRecord), _
    port As PortRecord)


    For Each p As PortRecord In list

        If p Is port Then
            Exit Sub
        End If

    Next


    list.Add(port)

End Sub



Sub FindFarthestPortPair( _
    ports As List(Of PortRecord), _
    ByRef outA As PortRecord, _
    ByRef outB As PortRecord)


    outA = Nothing
    outB = Nothing


    Dim best As Double = -1


    For i As Integer = 0 To ports.Count - 2

        For j As Integer = i + 1 To ports.Count - 1


            Dim a As PortRecord = ports.Item(i)
            Dim b As PortRecord = ports.Item(j)


            Dim d As Double = _
                Dist3D( _
                    a.X, a.Y, a.Z, _
                    b.X, b.Y, b.Z)


            If d > best Then

                best = d
                outA = a
                outB = b

            End If

        Next

    Next

End Sub



Sub FindMostOpposedPortPair( _
    ports As List(Of PortRecord), _
    ByRef outA As PortRecord, _
    ByRef outB As PortRecord)


    outA = Nothing
    outB = Nothing


    Dim bestDot As Double = Double.MaxValue


    For i As Integer = 0 To ports.Count - 2

        For j As Integer = i + 1 To ports.Count - 1


            Dim a As PortRecord = ports.Item(i)
            Dim b As PortRecord = ports.Item(j)


            Dim dotValue As Double = _
                NormalDot(a, b)


            If dotValue < bestDot Then

                bestDot = dotValue
                outA = a
                outB = b

            End If

        Next

    Next

End Sub



Function ClosestAxisIntersection( _
    a As PortRecord, _
    b As PortRecord, _
    ByRef outX As Double, _
    ByRef outY As Double, _
    ByRef outZ As Double, _
    ByRef separation As Double) As Boolean


    Dim p1x As Double = a.X
    Dim p1y As Double = a.Y
    Dim p1z As Double = a.Z

    Dim p2x As Double = b.X
    Dim p2y As Double = b.Y
    Dim p2z As Double = b.Z


    Dim d1x As Double = a.NX
    Dim d1y As Double = a.NY
    Dim d1z As Double = a.NZ

    Dim d2x As Double = b.NX
    Dim d2y As Double = b.NY
    Dim d2z As Double = b.NZ


    Dim rx As Double = p1x - p2x
    Dim ry As Double = p1y - p2y
    Dim rz As Double = p1z - p2z


    Dim aa As Double = _
        d1x * d1x + _
        d1y * d1y + _
        d1z * d1z

    Dim bb As Double = _
        d1x * d2x + _
        d1y * d2y + _
        d1z * d2z

    Dim cc As Double = _
        d2x * d2x + _
        d2y * d2y + _
        d2z * d2z

    Dim dd As Double = _
        d1x * rx + _
        d1y * ry + _
        d1z * rz

    Dim ee As Double = _
        d2x * rx + _
        d2y * ry + _
        d2z * rz


    Dim denominator As Double = _
        aa * cc - _
        bb * bb


    If Math.Abs(denominator) < 0.0000001 Then
        Return False
    End If


    Dim t As Double = _
        (bb * ee - cc * dd) / denominator

    Dim s As Double = _
        (aa * ee - bb * dd) / denominator


    Dim c1x As Double = p1x + t * d1x
    Dim c1y As Double = p1y + t * d1y
    Dim c1z As Double = p1z + t * d1z

    Dim c2x As Double = p2x + s * d2x
    Dim c2y As Double = p2y + s * d2y
    Dim c2z As Double = p2z + s * d2z


    outX = (c1x + c2x) / 2.0
    outY = (c1y + c2y) / 2.0
    outZ = (c1z + c2z) / 2.0


    separation = _
        Dist3D( _
            c1x, c1y, c1z, _
            c2x, c2y, c2z)


    Return True

End Function



' ===================================================================
' GRAPH / CLASSIFICATION HELPERS
' ===================================================================

Sub AssignDisplayCodes( _
    nodes As List(Of NodeRecord))


    Dim counters As New Dictionary(Of String, Integer)


    For Each n As NodeRecord In nodes


        Dim prefix As String = "X"


        Select Case n.ComponentType

            Case "FLANGE"
                prefix = "F"

            Case "ELBOW"
                prefix = "E"

            Case "TEE"
                prefix = "T"

            Case "PIPE"
                prefix = "P"

            Case "REDUCER"
                prefix = "R"

            Case "VALVE"
                prefix = "V"

            Case "COUPLING_SOCKET"
                prefix = "C"

            Case Else
                prefix = "X"

        End Select


        If Not counters.ContainsKey(prefix) Then
            counters.Add(prefix, 0)
        End If


        counters(prefix) = _
            counters(prefix) + 1


        n.Code = _
            prefix & _
            counters(prefix).ToString()

    Next

End Sub



Function CountGraphGroups( _
    nodes As List(Of NodeRecord)) As Integer


    Dim visited As New HashSet(Of NodeRecord)
    Dim groups As Integer = 0


    For Each n As NodeRecord In nodes


        If visited.Contains(n) Then
            Continue For
        End If


        groups += 1

        FloodVisit(n, visited)

    Next


    Return groups

End Function



Sub FloodVisit( _
    node As NodeRecord, _
    visited As HashSet(Of NodeRecord))


    If visited.Contains(node) Then
        Exit Sub
    End If


    visited.Add(node)


    For Each nextNode As NodeRecord In node.Neighbours

        FloodVisit( _
            nextNode, _
            visited)

    Next

End Sub



Function HasConnection( _
    edges As List(Of EdgeRecord), _
    a As NodeRecord, _
    b As NodeRecord) As Boolean


    For Each e As EdgeRecord In edges


        If e.A Is a AndAlso e.B Is b Then
            Return True
        End If


        If e.A Is b AndAlso e.B Is a Then
            Return True
        End If

    Next


    Return False

End Function



Function GetNeighbourCodes( _
    node As NodeRecord) As List(Of String)


    Dim result As New List(Of String)


    For Each n As NodeRecord In node.Neighbours

        result.Add(n.Code)

    Next


    Return result

End Function



Function GuessComponentType( _
    partNumber As String, _
    description As String, _
    occurrenceName As String) As String


    Dim text As String = _
        (partNumber & " " & _
         description & " " & _
         occurrenceName).ToLowerInvariant()


    If Regex.IsMatch(text, "\bflange\b") Then

        Return "FLANGE"

    ElseIf Regex.IsMatch(text, "\breducer\b") Then

        Return "REDUCER"

    ElseIf Regex.IsMatch(text, "\b(elbow|bend)\b") Then

        Return "ELBOW"

    ElseIf Regex.IsMatch(text, "\btee\b") Then

        Return "TEE"

    ElseIf Regex.IsMatch(text, "\bvalve\b") Then

        Return "VALVE"

    ElseIf Regex.IsMatch( _
        text, _
        "\b(socket|coupling|union)\b") Then

        Return "COUPLING_SOCKET"

    ElseIf Regex.IsMatch(text, "\b(pipe|tube)\b") Then

        Return "PIPE"

    End If


    Return "OTHER"

End Function



' ===================================================================
' MATH / IO HELPERS
' ===================================================================

Sub AddPortIfUnique( _
    ports As List(Of PortRecord), _
    newPort As PortRecord)


    For Each existing As PortRecord In ports


        Dim separation As Double = _
            Dist3D( _
                existing.X, _
                existing.Y, _
                existing.Z, _
                newPort.X, _
                newPort.Y, _
                newPort.Z)


        If separation < 0.1 Then


            Dim alignment As Double = _
                Math.Abs( _
                    NormalDot( _
                        existing, _
                        newPort))


            If alignment > 0.99 Then
                Exit Sub
            End If

        End If

    Next


    ports.Add(newPort)

End Sub



Function NormalDot( _
    a As PortRecord, _
    b As PortRecord) As Double


    Return _
        a.NX * b.NX + _
        a.NY * b.NY + _
        a.NZ * b.NZ

End Function



Function Dist3D( _
    x1 As Double, _
    y1 As Double, _
    z1 As Double, _
    x2 As Double, _
    y2 As Double, _
    z2 As Double) As Double


    Dim dx As Double = x2 - x1
    Dim dy As Double = y2 - y1
    Dim dz As Double = z2 - z1


    Return _
        Math.Sqrt( _
            dx * dx + _
            dy * dy + _
            dz * dz)

End Function



Sub NormalizeVector( _
    ByRef x As Double, _
    ByRef y As Double, _
    ByRef z As Double)


    Dim l As Double = _
        Math.Sqrt( _
            x * x + _
            y * y + _
            z * z)


    If l < 0.000001 Then

        x = 1
        y = 0
        z = 0

        Exit Sub

    End If


    x /= l
    y /= l
    z /= l

End Sub



Function GetIProperty( _
    doc As Document, _
    propertySetName As String, _
    propertyName As String) As String


    Try

        Return _
            doc.PropertySets _
               .Item(propertySetName) _
               .Item(propertyName) _
               .Value _
               .ToString() _
               .Trim()

    Catch

        Return ""

    End Try

End Function



Function Csv(value As String) As String


    If value Is Nothing Then
        value = ""
    End If


    Return _
        """" & _
        value.Replace("""", """""") & _
        """"

End Function



Function Num(value As Double) As String


    Return _
        value.ToString( _
            "0.###", _
            CultureInfo.InvariantCulture)

End Function



Function FormatMm(value As Double) As String


    Return _
        Math.Round(value, 1) _
            .ToString( _
                "0.#", _
                CultureInfo.InvariantCulture) & _
        " mm"

End Function



Function XmlText(value As String) As String


    If value Is Nothing Then
        Return ""
    End If


    Return _
        value.Replace("&", "&amp;") _
             .Replace("<", "&lt;") _
             .Replace(">", "&gt;") _
             .Replace("""", "&quot;")

End Function



Function SafeFileName(value As String) As String


    For Each invalidChar As Char In _
        System.IO.Path.GetInvalidFileNameChars()


        value = _
            value.Replace( _
                invalidChar, _
                "_"c)

    Next


    Return value

End Function





' ===================================================================
' DIMENSION GENERATOR V0.5 - TOPOLOGY-GUIDED BISECTORS + CHAINS
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

    Try
        For i As Integer = sheet.Centerlines.Count To 1 Step -1
            If IsAutoTaggedV01(sheet.Centerlines.Item(i)) Then
                sheet.Centerlines.Item(i).Delete()
            End If
        Next
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


Function ResolveProjectedAnchorsV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchors As List(Of AutoDimAnchorV01)) As Integer

    Dim unresolved As Integer = 0

    For Each anchor As AutoDimAnchorV01 In anchors

        anchor.Intent = _
            ResolveProjectedIntentV03( _
                sheet, view, nodes, anchor)

        If anchor.Intent Is Nothing Then
            unresolved += 1

            Dim nearNode As NodeRecord = _
                FindReferenceNodeAtPointV03( _
                    nodes, anchor.X, anchor.Y, anchor.Z, 1.0)

            Dim semanticName As String = "UNKNOWN"
            If nearNode IsNot Nothing Then
                semanticName = _
                    nearNode.Code & "/" & nearNode.ComponentType & "/" & nearNode.ReferenceType
            End If

            Logger.Error( _
                "No projected geometry for semantic anchor " & semanticName & _
                " at model mm (" & _
                Num(anchor.X) & ", " & Num(anchor.Y) & ", " & Num(anchor.Z) & ")")
        End If

    Next

    Return unresolved
End Function


Sub CreateAutomatedCenterlinesV03( _
    sheet As Sheet, _
    view As DrawingView)

    Try
        Dim settings As AutomatedCenterlineSettings = Nothing
        view.GetAutomatedCenterlineSettings(settings)

        settings.ApplyToCylinders = True
        settings.ProjectionParallelAxis = True
        settings.ProjectionNormalAxis = True

        ' Keep the command focused on piping axes, not bolt holes/patterns.
        settings.ApplyToHoles = False
        settings.ApplyToCircularPatterns = False
        settings.ApplyToRectangularPatterns = False
        settings.ApplyToPunches = False
        settings.ApplyToFillets = False
        settings.ApplyToSketches = False
        settings.ApplyToWorkFeatures = False

        Dim created As ObjectsEnumerator = _
            view.SetAutomatedCenterlineSettings(settings)

        If created IsNot Nothing Then
            For i As Integer = 1 To created.Count
                Dim obj As Object = created.Item(i)
                If TypeOf obj Is Centerline Then
                    TagAutoObjectV01(obj)
                End If
            Next
        End If

    Catch ex As Exception
        Logger.Error("Automated centerline command failed: " & ex.Message)
    End Try
End Sub


Function ResolveProjectedIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchor As AutoDimAnchorV01) As GeometryIntent

    ' ===============================================================
    ' V0.4 CONTROLLED RESOLUTION
    '
    ' 1) Real port/face anchors -> ACTUAL projected DrawingCurve.
    ' 2) TEE / ELBOW theoretical centre -> create at most two native
    '    AddBisector centerlines from opposite parallel projected lines
    '    of THAT occurrence only, then use their intersection.
    '
    ' NO automated-centerline command and NO global centerline search.
    ' ===============================================================

    Dim port As PortRecord = _
        FindPortAtModelPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.6)

    If port IsNot Nothing AndAlso _
       port.Owner IsNot Nothing AndAlso _
       port.Owner.Occurrence IsNot Nothing Then

        Dim projectedIntent As GeometryIntent = _
            FindOccurrenceDrawingIntentV031( _
                sheet, _
                view, _
                port.Owner.Occurrence, _
                anchor.SheetPoint)

        If projectedIntent IsNot Nothing Then
            anchor.SourceDescription = _
                port.Owner.Code & " PROJECTED CURVE NEAR FACE " & _
                port.FaceIndex.ToString()
            Return projectedIntent
        End If
    End If

    Dim refNode As NodeRecord = _
        FindReferenceNodeAtPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.8)

    If refNode Is Nothing Then Return Nothing

    If refNode.ComponentType <> "TEE" AndAlso _
       refNode.ComponentType <> "ELBOW" Then
        Return Nothing
    End If

    Dim centreIntent As GeometryIntent = _
        ResolveFittingCenterIntentV04( _
            sheet, _
            view, _
            refNode, _
            anchor.SheetPoint)

    If centreIntent IsNot Nothing Then
        anchor.SourceDescription = _
            refNode.Code & " NATIVE BISECTOR CENTERLINE"
    End If

    Return centreIntent
End Function


Function FindOccurrenceDrawingIntentV031( _
    sheet As Sheet, _
    view As DrawingView, _
    occurrence As ComponentOccurrence, _
    target As Point2d) As GeometryIntent

    If occurrence Is Nothing OrElse target Is Nothing Then Return Nothing

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(occurrence)

        If curves Is Nothing OrElse curves.Count = 0 Then Return Nothing

        Dim best As DrawingCurve = Nothing
        Dim bestDistance As Double = 0.18

        For Each c As DrawingCurve In curves
            Dim d As Double = DrawingCurveDistanceV03(c, target)
            If d <= bestDistance Then
                bestDistance = d
                best = c
            End If
        Next

        If best Is Nothing Then Return Nothing

        ' Prefer the actual projected line itself for end-face dimensions.
        If best.CurveType = CurveTypeEnum.kLineSegmentCurve Then
            Return sheet.CreateGeometryIntent(best)
        End If

        ' If a circular face is viewed normal-on, its centre is the semantic
        ' axis location and is a valid drawing-curve intent.
        If best.CurveType = CurveTypeEnum.kCircleCurve OrElse _
           best.CurveType = CurveTypeEnum.kCircularArcCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipseFullCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipticalArcCurve Then

            Return _
                sheet.CreateGeometryIntent( _
                    best, _
                    PointIntentEnum.kCenterPointIntent)
        End If

        Return Nothing

    Catch ex As Exception
        Logger.Error( _
            "Safe DrawingCurves(occurrence) resolve failed for " & _
            occurrence.Name & ": " & ex.Message)
        Return Nothing
    End Try
End Function




Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' ===============================================================
    ' V0.5
    ' Use the fitting's USED topology port axes to tell Inventor which
    ' centreline directions we actually need.  For each visible axis we
    ' search the fitting + directly connected occurrences for the two
    ' projected silhouette lines parallel to that axis and create the
    ' native Inventor Centerline using Centerlines.AddBisector.
    ' ===============================================================

    Dim centerlines As List(Of Centerline) = _
        CreateTopologyGuidedBisectorsV05( _
            sheet, _
            view, _
            node, _
            target)

    If centerlines.Count >= 2 Then
        For i As Integer = 0 To centerlines.Count - 2
            For j As Integer = i + 1 To centerlines.Count - 1

                If CenterlinesParallelV03( _
                    centerlines.Item(i), _
                    centerlines.Item(j)) Then
                    Continue For
                End If

                Try
                    Return _
                        sheet.CreateGeometryIntent( _
                            centerlines.Item(i), _
                            centerlines.Item(j))
                Catch ex As Exception
                    Logger.Error( _
                        "Centerline intersection intent failed for " & _
                        node.Code & ": " & ex.Message)
                End Try
            Next
        Next
    End If

    If centerlines.Count = 1 Then
        Try
            Return sheet.CreateGeometryIntent(centerlines.Item(0))
        Catch ex As Exception
            Logger.Error( _
                "Single centerline intent failed for " & _
                node.Code & ": " & ex.Message)
        End Try
    End If

    Return Nothing
End Function


Function CreateTopologyGuidedBisectorsV05( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As List(Of Centerline)

    Dim result As New List(Of Centerline)

    If node Is Nothing OrElse _
       node.Occurrence Is Nothing OrElse _
       target Is Nothing Then
        Return result
    End If

    Dim axes As List(Of AxisDirectionV05) = _
        GetVisibleTopologyAxesV05( _
            view, _
            node, _
            target)

    Logger.Info( _
        "Centerline search " & node.Code & _
        " visible topology axes=" & axes.Count.ToString())

    If axes.Count = 0 Then Return result

    Dim occurrences As New List(Of ComponentOccurrence)
    occurrences.Add(node.Occurrence)

    For Each neighbour As NodeRecord In node.Neighbours
        If neighbour IsNot Nothing AndAlso _
           neighbour.Occurrence IsNot Nothing Then

            Dim alreadyAdded As Boolean = False
            For Each existing As ComponentOccurrence In occurrences
                If existing Is neighbour.Occurrence Then
                    alreadyAdded = True
                    Exit For
                End If
            Next

            If Not alreadyAdded Then
                occurrences.Add(neighbour.Occurrence)
            End If
        End If
    Next

    For Each axis As AxisDirectionV05 In axes

        Dim pair As AxisLinePairV05 = _
            FindBestSilhouettePairForAxisV05( _
                view, _
                occurrences, _
                target, _
                axis.UX, _
                axis.UY)

        If pair Is Nothing Then
            Logger.Error( _
                "No silhouette pair found for " & node.Code & _
                " axis=" & Num(axis.UX) & "," & Num(axis.UY))
            Continue For
        End If

        Try
            Dim intentA As GeometryIntent = _
                sheet.CreateGeometryIntent(pair.A)
            Dim intentB As GeometryIntent = _
                sheet.CreateGeometryIntent(pair.B)

            Dim cl As Centerline = _
                sheet.Centerlines.AddBisector( _
                    intentA, _
                    intentB)

            If cl Is Nothing Then Continue For

            Dim clx As Double = cl.EndPoint.X - cl.StartPoint.X
            Dim cly As Double = cl.EndPoint.Y - cl.StartPoint.Y
            Dim clLength As Double = Math.Sqrt(clx * clx + cly * cly)

            If clLength < 0.0001 Then
                Try : cl.Delete() : Catch : End Try
                Continue For
            End If

            clx /= clLength : cly /= clLength

            Dim directionAlignment As Double = _
                Math.Abs(clx * axis.UX + cly * axis.UY)

            Dim centreError As Double = _
                DistancePointToInfiniteLineV03( _
                    target, _
                    cl.StartPoint, _
                    cl.EndPoint)

            If directionAlignment < 0.96 OrElse _
               centreError > 0.16 Then

                Logger.Error( _
                    "Rejected bisector for " & node.Code & _
                    " alignment=" & Num(directionAlignment) & _
                    " centreError=" & Num(centreError))

                Try : cl.Delete() : Catch : End Try
                Continue For
            End If

            TagAutoObjectV01(cl)
            result.Add(cl)

            Logger.Info( _
                "Created topology-guided bisector for " & _
                node.Code & _
                " axis=" & Num(axis.UX) & "," & Num(axis.UY) & _
                " pairScore=" & Num(pair.Score))

        Catch ex As Exception
            Logger.Error( _
                "AddBisector failed for " & _
                node.Code & _
                " axis=" & Num(axis.UX) & "," & Num(axis.UY) & _
                ": " & ex.Message)
        End Try

    Next

    Return result
End Function


Function GetVisibleTopologyAxesV05( _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As List(Of AxisDirectionV05)

    Dim result As New List(Of AxisDirectionV05)

    If node Is Nothing Then Return result

    For Each port As PortRecord In node.Ports

        If Not port.Used Then Continue For

        Dim p0 As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                node.RefX / 10.0, _
                node.RefY / 10.0, _
                node.RefZ / 10.0)

        Dim p1 As Inventor.Point = _
            ThisApplication.TransientGeometry.CreatePoint( _
                (node.RefX + port.NX * 100.0) / 10.0, _
                (node.RefY + port.NY * 100.0) / 10.0, _
                (node.RefZ + port.NZ * 100.0) / 10.0)

        Dim s0 As Point2d = view.ModelToSheetSpace(p0)
        Dim s1 As Point2d = view.ModelToSheetSpace(p1)

        Dim ux As Double = s1.X - s0.X
        Dim uy As Double = s1.Y - s0.Y
        Dim l As Double = Math.Sqrt(ux * ux + uy * uy)

        ' Port axis nearly normal to the drawing view: no useful 2D centreline.
        If l < 0.02 Then Continue For

        ux /= l : uy /= l

        ' Normalise sign so opposite port normals collapse to one axis.
        If ux < -0.0001 OrElse _
           (Math.Abs(ux) <= 0.0001 AndAlso uy < 0) Then
            ux *= -1.0
            uy *= -1.0
        End If

        Dim duplicate As Boolean = False
        For Each existing As AxisDirectionV05 In result
            Dim dot As Double = _
                Math.Abs(existing.UX * ux + existing.UY * uy)
            If dot > 0.97 Then
                duplicate = True
                Exit For
            End If
        Next

        If Not duplicate Then
            Dim a As New AxisDirectionV05
            a.UX = ux
            a.UY = uy
            result.Add(a)
        End If

    Next

    Return result
End Function


Function FindBestSilhouettePairForAxisV05( _
    view As DrawingView, _
    occurrences As List(Of ComponentOccurrence), _
    target As Point2d, _
    axisUX As Double, _
    axisUY As Double) As AxisLinePairV05

    Dim lines As New List(Of DrawingCurve)

    For Each occ As ComponentOccurrence In occurrences
        Try
            Dim curves As DrawingCurvesEnumerator = _
                view.DrawingCurves(occ)

            If curves Is Nothing Then Continue For

            For Each c As DrawingCurve In curves
                If c.CurveType <> CurveTypeEnum.kLineSegmentCurve Then
                    Continue For
                End If

                If c.StartPoint Is Nothing OrElse c.EndPoint Is Nothing Then
                    Continue For
                End If

                Dim dx As Double = c.EndPoint.X - c.StartPoint.X
                Dim dy As Double = c.EndPoint.Y - c.StartPoint.Y
                Dim l As Double = Math.Sqrt(dx * dx + dy * dy)

                If l < 0.10 Then Continue For

                dx /= l : dy /= l

                Dim alignment As Double = _
                    Math.Abs(dx * axisUX + dy * axisUY)

                If alignment < 0.96 Then Continue For

                lines.Add(c)
            Next

        Catch ex As Exception
            Logger.Error( _
                "DrawingCurves occurrence scan failed for centerline pair: " & _
                occ.Name & ": " & ex.Message)
        End Try
    Next

    Dim best As AxisLinePairV05 = Nothing
    Dim bestScore As Double = Double.MaxValue

    For i As Integer = 0 To lines.Count - 2
        For j As Integer = i + 1 To lines.Count - 1

            Dim a As DrawingCurve = lines.Item(i)
            Dim b As DrawingCurve = lines.Item(j)

            If Not DrawingLinesParallelV03(a, b) Then Continue For

            Dim da As Double = _
                SignedDistanceToLineV03( _
                    target, a.StartPoint, a.EndPoint)
            Dim db As Double = _
                SignedDistanceToLineV03( _
                    target, b.StartPoint, b.EndPoint)

            ' Correct pipe silhouettes must sit on opposite sides of axis.
            If da * db >= 0 Then Continue For

            Dim absA As Double = Math.Abs(da)
            Dim absB As Double = Math.Abs(db)
            Dim separation As Double = absA + absB

            If separation < 0.04 Then Continue For

            Dim symmetryError As Double = Math.Abs(absA - absB)
            Dim symmetryTolerance As Double = _
                Math.Max(0.10, separation * 0.28)

            If symmetryError > symmetryTolerance Then Continue For

            Dim segA As Double = _
                DistancePointToSegmentV03( _
                    target, a.StartPoint, a.EndPoint)
            Dim segB As Double = _
                DistancePointToSegmentV03( _
                    target, b.StartPoint, b.EndPoint)

            ' Allow the selected neighbour pipe lines to terminate near the
            ' fitting centre rather than requiring the centre to lie within
            ' the finite line segment itself.
            Dim endpointPenaltyA As Double = Math.Max(0.0, segA - absA)
            Dim endpointPenaltyB As Double = Math.Max(0.0, segB - absB)

            If endpointPenaltyA > 0.90 OrElse endpointPenaltyB > 0.90 Then
                Continue For
            End If

            Dim score As Double = _
                symmetryError * 4.0 + _
                endpointPenaltyA + _
                endpointPenaltyB + _
                separation * 0.02

            If score < bestScore Then
                bestScore = score
                best = New AxisLinePairV05
                best.A = a
                best.B = b
                best.Score = score
            End If

        Next
    Next

    Return best
End Function


Class AxisDirectionV05
    Public UX As Double
    Public UY As Double
End Class


Class AxisLinePairV05
    Public A As DrawingCurve = Nothing
    Public B As DrawingCurve = Nothing
    Public Score As Double
End Class


Sub SortBisectorCandidatesV04( _
    candidates As List(Of BisectorCandidateV04))

    For i As Integer = 0 To candidates.Count - 2
        For j As Integer = i + 1 To candidates.Count - 1
            If candidates.Item(j).Score < candidates.Item(i).Score Then
                Dim temp As BisectorCandidateV04 = candidates.Item(i)
                candidates.Item(i) = candidates.Item(j)
                candidates.Item(j) = temp
            End If
        Next
    Next
End Sub


Class BisectorCandidateV04
    Public A As DrawingCurve = Nothing
    Public B As DrawingCurve = Nothing
    Public UX As Double
    Public UY As Double
    Public Score As Double
End Class

Function FindPortAtModelPointV03( _
    nodes As List(Of NodeRecord), _
    x As Double, y As Double, z As Double, _
    toleranceMm As Double) As PortRecord

    Dim best As PortRecord = Nothing
    Dim bestD As Double = toleranceMm

    For Each n As NodeRecord In nodes
        For Each p As PortRecord In n.Ports
            Dim d As Double = Dist3D(x, y, z, p.X, p.Y, p.Z)
            If d <= bestD Then
                bestD = d
                best = p
            End If
        Next
    Next

    Return best
End Function


Function FindReferenceNodeAtPointV03( _
    nodes As List(Of NodeRecord), _
    x As Double, y As Double, z As Double, _
    toleranceMm As Double) As NodeRecord

    Dim best As NodeRecord = Nothing
    Dim bestD As Double = toleranceMm

    For Each n As NodeRecord In nodes
        Dim d As Double = _
            Dist3D(x, y, z, n.RefX, n.RefY, n.RefZ)
        If d <= bestD Then
            bestD = d
            best = n
        End If
    Next

    Return best
End Function


Function FindFaceDrawingIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    modelFace As Object, _
    target As Point2d) As GeometryIntent

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(modelFace)

        If curves Is Nothing OrElse curves.Count = 0 Then
            Return Nothing
        End If

        Dim best As DrawingCurve = Nothing
        Dim bestScore As Double = Double.MaxValue

        For Each c As DrawingCurve In curves
            Dim score As Double = _
                DrawingCurveDistanceV03(c, target)

            If score < bestScore Then
                bestScore = score
                best = c
            End If
        Next

        If best Is Nothing Then Return Nothing

        If best.CurveType = CurveTypeEnum.kCircleCurve OrElse _
           best.CurveType = CurveTypeEnum.kCircularArcCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipseFullCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipticalArcCurve Then

            Return _
                sheet.CreateGeometryIntent( _
                    best, _
                    PointIntentEnum.kCenterPointIntent)
        End If

        ' For an edge-on planar port face this is the actual projected
        ' face line.  A no-point intent is exactly what a linear/chain
        ' dimension expects for a datum line.
        Return sheet.CreateGeometryIntent(best)

    Catch ex As Exception
        Logger.Error("DrawingCurves(face) failed: " & ex.Message)
        Return Nothing
    End Try
End Function


Function FindNearestViewCurveIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    target As Point2d, _
    maxDistance As Double) As GeometryIntent

    Try
        Dim curves As DrawingCurvesEnumerator = view.DrawingCurves
        If curves Is Nothing Then Return Nothing

        Dim best As DrawingCurve = Nothing
        Dim bestD As Double = maxDistance

        For Each c As DrawingCurve In curves
            Dim d As Double = DrawingCurveDistanceV03(c, target)
            If d <= bestD Then
                bestD = d
                best = c
            End If
        Next

        If best Is Nothing Then Return Nothing

        If best.CurveType = CurveTypeEnum.kLineSegmentCurve Then
            Return sheet.CreateGeometryIntent(best, target)
        End If

        If best.CenterPoint IsNot Nothing AndAlso _
           SheetPointDistanceV03(best.CenterPoint, target) <= maxDistance Then
            Return sheet.CreateGeometryIntent(best, PointIntentEnum.kCenterPointIntent)
        End If

        Return sheet.CreateGeometryIntent(best, target)

    Catch
        Return Nothing
    End Try
End Function


Function DrawingCurveDistanceV03( _
    curve As DrawingCurve, _
    target As Point2d) As Double

    Try
        If curve.CurveType = CurveTypeEnum.kLineSegmentCurve AndAlso _
           curve.StartPoint IsNot Nothing AndAlso _
           curve.EndPoint IsNot Nothing Then

            Return _
                DistancePointToSegmentV03( _
                    target, curve.StartPoint, curve.EndPoint)
        End If

        If curve.CenterPoint IsNot Nothing Then
            Return SheetPointDistanceV03(target, curve.CenterPoint)
        End If

        Dim best As Double = Double.MaxValue
        If curve.StartPoint IsNot Nothing Then
            best = Math.Min(best, SheetPointDistanceV03(target, curve.StartPoint))
        End If
        If curve.EndPoint IsNot Nothing Then
            best = Math.Min(best, SheetPointDistanceV03(target, curve.EndPoint))
        End If
        If curve.MidPoint IsNot Nothing Then
            best = Math.Min(best, SheetPointDistanceV03(target, curve.MidPoint))
        End If
        Return best
    Catch
        Return Double.MaxValue
    End Try
End Function


Function DistancePointToSegmentV03( _
    p As Point2d, _
    a As Point2d, _
    b As Point2d) As Double

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim len2 As Double = dx * dx + dy * dy

    If len2 < 0.0000001 Then
        Return SheetPointDistanceV03(p, a)
    End If

    Dim t As Double = _
        ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / len2

    If t < 0 Then t = 0
    If t > 1 Then t = 1

    Dim q As Point2d = _
        ThisApplication.TransientGeometry.CreatePoint2d( _
            a.X + t * dx, a.Y + t * dy)

    Return SheetPointDistanceV03(p, q)
End Function


Function DistancePointToInfiniteLineV03( _
    p As Point2d, _
    a As Point2d, _
    b As Point2d) As Double

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return Double.MaxValue

    Return _
        Math.Abs( _
            dx * (a.Y - p.Y) - _
            (a.X - p.X) * dy) / l
End Function


Function SignedDistanceToLineV03( _
    p As Point2d, _
    a As Point2d, _
    b As Point2d) As Double

    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Dim l As Double = Math.Sqrt(dx * dx + dy * dy)
    If l < 0.000001 Then Return 0

    Return _
        (dx * (p.Y - a.Y) - dy * (p.X - a.X)) / l
End Function


Function SheetPointDistanceV03(a As Point2d, b As Point2d) As Double
    Dim dx As Double = b.X - a.X
    Dim dy As Double = b.Y - a.Y
    Return Math.Sqrt(dx * dx + dy * dy)
End Function


Function CenterlineNearPointV03( _
    centerline As Centerline, _
    view As DrawingView, _
    target As Point2d, _
    tolerance As Double) As Boolean

    Try
        Dim mx As Double = (centerline.StartPoint.X + centerline.EndPoint.X) / 2.0
        Dim my As Double = (centerline.StartPoint.Y + centerline.EndPoint.Y) / 2.0
        Dim rightX As Double = view.Left + view.Width
        Dim bottomY As Double = view.Top - view.Height

        If mx < view.Left - 0.2 OrElse mx > rightX + 0.2 OrElse _
           my < bottomY - 0.2 OrElse my > view.Top + 0.2 Then
            Return False
        End If

        Return _
            DistancePointToInfiniteLineV03( _
                target, centerline.StartPoint, centerline.EndPoint) <= tolerance
    Catch
        Return False
    End Try
End Function


Function FindCenterlineIntentAtPointV03( _
    sheet As Sheet, _
    view As DrawingView, _
    target As Point2d) As GeometryIntent

    Dim near As New List(Of Centerline)

    For i As Integer = 1 To sheet.Centerlines.Count
        Dim cl As Centerline = sheet.Centerlines.Item(i)
        If CenterlineNearPointV03(cl, view, target, 0.10) Then
            near.Add(cl)
        End If
    Next

    If near.Count >= 2 Then
        For i As Integer = 0 To near.Count - 2
            For j As Integer = i + 1 To near.Count - 1
                If Not CenterlinesParallelV03(near.Item(i), near.Item(j)) Then
                    Try
                        Return _
                            sheet.CreateGeometryIntent( _
                                near.Item(i), _
                                near.Item(j))
                    Catch
                    End Try
                End If
            Next
        Next
    End If

    If near.Count > 0 Then
        Try
            Return sheet.CreateGeometryIntent(near.Item(0), target)
        Catch
            Return sheet.CreateGeometryIntent(near.Item(0))
        End Try
    End If

    Return Nothing
End Function


Function CenterlinesParallelV03(a As Centerline, b As Centerline) As Boolean
    Try
        Dim ax As Double = a.EndPoint.X - a.StartPoint.X
        Dim ay As Double = a.EndPoint.Y - a.StartPoint.Y
        Dim bx As Double = b.EndPoint.X - b.StartPoint.X
        Dim by As Double = b.EndPoint.Y - b.StartPoint.Y
        Dim al As Double = Math.Sqrt(ax * ax + ay * ay)
        Dim bl As Double = Math.Sqrt(bx * bx + by * by)
        If al < 0.0001 OrElse bl < 0.0001 Then Return True
        Dim dot As Double = Math.Abs((ax * bx + ay * by) / (al * bl))
        Return dot > 0.995
    Catch
        Return True
    End Try
End Function


Sub EnsureBisectorCenterlinesForNodeV03( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d)

    If node Is Nothing OrElse node.Occurrence Is Nothing Then Exit Sub

    ' If the Automated Centerline command already created two useful axes,
    ' do not add anything else.
    Dim existing As Integer = 0
    For i As Integer = 1 To sheet.Centerlines.Count
        If CenterlineNearPointV03( _
            sheet.Centerlines.Item(i), view, target, 0.10) Then
            existing += 1
        End If
    Next
    If existing >= 2 Then Exit Sub

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(node.Occurrence)
        If curves Is Nothing Then Exit Sub

        Dim lines As New List(Of DrawingCurve)
        For Each c As DrawingCurve In curves
            If c.CurveType = CurveTypeEnum.kLineSegmentCurve AndAlso _
               c.StartPoint IsNot Nothing AndAlso _
               c.EndPoint IsNot Nothing Then
                lines.Add(c)
            End If
        Next

        For i As Integer = 0 To lines.Count - 2
            For j As Integer = i + 1 To lines.Count - 1

                Dim a As DrawingCurve = lines.Item(i)
                Dim b As DrawingCurve = lines.Item(j)

                If Not DrawingLinesParallelV03(a, b) Then Continue For

                Dim da As Double = _
                    SignedDistanceToLineV03( _
                        target, a.StartPoint, a.EndPoint)
                Dim db As Double = _
                    SignedDistanceToLineV03( _
                        target, b.StartPoint, b.EndPoint)

                If da * db >= 0 Then Continue For
                If Math.Abs(Math.Abs(da) - Math.Abs(db)) > 0.12 Then Continue For
                If Math.Abs(da) + Math.Abs(db) < 0.08 Then Continue For

                Try
                    Dim ia As GeometryIntent = sheet.CreateGeometryIntent(a)
                    Dim ib As GeometryIntent = sheet.CreateGeometryIntent(b)
                    Dim cl As Centerline = _
                        sheet.Centerlines.AddBisector(ia, ib)

                    If CenterlineNearPointV03(cl, view, target, 0.10) Then
                        TagAutoObjectV01(cl)
                        existing += 1
                    Else
                        cl.Delete()
                    End If
                Catch
                End Try

                If existing >= 2 Then Exit Sub
            Next
        Next

    Catch ex As Exception
        Logger.Error( _
            "Bisector centerline generation failed for " & _
            node.Code & ": " & ex.Message)
    End Try
End Sub


Function DrawingLinesParallelV03(a As DrawingCurve, b As DrawingCurve) As Boolean
    Try
        Dim ax As Double = a.EndPoint.X - a.StartPoint.X
        Dim ay As Double = a.EndPoint.Y - a.StartPoint.Y
        Dim bx As Double = b.EndPoint.X - b.StartPoint.X
        Dim by As Double = b.EndPoint.Y - b.StartPoint.Y
        Dim al As Double = Math.Sqrt(ax * ax + ay * ay)
        Dim bl As Double = Math.Sqrt(bx * bx + by * by)
        If al < 0.0001 OrElse bl < 0.0001 Then Return False
        Dim dot As Double = Math.Abs((ax * bx + ay * by) / (al * bl))
        Return dot > 0.995
    Catch
        Return False
    End Try
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
                If anchor.Intent IsNot Nothing Then
                    intents.Add(anchor.Intent)
                End If
            Next

            If intents.Count < 2 Then Continue For

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
End Function


Function CreateIndividualChainFallbackV02( _
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
                a.Intent
            Dim intent2 As GeometryIntent = _
                b.Intent

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

            If firstAnchor.Intent Is Nothing OrElse _
               lastAnchor.Intent Is Nothing Then
                Continue For
            End If

            Dim intent1 As GeometryIntent = firstAnchor.Intent
            Dim intent2 As GeometryIntent = lastAnchor.Intent

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

            If plan.Datum.Intent IsNot Nothing Then
                intents.Add(plan.Datum.Intent)
            End If

            For Each anchor As AutoDimAnchorV01 In plan.StationAnchors
                If anchor.Intent IsNot Nothing Then
                    intents.Add(anchor.Intent)
                End If
            Next

            If intents.Count < 2 Then
                Throw New Exception("Not enough projected geometry intents for attachment baseline.")
            End If

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
            If request.A.Intent Is Nothing OrElse _
               request.B.Intent Is Nothing Then
                Continue For
            End If

            Dim intent1 As GeometryIntent = request.A.Intent
            Dim intent2 As GeometryIntent = request.B.Intent

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
    Public Intent As GeometryIntent = Nothing
    Public SourceDescription As String = ""
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


' ===================================================================
' V0.9 ATTACHMENT-AWARE EXTRACTION / SCHEMATIC
' ===================================================================

Function DetectAttachmentsV09( _
    nodes As List(Of NodeRecord), _
    edges As List(Of EdgeRecord), _
    chains As List(Of StraightChain)) As List(Of AttachmentRecordV09)

    Dim result As New List(Of AttachmentRecordV09)
    Dim host As NodeRecord = FindAttachmentHostV09(nodes)

    If host Is Nothing OrElse host.Ports.Count < 2 Then Return result

    Dim hostP1 As PortRecord = Nothing
    Dim hostP2 As PortRecord = Nothing
    GetFarthestPortPairV09(host.Ports, hostP1, hostP2)

    If hostP1 Is Nothing OrElse hostP2 Is Nothing Then Return result

    Dim hux As Double = hostP2.X - hostP1.X
    Dim huy As Double = hostP2.Y - hostP1.Y
    Dim huz As Double = hostP2.Z - hostP1.Z
    Dim hostLength As Double = Math.Sqrt(hux * hux + huy * huy + huz * huz)

    If hostLength < 1.0 Then Return result

    hux /= hostLength : huy /= hostLength : huz /= hostLength

    Dim hostRadius As Double = (hostP1.Radius + hostP2.Radius) / 2.0
    If hostRadius <= 0 Then hostRadius = Math.Max(hostP1.Radius, hostP2.Radius)
    If hostRadius <= 0 Then Return result

    Dim alreadyAssigned As New List(Of NodeRecord)

    For Each candidate As NodeRecord In nodes

        If candidate Is host OrElse candidate.ComponentType <> "PIPE" OrElse candidate.Ports.Count < 2 Then Continue For
        If alreadyAssigned.Contains(candidate) Then Continue For

        Dim bp1 As PortRecord = Nothing
        Dim bp2 As PortRecord = Nothing
        GetFarthestPortPairV09(candidate.Ports, bp1, bp2)
        If bp1 Is Nothing OrElse bp2 Is Nothing Then Continue For

        Dim branchRadius As Double = Math.Max(bp1.Radius, bp2.Radius)
        If branchRadius >= hostRadius * 0.45 Then Continue For

        Dim bux As Double = bp2.X - bp1.X
        Dim buy As Double = bp2.Y - bp1.Y
        Dim buz As Double = bp2.Z - bp1.Z
        Dim branchLength As Double = Math.Sqrt(bux * bux + buy * buy + buz * buz)
        If branchLength < 1.0 Then Continue For

        bux /= branchLength : buy /= branchLength : buz /= branchLength

        Dim axisDot As Double = Math.Abs(bux * hux + buy * huy + buz * huz)
        If axisDot > 0.35 Then Continue For

        Dim bestPort As PortRecord = Nothing
        Dim bestError As Double = Double.MaxValue
        Dim bestAxisX As Double = 0
        Dim bestAxisY As Double = 0
        Dim bestAxisZ As Double = 0

        For Each p As PortRecord In candidate.Ports
            Dim axisX As Double = 0
            Dim axisY As Double = 0
            Dim axisZ As Double = 0
            Dim t As Double = 0
            Dim radial As Double = 0

            ProjectToHostAxisV09( _
                p.X, p.Y, p.Z, _
                hostP1.X, hostP1.Y, hostP1.Z, _
                hux, huy, huz, _
                axisX, axisY, axisZ, t, radial)

            If t < -25.0 OrElse t > hostLength + 25.0 Then Continue For

            Dim surfaceError As Double = Math.Abs(radial - hostRadius)
            If surfaceError < bestError Then
                bestError = surfaceError
                bestPort = p
                bestAxisX = axisX
                bestAxisY = axisY
                bestAxisZ = axisZ
            End If
        Next

        Dim allowedSurfaceError As Double = Math.Max(30.0, branchRadius * 3.0)
        If bestPort Is Nothing OrElse bestError > allowedSurfaceError Then Continue For

        Dim outX As Double = bestPort.X - bestAxisX
        Dim outY As Double = bestPort.Y - bestAxisY
        Dim outZ As Double = bestPort.Z - bestAxisZ
        Dim outLength As Double = Math.Sqrt(outX * outX + outY * outY + outZ * outZ)
        If outLength < 0.1 Then Continue For

        outX /= outLength : outY /= outLength : outZ /= outLength

        Dim a As New AttachmentRecordV09
        a.Host = host
        a.Root = candidate
        a.AxisPointX = bestAxisX : a.AxisPointY = bestAxisY : a.AxisPointZ = bestAxisZ
        a.BaseX = bestAxisX + outX * hostRadius
        a.BaseY = bestAxisY + outY * hostRadius
        a.BaseZ = bestAxisZ + outZ * hostRadius
        a.AxisX = outX : a.AxisY = outY : a.AxisZ = outZ
        a.SurfaceError = bestError
        a.Members = CollectAttachmentMembersV09(candidate)

        Dim bestTerminalDistance As Double = -Double.MaxValue
        Dim terminalFound As Boolean = False

        For Each member As NodeRecord In a.Members
            For Each p As PortRecord In member.Ports
                Dim signedDistance As Double = _
                    (p.X - a.BaseX) * outX + _
                    (p.Y - a.BaseY) * outY + _
                    (p.Z - a.BaseZ) * outZ

                If signedDistance > bestTerminalDistance Then
                    bestTerminalDistance = signedDistance
                    a.TerminalX = p.X : a.TerminalY = p.Y : a.TerminalZ = p.Z
                    terminalFound = True
                End If
            Next
        Next

        If Not terminalFound OrElse bestTerminalDistance < 5.0 Then Continue For

        a.Rise = bestTerminalDistance
        DetermineAttachmentTypeV09(a)
        result.Add(a)

        For Each member As NodeRecord In a.Members
            If Not alreadyAssigned.Contains(member) Then alreadyAssigned.Add(member)
        Next
    Next

    If result.Count = 0 Then Return result

    Dim longest As StraightChain = FindLongestChainV09(chains)
    If longest Is Nothing OrElse longest.Length < 1.0 Then Return result

    Dim score1 As Double = 0
    Dim score2 As Double = 0
    For Each a As AttachmentRecordV09 In result
        score1 += Dist3D(a.BaseX, a.BaseY, a.BaseZ, longest.X1, longest.Y1, longest.Z1)
        score2 += Dist3D(a.BaseX, a.BaseY, a.BaseZ, longest.X2, longest.Y2, longest.Z2)
    Next

    Dim datumX As Double, datumY As Double, datumZ As Double
    Dim farX As Double, farY As Double, farZ As Double

    If score1 <= score2 Then
        datumX = longest.X1 : datumY = longest.Y1 : datumZ = longest.Z1
        farX = longest.X2 : farY = longest.Y2 : farZ = longest.Z2
    Else
        datumX = longest.X2 : datumY = longest.Y2 : datumZ = longest.Z2
        farX = longest.X1 : farY = longest.Y1 : farZ = longest.Z1
    End If

    Dim mux As Double = farX - datumX
    Dim muy As Double = farY - datumY
    Dim muz As Double = farZ - datumZ
    Dim mainLength As Double = Math.Sqrt(mux * mux + muy * muy + muz * muz)
    If mainLength < 1.0 Then Return result

    mux /= mainLength : muy /= mainLength : muz /= mainLength

    For Each a As AttachmentRecordV09 In result
        a.DatumX = datumX : a.DatumY = datumY : a.DatumZ = datumZ
        a.MainUX = mux : a.MainUY = muy : a.MainUZ = muz
        a.MainOverall = mainLength
        a.Station = _
            (a.AxisPointX - datumX) * mux + _
            (a.AxisPointY - datumY) * muy + _
            (a.AxisPointZ - datumZ) * muz
        If a.Station < 0 Then a.Station *= -1.0
    Next

    SortAttachmentsV09(result)
    For i As Integer = 0 To result.Count - 1
        result.Item(i).ID = "A" & (i + 1).ToString()
    Next

    Return result
End Function

Function FindAttachmentHostV09(nodes As List(Of NodeRecord)) As NodeRecord
    Dim best As NodeRecord = Nothing
    Dim bestRadius As Double = -1
    For Each n As NodeRecord In nodes
        If n.ComponentType <> "PIPE" OrElse n.Ports.Count < 2 Then Continue For
        Dim maxRadius As Double = 0
        For Each p As PortRecord In n.Ports
            If p.Radius > maxRadius Then maxRadius = p.Radius
        Next
        If maxRadius > bestRadius Then bestRadius = maxRadius : best = n
    Next
    Return best
End Function

Sub GetFarthestPortPairV09(ports As List(Of PortRecord), ByRef p1 As PortRecord, ByRef p2 As PortRecord)
    p1 = Nothing : p2 = Nothing
    Dim best As Double = -1
    For i As Integer = 0 To ports.Count - 1
        For j As Integer = i + 1 To ports.Count - 1
            Dim a As PortRecord = ports.Item(i)
            Dim b As PortRecord = ports.Item(j)
            Dim d As Double = Dist3D(a.X, a.Y, a.Z, b.X, b.Y, b.Z)
            If d > best Then best = d : p1 = a : p2 = b
        Next
    Next
End Sub

Sub ProjectToHostAxisV09( _
    px As Double, py As Double, pz As Double, _
    ax As Double, ay As Double, az As Double, _
    ux As Double, uy As Double, uz As Double, _
    ByRef axisX As Double, ByRef axisY As Double, ByRef axisZ As Double, _
    ByRef t As Double, ByRef radial As Double)

    Dim vx As Double = px - ax
    Dim vy As Double = py - ay
    Dim vz As Double = pz - az
    t = vx * ux + vy * uy + vz * uz
    axisX = ax + t * ux : axisY = ay + t * uy : axisZ = az + t * uz
    radial = Dist3D(px, py, pz, axisX, axisY, axisZ)
End Sub

Function CollectAttachmentMembersV09(root As NodeRecord) As List(Of NodeRecord)
    Dim result As New List(Of NodeRecord)
    Dim queue As New List(Of NodeRecord)
    result.Add(root) : queue.Add(root)
    Dim index As Integer = 0
    While index < queue.Count
        Dim current As NodeRecord = queue.Item(index) : index += 1
        For Each neighbour As NodeRecord In current.Neighbours
            If neighbour.ComponentType = "FLANGE" Then Continue For
            If Not result.Contains(neighbour) Then result.Add(neighbour) : queue.Add(neighbour)
        Next
    End While
    Return result
End Function

Sub DetermineAttachmentTypeV09(a As AttachmentRecordV09)
    Dim hasSocket As Boolean = False
    Dim hasThreaded As Boolean = False
    For Each n As NodeRecord In a.Members
        If n.ComponentType = "COUPLING_SOCKET" Then hasSocket = True
        Dim tx As String = (n.PartNumber & " " & n.Description & " " & n.OccurrenceName).ToUpperInvariant()
        If tx.Contains("THREADED") OrElse tx.Contains("THREAD") Then hasThreaded = True
    Next
    If hasSocket Then
        a.AttachmentType = "SOCKET_BRANCH" : a.TerminalType = "FEMALE_SOCKET"
    ElseIf hasThreaded Then
        a.AttachmentType = "THREADED_BRANCH" : a.TerminalType = "THREADED_END"
    Else
        a.AttachmentType = "WELDED_BRANCH" : a.TerminalType = "OPEN_END"
    End If
End Sub

Function FindLongestChainV09(chains As List(Of StraightChain)) As StraightChain
    Dim longest As StraightChain = Nothing
    For Each c As StraightChain In chains
        If longest Is Nothing OrElse c.Length > longest.Length Then longest = c
    Next
    Return longest
End Function

Sub SortAttachmentsV09(attachments As List(Of AttachmentRecordV09))
    For i As Integer = 0 To attachments.Count - 2
        For j As Integer = i + 1 To attachments.Count - 1
            If attachments.Item(j).Station < attachments.Item(i).Station Then
                Dim temp As AttachmentRecordV09 = attachments.Item(i)
                attachments.Item(i) = attachments.Item(j)
                attachments.Item(j) = temp
            End If
        Next
    Next
End Sub

Function IsAttachmentMemberV09(node As NodeRecord, attachments As List(Of AttachmentRecordV09)) As Boolean
    For Each a As AttachmentRecordV09 In attachments
        If a.Members.Contains(node) Then Return True
    Next
    Return False
End Function

Sub ChooseDominantAttachmentDirectionV09(attachments As List(Of AttachmentRecordV09), ByRef dx As Double, ByRef dy As Double, ByRef dz As Double)
    dx = attachments.Item(0).AxisX : dy = attachments.Item(0).AxisY : dz = attachments.Item(0).AxisZ
    Dim bestCount As Integer = -1
    For Each candidate As AttachmentRecordV09 In attachments
        Dim count As Integer = 0
        For Each other As AttachmentRecordV09 In attachments
            Dim dot As Double = Math.Abs(candidate.AxisX * other.AxisX + candidate.AxisY * other.AxisY + candidate.AxisZ * other.AxisZ)
            If dot >= 0.90 Then count += 1
        Next
        If count > bestCount Then bestCount = count : dx = candidate.AxisX : dy = candidate.AxisY : dz = candidate.AxisZ
    Next
End Sub

Function AttachmentStationCoordinateV09(a As AttachmentRecordV09, x As Double, y As Double, z As Double) As Double
    Return (x - a.DatumX) * a.MainUX + (y - a.DatumY) * a.MainUY + (z - a.DatumZ) * a.MainUZ
End Function

Function AttachmentDimTextV09(value As Double) As String
    Return Math.Round(value, 0, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture)
End Function

Sub GenerateAttachmentVerificationSvgV09( _
    assemblyName As String, _
    nodes As List(Of NodeRecord), _
    componentDimensions As List(Of DimensionRecord), _
    chains As List(Of StraightChain), _
    attachments As List(Of AttachmentRecordV09), _
    graphGroups As Integer, _
    unresolved As List(Of String), _
    outputFile As String)

    If attachments.Count = 0 Then Exit Sub
    Dim longest As StraightChain = FindLongestChainV09(chains)
    If longest Is Nothing Then Exit Sub

    Dim svg As New StringBuilder
    svg.AppendLine("<svg xmlns=""http://www.w3.org/2000/svg"" width=""1600"" height=""1180"" viewBox=""0 0 1600 1180"">")
    svg.AppendLine("<rect x=""1"" y=""1"" width=""1598"" height=""1178"" fill=""white"" stroke=""black"" stroke-width=""2""/>")
    svg.AppendLine("<text x=""40"" y=""44"" font-family=""Arial"" font-size=""25"" font-weight=""bold"">" & XmlText(assemblyName) & "</text>")
    svg.AppendLine("<text x=""40"" y=""72"" font-family=""Arial"" font-size=""14"">Attachment-aware schematic   Detected attachments=" & attachments.Count.ToString() & "   Raw graph groups=" & graphGroups.ToString() & "   Unresolved non-attachments=" & XmlText(String.Join(",", unresolved.ToArray())) & "</text>")

    Dim primaryX As Double = 0, primaryY As Double = 0, primaryZ As Double = 0
    ChooseDominantAttachmentDirectionV09(attachments, primaryX, primaryY, primaryZ)

    Dim primary As New List(Of AttachmentRecordV09)
    Dim secondary As New List(Of AttachmentRecordV09)
    For Each a As AttachmentRecordV09 In attachments
        Dim dot As Double = Math.Abs(a.AxisX * primaryX + a.AxisY * primaryY + a.AxisZ * primaryZ)
        If dot >= 0.90 Then primary.Add(a) Else secondary.Add(a)
    Next
    SortAttachmentsV09(primary) : SortAttachmentsV09(secondary)

    Dim leftX As Double = 120
    Dim rightX As Double = 1480
    Dim overall As Double = attachments.Item(0).MainOverall
    If overall < 1 Then overall = longest.Length
    Dim sx As Double = (rightX - leftX) / overall

    svg.AppendLine("<rect x=""30"" y=""105"" width=""1540"" height=""535"" fill=""none"" stroke=""black"" stroke-width=""1.3""/>")
    svg.AppendLine("<text x=""48"" y=""135"" font-family=""Arial"" font-size=""17"" font-weight=""bold"">ATTACHMENT VIEW A - DOMINANT RADIAL PLANE</text>")

    Dim mainY As Double = 425
    svg.AppendLine("<line x1=""" & Num(leftX) & """ y1=""" & Num(mainY) & """ x2=""" & Num(rightX) & """ y2=""" & Num(mainY) & """ stroke=""black"" stroke-width=""4""/>")
    DrawAttachmentFlangeV09(svg, leftX, mainY) : DrawAttachmentFlangeV09(svg, rightX, mainY)

    For Each a As AttachmentRecordV09 In primary
        Dim x As Double = leftX + a.Station * sx
        Dim signedDot As Double = a.AxisX * primaryX + a.AxisY * primaryY + a.AxisZ * primaryZ
        Dim screenSign As Double = -1.0
        If signedDot < 0 Then screenSign = 1.0
        Dim risePixels As Double = Math.Max(55.0, Math.Min(85.0, a.Rise * 0.9))
        Dim endY As Double = mainY + screenSign * risePixels
        svg.AppendLine("<line x1=""" & Num(x) & """ y1=""" & Num(mainY) & """ x2=""" & Num(x) & """ y2=""" & Num(endY) & """ stroke=""black"" stroke-width=""3""/>")
        DrawAttachmentTerminalV09(svg, x, endY, a.TerminalType)
        DrawAttachmentRiseDimensionV09(svg, x + 18.0, mainY, endY, a.Rise)
        svg.AppendLine("<text x=""" & Num(x + 7) & """ y=""" & Num(endY - 8 * screenSign) & """ font-family=""Arial"" font-size=""12"" font-weight=""bold"">" & XmlText(a.ID) & "</text>")
        If a.TerminalType = "THREADED_END" Then svg.AppendLine("<text x=""" & Num(x + 18) & """ y=""" & Num(endY + 4) & """ font-family=""Arial"" font-size=""11"">THREADED END</text>")
    Next

    For i As Integer = 0 To primary.Count - 1
        Dim a As AttachmentRecordV09 = primary.Item(i)
        Dim x As Double = leftX + a.Station * sx
        Dim dimY As Double = mainY - 105.0 - i * 26.0
        DrawHorizontalDimensionV09(svg, leftX, x, dimY, a.Station)
    Next

    For Each d As DimensionRecord In componentDimensions
        If d.DimensionType = "PIPE_LENGTH" Then
            Dim s1 As Double = AttachmentStationCoordinateV09(attachments.Item(0), d.X1, d.Y1, d.Z1)
            Dim s2 As Double = AttachmentStationCoordinateV09(attachments.Item(0), d.X2, d.Y2, d.Z2)
            DrawHorizontalDimensionV09(svg, leftX + Math.Min(s1, s2) * sx, leftX + Math.Max(s1, s2) * sx, mainY + 72.0, d.Value)
        ElseIf d.DimensionType = "FLANGE_THICKNESS" Then
            Dim fs1 As Double = AttachmentStationCoordinateV09(attachments.Item(0), d.X1, d.Y1, d.Z1)
            Dim fs2 As Double = AttachmentStationCoordinateV09(attachments.Item(0), d.X2, d.Y2, d.Z2)
            DrawHorizontalDimensionV09(svg, leftX + Math.Min(fs1, fs2) * sx, leftX + Math.Max(fs1, fs2) * sx, mainY + 42.0, d.Value)
        End If
    Next
    DrawHorizontalDimensionV09(svg, leftX, rightX, mainY + 112.0, overall)

    If secondary.Count > 0 Then
        svg.AppendLine("<rect x=""30"" y=""665"" width=""1540"" height=""390"" fill=""none"" stroke=""black"" stroke-width=""1.3""/>")
        svg.AppendLine("<text x=""48"" y=""695"" font-family=""Arial"" font-size=""17"" font-weight=""bold"">ATTACHMENT VIEW B - ORTHOGONAL RADIAL PLANE</text>")
        Dim secondDirX As Double = secondary.Item(0).AxisX
        Dim secondDirY As Double = secondary.Item(0).AxisY
        Dim secondDirZ As Double = secondary.Item(0).AxisZ
        Dim mainY2 As Double = 845
        svg.AppendLine("<line x1=""" & Num(leftX) & """ y1=""" & Num(mainY2) & """ x2=""" & Num(rightX) & """ y2=""" & Num(mainY2) & """ stroke=""black"" stroke-width=""4""/>")
        DrawAttachmentFlangeV09(svg, leftX, mainY2) : DrawAttachmentFlangeV09(svg, rightX, mainY2)
        For Each a As AttachmentRecordV09 In secondary
            Dim x As Double = leftX + a.Station * sx
            Dim signedDot As Double = a.AxisX * secondDirX + a.AxisY * secondDirY + a.AxisZ * secondDirZ
            Dim screenSign As Double = 1.0
            If signedDot < 0 Then screenSign = -1.0
            Dim risePixels As Double = Math.Max(55.0, Math.Min(85.0, a.Rise * 0.9))
            Dim endY As Double = mainY2 + screenSign * risePixels
            svg.AppendLine("<line x1=""" & Num(x) & """ y1=""" & Num(mainY2) & """ x2=""" & Num(x) & """ y2=""" & Num(endY) & """ stroke=""black"" stroke-width=""3""/>")
            DrawAttachmentTerminalV09(svg, x, endY, a.TerminalType)
            DrawAttachmentRiseDimensionV09(svg, x + 18.0, mainY2, endY, a.Rise)
            DrawHorizontalDimensionV09(svg, leftX, x, mainY2 + screenSign * 125.0, a.Station)
            If a.TerminalType = "THREADED_END" Then svg.AppendLine("<text x=""" & Num(x + 20) & """ y=""" & Num(endY + 4) & """ font-family=""Arial"" font-size=""11"">THREADED END</text>")
        Next
    End If

    svg.AppendLine("<text x=""45"" y=""1110"" font-family=""Arial"" font-size=""13"" font-weight=""bold"">ATTACHMENT DIMENSIONS</text>")
    Dim tableX As Double = 45
    Dim tableY As Double = 1135
    For i As Integer = 0 To attachments.Count - 1
        Dim a As AttachmentRecordV09 = attachments.Item(i)
        svg.AppendLine("<text x=""" & Num(tableX + (i Mod 4) * 370) & """ y=""" & Num(tableY + (i \ 4) * 20) & """ font-family=""Arial"" font-size=""12"">" & XmlText(a.ID & "  " & a.AttachmentType & "  station=" & AttachmentDimTextV09(a.Station) & "  rise=" & AttachmentDimTextV09(a.Rise)) & "</text>")
    Next
    svg.AppendLine("</svg>")
    System.IO.File.WriteAllText(outputFile, svg.ToString(), New UTF8Encoding(False))
End Sub

Sub DrawAttachmentFlangeV09(svg As StringBuilder, x As Double, y As Double)
    svg.AppendLine("<line x1=""" & Num(x) & """ y1=""" & Num(y - 24) & """ x2=""" & Num(x) & """ y2=""" & Num(y + 24) & """ stroke=""black"" stroke-width=""4""/>")
    svg.AppendLine("<line x1=""" & Num(x + 7) & """ y1=""" & Num(y - 19) & """ x2=""" & Num(x + 7) & """ y2=""" & Num(y + 19) & """ stroke=""black"" stroke-width=""2""/>")
End Sub

Sub DrawAttachmentTerminalV09(svg As StringBuilder, x As Double, y As Double, terminalType As String)
    svg.AppendLine("<line x1=""" & Num(x - 10) & """ y1=""" & Num(y) & """ x2=""" & Num(x + 10) & """ y2=""" & Num(y) & """ stroke=""black"" stroke-width=""3""/>")
    If terminalType = "FEMALE_SOCKET" Then svg.AppendLine("<line x1=""" & Num(x - 8) & """ y1=""" & Num(y - 5) & """ x2=""" & Num(x + 8) & """ y2=""" & Num(y - 5) & """ stroke=""black"" stroke-width=""1.4""/>")
End Sub

Sub DrawHorizontalDimensionV09(svg As StringBuilder, x1 As Double, x2 As Double, y As Double, value As Double)
    If x2 < x1 Then Dim temp As Double = x1 : x1 = x2 : x2 = temp
    svg.AppendLine("<line x1=""" & Num(x1) & """ y1=""" & Num(y) & """ x2=""" & Num(x2) & """ y2=""" & Num(y) & """ stroke=""black"" stroke-width=""1""/>")
    svg.AppendLine("<line x1=""" & Num(x1) & """ y1=""" & Num(y - 7) & """ x2=""" & Num(x1) & """ y2=""" & Num(y + 7) & """ stroke=""black"" stroke-width=""1""/>")
    svg.AppendLine("<line x1=""" & Num(x2) & """ y1=""" & Num(y - 7) & """ x2=""" & Num(x2) & """ y2=""" & Num(y + 7) & """ stroke=""black"" stroke-width=""1""/>")
    svg.AppendLine("<text x=""" & Num((x1 + x2) / 2.0) & """ y=""" & Num(y - 6) & """ text-anchor=""middle"" font-family=""Arial"" font-size=""12"" style=""paint-order:stroke;stroke:white;stroke-width:4px"">" & AttachmentDimTextV09(value) & "</text>")
End Sub

Sub DrawAttachmentRiseDimensionV09(svg As StringBuilder, x As Double, y1 As Double, y2 As Double, value As Double)
    svg.AppendLine("<line x1=""" & Num(x) & """ y1=""" & Num(y1) & """ x2=""" & Num(x) & """ y2=""" & Num(y2) & """ stroke=""black"" stroke-width=""0.9""/>")
    svg.AppendLine("<line x1=""" & Num(x - 5) & """ y1=""" & Num(y1) & """ x2=""" & Num(x + 5) & """ y2=""" & Num(y1) & """ stroke=""black"" stroke-width=""0.9""/>")
    svg.AppendLine("<line x1=""" & Num(x - 5) & """ y1=""" & Num(y2) & """ x2=""" & Num(x + 5) & """ y2=""" & Num(y2) & """ stroke=""black"" stroke-width=""0.9""/>")
    Dim cy As Double = (y1 + y2) / 2.0
    svg.AppendLine("<text x=""" & Num(x + 4) & """ y=""" & Num(cy) & """ font-family=""Arial"" font-size=""11"" transform=""rotate(-90 " & Num(x + 4) & " " & Num(cy) & ")"">" & AttachmentDimTextV09(value) & "</text>")
End Sub

Sub AppendAttachmentCsvV09(assemblyName As String, attachments As List(Of AttachmentRecordV09), csvFile As String)
    Dim sb As New StringBuilder
    For Each a As AttachmentRecordV09 In attachments
        Dim members As New List(Of String)
        For Each n As NodeRecord In a.Members : members.Add(n.Code) : Next
        Dim memberText As String = String.Join(";", members.ToArray())
        AppendAttachmentCsvRowV09(sb, "ATTACHMENT", assemblyName, a, a.Rise, a.BaseX, a.BaseY, a.BaseZ, a.TerminalX, a.TerminalY, a.TerminalZ, "Station_mm=" & AttachmentDimTextV09(a.Station) & "; Rise_mm=" & AttachmentDimTextV09(a.Rise) & "; Members=" & memberText)
        AppendAttachmentCsvRowV09(sb, "ATTACHMENT_STATION", assemblyName, a, a.Station, a.DatumX, a.DatumY, a.DatumZ, a.AxisPointX, a.AxisPointY, a.AxisPointZ, "Flange datum to branch center axis")
        AppendAttachmentCsvRowV09(sb, "ATTACHMENT_RISE", assemblyName, a, a.Rise, a.BaseX, a.BaseY, a.BaseZ, a.TerminalX, a.TerminalY, a.TerminalZ, "Host outer surface to terminal outer face")
    Next
    System.IO.File.AppendAllText(csvFile, sb.ToString(), New UTF8Encoding(False))
End Sub

Sub AppendAttachmentCsvRowV09(sb As StringBuilder, recordType As String, assemblyName As String, a As AttachmentRecordV09, value As Double, x1 As Double, y1 As Double, z1 As Double, x2 As Double, y2 As Double, z2 As Double, notes As String)
    Dim f(37) As String
    For i As Integer = 0 To f.Length - 1 : f(i) = "" : Next
    f(0) = recordType : f(1) = assemblyName : f(2) = a.ID : f(3) = a.Host.Code
    f(4) = a.Root.OccurrenceName : f(5) = a.AttachmentType : f(6) = a.TerminalType
    f(9) = Num(a.BaseX) : f(10) = Num(a.BaseY) : f(11) = Num(a.BaseZ)
    f(12) = Num(a.AxisX) : f(13) = Num(a.AxisY) : f(14) = Num(a.AxisZ)
    f(17) = a.Host.Code : f(18) = "SIDE_ATTACHMENT" : f(19) = Num(a.SurfaceError)
    f(20) = "BRANCH_BASE_SURFACE" : f(21) = Num(a.BaseX) : f(22) = Num(a.BaseY) : f(23) = Num(a.BaseZ)
    f(29) = Num(value) : f(30) = Num(x1) : f(31) = Num(y1) : f(32) = Num(z1)
    f(33) = Num(x2) : f(34) = Num(y2) : f(35) = Num(z2) : f(37) = notes
    Dim encoded As New List(Of String)
    For Each item As String In f : encoded.Add(Csv(item)) : Next
    sb.AppendLine(String.Join(",", encoded.ToArray()))
End Sub

Class AttachmentRecordV09
    Public ID As String = ""
    Public Host As NodeRecord = Nothing
    Public Root As NodeRecord = Nothing
    Public Members As New List(Of NodeRecord)
    Public AttachmentType As String = ""
    Public TerminalType As String = ""
    Public AxisPointX As Double : Public AxisPointY As Double : Public AxisPointZ As Double
    Public BaseX As Double : Public BaseY As Double : Public BaseZ As Double
    Public TerminalX As Double : Public TerminalY As Double : Public TerminalZ As Double
    Public AxisX As Double : Public AxisY As Double : Public AxisZ As Double
    Public DatumX As Double : Public DatumY As Double : Public DatumZ As Double
    Public MainUX As Double : Public MainUY As Double : Public MainUZ As Double
    Public MainOverall As Double
    Public Station As Double
    Public Rise As Double
    Public SurfaceError As Double
End Class

' ===================================================================
' DATA CLASSES
' ===================================================================

Class NodeRecord

    Public OccurrenceName As String = ""
    Public Occurrence As ComponentOccurrence = Nothing

    Public PartNumber As String = ""
    Public Description As String = ""

    Public ComponentType As String = "OTHER"
    Public Code As String = ""


    Public X As Double
    Public Y As Double
    Public Z As Double


    Public Ports As New List(Of PortRecord)
    Public Neighbours As New List(Of NodeRecord)


    Public RefX As Double
    Public RefY As Double
    Public RefZ As Double

    Public ReferenceType As String = ""


    ' Flange manufacturing reference.
    Public HasOuterAnchor As Boolean = False

    Public InnerFaceIndex As Integer = 0
    Public OuterFaceIndex As Integer = 0
    Public OuterPort As PortRecord = Nothing

    Public OuterX As Double
    Public OuterY As Double
    Public OuterZ As Double

    Public OuterOffset As Double

    Public FlangeHostCode As String = ""

    Public HostPortX As Double
    Public HostPortY As Double
    Public HostPortZ As Double

End Class



Class PortRecord

    Public Owner As NodeRecord

    Public FaceIndex As Integer
    Public ModelFace As Object = Nothing


    Public X As Double
    Public Y As Double
    Public Z As Double


    Public NX As Double
    Public NY As Double
    Public NZ As Double


    Public Radius As Double

    Public CircularEdges As Integer
    Public FaceArea As Double


    Public Used As Boolean = False

End Class



Class EdgeRecord

    Public A As NodeRecord
    Public B As NodeRecord

    Public PortA As PortRecord
    Public PortB As PortRecord

    Public ConnectionType As String = ""

    Public ConnectionDistance As Double

End Class



Class PrimitiveSegment

    Public Owner As NodeRecord
    Public Kind As String = ""

    Public X1 As Double
    Public Y1 As Double
    Public Z1 As Double

    Public X2 As Double
    Public Y2 As Double
    Public Z2 As Double

    Public Length As Double


    Public Sub New( _
        ownerNode As NodeRecord, _
        primitiveKind As String, _
        ax As Double, _
        ay As Double, _
        az As Double, _
        bx As Double, _
        by As Double, _
        bz As Double)


        Owner = ownerNode
        Kind = primitiveKind

        X1 = ax
        Y1 = ay
        Z1 = az

        X2 = bx
        Y2 = by
        Z2 = bz

        Dim dx As Double = bx - ax
        Dim dy As Double = by - ay
        Dim dz As Double = bz - az

        Length = _
            Math.Sqrt( _
                dx * dx + _
                dy * dy + _
                dz * dz)

    End Sub

End Class



Class DimensionRecord

    Public Label As String = ""
    Public OwnerCode As String = ""

    Public DimensionType As String = ""
    Public Category As String = ""

    Public X1 As Double
    Public Y1 As Double
    Public Z1 As Double

    Public X2 As Double
    Public Y2 As Double
    Public Z2 As Double

    Public Value As Double

    Public ChainIndex As Integer = 0

End Class



Class StraightChain

    Public Index As Integer = 0

    Public Segments As New List(Of PrimitiveSegment)

    Public X1 As Double
    Public Y1 As Double
    Public Z1 As Double

    Public X2 As Double
    Public Y2 As Double
    Public Z2 As Double

    Public Length As Double

End Class



Class Point3DRecord

    Public X As Double
    Public Y As Double
    Public Z As Double


    Public Sub New( _
        px As Double, _
        py As Double, _
        pz As Double)


        X = px
        Y = py
        Z = pz

    End Sub

End Class



Class SvgPoint

    Public X As Double
    Public Y As Double


    Public Sub New( _
        px As Double, _
        py As Double)


        X = px
        Y = py

    End Sub

End Class



Class SchematicTransform

    Public OriginX As Double
    Public OriginY As Double
    Public OriginZ As Double

    Public UX As Double
    Public UY As Double
    Public UZ As Double

    Public VX As Double
    Public VY As Double
    Public VZ As Double

    Public Scale As Double

    Public ScreenOriginX As Double
    Public ScreenOriginY As Double

End Class
