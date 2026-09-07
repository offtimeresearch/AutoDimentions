; GTP_COMBINED_FINAL_BRIDGE.LSP
; =============================================================================
; Final route/component integration layer for GTP_DH_TOOLKIT_COMBINED.lsp.
;
; This block is appended AFTER the legacy geometry engine and Steps 1-6.
; It deliberately does not regenerate placed component solids. Instead it:
;   - keeps the proven elbow modeller as the bend source of truth;
;   - reads the persistent component registry;
;   - removes longitudinal component footprints from straight pipe intervals;
;   - models only the remaining straight pipe pieces;
;   - provides combined diagnostics/help commands.
; =============================================================================

(vl-load-com)

(setq *gtp-combined-version* "1.0")
(setq *gtp-combined-longitudinal-types*
  '("VALVE" "TEE" "REDUCER" "BRANCH" "END_CAP")
)

(defun gtp:combined-catalogue (component)
  (if component (gtp:component-get component 'catalogue) nil)
)

(defun gtp:combined-options (component)
  (if component (gtp:component-get component 'options) nil)
)

(defun gtp:combined-catalogue-get (component key / cat)
  (setq cat (gtp:combined-catalogue component))
  (if cat (gtp:catalogue-get cat key) nil)
)

(defun gtp:combined-component-length-du (component / type len mmLen opt footprint)
  ; Prefer explicit catalogue millimetres because Step 5/6 component records
  ; store several lengths in catalogue-mm while the geometry engine works in
  ; drawing units. This also keeps old persisted records usable after reload.
  (setq type (gtp:component-get component 'type))
  (setq mmLen (gtp:combined-catalogue-get component 'length-mm))

  (cond
    ((and mmLen (> mmLen 0.0))
      (gtp:mm mmLen)
    )

    ; Step 3 manual valve components store a converted component length, and
    ; also preserve length-mm in their catalogue. The branch above therefore
    ; normally wins. Keep this fallback for older valve records.
    ((= type "VALVE")
      (setq len (gtp:component-get component 'length))
      (if (and len (> len 0.0)) len 0.0)
    )

    ; Step 6 fitting commands store their component length in catalogue mm.
    ((member type '("TEE" "REDUCER" "BRANCH" "END_CAP"))
      (setq len (gtp:component-get component 'length))
      (if (and len (> len 0.0)) (gtp:mm len) 0.0)
    )

    (T
      (setq opt (gtp:combined-options component))
      (setq footprint (if opt (gtp:component-get opt 'footprint) nil))
      (cond
        ((and footprint (> footprint 0.0)) (* 2.0 footprint))
        (T
          (setq len (gtp:component-get component 'length))
          (if (and len (> len 0.0)) len 0.0)
        )
      )
    )
  )
)

(defun gtp:combined-segment-projection (start direction point)
  (gtp:dot (gtp:vsub point start) direction)
)

(defun gtp:combined-point-line-distance (start direction point / tproj foot)
  (setq tproj (gtp:combined-segment-projection start direction point))
  (setq foot (gtp:vadd start (gtp:vscale direction tproj)))
  (distance point foot)
)

(defun gtp:combined-component-range
  (start end component / type pos cdir direction total proj lateral align len lo hi)

  (setq type (gtp:component-get component 'type))
  (setq pos (gtp:component-get component 'position))

  (if (or (null pos)
          (not (member type *gtp-combined-longitudinal-types*)))
    nil
    (progn
      (setq total (distance start end))
      (if (<= total 1e-8)
        nil
        (progn
          (setq direction (gtp:vunit (gtp:vsub end start)))
          (setq proj (gtp:combined-segment-projection start direction pos))
          (setq lateral (gtp:combined-point-line-distance start direction pos))
          (setq cdir (gtp:component-get component 'direction))
          (setq align
            (if cdir
              (abs (gtp:dot direction (gtp:vunit cdir)))
              1.0
            )
          )
          (setq len (gtp:combined-component-length-du component))

          ; Only components genuinely on this straight interval participate.
          ; A 5 mm project-space tolerance matches the placement workflow.
          (if (or (> lateral (gtp:mm 5.0))
                  (< align 0.95)
                  (<= len 1e-8)
                  (< proj (- len))
                  (> proj (+ total len)))
            nil
            (progn
              (if (= type "END_CAP")
                ; End caps are endpoint-based, not centre-based. Reserve the
                ; material immediately behind the selected endpoint.
                (if (<= proj (/ total 2.0))
                  (setq lo proj hi (+ proj len))
                  (setq lo (- proj len) hi proj)
                )
                (setq lo (- proj (/ len 2.0)) hi (+ proj (/ len 2.0)))
              )
              (setq lo (max 0.0 lo))
              (setq hi (min total hi))
              (if (> hi lo) (list lo hi component) nil)
            )
          )
        )
      )
    )
  )
)

(defun gtp:combined-subtract-range (ranges cut / out a b r c d)
  (setq out '() a (car cut) b (cadr cut))
  (foreach r ranges
    (setq c (car r) d (cadr r))
    (if (or (>= c b) (<= d a))
      (setq out (append out (list r)))
      (progn
        (if (> a c) (setq out (append out (list (list c (min a d))))))
        (if (< b d) (setq out (append out (list (list (max b c) d)))))
      )
    )
  )
  out
)

(defun gtp:combined-segment-components (start end / out component cut)
  (setq out '())
  (if *gtp-component-registry*
    (foreach component *gtp-component-registry*
      (setq cut (gtp:combined-component-range start end component))
      (if cut (setq out (append out (list cut))))
    )
  )
  (vl-sort out '(lambda (a b) (< (car a) (car b))))
)

(defun gtp:combined-plan-straight-ranges (start end / total ranges cuts cut)
  (setq total (distance start end))
  (setq ranges (if (> total 1e-8) (list (list 0.0 total)) '()))
  (setq cuts (gtp:combined-segment-components start end))
  (foreach cut cuts
    (setq ranges (gtp:combined-subtract-range ranges cut))
  )
  (list ranges cuts)
)

(defun gtp:combined-distance-point (start direction dist)
  (gtp:vadd start (gtp:vscale direction dist))
)

(defun gtp:model-combined-straight
  (start end dn carrier casing mode / direction plan ranges cuts range p1 p2 count)

  (setq count 0)
  (if (> (distance start end) 1e-8)
    (progn
      (setq direction (gtp:vunit (gtp:vsub end start)))
      (setq plan (gtp:combined-plan-straight-ranges start end))
      (setq ranges (car plan) cuts (cadr plan))

      (foreach range ranges
        (setq p1 (gtp:combined-distance-point start direction (car range)))
        (setq p2 (gtp:combined-distance-point start direction (cadr range)))
        (if (> (distance p1 p2) 1e-8)
          (setq count (+ count (gtp:model-segment p1 p2 carrier casing mode)))
        )
      )

      (if (> (length cuts) 0)
        (princ
          (strcat
            "\nComponent-aware split: "
            (itoa (length cuts))
            " installed component footprint(s) excluded from this straight run."
          )
        )
      )
    )
  )
  count
)

(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e
   spoolCount elbowCount clippedCount system)

  ; Final combined route modeller. Elbow geometry stays delegated to the
  ; proven Step 2 wrapper; straight intervals use the persistent registry.
  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))

  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component
        (gtp:make-elbow-component
          (strcat "ELBOW-" (itoa i))
          system dn nil
          (nth (1- i) pts)
          (nth i pts)
          (nth (1+ i) pts)
          carrier casing style
        )
      )
    )
    (if (and component
             (gtp:spec 'clipped (gtp:elbow-component-spec component)))
      (setq clippedCount (1+ clippedCount))
    )
    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )

  ; Model straight intervals between elbow footprint ends, excluding every
  ; supported persistent component footprint on the same straight route.
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts))
    (setq s
      (if (nth i elbows)
        (gtp:elbow-component-end (nth i elbows))
        p1
      )
    )
    (setq e
      (if (nth (1+ i) elbows)
        (gtp:elbow-component-start (nth (1+ i) elbows))
        p2
      )
    )
    (if (> (distance s e) 1e-8)
      (setq spoolCount
        (+ spoolCount
           (gtp:model-combined-straight s e dn carrier casing mode)
        )
      )
    )
    (setq i (1+ i))
  )

  ; Keep the existing elbow solid modeller unchanged.
  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows)
      (progn
        (setq component (nth i elbows))
        (gtp:model-elbow-component component carrier casing mode)
        (setq elbowCount (1+ elbowCount))
      )
    )
    (setq i (1+ i))
  )

  (list spoolCount elbowCount clippedCount)
)

(defun gtp:combined-command-checks ()
  (list
    (list "GTPPIPE" 'c:GTPPIPE)
    (list "GTPMITER" 'c:GTPMITER)
    (list "GTPMITTER" 'c:GTPMITTER)
    (list "GTPUNITS" 'c:GTPUNITS)
    (list "GTPLAYER" 'c:GTPLAYER)
    (list "GTPVALVE" 'c:GTPVALVE)
    (list "GTPVALVECATALOG" 'c:GTPVALVECATALOG)
    (list "GTPVALVESUMMARY" 'c:GTPVALVESUMMARY)
    (list "GTPTEE" 'c:GTPTEE)
    (list "GTPREDUCER" 'c:GTPREDUCER)
    (list "GTPBRANCH" 'c:GTPBRANCH)
    (list "GTPENDCAP" 'c:GTPENDCAP)
    (list "GTPCOMPONENTS" 'c:GTPCOMPONENTS)
    (list "GTPCOMPONENTRELOAD" 'c:GTPCOMPONENTRELOAD)
    (list "GTPCOMPONENTSAVE" 'c:GTPCOMPONENTSAVE)
  )
)

(defun c:GTPCOMBINEDTEST (/ checks ok item)
  (setq checks (gtp:combined-command-checks) ok T)
  (princ "\n========================================")
  (princ "\n GTP COMBINED TOOLKIT TEST")
  (princ "\n========================================")
  (foreach item checks
    (if (fboundp (cadr item))
      (princ (strcat "\n[OK] " (car item)))
      (progn
        (setq ok nil)
        (princ (strcat "\n[FAIL] " (car item)))
      )
    )
  )
  (if (fboundp 'gtp:model-corner-route)
    (princ "\n[OK] Final multi-component route modeller active.")
    (progn (setq ok nil) (princ "\n[FAIL] Final route modeller missing."))
  )
  (princ
    (strcat
      "\nPersistent components in memory: "
      (itoa (if *gtp-component-registry* (length *gtp-component-registry*) 0))
    )
  )
  (if ok
    (princ "\nGTPCOMBINEDTEST PASS.")
    (princ "\nGTPCOMBINEDTEST FAIL - see [FAIL] entries above.")
  )
  (princ)
)

(defun c:GTPHELP ()
  (princ "\nGTP combined AutoCAD 3D district-heating toolkit:")
  (princ "\n  GTPPIPE             Generate carrier/casing pipe + 3D elbows from route")
  (princ "\n  GTPMITER            Join two route ends at their 3D axis intersection")
  (princ "\n  GTPMITTER           Alias for GTPMITER")
  (princ "\n  GTPUNITS            Set catalogue-mm to drawing-unit conversion")
  (princ "\n  GTPLAYER            Create/check GTP layers")
  (princ "\n  GTPVALVE            Place catalogue-backed valve component")
  (princ "\n  GTPVALVECATALOG     Inspect supported valve catalogue")
  (princ "\n  GTPVALVESUMMARY     List registered valves")
  (princ "\n  GTPTEE              Place tee component")
  (princ "\n  GTPREDUCER          Place catalogue-backed reducer component")
  (princ "\n  GTPBRANCH           Place branch component")
  (princ "\n  GTPENDCAP           Place end-cap component")
  (princ "\n  GTPCOMPONENTS       List persistent components")
  (princ "\n  GTPCOMPONENTRELOAD  Reload components from DWG Named Object Dictionary")
  (princ "\n  GTPCOMPONENTSAVE    Persist current component registry to DWG")
  (princ "\n  GTPCOMBINEDTEST     Verify combined command/function availability")
  (princ)
)

(princ
  (strcat
    "\nGTP_DH_TOOLKIT_COMBINED V" *gtp-combined-version*
    " loaded. Run GTPHELP for commands or GTPCOMBINEDTEST for diagnostics."
  )
)
(princ)
