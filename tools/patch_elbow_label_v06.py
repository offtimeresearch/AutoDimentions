#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("TopologyExtractor.vb")
text = p.read_text(encoding="utf-8")

# Pass edge information to the label renderer so elbow labels can be
# positioned from the actual used elbow ports / drawn arc.
old_call = '''    DrawComponentLabels( _\n        svg, _\n        nodes, _\n        transform)'''
new_call = '''    DrawComponentLabels( _\n        svg, _\n        nodes, _\n        edges, _\n        transform)'''
if old_call not in text:
    raise SystemExit("DrawComponentLabels call pattern not found")
text = text.replace(old_call, new_call, 1)

new_block = r'''Sub DrawComponentLabels( _
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

            ' -------------------------------------------------------
            ' Put the elbow label near the middle of the quarter arc.
            ' The elbow Ref point is the intersection of its two tangent
            ' axes, which can be visually far away from the curved line.
            ' -------------------------------------------------------

            Dim elbowPorts As List(Of PortRecord) = _
                GetUsedPorts(n, edges)

            Dim positionedOnArc As Boolean = False


            If elbowPorts.Count >= 2 Then

                Dim a As SvgPoint = _
                    MapCanonicalPoint( _
                        transform, _
                        elbowPorts.Item(0).X, _
                        elbowPorts.Item(0).Y, _
                        elbowPorts.Item(0).Z)

                Dim b As SvgPoint = _
                    MapCanonicalPoint( _
                        transform, _
                        elbowPorts.Item(1).X, _
                        elbowPorts.Item(1).Y, _
                        elbowPorts.Item(1).Z)


                Dim v1x As Double = a.X - p.X
                Dim v1y As Double = a.Y - p.Y
                Dim v2x As Double = b.X - p.X
                Dim v2y As Double = b.Y - p.Y

                Dim r1 As Double = _
                    Math.Sqrt(v1x * v1x + v1y * v1y)

                Dim r2 As Double = _
                    Math.Sqrt(v2x * v2x + v2y * v2y)


                If r1 > 1.0 AndAlso r2 > 1.0 Then

                    v1x /= r1
                    v1y /= r1
                    v2x /= r2
                    v2y /= r2

                    Dim bisX As Double = v1x + v2x
                    Dim bisY As Double = v1y + v2y

                    Dim bisLen As Double = _
                        Math.Sqrt(bisX * bisX + bisY * bisY)


                    If bisLen > 0.01 Then

                        bisX /= bisLen
                        bisY /= bisLen

                        Dim radiusPixels As Double = (r1 + r2) / 2.0

                        ' Slightly outside the centerline arc so the text
                        ' is close to E1 without sitting directly on it.
                        labelX = p.X + bisX * (radiusPixels + 18.0)
                        labelY = p.Y + bisY * (radiusPixels + 18.0) - 4.0
                        anchor = "middle"
                        positionedOnArc = True

                    End If

                End If

            End If


            If Not positionedOnArc Then

                labelX = p.X - 18
                labelY = p.Y - 14
                anchor = "end"

            End If

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

End Sub'''

pattern = re.compile(r"Sub DrawComponentLabels\( _.*?\nEnd Sub\n\n\n' ===================================================================\n' DIMENSION DRAWING", re.S)
m = pattern.search(text)
if not m:
    raise SystemExit("DrawComponentLabels function block not found")
replacement = new_block + "\n\n\n' ===================================================================\n' DIMENSION DRAWING"
text = text[:m.start()] + replacement + text[m.end():]

p.write_text(text, encoding="utf-8", newline="\r\n")
print("Applied elbow arc-label placement V0.6")
