#!/usr/bin/env python3
from pathlib import Path

src = Path('TopologyExtractor.vb')
text = src.read_text(encoding='utf-8-sig')

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
    ' V0.7 - CLOSED ELBOW PROFILE
    '
    ' The previous renderer drew only the elbow centerline.  For visual
    ' verification that made the bend look "open" compared with the
    ' fabrication drawing.  Draw two concentric arcs using the detected
    ' end-face radius as the pipe half-width, then close the profile at
    ' both tangent ends.
    '
    ' Dimension geometry remains based on the centerline radius and is
    ' intentionally unchanged.
    ' ===============================================================

    Dim c As SvgPoint = _
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


    Dim rA As Double = _
        Math.Sqrt( _
            (a.X - c.X) * (a.X - c.X) + _
            (a.Y - c.Y) * (a.Y - c.Y))

    Dim rB As Double = _
        Math.Sqrt( _
            (b.X - c.X) * (b.X - c.X) + _
            (b.Y - c.Y) * (b.Y - c.Y))


    If rA < 1 OrElse rB < 1 Then
        Exit Sub
    End If


    Dim centerRadius As Double = (rA + rB) / 2.0


    Dim u1x As Double = (a.X - c.X) / rA
    Dim u1y As Double = (a.Y - c.Y) / rA

    Dim u2x As Double = (b.X - c.X) / rB
    Dim u2y As Double = (b.Y - c.Y) / rB


    Dim cross2d As Double = _
        u1x * u2y - _
        u1y * u2x


    Dim sweep As Integer = 0

    If cross2d > 0 Then
        sweep = 1
    End If


    ' ---------------------------------------------------------------
    ' Convert the detected elbow end-face radius from mm to pixels.
    ' PortRecord.Radius comes from the largest circular boundary on the
    ' end face and therefore gives a useful visual pipe half-width.
    ' Keep a conservative fallback/clamp for unusual fitting geometry.
    ' ---------------------------------------------------------------

    Dim pipeRadiusMm As Double = 0

    If port1.Radius > 0 AndAlso port2.Radius > 0 Then
        pipeRadiusMm = (port1.Radius + port2.Radius) / 2.0
    ElseIf port1.Radius > 0 Then
        pipeRadiusMm = port1.Radius
    ElseIf port2.Radius > 0 Then
        pipeRadiusMm = port2.Radius
    End If


    Dim halfWidth As Double = pipeRadiusMm * transform.Scale

    If halfWidth < 8.0 Then
        halfWidth = 8.0
    End If

    Dim maxHalfWidth As Double = centerRadius * 0.42

    If halfWidth > maxHalfWidth Then
        halfWidth = maxHalfWidth
    End If


    Dim innerRadius As Double = centerRadius - halfWidth
    Dim outerRadius As Double = centerRadius + halfWidth

    If innerRadius < 3.0 Then
        innerRadius = 3.0
    End If


    Dim aInner As New SvgPoint( _
        c.X + u1x * innerRadius, _
        c.Y + u1y * innerRadius)

    Dim bInner As New SvgPoint( _
        c.X + u2x * innerRadius, _
        c.Y + u2y * innerRadius)

    Dim aOuter As New SvgPoint( _
        c.X + u1x * outerRadius, _
        c.Y + u1y * outerRadius)

    Dim bOuter As New SvgPoint( _
        c.X + u2x * outerRadius, _
        c.Y + u2y * outerRadius)


    ' Inner outline.
    svg.AppendLine( _
        "<path d=""M " & _
        Num(aInner.X) & " " & Num(aInner.Y) & _
        " A " & _
        Num(innerRadius) & " " & Num(innerRadius) & _
        " 0 0 " & sweep.ToString() & " " & _
        Num(bInner.X) & " " & Num(bInner.Y) & _
        """ fill=""none"" stroke=""black"" stroke-width=""3""/>")


    ' Outer outline - this is the missing line the verification image
    ' previously did not show near E1.
    svg.AppendLine( _
        "<path d=""M " & _
        Num(aOuter.X) & " " & Num(aOuter.Y) & _
        " A " & _
        Num(outerRadius) & " " & Num(outerRadius) & _
        " 0 0 " & sweep.ToString() & " " & _
        Num(bOuter.X) & " " & Num(bOuter.Y) & _
        """ fill=""none"" stroke=""black"" stroke-width=""3""/>")


    ' Close both tangent ends so the elbow reads as a pipe profile,
    ' not as a single open centerline curve.
    svg.AppendLine( _
        "<line x1=""" & Num(aInner.X) & _
        """ y1=""" & Num(aInner.Y) & _
        """ x2=""" & Num(aOuter.X) & _
        """ y2=""" & Num(aOuter.Y) & _
        """ stroke=""black"" stroke-width=""3""/>")

    svg.AppendLine( _
        "<line x1=""" & Num(bInner.X) & _
        """ y1=""" & Num(bInner.Y) & _
        """ x2=""" & Num(bOuter.X) & _
        """ y2=""" & Num(bOuter.Y) & _
        """ stroke=""black"" stroke-width=""3""/>")


    ' Thin dashed centerline retained only as a visual reference.
    svg.AppendLine( _
        "<path d=""M " & _
        Num(a.X) & " " & Num(a.Y) & _
        " A " & _
        Num(centerRadius) & " " & Num(centerRadius) & _
        " 0 0 " & sweep.ToString() & " " & _
        Num(b.X) & " " & Num(b.Y) & _
        """ fill=""none"" stroke=""black"" stroke-width=""1"" stroke-dasharray=""8,6""/>")

End Sub'''

new_text = text[:start] + replacement + text[end + len('\nEnd Sub'):]

# Keep plain UTF-8 with CRLF and no BOM for Inventor copy/paste.
new_text = new_text.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')
src.write_bytes(new_text.encode('utf-8'))

print('Patched DrawElbowArc with closed double-line elbow profile V0.7')
