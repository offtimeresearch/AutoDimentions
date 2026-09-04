; GTP_Valve_Component.lsp
; -----------------------------------------------------------------------------
; STEP 3 - First real component: SINGLE_SHUTOFF_VALVE.
;
; Load after:
;   GTP_DH_TOOLKIT.lsp
;   GTP_Component_Architecture.lsp
;   GTP_Elbow_Component_Integration.lsp
;
; No manufacturer dimensions are invented here. The repository currently has
; no verified isoplus valve dimensional table, so GTPVALVE asks for the
; approved catalogue values and stores them in the component catalogue record.
;
; STEP 3 provides:
;   - centre-based valve component
;   - route tangent alignment
;   - simple parametric valve body/stem geometry
;   - in-memory valve registry
;
; STEP 4 will make GTPPIPE split its pipe around registered valve footprints.
; -----------------------------------------------------------------------------

(vl-load-com)

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
              (setq a (vl-catch-all-apply 'vlax-curve-getPointAtParam
                          (list ent (max 0.0 (- param eps)))))
              (setq b (vl-catch-all-apply 'vlax-curve-getPointAtParam
                          (list ent (+ param eps))))
              (if (and (not (vl-catch-all-error-p a))
                       (not (vl-catch-all-error-p b))
                       (> (distance a b) 1e-10))
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
    )
    nil
  )
)

(defun gtp:add-valve-component (component)
  (if (gtp:component-valid-p component)
    (progn
      (setq *gtp-valve-components*
        (append *gtp-valve-components* (list component)))
      (setq *gtp-valve-next-id* (1+ *gtp-valve-next-id*))
      component
    )
  )
)

(defun gtp:model-single-shutoff-valve (component / p d up len body stem half flange collar p0 p1 s1 s2 s3 s4 sb st)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq up (gtp:component-get component 'up))
  (setq len (gtp:component-get component 'length))
  (setq body
    (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'body-od-mm)))
  (setq stem
    (gtp:mm (gtp:catalogue-get (gtp:component-get component 'catalogue) 'stem-height-mm)))
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
    (if (and dn (null row)) (princ "\nDN not in current pipe database."))
  )
  row
)

(defun c:GTPVALVE (/ *error* old sel ent pick info pos dir row dn series flow up len body stem comp)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPVALVE error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (if (not (fboundp 'gtp:make-valve-component))
    (princ "\nLoad GTP_Component_Architecture.lsp first.")
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
                          (setq dn (car row) series (gtp:get-series))
                          (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                          (setq up '(0.0 0.0 1.0))
                          (if (> (abs (gtp:dot dir up)) 0.95) (setq up '(0.0 1.0 0.0)))
                          (princ "\nEnter the approved isoplus catalogue dimensions; no manufacturer values are hard-coded.")
                          (setq len (gtp:valve-positive "Valve overall length (mm)" 500.0))
                          (setq body (gtp:valve-positive "Valve body outside diameter (mm)" (+ (nth 2 row) 100.0)))
                          (setq stem (gtp:valve-positive "Valve stem height (mm)" 300.0))
                          (setq comp
                            (gtp:make-single-shutoff-valve
                              (strcat "VALVE-" (itoa *gtp-valve-next-id*))
                              flow dn series pos dir up len body stem))
                          (if (gtp:add-valve-component comp)
                            (progn
                              (gtp:model-single-shutoff-valve comp)
                              (princ
                                (strcat "\nCreated SINGLE_SHUTOFF_VALVE "
                                        (gtp:component-get comp 'id)
                                        " | DN" (itoa dn)
                                        " | L=" (rtos len 2 2) " mm."))
                              (princ "\nComponent registered. GTPPIPE splitting is Step 4."))
                            (princ "\nCould not register valve component."))
                        )
                        (princ "\nCould not determine route tangent."))
                    )
                    (princ "\nPick a point within 5 mm of the route."))
                )
              )
            )
            (princ "\nSelected object must be a LINE/POLYLINE.")))
        (princ "\nNothing selected."))))
  (setvar "CMDECHO" old)
  (princ)
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

(princ "\nGTP Step 3 loaded: GTPVALVE creates single shut-off valve components.")
(princ)
