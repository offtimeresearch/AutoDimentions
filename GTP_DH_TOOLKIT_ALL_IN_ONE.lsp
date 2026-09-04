; GTP_DH_TOOLKIT_ALL_IN_ONE.LSP
; ============================================================================
; MONOLITHIC GTP DH TOOLKIT
;
; This file is the combined single-file build of the current GTP toolkit.
; It contains the original pipe engine plus the component architecture,
; elbow integration, valve component engine, valve-aware pipe integration,
; catalogue-backed valve variants, and persistent fitting/component registry.
;
; No external GTP .lsp dependency is required by this file.
; Load ONLY this file for the combined build.
; ============================================================================

(vl-load-com)

; -----------------------------------------------------------------------------
; CORE CATALOGUE DATA - millimetres
; -----------------------------------------------------------------------------
(setq *gtp-pipe-db*
  '(
    (20  26.9  90  110 125)
    (25  33.7  90  110 125)
    (32  42.4  110 125 140)
    (40  48.3  110 125 140)
    (50  60.3  125 140 160)
    (65  76.1  140 160 180)
    (80  88.9  160 180 200)
    (100 114.3 200 225 250)
    (125 139.7 225 250 280)
    (150 168.3 250 280 315)
    (200 219.1 315 355 400)
    (250 273.0 400 450 500)
    (300 323.9 450 500 560)
    (350 355.6 500 560 630)
    (400 406.4 560 630 710)
    (450 457.2 630 710 800)
    (500 508.0 710 800 900)
    (600 610.0 800 900 1000)
  )
)

(setq *gtp-elbow-db*
  '(
    (20  600.0 1000.0) (25  600.0 1000.0) (32  600.0 1000.0)
    (40  600.0 1000.0) (50  600.0 1000.0) (65  600.0 1000.0)
    (80  600.0 1000.0) (100 700.0 1000.0) (125 750.0 1000.0)
    (150 800.0 1000.0) (200 nil   1000.0) (250 nil   1000.0)
    (300 nil   1000.0) (350 nil   1000.0) (400 nil   1000.0)
    (450 nil   1100.0) (500 nil   1200.0) (600 nil   1300.0)
  )
)

(setq *gtp-max-pipe-length-mm* 12000.0)
(setq *gtp-end-cutback-mm* 220.0)
(setq *gtp-standard-bend-radius-factor* 3.0)
(setq *gtp-min-elbow-straight-mm* 50.0)
(setq *gtp-straight-angle-tol-deg* 0.5)
(setq *gtp-duplicate-point-tol* 1e-8)
(setq *gtp-mm-to-du* 1.0)
(setq *gtp-drawing-unit-name* "millimetres")
(setq *gtp-pipe-color* 1)
(setq *gtp-flow-type* "Flow")

; -----------------------------------------------------------------------------
; UNITS
; -----------------------------------------------------------------------------
(defun gtp:unit-info-from-insunits (u)
  (cond
    ((= u 1)  (list "inches" (/ 1.0 25.4)))
    ((= u 2)  (list "feet" (/ 1.0 304.8)))
    ((= u 4)  (list "millimetres" 1.0))
    ((= u 5)  (list "centimetres" 0.1))
    ((= u 6)  (list "metres" 0.001))
    ((= u 7)  (list "kilometres" 0.000001))
    ((= u 10) (list "yards" (/ 1.0 914.4)))
    ((= u 14) (list "decimetres" 0.01))
    ((= u 15) (list "decametres" 0.0001))
    ((= u 16) (list "hectometres" 0.00001))
    (T nil)
  )
)

(defun gtp:manual-unit-info (/ s)
  (initget "MM CM M Inch Feet")
  (setq s (getkword "\nDrawing unit [MM/CM/M/Inch/Feet] <MM>: "))
  (if (null s) (setq s "MM"))
  (cond
    ((= s "MM")   (list "millimetres" 1.0))
    ((= s "CM")   (list "centimetres" 0.1))
    ((= s "M")    (list "metres" 0.001))
    ((= s "Inch") (list "inches" (/ 1.0 25.4)))
    ((= s "Feet") (list "feet" (/ 1.0 304.8)))
  )
)

(defun gtp:setup-units (/ s info)
  (initget "Auto MM CM M Inch Feet")
  (setq s (getkword "\nCatalogue is mm. Drawing unit [Auto/MM/CM/M/Inch/Feet] <Auto>: "))
  (if (null s) (setq s "Auto"))
  (cond
    ((= s "Auto")
      (setq info (gtp:unit-info-from-insunits (getvar "INSUNITS")))
      (if (null info) (setq info (gtp:manual-unit-info)))
    )
    ((= s "MM")   (setq info (list "millimetres" 1.0)))
    ((= s "CM")   (setq info (list "centimetres" 0.1)))
    ((= s "M")    (setq info (list "metres" 0.001)))
    ((= s "Inch") (setq info (list "inches" (/ 1.0 25.4))))
    ((= s "Feet") (setq info (list "feet" (/ 1.0 304.8))))
  )
  (setq *gtp-drawing-unit-name* (car info))
  (setq *gtp-mm-to-du* (cadr info))
  (princ
    (strcat
      "\nGTP scale: 1000 mm = "
      (rtos (* 1000.0 *gtp-mm-to-du*) 2 6)
      " drawing units [" *gtp-drawing-unit-name* "]."
    )
  )
  info
)

(defun gtp:mm (x) (* x *gtp-mm-to-du*))
(defun c:GTPUNITS () (gtp:setup-units) (princ))

; -----------------------------------------------------------------------------
; LAYERS
; -----------------------------------------------------------------------------
(defun gtp:ensure-layer (name color / doc lays lay)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq lays (vla-get-Layers doc))
  (if (tblsearch "LAYER" name)
    (setq lay (vla-Item lays name))
    (setq lay (vla-Add lays name))
  )
  (if color (vla-put-Color lay color))
  (vl-catch-all-apply 'vla-put-LayerOn (list lay :vlax-true))
  (vl-catch-all-apply 'vla-put-Freeze (list lay :vlax-false))
  (vl-catch-all-apply 'vla-put-Lock (list lay :vlax-false))
  lay
)

(defun gtp:layers ()
  (gtp:ensure-layer "GTP-PIPE-CASING" 8)
  (gtp:ensure-layer "GTP-PIPE-INSULATION" 2)
  (gtp:ensure-layer "GTP-PIPE-CARRIER" 1)
  (gtp:ensure-layer "GTP-PIPE-CENTRELINE" 4)
  (princ)
)

(defun c:GTPLAYER () (gtp:layers) (princ "\nGTP layers ready and visible.") (princ))

; -----------------------------------------------------------------------------
; VECTOR / GEOMETRY HELPERS
; -----------------------------------------------------------------------------
(defun gtp:vadd (a b) (mapcar '+ a b))
(defun gtp:vsub (a b) (mapcar '- a b))
(defun gtp:vscale (v s) (mapcar '(lambda (x) (* x s)) v))
(defun gtp:dot (a b)
  (+ (* (car a) (car b)) (* (cadr a) (cadr b)) (* (caddr a) (caddr b)))
)
(defun gtp:vmag (v) (sqrt (gtp:dot v v)))
(defun gtp:vunit (v / m)
  (setq m (gtp:vmag v))
  (if (> m 1e-12) (gtp:vscale v (/ 1.0 m)) '(0.0 0.0 1.0))
)
(defun gtp:cross (a b)
  (list
    (- (* (cadr a) (caddr b)) (* (caddr a) (cadr b)))
    (- (* (caddr a) (car b)) (* (car a) (caddr b)))
    (- (* (car a) (cadr b)) (* (cadr a) (car b)))
  )
)
(defun gtp:rad->deg (a) (* a (/ 180.0 pi)))
(defun gtp:tan (a / c)
  (setq c (cos a))
  (if (< (abs c) 1e-12) 1e99 (/ (sin a) c))
)
(defun gtp:variant (lst)
  (vlax-make-variant
    (vlax-safearray-fill
      (vlax-make-safearray vlax-vbDouble '(0 . 2))
      lst
    )
  )
)

(defun gtp:axis-matrix (p1 p2 / z ref x y mid)
  (setq z (gtp:vunit (gtp:vsub p2 p1)))
  (setq mid (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
  (if (> (abs (caddr z)) 0.999)
    (setq ref '(0.0 1.0 0.0))
    (setq ref '(0.0 0.0 1.0))
  )
  (setq x (gtp:vunit (gtp:cross ref z)))
  (setq y (gtp:cross z x))
  (list
    (list (car x) (car y) (car z) (car mid))
    (list (cadr x) (cadr y) (cadr z) (cadr mid))
    (list (caddr x) (caddr y) (caddr z) (caddr mid))
    (list 0.0 0.0 0.0 1.0)
  )
)

(defun gtp:frame-z (origin z / ref x y)
  (setq z (gtp:vunit z))
  (if (> (abs (caddr z)) 0.999)
    (setq ref '(0.0 1.0 0.0))
    (setq ref '(0.0 0.0 1.0))
  )
  (setq x (gtp:vunit (gtp:cross ref z)))
  (setq y (gtp:cross z x))
  (list
    (list (car x) (car y) (car z) (car origin))
    (list (cadr x) (cadr y) (cadr z) (cadr origin))
    (list (caddr x) (caddr y) (caddr z) (caddr origin))
    (list 0.0 0.0 0.0 1.0)
  )
)

(defun gtp:frame-xyz (origin x y z)
  (list
    (list (car x) (car y) (car z) (car origin))
    (list (cadr x) (cadr y) (cadr z) (cadr origin))
    (list (caddr x) (caddr y) (caddr z) (caddr origin))
    (list 0.0 0.0 0.0 1.0)
  )
)

; -----------------------------------------------------------------------------
; SOLID CREATION
; -----------------------------------------------------------------------------
(defun gtp:make-cylinder (p1 p2 dia layer / doc ms len obj)
  (setq len (distance p1 p2))
  (if (> len 1e-8)
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq ms (vla-get-ModelSpace doc))
      (setq obj (vla-AddCylinder ms (gtp:variant '(0.0 0.0 0.0)) (/ dia 2.0) len))
      (vla-TransformBy obj (vlax-tmatrix (gtp:axis-matrix p1 p2)))
      (vla-put-Layer obj layer)
      (vla-put-Color obj *gtp-pipe-color*)
      obj
    )
  )
)

(defun gtp:safe-delete (obj)
  (if obj (vl-catch-all-apply 'vla-Delete (list obj)))
)

(defun gtp:make-circle-region (center normal radius / doc ms cir arr regs reg)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq cir (vla-AddCircle ms (gtp:variant '(0.0 0.0 0.0)) radius))
  (vla-TransformBy cir (vlax-tmatrix (gtp:frame-z center normal)))
  (setq arr (vlax-make-safearray vlax-vbObject '(0 . 0)))
  (vlax-safearray-put-element arr 0 cir)
  (setq regs (vl-catch-all-apply 'vla-AddRegion (list ms arr)))
  (if (vl-catch-all-error-p regs)
    (progn (gtp:safe-delete cir) nil)
    (progn
      (setq reg (vlax-safearray-get-element (vlax-variant-value regs) 0))
      (gtp:safe-delete cir)
      reg
    )
  )
)

(defun gtp:make-arc-path (center t1 normal radius phi / doc ms x y arc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq x (gtp:vunit (gtp:vsub t1 center)))
  (setq y (gtp:cross normal x))
  (setq arc (vla-AddArc ms (gtp:variant '(0.0 0.0 0.0)) radius 0.0 phi))
  (vla-TransformBy arc (vlax-tmatrix (gtp:frame-xyz center x y normal)))
  arc
)

(defun gtp:sweep-arc (center t1 normal tangent radius phi dia layer / doc ms path reg sol)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq path (gtp:make-arc-path center t1 normal radius phi))
  (setq reg (gtp:make-circle-region t1 tangent (/ dia 2.0)))
  (if (and path reg)
    (setq sol (vl-catch-all-apply 'vla-AddExtrudedSolidAlongPath (list ms reg path)))
  )
  (gtp:safe-delete reg)
  (gtp:safe-delete path)
  (if (or (null sol) (vl-catch-all-error-p sol))
    nil
    (progn
      (vla-put-Layer sol layer)
      (vla-put-Color sol *gtp-pipe-color*)
      sol
    )
  )
)

(defun gtp:arc-point (center x y radius a)
  (gtp:vadd center
    (gtp:vadd
      (gtp:vscale x (* radius (cos a)))
      (gtp:vscale y (* radius (sin a)))
    )
  )
)

(defun gtp:segmented-arc (center t1 normal radius phi dia layer / x y seg i a0 a1 p0 p1 obj out)
  (setq x (gtp:vunit (gtp:vsub t1 center)))
  (setq y (gtp:cross normal x))
  (setq seg (max 8 (fix (+ 0.5 (* 18.0 (/ phi (/ pi 2.0)))))))
  (setq i 0 out '())
  (while (< i seg)
    (setq a0 (* phi (/ (float i) seg)))
    (setq a1 (* phi (/ (float (1+ i)) seg)))
    (setq p0 (gtp:arc-point center x y radius a0))
    (setq p1 (gtp:arc-point center x y radius a1))
    (setq obj (gtp:make-cylinder p0 p1 dia layer))
    (if obj (setq out (cons obj out)))
    (setq i (1+ i))
  )
  (reverse out)
)

(defun gtp:model-arc (center t1 normal tangent radius phi dia layer / obj fallback)
  (setq obj
    (vl-catch-all-apply
      'gtp:sweep-arc
      (list center t1 normal tangent radius phi dia layer)
    )
  )
  (if (and obj (not (vl-catch-all-error-p obj)))
    (list obj)
    (progn
      (setq fallback
        (vl-catch-all-apply
          'gtp:segmented-arc
          (list center t1 normal radius phi dia layer)
        )
      )
      (if (vl-catch-all-error-p fallback) nil fallback)
    )
  )
)

; -----------------------------------------------------------------------------
; PIPE / ELBOW DATABASE HELPERS
; -----------------------------------------------------------------------------
(defun gtp:find-dn (dn) (assoc dn *gtp-pipe-db*))

(defun gtp:casing-od (row series)
  (cond
    ((= series 1) (nth 2 row))
    ((= series 2) (nth 3 row))
    ((= series 3) (nth 4 row))
  )
)

(defun gtp:get-dn (/ dn row)
  (while (null row)
    (setq dn (getint "\nNominal DN [20/25/32/40/50/65/80/100/125/150/200/250/300/350/400/450/500/600]: "))
    (if dn (setq row (gtp:find-dn dn)))
    (if (and dn (null row)) (princ "\nDN not in current database."))
  )
  row
)

(defun gtp:get-series (/ s)
  (initget "1 2 3")
  (setq s (getkword "\nInsulation series [1/2/3] <2>: "))
  (if s (atoi s) 2)
)

(defun gtp:get-mode (/ s)
  (initget "CASING FULL")
  (setq s (getkword "\nModel mode [CASING/FULL] <CASING>: "))
  (if s s "CASING")
)

(defun gtp:get-flow-type (/ s)
  (initget "Flow Return")
  (setq s (getkword "\nPipe duty [Flow/Return] <Flow>: "))
  (if (null s) (setq s "Flow"))
  (setq *gtp-flow-type* s)
  (setq *gtp-pipe-color* (if (= s "Flow") 1 5))
  (princ (strcat "\n" s " pipe colour: " (if (= s "Flow") "red." "blue.")))
  s
)

(defun gtp:get-elbow-style (/ s)
  (initget "Standard Short")
  (setq s (getkword "\nElbow leg [Standard/Short] <Standard>: "))
  (if s s "Standard")
)

(defun gtp:elbow-leg-mm (dn style / row short standard)
  (setq row (assoc dn *gtp-elbow-db*))
  (setq short (nth 1 row))
  (setq standard (nth 2 row))
  (if (= style "Short")
    (if short short standard)
    standard
  )
)

; -----------------------------------------------------------------------------
; ELBOW MODEL
; -----------------------------------------------------------------------------
(defun gtp:make-elbow-spec (prev vertex next dn carrier casing style / d1 d2 cr cm dp phi deg leg0 maxleg leg normal desiredR minR minStraight tang maxR radius tanDist fs fe t1 t2 inward center)
  (setq d1 (gtp:vunit (gtp:vsub vertex prev)))
  (setq d2 (gtp:vunit (gtp:vsub next vertex)))
  (setq cr (gtp:cross d1 d2))
  (setq cm (gtp:vmag cr))
  (setq dp (gtp:dot d1 d2))
  (setq phi (atan cm dp))
  (setq deg (gtp:rad->deg phi))

  (if (or (< deg 1.0) (> deg 175.0) (< cm 1e-10))
    nil
    (progn
      (setq normal (gtp:vunit cr))
      (setq leg0 (gtp:mm (gtp:elbow-leg-mm dn style)))
      (setq maxleg (min (* 0.45 (distance prev vertex)) (* 0.45 (distance vertex next))))
      (setq leg (min leg0 maxleg))
      (setq desiredR (* *gtp-standard-bend-radius-factor* carrier))
      (setq minR (* 0.55 casing))
      (setq minStraight
        (min
          (* 0.25 leg)
          (max (gtp:mm *gtp-min-elbow-straight-mm*)
               (gtp:mm *gtp-end-cutback-mm*))
        )
      )
      (setq tang (gtp:tan (/ phi 2.0)))
      (setq maxR
        (if (> tang 1e-10)
          (/ (max 0.0 (- leg minStraight)) tang)
          desiredR
        )
      )
      (setq radius (min desiredR maxR))
      (if (< radius minR)
        nil
        (progn
          (setq tanDist (* radius tang))
          (setq fs (gtp:vadd vertex (gtp:vscale d1 (- leg))))
          (setq fe (gtp:vadd vertex (gtp:vscale d2 leg)))
          (setq t1 (gtp:vadd vertex (gtp:vscale d1 (- tanDist))))
          (setq t2 (gtp:vadd vertex (gtp:vscale d2 tanDist)))
          (setq inward (gtp:vunit (gtp:cross normal d1)))
          (setq center (gtp:vadd t1 (gtp:vscale inward radius)))
          (list
            (cons 'radius radius)
            (cons 'phi phi)
            (cons 'deg deg)
            (cons 'd1 d1)
            (cons 'd2 d2)
            (cons 'normal normal)
            (cons 'start fs)
            (cons 'tan1 t1)
            (cons 'center center)
            (cons 'tan2 t2)
            (cons 'end fe)
            (cons 'clipped (< leg (- leg0 1e-8)))
          )
        )
      )
    )
  )
)

(defun gtp:spec (key spec) (cdr (assoc key spec)))

(defun gtp:model-elbow (spec carrier casing mode / r phi d1 d2 normal fs t1 center t2 fe cut cut1 cut2 cs ce)
  (setq r (gtp:spec 'radius spec))
  (setq phi (gtp:spec 'phi spec))
  (setq d1 (gtp:spec 'd1 spec))
  (setq d2 (gtp:spec 'd2 spec))
  (setq normal (gtp:spec 'normal spec))
  (setq fs (gtp:spec 'start spec))
  (setq t1 (gtp:spec 'tan1 spec))
  (setq center (gtp:spec 'center spec))
  (setq t2 (gtp:spec 'tan2 spec))
  (setq fe (gtp:spec 'end spec))

  (gtp:make-cylinder fs t1 carrier "GTP-PIPE-CARRIER")
  (gtp:model-arc center t1 normal d1 r phi carrier "GTP-PIPE-CARRIER")
  (gtp:make-cylinder t2 fe carrier "GTP-PIPE-CARRIER")

  (setq cut (gtp:mm *gtp-end-cutback-mm*))
  (setq cut1 (min cut (* 0.80 (distance fs t1))))
  (setq cut2 (min cut (* 0.80 (distance t2 fe))))
  (setq cs (gtp:vadd fs (gtp:vscale d1 cut1)))
  (setq ce (gtp:vadd fe (gtp:vscale d2 (- cut2))))

  (gtp:make-cylinder cs t1 casing "GTP-PIPE-CASING")
  (gtp:model-arc center t1 normal d1 r phi casing "GTP-PIPE-CASING")
  (gtp:make-cylinder t2 ce casing "GTP-PIPE-CASING")

  (if (= mode "FULL")
    (progn
      (gtp:make-cylinder cs t1 casing "GTP-PIPE-INSULATION")
      (gtp:model-arc center t1 normal d1 r phi casing "GTP-PIPE-INSULATION")
      (gtp:make-cylinder t2 ce casing "GTP-PIPE-INSULATION")
    )
  )
)

; -----------------------------------------------------------------------------
; STRAIGHT PIPE MODEL
; -----------------------------------------------------------------------------
(defun gtp:point-along (p1 p2 dist)
  (gtp:vadd p1 (gtp:vscale (gtp:vunit (gtp:vsub p2 p1)) dist))
)

(defun gtp:model-spool (p1 p2 carrier casing mode / len cut c1 c2)
  (setq len (distance p1 p2))
  (setq cut (gtp:mm *gtp-end-cutback-mm*))
  (if (>= (* 2.0 cut) len) (setq cut (/ len 4.0)))
  (setq c1 (gtp:point-along p1 p2 cut))
  (setq c2 (gtp:point-along p1 p2 (- len cut)))

  (gtp:make-cylinder p1 p2 carrier "GTP-PIPE-CARRIER")
  (if (> (distance c1 c2) 1e-8)
    (progn
      (gtp:make-cylinder c1 c2 casing "GTP-PIPE-CASING")
      (if (= mode "FULL")
        (gtp:make-cylinder c1 c2 casing "GTP-PIPE-INSULATION")
      )
    )
  )
)

(defun gtp:model-segment (p1 p2 carrier casing mode / len dir pos piece s1 s2 count)
  (setq len (distance p1 p2))
  (setq dir (gtp:vunit (gtp:vsub p2 p1)))
  (setq pos 0.0 count 0)
  (while (< pos (- len 1e-8))
    (setq piece (min (gtp:mm *gtp-max-pipe-length-mm*) (- len pos)))
    (setq s1 (gtp:vadd p1 (gtp:vscale dir pos)))
    (setq s2 (gtp:vadd p1 (gtp:vscale dir (+ pos piece))))
    (gtp:model-spool s1 s2 carrier casing mode)
    (setq pos (+ pos piece))
    (setq count (1+ count))
  )
  count
)

; -----------------------------------------------------------------------------
; ROUTE READING AND CLEANUP
; -----------------------------------------------------------------------------
(defun gtp:curve-points (ename / endParam i p pts)
  (setq endParam (vl-catch-all-apply 'vlax-curve-getEndParam (list ename)))
  (if (vl-catch-all-error-p endParam)
    nil
    (progn
      (setq i 0 pts '())
      (while (<= i (fix endParam))
        (setq p (vlax-curve-getPointAtParam ename i))
        (if p (setq pts (append pts (list p))))
        (setq i (1+ i))
      )
      pts
    )
  )
)

(defun gtp:remove-duplicate-route-points (pts / out lastp p)
  (setq out '() lastp nil)
  (foreach p pts
    (if (or (null lastp) (> (distance lastp p) *gtp-duplicate-point-tol*))
      (progn
        (setq out (append out (list p)))
        (setq lastp p)
      )
    )
  )
  out
)

(defun gtp:route-turn-angle-deg (a b c / u v cr dp)
  (setq u (gtp:vunit (gtp:vsub b a)))
  (setq v (gtp:vunit (gtp:vsub c b)))
  (setq cr (gtp:vmag (gtp:cross u v)))
  (setq dp (gtp:dot u v))
  (gtp:rad->deg (atan cr dp))
)

(defun gtp:simplify-route-points (pts / originalCount cleaned duplicateRemoved n out i prev cur nxt ang straightRemoved)
  (setq originalCount (length pts))
  (setq cleaned (gtp:remove-duplicate-route-points pts))
  (setq duplicateRemoved (- originalCount (length cleaned)))
  (setq straightRemoved 0)

  (if (<= (length cleaned) 2)
    (list cleaned duplicateRemoved 0)
    (progn
      (setq n (length cleaned))
      (setq out (list (car cleaned)))
      (setq i 1)
      (while (< i (1- n))
        (setq prev (nth (1- i) cleaned))
        (setq cur  (nth i cleaned))
        (setq nxt  (nth (1+ i) cleaned))
        (setq ang (gtp:route-turn-angle-deg prev cur nxt))
        (if (<= ang *gtp-straight-angle-tol-deg*)
          (setq straightRemoved (1+ straightRemoved))
          (setq out (append out (list cur)))
        )
        (setq i (1+ i))
      )
      (setq out (append out (list (last cleaned))))
      (list out duplicateRemoved straightRemoved)
    )
  )
)

(defun gtp:safe-simplify-route-points (pts / r)
  (setq r (vl-catch-all-apply 'gtp:simplify-route-points (list pts)))
  (if (or (vl-catch-all-error-p r) (null r) (null (car r)) (< (length (car r)) 2))
    (progn
      (princ "\nRoute cleanup warning: cleanup failed, so the original route vertices will be used.")
      (list pts 0 0)
    )
    r
  )
)

; -----------------------------------------------------------------------------
; COMPONENT ARCHITECTURE
; -----------------------------------------------------------------------------
(setq *gtp-component-types*
  '("PIPE" "ELBOW" "VALVE" "TEE" "REDUCER" "BRANCH" "VENT_DRAIN" "END_CAP" "SPECIAL")
)

(defun gtp:component-unit (v / m)
  (if (and v (= (length v) 3))
    (progn
      (setq m (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v)) (* (caddr v) (caddr v)))))
      (if (> m 1e-12)
        (mapcar '(lambda (x) (/ x m)) v)
        '(1.0 0.0 0.0)
      )
    )
    '(1.0 0.0 0.0)
  )
)

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

(defun gtp:component-get (component key) (cdr (assoc key component)))

(defun gtp:component-set (component key value)
  (if (assoc key component)
    (subst (cons key value) (assoc key component) component)
    (append component (list (cons key value)))
  )
)

(defun gtp:component-type-p (type) (member type *gtp-component-types*))

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
        pos (= (length pos) 3)
        dir (= (length dir) 3)
        (or (null len) (>= len 0.0))
      )
    )
  )
)

(defun gtp:component-start (component / p d half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq half (/ (gtp:component-get component 'length) 2.0))
  (mapcar '- p (mapcar '(lambda (x) (* x half)) d))
)

(defun gtp:component-end (component / p d half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq half (/ (gtp:component-get component 'length) 2.0))
  (mapcar '+ p (mapcar '(lambda (x) (* x half)) d))
)

(defun gtp:component-footprint (component)
  (list (cons 'start (gtp:component-start component)) (cons 'end (gtp:component-end component)))
)

(defun gtp:catalogue-get (catalogue key) (cdr (assoc key catalogue)))

(defun gtp:catalogue-set (catalogue key value)
  (if (assoc key catalogue)
    (subst (cons key value) (assoc key catalogue) catalogue)
    (append catalogue (list (cons key value)))
  )
)

(defun gtp:make-pipe-component (id system dn series start end options)
  (gtp:component-make id "PIPE" system dn series
    (mapcar '(lambda (a b) (/ (+ a b) 2.0)) start end)
    (gtp:component-unit (mapcar '- end start)) '(0.0 0.0 1.0)
    (distance start end) nil options
  )
)

(defun gtp:make-valve-component
  (id system dn series position direction up length catalogue options)
  (gtp:component-make id "VALVE" system dn series position direction up length catalogue options)
)

(defun gtp:make-generic-component
  (id type system dn series position direction up length catalogue options)
  (gtp:component-make id type system dn series position direction up length catalogue options)
)

(defun gtp:components-empty () '())

(defun gtp:components-add (components component)
  (if (gtp:component-valid-p component) (append components (list component)) components)
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
    (if (and (null found) (= (gtp:component-get component 'id) id)) (setq found component))
  )
  found
)

(defun gtp:route-segment-make (id start end system dn series)
  (list
    (cons 'id id) (cons 'start start) (cons 'end end)
    (cons 'direction (gtp:component-unit (mapcar '- end start)))
    (cons 'length (distance start end))
    (cons 'system system) (cons 'dn dn) (cons 'series series)
  )
)

(defun gtp:route-segment-get (segment key) (cdr (assoc key segment)))

(defun gtp:route-model-make (segments components metadata)
  (list (cons 'segments segments) (cons 'components components) (cons 'metadata metadata))
)

(defun gtp:route-model-get (model key) (cdr (assoc key model)))

(defun gtp:route-model-set (model key value)
  (if (assoc key model)
    (subst (cons key value) (assoc key model) model)
    (append model (list (cons key value)))
  )
)

(defun gtp:route-model-add-component (model component / components)
  (setq components (gtp:route-model-get model 'components))
  (gtp:route-model-set model 'components (gtp:components-add components component))
)

(defun gtp:point-distance-along (origin direction point)
  (gtp:dot (mapcar '- point origin) direction)
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
        (if (> a c) (setq out (append out (list (list c (min a d))))))
        (if (< b d) (setq out (append out (list (list (max b c) d)))))
      )
    )
  )
  out
)

(defun gtp:plan-pipe-intervals (start end components / direction total ranges cut component)
  (setq direction (gtp:component-unit (mapcar '- end start)))
  (setq total (distance start end))
  (setq ranges (list (list 0.0 total)))
  (foreach component components
    (setq cut (gtp:component-overlap-range start direction 0.0 total component))
    (if cut (setq ranges (gtp:subtract-range ranges cut)))
  )
  ranges
)

(defun gtp:ranges-to-points (start direction ranges / out range p1 p2)
  (setq out '())
  (foreach range ranges
    (setq p1 (mapcar '+ start (mapcar '(lambda (x) (* x (car range))) direction)))
    (setq p2 (mapcar '+ start (mapcar '(lambda (x) (* x (cadr range))) direction)))
    (setq out (append out (list (list p1 p2))))
  )
  out
)

(defun gtp:component-summary (component / id type dn series len pos)
  (setq id (gtp:component-get component 'id))
  (setq type (gtp:component-get component 'type))
  (setq dn (gtp:component-get component 'dn))
  (setq series (gtp:component-get component 'series))
  (setq len (gtp:component-get component 'length))
  (setq pos (gtp:component-get component 'position))
  (strcat
    "ID=" (if id id "<nil>")
    " TYPE=" (if type type "<nil>")
    " DN=" (if dn (itoa dn) "<nil>")
    " SERIES=" (if series (itoa series) "<nil>")
    " LENGTH=" (if len (rtos len 2 3) "<nil>")
    " POS=(" (if pos (rtos (car pos) 2 3) "<nil>") ","
      (if pos (rtos (cadr pos) 2 3) "<nil>") ","
      (if pos (rtos (caddr pos) 2 3) "<nil>") ")"
  )
)

(defun gtp:components-summary (components / out)
  (setq out "")
  (foreach component components
    (setq out (strcat out (if (> (strlen out) 0) "\n" "") (gtp:component-summary component)))
  )
  out
)

; -----------------------------------------------------------------------------
; ELBOW COMPONENT INTEGRATION
; -----------------------------------------------------------------------------
(defun gtp:make-elbow-component
  (id system dn series prev vertex next carrier casing style / spec)
  (setq spec (gtp:make-elbow-spec prev vertex next dn carrier casing style))
  (if spec
    (gtp:component-make
      id "ELBOW" system dn series vertex
      (gtp:spec 'd1 spec) (gtp:spec 'normal spec) nil
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
  (gtp:model-elbow (gtp:elbow-component-spec component) carrier casing mode)
)

(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e spoolCount elbowCount clippedCount system)
  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))
  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component
        (gtp:make-elbow-component
          (strcat "ELBOW-" (itoa i)) system dn nil
          (nth (1- i) pts) (nth i pts) (nth (1+ i) pts)
          carrier casing style
        )
      )
    )
    (if (and component (gtp:spec 'clipped (gtp:elbow-component-spec component)))
      (setq clippedCount (1+ clippedCount))
    )
    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts))
    (setq p2 (nth (1+ i) pts))
    (setq s (if (nth i elbows) (gtp:elbow-component-end (nth i elbows)) p1))
    (setq e (if (nth (1+ i) elbows) (gtp:elbow-component-start (nth (1+ i) elbows)) p2))
    (if (> (distance s e) 1e-8)
      (setq spoolCount (+ spoolCount (gtp:model-segment s e carrier casing mode)))
    )
    (setq i (1+ i))
  )
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

; -----------------------------------------------------------------------------
; VALVE COMPONENT FOUNDATION
; -----------------------------------------------------------------------------
(if (null *gtp-valve-components*) (setq *gtp-valve-components* '()))
(if (null *gtp-valve-next-id*) (setq *gtp-valve-next-id* 1))

(defun gtp:valve-layers ()
  (gtp:ensure-layer "GTP-VALVE-BODY" 6)
  (gtp:ensure-layer "GTP-VALVE-STEM" 3)
  (gtp:ensure-layer "GTP-VALVE-CENTRELINE" 4)
  (princ)
)

(defun gtp:valve-positive (prompt default / x)
  (initget 6)
  (setq x (getreal (strcat "\n" prompt " <" (rtos default 2 2) ">: ")))
  (if x x default)
)

(defun gtp:curve-point-direction (ent pick / cp param der a b eps)
  (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pick)))
  (if (vl-catch-all-error-p cp)
    nil
    (progn
      (setq param (vl-catch-all-apply 'vlax-curve-getParamAtPoint (list ent cp)))
      (if (vl-catch-all-error-p param)
        nil
        (progn
          (setq der (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list ent param)))
          (if (and (not (vl-catch-all-error-p der)) der (> (gtp:vmag der) 1e-10))
            (list cp (gtp:vunit der))
            (progn
              (setq eps 1e-4)
              (setq a (vl-catch-all-apply 'vlax-curve-getPointAtParam (list ent (max 0.0 (- param eps)))))
              (setq b (vl-catch-all-apply 'vlax-curve-getPointAtParam (list ent (+ param eps))))
              (if (and (not (vl-catch-all-error-p a)) (not (vl-catch-all-error-p b)) (> (distance a b) 1e-10))
                (list cp (gtp:vunit (gtp:vsub b a)))
                nil
              )
            )
          )
        )
      )
    )
  )
)

(defun gtp:make-single-shutoff-valve
  (id system dn series position direction up length-mm body-od-mm stem-height-mm)
  (gtp:make-valve-component
    id "VALVE" system dn series position direction up
    (gtp:mm length-mm)
    (list
      (cons 'family "SINGLE_SHUTOFF_VALVE")
      (cons 'manufacturer "ISOPLUS")
      (cons 'length-mm length-mm)
      (cons 'body-od-mm body-od-mm)
      (cons 'stem-height-mm stem-height-mm)
      (cons 'dimension-source "APPROVED_CATALOGUE_MANUAL_ENTRY")
    ) nil
  )
)

(defun gtp:add-valve-component (component)
  (if (gtp:component-valid-p component)
    (progn
      (setq *gtp-valve-components* (append *gtp-valve-components* (list component)))
      (setq *gtp-valve-next-id* (1+ *gtp-valve-next-id*))
      component
    )
  )
)

(defun gtp:model-single-shutoff-valve (component / p d up len body stem half flange collar p0 p1 s1 s2 sb st)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq up (gtp:component-get component 'up))
  (setq len (gtp:component-get component 'length))
  (setq body (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'body-od-mm)))
  (setq stem (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'stem-height-mm)))
  (setq half (/ len 2.0))
  (setq collar (min (gtp:mm 100.0) (* 0.12 len)))
  (setq flange (* 1.20 body))
  (setq p0 (gtp:vsub p (gtp:vscale d half)))
  (setq p1 (gtp:vadd p (gtp:vscale d half)))
  (setq s1 (gtp:vadd p0 (gtp:vscale d collar)))
  (setq s2 (gtp:vsub p1 (gtp:vscale d collar)))
  (gtp:make-cylinder p0 p1 body "GTP-VALVE-BODY")
  (gtp:make-cylinder p0 s1 flange "GTP-VALVE-BODY")
  (gtp:make-cylinder s2 p1 flange "GTP-VALVE-BODY")
  (setq sb (gtp:vadd p (gtp:vscale up (* 0.35 body))))
  (setq st (gtp:vadd sb (gtp:vscale up stem)))
  (gtp:make-cylinder sb st (max (gtp:mm 20.0) (* 0.12 body)) "GTP-VALVE-STEM")
)

(defun gtp:valve-on-route-p (ent p / cp)
  (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent p)))
  (and (not (vl-catch-all-error-p cp)) (<= (distance cp p) (gtp:mm 5.0)))
)

(defun gtp:valve-dn-row (/ dn row)
  (while (null row)
    (setq dn (getint "\nValve DN [20/25/32/40/50/65/80/100/125/150/200/250/300/350/400/450/500/600]: "))
    (if dn (setq row (gtp:find-dn dn)))
    (if (and dn (null row)) (princ "\nDN not in current database."))
  )
  row
)

(defun c:GTPVALVESUMMARY (/ text)
  (if *gtp-valve-components*
    (progn
      (setq text (gtp:components-summary *gtp-valve-components*))
      (princ "\nRegistered GTP valves:\n")
      (princ text))
    (princ "\nNo GTP valve components registered in this session."))
  (princ)
)

; -----------------------------------------------------------------------------
; VALVE-AWARE PIPE INTEGRATION
; -----------------------------------------------------------------------------
(defun gtp:valve-aware-filter-components (components / out component type)
  (setq out '())
  (foreach component components
    (setq type (gtp:component-get component 'type))
    (if (= type "VALVE") (setq out (append out (list component))))
  )
  out
)

(defun gtp:model-valve-component (component / catalogue family)
  (setq catalogue (gtp:component-get component 'catalogue))
  (setq family (gtp:catalogue-get catalogue 'family))
  (cond
    ((= family "SINGLE_SHUTOFF_VALVE") (gtp:model-single-shutoff-valve component))
    (T
      (princ (strcat "\nGTP warning: no modeller registered for valve family " (if family family "<nil>") "."))
      nil
    )
  )
)

(defun gtp:distance-point-on-line (origin direction dist)
  (gtp:vadd origin (gtp:vscale direction dist))
)

(defun gtp:model-valve-aware-straight
  (start end dn carrier casing mode components / direction total ranges pieces piece p1 p2 count)
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
          (setq count (+ count (gtp:model-segment p1 p2 carrier casing mode)))
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
  (setq cut (gtp:component-overlap-range start direction 0.0 total component))
  (and cut (> (cadr cut) (car cut)))
)

(defun gtp:validate-valve-clearances
  (pts valveComponents / component pos start end warnings)
  (setq warnings 0)
  (foreach component valveComponents
    (setq pos (gtp:component-get component 'position))
    (setq start (car pts))
    (setq end (last pts))
    (if (or (< (distance pos start) 1e-8) (< (distance pos end) 1e-8))
      (progn
        (princ (strcat "\nGTP warning: valve " (gtp:component-get component 'id') " is positioned at a route endpoint; verify the fitting arrangement."))
        (setq warnings (1+ warnings))
      )
    )
  )
  warnings
)

; -----------------------------------------------------------------------------
; ISOPLUS VALVE CATALOGUE
; -----------------------------------------------------------------------------
(setq *gtp-valve-single-db*
  '(
    (26.9  90 110 110 110 125 125 110 480 19 1510)
    (33.7  90 110 110 110 125 125 110 480 19 1510)
    (42.4 110 125 125 125 140 140 110 485 19 1510)
    (48.3 110 125 125 125 140 140 125 494 19 1510)
    (60.3 125 140 140 140 160 160 110 500 19 1510)
    (76.1 140 160 160 180 180 180 110 505 19 1510)
    (88.9 160 180 180 200 200 200 110 515 19 1510)
    (114.3 200 225 225 225 250 250 140 525 27/70 1510)
    (139.7 225 250 250 280 280 280 140 545 27/70 1510)
    (168.3 250 280 280 280 315 315 140 565 27/70 1510)
    (219.1 315 355 355 355 400 400 140 585 50/90 1510)
    (273.0 400 450 450 450 500 500 180 614 50/90 1510)
    (323.9 450 560 500 560 560 560 180 664 50/90 1810)
  )
)

(setq *gtp-valve-single-2vd-db*
  '(
    (26.9  90 110 110 110 125 125 110 110 33.7 480 250 19 1510)
    (33.7  90 110 110 110 125 125 110 110 33.7 480 250 19 1510)
    (42.4 110 125 125 125 140 140 110 110 33.7 485 250 19 1510)
    (48.3 110 125 125 125 140 140 110 125 48.3 494 250 19 1510)
    (60.3 125 140 140 140 160 160 110 125 48.3 500 250 19 1510)
    (76.1 140 160 160 180 180 180 110 125 48.3 505 250 19 1510)
    (88.9 160 180 180 200 200 200 110 125 48.3 515 250 19 1510)
    (114.3 200 225 225 225 250 250 140 140 60.3 525 250 27/70 1510)
    (139.7 225 250 250 280 280 280 140 140 60.3 545 250 27/70 1510)
    (168.3 250 280 280 315 315 140 140 60.3 565 250 27/70 1510)
    (219.1 315 355 355 400 400 140 140 60.3 585 250 50/90 1510)
    (273.0 400 450 450 500 500 180 140 60.3 614 305 50/90 1510)
    (323.9 450 560 500 560 560 180 140 60.3 664 370 50/90 1810)
  )
)

(setq *gtp-valve-twin-db*
  '(
    (33.7  140 180 160 180 180 200 110 210 461 365 19 1600)
    (42.4  160 200 180 200 200 250 110 210 471 366 19 1600)
    (48.3  160 200 180 200 200 250 110 210 499 366 19 1600)
    (60.3  200 250 225 250 250 280 110 210 519 366 19 1600)
    (76.1  225 280 250 280 280 315 110 210 542 360 19 1800)
    (88.9  250 315 280 315 315 355 110 210 574 358 19 1900)
    (114.3 315 400 355 400 450 110 210 618 365 27 1900)
    (139.7 400 500 450 500 560 180 210 690 383 27 2200)
    (168.3 450 560 500 560 630 180 210 752 383 27 2200)
    (219.1 560 630 630 710 710 800 180 210 800 383 27 2200)
  )
)

(setq *gtp-valve-twin-2vd-db*
  '(
    (26.9 125 140 160 355 348 482 33 19 2150)
    (33.7 140 160 180 355 348 482 48 19 2150)
    (42.4 160 180 200 355 348 485 48 19 2150)
    (48.3 160 180 200 355 348 494 48 19 2150)
    (60.3 200 225 250 355 348 480 48 19 2150)
    (76.1 225 250 280 450 426 506 48 19 2350)
    (88.9 250 280 315 450 426 515 48 19 2600)
    (114.3 315 355 400 560 527 527 48 27 2900)
    (139.7 400 450 500 560 533 546 48 27 3300)
    (168.3 450 500 560 630 595 565 48 27/70 4200)
    (219.1 560 630 710 800 665 750 48 50/90 5900)
    (273.0 710 800 900 1100 710 900 70 50/90 3000)
  )
)

(setq *gtp-valve-catalogue-source*
  '(
    ("SINGLE_SHUTOFF" . "ISOPLUS 5.9 / p.89")
    ("SINGLE_SHUTOFF_2VENT_DRAIN" . "ISOPLUS 5.9.1 / p.90")
    ("TWIN_SHUTOFF" . "ISOPLUS 8.10 / p.128")
    ("TWIN_SHUTOFF_2VENT_DRAIN" . "ISOPLUS 8.11 / p.129")
  )
)

(defun gtp:catalogue-row-by-value (db value / row)
  (setq row nil)
  (foreach r db
    (if (and (null row) (< (abs (- (car r) value)) 0.01)) (setq row r))
  )
  row
)

(defun gtp:valve-family-name (family)
  (cdr (assoc family *gtp-valve-catalogue-source*))
)

(defun gtp:valve-carrier-od (dn / row)
  (setq row (gtp:find-dn dn))
  (if row (nth 1 row))
)

(defun gtp:valve-db-for-family (family)
  (cond
    ((= family "SINGLE_SHUTOFF") *gtp-valve-single-db*)
    ((= family "SINGLE_SHUTOFF_2VENT_DRAIN") *gtp-valve-single-2vd-db*)
    ((= family "TWIN_SHUTOFF") *gtp-valve-twin-db*)
    ((= family "TWIN_SHUTOFF_2VENT_DRAIN") *gtp-valve-twin-2vd-db*)
  )
)

(defun gtp:valve-family-prompt (/ s)
  (initget "SINGLE SINGLE2VD TWIN TWIN2VD")
  (setq s (getkword "\nValve type [SINGLE/SINGLE2VD/TWIN/TWIN2VD] <SINGLE>: "))
  (cond
    ((= s "SINGLE2VD") "SINGLE_SHUTOFF_2VENT_DRAIN")
    ((= s "TWIN") "TWIN_SHUTOFF")
    ((= s "TWIN2VD") "TWIN_SHUTOFF_2VENT_DRAIN")
    (T "SINGLE_SHUTOFF")
  )
)

(defun gtp:valve-row-for-dn (family dn / db od row)
  (setq db (gtp:valve-db-for-family family))
  (setq od (gtp:valve-carrier-od dn))
  (if (and db od) (setq row (gtp:catalogue-row-by-value db od)))
  row
)

(defun gtp:valve-catalogue-record (family row series / rec)
  (cond
    ((= family "SINGLE_SHUTOFF")
      (list
        (cons 'family family) (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row)) (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-1-D1-mm (nth 2 row)) (cons 'series-2-D-mm (nth 3 row))
        (cons 'series-2-D1-mm (nth 4 row)) (cons 'series-3-D-mm (nth 5 row))
        (cons 'series-3-D1-mm (nth 6 row)) (cons 'body-D3-mm (nth 7 row))
        (cons 'stem-height-mm (nth 8 row)) (cons 'hex (nth 9 row))
        (cons 'length-mm (nth 10 row)) (cons 'selected-series series)
      )
    )
    ((= family "SINGLE_SHUTOFF_2VENT_DRAIN")
      (list
        (cons 'family family) (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row)) (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-1-D1-mm (nth 2 row)) (cons 'series-2-D-mm (nth 3 row))
        (cons 'series-2-D1-mm (nth 4 row)) (cons 'series-3-D-mm (nth 5 row))
        (cons 'series-3-D1-mm (nth 6 row)) (cons 'body-D2-mm (nth 7 row))
        (cons 'body-D3-mm (nth 8 row)) (cons 'vent-drain-d1-mm (nth 9 row))
        (cons 'stem-height-mm (nth 10 row)) (cons 'spacing-A-mm (nth 11 row))
        (cons 'hex (nth 12 row)) (cons 'length-mm (nth 13 row))
        (cons 'selected-series series)
      )
    )
    ((= family "TWIN_SHUTOFF")
      (list
        (cons 'family family) (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row)) (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-1-D1-mm (nth 2 row)) (cons 'series-2-D-mm (nth 3 row))
        (cons 'series-2-D1-mm (nth 4 row)) (cons 'series-3-D-mm (nth 5 row))
        (cons 'series-3-D1-mm (nth 6 row)) (cons 'body-D2-mm (nth 7 row))
        (cons 'spacing-A-mm (nth 8 row)) (cons 'stem-height-mm (nth 9 row))
        (cons 'stem-height-h1-mm (nth 10 row)) (cons 'hex (nth 11 row))
        (cons 'length-mm (nth 12 row)) (cons 'selected-series series)
      )
    )
    ((= family "TWIN_SHUTOFF_2VENT_DRAIN")
      (list
        (cons 'family family) (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row)) (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-2-D-mm (nth 2 row)) (cons 'series-3-D-mm (nth 3 row))
        (cons 'body-D1-mm (nth 4 row)) (cons 'body-D2-mm (nth 5 row))
        (cons 'stem-height-mm (nth 6 row)) (cons 'vent-drain-mm (nth 7 row))
        (cons 't-wrench (nth 8 row)) (cons 'length-mm (nth 9 row))
        (cons 'selected-series series)
      )
    )
  )
)

(defun gtp:valve-body-diameter-mm (catalogue)
  (cond
    ((gtp:catalogue-get catalogue 'body-D3-mm) (gtp:catalogue-get catalogue 'body-D3-mm))
    ((gtp:catalogue-get catalogue 'body-D2-mm) (gtp:catalogue-get catalogue 'body-D2-mm))
    ((gtp:catalogue-get catalogue 'body-D1-mm) (gtp:catalogue-get catalogue 'body-D1-mm))
    (T 110.0)
  )
)

(defun gtp:make-valve-stem (origin up bodyDia height layer / stemDia stemTop)
  (setq stemDia (max 19.0 (* 0.12 bodyDia)))
  (setq stemTop (gtp:vadd origin (gtp:vscale up height)))
  (gtp:make-cylinder origin stemTop stemDia layer)
)

(defun gtp:make-vertical-valve-head (origin up baseDia stemHeight stemDia)
  (gtp:make-cylinder origin (gtp:vadd origin (gtp:vscale up stemHeight)) stemDia "GTP-VALVE-STEM")
  (gtp:make-cylinder
    (gtp:vadd origin (gtp:vscale up (* 0.35 stemHeight)))
    (gtp:vadd origin (gtp:vscale up (* 0.35 stemHeight)))
    (max baseDia stemDia) "GTP-VALVE-BODY")
)

(defun gtp:place-single-valve-stems (component catalogue / p d up body h A x)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq up (gtp:component-get component 'up))
  (setq body (gtp:valve-body-diameter-mm catalogue))
  (setq h (gtp:mm (gtp:catalogue-get catalogue 'stem-height-mm)))
  (setq h (max h (gtp:mm 150.0)))
  (setq x (gtp:vunit (gtp:cross up d)))
  (if (< (gtp:vmag x) 1e-8) (setq x '(1.0 0.0 0.0)))
  (gtp:make-valve-stem p up (gtp:mm body) h "GTP-VALVE-STEM")
  (if (gtp:catalogue-get catalogue 'spacing-A-mm)
    (progn
      (setq A (gtp:mm (gtp:catalogue-get catalogue 'spacing-A-mm)))
      (gtp:make-valve-stem
        (gtp:vadd p (gtp:vscale x (- (/ A 2.0)))) up
        (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-d1-mm))
        (max (gtp:mm 100.0) (* 0.65 h)) "GTP-VALVE-STEM")
      (gtp:make-valve-stem
        (gtp:vadd p (gtp:vscale x (/ A 2.0))) up
        (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-d1-mm))
        (max (gtp:mm 100.0) (* 0.65 h)) "GTP-VALVE-STEM")
    )
  )
)

(defun gtp:place-twin-valve-stems (component catalogue / p d up A x h body)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq up (gtp:component-get component 'up))
  (setq body (gtp:valve-body-diameter-mm catalogue))
  (setq h (gtp:mm (gtp:catalogue-get catalogue 'stem-height-mm)))
  (setq h (max h (gtp:mm 150.0)))
  (setq x (gtp:vunit (gtp:cross up d)))
  (if (< (gtp:vmag x) 1e-8) (setq x '(1.0 0.0 0.0)))
  (setq A (gtp:mm (if (gtp:catalogue-get catalogue 'spacing-A-mm) (gtp:catalogue-get catalogue 'spacing-A-mm) 210.0)))
  (gtp:make-valve-stem (gtp:vadd p (gtp:vscale x (- (/ A 2.0)))) up (gtp:mm body) h "GTP-VALVE-STEM")
  (gtp:make-valve-stem (gtp:vadd p (gtp:vscale x (/ A 2.0))) up (gtp:mm body) h "GTP-VALVE-STEM")
  (if (gtp:catalogue-get catalogue 'vent-drain-mm)
    (progn
      (gtp:make-valve-stem p up (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-mm)) (max (gtp:mm 100.0) (* 0.65 h)) "GTP-VALVE-STEM")
      (gtp:make-valve-stem p up (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-mm)) (max (gtp:mm 100.0) (* 0.65 h)) "GTP-VALVE-STEM")
    )
  )
)

(defun gtp:model-catalogue-valve (component catalogue / p d len body p0 p1 flange)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq len (gtp:mm (gtp:catalogue-get catalogue 'length-mm)))
  (setq body (gtp:mm (gtp:valve-body-diameter-mm catalogue)))
  (setq p0 (gtp:vsub p (gtp:vscale d (/ len 2.0))))
  (setq p1 (gtp:vadd p (gtp:vscale d (/ len 2.0))))
  (setq flange (* 1.20 body))
  (gtp:make-cylinder p0 p1 body "GTP-VALVE-BODY")
  (gtp:make-cylinder p0 (gtp:vadd p0 (gtp:vscale d (min (gtp:mm 120.0) (* 0.10 len)))) flange "GTP-VALVE-BODY")
  (gtp:make-cylinder (gtp:vsub p1 (gtp:vscale d (min (gtp:mm 120.0) (* 0.10 len)))) p1 flange "GTP-VALVE-BODY")
  (if (member (gtp:catalogue-get catalogue 'family) '("SINGLE_SHUTOFF" "SINGLE_SHUTOFF_2VENT_DRAIN"))
    (gtp:place-single-valve-stems component catalogue)
    (gtp:place-twin-valve-stems component catalogue)
  )
)

(defun c:GTPVALVE (/ *error* old sel ent pick info pos dir row dn series family catalogue comp flow up id)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPVALVE error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (if (not (and (fboundp 'gtp:make-valve-component) (fboundp 'gtp:curve-point-direction)))
    (princ "\nLoad the component architecture first.")
    (progn
      (gtp:valve-layers)
      (setq sel (entsel "\nSelect route LINE / 2D or 3D POLYLINE: "))
      (if sel
        (progn
          (setq ent (car sel))
          (if (gtp:valid-route-p ent)
            (progn
              (setq pick (getpoint "\nPick valve centre on route: "))
              (if pick
                (progn
                  (setq pick (trans pick 1 0))
                  (if (gtp:valve-on-route-p ent pick)
                    (progn
                      (setq info (gtp:curve-point-direction ent pick))
                      (if info
                        (progn
                          (setq pos (car info) dir (cadr info))
                          (setq row (gtp:valve-dn-row))
                          (setq dn (car row))
                          (setq series (gtp:get-series))
                          (setq family (gtp:valve-family-prompt))
                          (setq row (gtp:valve-row-for-dn family dn))
                          (if row
                            (progn
                              (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                              (setq up '(0.0 0.0 1.0))
                              (if (> (abs (gtp:dot dir up)) 0.95) (setq up '(0.0 1.0 0.0)))
                              (setq catalogue (gtp:valve-catalogue-record family row series))
                              (setq id (strcat "VALVE-" (itoa *gtp-valve-next-id*)))
                              (setq comp (gtp:make-valve-component id flow dn series pos dir up (gtp:catalogue-get catalogue 'length-mm) catalogue nil))
                              (if (gtp:add-valve-component comp)
                                (progn
                                  (gtp:model-catalogue-valve comp catalogue)
                                  (princ (strcat "\nCreated " family " " id " | DN" (itoa dn) " | Series " (itoa series) " | L=" (rtos (gtp:catalogue-get catalogue 'length-mm) 2 0) " mm | " (gtp:valve-family-name family) "."))
                                  (princ "\nCatalogue-backed valve registered. GTPPIPE will split around its footprint."))
                                (princ "\nCould not register valve component."))
                            )
                            (princ (strcat "\nNo catalogue row exists for DN" (itoa dn) " in family " family ". Choose another family or DN."))
                          )
                        )
                        (princ "\nCould not determine route tangent."))
                    )
                    (princ "\nPick a point within 5 mm of the route."))
                )
              )
            )
            (princ "\nSelected object must be a LINE/POLYLINE."))
        )
        (princ "\nNothing selected."))
    )
  )
  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPVALVECATALOG (/ family db)
  (setq family (gtp:valve-family-prompt))
  (setq db (gtp:valve-db-for-family family))
  (princ (strcat "\nCatalogue: " family " | " (gtp:valve-family-name family)))
  (foreach row db
    (princ (strcat "\nCarrier OD " (rtos (car row) 2 1) " | L "
      (rtos
        (cond
          ((= family "SINGLE_SHUTOFF") (nth 10 row))
          ((= family "SINGLE_SHUTOFF_2VENT_DRAIN") (nth 13 row))
          ((= family "TWIN_SHUTOFF") (nth 12 row))
          (T (nth 9 row))
        ) 2 0) " mm"))
  )
  (princ)
)

; -----------------------------------------------------------------------------
; VALVE-AWARE CORNER ROUTE OVERRIDE
; -----------------------------------------------------------------------------
(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e spoolCount elbowCount clippedCount valveCount valveComponents system)
  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))
  (setq valveComponents (gtp:valve-aware-filter-components (if *gtp-valve-components* *gtp-valve-components* '())))
  (setq valveCount (length valveComponents))
  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component (gtp:make-elbow-component (strcat "ELBOW-" (itoa i)) system dn nil (nth (1- i) pts) (nth i pts) (nth (1+ i) pts) carrier casing style))
    )
    (if (and component (gtp:spec 'clipped (gtp:elbow-component-spec component))) (setq clippedCount (1+ clippedCount)))
    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts))
    (setq p2 (nth (1+ i) pts))
    (setq s (if (nth i elbows) (gtp:elbow-component-end (nth i elbows)) p1))
    (setq e (if (nth (1+ i) elbows) (gtp:elbow-component-start (nth (1+ i) elbows)) p2))
    (if (> (distance s e) 1e-8)
      (setq spoolCount (+ spoolCount (gtp:model-valve-aware-straight s e dn carrier casing mode valveComponents)))
    )
    (setq i (1+ i))
  )
  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows)
      (progn (setq component (nth i elbows)) (gtp:model-elbow-component component carrier casing mode) (setq elbowCount (1+ elbowCount)))
    )
    (setq i (1+ i))
  )
  (if (> valveCount 0) (princ (strcat "\nValve-aware routing: " (itoa valveCount) " registered valve component(s) considered for pipe splitting.")))
  (list spoolCount elbowCount clippedCount)
)

; -----------------------------------------------------------------------------
; PERSISTENT COMPONENT REGISTRY AND FITTINGS
; -----------------------------------------------------------------------------
(if (null *gtp-component-registry*) (setq *gtp-component-registry* '()))
(if (null *gtp-component-next-id*) (setq *gtp-component-next-id* 1))

(defun gtp:component-next-id (prefix / id)
  (setq id (strcat prefix "-" (itoa *gtp-component-next-id*)))
  (setq *gtp-component-next-id* (1+ *gtp-component-next-id*))
  id
)

(defun gtp:component-registry-add (component / id found)
  (if (and component (gtp:component-valid-p component))
    (progn
      (setq id (gtp:component-get component 'id))
      (setq found (gtp:component-find-id *gtp-component-registry* id))
      (if found
        (setq *gtp-component-registry*
          (mapcar '(lambda (c) (if (= (gtp:component-get c 'id) id) component c)) *gtp-component-registry*))
        (setq *gtp-component-registry* (append *gtp-component-registry* (list component)))
      )
      component
    )
  )
)

(defun gtp:component-registry-remove (id / out)
  (setq out '())
  (foreach component *gtp-component-registry*
    (if (/= (gtp:component-get component 'id) id) (setq out (append out (list component))))
  )
  (setq *gtp-component-registry* out)
)

(defun gtp:component-registry-by-type (type)
  (gtp:components-by-type *gtp-component-registry* type)
)

(defun gtp:persistence-root (/ nod root)
  (setq nod (namedobjdict))
  (setq root (dictsearch nod "GTP_COMPONENTS"))
  (if root
    (cdr (assoc -1 root))
    (progn
      (setq root (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary"))))
      (if root (dictadd nod "GTP_COMPONENTS" root))
      root
    )
  )
)

(defun gtp:persistence-id-valid-p (id)
  (and id (= (type id) 'STR) (> (strlen id) 0))
)

(defun gtp:persist-component (component / root id old xrec text)
  (if (and component (gtp:component-valid-p component))
    (progn
      (setq root (gtp:persistence-root))
      (setq id (gtp:component-get component 'id))
      (if (and root (gtp:persistence-id-valid-p id))
        (progn
          (setq old (dictsearch root id))
          (if old
            (progn
              (setq xrec (cdr (assoc -1 old)))
              (dictremove root id)
              (if xrec (entdel xrec))
            )
          )
          (setq text (vl-prin1-to-string component))
          (setq xrec (entmakex (list '(0 . "XRECORD") '(100 . "AcDbXrecord") (cons 1 text))))
          (if xrec (progn (dictadd root id xrec) T) nil)
        )
        nil
      )
    )
    nil
  )
)

(defun gtp:persistence-read-record (xrec / data text value)
  (setq data (entget xrec))
  (setq text (cdr (assoc 1 data)))
  (if text
    (progn
      (setq value (vl-catch-all-apply 'read (list text)))
      (if (vl-catch-all-error-p value) nil value)
    )
    nil
  )
)

(defun gtp:load-persisted-components (/ root pair xrec component loaded)
  (setq loaded '())
  (setq root (gtp:persistence-root))
  (if root
    (progn
      (setq pair (dictnext root T))
      (while pair
        (setq xrec (cdr (assoc 350 pair)))
        (if xrec
          (progn
            (setq component (gtp:persistence-read-record xrec))
            (if (and component (gtp:component-valid-p component)) (setq loaded (append loaded (list component))))
          )
        )
        (setq pair (dictnext root))
      )
    )
  )
  (setq *gtp-component-registry* loaded)
  loaded
)

(defun gtp:persist-all-components (/ component count)
  (setq count 0)
  (foreach component *gtp-component-registry*
    (if (gtp:persist-component component) (setq count (1+ count)))
  )
  count
)

(defun gtp:sync-valve-registry-from-components (/ component valves maxid id n dash)
  (setq valves '() maxid 0)
  (foreach component *gtp-component-registry*
    (if (= (gtp:component-get component 'type) "VALVE") (setq valves (append valves (list component))))
    (setq id (gtp:component-get component 'id))
    (setq dash (and id (vl-string-search "-" id)))
    (if (and dash (wcmatch id "VALVE-*,REDUCER-*,TEE-*,BRANCH-*,END_CAP-*"))
      (progn
        (setq n (atoi (substr id (+ dash 2))))
        (if (> n maxid) (setq maxid n))
      )
    )
  )
  (setq *gtp-valve-components* valves)
  (if (> maxid (1- *gtp-component-next-id*)) (setq *gtp-component-next-id* (1+ maxid)))
  valves
)

(defun gtp:register-persistent-component (component)
  (if (gtp:component-registry-add component)
    (progn (gtp:persist-component component) component)
  )
)

(defun gtp:component-store-command-message (component)
  (princ (strcat "\nStored " (gtp:component-get component 'type) " " (gtp:component-get component 'id) " in the DWG component registry."))
)

(defun gtp:add-valve-component (component)
  (if (gtp:component-valid-p component)
    (progn
      (if (null *gtp-valve-components*) (setq *gtp-valve-components* '()))
      (setq *gtp-valve-components*
        (append
          (vl-remove-if '(lambda (c) (= (gtp:component-get c 'id) (gtp:component-get component 'id))) *gtp-valve-components*)
          (list component)))
      (gtp:component-registry-add component)
      (gtp:persist-component component)
      component
    )
  )
)

(setq *gtp-reducer-single-db*
  '(
    (26.9 33.7 90 110 110 125 125 140 1500)
    (26.9 42.4 90 110 110 125 125 140 1500)
    (33.7 42.4 90 110 110 125 125 140 1500)
    (33.7 48.3 90 110 110 125 125 140 1500)
    (42.4 48.3 110 110 125 125 140 140 1500)
    (42.4 60.3 110 125 125 140 140 160 1500)
    (48.3 60.3 110 125 125 140 140 160 1500)
    (48.3 76.1 110 140 125 160 140 180 1500)
    (60.3 76.1 125 140 140 160 160 180 1500)
    (60.3 88.9 125 160 140 180 160 200 1500)
    (76.1 88.9 140 160 160 180 180 200 1500)
    (76.1 114.3 140 200 160 225 180 250 1500)
    (88.9 114.3 160 200 180 225 200 250 1500)
    (88.9 139.7 160 225 180 250 200 280 1500)
    (114.3 139.7 200 225 225 250 250 280 1500)
    (114.3 168.3 200 250 225 280 250 315 1500)
    (139.7 168.3 225 250 250 280 280 315 1500)
    (139.7 219.1 225 315 250 355 280 400 1500)
    (168.3 219.1 250 315 280 355 315 400 1500)
    (168.3 273.0 250 400 280 450 315 500 1500)
    (219.1 273.0 315 400 355 450 400 500 1500)
    (219.1 323.9 315 450 355 500 400 560 1500)
    (273.0 323.9 400 450 450 500 500 560 1500)
  )
)

(setq *gtp-reducer-twin-db*
  '(
    (26.9 33.7 125 140 140 160 160 180 1500)
    (33.7 42.4 140 160 160 180 180 200 1500)
    (42.4 48.3 160 160 180 180 200 200 1500)
    (48.3 60.3 160 200 180 225 200 250 1500)
    (60.3 76.1 200 225 225 250 250 280 1500)
    (76.1 88.9 225 250 250 280 280 315 1500)
    (88.9 114.3 250 315 280 355 315 400 1500)
    (114.3 139.7 315 400 355 450 400 500 1500)
    (139.7 168.3 400 450 450 500 500 560 1500)
    (168.3 219.1 450 560 500 630 560 710 1500)
    (219.1 273.0 560 710 630 800 710 900 1500)
  )
)

(defun gtp:reducer-row-find (db small large / row)
  (setq row nil)
  (foreach r db
    (if (and (null row) (< (abs (- (car r) small)) 0.01) (< (abs (- (cadr r) large)) 0.01)) (setq row r))
  )
  row
)

(setq *gtp-branch-joint-length-mm* 700.0)
(setq *gtp-branch-single-range* '((90 140) (90 250)))
(setq *gtp-branch-twin-range* '((90 160) (90 250)))

(defun gtp:branch-range-p (branchOD mainOD / ok)
  (setq ok nil)
  (foreach r *gtp-branch-single-range*
    (if (and (>= branchOD (car r)) (<= branchOD (cadr r)) (>= mainOD 125.0) (<= mainOD 630.0)) (setq ok T))
  )
  ok
)

(defun gtp:make-end-cap-disc (center normal dia thickness layer / p2)
  (setq p2 (gtp:vadd center (gtp:vscale (gtp:vunit normal) thickness)))
  (gtp:make-cylinder center p2 dia layer)
)

(defun gtp:model-tee-component (component / p d bdir len body branchLen branchDia q1 q2 b1)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq body (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'main-body-od-mm)))
  (setq len (gtp:mm (gtp:component-get component 'length)))
  (setq bdir (gtp:component-get (gtp:component-get component 'options) 'branch-direction))
  (setq branchDia (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'branch-body-od-mm)))
  (setq branchLen (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'branch-length-mm)))
  (setq q1 (gtp:vsub p (gtp:vscale d (/ len 2.0))))
  (setq q2 (gtp:vadd p (gtp:vscale d (/ len 2.0))))
  (gtp:make-cylinder q1 q2 body "GTP-FITTING-BODY")
  (setq b1 (gtp:vadd p (gtp:vscale (gtp:vunit bdir) branchLen)))
  (gtp:make-cylinder p b1 branchDia "GTP-FITTING-BODY")
)

(defun gtp:model-reducer-component (component / p d len small large bodySmall bodyLarge q1 q2 mid dia1 dia2)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq len (gtp:mm (gtp:component-get component 'length)))
  (setq small (gtp:catalogue-get (gtp:component-get component 'catalogue) 'small-carrier-od-mm))
  (setq large (gtp:catalogue-get (gtp:component-get component 'catalogue) 'large-carrier-od-mm))
  (setq bodySmall (gtp:mm small))
  (setq bodyLarge (gtp:mm large))
  (setq q1 (gtp:vsub p (gtp:vscale d (/ len 2.0))))
  (setq q2 (gtp:vadd p (gtp:vscale d (/ len 2.0))))
  (setq mid (gtp:point-along q1 q2 (/ len 2.0)))
  (gtp:make-cylinder q1 mid bodySmall "GTP-FITTING-BODY")
  (gtp:make-cylinder mid q2 bodyLarge "GTP-FITTING-BODY")
  (setq dia1 bodySmall dia2 bodyLarge)
  (list dia1 dia2)
)

(defun gtp:model-branch-component (component / p bdir branchLen branchDia endp)
  (setq p (gtp:component-get component 'position))
  (setq bdir (gtp:vunit (gtp:catalogue-get (gtp:component-get component 'catalogue) 'branch-direction)))
  (setq branchLen (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'branch-length-mm)))
  (setq branchDia (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'branch-od-mm)))
  (setq endp (gtp:vadd p (gtp:vscale bdir branchLen)))
  (gtp:make-cylinder p endp branchDia "GTP-FITTING-BODY")
)

(defun gtp:model-end-cap-component (component / p d dia thickness endPoint)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq dia (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'casing-od-mm)))
  (setq thickness (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'thickness-mm)))
  (setq endPoint (gtp:vsub p (gtp:vscale d thickness)))
  (gtp:make-end-cap-disc endPoint d dia thickness "GTP-FITTING-BODY")
)

(defun c:GTPTEE (/ *error* old sel ent pick info row dn series flow up branchPt bdir bodyLen branchLen branchOD catalogue comp)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPTEE error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:ensure-layer "GTP-FITTING-BODY" 6)
  (setq sel (entsel "\nSelect main route LINE / POLYLINE: "))
  (if sel
    (progn
      (setq ent (car sel))
      (if (gtp:valid-route-p ent)
        (progn
          (setq pick (getpoint "\nPick tee centre on main route: "))
          (if pick
            (progn
              (setq pick (trans pick 1 0))
              (setq info (gtp:curve-point-direction ent pick))
              (if info
                (progn
                  (setq row (gtp:find-dn (getint "\nMain pipe DN: ")))
                  (if row
                    (progn
                      (setq dn (car row) series (gtp:get-series))
                      (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                      (setq up '(0.0 0.0 1.0))
                      (if (> (abs (gtp:dot (cadr info) up)) 0.95) (setq up '(0.0 1.0 0.0)))
                      (setq branchPt (getpoint pick "\nPick branch direction/end point: "))
                      (if branchPt
                        (progn
                          (setq bdir (gtp:vunit (gtp:vsub (trans branchPt 1 0) (car info))))
                          (setq bodyLen (getreal "\nTee main body length (mm) <500>: "))
                          (if (null bodyLen) (setq bodyLen 500.0))
                          (setq branchLen (getreal "\nTee branch length (mm) <500>: "))
                          (if (null branchLen) (setq branchLen 500.0))
                          (setq branchOD (getreal "\nBranch outside diameter (mm) <carrier OD>: "))
                          (if (null branchOD) (setq branchOD (nth 1 row)))
                          (setq catalogue (list (cons 'family "TEE_GENERIC") (cons 'dimension-source "USER_APPROVED_PROJECT_DIMENSIONS") (cons 'main-body-od-mm (nth 1 row)) (cons 'branch-body-od-mm branchOD) (cons 'branch-length-mm branchLen)))
                          (setq comp (gtp:make-generic-component (gtp:component-next-id "TEE") flow dn series (car info) (cadr info) up bodyLen catalogue (list (cons 'branch-direction bdir))))
                          (gtp:register-persistent-component comp)
                          (gtp:model-tee-component comp)
                          (gtp:component-store-command-message comp)
                        )
                        (princ "\nNothing selected for branch direction."))
                    )
                    (princ "\nMain DN is not in the current pipe database."))
                )
                (princ "\nCould not determine route tangent."))
            )
          )
        )
        (princ "\nSelected object must be a LINE/POLYLINE.")))
    (princ "\nNothing selected."))
  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPREDUCER (/ *error* old family small large row series flow route pick info dn catalogue comp)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPREDUCER error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:ensure-layer "GTP-FITTING-BODY" 6)
  (initget "SINGLE TWIN")
  (setq family (getkword "\nReducer type [SINGLE/TWIN] <SINGLE>: "))
  (if (null family) (setq family "SINGLE"))
  (setq small (getreal "\nSmaller carrier outside diameter (mm): "))
  (setq large (getreal "\nLarger carrier outside diameter (mm): "))
  (if (and small large (> large small))
    (progn
      (setq row (if (= family "SINGLE") (gtp:reducer-row-find *gtp-reducer-single-db* small large) (gtp:reducer-row-find *gtp-reducer-twin-db* small large)))
      (if row
        (progn
          (setq route (entsel "\nSelect route LINE / POLYLINE containing reducer: "))
          (if route
            (progn
              (setq pick (getpoint "\nPick reducer centre on route: "))
              (setq info (gtp:curve-point-direction (car route) (trans pick 1 0)))
              (if info
                (progn
                  (setq dn (getint "\nReducer larger-side DN (for component metadata): ")))
                  (if (null dn) (setq dn 0))
                  (setq series (gtp:get-series))
                  (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                  (setq catalogue (list (cons 'family (if (= family "SINGLE") "REDUCER_SINGLE" "REDUCER_TWIN")) (cons 'dimension-source (if (= family "SINGLE") "ISOPLUS_5.3_PAGE_80" "ISOPLUS_8.3_PAGE_116")) (cons 'small-carrier-od-mm small) (cons 'large-carrier-od-mm large) (cons 'length-mm 1500.0) (cons 'small-casing-s1-mm (nth 2 row)) (cons 'large-casing-s1-mm (nth 3 row))))
                  (setq comp (gtp:make-generic-component (gtp:component-next-id "REDUCER") flow dn series (car info) (cadr info) '(0.0 0.0 1.0) 1500.0 catalogue nil))
                  (gtp:register-persistent-component comp)
                  (gtp:model-reducer-component comp)
                  (gtp:component-store-command-message comp)
                )
                (princ "\nCould not determine route tangent."))
            )
            (princ "\nNothing selected."))
        )
        (princ "\nReducer pair is not present in the supplied ISOPLUS table."))
    )
    (princ "\nInvalid reducer diameters. Larger diameter must exceed smaller diameter."))
  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPBRANCH (/ *error* old sel ent pick info row dn series flow branchPt bdir branchOD branchLen catalogue comp)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPBRANCH error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:ensure-layer "GTP-FITTING-BODY" 6)
  (setq sel (entsel "\nSelect main route LINE / POLYLINE: "))
  (if sel
    (progn
      (setq ent (car sel))
      (if (gtp:valid-route-p ent)
        (progn
          (setq pick (getpoint "\nPick branch connection point on main route: "))
          (setq info (gtp:curve-point-direction ent (trans pick 1 0)))
          (if info
            (progn
              (setq row (gtp:find-dn (getint "\nMain pipe DN: ")))
              (if row
                (progn
                  (setq dn (car row) series (gtp:get-series))
                  (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                  (setq branchPt (getpoint (car info) "\nPick branch endpoint/direction: "))
                  (if branchPt
                    (progn
                      (setq bdir (gtp:vunit (gtp:vsub (trans branchPt 1 0) (car info))))
                      (setq branchOD (getreal "\nBranch outside diameter (mm) <90>: "))
                      (if (null branchOD) (setq branchOD 90.0))
                      (setq branchLen (getreal "\nBranch model length (mm) <700>: "))
                      (if (null branchLen) (setq branchLen *gtp-branch-joint-length-mm*))
                      (setq catalogue (list (cons 'family "WELDABLE_BRANCH") (cons 'dimension-source "ISOPLUS_16.12_REFERENCE") (cons 'main-joint-length-mm *gtp-branch-joint-length-mm*) (cons 'branch-od-mm branchOD) (cons 'branch-length-mm branchLen) (cons 'branch-direction bdir)))
                      (setq comp (gtp:make-generic-component (gtp:component-next-id "BRANCH") flow dn series (car info) (cadr info) '(0.0 0.0 1.0) *gtp-branch-joint-length-mm* catalogue nil))
                      (gtp:register-persistent-component comp)
                      (gtp:model-branch-component comp)
                      (gtp:component-store-command-message comp)
                      (if (not (gtp:branch-range-p branchOD (nth 2 row))) (princ "\nGTP warning: branch diameter/main casing combination is outside the basic catalogue reference range."))
                    )
                  )
                )
                (princ "\nMain DN is not in the current pipe database."))
            )
            (princ "\nCould not determine route tangent."))
        )
        (princ "\nSelected object must be a LINE/POLYLINE.")))
    (princ "\nNothing selected."))
  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPENDCAP (/ *error* old sel ent choice pts row dn series flow casing catalogue thickness comp endpoint dir)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPENDCAP error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:ensure-layer "GTP-FITTING-BODY" 6)
  (setq sel (entsel "\nSelect route LINE / POLYLINE for end cap: "))
  (if sel
    (progn
      (setq ent (car sel))
      (if (gtp:valid-route-p ent)
        (progn
          (initget "Start End")
          (setq choice (getkword "\nCap route end [Start/End] <End>: "))
          (if (null choice) (setq choice "End"))
          (setq pts (gtp:curve-points ent))
          (if (> (length pts) 1)
            (progn
              (if (= choice "Start")
                (setq endpoint (car pts) dir (gtp:vunit (gtp:vsub (cadr pts) (car pts))))
                (setq endpoint (gtp:last-item pts) dir (gtp:vunit (gtp:vsub (gtp:last-item pts) (nth (- (length pts) 2) pts))))
              )
              (setq row (gtp:find-dn (getint "\nPipe DN: ")))
              (if row
                (progn
                  (setq dn (car row) series (gtp:get-series))
                  (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                  (setq casing (getreal "\nCasing outside diameter (mm) <catalogue series>: "))
                  (if (null casing) (setq casing (gtp:casing-od row series)))
                  (setq thickness (getreal "\nCap thickness / axial length (mm) <25>: "))
                  (if (null thickness) (setq thickness 25.0))
                  (setq catalogue (list (cons 'family "END_CAP") (cons 'dimension-source "ISOPLUS_17.2_TO_17.5_REFERENCE") (cons 'casing-od-mm casing) (cons 'thickness-mm thickness)))
                  (setq comp (gtp:make-generic-component (gtp:component-next-id "END_CAP") flow dn series endpoint dir '(0.0 0.0 1.0) thickness catalogue nil))
                  (gtp:register-persistent-component comp)
                  (gtp:model-end-cap-component comp)
                  (gtp:component-store-command-message comp)
                )
                (princ "\nPipe DN is not in the current database."))
            )
            (princ "\nRoute has insufficient vertices."))
        )
        (princ "\nSelected object must be a LINE/POLYLINE.")))
    (princ "\nNothing selected."))
  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPCOMPONENTS (/ count)
  (setq count (length *gtp-component-registry*))
  (princ (strcat "\nPersistent GTP components: " (itoa count)))
  (if (> count 0) (princ (strcat "\n" (gtp:components-summary *gtp-component-registry*))))
  (princ)
)

(defun c:GTPCOMPONENTRELOAD (/ loaded)
  (setq loaded (gtp:load-persisted-components))
  (gtp:sync-valve-registry-from-components)
  (princ (strcat "\nReloaded " (itoa (length loaded)) " persistent component(s) from DWG."))
  (princ)
)

(defun c:GTPCOMPONENTSAVE (/ count)
  (setq count (gtp:persist-all-components))
  (princ (strcat "\nPersisted " (itoa count) " component(s) to the DWG registry."))
  (princ)
)

; -----------------------------------------------------------------------------
; GTPPIPE
; -----------------------------------------------------------------------------
(defun c:GTPPIPE (/ *error* old ent typ row dn series carrierMM casingMM carrier casing mode flowType style rawPts cleanInfo pts dupRemoved straightRemoved result)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPPIPE error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)
  (setq ent (car (entsel "\nSelect prepared route LINE / 2D or 3D POLYLINE: ")))
  (if ent
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (if (member typ '("LINE" "LWPOLYLINE" "POLYLINE"))
        (progn
          (gtp:setup-units)
          (setq row (gtp:get-dn))
          (setq dn (nth 0 row))
          (setq carrierMM (nth 1 row))
          (setq series (gtp:get-series))
          (setq casingMM (gtp:casing-od row series))
          (setq carrier (gtp:mm carrierMM))
          (setq casing (gtp:mm casingMM))
          (setq mode (gtp:get-mode))
          (setq flowType (gtp:get-flow-type))
          (setq style (gtp:get-elbow-style))
          (setq rawPts (gtp:curve-points ent))
          (if (and rawPts (>= (length rawPts) 2))
            (progn
              (setq cleanInfo (gtp:safe-simplify-route-points rawPts))
              (setq pts (nth 0 cleanInfo))
              (setq dupRemoved (nth 1 cleanInfo))
              (setq straightRemoved (nth 2 cleanInfo))
              (princ (strcat "\nRoute cleanup: " (itoa (length rawPts)) " input vertex/vertices -> " (itoa (length pts)) " modelling vertex/vertices."))
              (if (> (+ dupRemoved straightRemoved) 0)
                (princ (strcat " Ignored " (itoa dupRemoved) " duplicate and " (itoa straightRemoved) " nearly-collinear intermediate point(s).")))
              (princ "\nGenerating 3D pipe...")
              (setq result (gtp:model-corner-route pts dn carrier casing mode style))
              (princ (strcat "\nCreated Isoplus DN" (itoa dn) " Series " (itoa series) " | " flowType " | " (itoa (nth 0 result)) " straight spool(s) | " (itoa (nth 1 result)) " 3D elbow(s)."))
              (if (> (nth 2 result) 0) (princ (strcat "\nNote: " (itoa (nth 2 result)) " elbow fitting leg(s) were shortened for available route length.")))
              (if (and (= (nth 0 result) 0) (= (nth 1 result) 0)) (princ "\nWarning: no pipe solids were generated from this route. Check that the selected route has non-zero length."))
            )
            (princ "\nCould not obtain route vertices.")
          )
        )
        (princ "\nGTPPIPE accepts LINE, LWPOLYLINE or POLYLINE.")
      )
    )
    (princ "\nNothing selected.")
  )
  (setvar "CMDECHO" old)
  (princ)
)

; -----------------------------------------------------------------------------
; MITER SUPPORT
; -----------------------------------------------------------------------------
(defun gtp:last-item (lst) (last lst))
(defun gtp:butlast (lst / out)
  (setq out '())
  (while (cdr lst) (setq out (append out (list (car lst)))) (setq lst (cdr lst)))
  out
)
(defun gtp:replace-first (lst value) (if lst (cons value (cdr lst)) (list value)))
(defun gtp:replace-last (lst value) (if lst (append (gtp:butlast lst) (list value)) (list value)))

(defun gtp:valid-route-p (ent / typ)
  (if ent
    (progn (setq typ (cdr (assoc 0 (entget ent)))) (member typ '("LINE" "LWPOLYLINE" "POLYLINE")))
    nil
  )
)

(defun gtp:end-info (pts pick / p0 pN d0 dN adj dir ordered)
  (setq p0 (car pts))
  (setq pN (gtp:last-item pts))
  (setq d0 (distance pick p0))
  (setq dN (distance pick pN))
  (if (<= d0 dN)
    (progn (setq adj (cadr pts)) (setq dir (gtp:vunit (gtp:vsub p0 adj))) (setq ordered (reverse pts)) (list (cons 'end p0) (cons 'dir dir) (cons 'ordered ordered) (cons 'len (distance p0 adj))))
    (progn (setq adj (nth (- (length pts) 2) pts)) (setq dir (gtp:vunit (gtp:vsub pN adj))) (setq ordered pts) (list (cons 'end pN) (cons 'dir dir) (cons 'ordered ordered) (cons 'len (distance pN adj))))
  )
)

(defun gtp:line-line-intersection (p1 u p2 v / w a b c d e den s t q1 q2)
  (setq u (gtp:vunit u))
  (setq v (gtp:vunit v))
  (setq w (gtp:vsub p1 p2))
  (setq a (gtp:dot u u))
  (setq b (gtp:dot u v))
  (setq c (gtp:dot v v))
  (setq d (gtp:dot u w))
  (setq e (gtp:dot v w))
  (setq den (- (* a c) (* b b)))
  (if (< (abs den) 1e-10)
    nil
    (progn
      (setq s (/ (- (* b e) (* c d)) den))
      (setq t (/ (- (* a e) (* b d)) den))
      (setq q1 (gtp:vadd p1 (gtp:vscale u s)))
      (setq q2 (gtp:vadd p2 (gtp:vscale v t)))
      (list (cons 'corner (mapcar '(lambda (x y) (/ (+ x y) 2.0)) q1 q2)) (cons 'gap (distance q1 q2)))
    )
  )
)

(defun gtp:make-3d-polyline (pts layer / head)
  (setq head (entmakex (list '(0 . "POLYLINE") '(100 . "AcDbEntity") (cons 8 layer) '(100 . "AcDb3dPolyline") (cons 10 '(0.0 0.0 0.0)) '(66 . 1) '(70 . 8))))
  (if head
    (progn
      (foreach p pts (entmakex (list '(0 . "VERTEX") '(100 . "AcDbEntity") (cons 8 layer) '(100 . "AcDbVertex") '(100 . "AcDb3dPolylineVertex") (cons 10 p) '(70 . 32))))
      (entmakex (list '(0 . "SEQEND") '(100 . "AcDbEntity") (cons 8 layer)))
      head
    )
  )
)

(defun gtp:miter-route-points (info1 info2 corner / a b)
  (setq a (gtp:replace-last (cdr (assoc 'ordered info1)) corner))
  (setq b (reverse (cdr (assoc 'ordered info2))))
  (setq b (gtp:replace-first b corner))
  (append a (cdr b))
)

(defun c:GTPMITER (/ *error* old sel1 sel2 ent1 ent2 pick1 pick2 pts1 pts2 info1 info2 ll corner gap tol route newEnt ss ans)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPMITER error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)
  (setq sel1 (entsel "\nSelect FIRST route near the end to connect: "))
  (if sel1
    (progn
      (setq ent1 (car sel1))
      (if (gtp:valid-route-p ent1)
        (progn
          (setq sel2 (entsel "\nSelect SECOND route near the end to connect: "))
          (if (and sel2 (/= ent1 (car sel2)) (gtp:valid-route-p (car sel2)))
            (progn
              (setq ent2 (car sel2))
              (setq pick1 (trans (cadr sel1) 1 0))
              (setq pick2 (trans (cadr sel2) 1 0))
              (setq pts1 (gtp:curve-points ent1))
              (setq pts2 (gtp:curve-points ent2))
              (if (and pts1 pts2 (>= (length pts1) 2) (>= (length pts2) 2))
                (progn
                  (setq info1 (gtp:end-info pts1 pick1))
                  (setq info2 (gtp:end-info pts2 pick2))
                  (setq ll (gtp:line-line-intersection (cdr (assoc 'end info1)) (cdr (assoc 'dir info1)) (cdr (assoc 'end info2)) (cdr (assoc 'dir info2))))
                  (if ll
                    (progn
                      (setq corner (cdr (assoc 'corner ll)))
                      (setq gap (cdr (assoc 'gap ll)))
                      (setq tol (max 1e-7 (* 0.002 (max (cdr (assoc 'len info1)) (cdr (assoc 'len info2))))))
                      (if (<= gap tol)
                        (progn
                          (setq route (gtp:miter-route-points info1 info2 corner))
                          (setq newEnt (gtp:make-3d-polyline route "GTP-PIPE-CENTRELINE"))
                          (if newEnt
                            (progn
                              (princ (strcat "\nMiter centreline created at (" (rtos (car corner) 2 4) ", " (rtos (cadr corner) 2 4) ", " (rtos (caddr corner) 2 4) ")."))
                              (initget "Keep Delete")
                              (setq ans (getkword "\nSource objects [Keep/Delete] <Keep>: "))
                              (if (null ans) (setq ans "Keep"))
                              (if (= ans "Delete") (progn (entdel ent1) (entdel ent2)))
                              (setq ss (ssadd))
                              (ssadd newEnt ss)
                              (sssetfirst nil ss)
                              (princ "\nNew centreline selected. Run GTPPIPE.")
                            )
                            (princ "\nCould not create joined 3D centreline.")
                          )
                        )
                        (princ (strcat "\nThe two selected axes are skew in 3D. Closest gap = " (rtos gap 2 6) "."))
                      )
                    )
                    (princ "\nSelected route ends are parallel/nearly parallel; no miter intersection exists.")
                  )
                )
                (princ "\nCould not read route vertices.")
              )
            )
            (princ "\nSecond selection must be a different LINE/POLYLINE."))
        )
        (princ "\nFirst selection must be a LINE/POLYLINE."))
    )
    (princ "\nNothing selected.")
  )
  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPMITTER () (c:GTPMITER))

(defun c:GTPHELP ()
  (princ "\nCommands loaded: GTPPIPE, GTPMITER, GTPMITTER, GTPUNITS, GTPLAYER, GTPHELP, GTPVALVE, GTPVALVESUMMARY, GTPVALVECATALOG, GTPTEE, GTPREDUCER, GTPBRANCH, GTPENDCAP, GTPCOMPONENTS, GTPCOMPONENTRELOAD, GTPCOMPONENTSAVE.")
  (princ)
)

; -----------------------------------------------------------------------------
; STARTUP RESTORE
; -----------------------------------------------------------------------------
(gtp:load-persisted-components)
(gtp:sync-valve-registry-from-components)

(princ "\n============================================================")
(princ "\nGTP_DH_TOOLKIT_ALL_IN_ONE loaded successfully.")
(princ "\nCombined pipe + elbow + valve + catalogue + fittings + persistence build.")
(princ "\nRun GTPHELP for available commands.")
(princ "\n============================================================")
(princ)
