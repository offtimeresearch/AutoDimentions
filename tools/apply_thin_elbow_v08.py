#!/usr/bin/env python3
from pathlib import Path

src = Path('TopologyExtractor.vb')
text = src.read_text(encoding='utf-8-sig')

# ------------------------------------------------------------------
# 1) Replace elbow renderer with a simple thin 90-degree schematic.
#    The elbow ports remain the true tangent/end locations and the
#    elbow.Ref point is the theoretical intersection of those axes.
#    Draw: port1 -> corner -> port2.
# ------------------------------------------------------------------
start_marker = 'Sub DrawElbowArc( _'
end_marker = "\nEnd Sub\n\n\n\n' ===================================================================\n' COMPONENT LABELS"

start = text.find(start_marker)
if start < 0:
    raise SystemExit('DrawElbowArc start not found')

end = text.find(end_marker, start)
if end < 0:
    raise SystemExit('DrawElbowArc end marker not found')

replacement = r'''Sub DrawElbowArc( _
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

End Sub'''

text = text[:start] + replacement + text[end + len('\nEnd Sub'):]

# ------------------------------------------------------------------
# 2) Put E1 next to the 90-degree corner rather than at arc midpoint.
# ------------------------------------------------------------------
label_start = '        ElseIf n.ComponentType = "ELBOW" Then'
label_end = '        ElseIf n.ComponentType = "FLANGE" Then'

ls = text.find(label_start)
if ls < 0:
    raise SystemExit('ELBOW label block start not found')

le = text.find(label_end, ls)
if le < 0:
    raise SystemExit('ELBOW label block end not found')

label_replacement = r'''        ElseIf n.ComponentType = "ELBOW" Then

            ' V0.8: elbow is drawn as a thin 90-degree routing symbol.
            ' Keep the label beside its extracted corner/reference point.
            labelX = p.X + 14
            labelY = p.Y - 14
            anchor = "start"

        ElseIf n.ComponentType = "FLANGE" Then'''

text = text[:ls] + label_replacement + text[le + len(label_end):]

# Update the top explanatory comment only; no calculation logic changes.
text = text.replace(
    "   ELBOW  : true quarter-arc between ports, with center reference",
    "   ELBOW  : thin 90-degree routing symbol through axis intersection",
    1,
)

# Plain UTF-8, CRLF, no BOM for Inventor copy/paste.
text = text.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')
src.write_bytes(text.encode('utf-8'))

print('Applied V0.8 thin 90-degree elbow renderer and corner label placement')
