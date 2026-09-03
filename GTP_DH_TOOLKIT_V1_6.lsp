; GTP_DH_TOOLKIT_V1_6.LSP
; Greentropy buried district-heating pipe modeller for AutoCAD / AutoCAD Mechanical
; Manufacturer data source: Isoplus Product Catalogue 11/2024
;
; Commands:
;   GTPPIPE    - Create Isoplus pre-insulated pipe along LINE / 2D or 3D polyline
;   GTPUNITS   - Set/check catalogue-mm to drawing-unit conversion
;   GTPPINFO   - Read stored GTP pipe metadata
;   GTPLAYER   - Create / repair GTP layers
;
; V1.6 notes:
; - Keeps the V1.4 catalogue-to-drawing scale correction and V1.5 3D elbow model.
; - Adds WELD-POINT route interpretation for polylines whose vertices are actual
;   pipe/fitting weld locations. A segment between two welds can be recognised as
;   ONE catalogue 45/90 bend instead of creating a bend at both weld points.
; - Incoming/outgoing straight axes are extrapolated to a virtual corner; the
;   actual weld coordinates remain fixed while one tangent 3D elbow replaces the
;   weld-to-weld fitting span.
; - CORNERS route interpretation preserves the V1.5 behavior where every interior
;   polyline vertex is the theoretical centerline intersection of a bend.
; - Uses Isoplus section 5.4 single-steel-pipe bend leg lengths. Standard leg is
;   the default; Short can be selected where the catalogue provides it.
; - 45 and 90 degree route turns are reported as standard catalogue bend angles.
;   Other route angles are also modelled because the catalogue states other
;   angles and leg lengths are available.
; - Elbow arc solids are made with AddExtrudedSolidAlongPath. If AutoCAD rejects
;   a sweep, the code automatically falls back to a fine segmented 3D bend.
; - Straight pipe runs are trimmed back to the fitting ends before spooling.
; - FULL mode creates three concentric solids on separate layers:
;       GTP-PIPE-CARRIER
;       GTP-PIPE-INSULATION
;       GTP-PIPE-CASING
;   Turn layers off to expose the inner construction.
; - CASING mode creates only the outside jacket/casing.
; - Dimensions are in millimetres.
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

; Isoplus pre-insulated steel single-pipe bends, catalogue section 5.4.
; DN  short-leg-mm  standard-leg-mm
; A NIL short leg means the catalogue only lists the standard leg for that DN.
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

; Fabrication / visualisation settings stored in CATALOGUE MILLIMETRES.
; These values are converted to the current drawing units before geometry is created.
(setq *gtp-max-pipe-length-mm* 12000.0) ; maximum straight pipe spool length
(setq *gtp-end-cutback-mm*       220.0) ; exposed carrier end from Isoplus catalogue
(setq *gtp-bend-angle-tol-deg*      12.0) ; recognition tolerance around 45/90 deg
(setq *gtp-mm-to-du*               1.0) ; drawing-units per catalogue mm
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
  (setq src (getkword
    "\nCatalogue is in mm. Drawing unit source [Auto/MM/CM/M/Inch/Feet] <Auto>: "
  ))
  (if (null src) (setq src "Auto"))
  (cond
    ((= src "Auto")
      (setq iu (getvar "INSUNITS")
            info (gtp:unit-info-from-insunits iu))
      (if (null info)
        (progn
          (princ
            (strcat
              "\nINSUNITS=" (itoa iu)
              " is unitless/unsupported, so Auto cannot determine the scale."
            )
          )
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

  (setq *gtp-drawing-unit-name* (car info)
        *gtp-mm-to-du*          (cadr info))

  (princ
    (strcat
      "\nGTP scale: 1 catalogue mm = "
      (rtos *gtp-mm-to-du* 2 8)
      " drawing unit(s) [" *gtp-drawing-unit-name* "]."
    )
  )
  info
)

(defun gtp:mm (value-mm)
  (* value-mm *gtp-mm-to-du*)
)

(defun c:GTPUNITS (/ info)
  (setq info (gtp:setup-units))
  (if info
    (princ
      (strcat
        "\nCurrent GTP conversion set for " *gtp-drawing-unit-name*
        ". Example: 1000 mm -> " (rtos (gtp:mm 1000.0) 2 6) " drawing units."
      )
    )
  )
  (princ)
)

(defun gtp:ensure-layer (name color / doc lays lay)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        lays (vla-get-Layers doc))
  (if (tblsearch "LAYER" name)
    (setq lay (vla-Item lays name))
    (setq lay (vla-Add lays name))
  )
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

(defun c:GTPLAYER ()
  (gtp:layers)
  (princ "\nGTP district-heating layers created/checked.")
  (princ)
)

(defun gtp:find-dn (dn)
  (assoc dn *gtp-pipe-db*)
)

(defun gtp:casing-od (row series)
  (cond
    ((= series 1) (nth 2 row))
    ((= series 2) (nth 3 row))
    ((= series 3) (nth 4 row))
  )
)

(defun gtp:list-dns (/ s r)
  (setq s "")
  (foreach r *gtp-pipe-db*
    (setq s (strcat s (itoa (car r)) " "))
  )
  s
)

(defun gtp:get-dn (/ dn row)
  (setq row nil)
  (while (not row)
    (setq dn (getint
      (strcat
        "\nNominal pipe size DN ["
        (gtp:list-dns)
        "]: "
      )
    ))
    (if dn
      (setq row (gtp:find-dn dn))
    )
    (if (and dn (not row))
      (princ "\nThat DN is not in the current Isoplus database.")
    )
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
  (setq s (getkword
    "\nPolyline vertices represent [WeldPoints/Corners] <WeldPoints>: "
  ))
  (if (null s) "WeldPoints" s)
)

(defun gtp:elbow-leg-mm (dn style / row short std)
  (setq row (assoc dn *gtp-elbow-db*))
  (if row
    (progn
      (setq short (nth 1 row)
            std   (nth 2 row))
      (if (= style "Short")
        (if short short std)
        std
      )
    )
  )
)

(defun gtp:variant (lst)
  (vlax-make-variant
    (vlax-safearray-fill
      (vlax-make-safearray vlax-vbDouble '(0 . 2))
      lst
    )
  )
)

(defun gtp:make-cylinder (p1 p2 dia layer / doc ms vec len cyl)
  (setq vec (mapcar '- p2 p1)
        len (distance p1 p2))
  (if (> len 1e-8)
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
            ms  (vla-get-ModelSpace doc)
            cyl (vla-AddCylinder ms (gtp:variant '(0.0 0.0 0.0)) (/ dia 2.0) len))
      (vla-TransformBy cyl
        (vlax-tmatrix
          (gtp:axis-matrix p1 p2)
        )
      )
      (vla-put-Layer cyl layer)
      cyl
    )
  )
)

(defun gtp:vunit (v / m)
  (setq m (distance '(0.0 0.0 0.0) v))
  (if (> m 1e-12)
    (mapcar '(lambda (x) (/ x m)) v)
    '(0.0 0.0 1.0)
  )
)

(defun gtp:cross (a b)
  (list
    (- (* (cadr a) (caddr b)) (* (caddr a) (cadr b)))
    (- (* (caddr a) (car b)) (* (car a) (caddr b)))
    (- (* (car a) (cadr b)) (* (cadr a) (car b)))
  )
)

(defun gtp:axis-matrix (p1 p2 / z ref x y mid)
  (setq z   (gtp:vunit (mapcar '- p2 p1))
        mid (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
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

(defun gtp:dot (a b)
  (+ (* (car a) (car b))
     (* (cadr a) (cadr b))
     (* (caddr a) (caddr b)))
)

(defun gtp:vmag (v)
  (sqrt (gtp:dot v v))
)

(defun gtp:vsub (a b)
  (mapcar '- a b)
)

(defun gtp:vadd (p v)
  (mapcar '+ p v)
)

(defun gtp:vscale (v s)
  (mapcar '(lambda (x) (* x s)) v)
)

(defun gtp:tan (a / c)
  (setq c (cos a))
  (if (< (abs c) 1e-12)
    1e99
    (/ (sin a) c)
  )
)

(defun gtp:rad->deg (a)
  (* a (/ 180.0 pi))
)

(defun gtp:snap-bend-deg (deg / tol)
  ; Return the catalogue bend class; preserve measured geometry for weld accuracy.
  (setq tol *gtp-bend-angle-tol-deg*)
  (cond
    ((<= (abs (- deg 90.0)) tol) 90.0)
    ((<= (abs (- deg 45.0)) tol) 45.0)
    (T nil)
  )
)

(defun gtp:line-line-corner (p1 u p2 v / w a b c d e den s t q1 q2 mid gap)
  ; Closest approach of two infinite 3D lines.
  ; L1=p1+s*u, L2=p2+t*v. For a weld-defined elbow, s>0 and t<0.
  (setq u (gtp:vunit u)
        v (gtp:vunit v)
        w (gtp:vsub p1 p2)
        a (gtp:dot u u)
        b (gtp:dot u v)
        c (gtp:dot v v)
        d (gtp:dot u w)
        e (gtp:dot v w)
        den (- (* a c) (* b b)))
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

(defun gtp:safe-delete (obj)
  (if obj
    (vl-catch-all-apply 'vla-Delete (list obj))
  )
)

(defun gtp:make-circle-region (center normal radius / doc ms cir arr regs reg)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        ms  (vla-get-ModelSpace doc)
        cir (vla-AddCircle ms (gtp:variant '(0.0 0.0 0.0)) radius))
  (vla-TransformBy cir (vlax-tmatrix (gtp:frame-z center normal)))
  (setq arr (vlax-make-safearray vlax-vbObject '(0 . 0)))
  (vlax-safearray-put-element arr 0 cir)
  (setq regs (vl-catch-all-apply 'vla-AddRegion (list ms arr)))
  (if (vl-catch-all-error-p regs)
    (progn
      (gtp:safe-delete cir)
      nil
    )
    (progn
      (setq reg (vlax-safearray-get-element (vlax-variant-value regs) 0))
      (gtp:safe-delete cir)
      reg
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

(defun gtp:make-arc-path (center t1 normal radius phi / doc ms x y arc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        ms  (vla-get-ModelSpace doc)
        x   (gtp:vunit (gtp:vsub t1 center))
        y   (gtp:cross normal x)
        arc (vla-AddArc ms (gtp:variant '(0.0 0.0 0.0)) radius 0.0 phi))
  (vla-TransformBy arc (vlax-tmatrix (gtp:frame-xyz center x y normal)))
  arc
)

(defun gtp:sweep-circle-on-arc (center t1 normal tangent radius phi dia layer / doc ms path reg sol)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        ms  (vla-get-ModelSpace doc)
        path (gtp:make-arc-path center t1 normal radius phi)
        reg  (gtp:make-circle-region t1 tangent (/ dia 2.0)))

  (if (and path reg)
    (setq sol
      (vl-catch-all-apply
        'vla-AddExtrudedSolidAlongPath
        (list ms reg path)
      )
    )
  )

  (gtp:safe-delete reg)
  (gtp:safe-delete path)

  (if (or (null sol) (vl-catch-all-error-p sol))
    nil
    (progn
      (vla-put-Layer sol layer)
      sol
    )
  )
)

(defun gtp:segmented-arc-solids (center t1 normal radius phi dia layer / x y segs a0 a1 p0 p1 i o out)
  (setq x (gtp:vunit (gtp:vsub t1 center))
        y (gtp:cross normal x)
        segs (max 8 (fix (+ 0.5 (* 18.0 (/ phi (/ pi 2.0))))))
        i 0
        out '())
  (while (< i segs)
    (setq a0 (* phi (/ (float i) segs))
          a1 (* phi (/ (float (1+ i)) segs))
          p0 (gtp:arc-point center x y radius a0)
          p1 (gtp:arc-point center x y radius a1)
          o  (gtp:make-cylinder p0 p1 dia layer))
    (if o (setq out (cons o out)))
    (setq i (1+ i))
  )
  (reverse out)
)

(defun gtp:add-xdata (obj dn series carrier casing mode / en app data)
  (regapp "GTP_DH_PIPE")
  (setq en (vlax-vla-object->ename obj))
  (setq data
    (list
      (list -3
        (list
          "GTP_DH_PIPE"
          (cons 1000 "ISOPLUS")
          (cons 1000 "STEEL_SINGLE")
          (cons 1070 dn)
          (cons 1070 series)
          (cons 1040 carrier)
          (cons 1040 casing)
          (cons 1000 mode)
        )
      )
    )
  )
  (entmod (append (entget en) data))
  (entupd en)
)

(defun gtp:add-xdata-many (objs dn series carrier casing mode)
  (foreach o objs
    (if o (gtp:add-xdata o dn series carrier casing mode))
  )
)

(defun gtp:model-arc-component (center t1 normal tangent radius phi dia layer dn series carrier casing tag / o objs)
  (setq o (gtp:sweep-circle-on-arc center t1 normal tangent radius phi dia layer))
  (if o
    (progn
      (gtp:add-xdata o dn series carrier casing tag)
      (list o)
    )
    (progn
      (setq objs (gtp:segmented-arc-solids center t1 normal radius phi dia layer))
      (gtp:add-xdata-many objs dn series carrier casing (strcat tag "-SEGMENTED"))
      objs
    )
  )
)

(defun gtp:elbow-tag (phi / deg)
  (setq deg (gtp:rad->deg phi))
  (cond
    ((<= (abs (- deg 45.0)) 1.0) "45")
    ((<= (abs (- deg 90.0)) 1.0) "90")
    (T (strcat "CUSTOM-" (rtos deg 2 1)))
  )
)

(defun gtp:make-elbow-spec (prev v next dn carrier casing style / d1 d2 cr cm dp phi deg legmm leg0 leg maxleg baseR maxR radius tang tanDist t1 t2 normal inward center fs fe clipped)
  ; d1 = direction INTO the vertex; d2 = direction OUT OF the vertex.
  (setq d1 (gtp:vunit (gtp:vsub v prev))
        d2 (gtp:vunit (gtp:vsub next v))
        cr (gtp:cross d1 d2)
        cm (gtp:vmag cr)
        dp (gtp:dot d1 d2)
        phi (atan cm dp)
        deg (gtp:rad->deg phi))

  ; Ignore essentially straight points and avoid unstable U-turn geometry.
  (if (or (< deg 1.0) (> deg 175.0) (< cm 1e-10))
    nil
    (progn
      (setq normal (gtp:vunit cr)
            legmm  (gtp:elbow-leg-mm dn style)
            leg0   (gtp:mm legmm)
            maxleg (min (* 0.45 (distance prev v))
                        (* 0.45 (distance v next)))
            leg    (min leg0 maxleg)
            clipped (< leg (- leg0 1e-8)))

      ; The catalogue gives fitting leg lengths but not a casing CLR in section 5.4.
      ; Start with a long-radius steel bend (1.5 x carrier OD), then make sure the
      ; centreline radius is large enough to sweep the selected pre-insulated casing.
      (setq baseR (max (* 1.5 carrier) (* 0.60 casing))
            tang  (gtp:tan (/ phi 2.0))
            maxR  (if (> tang 1e-10) (/ (* 0.90 leg) tang) baseR)
            radius (min baseR maxR))

      (if (< radius (* 0.55 casing))
        ; The route is exceptionally short. Keep a positive fitting but the sweep
        ; may fall back to segmented geometry.
        (setq radius (max radius (* 0.30 casing)))
      )

      (setq tanDist (* radius tang))
      (if (> tanDist (* 0.95 leg))
        (progn
          (setq tanDist (* 0.90 leg)
                radius (/ tanDist tang))
        )
      )

      (setq fs     (gtp:vadd v (gtp:vscale d1 (- leg)))
            fe     (gtp:vadd v (gtp:vscale d2 leg))
            t1     (gtp:vadd v (gtp:vscale d1 (- tanDist)))
            t2     (gtp:vadd v (gtp:vscale d2 tanDist))
            inward (gtp:vunit (gtp:cross normal d1))
            center (gtp:vadd t1 (gtp:vscale inward radius)))

      (list
        (cons 'leg leg)
        (cons 'legmm legmm)
        (cons 'radius radius)
        (cons 'phi phi)
        (cons 'd1 d1)
        (cons 'd2 d2)
        (cons 'normal normal)
        (cons 'start fs)
        (cons 'tan1 t1)
        (cons 'center center)
        (cons 'tan2 t2)
        (cons 'end fe)
        (cons 'tag (gtp:elbow-tag phi))
        (cons 'clipped clipped)
      )
    )
  )
)

(defun gtp:make-weld-elbow-spec (prev fs fe next dn carrier casing style / d1 d2 cr cm dp phi deg snap ll v leg1 leg2 gap gapTol legLimit baseR tang maxR radius tanDist t1 t2 normal inward center legmm)
  ; prev--fs = incoming straight, fs--fe = fitting span, fe--next = outgoing straight.
  ; fs and fe are actual weld points and are never moved.
  (if (or (< (distance prev fs) 1e-8)
          (< (distance fs fe) 1e-8)
          (< (distance fe next) 1e-8))
    nil
    (progn
      (setq d1 (gtp:vunit (gtp:vsub fs prev))
            d2 (gtp:vunit (gtp:vsub next fe))
            cr (gtp:cross d1 d2)
            cm (gtp:vmag cr)
            dp (gtp:dot d1 d2)
            phi (atan cm dp)
            deg (gtp:rad->deg phi)
            snap (gtp:snap-bend-deg deg))
      (if (or (null snap) (< cm 1e-10))
        nil
        (progn
          (setq ll (gtp:line-line-corner fs d1 fe d2))
          (if (null ll)
            nil
            (progn
              (setq v (cdr (assoc 'corner ll))
                    leg1 (cdr (assoc 's ll))
                    leg2 (- (cdr (assoc 't ll)))
                    gap (cdr (assoc 'gap ll))
                    gapTol (max (gtp:mm 20.0) (* 0.30 casing))
                    legmm (gtp:elbow-leg-mm dn style)
                    legLimit (* 3.0 (gtp:mm legmm)))
              ; The two neighboring straight axes must intersect near each other,
              ; ahead of the first weld and behind the second weld.
              (if (or (<= leg1 1e-8) (<= leg2 1e-8)
                      (> gap gapTol) (> leg1 legLimit) (> leg2 legLimit))
                nil
                (progn
                  (setq normal (gtp:vunit cr)
                        baseR (max (* 1.5 carrier) (* 0.60 casing))
                        tang (gtp:tan (/ phi 2.0))
                        maxR (if (> tang 1e-10)
                               (/ (* 0.90 (min leg1 leg2)) tang)
                               baseR)
                        radius (min baseR maxR))
                  (if (< radius (* 0.55 casing))
                    (setq radius (max radius (* 0.30 casing))))
                  (setq tanDist (* radius tang))
                  (if (> tanDist (* 0.95 (min leg1 leg2)))
                    (progn
                      (setq tanDist (* 0.90 (min leg1 leg2))
                            radius (/ tanDist tang))))
                  (setq t1 (gtp:vadd v (gtp:vscale d1 (- tanDist)))
                        t2 (gtp:vadd v (gtp:vscale d2 tanDist))
                        inward (gtp:vunit (gtp:cross normal d1))
                        center (gtp:vadd t1 (gtp:vscale inward radius)))
                  (list
                    (cons 'leg (min leg1 leg2))
                    (cons 'legmm legmm)
                    (cons 'radius radius)
                    (cons 'phi phi)
                    (cons 'd1 d1)
                    (cons 'd2 d2)
                    (cons 'normal normal)
                    (cons 'start fs)
                    (cons 'tan1 t1)
                    (cons 'center center)
                    (cons 'tan2 t2)
                    (cons 'end fe)
                    (cons 'tag (if (= snap 90.0) "90" "45"))
                    (cons 'measuredDeg deg)
                    (cons 'virtualCorner v)
                    (cons 'gap gap)
                    (cons 'clipped nil)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

(defun gtp:spec (key spec)
  (cdr (assoc key spec))
)

(defun gtp:model-elbow (spec dn series carrier casing mode / leg rad phi d1 d2 normal fs t1 center t2 fe cut1 cut2 straightAvail1 straightAvail2 cs ce o tag n)
  (setq leg    (gtp:spec 'leg spec)
        rad    (gtp:spec 'radius spec)
        phi    (gtp:spec 'phi spec)
        d1     (gtp:spec 'd1 spec)
        d2     (gtp:spec 'd2 spec)
        normal (gtp:spec 'normal spec)
        fs     (gtp:spec 'start spec)
        t1     (gtp:spec 'tan1 spec)
        center (gtp:spec 'center spec)
        t2     (gtp:spec 'tan2 spec)
        fe     (gtp:spec 'end spec)
        tag    (gtp:spec 'tag spec)
        n      0)

  ; Full-length carrier fitting: straight leg + smooth arc + straight leg.
  (setq o (gtp:make-cylinder fs t1 carrier "GTP-PIPE-CARRIER"))
  (if o
    (progn
      (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CARRIER"))
      (setq n (1+ n))
    )
  )

  (setq n
    (+ n
      (length
        (gtp:model-arc-component
          center t1 normal d1 rad phi carrier
          "GTP-PIPE-CARRIER" dn series carrier casing
          (strcat "ELBOW-" tag "-CARRIER")
        )
      )
    )
  )

  (setq o (gtp:make-cylinder t2 fe carrier "GTP-PIPE-CARRIER"))
  (if o
    (progn
      (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CARRIER"))
      (setq n (1+ n))
    )
  )

  ; Jacket/insulation cutback at the two fitting weld ends.
  ; Actual straight portion at each elbow side is distance from fitting end
  ; to the arc tangent point.
  (setq straightAvail1 (distance fs t1)
        straightAvail2 (distance t2 fe)
        cut1 (gtp:mm *gtp-end-cutback-mm*)
        cut2 (gtp:mm *gtp-end-cutback-mm*))
  (if (> straightAvail1 1e-8)
    (setq cut1 (min cut1 (* 0.80 straightAvail1)))
    (setq cut1 0.0))
  (if (> straightAvail2 1e-8)
    (setq cut2 (min cut2 (* 0.80 straightAvail2)))
    (setq cut2 0.0))
  (setq cs (gtp:vadd fs (gtp:vscale d1 cut1))
        ce (gtp:vadd fe (gtp:vscale d2 (- cut2))))

  (setq o (gtp:make-cylinder cs t1 casing "GTP-PIPE-CASING"))
  (if o
    (progn
      (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CASING"))
      (setq n (1+ n))
    )
  )

  (setq n
    (+ n
      (length
        (gtp:model-arc-component
          center t1 normal d1 rad phi casing
          "GTP-PIPE-CASING" dn series carrier casing
          (strcat "ELBOW-" tag "-CASING")
        )
      )
    )
  )

  (setq o (gtp:make-cylinder t2 ce casing "GTP-PIPE-CASING"))
  (if o
    (progn
      (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-CASING"))
      (setq n (1+ n))
    )
  )

  (if (= mode "FULL")
    (progn
      (setq o (gtp:make-cylinder cs t1 casing "GTP-PIPE-INSULATION"))
      (if o
        (progn
          (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-INSULATION"))
          (setq n (1+ n))
        )
      )

      (setq n
        (+ n
          (length
            (gtp:model-arc-component
              center t1 normal d1 rad phi casing
              "GTP-PIPE-INSULATION" dn series carrier casing
              (strcat "ELBOW-" tag "-INSULATION")
            )
          )
        )
      )

      (setq o (gtp:make-cylinder t2 ce casing "GTP-PIPE-INSULATION"))
      (if o
        (progn
          (gtp:add-xdata o dn series carrier casing (strcat "ELBOW-" tag "-INSULATION"))
          (setq n (1+ n))
        )
      )
    )
  )
  n
)

(defun gtp:curve-points (ename / obj endp i pts p)
  ; Works well for LINE, LWPOLYLINE and 2D/3D POLYLINE whose route is
  ; made from straight segments. Curved/bulged polyline segments are not
  ; interpreted as true bends in V1.
  (setq obj (vlax-ename->vla-object ename))
  (if (vl-catch-all-error-p
        (setq endp
          (vl-catch-all-apply 'vlax-curve-getEndParam (list ename))
        )
      )
    nil
    (progn
      (setq i 0
            pts '())
      (while (<= i (fix endp))
        (setq p (vlax-curve-getPointAtParam ename i))
        (if p (setq pts (append pts (list p))))
        (setq i (1+ i))
      )
      ; LINE can return EndParam=1, so both endpoints are included.
      pts
    )
  )
)

(defun gtp:point-along (p1 p2 dist / dir)
  (setq dir (gtp:vunit (mapcar '- p2 p1)))
  (gtp:vadd p1 (gtp:vscale dir dist))
)

(defun gtp:model-spool (p1 p2 dn series carrier casing mode / len cut c1 c2 o)
  ; A spool has full-length carrier pipe, while casing/insulation are cut back
  ; by the catalogue cutback at BOTH ends to show the exposed steel weld ends.
  (setq len (distance p1 p2)
        cut (gtp:mm *gtp-end-cutback-mm*))

  ; Never let cutbacks cross on a very short spool.
  (if (>= (* 2.0 cut) len)
    (setq cut (/ len 4.0))
  )

  (setq c1 (gtp:point-along p1 p2 cut)
        c2 (gtp:point-along p1 p2 (- len cut)))

  ; Carrier is always created so exposed ends are visible even in CASING mode.
  (setq o (gtp:make-cylinder p1 p2 carrier "GTP-PIPE-CARRIER"))
  (if o (gtp:add-xdata o dn series carrier casing "CARRIER"))

  ; Casing is shortened by the catalogue 220 mm exposed-end allowance at each spool end.
  (if (> (distance c1 c2) 1e-8)
    (progn
      (setq o (gtp:make-cylinder c1 c2 casing "GTP-PIPE-CASING"))
      (if o (gtp:add-xdata o dn series carrier casing "CASING"))

      ; In FULL mode, create the insulation over the same trimmed length.
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
  ; Split every straight route leg into pipe spools no longer than 12 m.
  ; Example: 16 m route leg => 12 m spool + 4 m spool.
  ; Each spool uses the catalogue exposed-end allowance at each end.
  (setq len    (distance p1 p2)
        dir    (gtp:vunit (mapcar '- p2 p1))
        pos    0.0
        count  0)

  (while (< pos (- len 1e-8))
    (setq remain (- len pos)
          piece  (min (gtp:mm *gtp-max-pipe-length-mm*) remain)
          s1     (gtp:vadd p1 (gtp:vscale dir pos))
          s2     (gtp:vadd p1 (gtp:vscale dir (+ pos piece))))

    (gtp:model-spool s1 s2 dn series carrier casing mode)

    (setq pos   (+ pos piece)
          count (1+ count))
  )
  count
)

(defun gtp:take (lst n / out i)
  (setq out '() i 0)
  (while (and lst (< i n))
    (setq out (append out (list (car lst)))
          lst (cdr lst)
          i (1+ i)))
  out
)

(defun gtp:drop (lst n / i)
  (setq i 0)
  (while (and lst (< i n))
    (setq lst (cdr lst) i (1+ i)))
  lst
)

(defun gtp:set-nth (lst idx value)
  (append (gtp:take lst idx) (list value) (gtp:drop lst (1+ idx)))
)

(defun gtp:model-corner-route (pts dn series carrier casing mode elbowStyle / elbows npts i spec p1 p2 s e spoolCount elbowCount clippedCount shortFallbackCount)
  ; V1.5 interpretation: each interior vertex is a theoretical bend corner.
  (setq npts (length pts) elbows '() i 0
        spoolCount 0 elbowCount 0 clippedCount 0 shortFallbackCount 0)
  (while (< i npts)
    (setq spec nil)
    (if (and (> i 0) (< i (1- npts)))
      (progn
        (setq spec (gtp:make-elbow-spec
                     (nth (1- i) pts) (nth i pts) (nth (1+ i) pts)
                     dn carrier casing elbowStyle))
        (if spec
          (progn
            (if (gtp:spec 'clipped spec)
              (setq clippedCount (1+ clippedCount)))
            (if (and (= elbowStyle "Short")
                     (null (nth 1 (assoc dn *gtp-elbow-db*))))
              (setq shortFallbackCount (1+ shortFallbackCount)))))))
    (setq elbows (append elbows (list spec)) i (1+ i)))

  (setq i 0)
  (while (< i (1- npts))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts)
          s (if (nth i elbows) (gtp:spec 'end (nth i elbows)) p1)
          e (if (nth (1+ i) elbows) (gtp:spec 'start (nth (1+ i) elbows)) p2))
    (if (> (distance s e) 1e-8)
      (setq spoolCount (+ spoolCount
                          (gtp:model-segment s e dn series carrier casing mode))))
    (setq i (1+ i)))

  (setq i 1)
  (while (< i (1- npts))
    (if (nth i elbows)
      (progn
        (gtp:model-elbow (nth i elbows) dn series carrier casing mode)
        (setq elbowCount (1+ elbowCount))))
    (setq i (1+ i)))
  (list spoolCount elbowCount clippedCount shortFallbackCount)
)

(defun gtp:model-weld-route (pts dn series carrier casing mode elbowStyle / npts segKinds specs i spec spoolCount elbowCount p1 p2 deg tag)
  ; Each polyline segment is initially a straight weld-to-weld component span.
  ; A span becomes ONE elbow if its neighboring straight axes form a plausible
  ; catalogue 45/90-degree bend. This prevents two elbows from being generated
  ; at the two welds that bound one physical bend.
  (setq npts (length pts) segKinds '() specs '()
        i 0 spoolCount 0 elbowCount 0)
  (repeat (1- npts)
    (setq segKinds (append segKinds (list "STRAIGHT"))
          specs (append specs (list nil))))

  ; A bend span requires four points: previous weld, fitting-start weld,
  ; fitting-end weld, and next weld.
  (setq i 1)
  (while (< i (- npts 2))
    (setq spec
      (gtp:make-weld-elbow-spec
        (nth (1- i) pts) (nth i pts) (nth (1+ i) pts) (nth (+ i 2) pts)
        dn carrier casing elbowStyle))
    (if spec
      (progn
        (setq segKinds (gtp:set-nth segKinds i "ELBOW")
              specs (gtp:set-nth specs i spec)
              deg (gtp:spec 'measuredDeg spec)
              tag (gtp:spec 'tag spec))
        (princ (strcat "\nDetected weld-to-weld " tag " deg bend at polyline segment "
                       (itoa (1+ i)) " (axis turn " (rtos deg 2 1) " deg)."))
        ; The immediately following segment is the outgoing straight used to
        ; establish this bend, so skip it as a candidate bend span.
        (setq i (+ i 2)))
      (setq i (1+ i))))

  (setq i 0)
  (while (< i (1- npts))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts))
    (if (= (nth i segKinds) "ELBOW")
      (progn
        (gtp:model-elbow (nth i specs) dn series carrier casing mode)
        (setq elbowCount (1+ elbowCount)))
      (if (> (distance p1 p2) 1e-8)
        (setq spoolCount (+ spoolCount
                          (gtp:model-segment p1 p2 dn series carrier casing mode)))))
    (setq i (1+ i)))
  (list spoolCount elbowCount 0 0)
)

(defun c:GTPPIPE (/ *error* oldcmdecho ent typ row dn series carrierMM casingMM carrier casing mode elbowStyle routeDef pts result spoolCount elbowCount clippedCount shortFallbackCount)
  (vl-load-com)

  (defun *error* (msg)
    (if oldcmdecho (setvar "CMDECHO" oldcmdecho))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPPIPE error: " msg)))
    (princ)
  )

  (setq oldcmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)
  (setq ent (car (entsel "\nSelect route LINE / 2D or 3D POLYLINE: ")))

  (if (null ent)
    (princ "\nNothing selected.")
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (if (not (member typ '("LINE" "LWPOLYLINE" "POLYLINE")))
        (princ "\nGTPPIPE accepts LINE, LWPOLYLINE or POLYLINE routes.")
        (progn
          (gtp:setup-units)
          (setq row (gtp:get-dn))
          (if row
            (progn
              (setq dn (nth 0 row)
                    carrierMM (nth 1 row)
                    series (gtp:get-series)
                    casingMM (gtp:casing-od row series)
                    carrier (gtp:mm carrierMM)
                    casing (gtp:mm casingMM)
                    mode (gtp:get-mode)
                    elbowStyle (gtp:get-elbow-style)
                    routeDef (gtp:get-route-definition)
                    pts (gtp:curve-points ent))

              (if (or (null pts) (< (length pts) 2))
                (princ "\nCould not obtain route vertices.")
                (progn
                  (if (and (= routeDef "WeldPoints") (< (length pts) 4))
                    (progn
                      (princ "\nWeldPoints mode needs at least 4 points to recognise a bend span; modelling this route as straight weld-to-weld pipe.")
                      (setq result (gtp:model-weld-route pts dn series carrier casing mode elbowStyle)))
                    (setq result
                      (if (= routeDef "WeldPoints")
                        (gtp:model-weld-route pts dn series carrier casing mode elbowStyle)
                        (gtp:model-corner-route pts dn series carrier casing mode elbowStyle))))

                  (setq spoolCount (nth 0 result)
                        elbowCount (nth 1 result)
                        clippedCount (nth 2 result)
                        shortFallbackCount (nth 3 result))

                  (princ (strcat "\nCreated Isoplus DN" (itoa dn) " Series " (itoa series)
                                 " | route=" routeDef
                                 " | carrier OD " (rtos carrierMM 2 1) " mm"
                                 " | casing OD " (rtos casingMM 2 1) " mm | " mode
                                 " | " (itoa spoolCount) " straight spool(s)"
                                 " | " (itoa elbowCount) " 3D elbow(s)."))

                  (if (and (= routeDef "WeldPoints") (= elbowCount 0) (> (length pts) 3))
                    (princ (strcat "\nNo weld-to-weld 45/90 bend span was recognised. Bend-angle tolerance is +/-"
                                   (rtos *gtp-bend-angle-tol-deg* 2 1) " deg.")))
                  (if (> clippedCount 0)
                    (princ (strcat "\nNote: " (itoa clippedCount)
                                   " fitting leg(s) were shortened because an adjacent route segment is shorter than the catalogue fitting envelope.")))
                  (if (> shortFallbackCount 0)
                    (princ "\nNote: Short elbow is not listed for this DN, so the catalogue Standard leg was used."))
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
      (setq ed (entget ent '("GTP_DH_PIPE"))
            xd (assoc -3 ed))
      (if xd
        (progn
          (setq app (cadr xd)
                data (cdr app))
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

(princ "\nGTP DH Toolkit V1.6 loaded. Commands: GTPPIPE, GTPUNITS, GTPPINFO, GTPLAYER.")
(princ)