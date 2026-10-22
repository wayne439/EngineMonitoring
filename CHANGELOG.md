# Engine Pulse changelog

## 0.9.7 (2026-10-22)
- Battery at engine start: every start now records the resting bus 1 voltage before cranking, the lowest voltage while cranking, the dip, cranking seconds, OAT and the charging voltage afterwards. A new HOME card charts the lowest cranking voltage over the last 20 starts against this battery's own normal and says "Check battery" when the newest 3 starts dip 1 V (24 V system) or 0.5 V (12 V) further than the earlier ones, with a note when the recent starts were much colder. Engine / Start history shows the same trend. Logs are re-read once to fill in the new values.
- POH page numbers (for example "POH 4-14") are shown only for Cirrus SR22s; other aircraft see "your POH". Issue guides on other aircraft drop SR22-only procedure links and annunciator names (M BUS, ALT 1/2) and point to the pilot's own POH/AFM procedure.
- 14-volt aircraft: bus-voltage limits written for 28-volt systems (24.5 V low, 32 V high) are halved automatically when the logs show a bus running below 18 V, so 14 V aircraft no longer flag low voltage on every flight.
- Early-warning thresholds for oil temperature, oil pressure and bus voltage come from the aircraft's own limits instead of fixed SR22 numbers. Mag-check and takeoff-RPM text uses the aircraft's limits and says "check your POH" on non-SR22 aircraft.
- Version 0.9.7 (40).

## 0.9.6 (2026-10-22)
- Cirrus G7: battery advice (low bus voltage, slow cranking, early warning) notes that battery 1 is a lithium-ion battery inside the instrument panel, not in the engine compartment, checked per the Cirrus maintenance manual and the battery maker (no lead-acid capacity tests or chargers).
- Removed notes specific to the first aircraft from every pilot's issue guides (injector nozzles past due on a Nov 2025 status sheet, leaks found at a Nov 2025 prebuy, Tornado Alley supplement wording); the guides now refer to the pilot's own POH/AFM and supplements.
- Version 0.9.6 (39).

## 0.9.5 (2026-10-22)
- No references to other companies' services: removed Savvy, FlySto, COPA (resources and "Ask COPA Commander", now "Copy a question for your A&P"), GAMI and GAMIjector (now "Lean test" and "fuel spread"), EzTrends, and the planned flyGarmin and AirSync partnership claims (AirSync is no longer offered as a data link). Avionics and engine-monitor brand names remain only to describe compatibility.
- Copyright: "© 2026 Engine Pulse LLC. All rights reserved." in the app (About, ACCOUNT) and on every website page, with a trademark notice. New ACCOUNT > Acknowledgements holds the open-source notices the JPI decoder's sources require. The repository has a proprietary LICENSE and THIRD-PARTY-NOTICES.md.
- Version 0.9.5 (38).
- Company name: Engine Pulse LLC (was Fueled Consulting LLC) in the app's About text and across the website (footers, Terms and Privacy Policy, effective October 22, 2026). Bundle and product IDs keep their com.fueledconsulting prefix: App Store Connect can't change them.

## 0.9.4 (2026-10-22)
- Sign in with Apple is off during the beta: "Hide My Email" created separate, empty accounts that didn't match the email used on the upload website. Email and password is the one sign-in everywhere.
- Website: enginepulse.net/start is a single page of setup steps for testers (install, register, bring in flights, POH, troubleshooting).
- Version 0.9.4 (37).

## 0.9.3 (2026-10-22)
- New Get started screen, shown right after registering and as a card on HOME until the first flight arrives: three ways to bring flights in (from a computer with the upload address, the pilot's own email and a one-click link; from an SD card or USB stick plugged into the iPad; from Garmin Pilot / flyGarmin), the download steps for the pilot's own monitor, a live flight count and a "Check for my flights" button that says exactly what it found.
- Version 0.9.3 (36).

## 0.9.2 (2026-10-21)
- Fix: flights uploaded on the website reached only the first device that opened the app, and were never saved to the account, so a pilot's other iPad or iPhone (or a reinstall) showed no flights. Every device now brings in every uploaded engine log, and new flights are saved to the account straight after they come in.
- Fix: when a different account signs in on a device, the previous account's flights and records are cleared from the device first, so two pilots' data can never mix or upload into the wrong account.
- Deleting a flight in DIAGNOSTICS > Flight Logs now deletes it from the account too, so it isn't restored again.
- MY FLYING: speeds are graded against each aircraft's own POH speeds (AIRCRAFT > Technique speeds; SR22s start with SR22 POH 4-3 values). Without them, only sink, bank, float and takeoff power are graded. Before, every aircraft was judged against SR22 speeds.
- MY FLYING shows why it's empty: no flights yet (with the signed-in email and a "Check for uploaded flights now" button), or flights from an engine-only monitor that records no airspeed or altitude.
- Version 0.9.2 (35).

## 0.9.1 (2026-10-21)
- Simpler Register screen: one password field (with Show password), make, model, tail and avionics. Data link and the data checklist are set up after registering.
- Delete uploads: in AIRCRAFT > Documents and uploads, swipe left on a file (or touch and hold) to delete it, for example a POH uploaded twice. The POH copy read on the iPad goes too.
- Uploading the same document again is refused with a note, so duplicates don't pile up.
- Admin: ACCOUNT > Beta testers lists every account with sign-in, aircraft, flight and upload counts (accounts listed in app_admins only; counts, never file contents).
- Website: sign-up page is now three steps (get the app from TestFlight with a QR code, register in the app, add flights); creating the account on the website is optional. The upload page takes a whole data_log folder, files engine logs into the logs box wherever they're dropped, skips files already uploaded, and has Delete on each file.
- Database: run schema.sql again for Beta testers (admin functions).
- Version 0.9.1 (34).

## 0.9.0 (2026-10-20)
- Engine monitors beyond Garmin. Every import is converted to the Garmin layout the analysis uses, so every monitor gets the same reports, early warning and cloud sync:
  - J.P. Instruments EDM downloads (.JPI and older .DAT): every flight in the file is added. Checked value for value against JPI's own export of a sample EDM-830 download.
  - JPI EzTrends / EZSave CSV exports.
  - Garmin G3X Touch, G3000, G500 / G600 TXi and GI 275 CSV logs (G3X header layout, Volts1 / Amps1 and m/d/yy dates).
  - Electronics International MVP / CGR, Dynon SkyView / HDX, Avidyne Entegra R9 (C_ENGINE.CSV), GRT, AFS, MGL and other CSV engine logs: columns recognised by name, °C converted to °F, fuel flow to gal/h, time from the file, its header or its name.
- Logs without airspeed (JPI, most EI) get engine-only flight phases: run-up and taxi, climb (full power), cruise and descent.
- Website uploads saved earlier as "not readable yet" (JPI files) are imported now.
- Avionics list: G3000, Dynon, GRT, AFS, MGL and Insight added, each with its own download steps in setup and the data checklist.
- Aircraft list: about 110 piston models across 30 makes (Cessna, Piper, Beechcraft, Mooney, Diamond, Cirrus by generation, Grumman, Commander, Socata, Maule, Van's and other kits), split by year where the factory avionics changed, each suggesting its usual avionics. Registration picks the make, then the model.
- Version 0.9.0 (33).

## 0.8.7 (2026-10-20)
- New avionics choice: Cirrus Perspective Touch+ (G7). Its SD-card data logs import like Perspective+, and the GDL 60 / Flight Stream 510 advice and Garmin guide cover it (tester feedback).
- Perspective+ now reads "Cirrus Perspective+ (G6)". Profiles saved with the old combined G6 / G7 name still open as Perspective+.
- Registration lists Cirrus by generation: SR20, SR22 and SR22T in G6 and G7, each with the right avionics filled in.
- Version 0.8.7 (32).

## 0.8.6 (2026-10-20)
- Aircraft transfer for a sale. The owner enters the buyer's email and cell number (ACCOUNT > Aircraft ownership, or AIRCRAFT), types the tail number to confirm, and the app texts the buyer a transfer code and emails the steps. The buyer signs in with that email and accepts with the code and their cell number (ACCOUNT > Accept a transfer). Flights and engine analysis, the locked profile, maintenance, issue reviews, event markers and uploaded documents move to the buyer's account.
- The code expires after 14 days, only its hash is stored, and five wrong tries cancel the transfer. The seller can cancel until the buyer accepts.
- After the sale the seller's devices pause syncing and offer to remove the aircraft, ready for the next one.
- Database: new aircraft_transfers table and accept function; file rules now follow row ownership, and rows can only point at files in the owner's own folder. Run schema.sql again in Supabase to switch it on.
- Version 0.8.6 (31).

## 0.8.5 (2026-10-20)
- New "Flights from Garmin" guide for GDL 60 and Flight Stream 510 owners (including Perspective+): share a flight from the Garmin Pilot logbook as CSV straight to Engine Pulse, or download Original CSV from flyGarmin and drop it on enginepulse.net/upload.
- The data-path advice for GDL 60 and Flight Stream 510 now gives these steps, with a data-card fallback note for Perspective+ over Flight Stream 510. The guide is also linked from Import Logs.
- Friendlier message when a CSV isn't an avionics engine log, asking the pilot to email it to sales@enginepulse.net so support can be added.
- Version 0.8.5 (30).

## 0.8.4 (2026-10-19)
- Contact email is now sales@enginepulse.net everywhere in the app (About, profile change requests and the unlock-code note), matching the website.
- Version 0.8.4 (29).

## 0.8.3 (2026-10-19)
- Wording: the landing page now reads "Engine monitoring for your aircraft", and registration no longer says piston aircraft only.
- Version 0.8.3 (28).

## 0.8.2 (2026-10-19)
- The paywall fetches the subscription from the App Store each time it opens, so price and free-trial changes show without restarting the app.
- Version 0.8.2 (27).

## 0.8.1 (2026-10-19)
- ACCOUNT: "See Engine Pulse Pro" and "Manage subscription" open reliably (the sheets now belong to the screen rather than the list section).
- Version 0.8.1 (26).

## 0.8.0 (2026-10-19)
- Engine Pulse Pro subscription (StoreKit 2): product com.fueledconsulting.enginepulse.monthly, $14.99 a month with the free-trial introductory offer set in App Store Connect. Paywall with what's included, trial and price read from the App Store, Restore Purchases, Manage subscription, Apple's renewal terms and links to Terms, Privacy and Apple's EULA.
- ACCOUNT shows the subscription status (trial, active, renews or ends), Manage subscription and Restore Purchases.
- During the beta the subscription is not required (Info.plist EMRequireSubscription = false); testers can still try buying in TestFlight (sandbox, not charged). Setting it to true locks the app behind the paywall when there is no active subscription or trial.
- Upload website, Terms and Privacy now point to enginepulse.net (/upload/, /terms/, /privacy/).
- Version 0.8.0 (25).

## 0.7.7 (2026-10-16)
- Everything syncs between devices, not just flights: maintenance items and service history, issue reviews and notes, and event markers are saved to the account (one app-state file) and pulled on every device when the app opens, comes to the front, or a few seconds after a change. Each part is last-change-wins.
- Aircraft profile (FIKI, serial, home airport, limits): the first time an account is restored on a device, the account's profile wins over values the device filled in from the POH; after that the newer one wins.
- Every device now uses the account's first aircraft, so a device that uploaded before restoring no longer ends up with its own separate copy.
- Records saved before this version are dated by their files, so they win over an empty device.
- Version 0.7.7 (24).

## 0.7.6 (2026-10-16)
- HOME early-warning dashboard: counts of open warnings, cautions, watch items and trends, then a row per key trend (any flagged trend first, the hottest cylinder's CHT, oil temperature and pressure, CHT and EGT spread, TIT gap, bus voltages) with a sparkline over its normal band, the latest value, the direction (orange when moving the bad way) and Normal / WATCH / ACT SOON. Each row opens its trend; "All trends and early warnings" opens the full view.
- Before the early-warning baseline exists (about 25 flights), the panel shows raw cruise values per flight instead.
- Version 0.7.6 (23).

## 0.7.5 (2026-10-16)
- The HOME gauge is now Engine HEALTH, scored from the last 10 flights themselves: each flight starts at 100 (warning -20, caution -8, watch -3), newer flights count more, and early-warning trends take 6 (15 if ACT SOON). Items waiting for review no longer lower it; they stay on the Open items tile.
- Status colour: green Healthy (85-100), yellow Watch (70-84), red Needs attention (below 70, a warning in the last 3 flights, or an ACT SOON trend). The pulse line and badge follow it.
- Trend arrow under the gauge: Improving, Steady or Declining, from the slope of the per-flight scores.
- Tap the gauge or badge for the breakdown: the score by flight on a chart, and exactly what took points off.
- Version 0.7.5 (22).

## 0.7.4 (2026-10-16)
- HOME is fully tappable: Flights analyzed opens DIAGNOSTICS, Engine hours opens MY FLYING, Open items and the health badge / Pulse score open the issue list, Oil change opens MAINTENANCE, and the trend card opens engine trends and early warnings. Tiles show a chevron and press down when tapped.
- Version 0.7.4 (21).

## 0.7.3 (2026-10-16)
- Same account on every device: after logging in on a new iPhone or iPad, the app adopts the account's aircraft, restores the aircraft profile (unless this device has a newer locked one) and downloads every flight not on the device yet.
- ACCOUNT now offers "Log in with email" and "Register" when signed out, not only Sign in with Apple, and explains that Apple's "Hide My Email" creates a separate account. Signing out returns to the landing page.
- Token refreshes run one at a time, so two screens refreshing together can no longer end a session.
- Version 0.7.3 (20).

## 0.7.2 (2026-10-16)
- POH and supplement cross-check: limits are read from the POH and from uploaded AFM supplements (for example the Tornado Alley turbonormalizer supplement) and compared line by line in Aircraft Profile: Match, Supplement governs, POH only or Supplement only, with the page of each. Where they differ the supplement value is used.
- New turbo limits read from the supplement or POH Section 9: TIT max and manifold pressure max. Both are locked like the other limits and checked after every flight.
- Version 0.7.2 (19).

## 0.7.1 (2026-10-16)
- Document checklist asks for nothing twice. The POH / AFM item is now the whole PDF including Section 9 supplements, and it covers the engine model, all limits and the turbo limits. It shows done once the POH has been read.
- The separate turbo item appears only when the POH and manuals read on the iPad don't contain the turbo limits.
- "Last annual and last oil change" also counts as done when both are recorded under MAINTENANCE.
- "Engine total time" replaces "engine model, total time and time since overhaul" (the model comes from the POH; overhaul only if there was one). Same changes on the registration checklist and the upload website.
- Version 0.7.1 (18).

## 0.7.0 (2026-10-16)
- New HOME screen, where the app now opens: a hero card with the tail number, a live pulse line colored by engine health, and an Engine Pulse score gauge (100 = nothing open; unreviewed warnings, cautions, watch items and overdue maintenance take points off).
- Tiles for flights analyzed, engine hours logged, open items and oil change status; the last flight with cruise CHT, oil temperature, oil pressure and fuel flow; a cruise CHT and oil temperature trend chart; what needs attention; a getting-set-up checklist; and quick actions (import flights, upload documents, AD check, ask).
- Version 0.7.0 (17).

## 0.6.9 (2026-10-16)
- Focused on engine monitoring: FLY and PROCEDURES are removed from the menu (and the procedures link in ASK). The app opens on DIAGNOSTICS. Your POH is still read for the aircraft profile limits, ASK search and issue guidance.
- Version 0.6.9 (16).

## 0.6.8 (2026-10-16)
- Aircraft Profile fills itself from the POH: engine model, cylinders, turbo, max RPM, overspeed, oil temperature max, oil pressure min / max / caution, CHT caution and max are read from Section 2, each showing its POH page.
- Required details lock once complete (automatically when the POH supplies them, or with "Everything matches my POH: lock the profile"). Locked values can't be edited; "Request a change" emails support, and a support code unlocks once.
- New AIRCRAFT > Airworthiness directives check: searches FAA ADs in the Federal Register for the model, engine family and propeller, with links, newest first, and "Mark reviewed with A&P". Links to the FAA DRS and Cirrus service bulletins.
- Version 0.6.8 (15).

## 0.6.7 (2026-10-16)
- Registration advice: Flight Stream 510 engine-data transfer now includes the GI 275 EIS (per Garmin), and says Perspective / Perspective+ are not on Garmin's list.
- Version 0.6.7 (14).

## 0.6.6 (2026-10-16)
- PROCEDURES and ASK now use the pilot's own POH. POH / AFM PDFs uploaded in the app or on the website are read on the iPad: page labels (3-17), sections, and the Section 3 / 3A emergency and abnormal checklists (from the PDF bookmarks, or from the checklist headings).
- Other manuals uploaded (for example a Garmin Perspective pilot's guide) are searchable in ASK alongside the POH, each result naming its manual and opening its page.
- PROCEDURES shows progress while a POH is read, "Load my POH from my uploads", and "Choose a POH PDF from Files".
- Version 0.6.6 (13).

## 0.6.5 (2026-10-16)
- Upload website is live at https://velvety-brigadeiros-12bd22.netlify.app. Documents and uploads now shows "Upload on our website", and "Email me an upload link" signs pilots straight in to it.
- Version 0.6.5 (12).

## 0.6.4 (2026-10-16)
- Documents and uploads is now a checklist of every document we need, each with its own Upload button, a Required / Recommended / Optional badge, and a received count with a green check. The header shows "X of Y required done". Files land in the right category automatically, matching the upload website's slots.
- Tail and serial number row links to Aircraft Profile (typed, not uploaded).
- Version 0.6.4 (11).

## 0.6.3 (2026-10-16)
- App renamed **Engine Pulse** everywhere: home-screen name, title, landing page, registration, account, reports and PDFs, the upload website, email templates and docs. App binary EnginePulse.app; bundle ID, module and repo unchanged.
- App icon and logo wordmark now read ENGINE PULSE.
- Version 0.6.3 (10).

## 0.6.2 (2026-10-16)
- Email confirmation and password reset use a 6-digit code typed into the app, so pilots never land on a dead web page. Register shows the code box right away; Log in shows it if the email isn't confirmed yet; Resend code.
- Forgot password: enter the emailed code and a new password in the app, then you're signed in.
- Email templates for Supabase in supabase/email-templates (confirm signup, reset password).
- Documents and uploads: "Email me an upload link" sends a one-click sign-in link that opens the upload website on the pilot's computer already signed in (works once the website is hosted and EMWebPortalURL is set).
- Version 0.6.2 (9).

## 0.6.1 (2026-10-16)
- Connected to the live Supabase project (dzihbnffnzixutfrdpai, West US): Register, Log in, Sign in with Apple, cloud sync, documents and the upload website now work. Anon (public) key only; row-level security protects data.
- Version 0.6.1 (8).

## 0.6.0 (2026-10-15)
- Register button now says why it is grey (accounts not switched on yet, or which field is missing).
- Upload website (`web/`): pilots sign in with the same account, see the data checklist, and drop logs and documents (POH limits, logbook entries, engine times, turbo, oil analysis, squawks). Tested in a headless browser against a stand-in backend.
- The app brings website uploads in automatically when it opens or returns to the front: engine-log CSVs become flights, documents are kept with the aircraft.
- New Documents and uploads screen (AIRCRAFT, and shown once right after registering): link to the website, upload from the iPad by category, list and preview everything uploaded.
- `inbox_uploads` gains a category and a `stored` status (RLS tests pass).
- `EMWebPortalURL` in Info.plist for the website address (blank until the site is live).
- Version 0.6.0 (7).

## 0.5.0 (2026-10-15)
- Getting data in without fuss:
  - One-tap SD card import (DIAGNOSTICS > Flight Logs > Import new flights from SD card): choose the data_log folder once, then each tap adds only new flights and skips ones already imported.
  - Open In / share sheet: engine log files shared from Files, Mail, AirDrop, Cirrus IQ or Garmin Pilot open in the app. Garmin CSV logs are analyzed right away; JPI and other formats are saved to the subscriber's cloud inbox until support arrives.
  - Cloud inbox (`inbox_uploads` table + `<user>/inbox/` files) ready for flyGarmin / PlaneSync, AirSync, email-in and web uploads; included in account deletion; RLS tests extended (ALL RLS TESTS PASSED).
- Registration asks for avionics / engine monitor and wireless data link (GDL 60, Flight Stream 510, Flight Stream 210, Cirrus IQ, AirSync, none) and shows the best way to get that aircraft's data in. The same advice is in Aircraft Profile.
- Flight Stream 210 is flagged as not carrying engine data; Flight Stream 510 only for G1000 NXi and TXi (per Garmin).
- More avionics choices: Perspective+, G1000 NXi, TXi, GI 275, Avidyne Entegra.
- Tests: data path advice, older profile decoding, SD folder de-duplication.
- Version 0.5.0 (6).

## 0.4.0 (2026-10-15)
- New landing page shown when the app opens: Register for AI Engine Monitoring, Log in to AI Engine Monitoring, Sign in with Apple, and Explore without an account; plus What it does, Why pilots use it, and About us.
- Registration: name, email, password; aircraft chosen from a drop-down (common single-engine piston models with Garmin glass, or Other) plus tail number, which fills the Aircraft Profile; a data checklist (required / recommended / optional) of what to gather; advisory acknowledgement.
- Log in with email and password, Forgot password (emailed reset link), and Sign in with Apple.
- Data checklist also under AIRCRAFT > Data checklist; ticks are kept on the device.
- Clearer error messages from the account server.
- Version 0.4.0 (5).

## 0.3.1 (2026-10-15)
- App renamed AI Engine Monitoring (briefly EngineAI): home-screen name, title, PDF and export wording; app binary EngineAI.app. Bundle ID, module and repo keep the EngineMonitoring name.
- Pre-shop report header now describes the owner's aircraft from the profile instead of a fixed SR22 line.
- Remaining SR22 / Tornado Alley wording in guidance, reports and COPA questions made aircraft-neutral.
- New app icon: gauge arc, pulse line, AI spark and an "ENGINE AI" wordmark, replacing the N63KA icon.
- Version 0.3.1 (4).

## 0.3.0 (2026-10-15)
- Cloud database (Supabase): `supabase/schema.sql` creates the `aircraft` and `flight_logs` tables, the private `engine-logs` file bucket, row-level security (each subscriber sees only their own data) and `delete_my_account()`. Tested on Postgres 16 with `supabase/tests` (ALL RLS TESTS PASSED). Setup steps: `supabase/README.md`.
- New ACCOUNT section: Sign in with Apple, cloud status, Sync now, sign out, delete account (App Store requirement), and restore of a saved aircraft profile on a new iPad.
- Automatic upload while signed in: the aircraft profile when you leave the profile screen, and each imported engine log (raw file plus its flight summary).
- Without the Supabase URL and anon key in Info.plist (`EMSupabaseURL`, `EMSupabaseAnonKey`) the app runs local-only.
- Sign in with Apple entitlement added (EngineMonitoring.entitlements); the App ID needs the Sign in with Apple capability.
- Removed the rest of N63KA: the tools folder (N63KA analysis scripts and data), N63KA logbook entries seeded into MAINTENANCE, SR22-specific tire pressures and oil quantities, owner name defaults, SharePoint wording, N63KA's avionics system ID in the test fixture, and the inherited N63KA changelog.
- Tests: CloudServiceTests (token parsing, row building, file paths, nonce).
- Version 0.3.0 (3).

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
