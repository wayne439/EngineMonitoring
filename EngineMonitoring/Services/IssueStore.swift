import Foundation

/// Flight history built from the the owner's records data_log folder and bundled with the app
/// (Resources/Data/flight_history.json). Rebuild with tools/build_history.sh when new logs are uploaded.
struct BundledFlightHistory: Codable, Sendable {
    let generatedOn: String
    let sourceFolder: String
    let logCount: Int
    let summaries: [FlightSummary]

    static func load(from url: URL?) -> BundledFlightHistory? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? EventPersistence.decoder.decode(BundledFlightHistory.self, from: data)
    }

    static var bundleURL: URL? { Bundle.main.url(forResource: "flight_history", withExtension: "json") }
}

/// Every issue found in the engine data and records, grouped by kind, with the pilot's status notes.
enum IssueHistory {
    static func build(summaries: [FlightSummary], records: [String: IssueStatusRecord],
                      includeRecords: Bool = true) -> [IssueGroup] {
        var all = summaries.flatMap(\.issues)
        all += IssueDetector.trendIssues(summaries)
        all += EarlyWarning.issues(EarlyWarning.analyze(summaries))
        all += TurboCheck.issues(summaries)
        if includeRecords { all += IssuePlaybook.recordIssues.map(\.issue) }
        let byKind = Dictionary(grouping: all, by: \.kind)
        return byKind.map { kind, items in
            IssueGroup(kind: kind, occurrences: items.sorted { $0.time > $1.time },
                       guide: IssuePlaybook.guide(for: kind), record: records[kind])
        }
        .sorted { a, b in
            if a.needsReview != b.needsReview { return a.needsReview }
            if a.effectiveStatus != b.effectiveStatus { return statusRank(a.effectiveStatus) < statusRank(b.effectiveStatus) }
            if a.severity != b.severity { return a.severity < b.severity }
            return a.latest.time > b.latest.time
        }
    }

    private static func statusRank(_ s: IssueStatusRecord.Status) -> Int {
        switch s {
        case .open: 0
        case .reviewed: 1
        case .monitoring: 2
        case .completed: 3
        }
    }

    /// Review log for the shop, the owner's records or the Claude engine-card review: every WARNING/CAUTION/WATCH
    /// issue with its status, what was discovered and what was done.
    static func reviewLogMarkdown(_ groups: [IssueGroup], generated: Date = Date()) -> String {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "yyyy-MM-dd"
        func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }
        let tracked = groups.filter(\.needsTracking)
        var md = "# Issue review log\n\nExported \(d.string(from: generated)) from AI Engine Monitoring. "
        md += "\(tracked.filter(\.needsReview).count) of \(tracked.count) WARNING/CAUTION/WATCH issues need review.\n\n"
        md += "| Kind | Issue | Severity | Status | Occurrences | New since review | Last review | Reviewed through |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for g in tracked {
            let last = g.record?.lastReview.map { "\(d.string(from: $0.date)) \($0.action.rawValue)" } ?? "never"
            let through = g.record?.reviewedThrough.map { d.string(from: $0) } ?? "-"
            md += "| \(g.kind) | \(cell(g.guide.title)) | \(g.severity.rawValue) | \(g.effectiveStatus.rawValue)\(g.recurredAfterCompletion ? " (RECURRED)" : "") | \(g.occurrences.count) | \(g.newOccurrences.count) | \(last) | \(through) |\n"
        }
        for g in tracked {
            guard let r = g.record, !r.reviews.isEmpty else { continue }
            md += "\n## \(g.guide.title)\n\n"
            for e in r.reviews {
                md += "- \(d.string(from: e.date)) **\(e.action.rawValue)**"
                if !e.reviewedBy.isEmpty { md += " by \(e.reviewedBy)" }
                if !e.discovered.isEmpty { md += ". Discovered: \(e.discovered)" }
                if !e.actionTaken.isEmpty { md += ". Action: \(e.actionTaken)" }
                if !e.reference.isEmpty { md += " (ref \(e.reference))" }
                md += "\n"
            }
        }
        return md
    }
}

/// Saved status ("Open / Monitoring / Resolved") and resolution notes, one per issue kind.
@MainActor
final class IssueStore: ObservableObject {
    @Published private(set) var records: [String: IssueStatusRecord] = [:]
    @Published private(set) var groups: [IssueGroup] = []
    @Published private(set) var isBuilding = false
    @Published var lastError: String?

    private let fileURL: URL
    private var lastSummaries: [FlightSummary] = []

    init(baseDirectory: URL = EventPersistence.defaultDirectory()) {
        fileURL = baseDirectory.appendingPathComponent("Issues", isDirectory: true).appendingPathComponent("status.json")
        if let data = try? Data(contentsOf: fileURL) {
            do { records = try EventPersistence.decoder.decode([String: IssueStatusRecord].self, from: data) } catch {
                lastError = "Issue notes could not be read: \(error.localizedDescription)"
            }
        }
    }

    /// Rebuilds the grouped list from every flight summary (bundled history plus imported logs).
    func refresh(summaries: [FlightSummary]) async {
        lastSummaries = summaries
        isBuilding = true
        defer { isBuilding = false }
        let records = self.records
        groups = await Task.detached(priority: .utility) {
            IssueHistory.build(summaries: summaries, records: records)
        }.value
    }

    func group(kind: String) -> IssueGroup? { groups.first { $0.kind == kind } }

    func groups(for system: DiagnosticSystem) -> [IssueGroup] { groups.filter { $0.system == system } }

    /// WARNING/CAUTION/WATCH issues never reviewed, recurred, or with new occurrences since the last review.
    var needsReviewCount: Int { groups.filter(\.needsReview).count }

    /// Adds a review to one kind of issue. By default the review covers every occurrence so far.
    func addReview(_ review: IssueReview, for kind: String) {
        var review = review
        if review.coversThrough == nil { review.coversThrough = group(kind: kind)?.latest.time ?? review.date }
        var record = records[kind] ?? IssueStatusRecord(status: .open)
        record.apply(review)
        records[kind] = record
        save()
        // Re-apply to the cached groups without rebuilding the history.
        groups = groups.map { g in
            g.kind == kind ? IssueGroup(kind: g.kind, occurrences: g.occurrences, guide: g.guide, record: record) : g
        }
    }

    func reviewLogMarkdown() -> String { IssueHistory.reviewLogMarkdown(groups) }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EventPersistence.encoder.encode(records).write(to: fileURL, options: [.atomic])
        } catch {
            lastError = "Issue notes could not be saved: \(error.localizedDescription)"
        }
    }
}
