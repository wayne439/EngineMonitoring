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

            Section {
                Picker("This file is", selection: $category) {
                    ForEach(InboxItem.categories, id: \.id) { Text($0.title).tag($0.id) }
                }
                Button {
                    picking = true
                } label: {
                    Label("Choose files from this iPad", systemImage: "square.and.arrow.up")
                }
                .disabled(!cloud.isSignedIn || cloud.isBusy)
                if !cloud.isSignedIn {
                    Text("Sign in first (ACCOUNT) so your files are kept in your account.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let message { Text(message).font(.footnote) }
            } header: {
                Text("Upload from this iPad")
            } footer: {
                Text("Engine log CSV files become flights right away. PDFs and photos (POH limits page, logbook entries, oil analysis) are kept with your aircraft.")
            }

            DataChecklistSection(turbo: aircraft.profile.isTurbocharged, monitor: aircraft.profile.monitor,
                                 header: "What we need")

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
