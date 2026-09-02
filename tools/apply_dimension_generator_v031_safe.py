#!/usr/bin/env python3
from pathlib import Path
import re

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DIMENSION GENERATOR V0.3 - PROJECTED DRAWING GEOMETRY LAYER',
              'DIMENSION GENERATOR V0.3.1 - SAFE PROJECTED CURVES ONLY')
s = s.replace('"DimensionGenerator V0.3"', '"DimensionGenerator V0.3.1"')
s = s.replace('"DimensionGenerator V0.3 failed:"', '"DimensionGenerator V0.3.1 failed:"')

# Disable all centerline creation in the resolver.
s = s.replace("    ' Create native Inventor centerlines from the actual projected view.\n    ' These are not sketch entities; they are sheet Centerline objects.\n    CreateAutomatedCenterlinesV03(sheet, view)\n\n", "")

# Replace the resolver with a deliberately conservative occurrence/projected-curve-only path.
start = s.index('Function ResolveProjectedIntentV03(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')
new_func = r'''Function ResolveProjectedIntentV03( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    anchor As AutoDimAnchorV01) As GeometryIntent

    ' V0.3.1 SAFE MODE
    ' Only resolve topology anchors that coincide with a real component port.
    ' Then inspect that occurrence's ACTUAL projected DrawingCurves and select
    ' the curve closest to the expected projected semantic point.
    '
    ' No automated centerlines, no AddBisector and no global view-curve snap.
    ' Theoretical tee/elbow centres are intentionally unresolved in this test.

    Dim port As PortRecord = _
        FindPortAtModelPointV03( _
            nodes, anchor.X, anchor.Y, anchor.Z, 0.6)

    If port Is Nothing OrElse _
       port.Owner Is Nothing OrElse _
       port.Owner.Occurrence Is Nothing Then
        Return Nothing
    End If

    Dim projectedIntent As GeometryIntent = _
        FindOccurrenceDrawingIntentV031( _
            sheet, _
            view, _
            port.Owner.Occurrence, _
            anchor.SheetPoint)

    If projectedIntent IsNot Nothing Then
        anchor.SourceDescription = _
            port.Owner.Code & " PROJECTED CURVE NEAR FACE " & _
            port.FaceIndex.ToString()
    End If

    Return projectedIntent
End Function


Function FindOccurrenceDrawingIntentV031( _
    sheet As Sheet, _
    view As DrawingView, _
    occurrence As ComponentOccurrence, _
    target As Point2d) As GeometryIntent

    If occurrence Is Nothing OrElse target Is Nothing Then Return Nothing

    Try
        Dim curves As DrawingCurvesEnumerator = _
            view.DrawingCurves(occurrence)

        If curves Is Nothing OrElse curves.Count = 0 Then Return Nothing

        Dim best As DrawingCurve = Nothing
        Dim bestDistance As Double = 0.18

        For Each c As DrawingCurve In curves
            Dim d As Double = DrawingCurveDistanceV03(c, target)
            If d <= bestDistance Then
                bestDistance = d
                best = c
            End If
        Next

        If best Is Nothing Then Return Nothing

        ' Prefer the actual projected line itself for end-face dimensions.
        If best.CurveType = CurveTypeEnum.kLineSegmentCurve Then
            Return sheet.CreateGeometryIntent(best)
        End If

        ' If a circular face is viewed normal-on, its centre is the semantic
        ' axis location and is a valid drawing-curve intent.
        If best.CurveType = CurveTypeEnum.kCircleCurve OrElse _
           best.CurveType = CurveTypeEnum.kCircularArcCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipseFullCurve OrElse _
           best.CurveType = CurveTypeEnum.kEllipticalArcCurve Then

            Return _
                sheet.CreateGeometryIntent( _
                    best, _
                    PointIntentEnum.kCenterPointIntent)
        End If

        Return Nothing

    Catch ex As Exception
        Logger.Error( _
            "Safe DrawingCurves(occurrence) resolve failed for " & _
            occurrence.Name & ": " & ex.Message)
        Return Nothing
    End Try
End Function'''
s = s[:start] + new_func + s[end:]

# Safe test: do NOT invoke native chain dimension sets. Use the existing
# individual linear fallback only, which consumes the same real projected intents.
chain_start = s.index('Function CreateChainDimensionsV01(')
chain_end = s.index('\nEnd Function', chain_start) + len('\nEnd Function')
new_chain = r'''Function CreateChainDimensionsV01( _
    sheet As Sheet, _
    requests As List(Of AutoChainRequestV01)) As Integer

    ' V0.3.1 SAFE MODE:
    ' First prove that dimensions attached directly to real projected curves
    ' are stable. Native ChainDimensionSet creation is deliberately disabled
    ' for this build and will be re-enabled after this test succeeds.

    Dim created As Integer = 0

    For Each request As AutoChainRequestV01 In requests
        created += _
            CreateIndividualChainFallbackV02( _
                sheet, _
                request)
    Next

    Return created
End Function'''
s = s[:chain_start] + new_chain + s[chain_end:]

# Safe test: overall dimensions remain ordinary AddLinear calls, but only with
# resolved real projected intents. Attachment generation is disabled in Main
# because attachment stations require centre/axis semantics not yet re-enabled.
s = s.replace('        Dim attachmentCount As Integer = _\n            CreateAttachmentDimensionsV01( _\n                sheet, _\n                attachmentPlan)\n',
              '        Dim attachmentCount As Integer = 0\n        Logger.Info("V0.3.1 safe mode: attachment dimensions deferred until native centerlines are re-enabled.")\n')

# Make the summary accurately describe this staged test.
s = s.replace('"Chain sets: " & chainCount.ToString() & vbCrLf & _',
              '"Projected-curve linear dimensions: " & chainCount.ToString() & vbCrLf & _')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.3.1 safe projected-curve mode')
