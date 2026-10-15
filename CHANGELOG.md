# Engine Monitoring changelog

## 0.2.0 (2026-10-15)
- New Aircraft Profile (AIRCRAFT > Set up your aircraft profile): tail number, make/model/year, serial, engine, 4/6/8 cylinders, turbo and TIT probes, engine monitor, propeller, home airport, FIKI, oil change interval, engine limits, technique references. Saved on the device (Application Support/EngineMonitoring/aircraft-profile.json).
- Every post-flight check now reads its limits from the profile. Starting values are an SR22 Turbo template, marked "template - confirm in Aircraft Profile" until the owner confirms them against their POH/AFM. The TIT reference only applies to turbo engines.
- Removed all N63KA data: bundled flight history (flight_history.json), POH text (poh_index.json), approach cards (approach_cards.json), N63KA facts, oil analysis samples, maintenance watch list and record-based issues.
- COPA links show only for Cirrus profiles; the COPA question describes the owner's aircraft.
- User-facing wording no longer says N63KA ("this aircraft's normal", "Post-flight report"); the ASK N63KA section is now ASK.
- Data folder renamed from N63KA to EngineMonitoring.
- Removed the unused old AircraftProfile struct in Models.swift.
- Tests: new AircraftProfileTests; bundle tests now check that no aircraft-specific data ships.
- Version 0.2.0 (2).

## 0.1.0 (2026-10-15)
- New app created from N63KA Copilot 0.9.7 (main 003a563).
- Renamed project, targets, scheme and module to EngineMonitoring; display name "Engine Monitoring"; bundle ID com.fueledconsulting.EngineMonitoring.
- Release signing switched from the manual "N63KA Copilot App Store" profile to automatic signing on team D64ZNA8J2P.
- PRODUCT_MODULE_NAME set to EngineMonitoring so the tests' `@testable import EngineMonitoring` resolves.
- Version reset to 0.1.0 (1).
- Known: N63KA's bundled data and wording are still inside; removed in 0.2.0.

---

# Inherited N63KA Copilot history

# Changelog

## v0.9.7 (build 22) - 2026-10-12

### Added: run-up mag check, GAMI lean test, report card, turbo and induction checks, A&P pre-shop report
- **Run-up mag check** on every flight, automatically: finds the run-up and each magneto's RPM drop (POH 4-14: 150 RPM
  max, 75 RPM difference) and each cylinder's EGT rise on each mag. A cylinder whose EGT stays flat on one mag is not
  firing on that mag (plug or lead). CAUTION issues for drops/splits over the POH limits, WATCH for a cold cylinder
  ("mag.cyl5"). N63KA's logs: 81 run-ups; cylinder 5 did not rise on the L mag on 3 of them; 1 drop and 2 splits over
  the limits.
- **GAMI lean test**: the spread (fuel flow at each cylinder's peak EGT) found automatically in any slow lean sweep, with
  a parabola fit through each peak; a guided lean-test card in the app. N63KA's logs only show big-mixture-pull leaning,
  which is too fast to measure, so no spread yet: fly the test once.
- **Report Card** for every flight: about 20 numbers (takeoff, climb, cruise, oil, electrical, mag drops) with the
  percentile against all earlier flights and the days since the previous flight.
- **Turbo & Induction**: takeoff RPM/MAP/fuel flow, full-throttle MAP by altitude (deck pressure) and the induction-leak
  check (a cylinder running much hotter than the others at low manifold pressure than in cruise), each against N63KA's
  normal; WATCH issues ("turbo.takeoff-ff", "turbo.deck", "turbo.induction.cylN" when seen on consecutive flights).
- **A&P Pre-Shop Report**: one page (PDF or text) with run-up, fuel distribution, cylinders/valves/probes, early warning,
  turbo/induction, oil/electrical and a numbered "please look at" list.
- All in DIAGNOSTICS > Engine Analysis, and in each post-flight report and bundled flight summary.
- Bundled history carries the new checks for all 324 logs. Flight summaries move to version 9.
- Tools: tools/n63ka_magcheck.py, n63ka_gami.py, n63ka_reportcard.py, n63ka_engine_export.py.

## v0.9.6 (build 21) - 2026-10-09

### Added: early warning and engine trend charts
- DIAGNOSTICS > Engine Analysis > **Early Warning & Trends**: every engine value followed across flights, warning when one
  starts to drift BEFORE it reaches a limit, with the likely cause and roughly how many flight hours remain at the
  current rate. Values (steady cruise only, corrected for outside air temperature and fuel flow): CHT per cylinder,
  each cylinder's EGT distance from the others, valve-watch cycle per cylinder, CHT and EGT spread, oil temperature and
  pressure, the gap between the two TITs, bus voltages.
- Method (tuned on the 324 SharePoint logs): newest 5 flights vs the 40 before them; SHIFT over 2.5 sigma or a
  significant DRIFT over the newest 10 flights; EARLY WARNING or ACT SOON (over 4 sigma or a limit within 10 flight
  hours). Moving back toward balance is never a warning. Patterns name what may be developing (exhaust valve, injector or
  induction leak, cooling, oil cooler, oil pressure, turbo/exhaust, charging system).
- Trend charts for every value: each flight, N63KA's normal band, the trend line and where it leads; all-cylinder CHT
  and valve-watch charts; and in each post-flight report, all six EGTs and CHTs through the flight.
- Early warnings appear in Issue History ("early.<value>") with what to check; a notification on the iPad when a new one
  appears.
- Bundled history carries the trend values for all 324 logs (63 flights with steady cruise). Today: nothing drifting.
- Flight summaries move to version 8.

## v0.9.5 (build 20) - 2026-10-09

### Added: probe and wiring check
- Every log is checked for sensor faults on all EGT, CHT, TIT, oil temperature and oil pressure channels, judged against
  the other cylinders so real engine changes are not mistaken for faults: blank readings in flight, one-second spikes,
  a jump only one cylinder makes that then stays, a stuck reading while the others move, off-scale readings, and a
  reading far from the other cylinders in steady cruise.
- DIAGNOSTICS > Engine Analysis > **Probes & Wiring**; a "Probes And Wiring" section in each post-flight report and
  bundled flight summary; a WATCH issue per faulty channel ("probe.egt3"...) with likely causes (connector, clamp, lead,
  thermocouple/sender, engine data unit) and what to ask the A&P.
- Bundled history: all 324 SharePoint logs checked (136 with enough engine running time): no sensor faults found.
  Injected faults in a real log (spikes, dropout, stuck, jump, dead probe, oil-pressure spikes) were all caught.
- tools/n63ka_probes.py: same check in Python. Flight summaries move to version 7.

## v0.9.4 (build 19) - 2026-10-09

### Valve watch is now visible for every flight
- DIAGNOSTICS > Engine Analysis > **Valve Watch**: flights checked, any flagged cylinder, each cylinder's typical and
  largest EGT cycle, and every checked flight (tap one for its summary).
- The bundled engine data history now carries the valve watch result for all 324 SharePoint logs (49 flights with
  steady cruise, 531 windows, no cylinder flagged), so it no longer needs an imported CSV to show results.
- Bundled flight summaries (Issue History > flight) show the Valve Watch section too.

## v0.9.3 (build 18) - 2026-10-09

### Added: valve watch (exhaust valves)
- Every flight is checked for the early exhaust-valve signature Savvy Aviation describes for FEVA: one cylinder's EGT
  swinging on its own, about once a minute, 30 °F or more, in steady cruise (AOPA, Aug 2014). Built from that published
  description, not Savvy's model.
- How: 8-minute windows of steady cruise (RPM, fuel flow and MAP steady); each cylinder's EGT minus the median of the
  other five, so power and mixture changes cancel; strongest cycle with a 40-100 s period. Probe spikes are repaired
  first so a bad probe does not look like a valve. A cylinder is flagged when it shows up in a quarter of the windows.
- Post-flight report: new "Valve Watch" section. Issues: a WATCH item per cylinder ("valve.cylN"), grouped across
  flights, with likely causes in order (valve, probe/wiring, injector), what to check and what to ask the A&P
  (borescope that cylinder; compare with the oil-analysis nickel).
- tools/n63ka_valves.py: same check in Python for a whole data_log folder (with a per-flight history file).
- Flight summaries move to version 6; imported logs are re-summarized automatically.

## v0.9.2 (build 17) - 2026-10-08

### Maintenance
- Removed unnecessary `nonisolated(unsafe)` on the shared DateFormatter / JSONEncoder / JSONDecoder constants
  (Models.swift, Persistence.swift, PerspectiveLog.swift) to clear the Xcode 27 warnings. No behavior change.
- `tools/__pycache__` is no longer tracked; `__pycache__/` and `*.pyc` added to .gitignore.
- First update through the GitHub pull request -> Xcode Cloud -> TestFlight path.

## v0.9.1 (build 16) - 2026-10-07

### Changed: maintenance uses your logbook baseline and total time
- Logbook baseline added once: annual Dec 22, 2025 at 1,940.3; 30-hour services at 1,971.9 (Apr 28, 2026) and 2,002.1
  (Aug 25, 2026). The service dates were matched to the Blackstone oil samples and the flight hours in the logs;
  edit them if the logbook says otherwise.
- Hours now count airborne time from the logs, which tracks the logbook total time (31.4 vs 31.6 h and 59.3 vs 61.8 h
  between the services). Each recorded tach reading resets the estimate; MAINTENANCE shows today's estimated total time.
- "Oil and filter change" is now "30-hour service and oil change": 30 hours or 4 months, whichever first.
- Built-in items pick up new text on update; a schedule you edited is kept.

## v0.9 (build 15) - 2026-10-07

### Added: MAINTENANCE
- New MAINTENANCE section: every item shows OK / Due soon / Overdue / Not recorded / Last check failed, sorted so what
  needs attention is on top. Schedules by days, by engine hours, or both (whichever first).
- Engine hours come from the data card logs (engine running time since the last entry, close to tach time).
- Built-in items:
  - Oil and filter change: 25 engine hours or 4 months (your practice; editable). Records tach, quarts, oil type, filter, sample.
  - FIKI ice protection system test: every 30 days, done by the PIC. Records overall pass/fail, fluid quantity, fluid on
    all surfaces and prop, windshield spray. Procedure: the Ice Protection System supplement (not on file yet).
  - Tire pressure check: monthly. Nose 30-35 psi, mains 60-65 psi (POH 8-18 / TPOH 15-15R2); out-of-range values are
    flagged automatically.
  - Annual inspection: 12 months (14 CFR 91.409).
- Record results directly in the app (date, who, values, notes). A failed check stays at the top until a passing one
  is recorded. Full history per item; swipe to delete a record.
- Add your own checks or services (days and/or hours, steps, values with min/max) and change any schedule.
- iPad reminders: 9 am on the due-soon day and on the due date for date-based items.
- Export Log: CSV of every record for the shop, SharePoint or the Claude review.

## v0.8.1 (build 14) - 2026-10-06
- The sidebar shows the running version and build (bottom of the section list), so you can confirm an update installed.
- MY FLYING is in the sidebar between DIAGNOSTICS and AIRCRAFT.

## v0.8 (build 13) - 2026-10-06

### Added: MY FLYING - takeoff and landing quality with charts and tables
- New MY FLYING section. Every takeoff and landing in the engine data (112 landings, 114 takeoffs bundled from the
  SharePoint logs, plus any log you import) is checked against POH 4-3 speeds and stable-approach gates:
  - Landing: 500 ft (75-100 KIAS, sink 1,000 fpm or less), 300 ft stable (75-95 KIAS, sink 1,000 or less, bank 15° or
    less), speed over the fence at 50 ft (80-85 KIAS POH; 77-90 counted on speed), flare (50 ft to touchdown 10 s or less).
  - Takeoff: full power (2,650-2,710 RPM), initial climb 100-1,000 ft (Vy 101 to 110-120 KIAS), time to 1,000 ft, fuel flow.
- Summary table (last 10 vs all), chart of speed over the fence per landing with the 80-85 KIAS band and Vref 77,
  stable-at-300-ft by month, and initial climb speed per takeoff.
- Tap any landing for its checks table and profile charts (height, airspeed, vertical speed, bank against time to
  touchdown, with the 500/300/50 ft gates marked); share a one-landing summary. Takeoffs show airspeed and height.
- Each flight's report and summary screen lists its takeoffs and landings; the shared post-flight report includes them.
- Flight summary version 5 (older summaries rebuild automatically).

## v0.7.2 (build 12) - 2026-10-06

### Fixed: one-page PDF cards on FLY
- The old bundled one-page PDFs (Garmin LPV/LNAV/ILS sheets and the v3 card set from the original developer) are removed;
  they did not open reliably and did not match the current approach cards.
- New "One-Page Kneeboard Cards (PDF)" on FLY: each approach (ILS, LOC, VOR, VOR/DME, LPV, LNAV/VNAV, LNAV, LNAV+V, LP)
  plus "All approach cards" is made into a half-letter PDF on the iPad from approach_cards.json, so it always matches
  the in-app card. Autopilot / Hand-flown switch, Share (save to Files) and Print.
- Test checks every card renders as exactly one page in both modes.

## v0.7.1 (build 11) - 2026-10-06

### Changed: oil and cylinder temperatures are compared at the same outside air temperature
- N63KA's oil temperature rises about 0.85 °F per °C of OAT (73 cruise flights). Trends for oil temperature and CHT now
  compare each flight with what N63KA shows at that flight's OAT (fit over all flights, 10th-90th percentile band),
  so hot desert days are not flagged just for being hot. The OAT and departure airport are shown with each trend.
- OAT is recorded per phase in every flight summary (summary version 4; older summaries rebuild automatically).
- The POH 240 °F oil temperature limit still applies regardless of OAT.

### Changed: TIT uses both turbochargers
- The TN engine logs TIT 1 and TIT 2; TIT 2 runs about 60 °F hotter. Earlier versions showed TIT 1 only, which is why
  TIT looked low. "TIT" is now the hotter of the two, and TIT 1 / TIT 2 are kept separately.
- Cruise TIT is compared with your 1,575 °F target in the post-flight report and Engine / In Flight history (pilot
  reference only; the basic POH has no TIT values - it needs the Tornado Alley AFM supplement).

## v0.7 (build 10) - 2026-10-06

### Added: review tracking for every WARNING, CAUTION and WATCH issue
- Each issue has a review log: Add Review records the action (Reviewed / Monitoring / Completed / Reopened), date,
  who reviewed it (you, A&P, shop), what was discovered, what was done, and a work order or logbook reference.
- A review covers every occurrence up to that point. Any later occurrence is marked NEW and the issue goes back to
  "Needs Review". A Completed issue that happens again shows RECURRED and reopens.
- Issue History opens on "Needs Review" (also Reviewed, Completed, All). DIAGNOSTICS shows how many issues need review,
  and each Diagnostic Area shows its count.
- Export Review Log (share button in Issue History): a markdown table of every tracked issue with status, new
  occurrences, last review and findings. Save it to SharePoint Cirrus/N63KA Copilot App (Claude) before a Claude
  engine-card review so Claude knows what has already been reviewed.
- v0.6 status notes are kept (Resolved becomes Completed; the note becomes the first review entry).

### Added: new-item check for Claude engine-card reviews
- tools/n63ka_issues.py runs the same issue checks as the app (verified identical on all 324 logs) and compares them
  with tools/issue-register.json (every issue seen so far). It lists NEW issue kinds, NEW occurrences, and anything
  marked Completed in the exported review log that happened again.

## v0.6 (build 9) - 2026-10-06

### Added: issue history from the engine data card, with how to resolve each issue
- All 324 Perspective logs from SharePoint Cirrus/Engine Data/data_log (Oct 2025 - Oct 2026, 89 flights) are analyzed and
  bundled in the app (Resources/Data/flight_history.json). No CSVs are needed on the iPad.
- DIAGNOSTICS > "Past Issues And How To Resolve": issue history grouped by kind with occurrence counts, plus the top open items.
  Each issue shows: what the data shows, what to do if it happens in flight (POH procedure, APPROVED, with a link to the
  procedure), how to resolve it (ground checks for you and the A&P, TRAINING), every occurrence (tap for that flight),
  Ask COPA Commander, and your status: Open / Monitoring / Resolved with a note and date (saved on the iPad).
  An issue marked Resolved that happens again shows as RECURRED.
- Each Diagnostic Area (Engine / Start, Electrical, ...) lists its issues first, then the history from every flight;
  flights from the bundled history open a summary screen.
- Issues detected: POH limits (now also bus voltage, POH 2-9), engine caught then stopped, extra cranking, oil pressure
  slow after start (POH 4-10), low idle oil pressure on the ground (POH 3A-6), sudden bus voltage drops, GPS fix loss,
  trends against N63KA's own normal, technique references, and open items from the maintenance records.
- Newly imported logs are analyzed the same way automatically (flight summary version 3; older summaries rebuild).
- tools/build_history.sh rebuilds the bundled history on the Mac after new logs are uploaded.

### Changed
- Oil pressure limits ignore the first 30 s after a start (POH 4-10); the 10-29 psi caution is split into in-flight
  (CAUTION) and on-ground idle (WATCH, POH 3A-6). Bus low-voltage limits are checked in flight only (alternators are
  OFF for the start, POH 4-10).

## v0.5.2 (build 8) - 2026-10-06

### Added: how to set up the Perspective, button by button
- Each approach card opens with "Set up Perspective": every task with its exact key sequence as keycaps, e.g.
  - Load the approach: PROC › FMS → SELECT APPROACH › ENT › FMS → approach › ENT › FMS → transition/VECTORS › ENT › ENT = LOAD
  - Set minimums: TMR/REF softkey › FMS → MINIMUMS › small FMS → BARO › FMS → set DA/MDA › ENT › TMR/REF
  - Tune NAV1: NAV knob → frequency › NAV ⇄ swap › Audio panel NAV1 → Morse ID
  - VOR: CDI softkey → VOR1 › CRS knob → final course
  - Activate approach / Activate Vector-to-Final, altitude preselect, configure.
- New "Perspective Keys" reference: what every PROC/FMS/softkey/radio/bug knob/autopilot key does.
- The flying lines are unchanged: short and big.
- Kneeboard cards print the set-up sequence above the flying lines (still one half-letter page).

## v0.5.1 (build 7) - 2026-10-06

### Changed: approach guides built for flying in IMC
- Opening an approach now shows a big-type flying card, not the long step list:
  - "Before the approach" checklist (load, minimums, brief, tune/ID, configure) that folds away when done;
  - then only 5-6 lines for flying it: when, at most three actions, and the one thing to see (e.g. "FAF - ALT SEL MDA · VS −700 · Timer - ALTS white");
  - the current line is large and highlighted; tap it when done and the next one lights up;
  - MISSED and THEN are always on screen in red: Power full · GO AROUND · Flaps 50% (80 KT), then AP · NAV · FLC.
- The detailed step-by-step version is one tap away ("All steps") for study on the ground.
- Print Kneeboard Card: large-type half-page card per approach and mode.

## v0.5 (build 6) - 2026-10-06

### New: Approach Guides on FLY
- Nine step-by-step approach guides: ILS, LOC, VOR, VOR/DME (new), RNAV LPV, LNAV/VNAV, LNAV, LNAV+V, LP/LP+V.
- Each shows what to push and when, as keycaps in order (PROC, FMS knob, ENT, CDI softkey, NAV swap, CRS knob, APR, VS, ALT SEL knob, GO AROUND...), the timing ("At the FAF"), and what to check on the FMA/HSI.
- Autopilot / Hand-flown switch: the steps change to match (remembered per device).
- Tick off steps as you go; reset with one tap.
- Phases: brief and load, tune and identify (ILS/LOC/VOR), getting to the final course (full approach or vectors-to-final), arm, final approach, minimums, missed approach.
- POH-based steps are marked APPROVED with the page: approach speeds (4-3), Before Landing (4-19), Balked Landing/Go-Around (4-21). Approved limitations are cited where they apply: GPS not to be used for ILS/LOC/VOR finals (2-19 item 4b-c), vertical guidance on non-precision approaches advisory only (4d), coupled missed approach allowed with GFC 700 software 0764.09+ (2-20 item g).
- VOR and VOR/DME guides: switch the CDI to VOR1 yourself and set the course; VAPP mode; GPS substitution for DME fixes that are in the loaded approach.
- Print or Save PDF: each guide prints on one Letter page (AirPrint, or Save to Files from the print sheet).
- The original PDF one-pagers remain below as "One-Page Cards (PDF)".
- `tools/gen_approaches.py` generates `Resources/Data/approach_cards.json`; edit the script, rerun, rebuild.

## v0.4.2 (build 5) - 2026-10-06

### Fixed
- DIAGNOSTICS > Engine / Start, GFC 700 / Autopilot, Electrical, Avionics and Engine / In Flight showed only static text, with nothing to tap (reported on TestFlight). Each area now shows:
  - your event markers for that system (tap for the marker's analysis);
  - the history from every imported log (tap for that flight's post-flight report):
    - Engine / Start: every start with outcome (started, or caught and stopped within 30 s), cranking episodes, lowest cranking voltage, peak fuel flow, weakest cylinder EGT rise, plus a cranking-voltage chart;
    - Autopilot: engage/disengage times per flight;
    - Electrical: lowest bus 1/2 voltage and largest 1-s drop per flight, with a chart;
    - Avionics: GPS fix losses per flight;
    - Engine / In Flight: cruise hottest cylinder, oil, TIT, EGT spread per flight, with a CHT chart.
- Pull down to refresh. Flight summaries saved by v0.4 are rebuilt automatically to include the new fields.

## v0.4.1 (build 4) - 2026-10-06

### Fixed
- FLY: approach training cards did not open when tapped (reported on TestFlight). The card list used a value-based NavigationLink inside a screen pushed by a destination link, which SwiftUI ignores in the split-view detail column. Cards now use destination links and are listed directly on the FLY screen, one tap to open.

## v0.4 (build 3) - 2026-10-06

The N63KA agent, offline part: the app now knows the POH, the aircraft's records and what normal looks like for N63KA.

### POH offline (approved data)
- Full text of the N63KA POH (13772-002 Reissue A, 348 pages) bundled as `Resources/Data/poh_index.json`, generated from POH.pdf.
- New PROCEDURES section: all 69 emergency (Section 3) and abnormal (Section 3A) procedures, grouped as in the POH, each opening its checklist text with the page label.
- ASK N63KA is now an offline search across every POH page and the aircraft records, with pilot shorthand (CHT, TIT, ALT, MAP, FF) and whole-word matching for short terms.
- FLY has a one-tap link to the emergency procedures.
- Optional: add POH.pdf to the app (see BUILD_GUIDE) and every procedure and search result gets "Open POH Page" at the exact page.

### Aircraft knowledge
- AIRCRAFT shows the profile from the records (engine, prop, avionics, hours, CAPS dates), each fact with its source.
- Limits the app checks: POH Section 2 values as APPROVED (RPM with the POH's 10 s / 5 s annunciation timing, oil temperature and pressure, CHT caution and warning); Jim Barker technique references as EXPERIENCE. No approved TIT or MAP limit until the Tornado Alley supplement is added.
- Oil analysis trend chart (nickel, chromium, iron) and a maintenance watch list from the records.
- Online resources: COPA.fyi, COPA Commander, Ask COPA U, COPA forum, Cirrus Tech Pubs (labeled; not used in flight).

### N63KA normal and post-flight report
- Every imported log is summarized by phase (ground, climb, cruise, descent): median, 5th/95th percentile and max for RPM, MAP, fuel flow, oil, TIT, voltages, current, each cylinder's CHT, hottest CHT and EGT spread.
- N63KA's normal range per phase is learned from all imported flights (needs 5).
- Tap a log for its post-flight report: POH limit exceedances with duration, values outside N63KA's normal, technique notes, your markers. Share it as text (for SharePoint and the Claude review) or copy a question for COPA Commander.
- Logs imported by v0.3 are summarized automatically on first launch.

### Tooling
- `tools/n63ka_flight.py`: the same analysis in Python, used by the Claude post-flight review skill.
- 18 new unit tests (49 in total) (POH index and search, phases, baseline, limits, report, summaries).

## v0.3 (build 2) - 2026-10-05

Fixes from the v0.2 code review, plus Perspective log import.

### Release blockers
- Info.plist: `CFBundleExecutable` was `$ (EXECUTABLE_NAME)` (stray space, never substituted). Now `$(EXECUTABLE_NAME)`.
- Info.plist: version, build, bundle name and identifier now come from build settings instead of hard-coded `0.1` / `1` / empty values. Category set to Navigation. Export-compliance key added (`ITSAppUsesNonExemptEncryption = NO`; the app uses no custom encryption).
- Added `PrivacyInfo.xcprivacy` declaring UserDefaults use (reason CA92.1), no tracking, no data collection.
- Unit-test target added to the Xcode project (it existed only in `project.yml`), with a shared scheme so tests run from Product > Test.
- `project.yml` brought back in line with the project. Removed `__MACOSX`, `.DS_Store` and `xcuserdata`; added `.gitignore`.

### Safety and content
- New `TRAINING` source authority. The eight bundled approach cards are relabeled from MANUFACTURER to TRAINING, since they are self-authored training aids.
- Documents gained `revision`, `effectiveDate`, `reviewDueDate` and `reviewedBy`. Unreviewed or overdue cockpit-critical documents are flagged in the list and viewer. `isCockpitCritical` is now used.
- Non-approved documents show their authority banner above the PDF.
- Event markers: the timestamp is captured at the tap of "Something Happened", not when Save is pressed. Details are optional and can be added later.
- Markers record the device time zone and UTC offset, and show both local and UTC times.
- PDF night mode (inverted colors), remembered per device.

### New: Perspective log import and evidence
- Parser for Garmin Perspective / G1000 CSV data logs (`#airframe_info` metadata, units row, header row, 1 Hz samples, UTC offset per row).
- Imported logs are copied into the app, indexed, and matched to markers by time; a different log can be chosen manually.
- The diagnostic engine now extracts recorded evidence per system (see README). Confidence never exceeds LOW and no cause is assigned.

### Code quality
- Event storage moved from UserDefaults to an atomic JSON file, with one-time migration of v0.2 markers. Save and load errors are shown, not swallowed.
- Markers can be edited, deleted (swipe or Edit) and exported as CSV.
- `DocumentRepository` reports catalog load errors, resolves filenames on the last dot, and lists catalog entries missing from the bundle (shown under AIRCRAFT).
- `PDFViewer` reloads if its URL changes.
- Diagnostic areas are generated from `DiagnosticSystem`; aircraft profile moved out of the view into `AircraftProfile.n63ka`.
- Each sidebar section gets a fresh navigation stack, so switching sections never leaves a stale pushed screen.

### Not changed (needs people, not code)
- Approach card content still needs review by a CFII familiar with Perspective / GFC 700.
- Signing team and App Store profile ownership must be confirmed by the owner.

## v0.2
- Diagnostics module scaffolding and "Something Happened" markers (developer delivery).

## v0.1
- Initial SwiftUI shell, PDF reader, approach cards, source-authority model.
