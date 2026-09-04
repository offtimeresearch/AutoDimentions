; GTP_Component_Persistence_and_Fittings.lsp
; -----------------------------------------------------------------------------
; STEP 6 - Persistent component registry + non-valve pipework components.
;
; LOAD AFTER:
;   GTP_DH_TOOLKIT.lsp
;   GTP_Component_Architecture.lsp
;   GTP_Elbow_Component_Integration.lsp
;   GTP_Valve_Component.lsp
;   GTP_Valve_Aware_Pipe_Integration.lsp
;   GTP_Valve_Catalogue_Integration.lsp
;
; PURPOSE
;   1. Persist component records inside the DWG Named Object Dictionary.
;   2. Restore registered components when the DWG is reopened.
;   3. Keep the existing valve registry synchronized with persisted records.
;   4. Add first-class TEE, REDUCER, BRANCH and END_CAP component records.
;   5. Use verified catalogue values where the supplied ISOPLUS catalogue
;      supports them, and ask for manual dimensions where the source is not
;      sufficiently unambiguous for exact automated selection.
;
; IMPORTANT
;   This step does NOT yet merge all component types into the GTPPIPE route
;   modeller. Valve-aware GTPPIPE remains provided by Step 4. Full multi-
;   component route integration is intentionally reserved for the final merge.
;
; CATALOGUE SOURCES FROM THE SUPPLIED ISOPLUS CATALOGUE PDF:
;   - Reducers single: section 5.3, page 80, length 1500 mm for listed rows.
;   - Reducers twin: section 8.3, page 116, length 1500 mm for listed rows.
;   - Weldable flex branch: joint dimensions include 460x390 and 700x700 mm;
;     the catalogue states branch ranges and a 700 mm joint dimension.
;   - End caps single/twin/open: sections 17.2-17.5. The extracted table data
;     is not used as an automatic exact dimensional lookup here because the
;     source layout is not reliably represented by text extraction.
; -----------------------------------------------------------------------------

(vl-load-com)

(if (null *gtp-component-registry*) (setq *gtp-component-registry* '()))
(if (null *gtp-component-next-id*) (setq *gtp-component-next-id* 1))

; -----------------------------------------------------------------------------
; GENERIC REGISTRY
; -----------------------------------------------------------------------------
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
          (mapcar
            '(lambda (c)
               (if (= (gtp:component-get c 'id) id) component c)
             )
            *gtp-component-registry*
          )
        )
        (setq *gtp-component-registry*
          (append *gtp-component-registry* (list component))
        )
      )
      component
    )
  )
)

(defun gtp:component-registry-remove (id / out)
  (setq out '())
  (foreach component *gtp-component-registry*
    (if (/= (gtp:component-get component 'id) id)
      (setq out (append out (list component)))
    )
  )
  (setq *gtp-component-registry* out)
)

(defun gtp:component-registry-by-type (type)
  (gtp:components-by-type *gtp-component-registry* type)
)

; -----------------------------------------------------------------------------
; DWG PERSISTENCE - NAMED OBJECT DICTIONARY / XRECORD
; -----------------------------------------------------------------------------
(defun gtp:persistence-root (/ nod root)
  (setq nod (namedobjdict))
  (setq root (dictsearch nod "GTP_COMPONENTS"))
  (if root
    (cdr (assoc -1 root))
    (progn
      (setq root (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary"))))
      (if root
        (dictadd nod "GTP_COMPONENTS" root)
      )
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
          ; Remove previous XRECORD with the same component id when updating.
          (setq old (dictsearch root id))
          (if old
            (progn
              (setq xrec (cdr (assoc -1 old)))
              (dictremove root id)
              (if xrec (entdel xrec))
            )
          )

          (setq text (vl-prin1-to-string component))
          (setq xrec
            (entmakex
              (list
                '(0 . "XRECORD")
                '(100 . "AcDbXrecord")
                (cons 1 text)
              )
            )
          )
          (if xrec
            (progn
              (dictadd root id xrec)
              T
            )
            nil
          )
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
            (if (and component (gtp:component-valid-p component))
              (setq loaded (append loaded (list component)))
            )
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
    (if (gtp:persist-component component)
      (setq count (1+ count))
    )
  )
  count
)

(defun gtp:sync-valve-registry-from-components (/ component valves maxid id n)
  (setq valves '() maxid 0)
  (foreach component *gtp-component-registry*
    (if (= (gtp:component-get component 'type) "VALVE")
      (setq valves (append valves (list component)))
    )
    (setq id (gtp:component-get component 'id))
    (if (and id (wcmatch id "VALVE-*,REDUCER-*,TEE-*,BRANCH-*,END_CAP-*") )
      (progn
        (setq n (atoi (substr id (+ 2 (vl-string-search "-" id)))))
        (if (> n maxid) (setq maxid n))
      )
    )
  )
  (setq *gtp-valve-components* valves)
  (if (> maxid (1- *gtp-component-next-id*))
    (setq *gtp-component-next-id* (1+ maxid))
  )
  valves
)

(defun gtp:register-persistent-component (component)
  (if (gtp:component-registry-add component)
    (progn
      (gtp:persist-component component)
      component
    )
  )
)

(defun gtp:component-store-command-message (component)
  (princ
    (strcat
      "\nStored "
      (gtp:component-get component 'type)
      " "
      (gtp:component-get component 'id)
      " in the DWG component registry."
    )
  )
)

; -----------------------------------------------------------------------------
; PERSISTENCE OVERRIDE FOR THE EXISTING VALVE REGISTRATION
; -----------------------------------------------------------------------------
; Step 5's GTPVALVE command calls gtp:add-valve-component when creating a
; valve. Redefining this function here makes newly-created valves persistent
; without changing the Step 5 file itself.
;
(defun gtp:add-valve-component (component)
  (if (gtp:component-valid-p component)
    (progn
      (if (null *gtp-valve-components*) (setq *gtp-valve-components* '()))
      (setq *gtp-valve-components*
        (append
          (vl-remove-if
            '(lambda (c)
               (= (gtp:component-get c 'id) (gtp:component-get component 'id)))
            *gtp-valve-components*
          )
          (list component)
        )
      )
      (gtp:component-registry-add component)
      (gtp:persist-component component)
      component
    )
  )
)

; -----------------------------------------------------------------------------
; FITTING CATALOGUE - REDUCERS
; -----------------------------------------------------------------------------
;
; Single reducer rows from ISOPLUS section 5.3 / page 80.
; Row = (smallCarrierOD largeCarrierOD S1small S1large S2small S2large
;        S3small S3large length)
;
(setq *gtp-reducer-single-db*
  '(
    (26.9  33.7  90 110 110 125 125 140 1500)
    (26.9  42.4  90 110 110 125 125 140 1500)
    (33.7  42.4  90 110 110 125 125 140 1500)
    (33.7  48.3  90 110 110 125 125 140 1500)
    (42.4  48.3 110 110 125 125 140 140 1500)
    (42.4  60.3 110 125 125 140 140 160 1500)
    (48.3  60.3 110 125 125 140 140 160 1500)
    (48.3  76.1 110 140 125 160 140 180 1500)
    (60.3  76.1 125 140 140 160 160 180 1500)
    (60.3  88.9 125 160 140 180 160 200 1500)
    (76.1  88.9 140 160 160 180 180 200 1500)
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

; Twin reducer rows from ISOPLUS section 8.3 / page 116.
; Pair OD is represented by one carrier outside diameter because both legs are
; twin pipes of the same size.
(setq *gtp-reducer-twin-db*
  '(
    (26.9  33.7  125 140 140 160 160 180 1500)
    (33.7  42.4  140 160 160 180 180 200 1500)
    (42.4  48.3  160 160 180 180 200 200 1500)
    (48.3  60.3  160 200 180 225 200 250 1500)
    (60.3  76.1  200 225 225 250 250 280 1500)
    (76.1  88.9  225 250 250 280 280 315 1500)
    (88.9 114.3  250 315 280 355 315 400 1500)
    (114.3 139.7 315 400 355 450 400 500 1500)
    (139.7 168.3 400 450 450 500 500 560 1500)
    (168.3 219.1 450 560 500 630 560 710 1500)
    (219.1 273.0 560 710 630 800 710 900 1500)
  )
)

(defun gtp:reducer-row-find (db small large / row)
  (setq row nil)
  (foreach r db
    (if (and (null row)
             (< (abs (- (car r) small)) 0.01)
             (< (abs (- (cadr r) large)) 0.01))
      (setq row r)
    )
  )
  row
)

; -----------------------------------------------------------------------------
; BRANCH CATALOGUE REFERENCES
; -----------------------------------------------------------------------------
(setq *gtp-branch-joint-length-mm* 700.0)

; These ranges are intentionally catalog metadata, not geometry assumptions.
(setq *gtp-branch-single-range*
  '((90 140) (90 250))
)
(setq *gtp-branch-twin-range*
  '((90 160) (90 250))
)

(defun gtp:branch-range-p (branchOD mainOD / ok)
  (setq ok nil)
  (foreach r *gtp-branch-single-range*
    (if (and (>= branchOD (car r))
             (<= branchOD (cadr r))
             (>= mainOD 125.0)
             (<= mainOD 630.0))
      (setq ok T)
    )
  )
  ok
)

; -----------------------------------------------------------------------------
; GEOMETRY HELPERS FOR FITTINGS
; -----------------------------------------------------------------------------
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
  ; Parametric reducer representation: two diameter sections plus a short
  ; transition section. The catalogue remains the dimensional source.
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

; -----------------------------------------------------------------------------
; TEEs
; -----------------------------------------------------------------------------
(defun c:GTPTEE (/ *error* old sel ent pick info row dn series flow up branchPt bdir bodyLen branchLen branchOD catalogue comp)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPTEE error: " msg)))
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
                          (setq catalogue
                            (list
                              (cons 'family "TEE_GENERIC")
                              (cons 'dimension-source "USER_APPROVED_PROJECT_DIMENSIONS")
                              (cons 'main-body-od-mm (nth 1 row))
                              (cons 'branch-body-od-mm branchOD)
                              (cons 'branch-length-mm branchLen)
                            )
                          )
                          (setq comp
                            (gtp:make-generic-component
                              (gtp:component-next-id "TEE")
                              flow dn series (car info) (cadr info) up
                              bodyLen catalogue
                              (list (cons 'branch-direction bdir))
                            )
                          )
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

; -----------------------------------------------------------------------------
; REDUCERS
; -----------------------------------------------------------------------------
(defun c:GTPREDUCER (/ *error* old family srow small large row series flow pos dir catalogue comp route pick info dn dummy)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPREDUCER error: " msg)))
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
      (setq row
        (if (= family "SINGLE")
          (gtp:reducer-row-find *gtp-reducer-single-db* small large)
          (gtp:reducer-row-find *gtp-reducer-twin-db* small large)
        )
      )
      (if row
        (progn
          (setq route (entsel "\nSelect route LINE / POLYLINE containing reducer: "))
          (if route
            (progn
              (setq pick (getpoint "\nPick reducer centre on route: "))
              (setq info (gtp:curve-point-direction (car route) (trans pick 1 0)))
              (if info
                (progn
                  (setq dn (getint "\nReducer larger-side DN (for component metadata): "))
                  (if (null dn) (setq dn 0))
                  (setq series (gtp:get-series))
                  (setq flow (if *gtp-flow-type* *gtp-flow-type* "Flow"))
                  (setq catalogue
                    (list
                      (cons 'family (if (= family "SINGLE") "REDUCER_SINGLE" "REDUCER_TWIN"))
                      (cons 'dimension-source (if (= family "SINGLE") "ISOPLUS_5.3_PAGE_80" "ISOPLUS_8.3_PAGE_116"))
                      (cons 'small-carrier-od-mm small)
                      (cons 'large-carrier-od-mm large)
                      (cons 'length-mm 1500.0)
                      (cons 'small-casing-s1-mm (nth 2 row))
                      (cons 'large-casing-s1-mm (nth 3 row))
                    )
                  )
                  (setq comp
                    (gtp:make-generic-component
                      (gtp:component-next-id "REDUCER")
                      flow dn series (car info) (cadr info) '(0.0 0.0 1.0)
                      1500.0 catalogue nil
                    )
                  )
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

; -----------------------------------------------------------------------------
; BRANCH
; -----------------------------------------------------------------------------
(defun c:GTPBRANCH (/ *error* old sel ent pick info row dn series flow branchPt bdir branchOD branchLen catalogue comp)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPBRANCH error: " msg)))
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
                      (setq catalogue
                        (list
                          (cons 'family "WELDABLE_BRANCH")
                          (cons 'dimension-source "ISOPLUS_16.12_REFERENCE")
                          (cons 'main-joint-length-mm *gtp-branch-joint-length-mm*)
                          (cons 'branch-od-mm branchOD)
                          (cons 'branch-length-mm branchLen)
                          (cons 'branch-direction bdir)
                        )
                      )
                      (setq comp
                        (gtp:make-generic-component
                          (gtp:component-next-id "BRANCH")
                          flow dn series (car info) (cadr info) '(0.0 0.0 1.0)
                          *gtp-branch-joint-length-mm* catalogue nil
                        )
                      )
                      (gtp:register-persistent-component comp)
                      (gtp:model-branch-component comp)
                      (gtp:component-store-command-message comp)
                      (if (not (gtp:branch-range-p branchOD (nth 2 row)))
                        (princ "\nGTP warning: branch diameter/main casing combination is outside the basic catalogue reference range."))
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

; -----------------------------------------------------------------------------
; END CAP
; -----------------------------------------------------------------------------
(defun c:GTPENDCAP (/ *error* old sel ent choice pts p dir row dn series flow casing catalogue thickness comp endpoint)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPENDCAP error: " msg)))
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
                  (if (null casing) (setq casing (gtp:casing-od dn series)))
                  (setq thickness (getreal "\nCap thickness / axial length (mm) <25>: "))
                  (if (null thickness) (setq thickness 25.0))
                  (setq catalogue
                    (list
                      (cons 'family "END_CAP")
                      (cons 'dimension-source "ISOPLUS_17.2_TO_17.5_REFERENCE")
                      (cons 'casing-od-mm casing)
                      (cons 'thickness-mm thickness)
                    )
                  )
                  (setq comp
                    (gtp:make-generic-component
                      (gtp:component-next-id "END_CAP")
                      flow dn series endpoint dir '(0.0 0.0 1.0)
                      thickness catalogue nil
                    )
                  )
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

; -----------------------------------------------------------------------------
; COMPONENT INSPECTION / RESTORE
; -----------------------------------------------------------------------------
(defun c:GTPCOMPONENTS (/ count)
  (setq count (length *gtp-component-registry*))
  (princ (strcat "\nPersistent GTP components: " (itoa count)))
  (if (> count 0)
    (princ (strcat "\n" (gtp:components-summary *gtp-component-registry*)))
  )
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
; STARTUP RESTORE
; -----------------------------------------------------------------------------
(gtp:load-persisted-components)
(gtp:sync-valve-registry-from-components)

(princ
  "\nGTP Step 6 loaded: persistent component registry + TEE/REDUCER/BRANCH/END_CAP foundations ready."
)
(princ)