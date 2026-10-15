import SwiftUI
import Charts

/// Everything recorded for one aircraft system: your markers and the history from every imported log.
/// Each row opens the marker's analysis or the flight's post-flight report.
struct SystemHistoryView: View {
    let system: DiagnosticSystem
    @EnvironmentObject private var eventStore: DiagnosticEventStore
    @EnvironmentObject private var logStore: FlightLogStore
    @EnvironmentObject private var issues: IssueStore

    /// Summaries newest first.
    private var flights: [FlightSummary] {
        logStore.summaries.values.sorted { $0.start > $1.start }
    }

    private var markers: [DiagnosticEvent] {
        eventStore.events.filter { $0.system == system }
    }

    var body: some View {
        List {
            Section {
                let groups = issues.groups(for: system).filter { $0.severity != .info }
                if groups.isEmpty { Text("No issues recorded for this system.").foregroundStyle(.secondary) }
                ForEach(groups) { group in
                    NavigationLink { IssueDetailView(kind: group.kind) } label: { IssueGroupRow(group: group) }
                }
                NavigationLink("All \(system.rawValue) issues, incl. resolved") { IssueHistoryView(system: system) }
            } header: {
                Text("Past Issues And How To Resolve")
            }

            Section {
                if markers.isEmpty {
                    Text("No markers for this system yet. Use Something Happened in flight.").foregroundStyle(.secondary)
                }
                ForEach(markers) { event in
                    NavigationLink {
                        DiagnosticEventDetail(eventID: event.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(EventTime.local(event)).font(.headline)
                            if !event.note.isEmpty { Text(event.note).lineLimit(2) }
                        }
                    }
                }
            } header: {
                Text("Your Markers (\(markers.count))")
            }

            historySections

            if logStore.entries.isEmpty && logStore.summaries.isEmpty {
                Section {
                    NavigationLink("Import Perspective Logs") { FlightLogsView() }
                } footer: {
                    Text("History appears here once logs are imported.")
                }
            } else if logStore.isSummarizing {
                Section { ProgressView("Reading logs…") }
            }

            Section {
                Text(system.evaluationSummary)
            } header: {
                Text("What Is Recorded")
            } footer: {
                Text("Recorded values only. Tap any flight for its full post-flight report. No cause is assigned.")
            }
        }
        .navigationTitle(system.rawValue)
        .refreshable { await logStore.refreshSummaries() }
    }

    @ViewBuilder
    private var historySections: some View {
        switch system {
        case .engineStart: engineStartHistory
        case .autopilot: autopilotHistory
        case .electrical: electricalHistory
        case .avionics: avionicsHistory
        case .engine: engineHistory
        case .other: EmptyView()
        }
    }

    // MARK: Engine / Start

    private struct StartRow: Identifiable {
        var id: String { "\(flight.filename)-\(record.time.timeIntervalSince1970)" }
        let flight: FlightSummary
        let record: StartRecord
        var caught: Bool { (record.rpmAfter30s ?? 0) >= 500 }
    }

    private var startRows: [StartRow] {
        flights.flatMap { f in f.starts.map { StartRow(flight: f, record: $0) } }.sorted { $0.record.time > $1.record.time }
    }

    @ViewBuilder
    private var engineStartHistory: some View {
        let rows = startRows
        if rows.count >= 2 {
            Section {
                Chart(rows.filter { $0.record.minVolt1 != nil }) { row in
                    PointMark(x: .value("Date", row.record.time), y: .value("Volts", row.record.minVolt1 ?? 0))
                        .foregroundStyle(row.caught ? Color.accentColor : Color.orange)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            } header: {
                Text("Lowest Bus 1 Voltage While Cranking")
            } footer: {
                Text("Orange = the engine caught but stopped within 30 s.")
            }
        }
        Section {
            ForEach(rows) { row in
                flightLink(row.flight) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.record.time.formatted(date: .abbreviated, time: .standard)).font(.headline)
                            Spacer()
                            Text(row.caught ? "Started" : "Stopped within 30 s")
                                .font(.caption.bold())
                                .foregroundStyle(row.caught ? Color.green : Color.orange)
                        }
                        Text(startDetail(row.record)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Engine Starts From Logs (\(rows.count))")
        }
    }

    private func startDetail(_ r: StartRecord) -> String {
        var parts: [String] = []
        if r.crankingEpisodes > 0 { parts.append("\(r.crankingEpisodes) cranking episode\(r.crankingEpisodes == 1 ? "" : "s") before") }
        if let v = r.minVolt1 { parts.append(String(format: "low %.1f V", v)) }
        if let ff = r.peakFuelFlow { parts.append(String(format: "peak FF %.1f gph", ff)) }
        if let w = r.weakestCylinder { parts.append(String(format: "smallest EGT rise cyl %ld +%.0f °F", w.cylinder, w.rise)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Autopilot

    @ViewBuilder
    private var autopilotHistory: some View {
        let withAP = flights.filter { !$0.afcsChanges.isEmpty }
        Section {
            if withAP.isEmpty && !flights.isEmpty { Text("No autopilot engagement recorded in the imported logs.").foregroundStyle(.secondary) }
            ForEach(withAP, id: \.filename) { f in
                flightLink(f) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text("\(f.afcsChanges.count - f.afcsDisengagements) engaged, \(f.afcsDisengagements) disengaged")
                            .font(.caption)
                        Text(f.afcsChanges.prefix(8).map { "\($0.time.formatted(date: .omitted, time: .shortened)) \($0.engaged ? "on" : "off")" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        } header: {
            Text("Autopilot Changes From Logs (\(withAP.count) flights)")
        } footer: {
            Text("The log records engaged/disengaged and the roll/pitch modes, not why a disconnect happened.")
        }
    }

    // MARK: Electrical

    @ViewBuilder
    private var electricalHistory: some View {
        let rows = flights.filter { $0.minVolt1Running != nil }
        if rows.count >= 2 {
            Section("Lowest Bus 1 Voltage With Engine Running") {
                Chart(rows, id: \.filename) { f in
                    PointMark(x: .value("Date", f.start), y: .value("Volts", f.minVolt1Running ?? 0))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            }
        }
        Section {
            ForEach(rows, id: \.filename) { f in
                flightLink(f) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text([f.minVolt1Running.map { String(format: "Bus 1 low %.1f V", $0) },
                              f.minVolt2Running.map { String(format: "Bus 2 low %.1f V", $0) },
                              f.largestVolt1Drop.map { String(format: "largest 1-s drop %.1f V", $0) }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Electrical From Logs (\(rows.count))")
        }
    }

    // MARK: Avionics

    @ViewBuilder
    private var avionicsHistory: some View {
        Section {
            ForEach(flights.filter(\.isFlight), id: \.filename) { f in
                flightLink(f) {
                    HStack {
                        Text(f.start.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(f.gpsFixLosses == 0 ? "GPS fix held" : "GPS fix lost \(f.gpsFixLosses)×")
                            .font(.caption.bold())
                            .foregroundStyle(f.gpsFixLosses == 0 ? Color.secondary : Color.orange)
                    }
                }
            }
        } header: {
            Text("GPS Fix In Flight")
        }
    }

    // MARK: Engine / In Flight

    @ViewBuilder
    private var engineHistory: some View {
        let rows = flights.filter { $0.stats[.cruise]?[.chtMax] != nil }
        if rows.count >= 2 {
            Section {
                Chart(rows, id: \.filename) { f in
                    PointMark(x: .value("Date", f.start), y: .value("°F", f.stats[.cruise]?[.chtMax]?.p50 ?? 0))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            } header: {
                Text("Cruise Hottest CHT (median per flight)")
            }
        }
        Section {
            ForEach(rows, id: \.filename) { f in
                flightLink(f) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text(cruiseDetail(f)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Cruise From Logs (\(rows.count))")
        }
    }

    private func cruiseDetail(_ f: FlightSummary) -> String {
        guard let c = f.stats[.cruise] else { return "" }
        let chts: [(Int, Double)] = [FlightMetric.cht1, .cht2, .cht3, .cht4, .cht5, .cht6].enumerated()
            .compactMap { i, m in c[m].map { (i + 1, $0.p50) } }
        let hottest = chts.max { $0.1 < $1.1 }
        var parts: [String] = []
        if let h = hottest { parts.append(String(format: "hottest cyl %ld %.0f °F", h.0, h.1)) }
        if let o = c[.oilTemp] { parts.append(String(format: "oil %.0f °F", o.p50)) }
        if let p = c[.oilPressure] { parts.append(String(format: "%.0f psi", p.p50)) }
        if let t = c[.tit] { parts.append(String(format: "TIT %.0f °F (target %.0f)", t.p50, AircraftKnowledge.cruiseTITTarget)) }
        if let o = c[.oat] { parts.append(String(format: "OAT %.0f °C", o.p50)) }
        if let d = f.departure { parts.append("from \(d)") }
        if let e = c[.egtSpread] { parts.append(String(format: "EGT spread %.0f °F", e.p50)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Helpers

    /// Opens the flight's post-flight report when its log is still imported.
    @ViewBuilder
    private func flightLink<Content: View>(_ f: FlightSummary, @ViewBuilder label: () -> Content) -> some View {
        if let entry = logStore.entry(named: f.filename) {
            NavigationLink {
                FlightReportView(entry: entry)
            } label: {
                label()
            }
        } else {
            NavigationLink {
                FlightSummaryView(summary: f)
            } label: {
                label()
            }
        }
    }
}
