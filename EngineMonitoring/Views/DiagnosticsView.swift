import SwiftUI
import Charts
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @EnvironmentObject private var eventStore: DiagnosticEventStore
    @EnvironmentObject private var logStore: FlightLogStore
    @EnvironmentObject private var issues: IssueStore
    /// Event just marked; its details sheet opens after the timestamp is already saved.
    @State private var newlyMarked: DiagnosticEvent?
    @State private var markCount = 0

    /// The most important open issues, shown right on the Diagnostics screen.
    private var topIssues: [IssueGroup] {
        Array(issues.groups.filter(\.needsReview).prefix(4))
    }

    var body: some View {
        List {
            Section {
                Button {
                    // Timestamp is captured HERE, at the tap, before anything else happens.
                    newlyMarked = eventStore.markNow()
                    markCount += 1
                } label: {
                    Label("Something Happened", systemImage: "exclamationmark.circle.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .accessibilityHint("Saves the current time as an event marker. Details can be added later.")
            } footer: {
                Text("One tap saves the time immediately. Add details now or after landing; the marker is kept either way.")
            }

            Section {
                NavigationLink {
                    IssueHistoryView()
                } label: {
                    LabeledContent {
                        if issues.isBuilding && issues.groups.isEmpty { ProgressView() } else { Text("\(issues.needsReviewCount) need review").foregroundStyle(issues.needsReviewCount > 0 ? Color.orange : Color.secondary) }
                    } label: {
                        Label("Issue History", systemImage: "list.bullet.clipboard").font(.headline)
                    }
                }
                ForEach(topIssues) { group in
                    NavigationLink {
                        IssueDetailView(kind: group.kind)
                    } label: {
                        IssueGroupRow(group: group)
                    }
                }
            } header: {
                Text("Past Issues And How To Resolve")
            } footer: {
                Text("From every engine log you import and your maintenance records. Every WARNING, CAUTION and WATCH item stays here until it is reviewed; new occurrences bring it back.")
            }

            Section {
                NavigationLink {
                    EarlyWarningView()
                } label: {
                    EarlyWarningRow(report: EarlyWarning.analyze(Array(logStore.summaries.values)))
                }
                NavigationLink {
                    ValveWatchHistoryView()
                } label: {
                    ValveWatchRow(overview: ValveWatchOverview(Array(logStore.summaries.values)))
                }
                NavigationLink {
                    ProbeHistoryView()
                } label: {
                    ProbeRow(overview: ProbeOverview(Array(logStore.summaries.values)))
                }
                EngineChecksRows()
            } header: {
                Text("Engine Analysis")
            } footer: {
                Text("Valve watch: every flight is checked for the early sign of a leaking exhaust valve (one cylinder's EGT cycling about once a minute in steady cruise). Probes & wiring: every sensor is checked for readings a running engine cannot produce. Early warning & trends: every value followed across flights, warning when one starts to drift before it becomes a problem. Report card: every flight's numbers against all earlier flights. Run-up mag check, lean test, turbo & induction checks, and a one-page report for your A&P.")
            }

            Section("Diagnostic Areas") {
                ForEach(DiagnosticSystem.allCases.filter { $0 != .other }) { system in
                    NavigationLink {
                        DiagnosticSystemView(system: system)
                    } label: {
                        LabeledContent {
                            let n = issues.groups(for: system).filter(\.needsReview).count
                            if n > 0 { Text("\(n) to review").foregroundStyle(.orange) }
                        } label: {
                            Label(system.rawValue, systemImage: system.icon)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    FlightLogsView()
                } label: {
                    LabeledContent {
                        Text("\(logStore.entries.count)")
                    } label: {
                        Label("Perspective Flight Logs", systemImage: "doc.text.magnifyingglass")
                    }
                }
            } header: {
                Text("Recorded Data")
            } footer: {
                Text("Import the CSV logs from the Perspective data card. Markers are matched to logs by time.")
            }

            Section("Event Markers") {
                if eventStore.events.isEmpty {
                    Text("No event markers yet.").foregroundStyle(.secondary)
                }
                ForEach(eventStore.events) { event in
                    NavigationLink {
                        DiagnosticEventDetail(eventID: event.id)
                    } label: {
                        EventRow(event: event, hasLog: event.flightLogFilename != nil)
                    }
                }
                .onDelete { offsets in
                    eventStore.delete(ids: Set(offsets.map { eventStore.events[$0].id }))
                }
            }

            Section("Safety Boundary") {
                Label("Diagnosis is advisory; approved aircraft procedures remain controlling.", systemImage: "checkmark.shield")
                Text("The app shows recorded evidence separately from possible causes. It does not assign a cause or convert a hypothesis into a procedure.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("DIAGNOSTICS")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !eventStore.events.isEmpty {
                    ShareLink(item: EventMarkersCSV(events: eventStore.events),
                              preview: SharePreview("Event markers")) {
                        Label("Export Markers", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !eventStore.events.isEmpty { EditButton() }
            }
        }
        .sensoryFeedback(.success, trigger: markCount)
        .sheet(item: $newlyMarked) { event in
            EventDetailsEditor(event: event, isNewMarker: true)
        }
        .alert("Storage problem", isPresented: Binding(get: { eventStore.lastError != nil },
                                                      set: { if !$0 { eventStore.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(eventStore.lastError ?? "")
        }
    }
}

private struct EventRow: View {
    let event: DiagnosticEvent
    let hasLog: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.detailsEntered ? event.system.rawValue : "Marker - details not added")
                    .font(.headline)
                    .foregroundStyle(event.detailsEntered ? Color.primary : Color.orange)
                Spacer()
                if hasLog { Image(systemName: "doc.text.fill").foregroundStyle(.secondary).accessibilityLabel("Log attached") }
            }
            Text(EventTime.local(event)).font(.caption).foregroundStyle(.secondary)
            if !event.note.isEmpty { Text(event.note).lineLimit(2) }
        }
    }
}

/// The event markers as a CSV file, generated only when the pilot actually shares.
struct EventMarkersCSV: Transferable {
    let events: [DiagnosticEvent]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { item in
            Data(EventExporter.csv(item.events).utf8)
        }
        .suggestedFileName("event-markers.csv")
    }
}

/// Formats an event time in the time zone where it was captured.
enum EventTime {
    static func local(_ event: DiagnosticEvent) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        f.timeZone = event.captureTimeZone
        let abbrev = event.captureTimeZone.abbreviation(for: event.timestamp) ?? ""
        return "\(f.string(from: event.timestamp)) \(abbrev)"
    }

    static func utc(_ event: DiagnosticEvent) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: event.timestamp)
    }
}

struct EventDetailsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventStore: DiagnosticEventStore
    @State private var draft: DiagnosticEvent
    let isNewMarker: Bool

    init(event: DiagnosticEvent, isNewMarker: Bool = false) {
        _draft = State(initialValue: event)
        self.isNewMarker = isNewMarker
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Marked at", value: EventTime.local(draft))
                } footer: {
                    if isNewMarker {
                        Text("Saved. Fly the airplane first; details can be added after landing.")
                    }
                }
                Section("What happened?") {
                    Picker("System", selection: $draft.system) {
                        ForEach(DiagnosticSystem.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Example: engine stumbled at 1,000 RPM with boost on", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isNewMarker ? "Marker Saved" : "Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isNewMarker ? "Later" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Start from the stored copy so changes made elsewhere (e.g. an attached log) are kept.
                        var updated = eventStore.event(id: draft.id) ?? draft
                        updated.system = draft.system
                        updated.note = draft.note
                        updated.detailsEntered = true
                        eventStore.update(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DiagnosticSystemView: View {
    let system: DiagnosticSystem

    var body: some View {
        SystemHistoryView(system: system)
    }
}

struct DiagnosticEventDetail: View {
    let eventID: UUID
    @EnvironmentObject private var eventStore: DiagnosticEventStore
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var editing = false
    @State private var finding: DiagnosticFinding?
    @State private var isAnalyzing = false
    private let engine = DiagnosticEngine()

    private var event: DiagnosticEvent? { eventStore.event(id: eventID) }

    var body: some View {
        Group {
            if let event {
                content(event)
            } else {
                ContentUnavailableView("Marker deleted", systemImage: "trash")
            }
        }
        .navigationTitle("Event Analysis")
        .task(id: analysisKey) { await analyze() }
    }

    /// Re-run analysis when the event's system or attached log changes.
    private var analysisKey: String {
        guard let event else { return "" }
        return "\(event.system.rawValue)|\(event.flightLogFilename ?? "")|\(event.note)|\(logStore.entries.count)"
    }

    @ViewBuilder
    private func content(_ event: DiagnosticEvent) -> some View {
        List {
            Section("Event") {
                LabeledContent("System", value: event.detailsEntered ? event.system.rawValue : "Not entered")
                LabeledContent("Local time", value: EventTime.local(event))
                LabeledContent("UTC", value: EventTime.utc(event))
                if !event.note.isEmpty { Text(event.note) }
                Button("Edit Details") { editing = true }
            }

            logSection(event)

            if isAnalyzing {
                Section { ProgressView("Reading flight log...") }
            } else if let finding {
                Section("Current Assessment") {
                    Text(finding.title).font(.headline)
                    LabeledContent("Confidence", value: finding.confidence.rawValue)
                    if let source = finding.dataSource { LabeledContent("Data source", value: source) }
                }
                Section("Recorded Evidence") {
                    ForEach(finding.evidence, id: \.self) { item in
                        LabeledContent(item.label) { Text(item.value).multilineTextAlignment(.trailing) }
                    }
                }
                Section("Possible Causes - Not Yet Proven") { ForEach(finding.possibleCauses, id: \.self) { Text($0) } }
                Section("Next Checks") { ForEach(finding.nextChecks, id: \.self) { Text($0) } }
                Section("Limitations") { Text(finding.limitations).foregroundStyle(.secondary) }
            }
        }
        .sheet(isPresented: $editing) { EventDetailsEditor(event: event) }
    }

    @ViewBuilder
    private func logSection(_ event: DiagnosticEvent) -> some View {
        Section {
            if let attached = logStore.entry(named: event.flightLogFilename) {
                LabeledContent("Attached log", value: attached.originalFilename)
                Button("Detach Log", role: .destructive) { setLog(nil, on: event) }
            } else if let match = logStore.bestMatch(for: event) {
                LabeledContent("Matching log", value: match.originalFilename)
                Button("Attach This Log") { setLog(match.filename, on: event) }
            } else {
                Text(logStore.entries.isEmpty
                     ? "No Perspective logs imported yet."
                     : "No imported log covers this time.")
                    .foregroundStyle(.secondary)
                NavigationLink("Import Logs") { FlightLogsView() }
            }
            if logStore.entries.count > 1 {
                Menu("Choose Another Log") {
                    ForEach(logStore.entries) { entry in
                        Button(entry.originalFilename) { setLog(entry.filename, on: event) }
                    }
                }
            }
        } header: {
            Text("Flight Data")
        }
    }

    private func setLog(_ filename: String?, on event: DiagnosticEvent) {
        var updated = event
        updated.flightLogFilename = filename
        eventStore.update(updated)
    }

    private func analyze() async {
        guard let event else { return }
        // An explicitly attached log wins; otherwise use the time match for a preview.
        let entry = logStore.entry(named: event.flightLogFilename) ?? logStore.bestMatch(for: event)
        guard let entry else {
            finding = engine.finding(for: event, log: nil)
            return
        }
        isAnalyzing = true
        let log = await logStore.log(for: entry)
        finding = engine.finding(for: event, log: log)
        isAnalyzing = false
    }
}

struct FlightLogsView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var importing = false
    /// What the file picker is choosing: the SD card's data_log folder, or individual log files.
    @State private var pickingFolder = false

    static func detail(for entry: FlightLogEntry) -> String {
        var text = "\(entry.sampleCount) samples"
        if let airframe = entry.airframeName { text += " - " + airframe }
        return text
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        if !(await logStore.importFromSavedFolder()) {
                            pickingFolder = true
                            importing = true
                        }
                    }
                } label: {
                    Label("Import new flights from SD card", systemImage: "sdcard")
                }
                .disabled(logStore.isImporting)
                if logStore.hasSavedFolder {
                    Button {
                        pickingFolder = true
                        importing = true
                    } label: {
                        Label("Choose a different folder", systemImage: "folder")
                    }
                    .disabled(logStore.isImporting)
                }
                Button {
                    pickingFolder = false
                    importing = true
                } label: {
                    Label("Import individual log files", systemImage: "square.and.arrow.down")
                }
                .disabled(logStore.isImporting)
                NavigationLink {
                    GarminImportGuideView()
                } label: {
                    Label("Flights from Garmin Pilot or flyGarmin", systemImage: "airplane.arrival")
                }
                if logStore.isImporting { ProgressView("Importing...") }
                if let summary = logStore.importSummary {
                    Label(summary, systemImage: "checkmark.circle").foregroundStyle(.green)
                }
            } footer: {
                Text("Plug the avionics data card into the iPad with a USB-C SD card reader. The first time, choose the data_log folder; after that one tap adds only the new flights. You can also share log files to this app from Files, Mail, AirDrop or Cirrus IQ. The app keeps its own copy. Tap a log for its post-flight report.")
            }

            Section("Imported Logs") {
                if logStore.entries.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                }
                ForEach(logStore.entries) { entry in
                    NavigationLink {
                        FlightReportView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.originalFilename).font(.headline)
                            Text("\(entry.start.formatted(date: .abbreviated, time: .shortened)) - \(entry.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(Self.detail(for: entry))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let gone = offsets.map { logStore.entries[$0] }
                    for entry in gone { logStore.delete(entry) }
                    Task { for entry in gone { await cloud.deleteFlight(filename: entry.filename) } }
                }
            }
        }
        .navigationTitle("Flight Logs")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: pickingFolder ? [.folder] : [.commaSeparatedText, .plainText, .data],
                      allowsMultipleSelection: !pickingFolder) { result in
            switch result {
            case .success(let urls):
                if pickingFolder, let folder = urls.first {
                    Task { await logStore.importFolder(folder) }
                } else {
                    Task { await logStore.importFiles(urls) }
                }
            case .failure(let error): logStore.lastError = error.localizedDescription
            }
        }
        .alert("Import problem", isPresented: Binding(get: { logStore.lastError != nil },
                                                     set: { if !$0 { logStore.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logStore.lastError ?? "")
        }
    }
}
