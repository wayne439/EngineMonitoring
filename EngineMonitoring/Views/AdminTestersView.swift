import SwiftUI

/// ACCOUNT > Beta testers (admins only): who has signed in, set up an aircraft and uploaded data.
struct AdminTestersView: View {
    @EnvironmentObject private var cloud: CloudStore
    @State private var testers: [TesterStatus] = []
    @State private var error: String?
    @State private var loading = false
    @State private var search = ""

    private var shown: [TesterStatus] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return testers }
        return testers.filter { t in
            [t.email, t.name, t.tailNumber, t.aircraft].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
    }

    var body: some View {
        List {
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            Section {
                LabeledContent("Accounts", value: "\(testers.count)")
                LabeledContent("With an aircraft", value: "\(testers.filter { $0.tailNumber != nil }.count)")
                LabeledContent("With flights", value: "\(testers.filter { $0.flights > 0 }.count)")
            } footer: {
                Text("Tap an account for its uploads and flights. File contents stay private to each pilot.")
            }
            Section {
                ForEach(shown) { t in
                    NavigationLink { AdminTesterDetailView(tester: t) } label: { TesterRow(tester: t) }
                }
                if !loading && shown.isEmpty && error == nil { Text("No accounts match.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Beta testers")
        .searchable(text: $search, prompt: "Name, email or tail")
        .overlay { if loading && testers.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            testers = try await cloud.testerStatus()
            error = nil
        } catch {
            self.error = "Could not load testers: \(error.localizedDescription)"
        }
    }
}

private struct TesterRow: View {
    let tester: TesterStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tester.name ?? tester.email).font(.headline)
                Spacer()
                if let tail = tester.tailNumber { Text(tail).font(.subheadline.monospaced()) }
            }
            if tester.name != nil { Text(tester.email).font(.caption).foregroundStyle(.secondary) }
            if let aircraft = tester.aircraft {
                Text([aircraft, tester.monitor].compactMap { $0 }.joined(separator: " · ")).font(.caption)
            }
            HStack(spacing: 6) {
                chip(tester.confirmed ? "Email confirmed" : "Email not confirmed", ok: tester.confirmed)
                chip(tester.lastSignIn.map { "Signed in " + $0.formatted(.relative(presentation: .named)) } ?? "Never signed in",
                     ok: tester.lastSignIn != nil)
            }
            HStack(spacing: 6) {
                chip(tester.tailNumber == nil ? "No aircraft" : "Aircraft set up", ok: tester.tailNumber != nil)
                chip("\(tester.flights) flight\(tester.flights == 1 ? "" : "s")" + (tester.lastFlight.map { ", last " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""),
                     ok: tester.flights > 0)
            }
            if tester.uploads > 0 {
                Text("Uploads: \(tester.uploads)" + (tester.waiting > 0 ? ", \(tester.waiting) waiting for the app" : "")
                     + (tester.failed > 0 ? ", \(tester.failed) unreadable" : "") + (tester.documents.map { " (\($0))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(tester.failed > 0 ? .orange : .secondary)
            }
            if let joined = tester.signedUp {
                Text("Joined " + joined.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func chip(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((ok ? Color.green : Color.orange).opacity(0.15), in: Capsule())
            .foregroundStyle(ok ? Color.green : Color.orange)
    }
}

/// One account: every upload (slot, status, any error) and every flight with the takeoffs and landings found.
private struct AdminTesterDetailView: View {
    let tester: TesterStatus
    @EnvironmentObject private var cloud: CloudStore
    @State private var detail: TesterDetail?
    @State private var error: String?

    private static let slots = ["logs": "Engine logs", "poh-limits": "POH / AFM", "logbook": "Logbook", "engine-time": "Engine time",
                                "oil-analysis": "Oil analysis", "squawks": "Squawks", "turbo": "Turbo supplement", "other": "Other"]
    private static let statuses = ["received": "Waiting for the pilot's app", "processing": "Being read", "imported": "Became a flight",
                                   "stored": "Kept as a document", "unsupported": "Not a readable engine log", "failed": "Could not be read"]

    var body: some View {
        List {
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            Section {
                LabeledContent("Email", value: tester.email)
                if let tail = tester.tailNumber { LabeledContent("Tail", value: tail) }
                if let aircraft = tester.aircraft { LabeledContent("Aircraft", value: aircraft) }
                if let monitor = tester.monitor { LabeledContent("Avionics / monitor", value: monitor) }
                LabeledContent("Last sign-in", value: tester.lastSignIn?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            }
            if let detail {
                Section {
                    if detail.flights.isEmpty {
                        Text(detail.uploads.contains { $0.category == "logs" }
                             ? "No flights yet. Engine logs are uploaded but the pilot's app hasn't brought them in: they need to open the app signed in with this email."
                             : "No flights and no engine logs uploaded. MY FLYING and engine trends need the CSV files from the avionics SD card's data_log folder.")
                            .foregroundStyle(.orange)
                    }
                    ForEach(detail.flights) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.filename).font(.subheadline.monospaced())
                            Text([f.start?.formatted(date: .abbreviated, time: .shortened),
                                  f.start.flatMap { s in f.end.map { e in "\(Int(e.timeIntervalSince(s) / 60)) min" } },
                                  "\(f.takeoffs) takeoff\(f.takeoffs == 1 ? "" : "s"), \(f.landings) landing\(f.landings == 1 ? "" : "s")"]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(f.takeoffs + f.landings == 0 ? Color.orange : Color.secondary)
                        }
                    }
                } header: {
                    Text("Flights (\(detail.flights.count))")
                } footer: {
                    Text("Takeoffs and landings as found by the pilot's app. Orange: none found (no airspeed or altitude in the log, or the recording missed them).")
                }
                Section {
                    if detail.uploads.isEmpty { Text("Nothing uploaded.").foregroundStyle(.secondary) }
                    ForEach(detail.uploads) { u in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.filename).font(.subheadline)
                            Text([Self.slots[u.category] ?? u.category, Self.statuses[u.status] ?? u.status,
                                  u.received?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(["failed", "unsupported"].contains(u.status) ? Color.orange : Color.secondary)
                            if let d = u.detail, !d.isEmpty { Text(d).font(.caption2).foregroundStyle(.orange) }
                        }
                    }
                } header: {
                    Text("Uploads (\(detail.uploads.count))")
                }
            } else if error == nil {
                Section { ProgressView() }
            }
        }
        .navigationTitle(tester.name ?? tester.email)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            detail = try await cloud.testerDetail(email: tester.email)
            error = nil
        } catch {
            self.error = "Could not load this account: \(error.localizedDescription). If this says the function doesn't exist, run supabase/schema.sql again."
        }
    }
}
