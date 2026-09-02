from pathlib import Path
import re

path = Path('DimensionGenerator.vb')
text = path.read_text(encoding='utf-8')

# Version strings.
text = text.replace('DIMENSION GENERATOR V0.7.1', 'DIMENSION GENERATOR V0.7.2')
text = text.replace('DimensionGenerator V0.7.1', 'DimensionGenerator V0.7.2')
text = text.replace(
    'Logger.Info("V0.7.1: fitting centers use ONE existing centerline as an infinite directional datum; attachment dimensions remain deferred.")',
    'Logger.Info("V0.7.2: centerline preservation diagnostics enabled; fitting centers still use ONE existing directional centerline; attachments deferred.")')

# Instrument the cleanup boundary exactly once.
old_call = '        DeletePreviousAutoDimensionsV01(sheet)\n'
new_call = '''        Logger.Info( _\n            "CENTERLINE_COUNT BEFORE_CLEANUP=" & _\n            sheet.Centerlines.Count.ToString())\n\n        DeletePreviousAutoDimensionsV01(sheet)\n\n        Logger.Info( _\n            "CENTERLINE_COUNT AFTER_CLEANUP=" & _\n            sheet.Centerlines.Count.ToString())\n'''
if 'CENTERLINE_COUNT BEFORE_CLEANUP=' not in text:
    if old_call not in text:
        raise RuntimeError('Could not find DeletePreviousAutoDimensionsV01(sheet) call')
    text = text.replace(old_call, new_call, 1)

# Also log immediately before anchor resolution so we can prove whether some
# intermediate planning step has touched the sheet centerline collection.
needle = '''        Dim unresolvedAnchors As Integer = _\n            ResolveProjectedAnchorsV03( _'''
replacement = '''        Logger.Info( _\n            "CENTERLINE_COUNT BEFORE_RESOLVE=" & _\n            sheet.Centerlines.Count.ToString())\n\n        Dim unresolvedAnchors As Integer = _\n            ResolveProjectedAnchorsV03( _'''
if 'CENTERLINE_COUNT BEFORE_RESOLVE=' not in text:
    if needle not in text:
        raise RuntimeError('Could not find ResolveProjectedAnchorsV03 call')
    text = text.replace(needle, replacement, 1)

# Replace the cleanup function wholesale.  Production DimensionGenerator is
# not allowed to inspect, tag, modify, or delete centerlines.  Centerlines are
# owned exclusively by CenterlineGenerator.
pattern = re.compile(
    r'Sub\s+DeletePreviousAutoDimensionsV01\s*\(\s*sheet\s+As\s+Sheet\s*\).*?\nEnd Sub',
    re.S | re.I)

safe_cleanup = r'''Sub DeletePreviousAutoDimensionsV01(sheet As Sheet)

    ' V0.7.2 HARD SAFETY BOUNDARY:
    ' DimensionGenerator NEVER touches sheet.Centerlines here.
    ' Centerlines are owned by CenterlineGenerator V0.2.

    Try
        Dim chainSets As ChainDimensionSets = _
            sheet.DrawingDimensions.ChainDimensionSets

        For i As Integer = chainSets.Count To 1 Step -1
            If IsAutoTaggedV01(chainSets.Item(i)) Then
                chainSets.Item(i).Delete()
            End If
        Next
    Catch ex As Exception
        Logger.Error("Cleanup chain dimensions failed: " & ex.Message)
    End Try

    Try
        Dim baselineSets As BaselineDimensionSets = _
            sheet.DrawingDimensions.BaselineDimensionSets

        For i As Integer = baselineSets.Count To 1 Step -1
            If IsAutoTaggedV01(baselineSets.Item(i)) Then
                baselineSets.Item(i).Delete()
            End If
        Next
    Catch ex As Exception
        Logger.Error("Cleanup baseline dimensions failed: " & ex.Message)
    End Try

    Try
        Dim generalDimensions As GeneralDimensions = _
            sheet.DrawingDimensions.GeneralDimensions

        For i As Integer = generalDimensions.Count To 1 Step -1
            If IsAutoTaggedV01(generalDimensions.Item(i)) Then
                generalDimensions.Item(i).Delete()
            End If
        Next
    Catch ex As Exception
        Logger.Error("Cleanup general dimensions failed: " & ex.Message)
    End Try

    Try
        Dim oldSketch As DrawingSketch = _
            sheet.Sketches.Item("AUTO_DIM_ANCHORS")
        oldSketch.Delete()
    Catch
    End Try

End Sub'''

m = pattern.search(text)
if not m:
    raise RuntimeError('DeletePreviousAutoDimensionsV01 function not found')
text = text[:m.start()] + safe_cleanup + text[m.end():]

# Hard assertion: the safe cleanup function must contain no Centerlines token.
cleanup_match = pattern.search(text)
if not cleanup_match:
    raise RuntimeError('Safe cleanup function missing after replacement')
cleanup_text = cleanup_match.group(0)
if 'Centerlines' in cleanup_text:
    raise RuntimeError('Unsafe Centerlines reference remains in cleanup function')

path.write_text(text, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator to V0.7.2 centerline-preservation diagnostics.')
