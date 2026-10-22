import SwiftUI

/// First thing after registering (and on HOME until the first flight arrives): the simplest way to get this
/// pilot's flights in, for where their files are and what monitor they have.
struct GetStartedView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @State private var importing = false
    @State private var pickingFolder = true
    @State private var message: String?
    @State private var checking = false

    private var monitor: EngineMonitorType { aircraft.profile.monitor }
    private var uploadAddress: String { WebPortal.url?.absoluteString ?? "https://enginepulse.net/upload/" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: logs.entries.isEmpty ? "airplane.arrival" : "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundStyle(logs.entries.isEmpty ? Color.accentColor : Color.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(logs.entries.isEmpty ? "Bring in your flights" : "\(logs.entries.count) flight\(logs.entries.count == 1 ? "" : "s") in")
                            .font(.title2.bold())
                        Text(logs.entries.isEmpty
                             ? "Pick where your engine logs are. It takes a couple of minutes, once."
                             : "Your engine health, reports and early warning are ready on HOME. Add more any time the same way.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if logs.isImporting || cloud.isBusy {
                    HStack { ProgressView(); Text(cloud.status ?? "Bringing in flights…").font(.footnote) }
                }
                if let message { Text(message).font(.footnote) }
            }

            Section {
                Step(n: 1, text: "On your computer, open \(uploadAddress.replacingOccurrences(of: "https://", with: ""))")
                Step(n: 2, text: "Log in with \(cloud.session?.email ?? "your Engine Pulse email") and your password.")
                Step(n: 3, text: monitor == .jpiEDM
                     ? "Drag the .JPI file from the USB stick onto Engine monitor log files."
                     : "Drag the whole data_log folder from the SD card (or all the log files) onto Engine monitor log files.")
                Step(n: 4, text: "Come back here and tap Check for my flights. They also arrive by themselves whenever the app opens.")
                Button {
                    Task {
                        message = await cloud.emailUploadLink()
                    }
                } label: {
                    Label("Email me a one-click link for my computer", systemImage: "envelope")
                }
                .disabled(!cloud.isSignedIn || cloud.isBusy)
                Button {
                    UIPasteboard.general.string = uploadAddress
                    message = "Copied \(uploadAddress). Paste it into a browser on your computer, or send it to yourself."
                } label: {
                    Label("Copy the upload address", systemImage: "doc.on.doc")
                }
                Button {
                    Task { await check() }
                } label: {
                    Label("Check for my flights", systemImage: "arrow.down.circle")
                        .font(.headline)
                }
                .disabled(!cloud.isSignedIn || cloud.isBusy || checking)
            } header: {
                Text("My files are on a computer")
            } footer: {
                if !cloud.isSignedIn {
                    Text("Sign in first (ACCOUNT), with the same email you'll use on the website.").foregroundStyle(.orange)
                }
            }

            Section {
                Text("Plug the SD card or USB stick into this \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") with a USB-C (or Lightning) card reader.")
                    .font(.subheadline)
                Button {
                    pickingFolder = true
                    importing = true
                } label: {
                    Label("Choose the card's folder", systemImage: "sdcard")
                        .font(.headline)
                }
                Button {
                    pickingFolder = false
                    importing = true
                } label: {
                    Label("Choose individual files", systemImage: "doc.badge.plus")
                }
            } header: {
                Text("The card or stick is here")
            } footer: {
                Text(monitor.isGarmin
                     ? "Choose the data_log folder on the card. Next time it's one tap: DIAGNOSTICS > Flight Logs > Import new flights."
                     : "Choose the folder on the stick (or the files). Every flight in them is added.")
            }

            if monitor.isGarmin {
                Section {
                    NavigationLink {
                        GarminImportGuideView()
                    } label: {
                        Label("From Garmin Pilot or flyGarmin (GDL 60, Flight Stream 510)", systemImage: "airplane.circle")
                    }
                } header: {
                    Text("My flights are in Garmin's apps")
                }
            }

            Section {
                ForEach(Array(monitor.downloadSteps.enumerated()), id: \.offset) { i, step in
                    Step(n: i + 1, text: step)
                }
            } header: {
                Text("Getting the files off your \(monitor.label)")
            }

            Section {
                NavigationLink {
                    DocumentsView()
                } label: {
                    Label("Next: upload your POH", systemImage: "book")
                }
            } footer: {
                Text("Stuck? Email sales@enginepulse.net with your tail number and we'll help.")
            }
        }
        .navigationTitle("Get started")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: pickingFolder ? [.folder] : [.commaSeparatedText, .plainText, .data],
                      allowsMultipleSelection: !pickingFolder) { result in
            switch result {
            case .success(let urls):
                Task {
                    let before = logs.entries.count
                    if pickingFolder, let folder = urls.first { await logs.importFolder(folder) } else { await logs.importFiles(urls) }
                    let added = logs.entries.count - before
                    message = logs.lastError ?? (added > 0 ? "Added \(added) flight\(added == 1 ? "" : "s")." : (logs.importSummary ?? "No new flights found there."))
                    logs.lastError = nil
                    await cloud.sync(profile: aircraft.profile, logs: logs)
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        let before = logs.entries.count
        await cloud.restore(aircraft: aircraft, logs: logs)
        await cloud.pullInbox(logs: logs)
        let added = logs.entries.count - before
        if added > 0 {
            message = "Added \(added) flight\(added == 1 ? "" : "s")."
        } else if let error = cloud.lastError {
            message = error
        } else {
            let waiting = cloud.inboxItems.filter { $0.isLog }.count
            message = waiting == 0
                ? "No uploads found for \(cloud.session?.email ?? "this account") yet. Check you logged in on the website with this same email."
                : "Your \(waiting) uploaded log\(waiting == 1 ? " is" : "s are") already here."
        }
    }
}

private struct Step: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

/// HOME card while there are no flights yet.
struct GetStartedCard: View {
    var body: some View {
        NavigationLink {
            GetStartedView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "airplane.arrival")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bring in your flights").font(.headline).foregroundStyle(.primary)
                    Text("From a computer, an SD card or Garmin's apps. A couple of minutes, once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
