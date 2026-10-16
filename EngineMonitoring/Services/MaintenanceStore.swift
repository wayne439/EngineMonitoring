import Foundation

/// Maintenance items (built-in and your own) and every recorded check or service. Saved on the device.
@MainActor
final class MaintenanceStore: ObservableObject {
    @Published private(set) var items: [MaintenanceItem] = []
    @Published private(set) var entries: [MaintenanceEntry] = []
    @Published var lastError: String?
    /// When the pilot last changed anything here (drives sync between devices).
    @Published private(set) var modifiedAt: Date = .distantPast
    private static let modifiedKey = "EM.sync.maintenance.modified"

    private let directory: URL
    private var itemsURL: URL { directory.appendingPathComponent("items.json") }
    private var entriesURL: URL { directory.appendingPathComponent("entries.json") }
    /// Called after any change, e.g. to reschedule reminders.
    var onChange: (@MainActor () -> Void)?

    init(baseDirectory: URL = EventPersistence.defaultDirectory()) {
        directory = baseDirectory.appendingPathComponent("Maintenance", isDirectory: true)
        modifiedAt = UserDefaults.standard.object(forKey: Self.modifiedKey) as? Date ?? .distantPast
        load()
        // Records saved before sync existed: date them by the file so they win over an empty device.
        if modifiedAt == .distantPast, !entries.isEmpty || items.contains(where: { !$0.builtIn || $0.userEdited == true }) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: entriesURL.path)
            modifiedAt = attrs?[.modificationDate] as? Date ?? Date()
            UserDefaults.standard.set(modifiedAt, forKey: Self.modifiedKey)
        }
    }

    private func load() {
        var saved: [MaintenanceItem] = []
        if let data = try? Data(contentsOf: itemsURL) {
            do { saved = try EventPersistence.decoder.decode([MaintenanceItem].self, from: data) } catch {
                lastError = "Maintenance items could not be read: \(error.localizedDescription)"
            }
        }
        // Built-in items you have not saved yet are added; your edits to built-ins are kept.
        // Built-in items take the current text and fields; a schedule you edited is kept.
        saved = saved.map { s in
            guard s.builtIn, var d = MaintenanceSchedule.defaults.first(where: { $0.id == s.id }) else { return s }
            if s.userEdited == true {
                d.intervalDays = s.intervalDays; d.intervalHours = s.intervalHours; d.warnDays = s.warnDays; d.userEdited = true
            }
            return d
        }
        let savedIDs = Set(saved.map(\.id))
        items = saved + MaintenanceSchedule.defaults.filter { !savedIDs.contains($0.id) }
        if let data = try? Data(contentsOf: entriesURL) {
            do { entries = try EventPersistence.decoder.decode([MaintenanceEntry].self, from: data) } catch {
                lastError = "Maintenance records could not be read: \(error.localizedDescription)"
            }
        }
        // Starting records (none for a new aircraft), added once for items with no records yet.
        let seededURL = directory.appendingPathComponent("baseline-2026-10-07")
        if !FileManager.default.fileExists(atPath: seededURL.path) {
            let seeds = MaintenanceSchedule.baselineEntries().filter { seed in !entries.contains { $0.itemID == seed.itemID && $0.by != "Logbook" } }
            entries += seeds.filter { seed in !entries.contains { $0.itemID == seed.itemID && $0.date == seed.date } }
            save(bump: false)
            try? Data().write(to: seededURL)
        }
    }

    /// Today's estimated total time: last recorded tach plus flight hours from the logs.
    func estimatedTach(summaries: [FlightSummary]) -> (value: Double, anchor: Double, anchorDate: Date)? {
        MaintenanceSchedule.estimatedTach(entries: entries, summaries: summaries)
    }

    func item(_ id: String) -> MaintenanceItem? { items.first { $0.id == id } }

    func entries(for itemID: String) -> [MaintenanceEntry] {
        entries.filter { $0.itemID == itemID }.sorted { $0.date > $1.date }
    }

    func status(_ item: MaintenanceItem, summaries: [FlightSummary], now: Date = Date()) -> MaintenanceStatus {
        MaintenanceSchedule.status(of: item, entries: entries, summaries: summaries, now: now)
    }

    func record(_ entry: MaintenanceEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        save()
    }

    func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func upsert(_ item: MaintenanceItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        save()
    }

    /// Your own items can be removed with their records; built-in items stay.
    func removeItem(_ id: String) {
        guard let item = item(id), !item.builtIn else { return }
        items.removeAll { $0.id == id }
        entries.removeAll { $0.itemID == id }
        save()
    }

    /// Every record as CSV for the shop, the owner's records or the Claude review.
    func csv() -> String {
        var lines = ["item,date,result,values,notes,by"]
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let f = ISO8601DateFormatter()
        for e in entries.sorted(by: { $0.date > $1.date }) {
            guard let item = item(e.itemID) else { continue }
            let vals = item.fields.compactMap { fl in e.values[fl.key].map { "\(fl.label)=\($0)" } }.joined(separator: "; ")
            let result = e.problems(for: item)
            lines.append([q(item.name), f.string(from: e.date), q(result.isEmpty ? "pass" : "fail: " + result.joined(separator: "; ")),
                          q(vals), q(e.notes), q(e.by)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Replaces everything with the copy from another device (newer than this one's).
    func replaceFromCloud(items: [MaintenanceItem], entries: [MaintenanceEntry], modified: Date) {
        self.items = items
        self.entries = entries
        save(bump: false)
        modifiedAt = modified
        UserDefaults.standard.set(modified, forKey: Self.modifiedKey)
        onChange?()
    }

    private func save(bump: Bool = true) {
        if bump {
            modifiedAt = Date()
            UserDefaults.standard.set(modifiedAt, forKey: Self.modifiedKey)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try EventPersistence.encoder.encode(items).write(to: itemsURL, options: [.atomic])
            try EventPersistence.encoder.encode(entries).write(to: entriesURL, options: [.atomic])
        } catch {
            lastError = "Maintenance could not be saved: \(error.localizedDescription)"
        }
        onChange?()
    }
}
