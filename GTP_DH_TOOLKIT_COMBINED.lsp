; GTP_DH_TOOLKIT_COMBINED.LSP
; =============================================================================
; COMBINED AUTOCAD 3D DISTRICT-HEATING TOOLKIT ENTRY POINT
;
; APPLOAD THIS FILE.
;
; Loads the complete repository implementation in the required order, then
; applies the final multi-component route bridge so GTPPIPE can generate pipe
; around persisted longitudinal components instead of modelling through them.
;
; A repository builder (tools/build_gtp_combined.py) can flatten the same
; source stack into a physically monolithic file when run in CI/local checkout.
; =============================================================================

(vl-load-com)

(setq *gtp-combined-files*
  '(
    "GTP_DH_TOOLKIT.lsp"
    "GTP_Component_Architecture.lsp"
    "GTP_Elbow_Component_Integration.lsp"
    "GTP_Valve_Component.lsp"
    "GTP_Valve_Aware_Pipe_Integration.lsp"
    "GTP_Valve_Catalogue_Integration.lsp"
    "GTP_Component_Persistence_and_Fittings.lsp"
    "GTP_Combined_Final_Bridge.lsp"
  )
)

(defun gtp:combined-base-directory (/ self)
  (setq self (findfile "GTP_DH_TOOLKIT_COMBINED.lsp"))
  (if self (vl-filename-directory self) nil)
)

(defun gtp:combined-load-one (base filename / path result)
  (setq path
    (if base
      (strcat base "\\" filename)
      (findfile filename)
    )
  )

  (if (and path (findfile path))
    (progn
      (princ (strcat "\nGTP combined load: " filename))
      (setq result (vl-catch-all-apply 'load (list path)))
      (if (vl-catch-all-error-p result)
        (progn
          (princ
            (strcat
              "\nGTP combined load FAILED: " filename
              " | " (vl-catch-all-error-message result)
            )
          )
          nil
        )
        T
      )
    )
    (progn
      (princ (strcat "\nGTP combined load MISSING: " filename))
      nil
    )
  )
)

(defun c:GTPCOMBINED (/ base loaded failed file ok)
  (setq base (gtp:combined-base-directory))
  (setq loaded 0 failed 0)

  (foreach file *gtp-combined-files*
    (setq ok (gtp:combined-load-one base file))
    (if ok
      (setq loaded (1+ loaded))
      (setq failed (1+ failed))
    )
  )

  (princ
    (strcat
      "\n\nGTP combined toolkit load complete."
      "\nLoaded: " (itoa loaded)
      " | Failed/missing: " (itoa failed)
    )
  )

  (if (= failed 0)
    (progn
      (princ "\nFinal component-aware GTPPIPE integration is active.")
      (if (fboundp 'c:GTPCOMBINEDTEST)
        (c:GTPCOMBINEDTEST)
      )
    )
    (princ "\nFix missing modules and run GTPCOMBINED again.")
  )
  (princ)
)

(c:GTPCOMBINED)

(princ "\nGTP_DH_TOOLKIT_COMBINED loaded. Use GTPPIPE for 3D pipe generation, GTPHELP for commands.")
(princ)
