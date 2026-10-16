# Engine Pulse changelog

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
