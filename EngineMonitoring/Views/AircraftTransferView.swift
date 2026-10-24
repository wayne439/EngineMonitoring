import SwiftUI
import MessageUI

// Selling the airplane: the current owner sends everything recorded for it (flights, engine analysis,
// maintenance, issue reviews, event markers and uploaded documents) to the buyer's Engine Pulse account.
// The owner enters the buyer's email and cell number; the buyer gets the code by text and the
// instructions by email, signs in with that email and accepts in ACCOUNT.

/// ACCOUNT section: transfer this aircraft, accept one, or remove a sold one from this device.
struct AircraftOwnershipSection: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore

    var body: some View {
        Section {
            if let sold = cloud.soldAircraft {
                SoldAircraftNotice(transfer: sold)
            } else {
                NavigationLink {
                    TransferAircraftView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Sold this aircraft? Transfer it", systemImage: "arrow.right.arrow.left")
                        if let t = cloud.outgoingTransfer {
                            Text("Waiting for \(t.toEmail) to accept")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                NavigationLink {
                    AcceptTransferView()
                } label: {
                    Label("Bought an aircraft? Accept a transfer", systemImage: "key")
                }
            }
        } header: {
            Text("Aircraft ownership")
        } footer: {
            Text("A transfer moves \(aircraft.profile.tailNumber.isEmpty ? "the aircraft" : aircraft.profile.tailNumber)'s flights, engine analysis, maintenance, notes and uploaded documents to the new owner's account.")
        }
        .task { await cloud.refreshTransfer() }
    }
}

// MARK: - Seller

struct TransferAircraftView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var events: DiagnosticEventStore

    @State private var email = ""
    @State private var phone = ""
    @State private var tailConfirm = ""
    @State private var confirmed = false
    @State private var code: String?
    @State private var confirmCancel = false

    private var tail: String { aircraft.profile.tailNumber }
    private var emailOK: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.split(separator: "@").last?.contains(".") == true && !e.contains(" ")
    }
    private var phoneDigits: String { phone.filter(\.isASCII).filter(\.isNumber) }
    private var phoneOK: Bool { (10...15).contains(phoneDigits.count) }
    private var tailOK: Bool { !tail.isEmpty && tailConfirm.trimmingCharacters(in: .whitespaces).uppercased() == tail.uppercased() }
    private var canStart: Bool { emailOK && phoneOK && tailOK && confirmed && !cloud.isBusy }

    var body: some View {
        List {
            if !cloud.isSignedIn {
                Section { Text("Sign in first. The transfer comes from the account that owns this aircraft.") }
            } else if let t = cloud.outgoingTransfer {
                pending(t)
            } else {
                form
            }
            if let error = cloud.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Transfer \(tail.isEmpty ? "aircraft" : tail)")
        .task { await cloud.refreshTransfer() }
        .confirmationDialog("Cancel this transfer?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel transfer", role: .destructive) { Task { await cloud.cancelTransfer() } }
        } message: {
            Text("The code stops working. You can start a new transfer afterwards.")
        }
    }

    @ViewBuilder
    private var form: some View {
        Section {
            Text("Everything recorded for \(tail.isEmpty ? "this aircraft" : tail) moves to the buyer's Engine Pulse account: \(logs.entries.count) flight\(logs.entries.count == 1 ? "" : "s") and their engine analysis, the locked aircraft profile, maintenance history, issue reviews, event markers and the documents uploaded to your account.")
                .font(.subheadline)
            Text("When the buyer accepts, the aircraft leaves your account and you can remove it from your devices. Your Engine Pulse account and subscription stay yours.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section {
            TextField("Buyer's email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Buyer's cell phone number", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        } header: {
            Text("New owner")
        } footer: {
            Text("The buyer must sign in to Engine Pulse with this email. The transfer code goes to this cell number by text, and the instructions to the email.")
        }
        Section {
            TextField("Type \(tail.isEmpty ? "the tail number" : tail) to confirm", text: $tailConfirm)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Toggle("I am the owner and I have sold or am selling this aircraft to this person", isOn: $confirmed)
                .font(.subheadline)
        } header: {
            Text("Confirm")
        }
        Section {
            Button {
                Task {
                    let state = CloudStore.appState(maintenance: maintenance, issues: issues, events: events)
                    code = await cloud.startTransfer(email: email, phone: phoneDigits, profile: aircraft.profile, logs: logs, state: state)
                }
            } label: {
                HStack {
                    if cloud.isBusy { ProgressView() }
                    Text("Start transfer").bold()
                }
            }
            .disabled(!canStart)
        } footer: {
            Text("Uploads any flights not in your account yet, then creates a code valid for 14 days. You can cancel until the buyer accepts.")
        }
    }

    @ViewBuilder
    private func pending(_ t: AircraftTransfer) -> some View {
        let shownCode = code ?? TransferCode.remembered(for: t.id)
        Section {
            LabeledContent("New owner", value: t.toEmail)
            LabeledContent("Cell", value: "ending \(t.phoneLast4)")
            if let exp = t.expiresAt {
                LabeledContent("Code expires", value: exp.formatted(date: .abbreviated, time: .omitted))
            }
            if let c = shownCode {
                LabeledContent("Transfer code") {
                    Text(TransferCode.display(c))
                        .font(.title3.monospaced().bold())
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Waiting for the buyer")
        } footer: {
            Text("Maintenance and notes you add before the buyer accepts go with the aircraft.")
        }
        Section {
            if let c = shownCode {
                TransferTextButton(transfer: t, code: c)
            }
            if let mail = TransferMessages.emailURL(transfer: t) {
                Link(destination: mail) {
                    Label("Email the buyer the instructions", systemImage: "envelope")
                }
            }
        } header: {
            Text("Send to the buyer")
        } footer: {
            Text("Send both: the code by text to \(t.phoneLast4.isEmpty ? "their cell" : "the cell ending \(t.phoneLast4)"), the steps by email. The buyer needs the code and that cell number to accept.")
        }
        Section {
            Button("Cancel transfer", role: .destructive) { confirmCancel = true }
        }
    }
}

/// Texts the code to the buyer (Messages), or offers the share sheet where texting isn't available.
private struct TransferTextButton: View {
    let transfer: AircraftTransfer
    let code: String
    @State private var composing = false

    var body: some View {
        let message = TransferMessages.text(transfer: transfer, code: code)
        if MFMessageComposeViewController.canSendText() {
            Button {
                composing = true
            } label: {
                Label("Text the code to the buyer", systemImage: "message")
            }
            .sheet(isPresented: $composing) {
                MessageComposer(recipients: [transfer.toPhone], body: message) { composing = false }
                    .ignoresSafeArea()
            }
        } else {
            ShareLink(item: message) {
                Label("Send the code to the buyer's cell", systemImage: "square.and.arrow.up")
            }
        }
    }
}

enum TransferMessages {
    static func expiry(_ t: AircraftTransfer) -> String {
        t.expiresAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "in 14 days"
    }

    static func text(transfer t: AircraftTransfer, code: String) -> String {
        "Engine Pulse transfer code for \(t.tailNumber): \(TransferCode.display(code)). Install Engine Pulse (enginepulse.net), sign in or register with \(t.toEmail), then go to ACCOUNT > Accept a transfer and enter this code and your cell number. Expires \(expiry(t))."
    }

    static func emailURL(transfer t: AircraftTransfer) -> URL? {
        let subject = "Engine Pulse records for \(t.tailNumber)"
        let body = """
        Hello,

        I'm transferring \(t.tailNumber)'s Engine Pulse records to you: every recorded flight with its engine analysis, the aircraft profile, maintenance history, notes and documents.

        1. Install Engine Pulse on your iPad or iPhone (enginepulse.net).
        2. Sign in, or register, with this email address: \(t.toEmail)
        3. Go to ACCOUNT > Accept a transfer.
        4. Enter the transfer code I texted to your cell ending \(t.phoneLast4), and your cell number.

        The code expires \(expiry(t)).
        """
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = t.toEmail
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return c.url
    }
}

/// Messages compose sheet.
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}

// MARK: - Buyer

struct AcceptTransferView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var events: DiagnosticEventStore
    @EnvironmentObject private var poh: POHRepository

    @State private var code = ""
    @State private var phone = ""
    @State private var message: String?
    @State private var accepted: String?
    @State private var working = false

    private var canAccept: Bool {
        TransferCode.normalize(code).count == 8 && phone.filter(\.isNumber).count >= 10 && !working
    }

    var body: some View {
        List {
            if !cloud.isSignedIn {
                Section {
                    Text("Sign in or register first, with the email address the seller used for the transfer.")
                }
            } else if let tail = accepted {
                Section {
                    Label("\(tail.isEmpty ? "The aircraft" : tail) is now yours", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Its flights, maintenance and notes are on this device, and its documents are being read. They follow you to your other devices when you sign in.")
                        .font(.subheadline)
                }
                if let status = cloud.status {
                    Section { Text(status).foregroundStyle(.secondary) }
                }
            } else {
                Section {
                    LabeledContent("Signed in as", value: cloud.session?.email ?? "Apple ID (email hidden)")
                    TextField("Transfer code (for example ABCD-2345)", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("Your cell phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("From the seller's text")
                } footer: {
                    Text("Use the code the seller texted you and the cell number it was sent to. The seller must have used the email you are signed in with.")
                }
                Section {
                    Button {
                        Task { await accept() }
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Text("Accept the aircraft").bold()
                        }
                    }
                    .disabled(!canAccept)
                } footer: {
                    Text("The aircraft is added to your account with its profile, flights, maintenance and notes. Any aircraft you already have stays: switch between them from the aircraft menu.")
                }
                if let message {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Accept a transfer")
    }

    private func accept() async {
        working = true
        defer { working = false }
        message = nil
        switch await cloud.acceptTransfer(code: code, phone: phone) {
        case .failed(let text):
            message = text
        case .accepted(let tail, let state):
            // The transferred aircraft is added to this account; the aircraft already on this device stays and
            // can be picked again from the aircraft menu.
            if let id = cloud.receivedAircraftID {
                let previous = cloud.aircraftID
                // An empty aircraft (made while registering) is replaced, as on the server.
                let keepPrevious = !logs.entries.isEmpty || !cloud.inboxItems.isEmpty
                await AircraftSwitcher.switchTo(id, cloud: cloud, aircraft: aircraft, logs: logs, maintenance: maintenance,
                                                issues: issues, events: events, poh: poh, syncFromCloud: false)
                if !keepPrevious { AircraftVault.discard(previous) }
            }
            let now = Date()
            if let state {
                maintenance.replaceFromCloud(items: state.maintenanceItems ?? MaintenanceSchedule.defaults,
                                             entries: state.maintenanceEntries ?? [], modified: now)
                await issues.replaceFromCloud(records: state.issueRecords ?? [:], modified: now)
                events.replaceFromCloud(events: state.events ?? [], modified: now)
            }
            accepted = tail
            await cloud.restore(aircraft: aircraft, logs: logs)
            await cloud.syncAppState(maintenance: maintenance, issues: issues, events: events)
            await cloud.refreshInbox()
            await cloud.refreshFleet()
        }
    }
}

// MARK: - After the sale (seller's devices)

/// Shown on the seller's devices once the buyer has accepted.
struct SoldAircraftNotice: View {
    let transfer: AircraftTransfer
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var events: DiagnosticEventStore
    @EnvironmentObject private var poh: POHRepository
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(transfer.tailNumber.isEmpty ? "This aircraft" : transfer.tailNumber) now belongs to its new owner", systemImage: "checkmark.seal")
                .font(.headline)
            Text("Its records moved to \(transfer.toEmail)\(transfer.acceptedAt.map { " on " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""). Syncing is paused on this device. Remove it here to set up your next aircraft.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Remove from this device", role: .destructive) { confirm = true }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .confirmationDialog("Remove \(transfer.tailNumber) from this device?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Remove flights, maintenance and documents", role: .destructive) {
                Task {
                    await SoldAircraftCleanup.run(cloud: cloud, aircraft: aircraft, logs: logs, maintenance: maintenance,
                                                  issues: issues, events: events, poh: poh)
                }
            }
        } message: {
            Text("The new owner keeps everything. This only clears this device.")
        }
    }
}

enum SoldAircraftCleanup {
    @MainActor
    static func run(cloud: CloudStore, aircraft: AircraftProfileStore, logs: FlightLogStore, maintenance: MaintenanceStore,
                    issues: IssueStore, events: DiagnosticEventStore, poh: POHRepository) async {
        let sold = cloud.aircraftID
        for entry in logs.entries { logs.delete(entry) }
        let now = Date()
        maintenance.replaceFromCloud(items: MaintenanceSchedule.defaults, entries: [], modified: now)
        await issues.replaceFromCloud(records: [:], modified: now)
        events.replaceFromCloud(events: [], modified: now)
        await poh.removeAll()
        // Another aircraft in this account: switch to it and drop the sold one from this device.
        await cloud.refreshFleet()
        if let other = cloud.fleet.first(where: { $0.id != sold }) {
            await AircraftSwitcher.switchTo(other.id, cloud: cloud, aircraft: aircraft, logs: logs, maintenance: maintenance,
                                            issues: issues, events: events, poh: poh)
            AircraftVault.discard(sold)
            return
        }
        cloud.forgetSoldAircraft()
        aircraft.profile = AircraftProfile.sr22TurboTemplate
        // This account's own copy of the records is now empty too (the buyer has theirs).
        await cloud.syncAppState(maintenance: maintenance, issues: issues, events: events)
    }
}

/// Another account signed in on this device: clear the previous account's local copy (it stays in that account).
enum AccountSwitchCleanup {
    @MainActor
    static func run(cloud: CloudStore, aircraft: AircraftProfileStore, logs: FlightLogStore, maintenance: MaintenanceStore,
                    issues: IssueStore, events: DiagnosticEventStore, poh: POHRepository) async {
        for entry in logs.entries { logs.delete(entry) }
        // Dated long ago, so the new account's saved records win when they sync.
        maintenance.replaceFromCloud(items: MaintenanceSchedule.defaults, entries: [], modified: .distantPast)
        await issues.replaceFromCloud(records: [:], modified: .distantPast)
        events.replaceFromCloud(events: [], modified: .distantPast)
        await poh.removeAll()
        cloud.resetForAccountSwitch()
        aircraft.profile = AircraftProfile.sr22TurboTemplate
    }
}
