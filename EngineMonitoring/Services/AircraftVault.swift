import Foundation

/// Several aircraft in one account. Only the selected aircraft's data is in place on the device (flights, profile,
/// POH, maintenance, issue reviews, markers); the others wait in Application Support/AircraftVault/<aircraft id>/,
/// so switching is instant and nothing is re-downloaded. Each aircraft's data also lives in the cloud under its id.
@MainActor
enum AircraftVault {
    /// Settings that belong to one aircraft (the rest of the "EM." settings belong to the account or device).
    static let aircraftKeyPrefixes = ["EM.cloud.uploadedLogs", "EM.sync.", "EM.importedLogSources", "EM.cloud.summaryVersion",
                                      "EM.DiagnosticEvents", "EM.cloud.profileRestored."]

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AircraftVault", isDirectory: true)
    }

    private static var dataFolders: [URL] { [EventPersistence.defaultDirectory(), POHRepository.folder] }

    private static func vault(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private static func isAircraftKey(_ key: String) -> Bool {
        aircraftKeyPrefixes.contains { key.hasPrefix($0) }
    }

    static func hasCopy(of id: UUID) -> Bool { FileManager.default.fileExists(atPath: vault(id).path) }

    /// Removes a stored aircraft (for example one that was sold).
    static func discard(_ id: UUID) { try? FileManager.default.removeItem(at: vault(id)) }

    /// Puts `current`'s data away and brings `next`'s back if this device has it.
    /// Returns true when `next`'s data was restored (false: it starts empty and fills from the cloud).
    @discardableResult
    static func switchAircraft(from current: UUID, to next: UUID, defaults: UserDefaults = .standard) -> Bool {
        let fm = FileManager.default
        let out = vault(current)
        try? fm.removeItem(at: out)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        for folder in dataFolders where fm.fileExists(atPath: folder.path) {
            try? fm.moveItem(at: folder, to: out.appendingPathComponent(folder.lastPathComponent, isDirectory: true))
        }
        var settings: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("EM.") && isAircraftKey(key) {
            settings[key] = value
            defaults.removeObject(forKey: key)
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0) {
            try? data.write(to: out.appendingPathComponent("settings.plist"))
        }

        let incoming = vault(next)
        guard fm.fileExists(atPath: incoming.path) else { return false }
        for folder in dataFolders {
            let saved = incoming.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            guard fm.fileExists(atPath: saved.path) else { continue }
            try? fm.removeItem(at: folder)
            try? fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: saved, to: folder)
        }
        if let data = try? Data(contentsOf: incoming.appendingPathComponent("settings.plist")),
           let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in saved where isAircraftKey(key) { defaults.set(value, forKey: key) }
        }
        try? fm.removeItem(at: incoming)
        return true
    }
}

/// Switching the selected aircraft: puts this aircraft's data aside, brings the other one's back (or starts it
/// empty), reloads every store, then fills anything missing from the cloud.
@MainActor
enum AircraftSwitcher {
    static func switchTo(_ id: UUID, cloud: CloudStore, aircraft: AircraftProfileStore, logs: FlightLogStore,
                         maintenance: MaintenanceStore, issues: IssueStore, events: DiagnosticEventStore, poh: POHRepository,
                         syncFromCloud: Bool = true, newProfile: AircraftProfile? = nil) async {
        let current = cloud.aircraftID
        guard id != current else { return }
        // Nothing uploads until the new aircraft has loaded (a blank profile must never overwrite it).
        cloud.holdSync = true
        defer { cloud.holdSync = false }
        AircraftVault.switchAircraft(from: current, to: id)
        cloud.setActiveAircraft(id)
        aircraft.reloadFromDisk()
        // A just-added aircraft starts with the details entered for it.
        if let newProfile { aircraft.profile = newProfile }
        maintenance.reloadFromDisk()
        issues.reloadFromDisk()
        events.reloadFromDisk()
        await poh.load()
        await logs.reloadFromDisk()
        await issues.refresh(summaries: Array(logs.summaries.values))
        guard syncFromCloud else { return }
        await cloud.restore(aircraft: aircraft, logs: logs)
        cloud.holdSync = false
        await cloud.syncAppState(maintenance: maintenance, issues: issues, events: events)
        await cloud.pullInbox(logs: logs)
        await poh.syncFromUploads(cloud: cloud)
        await cloud.sync(profile: aircraft.profile, logs: logs)
    }
}
