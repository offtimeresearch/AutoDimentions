#!/usr/bin/env python3
from pathlib import Path

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

s = s.replace('DimensionGenerator V0.6.2', 'DimensionGenerator V0.6.3')
s = s.replace('DIMENSION GENERATOR V0.6.2 - EXISTING CENTERLINES + CHAINS',
              'DIMENSION GENERATOR V0.6.3 - SHEET CENTERLINES + CHAINS')

start = s.index('Function GetGeneratedCenterlinesV062( _')
end = s.index('\nEnd Function', start) + len('\nEnd Function')

new_func = r'''Function GetGeneratedCenterlinesV062( _
    sheet As Sheet) As List(Of Centerline)

    ' V0.6.3
    ' Do NOT require AttributeSets or Centerline.Attached here.
    ' The previous filters rejected centerlines that are visibly present in
    ' the drawing.  Topology already supplies the exact semantic target point,
    ' so we can safely inspect every real centerline on the active sheet and
    ' later accept only a non-parallel pair whose mathematical intersection is
    ' very close to that target.

    Dim result As New List(Of Centerline)
    Dim taggedCount As Integer = 0

    Try
        Logger.Info( _
            "CENTER_SCAN sheet.Centerlines.Count=" & _
            sheet.Centerlines.Count.ToString())

        For i As Integer = 1 To sheet.Centerlines.Count

            Dim cl As Centerline = sheet.Centerlines.Item(i)
            If cl Is Nothing Then Continue For

            Try
                If cl.StartPoint Is Nothing OrElse cl.EndPoint Is Nothing Then
                    Continue For
                End If

                Dim dx As Double = cl.EndPoint.X - cl.StartPoint.X
                Dim dy As Double = cl.EndPoint.Y - cl.StartPoint.Y
                Dim length As Double = Math.Sqrt(dx * dx + dy * dy)

                If length < 0.001 Then Continue For
            Catch
                Continue For
            End Try

            Try
                Dim tags As AttributeSet = _
                    cl.AttributeSets.Item("AutoSpoolCenterline")
                If tags IsNot Nothing Then taggedCount += 1
            Catch
                ' Tag is diagnostic only in V0.6.3.
            End Try

            result.Add(cl)

        Next

        Logger.Info( _
            "CENTER_SCAN usable=" & result.Count.ToString() & _
            " | tagged AutoSpoolCenterline=" & taggedCount.ToString())

    Catch ex As Exception
        Logger.Error("Reading sheet centerlines failed: " & ex.Message)
    End Try

    Return result
End Function'''

s = s[:start] + new_func + s[end:]

s = s.replace('V0.5 staged mode: attachment dimensions remain deferred until topology-guided fitting centerlines are verified.',
              'V0.6.3 staged mode: attachment dimensions remain deferred while existing centerline fitting-center intents are verified.')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.6.3 direct sheet centerline scan')
