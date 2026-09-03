; GTP_DH_TOOLKIT_V1_4.LSP
; Greentropy buried district-heating pipe modeller for AutoCAD / AutoCAD Mechanical
; Manufacturer data source: Isoplus Product Catalogue 11/2024
;
; Commands:
;   GTPPIPE    - Create Isoplus pre-insulated pipe along LINE / 2D or 3D polyline
;   GTPUNITS   - Set/check catalogue-mm to drawing-unit conversion
;   GTPPINFO   - Read stored GTP pipe metadata
;   GTPLAYER   - Create / repair GTP layers
;
; V1.4 notes:
; - Fixes catalogue-to-drawing scale by converting all Isoplus millimetre dimensions
;   to the current AutoCAD drawing unit (INSUNITS), with a manual override.
; - Straight route segments are modelled as overlapping cylinders.
; - At route vertices the cylinders overlap; dedicated fittings/elbows are planned for V2.
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

; Fabrication / visualisation settings stored in CATALOGUE MILLIMETRES.
; These values are converted to the current drawing units before geometry is created.
(setq *gtp-max-pipe-length-mm* 12000.0) ; maximum straight pipe spool length
(setq *gtp-end-cutback-mm*       220.0) ; exposed carrier end from Isoplus catalogue
(setq *gtp-mm-to-du*               1.0) ; drawing-units per catalogue mm
(setq *gtp-drawing-unit-name*      "millimetres")

(defun gtp:unit-info-from-insunits (u)
  ; Return (unit-name drawing-units-per-mm), or NIL when unitless/unsupported.
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
  (setq s (getkword
    "\nDrawing geometry unit [MM/CM/M/Inch/Feet] <MM>: "
  ))
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
  ; Catalogue dimensions are millimetres. Route coordinates are never scaled.
  ; Only pipe/fitting dimensions are converted to the drawing's geometry unit.
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
  ; ACI colours are simply sensible defaults and can be changed in Layer Manager.
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
            ; IMPORTANT:
            ; Create the cylinder at WCS origin. The transformation matrix below
            ; both rotates it onto the route vector AND translates its centre to the route midpoint.
            ; Creating it at p1 and then applying a matrix containing p1 would
            ; translate it twice, making consecutive runs appear disjoint.
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
  ; AddCylinder is centred on the supplied centre point, with half the
  ; cylinder extending in each local Z direction. Therefore the transform
  ; must place the cylinder CENTRE at the midpoint of p1-p2, not at p1.
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


(defun gtp:vadd (p v)
  (mapcar '+ p v)
)

(defun gtp:vscale (v s)
  (mapcar '(lambda (x) (* x s)) v)
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

  ; Casing is shortened 100 mm at each spool end.
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

(defun c:GTPPIPE (/ *error* oldcmdecho ent typ row dn series carrierMM casingMM carrier casing mode pts n i)
  (vl-load-com)

  (defun *error* (msg)
    (if oldcmdecho (setvar "CMDECHO" oldcmdecho))
    (if (and msg
             (/= msg "Function cancelled")
             (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPPIPE error: " msg))
    )
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
        (princ "\nV1 accepts LINE, LWPOLYLINE or POLYLINE routes.")
        (progn
          ; Resolve catalogue millimetres to the actual drawing unit BEFORE modelling.
          ; This is the V1.4 scale fix. Route coordinates themselves are left unchanged.
          (gtp:setup-units)
          (setq row (gtp:get-dn))
          (if row
            (progn
              (setq dn        (nth 0 row)
                    carrierMM (nth 1 row)
                    series    (gtp:get-series)
                    casingMM  (gtp:casing-od row series)
                    carrier   (gtp:mm carrierMM)
                    casing    (gtp:mm casingMM)
                    mode      (gtp:get-mode)
                    pts       (gtp:curve-points ent))

              (if (or (null pts) (< (length pts) 2))
                (princ "\nCould not obtain route vertices.")
                (progn
                  (setq n 0
                        i 0)
                  (while (< i (1- (length pts)))
                    (if (> (distance (nth i pts) (nth (1+ i) pts)) 1e-8)
                      (setq n
                        (+ n
                          (gtp:model-segment
                            (nth i pts)
                            (nth (1+ i) pts)
                            dn series carrier casing mode
                          )
                        )
                      )
                    )
                    (setq i (1+ i))
                  )

                  (princ
                    (strcat
                      "\nCreated Isoplus DN" (itoa dn)
                      " Series " (itoa series)
                      " | catalogue carrier OD " (rtos carrierMM 2 1) " mm"
                      " | catalogue casing OD " (rtos casingMM 2 1) " mm"
                      " | drawing units: " *gtp-drawing-unit-name*
                      " | " mode
                      " | " (itoa n) " pipe spool(s), max 12 m, 220 mm exposed carrier each end."
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
          (setq app  (cadr xd)
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

(princ "\nGTP DH Toolkit V1.4 loaded. Commands: GTPPIPE, GTPUNITS, GTPPINFO, GTPLAYER.")
(princ)
