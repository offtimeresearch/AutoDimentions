; GTP_Valve_Aware_Pipe_Integration.lsp
; -----------------------------------------------------------------------------
; STEP 4 - Make GTPPIPE valve-aware.
;
; LOAD AFTER:
;   1. GTP_DH_TOOLKIT.lsp
;   2. GTP_Component_Architecture.lsp
;   3. GTP_Elbow_Component_Integration.lsp
;   4. GTP_Valve_Component.lsp
;
; PURPOSE
;   Replace the straight-pipe interval stage with a valve-aware planner.
;   Registered longitudinal valve components occupy real route length, so
;   GTPPIPE no longer generates a continuous pipe through the valve footprint.
;
; IMPORTANT
;   This is an integration bridge. It does not rewrite the existing solid
;   generators or valve modeller. Existing elbows continue to use the legacy
;   elbow engine through the Step 2 wrapper.
;
;   GTPVALVE registers components in the current AutoCAD session. Therefore
;   valves must be created before running GTPPIPE for this session.
;
;   Only VALVE components that overlap a straight interval are removed from
;   that interval. Elbow footprint handling remains exactly as Step 2.
; -----------------------------------------------------------------------------

(vl-load-com)

(defun gtp:valve-aware-filter-components (components / out component type)
  (setq out '())
  (foreach component components
    (setq type (gtp:component-get component 'type))
    (if (= type "VALVE")
      (setq out (append out (list component)))
    )
  )
  out
)

(defun gtp:model-valve-component (component / catalogue family)
  (setq catalogue (gtp:component-get component 'catalogue))
  (setq family (gtp:catalogue-get catalogue 'family))
  (cond
    ((= family "SINGLE_SHUTOFF_VALVE")
      (gtp:model-single-shutoff-valve component)
    )
    (T
      (princ
        (strcat
          "\nGTP warning: no modeller registered for valve family "
          (if family family "<nil>") "."
        )
      )
      nil
    )
  )
)

(defun gtp:distance-point-on-line (origin direction dist)
  (gtp:vadd origin (gtp:vscale direction dist))
)

(defun gtp:model-valve-aware-straight
  (start end dn carrier casing mode components / direction total ranges pieces piece a b p1 p2 count)
  (setq direction (gtp:vunit (gtp:vsub end start)))
  (setq total (distance start end))
  (setq count 0)
  (if (<= total 1e-8)
    0
    (progn
      (setq ranges (gtp:plan-pipe-intervals start end components))
      (setq pieces (gtp:ranges-to-points start direction ranges))
      (foreach piece pieces
        (setq p1 (car piece))
        (setq p2 (cadr piece))
        (if (> (distance p1 p2) 1e-8)
          (setq count
            (+ count
               (gtp:model-segment p1 p2 carrier casing mode)
            )
          )
        )
      )
      count
    )
  )
)

(defun gtp:component-overlaps-route-range-p
  (start end component / direction total cut)
  (setq direction (gtp:vunit (gtp:vsub end start)))
  (setq total (distance start end))
  (setq cut
    (gtp:component-overlap-range
      start direction 0.0 total component
    )
  )
  (and cut (> (cadr cut) (car cut)))
)

(defun gtp:validate-valve-clearances
  (pts valveComponents / component pos start end warnings)
  (setq warnings 0)
  (foreach component valveComponents
    (setq pos (gtp:component-get component 'position))
    (setq start (car pts))
    (setq end (gtp:last-item pts))
    ; This first integration only needs a route-level sanity check. Detailed
    ; per-segment assignment is performed during modelling.
    (if (or (< (distance pos start) 1e-8)
            (< (distance pos end) 1e-8))
      (progn
        (princ
          (strcat
            "\nGTP warning: valve "
            (gtp:component-get component 'id')
            " is positioned at a route endpoint; verify the fitting arrangement."
          )
        )
        (setq warnings (1+ warnings))
      )
    )
  )
  warnings
)

; -----------------------------------------------------------------------------
; COMPONENT-AWARE CORNER ROUTE MODELLER
; -----------------------------------------------------------------------------
;
; This keeps the Step 2 elbow component representation, then augments each
; straight route interval with registered VALVE components.
;
(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e
  spoolCount elbowCount clippedCount valveCount valveComponents system)

  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))
  (setq valveComponents
    (gtp:valve-aware-filter-components
      (if *gtp-valve-components* *gtp-valve-components* '())
    )
  )
  (setq valveCount (length valveComponents))

  ; Build the same elbow components established by Step 2.
  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component
        (gtp:make-elbow-component
          (strcat "ELBOW-" (itoa i))
          system
          dn
          nil
          (nth (1- i) pts)
          (nth i pts)
          (nth (1+ i) pts)
          carrier
          casing
          style
        )
      )
    )
    (if
      (and component
           (gtp:spec 'clipped (gtp:elbow-component-spec component)))
      (setq clippedCount (1+ clippedCount))
    )
    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )

  ; Model pipe between elbow footprints, while removing any registered valve
  ; footprint that lies on the same straight route interval.
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts))
    (setq p2 (nth (1+ i) pts))

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
           (gtp:model-valve-aware-straight
             s e dn carrier casing mode valveComponents
           )
        )
      )
    )
    (setq i (1+ i))
  )

  ; Existing elbow geometry remains untouched.
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

  ; Valve geometry is already present if GTPVALVE was run before GTPPIPE.
  ; Do not regenerate it here; just report how many components participated
  ; in pipe splitting. This prevents duplicate valve solids.
  (if (> valveCount 0)
    (princ
      (strcat
        "\nValve-aware routing: "
        (itoa valveCount)
        " registered valve component(s) considered for pipe splitting."
      )
    )
  )

  (list spoolCount elbowCount clippedCount)
)

(princ "\nGTP Step 4 loaded: GTPPIPE is now valve-aware for registered longitudinal valves.")
(princ)
