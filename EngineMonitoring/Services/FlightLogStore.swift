import Foundation

@MainActor
final class FlightLogStore: ObservableObject {
    @Published private(set) var entries: [FlightLogEntry] = []
    @Published var lastError: String?
    @Published private(set) var isImporting = false
    /// One-line result of the last import ("Imported 3 new flights."), for a confirmation message.
    @Published var importSummary: String?
    /// One compact summary per imported log; the aircraft's normal ranges are built from these.
    @Published private(set) var summaries: [String: FlightSummary] = [:]
    @Published private(set) var isSummarizing = false
    /// Flights bundled with the app (none in AI Engine Monitoring; kept so older code paths still work).
    let bundled: BundledFlightHistory?
    private let bundledByName: [String: FlightSummary]

    private let library: FlightLogLibrary
    /// Parsed logs kept in memory; a large log is several MB once parsed, so keep only a few.
    private var cache: [String: PerspectiveLog] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 3

    init(baseDirectory: URL = EventPersistence.defaultDirectory(), bundledHistoryURL: URL? = BundledFlightHistory.bundleURL) {
        library = FlightLogLibrary(baseDirectory: baseDirectory)
        bundled = BundledFlightHistory.load(from: bundledHistoryURL)
        bundledByName = Dictionary((bundled?.summaries ?? []).map { ($0.filename, $0) }, uniquingKeysWith: { a, _ in a })
        summaries = bundledByName
        do { entries = try library.loadIndex() } catch {
            lastError = "Flight log index could not be read: \(error.localizedDescription)"
        }
        Task { await refreshSummaries() }
    }

    /// the aircraft's normal ranges from every imported flight (optionally leaving one log out).
    func baseline(excluding filename: String? = nil) -> Baseline {
        Baseline.build(from: summaries.values.filter { $0.filename != filename })
    }

    /// Loads saved summaries and builds any that are missing (logs imported before v0.4).
    func refreshSummaries() async {
        isSummarizing = true
        defer { isSummarizing = false }
        let library = self.library
        let entries = self.entries
        let loaded = await Task.detached(priority: .utility) { library.loadOrBuildSummaries(for: entries) }.value
        // Imported logs replace the bundled summary of the same file.
        summaries = bundledByName.merging(loaded.map { ($0.filename, $0) }, uniquingKeysWith: { _, imported in imported })
    }

    /// Post-flight report for one log, compared with every other imported flight.
    func report(for entry: FlightLogEntry, markers: [DiagnosticEvent]) async -> FlightReport? {
        guard let log = await log(for: entry) else { return nil }
        let history = Array(summaries.values)
        return await Task.detached(priority: .userInitiated) {
            FlightReport.build(log: log, history: history, markers: markers)
        }.value
    }

    /// Imports Perspective CSV files picked by the user (security-scoped URLs from the file importer).
    func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                let existing = entries
                let library = self.library
                // Parsing a multi-MB log takes noticeable time; keep it off the main thread.
                let result = try await Task.detached(priority: .userInitiated) {
                    try library.importLog(data: data, originalFilename: name, existing: existing)
                }.value
                entries = result.index
                remember(result.log)
                if let summary = await Task.detached(priority: .utility, operation: { library.loadSummary(for: result.entry.filename) }).value {
                    summaries[summary.filename] = summary
                }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { lastError = "Some files were not imported.\n" + failures.joined(separator: "\n") }
        let added = urls.count - failures.count
        importSummary = added > 0 ? "Imported \(added) flight\(added == 1 ? "" : "s")." : nil
    }

    // MARK: SD card folder import

    private static let folderBookmarkKey = "EM.logFolderBookmark"

    /// True once a data_log folder has been chosen, so "Import new flights" is one tap.
    var hasSavedFolder: Bool { UserDefaults.standard.data(forKey: Self.folderBookmarkKey) != nil }

    /// Engine log files in a folder (and one level of subfolders) that have not been imported yet.
    /// nil when the folder cannot be read (card removed, or access lost).
    static func newLogFiles(in folder: URL, existing: [FlightLogEntry]) -> [URL]? {
        let known = Set(existing.map { $0.originalFilename.lowercased() })
        let fm = FileManager.default
        var found: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let top = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        for url in top {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                found += (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            } else {
                found.append(url)
            }
        }
        return found
            .filter { $0.pathExtension.lowercased() == "csv" && !known.contains($0.lastPathComponent.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Imports every new log in a folder the pilot picked (the SD card's data_log folder) and remembers the folder.
    func importFolder(_ folder: URL) async {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.folderBookmarkKey)
        }
        guard let files = Self.newLogFiles(in: folder, existing: entries) else {
            UserDefaults.standard.removeObject(forKey: Self.folderBookmarkKey)
            lastError = "That folder could not be opened. Insert the card and choose the data_log folder again."
            return
        }
        if files.isEmpty {
            importSummary = "No new flights on the card. Everything there is already imported."
            return
        }
        await importFiles(files)
    }

    /// One tap: imports new logs from the folder chosen last time. Returns false when the folder must be picked again
    /// (first use, or the card was swapped).
    func importFromSavedFolder() async -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.folderBookmarkKey) else { return false }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              !stale else {
            UserDefaults.standard.removeObject(forKey: Self.folderBookmarkKey)
            return false
        }
        await importFolder(folder)
        return true
    }

    func delete(_ entry: FlightLogEntry) {
        do {
            entries = try library.delete(entry, from: entries)
            summaries[entry.filename] = bundledByName[entry.filename]
            cache[entry.filename] = nil
            cacheOrder.removeAll { $0 == entry.filename }
        } catch {
            lastError = "Log could not be deleted: \(error.localizedDescription)"
        }
    }

    /// The stored copy of an imported log file (for cloud upload).
    func fileURL(for entry: FlightLogEntry) -> URL {
        library.directory.appendingPathComponent(entry.filename)
    }

    /// Summary for a flight (imported or bundled).
    func summary(named filename: String) -> FlightSummary? { summaries[filename] }

    func entry(named filename: String?) -> FlightLogEntry? {
        guard let filename else { return nil }
        return entries.first { $0.filename == filename }
    }

    func bestMatch(for event: DiagnosticEvent) -> FlightLogEntry? {
        FlightLogLibrary.bestMatch(for: event.timestamp, in: entries)
    }

    /// Loads (and caches) the parsed log for an entry.
    func log(for entry: FlightLogEntry) async -> PerspectiveLog? {
        if let cached = cache[entry.filename] { return cached }
        let library = self.library
        do {
            let log = try await Task.detached(priority: .userInitiated) { try library.loadLog(entry) }.value
            remember(log)
            return log
        } catch {
            lastError = "\(entry.originalFilename) could not be read: \(error.localizedDescription)"
            return nil
        }
    }

    private func remember(_ log: PerspectiveLog) {
        cache[log.filename] = log
        cacheOrder.removeAll { $0 == log.filename }
        cacheOrder.append(log.filename)
        while cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }
}
