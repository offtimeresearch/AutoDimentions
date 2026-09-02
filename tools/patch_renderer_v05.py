#!/usr/bin/env python3
import re
import sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "TopologyExtractor.vb")
text = src.read_text(encoding="utf-8")
original = text


def replace_sub(name: str, replacement: str) -> None:
    global text
    rx = re.compile(r"(?ms)^Sub\s+" + re.escape(name) + r"\s*\(.*?^End\s+Sub\s*\n?")
    matches = list(rx.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one Sub {name}, found {len(matches)}")
    m = matches[0]
    text = text[:m.start()] + replacement.strip("\n") + "\n\n\n" + text[m.end():]


# ------------------------------------------------------------------
# Make the CSV self-explanatory: the 5 mm FLANGED_END value is only
# a topology-association gap, not a manufacturing flange dimension.
# ------------------------------------------------------------------
text = text.replace('"ConnectionDistance_mm," & _', '"TopologyGap_mm," & _')

# Slightly enlarge the actual spool inside the schematic panel while
# still leaving room for dimension chains.
text = text.replace(
    "Dim geometryW As Double = w * 0.72\n    Dim geometryH As Double = h * 0.58",
    "Dim geometryW As Double = w * 0.82\n    Dim geometryH As Double = h * 0.68",
)


replace_sub("DrawComponentLabels", r'''
Sub DrawComponentLabels( _
    svg As StringBuilder, _
    nodes As List(Of NodeRecord), _
    transform As SchematicTransform)


    ' Labels are deliberately kept away from the dimension zones.
    ' No reference-point circles are drawn: they added clutter and
    ' made flanges / elbows look less like a fabrication schematic.

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

            ' Elbow reference point is normally in the empty quadrant
            ' beside the bend.  Shift the label left so it does not sit
            ' on top of the vertical 305 / 320 dimensions.
            labelX = p.X - 18
            labelY = p.Y - 14
            anchor = "end"

        ElseIf n.ComponentType = "FLANGE" Then

            ' Place flange labels on the geometry side, not on the
            ' dimension side.  Use the neighbour direction to determine
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
''')


replace_sub("DrawAllDimensions", r'''
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
''')


replace_sub("DrawOneDimension", r'''
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
''')


# Make the important geometry visually stronger without changing the
# extracted skeleton itself.
text = text.replace(
    '""" stroke=""black"" stroke-width=""4""/>")',
    '""" stroke=""black"" stroke-width=""5"" stroke-linecap=""round""/>")',
    1,
)

# Version label only; no geometry/extraction behaviour is changed here.
text = text.replace(
    "AUTOSPOOL - SINGLE SPOOL TOPOLOGY / DIMENSION VERIFIER V0.4",
    "AUTOSPOOL - SINGLE SPOOL TOPOLOGY / DIMENSION VERIFIER V0.5",
    1,
)
text = text.replace("AutoSpool V0.4", "AutoSpool V0.5")

if text == original:
    raise RuntimeError("Patch made no changes; source layout may have changed")

src.write_text(text, encoding="utf-8", newline="")
print("Renderer V0.5 patch applied successfully")
