from pathlib import Path
import re

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

if 'DimensionGenerator V0.9' not in text:
    raise RuntimeError('Expected DimensionGenerator V0.9 as patch base')

text = text.replace('DimensionGenerator V0.9', 'DimensionGenerator V0.10')
text = text.replace(
    'V0.9: native physical chain sets + reference fitting dimensions + cleaned dimension tiers; attachments deferred.',
    'V0.10: true Inventor reference dimensions + explicit drawing-view selection + increased annotation spacing; attachments deferred.')


def replace_function(name, replacement):
    global text
    rx = re.compile(r'Function\s+' + re.escape(name) + r'\s*\(.*?\nEnd Function', re.S | re.I)
    m = rx.search(text)
    if not m:
        raise RuntimeError('Function not found: ' + name)
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


def replace_sub(name, replacement):
    global text
    rx = re.compile(r'Sub\s+' + re.escape(name) + r'\s*\(.*?\nEnd Sub', re.S | re.I)
    m = rx.search(text)
    if not m:
        raise RuntimeError('Sub not found: ' + name)
    text = text[:m.start()] + replacement.rstrip() + text[m.end():]


# ---------------------------------------------------------------------------
# Explicit drawing-view choice.
# - If exactly one DrawingView is preselected, use it.
# - If only one view exists on the sheet, use it directly.
# - Otherwise show an InputListBox so the user decides which view to dimension.
# ---------------------------------------------------------------------------
replace_function('GetTargetDrawingViewV01', r'''Function GetTargetDrawingViewV01( _
    drawDoc As DrawingDocument, _
    sheet As Sheet) As DrawingView

    If drawDoc Is Nothing OrElse sheet Is Nothing Then Return Nothing

    ' ---------------------------------------------------------------
    ' Preferred workflow: preselect the view, then run the rule.
    ' ---------------------------------------------------------------
    Try
        Dim selectedView As DrawingView = Nothing
        Dim selectedCount As Integer = 0

        For Each selectedObject As Object In drawDoc.SelectSet
            If TypeOf selectedObject Is DrawingView Then
                Dim candidate As DrawingView = CType(selectedObject, DrawingView)

                ' Accept only a view that belongs to the active sheet.
                For i As Integer = 1 To sheet.DrawingViews.Count
                    Dim sheetView As DrawingView = sheet.DrawingViews.Item(i)
                    If sheetView.Name = candidate.Name Then
                        selectedView = sheetView
                        selectedCount += 1
                        Exit For
                    End If
                Next
            End If
        Next

        If selectedCount = 1 AndAlso selectedView IsNot Nothing Then
            Logger.Info("VIEW_PICKER preselected | " & selectedView.Name)
            Return selectedView
        End If
    Catch ex As Exception
        Logger.Info("VIEW_PICKER preselection check skipped | " & ex.Message)
    End Try

    If sheet.DrawingViews.Count = 0 Then Return Nothing

    If sheet.DrawingViews.Count = 1 Then
        Logger.Info("VIEW_PICKER single view | " & sheet.DrawingViews.Item(1).Name)
        Return sheet.DrawingViews.Item(1)
    End If

    Dim labels As New System.Collections.ArrayList

    For i As Integer = 1 To sheet.DrawingViews.Count
        Dim v As DrawingView = sheet.DrawingViews.Item(i)
        labels.Add(v.Name)
    Next

    Dim choice As Object = _
        InputListBox( _
            "Select the drawing view to auto-dimension.", _
            labels, _
            labels.Item(0), _
            "Auto Dimensions - Select View", _
            "Drawing View")

    If choice Is Nothing Then
        Logger.Info("VIEW_PICKER cancelled")
        Return Nothing
    End If

    Dim selectedName As String = CStr(choice)

    For i As Integer = 1 To sheet.DrawingViews.Count
        Dim v As DrawingView = sheet.DrawingViews.Item(i)
        If v.Name = selectedName Then
            Logger.Info("VIEW_PICKER chosen | " & v.Name)
            Return v
        End If
    Next

    Return Nothing
End Function''')


# ---------------------------------------------------------------------------
# Use Inventor's real reference-dimension state instead of text parentheses.
# This is the exact mechanism proven by the user:
#     GeneralDimension.Tolerance.SetToReference
# It works for ordinary GeneralDimensions and ChainDimensionSet members.
# ---------------------------------------------------------------------------
replace_sub('ApplyReferenceDisplayV09', r'''Sub ApplyReferenceDisplayV09(dimObj As GeneralDimension)
    If dimObj Is Nothing Then Exit Sub

    Try
        dimObj.Tolerance.SetToReference()

        Try
            If Not dimObj.AttributeSets.NameIsUsed("AutoReferenceDimension") Then
                dimObj.AttributeSets.Add("AutoReferenceDimension")
            End If
        Catch
        End Try

        Logger.Info("REFERENCE_DIM true reference applied")

    Catch ex As Exception
        Logger.Error("Reference SetToReference failed: " & ex.Message)
    End Try
End Sub''')


# ---------------------------------------------------------------------------
# Increase space between the spool/view envelope and dimension tiers.
# Keep the same relative layout logic, only increase offsets.
# ---------------------------------------------------------------------------
text = text.replace('bottomY - 0.65)', 'bottomY - 1.00)')
text = text.replace('bottomY - 1.35)', 'bottomY - 1.85)')
text = text.replace('rightX + 0.65, _', 'rightX + 1.00, _')
text = text.replace('rightX + 1.40, _', 'rightX + 1.85, _')
text = text.replace('Dim offset As Double = 0.85 + (alignedLevel - 1) * 0.60',
                    'Dim offset As Double = 1.15 + (alignedLevel - 1) * 0.75')
text = text.replace('midX + nx * (offset + 0.70)', 'midX + nx * (offset + 0.85)')
text = text.replace('midY + ny * (offset + 0.70)', 'midY + ny * (offset + 0.85)')

# Global vertical overall V0.9 may use a fixed right-side offset independent of
# BuildChainRequests.  Move it outward if that exact placement is present.
text = text.replace('rightX + 2.15', 'rightX + 2.45')
text = text.replace('rightX + 2.10', 'rightX + 2.45')

path.write_text(text, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator to V0.10')
