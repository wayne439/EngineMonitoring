import Foundation

/// File-backed storage for event markers. JSON in Application Support, written atomically.
/// Kept free of SwiftUI/Combine so it can be unit-tested directly.
struct EventPersistence {
    let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("diagnostic-events.json")
    }

    func load() throws -> [DiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode([DiagnosticEvent].self, from: data)
            .sorted { $0.timestamp > $1.timestamp }
    }

    func save(_ events: [DiagnosticEvent]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(events)
        try data.write(to: fileURL, options: [.atomic])
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Decodes events saved by the v0.2 build (UserDefaults, default JSONEncoder date strategy).
    static func decodeLegacy(_ data: Data) throws -> [DiagnosticEvent] {
        try JSONDecoder().decode([DiagnosticEvent].self, from: data)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("N63KA", isDirectory: true)
    }
}

/// Summary of an imported log, stored in an index so logs need not be re-parsed to list them.
struct FlightLogEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String { filename }
    let filename: String
    let originalFilename: String
    let start: Date
    let end: Date
    let sampleCount: Int
    let airframeName: String?
    let systemID: String?
    let importedAt: Date

    func covers(_ date: Date, tolerance: TimeInterval) -> Bool {
        date >= start.addingTimeInterval(-tolerance) && date <= end.addingTimeInterval(tolerance)
    }

    func distance(to date: Date) -> TimeInterval {
        if date < start { return start.timeIntervalSince(date) }
        if date > end { return date.timeIntervalSince(end) }
        return 0
    }
}

/// Imported Perspective logs, stored as copies inside the app's own directory.
struct FlightLogLibrary: Sendable {
    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(baseDirectory: URL) {
        directory = baseDirectory.appendingPathComponent("FlightLogs", isDirectory: true)
    }

    func loadIndex() throws -> [FlightLogEntry] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try EventPersistence.decoder.decode([FlightLogEntry].self, from: data).sorted { $0.start > $1.start }
    }

    func saveIndex(_ entries: [FlightLogEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try EventPersistence.encoder.encode(entries).write(to: indexURL, options: [.atomic])
    }

    /// Parses `data` as a Perspective log and stores a copy. Re-importing the same log replaces it.
    func importLog(data: Data, originalFilename: String, existing: [FlightLogEntry]) throws -> (entry: FlightLogEntry, log: PerspectiveLog, index: [FlightLogEntry]) {
        let storedName = Self.storedFilename(for: originalFilename)
        let log = try PerspectiveLogParser.parse(data: data, filename: storedName)
        guard let start = log.start, let end = log.end else { throw PerspectiveLogError.noSamples }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(storedName), options: [.atomic])

        let entry = FlightLogEntry(filename: storedName, originalFilename: originalFilename, start: start, end: end,
                                   sampleCount: log.sampleCount, airframeName: log.airframeName,
                                   systemID: log.systemID,
                                   // Whole seconds, so the entry survives the ISO-8601 index round trip unchanged.
                                   importedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
        var index = existing.filter { $0.filename != storedName }
        index.append(entry)
        index.sort { $0.start > $1.start }
        try saveIndex(index)
        // Keep a compact summary for N63KA's normal ranges; a failure here must not lose the import.
        try? saveSummary(FlightSummarizer.summarize(log))
        return (entry, log, index)
    }

    // MARK: - Flight summaries (for N63KA's normal ranges)

    private var summaryDirectory: URL { directory.appendingPathComponent("Summaries", isDirectory: true) }

    private func summaryURL(_ filename: String) -> URL {
        summaryDirectory.appendingPathComponent(filename + ".summary.json")
    }

    func saveSummary(_ summary: FlightSummary) throws {
        try FileManager.default.createDirectory(at: summaryDirectory, withIntermediateDirectories: true)
        try EventPersistence.encoder.encode(summary).write(to: summaryURL(summary.filename), options: [.atomic])
    }

    func loadSummary(for filename: String) -> FlightSummary? {
        guard let data = try? Data(contentsOf: summaryURL(filename)) else { return nil }
        return try? EventPersistence.decoder.decode(FlightSummary.self, from: data)
    }

    /// Summaries for every log in the index; logs imported before v0.4 are summarized now and saved.
    func loadOrBuildSummaries(for entries: [FlightLogEntry]) -> [FlightSummary] {
        entries.compactMap { entry in
            if let s = loadSummary(for: entry.filename), s.isCurrent { return s }
            guard let log = try? loadLog(entry) else { return nil }
            let s = FlightSummarizer.summarize(log)
            try? saveSummary(s)
            return s
        }
    }

    func loadLog(_ entry: FlightLogEntry) throws -> PerspectiveLog {
        let data = try Data(contentsOf: directory.appendingPathComponent(entry.filename))
        return try PerspectiveLogParser.parse(data: data, filename: entry.filename)
    }

    func delete(_ entry: FlightLogEntry, from index: [FlightLogEntry]) throws -> [FlightLogEntry] {
        let url = directory.appendingPathComponent(entry.filename)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try? FileManager.default.removeItem(at: summaryURL(entry.filename))
        let remaining = index.filter { $0.filename != entry.filename }
        try saveIndex(remaining)
        return remaining
    }

    /// The log containing `date`, or else the nearest log within `tolerance` seconds.
    static func bestMatch(for date: Date, in entries: [FlightLogEntry], tolerance: TimeInterval = 600) -> FlightLogEntry? {
        entries
            .filter { $0.covers(date, tolerance: tolerance) }
            .min { $0.distance(to: date) < $1.distance(to: date) }
    }

    /// Keeps only safe filename characters; ensures a .csv extension.
    static func storedFilename(for original: String) -> String {
        let base = (original as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if cleaned.isEmpty || cleaned.hasPrefix(".") { cleaned = "log_" + cleaned }
        if !cleaned.lowercased().hasSuffix(".csv") { cleaned += ".csv" }
        return cleaned
    }
}

/// CSV export of event markers for maintenance or records.
enum EventExporter {
    static func csv(_ events: [DiagnosticEvent]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var lines = ["id,timestamp_utc,local_time,utc_offset_seconds,time_zone,system,note,flight_log"]
        for e in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = e.captureTimeZone
            local.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let fields = [e.id.uuidString, iso.string(from: e.timestamp), local.string(from: e.timestamp),
                          String(e.utcOffsetSeconds), e.timeZoneIdentifier, e.system.rawValue, e.note,
                          e.flightLogFilename ?? ""]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
