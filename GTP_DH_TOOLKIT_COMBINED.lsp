; GTP_DH_TOOLKIT_COMBINED.LSP
; =============================================================================
; SELF-CONTAINED GENERATED BUILD - APPLOAD ONLY THIS FILE
;
; Generated from the proven GTP geometry core, component Steps 1-6,
; the final multi-component route bridge, intelligent GTPPIPE session,
; reducer-driven variable-DN generation, and the authoritative ISOPLUS
; 11/2024 catalogue correction layer. Do not hand-edit this generated
; file; edit the source modules and run tools/build_gtp_combined.py.
;
; Source manifest (SHA-256 of included text):
;   GTP_DH_TOOLKIT.lsp [geometry core only]: 6ee2c36a14c7ff2630d20aa5c29f240a83a4f11216593c8a3a60d8aaa6ee70a0
;   GTP_Component_Architecture.lsp: 8fdaab1a0d204fd21e855dff3aec53200b24092886fb1c5a0f552c0fe8ecf15f
;   GTP_Elbow_Component_Integration.lsp: 258ee6aa6749eb07b7bb2137211f0223020a4623a97f85d7fbf30905edec7c61
;   GTP_Valve_Component.lsp: 67ea586ed7fc89a4cd1a8466cb965ae8cd05de6ff6d4cb60bb65841b7f9ede6d
;   GTP_Valve_Aware_Pipe_Integration.lsp: 66bc2d03124538a84a1a6c1dfaf3f4c7e9b06024934032cf817a99c51404ccb8
;   GTP_Valve_Catalogue_Integration.lsp: ee6c0e54553207fb05819464ca46a9771bb49406715641767a4f54257e21a64b
;   GTP_Component_Persistence_and_Fittings.lsp: 428e3924b4af03bf16d98a932715c9677107ddb61a9de78be9769f8110df46c6
;   GTP_Combined_Final_Bridge.lsp: 916a211b9009cdaa2356e2533e4cc7b63de9289fe7791546c8ab7fb4da0aea90
;   GTP_Smart_Pipe_Command.lsp: 221ea42324a10d54da556c7b6bb4801d3ce45b514bc36f77029c7a76b952304f
;   GTP_Variable_DN_Route.lsp: 248c97000fab965d3f6423036f399bf96c334bfd632686660a3cbf4f5a558391
;   GTP_Variable_DN_Fixes.lsp: 282d87879a60f84a8093f0ecc49bbe831b2643fb7c912e3f5cfa1fec4f284083
;   GTP_Catalogue_Corrections.lsp: 92e77d68299d4b19d8aa92a12ad10fde504d4d44050f600056415a88006c7c0c
;
; Architecture:
;   route -> one-time setup -> reducer DN transitions -> component menu
;   -> route cleanup -> local-DN elbow footprints -> component footprints
;   -> local-DN straight intervals -> catalogue stock-length spools -> 3D solids
;   -> final ISOPLUS 11/2024 verified data/function overrides
; =============================================================================

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_DH_TOOLKIT.lsp [geometry core only]
; ===========================================================================
; GTP_DH_TOOLKIT.LSP
; Permanent AutoLISP toolkit for AutoCAD / AutoCAD Mechanical
; ONE FILE ONLY - update this file in place.
;
; Commands:
;   GTPPIPE   - Create Isoplus pre-insulated 3D pipe from a prepared route
;   GTPMITER  - Extend/trim two selected route ends to their axis intersection
;   GTPMITTER - Alias for GTPMITER
;   GTPUNITS  - Set/check catalogue-mm to drawing-unit conversion
;   GTPLAYER  - Create/check GTP layers
;   GTPHELP   - Show loaded commands
;
; Route rule:
;   GTPPIPE ignores duplicate and nearly-collinear intermediate route vertices.
;   Only real direction changes are treated as bend corners.
;   The original selected polyline is NOT modified.
;   Route cleanup is fail-safe: if cleanup fails, the original route is used.
;   True straight runs are still split by catalogue stock length for real spool joints.

(vl-load-com)

; -----------------------------------------------------------------------------
; AUTOLISP FUNCTION-AVAILABILITY COMPATIBILITY
; -----------------------------------------------------------------------------
; AutoLISP does not provide Common Lisp FBOUNDP.  Use ATOMS-FAMILY to test
; whether a named function/command symbol is currently defined without calling it.
(defun gtp:function-defined-p (sym / name hit)
  (setq name (vl-symbol-name sym))
  (setq hit (car (atoms-family 0 (list name))))
  (if hit T nil)
)

; -----------------------------------------------------------------------------
; CATALOGUE DATA - millimetres
; -----------------------------------------------------------------------------
(setq *gtp-pipe-db*
  '(
    (20  26.9  90  110 125)
    (25  33.7  90  110 125)
    (32  42.4  110 125 140)
    (40  48.3  110 125 140)
    (50  60.3  125 140 160)
    (65  76.1  140 160 180)
    (80  88.9  160 180 200)
    (100 114.3 200 225 250)
    (125 139.7 225 250 280)
    (150 168.3 250 280 315)
    (200 219.1 315 355 400)
    (250 273.0 400 450 500)
    (300 323.9 450 500 560)
    (350 355.6 500 560 630)
    (400 406.4 560 630 710)
    (450 457.2 630 710 800)
    (500 508.0 710 800 900)
    (600 610.0 800 900 1000)
  )
)

(setq *gtp-elbow-db*
  '(
    (20  600.0 1000.0) (25  600.0 1000.0) (32  600.0 1000.0)
    (40  600.0 1000.0) (50  600.0 1000.0) (65  600.0 1000.0)
    (80  600.0 1000.0) (100 700.0 1000.0) (125 750.0 1000.0)
    (150 800.0 1000.0) (200 nil   1000.0) (250 nil   1000.0)
    (300 nil   1000.0) (350 nil   1000.0) (400 nil   1000.0)
    (450 nil   1100.0) (500 nil   1200.0) (600 nil   1300.0)
  )
)

(setq *gtp-max-pipe-length-mm* 12000.0)
(setq *gtp-end-cutback-mm* 220.0)
(setq *gtp-standard-bend-radius-factor* 3.0)
(setq *gtp-min-elbow-straight-mm* 50.0)
(setq *gtp-straight-angle-tol-deg* 2.0)
(setq *gtp-duplicate-point-tol* 1e-8)
(setq *gtp-mm-to-du* 1.0)
(setq *gtp-drawing-unit-name* "millimetres")
(setq *gtp-pipe-color* 1)
(setq *gtp-flow-type* "Flow")

(defun gtp:unit-info-from-insunits (u)
  (cond
    ((= u 1)  (list "inches" (/ 1.0 25.4)))
    ((= u 2)  (list "feet" (/ 1.0 304.8)))
    ((= u 4)  (list "millimetres" 1.0))
    ((= u 5)  (list "centimetres" 0.1))
    ((= u 6)  (list "metres" 0.001))
    ((= u 7)  (list "kilometres" 0.000001))
    ((= u 10) (list "yards" (/ 1.0 914.4)))
    ((= u 14) (list "decimetres" 0.01))
    ((= u 15) (list "decametres" 0.0001))
    ((= u 16) (list "hectometres" 0.00001))
    (T nil)
  )
)
(defun gtp:manual-unit-info (/ s)
  (initget "MM CM M Inch Feet")
  (setq s (getkword "\nDrawing unit [MM/CM/M/Inch/Feet] <MM>: "))
  (if (null s) (setq s "MM"))
  (cond
    ((= s "MM")   (list "millimetres" 1.0))
    ((= s "CM")   (list "centimetres" 0.1))
    ((= s "M")    (list "metres" 0.001))
    ((= s "Inch") (list "inches" (/ 1.0 25.4)))
    ((= s "Feet") (list "feet" (/ 1.0 304.8)))
  )
)
(defun gtp:setup-units (/ s info)
  (initget "Auto MM CM M Inch Feet")
  (setq s (getkword "\nCatalogue is mm. Drawing unit [Auto/MM/CM/M/Inch/Feet] <Auto>: "))
  (if (null s) (setq s "Auto"))
  (cond
    ((= s "Auto")
      (setq info (gtp:unit-info-from-insunits (getvar "INSUNITS")))
      (if (null info) (setq info (gtp:manual-unit-info)))
    )
    ((= s "MM")   (setq info (list "millimetres" 1.0)))
    ((= s "CM")   (setq info (list "centimetres" 0.1)))
    ((= s "M")    (setq info (list "metres" 0.001)))
    ((= s "Inch") (setq info (list "inches" (/ 1.0 25.4))))
    ((= s "Feet") (setq info (list "feet" (/ 1.0 304.8))))
  )
  (setq *gtp-drawing-unit-name* (car info))
  (setq *gtp-mm-to-du* (cadr info))
  (princ (strcat "\nGTP scale: 1000 mm = " (rtos (* 1000.0 *gtp-mm-to-du*) 2 6) " drawing units [" *gtp-drawing-unit-name* "]."))
  info
)
(defun gtp:mm (x) (* x *gtp-mm-to-du*))
(defun c:GTPUNITS () (gtp:setup-units) (princ))

(defun gtp:ensure-layer (name color / doc lays lay)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq lays (vla-get-Layers doc))
  (if (tblsearch "LAYER" name) (setq lay (vla-Item lays name)) (setq lay (vla-Add lays name)))
  (if color (vla-put-Color lay color))
  (vl-catch-all-apply 'vla-put-LayerOn (list lay :vlax-true))
  (vl-catch-all-apply 'vla-put-Freeze (list lay :vlax-false))
  (vl-catch-all-apply 'vla-put-Lock (list lay :vlax-false))
  lay
)
(defun gtp:layers ()
  (gtp:ensure-layer "GTP-PIPE-CASING" 8)
  (gtp:ensure-layer "GTP-PIPE-INSULATION" 2)
  (gtp:ensure-layer "GTP-PIPE-CARRIER" 1)
  (gtp:ensure-layer "GTP-PIPE-CENTRELINE" 4)
  (princ)
)
(defun c:GTPLAYER () (gtp:layers) (princ "\nGTP layers ready and visible.") (princ))

(defun gtp:vadd (a b) (mapcar '+ a b))
(defun gtp:vsub (a b) (mapcar '- a b))
(defun gtp:vscale (v s) (mapcar '(lambda (x) (* x s)) v))
(defun gtp:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b)) (* (caddr a) (caddr b))))
(defun gtp:vmag (v) (sqrt (gtp:dot v v)))
(defun gtp:vunit (v / m) (setq m (gtp:vmag v)) (if (> m 1e-12) (gtp:vscale v (/ 1.0 m)) '(0.0 0.0 1.0)))
(defun gtp:cross (a b)
  (list
    (- (* (cadr a) (caddr b)) (* (caddr a) (cadr b)))
    (- (* (caddr a) (car b)) (* (car a) (caddr b)))
    (- (* (car a) (cadr b)) (* (cadr a) (car b)))
  )
)
(defun gtp:rad->deg (a) (* a (/ 180.0 pi)))
(defun gtp:tan (a / c) (setq c (cos a)) (if (< (abs c) 1e-12) 1e99 (/ (sin a) c)))
(defun gtp:variant (lst)
  (vlax-make-variant
    (vlax-safearray-fill (vlax-make-safearray vlax-vbDouble '(0 . 2)) lst)
  )
)
(defun gtp:axis-matrix (p1 p2 / z ref x y mid)
  (setq z (gtp:vunit (gtp:vsub p2 p1)))
  (setq mid (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
  (if (> (abs (caddr z)) 0.999) (setq ref '(0.0 1.0 0.0)) (setq ref '(0.0 0.0 1.0)))
  (setq x (gtp:vunit (gtp:cross ref z)))
  (setq y (gtp:cross z x))
  (list
    (list (car x) (car y) (car z) (car mid))
    (list (cadr x) (cadr y) (cadr z) (cadr mid))
    (list (caddr x) (caddr y) (caddr z) (caddr mid))
    (list 0.0 0.0 0.0 1.0)
  )
)
(defun gtp:frame-z (origin z / ref x y)
  (setq z (gtp:vunit z))
  (if (> (abs (caddr z)) 0.999) (setq ref '(0.0 1.0 0.0)) (setq ref '(0.0 0.0 1.0)))
  (setq x (gtp:vunit (gtp:cross ref z)))
  (setq y (gtp:cross z x))
  (list
    (list (car x) (car y) (car z) (car origin))
    (list (cadr x) (cadr y) (cadr z) (cadr origin))
    (list (caddr x) (caddr y) (caddr z) (caddr origin))
    (list 0.0 0.0 0.0 1.0)
  )
)
(defun gtp:frame-xyz (origin x y z)
  (list
    (list (car x) (car y) (car z) (car origin))
    (list (cadr x) (cadr y) (cadr z) (cadr origin))
    (list (caddr x) (caddr y) (caddr z) (caddr origin))
    (list 0.0 0.0 0.0 1.0)
  )
)

(defun gtp:make-cylinder (p1 p2 dia layer / doc ms len obj)
  (setq len (distance p1 p2))
  (if (> len 1e-8)
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq ms (vla-get-ModelSpace doc))
      (setq obj (vla-AddCylinder ms (gtp:variant '(0.0 0.0 0.0)) (/ dia 2.0) len))
      (vla-TransformBy obj (vlax-tmatrix (gtp:axis-matrix p1 p2)))
      (vla-put-Layer obj layer)
      (vla-put-Color obj *gtp-pipe-color*)
      obj
    )
  )
)
(defun gtp:safe-delete (obj) (if obj (vl-catch-all-apply 'vla-Delete (list obj))))
(defun gtp:make-circle-region (center normal radius / doc ms cir arr regs reg)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq cir (vla-AddCircle ms (gtp:variant '(0.0 0.0 0.0)) radius))
  (vla-TransformBy cir (vlax-tmatrix (gtp:frame-z center normal)))
  (setq arr (vlax-make-safearray vlax-vbObject '(0 . 0)))
  (vlax-safearray-put-element arr 0 cir)
  (setq regs (vl-catch-all-apply 'vla-AddRegion (list ms arr)))
  (if (vl-catch-all-error-p regs)
    (progn (gtp:safe-delete cir) nil)
    (progn (setq reg (vlax-safearray-get-element (vlax-variant-value regs) 0)) (gtp:safe-delete cir) reg)
  )
)
(defun gtp:make-arc-path (center t1 normal radius phi / doc ms x y arc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq x (gtp:vunit (gtp:vsub t1 center)))
  (setq y (gtp:cross normal x))
  (setq arc (vla-AddArc ms (gtp:variant '(0.0 0.0 0.0)) radius 0.0 phi))
  (vla-TransformBy arc (vlax-tmatrix (gtp:frame-xyz center x y normal)))
  arc
)
(defun gtp:sweep-arc (center t1 normal tangent radius phi dia layer / doc ms path reg sol)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq path (gtp:make-arc-path center t1 normal radius phi))
  (setq reg (gtp:make-circle-region t1 tangent (/ dia 2.0)))
  (if (and path reg) (setq sol (vl-catch-all-apply 'vla-AddExtrudedSolidAlongPath (list ms reg path))))
  (gtp:safe-delete reg)
  (gtp:safe-delete path)
  (if (or (null sol) (vl-catch-all-error-p sol)) nil (progn (vla-put-Layer sol layer) (vla-put-Color sol *gtp-pipe-color*) sol))
)
(defun gtp:arc-point (center x y radius a)
  (gtp:vadd center (gtp:vadd (gtp:vscale x (* radius (cos a))) (gtp:vscale y (* radius (sin a)))))
)
(defun gtp:segmented-arc (center t1 normal radius phi dia layer / x y seg i a0 a1 p0 p1 obj out)
  (setq x (gtp:vunit (gtp:vsub t1 center)))
  (setq y (gtp:cross normal x))
  (setq seg (max 8 (fix (+ 0.5 (* 18.0 (/ phi (/ pi 2.0)))))))
  (setq i 0 out '())
  (while (< i seg)
    (setq a0 (* phi (/ (float i) seg)) a1 (* phi (/ (float (1+ i)) seg)))
    (setq p0 (gtp:arc-point center x y radius a0) p1 (gtp:arc-point center x y radius a1))
    (setq obj (gtp:make-cylinder p0 p1 dia layer))
    (if obj (setq out (cons obj out)))
    (setq i (1+ i))
  )
  (reverse out)
)
(defun gtp:model-arc (center t1 normal tangent radius phi dia layer / obj fallback)
  (setq obj (vl-catch-all-apply 'gtp:sweep-arc (list center t1 normal tangent radius phi dia layer)))
  (if (and obj (not (vl-catch-all-error-p obj)))
    (list obj)
    (progn
      (setq fallback (vl-catch-all-apply 'gtp:segmented-arc (list center t1 normal radius phi dia layer)))
      (if (vl-catch-all-error-p fallback) nil fallback)
    )
  )
)

(defun gtp:find-dn (dn) (assoc dn *gtp-pipe-db*))
(defun gtp:casing-od (row series)
  (cond ((= series 1) (nth 2 row)) ((= series 2) (nth 3 row)) ((= series 3) (nth 4 row)))
)
(defun gtp:get-dn (/ dn row)
  (while (null row)
    (setq dn (getint "\nNominal DN [20/25/32/40/50/65/80/100/125/150/200/250/300/350/400/450/500/600]: "))
    (if dn (setq row (gtp:find-dn dn)))
    (if (and dn (null row)) (princ "\nDN not in current database."))
  )
  row
)
(defun gtp:get-series (/ s) (initget "1 2 3") (setq s (getkword "\nInsulation series [1/2/3] <2>: ")) (if s (atoi s) 2))
(defun gtp:get-mode (/ s) (initget "CASING FULL") (setq s (getkword "\nModel mode [CASING/FULL] <CASING>: ")) (if s s "CASING"))
(defun gtp:get-flow-type (/ s)
  (initget "Flow Return")
  (setq s (getkword "\nPipe duty [Flow/Return] <Flow>: "))
  (if (null s) (setq s "Flow"))
  (setq *gtp-flow-type* s *gtp-pipe-color* (if (= s "Flow") 1 5))
  (princ (strcat "\n" s " pipe colour: " (if (= s "Flow") "red." "blue.")))
  s
)
(defun gtp:get-elbow-style (/ s) (initget "Standard Short") (setq s (getkword "\nElbow leg [Standard/Short] <Standard>: ")) (if s s "Standard"))
(defun gtp:elbow-leg-mm (dn style / row short standard)
  (setq row (assoc dn *gtp-elbow-db*) short (nth 1 row) standard (nth 2 row))
  (if (= style "Short") (if short short standard) standard)
)
(defun gtp:make-elbow-spec (prev vertex next dn carrier casing style / d1 d2 cr cm dp phi deg leg0 maxleg leg normal desiredR minR minStraight tang maxR radius tanDist fs fe t1 t2 inward center)
  (setq d1 (gtp:vunit (gtp:vsub vertex prev)) d2 (gtp:vunit (gtp:vsub next vertex)))
  (setq cr (gtp:cross d1 d2) cm (gtp:vmag cr) dp (gtp:dot d1 d2) phi (atan cm dp) deg (gtp:rad->deg phi))
  (if (or (< deg 1.0) (> deg 175.0) (< cm 1e-10)) nil
    (progn
      (setq normal (gtp:vunit cr) leg0 (gtp:mm (gtp:elbow-leg-mm dn style)))
      (setq maxleg (min (* 0.45 (distance prev vertex)) (* 0.45 (distance vertex next))))
      (setq leg (min leg0 maxleg))
      (setq desiredR (* *gtp-standard-bend-radius-factor* carrier) minR (* 0.55 casing))
      (setq minStraight (min (* 0.25 leg) (max (gtp:mm *gtp-min-elbow-straight-mm*) (gtp:mm *gtp-end-cutback-mm*))))
      (setq tang (gtp:tan (/ phi 2.0)))
      (setq maxR (if (> tang 1e-10) (/ (max 0.0 (- leg minStraight)) tang) desiredR))
      (setq radius (min desiredR maxR))
      (if (< radius minR) nil
        (progn
          (setq tanDist (* radius tang))
          (setq fs (gtp:vadd vertex (gtp:vscale d1 (- leg))))
          (setq fe (gtp:vadd vertex (gtp:vscale d2 leg)))
          (setq t1 (gtp:vadd vertex (gtp:vscale d1 (- tanDist))))
          (setq t2 (gtp:vadd vertex (gtp:vscale d2 tanDist)))
          (setq inward (gtp:vunit (gtp:cross normal d1)) center (gtp:vadd t1 (gtp:vscale inward radius)))
          (list (cons 'radius radius) (cons 'phi phi) (cons 'deg deg) (cons 'd1 d1) (cons 'd2 d2) (cons 'normal normal) (cons 'start fs) (cons 'tan1 t1) (cons 'center center) (cons 'tan2 t2) (cons 'end fe) (cons 'clipped (< leg (- leg0 1e-8))))
        )
      )
    )
  )
)
(defun gtp:spec (key spec) (cdr (assoc key spec)))
(defun gtp:model-elbow (spec carrier casing mode / r phi d1 d2 normal fs t1 center t2 fe cut cut1 cut2 cs ce)
  (setq r (gtp:spec 'radius spec) phi (gtp:spec 'phi spec) d1 (gtp:spec 'd1 spec) d2 (gtp:spec 'd2 spec) normal (gtp:spec 'normal spec) fs (gtp:spec 'start spec) t1 (gtp:spec 'tan1 spec) center (gtp:spec 'center spec) t2 (gtp:spec 'tan2 spec) fe (gtp:spec 'end spec))
  (gtp:make-cylinder fs t1 carrier "GTP-PIPE-CARRIER")
  (gtp:model-arc center t1 normal d1 r phi carrier "GTP-PIPE-CARRIER")
  (gtp:make-cylinder t2 fe carrier "GTP-PIPE-CARRIER")
  (setq cut (gtp:mm *gtp-end-cutback-mm*) cut1 (min cut (* 0.80 (distance fs t1))) cut2 (min cut (* 0.80 (distance t2 fe))))
  (setq cs (gtp:vadd fs (gtp:vscale d1 cut1)) ce (gtp:vadd fe (gtp:vscale d2 (- cut2))))
  (gtp:make-cylinder cs t1 casing "GTP-PIPE-CASING")
  (gtp:model-arc center t1 normal d1 r phi casing "GTP-PIPE-CASING")
  (gtp:make-cylinder t2 ce casing "GTP-PIPE-CASING")
  (if (= mode "FULL")
    (progn
      (gtp:make-cylinder cs t1 casing "GTP-PIPE-INSULATION")
      (gtp:model-arc center t1 normal d1 r phi casing "GTP-PIPE-INSULATION")
      (gtp:make-cylinder t2 ce casing "GTP-PIPE-INSULATION")
    )
  )
)
(defun gtp:point-along (p1 p2 dist) (gtp:vadd p1 (gtp:vscale (gtp:vunit (gtp:vsub p2 p1)) dist)))
(defun gtp:model-spool (p1 p2 carrier casing mode / len cut c1 c2)
  (setq len (distance p1 p2) cut (gtp:mm *gtp-end-cutback-mm*))
  (if (>= (* 2.0 cut) len) (setq cut (/ len 4.0)))
  (setq c1 (gtp:point-along p1 p2 cut) c2 (gtp:point-along p1 p2 (- len cut)))
  (gtp:make-cylinder p1 p2 carrier "GTP-PIPE-CARRIER")
  (if (> (distance c1 c2) 1e-8)
    (progn
      (gtp:make-cylinder c1 c2 casing "GTP-PIPE-CASING")
      (if (= mode "FULL") (gtp:make-cylinder c1 c2 casing "GTP-PIPE-INSULATION"))
    )
  )
)
(defun gtp:model-segment (p1 p2 carrier casing mode / len dir pos piece s1 s2 count)
  (setq len (distance p1 p2) dir (gtp:vunit (gtp:vsub p2 p1)) pos 0.0 count 0)
  (while (< pos (- len 1e-8))
    (setq piece (min (gtp:mm *gtp-max-pipe-length-mm*) (- len pos)))
    (setq s1 (gtp:vadd p1 (gtp:vscale dir pos)) s2 (gtp:vadd p1 (gtp:vscale dir (+ pos piece))))
    (gtp:model-spool s1 s2 carrier casing mode)
    (setq pos (+ pos piece) count (1+ count))
  )
  count
)
(defun gtp:curve-points (ename / endParam i p pts)
  (setq endParam (vl-catch-all-apply 'vlax-curve-getEndParam (list ename)))
  (if (vl-catch-all-error-p endParam) nil
    (progn
      (setq i 0 pts '())
      (while (<= i (fix endParam))
        (setq p (vlax-curve-getPointAtParam ename i))
        (if p (setq pts (append pts (list p))))
        (setq i (1+ i))
      )
      pts
    )
  )
)
(defun gtp:remove-duplicate-route-points (pts / out lastp p)
  (setq out '() lastp nil)
  (foreach p pts
    (if (or (null lastp) (> (distance lastp p) *gtp-duplicate-point-tol*)) (progn (setq out (append out (list p))) (setq lastp p)))
  )
  out
)
(defun gtp:route-turn-angle-deg (a b c / u v cr dp)
  (setq u (gtp:vunit (gtp:vsub b a)) v (gtp:vunit (gtp:vsub c b)) cr (gtp:vmag (gtp:cross u v)) dp (gtp:dot u v))
  (gtp:rad->deg (atan cr dp))
)
(defun gtp:simplify-route-points (pts / originalCount cleaned duplicateRemoved n out i prev cur nxt ang straightRemoved)
  (setq originalCount (length pts) cleaned (gtp:remove-duplicate-route-points pts) duplicateRemoved (- originalCount (length cleaned)) straightRemoved 0)
  (if (<= (length cleaned) 2) (list cleaned duplicateRemoved 0)
    (progn
      (setq n (length cleaned) out (list (car cleaned)) i 1)
      (while (< i (1- n))
        (setq prev (nth (1- i) cleaned) cur (nth i cleaned) nxt (nth (1+ i) cleaned) ang (gtp:route-turn-angle-deg prev cur nxt))
        (if (<= ang *gtp-straight-angle-tol-deg*) (setq straightRemoved (1+ straightRemoved)) (setq out (append out (list cur))))
        (setq i (1+ i))
      )
      (setq out (append out (list (last cleaned))))
      (list out duplicateRemoved straightRemoved)
    )
  )
)
(defun gtp:safe-simplify-route-points (pts / r)
  (setq r (vl-catch-all-apply 'gtp:simplify-route-points (list pts)))
  (if (or (vl-catch-all-error-p r) (null r) (null (car r)) (< (length (car r)) 2))
    (progn (princ "\nRoute cleanup warning: cleanup failed, so the original route vertices will be used.") (list pts 0 0))
    r
  )
)
(defun gtp:model-corner-route (pts dn carrier casing mode style / n elbows i spec p1 p2 s e spoolCount elbowCount clippedCount)
  (setq n (length pts) elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (while (< i n)
    (setq spec nil)
    (if (and (> i 0) (< i (1- n))) (setq spec (gtp:make-elbow-spec (nth (1- i) pts) (nth i pts) (nth (1+ i) pts) dn carrier casing style)))
    (if (and spec (gtp:spec 'clipped spec)) (setq clippedCount (1+ clippedCount)))
    (setq elbows (append elbows (list spec)) i (1+ i))
  )
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts))
    (setq s (if (nth i elbows) (gtp:spec 'end (nth i elbows)) p1))
    (setq e (if (nth (1+ i) elbows) (gtp:spec 'start (nth (1+ i) elbows)) p2))
    (if (> (distance s e) 1e-8) (setq spoolCount (+ spoolCount (gtp:model-segment s e carrier casing mode))))
    (setq i (1+ i))
  )
  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows) (progn (gtp:model-elbow (nth i elbows) carrier casing mode) (setq elbowCount (1+ elbowCount))))
    (setq i (1+ i))
  )
  (list spoolCount elbowCount clippedCount)
)
(defun c:GTPPIPE (/ *error* old ent typ row dn series carrierMM casingMM carrier casing mode flowType style rawPts cleanInfo pts dupRemoved straightRemoved result)
  (vl-load-com)
  (defun *error* (msg)
    (if old (setvar "CMDECHO" old))
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPPIPE error: " msg)))
    (princ)
  )
  (setq old (getvar "CMDECHO")) (setvar "CMDECHO" 0) (gtp:layers)
  (setq ent (car (entsel "\nSelect prepared route LINE / 2D or 3D POLYLINE: ")))
  (if ent
    (progn
      (setq typ (cdr (assoc 0 (entget ent))))
      (if (member typ '("LINE" "LWPOLYLINE" "POLYLINE"))
        (progn
          (gtp:setup-units) (setq row (gtp:get-dn) dn (nth 0 row) carrierMM (nth 1 row) series (gtp:get-series) casingMM (gtp:casing-od row series))
          (setq carrier (gtp:mm carrierMM) casing (gtp:mm casingMM) mode (gtp:get-mode) flowType (gtp:get-flow-type) style (gtp:get-elbow-style))
          (setq rawPts (gtp:curve-points ent))
          (if (and rawPts (>= (length rawPts) 2))
            (progn
              (setq cleanInfo (gtp:safe-simplify-route-points rawPts) pts (nth 0 cleanInfo) dupRemoved (nth 1 cleanInfo) straightRemoved (nth 2 cleanInfo))
              (princ (strcat "\nRoute cleanup: " (itoa (length rawPts)) " input vertex/vertices -> " (itoa (length pts)) " modelling vertex/vertices."))
              (if (> (+ dupRemoved straightRemoved) 0) (princ (strcat " Ignored " (itoa dupRemoved) " duplicate and " (itoa straightRemoved) " nearly-collinear intermediate point(s).")))
              (princ "\nGenerating 3D pipe...")
              (setq result (gtp:model-corner-route pts dn carrier casing mode style))
              (princ (strcat "\nCreated Isoplus DN" (itoa dn) " Series " (itoa series) " | " flowType " | " (itoa (nth 0 result)) " straight spool(s) | " (itoa (nth 1 result)) " 3D elbow(s)."))
              (if (> (nth 2 result) 0) (princ (strcat "\nNote: " (itoa (nth 2 result)) " elbow fitting leg(s) were shortened for available route length.")))
              (if (and (= (nth 0 result) 0) (= (nth 1 result) 0)) (princ "\nWarning: no pipe solids were generated from this route. Check that the selected route has non-zero length."))
            )
            (princ "\nCould not obtain route vertices.")
          )
        )
        (princ "\nGTPPIPE accepts LINE, LWPOLYLINE or POLYLINE.")
      )
    )
    (princ "\nNothing selected.")
  )
  (setvar "CMDECHO" old) (princ)
)

(defun gtp:last-item (lst) (last lst))
(defun gtp:butlast (lst / out) (setq out '()) (while (cdr lst) (setq out (append out (list (car lst)))) (setq lst (cdr lst))) out)
(defun gtp:replace-first (lst value) (if lst (cons value (cdr lst)) (list value)))
(defun gtp:replace-last (lst value) (if lst (append (gtp:butlast lst) (list value)) (list value)))
(defun gtp:valid-route-p (ent / typ) (if ent (progn (setq typ (cdr (assoc 0 (entget ent)))) (member typ '("LINE" "LWPOLYLINE" "POLYLINE"))) nil))
(defun gtp:end-info (pts pick / p0 pN d0 dN adj dir ordered)
  (setq p0 (car pts) pN (gtp:last-item pts) d0 (distance pick p0) dN (distance pick pN))
  (if (<= d0 dN)
    (progn (setq adj (cadr pts) dir (gtp:vunit (gtp:vsub p0 adj)) ordered (reverse pts)) (list (cons 'end p0) (cons 'dir dir) (cons 'ordered ordered) (cons 'len (distance p0 adj))))
    (progn (setq adj (nth (- (length pts) 2) pts) dir (gtp:vunit (gtp:vsub pN adj)) ordered pts) (list (cons 'end pN) (cons 'dir dir) (cons 'ordered ordered) (cons 'len (distance pN adj))))
  )
)
(defun gtp:line-line-intersection (p1 u p2 v / w a b c d e den s t q1 q2)
  (setq u (gtp:vunit u) v (gtp:vunit v) w (gtp:vsub p1 p2) a (gtp:dot u u) b (gtp:dot u v) c (gtp:dot v v) d (gtp:dot u w) e (gtp:dot v w) den (- (* a c) (* b b)))
  (if (< (abs den) 1e-10) nil
    (progn
      (setq s (/ (- (* b e) (* c d)) den) t (/ (- (* a e) (* b d)) den))
      (setq q1 (gtp:vadd p1 (gtp:vscale u s)) q2 (gtp:vadd p2 (gtp:vscale v t)))
      (list (cons 'corner (mapcar '(lambda (x y) (/ (+ x y) 2.0)) q1 q2)) (cons 'gap (distance q1 q2)))
    )
  )
)
(defun gtp:make-3d-polyline (pts layer / head)
  (setq head (entmakex (list '(0 . "POLYLINE") '(100 . "AcDbEntity") (cons 8 layer) '(100 . "AcDb3dPolyline") (cons 10 '(0.0 0.0 0.0)) '(66 . 1) '(70 . 8))))
  (if head
    (progn
      (foreach p pts (entmakex (list '(0 . "VERTEX") '(100 . "AcDbEntity") (cons 8 layer) '(100 . "AcDbVertex") '(100 . "AcDb3dPolylineVertex") (cons 10 p) '(70 . 32))))
      (entmakex (list '(0 . "SEQEND") '(100 . "AcDbEntity") (cons 8 layer))) head
    )
  )
)
(defun gtp:miter-route-points (info1 info2 corner / a b)
  (setq a (gtp:replace-last (cdr (assoc 'ordered info1)) corner) b (reverse (cdr (assoc 'ordered info2))) b (gtp:replace-first b corner))
  (append a (cdr b))
)
(defun c:GTPMITER (/ *error* old sel1 sel2 ent1 ent2 pick1 pick2 pts1 pts2 info1 info2 ll corner gap tol route newEnt ss ans)
  (vl-load-com)
  (defun *error* (msg) (if old (setvar "CMDECHO" old)) (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort")) (princ (strcat "\nGTPMITER error: " msg))) (princ))
  (setq old (getvar "CMDECHO")) (setvar "CMDECHO" 0) (gtp:layers)
  (setq sel1 (entsel "\nSelect FIRST route near the end to connect: "))
  (if sel1
    (progn
      (setq ent1 (car sel1))
      (if (gtp:valid-route-p ent1)
        (progn
          (setq sel2 (entsel "\nSelect SECOND route near the end to connect: "))
          (if (and sel2 (/= ent1 (car sel2)) (gtp:valid-route-p (car sel2)))
            (progn
              (setq ent2 (car sel2) pick1 (trans (cadr sel1) 1 0) pick2 (trans (cadr sel2) 1 0) pts1 (gtp:curve-points ent1) pts2 (gtp:curve-points ent2))
              (if (and pts1 pts2 (>= (length pts1) 2) (>= (length pts2) 2))
                (progn
                  (setq info1 (gtp:end-info pts1 pick1) info2 (gtp:end-info pts2 pick2))
                  (setq ll (gtp:line-line-intersection (cdr (assoc 'end info1)) (cdr (assoc 'dir info1)) (cdr (assoc 'end info2)) (cdr (assoc 'dir info2))))
                  (if ll
                    (progn
                      (setq corner (cdr (assoc 'corner ll)) gap (cdr (assoc 'gap ll)) tol (max 1e-7 (* 0.002 (max (cdr (assoc 'len info1)) (cdr (assoc 'len info2))))))
                      (if (<= gap tol)
                        (progn
                          (setq route (gtp:miter-route-points info1 info2 corner) newEnt (gtp:make-3d-polyline route "GTP-PIPE-CENTRELINE"))
                          (if newEnt
                            (progn
                              (princ (strcat "\nMiter centreline created at (" (rtos (car corner) 2 4) ", " (rtos (cadr corner) 2 4) ", " (rtos (caddr corner) 2 4) ")."))
                              (initget "Keep Delete") (setq ans (getkword "\nSource objects [Keep/Delete] <Keep>: ")) (if (null ans) (setq ans "Keep"))
                              (if (= ans "Delete") (progn (entdel ent1) (entdel ent2)))
                              (setq ss (ssadd)) (ssadd newEnt ss) (sssetfirst nil ss) (princ "\nNew centreline selected. Run GTPPIPE.")
                            )
                            (princ "\nCould not create joined 3D centreline.")
                          )
                        )
                        (princ (strcat "\nThe two selected axes are skew in 3D. Closest gap = " (rtos gap 2 6) "."))
                      )
                    )
                    (princ "\nSelected route ends are parallel/nearly parallel; no miter intersection exists.")
                  )
                )
                (princ "\nCould not read route vertices.")
              )
            )
            (princ "\nSecond selection must be a different LINE/POLYLINE.")
          )
        )
        (princ "\nFirst selection must be a LINE/POLYLINE.")
      )
    )
    (princ "\nNothing selected.")
  )
  (setvar "CMDECHO" old) (princ)
)
(defun c:GTPMITTER () (c:GTPMITER))

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Component_Architecture.lsp
; ===========================================================================
; GTP_COMPONENT_ARCHITECTURE.LSP
; -----------------------------------------------------------------------------
; Component architecture foundation for GTPPIPE.
;
; PURPOSE
;   This file introduces the data model needed to move GTPPIPE from a
;   route-only modeller toward a component-aware pipe system.
;
; IMPORTANT
;   This file intentionally has NO effect on the existing GTPPIPE command.
;   It does not replace the current route modeller, elbow modeller, catalogue,
;   or solid-generation functions.  Load it alongside GTP_DH_TOOLKIT.lsp while
;   the architecture is being introduced incrementally.
;
; DESIGN RULES
;   ROUTE       = where the pipe centreline goes.
;   COMPONENT   = something installed in/on the route (elbow, valve, tee...).
;   CATALOGUE   = dimensional/product information for a component.
;   MODEL       = AutoCAD geometry generated from route + component data.
;
;   A component is centre-based.  Its insertion point is its physical centre,
;   not the beginning or end of its footprint.
;
;   The component longitudinal direction is independent of the current UCS.
;   This is required for valves and future components in arbitrary 3D routes.
;
;   Pipe splitting around a component is a later modelling step.  This file
;   only establishes the data structures and pure helper functions needed for
;   that step.
; -----------------------------------------------------------------------------

(vl-load-com)

; -----------------------------------------------------------------------------
; COMPONENT TYPE CONSTANTS
; -----------------------------------------------------------------------------
(setq *gtp-component-types*
  '("PIPE" "ELBOW" "VALVE" "TEE" "REDUCER" "BRANCH"
    "VENT_DRAIN" "END_CAP" "SPECIAL")
)

; -----------------------------------------------------------------------------
; COMPONENT OBJECT
;
; Representation:
;   (list
;     (cons 'id ...)
;     (cons 'type ...)
;     (cons 'system ...)
;     (cons 'dn ...)
;     (cons 'series ...)
;     (cons 'position ...)
;     (cons 'direction ...)
;     (cons 'up ...)
;     (cons 'length ...)
;     (cons 'catalogue ...)
;     (cons 'options ...)
;   )
;
; Keeping this as a property list instead of a VLA object is deliberate:
;   - it is lightweight;
;   - it is easy to inspect/debug;
;   - it is independent of AutoCAD geometry;
;   - later model functions can consume it without changing the data model.
; -----------------------------------------------------------------------------

(defun gtp:component-make
  (id type system dn series position direction up componentLength catalogue options)
  (list
    (cons 'id id)
    (cons 'type type)
    (cons 'system system)
    (cons 'dn dn)
    (cons 'series series)
    (cons 'position position)
    (cons 'direction (gtp:component-unit direction))
    (cons 'up (gtp:component-unit up))
    (cons 'length componentLength)
    (cons 'catalogue catalogue)
    (cons 'options options)
  )
)

(defun gtp:component-get (component key)
  (cdr (assoc key component))
)

(defun gtp:component-set (component key value)
  (if (assoc key component)
    (subst (cons key value) (assoc key component) component)
    (append component (list (cons key value)))
  )
)

(defun gtp:component-unit (v / m)
  (if (and v (= (length v) 3))
    (progn
      (setq m (sqrt (+ (* (car v) (car v))
                       (* (cadr v) (cadr v))
                       (* (caddr v) (caddr v)))))
      (if (> m 1e-12)
        (mapcar '(lambda (x) (/ x m)) v)
        '(1.0 0.0 0.0)
      )
    )
    '(1.0 0.0 0.0)
  )
)

; -----------------------------------------------------------------------------
; COMPONENT VALIDATION
; -----------------------------------------------------------------------------
(defun gtp:component-type-p (type)
  (member type *gtp-component-types*)
)

(defun gtp:component-valid-p (component / type pos dir len)
  (if (not component)
    nil
    (progn
      (setq type (gtp:component-get component 'type))
      (setq pos  (gtp:component-get component 'position))
      (setq dir  (gtp:component-get component 'direction))
      (setq len  (gtp:component-get component 'length))
      (and
        (gtp:component-type-p type)
        pos
        (= (length pos) 3)
        dir
        (= (length dir) 3)
        (or (null len) (>= len 0.0))
      )
    )
  )
)

; -----------------------------------------------------------------------------
; COMPONENT FOOTPRINT
;
; For a longitudinal component of length L:
;   start = centre - direction * L/2
;   end   = centre + direction * L/2
;
; These are geometric footprint points, not AutoCAD entities.
; -----------------------------------------------------------------------------
(defun gtp:component-start (component / p d half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq half (/ (gtp:component-get component 'length) 2.0))
  (mapcar
    '-
    p
    (mapcar '(lambda (x) (* x half)) d)
  )
)

(defun gtp:component-end (component / p d half)
  (setq p (gtp:component-get component 'position))
  (setq d (gtp:component-get component 'direction))
  (setq half (/ (gtp:component-get component 'length) 2.0))
  (mapcar
    '+
    p
    (mapcar '(lambda (x) (* x half)) d)
  )
)

(defun gtp:component-footprint (component)
  (list
    (cons 'start (gtp:component-start component))
    (cons 'end (gtp:component-end component))
  )
)

; -----------------------------------------------------------------------------
; COMPONENT CATALOGUE RECORD
;
; Catalogue data is deliberately kept separate from the installed component.
;
; Example concept:
;   catalogue =
;     ((family . "SINGLE_SHUTOFF_VALVE")
;      (length-mm . 360.0)
;      (stem-height-mm . 180.0)
;      (manufacturer . "ISOPLUS"))
;
; No real valve dimensions are added here yet.  The existing project catalogue
; remains the source of truth until the valve catalogue is migrated.
; -----------------------------------------------------------------------------

(defun gtp:catalogue-get (catalogue key)
  (cdr (assoc key catalogue))
)

(defun gtp:catalogue-set (catalogue key value)
  (if (assoc key catalogue)
    (subst (cons key value) (assoc key catalogue) catalogue)
    (append catalogue (list (cons key value)))
  )
)

; -----------------------------------------------------------------------------
; COMPONENT FACTORIES
;
; These factories create DATA ONLY.  They do not create AutoCAD geometry.
; -----------------------------------------------------------------------------

(defun gtp:make-pipe-component
  (id system dn series start end options)
  (gtp:component-make
    id
    "PIPE"
    system
    dn
    series
    (mapcar '(lambda (a b) (/ (+ a b) 2.0)) start end)
    (gtp:component-unit (mapcar '- end start))
    '(0.0 0.0 1.0)
    (distance start end)
    nil
    options
  )
)

(defun gtp:make-valve-component
  (id system dn series position direction up componentLength catalogue options)
  (gtp:component-make
    id "VALVE" system dn series position direction up componentLength catalogue options
  )
)

(defun gtp:make-generic-component
  (id type system dn series position direction up componentLength catalogue options)
  (gtp:component-make
    id type system dn series position direction up componentLength catalogue options
  )
)

; -----------------------------------------------------------------------------
; COMPONENT COLLECTION
; -----------------------------------------------------------------------------

(defun gtp:components-empty () '())

(defun gtp:components-add (components component)
  (if (gtp:component-valid-p component)
    (append components (list component))
    components
  )
)

(defun gtp:components-by-type (components type / out)
  (setq out '())
  (foreach component components
    (if (= (gtp:component-get component 'type) type)
      (setq out (append out (list component)))
    )
  )
  out
)

(defun gtp:component-find-id (components id / found)
  (setq found nil)
  (foreach component components
    (if (and (null found) (= (gtp:component-get component 'id) id))
      (setq found component)
    )
  )
  found
)

; -----------------------------------------------------------------------------
; ROUTE SEGMENT DATA
;
; This is the target internal representation for the future route engine.
; Existing GTPPIPE still uses its current point-list route representation.
; -----------------------------------------------------------------------------

(defun gtp:route-segment-make (id start end system dn series)
  (list
    (cons 'id id)
    (cons 'start start)
    (cons 'end end)
    (cons 'direction (gtp:component-unit (mapcar '- end start)))
    (cons 'length (distance start end))
    (cons 'system system)
    (cons 'dn dn)
    (cons 'series series)
  )
)

(defun gtp:route-segment-get (segment key)
  (cdr (assoc key segment))
)

; -----------------------------------------------------------------------------
; ROUTE MODEL CONTAINER
;
; A future route model can be represented as:
;   ((segments . (...))
;    (components . (...))
;    (metadata . (...)))
;
; Keeping this container separate from AutoCAD entities allows later features
; such as BOM extraction, component editing, clash checks, and pipe splitting
; to operate on the same model.
; -----------------------------------------------------------------------------

(defun gtp:route-model-make (segments components metadata)
  (list
    (cons 'segments segments)
    (cons 'components components)
    (cons 'metadata metadata)
  )
)

(defun gtp:route-model-get (model key)
  (cdr (assoc key model))
)

(defun gtp:route-model-add-component (model component / components)
  (setq components (gtp:route-model-get model 'components))
  (gtp:route-model-set
    model
    'components
    (gtp:components-add components component)
  )
)

(defun gtp:route-model-set (model key value)
  (if (assoc key model)
    (subst (cons key value) (assoc key model) model)
    (append model (list (cons key value)))
  )
)

; -----------------------------------------------------------------------------
; PIPE SPLIT PLANNING
;
; This function is intentionally planning-only.  It does not call any current
; GTP solid-generation function.  Given a straight pipe interval and a list of
; longitudinal components, it returns intervals that remain available for pipe
; modelling.
;
; Later this becomes the bridge between:
;   route geometry -> component footprints -> spool generator.
; -----------------------------------------------------------------------------

(defun gtp:point-distance-along (origin direction point)
  (gtp:dot
    (mapcar '- point origin)
    direction
  )
)

(defun gtp:component-overlap-range
  (origin direction startDist endDist component / cs ce a b lo hi)
  (setq cs (gtp:component-start component))
  (setq ce (gtp:component-end component))
  (setq a (gtp:point-distance-along origin direction cs))
  (setq b (gtp:point-distance-along origin direction ce))
  (setq lo (min a b))
  (setq hi (max a b))
  (if (and (< lo endDist) (> hi startDist))
    (list (max startDist lo) (min endDist hi))
    nil
  )
)

(defun gtp:subtract-range (ranges cut / out a b c d)
  (setq out '())
  (setq a (car cut))
  (setq b (cadr cut))
  (foreach range ranges
    (setq c (car range))
    (setq d (cadr range))
    (if (or (>= c b) (<= d a))
      (setq out (append out (list range)))
      (progn
        (if (> a c)
          (setq out (append out (list (list c (min a d)))))
        )
        (if (< b d)
          (setq out (append out (list (list (max b c) d))))
        )
      )
    )
  )
  out
)

(defun gtp:plan-pipe-intervals
  (start end components / direction total ranges cut component)
  (setq direction (gtp:component-unit (mapcar '- end start)))
  (setq total (distance start end))
  (setq ranges (list (list 0.0 total)))

  (foreach component components
    (setq cut
      (gtp:component-overlap-range
        start direction 0.0 total component
      )
    )
    (if cut
      (setq ranges (gtp:subtract-range ranges cut))
    )
  )
  ranges
)

(defun gtp:ranges-to-points (start direction ranges / out range p1 p2)
  (setq out '())
  (foreach range ranges
    (setq p1
      (mapcar
        '+
        start
        (mapcar '(lambda (x) (* x (car range))) direction)
      )
    )
    (setq p2
      (mapcar
        '+
        start
        (mapcar '(lambda (x) (* x (cadr range))) direction)
      )
    )
    (setq out (append out (list (list p1 p2))))
  )
  out
)

; -----------------------------------------------------------------------------
; DEBUG / INSPECTION HELPERS
; -----------------------------------------------------------------------------

(defun gtp:component-summary (component / id type dn series len pos)
  (setq id     (gtp:component-get component 'id))
  (setq type   (gtp:component-get component 'type))
  (setq dn     (gtp:component-get component 'dn))
  (setq series (gtp:component-get component 'series))
  (setq len    (gtp:component-get component 'length))
  (setq pos    (gtp:component-get component 'position))
  (strcat
    "ID=" (if id id "<nil>")
    " TYPE=" (if type type "<nil>")
    " DN=" (if dn (itoa dn) "<nil>")
    " SERIES=" (if series (itoa series) "<nil>")
    " LENGTH=" (if len (rtos len 2 3) "<nil>")
    " POS=("
      (if pos (rtos (car pos) 2 3) "<nil>") ","
      (if pos (rtos (cadr pos) 2 3) "<nil>") ","
      (if pos (rtos (caddr pos) 2 3) "<nil>") ")"
  )
)

(defun gtp:components-summary (components / out)
  (setq out "")
  (foreach component components
    (setq out
      (strcat
        out
        (if (> (strlen out) 0) "\n" "")
        (gtp:component-summary component)
      )
    )
  )
  out
)

(princ "\nGTP component architecture foundation loaded. GTPPIPE behaviour unchanged.")
(princ)

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Elbow_Component_Integration.lsp
; ===========================================================================
; GTP_Elbow_Component_Integration.lsp
; -----------------------------------------------------------------------------
; STEP 2 - Wrap the existing GTP elbow engine as a component.
;
; LOAD ORDER
;   1. GTP_DH_TOOLKIT.lsp
;   2. GTP_Component_Architecture.lsp
;   3. GTP_Elbow_Component_Integration.lsp
;
; DESIGN INTENT
;   This file changes the INTERNAL route representation only.
;   Existing elbow geometry is still produced by:
;       gtp:make-elbow-spec
;       gtp:model-elbow
;
;   No new elbow geometry is introduced here.
;   No valve/component geometry is introduced here.
;   The existing GTPPIPE prompts and catalogue behaviour remain unchanged.
;
;   The integration works by redefining gtp:model-corner-route after the
;   original toolkit has loaded. GTPPIPE calls the same function name, so the
;   command does not need to be changed yet.
; -----------------------------------------------------------------------------

(vl-load-com)

; -----------------------------------------------------------------------------
; ELBOW COMPONENT FACTORY
; -----------------------------------------------------------------------------
(defun gtp:make-elbow-component
  (id system dn series prev vertex next carrier casing style / spec)
  (setq spec
    (gtp:make-elbow-spec
      prev vertex next dn carrier casing style
    )
  )
  (if spec
    (gtp:component-make
      id
      "ELBOW"
      system
      dn
      series
      vertex
      (gtp:spec 'd1 spec)
      (gtp:spec 'normal spec)
      nil
      (list
        (cons 'legacy-spec spec)
        (cons 'style style)
        (cons 'carrier carrier)
        (cons 'casing casing)
      )
      nil
    )
  )
)

(defun gtp:elbow-component-spec (component / catalogue)
  (setq catalogue (gtp:component-get component 'catalogue))
  (gtp:catalogue-get catalogue 'legacy-spec)
)

(defun gtp:elbow-component-start (component)
  (gtp:spec 'start (gtp:elbow-component-spec component))
)

(defun gtp:elbow-component-end (component)
  (gtp:spec 'end (gtp:elbow-component-spec component))
)

(defun gtp:model-elbow-component (component carrier casing mode)
  ; Deliberately delegate to the existing elbow modeller so geometry stays
  ; identical to the pre-component implementation.
  (gtp:model-elbow
    (gtp:elbow-component-spec component)
    carrier
    casing
    mode
  )
)

; -----------------------------------------------------------------------------
; COMPONENT-AWARE CORNER ROUTE MODELLER
; -----------------------------------------------------------------------------
; Signature intentionally matches the existing gtp:model-corner-route so the
; existing c:GTPPIPE command can call this function without modification.
;
; `series` is not available in the legacy function signature, so the component
; stores NIL for series for now. Step 3/4 can promote series into the route
; modeller signature once valve/component catalogue selection is introduced.
; -----------------------------------------------------------------------------
(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e
  spoolCount elbowCount clippedCount system)

  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))

  ; Build component records while retaining the exact legacy elbow spec inside
  ; each component. This gives the new architecture the same geometric source
  ; of truth used by the existing modeller.
  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component
        (gtp:make-elbow-component
          (strcat "ELBOW-" (itoa i))
          system
          dn
          nil
          (nth (1- i) pts)
          (nth i pts)
          (nth (1+ i) pts)
          carrier
          casing
          style
        )
      )
    )

    (if
      (and component
           (gtp:spec 'clipped (gtp:elbow-component-spec component)))
      (setq clippedCount (1+ clippedCount))
    )

    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )

  ; Model straight intervals between the geometric footprint ends of adjacent
  ; elbow components. This is intentionally the same interval logic used by
  ; the original modeller.
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts))
    (setq p2 (nth (1+ i) pts))

    (setq s
      (if (nth i elbows)
        (gtp:elbow-component-end (nth i elbows))
        p1
      )
    )

    (setq e
      (if (nth (1+ i) elbows)
        (gtp:elbow-component-start (nth (1+ i) elbows))
        p2
      )
    )

    (if (> (distance s e) 1e-8)
      (setq spoolCount
        (+ spoolCount
           (gtp:model-segment s e carrier casing mode)
        )
      )
    )

    (setq i (1+ i))
  )

  ; Delegate actual elbow solids to the unchanged modeller.
  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows)
      (progn
        (setq component (nth i elbows))
        (gtp:model-elbow-component component carrier casing mode)
        (setq elbowCount (1+ elbowCount))
      )
    )
    (setq i (1+ i))
  )

  (list spoolCount elbowCount clippedCount)
)

(princ
  "\nGTP Step 2 loaded: existing elbows are now wrapped as components; geometry engine unchanged."
)
(princ)

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Valve_Component.lsp
; ===========================================================================
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
  (if (not (gtp:function-defined-p 'gtp:make-valve-component))
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

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Valve_Aware_Pipe_Integration.lsp
; ===========================================================================
; GTP_Valve_Aware_Pipe_Integration.lsp
; -----------------------------------------------------------------------------
; STEP 4 - Make GTPPIPE valve-aware.
;
; LOAD AFTER:
;   1. GTP_DH_TOOLKIT.lsp
;   2. GTP_Component_Architecture.lsp
;   3. GTP_Elbow_Component_Integration.lsp
;   4. GTP_Valve_Component.lsp
;
; PURPOSE
;   Replace the straight-pipe interval stage with a valve-aware planner.
;   Registered longitudinal valve components occupy real route length, so
;   GTPPIPE no longer generates a continuous pipe through the valve footprint.
;
; IMPORTANT
;   This is an integration bridge. It does not rewrite the existing solid
;   generators or valve modeller. Existing elbows continue to use the legacy
;   elbow engine through the Step 2 wrapper.
;
;   GTPVALVE registers components in the current AutoCAD session. Therefore
;   valves must be created before running GTPPIPE for this session.
;
;   Only VALVE components that overlap a straight interval are removed from
;   that interval. Elbow footprint handling remains exactly as Step 2.
; -----------------------------------------------------------------------------

(vl-load-com)

(defun gtp:valve-aware-filter-components (components / out component type)
  (setq out '())
  (foreach component components
    (setq type (gtp:component-get component 'type))
    (if (= type "VALVE")
      (setq out (append out (list component)))
    )
  )
  out
)

(defun gtp:model-valve-component (component / catalogue family)
  (setq catalogue (gtp:component-get component 'catalogue))
  (setq family (gtp:catalogue-get catalogue 'family))
  (cond
    ((= family "SINGLE_SHUTOFF_VALVE")
      (gtp:model-single-shutoff-valve component)
    )
    (T
      (princ
        (strcat
          "\nGTP warning: no modeller registered for valve family "
          (if family family "<nil>") "."
        )
      )
      nil
    )
  )
)

(defun gtp:distance-point-on-line (origin direction dist)
  (gtp:vadd origin (gtp:vscale direction dist))
)

(defun gtp:model-valve-aware-straight
  (start end dn carrier casing mode components / direction total ranges pieces piece a b p1 p2 count)
  (setq direction (gtp:vunit (gtp:vsub end start)))
  (setq total (distance start end))
  (setq count 0)
  (if (<= total 1e-8)
    0
    (progn
      (setq ranges (gtp:plan-pipe-intervals start end components))
      (setq pieces (gtp:ranges-to-points start direction ranges))
      (foreach piece pieces
        (setq p1 (car piece))
        (setq p2 (cadr piece))
        (if (> (distance p1 p2) 1e-8)
          (setq count
            (+ count
               (gtp:model-segment p1 p2 carrier casing mode)
            )
          )
        )
      )
      count
    )
  )
)

(defun gtp:component-overlaps-route-range-p
  (start end component / direction total cut)
  (setq direction (gtp:vunit (gtp:vsub end start)))
  (setq total (distance start end))
  (setq cut
    (gtp:component-overlap-range
      start direction 0.0 total component
    )
  )
  (and cut (> (cadr cut) (car cut)))
)

(defun gtp:validate-valve-clearances
  (pts valveComponents / component pos start end warnings)
  (setq warnings 0)
  (foreach component valveComponents
    (setq pos (gtp:component-get component 'position))
    (setq start (car pts))
    (setq end (gtp:last-item pts))
    ; This first integration only needs a route-level sanity check. Detailed
    ; per-segment assignment is performed during modelling.
    (if (or (< (distance pos start) 1e-8)
            (< (distance pos end) 1e-8))
      (progn
        (princ
          (strcat
            "\nGTP warning: valve "
            (gtp:component-get component 'id)
            " is positioned at a route endpoint; verify the fitting arrangement."
          )
        )
        (setq warnings (1+ warnings))
      )
    )
  )
  warnings
)

; -----------------------------------------------------------------------------
; COMPONENT-AWARE CORNER ROUTE MODELLER
; -----------------------------------------------------------------------------
;
; This keeps the Step 2 elbow component representation, then augments each
; straight route interval with registered VALVE components.
;
(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e
  spoolCount elbowCount clippedCount valveCount valveComponents system)

  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))
  (setq valveComponents
    (gtp:valve-aware-filter-components
      (if *gtp-valve-components* *gtp-valve-components* '())
    )
  )
  (setq valveCount (length valveComponents))

  ; Build the same elbow components established by Step 2.
  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component
        (gtp:make-elbow-component
          (strcat "ELBOW-" (itoa i))
          system
          dn
          nil
          (nth (1- i) pts)
          (nth i pts)
          (nth (1+ i) pts)
          carrier
          casing
          style
        )
      )
    )
    (if
      (and component
           (gtp:spec 'clipped (gtp:elbow-component-spec component)))
      (setq clippedCount (1+ clippedCount))
    )
    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )

  ; Model pipe between elbow footprints, while removing any registered valve
  ; footprint that lies on the same straight route interval.
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts))
    (setq p2 (nth (1+ i) pts))

    (setq s
      (if (nth i elbows)
        (gtp:elbow-component-end (nth i elbows))
        p1
      )
    )
    (setq e
      (if (nth (1+ i) elbows)
        (gtp:elbow-component-start (nth (1+ i) elbows))
        p2
      )
    )

    (if (> (distance s e) 1e-8)
      (setq spoolCount
        (+ spoolCount
           (gtp:model-valve-aware-straight
             s e dn carrier casing mode valveComponents
           )
        )
      )
    )
    (setq i (1+ i))
  )

  ; Existing elbow geometry remains untouched.
  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows)
      (progn
        (setq component (nth i elbows))
        (gtp:model-elbow-component component carrier casing mode)
        (setq elbowCount (1+ elbowCount))
      )
    )
    (setq i (1+ i))
  )

  ; Valve geometry is already present if GTPVALVE was run before GTPPIPE.
  ; Do not regenerate it here; just report how many components participated
  ; in pipe splitting. This prevents duplicate valve solids.
  (if (> valveCount 0)
    (princ
      (strcat
        "\nValve-aware routing: "
        (itoa valveCount)
        " registered valve component(s) considered for pipe splitting."
      )
    )
  )

  (list spoolCount elbowCount clippedCount)
)

(princ "\nGTP Step 4 loaded: GTPPIPE is now valve-aware for registered longitudinal valves.")
(princ)

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Valve_Catalogue_Integration.lsp
; ===========================================================================
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

  (if (not (and (gtp:function-defined-p 'gtp:make-valve-component)
                (gtp:function-defined-p 'gtp:curve-point-direction)))
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

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Component_Persistence_and_Fittings.lsp
; ===========================================================================
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
                              "TEE" flow dn series (car info) (cadr info) up
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
                      "REDUCER" flow dn series (car info) (cadr info) '(0.0 0.0 1.0)
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
                          "BRANCH" flow dn series (car info) (cadr info) '(0.0 0.0 1.0)
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
                  (if (null casing) (setq casing (gtp:casing-od row series)))
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
                      "END_CAP" flow dn series endpoint dir '(0.0 0.0 1.0)
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

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Combined_Final_Bridge.lsp
; ===========================================================================
; GTP_COMBINED_FINAL_BRIDGE.LSP
; =============================================================================
; Final route/component integration layer for GTP_DH_TOOLKIT_COMBINED.lsp.
;
; This block is appended AFTER the legacy geometry engine and Steps 1-6.
; It deliberately does not regenerate placed component solids. Instead it:
;   - keeps the proven elbow modeller as the bend source of truth;
;   - reads the persistent component registry;
;   - removes longitudinal component footprints from straight pipe intervals;
;   - models only the remaining straight pipe pieces;
;   - provides combined diagnostics/help commands.
; =============================================================================

(vl-load-com)

(setq *gtp-combined-version* "1.0")
(setq *gtp-combined-longitudinal-types*
  '("VALVE" "TEE" "REDUCER" "BRANCH" "END_CAP")
)

(defun gtp:combined-catalogue (component)
  (if component (gtp:component-get component 'catalogue) nil)
)

(defun gtp:combined-options (component)
  (if component (gtp:component-get component 'options) nil)
)

(defun gtp:combined-catalogue-get (component key / cat)
  (setq cat (gtp:combined-catalogue component))
  (if cat (gtp:catalogue-get cat key) nil)
)

(defun gtp:combined-component-length-du (component / type len mmLen opt footprint)
  ; Prefer explicit catalogue millimetres because Step 5/6 component records
  ; store several lengths in catalogue-mm while the geometry engine works in
  ; drawing units. This also keeps old persisted records usable after reload.
  (setq type (gtp:component-get component 'type))
  (setq mmLen (gtp:combined-catalogue-get component 'length-mm))

  (cond
    ((and mmLen (> mmLen 0.0))
      (gtp:mm mmLen)
    )

    ; Step 3 manual valve components store a converted component length, and
    ; also preserve length-mm in their catalogue. The branch above therefore
    ; normally wins. Keep this fallback for older valve records.
    ((= type "VALVE")
      (setq len (gtp:component-get component 'length))
      (if (and len (> len 0.0)) len 0.0)
    )

    ; Step 6 fitting commands store their component length in catalogue mm.
    ((member type '("TEE" "REDUCER" "BRANCH" "END_CAP"))
      (setq len (gtp:component-get component 'length))
      (if (and len (> len 0.0)) (gtp:mm len) 0.0)
    )

    (T
      (setq opt (gtp:combined-options component))
      (setq footprint (if opt (gtp:component-get opt 'footprint) nil))
      (cond
        ((and footprint (> footprint 0.0)) (* 2.0 footprint))
        (T
          (setq len (gtp:component-get component 'length))
          (if (and len (> len 0.0)) len 0.0)
        )
      )
    )
  )
)

(defun gtp:combined-segment-projection (start direction point)
  (gtp:dot (gtp:vsub point start) direction)
)

(defun gtp:combined-point-line-distance (start direction point / tproj foot)
  (setq tproj (gtp:combined-segment-projection start direction point))
  (setq foot (gtp:vadd start (gtp:vscale direction tproj)))
  (distance point foot)
)

(defun gtp:combined-component-range
  (start end component / type pos cdir direction total proj lateral align len lo hi)

  (setq type (gtp:component-get component 'type))
  (setq pos (gtp:component-get component 'position))

  (if (or (null pos)
          (not (member type *gtp-combined-longitudinal-types*)))
    nil
    (progn
      (setq total (distance start end))
      (if (<= total 1e-8)
        nil
        (progn
          (setq direction (gtp:vunit (gtp:vsub end start)))
          (setq proj (gtp:combined-segment-projection start direction pos))
          (setq lateral (gtp:combined-point-line-distance start direction pos))
          (setq cdir (gtp:component-get component 'direction))
          (setq align
            (if cdir
              (abs (gtp:dot direction (gtp:vunit cdir)))
              1.0
            )
          )
          (setq len (gtp:combined-component-length-du component))

          ; Only components genuinely on this straight interval participate.
          ; A 5 mm project-space tolerance matches the placement workflow.
          (if (or (> lateral (gtp:mm 5.0))
                  (< align 0.95)
                  (<= len 1e-8)
                  (< proj (- len))
                  (> proj (+ total len)))
            nil
            (progn
              (if (= type "END_CAP")
                ; End caps are endpoint-based, not centre-based. Reserve the
                ; material immediately behind the selected endpoint.
                (if (<= proj (/ total 2.0))
                  (setq lo proj hi (+ proj len))
                  (setq lo (- proj len) hi proj)
                )
                (setq lo (- proj (/ len 2.0)) hi (+ proj (/ len 2.0)))
              )
              (setq lo (max 0.0 lo))
              (setq hi (min total hi))
              (if (> hi lo) (list lo hi component) nil)
            )
          )
        )
      )
    )
  )
)

(defun gtp:combined-subtract-range (ranges cut / out a b r c d)
  (setq out '() a (car cut) b (cadr cut))
  (foreach r ranges
    (setq c (car r) d (cadr r))
    (if (or (>= c b) (<= d a))
      (setq out (append out (list r)))
      (progn
        (if (> a c) (setq out (append out (list (list c (min a d))))))
        (if (< b d) (setq out (append out (list (list (max b c) d)))))
      )
    )
  )
  out
)

(defun gtp:combined-segment-components (start end / out component cut)
  (setq out '())
  (if *gtp-component-registry*
    (foreach component *gtp-component-registry*
      (setq cut (gtp:combined-component-range start end component))
      (if cut (setq out (append out (list cut))))
    )
  )
  (vl-sort out '(lambda (a b) (< (car a) (car b))))
)

(defun gtp:combined-plan-straight-ranges (start end / total ranges cuts cut)
  (setq total (distance start end))
  (setq ranges (if (> total 1e-8) (list (list 0.0 total)) '()))
  (setq cuts (gtp:combined-segment-components start end))
  (foreach cut cuts
    (setq ranges (gtp:combined-subtract-range ranges cut))
  )
  (list ranges cuts)
)

(defun gtp:combined-distance-point (start direction dist)
  (gtp:vadd start (gtp:vscale direction dist))
)

(defun gtp:model-combined-straight
  (start end dn carrier casing mode / direction plan ranges cuts range p1 p2 count)

  (setq count 0)
  (if (> (distance start end) 1e-8)
    (progn
      (setq direction (gtp:vunit (gtp:vsub end start)))
      (setq plan (gtp:combined-plan-straight-ranges start end))
      (setq ranges (car plan) cuts (cadr plan))

      (foreach range ranges
        (setq p1 (gtp:combined-distance-point start direction (car range)))
        (setq p2 (gtp:combined-distance-point start direction (cadr range)))
        (if (> (distance p1 p2) 1e-8)
          (setq count (+ count (gtp:model-segment p1 p2 carrier casing mode)))
        )
      )

      (if (> (length cuts) 0)
        (princ
          (strcat
            "\nComponent-aware split: "
            (itoa (length cuts))
            " installed component footprint(s) excluded from this straight run."
          )
        )
      )
    )
  )
  count
)

(defun gtp:model-corner-route
  (pts dn carrier casing mode style / n elbows i component p1 p2 s e
   spoolCount elbowCount clippedCount system)

  ; Final combined route modeller. Elbow geometry stays delegated to the
  ; proven Step 2 wrapper; straight intervals use the persistent registry.
  (setq n (length pts))
  (setq elbows '() i 0 spoolCount 0 elbowCount 0 clippedCount 0)
  (setq system (if *gtp-flow-type* *gtp-flow-type* "Flow"))

  (while (< i n)
    (setq component nil)
    (if (and (> i 0) (< i (1- n)))
      (setq component
        (gtp:make-elbow-component
          (strcat "ELBOW-" (itoa i))
          system dn nil
          (nth (1- i) pts)
          (nth i pts)
          (nth (1+ i) pts)
          carrier casing style
        )
      )
    )
    (if (and component
             (gtp:spec 'clipped (gtp:elbow-component-spec component)))
      (setq clippedCount (1+ clippedCount))
    )
    (setq elbows (append elbows (list component)))
    (setq i (1+ i))
  )

  ; Model straight intervals between elbow footprint ends, excluding every
  ; supported persistent component footprint on the same straight route.
  (setq i 0)
  (while (< i (1- n))
    (setq p1 (nth i pts) p2 (nth (1+ i) pts))
    (setq s
      (if (nth i elbows)
        (gtp:elbow-component-end (nth i elbows))
        p1
      )
    )
    (setq e
      (if (nth (1+ i) elbows)
        (gtp:elbow-component-start (nth (1+ i) elbows))
        p2
      )
    )
    (if (> (distance s e) 1e-8)
      (setq spoolCount
        (+ spoolCount
           (gtp:model-combined-straight s e dn carrier casing mode)
        )
      )
    )
    (setq i (1+ i))
  )

  ; Keep the existing elbow solid modeller unchanged.
  (setq i 1)
  (while (< i (1- n))
    (if (nth i elbows)
      (progn
        (setq component (nth i elbows))
        (gtp:model-elbow-component component carrier casing mode)
        (setq elbowCount (1+ elbowCount))
      )
    )
    (setq i (1+ i))
  )

  (list spoolCount elbowCount clippedCount)
)

(defun gtp:combined-command-checks ()
  (list
    (list "GTPPIPE" 'c:GTPPIPE)
    (list "GTPMITER" 'c:GTPMITER)
    (list "GTPMITTER" 'c:GTPMITTER)
    (list "GTPUNITS" 'c:GTPUNITS)
    (list "GTPLAYER" 'c:GTPLAYER)
    (list "GTPVALVE" 'c:GTPVALVE)
    (list "GTPVALVECATALOG" 'c:GTPVALVECATALOG)
    (list "GTPVALVESUMMARY" 'c:GTPVALVESUMMARY)
    (list "GTPTEE" 'c:GTPTEE)
    (list "GTPREDUCER" 'c:GTPREDUCER)
    (list "GTPBRANCH" 'c:GTPBRANCH)
    (list "GTPENDCAP" 'c:GTPENDCAP)
    (list "GTPCOMPONENTS" 'c:GTPCOMPONENTS)
    (list "GTPCOMPONENTRELOAD" 'c:GTPCOMPONENTRELOAD)
    (list "GTPCOMPONENTSAVE" 'c:GTPCOMPONENTSAVE)
  )
)

(defun c:GTPCOMBINEDTEST (/ checks ok item)
  (setq checks (gtp:combined-command-checks) ok T)
  (princ "\n========================================")
  (princ "\n GTP COMBINED TOOLKIT TEST")
  (princ "\n========================================")
  (foreach item checks
    (if (gtp:function-defined-p (cadr item))
      (princ (strcat "\n[OK] " (car item)))
      (progn
        (setq ok nil)
        (princ (strcat "\n[FAIL] " (car item)))
      )
    )
  )
  (if (gtp:function-defined-p 'gtp:model-corner-route)
    (princ "\n[OK] Final multi-component route modeller active.")
    (progn (setq ok nil) (princ "\n[FAIL] Final route modeller missing."))
  )
  (princ
    (strcat
      "\nPersistent components in memory: "
      (itoa (if *gtp-component-registry* (length *gtp-component-registry*) 0))
    )
  )
  (if ok
    (princ "\nGTPCOMBINEDTEST PASS.")
    (princ "\nGTPCOMBINEDTEST FAIL - see [FAIL] entries above.")
  )
  (princ)
)

(defun c:GTPHELP ()
  (princ "\nGTP combined AutoCAD 3D district-heating toolkit:")
  (princ "\n  GTPPIPE             Generate carrier/casing pipe + 3D elbows from route")
  (princ "\n  GTPMITER            Join two route ends at their 3D axis intersection")
  (princ "\n  GTPMITTER           Alias for GTPMITER")
  (princ "\n  GTPUNITS            Set catalogue-mm to drawing-unit conversion")
  (princ "\n  GTPLAYER            Create/check GTP layers")
  (princ "\n  GTPVALVE            Place catalogue-backed valve component")
  (princ "\n  GTPVALVECATALOG     Inspect supported valve catalogue")
  (princ "\n  GTPVALVESUMMARY     List registered valves")
  (princ "\n  GTPTEE              Place tee component")
  (princ "\n  GTPREDUCER          Place catalogue-backed reducer component")
  (princ "\n  GTPBRANCH           Place branch component")
  (princ "\n  GTPENDCAP           Place end-cap component")
  (princ "\n  GTPCOMPONENTS       List persistent components")
  (princ "\n  GTPCOMPONENTRELOAD  Reload components from DWG Named Object Dictionary")
  (princ "\n  GTPCOMPONENTSAVE    Persist current component registry to DWG")
  (princ "\n  GTPCOMBINEDTEST     Verify combined command/function availability")
  (princ)
)

(princ
  (strcat
    "\nGTP_DH_TOOLKIT_COMBINED V" *gtp-combined-version*
    " loaded. Run GTPHELP for commands or GTPCOMBINEDTEST for diagnostics."
  )
)
(princ)

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Smart_Pipe_Command.lsp
; ===========================================================================
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
    ((and component (gtp:function-defined-p 'gtp:register-persistent-component))
      (gtp:register-persistent-component component)
    )
    ((and component (gtp:function-defined-p 'gtp:component-registry-add))
      (gtp:component-registry-add component)
    )
    (T component)
  )
)

(defun gtp:smart-component-id (prefix)
  (if (gtp:function-defined-p 'gtp:component-next-id)
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
        (if (gtp:function-defined-p 'c:GTPCOMPONENTS)
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
                  (if (gtp:function-defined-p 'gtp:persist-all-components)
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
    (if (not (gtp:function-defined-p fn))
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

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Variable_DN_Route.lsp
; ===========================================================================
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
        (if (gtp:function-defined-p 'c:GTPCOMPONENTS) (c:GTPCOMPONENTS))
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
                      (if (gtp:function-defined-p 'gtp:persist-all-components)
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
    (if (not (gtp:function-defined-p fn))
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

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Variable_DN_Fixes.lsp
; ===========================================================================
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

; ===========================================================================
; BEGIN COMBINED SOURCE: GTP_Catalogue_Corrections.lsp
; ===========================================================================
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
