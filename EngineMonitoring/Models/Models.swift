import Foundation

/// Who stands behind a piece of content. The badge shown in the UI must match the
/// real origin of the document, so pilots never mistake self-authored material for
/// approved or manufacturer data.
enum SourceAuthority: String, Codable, CaseIterable, Identifiable {
    /// FAA-approved: AFM/POH, approved supplements, approved checklists.
    case approved = "APPROVED"
    /// Published by Cirrus or Garmin (pilot guides, service information).
    case manufacturer = "MANUFACTURER"
    /// Self-authored training aids and study cards. Not approved; not manufacturer data.
    case training = "TRAINING"
    /// Pilot/operator experience and techniques.
    case experience = "EXPERIENCE"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .approved: "checkmark.shield.fill"
        case .manufacturer: "building.2.fill"
        case .training: "graduationcap.fill"
        case .experience: "person.2.fill"
        }
    }

    /// One-line explanation shown with the badge.
    var explanation: String {
        switch self {
        case .approved: "FAA-approved aircraft documentation."
        case .manufacturer: "Published by Cirrus or Garmin."
        case .training: "Training aid. Not approved data; controlling documents govern."
        case .experience: "Pilot technique or experience. Not approved data."
        }
    }
}

struct KnowledgeDocument: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: String
    let authority: SourceAuthority
    let bundledFilename: String?
    let isCockpitCritical: Bool
    /// Document revision as printed on the document, e.g. "v3".
    let revision: String?
    /// Date the revision took effect (yyyy-MM-dd).
    let effectiveDate: String?
    /// Date by which the document must be re-verified against controlling sources (yyyy-MM-dd).
    let reviewDueDate: String?
    /// Who verified the content, if anyone (e.g. CFII name). Nil = not yet reviewed.
    let reviewedBy: String?

    init(id: String, title: String, subtitle: String, category: String, authority: SourceAuthority,
         bundledFilename: String?, isCockpitCritical: Bool, revision: String? = nil,
         effectiveDate: String? = nil, reviewDueDate: String? = nil, reviewedBy: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.authority = authority
        self.bundledFilename = bundledFilename
        self.isCockpitCritical = isCockpitCritical
        self.revision = revision
        self.effectiveDate = effectiveDate
        self.reviewDueDate = reviewDueDate
        self.reviewedBy = reviewedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        category = try c.decode(String.self, forKey: .category)
        authority = try c.decode(SourceAuthority.self, forKey: .authority)
        bundledFilename = try c.decodeIfPresent(String.self, forKey: .bundledFilename)
        isCockpitCritical = try c.decodeIfPresent(Bool.self, forKey: .isCockpitCritical) ?? false
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        effectiveDate = try c.decodeIfPresent(String.self, forKey: .effectiveDate)
        reviewDueDate = try c.decodeIfPresent(String.self, forKey: .reviewDueDate)
        reviewedBy = try c.decodeIfPresent(String.self, forKey: .reviewedBy)
    }

    /// True when a review-due date exists and has passed.
    func isReviewOverdue(asOf now: Date = Date()) -> Bool {
        guard let due = reviewDueDate.flatMap(KnowledgeDocument.dayFormatter.date(from:)) else { return false }
        return due < now
    }

    /// Cockpit-critical content that has never been reviewed or is overdue for review.
    func needsVerification(asOf now: Date = Date()) -> Bool {
        isCockpitCritical && (reviewedBy == nil || isReviewOverdue(asOf: now))
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct AircraftProfile: Codable, Equatable {
    let registration: String
    let serialNumber: String
    let description: String
    let avionics: String
    let autopilot: String
    let engine: String

    /// N63KA. Verify against the aircraft records before relying on it.
    static let n63ka = AircraftProfile(
        registration: "N63KA",
        serialNumber: "3444",
        description: "2009 Cirrus SR22 G3 - Perspective - turbonormalized configuration",
        avionics: "Cirrus Perspective (Garmin)",
        autopilot: "Garmin GFC 700",
        engine: "Continental IO-550-N family / TAT turbonormalized configuration"
    )
}
