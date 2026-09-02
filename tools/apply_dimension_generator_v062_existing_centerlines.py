#!/usr/bin/env python3
from pathlib import Path
import re

p = Path('DimensionGenerator.vb')
s = p.read_text(encoding='utf-8')

# Version text only; keep all stable projected-curve and chain logic intact.
s = s.replace('V0.6.1', 'V0.6.2')
s = re.sub(r"DIMENSION GENERATOR V0\.[^\n']*", "DIMENSION GENERATOR V0.6.2 - EXISTING CENTERLINES + CHAINS", s)

start = s.index('Function ResolveFittingCenterIntentV04(')
end = s.index('\nEnd Function', start) + len('\nEnd Function')

new_block = r'''Function ResolveFittingCenterIntentV04( _
    sheet As Sheet, _
    view As DrawingView, _
    node As NodeRecord, _
    target As Point2d) As GeometryIntent

    ' ===============================================================
    ' V0.6.2 - REUSE EXISTING CENTERLINES ONLY
    '
    ' CenterlineGenerator creates the PIPE / FLANGE native bisectors in a
    ' separate, already-tested rule.  DimensionGenerator NEVER calls
    ' Centerlines.AddBisector here.
    '
    ' For a TEE / ELBOW semantic center:
    '   1. Read only centerlines tagged AutoSpoolCenterline.
    '   2. Find two non-parallel axes whose mathematical intersection is
    '      at the topology-projected semantic center.
    '   3. Ask Inventor for a GeometryIntent at the intersection of those
    '      two EXISTING centerlines.
    ' ===============================================================

    If node Is Nothing OrElse target Is Nothing Then Return Nothing

    Dim generated As List(Of Centerline) = _
        GetGeneratedCenterlinesV062(sheet)

    If generated.Count < 2 Then
        Logger.Info( _
            "CENTER_INTENT SKIP " & node.Code & "/" & node.ComponentType & _
            " | generated centerlines=" & generated.Count.ToString())
        Return Nothing
    End If

    Dim bestA As Centerline = Nothing
    Dim bestB As Centerline = Nothing
    Dim bestError As Double = Double.MaxValue
    Dim bestIX As Double = 0
    Dim bestIY As Double = 0

    For i As Integer = 0 To generated.Count - 2
        For j As Integer = i + 1 To generated.Count - 1

            Dim a As Centerline = generated.Item(i)
            Dim b As Centerline = generated.Item(j)

            If a Is Nothing OrElse b Is Nothing Then Continue For

            Dim ix As Double = 0
            Dim iy As Double = 0

            If Not TryCenterlineIntersectionV062(a, b, ix, iy) Then
                Continue For
            End If

            Dim dx As Double = ix - target.X
            Dim dy As Double = iy - target.Y
            Dim errorDistance As Double = Math.Sqrt(dx * dx + dy * dy)

            ' Sheet database units are cm.  0.20 cm = 2 mm on the sheet.
            ' The semantic point came from ModelToSheetSpace, so a valid pair
            ' should normally be much closer than this.
            If errorDistance > 0.20 Then Continue For

            If errorDistance < bestError Then
                bestError = errorDistance
                bestA = a
                bestB = b
                bestIX = ix
                bestIY = iy
            End If

        Next
    Next

    If bestA Is Nothing OrElse bestB Is Nothing Then
        Logger.Info( _
            "CENTER_INTENT SKIP " & node.Code & "/" & node.ComponentType & _
            " | no existing centerline intersection near semantic point")
        Return Nothing
    End If

    Logger.Info( _
        "CENTER_INTENT PAIR " & node.Code & "/" & node.ComponentType & _
        " | A=" & GetCenterlineOccurrenceTagV062(bestA) & _
        " | B=" & GetCenterlineOccurrenceTagV062(bestB) & _
        " | intersection=" & Num(bestIX) & "," & Num(bestIY) & _
        " | target=" & Num(target.X) & "," & Num(target.Y) & _
        " | error=" & Num(bestError))

    Try
        ' No centerline is created or edited here.  The optional Intent
        ' argument is another geometry, which Autodesk documents as the way
        ' to create an intersection GeometryIntent.
        Dim centreIntent As GeometryIntent = _
            sheet.CreateGeometryIntent(bestA, bestB)

        If centreIntent Is Nothing Then Return Nothing

        ' Validate the returned point when Inventor exposes one.
        Try
            Dim resolved As Point2d = centreIntent.PointOnSheet
            If resolved IsNot Nothing Then
                Dim rdx As Double = resolved.X - target.X
                Dim rdy As Double = resolved.Y - target.Y
                Dim resolvedError As Double = Math.Sqrt(rdx * rdx + rdy * rdy)

                If resolvedError > 0.25 Then
                    Logger.Error( _
                        "CENTER_INTENT rejected " & node.Code & _
                        " | Inventor point error=" & Num(resolvedError))
                    Return Nothing
                End If
            End If
        Catch
        End Try

        Logger.Info( _
            "CENTER_INTENT resolved " & _
            node.Code & "/" & node.ComponentType & _
            " from existing generated centerlines")

        Return centreIntent

    Catch ex As Exception
        Logger.Error( _
            "Existing centerline intersection intent failed for " & _
            node.Code & "/" & node.ComponentType & _
            " : " & ex.Message)
        Return Nothing
    End Try
End Function


Function GetGeneratedCenterlinesV062( _
    sheet As Sheet) As List(Of Centerline)

    Dim result As New List(Of Centerline)

    Try
        For i As Integer = 1 To sheet.Centerlines.Count
            Dim cl As Centerline = sheet.Centerlines.Item(i)

            If cl Is Nothing Then Continue For

            Try
                If Not cl.Attached Then Continue For
            Catch
            End Try

            Try
                Dim tags As AttributeSet = _
                    cl.AttributeSets.Item("AutoSpoolCenterline")

                If tags IsNot Nothing Then
                    result.Add(cl)
                End If
            Catch
            End Try
        Next
    Catch ex As Exception
        Logger.Error("Reading AutoSpoolCenterline set failed: " & ex.Message)
    End Try

    Return result
End Function


Function GetCenterlineOccurrenceTagV062( _
    cl As Centerline) As String

    If cl Is Nothing Then Return "?"

    Try
        Dim tags As AttributeSet = _
            cl.AttributeSets.Item("AutoSpoolCenterline")

        Dim occurrenceName As String = _
            tags.Item("Occurrence").Value.ToString()

        Dim componentType As String = _
            tags.Item("ComponentType").Value.ToString()

        Return componentType & ":" & occurrenceName
    Catch
        Return "UNTAGGED"
    End Try
End Function


Function TryCenterlineIntersectionV062( _
    a As Centerline, _
    b As Centerline, _
    ByRef ix As Double, _
    ByRef iy As Double) As Boolean

    If a Is Nothing OrElse b Is Nothing Then Return False

    Try
        If a.StartPoint Is Nothing OrElse a.EndPoint Is Nothing OrElse _
           b.StartPoint Is Nothing OrElse b.EndPoint Is Nothing Then
            Return False
        End If

        Dim px As Double = a.StartPoint.X
        Dim py As Double = a.StartPoint.Y
        Dim rx As Double = a.EndPoint.X - a.StartPoint.X
        Dim ry As Double = a.EndPoint.Y - a.StartPoint.Y

        Dim qx As Double = b.StartPoint.X
        Dim qy As Double = b.StartPoint.Y
        Dim sx As Double = b.EndPoint.X - b.StartPoint.X
        Dim sy As Double = b.EndPoint.Y - b.StartPoint.Y

        Dim rLength As Double = Math.Sqrt(rx * rx + ry * ry)
        Dim sLength As Double = Math.Sqrt(sx * sx + sy * sy)

        If rLength < 0.000001 OrElse sLength < 0.000001 Then Return False

        Dim crossRS As Double = rx * sy - ry * sx
        Dim normalizedCross As Double = _
            Math.Abs(crossRS) / (rLength * sLength)

        ' Reject nearly parallel axes.  This is ~11.5 degrees minimum angle.
        If normalizedCross < 0.20 Then Return False

        Dim qpx As Double = qx - px
        Dim qpy As Double = qy - py

        Dim t As Double = _
            (qpx * sy - qpy * sx) / crossRS

        ix = px + t * rx
        iy = py + t * ry

        Return True

    Catch ex As Exception
        Logger.Error("Centerline intersection math failed: " & ex.Message)
        Return False
    End Try
End Function'''

s = s[:start] + new_block + s[end:]

# Make the run summary explicit about the safe two-stage workflow.
s = s.replace(
    'stable mode: chains enabled; centerline-dependent and attachment dimensions deferred.',
    'two-stage mode: chains enabled; fitting centers reuse existing AutoSpoolCenterline axes; attachments deferred.')

p.write_text(s, encoding='utf-8', newline='\n')
print('Patched DimensionGenerator.vb to V0.6.2 existing-centerline intersection intents')
