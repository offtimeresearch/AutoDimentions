; GTP_DH_TOOLKIT_V1_8.LSP
; Greentropy buried district-heating pipe modeller for AutoCAD / AutoCAD Mechanical
; Manufacturer data source: Isoplus Product Catalogue 11/2024
;
; Commands:
;   GTPPIPE    - Create Isoplus pre-insulated pipe along LINE / 2D or 3D polyline
;   GTPUNITS   - Set/check catalogue-mm to drawing-unit conversion
;   GTPPINFO   - Read stored GTP pipe metadata
;   GTPLAYER   - Create / repair GTP layers
;
; V1.8 notes:
; - Corrects the WELD-POINT interpretation shown in the user's marked-up route:
;     P0->P1 = incoming straight axis
;     P1->P2 = weld-to-weld bookkeeping chord (NOT a pipe route)
;     P2->P3 = outgoing straight axis
; - When the incoming/outgoing axes form a 45/90 degree bend, they are extended
;   to a virtual corner and one elbow is generated between the two weld points.
; - The diagonal/chord between the elbow welds is never used as the physical pipe
;   path for a recognised bend.
; - Removes V1.6/V1.7's over-restrictive catalogue-leg-distance rejection.
; - Allows realistic small 3D drafting/elevation mismatch when intersecting axes.
; - If AutoCAD rejects the smooth elbow operation, fallback geometry follows
;   P1->virtual-corner->P2 instead of drawing the diagonal chord.
; - Keeps the V1.4 unit-scale fix, V1.5 elbow solids, and Corners mode.
; - FULL mode creates carrier / insulation / casing on separate GTP layers.
; - CASING mode creates the outer casing plus the exposed carrier ends.
;
; AutoCAD Mechanical supports AutoLISP / Visual LISP in full AutoCAD-based installations.
; Load with APPLOAD, then run GTPPIPE.

(vl-load-com)

(setq *gtp-pipe-db*
  '(
    ; DN  carrier-OD  Series-1-jacket  Series-2-jacket  Series-3-jacket
    ; Source: Isoplus catalogue sections 5.1 / 5.1.1 / 5.1.2.
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
    (20   600.0 1000.0)
    (25   600.0 1000.0)
    (32   600.0 1000.0)
    (40   600.0 1000.0)
    (50   600.0 1000.0)
    (65   600.0 1000.0)
    (80   600.0 1000.0)
    (100  700.0 1000.0)
    (125  750.0 1000.0)
    (150  800.0 1000.0)
    (200  nil   1000.0)
    (250  nil   1000.0)
    (300  nil   1000.0)
    (350  nil   1000.0)
    (400  nil   1000.0)
    (450  nil   1100.0)
    (500  nil   1200.0)
    (600  nil   1300.0)
  )
)

(setq *gtp-max-pipe-length-mm* 12000.0)
(setq *gtp-end-cutback-mm*       220.0)
(setq *gtp-bend-angle-tol-deg*      12.0)
(setq *gtp-mm-to-du*               1.0)
(setq *gtp-drawing-unit-name*      "millimetres")

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
    ((= u 21) (list "US survey feet" (/ 3937.0 1200000.0)))
    ((= u 22) (list "US survey inches" (/ 3937.0 100000.0)))
    ((= u 23) (list "US survey yards" (/ 3937.0 3600000.0)))
    (T nil)
  )
)

(defun gtp:manual-unit-info (/ s)
  (initget "MM CM M Inch Feet")
  (setq s (getkword "\nDrawing geometry unit [MM/CM/M/Inch/Feet] <MM>: "))
  (if (null s) (setq s "MM"))
  (cond
    ((= s "MM")   (list "millimetres" 1.0))
    ((= s "CM")   (list "centimetres" 0.1))
    ((= s "M")    (list "metres" 0.001))
    ((= s "Inch") (list "inches" (/ 1.0 25.4)))
    ((= s "Feet") (list "feet" (/ 1.0 304.8)))
  )
)

(defun gtp:setup-units (/ src info iu)
  (initget "Auto MM CM M Inch Feet")
  (setq src (getkword "\nCatalogue is in mm. Drawing unit source [Auto/MM/CM/M/Inch/Feet] <Auto>: "))
  (if (null src) (setq src "Auto"))
  (cond
    ((= src "Auto")
      (setq iu (getvar "INSUNITS") info (gtp:unit-info-from-insunits iu))
      (if (null info)
        (progn
          (princ (strcat "\nINSUNITS=" (itoa iu) " is unitless/unsupported, so Auto cannot determine the scale."))
          (setq info (gtp:manual-unit-info))
        )
      )
    )
    ((= src "MM")   (setq info (list "millimetres" 1.0)))
    ((= src "CM")   (setq info (list "centimetres" 0.1)))
    ((= src "M")    (setq info (list "metres" 0.001)))
    ((= src "Inch") (setq info (list "inches" (/ 1.0 25.4))))
    ((= src "Feet") (setq info (list "feet" (/ 1.0 304.8))))
  )
  (setq *gtp-drawing-unit-name* (car info) *gtp-mm-to-du* (cadr info))
  (princ (strcat "\nGTP scale: 1 catalogue mm = " (rtos *gtp-mm-to-du* 2 8) " drawing unit(s) [" *gtp-drawing-unit-name* "]."))
  info
)

(defun gtp:mm (value-mm) (* value-mm *gtp-mm-to-du*))
(defun c:GTPUNITS (/ info)
  (setq info (gtp:setup-units))
  (if info (princ (strcat "\nCurrent GTP conversion set for " *gtp-drawing-unit-name* ". Example: 1000 mm -> " (rtos (gtp:mm 1000.0) 2 6) " drawing units.")))
  (princ)
)

(defun gtp:ensure-layer (name color / doc lays lay)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) lays (vla-get-Layers doc))
  (if (tblsearch "LAYER" name) (setq lay (vla-Item lays name)) (setq lay (vla-Add lays name)))
  (if color (vla-put-Color lay color))
  lay
)

(defun gtp:layers ()
  (gtp:ensure-layer "GTP-PIPE-CASING" 8)
  (gtp:ensure-layer "GTP-PIPE-INSULATION" 2)
  (gtp:ensure-layer "GTP-PIPE-CARRIER" 1)
  (gtp:ensure-layer "GTP-PIPE-CENTRELINE" 4)
  (princ)
)

(defun c:GTPLAYER () (gtp:layers) (princ "\nGTP district-heating layers created/checked.") (princ))
(defun gtp:find-dn (dn) (assoc dn *gtp-pipe-db*))
(defun gtp:casing-od (row series) (cond ((= series 1) (nth 2 row)) ((= series 2) (nth 3 row)) ((= series 3) (nth 4 row))))

(defun gtp:list-dns (/ s r)
  (setq s "")
  (foreach r *gtp-pipe-db* (setq s (strcat s (itoa (car r)) " ")))
  s
)

(defun gtp:get-dn (/ dn row)
  (setq row nil)
  (while (not row)
    (setq dn (getint (strcat "\nNominal pipe size DN [" (gtp:list-dns) "]: ")))
    (if dn (setq row (gtp:find-dn dn)))
    (if (and dn (not row)) (princ "\nThat DN is not in the current Isoplus database."))
  )
  row
)

(defun gtp:get-series (/ s)
  (initget "1 2 3")
  (setq s (getkword "\nInsulation series [1/2/3] <2>: "))
  (if (null s) 2 (atoi s))
)

(defun gtp:get-mode (/ m)
  (initget "CASING FULL")
  (setq m (getkword "\nModel mode [CASING/FULL] <CASING>: "))
  (if (null m) "CASING" m)
)

(defun gtp:get-elbow-style (/ s)
  (initget "Standard Short")
  (setq s (getkword "\nElbow leg [Standard/Short] <Standard>: "))
  (if (null s) "Standard" s)
)

(defun gtp:get-route-definition (/ s)
  (initget "WeldPoints Corners")
  (setq s (getkword "\nPolyline vertices represent [WeldPoints/Corners] <WeldPoints>: "))
  (if (null s) "WeldPoints" s)
)

(defun gtp:elbow-leg-mm (dn style / row short std)
  (setq row (assoc dn *gtp-elbow-db*))
  (if row
    (progn
      (setq short (nth 1 row) std (nth 2 row))
      (if (= style "Short") (if short short std) std)
    )
  )
)

(defun gtp:variant (lst)
  (vlax-make-variant (vlax-safearray-fill (vlax-make-safearray vlax-vbDouble '(0 . 2)) lst))
)

(defun gtp:vunit (v / m)
  (setq m (distance '(0.0 0.0 0.0) v))
  (if (> m 1e-12) (mapcar '(lambda (x) (/ x m)) v) '(0.0 0.0 1.0))
)

(defun gtp:cross (a b)
  (list
    (- (* (cadr a) (caddr b)) (* (caddr a) (cadr b)))
    (- (* (caddr a) (car b)) (* (car a) (caddr b)))
    (- (* (car a) (cadr b)) (* (cadr a) (car b)))
  )
)

(defun gtp:axis-matrix (p1 p2 / z ref x y mid)
  (setq z (gtp:vunit (mapcar '- p2 p1)) mid (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
  (if (> (abs (caddr z)) 0.999) (setq ref '(0.0 1.0 0.0)) (setq ref '(0.0 0.0 1.0)))
  (setq x (gtp:vunit (gtp:cross ref z)) y (gtp:cross z x))
  (list
    (list (car x) (car y) (car z) (car mid))
    (list (cadr x) (cadr y) (cadr z) (cadr mid))
    (list (caddr x) (caddr y) (caddr z) (caddr mid))
    (list 0.0 0.0 0.0 1.0)
  )
)

(defun gtp:make-cylinder (p1 p2 dia layer / doc ms len cyl)
  (setq len (distance p1 p2))
  (if (> len 1e-8)
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) ms (vla-get-ModelSpace doc)
            cyl (vla-AddCylinder ms (gtp:variant '(0.0 0.0 0.0)) (/ dia 2.0) len))
      (vla-TransformBy cyl (vlax-tmatrix (gtp:axis-matrix p1 p2)))
      (vla-put-Layer cyl layer)
      cyl
    )
  )
)

(defun gtp:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b)) (* (caddr a) (caddr b))))
(defun gtp:vmag (v) (sqrt (gtp:dot v v)))
(defun gtp:vsub (a b) (mapcar '- a b))
(defun gtp:vadd (p v) (mapcar '+ p v))
(defun gtp:vscale (v s) (mapcar '(lambda (x) (* x s)) v))
(defun gtp:tan (a / c) (setq c (cos a)) (if (< (abs c) 1e-12) 1e99 (/ (sin a) c)))
(defun gtp:rad->deg (a) (* a (/ 180.0 pi)))

(defun gtp:snap-bend-deg (deg / tol)
  (setq tol *gtp-bend-angle-tol-deg*)
  (cond ((<= (abs (- deg 90.0)) tol) 90.0)
        ((<= (abs (- deg 45.0)) tol) 45.0)
        (T nil))
)

(defun gtp:line-line-corner (p1 u p2 v / w a b c d e den s t q1 q2 mid gap)
  (setq u (gtp:vunit u) v (gtp:vunit v) w (gtp:vsub p1 p2)
        a (gtp:dot u u) b (gtp:dot u v) c (gtp:dot v v)
        d (gtp:dot u w) e (gtp:dot v w) den (- (* a c) (* b b)))
  (if (< (abs den) 1e-10)
    nil
    (progn
      (setq s (/ (- (* b e) (* c d)) den)
            t (/ (- (* a e) (* b d)) den)
            q1 (gtp:vadd p1 (gtp:vscale u s))
            q2 (gtp:vadd p2 (gtp:vscale v t))
            mid (mapcar '(lambda (x y) (/ (+ x y) 2.0)) q1 q2)
            gap (distance q1 q2))
      (list (cons 'corner mid) (cons 's s) (cons 't t) (cons 'gap gap))
    )
  )
)

(defun gtp:frame-z (origin z / ref x y)
  (setq z (gtp:vunit z))
  (if (> (abs (caddr z)) 0.999) (setq ref '(0.0 1.0 0.0)) (setq ref '(0.0 0.0 1.0)))
  (setq x (gtp:vunit (gtp:cross ref z)) y (gtp:cross z x))
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

(defun gtp:safe-delete (obj) (if obj (vl-catch-all-apply 'vla-Delete (list obj))))

(defun gtp:make-circle-region (center normal radius / doc ms cir arr regs reg)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) ms (vla-get-ModelSpace doc)
        cir (vla-AddCircle ms (gtp:variant '(0.0 0.0 0.0)) radius))
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

(defun gtp:arc-point (center x y radius a)
  (gtp:vadd center (gtp:vadd (gtp:vscale x (* radius (cos a))) (gtp:vscale y (* radius (sin a)))))
)

(defun gtp:make-arc-path (center t1 normal radius phi / doc ms x y arc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) ms (vla-get-ModelSpace doc)
        x (gtp:vunit (gtp:vsub t1 center)) y (gtp:cross normal x)
        arc (vla-AddArc ms (gtp:variant '(0.0 0.0 0.0)) radius 0.0 phi))
  (vla-TransformBy arc (vlax-tmatrix (gtp:frame-xyz center x y normal)))
  arc
)

(defun gtp:sweep-circle-on-arc (center t1 normal tangent radius phi dia layer / doc ms path reg sol)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) ms (vla-get-ModelSpace doc)
        path (gtp:make-arc-path center t1 normal radius phi)
        reg (gtp:make-circle-region t1 tangent (/ dia 2.0)))
  (if (and path reg)
    (setq sol (vl-catch-all-apply 'vla-AddExtrudedSolidAlongPath (list ms reg path))))
  (gtp:safe-delete reg)
  (gtp:safe-delete path)
  (if (or (null sol) (vl-catch-all-error-p sol)) nil (progn (vla-put-Layer sol layer) sol))
)

(defun gtp:segmented-arc-solids (center t1 normal radius phi dia layer / x y segs a0 a1 p0 p1 i o out)
  (setq x (gtp:vunit (gtp:vsub t1 center)) y (gtp:cross normal x)
        segs (max 8 (fix (+ 0.5 (* 18.0 (/ phi (/ pi 2.0)))))) i 0 out '())
  (while (< i segs)
    (setq a0 (* phi (/ (float i) segs)) a1 (* phi (/ (float (1+ i)) segs))
          p0 (gtp:arc-point center x y radius a0) p1 (gtp:arc-point center x y radius a1)
          o (gtp:make-cylinder p0 p1 dia layer))
    (if o (setq out (cons o out)))
    (setq i (1+ i))
  )
  (reverse out)
)

(defun gtp:add-xdata (obj dn series carrier casing mode / en data)
  (regapp "GTP_DH_PIPE")
  (setq en (vlax-vla-object->ename obj))
  (setq data (list (list -3 (list "GTP_DH_PIPE" (cons 1000 "ISOPLUS") (cons 1000 "STEEL_SINGLE")
                                  (cons 1070 dn) (cons 1070 series) (cons 1040 carrier)
                                  (cons 1040 casing) (cons 1000 mode)))))
  (entmod (append (entget en) data))
  (entupd en)
)

(defun gtp:add-xdata-many (objs dn series carrier casing mode)
  (foreach o objs (if o (gtp:add-xdata o dn series carrier casing mode)))
)

(defun gtp:model-arc-component (center t1 normal tangent radius phi dia layer dn series carrier casing tag / o objs)
  (setq o (gtp:sweep-circle-on-arc center t1 normal tangent radius phi dia layer))
  (if o
    (progn (gtp:add-xdata o dn series carrier casing tag) (list o))
    (progn
      (setq objs (gtp:segmented-arc-solids center t1 normal radius phi dia layer))
      (gtp:add-xdata-many objs dn series carrier casing (strcat tag "-SEGMENTED"))
      objs
    )
  )
)

(defun gtp:elbow-tag (phi / deg)
  (setq deg (gtp:rad->deg phi))
  (cond ((<= (abs (- deg 45.0)) 1.0) "45") ((<= (abs (- deg 90.0)) 1.0) "90") (T (strcat "CUSTOM-" (rtos deg 2 1))))
)

(defun gtp:make-elbow-spec (prev v next dn carrier casing style / d1 d2 cr cm dp phi deg legmm leg0 leg maxleg baseR maxR radius tang tanDist t1 t2 normal inward center fs fe clipped)
  (setq d1 (gtp:vunit (gtp:vsub v prev)) d2 (gtp:vunit (gtp:vsub next v))
        cr (gtp:cross d1 d2) cm (gtp:vmag cr) dp (gtp:dot d1 d2)
        phi (atan cm dp) deg (gtp:rad->deg phi))
  (if (or (< deg 1.0) (> deg 175.0) (< cm 1e-10)) nil
    (progn
      (setq normal (gtp:vunit cr) legmm (gtp:elbow-leg-mm dn style) leg0 (gtp:mm legmm)
            maxleg (min (* 0.45 (distance prev v)) (* 0.45 (distance v next)))
            leg (min leg0 maxleg) clipped (< leg (- leg0 1e-8))
            baseR (max (* 1.5 carrier) (* 0.60 casing))
            tang (gtp:tan (/ phi 2.0)) maxR (if (> tang 1e-10) (/ (* 0.90 leg) tang) baseR)
            radius (min baseR maxR))
      (if (< radius (* 0.55 casing)) (setq radius (max radius (* 0.30 casing))))
      (setq tanDist (* radius tang))
      (if (> tanDist (* 0.95 leg)) (setq tanDist (* 0.90 leg) radius (/ tanDist tang)))
      (setq fs (gtp:vadd v (gtp:vscale d1 (- leg))) fe (gtp:vadd v (gtp:vscale d2 leg))
            t1 (gtp:vadd v (gtp:vscale d1 (- tanDist))) t2 (gtp:vadd v (gtp:vscale d2 tanDist))
            inward (gtp:vunit (gtp:cross normal d1)) center (gtp:vadd t1 (gtp:vscale inward radius)))
      (list (cons 'leg leg) (cons 'legmm legmm) (cons 'radius radius) (cons 'phi phi)
            (cons 'd1 d1) (cons 'd2 d2) (cons 'normal normal) (cons 'start fs)
            (cons 'tan1 t1) (cons 'center center) (cons 'tan2 t2) (cons 'end fe)
            (cons 'tag (gtp:elbow-tag phi)) (cons 'clipped clipped))
    )
  )
)

(defun gtp:make-weld-elbow-spec (prev fs fe next dn carrier casing style / d1 d2 cr cm dp phi deg snap ll v leg1 leg2 gap gapTol baseR tang maxR radius tanDist t1 t2 normal inward center legmm)
  ; WELD-POINT RULE:
  ; prev->fs incoming axis, fs->fe is ONLY the chord between welds, fe->next outgoing axis.
  (if (or (< (distance prev fs) 1e-8) (< (distance fs fe) 1e-8) (< (distance fe next) 1e-8))
    nil
    (progn
      (setq d1 (gtp:vunit (gtp:vsub fs prev)) d2 (gtp:vunit (gtp:vsub next fe))
            cr (gtp:cross d1 d2) cm (gtp:vmag cr) dp (gtp:dot d1 d2)
            phi (atan cm dp) deg (gtp:rad->deg phi) snap (gtp:snap-bend-deg deg))
      (if (or (null snap) (< cm 1e-10))
        nil
        (progn
          (setq ll (gtp:line-line-corner fs d1 fe d2))
          (if (null ll)
            nil
            (progn
              (setq v (cdr (assoc 'corner ll)) leg1 (cdr (assoc 's ll))
                    leg2 (- (cdr (assoc 't ll))) gap (cdr (assoc 'gap ll))
                    gapTol (max (gtp:mm 100.0) (* 1.50 casing))
                    legmm (gtp:elbow-leg-mm dn style))
              (if (or (<= leg1 1e-8) (<= leg2 1e-8) (> gap gapTol))
                nil
                (progn
                  (setq normal (gtp:vunit cr) baseR (max (* 1.5 carrier) (* 0.60 casing))
                        tang (gtp:tan (/ phi 2.0))
                        maxR (if (> tang 1e-10) (/ (* 0.90 (min leg1 leg2)) tang) baseR)
                        radius (min baseR maxR))
                  (if (< radius (* 0.55 casing)) (setq radius (max radius (* 0.30 casing))))
                  (setq tanDist (* radius tang))
                  (if (> tanDist (* 0.95 (min leg1 leg2)))
                    (setq tanDist (* 0.90 (min leg1 leg2)) radius (/ tanDist tang)))
                  (setq t1 (gtp:vadd v (gtp:vscale d1 (- tanDist)))
                        t2 (gtp:vadd v (gtp:vscale d2 tanDist))
                        inward (gtp:vunit (gtp:cross normal d1))
                        center (gtp:vadd t1 (gtp:vscale inward radius)))
                  (list (cons 'leg (min leg1 leg2)) (cons 'legmm legmm)
                        (cons 'radius radius) (cons 'phi phi) (cons 'd1 d1) (cons 'd2 d2)
                        (cons 'normal normal) (cons 'start fs) (cons 'tan1 t1)
                        (cons 'center center) (cons 'tan2 t2) (cons 'end fe)
                        (cons 'tag (if (= snap 90.0) "90" "45"))
                        (cons 'measuredDeg deg) (cons 'virtualCorner v)
                        (cons 'gap gap) (cons 'clipped nil))
                )
              )
            )
          )
        )
      )
    )
  )
)

(defun gtp:spec (key spec) (cdr (assoc key spec)))

(defun gtp:model-elbow (spec dn series carrier casing mode / leg rad phi d1 d2 normal fs t1 center t2 fe cut1 cut2 straightAvail1 straightAvail2 cs ce o tag n)
  (setq leg (gtp:spec 'leg spec) rad (gtp:spec 'radius spec) phi (gtp:spec 'phi spec)
        d1 (gtp:spec 'd1 spec) d2 (gtp:spec 'd2 spec) normal (gtp:spec 'normal spec)
        fs (gtp:spec 'start spec) t1 (gtp:spec 'tan1 spec) center (gtp:spec 'center spec)
        t2 (gtp:spec 'tan2 spec) fe (gtp:spec 'end spec) tag (gtp:spec 'tag spec) n 0)
  (setq o (gtp:make-cylinder fs t1 carrier "GTP-PIPE-CARRIER"))
  (if o (progn (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CARRIER")) (setq n (1+ n))))
  (setq n (+ n (length (gtp:model-arc-component center t1 normal d1 rad phi carrier "GTP-PIPE-CARRIER" dn series carrier casing (strcat "ELBOW-" tag "-CARRIER")))))
  (setq o (gtp:make-cylinder t2 fe carrier "GTP-PIPE-CARRIER"))
  (if o (progn (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CARRIER")) (setq n (1+ n))))
  (setq straightAvail1 (distance fs t1) straightAvail2 (distance t2 fe)
        cut1 (gtp:mm *gtp-end-cutback-mm*) cut2 (gtp:mm *gtp-end-cutback-mm*))
  (if (> straightAvail1 1e-8) (setq cut1 (min cut1 (* 0.80 straightAvail1))) (setq cut1 0.0))
  (if (> straightAvail2 1e-8) (setq cut2 (min cut2 (* 0.80 straightAvail2))) (setq cut2 0.0))
  (setq cs (gtp:vadd fs (gtp:vscale d1 cut1)) ce (gtp:vadd fe (gtp:vscale d2 (- cut2))))
  (setq o (gtp:make-cylinder cs t1 casing "GTP-PIPE-CASING"))
  (if o (progn (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CASING")) (setq n (1+ n))))
  (setq n (+ n (length (gtp:model-arc-component center t1 normal d1 rad phi casing "GTP-PIPE-CASING" dn series carrier casing (strcat "ELBOW-" tag "-CASING")))))
  (setq o (gtp:make-cylinder t2 ce casing "GTP-PIPE-CASING"))
  (if o (progn (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CASING")) (setq n (1+ n))))
  (if (= mode "FULL")
    (progn
      (setq o (gtp:make-cylinder cs t1 casing "GTP-PIPE-INSULATION"))
      (if o (progn (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-INSULATION")) (setq n (1+ n))))
      (setq n (+ n (length (gtp:model-arc-component center t1 normal d1 rad phi casing "GTP-PIPE-INSULATION" dn series carrier casing (strcat "ELBOW-" tag "-INSULATION")))))
      (setq o (gtp:make-cylinder t2 ce casing "GTP-PIPE-INSULATION"))
      (if o (progn (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-INSULATION")) (setq n (1+ n))))
    )
  )
  n
)

(defun gtp:curve-points (ename / endp i pts p)
  (if (vl-catch-all-error-p (setq endp (vl-catch-all-apply 'vlax-curve-getEndParam (list ename)))) nil
    (progn
      (setq i 0 pts '())
      (while (<= i (fix endp))
        (setq p (vlax-curve-getPointAtParam ename i))
        (if p (setq pts (append pts (list p))))
        (setq i (1+ i))
      )
      pts
    )
  )
)

(defun gtp:point-along (p1 p2 dist / dir)
  (setq dir (gtp:vunit (mapcar '- p2 p1)))
  (gtp:vadd p1 (gtp:vscale dir dist))
)

(defun gtp:model-spool (p1 p2 dn series carrier casing mode / len cut c1 c2 o)
  (setq len (distance p1 p2) cut (gtp:mm *gtp-end-cutback-mm*))
  (if (>= (* 2.0 cut) len) (setq cut (/ len 4.0)))
  (setq c1 (gtp:point-along p1 p2 cut) c2 (gtp:point-along p1 p2 (- len cut)))
  (setq o (gtp:make-cylinder p1 p2 carrier "GTP-PIPE-CARRIER"))
  (if o (gtp:add-xdata o dn series carrier casing "CARRIER"))
  (if (> (distance c1 c2) 1e-8)
    (progn
      (setq o (gtp:make-cylinder c1 c2 casing "GTP-PIPE-CASING"))
      (if o (gtp:add-xdata o dn series carrier casing "CASING"))
      (if (= mode "FULL")
        (progn
          (setq o (gtp:make-cylinder c1 c2 casing "GTP-PIPE-INSULATION"))
          (if o (gtp:add-xdata o dn series carrier casing "INSULATION"))
        )
      )
    )
  )
)

(defun gtp:model-segment (p1 p2 dn series carrier casing mode / len dir pos remain piece s1 s2 count)
  (setq len (distance p1 p2) dir (gtp:vunit (mapcar '- p2 p1)) pos 0.0 count 0)
  (while (< pos (- len 1e-8))
    (setq remain (- len pos) piece (min (gtp:mm *gtp-max-pipe-length-mm*) remain)
          s1 (gtp:vadd p1 (gtp:vscale dir pos)) s2 (gtp:vadd p1 (gtp:vscale dir (+ pos piece))))
    (gtp:model-spool s1 s2 dn series carrier casing mode)
    (setq pos (+ pos piece) count (1+ count))
  )
  count
)

(defun gtp:take (lst n / out i)
  (setq out '() i 0)
  (while (and lst (< i n)) (setq out (append out (list (car lst))) lst (cdr lst) i (1+ i)))
  out
)
(defun gtp:drop (lst n / i)
  (setq i 0)
  (while (and lst (< i n)) (setq lst (cdr lst) i (1+ i)))
  lst
)
(defun gtp:set-nth (lst idx value) (append (gtp:take lst idx) (list value) (gtp:drop lst (1+ idx))))

(defun gtp:model-corner-route (pts dn series carrier casing mode elbowStyle / elbows npts i spec p1 p2 s e spoolCount elbowCount clippedCount shortFallbackCount)
  (setq npts (length pts) elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0 shortFallbackCount 0)
  (while (< i npts)
    (setq spec nil)
    (if (and (> i 0) (< i (1- npts)))
      (progn
        (setq spec (gtp:make-elbow-spec (nth (1- i) pts) (nth i pts) (nth (1+ i) pts) dn carrier casing elbowStyle))
        (if spec
          (progn
            (if (gtp:spec 'clipped spec) (setq clippedCount (1+ clippedCount)))
            (if (and (= elbowStyle "Short") (null (nth 1 (assoc dn *gtp-elbow-db*)))) (setq shortFallbackCount (1+ shortFallbackCount)))
          )
        )
      )
    )
    (setq elbows (append elbows (list spec)) i (1+ i))
  )
  (setq i 0)
  (while (< i (1- npts))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts)
          s (if (nth i elbows) (gtp:spec 'end (nth i elbows)) p1)
          e (if (nth (1+ i) elbows) (gtp:spec 'start (nth (1+ i) elbows)) p2))
    (if (> (distance s e) 1e-8) (setq spoolCount (+ spoolCount (gtp:model-segment s e dn series carrier casing mode))))
    (setq i (1+ i))
  )
  (setq i 1)
  (while (< i (1- npts))
    (if (nth i elbows) (progn (gtp:model-elbow (nth i elbows) dn series carrier casing mode) (setq elbowCount (1+ elbowCount))))
    (setq i (1+ i))
  )
  (list spoolCount elbowCount clippedCount shortFallbackCount)
)

(defun gtp:safe-weld-elbow-spec (prev fs fe next dn carrier casing style segno / r)
  (setq r (vl-catch-all-apply 'gtp:make-weld-elbow-spec (list prev fs fe next dn carrier casing style)))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\nWeldPoints: segment " (itoa segno) " bend check failed; keeping it as straight geometry. Reason: " (vl-catch-all-error-message r)))
      nil
    )
    r
  )
)

(defun gtp:model-weld-axis-fallback (spec dn series carrier casing mode / fs fe v o count)
  (setq fs (gtp:spec 'start spec) fe (gtp:spec 'end spec) v (gtp:spec 'virtualCorner spec) count 0)
  (if (and fs fe v)
    (progn
      (setq o (gtp:make-cylinder fs v carrier "GTP-PIPE-CARRIER"))
      (if o (progn (gtp:add-xdata o dn series carrier casing "ELBOW-AXIS-FALLBACK-CARRIER") (setq count (1+ count))))
      (setq o (gtp:make-cylinder v fe carrier "GTP-PIPE-CARRIER"))
      (if o (progn (gtp:add-xdata o dn series carrier casing "ELBOW-AXIS-FALLBACK-CARRIER") (setq count (1+ count))))
      (setq o (gtp:make-cylinder fs v casing "GTP-PIPE-CASING"))
      (if o (progn (gtp:add-xdata o dn series carrier casing "ELBOW-AXIS-FALLBACK-CASING") (setq count (1+ count))))
      (setq o (gtp:make-cylinder v fe casing "GTP-PIPE-CASING"))
      (if o (progn (gtp:add-xdata o dn series carrier casing "ELBOW-AXIS-FALLBACK-CASING") (setq count (1+ count))))
      (if (= mode "FULL")
        (progn
          (setq o (gtp:make-cylinder fs v casing "GTP-PIPE-INSULATION"))
          (if o (progn (gtp:add-xdata o dn series carrier casing "ELBOW-AXIS-FALLBACK-INSULATION") (setq count (1+ count))))
          (setq o (gtp:make-cylinder v fe casing "GTP-PIPE-INSULATION"))
          (if o (progn (gtp:add-xdata o dn series carrier casing "ELBOW-AXIS-FALLBACK-INSULATION") (setq count (1+ count))))
        )
      )
    )
  )
  count
)

(defun gtp:safe-model-weld-elbow (spec p1 p2 dn series carrier casing mode segno / r n)
  (setq r (vl-catch-all-apply 'gtp:model-elbow (list spec dn series carrier casing mode)))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\nWeldPoints: smooth elbow on segment " (itoa segno) " failed; using axis-correct corner fallback (NOT the weld chord). Reason: " (vl-catch-all-error-message r)))
      (setq n (gtp:model-weld-axis-fallback spec dn series carrier casing mode))
      (if (> n 0) 'FALLBACK nil)
    )
    T
  )
)

(defun gtp:model-weld-route (pts dn series carrier casing mode elbowStyle / npts segKinds specs i spec modelResult spoolCount elbowCount p1 p2 deg tag fallbackCount)
  (setq npts (length pts) segKinds '() specs '() i 0 spoolCount 0 elbowCount 0 fallbackCount 0)
  (repeat (1- npts)
    (setq segKinds (append segKinds (list "STRAIGHT")) specs (append specs (list nil))))
  (setq i 1)
  (while (< i (- npts 2))
    (setq spec (gtp:safe-weld-elbow-spec (nth (1- i) pts) (nth i pts) (nth (1+ i) pts) (nth (+ i 2) pts)
                                          dn carrier casing elbowStyle (1+ i)))
    (if spec
      (progn
        (setq segKinds (gtp:set-nth segKinds i "ELBOW") specs (gtp:set-nth specs i spec)
              deg (gtp:spec 'measuredDeg spec) tag (gtp:spec 'tag spec))
        (princ (strcat "\nDetected weld-to-weld " tag " deg bend at polyline segment " (itoa (1+ i))
                       " (axis turn " (rtos deg 2 1) " deg). The weld chord will NOT be modelled."))
        (setq i (+ i 2))
      )
      (setq i (1+ i))
    )
  )
  (setq i 0)
  (while (< i (1- npts))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts))
    (if (= (nth i segKinds) "ELBOW")
      (progn
        (setq modelResult (gtp:safe-model-weld-elbow (nth i specs) p1 p2 dn series carrier casing mode (1+ i)))
        (cond
          ((eq modelResult T) (setq elbowCount (1+ elbowCount)))
          ((eq modelResult 'FALLBACK) (setq elbowCount (1+ elbowCount) fallbackCount (1+ fallbackCount)))
          (T (princ (strcat "\nWeldPoints: elbow segment " (itoa (1+ i)) " could not be modelled. No diagonal pipe was created for this fitting span.")))
        )
      )
      (if (> (distance p1 p2) 1e-8)
        (setq spoolCount (+ spoolCount (gtp:model-segment p1 p2 dn series carrier casing mode)))
      )
    )
    (setq i (1+ i))
  )
  (if (> fallbackCount 0)
    (princ (strcat "\nWeldPoints: " (itoa fallbackCount) " detected fitting span(s) used axis-correct sharp-corner fallback because AutoCAD rejected the smooth 3D elbow.")))
  (list spoolCount elbowCount 0 0)
)

(defun c:GTPPIPE (/ *error* oldcmdecho ent typ row dn series carrierMM casingMM carrier casing mode elbowStyle routeDef pts result spoolCount elbowCount clippedCount shortFallbackCount)
  (vl-load-com)
  (defun *error* (msg)
    (if oldcmdecho (setvar "CMDECHO" oldcmdecho))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPPIPE error: " msg)))
    (princ)
  )
  (setq oldcmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)
  (setq ent (car (entsel "\nSelect route LINE / 2D or 3D POLYLINE: ")))
  (if (null ent) (princ "\nNothing selected.")
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (if (not (member typ '("LINE" "LWPOLYLINE" "POLYLINE"))) (princ "\nGTPPIPE accepts LINE, LWPOLYLINE or POLYLINE routes.")
        (progn
          (gtp:setup-units)
          (setq row (gtp:get-dn))
          (if row
            (progn
              (setq dn (nth 0 row) carrierMM (nth 1 row) series (gtp:get-series)
                    casingMM (gtp:casing-od row series) carrier (gtp:mm carrierMM) casing (gtp:mm casingMM)
                    mode (gtp:get-mode) elbowStyle (gtp:get-elbow-style) routeDef (gtp:get-route-definition)
                    pts (gtp:curve-points ent))
              (if (or (null pts) (< (length pts) 2)) (princ "\nCould not obtain route vertices.")
                (progn
                  (setq result (if (= routeDef "WeldPoints")
                                 (gtp:model-weld-route pts dn series carrier casing mode elbowStyle)
                                 (gtp:model-corner-route pts dn series carrier casing mode elbowStyle)))
                  (setq spoolCount (nth 0 result) elbowCount (nth 1 result)
                        clippedCount (nth 2 result) shortFallbackCount (nth 3 result))
                  (princ (strcat "\nCreated Isoplus DN" (itoa dn) " Series " (itoa series)
                                 " | route=" routeDef " | carrier OD " (rtos carrierMM 2 1) " mm | casing OD "
                                 (rtos casingMM 2 1) " mm | " mode " | " (itoa spoolCount) " straight spool(s) | "
                                 (itoa elbowCount) " 3D elbow(s)."))
                  (if (and (= routeDef "WeldPoints") (= elbowCount 0) (> (length pts) 3))
                    (princ (strcat "\nNo weld-to-weld 45/90 bend span was recognised. Bend-angle tolerance is +/-"
                                   (rtos *gtp-bend-angle-tol-deg* 2 1) " deg.")))
                  (if (> clippedCount 0) (princ (strcat "\nNote: " (itoa clippedCount) " fitting leg(s) were shortened because the adjacent route segment was shorter than the catalogue fitting envelope.")))
                  (if (> shortFallbackCount 0) (princ "\nNote: Short elbow is not listed for this DN, so the catalogue Standard leg was used."))
                )
              )
            )
          )
        )
      )
    )
  )
  (setvar "CMDECHO" oldcmdecho)
  (princ)
)

(defun c:GTPPINFO (/ ent ed xd app data)
  (setq ent (car (entsel "\nSelect a GTP pipe solid: ")))
  (if ent
    (progn
      (setq ed (entget ent '("GTP_DH_PIPE")) xd (assoc -3 ed))
      (if xd
        (progn
          (setq app (cadr xd) data (cdr app))
          (princ "\nGTP pipe metadata:")
          (foreach x data
            (cond
              ((= (car x) 1000) (princ (strcat "\n  " (cdr x))))
              ((= (car x) 1070) (princ (strcat "\n  " (itoa (cdr x)))))
              ((= (car x) 1040) (princ (strcat "\n  " (rtos (cdr x) 2 1))))
            )
          )
        )
        (princ "\nNo GTP_DH_PIPE metadata found on this object.")
      )
    )
  )
  (princ)
)

(princ "\nGTP DH Toolkit V1.8 loaded. Commands: GTPPIPE, GTPUNITS, GTPPINFO, GTPLAYER.")
(princ)