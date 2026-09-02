#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DIMENSION GENERATOR V0.6.3 - SHEET CENTERLINES + CHAINS',
              'DIMENSION GENERATOR V0.6.3.1 - STABLE PROJECTED CURVES + CHAINS')
s = s.replace('"DimensionGenerator V0.6.3"', '"DimensionGenerator V0.6.3.1"')
s = s.replace('"DimensionGenerator V0.6.3 failed:"', '"DimensionGenerator V0.6.3.1 failed:"')
s = s.replace('V0.6.3 staged mode: attachment dimensions remain deferred while existing centerline fitting-center intents are verified.',
              'V0.6.3.1 stable mode: projected-curve chains enabled; fitting-center and attachment dimensions deferred.')

start = s.index('Function ResolveFittingCenterIntentV04(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_func = r'''Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' V0.6.3.1 PRODUCTION SAFETY
    ' Do NOT consume centerlines in the production dimension rule yet.
    '
    ' Proven stable:
    '   - real projected DrawingCurve intents
    '   - native ChainDimensionSet
    '   - separate CenterlineGenerator creating PIPE / FLANGE centerlines
    '
    ' Not yet proven safe:
    '   - centerline GeometryIntent inside a dimension
    '   - centerline/centerline intersection GeometryIntent
    '
    ' These are isolated in CenterlineDimensionProbe.vb before being
    ' reintroduced here.

    If node IsNot Nothing Then
        Logger.Info( _
            "CENTER_INTENT DEFER " & _
            node.Code & "/" & node.ComponentType & _
            " | production rule will not consume centerlines")
    End If

    Return Nothing
End Function'''

s = s[:start] + new_func + s[end:]
p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator to V0.6.3.1 stable mode')
