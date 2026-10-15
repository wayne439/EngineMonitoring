import Foundation
import CryptoKit
import Security

// Cloud storage for subscribers: Sign in with Apple, then the aircraft profile, engine log files and
// flight summaries are stored in the subscriber's own Supabase account (see supabase/README.md).
// Plain URLSession calls, no third-party SDK. Everything is optional: with no keys in Info.plist the
// app stays in local-only mode.

/// Project URL and public (anon) key from Info.plist. nil = cloud not set up in this build.
struct CloudConfig: Sendable {
    let url: URL
    let anonKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> CloudConfig? {
        guard let raw = bundle.object(forInfoDictionaryKey: "EMSupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "EMSupabaseAnonKey") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty, !key.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return CloudConfig(url: url, anonKey: key.trimmingCharacters(in: .whitespaces))
    }
}

/// A signed-in session (kept in the Keychain).
struct CloudSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
}

enum CloudError: LocalizedError {
    case notConfigured
    case notSignedIn
    case server(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud storage is not set up in this build."
        case .notSignedIn: return "Sign in first."
        case .server(let code, let body): return body.isEmpty ? "Server error \(code)." : String(body.prefix(300))
        case .badResponse: return "Unexpected response from the server."
        }
    }
}

/// Raw calls to Supabase Auth, the REST API (PostgREST) and Storage.
struct CloudAPI: Sendable {
    let config: CloudConfig
    static let bucket = "engine-logs"

    // MARK: Auth

    /// Exchanges Apple's identity token for a Supabase session. `nonce` is the raw nonce whose SHA-256 was sent to Apple.
    func signInWithApple(idToken: String, nonce: String) async throws -> CloudSession {
        let body: [String: Any] = ["provider": "apple", "id_token": idToken, "nonce": nonce]
        let data = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")], json: body, token: nil)
        return try Self.session(from: data)
    }

    /// Creates an account with email and password. Returns a session when the project does not require
    /// email confirmation, or nil when Supabase has emailed a confirmation link first.
    func signUp(email: String, password: String, fullName: String) async throws -> CloudSession? {
        let body: [String: Any] = ["email": email, "password": password, "data": ["full_name": fullName]]
        let data = try await send("POST", "auth/v1/signup", query: [], json: body, token: nil)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudError.badResponse }
        return obj["access_token"] == nil ? nil : try Self.session(from: data)
    }

    func signIn(email: String, password: String) async throws -> CloudSession {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], json: body, token: nil)
        return try Self.session(from: data)
    }

    /// Emails a password-reset link.
    func resetPassword(email: String) async throws {
        _ = try await send("POST", "auth/v1/recover", query: [], json: ["email": email], token: nil)
    }

    func refresh(_ session: CloudSession) async throws -> CloudSession {
        let body: [String: Any] = ["refresh_token": session.refreshToken]
        let data = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], json: body, token: nil)
        return try Self.session(from: data)
    }

    static func session(from data: Data) throws -> CloudSession {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String,
              let user = obj["user"] as? [String: Any],
              let id = user["id"] as? String else { throw CloudError.badResponse }
        let expiresIn = (obj["expires_in"] as? Double) ?? (obj["expires_in"] as? Int).map { Double($0) } ?? 3600
        return CloudSession(accessToken: access, refreshToken: refresh,
                            expiresAt: Date().addingTimeInterval(expiresIn), userID: id, email: user["email"] as? String)
    }

    // MARK: Database rows

    /// Insert or update rows (PostgREST upsert on the given conflict columns).
    func upsert(table: String, rows: [[String: Any]], onConflict: String, token: String) async throws {
        _ = try await send("POST", "rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: onConflict)],
                           json: rows, token: token,
                           extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    func select(table: String, query: [URLQueryItem], token: String) async throws -> [[String: Any]] {
        let data = try await send("GET", "rest/v1/\(table)", query: query, json: nil, token: token)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func rpc(_ function: String, token: String) async throws {
        _ = try await send("POST", "rest/v1/rpc/\(function)", query: [], json: [String: Any](), token: token)
    }

    // MARK: Files

    func uploadFile(path: String, data: Data, contentType: String, token: String) async throws {
        var request = makeRequest("POST", "storage/v1/object/\(Self.bucket)/\(path)", query: [], token: token)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        _ = try await perform(request)
    }

    func downloadFile(path: String, token: String) async throws -> Data {
        let request = makeRequest("GET", "storage/v1/object/\(Self.bucket)/\(path)", query: [], token: token)
        return try await perform(request)
    }

    /// Updates rows matching `filter` (PostgREST, e.g. ["id": "eq.<uuid>"]).
    func update(table: String, filter: [String: String], values: [String: Any], token: String) async throws {
        _ = try await send("PATCH", "rest/v1/\(table)", query: filter.map { URLQueryItem(name: $0.key, value: $0.value) },
                           json: values, token: token, extraHeaders: ["Prefer": "return=minimal"])
    }

    func deleteFiles(paths: [String], token: String) async throws {
        guard !paths.isEmpty else { return }
        _ = try await send("DELETE", "storage/v1/object/\(Self.bucket)", query: [], json: ["prefixes": paths], token: token)
    }

    // MARK: Plumbing

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], token: String?) -> URLRequest {
        var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        var request = URLRequest(url: components?.url ?? config.url.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem], json: Any?, token: String?,
                      extraHeaders: [String: String] = [:]) async throws -> Data {
        var request = makeRequest(method, path, query: query, token: token)
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudError.server(http.statusCode, Self.message(from: data))
        }
        return data
    }

    /// The human-readable part of a Supabase error body ("msg", "error_description" or "message").
    static func message(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "error_description", "message", "error"] {
                if let text = obj[key] as? String, !text.isEmpty { return text }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Row building

    /// Postgres timestamps come back with or without fractional seconds.
    static func parseDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// A Codable value as a JSON object for a jsonb column.
    static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: EventPersistence.encoder.encode(value))
    }

    /// JSON null for a missing value.
    static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    static func aircraftRow(id: UUID, profile: AircraftProfile) throws -> [String: Any] {
        var row: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "tail_number": profile.tailNumber,
            "make": profile.make,
            "model": profile.model,
            "engine_model": profile.engineModel,
            "cylinders": profile.cylinders,
            "is_turbocharged": profile.isTurbocharged,
            "monitor": profile.monitor.rawValue,
            "limits_confirmed": profile.limitsConfirmedByOwner,
            "profile": try jsonObject(profile),
        ]
        row["year"] = orNull(profile.year > 0 ? profile.year : nil)
        return row
    }

    static func logPath(userID: String, aircraftID: UUID, filename: String) -> String {
        "\(userID.lowercased())/\(aircraftID.uuidString.lowercased())/\(filename)"
    }

    static func flightLogRow(aircraftID: UUID, entry: FlightLogEntry, path: String, size: Int, summary: FlightSummary?) throws -> [String: Any] {
        var row: [String: Any] = [
            "aircraft_id": aircraftID.uuidString.lowercased(),
            "filename": entry.filename,
            "original_filename": entry.originalFilename,
            "started_at": isoFormatter.string(from: entry.start),
            "ended_at": isoFormatter.string(from: entry.end),
            "sample_count": entry.sampleCount,
            "storage_path": path,
            "size_bytes": size,
        ]
        row["airframe_name"] = orNull(entry.airframeName)
        row["system_id"] = orNull(entry.systemID)
        row["summary"] = orNull(try summary.map { try jsonObject($0) })
        return row
    }

    // MARK: Sign in with Apple nonce

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(generator.next() % UInt64(chars.count))] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A file in the subscriber's cloud inbox (uploaded on the website, shared to the app, or later by a data link).
struct InboxItem: Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let storagePath: String
    let category: String
    let format: String
    let status: String
    let source: String
    let receivedAt: Date?

    static let categories: [(id: String, title: String)] = [
        ("logs", "Engine monitor logs"),
        ("poh-limits", "POH / AFM engine limits"),
        ("logbook", "Logbook entries (annual, oil changes)"),
        ("engine-time", "Engine times and overhaul records"),
        ("turbo", "Turbo limits / supplement"),
        ("oil-analysis", "Oil analysis reports"),
        ("squawks", "Open squawks / recent engine work"),
        ("other", "Other"),
    ]

    var categoryTitle: String { Self.categories.first { $0.id == category }?.title ?? category }

    var isLog: Bool { category == "logs" && filename.lowercased().hasSuffix(".csv") }

    init?(row: [String: Any]) {
        guard let id = row["id"] as? String, let name = row["original_filename"] as? String,
              let path = row["storage_path"] as? String else { return nil }
        self.id = id
        filename = name
        storagePath = path
        category = row["category"] as? String ?? "other"
        format = row["format"] as? String ?? "unknown"
        status = row["status"] as? String ?? "received"
        source = row["source"] as? String ?? "app"
        receivedAt = (row["received_at"] as? String).flatMap { CloudAPI.parseDate($0) }
    }
}

/// Stores the session in the Keychain (this device only).
enum CloudKeychain {
    private static let service = "com.fueledconsulting.EngineMonitoring.cloud"
    private static let account = "session"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> CloudSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? EventPersistence.decoder.decode(CloudSession.self, from: data)
    }

    static func save(_ session: CloudSession?) {
        SecItemDelete(query as CFDictionary)
        guard let session, let data = try? EventPersistence.encoder.encode(session) else { return }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// The subscriber's cloud account for the UI: sign-in state, sync status and the actions.
@MainActor
final class CloudStore: ObservableObject {
    @Published private(set) var session: CloudSession?
    @Published private(set) var isBusy = false
    @Published private(set) var status: String?
    @Published var lastError: String?
    @Published private(set) var uploadedLogs: Set<String>
    @Published private(set) var lastSync: Date?
    /// Documents and files in the cloud inbox (everything except logs already turned into flights).
    @Published private(set) var inboxItems: [InboxItem] = []

    let api: CloudAPI?
    /// Cloud id of this device's aircraft (one aircraft per device for now).
    let aircraftID: UUID
    private let defaults: UserDefaults

    private static let aircraftIDKey = "EM.cloud.aircraftID"
    private static let uploadedKey = "EM.cloud.uploadedLogs"
    private static let lastSyncKey = "EM.cloud.lastSync"

    init(config: CloudConfig? = CloudConfig.fromBundle(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        api = config.map { CloudAPI(config: $0) }
        if let raw = defaults.string(forKey: Self.aircraftIDKey), let id = UUID(uuidString: raw) {
            aircraftID = id
        } else {
            let id = UUID()
            defaults.set(id.uuidString, forKey: Self.aircraftIDKey)
            aircraftID = id
        }
        uploadedLogs = Set(defaults.stringArray(forKey: Self.uploadedKey) ?? [])
        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
        session = api == nil ? nil : CloudKeychain.load()
    }

    var isConfigured: Bool { api != nil }
    var isSignedIn: Bool { session != nil }

    // MARK: Sign in / out

    func signIn(idToken: String, nonce: String) async {
        guard let api else { lastError = CloudError.notConfigured.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            let s = try await api.signInWithApple(idToken: idToken, nonce: nonce)
            setSession(s)
            status = "Signed in."
            lastError = nil
        } catch {
            lastError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    /// Registers with email and password. True when the account was created (signed in, or waiting for email confirmation).
    func register(email: String, password: String, fullName: String) async -> Bool {
        guard let api else { lastError = CloudError.notConfigured.localizedDescription; return false }
        isBusy = true
        defer { isBusy = false }
        do {
            if let s = try await api.signUp(email: email, password: password, fullName: fullName) {
                setSession(s)
                status = "Account created. You're signed in."
            } else {
                status = "Account created. Check \(email) for a confirmation link, then log in."
            }
            lastError = nil
            return true
        } catch {
            lastError = "Registration failed: \(error.localizedDescription)"
            return false
        }
    }

    func logIn(email: String, password: String) async -> Bool {
        guard let api else { lastError = CloudError.notConfigured.localizedDescription; return false }
        isBusy = true
        defer { isBusy = false }
        do {
            setSession(try await api.signIn(email: email, password: password))
            status = "Signed in."
            lastError = nil
            return true
        } catch {
            lastError = "Log in failed: \(error.localizedDescription)"
            return false
        }
    }

    func resetPassword(email: String) async {
        guard let api else { lastError = CloudError.notConfigured.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.resetPassword(email: email)
            status = "If an account exists for \(email), a reset link is on its way."
            lastError = nil
        } catch {
            lastError = "Could not send the reset email: \(error.localizedDescription)"
        }
    }

    func clearMessages() {
        status = nil
        lastError = nil
    }

    func signOut() {
        setSession(nil)
        uploadedLogs = []
        defaults.removeObject(forKey: Self.uploadedKey)
        status = "Signed out. Your data stays on this iPad and in your cloud account."
    }

    private func setSession(_ s: CloudSession?) {
        session = s
        CloudKeychain.save(s)
    }

    /// A valid access token, refreshed when it is about to expire.
    private func token() async throws -> (api: CloudAPI, session: CloudSession) {
        guard let api else { throw CloudError.notConfigured }
        guard var s = session else { throw CloudError.notSignedIn }
        if s.expiresAt.timeIntervalSinceNow < 120 {
            s = try await api.refresh(s)
            setSession(s)
        }
        return (api, s)
    }

    // MARK: Sync

    /// Uploads the aircraft profile, then every log not uploaded yet. Safe to call often.
    func sync(profile: AircraftProfile, logs: FlightLogStore) async {
        guard isConfigured, isSignedIn, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            try await api.upsert(table: "aircraft", rows: [CloudAPI.aircraftRow(id: aircraftID, profile: profile)],
                                 onConflict: "id", token: s.accessToken)
            var done = 0
            let pending = logs.entries.filter { !uploadedLogs.contains($0.filename) }
            for entry in pending {
                status = "Uploading \(done + 1) of \(pending.count): \(entry.originalFilename)"
                let data = try Data(contentsOf: logs.fileURL(for: entry))
                let path = CloudAPI.logPath(userID: s.userID, aircraftID: aircraftID, filename: entry.filename)
                try await api.uploadFile(path: path, data: data, contentType: "text/csv", token: s.accessToken)
                let row = try CloudAPI.flightLogRow(aircraftID: aircraftID, entry: entry, path: path, size: data.count,
                                                    summary: logs.summary(named: entry.filename))
                try await api.upsert(table: "flight_logs", rows: [row], onConflict: "aircraft_id,filename", token: s.accessToken)
                uploadedLogs.insert(entry.filename)
                defaults.set(Array(uploadedLogs), forKey: Self.uploadedKey)
                done += 1
            }
            lastSync = Date()
            defaults.set(lastSync, forKey: Self.lastSyncKey)
            status = pending.isEmpty ? "Up to date." : "Uploaded \(done) log\(done == 1 ? "" : "s")."
            lastError = nil
        } catch {
            lastError = "Sync stopped: \(error.localizedDescription)"
        }
    }

    // MARK: Inbox

    /// Saves a file the app cannot analyze yet (JPI, EI, other) to the subscriber's cloud inbox, so it can be
    /// processed when support arrives. Returns a message for the pilot.
    func uploadToInbox(fileURL: URL, source: String = "share", category: String = "logs") async -> String {
        guard isConfigured else { return "This file type can't be analyzed yet. Cloud storage isn't set up in this build, so it wasn't saved." }
        guard isSignedIn else { return "This file type can't be analyzed yet. Sign in (ACCOUNT) and share it again to save it to your account for when support arrives." }
        isBusy = true
        defer { isBusy = false }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let (api, s) = try await token()
            let data = try Data(contentsOf: fileURL)
            let name = fileURL.lastPathComponent
            let stamp = Int(Date().timeIntervalSince1970)
            let path = "\(s.userID.lowercased())/inbox/\(stamp)-\(FlightLogLibrary.storedFilename(for: name))"
            try await api.uploadFile(path: path, data: data, contentType: "application/octet-stream", token: s.accessToken)
            let format = Self.format(for: fileURL)
            let isDocument = category != "logs"
            let row: [String: Any] = [
                "aircraft_id": aircraftID.uuidString.lowercased(),
                "source": source,
                "category": category,
                "original_filename": name,
                "storage_path": path,
                "size_bytes": data.count,
                "format": format,
                "status": isDocument ? "stored" : "unsupported",
            ]
            // The aircraft row must exist before the inbox row can point at it.
            try await api.upsert(table: "aircraft", rows: [CloudAPI.aircraftRow(id: aircraftID, profile: AircraftProfileSnapshot.shared.profile)],
                                 onConflict: "id", token: s.accessToken)
            try await api.upsert(table: "inbox_uploads", rows: [row], onConflict: "id", token: s.accessToken)
            await refreshInbox()
            return isDocument
                ? "\(name) was saved to your account."
                : "\(name) was saved to your account. It will be analyzed when support for this file type arrives."
        } catch {
            return "\(fileURL.lastPathComponent) could not be saved: \(error.localizedDescription)"
        }
    }

    static func format(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "csv": return "garmin-csv"
        case "jpi": return "jpi"
        case "pdf": return "pdf"
        case "jpg", "jpeg", "png", "heic": return "image"
        default: return "unknown"
        }
    }

    /// Lists the inbox (newest first) for the Documents screen.
    func refreshInbox() async {
        guard isConfigured, isSignedIn else { inboxItems = []; return }
        do {
            let (api, s) = try await token()
            let rows = try await api.select(table: "inbox_uploads",
                                            query: [URLQueryItem(name: "select", value: "id,original_filename,storage_path,category,format,status,source,received_at"),
                                                    URLQueryItem(name: "order", value: "received_at.desc")],
                                            token: s.accessToken)
            inboxItems = rows.compactMap(InboxItem.init(row:))
        } catch {
            lastError = "Could not load your uploads: \(error.localizedDescription)"
        }
    }

    /// Brings uploads from the website into the app: engine log CSVs become flights, documents are kept
    /// in Documents. Runs when the app opens or comes back to the foreground.
    func pullInbox(logs: FlightLogStore) async {
        guard isConfigured, isSignedIn, !isBusy else { return }
        await refreshInbox()
        let waiting = inboxItems.filter { $0.status == "received" }
        guard !waiting.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        var imported = 0
        do {
            let (api, s) = try await token()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            for item in waiting {
                var newStatus = "stored"
                var detail: Any = NSNull()
                if item.isLog {
                    let data = try await api.downloadFile(path: item.storagePath, token: s.accessToken)
                    let file = folder.appendingPathComponent(item.filename)
                    try data.write(to: file)
                    logs.lastError = nil
                    await logs.importFiles([file])
                    if let error = logs.lastError {
                        newStatus = "failed"
                        detail = error
                        logs.lastError = nil
                    } else {
                        newStatus = "imported"
                        imported += 1
                    }
                } else if item.category == "logs" {
                    newStatus = "unsupported"
                }
                try await api.update(table: "inbox_uploads", filter: ["id": "eq.\(item.id)"],
                                     values: ["status": newStatus, "detail": detail,
                                              "processed_at": CloudAPI.isoFormatter.string(from: Date())],
                                     token: s.accessToken)
            }
            status = imported > 0 ? "Added \(imported) flight\(imported == 1 ? "" : "s") from your uploads." : "Your uploads are up to date."
            lastError = nil
        } catch {
            lastError = "Could not bring in your uploads: \(error.localizedDescription)"
        }
        await refreshInbox()
    }

    /// Downloads one inbox file to a temporary place for viewing.
    func download(_ item: InboxItem) async -> URL? {
        do {
            let (api, s) = try await token()
            let data = try await api.downloadFile(path: item.storagePath, token: s.accessToken)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.filename)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            lastError = "Could not open \(item.filename): \(error.localizedDescription)"
            return nil
        }
    }

    /// The aircraft saved in the cloud for this account (to restore a profile on a new device).
    func cloudProfile() async -> AircraftProfile? {
        do {
            let (api, s) = try await token()
            let rows = try await api.select(table: "aircraft",
                                            query: [URLQueryItem(name: "select", value: "profile"),
                                                    URLQueryItem(name: "order", value: "updated_at.desc"),
                                                    URLQueryItem(name: "limit", value: "1")],
                                            token: s.accessToken)
            guard let profile = rows.first?["profile"] else { return nil }
            let data = try JSONSerialization.data(withJSONObject: profile)
            return try EventPersistence.decoder.decode(AircraftProfile.self, from: data)
        } catch {
            lastError = "Could not read the cloud profile: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Delete account (App Store requirement)

    /// Deletes every uploaded file, then the account (its rows go with it). Local data on this iPad stays.
    func deleteAccount() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            let rows = try await api.select(table: "flight_logs", query: [URLQueryItem(name: "select", value: "storage_path")],
                                            token: s.accessToken)
            let inbox = try await api.select(table: "inbox_uploads", query: [URLQueryItem(name: "select", value: "storage_path")],
                                             token: s.accessToken)
            let paths = (rows + inbox).compactMap { $0["storage_path"] as? String }
            for start in stride(from: 0, to: paths.count, by: 100) {
                try await api.deleteFiles(paths: Array(paths[start..<min(start + 100, paths.count)]), token: s.accessToken)
            }
            try await api.rpc("delete_my_account", token: s.accessToken)
            setSession(nil)
            uploadedLogs = []
            defaults.removeObject(forKey: Self.uploadedKey)
            status = "Your account and all cloud data were deleted."
            lastError = nil
            return true
        } catch {
            lastError = "Account was not deleted: \(error.localizedDescription)"
            return false
        }
    }
}
