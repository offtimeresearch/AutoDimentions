from pathlib import Path

path = Path("DimensionGenerator.vb")
text = path.read_text(encoding="utf-8")

old_call = '''        overallCount += _
            CreateGlobalVerticalFlangeOverallV09( _
                sheet, _
                view, _
                nodes)
'''
new_call = '''        overallCount += _
            CreateGlobalVerticalFlangeOverallV09( _
                sheet, _
                view, _
                nodes, _
                chainRequests)
'''
if old_call not in text:
    raise SystemExit("main overall call block not found")
text = text.replace(old_call, new_call, 1)

old_sig = '''Function CreateGlobalVerticalFlangeOverallV09( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord)) As Integer
'''
new_sig = '''Function CreateGlobalVerticalFlangeOverallV09( _
    sheet As Sheet, _
    view As DrawingView, _
    nodes As List(Of NodeRecord), _
    requests As List(Of AutoChainRequestV01)) As Integer
'''
if old_sig not in text:
    raise SystemExit("overall function signature not found")
text = text.replace(old_sig, new_sig, 1)

old_place = '''    Try
        Dim rightX As Double = view.Left + view.Width
        Dim placement As Point2d = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                rightX + 2.55, _
                (topPoint.Y + bottomPoint.Y) / 2.0)
'''
new_place = '''    Try
        ' V0.12.1: the overall vertical dimension must follow the same side
        ' selected by the collision-aware global vertical chain.  Do not make
        ' an independent right-side decision here.
        Dim placementX As Double = view.Left + view.Width + 2.55
        Dim placementSide As String = "RIGHT_FALLBACK"

        If requests IsNot Nothing Then
            For Each request As AutoChainRequestV01 In requests
                If request Is Nothing Then Continue For

                If request.Name = "GLOBAL VERTICAL V011" AndAlso _
                   request.OverallPlacementPoint IsNot Nothing Then

                    placementX = request.OverallPlacementPoint.X
                    placementSide = _
                        If(placementX < view.Left, "LEFT", "RIGHT")
                    Exit For
                End If
            Next
        End If

        Dim placement As Point2d = _
            ThisApplication.TransientGeometry.CreatePoint2d( _
                placementX, _
                (topPoint.Y + bottomPoint.Y) / 2.0)
'''
if old_place not in text:
    raise SystemExit("overall fixed-right placement block not found")
text = text.replace(old_place, new_place, 1)

old_log = '''        Logger.Info( _
            "OVERALL_VERTICAL_FLANGE " & _
            topNode.Code & " -> " & bottomNode.Code)
'''
new_log = '''        Logger.Info( _
            "OVERALL_VERTICAL_FLANGE " & _
            topNode.Code & " -> " & bottomNode.Code & _
            " | side=" & placementSide & _
            " | placementX_cm=" & Num(placementX))
'''
if old_log not in text:
    raise SystemExit("overall log block not found")
text = text.replace(old_log, new_log, 1)

text = text.replace(
    'Logger.Info("V0.12: collision-aware left/right placement for the global vertical chain; true reference members preserved; attachments deferred.")',
    'Logger.Info("V0.12.1: vertical chain and vertical overall share the same collision-selected side; true reference members preserved; attachments deferred.")',
    1,
)
text = text.replace('"DimensionGenerator V0.12")', '"DimensionGenerator V0.12.1")', 1)
text = text.replace('"DimensionGenerator V0.12 failed:"', '"DimensionGenerator V0.12.1 failed:"', 1)

path.write_text(text, encoding="utf-8")
print("Patched DimensionGenerator.vb to V0.12.1")
