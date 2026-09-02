#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DIMENSION GENERATOR V0.5 - TOPOLOGY-GUIDED BISECTORS + CHAINS',
              'DIMENSION GENERATOR V0.5.1 - STABLE PROJECTED CURVES + CHAINS')
s = s.replace('"DimensionGenerator V0.5"', '"DimensionGenerator V0.5.1"')
s = s.replace('"DimensionGenerator V0.5 failed:"', '"DimensionGenerator V0.5.1 failed:"')

# Keep the proven real projected-curve resolver and native ChainDimensionSet,
# but NEVER call AddBisector from the main generator. Inventor 2026.3 has
# crashed at the COM/native layer when AddBisector is invoked programmatically.
start = s.index('Function ResolveFittingCenterIntentV04(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_func = r'''Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' V0.5.1 STABLE MODE
    ' Native ChainDimensionSet is proven stable.
    ' Real projected DrawingCurve intents are proven stable.
    '
    ' IMPORTANT:
    ' Centerlines.AddBisector is deliberately NOT called from the production
    ' dimension generator because the Inventor native process crashed when
    ' the API call was exercised.  Centre-dependent dimensions are skipped
    ' until the centerline API path is validated in a separate diagnostic rule.

    If node IsNot Nothing Then
        Logger.Info( _
            "Center-dependent anchor deferred for " & _
            node.Code & "/" & node.ComponentType & _
            " (AddBisector isolated from production rule)")
    End If

    Return Nothing
End Function'''
s = s[:start] + new_func + s[end:]

# Make the staged-mode log explicit.
s = s.replace('V0.4 staged mode: attachment dimensions remain deferred until normal spool chains/centerlines are verified.',
              'V0.5.1 stable mode: chains enabled; centerline-dependent and attachment dimensions deferred.')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.5.1 stable projected-curves + chains')
