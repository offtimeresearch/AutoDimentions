; GTP_DH_TOOLKIT.LSP
; Permanent AutoLISP toolkit for AutoCAD / AutoCAD Mechanical
; ONE FILE ONLY - update this file in place.
;
; Commands:
;   GTPPIPE   - Create Isoplus pre-insulated 3D pipe from a prepared route
;   GTPMITER  - Extend/trim two selected route ends to their axis intersection
;   GTPMITTER - Alias for GTPMITER
;   GTPUNITS  - Set/check catalogue-mm to drawing-unit conversion
;   GTPLAYER  - Create/check GTP layers
;   GTPHELP   - Show loaded commands
;
; Route rule:
;   GTPPIPE ignores duplicate and nearly-collinear intermediate route vertices.
;   Only real direction changes are treated as bend corners.
;   The original selected polyline is NOT modified.
;   Route cleanup is fail-safe: if cleanup fails, the original route is used.
;   True straight runs are still split by catalogue stock length for real spool joints.

(vl-load-com)

; -----------------------------------------------------------------------------
; CATALOGUE DATA - millimetres
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

; row = (DN shortLeg standardLeg)
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
  ; Make sure newly generated geometry cannot be hidden by a previous layer state.
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
    (progn (vla-put-Layer sol layer) sol)
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
  ; Protect the COMPLETE native sweep operation.  AutoCAD can reject either
  ; the temporary arc/profile construction or the final path sweep depending
  ; on drawing units and the orientation of a 3D bend.
  (setq obj
    (vl-catch-all-apply
      'gtp:sweep-arc
      (list center t1 normal tangent radius phi dia layer)
    )
  )
  (if (and obj (not (vl-catch-all-error-p obj)))
    (list obj)
    (progn
      ; Keep GTPPIPE running when the ActiveX sweep is unavailable.  The
      ; fallback is deliberately caught too, so one bad bend cannot cancel
      ; all otherwise-valid straight pipe solids.
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
      ; The Isoplus table gives the complete equal leg length L, measured from
      ; the theoretical corner to each fitting end.  It is NOT the bend radius.
      ; Use the catalogue's normal 3D bend as the preferred centre-line radius,
      ; then retain a real straight end inside L.  The previous implementation
      ; invented a 1.5D/0.6-casing radius and could subsequently force it below
      ; the casing radius, producing visibly tight or failed elbow sweeps.
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

      ; A swept circular casing cannot make a valid solid when its centre-line
      ; radius is smaller than approximately half its outside diameter.
      ; If the selected route is too short, omit this elbow instead of creating
      ; corrupt/folded solids.  The caller will leave the route as straight runs.
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
        ; Use the original adjacent triple. This is deliberately simple and
        ; avoids allowing a previously removed point to affect later testing.
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
      (setq out (append out (list (car (last cleaned)))))
      (list out duplicateRemoved straightRemoved)
    )
  )
)

(defun gtp:safe-simplify-route-points (pts / r)
  (setq r (vl-catch-all-apply 'gtp:simplify-route-points (list pts)))
  (if (or
        (vl-catch-all-error-p r)
        (null r)
        (null (car r))
        (< (length (car r)) 2)
      )
    (progn
      (princ "\nRoute cleanup warning: cleanup failed, so the original route vertices will be used.")
      (list pts 0 0)
    )
    r
  )
)

; -----------------------------------------------------------------------------
; CORNER ROUTE MODELLING
; -----------------------------------------------------------------------------
(defun gtp:model-corner-route (pts dn carrier casing mode style / n elbows i spec p1 p2 s e spoolCount elbowCount clippedCount)
  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)

  (while (< i n)
    (setq spec nil)
    (if (and (> i 0) (< i (1- n)))
      (setq spec
        (gtp:make-elbow-spec
          (nth (1- i) pts)
          (nth i pts)
          (nth (1+ i) pts)
          dn carrier casing style
        )
      )
    )
    (if (and spec (gtp:spec 'clipped spec))
      (setq clippedCount (1+ clippedCount))
    )
    (setq elbows (append elbows (list spec)))
    (setq i (1+ i))
  )

  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts))
    (setq p2 (nth (1+ i) pts))
    (setq s (if (nth i elbows) (gtp:spec 'end (nth i elbows)) p1))
    (setq e (if (nth (1+ i) elbows) (gtp:spec 'start (nth (1+ i) elbows)) p2))
    (if (> (distance s e) 1e-8)
      (setq spoolCount (+ spoolCount (gtp:model-segment s e carrier casing mode)))
    )
    (setq i (1+ i))
  )

  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows)
      (progn
        (gtp:model-elbow (nth i elbows) carrier casing mode)
        (setq elbowCount (1+ elbowCount))
      )
    )
    (setq i (1+ i))
  )

  (list spoolCount elbowCount clippedCount)
)

; =============================================================================
; COMMAND: GTPPIPE
; =============================================================================
(defun c:GTPPIPE (/ *error* old ent typ row dn series carrierMM casingMM carrier casing mode style rawPts cleanInfo pts dupRemoved straightRemoved result)
  (vl-load-com)

  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPPIPE error: " msg))
    )
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
          (setq style (gtp:get-elbow-style))

          (setq rawPts (gtp:curve-points ent))
          (if (and rawPts (>= (length rawPts) 2))
            (progn
              (setq cleanInfo (gtp:safe-simplify-route-points rawPts))
              (setq pts (nth 0 cleanInfo))
              (setq dupRemoved (nth 1 cleanInfo))
              (setq straightRemoved (nth 2 cleanInfo))

              (princ
                (strcat
                  "\nRoute cleanup: "
                  (itoa (length rawPts)) " input vertex/vertices -> "
                  (itoa (length pts)) " modelling vertex/vertices."
                )
              )
              (if (> (+ dupRemoved straightRemoved) 0)
                (princ
                  (strcat
                    " Ignored "
                    (itoa dupRemoved) " duplicate and "
                    (itoa straightRemoved)
                    " nearly-collinear intermediate point(s)."
                  )
                )
              )

              (princ "\nGenerating 3D pipe...")
              (setq result (gtp:model-corner-route pts dn carrier casing mode style))

              (princ
                (strcat
                  "\nCreated Isoplus DN" (itoa dn)
                  " Series " (itoa series)
                  " | " (itoa (nth 0 result)) " straight spool(s)"
                  " | " (itoa (nth 1 result)) " 3D elbow(s)."
                )
              )
              (if (> (nth 2 result) 0)
                (princ
                  (strcat
                    "\nNote: " (itoa (nth 2 result))
                    " elbow fitting leg(s) were shortened for available route length."
                  )
                )
              )
              (if (and (= (nth 0 result) 0) (= (nth 1 result) 0))
                (princ "\nWarning: no pipe solids were generated from this route. Check that the selected route has non-zero length.")
              )
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
; MITER HELPERS
; -----------------------------------------------------------------------------
(defun gtp:last-item (lst) (car (last lst)))

(defun gtp:butlast (lst / out)
  (setq out '())
  (while (cdr lst)
    (setq out (append out (list (car lst))))
    (setq lst (cdr lst))
  )
  out
)

(defun gtp:replace-first (lst value)
  (if lst (cons value (cdr lst)) (list value))
)

(defun gtp:replace-last (lst value)
  (if lst (append (gtp:butlast lst) (list value)) (list value))
)

(defun gtp:valid-route-p (ent / typ)
  (if ent
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (member typ '("LINE" "LWPOLYLINE" "POLYLINE"))
    )
    nil
  )
)

(defun gtp:end-info (pts pick / p0 pN d0 dN adj dir ordered)
  (setq p0 (car pts))
  (setq pN (gtp:last-item pts))
  (setq d0 (distance pick p0))
  (setq dN (distance pick pN))
  (if (<= d0 dN)
    (progn
      (setq adj (cadr pts))
      (setq dir (gtp:vunit (gtp:vsub p0 adj)))
      (setq ordered (reverse pts))
      (list
        (cons 'end p0)
        (cons 'dir dir)
        (cons 'ordered ordered)
        (cons 'len (distance p0 adj))
      )
    )
    (progn
      (setq adj (nth (- (length pts) 2) pts))
      (setq dir (gtp:vunit (gtp:vsub pN adj)))
      (setq ordered pts)
      (list
        (cons 'end pN)
        (cons 'dir dir)
        (cons 'ordered ordered)
        (cons 'len (distance pN adj))
      )
    )
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
      (list
        (cons 'corner (mapcar '(lambda (x y) (/ (+ x y) 2.0)) q1 q2))
        (cons 'gap (distance q1 q2))
      )
    )
  )
)

(defun gtp:make-3d-polyline (pts layer / head)
  (setq head
    (entmakex
      (list
        '(0 . "POLYLINE")
        '(100 . "AcDbEntity")
        (cons 8 layer)
        '(100 . "AcDb3dPolyline")
        (cons 10 '(0.0 0.0 0.0))
        '(66 . 1)
        '(70 . 8)
      )
    )
  )
  (if head
    (progn
      (foreach p pts
        (entmakex
          (list
            '(0 . "VERTEX")
            '(100 . "AcDbEntity")
            (cons 8 layer)
            '(100 . "AcDbVertex")
            '(100 . "AcDb3dPolylineVertex")
            (cons 10 p)
            '(70 . 32)
          )
        )
      )
      (entmakex
        (list
          '(0 . "SEQEND")
          '(100 . "AcDbEntity")
          (cons 8 layer)
        )
      )
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

; =============================================================================
; COMMAND: GTPMITER
; =============================================================================
(defun c:GTPMITER (/ *error* old sel1 sel2 ent1 ent2 pick1 pick2 pts1 pts2 info1 info2 ll corner gap tol route newEnt ss ans)
  (vl-load-com)

  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPMITER error: " msg))
    )
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
                  (setq ll
                    (gtp:line-line-intersection
                      (cdr (assoc 'end info1))
                      (cdr (assoc 'dir info1))
                      (cdr (assoc 'end info2))
                      (cdr (assoc 'dir info2))
                    )
                  )

                  (if ll
                    (progn
                      (setq corner (cdr (assoc 'corner ll)))
                      (setq gap (cdr (assoc 'gap ll)))
                      (setq tol
                        (max
                          1e-7
                          (* 0.002
                            (max
                              (cdr (assoc 'len info1))
                              (cdr (assoc 'len info2))
                            )
                          )
                        )
                      )

                      (if (<= gap tol)
                        (progn
                          (setq route (gtp:miter-route-points info1 info2 corner))
                          (setq newEnt (gtp:make-3d-polyline route "GTP-PIPE-CENTRELINE"))

                          (if newEnt
                            (progn
                              (princ
                                (strcat
                                  "\nMiter centreline created at ("
                                  (rtos (car corner) 2 4) ", "
                                  (rtos (cadr corner) 2 4) ", "
                                  (rtos (caddr corner) 2 4) ")."
                                )
                              )
                              (initget "Keep Delete")
                              (setq ans (getkword "\nSource objects [Keep/Delete] <Keep>: "))
                              (if (null ans) (setq ans "Keep"))
                              (if (= ans "Delete")
                                (progn (entdel ent1) (entdel ent2))
                              )
                              (setq ss (ssadd))
                              (ssadd newEnt ss)
                              (sssetfirst nil ss)
                              (princ "\nNew centreline selected. Run GTPPIPE.")
                            )
                            (princ "\nCould not create joined 3D centreline.")
                          )
                        )
                        (princ
                          (strcat
                            "\nThe two selected axes are skew in 3D. Closest gap = "
                            (rtos gap 2 6) "."
                          )
                        )
                      )
                    )
                    (princ "\nSelected route ends are parallel/nearly parallel; no miter intersection exists.")
                  )
                )
                (princ "\nCould not read route vertices.")
              )
            )
            (princ "\nSecond selection must be a different LINE/POLYLINE.")
          )
        )
        (princ "\nFirst selection must be a LINE/POLYLINE.")
      )
    )
    (princ "\nNothing selected.")
  )

  (setvar "CMDECHO" old)
  (princ)
)

(defun c:GTPMITTER () (c:GTPMITER))

(defun c:GTPHELP ()
  (princ "\nCommands loaded: GTPPIPE, GTPMITER, GTPMITTER, GTPUNITS, GTPLAYER, GTPHELP.")
  (princ)
)

(princ "\nGTP_DH_TOOLKIT.lsp loaded successfully.")
(princ "\nCommands: GTPPIPE, GTPMITER (GTPMITTER), GTPUNITS, GTPLAYER, GTPHELP.")
(princ)
