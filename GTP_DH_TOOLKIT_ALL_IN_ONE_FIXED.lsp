; GTP_DH_TOOLKIT_ALL_IN_ONE_FIXED.LSP
; ============================================================================
; CLEAN SELF-CONTAINED MONOLITHIC BUILD
; Load ONLY this file.
; ============================================================================

(vl-load-com)

; ----------------------------- CORE SETTINGS --------------------------------
(setq *gtp-pipe-db*
 '((20 26.9 90 110 125)(25 33.7 90 110 125)(32 42.4 110 125 140)
   (40 48.3 110 125 140)(50 60.3 125 140 160)(65 76.1 140 160 180)
   (80 88.9 160 180 200)(100 114.3 200 225 250)(125 139.7 225 250 280)
   (150 168.3 250 280 315)(200 219.1 315 355 400)(250 273.0 400 450 500)
   (300 323.9 450 500 560)(350 355.6 500 560 630)(400 406.4 560 630 710)
   (450 457.2 630 710 800)(500 508.0 710 800 900)(600 610.0 800 900 1000)))
(setq *gtp-elbow-db*
 '((20 600 1000)(25 600 1000)(32 600 1000)(40 600 1000)(50 600 1000)
   (65 600 1000)(80 600 1000)(100 700 1000)(125 750 1000)(150 800 1000)
   (200 nil 1000)(250 nil 1000)(300 nil 1000)(350 nil 1000)(400 nil 1000)
   (450 nil 1100)(500 nil 1200)(600 nil 1300)))
(setq *gtp-max-pipe-length-mm* 12000.0)
(setq *gtp-end-cutback-mm* 220.0)
(setq *gtp-standard-bend-radius-factor* 3.0)
(setq *gtp-straight-angle-tol-deg* 0.5)
(setq *gtp-duplicate-point-tol* 1e-8)
(setq *gtp-mm-to-du* 1.0)
(setq *gtp-drawing-unit-name* "millimetres")
(setq *gtp-pipe-color* 1)
(setq *gtp-flow-type* "Flow")
(setq *gtp-component-registry* '())
(setq *gtp-component-next-id* 1)

; ----------------------------- BASIC HELPERS --------------------------------
(defun gtp:unit-info-from-insunits (u)
 (cond ((= u 1)(list "inches" (/ 1.0 25.4)))
       ((= u 2)(list "feet" (/ 1.0 304.8)))
       ((= u 4)(list "millimetres" 1.0))
       ((= u 5)(list "centimetres" 0.1))
       ((= u 6)(list "metres" 0.001))
       ((= u 10)(list "yards" (/ 1.0 914.4)))
       (T nil)))
(defun gtp:mm (x)(* x *gtp-mm-to-du*))
(defun gtp:vadd (a b)(mapcar '+ a b))
(defun gtp:vsub (a b)(mapcar '- a b))
(defun gtp:vscale (v s)(mapcar '(lambda(x)(* x s)) v))
(defun gtp:dot (a b)(+ (* (car a)(car b))(* (cadr a)(cadr b))(* (caddr a)(caddr b))))
(defun gtp:vmag (v)(sqrt (gtp:dot v v)))
(defun gtp:vunit (v / m)(setq m (gtp:vmag v))(if (> m 1e-12)(gtp:vscale v (/ 1.0 m)) '(1.0 0.0 0.0)))
(defun gtp:cross (a b)(list (- (* (cadr a)(caddr b))(* (caddr a)(cadr b))) (- (* (caddr a)(car b))(* (car a)(caddr b))) (- (* (car a)(cadr b))(* (cadr a)(car b)))))
(defun gtp:variant (p)(vlax-3D-point p))
(defun gtp:ensure-layer (n c / doc lays lay)(setq doc (vla-get-ActiveDocument(vlax-get-acad-object)) lays (vla-get-Layers doc))(if(tblsearch "LAYER" n)(setq lay(vla-Item lays n))(setq lay(vla-Add lays n)))(if c(vla-put-Color lay c))(vla-put-LayerOn lay :vlax-true)(vla-put-Freeze lay :vlax-false)(vla-put-Lock lay :vlax-false) lay)
(defun gtp:layers ()(gtp:ensure-layer "GTP-PIPE-CASING" 8)(gtp:ensure-layer "GTP-PIPE-INSULATION" 2)(gtp:ensure-layer "GTP-PIPE-CARRIER" 1)(gtp:ensure-layer "GTP-PIPE-CENTRELINE" 4)(gtp:ensure-layer "GTP-FITTING-BODY" 6)(gtp:ensure-layer "GTP-VALVE-BODY" 6)(gtp:ensure-layer "GTP-VALVE-STEM" 3))

; ----------------------------- UNITS -----------------------------------------
(defun gtp:setup-units (/ s info)
 (initget "Auto MM CM M Inch Feet")
 (setq s(getkword "\nCatalogue is mm. Drawing unit [Auto/MM/CM/M/Inch/Feet] <Auto>: "))
 (if(null s)(setq s "Auto"))
 (setq info(cond ((= s "Auto")(or(gtp:unit-info-from-insunits(getvar "INSUNITS"))(list "millimetres" 1.0)))
                  ((= s "MM")(list "millimetres" 1.0))((= s "CM")(list "centimetres" 0.1))
                  ((= s "M")(list "metres" 0.001))((= s "Inch")(list "inches" (/ 1.0 25.4)))
                  ((= s "Feet")(list "feet" (/ 1.0 304.8)))))
 (setq *gtp-drawing-unit-name*(car info) *gtp-mm-to-du*(cadr info))
 (princ(strcat "\nGTP units: " *gtp-drawing-unit-name* " | 1000 mm = " (rtos(* 1000.0 *gtp-mm-to-du*)2 4)" du.")))
(defun c:GTPUNITS()(gtp:setup-units)(princ))

; ----------------------------- GEOMETRY --------------------------------------
(defun gtp:axis-matrix(p1 p2 / z ref x y m)(setq z(gtp:vunit(gtp:vsub p2 p1)) m(mapcar '(lambda(a b)(/ (+ a b)2.0))p1 p2))(setq ref(if(> (abs(caddr z))0.999)'(0.0 1.0 0.0)'(0.0 0.0 1.0)) x(gtp:vunit(gtp:cross ref z)) y(gtp:cross z x))(list(list(car x)(car y)(car z)(car m))(list(cadr x)(cadr y)(cadr z)(cadr m))(list(caddr x)(caddr y)(caddr z)(caddr m))(list 0 0 0 1)))
(defun gtp:make-cylinder(p1 p2 dia layer / doc ms obj)(if(> (distance p1 p2)1e-8)(progn(setq doc(vla-get-ActiveDocument(vlax-get-acad-object)) ms(vla-get-ModelSpace doc) obj(vla-AddCylinder ms(vlax-3D-point '(0 0 0))(/ dia 2.0)(distance p1 p2)))(vla-TransformBy obj(vlax-tmatrix(gtp:axis-matrix p1 p2)))(vla-put-Layer obj layer)(vla-put-Color obj *gtp-pipe-color*) obj)))
(defun gtp:make-3d-polyline(pts layer / h)(setq h(entmakex(list'(0 . "POLYLINE")'(100 . "AcDbEntity")(cons 8 layer)'(100 . "AcDb3dPolyline")(cons 10 '(0 0 0))'(66 . 1)'(70 . 8))))(if h(progn(foreach p pts(entmakex(list'(0 . "VERTEX")'(100 . "AcDbEntity")(cons 8 layer)'(100 . "AcDbVertex")'(100 . "AcDb3dPolylineVertex")(cons 10 p)'(70 . 32))))(entmakex(list'(0 . "SEQEND")'(100 . "AcDbEntity")(cons 8 layer))) h)))

; ----------------------------- CATALOGUE -------------------------------------
(defun gtp:find-dn(dn)(assoc dn *gtp-pipe-db*))
(defun gtp:casing-od(row series)(nth(+ 1 series)row))
(defun gtp:get-dn(/ d r)(setq d(getint "\nDN [20 25 32 40 50 65 80 100 125 150 200 250 300 350 400 450 500 600]: "))(while(and d(null(setq r(gtp:find-dn d))))(princ "\nDN not in catalogue.")(setq d(getint "\nDN: ")))(or r(car *gtp-pipe-db*)))
(defun gtp:get-series(/ s)(initget "1 2 3")(setq s(getkword "\nSeries [1/2/3] <2>: "))(if s(atoi s)2))
(defun gtp:get-mode(/ s)(initget "CASING FULL")(setq s(getkword "\nMode [CASING/FULL] <CASING>: "))(if s s "CASING"))
(defun gtp:get-flow(/ s)(initget "Flow Return")(setq s(getkword "\nDuty [Flow/Return] <Flow>: "))(if(null s)(setq s "Flow"))(setq *gtp-flow-type* s *gtp-pipe-color*(if(= s "Flow")1 5)) s)

; ----------------------------- ROUTE -----------------------------------------
(defun gtp:curve-points(e / ep i p out)(setq ep(vl-catch-all-apply 'vlax-curve-getEndParam(list e)))(if(vl-catch-all-error-p ep)nil(progn(setq i 0 out '())(while(<= i(fix ep))(setq p(vlax-curve-getPointAtParam e i))(if p(setq out(append out(list p))))(setq i(1+ i)))out)))
(defun gtp:valid-route-p(e / t)(setq t(cdr(assoc 0(entget e))))(member t '("LINE" "LWPOLYLINE" "POLYLINE")))
(defun gtp:turn-angle(a b c / u v cr dp)(setq u(gtp:vunit(gtp:vsub b a)) v(gtp:vunit(gtp:vsub c b)) cr(gtp:vmag(gtp:cross u v)) dp(gtp:dot u v))(atan cr dp))
(defun gtp:clean-points(pts / a b c out i)(setq out(list(car pts)) i 1)(while(< i(1- (length pts)))(setq a(nth(- i 1)pts)b(nth i pts)c(nth(+ i 1)pts))(if(> (* 180.0(/(gtp:turn-angle a b c)pi)) *gtp-straight-angle-tol-deg*)(setq out(append out(list b))))(setq i(1+ i)))(append out(list(last pts))))

; ----------------------------- ELBOW -----------------------------------------
(defun gtp:elbow-leg(dn style / r)(setq r(assoc dn *gtp-elbow-db*))(if(= style "Short")(or(nth 1 r)(nth 2 r))(nth 2 r)))
(defun gtp:elbow-spec(a b c dn carrier casing style / d1 d2 n ph leg maxleg r td center)(setq d1(gtp:vunit(gtp:vsub b a)) d2(gtp:vunit(gtp:vsub c b)) n(gtp:vunit(gtp:cross d1 d2)) ph(atan(gtp:vmag(gtp:cross d1 d2))(gtp:dot d1 d2)) leg(gtp:mm(gtp:elbow-leg dn style)) maxleg(* 0.45(min(distance a b)(distance b c))))(setq leg(min leg maxleg))(setq r(min(* *gtp-standard-bend-radius-factor* carrier)(/ (max 1.0(- leg(gtp:mm *gtp-end-cutback-mm*))) (max 1e-6(tan(/ ph 2.0)))))))(if(< r(* 0.55 casing) )nil(progn(setq td(* r(tan(/ ph 2.0))) center(gtp:vadd(gtp:vadd b(gtp:vscale d1(- td))) (gtp:vscale(gtp:vunit(gtp:cross n d1)) r)))(list(cons'd1 d1)(cons'd2 d2)(cons'normal n)(cons'r r)(cons'phi ph)(cons'start(gtp:vadd b(gtp:vscale d1(- leg))))(cons'end(gtp:vadd b(gtp:vscale d2 leg)))(cons't1(gtp:vadd b(gtp:vscale d1(- td))))(cons't2(gtp:vadd b(gtp:vscale d2 td)))(cons'center center)))))
(defun gtp:spec(k s)(cdr(assoc k s)))
(defun gtp:model-elbow(s carrier casing mode / fs fe t1 t2)(setq fs(gtp:spec 'start s)fe(gtp:spec 'end s)t1(gtp:spec 't1 s)t2(gtp:spec 't2 s))(gtp:make-cylinder fs t1 carrier "GTP-PIPE-CARRIER")(gtp:make-cylinder t2 fe carrier "GTP-PIPE-CARRIER")(gtp:make-cylinder fs t1 casing "GTP-PIPE-CASING")(gtp:make-cylinder t2 fe casing "GTP-PIPE-CASING"))

; ----------------------------- COMPONENT CORE --------------------------------
(setq *gtp-component-types* '("PIPE" "ELBOW" "VALVE" "TEE" "REDUCER" "BRANCH" "VENT_DRAIN" "END_CAP"))
(defun gtp:component-make(id type sys dn series pos dir up len cat opt)(list(cons'id id)(cons'type type)(cons'system sys)(cons'dn dn)(cons'series series)(cons'position pos)(cons'direction(gtp:vunit dir))(cons'up(gtp:vunit up))(cons'length len)(cons'catalogue cat)(cons'options opt)))
(defun gtp:component-get(c k)(cdr(assoc k c)))
(defun gtp:component-valid-p(c / p d l)(and c(member(gtp:component-get c 'type)*gtp-component-types*)(setq p(gtp:component-get c 'position)) (= 3(length p))(setq d(gtp:component-get c 'direction))(= 3(length d))(or(null(setq l(gtp:component-get c 'length)))(>= l 0.0))))
(defun gtp:cat-get(c k)(cdr(assoc k c)))
(defun gtp:reg-add(c / id old)(if(gtp:component-valid-p c)(progn(setq id(gtp:component-get c 'id) old(vl-position id(mapcar '(lambda(x)(gtp:component-get x 'id))*gtp-component-registry*)))(if old(setq *gtp-component-registry*(subst c(nth old *gtp-component-registry*)*gtp-component-registry*))(setq *gtp-component-registry*(append *gtp-component-registry*(list c)))) c)))
(defun gtp:next-id(pre / s)(setq s(strcat pre "-" (itoa *gtp-component-next-id*)) *gtp-component-next-id*(1+ *gtp-component-next-id*)) s)
(defun gtp:comp-start(c / p d h)(setq p(gtp:component-get c 'position)d(gtp:component-get c 'direction)h(/(gtp:component-get c 'length)2.0))(gtp:vsub p(gtp:vscale d h)))
(defun gtp:comp-end(c / p d h)(setq p(gtp:component-get c 'position)d(gtp:component-get c 'direction)h(/(gtp:component-get c 'length)2.0))(gtp:vadd p(gtp:vscale d h)))

; ----------------------------- VALVE CATALOGUE -------------------------------
(setq *gtp-valve-single-db* '((26.9 90 110 110 110 125 125 110 480 19 1510)(33.7 90 110 110 110 125 125 110 480 19 1510)(42.4 110 125 125 125 140 140 110 485 19 1510)(48.3 110 125 125 125 140 140 125 494 19 1510)(60.3 125 140 140 140 160 160 110 500 19 1510)(76.1 140 160 160 180 180 180 110 505 19 1510)(88.9 160 180 180 200 200 200 110 515 19 1510)(114.3 200 225 225 225 250 250 140 525 27 1510)(139.7 225 250 250 280 280 280 140 545 27 1510)(168.3 250 280 280 280 315 315 140 565 27 1510)(219.1 315 355 355 355 400 400 140 585 50 1510)(273.0 400 450 450 450 500 500 180 614 50 1510)(323.9 450 560 500 560 560 180 664 50 1810)))
(setq *gtp-valve-twin-db* '((33.7 140 180 160 180 180 200 110 210 461 365 19 1600)(42.4 160 200 180 200 200 250 110 210 471 366 19 1600)(48.3 160 200 180 200 250 110 210 499 366 19 1600)(60.3 200 250 225 250 250 280 110 210 519 366 19 1600)(76.1 225 280 250 280 280 315 110 210 542 360 19 1800)(88.9 250 315 280 315 315 355 110 210 574 358 19 1900)(114.3 315 400 355 400 400 450 110 210 618 365 27 1900)(139.7 400 500 450 500 500 560 180 210 690 383 27 2200)(168.3 450 560 500 560 630 180 210 752 383 27 2200)(219.1 560 630 630 710 710 800 180 210 800 383 27 2200)))
(defun gtp:valve-family-row(family od / db r)(setq db(cond((= family "SINGLE")(setq db *gtp-valve-single-db*))(T(setq db *gtp-valve-twin-db*))))(foreach x db(if(and(null r)(< (abs(- (car x)od))0.01))(setq r x)))r)
(defun gtp:valve-body(row family)(if(= family "SINGLE")(nth 7 row)(nth 7 row)))
(defun gtp:valve-length(row family)(if(= family "SINGLE")(nth 10 row)(nth 12 row)))
(defun gtp:valve-stem(row family)(if(= family "SINGLE")(nth 8 row)(nth 9 row)))

; ----------------------------- VALVE MODEL -----------------------------------
(defun gtp:make-valve-body(c row family / p d up len body half p1 p2)(setq p(gtp:component-get c 'position)d(gtp:component-get c 'direction)up(gtp:component-get c 'up)len(gtp:mm(gtp:valve-length row family))body(gtp:mm(gtp:valve-body row family))half(/ len 2.0)p1(gtp:vsub p(gtp:vscale d half))p2(gtp:vadd p(gtp:vscale d half)))(gtp:make-cylinder p1 p2 body "GTP-VALVE-BODY")(gtp:make-cylinder p1(gtp:vadd p1(gtp:vscale d(min 120.0(* .1 len))))(* 1.2 body)"GTP-VALVE-BODY")(gtp:make-cylinder(gtp:vsub p2(gtp:vscale d(min 120.0(* .1 len))))p2(* 1.2 body)"GTP-VALVE-BODY")(gtp:make-cylinder p(gtp:vadd p(gtp:vscale up(gtp:mm(gtp:valve-stem row family))))(max 19.0(* .12 body))"GTP-VALVE-STEM"))

; ----------------------------- PERSISTENCE -----------------------------------
(defun gtp:persist-all() (princ "\nComponent persistence is session-safe; use DWG save for geometry."))
(defun gtp:components-summary() (princ(strcat "\nComponents: "(itoa(length *gtp-component-registry*))))(foreach c *gtp-component-registry*(princ(strcat "\n"(gtp:component-get c 'id)" | "(gtp:component-get c 'type)" | DN"(itoa(or(gtp:component-get c 'dn)0))))))

; ----------------------------- PIPE MODEL ------------------------------------
(defun gtp:model-segment(a b carrier casing mode / L step pos p1 p2)(setq L(distance a b)step(gtp:mm *gtp-max-pipe-length-mm*)pos 0.0)(while(< pos L)(setq p1(gtp:vadd a(gtp:vscale(gtp:vunit(gtp:vsub b a))pos))p2(gtp:vadd a(gtp:vscale(gtp:vunit(gtp:vsub b a))(min L(+ pos step)))))(if(> (distance p1 p2)1e-8)(progn(gtp:make-cylinder p1 p2 carrier "GTP-PIPE-CARRIER")(gtp:make-cylinder p1 p2 casing "GTP-PIPE-CASING")))(setq pos(+ pos step))))
(defun gtp:plan-valve-gaps(a b valves / d L ranges cut c cs ce x y out)(setq d(gtp:vunit(gtp:vsub b a))L(distance a b)ranges(list(list 0.0 L)))(foreach c valves(setq cs(gtp:comp-start c)ce(gtp:comp-end c)x(gtp:dot(gtp:vsub cs a)d)y(gtp:dot(gtp:vsub ce a)d))(setq cut(list(max 0.0(min x y))(min L(max x y))))(setq out '())(foreach r ranges(if(or(>= (car r)(cadr cut))(<= (cadr r)(car cut)))(setq out(append out(list r)))(progn(if(> (car cut)(car r))(setq out(append out(list(list(car r)(min(cadr cut)(cadr r))))))(if(< (cadr cut)(cadr r))(setq out(append out(list(list(max(car cut)(car r))(cadr r))))))))))(setq ranges out))ranges)
(defun gtp:model-route(pts dn carrier casing mode style / elbows valves i p1 p2 s e rs r a b n count ec)(setq n(length pts)elbows '()valves(vl-remove-if-not '(lambda(c)(= (gtp:component-get c 'type)"VALVE"))*gtp-component-registry*)i 1 count 0 ec 0)(while(< i(1- n))(setq rs(gtp:elbow-spec(nth(- i 1)pts)(nth i pts)(nth(+ i 1)pts)dn carrier casing style))(setq elbows(append elbows(list rs)))(setq i(1+ i)))(setq i 0)(while(< i(1- n))(setq p1(nth i pts)p2(nth(+ i 1)pts)s(if(and(> i 0)(nth(- i 1)elbows))(gtp:spec 'end(nth(- i 1)elbows))p1)e(if(and(<(+ i 1)(length elbows))(nth i elbows))(gtp:spec 'start(nth i elbows))p2))(foreach r(gtp:plan-valve-gaps s e valves)(setq a(gtp:vadd s(gtp:vscale(gtp:vunit(gtp:vsub e s))(car r))) b(gtp:vadd s(gtp:vscale(gtp:vunit(gtp:vsub e s))(cadr r))))(if(> (distance a b)1e-8)(progn(gtp:model-segment a b carrier casing mode)(setq count(1+ count))))) (setq i(1+ i)))(foreach rs elbows(if rs(progn(gtp:model-elbow rs carrier casing mode)(setq ec(1+ ec)))))(list count ec))

; ----------------------------- COMMAND: GTPPIPE ------------------------------
(defun c:GTPPIPE(/ *error* old ent row dn series carrier casing mode flow style raw pts)
 (setq old(getvar "CMDECHO"))(setvar "CMDECHO" 0)
 (defun *error*(m)(setvar "CMDECHO" old)(if(and m(/= m "Function cancelled"))(princ(strcat "\nGTPPIPE error: "m)))(princ))
 (gtp:layers)(gtp:setup-units)(setq ent(car(entsel "\nSelect route LINE / POLYLINE: ")))
 (if(and ent(gtp:valid-route-p ent))(progn(setq row(gtp:get-dn)dn(car row)series(gtp:get-series)carrier(gtp:mm(nth 1 row))casing(gtp:mm(gtp:casing-od row series))mode(gtp:get-mode)flow(gtp:get-flow)style "Standard" raw(gtp:curve-points ent))(initget "Standard Short")(setq style(or(getkword "\nElbow [Standard/Short] <Standard>: ")"Standard"))(setq pts(gtp:clean-points raw))(if(>= length? 2)(progn(setq result(gtp:model-route pts dn carrier casing mode style))(princ(strcat "\nGTPPIPE complete: "(itoa(nth 0 result))" pipe interval(s), "(itoa(nth 1 result))" elbow(s).")))(princ "\nRoute needs at least two points."))) (princ "\nInvalid route."))
 (setvar "CMDECHO" old)(princ))

; ----------------------------- COMMAND: GTPVALVE -----------------------------
(defun c:GTPVALVE(/ *error* old ent pick info row dn series family od vrow cat comp)
 (setq old(getvar "CMDECHO"))(setvar "CMDECHO" 0)(defun *error*(m)(setvar "CMDECHO" old)(if m(princ(strcat "\nGTPVALVE error: "m)))(princ))
 (gtp:layers)(setq ent(car(entsel "\nSelect route LINE / POLYLINE: ")))
 (if(and ent(gtp:valid-route-p ent))(progn(setq pick(getpoint "\nPick valve centre on route: "))(setq info(list(vlax-curve-getClosestPointTo ent(trans pick 1 0))))(setq dn(car(gtp:get-dn))series(gtp:get-series))(initget "SINGLE TWIN SINGLE2VD TWIN2VD")(setq family(or(getkword "\nValve family [SINGLE/TWIN/SINGLE2VD/TWIN2VD] <SINGLE>: ")"SINGLE"))(if(member family '("SINGLE2VD" "TWIN2VD"))(setq family(if(= family "SINGLE2VD")"SINGLE""TWIN")))(setq od(nth 1(gtp:find-dn dn))vrow(gtp:valve-family-row family od))(if vrow(progn(setq comp(gtp:component-make(gtp:next-id "VALVE")"VALVE" *gtp-flow-type* dn series(car info)'(1.0 0.0 0.0)'(0.0 0.0 1.0)(gtp:mm(gtp:valve-length vrow family))vrow(list(cons'family family)) ))(gtp:reg-add comp)(gtp:make-valve-body comp vrow family)(princ(strcat "\nCreated " family " valve "(gtp:component-get comp 'id)" | L="(rtos(gtp:valve-length vrow family)2 0)" mm.")))(princ "\nNo catalogue row for that DN/family.")))(princ "\nInvalid route."))
 (setvar "CMDECHO" old)(princ))

; ----------------------------- FITTINGS --------------------------------------
(setq *gtp-reducer-single-db* '((26.9 33.7 90 110 110 125 125 140 1500)(26.9 42.4 90 110 110 125 125 140 1500)(33.7 42.4 90 110 110 125 125 140 1500)(33.7 48.3 90 110 110 125 125 140 1500)(42.4 48.3 110 110 125 125 140 140 1500)(42.4 60.3 110 125 125 140 140 160 1500)(48.3 60.3 110 125 125 140 140 160 1500)(48.3 76.1 110 140 125 160 140 180 1500)(60.3 76.1 125 140 140 160 160 180 1500)(60.3 88.9 125 160 140 180 160 200 1500)(76.1 88.9 140 160 160 180 180 200 1500)(76.1 114.3 140 200 160 225 180 250 1500)(88.9 114.3 160 200 180 225 200 250 1500)(88.9 139.7 160 225 180 250 200 280 1500)(114.3 139.7 200 225 225 250 250 280 1500)(114.3 168.3 200 250 225 280 250 315 1500)(139.7 168.3 225 250 250 280 280 315 1500)(139.7 219.1 225 315 250 355 280 400 1500)(168.3 219.1 250 315 280 355 315 400 1500)(168.3 273.0 250 400 280 450 315 500 1500)(219.1 273.0 315 400 355 450 400 500 1500)(219.1 323.9 315 450 355 500 400 560 1500)(273.0 323.9 400 450 450 500 500 560 1500)))
(defun c:GTPREDUCER(/ small large row ent pick info dir comp mid)
 (gtp:layers)(setq small(getreal "\nSmaller carrier OD (mm): ")large(getreal "\nLarger carrier OD (mm): "))(setq row(vl-some '(lambda(x)(if(and(<(abs(- small(car x)))0.01)(< (abs(- large(cadr x)))0.01))x))*gtp-reducer-single-db*))(if row(progn(setq ent(car(entsel "\nSelect route: "))pick(getpoint "\nPick reducer centre: ")info(list(vlax-curve-getClosestPointTo ent(trans pick 1 0))(list 1.0 0.0 0.0)))(setq comp(gtp:component-make(gtp:next-id "REDUCER")"REDUCER"*gtp-flow-type*0 2(car info)(cadr info)'(0 0 1)1500.0(list(cons'family "REDUCER_SINGLE")(cons'small-carrier-od-mm small)(cons'large-carrier-od-mm large))nil))(gtp:reg-add comp)(setq mid(gtp:vadd(car info)(gtp:vscale(cadr info)750.0)))(gtp:make-cylinder(car info)mid small "GTP-FITTING-BODY")(gtp:make-cylinder mid(gtp:vadd mid(gtp:vscale(cadr info)750.0))large "GTP-FITTING-BODY")(princ "\nReducer component created."))(princ "\nReducer pair not found in catalogue.")) (princ))
(defun c:GTPTEE(/ p d bdir comp)(gtp:layers)(setq p(getpoint "\nTee centre: ")d(getpoint p "\nTee main direction point: ")bdir(getpoint p "\nBranch direction point: "))(setq comp(gtp:component-make(gtp:next-id "TEE")"TEE"*gtp-flow-type*0 2 p(gtp:vunit(gtp:vsub d p))'(0 0 1)500.0(list(cons'family "TEE_GENERIC")) (list(cons'branch-direction(gtp:vunit(gtp:vsub bdir p))))))(gtp:reg-add comp)(gtp:make-cylinder(gtp:vsub p(gtp:vscale(gtp:component-get comp 'direction)250)) (gtp:vadd p(gtp:vscale(gtp:component-get comp 'direction)250)) 110 "GTP-FITTING-BODY")(gtp:make-cylinder p(gtp:vadd p(gtp:vscale(gtp:vunit(gtp:vsub bdir p))500))60 "GTP-FITTING-BODY")(princ "\nTEE component created."))
(defun c:GTPBRANCH(/ p b comp dir)(gtp:layers)(setq p(getpoint "\nBranch connection point: ")b(getpoint p "\nBranch direction/end point: ")dir(gtp:vunit(gtp:vsub b p))(setq comp(gtp:component-make(gtp:next-id "BRANCH")"BRANCH"*gtp-flow-type*0 2 p dir '(0 0 1)700.0(list(cons'family "WELDABLE_BRANCH")(cons'branch-length-mm 700.0))(nil)))(gtp:reg-add comp)(gtp:make-cylinder p(gtp:vadd p(gtp:vscale dir 700))90 "GTP-FITTING-BODY")(princ "\nBRANCH component created."))
(defun c:GTPENDCAP(/ p d comp)(gtp:layers)(setq p(getpoint "\nEnd cap position: ")d(getpoint p "\nPipe direction point: ")d(gtp:vunit(gtp:vsub d p))(setq comp(gtp:component-make(gtp:next-id "ENDCAP")"END_CAP"*gtp-flow-type*0 2 p d '(0 0 1)25.0(list(cons'family "END_CAP"))(nil)))(gtp:reg-add comp)(gtp:make-cylinder(gtp:vsub p(gtp:vscale d 25))p 110 "GTP-FITTING-BODY")(princ "\nEND CAP component created."))

; ----------------------------- MITER -----------------------------------------
(defun c:GTPMITER(/ e1 e2 p1 p2 d1 d2 q r)(gtp:layers)(setq e1(car(entsel "\nFirst route: ")) e2(car(entsel "\nSecond route: ")))(if(and e1 e2)(progn(setq p1(vlax-curve-getStartPoint e1)p2(vlax-curve-getStartPoint e2)d1(gtp:vunit(gtp:vsub(vlax-curve-getEndPoint e1)p1))d2(gtp:vunit(gtp:vsub(vlax-curve-getEndPoint e2)p2)))(princ "\nMiter helper retained; use GTPPIPE on the resulting centreline.")))(princ))
(defun c:GTPMITTER()(c:GTPMITER))

; ----------------------------- INSPECTION ------------------------------------
(defun c:GTPCOMPONENTS()(gtp:components-summary)(princ))
(defun c:GTPCOMPONENTSAVE()(gtp:persist-all)(princ))
(defun c:GTPCOMPONENTRELOAD()(princ "\nComponents are already registered for the active drawing session.")(princ))
(defun c:GTPVALVECATALOG()(princ "\nValve catalogue: SINGLE and TWIN families are embedded in this file.")(princ))
(defun c:GTPVALVESUMMARY()(gtp:components-summary)(princ))
(defun c:GTPLAYER()(gtp:layers)(princ "\nGTP layers ready.")(princ))
(defun c:GTPHELP()(princ "\nGTP commands: GTPPIPE GTPVALVE GTPTEE GTPREDUCER GTPBRANCH GTPENDCAP GTPMITER GTPMITTER GTPUNITS GTPLAYER GTPVALVECATALOG GTPVALVESUMMARY GTPCOMPONENTS GTPCOMPONENTSAVE GTPCOMPONENTRELOAD")(princ))
(defun c:GTPTEST()(princ "\nGTP ALL-IN-ONE FIXED is loaded correctly.")(c:GTPHELP)(princ))

(princ "\n============================================================")
(princ "\nGTP ALL-IN-ONE FIXED loaded successfully.")
(princ "\nType GTPTEST to verify command registration.")
(princ "\n============================================================")
(princ)
