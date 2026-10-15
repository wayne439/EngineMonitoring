#!/bin/sh
# Rebuilds the bundled engine-data history (EngineMonitoring/Resources/Data/flight_history.json)
# from the SharePoint data_log folder, using the app's own summarizer and issue detector.
#
# 1. SharePoint > Cirrus > Engine Data > right-click data_log > Download, unzip it (e.g. ~/Downloads/data_log)
# 2. In Terminal, from the project folder:   sh tools/build_history.sh ~/Downloads/data_log
# 3. Rebuild the app in Xcode (raise the Build number) and upload to TestFlight.
set -e
LOGS="${1:?usage: sh tools/build_history.sh <data_log folder>}"
cd "$(dirname "$0")/.."
xcrun swiftc -O -o /tmp/n63ka_historygen \
  EngineMonitoring/Models/*.swift EngineMonitoring/Services/*.swift tools/historygen/main.swift
/tmp/n63ka_historygen "$LOGS" EngineMonitoring/Resources/Data/flight_history.json N63KA_Issue_History.md
python3 tools/n63ka_issues.py "$LOGS"/*.csv --register tools/issue-register.json --update > /tmp/n63ka_new_items.json && echo "New items: /tmp/n63ka_new_items.json"
echo "Updated EngineMonitoring/Resources/Data/flight_history.json and N63KA_Issue_History.md"
