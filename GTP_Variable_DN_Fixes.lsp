; GTP_VARIABLE_DN_FIXES.LSP
; Final compatibility fixes loaded after GTP_Variable_DN_Route.lsp.

(defun gtp:vcdn-last-reducer-station (pts / reducers lastReducer)
  (setq reducers (gtp:vcdn-route-reducers pts))
  (if reducers
    (progn
      (setq lastReducer (car (last reducers)))
      (cdr (assoc 'station lastReducer))
    )
    nil
  )
)

(princ "\nGTP variable-DN compatibility fixes loaded.")
(princ)
