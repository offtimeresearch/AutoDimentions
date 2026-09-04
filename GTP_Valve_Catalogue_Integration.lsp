; GTP_Valve_Catalogue_Integration.lsp
; -----------------------------------------------------------------------------
; STEP 5 - Catalogue-backed valve variants.
;
; LOAD AFTER:
;   GTP_DH_TOOLKIT.lsp
;   GTP_Component_Architecture.lsp
;   GTP_Elbow_Component_Integration.lsp
;   GTP_Valve_Component.lsp
;   GTP_Valve_Aware_Pipe_Integration.lsp
;
; This file replaces the manual-dimension GTPVALVE command with catalogue
; selection for the valve families currently supported by the supplied
; ISOPLUS catalogue PDF:
;   SINGLE_SHUTOFF
;   SINGLE_SHUTOFF_2VENT_DRAIN
;   TWIN_SHUTOFF
;   TWIN_SHUTOFF_2VENT_DRAIN
;
; The catalogue rows below are transcribed from:
;   p.89  Shut-off valves - single, 5.9
;   p.90  Shut-off valves with 2 vent/drain valves - single, 5.9.1
;   p.128 Shut-off valves - twin, 8.10
;   p.129 Shut-off valves with 2 vent/drain valves - twin, 8.11
;
; IMPORTANT
;   The catalogue itself states that several dimensions vary by valve make.
;   These rows therefore remain tagged as catalogue reference data, not as
;   universal manufacturer geometry.  The model uses the catalogue dimensions
;   for the selected row; it does not invent a product-specific valve body.
;
; Geometry remains intentionally parametric.  STEP 5's goal is to remove
; manual dimensions from the normal placement workflow and establish the
; correct component/catalogue relationship.
; -----------------------------------------------------------------------------

(vl-load-com)

; -----------------------------------------------------------------------------
; CATALOGUE DATA - millimetres
; -----------------------------------------------------------------------------
;
; SINGLE_SHUTOFF row:
;   (carrierOD S1D S1D1 S2D S2D1 S3D S3D1 D3 h hex L)
;
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

; SINGLE_SHUTOFF_2VENT_DRAIN row:
;   (carrierOD S1D S1D1 S2D S2D1 S3D S3D1 D2 D3 d1 h A hex L)
;
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
    (168.3 250 280 280 280 315 315 140 140 60.3 565 250 27/70 1510)
    (219.1 315 355 355 355 400 400 140 140 60.3 585 250 50/90 1510)
    (273.0 400 450 450 450 500 500 180 140 60.3 614 305 50/90 1510)
    (323.9 450 560 500 560 560 560 180 140 60.3 664 370 50/90 1810)
  )
)

; TWIN_SHUTOFF row:
;   (carrierODpair S1D S1D1 S2D S2D1 S3D S3D1 D2 A h h1 hex L)
;
(setq *gtp-valve-twin-db*
  '(
    (33.7  140 180 160 180 180 200 110 210 461 365 19 1600)
    (42.4  160 200 180 200 200 250 110 210 471 366 19 1600)
    (48.3  160 200 180 200 200 250 110 210 499 366 19 1600)
    (60.3  200 250 225 250 250 280 110 210 519 366 19 1600)
    (76.1  225 280 250 280 280 315 110 210 542 360 19 1800)
    (88.9  250 315 280 315 315 355 110 210 574 358 19 1900)
    (114.3 315 400 355 400 400 450 110 210 618 365 27 1900)
    (139.7 400 500 450 500 500 560 180 210 690 383 27 2200)
    (168.3 450 560 500 560 560 630 180 210 752 383 27 2200)
    (219.1 560 630 630 710 710 800 180 210 800 383 27 2200)
  )
)

; TWIN_SHUTOFF_2VENT_DRAIN row:
;   (carrierODpair S1D S2D S3D D1 D2 h ventDrainDia tWrench L)
;
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

; -----------------------------------------------------------------------------
; CATALOGUE HELPERS
; -----------------------------------------------------------------------------
(defun gtp:catalogue-row-by-value (db value / row)
  (setq row nil)
  (foreach r db
    (if (and (null row) (< (abs (- (car r) value)) 0.01))
      (setq row r)
    )
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
  (setq s
    (getkword
      "\nValve type [SINGLE/SINGLE2VD/TWIN/TWIN2VD] <SINGLE>: "
    )
  )
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
  (if (and db od)
    (setq row (gtp:catalogue-row-by-value db od))
  )
  row
)

; -----------------------------------------------------------------------------
; CATALOGUE METADATA
; -----------------------------------------------------------------------------
(defun gtp:valve-catalogue-record (family row series / rec)
  (cond
    ((= family "SINGLE_SHUTOFF")
      (list
        (cons 'family family)
        (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row))
        (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-1-D1-mm (nth 2 row))
        (cons 'series-2-D-mm (nth 3 row))
        (cons 'series-2-D1-mm (nth 4 row))
        (cons 'series-3-D-mm (nth 5 row))
        (cons 'series-3-D1-mm (nth 6 row))
        (cons 'body-D3-mm (nth 7 row))
        (cons 'stem-height-mm (nth 8 row))
        (cons 'hex (nth 9 row))
        (cons 'length-mm (nth 10 row))
        (cons 'selected-series series)
      )
    )

    ((= family "SINGLE_SHUTOFF_2VENT_DRAIN")
      (list
        (cons 'family family)
        (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row))
        (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-1-D1-mm (nth 2 row))
        (cons 'series-2-D-mm (nth 3 row))
        (cons 'series-2-D1-mm (nth 4 row))
        (cons 'series-3-D-mm (nth 5 row))
        (cons 'series-3-D1-mm (nth 6 row))
        (cons 'body-D2-mm (nth 7 row))
        (cons 'body-D3-mm (nth 8 row))
        (cons 'vent-drain-d1-mm (nth 9 row))
        (cons 'stem-height-mm (nth 10 row))
        (cons 'spacing-A-mm (nth 11 row))
        (cons 'hex (nth 12 row))
        (cons 'length-mm (nth 13 row))
        (cons 'selected-series series)
      )
    )

    ((= family "TWIN_SHUTOFF")
      (list
        (cons 'family family)
        (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row))
        (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-1-D1-mm (nth 2 row))
        (cons 'series-2-D-mm (nth 3 row))
        (cons 'series-2-D1-mm (nth 4 row))
        (cons 'series-3-D-mm (nth 5 row))
        (cons 'series-3-D1-mm (nth 6 row))
        (cons 'body-D2-mm (nth 7 row))
        (cons 'spacing-A-mm (nth 8 row))
        (cons 'stem-height-mm (nth 9 row))
        (cons 'stem-height-h1-mm (nth 10 row))
        (cons 'hex (nth 11 row))
        (cons 'length-mm (nth 12 row))
        (cons 'selected-series series)
      )
    )

    ((= family "TWIN_SHUTOFF_2VENT_DRAIN")
      (list
        (cons 'family family)
        (cons 'source (gtp:valve-family-name family))
        (cons 'carrier-od-mm (nth 0 row))
        (cons 'series-1-D-mm (nth 1 row))
        (cons 'series-2-D-mm (nth 2 row))
        (cons 'series-3-D-mm (nth 3 row))
        (cons 'body-D1-mm (nth 4 row))
        (cons 'body-D2-mm (nth 5 row))
        (cons 'stem-height-mm (nth 6 row))
        (cons 'vent-drain-mm (nth 7 row))
        (cons 't-wrench (nth 8 row))
        (cons 'length-mm (nth 9 row))
        (cons 'selected-series series)
      )
    )
  )
)

; -----------------------------------------------------------------------------
; PARAMETRIC VALVE GEOMETRY
; -----------------------------------------------------------------------------
(defun gtp:valve-body-diameter-mm (catalogue)
  (cond
    ((gtp:catalogue-get catalogue 'body-D3-mm)
      (gtp:catalogue-get catalogue 'body-D3-mm))
    ((gtp:catalogue-get catalogue 'body-D2-mm)
      (gtp:catalogue-get catalogue 'body-D2-mm))
    ((gtp:catalogue-get catalogue 'body-D1-mm)
      (gtp:catalogue-get catalogue 'body-D1-mm))
    (T 110.0)
  )
)

(defun gtp:make-valve-stem (origin up bodyDia height layer / stemDia stemTop)
  (setq stemDia (max 19.0 (* 0.12 bodyDia)))
  (setq stemTop
    (gtp:vadd origin (gtp:vscale up height))
  )
  (gtp:make-cylinder origin stemTop stemDia layer)
)

(defun gtp:make-vertical-valve-head (origin up baseDia stemHeight stemDia)
  (gtp:make-cylinder
    origin
    (gtp:vadd origin (gtp:vscale up stemHeight))
    stemDia
    "GTP-VALVE-STEM"
  )
  (gtp:make-cylinder
    (gtp:vadd origin (gtp:vscale up (* 0.35 stemHeight)))
    (gtp:vadd origin (gtp:vscale up (* 0.35 stemHeight)))
    (max baseDia stemDia)
    "GTP-VALVE-BODY"
  )
)

(defun gtp:place-single-valve-stems (component catalogue / p d up body h A x half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq up (gtp:component-get component 'up))
  (setq body (gtp:valve-body-diameter-mm catalogue))
  (setq h (gtp:mm (gtp:catalogue-get catalogue 'stem-height-mm)))
  (setq h (max h (gtp:mm 150.0)))

  (setq x
    (gtp:vunit
      (gtp:cross up d)
    )
  )
  (if (< (gtp:vmag x) 1e-8)
    (setq x '(1.0 0.0 0.0))
  )

  ; Main shut-off valve stem.
  (setq half (gtp:mm (* 0.50 body)))
  (gtp:make-valve-stem
    (gtp:vadd p (gtp:vscale d 0.0))
    up
    (gtp:mm body)
    h
    "GTP-VALVE-STEM"
  )

  ; Two vent/drain families use the catalogue spacing A.
  (if (gtp:catalogue-get catalogue 'spacing-A-mm)
    (progn
      (setq A (gtp:mm (gtp:catalogue-get catalogue 'spacing-A-mm)))
      (gtp:make-valve-stem
        (gtp:vadd p (gtp:vscale x (- (/ A 2.0))))
        up
        (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-d1-mm))
        (max (gtp:mm 100.0) (* 0.65 h))
        "GTP-VALVE-STEM"
      )
      (gtp:make-valve-stem
        (gtp:vadd p (gtp:vscale x (/ A 2.0)))
        up
        (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-d1-mm))
        (max (gtp:mm 100.0) (* 0.65 h))
        "GTP-VALVE-STEM"
      )
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
  (if (< (gtp:vmag x) 1e-8)
    (setq x '(1.0 0.0 0.0))
  )
  (setq A (gtp:mm (if (gtp:catalogue-get catalogue 'spacing-A-mm)
                      (gtp:catalogue-get catalogue 'spacing-A-mm)
                      210.0)))

  ; Two main valve operating stems for the twin body.
  (gtp:make-valve-stem
    (gtp:vadd p (gtp:vscale x (- (/ A 2.0))))
    up (gtp:mm body) h "GTP-VALVE-STEM")
  (gtp:make-valve-stem
    (gtp:vadd p (gtp:vscale x (/ A 2.0)))
    up (gtp:mm body) h "GTP-VALVE-STEM")

  ; Twin + 2 vent/drain has an additional centre pair represented by the
  ; same catalogue spacing.  Their smaller dia is taken from vent-drain-mm.
  (if (gtp:catalogue-get catalogue 'vent-drain-mm)
    (progn
      (gtp:make-valve-stem
        p up
        (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-mm))
        (max (gtp:mm 100.0) (* 0.65 h))
        "GTP-VALVE-STEM")
      (gtp:make-valve-stem
        p up
        (gtp:mm (gtp:catalogue-get catalogue 'vent-drain-mm))
        (max (gtp:mm 100.0) (* 0.65 h))
        "GTP-VALVE-STEM")
    )
  )
)

(defun gtp:model-catalogue-valve (component catalogue / p d len body p0 p1 flange stem)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq len (gtp:mm (gtp:catalogue-get catalogue 'length-mm)))
  (setq body (gtp:mm (gtp:valve-body-diameter-mm catalogue)))
  (setq p0 (gtp:vsub p (gtp:vscale d (/ len 2.0))))
  (setq p1 (gtp:vadd p (gtp:vscale d (/ len 2.0))))
  (setq flange (* 1.20 body))

  (gtp:make-cylinder p0 p1 body "GTP-VALVE-BODY")
  (gtp:make-cylinder p0 (gtp:vadd p0 (gtp:vscale d (min (gtp:mm 120.0) (* 0.10 len))))
                       flange "GTP-VALVE-BODY")
  (gtp:make-cylinder (gtp:vsub p1 (gtp:vscale d (min (gtp:mm 120.0) (* 0.10 len)))) p1
                       flange "GTP-VALVE-BODY")

  (if (member (gtp:catalogue-get catalogue 'family)
              '("SINGLE_SHUTOFF" "SINGLE_SHUTOFF_2VENT_DRAIN"))
    (gtp:place-single-valve-stems component catalogue)
    (gtp:place-twin-valve-stems component catalogue)
  )
)

; -----------------------------------------------------------------------------
; GTPVALVE - CATALOGUE-BACKED COMMAND
; -----------------------------------------------------------------------------
(defun c:GTPVALVE (/ *error* old sel ent pick info pos dir row dn series family catalogue comp flow up id)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPVALVE error: " msg))
    )
    (princ)
  )

  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (if (not (and (fboundp 'gtp:make-valve-component)
                (fboundp 'gtp:curve-point-direction)))
    (princ "\nLoad the Step 3 valve component file and the component architecture first.")
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
                          (setq pos (car info))
                          (setq dir (cadr info))
                          (setq row (gtp:valve-dn-row))
                          (setq dn (car row))
                          (setq series (gtp:get-series))
                          (setq family (gtp:valve-family-prompt))

                          ; Recheck the selected family against the requested DN.
                          (setq row (gtp:valve-row-for-dn family dn))
                          (if row
                            (progn
                              (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                              (setq up '(0.0 0.0 1.0))
                              (if (> (abs (gtp:dot dir up)) 0.95)
                                (setq up '(0.0 1.0 0.0))
                              )
                              (setq catalogue (gtp:valve-catalogue-record family row series))
                              (setq id (strcat "VALVE-" (itoa *gtp-valve-next-id*)))
                              (setq comp
                                (gtp:make-valve-component
                                  id flow dn series pos dir up
                                  (gtp:catalogue-get catalogue 'length-mm)
                                  catalogue nil
                                )
                              )
                              (if (gtp:add-valve-component comp)
                                (progn
                                  (gtp:model-catalogue-valve comp catalogue)
                                  (princ
                                    (strcat
                                      "\nCreated " family
                                      " " id
                                      " | DN" (itoa dn)
                                      " | Series " (itoa series)
                                      " | L="
                                      (rtos (gtp:catalogue-get catalogue 'length-mm) 2 0)
                                      " mm"
                                      " | " (gtp:valve-family-name family) "."
                                    )
                                  )
                                  (princ "\nCatalogue-backed valve registered. GTPPIPE will split around its footprint."))
                                (princ "\nCould not register valve component."))
                            )
                            (princ
                              (strcat
                                "\nNo catalogue row exists for DN" (itoa dn)
                                " in family " family
                                ". Choose another family or DN."
                              )
                            )
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

; -----------------------------------------------------------------------------
; CATALOGUE INSPECTION
; -----------------------------------------------------------------------------
(defun c:GTPVALVECATALOG (/ family db)
  (setq family (gtp:valve-family-prompt))
  (setq db (gtp:valve-db-for-family family))
  (princ
    (strcat
      "\nCatalogue: " family
      " | " (gtp:valve-family-name family)
    )
  )
  (foreach row db
    (princ
      (strcat
        "\nCarrier OD " (rtos (car row) 2 1)
        " | L "
        (rtos
          (cond
            ((= family "SINGLE_SHUTOFF") (nth 10 row))
            ((= family "SINGLE_SHUTOFF_2VENT_DRAIN") (nth 13 row))
            ((= family "TWIN_SHUTOFF") (nth 12 row))
            (T (nth 9 row))
          )
          2 0
        )
        " mm"
      )
    )
  )
  (princ)
)

(princ "\nGTP Step 5 loaded: catalogue-backed valve variants are available.")
(princ)
