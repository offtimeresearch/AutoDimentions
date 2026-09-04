; GTP_DH_TOOLKIT_INTEGRATED.LSP
; -----------------------------------------------------------------------------
; FINAL INTEGRATION ENTRY POINT
;
; This is the single entry-point file for the component-aware GTPPIPE toolkit.
; It intentionally keeps the implementation modules separate in the repository
; so they remain readable and maintainable, while presenting one file to load
; in AutoCAD.
;
; LOAD ORDER
;   1. GTP_DH_TOOLKIT.lsp
;   2. GTP_Component_Architecture.lsp
;   3. GTP_Elbow_Component_Integration.lsp
;   4. GTP_Valve_Component.lsp
;   5. GTP_Valve_Aware_Pipe_Integration.lsp
;   6. GTP_Valve_Catalogue_Integration.lsp
;   7. GTP_Component_Persistence_and_Fittings.lsp
;
; INTEGRATION RULES
;   - The original geometry engine remains the source of truth for pipe/elbow
;     generation.
;   - Component data is represented by the common component model.
;   - Valve catalogue selection replaces manual valve dimensions.
;   - Valve-aware pipe splitting is enabled through the route modeller bridge.
;   - Component records are persisted in the DWG by Step 6.
;   - TEE / REDUCER / BRANCH / END_CAP are available as component foundations.
;   - No source module is copied or rewritten here. This file is the stable
;     loader/orchestration layer and is the file intended for APPLOAD.
;
; IMPORTANT
;   All seven module files must remain beside this file (or otherwise reachable
;   from the same directory) when loaded.
; -----------------------------------------------------------------------------

(vl-load-com)

(setq *gtp-integrated-module-list*
  '(
    "GTP_DH_TOOLKIT.lsp"
    "GTP_Component_Architecture.lsp"
    "GTP_Elbow_Component_Integration.lsp"
    "GTP_Valve_Component.lsp"
    "GTP_Valve_Aware_Pipe_Integration.lsp"
    "GTP_Valve_Catalogue_Integration.lsp"
    "GTP_Component_Persistence_and_Fittings.lsp"
  )
)

(defun gtp:integrated-directory (/ self)
  (setq self (findfile "GTP_DH_TOOLKIT_INTEGRATED.lsp"))
  (if self
    (vl-filename-directory self)
    nil
  )
)

(defun gtp:integrated-load-module (base filename / path result)
  (setq path
    (if base
      (strcat base "\\" filename)
      (findfile filename)
    )
  )
  (if (and path (findfile path))
    (progn
      (princ (strcat "\nGTP integrated load: " filename))
      (setq result (vl-catch-all-apply 'load (list path)))
      (if (vl-catch-all-error-p result)
        (progn
          (princ
            (strcat
              "\nGTP integrated load FAILED: " filename
              " | " (vl-catch-all-error-message result)
            )
          )
          nil
        )
        T
      )
    )
    (progn
      (princ (strcat "\nGTP integrated load MISSING: " filename))
      nil
    )
  )
)

(defun gtp:integrated-command-p (name)
  (and (fboundp name) T)
)

(defun gtp:integrated-status (/ checks ok)
  (setq checks
    (list
      (list "GTPPIPE" 'c:GTPPIPE)
      (list "GTPVALVE" 'c:GTPVALVE)
      (list "GTPTEE" 'c:GTPTEE)
      (list "GTPREDUCER" 'c:GTPREDUCER)
      (list "GTPBRANCH" 'c:GTPBRANCH)
      (list "GTPENDCAP" 'c:GTPENDCAP)
      (list "GTPCOMPONENTS" 'c:GTPCOMPONENTS)
      (list "GTPCOMPONENTRELOAD" 'c:GTPCOMPONENTRELOAD)
      (list "GTPCOMPONENTSAVE" 'c:GTPCOMPONENTSAVE)
    )
  )
  (setq ok T)
  (foreach item checks
    (if (fboundp (cadr item))
      (princ (strcat "\n  [OK] " (car item)))
      (progn
        (setq ok nil)
        (princ (strcat "\n  [MISSING] " (car item)))
      )
    )
  )
  ok
)

(defun c:GTPINTEGRATED (/ base loaded failed file success)
  (vl-load-com)
  (setq base (gtp:integrated-directory))
  (setq loaded 0)
  (setq failed 0)

  (foreach file *gtp-integrated-module-list*
    (setq success (gtp:integrated-load-module base file))
    (if success
      (setq loaded (1+ loaded))
      (setq failed (1+ failed))
    )
  )

  (princ
    (strcat
      "\n\nGTP integrated toolkit load complete."
      "\nModules loaded: " (itoa loaded)
      " | Failed/missing: " (itoa failed)
      "."
    )
  )

  (if (= failed 0)
    (progn
      (princ "\nCommand availability:")
      (gtp:integrated-status)
      (princ
        "\n\nGTPPIPE component-aware toolkit is ready."
      )
    )
    (princ
      "\n\nFix the missing/failed module(s), then run GTPINTEGRATED again."
    )
  )
  (princ)
)

; -----------------------------------------------------------------------------
; AUTO-LOAD ON APPLOAD
; -----------------------------------------------------------------------------
; APPLOAD of this file immediately loads the complete stack. Running
; GTPINTEGRATED manually later simply reloads the same stack and is useful
; after editing/reloading a module during development.
; -----------------------------------------------------------------------------

(c:GTPINTEGRATED)

(princ
  "\nGTP_DH_TOOLKIT_INTEGRATED loaded. Use GTPPIPE for modelling; GTPINTEGRATED to reload all modules."
)
(princ)
