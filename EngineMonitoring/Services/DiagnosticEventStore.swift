import Foundation

@MainActor
final class DiagnosticEventStore: ObservableObject {
    @Published private(set) var events: [DiagnosticEvent] = []
    /// Last storage error, shown to the pilot rather than silently dropped.
    @Published var lastError: String?

    private let persistence: EventPersistence
    private let defaults: UserDefaults
    private static let legacyKey = "EM.DiagnosticEvents.v1"

    init(directory: URL = EventPersistence.defaultDirectory(), defaults: UserDefaults = .standard) {
        persistence = EventPersistence(directory: directory)
        self.defaults = defaults
        load()
    }

    /// Records a marker at this instant. Call this the moment the pilot taps; details come later.
    @discardableResult
    func markNow(at date: Date = Date()) -> DiagnosticEvent {
        let event = DiagnosticEvent(timestamp: date)
        events.insert(event, at: 0)
        save()
        return event
    }

    func update(_ event: DiagnosticEvent) {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updated = event
        updated.note = event.note.trimmingCharacters(in: .whitespacesAndNewlines)
        events[i] = updated
        save()
    }

    func delete(ids: Set<UUID>) {
        events.removeAll { ids.contains($0.id) }
        save()
    }

    func event(id: UUID) -> DiagnosticEvent? { events.first { $0.id == id } }

    private func save() {
        do { try persistence.save(events) } catch {
            lastError = "Event markers could not be saved: \(error.localizedDescription)"
        }
    }

    private func load() {
        do {
            events = try persistence.load()
        } catch {
            lastError = "Saved event markers could not be read: \(error.localizedDescription)"
        }
        migrateFromUserDefaultsIfNeeded()
    }

    /// One-time move of v0.2 markers from UserDefaults into the file store.
    private func migrateFromUserDefaultsIfNeeded() {
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        do {
            let legacy = try EventPersistence.decodeLegacy(data)
            let known = Set(events.map(\.id))
            events = (events + legacy.filter { !known.contains($0.id) }).sorted { $0.timestamp > $1.timestamp }
            try persistence.save(events)
            defaults.removeObject(forKey: Self.legacyKey)
        } catch {
            lastError = "Older event markers could not be migrated: \(error.localizedDescription)"
        }
    }
}
