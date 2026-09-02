#!/usr/bin/env python3
from pathlib import Path

src = Path('TopologyExtractor.vb')
text = src.read_text(encoding='utf-8-sig')
text = text.replace('\r\n', '\n').replace('\r', '\n')

if 'Function DetectAttachmentsV09(' in text:
    print('Attachment-aware V0.9 already applied.')
    raise SystemExit(0)

needle = """        AssignDimensionsToChains( _
            componentDimensions, _
            chains)


        ' =============================================================
        ' 7. GRAPH DIAGNOSTICS
"""
replacement = """        AssignDimensionsToChains( _
            componentDimensions, _
            chains)


        ' =============================================================
        ' 6B. DETECT SIDE / INSTRUMENT ATTACHMENTS
        ' =============================================================

        Dim attachments As List(Of AttachmentRecordV09) = _
            DetectAttachmentsV09( _
                nodes, _
                edges, _
                chains)


        ' =============================================================
        ' 7. GRAPH DIAGNOSTICS
"""
if needle not in text:
    raise SystemExit('Could not find AssignDimensionsToChains insertion point.')
text = text.replace(needle, replacement, 1)

needle = """            If n.Neighbours.Count = 0 Then
                unresolved.Add(n.Code)
            End If
"""
replacement = """            If n.Neighbours.Count = 0 AndAlso _
               Not IsAttachmentMemberV09(n, attachments) Then

                unresolved.Add(n.Code)

            End If
"""
if needle not in text:
    raise SystemExit('Could not find unresolved-node block.')
text = text.replace(needle, replacement, 1)

marker = """        ' =============================================================
        ' 9. GENERATE CLEAN VISUAL SCHEMATIC
"""
if marker not in text:
    raise SystemExit('Could not find SVG generation marker.')
text = text.replace(marker, """        If attachments.Count > 0 Then

            AppendAttachmentCsvV09( _
                asmName, _
                attachments, _
                csvFile)

        End If


""" + marker, 1)

old = """        GenerateVerificationSvg( _
            asmName, _
            nodes, _
            edges, _
            primitives, _
            componentDimensions, _
            chains, _
            overallDimensions, _
            graphGroups, _
            unresolved, _
            svgFile)
"""
new = """        If attachments.Count > 0 Then

            GenerateAttachmentVerificationSvgV09( _
                asmName, _
                nodes, _
                componentDimensions, _
                chains, _
                attachments, _
                graphGroups, _
                unresolved, _
                svgFile)

        Else

            GenerateVerificationSvg( _
                asmName, _
                nodes, _
                edges, _
                primitives, _
                componentDimensions, _
                chains, _
                overallDimensions, _
                graphGroups, _
                unresolved, _
                svgFile)

        End If
"""
if old not in text:
    raise SystemExit('Could not find GenerateVerificationSvg call.')
text = text.replace(old, new, 1)

needle = """        summary.AppendLine(\"Connections: \" & edges.Count.ToString())
        summary.AppendLine(\"Graph groups: \" & graphGroups.ToString())
"""
replacement = """        summary.AppendLine(\"Connections: \" & edges.Count.ToString())
        summary.AppendLine(\"Graph groups: \" & graphGroups.ToString())
        summary.AppendLine(\"Detected attachments: \" & attachments.Count.ToString())
"""
if needle in text:
    text = text.replace(needle, replacement, 1)

helpers = r'''
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
        If d.ConnectionType = "PIPE_LENGTH" Then
            Dim s1 As Double = AttachmentStationCoordinateV09(attachments.Item(0), d.X1, d.Y1, d.Z1)
            Dim s2 As Double = AttachmentStationCoordinateV09(attachments.Item(0), d.X2, d.Y2, d.Z2)
            DrawHorizontalDimensionV09(svg, leftX + Math.Min(s1, s2) * sx, leftX + Math.Max(s1, s2) * sx, mainY + 72.0, d.Value)
        ElseIf d.ConnectionType = "FLANGE_THICKNESS" Then
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

'''

data_marker = """' ===================================================================
' DATA CLASSES
' ===================================================================
"""
if data_marker not in text:
    raise SystemExit('DATA CLASSES marker not found.')
text = text.replace(data_marker, helpers + data_marker, 1)

text = text.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')
src.write_bytes(text.encode('utf-8'))
print('Applied attachment-aware extraction and two-view schematic V0.9')
