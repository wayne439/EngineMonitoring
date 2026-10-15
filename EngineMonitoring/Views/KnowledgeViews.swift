import SwiftUI
import Charts
import UIKit

// MARK: - AIRCRAFT

struct AircraftView: View {
    @EnvironmentObject private var logStore: FlightLogStore
    @EnvironmentObject private var repository: DocumentRepository
    @EnvironmentObject private var aircraft: AircraftProfileStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AircraftProfileView()
                } label: {
                    if aircraft.needsSetup {
                        Label("Set up your aircraft profile", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Edit aircraft profile", systemImage: "pencil")
                    }
                }
                ForEach(AircraftKnowledge.facts) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label).font(.caption).foregroundStyle(.secondary)
                        Text(fact.value)
                        Text(fact.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(aircraft.profile.displayName)
            } footer: {
                Text("From your aircraft profile. Limits come from your POH/AFM; the app never replaces them.")
            }

            Section("Engine Data") {
                NavigationLink {
                    NormalRangesView()
                } label: {
                    LabeledContent("Normal ranges", value: "\(logStore.baseline().flightCount) flights")
                }
                NavigationLink {
                    FlightLogsView()
                } label: {
                    LabeledContent("Imported engine logs", value: "\(logStore.entries.count)")
                }
                NavigationLink {
                    LimitsView()
                } label: {
                    Text("Limits and references checked after each flight")
                }
                NavigationLink {
                    OilAnalysisView()
                } label: {
                    LabeledContent("Oil analysis", value: "\(AircraftKnowledge.oilSamples.count) samples")
                }
            }

            if !AircraftKnowledge.watchList.isEmpty {
            Section {
                ForEach(AircraftKnowledge.watchList) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.item).font(.headline)
                        Text(item.detail)
                        Text(item.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Maintenance Watch List")
            } footer: {
                Text("Questions raised by the records. Confirm each with your A&P; some may already be closed.")
            }
            }

            OnlineResourcesSection()

            let missing = repository.missingDocuments()
            if !missing.isEmpty {
                Section("Build Check") {
                    Label("\(missing.count) catalog document(s) missing from this build", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    ForEach(missing) { Text($0.bundledFilename ?? $0.title).font(.caption) }
                }
            }
        }
        .navigationTitle("AIRCRAFT")
    }
}

struct OnlineResourcesSection: View {
    var body: some View {
        if !AircraftKnowledge.onlineResources.isEmpty {
        Section {
            ForEach(AircraftKnowledge.onlineResources) { resource in
                if let url = URL(string: resource.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(resource.title).font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                            Text(resource.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Online Resources")
        } footer: {
            Text("Need internet, so not available in flight. COPA content is community and training material, not approved data.")
        }
        }
    }
}

struct LimitsView: View {
    var body: some View {
        List {
            Section {
                ForEach(AircraftKnowledge.limits.filter { $0.authority == .approved }) { limit in
                    LimitRow(limit: limit)
                }
            } header: {
                Text("Limits - from your POH/AFM")
            } footer: {
                Text("Set in Aircraft Profile. Until you confirm them there, these are template values and must be checked against your own POH/AFM.")
            }
            Section {
                ForEach(AircraftKnowledge.limits.filter { $0.authority != .approved }) { limit in
                    LimitRow(limit: limit)
                }
            } header: {
                Text("Technique References")
            } footer: {
                Text("Technique references you set in Aircraft Profile. Shown as notes, never as limits.")
            }
        }
        .navigationTitle("Limits")
    }
}

private struct LimitRow: View {
    let limit: AircraftKnowledge.EngineLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AuthorityBadge(authority: limit.authority)
                Text(limit.kind.rawValue).font(.caption.bold()).foregroundStyle(limit.kind == .warning ? Color.red : Color.orange)
            }
            Text(limit.label)
            Text(limit.source).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Normal ranges

struct NormalRangesView: View {
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var phase: FlightPhase = .cruise

    var body: some View {
        let baseline = logStore.baseline()
        List {
            Section {
                Picker("Phase", selection: $phase) {
                    ForEach(FlightPhase.compared, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Learned from \(baseline.flightCount) imported flights: the middle 80% of each flight's median value. A new flight outside these ranges is flagged in its report.")
            }

            if baseline.flightCount < Baseline.minimumFlights {
                Section {
                    Label("Import at least \(Baseline.minimumFlights) flights to learn this aircraft's normal ranges (\(baseline.flightCount) so far).",
                          systemImage: "info.circle")
                }
            }

            Section(phase.rawValue) {
                ForEach(FlightMetric.allCases, id: \.self) { metric in
                    if let r = baseline.ranges[phase]?[metric] {
                        LabeledContent(metric.label) {
                            Text("\(metric.format(r.low)) - \(metric.format(r.high))")
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await logStore.refreshSummaries() }
                } label: {
                    if logStore.isSummarizing { ProgressView() } else { Text("Rebuild From All Logs") }
                }
                .disabled(logStore.isSummarizing)
            }
        }
        .navigationTitle("Normal Ranges")
    }
}

// MARK: - Oil analysis

struct OilAnalysisView: View {
    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let element: String
        let ppm: Double
    }

    private var points: [Point] {
        AircraftKnowledge.oilSamples.flatMap { s -> [Point] in
            guard let d = KnowledgeDocument.dayFormatter.date(from: s.date) else { return [] }
            return [Point(date: d, element: "Nickel", ppm: s.nickel),
                    Point(date: d, element: "Chromium", ppm: s.chromium),
                    Point(date: d, element: "Iron", ppm: s.iron)]
        }
    }

    var body: some View {
        List {
            Section {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("ppm", p.ppm))
                        .foregroundStyle(by: .value("Element", p.element))
                    PointMark(x: .value("Date", p.date), y: .value("ppm", p.ppm))
                        .foregroundStyle(by: .value("Element", p.element))
                }
                .frame(height: 220)
                .padding(.vertical, 8)
            } header: {
                Text("Wear Metals (ppm)")
            } footer: {
                Text(points.isEmpty ? "No oil analysis results yet. Entering lab results comes in a later version."
                     : "General nickel alert guide: \(Int(AircraftKnowledge.oilAlertGuide["Nickel"] ?? 0)) ppm. Your lab's report is the reference.")
            }

            Section("Samples") {
                ForEach(AircraftKnowledge.oilSamples.reversed()) { s in
                    VStack(alignment: .leading) {
                        Text(s.date).font(.headline)
                        Text("Fe \(Int(s.iron))  Cu \(Int(s.copper))  Ni \(Int(s.nickel))  Cr \(Int(s.chromium))  Al \(Int(s.aluminum))  Si \(Int(s.silicon))")
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Oil Analysis")
    }
}

// MARK: - Post-flight report

struct FlightReportView: View {
    let entry: FlightLogEntry
    @EnvironmentObject private var logStore: FlightLogStore
    @EnvironmentObject private var eventStore: DiagnosticEventStore
    @Environment(\.openURL) private var openURL
    @State private var report: FlightReport?
    @State private var loading = true
    @State private var copied = false

    var body: some View {
        List {
            if loading {
                ProgressView("Analyzing flight…")
            } else if let report {
                content(report)
            } else {
                Text("This log could not be read.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Post-Flight Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let report {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: report.markdown(), subject: Text("Post-flight report"),
                              preview: SharePreview("Post-flight report")) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            report = await logStore.report(for: entry, markers: eventStore.events)
            loading = false
        }
    }

    @ViewBuilder
    private func content(_ report: FlightReport) -> some View {
        Section("Flight") {
            LabeledContent("Log", value: entry.originalFilename)
            LabeledContent("Start", value: report.summary.start.formatted(date: .abbreviated, time: .shortened))
            ForEach(FlightPhase.allCases, id: \.self) { phase in
                if let s = report.summary.phaseSeconds[phase], s >= 60 {
                    LabeledContent(phase.rawValue, value: "\(s / 60) min")
                }
            }
        }

        FlightTechniqueSection(summary: report.summary)

        Section {
            if report.approvedExceedances.isEmpty {
                Label("No recorded value outside the POH limits the app checks.", systemImage: "checkmark.circle")
            }
            ForEach(report.approvedExceedances, id: \.self) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(e.limit.kind.rawValue): \(e.limit.label)").font(.headline)
                        .foregroundStyle(e.limit.kind == .warning ? Color.red : Color.orange)
                    Text("\(e.seconds) s, first at \(e.first.formatted(date: .omitted, time: .standard)); extreme \(e.limit.metric.format(e.extreme))")
                    Text(e.limit.source).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("POH Limits (Approved)")
        } footer: {
            Text("TIT and manifold-pressure limits are not checked until the Tornado Alley supplement is loaded.")
        }

        Section {
            if report.baselineFlights < Baseline.minimumFlights {
                Text("Needs \(Baseline.minimumFlights) earlier flights (\(report.baselineFlights) so far).").foregroundStyle(.secondary)
            } else if report.deviations.isEmpty {
                Label("Climb and cruise values are within this aircraft's usual ranges.", systemImage: "checkmark.circle")
            }
            ForEach(report.deviations, id: \.self) { d in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(d.phase.rawValue): \(d.metric.label)").font(.headline)
                    Text("Median \(d.metric.format(d.value)), \(d.direction) the usual \(d.metric.format(d.range.low)) - \(d.metric.format(d.range.high))")
                    Text("\(d.range.flights) earlier flights").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Compared With This Aircraft's Normal")
        }

        ValveWatchSection(result: report.summary.valveWatch)

        ProbeCheckSection(result: report.summary.probeCheck, timeZone: report.timeZone)

        EngineChecksSection(result: report.summary.engineChecks, timeZone: report.timeZone)

        ReportCardSection(summary: report.summary, summaries: Array(logStore.summaries.values))

        if let ew = report.earlyWarning {
            Section {
                NavigationLink {
                    EarlyWarningView()
                } label: {
                    EarlyWarningRow(report: ew)
                }
            } header: {
                Text("Early Warning (All Flights)")
            }
        }

        if let series = report.cylinderSeries {
            FlightCylinderCharts(series: series)
        }

        if !report.techniqueNotes.isEmpty {
            Section("Technique References (Not Limits)") {
                ForEach(report.techniqueNotes, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.limit.label)
                        Text("\(e.seconds) s, peak \(e.limit.metric.format(e.extreme)) - \(e.limit.source)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        if !report.markers.isEmpty {
            Section("Your Event Markers") {
                ForEach(report.markers) { m in
                    NavigationLink {
                        DiagnosticEventDetail(eventID: m.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(m.detailsEntered ? m.system.rawValue : "Marker").font(.headline)
                            Text(m.timestamp.formatted(date: .omitted, time: .standard)).font(.caption)
                        }
                    }
                }
            }
        }

        Section {
            Button {
                UIPasteboard.general.string = copaQuestion(report)
                copied = true
                if let url = URL(string: "https://commander.copa.fyi") { openURL(url) }
            } label: {
                Label(copied ? "Question copied - paste it in COPA Commander" : "Ask COPA Commander (copies a question)",
                      systemImage: "bubble.left.and.text.bubble.right")
            }
        } header: {
            Text("Get a Second Opinion (Online)")
        } footer: {
            Text("Share the report to SharePoint for the Claude post-flight review, or ask COPA. Community answers are not approved data.")
        }
    }

    private func copaQuestion(_ report: FlightReport) -> String {
        let findings = (report.approvedExceedances.map { $0.limit.label }
                        + report.deviations.prefix(3).map { "\($0.phase.rawValue) \($0.metric.label) \($0.metric.format($0.value)) vs usual \($0.metric.format($0.range.low))-\($0.metric.format($0.range.high))" })
        let topic = findings.isEmpty ? "Reviewing a normal flight's engine data" : "Engine data after a flight"
        return AircraftKnowledge.copaQuestion(about: topic, details: findings.isEmpty ? "No exceedances." : findings.joined(separator: "; ") + ".")
    }
}

// MARK: - ASK (offline search across the POH and the aircraft profile)

struct AskView: View {
    @EnvironmentObject private var poh: POHRepository
    @State private var query = ""

    private var recordHits: [AircraftKnowledge.Fact] {
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard !terms.isEmpty else { return [] }
        let facts = AircraftKnowledge.facts + AircraftKnowledge.watchList.map {
            AircraftKnowledge.Fact(label: $0.item, value: $0.detail, source: $0.source)
        }
        return facts.filter { f in
            let text = (f.label + " " + f.value).lowercased()
            return terms.contains { text.contains($0) }
        }
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    Label("Search the full POH and this aircraft's records. Works offline.", systemImage: "magnifyingglass")
                    Text("Try: oil pressure, alternator, partial power, CHT, CAPS, icing")
                        .foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink {
                        ProceduresView()
                    } label: {
                        Label("Emergency and Abnormal Procedures", systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    Text("AI answers are off on this iPad (on-device AI needs an M-series or A17 Pro iPad). Search shows the POH's own words with page numbers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                let hits = poh.search(query)
                Section("POH (\(hits.count))") {
                    if hits.isEmpty { Text("No POH page contains all of those words.").foregroundStyle(.secondary) }
                    ForEach(hits) { hit in
                        NavigationLink {
                            POHPageView(page: hit.page, highlight: query)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page \(hit.page.label) - \(hit.page.section)").font(.headline)
                                Text(hit.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
                if !recordHits.isEmpty {
                    Section("Aircraft Profile") {
                        ForEach(recordHits) { fact in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.label).font(.headline)
                                Text(fact.value)
                                Text(fact.source).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                OnlineResourcesSection()
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search POH and records")
        .autocorrectionDisabled()
        .navigationTitle("ASK")
    }
}

/// Valve watch result for one flight (ValveWatch).
struct ValveWatchSection: View {
    let result: ValveWatchResult?

    var body: some View {
        Section {
            if let result, result.checked {
                if result.flagged.isEmpty {
                    Label("No cylinder showed the slow EGT cycle of a leaking exhaust valve (\(result.steadyWindows) steady cruise windows).",
                          systemImage: "checkmark.circle")
                }
                ForEach(result.flagged, id: \.cylinder) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WATCH: Cylinder \(c.cylinder)").font(.headline).foregroundStyle(.orange)
                        Text(String(format: "EGT cycling about %.0f °F every %.0f s, %.1fx the other cylinders, in %ld of %ld windows",
                                    c.largestCycle ?? 0, c.periodSeconds ?? 0, c.dominance ?? 0, c.hitWindows, result.steadyWindows))
                        Text("If it repeats on other flights, ask the A&P to borescope cylinder \(c.cylinder). See Issues for likely causes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if result == nil {
                Text("Not checked yet for this log.").foregroundStyle(.secondary)
            } else {
                Text("No steady cruise of 8 minutes or more, so the valves were not checked.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Valve Watch (Exhaust Valves)")
        } footer: {
            Text("Looks for one cylinder's EGT cycling about once a minute in steady cruise. \(ValveWatch.source). Advisory only.")
        }
    }
}

/// Valve watch across every flight (bundled history and imported logs).
struct ValveWatchOverview {
    /// Flights with at least one steady cruise window, newest first.
    let checked: [FlightSummary]
    /// Flights without 8 minutes of steady cruise, or summaries from before v0.9.3.
    let notChecked: Int

    init(_ summaries: [FlightSummary]) {
        let flights = summaries.filter(\.isFlight)
        checked = flights.filter { $0.valveWatch?.checked == true }.sorted { $0.start > $1.start }
        notChecked = flights.count - checked.count
    }

    var windows: Int { checked.reduce(0) { $0 + ($1.valveWatch?.steadyWindows ?? 0) } }

    /// Cylinder -> number of flights on which it was flagged.
    var flaggedCylinders: [Int: Int] {
        var out: [Int: Int] = [:]
        for s in checked { for c in s.valveWatch?.flagged ?? [] { out[c.cylinder, default: 0] += 1 } }
        return out
    }

    /// Typical (median) and largest single-cylinder EGT cycle for one cylinder across all checked flights.
    func cycleRange(_ cylinder: Int) -> String {
        let v = checked.compactMap { $0.valveWatch?.cylinders.first { $0.cylinder == cylinder }?.largestCycle }.sorted()
        guard let top = v.last else { return "-" }
        return String(format: "%.0f °F typical · %.0f °F max", v[v.count / 2], top)
    }
}

/// One-line valve watch status (DIAGNOSTICS).
struct ValveWatchRow: View {
    let overview: ValveWatchOverview

    var body: some View {
        LabeledContent {
            let flagged = overview.flaggedCylinders.keys.sorted()
            if flagged.isEmpty {
                Text("\(overview.checked.count) flights · none flagged").foregroundStyle(.secondary)
            } else {
                Text(flagged.map { "Cyl \($0)" }.joined(separator: ", ")).foregroundStyle(.orange)
            }
        } label: {
            Label("Valve Watch", systemImage: "waveform.path")
        }
    }
}

/// Valve watch results for every flight.
struct ValveWatchHistoryView: View {
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        let o = ValveWatchOverview(Array(logStore.summaries.values))
        List {
            Section {
                LabeledContent("Flights checked", value: "\(o.checked.count)")
                LabeledContent("Steady cruise windows", value: "\(o.windows)")
                if o.notChecked > 0 {
                    LabeledContent("Flights not checked", value: "\(o.notChecked)")
                }
                let flagged = o.flaggedCylinders.keys.sorted()
                if flagged.isEmpty {
                    Label("No cylinder has shown the early exhaust-valve sign.", systemImage: "checkmark.circle")
                }
                ForEach(flagged, id: \.self) { c in
                    NavigationLink {
                        IssueDetailView(kind: "valve.cyl\(c)")
                    } label: {
                        Text("WATCH: Cylinder \(c) on \(o.flaggedCylinders[c] ?? 0) flight(s)").foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("All Flights")
            } footer: {
                Text("Looks for one cylinder's EGT cycling about once a minute, 30 °F or more, in 8-minute stretches of steady cruise. Flights not checked had no steady cruise that long. \(ValveWatch.source). Advisory only.")
            }

            Section {
                ForEach(1...6, id: \.self) { c in
                    LabeledContent("Cylinder \(c)", value: o.cycleRange(c))
                }
            } header: {
                Text("Largest Single-Cylinder EGT Cycle")
            } footer: {
                Text("Per flight: typical and largest. The watch threshold is 30 °F.")
            }

            Section("Flights (Newest First)") {
                ForEach(o.checked, id: \.filename) { s in
                    NavigationLink {
                        FlightSummaryView(summary: s)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.start.formatted(date: .abbreviated, time: .shortened) + (s.departure.map { " · \($0)" } ?? ""))
                                .font(.headline)
                            if let vw = s.valveWatch {
                                if vw.flagged.isEmpty {
                                    let top = vw.cylinders.max { ($0.largestCycle ?? 0) < ($1.largestCycle ?? 0) }
                                    Text(String(format: "No valve sign · largest cycle %.0f °F (cyl %ld) · %ld windows",
                                                top?.largestCycle ?? 0, top?.cylinder ?? 0, vw.steadyWindows))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("WATCH: " + vw.flagged.map { "cylinder \($0.cylinder)" }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Valve Watch")
    }
}

/// Probe and wiring check for one flight (ProbeCheck).
struct ProbeCheckSection: View {
    let result: ProbeCheckResult?
    var timeZone: TimeZone = .current

    var body: some View {
        Section {
            if let result, result.checked {
                if result.faults.isEmpty {
                    Label("\(result.channelsChecked) sensors checked: no dropouts, spikes, jumps, stuck or off-scale readings.",
                          systemImage: "checkmark.circle")
                }
                ForEach(result.faultyChannels, id: \.self) { ch in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WATCH: \(ProbeCheck.label(ch))").font(.headline).foregroundStyle(.orange)
                        ForEach(result.faults.filter { $0.channel == ch }, id: \.self) { f in
                            Text("\(f.kind.label): " + ProbeCheck.describe(f, timeZone: timeZone)).font(.callout)
                        }
                        Text("Check the probe, clamp, connector and wiring. See Issues for likely causes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if result == nil {
                Text("Not checked yet for this log.").foregroundStyle(.secondary)
            } else {
                Text("Engine not running long enough to check.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Probes And Wiring")
        } footer: {
            Text("EGT, CHT, TIT and oil sensors: readings a running engine cannot produce point to the probe or wiring, not the engine.")
        }
    }
}

/// Probe and wiring check across every flight.
struct ProbeOverview {
    let checked: [FlightSummary]

    init(_ summaries: [FlightSummary]) {
        checked = summaries.filter { $0.probeCheck?.checked == true }.sorted { $0.start > $1.start }
    }

    var withFaults: [FlightSummary] { checked.filter { !($0.probeCheck?.faults.isEmpty ?? true) } }

    struct ChannelCount: Hashable {
        let channel: String
        let flights: Int
    }

    /// Channels with a fault, and on how many flights.
    var faultyChannels: [ChannelCount] {
        ProbeCheck.channels.compactMap { ch -> ChannelCount? in
            let n = checked.filter { $0.probeCheck?.faults.contains { $0.channel == ch } == true }.count
            return n > 0 ? ChannelCount(channel: ch, flights: n) : nil
        }
    }
}

struct ProbeRow: View {
    let overview: ProbeOverview

    var body: some View {
        LabeledContent {
            let bad = overview.faultyChannels
            if bad.isEmpty {
                Text("\(overview.checked.count) logs · no faults").foregroundStyle(.secondary)
            } else {
                Text(bad.map { ProbeCheck.label($0.channel) }.joined(separator: ", ")).foregroundStyle(.orange)
            }
        } label: {
            Label("Probes & Wiring", systemImage: "cable.connector")
        }
    }
}

struct ProbeHistoryView: View {
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        let o = ProbeOverview(Array(logStore.summaries.values))
        List {
            Section {
                LabeledContent("Logs checked", value: "\(o.checked.count)")
                LabeledContent("Logs with a sensor fault", value: "\(o.withFaults.count)")
                if o.faultyChannels.isEmpty {
                    Label("No probe or wiring faults found in any log.", systemImage: "checkmark.circle")
                }
                ForEach(o.faultyChannels, id: \.channel) { item in
                    NavigationLink {
                        IssueDetailView(kind: ProbeCheck.issueKind(item.channel))
                    } label: {
                        Text("WATCH: \(ProbeCheck.label(item.channel)) on \(item.flights) log(s)").foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("All Logs")
            } footer: {
                Text("Checks every EGT, CHT, TIT and oil sensor for blanks, one-second spikes, jumps that only one cylinder makes, stuck readings, off-scale readings and readings far from the other cylinders.")
            }

            if !o.withFaults.isEmpty {
                Section("Logs With Faults (Newest First)") {
                    ForEach(o.withFaults, id: \.filename) { s in
                        NavigationLink {
                            FlightSummaryView(summary: s)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text((s.probeCheck?.faultyChannels ?? []).map(ProbeCheck.label).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Probes & Wiring")
    }
}
