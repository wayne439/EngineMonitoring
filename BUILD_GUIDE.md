# N63KA Copilot v0.9.1 - Xcode Build Guide

Follow in order. If a step does not match what you see, stop and send Claude a screenshot.

## Before you start
- Xcode 15.3 or later (16 recommended): Xcode > About Xcode. Update from the Mac App Store if older.
- Xcode > Settings > Accounts: your Apple ID with team D64ZNA8J2P.
- Xcode > Settings > Platforms (or Components): iOS simulator installed.

## Step 1: Open the project
1. Unzip `N63KA_Copilot_v0.9.1.zip` and move the folder to e.g. Documents/Projects (not Downloads, not a synced OneDrive/iCloud folder).
2. Double-click `N63KACopilot.xcodeproj`. Click Trust and Open if asked. Wait for indexing to finish.

## Step 1b (optional): Add POH.pdf for "Open POH Page"
1. Download POH.pdf from SharePoint (Cirrus folder) to the Mac.
2. In Xcode's left sidebar, drag it into N63KACopilot > Resources (the Resources folder).
3. In the dialog: tick "Copy items if needed" and target "N63KACopilot". Click Finish.
Without it the POH text, search and procedures still work; only the page images are missing.

## Step 2: Build for the simulator
1. Top bar: choose an iPad simulator.
2. Press Cmd+B. Expect "Build Succeeded".
3. If there are red errors: Cmd+5 (Issue Navigator), copy each error to Claude, apply the fix, build again. Yellow warnings are fine.

## Step 3: Run the tests
1. Press Cmd+U. Cmd+6 opens the Test Navigator.
2. All 90 tests should be green. Send any failure to Claude.

## Step 4: Try the app in the simulator (Cmd+R)
- FLY > Approach Guides: open each of the 9 approaches (ILS, LOC, VOR, VOR/DME, LPV, LNAV/VNAV, LNAV, LNAV+V, LP); each opens the big-type flying card (tap a line when done; MISSED always visible); switch Autopilot / Hand-flown; 'All steps' opens the detailed version; printer prints a kneeboard card.
- FLY > One-Page Kneeboard Cards (PDF): tap a card (or All approach cards) - the PDF is made on the iPad and shows in about a second; switch Autopilot / Hand-flown; Share saves it to Files; printer prints it.
- MAINTENANCE: allow notifications when asked. All four items show "Not recorded yet". Open Tire pressure check > Record Check Result, enter nose 28 > it shows FAIL in red; record again with 32 > OK. Open Oil and filter change > Record It Done (date of your last change) > hours since change appear. Add a check or service > save > it appears in the list.
- MY FLYING: quality table (last 10 vs all), speed-over-the-fence chart, stable-at-300-ft by month, climb speed chart. Tap a landing: checks table and four profile charts. Switch the list to Takeoffs and open one.
- DIAGNOSTICS > Past Issues And How To Resolve: shows how many need review. Open Issue History (opens on Needs Review). Open "Engine catches, then stops": Review And Findings > Add Review > Monitoring, type what was discovered and what was done > Save. Back in the list it moves to Reviewed. Share button > Export Review Log shows the table.
- DIAGNOSTICS > Engine / Start (and the other areas): issues first, then your markers plus the history from every imported log; tap a row to open that flight's report.
- DIAGNOSTICS: Something Happened > Later > marker listed in orange; Edit Details saves; swipe to delete; share exports CSV.
- PROCEDURES: Section 3 and 3A lists; open "Engine Partial Power Loss" and check the steps read like the POH page 3-17.
- ASK N63KA: search "oil pressure" - first result is page 3-19.
- AIRCRAFT: facts, Limits, Oil analysis chart, watch list, COPA links; no red Build Check warning.
- Real log: download a log_*.csv from SharePoint Cirrus/Engine Data/data_log, drag it onto the simulator, save to On My iPad, then Diagnostics > Perspective Flight Logs > Import. Tap the log for its post-flight report. Import 5+ flights to see N63KA normal ranges.

## Step 5: Run on your iPad
1. Connect by cable, tap Trust.
2. iPad: Settings > Privacy & Security > Developer Mode > On (restart, confirm).
3. Xcode: choose the iPad as destination, Cmd+R.
4. Signing problem: target N63KACopilot > Signing & Capabilities > Debug > Automatically manage signing, Team D64ZNA8J2P.

## Step 6: TestFlight
1. App Store Connect > Apps: confirm an app with bundle ID com.fueledconsulting.N63KACopilot (create it with + > New App if missing).
2. Signing & Capabilities > Release: Automatically manage signing, Team D64ZNA8J2P.
3. General tab: Version 0.7.1, Build 11. Raise Build by 1 for every later upload.
4. Destination: Any iOS Device (arm64). Product > Archive.
5. Organizer > Distribute App > App Store Connect > Upload.
6. After processing (10-30 min): TestFlight > Internal Testing > add yourself; install via the TestFlight app on the iPad.

## Updating the issue history after new flights
1. Upload the new logs to SharePoint Cirrus/Engine Data/data_log as usual.
2. Download the data_log folder (right-click > Download) and unzip it.
3. Terminal, in the project folder: `sh tools/build_history.sh ~/Downloads/data_log`
4. Raise Build by 1, Archive, upload. (Or ask Claude to rebuild it.) Logs imported on the iPad are analyzed automatically in the meantime.

## Quick fixes
- Strange errors after moving folders: Product > Clean Build Folder (Shift+Cmd+K).
- Duplicate build number on upload: raise Build, archive again.
- iPad not listed: unlock, Trust, Developer Mode, reconnect.
