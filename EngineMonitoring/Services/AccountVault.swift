import Foundation

/// Keeps each account's data on this device when another account signs in, so switching back is instant:
/// no re-download of flights, no re-reading of logs, and nothing recorded on this device is lost.
///
/// Everything an account owns on the device lives in two folders (Application Support/EngineMonitoring and
/// Application Support/Manuals) plus the app's "EM." settings. Switching moves the current account's copy into
/// Application Support/AccountVault/<user id>/ and moves the incoming account's copy (if this device has one) back.
/// The two accounts' data never mix: only one account's copy is in place at a time.
@MainActor
enum AccountVault {
    /// Settings that belong to the device, not to an account.
    private static let deviceKeys: Set<String> = ["EM.deviceOwner"]

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// The folders holding one account's data on this device.
    private static var dataFolders: [URL] {
        [EventPersistence.defaultDirectory(), POHRepository.folder]
    }

    private static func vault(_ uid: String) -> URL {
        appSupport.appendingPathComponent("AccountVault", isDirectory: true).appendingPathComponent(uid.lowercased(), isDirectory: true)
    }

    static func hasCopy(of uid: String) -> Bool {
        FileManager.default.fileExists(atPath: vault(uid).path)
    }

    /// Moves the current data into `previous`'s vault and brings `next`'s vault back if this device has one.
    /// Returns true when `next`'s data was restored (false: start clean and fill from the cloud).
    @discardableResult
    static func switchAccount(from previous: String, to next: String, defaults: UserDefaults = .standard) -> Bool {
        let fm = FileManager.default
        // 1. Put the outgoing account's data away (replacing any older copy of it).
        let out = vault(previous)
        try? fm.removeItem(at: out)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        for folder in dataFolders where fm.fileExists(atPath: folder.path) {
            try? fm.moveItem(at: folder, to: out.appendingPathComponent(folder.lastPathComponent, isDirectory: true))
        }
        var settings: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("EM.") && !deviceKeys.contains(key) {
            settings[key] = value
            defaults.removeObject(forKey: key)
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0) {
            try? data.write(to: out.appendingPathComponent("settings.plist"))
        }

        // 2. Bring the incoming account's data back.
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
            for (key, value) in saved where !deviceKeys.contains(key) { defaults.set(value, forKey: key) }
        }
        try? fm.removeItem(at: incoming)
        return true
    }
}
