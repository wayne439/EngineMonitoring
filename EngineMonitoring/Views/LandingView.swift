import SwiftUI
import AuthenticationServices
import UIKit

/// Decides what opens first: the landing page until the pilot signs in (or chooses to explore
/// without an account), then the app.
struct RootView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var flightLogs: FlightLogStore
    @AppStorage("EM.exploreWithoutAccount") private var exploring = false
    @State private var incomingMessage: String?
    @AppStorage("EM.documentsPromptShown") private var documentsPromptShown = false
    @State private var showDocuments = false

    var body: some View {
        Group {
            if cloud.isSignedIn || exploring {
                ContentView()
            } else {
                LandingView(exploring: $exploring)
            }
        }
        // Right after a pilot first signs in (usually straight after Register): upload your documents.
        .onChange(of: cloud.isSignedIn) {
            if cloud.isSignedIn && !documentsPromptShown {
                documentsPromptShown = true
                showDocuments = true
            }
        }
        .sheet(isPresented: $showDocuments) {
            NavigationStack {
                DocumentsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showDocuments = false } }
                    }
            }
        }
        // Files shared to the app (Files, Mail, AirDrop, Cirrus IQ, Garmin Pilot): "Open in AI Engine Monitoring".
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
        if url.pathExtension.lowercased() == "csv" {
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
                        Bullet("Reads the engine data your avionics already record. Garmin G1000 / NXi and Perspective logs work today, with more monitors coming.")
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
                        Text("AI Engine Monitoring is built by Fueled Consulting LLC in Cave Creek, Arizona. It started as the tool we built to watch the engine on our own airplane after every flight, and we are now opening it to every owner whose avionics record engine data.")
                        Text("We are pilots and owners first. Questions or ideas: support@fueledconsulting.com")
                            .foregroundStyle(.secondary)
                    }
                    Text("Advisory only. AI Engine Monitoring is not FAA-approved and never replaces your POH/AFM, your engine monitor or your A&P.")
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
            Text("AI Engine Monitoring")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("AI early warning from your engine data")
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
                Text("Register for AI Engine Monitoring")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            NavigationLink {
                LoginView()
            } label: {
                Text("Log in to AI Engine Monitoring")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if cloud.isConfigured {
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
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var agreed = false
    @State private var done = false

    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter your name." }
        if !email.contains("@") || !email.contains(".") { return "Enter a valid email address." }
        if password.count < 8 { return "Use at least 8 characters for the password." }
        if password != confirm { return "The passwords do not match." }
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
                SecureField("Password (8+ characters)", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
            } header: {
                Text("1. Create your account")
            }
            Section {
                Picker("Aircraft", selection: $aircraftID) {
                    Text("Select your aircraft").tag("")
                    ForEach(AircraftModelOption.catalog) { option in
                        Text(option.id == AircraftModelOption.other.id ? "Other (enter details later)" : option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                TextField("Tail number (e.g. N12345)", text: $tailNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if let selected, selected.id != AircraftModelOption.other.id {
                    Text("\(selected.cylinders) cylinders, \(selected.turbo ? "turbocharged" : "normally aspirated"). You can change any of this in Aircraft Profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("2. Your aircraft")
            } footer: {
                Text("Single-engine piston aircraft for now. Twins and turbines are coming.")
            }
            Section {
                Picker("Avionics / engine monitor", selection: $monitor) {
                    ForEach(EngineMonitorType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Wireless data link", selection: $link) {
                    ForEach(DataLink.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                DataPathAdviceView(advice: DataPathAdvice.advise(monitor: monitor, link: link, make: selected?.make ?? ""))
            } header: {
                Text("3. Avionics and how your data gets to us")
            } footer: {
                Text("Not sure? Check the avionics name on the startup screen, or ask your avionics shop. You can change this later in Aircraft Profile.")
            }
            DataChecklistSection(turbo: selected?.turbo ?? false, monitor: monitor,
                                 header: "4. Data to have ready")
            Section {
                Toggle("I understand AI Engine Monitoring is advisory only and does not replace my POH/AFM, engine monitor or A&P.", isOn: $agreed)
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
            if done && !cloud.isSignedIn {
                Section {
                    NavigationLink("Go to log in") { LoginView() }
                }
            }
        }
        .navigationTitle("Register")
        .onAppear { cloud.clearMessages() }
        // Choosing an aircraft suggests its usual avionics; the pilot can still change it.
        .onChange(of: aircraftID) {
            if let selected, selected.id != AircraftModelOption.other.id { monitor = selected.monitor }
        }
    }
}

// MARK: - Log in

struct LoginView: View {
    @EnvironmentObject private var cloud: CloudStore
    @State private var email = ""
    @State private var password = ""

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
                    Task { await cloud.resetPassword(email: email.trimmingCharacters(in: .whitespaces)) }
                }
                .disabled(!email.contains("@") || cloud.isBusy || !cloud.isConfigured)
            }
            if cloud.isConfigured {
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
        }
        .padding(.vertical, 4)
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
