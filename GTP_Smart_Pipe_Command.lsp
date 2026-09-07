; GTP_SMART_PIPE_COMMAND.LSP
; =============================================================================
; Intelligent single-session GTPPIPE workflow.
;
; Loaded after GTP_Combined_Final_Bridge.lsp. This file intentionally overrides
; c:GTPPIPE while leaving all lower-level geometry/catalogue/component functions
; available for diagnostics and standalone use.
;
; Workflow:
;   1. Select ONE prepared LINE / 2D or 3D POLYLINE.
;   2. Choose units, base DN, insulation series, model mode, Flow/Return,
;      and elbow style once.
;   3. Add zero or more components from an in-command menu without reselecting
;      the route or re-entering the base pipe settings.
;   4. BUILD generates the straight pipe + route elbows around all persisted
;      component footprints.
;
; Route corners remain the source of elbow locations. Components are centre-
; based unless they are endpoint fittings such as END_CAP.
; =============================================================================

(vl-load-com)

(setq *gtp-smart-version* "1.0")

(defun gtp:smart-up-vector (dir / up)
  (setq up '(0.0 0.0 1.0))
  (if (> (abs (gtp:dot (gtp:vunit dir) up)) 0.95)
    (setq up '(0.0 1.0 0.0))
  )
  up
)

(defun gtp:smart-route-point-info (ent prompt / pick world info)
  (setq pick (getpoint prompt))
  (if pick
    (progn
      (setq world (trans pick 1 0))
      (setq info (gtp:curve-point-direction ent world))
      (if (and info
               (<= (distance world (car info)) (gtp:mm 5.0)))
        info
        (progn
          (princ "\nPick a point on/within 5 mm of the selected route.")
          nil
        )
      )
    )
    nil
  )
)

(defun gtp:smart-register-component (component)
  (cond
    ((and component (fboundp 'gtp:register-persistent-component))
      (gtp:register-persistent-component component)
    )
    ((and component (fboundp 'gtp:component-registry-add))
      (gtp:component-registry-add component)
    )
    (T component)
  )
)

(defun gtp:smart-component-id (prefix)
  (if (fboundp 'gtp:component-next-id)
    (gtp:component-next-id prefix)
    (strcat prefix "-" (itoa (1+ (length *gtp-component-registry*))))
  )
)

(defun gtp:smart-flow ()
  (if *gtp-flow-type* *gtp-flow-type* "Flow")
)

(defun gtp:smart-prompt-real-default (prompt default / x)
  (initget 6)
  (setq x
    (getreal
      (strcat
        "\n" prompt
        " <" (rtos default 2 1) ">: "
      )
    )
  )
  (if x x default)
)

(defun gtp:smart-prompt-dn (prompt defaultDn / dn row)
  (setq row nil)
  (while (null row)
    (initget 6)
    (setq dn
      (getint
        (strcat
          "\n" prompt
          " <" (itoa defaultDn) ">: "
        )
      )
    )
    (if (null dn) (setq dn defaultDn))
    (setq row (gtp:find-dn dn))
    (if (null row)
      (princ "\nDN is not in the current pipe catalogue.")
    )
  )
  row
)

(defun gtp:smart-vector-reverse (v)
  (gtp:vscale v -1.0)
)

(defun gtp:smart-place-valve (ent dn series / info pos dir up family row catalogue comp id)
  (setq info (gtp:smart-route-point-info ent "\nPick valve centre on route: "))
  (if info
    (progn
      (setq pos (car info) dir (cadr info) up (gtp:smart-up-vector dir))
      (setq family (gtp:valve-family-prompt))
      (setq row (gtp:valve-row-for-dn family dn))
      (if row
        (progn
          (setq catalogue (gtp:valve-catalogue-record family row series))
          (setq id (gtp:smart-component-id "VALVE"))
          (setq comp
            (gtp:make-valve-component
              id
              (gtp:smart-flow)
              dn
              series
              pos
              dir
              up
              (gtp:catalogue-get catalogue 'length-mm)
              catalogue
              nil
            )
          )
          (if (gtp:add-valve-component comp)
            (progn
              (gtp:model-catalogue-valve comp catalogue)
              (princ
                (strcat
                  "\nPlaced " id
                  " | " family
                  " | DN" (itoa dn)
                  " | footprint "
                  (rtos (gtp:catalogue-get catalogue 'length-mm) 2 0)
                  " mm."
                )
              )
              comp
            )
            (progn (princ "\nValve registration failed.") nil)
          )
        )
        (progn
          (princ
            (strcat
              "\nNo valve catalogue row for DN"
              (itoa dn)
              " in family " family "."
            )
          )
          nil
        )
      )
    )
    nil
  )
)

(defun gtp:smart-place-tee
  (ent dn series mainRow mainCasingMM / info pos dir up branchPt bdir branchRow branchDn
   bodyLen branchLen branchCasingMM catalogue comp id)

  (setq info (gtp:smart-route-point-info ent "\nPick tee centre on main route: "))
  (if info
    (progn
      (setq pos (car info) dir (cadr info) up (gtp:smart-up-vector dir))
      (setq branchPt (getpoint (trans pos 0 1) "\nPick branch direction/end point: "))
      (if branchPt
        (progn
          (setq branchPt (trans branchPt 1 0))
          (setq bdir (gtp:vunit (gtp:vsub branchPt pos)))
          (setq branchRow (gtp:smart-prompt-dn "Branch DN" dn))
          (setq branchDn (car branchRow))
          (setq bodyLen (gtp:smart-prompt-real-default "Tee main fitting length (mm)" 500.0))
          (setq branchLen
            (gtp:smart-prompt-real-default
              "Tee branch fitting length (mm)"
              500.0
            )
          )
          (setq branchCasingMM (gtp:casing-od branchRow series))
          (setq catalogue
            (list
              (cons 'family "TEE_SMART")
              (cons 'dimension-source "SESSION_APPROVED_DIMENSIONS")
              (cons 'length-mm bodyLen)
              (cons 'main-body-od-mm mainCasingMM)
              (cons 'branch-body-od-mm branchCasingMM)
              (cons 'branch-dn branchDn)
              (cons 'branch-length-mm branchLen)
            )
          )
          (setq id (gtp:smart-component-id "TEE"))
          (setq comp
            (gtp:component-make
              id "TEE" (gtp:smart-flow) dn series
              pos dir up bodyLen catalogue
              (list (cons 'branch-direction bdir))
            )
          )
          (if (gtp:smart-register-component comp)
            (progn
              (gtp:model-tee-component comp)
              (princ
                (strcat
                  "\nPlaced " id
                  " | main DN" (itoa dn)
                  " -> branch DN" (itoa branchDn) "."
                )
              )
              comp
            )
            (progn (princ "\nTEE registration failed.") nil)
          )
        )
        nil
      )
    )
    nil
  )
)

(defun gtp:smart-reducer-casing-for-row (row series smallSide)
  (cond
    ((= series 1) (if smallSide (nth 2 row) (nth 3 row)))
    ((= series 2) (if smallSide (nth 4 row) (nth 5 row)))
    (T            (if smallSide (nth 6 row) (nth 7 row)))
  )
)

(defun gtp:smart-model-reducer
  (component / p d len cat smallBody largeBody q1 q2 a b m1 m2)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq cat (gtp:component-get component 'catalogue))
  (setq len (gtp:mm (gtp:catalogue-get cat 'length-mm)))
  (setq smallBody (gtp:mm (gtp:catalogue-get cat 'small-casing-od-mm)))
  (setq largeBody (gtp:mm (gtp:catalogue-get cat 'large-casing-od-mm)))
  (setq q1 (gtp:vsub p (gtp:vscale d (/ len 2.0))))
  (setq q2 (gtp:vadd p (gtp:vscale d (/ len 2.0))))
  (setq m1 (gtp:point-along q1 q2 (* len 0.35)))
  (setq m2 (gtp:point-along q1 q2 (* len 0.65)))
  (gtp:make-cylinder q1 m1 smallBody "GTP-FITTING-BODY")
  (gtp:make-cylinder m1 m2 (/ (+ smallBody largeBody) 2.0) "GTP-FITTING-BODY")
  (gtp:make-cylinder m2 q2 largeBody "GTP-FITTING-BODY")
  component
)

(defun gtp:smart-place-reducer
  (ent dn series mainRow / info pos tangent otherRow otherDn currentOD otherOD small large
   family db row side sideVec largeDir smallCasing largeCasing catalogue comp id largeDn)

  (setq info (gtp:smart-route-point-info ent "\nPick reducer centre on route: "))
  (if info
    (progn
      (setq pos (car info) tangent (cadr info))
      (setq otherRow (gtp:smart-prompt-dn "Other-side DN" dn))
      (setq otherDn (car otherRow))
      (if (= otherDn dn)
        (progn
          (princ "\nReducer requires a different DN.")
          nil
        )
        (progn
          (setq currentOD (nth 1 mainRow) otherOD (nth 1 otherRow))
          (setq small (min currentOD otherOD) large (max currentOD otherOD))
          (initget "SINGLE TWIN")
          (setq family (getkword "\nReducer family [SINGLE/TWIN] <SINGLE>: "))
          (if (null family) (setq family "SINGLE"))
          (setq db
            (if (= family "TWIN")
              *gtp-reducer-twin-db*
              *gtp-reducer-single-db*
            )
          )
          (setq row (gtp:reducer-row-find db small large))
          (if row
            (progn
              (initget "Forward Backward")
              (setq side
                (getkword
                  "\nOther DN is on which route side [Forward/Backward] <Forward>: "
                )
              )
              (if (null side) (setq side "Forward"))
              (setq sideVec
                (if (= side "Backward")
                  (gtp:smart-vector-reverse tangent)
                  tangent
                )
              )
              ; Component direction points from SMALL side to LARGE side because
              ; the reducer modeller places small at -direction and large at +direction.
              (setq largeDir
                (if (> otherOD currentOD)
                  sideVec
                  (gtp:smart-vector-reverse sideVec)
                )
              )
              (setq smallCasing (gtp:smart-reducer-casing-for-row row series T))
              (setq largeCasing (gtp:smart-reducer-casing-for-row row series nil))
              (setq largeDn (if (> otherOD currentOD) otherDn dn))
              (setq catalogue
                (list
                  (cons 'family (if (= family "TWIN") "REDUCER_TWIN" "REDUCER_SINGLE"))
                  (cons 'dimension-source
                    (if (= family "TWIN")
                      "ISOPLUS_8.3_PAGE_116"
                      "ISOPLUS_5.3_PAGE_80"
                    )
                  )
                  (cons 'length-mm 1500.0)
                  (cons 'small-carrier-od-mm small)
                  (cons 'large-carrier-od-mm large)
                  (cons 'small-casing-od-mm smallCasing)
                  (cons 'large-casing-od-mm largeCasing)
                  (cons 'other-dn otherDn)
                )
              )
              (setq id (gtp:smart-component-id "REDUCER"))
              (setq comp
                (gtp:component-make
                  id "REDUCER" (gtp:smart-flow) largeDn series
                  pos largeDir (gtp:smart-up-vector largeDir)
                  1500.0 catalogue
                  (list
                    (cons 'base-dn dn)
                    (cons 'other-dn otherDn)
                    (cons 'other-side side)
                  )
                )
              )
              (if (gtp:smart-register-component comp)
                (progn
                  (gtp:smart-model-reducer comp)
                  (princ
                    (strcat
                      "\nPlaced " id
                      " | DN" (itoa dn)
                      " <-> DN" (itoa otherDn)
                      " | 1500 mm fitting."
                    )
                  )
                  (princ
                    "\nNote: the current route generation still uses the session base DN on both sides; the reducer fitting is modelled and its footprint is reserved."
                  )
                  comp
                )
                (progn (princ "\nReducer registration failed.") nil)
              )
            )
            (progn
              (princ "\nThat reducer size pair is not in the selected catalogue family.")
              nil
            )
          )
        )
      )
    )
    nil
  )
)

(defun gtp:smart-model-branch
  (component / p d cat len mainDia bdir branchLen branchDia q1 q2 endp)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq cat (gtp:component-get component 'catalogue))
  (setq len (gtp:mm (gtp:catalogue-get cat 'length-mm)))
  (setq mainDia (gtp:mm (gtp:catalogue-get cat 'main-body-od-mm)))
  (setq bdir (gtp:vunit (gtp:catalogue-get cat 'branch-direction)))
  (setq branchLen (gtp:mm (gtp:catalogue-get cat 'branch-length-mm)))
  (setq branchDia (gtp:mm (gtp:catalogue-get cat 'branch-od-mm)))
  (setq q1 (gtp:vsub p (gtp:vscale d (/ len 2.0))))
  (setq q2 (gtp:vadd p (gtp:vscale d (/ len 2.0))))
  (setq endp (gtp:vadd p (gtp:vscale bdir branchLen)))
  (gtp:make-cylinder q1 q2 mainDia "GTP-FITTING-BODY")
  (gtp:make-cylinder p endp branchDia "GTP-FITTING-BODY")
  component
)

(defun gtp:smart-place-branch
  (ent dn series mainCasingMM / info pos dir branchPt bdir branchRow branchDn
   branchLen branchCasingMM mainLen catalogue comp id)

  (setq info (gtp:smart-route-point-info ent "\nPick branch connection point on main route: "))
  (if info
    (progn
      (setq pos (car info) dir (cadr info))
      (setq branchPt (getpoint (trans pos 0 1) "\nPick branch endpoint/direction: "))
      (if branchPt
        (progn
          (setq branchPt (trans branchPt 1 0))
          (setq bdir (gtp:vunit (gtp:vsub branchPt pos)))
          (setq branchRow (gtp:smart-prompt-dn "Branch DN" dn))
          (setq branchDn (car branchRow))
          (setq branchCasingMM (gtp:casing-od branchRow series))
          (setq mainLen
            (gtp:smart-prompt-real-default
              "Main branch-joint footprint length (mm)"
              *gtp-branch-joint-length-mm*
            )
          )
          (setq branchLen
            (gtp:smart-prompt-real-default
              "Branch model length (mm)"
              *gtp-branch-joint-length-mm*
            )
          )
          (setq catalogue
            (list
              (cons 'family "WELDABLE_BRANCH_SMART")
              (cons 'dimension-source "ISOPLUS_16.12_REFERENCE")
              (cons 'length-mm mainLen)
              (cons 'main-body-od-mm mainCasingMM)
              (cons 'branch-dn branchDn)
              (cons 'branch-od-mm branchCasingMM)
              (cons 'branch-length-mm branchLen)
              (cons 'branch-direction bdir)
            )
          )
          (setq id (gtp:smart-component-id "BRANCH"))
          (setq comp
            (gtp:component-make
              id "BRANCH" (gtp:smart-flow) dn series
              pos dir (gtp:smart-up-vector dir)
              mainLen catalogue nil
            )
          )
          (if (gtp:smart-register-component comp)
            (progn
              (gtp:smart-model-branch comp)
              (princ
                (strcat
                  "\nPlaced " id
                  " | main DN" (itoa dn)
                  " -> branch DN" (itoa branchDn) "."
                )
              )
              comp
            )
            (progn (princ "\nBranch registration failed.") nil)
          )
        )
        nil
      )
    )
    nil
  )
)

(defun gtp:smart-place-endcap
  (ent dn series casingMM / pts choice endpoint dir thickness catalogue comp id n)

  (setq pts (gtp:curve-points ent))
  (if (and pts (>= (length pts) 2))
    (progn
      (setq n (length pts))
      (initget "Start End")
      (setq choice (getkword "\nCap route end [Start/End] <End>: "))
      (if (null choice) (setq choice "End"))
      (if (= choice "Start")
        (progn
          (setq endpoint (car pts))
          (setq dir (gtp:vunit (gtp:vsub (cadr pts) (car pts))))
        )
        (progn
          (setq endpoint (nth (1- n) pts))
          (setq dir
            (gtp:vunit
              (gtp:vsub (nth (1- n) pts) (nth (- n 2) pts))
            )
          )
        )
      )
      (setq thickness
        (gtp:smart-prompt-real-default
          "End-cap axial length/thickness (mm)"
          25.0
        )
      )
      (setq catalogue
        (list
          (cons 'family "END_CAP")
          (cons 'dimension-source "ISOPLUS_17.2_TO_17.5_REFERENCE")
          (cons 'length-mm thickness)
          (cons 'casing-od-mm casingMM)
          (cons 'thickness-mm thickness)
        )
      )
      (setq id (gtp:smart-component-id "END_CAP"))
      (setq comp
        (gtp:component-make
          id "END_CAP" (gtp:smart-flow) dn series
          endpoint dir (gtp:smart-up-vector dir)
          thickness catalogue nil
        )
      )
      (if (gtp:smart-register-component comp)
        (progn
          (gtp:model-end-cap-component comp)
          (princ
            (strcat
              "\nPlaced " id
              " at route " choice "."
            )
          )
          comp
        )
        (progn (princ "\nEnd-cap registration failed.") nil)
      )
    )
    (progn
      (princ "\nCould not read route endpoints.")
      nil
    )
  )
)

(defun gtp:smart-settings-summary (dn series carrierMM casingMM mode flowType style)
  (princ "\n----------------------------------------")
  (princ "\n GTPPIPE SMART SESSION")
  (princ "\n----------------------------------------")
  (princ
    (strcat
      "\nDN" (itoa dn)
      " | Series " (itoa series)
      " | carrier OD " (rtos carrierMM 2 1) " mm"
      " | casing OD " (rtos casingMM 2 1) " mm"
    )
  )
  (princ
    (strcat
      "\nMode " mode
      " | " flowType
      " | elbow " style
    )
  )
  (princ
    "\nRoute corners automatically become elbows; add other fittings/components below."
  )
)

(defun gtp:smart-component-menu
  (ent dn series row casingMM / choice added comp)
  (setq choice "" added 0)
  (while (and choice (/= choice "Build") (/= choice "Cancel"))
    (initget "Valve Tee Reducer Branch Endcap Status Build Cancel")
    (setq choice
      (getkword
        "\nComponent [Valve/Tee/Reducer/Branch/Endcap/Status/Build/Cancel] <Build>: "
      )
    )
    (if (null choice) (setq choice "Build"))
    (cond
      ((= choice "Valve")
        (setq comp (gtp:smart-place-valve ent dn series))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Tee")
        (setq comp
          (gtp:smart-place-tee
            ent dn series row (gtp:casing-od row series)
          )
        )
        (if comp (setq added (1+ added)))
      )
      ((= choice "Reducer")
        (setq comp (gtp:smart-place-reducer ent dn series row))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Branch")
        (setq comp
          (gtp:smart-place-branch
            ent dn series (gtp:casing-od row series)
          )
        )
        (if comp (setq added (1+ added)))
      )
      ((= choice "Endcap")
        (setq comp (gtp:smart-place-endcap ent dn series casingMM))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Status")
        (if (fboundp 'c:GTPCOMPONENTS)
          (c:GTPCOMPONENTS)
          (princ
            (strcat
              "\nComponents in registry: "
              (itoa
                (if *gtp-component-registry*
                  (length *gtp-component-registry*)
                  0
                )
              )
            )
          )
        )
      )
    )
  )
  (list choice added)
)

(defun gtp:smart-generate
  (pts dn carrier casing mode style / result)
  (princ "\nGenerating component-aware 3D pipe + route elbows...")
  (setq result (gtp:model-corner-route pts dn carrier casing mode style))
  (princ
    (strcat
      "\nCreated route: "
      (itoa (nth 0 result)) " straight spool(s) | "
      (itoa (nth 1 result)) " 3D elbow(s)."
    )
  )
  (if (> (nth 2 result) 0)
    (princ
      (strcat
        "\nNote: "
        (itoa (nth 2 result))
        " elbow fitting leg(s) were shortened to fit available route length."
      )
    )
  )
  result
)

(defun c:GTPPIPE
  (/ *error* old sel ent typ row dn series carrierMM casingMM carrier casing
   mode flowType style rawPts cleanInfo pts dupRemoved straightRemoved menuResult
   action added)

  (vl-load-com)

  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg
             (/= msg "Function cancelled")
             (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPPIPE smart-session error: " msg))
    )
    (princ)
  )

  (setq old (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)

  (setq sel (entsel "\nSelect prepared route LINE / 2D or 3D POLYLINE: "))
  (if sel
    (progn
      (setq ent (car sel))
      (setq typ (cdr (assoc 0 (entget ent))))
      (if (member typ '("LINE" "LWPOLYLINE" "POLYLINE"))
        (progn
          ; One-time session configuration.
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

          ; Route cleanup is performed before any component placement so both
          ; the preview/session and final model use the same route interpretation.
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
                  (itoa (length rawPts))
                  " input vertices -> "
                  (itoa (length pts))
                  " modelling vertices."
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

              (gtp:smart-settings-summary
                dn series carrierMM casingMM mode flowType style
              )

              (setq menuResult
                (gtp:smart-component-menu ent dn series row casingMM)
              )
              (setq action (car menuResult))
              (setq added (cadr menuResult))

              (if (= action "Build")
                (progn
                  (gtp:smart-generate pts dn carrier casing mode style)
                  (if (fboundp 'gtp:persist-all-components)
                    (gtp:persist-all-components)
                  )
                  (princ
                    (strcat
                      "\nGTPPIPE smart session complete. "
                      (itoa added)
                      " component(s) added during this session."
                    )
                  )
                )
                (princ
                  (strcat
                    "\nGTPPIPE modelling cancelled before BUILD. "
                    (itoa added)
                    " component(s) placed during this session remain persisted."
                  )
                )
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

(defun c:GTPPIPESMART ()
  (c:GTPPIPE)
)

; Extend combined diagnostics after this override loads.
(defun c:GTPSMARTTEST (/ ok)
  (setq ok T)
  (foreach fn
    '(gtp:smart-place-valve
      gtp:smart-place-tee
      gtp:smart-place-reducer
      gtp:smart-place-branch
      gtp:smart-place-endcap
      gtp:smart-component-menu
      gtp:smart-generate
      c:GTPPIPE)
    (if (not (fboundp fn))
      (progn
        (setq ok nil)
        (princ (strcat "\n[FAIL] " (vl-princ-to-string fn)))
      )
    )
  )
  (if ok
    (princ "\nGTPSMARTTEST PASS - intelligent GTPPIPE workflow is loaded.")
    (princ "\nGTPSMARTTEST FAIL.")
  )
  (princ)
)

(defun c:GTPHELP ()
  (princ "\nGTP combined AutoCAD 3D district-heating toolkit:")
  (princ "\n  GTPPIPE             Intelligent one-route modelling session")
  (princ "\n                      Select route + base settings once, add components, BUILD")
  (princ "\n  GTPPIPESMART        Alias for the intelligent GTPPIPE workflow")
  (princ "\n  GTPMITER            Join two route ends at their 3D axis intersection")
  (princ "\n  GTPMITTER           Alias for GTPMITER")
  (princ "\n  GTPUNITS            Set catalogue-mm to drawing-unit conversion")
  (princ "\n  GTPLAYER            Create/check GTP layers")
  (princ "\n  GTPVALVE            Standalone catalogue-backed valve placement")
  (princ "\n  GTPVALVECATALOG     Inspect supported valve catalogue")
  (princ "\n  GTPTEE              Standalone tee placement")
  (princ "\n  GTPREDUCER          Standalone reducer placement")
  (princ "\n  GTPBRANCH           Standalone branch placement")
  (princ "\n  GTPENDCAP           Standalone end-cap placement")
  (princ "\n  GTPCOMPONENTS       List persistent components")
  (princ "\n  GTPCOMPONENTRELOAD  Reload components stored in the DWG")
  (princ "\n  GTPCOMPONENTSAVE    Persist the current component registry")
  (princ "\n  GTPCOMBINEDTEST     Combined toolkit diagnostics")
  (princ "\n  GTPSMARTTEST        Intelligent GTPPIPE workflow diagnostics")
  (princ "\n")
  (princ "\nInside GTPPIPE, route corners automatically become elbows.")
  (princ "\nComponent menu: Valve / Tee / Reducer / Branch / Endcap / Status / Build / Cancel.")
  (princ)
)

(princ
  (strcat
    "\nGTP smart pipe workflow V" *gtp-smart-version*
    " loaded. GTPPIPE now runs one-route/one-setup component-aware modelling."
  )
)
(princ)
