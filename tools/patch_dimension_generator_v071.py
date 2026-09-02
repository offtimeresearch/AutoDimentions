from pathlib import Path
import re

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

text = text.replace(
    'DIMENSION GENERATOR V0.7 - DIRECTIONAL CENTERLINE DATUMS + SAFE CHAINS',
    'DIMENSION GENERATOR V0.7.1 - EXTENDED DIRECTIONAL CENTERLINE DATUMS')
text = text.replace('DimensionGenerator V0.7', 'DimensionGenerator V0.7.1')
text = text.replace(
    'Logger.Info("V0.7: projected-curve chains enabled; fitting centers use ONE existing perpendicular centerline; attachment dimensions remain deferred.")',
    'Logger.Info("V0.7.1: fitting centers use ONE existing centerline as an infinite directional datum; attachment dimensions remain deferred.")')


def replace_function(name: str, replacement: str):
    global text
    pattern = re.compile(r'Function\s+' + re.escape(name) + r'\s*\(.*?\nEnd Function', re.S)
    m = pattern.search(text)
    if not m:
        raise RuntimeError(f'Function not found: {name}')
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


replace_function('FindDirectionalCenterlineDatumV07', r'''Function FindDirectionalCenterlineDatumV07( _
    sheet As Sheet, _
    target As Point2d, _
    wantVerticalAxis As Boolean) As Centerline

    If sheet Is Nothing OrElse target Is Nothing Then Return Nothing

    ' V0.7.1 IMPORTANT:
    ' A PIPE / FLANGE centerline is normally only a short finite drawing
    ' object.  The TEE / ELBOW center can lie well beyond its visible ends.
    ' Therefore DO NOT test whether the target lies on the finite segment.
    '
    ' For a horizontal dimension we only need the X coordinate supplied by a
    ' vertical axis.  For a vertical dimension we only need the Y coordinate
    ' supplied by a horizontal axis.  Extend each candidate mathematically to
    ' the target Y/X and compare that ONE coordinate.

    Dim bestTagged As Centerline = Nothing
    Dim bestTaggedError As Double = Double.MaxValue
    Dim bestTaggedOrientation As Double = 0

    Dim bestAny As Centerline = Nothing
    Dim bestAnyError As Double = Double.MaxValue
    Dim bestAnyOrientation As Double = 0

    Dim directionalCandidates As Integer = 0
    Dim taggedCandidates As Integer = 0

    Try
        Logger.Info( _
            "CENTER_DATUM_SCAN total centerlines=" & _
            sheet.Centerlines.Count.ToString() & _
            " | need=" & If(wantVerticalAxis, "VERTICAL/X", "HORIZONTAL/Y"))

        For i As Integer = 1 To sheet.Centerlines.Count

            Dim cl As Centerline = sheet.Centerlines.Item(i)
            If cl Is Nothing Then Continue For

            Dim a As Point2d = Nothing
            Dim b As Point2d = Nothing

            Try
                a = cl.StartPoint
                b = cl.EndPoint
            Catch
                Continue For
            End Try

            If a Is Nothing OrElse b Is Nothing Then Continue For

            Dim dx As Double = b.X - a.X
            Dim dy As Double = b.Y - a.Y
            Dim length As Double = Math.Sqrt(dx * dx + dy * dy)
            If length < 0.001 Then Continue For

            Dim ux As Double = dx / length
            Dim uy As Double = dy / length

            Dim orientation As Double
            If wantVerticalAxis Then
                orientation = Math.Abs(uy)
            Else
                orientation = Math.Abs(ux)
            End If

            ' Deliberately tolerant of tiny drawing-view skew.  We score the
            ' remaining orientation error instead of requiring perfect H/V.
            If orientation < 0.90 Then Continue For

            Dim coordinateError As Double = Double.MaxValue

            If wantVerticalAxis Then
                If Math.Abs(dy) < 0.000001 Then Continue For

                Dim xAtTargetY As Double = _
                    a.X + (target.Y - a.Y) * dx / dy

                coordinateError = Math.Abs(xAtTargetY - target.X)
            Else
                If Math.Abs(dx) < 0.000001 Then Continue For

                Dim yAtTargetX As Double = _
                    a.Y + (target.X - a.X) * dy / dx

                coordinateError = Math.Abs(yAtTargetX - target.Y)
            End If

            directionalCandidates += 1

            Dim isGenerated As Boolean = False
            Dim ownerText As String = "UNTAGGED"

            Try
                Dim tags As AttributeSet = _
                    cl.AttributeSets.Item("AutoSpoolCenterline")

                If tags IsNot Nothing Then
                    isGenerated = True
                    taggedCandidates += 1

                    Try
                        ownerText = _
                            tags.Item("ComponentType").Value.ToString() & ":" & _
                            tags.Item("Occurrence").Value.ToString()
                    Catch
                        ownerText = "TAGGED"
                    End Try
                End If
            Catch
            End Try

            If isGenerated Then
                Logger.Info( _
                    "CENTER_DATUM_CANDIDATE " & ownerText & _
                    " | need=" & If(wantVerticalAxis, "VERTICAL/X", "HORIZONTAL/Y") & _
                    " | coordinateError_cm=" & Num(coordinateError) & _
                    " | orientation=" & Num(orientation))

                If coordinateError < bestTaggedError OrElse _
                   (Math.Abs(coordinateError - bestTaggedError) < 0.000001 AndAlso _
                    orientation > bestTaggedOrientation) Then

                    bestTagged = cl
                    bestTaggedError = coordinateError
                    bestTaggedOrientation = orientation
                End If
            End If

            If coordinateError < bestAnyError OrElse _
               (Math.Abs(coordinateError - bestAnyError) < 0.000001 AndAlso _
                orientation > bestAnyOrientation) Then

                bestAny = cl
                bestAnyError = coordinateError
                bestAnyOrientation = orientation
            End If
        Next

    Catch ex As Exception
        Logger.Error("CENTER_DATUM centerline scan failed: " & ex.Message)
        Return Nothing
    End Try

    Dim chosen As Centerline = Nothing
    Dim chosenError As Double = Double.MaxValue
    Dim sourceText As String = "NONE"

    ' Prefer centerlines created by CenterlineGenerator V0.2.  They belong to
    ' this spool and are much safer than arbitrary manually-created centerlines.
    If bestTagged IsNot Nothing Then
        chosen = bestTagged
        chosenError = bestTaggedError
        sourceText = "AutoSpoolCenterline"
    ElseIf bestAny IsNot Nothing Then
        chosen = bestAny
        chosenError = bestAnyError
        sourceText = "sheet fallback"
    End If

    Logger.Info( _
        "CENTER_DATUM_SCAN result" & _
        " | need=" & If(wantVerticalAxis, "VERTICAL/X", "HORIZONTAL/Y") & _
        " | directional=" & directionalCandidates.ToString() & _
        " | tagged=" & taggedCandidates.ToString() & _
        " | source=" & sourceText & _
        " | bestCoordinateError_cm=" & _
        If(chosen Is Nothing, "NONE", Num(chosenError)))

    If chosen Is Nothing Then Return Nothing

    ' Sanity guard only.  The correct generated axis should normally be nearly
    ' zero error.  0.75 cm on the sheet is intentionally generous enough for
    ' projection/rounding variation while still rejecting a clearly wrong axis.
    If chosenError > 0.75 Then
        Logger.Error( _
            "CENTER_DATUM rejected nearest directional axis because coordinate error is " & _
            Num(chosenError) & " cm")
        Return Nothing
    End If

    Return chosen
End Function''')

path.write_text(text, encoding='utf-8')
print('Patched DimensionGenerator.vb to V0.7.1')
