import SwiftUI
import UIKit

/// Every issue found in the engine data card logs and the records, grouped by kind,
/// with how to handle it in flight, how to resolve it, and your status notes.
struct IssueHistoryView: View {
    /// nil = all systems.
    var system: DiagnosticSystem? = nil
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var filter: Filter = .needsReview
    @State private var includeInfo = false

    enum Filter: String, CaseIterable, Identifiable {
        case needsReview = "Needs Review"
        case reviewed = "Reviewed"
        case completed = "Completed"
        case all = "All"
        var id: String { rawValue }
    }

    private var shown: [IssueGroup] {
        issues.groups.filter { g in
            (system == nil || g.system == system)
                && (includeInfo || filter == .all || g.severity != .info)
                && matches(g)
        }
    }

    private func matches(_ g: IssueGroup) -> Bool {
        switch filter {
        case .needsReview: return g.needsReview
        case .reviewed: return !g.needsReview && (g.effectiveStatus == .reviewed || g.effectiveStatus == .monitoring)
        case .completed: return !g.needsReview && g.effectiveStatus == .completed
        case .all: return true
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show technique notes and info items", isOn: $includeInfo)
            } footer: {
                Text(sourceLine + " Every WARNING, CAUTION and WATCH item needs a review; a new occurrence after a review brings it back here. Export the review log with the share button to send it to your A&P.")
            }

            if issues.isBuilding && issues.groups.isEmpty {
                Section { ProgressView("Reading flight history…") }
            } else if shown.isEmpty {
                Section { Text("Nothing \(filter == .all ? "" : filter.rawValue.lowercased() + " ")here.").foregroundStyle(.secondary) }
            }

            ForEach(IssueSeverity.allCases, id: \.self) { severity in
                let rows = shown.filter { $0.severity == severity }
                if !rows.isEmpty {
                    Section(severity.rawValue) {
                        ForEach(rows) { group in
                            NavigationLink {
                                IssueDetailView(kind: group.kind)
                            } label: {
                                IssueGroupRow(group: group)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(system.map { "\($0.rawValue) Issues" } ?? "Issue History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: issues.reviewLogMarkdown(), subject: Text("Issue review log"),
                          preview: SharePreview("Issue review log")) {
                    Label("Export Review Log", systemImage: "square.and.arrow.up")
                }
            }
        }
        .refreshable { await issues.refresh(summaries: Array(logStore.summaries.values)) }
    }

    private var sourceLine: String {
        var s = ""
        if let b = logStore.bundled {
            s += "\(b.logCount) engine data card logs from \(b.sourceFolder) (built \(b.generatedOn))"
        }
        let imported = logStore.entries.count
        if imported > 0 { s += (s.isEmpty ? "" : ", plus ") + "\(imported) imported log\(imported == 1 ? "" : "s")" }
        s += (s.isEmpty ? "" : ", ") + "and the maintenance records. Recorded values only; no cause is assigned."
        return s
    }
}

struct IssueGroupRow: View {
    let group: IssueGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                SeverityDot(severity: group.severity)
                Text(group.guide.title).font(.headline)
                Spacer()
                statusTag
            }
            Text(countLine).font(.caption).foregroundStyle(.secondary)
            if let r = group.record?.lastReview {
                Text(reviewLine(r)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text(group.latest.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusTag: some View {
        let newCount = group.newOccurrences.count
        if group.recurredAfterCompletion {
            Text("RECURRED").font(.caption2.bold()).foregroundStyle(.red)
        } else if group.needsTracking && group.record == nil {
            Text("NOT REVIEWED").font(.caption2.bold()).foregroundStyle(.orange)
        } else if group.needsTracking && newCount > 0 {
            Text("\(newCount) NEW").font(.caption2.bold()).foregroundStyle(.orange)
        } else if let r = group.record {
            Text(r.status.rawValue.uppercased()).font(.caption2.bold())
                .foregroundStyle(r.status == .completed ? Color.green : Color.blue)
        }
    }

    private func reviewLine(_ r: IssueReview) -> String {
        var s = "\(r.action.rawValue) \(r.date.formatted(date: .abbreviated, time: .omitted))"
        if !r.reviewedBy.isEmpty { s += " by \(r.reviewedBy)" }
        if !r.discovered.isEmpty { s += ": \(r.discovered)" }
        return s
    }

    private var countLine: String {
        let when = group.latest.time.formatted(date: .abbreviated, time: .omitted)
        if group.latest.origin == .records { return "\(group.system.rawValue) · \(group.latest.source) · \(when)" }
        let n = group.occurrences.count
        return "\(group.system.rawValue) · \(n) time\(n == 1 ? "" : "s") in \(group.flightCount) log\(group.flightCount == 1 ? "" : "s") · latest \(when)"
    }
}

struct SeverityDot: View {
    let severity: IssueSeverity
    var body: some View {
        Circle().fill(color).frame(width: 10, height: 10).accessibilityLabel(severity.rawValue)
    }
    private var color: Color {
        switch severity {
        case .warning: .red
        case .caution: .orange
        case .watch: .yellow
        case .info: .gray
        }
    }
}

/// One kind of issue: what it means, what to do in flight (POH), how to resolve it, every occurrence, and your notes.
struct IssueDetailView: View {
    let kind: String
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var logStore: FlightLogStore
    @EnvironmentObject private var poh: POHRepository
    @Environment(\.openURL) private var openURL
    @AppStorage("reviewerName") private var reviewerName = ""
    @State private var showingReview = false
    @State private var copied = false

    var body: some View {
        List {
            if let group = issues.group(kind: kind) {
                content(group)
            } else {
                Text("This issue is no longer in the history.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Issue")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReview) {
            if let group = issues.group(kind: kind) {
                IssueReviewEditor(group: group, reviewerName: $reviewerName) { review in
                    issues.addReview(review, for: kind)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ group: IssueGroup) -> some View {
        let guide = group.guide
        Section {
            HStack {
                SeverityDot(severity: group.severity)
                Text(group.severity.rawValue).font(.caption.bold())
                Text("· \(group.system.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            Text(guide.title).font(.title2.bold())
            Text(guide.meaning)
            if group.recurredAfterCompletion {
                Label("Happened again after it was marked completed.", systemImage: "exclamationmark.arrow.circlepath")
                    .foregroundStyle(.red)
            }
        }

        reviewSection(group)

        Section {
            ForEach(guide.inFlight, id: \.self) { Label($0, systemImage: "airplane").labelStyle(.titleAndIcon) }
            if let id = guide.pohProcedureID, let procedure = poh.index?.procedures.first(where: { $0.id == id }) {
                NavigationLink {
                    ProcedureView(procedure: procedure)
                } label: {
                    Label("Open POH \(procedure.label) \(procedure.title)", systemImage: "book.closed.fill").bold()
                }
            }
        } header: {
            HStack {
                Text("If It Happens In Flight")
                Spacer()
                if guide.pohReference != nil { AuthorityBadge(authority: .approved) }
            }
        } footer: {
            Text(guide.pohReference.map { "From \($0). The POH and approved checklists control." } ?? "No specific POH procedure. Fly the airplane; the POH and approved checklists control.")
        }

        Section {
            ForEach(guide.toResolve, id: \.self) { Label($0, systemImage: "wrench.adjustable") }
        } header: {
            HStack {
                Text("How To Resolve")
                Spacer()
                AuthorityBadge(authority: .training)
            }
        } footer: {
            Text("Checks to discuss with your A&P. Not a diagnosis.")
        }

        Section {
            ForEach(group.occurrences) { o in
                occurrenceRow(o, isNew: group.needsTracking && group.record != nil && group.isNew(o))
            }
        } header: {
            Text(group.latest.origin == .records ? "Source" : "Occurrences (\(group.occurrences.count))")
        }

        Section {
            Button {
                UIPasteboard.general.string = AircraftKnowledge.copaQuestion(
                    about: guide.copaTopic,
                    details: "\(group.occurrences.count) occurrence(s); latest: \(group.latest.detail).")
                copied = true
            } label: {
                Label(copied ? "Question copied - paste it in an email or message to your A&P" : "Copy a question for your A&P",
                      systemImage: "questionmark.bubble")
            }
        } footer: {
            Text("Your A&P and the POH/AFM are the authority.")
        }
    }

    @ViewBuilder
    private func occurrenceRow(_ o: FlightIssue, isNew: Bool) -> some View {
        let summary = logStore.summary(named: o.source)
        let tz = summary?.timeZone ?? .current
        let label = VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(localTime(o.time, tz)).font(.headline)
                if isNew { Text("NEW").font(.caption2.bold()).foregroundStyle(.orange) }
            }
            Text(o.title).font(.caption.bold())
            Text(o.detail).font(.caption).foregroundStyle(.secondary)
            Text(o.source).font(.caption2).foregroundStyle(.secondary)
        }
        if let entry = logStore.entry(named: o.source) {
            NavigationLink { FlightReportView(entry: entry) } label: { label }
        } else if let summary {
            NavigationLink { FlightSummaryView(summary: summary) } label: { label }
        } else {
            label
        }
    }

    private func localTime(_ d: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "d MMM yyyy HH:mm"
        return f.string(from: d)
    }

    @ViewBuilder
    private func reviewSection(_ group: IssueGroup) -> some View {
        Section {
            if group.needsTracking {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(group.effectiveStatus.rawValue).bold()
                        .foregroundStyle(group.needsReview ? Color.orange : (group.effectiveStatus == .completed ? Color.green : Color.blue))
                }
                if group.record == nil {
                    Label("Not reviewed yet", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                } else if !group.newOccurrences.isEmpty {
                    Label("\(group.newOccurrences.count) new occurrence\(group.newOccurrences.count == 1 ? "" : "s") since the last review",
                          systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                }
                if let through = group.record?.reviewedThrough {
                    LabeledContent("Reviewed through", value: through.formatted(date: .abbreviated, time: .shortened))
                }
                if let done = group.record?.completedOn, group.effectiveStatus == .completed {
                    LabeledContent("Completed", value: done.formatted(date: .abbreviated, time: .omitted))
                }
                Button {
                    showingReview = true
                } label: {
                    Label("Add Review", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("INFO items are for reference and are not tracked for review.").foregroundStyle(.secondary)
            }
            ForEach(group.record?.reviews ?? []) { r in
                ReviewRow(review: r)
            }
        } header: {
            Text("Review And Findings")
        } footer: {
            Text("Record each review: what was discovered and what was done. Saved on this iPad; export the review log from Issue History.")
        }
    }
}

private struct ReviewRow: View {
    let review: IssueReview

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(review.action.rawValue).font(.subheadline.bold()).foregroundStyle(color)
                Text(review.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                Spacer()
                if !review.reviewedBy.isEmpty { Text(review.reviewedBy).font(.caption).foregroundStyle(.secondary) }
            }
            if !review.discovered.isEmpty { Text("Discovered: \(review.discovered)").font(.callout) }
            if !review.actionTaken.isEmpty { Text("Action: \(review.actionTaken)").font(.callout) }
            if !review.reference.isEmpty { Text("Ref: \(review.reference)").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch review.action {
        case .completed: .green
        case .reopened: .red
        case .monitoring, .reviewed: .blue
        }
    }
}

/// Sheet for adding one review: action, who, what was discovered, what was done.
struct IssueReviewEditor: View {
    let group: IssueGroup
    @Binding var reviewerName: String
    let onSave: (IssueReview) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var action: IssueReview.Action = .reviewed
    @State private var date = Date()
    @State private var discovered = ""
    @State private var actionTaken = ""
    @State private var reference = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(group.guide.title).font(.headline)
                    Text("\(group.occurrences.count) occurrence\(group.occurrences.count == 1 ? "" : "s"); this review covers all of them through \(group.latest.time.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Result") {
                    Picker("Action", selection: $action) {
                        ForEach(IssueReview.Action.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Reviewed by (you, A&P, shop)", text: $reviewerName)
                }
                Section("What Was Discovered") {
                    TextField("Findings, e.g. injector #3 partially blocked; idle mixture lean (RPM rise 10)", text: $discovered, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("What Was Done") {
                    TextField("Action taken, e.g. nozzles cleaned, idle mixture richened 2 clicks", text: $actionTaken, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Work order / logbook reference (optional)", text: $reference)
                }
            }
            .navigationTitle("Add Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(IssueReview(date: date, action: action, reviewedBy: reviewerName,
                                           discovered: discovered.trimmingCharacters(in: .whitespacesAndNewlines),
                                           actionTaken: actionTaken.trimmingCharacters(in: .whitespacesAndNewlines),
                                           reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
                                           coversThrough: group.latest.time))
                        dismiss()
                    }
                    .disabled(action != .reviewed && action != .reopened && discovered.isEmpty && actionTaken.isEmpty)
                }
            }
        }
    }
}

/// A flight from the bundled history (its CSV is on the owner's records, not on the iPad): summary values and issues.
struct FlightSummaryView: View {
    let summary: FlightSummary
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        List {
            Section {
                LabeledContent("Log", value: summary.filename)
                LabeledContent("Start", value: time(summary.start, date: true))
                LabeledContent("End", value: time(summary.end, date: false))
                ForEach(FlightPhase.allCases, id: \.self) { p in
                    if let s = summary.phaseSeconds[p], s >= 60 { LabeledContent(p.rawValue, value: "\(s / 60) min") }
                }
            } footer: {
                Text("Import this log file for the full post-flight report.")
            }

            FlightTechniqueSection(summary: summary)

            ValveWatchSection(result: summary.valveWatch)

            ProbeCheckSection(result: summary.probeCheck, timeZone: summary.timeZone)

            EngineChecksSection(result: summary.engineChecks, timeZone: summary.timeZone)

            ReportCardSection(summary: summary, summaries: Array(logStore.summaries.values))

            Section("Issues In This Log") {
                if summary.issues.isEmpty { Text("None recorded.").foregroundStyle(.secondary) }
                ForEach(summary.issues) { i in
                    NavigationLink { IssueDetailView(kind: i.kind) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            SeverityDot(severity: i.severity)
                            VStack(alignment: .leading) {
                                Text(i.title).font(.headline)
                                Text(i.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !summary.starts.isEmpty {
                Section("Engine Starts") {
                    ForEach(summary.starts, id: \.time) { s in
                        LabeledContent(time(s.time, date: false),
                                       value: ((s.rpmAfter30s ?? 0) >= 500 ? "Started" : "Stopped within 30 s")
                                       + (s.minVolt1.map { String(format: " · %.1f V", $0) } ?? ""))
                    }
                }
            }

            ForEach(FlightPhase.compared, id: \.self) { phase in
                if let stats = summary.stats[phase] {
                    Section("\(phase.rawValue) (median · max)") {
                        ForEach(FlightMetric.allCases, id: \.self) { m in
                            if let s = stats[m] {
                                LabeledContent(m.label, value: "\(m.format(s.p50)) · \(m.format(s.max))")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(time(summary.start, date: true))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func time(_ d: Date, date: Bool) -> String {
        let f = DateFormatter()
        f.timeZone = summary.timeZone
        f.dateFormat = date ? "d MMM yyyy HH:mm" : "HH:mm:ss"
        return f.string(from: d)
    }
}
