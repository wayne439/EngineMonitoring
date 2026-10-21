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
                Text("Counts only. File contents stay private to each pilot.")
            }
            Section {
                ForEach(shown) { TesterRow(tester: $0) }
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
