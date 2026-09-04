; GTP_Elbow_Component_Integration.lsp
; -----------------------------------------------------------------------------
; STEP 2 - Wrap the existing GTP elbow engine as a component.
;
; LOAD ORDER
;   1. GTP_DH_TOOLKIT.lsp
;   2. GTP_Component_Architecture.lsp
;   3. GTP_Elbow_Component_Integration.lsp
;
; DESIGN INTENT
;   This file changes the INTERNAL route representation only.
;   Existing elbow geometry is still produced by:
;       gtp:make-elbow-spec
;       gtp:model-elbow
;
;   No new elbow geometry is introduced here.
;   No valve/component geometry is introduced here.
;   The existing GTPPIPE prompts and catalogue behaviour remain unchanged.
;
;   The integration works by redefining gtp:model-corner-route after the
;   original toolkit has loaded. GTPPIPE calls the same function name, so the
;   command does not need to be changed yet.
; -----------------------------------------------------------------------------

(vl-load-com)

; -----------------------------------------------------------------------------
; ELBOW COMPONENT FACTORY
; -----------------------------------------------------------------------------
(defun gtp:make-elbow-component
  (id system dn series prev vertex next carrier casing style / spec)
  (setq spec
    (gtp:make-elbow-spec
      prev vertex next dn carrier casing style
    )
  )
  (if spec
    (gtp:component-make
      id
      "ELBOW"
      system
      dn
      series
      vertex
      (gtp:spec 'd1 spec)
      (gtp:spec 'normal spec)
      nil
      (list
        (cons 'legacy-spec spec)
        (cons 'style style)
        (cons 'carrier carrier)
        (cons 'casing casing)
      )
      nil
    )
  )
)

(defun gtp:elbow-component-spec (component / catalogue)
  (setq catalogue (gtp:component-get component 'catalogue))
  (gtp:catalogue-get catalogue 'legacy-spec)
)

(defun gtp:elbow-component-start (component)
  (gtp:spec 'start (gtp:elbow-component-spec component))
)

(defun gtp:elbow-component-end (component)
  (gtp:spec 'end (gtp:elbow-component-spec component))
)

(defun gtp:model-elbow-component (component carrier casing mode)
  ; Deliberately delegate to the existing elbow modeller so geometry stays
  ; identical to the pre-component implementation.
  (gtp:model-elbow
    (gtp:elbow-component-spec component)
    carrier
    casing
    mode
  )
)

; -----------------------------------------------------------------------------
; COMPONENT-AWARE CORNER ROUTE MODELLER
; -----------------------------------------------------------------------------
; Signature intentionally matches the existing gtp:model-corner-route so the
; existing c:GTPPIPE command can call this function without modification.
;
; `series` is not available in the legacy function signature, so the component
; stores NIL for series for now. Step 3/4 can promote series into the route
; modeller signature once valve/component catalogue selection is introduced.
; -----------------------------------------------------------------------------
(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e
  spoolCount elbowCount clippedCount system)

  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))

  ; Build component records while retaining the exact legacy elbow spec inside
  ; each component. This gives the new architecture the same geometric source
  ; of truth used by the existing modeller.
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

  ; Model straight intervals between the geometric footprint ends of adjacent
  ; elbow components. This is intentionally the same interval logic used by
  ; the original modeller.
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
           (gtp:model-segment s e carrier casing mode)
        )
      )
    )

    (setq i (1+ i))
  )

  ; Delegate actual elbow solids to the unchanged modeller.
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

(princ
  "\nGTP Step 2 loaded: existing elbows are now wrapped as components; geometry engine unchanged."
)
(princ)
