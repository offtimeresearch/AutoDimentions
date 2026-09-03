from pathlib import Path

src = Path('GTP_DH_TOOLKIT_V1_6.lsp')
out = Path('GTP_DH_TOOLKIT_V1_7.lsp')
s = src.read_text(encoding='utf-8')

s = s.replace('GTP_DH_TOOLKIT_V1_6.LSP', 'GTP_DH_TOOLKIT_V1_7.LSP')
s = s.replace('V1.6 notes:', 'V1.7 notes:', 1)
s = s.replace('GTP DH Toolkit V1.6 loaded.', 'GTP DH Toolkit V1.7 loaded.')

notes = (
    '; - Fixes WeldPoints mode aborting before geometry creation by isolating bend-recognition\n'
    ';   errors from the modelling pass. A bad candidate can no longer stop the whole route.\n'
    '; - Weld-to-weld bend detection is now fail-safe: rejected candidates remain straight,\n'
    ';   detected bends are modelled individually, and a failed elbow falls back to visible\n'
    ';   straight weld-to-weld geometry instead of leaving the route empty.\n'
    '; - Adds command-line diagnostics so a rejected/failed weld bend reports its segment.\n'
)
s = s.replace('; V1.7 notes:\n', '; V1.7 notes:\n' + notes, 1)

marker = '(defun gtp:model-weld-route '
idx = s.index(marker)
helper = r'''(defun gtp:safe-weld-elbow-spec (prev fs fe next dn carrier casing style segno / r)
  (setq r
    (vl-catch-all-apply
      'gtp:make-weld-elbow-spec
      (list prev fs fe next dn carrier casing style)
    )
  )
  (if (vl-catch-all-error-p r)
    (progn
      (princ
        (strcat
          "\nWeldPoints: segment " (itoa segno)
          " bend check failed; keeping it as straight geometry. Reason: "
          (vl-catch-all-error-message r)
        )
      )
      nil
    )
    r
  )
)

(defun gtp:safe-model-weld-elbow (spec p1 p2 dn series carrier casing mode segno / r)
  (setq r
    (vl-catch-all-apply
      'gtp:model-elbow
      (list spec dn series carrier casing mode)
    )
  )
  (if (vl-catch-all-error-p r)
    (progn
      (princ
        (strcat
          "\nWeldPoints: 3D elbow on segment " (itoa segno)
          " could not be created; using visible straight fallback. Reason: "
          (vl-catch-all-error-message r)
        )
      )
      (gtp:model-segment p1 p2 dn series carrier casing mode)
      nil
    )
    T
  )
)

'''
s = s[:idx] + helper + s[idx:]

start = s.index('(defun gtp:model-weld-route ')
end = s.index('(defun c:GTPPIPE ', start)
new = r'''(defun gtp:model-weld-route (pts dn series carrier casing mode elbowStyle / npts segKinds specs i spec spoolCount elbowCount p1 p2 deg tag fallbackCount)
  (setq npts (length pts)
        segKinds '()
        specs '()
        i 0
        spoolCount 0
        elbowCount 0
        fallbackCount 0)

  (repeat (1- npts)
    (setq segKinds (append segKinds (list "STRAIGHT"))
          specs    (append specs    (list nil))))

  (setq i 1)
  (while (< i (- npts 2))
    (setq spec
      (gtp:safe-weld-elbow-spec
        (nth (1- i) pts)
        (nth i pts)
        (nth (1+ i) pts)
        (nth (+ i 2) pts)
        dn carrier casing elbowStyle
        (1+ i)
      )
    )
    (if spec
      (progn
        (setq segKinds (gtp:set-nth segKinds i "ELBOW")
              specs    (gtp:set-nth specs i spec)
              deg      (gtp:spec 'measuredDeg spec)
              tag      (gtp:spec 'tag spec))
        (princ
          (strcat
            "\nDetected weld-to-weld " tag " deg bend at polyline segment "
            (itoa (1+ i)) " (axis turn " (rtos deg 2 1) " deg)."
          )
        )
        (setq i (+ i 2))
      )
      (setq i (1+ i))
    )
  )

  (setq i 0)
  (while (< i (1- npts))
    (setq p1 (nth i pts)
          p2 (nth (1+ i) pts))
    (if (= (nth i segKinds) "ELBOW")
      (if (gtp:safe-model-weld-elbow
            (nth i specs) p1 p2 dn series carrier casing mode (1+ i))
        (setq elbowCount (1+ elbowCount))
        (progn
          (setq spoolCount (1+ spoolCount)
                fallbackCount (1+ fallbackCount))
        )
      )
      (if (> (distance p1 p2) 1e-8)
        (setq spoolCount
          (+ spoolCount
             (gtp:model-segment p1 p2 dn series carrier casing mode)))
      )
    )
    (setq i (1+ i))
  )

  (if (> fallbackCount 0)
    (princ
      (strcat
        "\nWeldPoints: " (itoa fallbackCount)
        " detected fitting span(s) used straight fallback geometry because AutoCAD rejected the 3D elbow solid."
      )
    )
  )
  (list spoolCount elbowCount 0 0)
)

'''
s = s[:start] + new + s[end:]
out.write_text(s, encoding='utf-8')
print(out)
