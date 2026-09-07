# GTP Variable-DN AutoCAD Test Plan

## Objective
Verify that `GTP_DH_TOOLKIT_COMBINED.lsp` changes pipe DN correctly after reducers, uses the local DN for downstream elbows and components, preserves component footprints, and rejects ambiguous or unsafe reducer placement.

## Test environment
- AutoCAD / AutoCAD Mechanical with Visual LISP/ActiveX support.
- APPLOAD only `GTP_DH_TOOLKIT_COMBINED.lsp`.
- Start from a clean DWG for the core tests.
- Use millimetres first (`INSUNITS=4`), then repeat the unit-conversion cases.
- Run `GTPCOMBINEDTEST`, `GTPSMARTTEST`, and `GTPVARDNTEST` after APPLOAD.

## DN interpretation rule
The DN selected at the beginning of `GTPPIPE` is the DN at **route Start**. Reducers must be placed in route order from Start toward End. Each reducer changes the active DN toward route End.

## Catalogue reference values used in acceptance checks
For Series 2 from the current pipe database:
- DN100: carrier OD 114.3 mm, casing OD 225 mm.
- DN150: carrier OD 168.3 mm, casing OD 280 mm.
- DN200: carrier OD 219.1 mm, casing OD 355 mm.

Reducer pairs DN100/DN150 and DN150/DN200 exist in the current single-pipe reducer table and use a 1500 mm reducer length.

---

## TC-01 — Load and command smoke test
**Setup:** New empty DWG.

**Steps:**
1. APPLOAD `GTP_DH_TOOLKIT_COMBINED.lsp`.
2. Run `GTPCOMBINEDTEST`.
3. Run `GTPSMARTTEST`.
4. Run `GTPVARDNTEST`.
5. Run `GTPHELP`.

**Expected:**
- No load errors.
- All three diagnostic commands report PASS.
- Help text identifies `GTPPIPE` as variable-DN and states that reducers change DN toward route End.

## TC-02 — No reducer regression
**Route:** Straight 10,000 mm line.

**Steps:**
1. Run `GTPPIPE`.
2. Start DN = DN100, Series 2, CASING, Flow, Standard elbow.
3. Choose `Build` without adding components.

**Expected:**
- Entire route remains DN100.
- Carrier OD = 114.3 mm.
- Casing OD = 225 mm.
- No reducer-related warning.

## TC-03 — Single reducing transition DN150 -> DN100
**Route:** Straight 20,000 mm line, drawn Start -> End.

**Steps:**
1. Run `GTPPIPE` with Start DN150, Series 2.
2. Choose `Reducer`.
3. Pick reducer centre at approximately 8,000 mm from route Start.
4. Enter downstream DN100.
5. Choose SINGLE reducer family.
6. Choose `Zones`.
7. Choose `Build`.

**Expected:**
- Zones show DN150 before the reducer and DN100 after it.
- Reducer occupies 1500 mm and straight pipe does not pass through its footprint.
- Upstream straight pipe uses carrier 168.3 / casing 280 mm.
- Downstream straight pipe uses carrier 114.3 / casing 225 mm.
- Console reports straight intervals using their local DN.

## TC-04 — Single increasing transition DN100 -> DN150
**Route:** Straight 20,000 mm line.

**Steps:** Same as TC-03, but Start DN100 and downstream DN150.

**Expected:**
- Upstream pipe is DN100.
- Downstream pipe is DN150.
- Reducer solid orientation expands toward route End.
- No continuous DN100 pipe remains through the downstream zone.

## TC-05 — Two reducers in sequence
**Route:** Straight 35,000 mm line.

**Steps:**
1. Start DN200, Series 2.
2. Place reducer at 8,000 mm: DN200 -> DN150.
3. Place reducer at 20,000 mm: DN150 -> DN100.
4. Run `Zones`.
5. Build.

**Expected:**
- Zone 1: DN200.
- Zone 2: DN150.
- Zone 3: DN100.
- Carrier/casing sizes match the catalogue for each zone.
- Both 1500 mm reducer footprints are clear of straight pipe.

## TC-06 — Downstream elbow changes DN
**Route:** 3D or 2D polyline with a 90-degree corner. Put the reducer on the straight leg at least 3000 mm before the corner.

**Steps:**
1. Start DN150, Series 2.
2. Place reducer DN150 -> DN100 before the corner.
3. Build.

**Expected:**
- Straight pipe before reducer is DN150.
- Straight pipe after reducer is DN100.
- The downstream elbow is generated as DN100, using DN100 carrier/casing dimensions and the DN100 elbow catalogue input.
- Console states that the elbow at that route vertex is DN100.

## TC-07 — Elbow before reducer stays upstream DN
**Route:** Corner first, reducer later on the next straight leg.

**Steps:**
1. Start DN150.
2. Place reducer after the corner, DN150 -> DN100.
3. Build.

**Expected:**
- First elbow is DN150.
- Pipe after reducer becomes DN100.

## TC-08 — Valve downstream uses local DN
**Route:** Straight 25,000 mm line.

**Steps:**
1. Start DN150.
2. Place reducer DN150 -> DN100 at 8,000 mm.
3. Place a valve at 15,000 mm.
4. Select a valve family that has a DN100 row.
5. Build.

**Expected:**
- Valve placement message reports local DN100.
- Valve catalogue row is DN100.
- DN100 straight pipe stops at the valve footprint and resumes after it.

## TC-09 — Tee downstream uses local main DN
**Steps:**
1. Start DN150.
2. Add reducer DN150 -> DN100.
3. Add a tee downstream of reducer.
4. Use branch DN80 or DN100.
5. Build.

**Expected:**
- Tee reports local main DN100.
- Main fitting casing corresponds to DN100/selected series.
- Main pipe around tee remains DN100.

## TC-10 — Branch downstream uses local main DN
Repeat TC-09 with `Branch`.

**Expected:** Branch reports local main DN100 and uses the DN100 main casing size.

## TC-11 — End cap uses final DN
**Steps:**
1. Start DN150.
2. Place reducer DN150 -> DN100.
3. Add Endcap at route End.
4. Build.

**Expected:** End cap reports local DN100 and uses DN100 casing OD.

## TC-12 — Start end cap remains Start DN
Same route as TC-11, but place an end cap at route Start.

**Expected:** Start end cap is DN150 while End-side pipe after reducer is DN100.

## TC-13 — Stock-length split after reducer
**Route:** Straight 35,000 mm line.

**Steps:**
1. Start DN150.
2. Reducer at 5,000 mm to DN100.
3. Build.

**Expected:**
- DN100 downstream zone longer than 12,000 mm is split into catalogue stock-length spools.
- Every downstream spool remains DN100.

## TC-14 — Reducer too close to corner
**Route:** Polyline with a corner.

**Steps:** Try to place reducer centre less than 750 mm from the corner.

**Expected:** Placement is rejected with the 750 mm clearance message; no reducer is registered.

## TC-15 — Reducer too close to route endpoint
Try to place reducer centre less than 750 mm from Start or End of a straight route segment.

**Expected:** Placement is rejected.

## TC-16 — Overlapping reducers
Place one reducer, then attempt a second reducer with centre less than 1500 mm from the first.

**Expected:** Second reducer is rejected because footprints would overlap.

## TC-17 — Reducer placement order protection
**Steps:**
1. Place a downstream reducer first.
2. Attempt to place another reducer upstream of it.

**Expected:** Upstream reducer is rejected and user is instructed to place reducers Start -> End.

## TC-18 — Prevent reducer after already-sized downstream component
**Steps:**
1. Start DN150.
2. Place a valve or tee at 15,000 mm.
3. Attempt to add a reducer at 8,000 mm.

**Expected:** Reducer is rejected because downstream components already exist and could have the wrong size.

## TC-19 — Same-DN reducer rejection
Attempt DN100 -> DN100.

**Expected:** Reducer is rejected because downstream DN must differ.

## TC-20 — Unsupported reducer catalogue pair
Choose a DN pair not present in the selected reducer family.

**Expected:** No reducer is created; command reports that the pair is absent from the catalogue.

## TC-21 — Flow and Return colour regression
Run TC-03 once as Flow and once as Return.

**Expected:** Variable DN does not alter the existing Flow/Return colour behavior.

## TC-22 — Series 1 / 2 / 3
Repeat TC-03 for all three insulation series.

**Expected:** Carrier DN transition is the same, while casing OD changes according to the selected series on both sides.

## TC-23 — FULL versus CASING model modes
Repeat TC-03 in both model modes.

**Expected:** DN transition works identically in both modes; FULL mode retains the existing insulation-generation behavior.

## TC-24 — 3D route with vertical and inclined legs
**Route:** 3D polyline with horizontal, vertical and inclined straight legs and at least two corners.

**Steps:** Place a reducer before a vertical/inclined downstream section and Build.

**Expected:**
- Stationing follows the actual 3D route length.
- Downstream 3D straight solids and elbows use the new DN.
- No dependence on world XY orientation.

## TC-25 — Persistence / reopen
**Steps:**
1. Create a route with two reducers and components.
2. Save the DWG.
3. Close and reopen AutoCAD/DWG.
4. APPLOAD combined toolkit.
5. Run `GTPCOMPONENTRELOAD` and `GTPCOMPONENTS`.
6. Re-run `GTPPIPE` on the route and inspect `Zones` before Build.

**Expected:** Reducer records reload from the DWG and DN zones are reconstructed in the same Start -> End order.

## TC-26 — Unit conversion
Repeat TC-03 with drawings configured in centimetres, metres and inches.

**Expected:**
- Reducer remains physically 1500 mm long after conversion.
- 750 mm corner/endpoint clearance is converted correctly.
- DN changes occur at the same physical route locations.

## TC-27 — Legacy standalone command regression
After APPLOAD, run standalone `GTPVALVE`, `GTPTEE`, `GTPREDUCER`, `GTPBRANCH`, and `GTPENDCAP` in a scratch DWG.

**Expected:** Commands still load and execute without component-factory signature errors. Variable-DN behavior is specifically guaranteed through the intelligent `GTPPIPE` workflow.

---

## Pass criteria
The feature is accepted when:
1. All load/static diagnostics pass.
2. TC-03, TC-04, TC-05 and TC-06 demonstrate visible carrier/casing DN changes across reducers.
3. Downstream elbows and smart-session components report/use the correct local DN.
4. Unsafe reducer placement cases are rejected rather than generating ambiguous geometry.
5. Persistence reconstructs the same DN zones after reopening the DWG.
6. Existing no-reducer, Flow/Return, series, stock-length and 3D-route behavior remains intact.

## Recommended first five tests
If time is limited, run TC-01, TC-03, TC-05, TC-06 and TC-08 first. They cover loading, one reducer, multiple reducers, downstream elbow sizing and downstream component sizing.
