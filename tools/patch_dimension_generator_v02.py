#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

old = '''Function CreateAnchorSketchV01( _
    sheet As Sheet, _
    allAnchors As List(Of AutoDimAnchorV01)) As DrawingSketch

    Dim sketch As DrawingSketch = sheet.Sketches.Add()
    sketch.Name = "AUTO_DIM_ANCHORS"

    sketch.Edit()

    For Each anchor As AutoDimAnchorV01 In allAnchors
        anchor.Entity = _
            sketch.SketchPoints.Add( _
                ThisApplication.TransientGeometry.CreatePoint2d( _
                    anchor.SheetPoint.X, _
                    anchor.SheetPoint.Y), _
                False)
    Next

    sketch.ExitEdit()
    Return sketch
End Function
'''

new = '''Function CreateAnchorSketchV01( _
    sheet As Sheet, _
    allAnchors As List(Of AutoDimAnchorV01)) As DrawingSketch

    Dim sketch As DrawingSketch = sheet.Sketches.Add()
    sketch.Name = "AUTO_DIM_ANCHORS"

    sketch.Edit()

    ' V0.2: Sheet.CreateGeometryIntent accepts sheet-sketch entities.
    ' A standalone SketchPoint was producing E_FAIL in Inventor.
    ' Create a tiny 45-degree sketch line centred exactly on every
    ' semantic anchor and later request its midpoint intent.
    Dim halfLength As Double = 0.025

    For Each anchor As AutoDimAnchorV01 In allAnchors

        Dim p1 As Point2d = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                anchor.SheetPoint.X - halfLength, _
                anchor.SheetPoint.Y - halfLength)

        Dim p2 As Point2d = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                anchor.SheetPoint.X + halfLength, _
                anchor.SheetPoint.Y + halfLength)

        anchor.Entity = _
            sketch.SketchLines.AddByTwoPoints(p1, p2)

        Try
            anchor.Entity.Construction = True
        Catch
        End Try

    Next

    sketch.ExitEdit()
    Return sketch
End Function


Function CreateAnchorIntentV02( _
    sheet As Sheet, _
    anchor As AutoDimAnchorV01) As GeometryIntent

    If anchor Is Nothing OrElse anchor.Entity Is Nothing Then
        Return Nothing
    End If

    Return _
        sheet.CreateGeometryIntent( _
            anchor.Entity, _
            PointIntentEnum.kMidPointIntent)
End Function
'''

if old not in s:
    raise SystemExit('CreateAnchorSketchV01 block not found')
s = s.replace(old, new, 1)

repls = {
    'sheet.CreateGeometryIntent(anchor.Entity)': 'CreateAnchorIntentV02(sheet, anchor)',
    'sheet.CreateGeometryIntent(firstAnchor.Entity)': 'CreateAnchorIntentV02(sheet, firstAnchor)',
    'sheet.CreateGeometryIntent(lastAnchor.Entity)': 'CreateAnchorIntentV02(sheet, lastAnchor)',
    'sheet.CreateGeometryIntent(plan.Datum.Entity)': 'CreateAnchorIntentV02(sheet, plan.Datum)',
    'sheet.CreateGeometryIntent(request.A.Entity)': 'CreateAnchorIntentV02(sheet, request.A)',
    'sheet.CreateGeometryIntent(request.B.Entity)': 'CreateAnchorIntentV02(sheet, request.B)',
}
for a, b in repls.items():
    s = s.replace(a, b)

s = s.replace('Public Entity As SketchPoint = Nothing', 'Public Entity As SketchLine = Nothing')

oldcatch = '''        Catch ex As Exception
            Logger.Error( _
                "Chain dimension failed for " & _
                request.Name & _
                ": " & _
                ex.Message)
        End Try
'''
newcatch = '''        Catch ex As Exception
            Logger.Error( _
                "Chain dimension set failed for " & _
                request.Name & _
                ": " & _
                ex.Message & _
                " | attempting individual fallback")

            created += _
                CreateIndividualChainFallbackV02( _
                    sheet, _
                    request)
        End Try
'''
if oldcatch not in s:
    raise SystemExit('Chain catch block not found')
s = s.replace(oldcatch, newcatch, 1)

marker = '''Function CreateOverallDimensionsV01( _
'''
fallback = '''Function CreateIndividualChainFallbackV02( _
    sheet As Sheet, _
    request As AutoChainRequestV01) As Integer

    Dim created As Integer = 0

    If request Is Nothing OrElse request.Anchors.Count < 2 Then
        Return created
    End If

    For i As Integer = 0 To request.Anchors.Count - 2

        Try
            Dim a As AutoDimAnchorV01 = request.Anchors.Item(i)
            Dim b As AutoDimAnchorV01 = request.Anchors.Item(i + 1)

            Dim intent1 As GeometryIntent = _
                CreateAnchorIntentV02(sheet, a)
            Dim intent2 As GeometryIntent = _
                CreateAnchorIntentV02(sheet, b)

            If intent1 Is Nothing OrElse intent2 Is Nothing Then
                Continue For
            End If

            Dim textPoint As Point2d = _
                request.PlacementPoint.Copy()

            If request.DimensionType = _
               DimensionTypeEnum.kHorizontalDimensionType Then

                textPoint.X = _
                    (a.SheetPoint.X + b.SheetPoint.X) / 2.0

            ElseIf request.DimensionType = _
                   DimensionTypeEnum.kVerticalDimensionType Then

                textPoint.Y = _
                    (a.SheetPoint.Y + b.SheetPoint.Y) / 2.0

            Else

                textPoint.X = _
                    (a.SheetPoint.X + b.SheetPoint.X) / 2.0
                textPoint.Y = _
                    (a.SheetPoint.Y + b.SheetPoint.Y) / 2.0
            End If

            Dim dimObj As LinearGeneralDimension = _
                sheet.DrawingDimensions.GeneralDimensions.AddLinear( _
                    textPoint, _
                    intent1, _
                    intent2, _
                    request.DimensionType)

            Try
                dimObj.Precision = 0
            Catch
            End Try

            TagAutoObjectV01(dimObj)
            created += 1

        Catch ex As Exception
            Logger.Error( _
                "Individual chain fallback failed for " & _
                request.Name & _
                " member " & _
                (i + 1).ToString() & _
                ": " & _
                ex.Message)
        End Try

    Next

    Return created
End Function


'''
if marker not in s:
    raise SystemExit('Overall function marker not found')
s = s.replace(marker, fallback + marker, 1)

# Improve title/version markers.
s = s.replace('DimensionGenerator V0.1 failed:', 'DimensionGenerator V0.2 failed:')
s = s.replace('"DimensionGenerator V0.1")', '"DimensionGenerator V0.2")')
s = s.replace("' DIMENSION GENERATOR V0.1 - DRAWING API LAYER", "' DIMENSION GENERATOR V0.2 - DRAWING API LAYER")

# Sanity checks for the exact bug we are fixing.
if 'Public Entity As SketchPoint' in s:
    raise SystemExit('SketchPoint anchor entity still present')
if 'CreateGeometryIntent(anchor.Entity)' in s:
    raise SystemExit('Direct anchor.Entity intent still present')
if 'CreateAnchorIntentV02' not in s:
    raise SystemExit('V0.2 intent helper missing')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.2')
