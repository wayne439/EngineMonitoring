import Foundation

/// How much attention an issue needs. Only POH limit exceedances are WARNING/CAUTION.
enum IssueSeverity: String, Codable, CaseIterable, Comparable, Sendable {
    case warning = "WARNING"
    case caution = "CAUTION"
    case watch = "WATCH"
    case info = "INFO"

    private var rank: Int {
        switch self {
        case .warning: 0
        case .caution: 1
        case .watch: 2
        case .info: 3
        }
    }
    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// Where an issue was found.
enum IssueOrigin: String, Codable, Sendable {
    /// Found in a Perspective data-card log.
    case engineData = "Engine data card"
    /// Compared with the aircraft's normal ranges from earlier flights.
    case trend = "Trend vs normal"
    /// From the maintenance records on the owner's records.
    case records = "Maintenance records"
}

/// One occurrence of an issue, found in one flight log (or one records document).
struct FlightIssue: Codable, Hashable, Identifiable, Sendable {
    /// Stable key for the KIND of problem, e.g. "start.stopped", "limit.cht-caution", "trend.cruise.oilTemp".
    /// Status and resolution notes are kept per kind, so a recurring problem is tracked once.
    let kind: String
    let system: DiagnosticSystem
    let severity: IssueSeverity
    let origin: IssueOrigin
    /// Log filename, or the records document the item came from.
    let source: String
    let time: Date
    /// Short, specific title for this occurrence.
    let title: String
    /// Recorded values (never a cause).
    let detail: String

    var id: String { "\(kind)|\(source)|\(Int(time.timeIntervalSince1970))" }
}

/// One review of an issue: who looked at it, what was discovered and what was done.
struct IssueReview: Codable, Hashable, Identifiable, Sendable {
    enum Action: String, Codable, CaseIterable, Sendable {
        /// Looked at; nothing to do yet or waiting for the shop.
        case reviewed = "Reviewed"
        /// Reviewed and being watched on the next flights.
        case monitoring = "Monitoring"
        /// The corrective action is done (repair, adjustment, technique change).
        case completed = "Completed"
        /// Opened again (e.g. it came back, or the fix did not work).
        case reopened = "Reopened"
    }
    var id = UUID()
    var date: Date
    var action: Action
    /// Pilot, A&P or shop.
    var reviewedBy: String
    /// What was discovered (findings).
    var discovered: String
    /// What was done about it.
    var actionTaken: String
    /// Work order, logbook entry or invoice number.
    var reference: String
    /// Occurrences up to this time were covered by this review.
    var coversThrough: Date?
}

/// Review state of one kind of issue. Saved on the device (Issues/status.json).
struct IssueStatusRecord: Codable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case open = "Open"
        case reviewed = "Reviewed"
        case monitoring = "Monitoring"
        case completed = "Completed"

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // v0.6 saved "Resolved".
            self = raw == "Resolved" ? .completed : (Status(rawValue: raw) ?? .open)
        }
    }
    var status: Status
    /// Newest first.
    var reviews: [IssueReview]
    var completedOn: Date?
    /// Occurrences up to this time have been reviewed; later ones show as NEW.
    var reviewedThrough: Date?
    var updated: Date

    init(status: Status, reviews: [IssueReview] = [], completedOn: Date? = nil, reviewedThrough: Date? = nil, updated: Date = Date()) {
        self.status = status
        self.reviews = reviews
        self.completedOn = completedOn
        self.reviewedThrough = reviewedThrough
        self.updated = updated
    }

    private enum CodingKeys: String, CodingKey { case status, reviews, completedOn, reviewedThrough, updated, note, resolvedOn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
        completedOn = try c.decodeIfPresent(Date.self, forKey: .completedOn) ?? c.decodeIfPresent(Date.self, forKey: .resolvedOn)
        reviewedThrough = try c.decodeIfPresent(Date.self, forKey: .reviewedThrough)
        var reviews = try c.decodeIfPresent([IssueReview].self, forKey: .reviews) ?? []
        // v0.6 kept one note; turn it into the first review entry.
        if reviews.isEmpty, let note = try c.decodeIfPresent(String.self, forKey: .note) {
            let action: IssueReview.Action = status == .completed ? .completed : (status == .monitoring ? .monitoring : .reviewed)
            reviews = [IssueReview(date: completedOn ?? updated, action: action, reviewedBy: "", discovered: note,
                                   actionTaken: "", reference: "", coversThrough: reviewedThrough ?? completedOn ?? updated)]
        }
        self.reviews = reviews
        if reviewedThrough == nil, status != .open { reviewedThrough = completedOn ?? updated }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(reviews, forKey: .reviews)
        try c.encodeIfPresent(completedOn, forKey: .completedOn)
        try c.encodeIfPresent(reviewedThrough, forKey: .reviewedThrough)
        try c.encode(updated, forKey: .updated)
    }

    var lastReview: IssueReview? { reviews.first }

    /// Applies a new review (newest first) and moves the status.
    mutating func apply(_ review: IssueReview) {
        reviews.insert(review, at: 0)
        updated = review.date
        switch review.action {
        case .reviewed: status = .reviewed
        case .monitoring: status = .monitoring
        case .completed: status = .completed; completedOn = review.date
        case .reopened: status = .open; completedOn = nil
        }
        if review.action != .reopened, let through = review.coversThrough {
            reviewedThrough = max(reviewedThrough ?? through, through)
        }
    }
}

/// Every occurrence of one kind of issue, with its guidance and the saved review state.
struct IssueGroup: Identifiable, Hashable, Sendable {
    let kind: String
    let occurrences: [FlightIssue]   // newest first
    let guide: IssueGuide
    let record: IssueStatusRecord?

    var id: String { kind }
    var latest: FlightIssue { occurrences[0] }
    var system: DiagnosticSystem { latest.system }
    var severity: IssueSeverity { occurrences.map(\.severity).min() ?? .info }
    var flightCount: Int { Set(occurrences.map(\.source)).count }
    /// WARNING, CAUTION and WATCH items are tracked for review; INFO items are not.
    var needsTracking: Bool { severity != .info }

    /// Occurrences after the last review (all of them if never reviewed).
    var newOccurrences: [FlightIssue] {
        guard let through = record?.reviewedThrough else { return record == nil ? occurrences : [] }
        return occurrences.filter { $0.time > through }
    }

    func isNew(_ o: FlightIssue) -> Bool {
        guard let through = record?.reviewedThrough else { return record == nil }
        return o.time > through
    }

    /// Completed stays completed only while nothing new has happened since.
    var recurredAfterCompletion: Bool {
        guard let record, record.status == .completed, let done = record.completedOn else { return false }
        return latest.origin != .records && occurrences.contains { $0.time > max(done, record.reviewedThrough ?? done) }
    }

    var effectiveStatus: IssueStatusRecord.Status {
        if recurredAfterCompletion { return .open }
        return record?.status ?? .open
    }

    /// Never reviewed, recurred after completion, or happened again since the last review.
    var needsReview: Bool {
        guard needsTracking else { return false }
        if record == nil || effectiveStatus == .open { return true }
        return !newOccurrences.isEmpty
    }
}

/// How to handle and how to resolve one kind of issue.
/// In-flight actions restate the POH (APPROVED) and name the page; ground checks are TRAINING
/// items for the pilot and the A&P to decide on, never a diagnosis.
struct IssueGuide: Hashable, Sendable {
    let title: String
    /// What the data shows, in plain words.
    let meaning: String
    /// POH procedure to open in PROCEDURES (id from poh_index.json), if one applies.
    let pohProcedureID: String?
    /// POH reference shown with the in-flight actions.
    let pohReference: String?
    /// What to do if it happens in flight (POH wording, APPROVED).
    let inFlight: [String]
    /// What to check on the ground to resolve it (TRAINING / shop).
    let toResolve: [String]
    /// Topic for the "Copy a question for your A&P" button.
    let copaTopic: String
}
