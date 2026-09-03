; GTP_DH_TOOLKIT_V1_9_MITER_PATCH.LSP
; Small maintainable overlay for GTP_DH_TOOLKIT_V1_8.lsp.
; Adds GTPMITER and replaces GTPPIPE with corner-only route interpretation.
; The full generated V1.9 file can be built from V1.8 + this overlay.

(vl-load-com)

; Auto-load the V1.8 base when it has not already been loaded.
(if (not (fboundp 'gtp:model-corner-route))
  (progn
    (if (findfile "GTP_DH_TOOLKIT_V1_8.lsp")
      (load "GTP_DH_TOOLKIT_V1_8.lsp")
      (princ "\nV1.9 patch needs GTP_DH_TOOLKIT_V1_8.lsp in the same folder or AutoCAD support path.")
    )
  )
)

; -----------------------------------------------------------------------------
; V1.9 MITER ROUTE PREPARATION
; -----------------------------------------------------------------------------

(defun gtp:last-item (lst)
  (car (last lst))
)

(defun gtp:butlast (lst / out)
  (setq out '())
  (while (cdr lst)
    (setq out (append out (list (car lst)))
          lst (cdr lst)))
  out
)

(defun gtp:replace-first (lst value)
  (if lst (cons value (cdr lst)) (list value))
)

(defun gtp:replace-last (lst value)
  (if lst (append (gtp:butlast lst) (list value)) (list value))
)

(defun gtp:valid-route-entity-p (ent / typ)
  (if ent
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (member typ '("LINE" "LWPOLYLINE" "POLYLINE")))
    nil)
)

(defun gtp:end-info (pts pick / p0 pN pAdj side ordered endpt dir d0 dN)
  ; Return information for the endpoint nearest the user's selection pick.
  ; DIR always points OUTWARD from the source object toward the would-be miter.
  (if (and pts (> (length pts) 1))
    (progn
      (setq p0 (car pts)
            pN (gtp:last-item pts)
            d0 (distance pick p0)
            dN (distance pick pN))
      (if (<= d0 dN)
        (progn
          (setq side "START"
                endpt p0
                pAdj (cadr pts)
                dir (gtp:vunit (gtp:vsub endpt pAdj))
                ordered (reverse pts))) ; selected end becomes LAST
        (progn
          (setq side "END"
                endpt pN
                pAdj (nth (- (length pts) 2) pts)
                dir (gtp:vunit (gtp:vsub endpt pAdj))
                ordered pts)))          ; selected end already LAST
      (list
        (cons 'side side)
        (cons 'end endpt)
        (cons 'adj pAdj)
        (cons 'dir dir)
        (cons 'ordered-to-end ordered)
        (cons 'localLength (distance endpt pAdj))))
    nil)
)

(defun gtp:make-3d-polyline (pts layer / head v lastent)
  ; Create a true 3D POLYLINE so X/Y/Z centreline geometry is preserved.
  (setq head
    (entmakex
      (list
        '(0 . "POLYLINE")
        '(100 . "AcDbEntity")
        (cons 8 layer)
        '(100 . "AcDb3dPolyline")
        (cons 10 '(0.0 0.0 0.0))
        '(66 . 1)
        '(70 . 8))))
  (if head
    (progn
      (foreach p pts
        (entmakex
          (list
            '(0 . "VERTEX")
            '(100 . "AcDbEntity")
            (cons 8 layer)
            '(100 . "AcDbVertex")
            '(100 . "AcDb3dPolylineVertex")
            (cons 10 p)
            '(70 . 32))))
      (setq lastent
        (entmakex
          (list
            '(0 . "SEQEND")
            '(100 . "AcDbEntity")
            (cons 8 layer))))
      head)
    nil)
)

(defun gtp:miter-build-points (pts1 info1 pts2 info2 corner / a b)
  ; First source is ordered from its far end TO the selected connection end.
  ; Second source is ordered FROM the selected connection end to its far end.
  (setq a (gtp:replace-last (cdr (assoc 'ordered-to-end info1)) corner)
        b (reverse (cdr (assoc 'ordered-to-end info2)))
        b (gtp:replace-first b corner))
  ; Avoid duplicating the shared corner vertex.
  (append a (cdr b))
)

(defun c:GTPMITER (/ *error* oldcmdecho sel1 sel2 ent1 ent2 pick1 pick2 pts1 pts2 info1 info2 e1 e2 d1 d2 ll corner gap gapTol localScale routePts newEnt keep ans out1 out2 phi outDir deg s1 s2)
  (vl-load-com)
  (defun *error* (msg)
    (if oldcmdecho (setvar "CMDECHO" oldcmdecho))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPMITER error: " msg)))
    (princ))

  (setq oldcmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)

  (setq sel1 (entsel "\nSelect FIRST route near the end to connect: "))
  (if (null sel1)
    (princ "\nNothing selected.")
    (progn
      (setq ent1 (car sel1))
      (if (not (gtp:valid-route-entity-p ent1))
        (princ "\nFirst object must be a LINE, LWPOLYLINE or POLYLINE.")
        (progn
          (setq sel2 (entsel "\nSelect SECOND route near the end to connect: "))
          (if (null sel2)
            (princ "\nNothing selected for the second route.")
            (progn
              (setq ent2 (car sel2))
              (cond
                ((= ent1 ent2)
                  (princ "\nSelect two different route objects."))
                ((not (gtp:valid-route-entity-p ent2))
                  (princ "\nSecond object must be a LINE, LWPOLYLINE or POLYLINE."))
                (T
                  (setq pick1 (trans (cadr sel1) 1 0)
                        pick2 (trans (cadr sel2) 1 0)
                        pts1 (gtp:curve-points ent1)
                        pts2 (gtp:curve-points ent2))
                  (if (or (null pts1) (null pts2) (< (length pts1) 2) (< (length pts2) 2))
                    (princ "\nCould not read straight-segment vertices from one of the selected routes.")
                    (progn
                      (setq info1 (gtp:end-info pts1 pick1)
                            info2 (gtp:end-info pts2 pick2)
                            e1 (cdr (assoc 'end info1))
                            e2 (cdr (assoc 'end info2))
                            d1 (cdr (assoc 'dir info1))
                            d2 (cdr (assoc 'dir info2))
                            ll (gtp:line-line-corner e1 d1 e2 d2))
                      (if (null ll)
                        (princ "\nThe selected terminal axes are parallel or nearly parallel; no miter intersection exists.")
                        (progn
                          (setq corner (cdr (assoc 'corner ll))
                                gap (cdr (assoc 'gap ll))
                                s1 (cdr (assoc 's ll))
                                s2 (cdr (assoc 't ll))
                                localScale (max (cdr (assoc 'localLength info1))
                                                (cdr (assoc 'localLength info2)))
                                ; Relative tolerance: permits tiny 3D drafting noise but rejects truly skew axes.
                                gapTol (max 1e-7 (* 0.002 localScale)))
                          (if (> gap gapTol)
                            (princ
                              (strcat
                                "\nThe two terminal axes are skew in 3D and do not truly intersect. Closest-axis gap = "
                                (rtos gap 2 6)
                                ". Align their elevations/planes, then run GTPMITER again."))
                            (progn
                              (setq routePts (gtp:miter-build-points pts1 info1 pts2 info2 corner)
                                    newEnt (gtp:make-3d-polyline routePts "GTP-PIPE-CENTRELINE"))
                              (if (null newEnt)
                                (princ "\nCould not create the joined 3D miter centreline.")
                                (progn
                                  ; Turn angle from incoming route into outgoing route.
                                  (setq outDir (gtp:vneg d2)
                                        phi (atan (gtp:vmag (gtp:cross d1 outDir)) (gtp:dot d1 outDir))
                                        deg (gtp:rad->deg phi))
                                  (princ
                                    (strcat
                                      "\nCreated mitered GTP centreline. Virtual corner = ("
                                      (rtos (car corner) 2 4) ", "
                                      (rtos (cadr corner) 2 4) ", "
                                      (rtos (caddr corner) 2 4) ")"
                                      " | bend angle = " (rtos deg 2 2) " deg."))
                                  (princ
                                    (strcat
                                      "\nFirst route end "
                                      (if (>= s1 0.0) "extended " "trimmed ")
                                      (rtos (abs s1) 2 4)
                                      "; second route end "
                                      (if (>= s2 0.0) "extended " "trimmed ")
                                      (rtos (abs s2) 2 4) "."))

                                  (initget "Keep Delete")
                                  (setq ans (getkword "\nSource objects [Keep/Delete] <Keep>: "))
                                  (if (null ans) (setq ans "Keep"))
                                  (if (= ans "Delete")
                                    (progn
                                      (entdel ent1)
                                      (entdel ent2)
                                      (princ "\nOriginal route objects deleted.")))

                                  ; Highlight the new route so it is easy to use immediately with GTPPIPE.
                                  (setq keep (ssadd))
                                  (ssadd newEnt keep)
                                  (sssetfirst nil keep)
                                  (princ "\nNew route selected. Run GTPPIPE and select this centreline."))))))))))))))))

  (setvar "CMDECHO" oldcmdecho)
  (princ)
)

(defun c:GTPPIPE (/ *error* oldcmdecho ent typ row dn series carrierMM casingMM carrier casing mode elbowStyle pts result spoolCount elbowCount clippedCount shortFallbackCount)
  (vl-load-com)

  (defun *error* (msg)
    (if oldcmdecho (setvar "CMDECHO" oldcmdecho))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nGTPPIPE error: " msg)))
    (princ))

  (setq oldcmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (gtp:layers)
  (setq ent (car (entsel "\nSelect prepared route LINE / 2D or 3D POLYLINE: ")))

  (if (null ent)
    (princ "\nNothing selected.")
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (if (not (member typ '("LINE" "LWPOLYLINE" "POLYLINE")))
        (princ "\nGTPPIPE accepts LINE, LWPOLYLINE or POLYLINE routes.")
        (progn
          (gtp:setup-units)
          (setq row (gtp:get-dn))
          (if row
            (progn
              (setq dn (nth 0 row)
                    carrierMM (nth 1 row)
                    series (gtp:get-series)
                    casingMM (gtp:casing-od row series)
                    carrier (gtp:mm carrierMM)
                    casing (gtp:mm casingMM)
                    mode (gtp:get-mode)
                    elbowStyle (gtp:get-elbow-style)
                    pts (gtp:curve-points ent))

              (if (or (null pts) (< (length pts) 2))
                (princ "\nCould not obtain route vertices.")
                (progn
                  ; V1.9: one interpretation only. Every interior route vertex is
                  ; the theoretical centreline intersection / bend corner.
                  (setq result (gtp:model-corner-route pts dn series carrier casing mode elbowStyle)
                        spoolCount (nth 0 result)
                        elbowCount (nth 1 result)
                        clippedCount (nth 2 result)
                        shortFallbackCount (nth 3 result))

                  (princ
                    (strcat
                      "\nCreated Isoplus DN" (itoa dn) " Series " (itoa series)
                      " | route=Corners"
                      " | carrier OD " (rtos carrierMM 2 1) " mm"
                      " | casing OD " (rtos casingMM 2 1) " mm | " mode
                      " | " (itoa spoolCount) " straight spool(s)"
                      " | " (itoa elbowCount) " 3D elbow(s)."))

                  (if (> clippedCount 0)
                    (princ
                      (strcat
                        "\nNote: " (itoa clippedCount)
                        " fitting leg(s) were shortened because an adjacent route segment is shorter than the catalogue fitting envelope.")))
                  (if (> shortFallbackCount 0)
                    (princ "\nNote: Short elbow is not listed for this DN, so the catalogue Standard leg was used.")))))))))))

  (setvar "CMDECHO" oldcmdecho)
  (princ)
)

(princ "\nGTP V1.9 miter patch loaded. Commands: GTPMITER, GTPPIPE.")
(princ)
