; GTP_CATALOGUE_CORRECTIONS.LSP
; =============================================================================
; Authoritative correction layer for the uploaded ISOPLUS Product Catalogue
; 11/2024. Load LAST, after the variable-DN route/fix modules.
;
; This module intentionally overrides only data/functions where the catalogue
; gives unambiguous values. It does NOT invent dimensions that the catalogue
; does not provide.
;
; Verified catalogue sources:
;   5.1 / 5.1.1 / 5.1.2  Steel pipes - single, pp. 76-78
;   5.3                  Reducers - single, p. 80
;   5.4                  Bends 45/90 - single, p. 81
;   5.9 / 5.9.1          Shut-off valves - single, pp. 89-90
;   8.3                  Reducers - twin, p. 116
;   8.10 / 8.11          Shut-off valves - twin, pp. 128-129
;   16.12.1              Weldable saddle/flex branch ranges
;   17.2-17.5            End-cap selection references
;
; Important modelling boundaries retained deliberately:
;   - The 3x carrier-OD bend radius is a MODEL ASSUMPTION, not an ISOPLUS 5.4
;     catalogue radius. Section 5.4 supplies bend leg lengths, not centre radius.
;   - Generic TEE geometry remains user/project defined.
;   - End-cap axial thickness remains a model-only input because sections
;     17.2-17.5 provide selection/type information, not a universal 25 mm
;     axial thickness.
;   - Reducer design spacing depends on system/laying rules. The 1500 mm check
;     in the modeller is only a physical footprint-overlap check.
; =============================================================================

(vl-load-com)

(setq *gtp-catalogue-corrections-version* "1.0")
(setq *gtp-catalogue-edition* "ISOPLUS Product Catalogue 11/2024")
(setq *gtp-bend-radius-source* "MODEL_ASSUMPTION_3X_CARRIER_OD_NOT_ISOPLUS_5.4")

; -----------------------------------------------------------------------------
; GENERIC TABLE PATCH HELPERS
; -----------------------------------------------------------------------------
(defun gtp:catalogue-replace-row-by-first (db key newrow / out replaced r)
  (setq out '() replaced nil)
  (foreach r db
    (if (and (not replaced) (< (abs (- (car r) key)) 0.01))
      (progn
        (setq out (append out (list newrow)))
        (setq replaced T)
      )
      (setq out (append out (list r)))
    )
  )
  out
)

(defun gtp:catalogue-replace-reducer-row (db small large newrow / out replaced r)
  (setq out '() replaced nil)
  (foreach r db
    (if (and (not replaced)
             (< (abs (- (car r) small)) 0.01)
             (< (abs (- (cadr r) large)) 0.01))
      (progn
        (setq out (append out (list newrow)))
        (setq replaced T)
      )
      (setq out (append out (list r)))
    )
  )
  out
)

; -----------------------------------------------------------------------------
; DATA CORRECTIONS
; -----------------------------------------------------------------------------
; ISOPLUS 5.3 p.80, carrier 26.9 -> 33.7:
;   S1 90/90, S2 110/110, S3 125/125, L=1500.
(setq *gtp-reducer-single-db*
  (gtp:catalogue-replace-reducer-row
    *gtp-reducer-single-db*
    26.9 33.7
    '(26.9 33.7 90 90 110 110 125 125 1500)
  )
)

; ISOPLUS 5.9 p.89, carrier 48.3 single shut-off valve:
; body D3 is 110 mm (not 125 mm).
(setq *gtp-valve-single-db*
  (gtp:catalogue-replace-row-by-first
    *gtp-valve-single-db*
    48.3
    '(48.3 110 125 125 125 140 140 110 494 19 1510)
  )
)

; ISOPLUS 8.10 p.128 contains two carrier-219.1 twin-valve rows. The second
; catalogue variant differs at Series-2 D1 (670 instead of 710).
(setq *gtp-valve-twin-219-alt-row*
  '(219.1 560 630 630 670 710 800 180 210 800 383 27 2200)
)
(if (not (member *gtp-valve-twin-219-alt-row* *gtp-valve-twin-db*))
  (setq *gtp-valve-twin-db*
    (append *gtp-valve-twin-db* (list *gtp-valve-twin-219-alt-row*))
  )
)

; Override lookup only for the ambiguous DN200 twin shut-off valve. All other
; families/diameters retain the normal catalogue lookup behavior.
(defun gtp:valve-row-for-dn (family dn / db od row choice)
  (setq db (gtp:valve-db-for-family family))
  (setq od (gtp:valve-carrier-od dn))
  (if (and db od)
    (if (and (= family "TWIN_SHUTOFF") (< (abs (- od 219.1)) 0.01))
      (progn
        (initget "D1710 D1670")
        (setq choice
          (getkword
            "\nDN200 twin valve p.128 variant [D1710/D1670] <D1710>: "
          )
        )
        (if (= choice "D1670")
          (setq row *gtp-valve-twin-219-alt-row*)
          (setq row '(219.1 560 630 630 710 710 800 180 210 800 383 27 2200))
        )
      )
      (setq row (gtp:catalogue-row-by-value db od))
    )
  )
  row
)

; -----------------------------------------------------------------------------
; CATALOGUE-AWARE MAXIMUM STANDARD STOCK LENGTH
; -----------------------------------------------------------------------------
; Values below are the maximum listed standard straight-pipe length for each
; DN/series in ISOPLUS 5.1, 5.1.1 and 5.1.2 (pp.76-78).
; Row = (DN Series1MaxMM Series2MaxMM Series3MaxMM)
(setq *gtp-stock-max-db*
  '(
    (20   6000 12000 12000)
    (25   6000 12000 12000)
    (32  12000 12000 12000)
    (40  12000 12000 12000)
    (50  12000 12000 12000)
    (65  12000 12000 12000)
    (80  12000 12000 12000)
    (100 16000 16000 16000)
    (125 16000 16000 16000)
    (150 16000 16000 16000)
    (200 16000 16000 16000)
    (250 16000 16000 16000)
    (300 16000 16000 16000)
    (350 16000 16000 16000)
    (400 16000 16000 16000)
    (450 16000 16000 16000)
    (500 16000 16000 16000)
    (600 16000 16000 16000)
  )
)

(defun gtp:catalogue-max-stock-length-mm (dn series / row)
  (setq row (assoc dn *gtp-stock-max-db*))
  (if (and row (>= series 1) (<= series 3))
    (nth series row)
    *gtp-max-pipe-length-mm*
  )
)

(defun gtp:catalogue-pipe-row-from-carrier-du (carrier / carrierMM found r)
  (setq carrierMM
    (if (> (abs *gtp-mm-to-du*) 1e-12)
      (/ carrier *gtp-mm-to-du*)
      carrier
    )
  )
  (setq found nil)
  (foreach r *gtp-pipe-db*
    (if (and (null found) (< (abs (- (nth 1 r) carrierMM)) 0.2))
      (setq found r)
    )
  )
  found
)

(defun gtp:catalogue-series-from-casing-du (row casing / casingMM)
  (setq casingMM
    (if (> (abs *gtp-mm-to-du*) 1e-12)
      (/ casing *gtp-mm-to-du*)
      casing
    )
  )
  (cond
    ((and row (< (abs (- (nth 2 row) casingMM)) 0.2)) 1)
    ((and row (< (abs (- (nth 3 row) casingMM)) 0.2)) 2)
    ((and row (< (abs (- (nth 4 row) casingMM)) 0.2)) 3)
    (T nil)
  )
)

(defun gtp:catalogue-stock-length-from-geometry (carrier casing / row series)
  (setq row (gtp:catalogue-pipe-row-from-carrier-du carrier))
  (setq series (gtp:catalogue-series-from-casing-du row casing))
  (if (and row series)
    (gtp:catalogue-max-stock-length-mm (car row) series)
    *gtp-max-pipe-length-mm*
  )
)

; Final override of the straight-segment spool splitter. Existing callers need
; no signature change; DN/series are recovered from carrier/casing geometry.
(defun gtp:model-segment (p1 p2 carrier casing mode / len dir pos piece s1 s2 count maxMM maxDU)
  (setq len (distance p1 p2))
  (setq dir (gtp:vunit (gtp:vsub p2 p1)))
  (setq pos 0.0 count 0)
  (setq maxMM (gtp:catalogue-stock-length-from-geometry carrier casing))
  (setq maxDU (gtp:mm maxMM))
  (while (< pos (- len 1e-8))
    (setq piece (min maxDU (- len pos)))
    (setq s1 (gtp:vadd p1 (gtp:vscale dir pos)))
    (setq s2 (gtp:vadd p1 (gtp:vscale dir (+ pos piece))))
    (gtp:model-spool s1 s2 carrier casing mode)
    (setq pos (+ pos piece))
    (setq count (1+ count))
  )
  count
)

; -----------------------------------------------------------------------------
; WELDABLE BRANCH RANGE VALIDATION (ISOPLUS 16.12.1)
; -----------------------------------------------------------------------------
; Model H 460x390: main jacket D125-D630 / branch D90-D140
; Model D 700x700: main jacket D225-D630 / branch D90-D250
(defun gtp:catalogue-weldable-branch-model (mainJacket branchJacket)
  (cond
    ((and (>= mainJacket 125.0) (<= mainJacket 630.0)
          (>= branchJacket 90.0) (<= branchJacket 140.0))
      "H_460x390")
    ((and (>= mainJacket 225.0) (<= mainJacket 630.0)
          (>= branchJacket 90.0) (<= branchJacket 250.0))
      "D_700x700")
    (T nil)
  )
)

; Smart-session branch override: validate the selected main/branch jacket
; combination against 16.12.1, but keep simplified body lengths explicitly
; user-defined because the catalogue model H/D dimensions are assembly/joint
; envelope values, not a universal branch-body axial length.
(defun gtp:vcdn-place-branch
  (ent pts startDn series / info pos dir localDn mainRow mainCasingMM branchPt bdir
   branchRow branchDn branchCasingMM branchModel mainLen branchLen catalogue comp id)
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
          (setq branchModel
            (gtp:catalogue-weldable-branch-model mainCasingMM branchCasingMM)
          )
          (if (null branchModel)
            (progn
              (princ
                (strcat
                  "\nBranch not placed: Series " (itoa series)
                  " main jacket D" (rtos mainCasingMM 2 0)
                  " / branch jacket D" (rtos branchCasingMM 2 0)
                  " is outside the ISOPLUS 16.12.1 Model H/D catalogue range."
                )
              )
              nil
            )
            (progn
              (setq mainLen
                (gtp:smart-prompt-real-default
                  "User model main branch footprint length (mm)" 700.0
                )
              )
              (setq branchLen
                (gtp:smart-prompt-real-default
                  "User model branch projection length (mm)" 700.0
                )
              )
              (setq catalogue
                (list
                  (cons 'family "WELDABLE_BRANCH_VARIABLE_DN")
                  (cons 'dimension-source "USER_DEFINED_MODEL_GEOMETRY")
                  (cons 'catalogue-range-source "ISOPLUS_16.12.1")
                  (cons 'catalogue-model branchModel)
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
                      "\nPlaced " id " | " branchModel
                      " catalogue range validated | local main DN" (itoa localDn)
                      " -> branch DN" (itoa branchDn) "."
                    )
                  )
                  comp
                )
                nil
              )
            )
          )
        )
        nil
      )
    )
    nil
  )
)

; -----------------------------------------------------------------------------
; END-CAP SOURCE CORRECTION
; -----------------------------------------------------------------------------
; Sections 17.2-17.5 are used only as selection/reference data here. The
; simplified solid thickness is explicitly a user/model value, not a catalogue
; thickness.
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
      (setq thickness
        (gtp:smart-prompt-real-default
          "Model-only end-cap axial thickness (mm; not catalogue dimension)" 25.0
        )
      )
      (setq catalogue
        (list
          (cons 'family "END_CAP_VARIABLE_DN")
          (cons 'dimension-source "USER_DEFINED_MODEL_GEOMETRY")
          (cons 'catalogue-reference "ISOPLUS_17.2_TO_17.5_SELECTION")
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
              " | local DN" (itoa localDn)
              ". Note: axial thickness is model-only, not an ISOPLUS catalogue dimension."
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
; REDUCER SPACING CLARIFICATION
; -----------------------------------------------------------------------------
(setq *gtp-reducer-design-note-shown* nil)
(defun gtp:vcdn-reducer-spacing-ok-p (pts station / reducers tr other minSpace ok)
  (if (not *gtp-reducer-design-note-shown*)
    (progn
      (princ
        "\nCatalogue note: 1500 mm here is only the reducer solid-footprint overlap check. Engineering reducer spacing/step limits depend on the ISOPLUS system and laying method and are not automatically approved by this command."
      )
      (setq *gtp-reducer-design-note-shown* T)
    )
  )
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

; -----------------------------------------------------------------------------
; CATALOGUE CORRECTION SELF-TEST
; -----------------------------------------------------------------------------
(defun c:GTPCATALOGUETEST (/ ok r v count alt stock branchModel)
  (setq ok T)
  (princ "\n========================================")
  (princ "\n GTP ISOPLUS 11/2024 CATALOGUE TEST")
  (princ "\n========================================")

  (setq r (gtp:reducer-row-find *gtp-reducer-single-db* 26.9 33.7))
  (if (and r
           (= (nth 2 r) 90) (= (nth 3 r) 90)
           (= (nth 4 r) 110) (= (nth 5 r) 110)
           (= (nth 6 r) 125) (= (nth 7 r) 125)
           (= (nth 8 r) 1500))
    (princ "\n[OK] ISOPLUS 5.3 DN20->DN25 reducer row corrected.")
    (progn (setq ok nil) (princ "\n[FAIL] DN20->DN25 reducer row."))
  )

  (setq v (gtp:catalogue-row-by-value *gtp-valve-single-db* 48.3))
  (if (and v (= (nth 7 v) 110) (= (nth 8 v) 494) (= (nth 10 v) 1510))
    (princ "\n[OK] ISOPLUS 5.9 carrier-48.3 single-valve D3=110.")
    (progn (setq ok nil) (princ "\n[FAIL] carrier-48.3 single-valve row."))
  )

  (setq count 0)
  (foreach v *gtp-valve-twin-db*
    (if (< (abs (- (car v) 219.1)) 0.01) (setq count (1+ count)))
  )
  (if (>= count 2)
    (princ "\n[OK] ISOPLUS 8.10 both carrier-219.1 twin-valve variants available.")
    (progn (setq ok nil) (princ "\n[FAIL] second DN200 twin-valve variant missing."))
  )

  (if (and (= (gtp:catalogue-max-stock-length-mm 20 1) 6000)
           (= (gtp:catalogue-max-stock-length-mm 20 2) 12000)
           (= (gtp:catalogue-max-stock-length-mm 80 3) 12000)
           (= (gtp:catalogue-max-stock-length-mm 100 1) 16000)
           (= (gtp:catalogue-max-stock-length-mm 600 3) 16000))
    (princ "\n[OK] ISOPLUS 5.1/5.1.1/5.1.2 maximum stock-length rules active.")
    (progn (setq ok nil) (princ "\n[FAIL] stock-length database."))
  )

  (setq branchModel (gtp:catalogue-weldable-branch-model 225 140))
  (if (and (= branchModel "H_460x390")
           (= (gtp:catalogue-weldable-branch-model 355 200) "D_700x700")
           (null (gtp:catalogue-weldable-branch-model 200 200)))
    (princ "\n[OK] ISOPLUS 16.12.1 weldable branch range validation active.")
    (progn (setq ok nil) (princ "\n[FAIL] branch range validation."))
  )

  (princ "\n[INFO] Bend centre radius remains a documented model assumption (3x carrier OD); ISOPLUS 5.4 does not provide that radius.")
  (princ "\n[INFO] Generic TEE and end-cap axial model geometry remain user-defined where the catalogue does not provide a universal value.")
  (princ "\n[INFO] Reducer 1500 mm spacing check is geometry-only; design spacing depends on laying/system rules.")

  (if ok
    (princ "\nGTPCATALOGUETEST PASS.")
    (princ "\nGTPCATALOGUETEST FAIL - see [FAIL] entries above."))
  (princ)
)

(princ "\nGTP catalogue correction layer active: ISOPLUS Product Catalogue 11/2024.")
(princ "\nRun GTPCATALOGUETEST to verify corrected catalogue data.")
(princ)
