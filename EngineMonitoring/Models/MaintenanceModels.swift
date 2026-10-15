import Foundation

/// A value the pilot or shop records when a check or service is done.
struct MaintenanceField: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case passFail, yesNo, number, text }
    var id: String { key }
    let key: String
    let label: String
    let kind: Kind
    var unit: String? = nil
    /// Acceptable range for numbers (outside = flagged).
    var low: Double? = nil
    var high: Double? = nil
    var optional: Bool = false

    var rangeText: String? {
        switch (low, high) {
        case let (l?, h?): return "\(fmt(l))-\(fmt(h))\(unit.map { " \($0)" } ?? "")"
        case let (l?, nil): return "at least \(fmt(l))\(unit.map { " \($0)" } ?? "")"
        case let (nil, h?): return "at most \(fmt(h))\(unit.map { " \($0)" } ?? "")"
        default: return nil
        }
    }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}

/// Something that has to be done on a schedule: by days, by engine hours, or both (whichever comes first).
struct MaintenanceItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case pilotCheck = "Pilot check"
        case service = "Service"
        case inspection = "Inspection"
    }
    let id: String
    var name: String
    var kind: Kind
    var intervalDays: Int?
    var intervalHours: Double?
    /// "Due soon" this many days / engine hours before it is due.
    var warnDays: Int
    var warnHours: Double
    var instructions: [String]
    var fields: [MaintenanceField]
    /// Where the interval and the values come from.
    var source: String
    var authority: SourceAuthority
    var builtIn: Bool
    /// Set when you change a built-in item's schedule (kept when the app updates the built-in text).
    var userEdited: Bool? = nil

    var intervalText: String {
        let d = intervalDays.map { $0 % 365 == 0 ? "\($0 / 365) year\($0 == 365 ? "" : "s")" : "\($0) days" }
        let h = intervalHours.map { String(format: "%.0f hours", $0) }
        switch (d, h) {
        case let (d?, h?): return "Every \(h) or \(d), whichever comes first"
        case let (d?, nil): return "Every \(d)"
        case let (nil, h?): return "Every \(h)"
        default: return "No schedule"
        }
    }
}

/// One time the item was done, with its results.
struct MaintenanceEntry: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let itemID: String
    var date: Date
    /// Values by field key, as typed ("62", "yes", "pass").
    var values: [String: String]
    var notes: String
    var by: String
    var created: Date = Date()

    /// Fields whose value is outside the field's range, "fail" or "no".
    func problems(for item: MaintenanceItem) -> [String] {
        item.fields.compactMap { f in
            guard let raw = values[f.key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            switch f.kind {
            case .passFail: return raw.lowercased() == "fail" ? "\(f.label): fail" : nil
            case .yesNo: return raw.lowercased() == "no" ? "\(f.label): no" : nil
            case .number:
                guard let v = Double(raw) else { return "\(f.label): not a number" }
                if let l = f.low, v < l { return "\(f.label) \(raw)\(f.unit.map { " \($0)" } ?? "") below \(f.rangeText ?? "")" }
                if let h = f.high, v > h { return "\(f.label) \(raw)\(f.unit.map { " \($0)" } ?? "") above \(f.rangeText ?? "")" }
                return nil
            case .text: return nil
            }
        }
    }

    func passed(for item: MaintenanceItem) -> Bool { problems(for: item).isEmpty }
}

struct MaintenanceStatus: Hashable, Sendable {
    enum State: Int, Comparable, Sendable {
        case failed = 0, overdue, neverDone, dueSoon, ok
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        var label: String {
            switch self {
            case .failed: "Last check failed"
            case .overdue: "Overdue"
            case .neverDone: "Not recorded yet"
            case .dueSoon: "Due soon"
            case .ok: "OK"
            }
        }
    }
    let state: State
    let last: MaintenanceEntry?
    let nextDate: Date?
    let daysLeft: Int?
    /// Engine hours since the last entry (from the logs).
    let hoursSince: Double?
    let hoursLeft: Double?
    let problems: [String]

    var summary: String {
        var parts: [String] = []
        if let d = daysLeft { parts.append(d >= 0 ? "\(d) day\(d == 1 ? "" : "s") left" : "\(-d) day\(d == -1 ? "" : "s") overdue") }
        if let h = hoursLeft { parts.append(h >= 0 ? String(format: "%.1f h left", h) : String(format: "%.1f h over", -h)) }
        return parts.joined(separator: " · ")
    }
}

enum MaintenanceSchedule {
    /// Flight hours (airborne time) from the logs that start on or after `since`.
    /// Airborne time from the logs tracks logbook total time within a few percent.
    static func flightHours(since: Date, summaries: [FlightSummary]) -> Double {
        summaries.filter { $0.start >= since }.reduce(0) { $0 + Double($1.airborneSeconds) / 3600 }
    }

    /// Latest entry (any item) with a tach / total time reading, plus the flight hours logged since.
    static func estimatedTach(entries: [MaintenanceEntry], summaries: [FlightSummary]) -> (value: Double, anchor: Double, anchorDate: Date)? {
        let withTach = entries.compactMap { e -> (Double, Date)? in
            guard let raw = e.values["tach"], let v = Double(raw) else { return nil }
            return (v, e.date)
        }
        guard let last = withTach.max(by: { $0.1 < $1.1 }) else { return nil }
        return (last.0 + flightHours(since: last.1, summaries: summaries), last.0, last.1)
    }

    /// Starting records for a new aircraft. Empty: owners enter their own logbook entries.
    static func baselineEntries() -> [MaintenanceEntry] { [] }

    static func status(of item: MaintenanceItem, entries: [MaintenanceEntry], summaries: [FlightSummary],
                       now: Date = Date(), calendar: Calendar = .current) -> MaintenanceStatus {
        let mine = entries.filter { $0.itemID == item.id }.sorted { $0.date > $1.date }
        guard let last = mine.first else {
            return MaintenanceStatus(state: .neverDone, last: nil, nextDate: nil, daysLeft: nil, hoursSince: nil, hoursLeft: nil, problems: [])
        }
        let problems = last.problems(for: item)
        var nextDate: Date?, daysLeft: Int?, hoursSince: Double?, hoursLeft: Double?
        if let days = item.intervalDays, let due = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: last.date)) {
            nextDate = due
            daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day
        }
        if let hours = item.intervalHours {
            // Prefer total time: the tach recorded at the last service against today's estimated total time.
            let since: Double
            if let t = last.values["tach"].flatMap(Double.init), let now = estimatedTach(entries: entries, summaries: summaries) {
                since = max(0, now.value - t)
            } else {
                since = flightHours(since: last.date, summaries: summaries)
            }
            hoursSince = since
            hoursLeft = hours - since
        }
        let state: MaintenanceStatus.State
        if !problems.isEmpty { state = .failed }
        else if (daysLeft ?? 1) < 0 || (hoursLeft ?? 1) < 0 { state = .overdue }
        else if (daysLeft.map { $0 <= item.warnDays } ?? false) || (hoursLeft.map { $0 <= item.warnHours } ?? false) { state = .dueSoon }
        else { state = .ok }
        return MaintenanceStatus(state: state, last: last, nextDate: nextDate, daysLeft: daysLeft, hoursSince: hoursSince,
                                 hoursLeft: hoursLeft, problems: problems)
    }

    // MARK: - Built-in items

    static let defaults: [MaintenanceItem] = [
        MaintenanceItem(
            id: "oil-change", name: "Oil change", kind: .service,
            intervalDays: 120, intervalHours: 30, warnDays: 14, warnHours: 3,
            instructions: [
                "Record each oil and filter change with the total time (tach) from the logbook.",
                "Hours since then = today's estimated total time (last recorded tach + flight hours from the data card logs), so upload every card.",
                "Send an oil sample with each change if you use oil analysis.",
            ],
            fields: [
                MaintenanceField(key: "tach", label: "Tach hours at change", kind: .number, unit: "h", optional: true),
                MaintenanceField(key: "quarts", label: "Oil added", kind: .number, unit: "qt", optional: true),
                MaintenanceField(key: "oil", label: "Oil type", kind: .text, optional: true),
                MaintenanceField(key: "filter", label: "Filter changed", kind: .yesNo),
                MaintenanceField(key: "sample", label: "Oil sample sent", kind: .yesNo, optional: true),
            ],
            source: "Default interval: 30 hours or 4 months, whichever comes first. Set the hours in Aircraft Profile and confirm with your A&P; oil type and quantity per your engine manual.",
            authority: .experience, builtIn: true),
        MaintenanceItem(
            id: "fiki-test", name: "FIKI ice protection system test", kind: .pilotCheck,
            intervalDays: 30, intervalHours: nil, warnDays: 5, warnHours: 0,
            instructions: [
                "Run the ice protection system test exactly as the Ice Protection System AFM supplement says. Keep your supplement handy; the app records the result, it does not replace the procedure.",
                "Record what you saw: fluid quantity, fluid on every protected surface and the propeller, windshield spray, and any messages on the MFD.",
                "A failed test stays at the top of MAINTENANCE until a passing test is recorded.",
            ],
            fields: [
                MaintenanceField(key: "result", label: "Overall result", kind: .passFail),
                MaintenanceField(key: "fluid", label: "Fluid quantity", kind: .number, unit: "gal", optional: true),
                MaintenanceField(key: "surfaces", label: "Fluid on all surfaces and prop", kind: .yesNo),
                MaintenanceField(key: "windshield", label: "Windshield spray works", kind: .yesNo, optional: true),
            ],
            source: "Interval: pilot practice, every 30 days. Procedure: your Ice Protection System AFM supplement. Only for FIKI-equipped aircraft.",
            authority: .training, builtIn: true),
        MaintenanceItem(
            id: "tire-pressure", name: "Tire pressure check", kind: .pilotCheck,
            intervalDays: 30, intervalHours: nil, warnDays: 5, warnHours: 0,
            instructions: [
                "Check each tire with a dial-type gauge at the pressures in your POH (usually Section 8, Handling, Servicing and Maintenance).",
                "Record what you measured; compare with your POH values.",
                "Look at each tire for wear, cuts, nicks and bruises while you are there.",
            ],
            fields: [
                MaintenanceField(key: "nose", label: "Nose / tail", kind: .number, unit: "psi"),
                MaintenanceField(key: "left", label: "Left main", kind: .number, unit: "psi"),
                MaintenanceField(key: "right", label: "Right main", kind: .number, unit: "psi"),
                MaintenanceField(key: "condition", label: "Tires free of cuts and wear", kind: .yesNo),
            ],
            source: "Pressures: your POH. Interval: pilot practice, monthly.",
            authority: .training, builtIn: true),
        MaintenanceItem(
            id: "annual", name: "Annual inspection", kind: .inspection,
            intervalDays: 365, intervalHours: nil, warnDays: 45, warnHours: 0,
            instructions: [
                "Record the date the annual inspection was signed off in the logbook.",
                "The annual is due by the end of the 12th calendar month (14 CFR 91.409); the date here is a reminder, the logbook governs.",
            ],
            fields: [
                MaintenanceField(key: "shop", label: "Shop", kind: .text, optional: true),
                MaintenanceField(key: "tach", label: "Tach hours", kind: .number, unit: "h", optional: true),
                MaintenanceField(key: "wo", label: "Work order", kind: .text, optional: true),
            ],
            source: "14 CFR 91.409 annual inspection: due by the end of the 12th calendar month after the last one. Record yours here.",
            authority: .approved, builtIn: true),
    ]
}
