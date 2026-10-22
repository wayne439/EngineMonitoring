import SwiftUI
import AuthenticationServices
import UIKit

/// Decides what opens first: the landing page until the pilot signs in (or chooses to explore
/// without an account), then the app.
struct RootView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var flightLogs: FlightLogStore
    @EnvironmentObject private var subscription: SubscriptionStore
    @AppStorage("EM.exploreWithoutAccount") private var exploring = false
    @State private var incomingMessage: String?
    @AppStorage("EM.documentsPromptShown") private var documentsPromptShown = false
    @State private var showDocuments = false

    var body: some View {
        Group {
            if (cloud.isSignedIn || exploring) && !subscription.hasAccess {
                // After the beta: the app needs Engine Pulse Pro (the free trial starts here).
                NavigationStack { PaywallView(isGate: true) }
            } else if cloud.isSignedIn || exploring {
                ContentView()
            } else {
                LandingView(exploring: $exploring)
            }
        }
        // Right after a pilot first signs in (usually straight after Register): bring in your flights.
        .onChange(of: cloud.isSignedIn) {
            if cloud.isSignedIn && !documentsPromptShown {
                documentsPromptShown = true
                showDocuments = true
            }
        }
        .sheet(isPresented: $showDocuments) {
            NavigationStack {
                GetStartedView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showDocuments = false } }
                    }
            }
        }
        // Files shared to the app (Files, Mail, AirDrop, Cirrus IQ, Garmin Pilot): "Open in Engine Pulse".
        .onOpenURL { url in
            Task { await receive(url) }
        }
        .alert("Engine data", isPresented: Binding(get: { incomingMessage != nil }, set: { if !$0 { incomingMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(incomingMessage ?? "")
        }
    }

    /// Garmin CSV logs are analyzed right away; other formats go to the cloud inbox until they are supported.
    private func receive(_ url: URL) async {
        guard url.isFileURL else { return }
        if EngineLogConverter.logExtensions.contains(url.pathExtension.lowercased()) {
            flightLogs.lastError = nil
            await flightLogs.importFiles([url])
            incomingMessage = flightLogs.lastError ?? flightLogs.importSummary ?? "\(url.lastPathComponent) was imported."
            flightLogs.lastError = nil
        } else {
            incomingMessage = await cloud.uploadToInbox(fileURL: url, source: "share")
        }
    }
}

// MARK: - Landing page

struct LandingView: View {
    @EnvironmentObject private var cloud: CloudStore
    @Binding var exploring: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    actions
                    InfoCard(title: "What it does", systemImage: "waveform.path.ecg") {
                        Bullet("Reads the engine data your avionics already record: Garmin G1000 / NXi, Perspective, G3X and TXi, J.P. Instruments EDM, Electronics International, Dynon, Avidyne and other CSV engine logs.")
                        Bullet("After every flight, compares each cylinder, temperature and pressure with your engine's own normal and with the limits from your POH.")
                        Bullet("Early warning spots slow trends (exhaust valves, probes, induction leaks, turbo, oil) before they turn into squawks.")
                        Bullet("Keeps maintenance on track: oil changes, the annual and your own pilot checks.")
                    }
                    InfoCard(title: "Why pilots use it", systemImage: "airplane") {
                        Benefit("shield.checkered", "Catch problems early", "Find a failing valve, probe or leak while it is still a small fix.")
                        Benefit("doc.text.magnifyingglass", "Walk into the shop prepared", "A one-page pre-shop report shows your A&P exactly what the data says.")
                        Benefit("chart.xyaxis.line", "Know your engine", "A report card and trend charts after every flight show what normal looks like for your airplane.")
                        Benefit("wifi.slash", "Works in the cockpit", "Everything runs on your iPad, with or without internet.")
                        Benefit("lock.shield", "Your data stays yours", "Your aircraft and logs are private to your account and can be deleted at any time.")
                    }
                    InfoCard(title: "About us", systemImage: "person.2") {
                        Text("Engine Pulse is built by Fueled Consulting LLC in Cave Creek, Arizona. It started as the tool we built to watch the engine on our own airplane after every flight, and we are now opening it to every owner whose avionics record engine data.")
                        Text("We are pilots and owners first. Questions or ideas: sales@enginepulse.net")
                            .foregroundStyle(.secondary)
                    }
                    Text("Advisory only. Engine Pulse is not FAA-approved and never replaces your POH/AFM, your engine monitor or your A&P.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(radius: 8, y: 4)
            Text("Engine Pulse")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Engine monitoring for your aircraft")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            NavigationLink {
                RegisterView()
            } label: {
                Text("Register for Engine Pulse")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            NavigationLink {
                LoginView()
            } label: {
                Text("Log in to Engine Pulse")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if cloud.isConfigured && AppleSignIn.enabled {
                AppleSignInButton()
                    .frame(height: 50)
            }

            Button("Explore without an account") { exploring = true }
                .font(.subheadline)
                .padding(.top, 4)

            if let error = cloud.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Register

struct RegisterView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @State private var aircraftID = ""
    @State private var tailNumber = ""
    @State private var monitor: EngineMonitorType = .garminG1000
    @State private var link: DataLink = .notSure
    @State private var make = ""
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var agreed = false
    @State private var done = false

    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter your name." }
        if !email.contains("@") || !email.contains(".") { return "Enter a valid email address." }
        if password.count < 8 { return "Use at least 8 characters for the password." }
        if aircraftID.isEmpty { return "Choose your aircraft." }
        if tailNumber.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter your tail number." }
        if !agreed { return "Please accept the advisory notice." }
        return nil
    }

    private var selected: AircraftModelOption? {
        AircraftModelOption.catalog.first { $0.id == aircraftID }
    }

    var body: some View {
        Form {
            NotConfiguredNotice()
            Section {
                TextField("Full name", text: $name)
                    .textContentType(.name)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Group {
                    if showPassword {
                        TextField("Password (8+ characters)", text: $password)
                    } else {
                        SecureField("Password (8+ characters)", text: $password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Toggle("Show password", isOn: $showPassword)
                    .font(.footnote)
            } header: {
                Text("1. Your account")
            } footer: {
                Text("Use this email and password on every iPad and iPhone, and on enginepulse.net/upload.")
            }
            Section {
                Picker("Make", selection: $make) {
                    Text("Select the make").tag("")
                    ForEach(AircraftModelOption.makes, id: \.self) { Text($0).tag($0) }
                    Text("Other (enter details later)").tag(AircraftModelOption.other.id)
                }
                .pickerStyle(.menu)
                if !make.isEmpty && make != AircraftModelOption.other.id {
                    Picker("Model", selection: $aircraftID) {
                        Text("Select the model").tag("")
                        ForEach(AircraftModelOption.models(of: make)) { Text($0.model).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                TextField("Tail number (e.g. N12345)", text: $tailNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if let selected, selected.id != AircraftModelOption.other.id {
                    Text("\(selected.cylinders) cylinders, \(selected.turbo ? "turbocharged" : "normally aspirated")\(selected.twin ? ", twin (the left engine is analysed for now)" : ""). You can change any of this in Aircraft Profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Picker("Avionics / engine monitor", selection: $monitor) {
                    ForEach(EngineMonitorType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            } header: {
                Text("2. Your aircraft")
            } footer: {
                Text("Pick the make and model (or Other). The usual avionics fill in; change them if yours differ. Everything else, like how your data gets here, is set up after you register.")
            }
            Section {
                Toggle("I understand Engine Pulse is advisory only and does not replace my POH/AFM, engine monitor or A&P.", isOn: $agreed)
                    .font(.footnote)
            }
            Section {
                Button {
                    Task {
                        done = await cloud.register(email: email.trimmingCharacters(in: .whitespaces), password: password, fullName: name)
                        if done, let selected {
                            var p = selected.applied(to: aircraft.profile, tailNumber: tailNumber)
                            p.monitor = monitor
                            p.dataLink = link
                            aircraft.profile = p
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if cloud.isBusy { ProgressView() } else { Text("Register").bold() }
                        Spacer()
                    }
                }
                .disabled(problem != nil || cloud.isBusy || !cloud.isConfigured)
            } footer: {
                // Always say why Register is grey, so a pilot is never stuck guessing.
                if !cloud.isConfigured {
                    Text("Register is turned off because accounts are not switched on in this test build yet. Use Explore without an account for now.")
                        .foregroundStyle(.orange)
                } else if let problem {
                    Text(problem).foregroundStyle(.orange)
                }
            }
            MessagesSection()
            if done && !cloud.isSignedIn && cloud.pendingConfirmationEmail != nil {
                ConfirmCodeSection()
            }
        }
        .navigationTitle("Register")
        .onAppear { cloud.clearMessages() }
        // Choosing an aircraft suggests its usual avionics; the pilot can still change it.
        .onChange(of: aircraftID) {
            if let selected, selected.id != AircraftModelOption.other.id { monitor = selected.monitor }
        }
        // A new make clears the model; Other needs no model.
        .onChange(of: make) {
            aircraftID = make == AircraftModelOption.other.id ? AircraftModelOption.other.id : ""
        }
    }
}

// MARK: - Log in

struct LoginView: View {
    @EnvironmentObject private var cloud: CloudStore
    @State private var email = ""
    @State private var password = ""
    @State private var resetRequested = false
    @State private var resetCode = ""
    @State private var newPassword = ""

    var body: some View {
        Form {
            NotConfiguredNotice()
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Log in")
            }
            Section {
                Button {
                    Task { _ = await cloud.logIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                } label: {
                    HStack {
                        Spacer()
                        if cloud.isBusy { ProgressView() } else { Text("Log in").bold() }
                        Spacer()
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || cloud.isBusy || !cloud.isConfigured)
                Button("Forgot password?") {
                    Task {
                        await cloud.resetPassword(email: email.trimmingCharacters(in: .whitespaces))
                        resetRequested = cloud.lastError == nil
                    }
                }
                .disabled(!email.contains("@") || cloud.isBusy || !cloud.isConfigured)
            } footer: {
                if !email.contains("@") { Text("Enter your email above to reset your password.") }
            }
            if cloud.pendingConfirmationEmail != nil {
                ConfirmCodeSection()
            }
            if resetRequested {
                Section {
                    TextField("6-digit code from the email", text: $resetCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    SecureField("New password (8+ characters)", text: $newPassword)
                        .textContentType(.newPassword)
                    Button("Set new password and log in") {
                        Task {
                            if await cloud.resetPassword(email: email.trimmingCharacters(in: .whitespaces),
                                                         code: resetCode.trimmingCharacters(in: .whitespaces),
                                                         newPassword: newPassword) {
                                resetRequested = false
                            }
                        }
                    }
                    .disabled(resetCode.count < 6 || newPassword.count < 8 || cloud.isBusy)
                } header: {
                    Text("Reset your password")
                }
            }
            if cloud.isConfigured && AppleSignIn.enabled {
                Section {
                    AppleSignInButton()
                        .frame(height: 48)
                } header: {
                    Text("Or")
                }
            }
            MessagesSection()
        }
        .navigationTitle("Log In")
        .onAppear { cloud.clearMessages() }
    }
}

// MARK: - Email confirmation code

/// Type the 6-digit code from the confirmation email (no web page needed), or resend it.
struct ConfirmCodeSection: View {
    @EnvironmentObject private var cloud: CloudStore
    @State private var code = ""

    var body: some View {
        Section {
            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit())
            Button {
                Task { _ = await cloud.confirmEmail(code: code.trimmingCharacters(in: .whitespaces)) }
            } label: {
                HStack {
                    Spacer()
                    if cloud.isBusy { ProgressView() } else { Text("Confirm and sign in").bold() }
                    Spacer()
                }
            }
            .disabled(code.trimmingCharacters(in: .whitespaces).count < 6 || cloud.isBusy)
            Button("Resend code") { Task { await cloud.resendConfirmation() } }
                .disabled(cloud.isBusy)
        } header: {
            Text("Confirm your email")
        } footer: {
            Text("We sent the code to \(cloud.pendingConfirmationEmail ?? "your email"). Check spam if you don't see it.")
        }
    }
}

// MARK: - Data path advice

/// "Best way to get your data in" box for the chosen avionics and data link.
struct DataPathAdviceView: View {
    let advice: DataPathAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(advice.title, systemImage: advice.automatic ? "antenna.radiowaves.left.and.right" : "sdcard")
                .font(.subheadline.bold())
                .foregroundStyle(advice.automatic ? Color.green : Color.accentColor)
            ForEach(Array(advice.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).").font(.footnote.bold()).foregroundStyle(.secondary)
                    Text(step).font(.footnote)
                }
            }
            if advice.showsGarminGuide {
                NavigationLink {
                    GarminImportGuideView()
                } label: {
                    Label("Step-by-step: get your flights from Garmin", systemImage: "book")
                        .font(.footnote.bold())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// How to bring flights from a GDL 60 or Flight Stream 510 into Engine Pulse, until flyGarmin sharing is approved.
struct GarminImportGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Garmin's GDL 60 and Flight Stream 510 only send engine logs to Garmin's own apps (Garmin Pilot and flyGarmin). From there, each flight takes a few taps to reach Engine Pulse.")
                    .font(.subheadline)
            }
            Section {
                GuideStep(n: 1, text: "Before the flight, open Garmin Pilot and connect it to the Flight Stream 510 (Connext). Keep it open, in the foreground or background, for the whole flight.")
                GuideStep(n: 2, text: "After landing, in Garmin Pilot: More > Logbook > Entries, and open the flight.")
                GuideStep(n: 3, text: "Tap the Share icon, choose CSV, then choose Engine Pulse. (If Engine Pulse isn't in the row of apps, tap More and add it.)")
                GuideStep(n: 4, text: "Engine Pulse opens and adds the flight. Its report and the health score update straight away.")
            } header: {
                Text("Flight Stream 510: from Garmin Pilot on the iPad")
            } footer: {
                Text("Garmin lists Flight Stream 510 engine logs for the G1000 NXi, TXi and GI 275 EIS. If the logbook entry has no engine data, use the data card or flyGarmin.")
            }
            Section {
                GuideStep(n: 1, text: "On a computer, sign in at flyGarmin.com and open Logbook. With a GDL 60 the flight appears a few minutes after shutdown; with a Flight Stream 510, after Garmin Pilot syncs.")
                GuideStep(n: 2, text: "Open the flight, click Download, and choose Original CSV.")
                GuideStep(n: 3, text: "Go to enginepulse.net/upload (or use Email me an upload link in AIRCRAFT > Documents and uploads), sign in, and drop the file on Engine monitor log files.")
                GuideStep(n: 4, text: "Open Engine Pulse on the iPad: the flight is imported automatically.")
            } header: {
                Text("GDL 60 or Flight Stream 510: from flyGarmin on a computer")
            }
            Section {
                Text("We plan to receive flights through Garmin's flyGarmin sharing program, the way FlySto and Savvy do. Once Garmin approves Engine Pulse, you switch on sharing in flyGarmin once and every flight arrives on its own.")
                    .font(.subheadline)
            } header: {
                Text("Planned: automatic")
            }
            Section {
                Text("If a file won't import, email it to sales@enginepulse.net and we'll add support for it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Flights from Garmin")
    }
}

private struct GuideStep: View {
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
        .padding(.vertical, 2)
    }
}

// MARK: - Data checklist

/// Tick list of the data a pilot gathers so the analysis has everything it needs. Ticks are kept on this device.
struct DataChecklistSection: View {
    let turbo: Bool
    let monitor: EngineMonitorType
    var header = "Data to have ready"
    @AppStorage("EM.dataChecklist") private var doneRaw = ""

    private var done: Set<String> { Set(doneRaw.split(separator: ",").map(String.init)) }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { done.contains(id) }, set: { on in
            var s = done
            if on { s.insert(id) } else { s.remove(id) }
            doneRaw = s.sorted().joined(separator: ",")
        })
    }

    var body: some View {
        let items = DataChecklist.items(turbo: turbo, monitor: monitor)
        let required = items.filter { $0.level == .required }
        let readyRequired = required.filter { done.contains($0.id) }.count
        Section {
            ForEach(items) { item in
                Toggle(isOn: binding(item.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.title).font(.subheadline.bold())
                            Text(item.level.rawValue.uppercased())
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(item.level == .required ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.15),
                                            in: Capsule())
                        }
                        Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(header)
        } footer: {
            Text(readyRequired == required.count
                 ? "All required items are ready. You will upload the log files after you sign in."
                 : "\(readyRequired) of \(required.count) required items ready. Tick each one as you gather it; you can finish this later under AIRCRAFT.")
        }
    }
}

/// The checklist on its own screen (AIRCRAFT > Data checklist).
struct DataChecklistView: View {
    @EnvironmentObject private var aircraft: AircraftProfileStore

    var body: some View {
        Form {
            DataChecklistSection(turbo: aircraft.profile.isTurbocharged, monitor: aircraft.profile.monitor)
        }
        .navigationTitle("Data Checklist")
    }
}

// MARK: - Shared pieces

/// Sign in with Apple is off during the beta: "Hide My Email" made separate, empty accounts that didn't match
/// the email used on the upload website. Email and password is the only sign-in, so Apple doesn't require it.
/// Accounts made with Apple keep working while their session lasts.
enum AppleSignIn {
    static let enabled = false
}

/// Sign in with Apple, using the same nonce handshake as the ACCOUNT screen.
struct AppleSignInButton: View {
    @EnvironmentObject private var cloud: CloudStore
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = CloudAPI.randomNonce()
            request.requestedScopes = [.fullName, .email]
            request.nonce = CloudAPI.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    cloud.lastError = "Apple did not return a sign-in token."
                    return
                }
                let raw = nonce
                Task { await cloud.signIn(idToken: idToken, nonce: raw) }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    cloud.lastError = "Sign in with Apple failed: \(error.localizedDescription)"
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
    }
}

private struct NotConfiguredNotice: View {
    @EnvironmentObject private var cloud: CloudStore

    var body: some View {
        if !cloud.isConfigured {
            Section {
                Label("Accounts are not switched on in this test build yet. Go back and choose Explore without an account.", systemImage: "info.circle")
                    .font(.footnote)
            }
        }
    }
}

private struct MessagesSection: View {
    @EnvironmentObject private var cloud: CloudStore

    var body: some View {
        if cloud.status != nil || cloud.lastError != nil {
            Section {
                if let status = cloud.status { Text(status) }
                if let error = cloud.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
        }
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct Bullet: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            Text(text)
        }
    }
}

private struct Benefit: View {
    let symbol: String
    let title: String
    let detail: String
    init(_ symbol: String, _ title: String, _ detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
