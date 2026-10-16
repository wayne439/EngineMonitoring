import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import UIKit

/// Address of the upload website (Info.plist `EMWebPortalURL`). nil until the site is live.
enum WebPortal {
    static var url: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "EMWebPortalURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(string: raw.trimmingCharacters(in: .whitespaces))
    }
}

/// "Upload your documents": the data checklist, the website link, uploading from this iPad, and everything
/// already uploaded. Shown once right after registration and always under AIRCRAFT > Documents and uploads.
struct DocumentsView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @State private var category = "logs"
    @State private var picking = false
    @State private var message: String?
    @State private var preview: URL?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { message = await cloud.emailUploadLink() }
                } label: {
                    Label("Email me an upload link", systemImage: "envelope")
                        .font(.headline)
                }
                .disabled(!cloud.isSignedIn || cloud.isBusy)
                Text("Your files are usually on a computer. We'll email you a link: click it on your computer and the upload page opens already signed in. Then drag your files in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = WebPortal.url {
                    Link(destination: url) {
                        Label("Upload on our website", systemImage: "globe")
                    }
                    Text("Easiest from a computer: sign in with the same account and drag in your files. They appear here as soon as you open the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Our upload website is coming soon. For now, upload from this iPad below.", systemImage: "globe")
                        .font(.footnote)
                }
            } header: {
                Text("Upload your documents")
            }

            if !cloud.isSignedIn {
                Section {
                    Label("Sign in first (ACCOUNT) so your files are kept in your account.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Image(systemName: aircraftDetailsDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(aircraftDetailsDone ? Color.green : Color.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Tail number and serial number").font(.subheadline.bold())
                            LevelBadge(level: .required)
                        }
                        Text(aircraftDetailsDone ? "\(aircraft.profile.tailNumber) · S/N \(aircraft.profile.serialNumber)" : "Typed in, no upload needed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink("Edit") { AircraftProfileView() }
                        .fixedSize()
                }
                ForEach(DocumentRequirement.list(turbo: aircraft.profile.isTurbocharged)) { item in
                    DocumentRow(item: item, count: count(for: item)) {
                        category = item.id
                        picking = true
                    }
                    .disabled(!cloud.isSignedIn || cloud.isBusy)
                }
                if let message { Text(message).font(.footnote) }
            } header: {
                Text("What we need: \(requiredDone) of \(requiredTotal) required done")
            } footer: {
                Text("Tap Upload next to each item so every file lands in the right place. Engine log CSV files become flights right away; PDFs and photos are kept with your aircraft.")
            }

            Section {
                if cloud.inboxItems.isEmpty {
                    Text(cloud.isSignedIn ? "Nothing uploaded yet." : "Sign in to see your uploads.")
                        .foregroundStyle(.secondary)
                }
                ForEach(cloud.inboxItems) { item in
                    Button {
                        Task { preview = await cloud.download(item) }
                    } label: {
                        HStack {
                            Image(systemName: item.isLog ? "waveform.path.ecg" : "doc.text")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename).foregroundStyle(.primary)
                                Text(Self.detail(for: item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Your uploads")
                    Spacer()
                    if cloud.isSignedIn {
                        Button("Refresh") { Task { await cloud.pullInbox(logs: logs) } }
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Documents and Uploads")
        .task { await cloud.pullInbox(logs: logs) }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image, .commaSeparatedText, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    var notes: [String] = []
                    for url in urls {
                        if category == "logs" && url.pathExtension.lowercased() == "csv" {
                            await logs.importFiles([url])
                            notes.append(logs.lastError ?? "\(url.lastPathComponent) imported as a flight.")
                            logs.lastError = nil
                        } else {
                            notes.append(await cloud.uploadToInbox(fileURL: url, source: "app", category: category))
                        }
                    }
                    message = notes.joined(separator: "\n")
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .quickLookPreview($preview)
    }

    private var aircraftDetailsDone: Bool {
        !aircraft.profile.tailNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !aircraft.profile.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Files received for an item (engine logs also count flights already imported on this iPad).
    private func count(for item: DocumentRequirement) -> Int {
        let uploaded = cloud.inboxItems.filter { $0.category == item.id && $0.status != "failed" }.count
        return item.id == "logs" ? max(uploaded, logs.entries.count) : uploaded
    }

    private var requiredTotal: Int {
        DocumentRequirement.list(turbo: aircraft.profile.isTurbocharged).filter { $0.level == .required }.count + 1
    }

    private var requiredDone: Int {
        DocumentRequirement.list(turbo: aircraft.profile.isTurbocharged)
            .filter { $0.level == .required && count(for: $0) > 0 }.count + (aircraftDetailsDone ? 1 : 0)
    }

    static func detail(for item: InboxItem) -> String {
        var parts = [item.categoryTitle, statusText(item.status)]
        if let date = item.receivedAt { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    static func statusText(_ status: String) -> String {
        switch status {
        case "received": return "waiting"
        case "imported": return "added as a flight"
        case "stored": return "saved"
        case "unsupported": return "saved; analysis coming"
        case "failed": return "could not be read"
        default: return status
        }
    }
}

/// One document with its status and its own Upload button.
private struct DocumentRow: View {
    let item: DocumentRequirement
    let count: Int
    let upload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(count > 0 ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.subheadline.bold())
                    LevelBadge(level: item.level)
                }
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                Text(count == 0 ? "Not uploaded yet" : "\(count) \(item.id == "logs" ? "flight" : "file")\(count == 1 ? "" : "s") received")
                    .font(.caption.bold())
                    .foregroundStyle(count > 0 ? Color.green : (item.level == .required ? Color.orange : Color.secondary))
            }
            Spacer(minLength: 8)
            Button(action: upload) {
                Label("Upload", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }
}

struct LevelBadge: View {
    let level: DataChecklist.Level

    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(level == .required ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
    }
}
