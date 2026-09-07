; GTP_VARIABLE_DN_ROUTE.LSP
; =============================================================================
; Reducer-driven variable-DN route generation for the intelligent GTPPIPE.
;
; Loaded AFTER GTP_Smart_Pipe_Command.lsp. This module intentionally overrides
; the smart session menu/GTPPIPE generation path while keeping the proven solid
; primitives, elbow geometry, component persistence and catalogue data intact.
;
; DN RULE
;   - The DN chosen at GTPPIPE setup is the DN at ROUTE START.
;   - Reducers are placed in route order, Start -> End.
;   - Each reducer changes the current DN to a new DN toward ROUTE END.
;   - Straight pipe and every downstream elbow use the resulting local DN.
;   - Valves, tees, branches and end caps placed after reducers also use the
;     local DN at their route station.
;
; This deterministic Start->End rule avoids an ambiguous reducer direction and
; allows multiple reducers in one route (for example DN200 -> DN150 -> DN100).
; =============================================================================

(vl-load-com)

(setq *gtp-variable-dn-version* "1.0")

; -----------------------------------------------------------------------------
; ROUTE STATIONING
; -----------------------------------------------------------------------------
(defun gtp:vcdn-route-point-data
  (pts point / best bestDist cum i a b seg len dir proj along foot lateral)
  (setq best nil bestDist 1e99 cum 0.0 i 0)
  (while (< i (1- (length pts)))
    (setq a (nth i pts) b (nth (1+ i) pts))
    (setq seg (gtp:vsub b a) len (distance a b))
    (if (> len 1e-10)
      (progn
        (setq dir (gtp:vunit seg))
        (setq proj (gtp:dot (gtp:vsub point a) dir))
        (setq along (max 0.0 (min len proj)))
        (setq foot (gtp:vadd a (gtp:vscale dir along)))
        (setq lateral (distance point foot))
        (if (< lateral bestDist)
          (progn
            (setq bestDist lateral)
            (setq best
              (list
                (cons 'station (+ cum along))
                (cons 'segment-index i)
                (cons 'segment-start-station cum)
                (cons 'segment-length len)
                (cons 'offset along)
                (cons 'point foot)
                (cons 'direction dir)
                (cons 'lateral lateral)
              )
            )
          )
        )
      )
    )
    (setq cum (+ cum len))
    (setq i (1+ i))
  )
  best
)

(defun gtp:vcdn-route-total-length (pts / total i)
  (setq total 0.0 i 0)
  (while (< i (1- (length pts)))
    (setq total (+ total (distance (nth i pts) (nth (1+ i) pts))))
    (setq i (1+ i))
  )
  total
)

(defun gtp:vcdn-vertex-stations (pts / out total i)
  (setq out (list 0.0) total 0.0 i 0)
  (while (< i (1- (length pts)))
    (setq total (+ total (distance (nth i pts) (nth (1+ i) pts))))
    (setq out (append out (list total)))
    (setq i (1+ i))
  )
  out
)

(defun gtp:vcdn-du-to-mm (x)
  (if (> (abs *gtp-mm-to-du*) 1e-12)
    (/ x *gtp-mm-to-du*)
    x
  )
)

(defun gtp:vcdn-component-on-route-data (pts component / pos data cdir rdir align)
  (setq pos (gtp:component-get component 'position))
  (if pos
    (progn
      (setq data (gtp:vcdn-route-point-data pts pos))
      (if data
        (progn
          (setq cdir (gtp:component-get component 'direction))
          (setq rdir (cdr (assoc 'direction data)))
          (setq align (if cdir (abs (gtp:dot (gtp:vunit cdir) rdir)) 1.0))
          (if (and (<= (cdr (assoc 'lateral data)) (gtp:mm 5.0))
                   (>= align 0.95))
            data
            nil
          )
        )
        nil
      )
    )
    nil
  )
)

; -----------------------------------------------------------------------------
; REDUCER TRANSITIONS
; -----------------------------------------------------------------------------
(defun gtp:vcdn-reducer-transition (pts component / data opt startDn endDn side station)
  (if (= (gtp:component-get component 'type) "REDUCER")
    (progn
      (setq data (gtp:vcdn-component-on-route-data pts component))
      (if data
        (progn
          (setq opt (gtp:component-get component 'options))
          (setq startDn (if opt (gtp:component-get opt 'route-start-dn) nil))
          (setq endDn (if opt (gtp:component-get opt 'route-end-dn) nil))
          (setq station (cdr (assoc 'station data)))

          ; Compatibility with the previous smart reducer records.
          (if (or (null startDn) (null endDn))
            (progn
              (setq side (if opt (gtp:component-get opt 'other-side) nil))
              (if (= side "Forward")
                (progn
                  (setq startDn (gtp:component-get opt 'base-dn))
                  (setq endDn (gtp:component-get opt 'other-dn))
                )
              )
              (if (= side "Backward")
                (progn
                  (setq startDn (gtp:component-get opt 'other-dn))
                  (setq endDn (gtp:component-get opt 'base-dn))
                )
              )
            )
          )

          (if (and startDn endDn)
            (list
              (cons 'station station)
              (cons 'start-dn startDn)
              (cons 'end-dn endDn)
              (cons 'component component)
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

(defun gtp:vcdn-route-reducers (pts / out component tr)
  (setq out '())
  (if *gtp-component-registry*
    (foreach component *gtp-component-registry*
      (setq tr (gtp:vcdn-reducer-transition pts component))
      (if tr (setq out (append out (list tr))))
    )
  )
  (vl-sort
    out
    '(lambda (a b)
       (< (cdr (assoc 'station a)) (cdr (assoc 'station b)))
     )
  )
)

(defun gtp:vcdn-validate-transitions (startDn transitions / current ok tr a b id)
  (setq current startDn ok T)
  (foreach tr transitions
    (setq a (cdr (assoc 'start-dn tr)))
    (setq b (cdr (assoc 'end-dn tr)))
    (setq id
      (gtp:component-get
        (cdr (assoc 'component tr))
        'id
      )
    )
    (if (/= a current)
      (progn
        (setq ok nil)
        (princ
          (strcat
            "\nVariable-DN validation error at "
            (if id id "REDUCER")
            ": route arrives as DN" (itoa current)
            " but reducer start side is DN" (itoa a) "."
          )
        )
      )
    )
    (setq current b)
  )
  ok
)

(defun gtp:vcdn-dn-at-station (startDn transitions station / dn tr)
  (setq dn startDn)
  (foreach tr transitions
    (if (> station (cdr (assoc 'station tr)))
      (setq dn (cdr (assoc 'end-dn tr)))
    )
  )
  dn
)

(defun gtp:vcdn-dn-at-point (pts startDn point / data transitions)
  (setq data (gtp:vcdn-route-point-data pts point))
  (setq transitions (gtp:vcdn-route-reducers pts))
  (if data
    (gtp:vcdn-dn-at-station startDn transitions (cdr (assoc 'station data)))
    startDn
  )
)

(defun gtp:vcdn-last-reducer-station (pts / reducers)
  (setq reducers (gtp:vcdn-route-reducers pts))
  (if reducers
    (cdr (assoc 'station (last reducers)))
    nil
  )
)

(defun gtp:vcdn-downstream-nonreducer-count (pts station / count component data type)
  (setq count 0)
  (if *gtp-component-registry*
    (foreach component *gtp-component-registry*
      (setq type (gtp:component-get component 'type))
      (if (/= type "REDUCER")
        (progn
          (setq data (gtp:vcdn-component-on-route-data pts component))
          (if (and data (> (cdr (assoc 'station data)) station))
            (setq count (1+ count))
          )
        )
      )
    )
  )
  count
)

(defun gtp:vcdn-reducer-spacing-ok-p (pts station / reducers tr other minSpace ok)
  (setq reducers (gtp:vcdn-route-reducers pts))
  (setq minSpace (gtp:mm 1500.0) ok T)
  (foreach tr reducers
    (setq other (cdr (assoc 'station tr)))
    (if (< (abs (- station other)) minSpace)
      (setq ok nil)
    )
  )
  ok
)

(defun gtp:vcdn-print-zones (pts startDn / reducers total cursor current tr s)
  (setq reducers (gtp:vcdn-route-reducers pts))
  (setq total (gtp:vcdn-route-total-length pts))
  (setq cursor 0.0 current startDn)
  (princ "\nDN zones from route Start -> End:")
  (foreach tr reducers
    (setq s (cdr (assoc 'station tr)))
    (princ
      (strcat
        "\n  " (rtos (gtp:vcdn-du-to-mm cursor) 2 0)
        " to " (rtos (gtp:vcdn-du-to-mm s) 2 0)
        " mm : DN" (itoa current)
      )
    )
    (setq current (cdr (assoc 'end-dn tr)))
    (setq cursor s)
  )
  (princ
    (strcat
      "\n  " (rtos (gtp:vcdn-du-to-mm cursor) 2 0)
      " to " (rtos (gtp:vcdn-du-to-mm total) 2 0)
      " mm : DN" (itoa current)
    )
  )
  (princ)
)

; -----------------------------------------------------------------------------
; LOCAL-DN COMPONENT PLACEMENT
; -----------------------------------------------------------------------------
(defun gtp:vcdn-place-valve (ent pts startDn series / info pos dir up localDn family row catalogue comp id)
  (setq info (gtp:smart-route-point-info ent "\nPick valve centre on route: "))
  (if info
    (progn
      (setq pos (car info) dir (cadr info))
      (setq localDn (gtp:vcdn-dn-at-point pts startDn pos))
      (setq up (gtp:smart-up-vector dir))
      (setq family (gtp:valve-family-prompt))
      (setq row (gtp:valve-row-for-dn family localDn))
      (if row
        (progn
          (setq catalogue (gtp:valve-catalogue-record family row series))
          (setq id (gtp:smart-component-id "VALVE"))
          (setq comp
            (gtp:make-valve-component
              id (gtp:smart-flow) localDn series pos dir up
              (gtp:catalogue-get catalogue 'length-mm)
              catalogue nil
            )
          )
          (if (gtp:add-valve-component comp)
            (progn
              (gtp:model-catalogue-valve comp catalogue)
              (princ
                (strcat
                  "\nPlaced " id " | " family
                  " | local DN" (itoa localDn) "."
                )
              )
              comp
            )
            nil
          )
        )
        (progn
          (princ (strcat "\nNo valve catalogue row for local DN" (itoa localDn) "."))
          nil
        )
      )
    )
    nil
  )
)

(defun gtp:vcdn-place-tee
  (ent pts startDn series / info pos dir up localDn mainRow mainCasingMM branchPt bdir
   branchRow branchDn bodyLen branchLen branchCasingMM catalogue comp id)
  (setq info (gtp:smart-route-point-info ent "\nPick tee centre on main route: "))
  (if info
    (progn
      (setq pos (car info) dir (cadr info))
      (setq localDn (gtp:vcdn-dn-at-point pts startDn pos))
      (setq mainRow (gtp:find-dn localDn))
      (setq mainCasingMM (gtp:casing-od mainRow series))
      (setq up (gtp:smart-up-vector dir))
      (setq branchPt (getpoint (trans pos 0 1) "\nPick branch direction/end point: "))
      (if branchPt
        (progn
          (setq branchPt (trans branchPt 1 0))
          (setq bdir (gtp:vunit (gtp:vsub branchPt pos)))
          (setq branchRow (gtp:smart-prompt-dn "Branch DN" localDn))
          (setq branchDn (car branchRow))
          (setq bodyLen (gtp:smart-prompt-real-default "Tee main fitting length (mm)" 500.0))
          (setq branchLen (gtp:smart-prompt-real-default "Tee branch fitting length (mm)" 500.0))
          (setq branchCasingMM (gtp:casing-od branchRow series))
          (setq catalogue
            (list
              (cons 'family "TEE_SMART_VARIABLE_DN")
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
              id "TEE" (gtp:smart-flow) localDn series
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
                  " | local main DN" (itoa localDn)
                  " -> branch DN" (itoa branchDn) "."
                )
              )
              comp
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

(defun gtp:vcdn-place-branch
  (ent pts startDn series / info pos dir localDn mainRow mainCasingMM branchPt bdir
   branchRow branchDn branchCasingMM mainLen branchLen catalogue comp id)
  (setq info (gtp:smart-route-point-info ent "\nPick branch connection point on main route: "))
  (if info
    (progn
      (setq pos (car info) dir (cadr info))
      (setq localDn (gtp:vcdn-dn-at-point pts startDn pos))
      (setq mainRow (gtp:find-dn localDn))
      (setq mainCasingMM (gtp:casing-od mainRow series))
      (setq branchPt (getpoint (trans pos 0 1) "\nPick branch endpoint/direction: "))
      (if branchPt
        (progn
          (setq branchPt (trans branchPt 1 0))
          (setq bdir (gtp:vunit (gtp:vsub branchPt pos)))
          (setq branchRow (gtp:smart-prompt-dn "Branch DN" localDn))
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
              (cons 'family "WELDABLE_BRANCH_VARIABLE_DN")
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
              id "BRANCH" (gtp:smart-flow) localDn series
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
                  " | local main DN" (itoa localDn)
                  " -> branch DN" (itoa branchDn) "."
                )
              )
              comp
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

(defun gtp:vcdn-place-endcap
  (ent pts startDn series / routePts choice endpoint dir station transitions localDn row casingMM
   thickness catalogue comp id n)
  (setq routePts (gtp:curve-points ent))
  (if (and routePts (>= (length routePts) 2))
    (progn
      (setq n (length routePts))
      (setq transitions (gtp:vcdn-route-reducers pts))
      (initget "Start End")
      (setq choice (getkword "\nCap route end [Start/End] <End>: "))
      (if (null choice) (setq choice "End"))
      (if (= choice "Start")
        (progn
          (setq endpoint (car routePts))
          (setq dir (gtp:vunit (gtp:vsub (cadr routePts) (car routePts))))
          (setq station 0.0)
        )
        (progn
          (setq endpoint (nth (1- n) routePts))
          (setq dir (gtp:vunit (gtp:vsub (nth (1- n) routePts) (nth (- n 2) routePts))))
          (setq station (gtp:vcdn-route-total-length pts))
        )
      )
      (setq localDn (gtp:vcdn-dn-at-station startDn transitions station))
      (setq row (gtp:find-dn localDn))
      (setq casingMM (gtp:casing-od row series))
      (setq thickness (gtp:smart-prompt-real-default "End-cap axial length/thickness (mm)" 25.0))
      (setq catalogue
        (list
          (cons 'family "END_CAP_VARIABLE_DN")
          (cons 'dimension-source "ISOPLUS_17.2_TO_17.5_REFERENCE")
          (cons 'length-mm thickness)
          (cons 'casing-od-mm casingMM)
          (cons 'thickness-mm thickness)
        )
      )
      (setq id (gtp:smart-component-id "END_CAP"))
      (setq comp
        (gtp:component-make
          id "END_CAP" (gtp:smart-flow) localDn series
          endpoint dir (gtp:smart-up-vector dir)
          thickness catalogue nil
        )
      )
      (if (gtp:smart-register-component comp)
        (progn
          (gtp:model-end-cap-component comp)
          (princ
            (strcat
              "\nPlaced " id " at route " choice
              " | local DN" (itoa localDn) "."
            )
          )
          comp
        )
        nil
      )
    )
    nil
  )
)

; -----------------------------------------------------------------------------
; REDUCER PLACEMENT - DEFINES THE DN TRANSITION
; -----------------------------------------------------------------------------
(defun gtp:vcdn-place-reducer
  (ent pts startDn series / info pos routeData station segLen offset lastStation downstreamCount
   transitions currentDn currentRow otherRow otherDn currentOD otherOD small large family db row
   routeDir largeDir smallCasing largeCasing catalogue comp id largeDn)

  (setq info (gtp:smart-route-point-info ent "\nPick reducer centre on route: "))
  (if info
    (progn
      (setq pos (car info))
      (setq routeData (gtp:vcdn-route-point-data pts pos))
      (setq station (cdr (assoc 'station routeData)))
      (setq segLen (cdr (assoc 'segment-length routeData)))
      (setq offset (cdr (assoc 'offset routeData)))

      ; A 1500 mm reducer must remain fully inside one straight route segment.
      (if (or (< offset (gtp:mm 750.0))
              (< (- segLen offset) (gtp:mm 750.0)))
        (progn
          (princ "\nReducer centre must be at least 750 mm from either end/corner of its straight route segment.")
          nil
        )
        (progn
          ; Reducers are intentionally placed from route Start -> End so local
          ; DN state is deterministic even with multiple transitions.
          (setq lastStation (gtp:vcdn-last-reducer-station pts))
          (if (and lastStation (<= station lastStation))
            (progn
              (princ "\nPlace reducers in route order from Start toward End. This reducer is upstream of an existing reducer.")
              nil
            )
            (progn
              (if (not (gtp:vcdn-reducer-spacing-ok-p pts station))
                (progn
                  (princ "\nReducer footprints would overlap. Keep reducer centres at least 1500 mm apart.")
                  nil
                )
                (progn
                  (setq downstreamCount (gtp:vcdn-downstream-nonreducer-count pts station))
                  (if (> downstreamCount 0)
                    (progn
                      (princ
                        (strcat
                          "\nReducer not placed: " (itoa downstreamCount)
                          " downstream component(s) already exist. Place all reducers Start->End before downstream valves/tees/branches/endcaps so their sizes stay correct."
                        )
                      )
                      nil
                    )
                    (progn
                      (setq transitions (gtp:vcdn-route-reducers pts))
                      (if (not (gtp:vcdn-validate-transitions startDn transitions))
                        (progn
                          (princ "\nExisting reducer transitions are inconsistent. Fix them before adding another reducer.")
                          nil
                        )
                        (progn
                          (setq currentDn (gtp:vcdn-dn-at-station startDn transitions station))
                          (setq currentRow (gtp:find-dn currentDn))
                          (setq otherRow (gtp:smart-prompt-dn "DN after reducer toward route End" currentDn))
                          (setq otherDn (car otherRow))
                          (if (= otherDn currentDn)
                            (progn
                              (princ "\nReducer requires a different downstream DN.")
                              nil
                            )
                            (progn
                              (setq currentOD (nth 1 currentRow) otherOD (nth 1 otherRow))
                              (setq small (min currentOD otherOD) large (max currentOD otherOD))
                              (initget "SINGLE TWIN")
                              (setq family (getkword "\nReducer family [SINGLE/TWIN] <SINGLE>: "))
                              (if (null family) (setq family "SINGLE"))
                              (setq db (if (= family "TWIN") *gtp-reducer-twin-db* *gtp-reducer-single-db*))
                              (setq row (gtp:reducer-row-find db small large))
                              (if row
                                (progn
                                  (setq routeDir (cdr (assoc 'direction routeData)))
                                  ; Reducer solid points SMALL -> LARGE. Route DN
                                  ; state independently runs Start -> End.
                                  (setq largeDir
                                    (if (> otherOD currentOD)
                                      routeDir
                                      (gtp:smart-vector-reverse routeDir)
                                    )
                                  )
                                  (setq smallCasing (gtp:smart-reducer-casing-for-row row series T))
                                  (setq largeCasing (gtp:smart-reducer-casing-for-row row series nil))
                                  (setq largeDn (if (> otherOD currentOD) otherDn currentDn))
                                  (setq catalogue
                                    (list
                                      (cons 'family (if (= family "TWIN") "REDUCER_TWIN" "REDUCER_SINGLE"))
                                      (cons 'dimension-source (if (= family "TWIN") "ISOPLUS_8.3_PAGE_116" "ISOPLUS_5.3_PAGE_80"))
                                      (cons 'length-mm 1500.0)
                                      (cons 'small-carrier-od-mm small)
                                      (cons 'large-carrier-od-mm large)
                                      (cons 'small-casing-od-mm smallCasing)
                                      (cons 'large-casing-od-mm largeCasing)
                                      (cons 'from-dn currentDn)
                                      (cons 'to-dn otherDn)
                                      (cons 'route-station-mm (gtp:vcdn-du-to-mm station))
                                    )
                                  )
                                  (setq id (gtp:smart-component-id "REDUCER"))
                                  (setq comp
                                    (gtp:component-make
                                      id "REDUCER" (gtp:smart-flow) largeDn series
                                      pos largeDir (gtp:smart-up-vector largeDir)
                                      1500.0 catalogue
                                      (list
                                        (cons 'route-start-dn currentDn)
                                        (cons 'route-end-dn otherDn)
                                        (cons 'route-station station)
                                        (cons 'base-dn currentDn)
                                        (cons 'other-dn otherDn)
                                        (cons 'other-side "Forward")
                                      )
                                    )
                                  )
                                  (if (gtp:smart-register-component comp)
                                    (progn
                                      (gtp:smart-model-reducer comp)
                                      (princ
                                        (strcat
                                          "\nPlaced " id
                                          " | route DN changes DN" (itoa currentDn)
                                          " -> DN" (itoa otherDn)
                                          " toward route End."
                                        )
                                      )
                                      comp
                                    )
                                    nil
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
    nil
  )
)

; -----------------------------------------------------------------------------
; VARIABLE-DN PIPE + ELBOW GENERATION
; -----------------------------------------------------------------------------
(defun gtp:vcdn-elbow-record
  (prev vertex next station startDn transitions series style / dn row carrier casing spec)
  (setq dn (gtp:vcdn-dn-at-station startDn transitions station))
  (setq row (gtp:find-dn dn))
  (if row
    (progn
      (setq carrier (gtp:mm (nth 1 row)))
      (setq casing (gtp:mm (gtp:casing-od row series)))
      (setq spec (gtp:make-elbow-spec prev vertex next dn carrier casing style))
      (if spec
        (list
          (cons 'spec spec)
          (cons 'dn dn)
          (cons 'carrier carrier)
          (cons 'casing casing)
        )
        nil
      )
    )
    nil
  )
)

(defun gtp:vcdn-model-straight
  (pts startDn transitions series mode start end / direction plan ranges cuts range p1 p2 mid data station dn row carrier casing count)
  (setq count 0)
  (if (> (distance start end) 1e-8)
    (progn
      (setq direction (gtp:vunit (gtp:vsub end start)))
      ; Reuse the combined footprint planner so valves/tees/reducers/branches/
      ; end caps are physically removed from the pipe interval.
      (setq plan (gtp:combined-plan-straight-ranges start end))
      (setq ranges (car plan) cuts (cadr plan))
      (foreach range ranges
        (setq p1 (gtp:vadd start (gtp:vscale direction (car range))))
        (setq p2 (gtp:vadd start (gtp:vscale direction (cadr range))))
        (if (> (distance p1 p2) 1e-8)
          (progn
            (setq mid (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
            (setq data (gtp:vcdn-route-point-data pts mid))
            (setq station (cdr (assoc 'station data)))
            (setq dn (gtp:vcdn-dn-at-station startDn transitions station))
            (setq row (gtp:find-dn dn))
            (if row
              (progn
                (setq carrier (gtp:mm (nth 1 row)))
                (setq casing (gtp:mm (gtp:casing-od row series)))
                (setq count (+ count (gtp:model-segment p1 p2 carrier casing mode)))
                (princ
                  (strcat
                    "\n  Straight interval modelled as DN" (itoa dn)
                    " | carrier OD " (rtos (nth 1 row) 2 1)
                    " mm | casing OD " (rtos (gtp:casing-od row series) 2 1) " mm."
                  )
                )
              )
            )
          )
        )
      )
      (if (> (length cuts) 0)
        (princ
          (strcat
            "\n  Excluded " (itoa (length cuts))
            " installed component footprint(s) from this straight interval."
          )
        )
      )
    )
  )
  count
)

(defun gtp:vcdn-model-route
  (pts startDn series mode style / transitions stations n elbows i rec p1 p2 s e spoolCount elbowCount clippedCount spec)
  (setq transitions (gtp:vcdn-route-reducers pts))
  (if (not (gtp:vcdn-validate-transitions startDn transitions))
    nil
    (progn
      (setq stations (gtp:vcdn-vertex-stations pts))
      (setq n (length pts) elbows '() i 0)
      (setq spoolCount 0 elbowCount 0 clippedCount 0)

      ; Build each elbow with the DN active at that route vertex.
      (while (< i n)
        (setq rec nil)
        (if (and (> i 0) (< i (1- n)))
          (setq rec
            (gtp:vcdn-elbow-record
              (nth (1- i) pts) (nth i pts) (nth (1+ i) pts)
              (nth i stations) startDn transitions series style
            )
          )
        )
        (if rec
          (progn
            (setq spec (cdr (assoc 'spec rec)))
            (if (gtp:spec 'clipped spec)
              (setq clippedCount (1+ clippedCount))
            )
          )
        )
        (setq elbows (append elbows (list rec)))
        (setq i (1+ i))
      )

      ; Straight route pieces use the DN at their actual station. Reducer
      ; footprints already split the interval before local DN is selected.
      (setq i 0)
      (while (< i (1- n))
        (setq p1 (nth i pts) p2 (nth (1+ i) pts))
        (setq s
          (if (nth i elbows)
            (gtp:spec 'end (cdr (assoc 'spec (nth i elbows))))
            p1
          )
        )
        (setq e
          (if (nth (1+ i) elbows)
            (gtp:spec 'start (cdr (assoc 'spec (nth (1+ i) elbows))))
            p2
          )
        )
        (if (> (distance s e) 1e-8)
          (setq spoolCount
            (+ spoolCount
               (gtp:vcdn-model-straight pts startDn transitions series mode s e)
            )
          )
        )
        (setq i (1+ i))
      )

      ; Model each elbow using its own local carrier/casing dimensions.
      (setq i 1)
      (while (< i (1- n))
        (setq rec (nth i elbows))
        (if rec
          (progn
            (gtp:model-elbow
              (cdr (assoc 'spec rec))
              (cdr (assoc 'carrier rec))
              (cdr (assoc 'casing rec))
              mode
            )
            (setq elbowCount (1+ elbowCount))
            (princ
              (strcat
                "\n  Elbow at route vertex " (itoa i)
                " modelled as DN" (itoa (cdr (assoc 'dn rec))) "."
              )
            )
          )
        )
        (setq i (1+ i))
      )

      (list spoolCount elbowCount clippedCount)
    )
  )
)

; -----------------------------------------------------------------------------
; VARIABLE-DN SMART SESSION MENU
; -----------------------------------------------------------------------------
(defun gtp:vcdn-component-menu (ent pts startDn series / choice added comp)
  (setq choice "" added 0)
  (while (and choice (/= choice "Build") (/= choice "Cancel"))
    (initget "Valve Tee Reducer Branch Endcap Zones Status Build Cancel")
    (setq choice
      (getkword
        "\nComponent [Valve/Tee/Reducer/Branch/Endcap/Zones/Status/Build/Cancel] <Build>: "
      )
    )
    (if (null choice) (setq choice "Build"))
    (cond
      ((= choice "Valve")
        (setq comp (gtp:vcdn-place-valve ent pts startDn series))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Tee")
        (setq comp (gtp:vcdn-place-tee ent pts startDn series))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Reducer")
        (setq comp (gtp:vcdn-place-reducer ent pts startDn series))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Branch")
        (setq comp (gtp:vcdn-place-branch ent pts startDn series))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Endcap")
        (setq comp (gtp:vcdn-place-endcap ent pts startDn series))
        (if comp (setq added (1+ added)))
      )
      ((= choice "Zones")
        (gtp:vcdn-print-zones pts startDn)
      )
      ((= choice "Status")
        (if (fboundp 'c:GTPCOMPONENTS) (c:GTPCOMPONENTS))
        (gtp:vcdn-print-zones pts startDn)
      )
    )
  )
  (list choice added)
)

(defun gtp:vcdn-generate (pts startDn series mode style / result)
  (princ "\nGenerating variable-DN component-aware 3D pipe + elbows...")
  (gtp:vcdn-print-zones pts startDn)
  (setq result (gtp:vcdn-model-route pts startDn series mode style))
  (if result
    (progn
      (princ
        (strcat
          "\nCreated variable-DN route: "
          (itoa (nth 0 result)) " straight spool(s) | "
          (itoa (nth 1 result)) " 3D elbow(s)."
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
      result
    )
    (progn
      (princ "\nVariable-DN route generation stopped because reducer transitions are inconsistent.")
      nil
    )
  )
)

; -----------------------------------------------------------------------------
; FINAL GTPPIPE OVERRIDE
; -----------------------------------------------------------------------------
(defun c:GTPPIPE
  (/ *error* old sel ent typ row startDn series carrierMM casingMM mode flowType style
   rawPts cleanInfo pts dupRemoved straightRemoved menuResult action added result)

  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPPIPE variable-DN session error: " msg))
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
          (gtp:setup-units)
          (princ "\nThe selected DN is the DN at ROUTE START. Reducers change DN toward ROUTE END.")
          (setq row (gtp:get-dn))
          (setq startDn (nth 0 row))
          (setq carrierMM (nth 1 row))
          (setq series (gtp:get-series))
          (setq casingMM (gtp:casing-od row series))
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
              (princ
                (strcat
                  "\nRoute cleanup: " (itoa (length rawPts))
                  " input vertices -> " (itoa (length pts))
                  " modelling vertices."
                )
              )
              (if (> (+ dupRemoved straightRemoved) 0)
                (princ
                  (strcat
                    " Ignored " (itoa dupRemoved) " duplicate and "
                    (itoa straightRemoved) " nearly-collinear intermediate point(s)."
                  )
                )
              )

              (gtp:smart-settings-summary
                startDn series carrierMM casingMM mode flowType style
              )
              (princ "\nReducer rule: place reducers from route Start -> End before adding downstream components.")
              (gtp:vcdn-print-zones pts startDn)

              (setq menuResult (gtp:vcdn-component-menu ent pts startDn series))
              (setq action (car menuResult) added (cadr menuResult))
              (if (= action "Build")
                (progn
                  (setq result (gtp:vcdn-generate pts startDn series mode style))
                  (if result
                    (progn
                      (if (fboundp 'gtp:persist-all-components)
                        (gtp:persist-all-components)
                      )
                      (princ
                        (strcat
                          "\nGTPPIPE variable-DN session complete. "
                          (itoa added) " component(s) added during this session."
                        )
                      )
                    )
                  )
                )
                (princ
                  (strcat
                    "\nGTPPIPE modelling cancelled before BUILD. "
                    (itoa added) " placed component(s) remain persisted."
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

(defun c:GTPPIPESMART () (c:GTPPIPE))

(defun c:GTPVARDNTEST (/ ok)
  (setq ok T)
  (foreach fn
    '(gtp:vcdn-route-point-data
      gtp:vcdn-route-reducers
      gtp:vcdn-validate-transitions
      gtp:vcdn-dn-at-station
      gtp:vcdn-place-reducer
      gtp:vcdn-model-route
      gtp:vcdn-component-menu
      gtp:vcdn-generate
      c:GTPPIPE)
    (if (not (fboundp fn))
      (progn
        (setq ok nil)
        (princ (strcat "\n[FAIL] " (vl-princ-to-string fn)))
      )
    )
  )
  (if ok
    (princ "\nGTPVARDNTEST PASS - reducer-driven variable-DN route functions are loaded.")
    (princ "\nGTPVARDNTEST FAIL.")
  )
  (princ)
)

(defun c:GTPHELP ()
  (princ "\nGTP combined AutoCAD 3D district-heating toolkit:")
  (princ "\n  GTPPIPE             Intelligent variable-DN one-route modelling session")
  (princ "\n                      Start DN is chosen once; reducers change DN toward route End")
  (princ "\n  GTPPIPESMART        Alias for GTPPIPE")
  (princ "\n  GTPMITER            Join two route ends at their 3D axis intersection")
  (princ "\n  GTPMITTER           Alias for GTPMITER")
  (princ "\n  GTPUNITS            Set catalogue-mm to drawing-unit conversion")
  (princ "\n  GTPLAYER            Create/check GTP layers")
  (princ "\n  GTPVALVE            Standalone valve placement")
  (princ "\n  GTPVALVECATALOG     Inspect supported valve catalogue")
  (princ "\n  GTPTEE              Standalone tee placement")
  (princ "\n  GTPREDUCER          Standalone reducer placement")
  (princ "\n  GTPBRANCH           Standalone branch placement")
  (princ "\n  GTPENDCAP           Standalone end-cap placement")
  (princ "\n  GTPCOMPONENTS       List persistent components")
  (princ "\n  GTPCOMPONENTRELOAD  Reload components stored in the DWG")
  (princ "\n  GTPCOMPONENTSAVE    Persist the current component registry")
  (princ "\n  GTPCOMBINEDTEST     Combined toolkit diagnostics")
  (princ "\n  GTPSMARTTEST        Smart workflow diagnostics")
  (princ "\n  GTPVARDNTEST        Variable-DN function availability diagnostics")
  (princ "\n")
  (princ "\nInside GTPPIPE, route corners automatically become elbows at the LOCAL DN.")
  (princ "\nComponent menu: Valve / Tee / Reducer / Branch / Endcap / Zones / Status / Build / Cancel.")
  (princ "\nPlace reducers from route Start -> End before downstream components.")
  (princ)
)

(princ
  (strcat
    "\nGTP variable-DN route V" *gtp-variable-dn-version*
    " loaded. Reducers now change downstream pipe and elbow DN toward route End."
  )
)
(princ)
