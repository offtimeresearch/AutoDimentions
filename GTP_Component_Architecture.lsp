; GTP_COMPONENT_ARCHITECTURE.LSP
; -----------------------------------------------------------------------------
; Component architecture foundation for GTPPIPE.
;
; PURPOSE
;   This file introduces the data model needed to move GTPPIPE from a
;   route-only modeller toward a component-aware pipe system.
;
; IMPORTANT
;   This file intentionally has NO effect on the existing GTPPIPE command.
;   It does not replace the current route modeller, elbow modeller, catalogue,
;   or solid-generation functions.  Load it alongside GTP_DH_TOOLKIT.lsp while
;   the architecture is being introduced incrementally.
;
; DESIGN RULES
;   ROUTE       = where the pipe centreline goes.
;   COMPONENT   = something installed in/on the route (elbow, valve, tee...).
;   CATALOGUE   = dimensional/product information for a component.
;   MODEL       = AutoCAD geometry generated from route + component data.
;
;   A component is centre-based.  Its insertion point is its physical centre,
;   not the beginning or end of its footprint.
;
;   The component longitudinal direction is independent of the current UCS.
;   This is required for valves and future components in arbitrary 3D routes.
;
;   Pipe splitting around a component is a later modelling step.  This file
;   only establishes the data structures and pure helper functions needed for
;   that step.
; -----------------------------------------------------------------------------

(vl-load-com)

; -----------------------------------------------------------------------------
; COMPONENT TYPE CONSTANTS
; -----------------------------------------------------------------------------
(setq *gtp-component-types*
  '("PIPE" "ELBOW" "VALVE" "TEE" "REDUCER" "BRANCH"
    "VENT_DRAIN" "END_CAP" "SPECIAL")
)

; -----------------------------------------------------------------------------
; COMPONENT OBJECT
;
; Representation:
;   (list
;     (cons 'id ...)
;     (cons 'type ...)
;     (cons 'system ...)
;     (cons 'dn ...)
;     (cons 'series ...)
;     (cons 'position ...)
;     (cons 'direction ...)
;     (cons 'up ...)
;     (cons 'length ...)
;     (cons 'catalogue ...)
;     (cons 'options ...)
;   )
;
; Keeping this as a property list instead of a VLA object is deliberate:
;   - it is lightweight;
;   - it is easy to inspect/debug;
;   - it is independent of AutoCAD geometry;
;   - later model functions can consume it without changing the data model.
; -----------------------------------------------------------------------------

(defun gtp:component-make
  (id type system dn series position direction up length catalogue options)
  (list
    (cons 'id id)
    (cons 'type type)
    (cons 'system system)
    (cons 'dn dn)
    (cons 'series series)
    (cons 'position position)
    (cons 'direction (gtp:component-unit direction))
    (cons 'up (gtp:component-unit up))
    (cons 'length length)
    (cons 'catalogue catalogue)
    (cons 'options options)
  )
)

(defun gtp:component-get (component key)
  (cdr (assoc key component))
)

(defun gtp:component-set (component key value)
  (if (assoc key component)
    (subst (cons key value) (assoc key component) component)
    (append component (list (cons key value)))
  )
)

(defun gtp:component-unit (v / m)
  (if (and v (= (length v) 3))
    (progn
      (setq m (sqrt (+ (* (car v) (car v))
                       (* (cadr v) (cadr v))
                       (* (caddr v) (caddr v)))))
      (if (> m 1e-12)
        (mapcar '(lambda (x) (/ x m)) v)
        '(1.0 0.0 0.0)
      )
    )
    '(1.0 0.0 0.0)
  )
)

; -----------------------------------------------------------------------------
; COMPONENT VALIDATION
; -----------------------------------------------------------------------------
(defun gtp:component-type-p (type)
  (member type *gtp-component-types*)
)

(defun gtp:component-valid-p (component / type pos dir len)
  (if (not component)
    nil
    (progn
      (setq type (gtp:component-get component 'type))
      (setq pos  (gtp:component-get component 'position))
      (setq dir  (gtp:component-get component 'direction))
      (setq len  (gtp:component-get component 'length))
      (and
        (gtp:component-type-p type)
        pos
        (= (length pos) 3)
        dir
        (= (length dir) 3)
        (or (null len) (>= len 0.0))
      )
    )
  )
)

; -----------------------------------------------------------------------------
; COMPONENT FOOTPRINT
;
; For a longitudinal component of length L:
;   start = centre - direction * L/2
;   end   = centre + direction * L/2
;
; These are geometric footprint points, not AutoCAD entities.
; -----------------------------------------------------------------------------
(defun gtp:component-start (component / p d half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq half (/ (gtp:component-get component 'length) 2.0))
  (mapcar
    '-
    p
    (mapcar '(lambda (x) (* x half)) d)
  )
)

(defun gtp:component-end (component / p d half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq half (/ (gtp:component-get component 'length) 2.0))
  (mapcar
    '+
    p
    (mapcar '(lambda (x) (* x half)) d)
  )
)

(defun gtp:component-footprint (component)
  (list
    (cons 'start (gtp:component-start component))
    (cons 'end (gtp:component-end component))
  )
)

; -----------------------------------------------------------------------------
; COMPONENT CATALOGUE RECORD
;
; Catalogue data is deliberately kept separate from the installed component.
;
; Example concept:
;   catalogue =
;     ((family . "SINGLE_SHUTOFF_VALVE")
;      (length-mm . 360.0)
;      (stem-height-mm . 180.0)
;      (manufacturer . "ISOPLUS"))
;
; No real valve dimensions are added here yet.  The existing project catalogue
; remains the source of truth until the valve catalogue is migrated.
; -----------------------------------------------------------------------------

(defun gtp:catalogue-get (catalogue key)
  (cdr (assoc key catalogue))
)

(defun gtp:catalogue-set (catalogue key value)
  (if (assoc key catalogue)
    (subst (cons key value) (assoc key catalogue) catalogue)
    (append catalogue (list (cons key value)))
  )
)

; -----------------------------------------------------------------------------
; COMPONENT FACTORIES
;
; These factories create DATA ONLY.  They do not create AutoCAD geometry.
; -----------------------------------------------------------------------------

(defun gtp:make-pipe-component
  (id system dn series start end options)
  (gtp:component-make
    id
    "PIPE"
    system
    dn
    series
    (mapcar '(lambda (a b) (/ (+ a b) 2.0)) start end)
    (gtp:component-unit (mapcar '- end start))
    '(0.0 0.0 1.0)
    (distance start end)
    nil
    options
  )
)

(defun gtp:make-valve-component
  (id system dn series position direction up length catalogue options)
  (gtp:component-make
    id "VALVE" system dn series position direction up length catalogue options
  )
)

(defun gtp:make-generic-component
  (id type system dn series position direction up length catalogue options)
  (gtp:component-make
    id type system dn series position direction up length catalogue options
  )
)

; -----------------------------------------------------------------------------
; COMPONENT COLLECTION
; -----------------------------------------------------------------------------

(defun gtp:components-empty () '())

(defun gtp:components-add (components component)
  (if (gtp:component-valid-p component)
    (append components (list component))
    components
  )
)

(defun gtp:components-by-type (components type / out)
  (setq out '())
  (foreach component components
    (if (= (gtp:component-get component 'type) type)
      (setq out (append out (list component)))
    )
  )
  out
)

(defun gtp:component-find-id (components id / found)
  (setq found nil)
  (foreach component components
    (if (and (null found) (= (gtp:component-get component 'id) id))
      (setq found component)
    )
  )
  found
)

; -----------------------------------------------------------------------------
; ROUTE SEGMENT DATA
;
; This is the target internal representation for the future route engine.
; Existing GTPPIPE still uses its current point-list route representation.
; -----------------------------------------------------------------------------

(defun gtp:route-segment-make (id start end system dn series)
  (list
    (cons 'id id)
    (cons 'start start)
    (cons 'end end)
    (cons 'direction (gtp:component-unit (mapcar '- end start)))
    (cons 'length (distance start end))
    (cons 'system system)
    (cons 'dn dn)
    (cons 'series series)
  )
)

(defun gtp:route-segment-get (segment key)
  (cdr (assoc key segment))
)

; -----------------------------------------------------------------------------
; ROUTE MODEL CONTAINER
;
; A future route model can be represented as:
;   ((segments . (...))
;    (components . (...))
;    (metadata . (...)))
;
; Keeping this container separate from AutoCAD entities allows later features
; such as BOM extraction, component editing, clash checks, and pipe splitting
; to operate on the same model.
; -----------------------------------------------------------------------------

(defun gtp:route-model-make (segments components metadata)
  (list
    (cons 'segments segments)
    (cons 'components components)
    (cons 'metadata metadata)
  )
)

(defun gtp:route-model-get (model key)
  (cdr (assoc key model))
)

(defun gtp:route-model-add-component (model component / components)
  (setq components (gtp:route-model-get model 'components))
  (gtp:route-model-set
    model
    'components
    (gtp:components-add components component)
  )
)

(defun gtp:route-model-set (model key value)
  (if (assoc key model)
    (subst (cons key value) (assoc key model) model)
    (append model (list (cons key value)))
  )
)

; -----------------------------------------------------------------------------
; PIPE SPLIT PLANNING
;
; This function is intentionally planning-only.  It does not call any current
; GTP solid-generation function.  Given a straight pipe interval and a list of
; longitudinal components, it returns intervals that remain available for pipe
; modelling.
;
; Later this becomes the bridge between:
;   route geometry -> component footprints -> spool generator.
; -----------------------------------------------------------------------------

(defun gtp:point-distance-along (origin direction point)
  (gtp:dot
    (mapcar '- point origin)
    direction
  )
)

(defun gtp:component-overlap-range
  (origin direction startDist endDist component / cs ce a b lo hi)
  (setq cs (gtp:component-start component))
  (setq ce (gtp:component-end component))
  (setq a (gtp:point-distance-along origin direction cs))
  (setq b (gtp:point-distance-along origin direction ce))
  (setq lo (min a b))
  (setq hi (max a b))
  (if (and (< lo endDist) (> hi startDist))
    (list (max startDist lo) (min endDist hi))
    nil
  )
)

(defun gtp:subtract-range (ranges cut / out a b c d)
  (setq out '())
  (setq a (car cut))
  (setq b (cadr cut))
  (foreach range ranges
    (setq c (car range))
    (setq d (cadr range))
    (if (or (>= c b) (<= d a))
      (setq out (append out (list range)))
      (progn
        (if (> a c)
          (setq out (append out (list (list c (min a d)))))
        )
        (if (< b d)
          (setq out (append out (list (list (max b c) d))))
        )
      )
    )
  )
  out
)

(defun gtp:plan-pipe-intervals
  (start end components / direction total ranges cut component)
  (setq direction (gtp:component-unit (mapcar '- end start)))
  (setq total (distance start end))
  (setq ranges (list (list 0.0 total)))

  (foreach component components
    (setq cut
      (gtp:component-overlap-range
        start direction 0.0 total component
      )
    )
    (if cut
      (setq ranges (gtp:subtract-range ranges cut))
    )
  )
  ranges
)

(defun gtp:ranges-to-points (start direction ranges / out range p1 p2)
  (setq out '())
  (foreach range ranges
    (setq p1
      (mapcar
        '+
        start
        (mapcar '(lambda (x) (* x (car range))) direction)
      )
    )
    (setq p2
      (mapcar
        '+
        start
        (mapcar '(lambda (x) (* x (cadr range))) direction)
      )
    )
    (setq out (append out (list (list p1 p2))))
  )
  out
)

; -----------------------------------------------------------------------------
; DEBUG / INSPECTION HELPERS
; -----------------------------------------------------------------------------

(defun gtp:component-summary (component / id type dn series len pos)
  (setq id     (gtp:component-get component 'id))
  (setq type   (gtp:component-get component 'type))
  (setq dn     (gtp:component-get component 'dn))
  (setq series (gtp:component-get component 'series))
  (setq len    (gtp:component-get component 'length))
  (setq pos    (gtp:component-get component 'position))
  (strcat
    "ID=" (if id id "<nil>")
    " TYPE=" (if type type "<nil>")
    " DN=" (if dn (itoa dn) "<nil>")
    " SERIES=" (if series (itoa series) "<nil>")
    " LENGTH=" (if len (rtos len 2 3) "<nil>")
    " POS=("
      (if pos (rtos (car pos) 2 3) "<nil>") ","
      (if pos (rtos (cadr pos) 2 3) "<nil>") ","
      (if pos (rtos (caddr pos) 2 3) "<nil>") ")"
  )
)

(defun gtp:components-summary (components / out)
  (setq out "")
  (foreach component components
    (setq out
      (strcat
        out
        (if (> (strlen out) 0) "\n" "")
        (gtp:component-summary component)
      )
    )
  )
  out
)

(princ "\nGTP component architecture foundation loaded. GTPPIPE behaviour unchanged.")
(princ)
