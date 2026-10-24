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

    /// Checks the 6-digit code from a confirmation ("email") or password-reset ("recovery") email; returns a session.
    func verifyCode(email: String, code: String, type: String) async throws -> CloudSession {
        let body: [String: Any] = ["type": type, "email": email, "token": code]
        let data = try await send("POST", "auth/v1/verify", query: [], json: body, token: nil)
        return try Self.session(from: data)
    }

    /// Emails a one-click sign-in link for an existing account that opens `redirect` (the upload website) signed in.
    func sendSignInLink(email: String, redirect: URL) async throws {
        _ = try await send("POST", "auth/v1/otp", query: [URLQueryItem(name: "redirect_to", value: redirect.absoluteString)],
                           json: ["email": email, "create_user": false], token: nil)
    }

    /// Sends the signup confirmation email again.
    func resendConfirmation(email: String) async throws {
        _ = try await send("POST", "auth/v1/resend", query: [], json: ["type": "signup", "email": email], token: nil)
    }

    /// Sets a new password for the signed-in user (after a password-reset code).
    func updatePassword(_ password: String, token: String) async throws {
        _ = try await send("PUT", "auth/v1/user", query: [], json: ["password": password], token: token)
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

    /// Calls a database function with named parameters and returns its JSON result.
    func rpc(_ function: String, params: [String: Any], token: String) async throws -> Any {
        let data = try await send("POST", "rest/v1/rpc/\(function)", query: [], json: params, token: token)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Inserts rows and returns them as stored (with their ids and defaults).
    func insert(table: String, rows: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let data = try await send("POST", "rest/v1/\(table)", query: [], json: rows, token: token,
                                  extraHeaders: ["Prefer": "return=representation"])
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
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

    /// Deletes rows matching `filter` (PostgREST, e.g. ["id": "eq.<uuid>"]).
    func delete(table: String, filter: [String: String], token: String) async throws {
        _ = try await send("DELETE", "rest/v1/\(table)", query: filter.map { URLQueryItem(name: $0.key, value: $0.value) },
                           json: nil, token: token, extraHeaders: ["Prefer": "return=minimal"])
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
    /// The aircraft the file was uploaded for (nil: not chosen yet).
    var aircraftID: String? = nil

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

    var isLog: Bool { category == "logs" && EngineLogConverter.logExtensions.contains((filename as NSString).pathExtension.lowercased()) }

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
        aircraftID = (row["aircraft_id"] as? String)?.lowercased()
    }
}

/// Maintenance, issue reviews and event markers, saved to the account as one file so every device matches.
struct AppSyncState: Codable {
    var version = 1
    var maintenanceModified: Date?
    var maintenanceItems: [MaintenanceItem]?
    var maintenanceEntries: [MaintenanceEntry]?
    var maintenanceDeleted: [UUID]?
    var issuesModified: Date?
    var issueRecords: [String: IssueStatusRecord]?
    var eventsModified: Date?
    var events: [DiagnosticEvent]?
    var eventsDeleted: [UUID]?
}

/// Record-by-record merge of two devices' copies.
enum AppSyncMerge {
    /// Everything in either list, minus deleted ids; where both have the same id, `localWins` picks the side.
    static func union<T: Identifiable & Hashable>(_ local: [T], _ remote: [T], localWins: Bool, deleted: Set<UUID>) -> [T] where T.ID == UUID {
        var byID: [UUID: T] = [:]
        for r in remote { byID[r.id] = r }
        for l in local where localWins || byID[l.id] == nil { byID[l.id] = l }
        let order = local.map(\.id) + remote.map(\.id)
        var seen = Set<UUID>()
        return order.compactMap { id in
            guard !deleted.contains(id), seen.insert(id).inserted else { return nil }
            return byID[id]
        }
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
    /// Email waiting for its confirmation code (set after registering, or when log in says "not confirmed").
    @Published var pendingConfirmationEmail: String?
    /// Documents and files in the cloud inbox (everything except logs already turned into flights).
    @Published private(set) var inboxItems: [InboxItem] = []
    /// Every aircraft in this account (oldest first). The selected one is `aircraftID`.
    @Published private(set) var fleet: [FleetAircraft] = []
    /// A transfer of this aircraft to a buyer that is waiting for them to accept.
    @Published private(set) var outgoingTransfer: AircraftTransfer?
    /// Set when this device's aircraft has been transferred to its new owner (sold). Syncing stops until
    /// the pilot removes it from this device.
    @Published private(set) var soldAircraft: AircraftTransfer?

    let api: CloudAPI?
    /// Cloud id of the selected aircraft. Adopts the account's first aircraft when a pilot signs in on a new device;
    /// AircraftSwitcher changes it when the pilot picks another of their aircraft.
    @Published private(set) var aircraftID: UUID
    /// One token refresh at a time: Supabase revokes a session if the same refresh token is used twice.
    private var refreshTask: Task<CloudSession, Error>?
    private var stateSyncing = false
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
                pendingConfirmationEmail = email
                status = "Account created. We emailed a 6-digit code to \(email). Enter it below."
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
            let text = error.localizedDescription
            if text.lowercased().contains("not confirmed") {
                pendingConfirmationEmail = email
                lastError = "Your email isn't confirmed yet. Enter the 6-digit code from your email, or tap Resend code."
            } else {
                lastError = "Log in failed: \(text)"
            }
            return false
        }
    }

    /// Emails the signed-in pilot a link that opens the upload website already signed in, for uploading from a computer.
    func emailUploadLink() async -> String {
        guard let api, let session else { return "Sign in first." }
        guard let portal = WebPortal.url else { return "The upload website isn't live yet. It's coming soon; for now upload from this iPad." }
        guard let email = session.email, !email.isEmpty else {
            return "Your account has no email address we can send to. Open \(portal.absoluteString) on your computer instead."
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.sendSignInLink(email: email, redirect: portal)
            return "Sent. Open the email from Engine Pulse on your computer and click the link: the upload page opens already signed in."
        } catch {
            return "Could not send the link: \(error.localizedDescription)"
        }
    }

    /// Confirms a new account with the code from the email; signs the pilot in.
    func confirmEmail(code: String) async -> Bool {
        guard let api, let email = pendingConfirmationEmail else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            setSession(try await api.verifyCode(email: email, code: code, type: "email"))
            pendingConfirmationEmail = nil
            status = "Email confirmed. You're signed in."
            lastError = nil
            return true
        } catch {
            lastError = "That code didn't work: \(error.localizedDescription). Check the newest email, or tap Resend code."
            return false
        }
    }

    func resendConfirmation() async {
        guard let api, let email = pendingConfirmationEmail else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.resendConfirmation(email: email)
            status = "A new code is on its way to \(email)."
            lastError = nil
        } catch {
            lastError = "Could not resend: \(error.localizedDescription)"
        }
    }

    /// Sets a new password using the code from a password-reset email, then signs in.
    func resetPassword(email: String, code: String, newPassword: String) async -> Bool {
        guard let api else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let s = try await api.verifyCode(email: email, code: code, type: "recovery")
            try await api.updatePassword(newPassword, token: s.accessToken)
            setSession(s)
            status = "Password changed. You're signed in."
            lastError = nil
            return true
        } catch {
            lastError = "Could not change the password: \(error.localizedDescription)"
            return false
        }
    }

    func resetPassword(email: String) async {
        guard let api else { lastError = CloudError.notConfigured.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.resetPassword(email: email)
            status = "If an account exists for \(email), we emailed a 6-digit code. Enter it below with a new password."
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
            if let running = refreshTask {
                s = try await running.value
            } else {
                let current = s
                let task = Task { try await api.refresh(current) }
                refreshTask = task
                defer { refreshTask = nil }
                s = try await task.value
                setSession(s)
            }
        }
        return (api, s)
    }

    // MARK: Sync

    /// Uploads the aircraft profile, then every log not uploaded yet. Safe to call often.
    func sync(profile: AircraftProfile, logs: FlightLogStore) async {
        guard isConfigured, isSignedIn, !isBusy, soldAircraft == nil else { return }
        // Not until restore has matched this device to the account's aircraft (see aircraftConfirmed).
        guard aircraftConfirmed, !holdSync else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            // A blank starting profile never overwrites an aircraft the account already has (for example while
            // switching to an aircraft whose profile hasn't loaded yet).
            let blank = profile.tailNumber.trimmingCharacters(in: .whitespaces).isEmpty && !profile.isLocked
            if !(blank && fleet.contains { $0.id == aircraftID }) {
                try await api.upsert(table: "aircraft", rows: [CloudAPI.aircraftRow(id: aircraftID, profile: profile)],
                                     onConflict: "id", token: s.accessToken)
            }
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
            // Flights already in the account whose summary was re-read by a newer version (for example newly found
            // takeoffs and landings): update the stored summary so other devices and the admin view see it.
            let summaryKey = "EM.cloud.summaryVersion\(FlightSummary.currentVersion)"
            var current = Set(defaults.stringArray(forKey: summaryKey) ?? [])
            for entry in logs.entries where uploadedLogs.contains(entry.filename) && !current.contains(entry.filename) {
                guard let summary = logs.summary(named: entry.filename), summary.isCurrent else { continue }
                try await api.update(table: "flight_logs",
                                     filter: ["aircraft_id": "eq.\(aircraftID.uuidString.lowercased())", "filename": "eq.\(entry.filename)"],
                                     values: ["summary": try CloudAPI.jsonObject(summary)], token: s.accessToken)
                current.insert(entry.filename)
                defaults.set(Array(current), forKey: summaryKey)
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
        guard soldAircraft == nil else { return "\(soldAircraft?.tailNumber ?? "This aircraft") now belongs to its new owner. Remove it from this device (ACCOUNT) before adding files." }
        isBusy = true
        defer { isBusy = false }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        // The same document twice (for example the POH uploaded again) only adds a duplicate.
        if inboxItems.contains(where: { $0.filename == fileURL.lastPathComponent && $0.category == category && $0.status != "failed" }) {
            return "\(fileURL.lastPathComponent) is already in your uploads. Delete the old one first (swipe left on it) to replace it."
        }
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
                "aircraft_id": aircraftConfirmed ? aircraftID.uuidString.lowercased() : NSNull(),
                "source": source,
                "category": category,
                "original_filename": name,
                "storage_path": path,
                "size_bytes": data.count,
                "format": format,
                "status": isDocument ? "stored" : "unsupported",
            ]
            // The aircraft row must exist before the inbox row can point at it.
            if aircraftConfirmed {
                try await api.upsert(table: "aircraft", rows: [CloudAPI.aircraftRow(id: aircraftID, profile: AircraftProfileSnapshot.shared.profile)],
                                     onConflict: "id", token: s.accessToken)
            }
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
        case "jpi", "dat": return "jpi"
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
                                            query: [URLQueryItem(name: "select", value: "id,original_filename,storage_path,category,format,status,source,received_at,aircraft_id"),
                                                    URLQueryItem(name: "order", value: "received_at.desc")],
                                            token: s.accessToken)
            // Only this aircraft's uploads (and any not tied to an aircraft yet, which become this one's).
            let mine = aircraftID.uuidString.lowercased()
            inboxItems = rows.compactMap(InboxItem.init(row:)).filter { $0.aircraftID == nil || $0.aircraftID == mine }
        } catch {
            lastError = "Could not load your uploads: \(error.localizedDescription)"
        }
    }

    /// Brings uploads from the website into the app: engine log CSVs become flights, documents are kept
    /// in Documents. Runs when the app opens or comes back to the foreground.
    func pullInbox(logs: FlightLogStore) async {
        guard isConfigured, isSignedIn, !isBusy, soldAircraft == nil, let uid = session?.userID.lowercased() else { return }
        await refreshInbox()
        // Every device brings in every uploaded engine log once (not only the first device to open the app),
        // plus new documents. Logs saved earlier in a format this version can now read are retried too.
        let doneKey = "EM.inboxDone.\(uid)"
        var done = Set(defaults.stringArray(forKey: doneKey) ?? [])
        let haveNames = Set(logs.entries.map { $0.originalFilename.lowercased() })
        let waiting = inboxItems.filter { item in
            if item.isLog {
                return !done.contains(item.id) && !haveNames.contains(item.filename.lowercased())
                    && ["received", "unsupported", "imported", "processing"].contains(item.status)
            }
            return item.status == "received"
        }
        guard !waiting.isEmpty else { return }
        isBusy = true
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
                    status = "Bringing in \(item.filename)…"
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
                    done.insert(item.id)
                    defaults.set(Array(done), forKey: doneKey)
                } else if item.category == "logs" {
                    newStatus = "unsupported"
                }
                // Another device may already have imported it; only new uploads change status.
                if item.status != "imported" || newStatus == "failed" {
                    try await api.update(table: "inbox_uploads", filter: ["id": "eq.\(item.id)"],
                                         values: ["status": newStatus, "detail": detail,
                                                  "processed_at": CloudAPI.isoFormatter.string(from: Date()),
                                                  "aircraft_id": aircraftID.uuidString.lowercased()],
                                         token: s.accessToken)
                }
            }
            status = imported > 0 ? "Added \(imported) flight\(imported == 1 ? "" : "s") from your uploads." : "Your uploads are up to date."
            lastError = nil
        } catch {
            lastError = "Could not bring in your uploads: \(error.localizedDescription)"
        }
        isBusy = false
        await refreshInbox()
        // The new flights go to the account straight away, so every other device (and a reinstall) gets them.
        // (Sync is skipped while busy, so the import above couldn't start it.)
        if imported > 0 { await sync(profile: AircraftProfileSnapshot.shared.profile, logs: logs) }
    }

    /// Deletes a flight from the account too, so it isn't restored again on this or another device.
    func deleteFlight(filename: String) async {
        guard isConfigured, isSignedIn else { return }
        do {
            let (api, s) = try await token()
            let rows = try await api.select(table: "flight_logs", query: [
                URLQueryItem(name: "select", value: "id,storage_path"),
                URLQueryItem(name: "filename", value: "eq.\(filename)"),
                URLQueryItem(name: "aircraft_id", value: "eq.\(aircraftID.uuidString.lowercased())"),
            ], token: s.accessToken)
            let paths = rows.compactMap { $0["storage_path"] as? String }
            try? await api.deleteFiles(paths: paths, token: s.accessToken)
            try await api.delete(table: "flight_logs", filter: ["filename": "eq.\(filename)", "aircraft_id": "eq.\(aircraftID.uuidString.lowercased())"],
                                 token: s.accessToken)
            uploadedLogs.remove(filename)
            defaults.set(Array(uploadedLogs), forKey: Self.uploadedKey)
        } catch {
            lastError = "The flight was removed from this iPad but not from your account: \(error.localizedDescription)"
        }
    }

    /// The account whose data this device holds (nil until someone signs in here).
    var deviceOwner: String? {
        get { defaults.string(forKey: "EM.deviceOwner") }
        set { defaults.set(newValue, forKey: "EM.deviceOwner") }
    }

    // MARK: Fleet (several aircraft in one account)

    /// The aircraft a transfer just gave this account (the caller switches to it).
    private(set) var receivedAircraftID: UUID?

    private static let oldestKey = "EM.fleet.oldestAircraft"
    private static let confirmedKey = "EM.cloud.aircraftConfirmed"

    /// True while AircraftSwitcher is changing aircraft: nothing is uploaded until the new aircraft has loaded.
    var holdSync = false

    /// True once this device knows the selected aircraft belongs to the account (restored from it, created on
    /// purpose, or the account had none). Until then nothing creates an aircraft row, so a device that signs in
    /// never makes its own copy of the account's aircraft.
    var aircraftConfirmed: Bool {
        get { defaults.bool(forKey: Self.confirmedKey) }
        set { defaults.set(newValue, forKey: Self.confirmedKey) }
    }

    /// The account's first aircraft keeps the original records file; others have their own.
    private func appStatePath(userID: String) -> String {
        let oldest = defaults.string(forKey: Self.oldestKey).flatMap(UUID.init(uuidString:))
        if oldest == nil || oldest == aircraftID { return "\(userID.lowercased())/app-state.json" }
        return "\(userID.lowercased())/app-state-\(aircraftID.uuidString.lowercased()).json"
    }

    private func setFleet(_ rows: [[String: Any]]) {
        fleet = rows.compactMap(FleetAircraft.init(row:))
        if let first = fleet.first { defaults.set(first.id.uuidString, forKey: Self.oldestKey) }
    }

    /// Reloads the list of this account's aircraft.
    func refreshFleet() async {
        guard isConfigured, isSignedIn else { fleet = []; return }
        do {
            let (api, s) = try await token()
            let rows = try await api.select(table: "aircraft",
                                            query: [URLQueryItem(name: "select", value: "id,tail_number,make,model,created_at"),
                                                    URLQueryItem(name: "order", value: "created_at.asc")],
                                            token: s.accessToken)
            setFleet(rows)
        } catch {
            lastError = "Could not load your aircraft: \(error.localizedDescription)"
        }
    }

    /// Adds an aircraft to the account (saved to the cloud straight away, so every device and the website see it).
    /// Returns its id; switch to it with AircraftSwitcher.
    func createAircraft(profile: AircraftProfile) async -> UUID? {
        guard isConfigured, isSignedIn else { lastError = "Sign in to add an aircraft."; return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            let id = UUID()
            try await api.upsert(table: "aircraft", rows: [CloudAPI.aircraftRow(id: id, profile: profile)], onConflict: "id", token: s.accessToken)
            aircraftConfirmed = true
            isBusy = false
            await refreshFleet()
            return id
        } catch {
            lastError = "Could not add the aircraft: \(error.localizedDescription)"
            return nil
        }
    }

    /// Removes an aircraft that isn't selected from the account: its flights, uploads and files.
    func removeAircraft(_ id: UUID) async -> Bool {
        guard id != aircraftID else { lastError = "Switch to another aircraft before removing this one."; return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            let aid = "eq.\(id.uuidString.lowercased())"
            let logs = try await api.select(table: "flight_logs", query: [URLQueryItem(name: "select", value: "storage_path"),
                                                                         URLQueryItem(name: "aircraft_id", value: aid)], token: s.accessToken)
            let inbox = try await api.select(table: "inbox_uploads", query: [URLQueryItem(name: "select", value: "storage_path"),
                                                                            URLQueryItem(name: "aircraft_id", value: aid)], token: s.accessToken)
            let paths = (logs + inbox).compactMap { $0["storage_path"] as? String }
            if !paths.isEmpty { try? await api.deleteFiles(paths: paths, token: s.accessToken) }
            try await api.delete(table: "inbox_uploads", filter: ["aircraft_id": aid], token: s.accessToken)
            try await api.delete(table: "aircraft", filter: ["id": aid], token: s.accessToken)
            AircraftVault.discard(id)
            isBusy = false
            await refreshFleet()
            status = "The aircraft was removed from your account."
            return true
        } catch {
            lastError = "Could not remove the aircraft: \(error.localizedDescription)"
            return false
        }
    }

    /// Makes `id` the selected aircraft and re-reads its settings (AircraftVault has already swapped the data).
    func setActiveAircraft(_ id: UUID) {
        aircraftID = id
        defaults.set(id.uuidString, forKey: Self.aircraftIDKey)
        uploadedLogs = Set(defaults.stringArray(forKey: Self.uploadedKey) ?? [])
        outgoingTransfer = nil
        soldAircraft = nil
        inboxItems = []
        receivedAircraftID = nil
    }

    /// Re-reads this device's per-account settings after AccountVault swapped accounts.
    func reloadAfterAccountSwitch() {
        // A copy of this account brought back from the device keeps its own confirmed flag (it moved with it).
        if let raw = defaults.string(forKey: Self.aircraftIDKey), let id = UUID(uuidString: raw) {
            aircraftID = id
        } else {
            let id = UUID()
            defaults.set(id.uuidString, forKey: Self.aircraftIDKey)
            aircraftID = id
        }
        uploadedLogs = Set(defaults.stringArray(forKey: Self.uploadedKey) ?? [])
        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
        outgoingTransfer = nil
        soldAircraft = nil
        inboxItems = []
        fleet = []
    }

    /// Another account signed in on this device: start from a clean slate so the two accounts' flights and
    /// records never mix (the previous account's data is in its own cloud account). The caller clears the stores.
    func resetForAccountSwitch() {
        aircraftConfirmed = false
        let id = UUID()
        aircraftID = id
        defaults.set(id.uuidString, forKey: Self.aircraftIDKey)
        uploadedLogs = []
        defaults.removeObject(forKey: Self.uploadedKey)
        outgoingTransfer = nil
        soldAircraft = nil
        inboxItems = []
    }

    /// Deletes an uploaded file and its row (for example a POH uploaded twice). Flights already imported from
    /// it stay. Returns false and sets lastError if it couldn't be deleted.
    func deleteUpload(_ item: InboxItem) async -> Bool {
        do {
            let (api, s) = try await token()
            try? await api.deleteFiles(paths: [item.storagePath], token: s.accessToken)
            try await api.delete(table: "inbox_uploads", filter: ["id": "eq.\(item.id)"], token: s.accessToken)
            inboxItems.removeAll { $0.id == item.id }
            status = "\(item.filename) was deleted."
            return true
        } catch {
            lastError = "Could not delete \(item.filename): \(error.localizedDescription)"
            return false
        }
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

    /// On a new device (or after signing in again): adopts the account's aircraft, restores the profile
    /// unless this device has a newer locked one, and downloads every flight not on this device yet.
    func restore(aircraft: AircraftProfileStore, logs: FlightLogStore) async {
        guard isConfigured, isSignedIn, !isBusy else { return }
        await refreshTransfer()
        guard soldAircraft == nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            let planes = try await api.select(table: "aircraft",
                                              query: [URLQueryItem(name: "select", value: "id,profile,updated_at,created_at,tail_number,make,model"),
                                                      URLQueryItem(name: "order", value: "created_at.asc")],
                                              token: s.accessToken)
            setFleet(planes)
            // The account has no aircraft yet: this device's becomes its first.
            if planes.isEmpty { aircraftConfirmed = true }
            // One aircraft per account: every device uses the account's first aircraft, so a device that
            // uploaded before restoring doesn't end up with its own copy.
            // This device's aircraft if the account has it (for example one just received by transfer), else the first.
            let current = aircraftID.uuidString.lowercased()
            let chosen = planes.first { ($0["id"] as? String)?.lowercased() == current } ?? planes.first
            if let newest = chosen, let rawID = newest["id"] as? String, let cloudID = UUID(uuidString: rawID) {
                // Switching to another aircraft (a new device, or a transfer accepted on another device): its profile wins.
                aircraftConfirmed = true
                let adopting = aircraftID != cloudID
                if adopting {
                    aircraftID = cloudID
                    defaults.set(cloudID.uuidString, forKey: Self.aircraftIDKey)
                    // An older copy of this aircraft put aside on this device is out of date now.
                    AircraftVault.discard(cloudID)
                }
                if let json = newest["profile"], !(json is NSNull),
                   let cloud = try? EventPersistence.decoder.decode(AircraftProfile.self, from: JSONSerialization.data(withJSONObject: json)) {
                    let local = aircraft.profile
                    // The first time this account is restored on this device, the account's profile wins (this
                    // device may already have filled a few values from the POH). After that, the newer one wins.
                    let firstKey = "EM.cloud.profileRestored.\(s.userID.lowercased())"
                    let first = !defaults.bool(forKey: firstKey)
                    // Same aircraft already set up and locked on this device (for example after duplicate copies of it
                    // were merged in the account): this device's newer, locked profile is kept and uploaded instead.
                    let sameLockedHere = local.isLocked && !local.tailNumber.isEmpty
                        && local.tailNumber.uppercased() == cloud.tailNumber.uppercased() && local.updatedAt >= cloud.updatedAt
                    if (first || adopting) && !sameLockedHere || cloud.updatedAt > local.updatedAt {
                        var merged = cloud
                        merged.documentsAppliedFrom = nil   // re-read this device's POH copy against the restored profile
                        aircraft.profile = merged
                    }
                    defaults.set(true, forKey: firstKey)
                }
            }
            let rows = try await api.select(table: "flight_logs",
                                            query: [URLQueryItem(name: "select", value: "filename,original_filename,storage_path"),
                                                    URLQueryItem(name: "aircraft_id", value: "eq.\(aircraftID.uuidString.lowercased())")],
                                            token: s.accessToken)
            let have = Set(logs.entries.map(\.filename))
            let missing = rows.filter { ($0["filename"] as? String).map { !have.contains($0) } ?? false }
            guard !missing.isEmpty else { return }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            var files: [URL] = []
            for (i, row) in missing.enumerated() {
                guard let path = row["storage_path"] as? String, let name = row["filename"] as? String else { continue }
                status = "Restoring flight \(i + 1) of \(missing.count) from your account…"
                let data = try await api.downloadFile(path: path, token: s.accessToken)
                let url = folder.appendingPathComponent(name)
                try data.write(to: url)
                files.append(url)
                uploadedLogs.insert(name)
            }
            defaults.set(Array(uploadedLogs), forKey: Self.uploadedKey)
            await logs.importFiles(files)
            status = "Restored \(files.count) flight\(files.count == 1 ? "" : "s") from your account."
            lastError = nil
        } catch {
            lastError = "Could not restore from your account: \(error.localizedDescription)"
        }
    }

    // MARK: Everything else the pilot records (maintenance, issue reviews, event markers)

    /// Pulls the account's saved app state, takes each part that is newer than this device's, and uploads
    /// the parts this device changed more recently. Each part is last-change-wins as a whole.
    func syncAppState(maintenance: MaintenanceStore, issues: IssueStore, events: DiagnosticEventStore) async {
        guard isConfigured, isSignedIn, !stateSyncing, soldAircraft == nil else { return }
        stateSyncing = true
        defer { stateSyncing = false }
        do {
            let (api, s) = try await token()
            let path = appStatePath(userID: s.userID)
            var remote: AppSyncState?
            do {
                let data = try await api.downloadFile(path: path, token: s.accessToken)
                remote = try EventPersistence.decoder.decode(AppSyncState.self, from: data)
            } catch CloudError.server(let code, let body) where code == 404 || code == 400 && body.lowercased().contains("not found") {
                remote = nil
            }
            var upload = remote == nil
            // Records are merged, not replaced: a record added on any device is kept, a record deleted on any
            // device stays deleted, and where both devices changed the same record the newer side wins.

            // Maintenance: your items list from the newer side; records merged one by one.
            let rm = remote?.maintenanceModified ?? .distantPast
            let localMaintNewer = maintenance.modifiedAt > rm || remote?.maintenanceItems == nil
            let maintDeleted = maintenance.deletedEntryIDs.union(remote?.maintenanceDeleted ?? [])
            let items = localMaintNewer ? maintenance.items : (remote?.maintenanceItems ?? maintenance.items)
            let entries = AppSyncMerge.union(maintenance.entries, remote?.maintenanceEntries ?? [], localWins: localMaintNewer, deleted: maintDeleted)
            let maintModified = max(maintenance.modifiedAt, rm)
            maintenance.noteDeleted(Array(remote?.maintenanceDeleted ?? []))
            if items != maintenance.items || Set(entries) != Set(maintenance.entries) {
                maintenance.replaceFromCloud(items: items, entries: entries, modified: maintModified)
            }
            if remote?.maintenanceItems.map({ $0 != items }) ?? true || Set(remote?.maintenanceEntries ?? []) != Set(entries)
                || Set(remote?.maintenanceDeleted ?? []) != maintDeleted { upload = true }

            // Issue reviews: per issue, the record changed most recently.
            let ri = remote?.issuesModified ?? .distantPast
            var records = issues.records
            for (kind, r) in remote?.issueRecords ?? [:] where records[kind].map({ r.updated > $0.updated }) ?? true {
                records[kind] = r
            }
            let issuesModified = max(issues.modifiedAt, ri)
            if records != issues.records { await issues.replaceFromCloud(records: records, modified: issuesModified) }
            if remote?.issueRecords != records { upload = true }

            // Event markers: merged one by one.
            let re = remote?.eventsModified ?? .distantPast
            let eventsDeleted = events.deletedIDs.union(remote?.eventsDeleted ?? [])
            let markers = AppSyncMerge.union(events.events, remote?.events ?? [], localWins: events.modifiedAt > re, deleted: eventsDeleted)
            let eventsModified = max(events.modifiedAt, re)
            events.noteDeleted(Array(remote?.eventsDeleted ?? []))
            if Set(markers) != Set(events.events) { events.replaceFromCloud(events: markers, modified: eventsModified) }
            if Set(remote?.events ?? []) != Set(markers) || Set(remote?.eventsDeleted ?? []) != eventsDeleted { upload = true }

            if upload {
                let state = AppSyncState(maintenanceModified: maintModified, maintenanceItems: items,
                                         maintenanceEntries: entries, maintenanceDeleted: Array(maintDeleted),
                                         issuesModified: issuesModified, issueRecords: records,
                                         eventsModified: eventsModified, events: markers, eventsDeleted: Array(eventsDeleted))
                let data = try EventPersistence.encoder.encode(state)
                try await api.uploadFile(path: path, data: data, contentType: "application/json", token: s.accessToken)
                // While a sale is pending, the buyer's copy follows the seller's latest records.
                if let snapshot = outgoingTransfer?.statePath {
                    try? await api.uploadFile(path: snapshot, data: data, contentType: "application/json", token: s.accessToken)
                }
            }
        } catch {
            lastError = "Could not sync maintenance and notes: \(error.localizedDescription)"
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

// MARK: - Aircraft transfer (sale)

/// A transfer of an aircraft and everything recorded for it to a buyer's account.
struct AircraftTransfer: Equatable, Sendable, Identifiable {
    let id: String
    let tailNumber: String
    let toEmail: String
    let toPhone: String
    let status: String
    let statePath: String?
    let expiresAt: Date?
    let acceptedAt: Date?

    init?(row: [String: Any]) {
        guard let id = row["id"] as? String else { return nil }
        self.id = id
        tailNumber = row["tail_number"] as? String ?? ""
        toEmail = row["to_email"] as? String ?? ""
        toPhone = row["to_phone"] as? String ?? ""
        status = row["status"] as? String ?? "pending"
        statePath = row["state_path"] as? String
        expiresAt = (row["expires_at"] as? String).flatMap { CloudAPI.parseDate($0) }
        acceptedAt = (row["accepted_at"] as? String).flatMap { CloudAPI.parseDate($0) }
    }

    var phoneLast4: String { String(toPhone.suffix(4)) }
}

/// The one-time code the seller texts to the buyer. Only its hash is stored in the cloud.
enum TransferCode {
    /// No 0/O, 1/I/L, so it reads cleanly in a text message.
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<8).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
    }

    /// Upper-case letters and digits only, as the database compares it.
    static func normalize(_ code: String) -> String {
        String(code.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    static func hash(_ code: String) -> String { CloudAPI.sha256(normalize(code)) }

    /// ABCD-2345
    static func display(_ code: String) -> String {
        let n = normalize(code)
        guard n.count == 8 else { return n }
        return String(n.prefix(4)) + "-" + String(n.suffix(4))
    }

    /// The seller's device keeps the code while the transfer is pending, so it can be texted again.
    static func remember(_ code: String?, for transferID: String?) {
        guard let transferID else { return }
        let key = "EM.transferCode.\(transferID)"
        if let code { UserDefaults.standard.set(code, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }

    static func remembered(for transferID: String) -> String? {
        UserDefaults.standard.string(forKey: "EM.transferCode.\(transferID)")
    }
}

enum TransferAcceptOutcome {
    case accepted(tail: String, state: AppSyncState?)
    case failed(String)
}

extension CloudStore {
    /// Maintenance, issue reviews and event markers as one file (the same shape as the account's app state).
    static func appState(maintenance: MaintenanceStore, issues: IssueStore, events: DiagnosticEventStore) -> AppSyncState {
        AppSyncState(maintenanceModified: maintenance.modifiedAt, maintenanceItems: maintenance.items,
                     maintenanceEntries: maintenance.entries, issuesModified: issues.modifiedAt,
                     issueRecords: issues.records, eventsModified: events.modifiedAt, events: events.events)
    }

    /// Reads this aircraft's latest transfer started from this account: pending (waiting for the buyer)
    /// or accepted (sold).
    func refreshTransfer() async {
        guard isConfigured, isSignedIn else { return }
        do {
            let (api, s) = try await token()
            let rows = try await api.select(table: "aircraft_transfers", query: [
                URLQueryItem(name: "select", value: "id,tail_number,to_email,to_phone,status,state_path,expires_at,accepted_at"),
                URLQueryItem(name: "aircraft_id", value: "eq.\(aircraftID.uuidString.lowercased())"),
                URLQueryItem(name: "from_owner", value: "eq.\(s.userID.lowercased())"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ], token: s.accessToken)
            let latest = rows.first.flatMap(AircraftTransfer.init(row:))
            let live = latest.map { $0.status == "pending" && ($0.expiresAt ?? .distantFuture) > Date() } ?? false
            outgoingTransfer = live ? latest : nil
            soldAircraft = latest?.status == "accepted" ? latest : nil
        } catch {
            // Older databases without the transfers table, or offline: nothing to show.
        }
    }

    /// Seller: uploads every flight and a copy of the maintenance records, then starts a transfer to the
    /// buyer's email and cell. Returns the code to text the buyer, or nil (see lastError).
    func startTransfer(email: String, phone: String, profile: AircraftProfile, logs: FlightLogStore, state: AppSyncState) async -> String? {
        lastError = nil
        await sync(profile: profile, logs: logs)
        if let error = lastError {
            lastError = "Your flights must be uploaded before the transfer. \(error)"
            return nil
        }
        guard !isBusy else { lastError = "Still syncing. Try again in a moment."; return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            let uid = s.userID.lowercased()
            let aid = aircraftID.uuidString.lowercased()
            let statePath = "\(uid)/\(aid)/transfer-state.json"
            try await api.uploadFile(path: statePath, data: EventPersistence.encoder.encode(state),
                                     contentType: "application/json", token: s.accessToken)
            let code = TransferCode.make()
            let row: [String: Any] = [
                "aircraft_id": aid,
                "tail_number": profile.tailNumber,
                "to_email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "to_phone": phone.filter(\.isASCII).filter(\.isNumber),
                "code_hash": TransferCode.hash(code),
                "state_path": statePath,
            ]
            let rows = try await api.insert(table: "aircraft_transfers", rows: [row], token: s.accessToken)
            outgoingTransfer = rows.first.flatMap(AircraftTransfer.init(row:))
            TransferCode.remember(code, for: outgoingTransfer?.id)
            status = "Transfer started. Send the buyer the code."
            return code
        } catch CloudError.server(let code, let body) where code == 409 || body.contains("aircraft_transfers_one_pending") {
            lastError = "A transfer for this aircraft is already waiting. Cancel it first to start a new one."
            await refreshTransfer()
            return nil
        } catch {
            lastError = "The transfer could not be started: \(error.localizedDescription)"
            return nil
        }
    }

    /// Seller: cancels the pending transfer (the code stops working).
    func cancelTransfer() async {
        guard let t = outgoingTransfer else { return }
        do {
            let (api, s) = try await token()
            try await api.update(table: "aircraft_transfers", filter: ["id": "eq.\(t.id)"], values: ["status": "cancelled"], token: s.accessToken)
            TransferCode.remember(nil, for: t.id)
            outgoingTransfer = nil
            status = "Transfer cancelled."
        } catch {
            lastError = "Could not cancel the transfer: \(error.localizedDescription)"
        }
    }

    /// Buyer: accepts with the texted code and their cell number. On success this device switches to the
    /// transferred aircraft; the caller applies the returned records and then runs restore.
    func acceptTransfer(code: String, phone: String) async -> TransferAcceptOutcome {
        isBusy = true
        defer { isBusy = false }
        do {
            let (api, s) = try await token()
            let result = try await api.rpc("accept_aircraft_transfer",
                                           params: ["transfer_code": TransferCode.normalize(code), "phone": phone],
                                           token: s.accessToken)
            guard let r = result as? [String: Any] else { return .failed("Unexpected answer from the server.") }
            guard (r["ok"] as? Bool) == true, let raw = r["aircraft_id"] as? String, let id = UUID(uuidString: raw) else {
                return .failed(Self.acceptMessage(reason: r["reason"] as? String, tail: r["tail_number"] as? String, email: s.email))
            }
            receivedAircraftID = id
            outgoingTransfer = nil
            soldAircraft = nil
            var state: AppSyncState?
            if let path = r["state_path"] as? String, !path.isEmpty,
               let data = try? await api.downloadFile(path: path, token: s.accessToken) {
                state = try? EventPersistence.decoder.decode(AppSyncState.self, from: data)
            }
            return .accepted(tail: r["tail_number"] as? String ?? "", state: state)
        } catch CloudError.server(let code, let body) where code == 404 && body.contains("accept_aircraft_transfer") {
            return .failed("Aircraft transfers aren't switched on for this account yet. Contact sales@enginepulse.net.")
        } catch {
            return .failed("The transfer could not be accepted: \(error.localizedDescription)")
        }
    }

    static func acceptMessage(reason: String?, tail: String?, email: String?) -> String {
        switch reason {
        case "unconfirmed":
            return "Confirm your email address first (the code we emailed when you registered), then try again."
        case "none":
            return "No transfer is waiting for \(email ?? "this account"). Check the seller used this exact email address and that it is less than 14 days old. If you signed in with Apple and hid your email, register with your email instead."
        case "mismatch":
            return "The code or the cell number doesn't match. Use the code from the seller's text and the cell number it was sent to. After 5 wrong tries the transfer is cancelled."
        case "locked":
            return "Too many wrong tries, so the transfer was cancelled. Ask the seller to start a new one."
        case "self":
            return "This transfer was started from this account. Sign in with the buyer's account to accept it."
        case "has_aircraft":
            return "Your account already has \(tail.map { $0.isEmpty ? "an aircraft" : $0 } ?? "an aircraft"). Update the app to add the transferred aircraft alongside it."
        default:
            return "The transfer could not be accepted."
        }
    }

    /// Seller, after the sale: this device starts fresh with a new aircraft id (the caller clears the records).
    func forgetSoldAircraft() {
        let id = UUID()
        aircraftID = id
        defaults.set(id.uuidString, forKey: Self.aircraftIDKey)
        uploadedLogs = []
        defaults.removeObject(forKey: Self.uploadedKey)
        if let t = soldAircraft { TransferCode.remember(nil, for: t.id) }
        soldAircraft = nil
        outgoingTransfer = nil
        inboxItems = []
        status = "The sold aircraft was removed from this device. Set up your next aircraft in AIRCRAFT."
    }
}

// MARK: - Beta tester status (admins only)

/// One account as the admin status function reports it (counts only).
struct TesterStatus: Identifiable, Sendable {
    let email: String
    let name: String?
    let signedUp: Date?
    let confirmed: Bool
    let lastSignIn: Date?
    let tailNumber: String?
    let aircraft: String?
    let monitor: String?
    let flights: Int
    let lastFlight: Date?
    let uploads: Int
    let waiting: Int
    let failed: Int
    let documents: String?

    var id: String { email }

    init?(row: [String: Any]) {
        guard let email = row["email"] as? String else { return nil }
        func date(_ k: String) -> Date? { (row[k] as? String).flatMap { CloudAPI.parseDate($0) } }
        func int(_ k: String) -> Int { (row[k] as? Int) ?? (row[k] as? NSNumber)?.intValue ?? 0 }
        func text(_ k: String) -> String? { (row[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        self.email = email
        name = text("full_name")
        signedUp = date("signed_up")
        confirmed = (row["confirmed"] as? Bool) ?? false
        lastSignIn = date("last_sign_in")
        tailNumber = text("tail_number")
        aircraft = text("aircraft")
        monitor = text("monitor")
        flights = int("flights")
        lastFlight = date("last_flight")
        uploads = int("uploads")
        waiting = int("uploads_waiting")
        failed = int("uploads_failed")
        documents = text("documents")
    }
}

extension CloudStore {
    /// True when this account is listed in app_admins (false on older databases or when signed out).
    /// Tries up to three times; a network hiccup or a token refresh while the app is busy syncing no longer
    /// hides the admin section. The last answer is remembered for this account, so the section shows at once.
    func checkAdmin() async -> Bool {
        guard isConfigured, isSignedIn, let uid = session?.userID.lowercased() else { return false }
        let key = "EM.admin.\(uid)"
        for attempt in 0..<3 {
            do {
                let (api, s) = try await token()
                let admin = (try await api.rpc("is_app_admin", params: [:], token: s.accessToken) as? Bool) ?? false
                defaults.set(admin, forKey: key)
                return admin
            } catch {
                if attempt < 2 { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        return defaults.bool(forKey: key)
    }

    /// The last admin answer for the signed-in account (shown while checking again).
    var rememberedAdmin: Bool {
        guard let uid = session?.userID.lowercased() else { return false }
        return defaults.bool(forKey: "EM.admin.\(uid)")
    }

    /// One account's uploads and flights (admins only).
    func testerDetail(email: String) async throws -> TesterDetail {
        let (api, s) = try await token()
        let json = try await api.rpc("admin_tester_detail", params: ["tester_email": email], token: s.accessToken) as? [String: Any] ?? [:]
        return TesterDetail(json: json)
    }

    func testerStatus() async throws -> [TesterStatus] {
        let (api, s) = try await token()
        let rows = try await api.rpc("admin_tester_status", params: [:], token: s.accessToken) as? [[String: Any]] ?? []
        return rows.compactMap(TesterStatus.init(row:))
    }
}

/// One account in detail for the admin view: each upload and each flight (no file contents).
struct TesterDetail: Sendable {
    struct Upload: Identifiable, Sendable {
        let id = UUID()
        let filename: String
        let category: String
        let status: String
        let detail: String?
        let source: String
        let received: Date?
    }
    struct Flight: Identifiable, Sendable {
        let id = UUID()
        let filename: String
        let start: Date?
        let end: Date?
        let samples: Int
        let takeoffs: Int
        let landings: Int
    }
    let uploads: [Upload]
    let flights: [Flight]

    init(json: [String: Any]) {
        func date(_ v: Any?) -> Date? { (v as? String).flatMap { CloudAPI.parseDate($0) } }
        func int(_ v: Any?) -> Int { (v as? Int) ?? (v as? NSNumber)?.intValue ?? 0 }
        uploads = (json["uploads"] as? [[String: Any]] ?? []).map { u in
            Upload(filename: u["filename"] as? String ?? "?", category: u["category"] as? String ?? "",
                   status: u["status"] as? String ?? "", detail: u["detail"] as? String,
                   source: u["source"] as? String ?? "", received: date(u["received_at"]))
        }
        flights = (json["flights"] as? [[String: Any]] ?? []).map { f in
            Flight(filename: f["filename"] as? String ?? "?", start: date(f["started_at"]), end: date(f["ended_at"]),
                   samples: int(f["samples"]), takeoffs: int(f["takeoffs"]), landings: int(f["landings"]))
        }
    }
}

/// One aircraft in the account, for the aircraft picker.
struct FleetAircraft: Identifiable, Hashable, Sendable {
    let id: UUID
    let tailNumber: String
    let make: String
    let model: String

    var title: String {
        let t = tailNumber.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (model.isEmpty ? "New aircraft" : model) : t
    }
    var subtitle: String { [make, model].filter { !$0.isEmpty }.joined(separator: " ") }

    init?(row: [String: Any]) {
        guard let raw = row["id"] as? String, let id = UUID(uuidString: raw) else { return nil }
        self.id = id
        tailNumber = row["tail_number"] as? String ?? ""
        make = row["make"] as? String ?? ""
        model = row["model"] as? String ?? ""
    }
}
