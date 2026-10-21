import SwiftUI

struct ContentView: View {
    @State private var selection: SectionItem? = .home
    @EnvironmentObject private var flightLogs: FlightLogStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var poh: POHRepository
    @EnvironmentObject private var diagnosticEvents: DiagnosticEventStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSold = false
    @AppStorage("EM.soldNoticeShown") private var soldNoticeShown = ""

    enum SectionItem: String, CaseIterable, Identifiable {
        case home = "HOME"
        case diagnostics = "DIAGNOSTICS"
        case myFlying = "MY FLYING"
        case maintenance = "MAINTENANCE"
        case aircraft = "AIRCRAFT"
        case ask = "ASK"
        case account = "ACCOUNT"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: "waveform.path.ecg"
            case .diagnostics: "stethoscope"
            case .myFlying: "chart.xyaxis.line"
            case .maintenance: "checklist"
            case .aircraft: "wrench.and.screwdriver"
            case .ask: "bubble.left.and.text.bubble.right"
            case .account: "person.crop.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SectionItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("Engine Pulse")
            .safeAreaInset(edge: .bottom) {
                // Shows which build is running, so an old install is easy to spot.
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        } detail: {
            NavigationStack {
                switch selection ?? .home {
                case .home: HomeView(go: { selection = $0 })
                case .diagnostics: DiagnosticsView()
                case .myFlying: MyFlyingView()
                case .maintenance: MaintenanceView()
                case .aircraft: AircraftView()
                case .ask: AskView()
                case .account: AccountView()
                }
            }
            // A fresh stack per section, so switching sections never leaves a stale pushed screen.
            .id(selection ?? .home)
        }
        // Issue history follows the flight summaries (bundled history plus every imported log).
        .task(id: flightLogs.summaries.count) {
            await issues.refresh(summaries: Array(flightLogs.summaries.values))
            MaintenanceReminders.reschedule(store: maintenance, summaries: Array(flightLogs.summaries.values))
            EarlyWarningNotifier.check(summaries: Array(flightLogs.summaries.values))
            // New logs go to the subscriber's cloud account (no-op when signed out or not configured).
            await cloud.sync(profile: aircraft.profile, logs: flightLogs)
        }
        // Files uploaded on the website arrive whenever the app opens or comes back to the front.
        // After signing in (here or on another device): bring back the aircraft and flights, then new uploads.
        .task(id: cloud.session?.userID) {
            // A different account than the one whose data is on this device: clear the local copy first, so
            // one pilot's flights never show in (or upload to) another pilot's account.
            if let uid = cloud.session?.userID.lowercased() {
                if let previous = cloud.deviceOwner, previous != uid {
                    await AccountSwitchCleanup.run(cloud: cloud, aircraft: aircraft, logs: flightLogs, maintenance: maintenance,
                                                   issues: issues, events: diagnosticEvents, poh: poh)
                }
                cloud.deviceOwner = uid
            }
            await cloud.restore(aircraft: aircraft, logs: flightLogs)
            await cloud.syncAppState(maintenance: maintenance, issues: issues, events: diagnosticEvents)
            await cloud.pullInbox(logs: flightLogs)
        }
        // Maintenance, issue reviews and event markers follow the pilot to every device (a few seconds after a change).
        .task(id: [maintenance.modifiedAt, issues.modifiedAt, diagnosticEvents.modifiedAt]) {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await cloud.syncAppState(maintenance: maintenance, issues: issues, events: diagnosticEvents)
        }
        // The seller's devices, once the buyer has accepted a transfer of this aircraft.
        .onChange(of: cloud.soldAircraft?.id) {
            if let id = cloud.soldAircraft?.id, soldNoticeShown != id {
                soldNoticeShown = id
                showSold = true
            }
        }
        .alert("Aircraft transferred", isPresented: $showSold) {
            Button("Open ACCOUNT") { selection = .account }
            Button("Later", role: .cancel) {}
        } message: {
            Text("\(cloud.soldAircraft?.tailNumber ?? "Your aircraft") now belongs to its new owner, with all its records. Syncing is paused on this device until you remove it (ACCOUNT).")
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await cloud.restore(aircraft: aircraft, logs: flightLogs)
                    await cloud.syncAppState(maintenance: maintenance, issues: issues, events: diagnosticEvents)
                    await cloud.pullInbox(logs: flightLogs)
                }
            }
        }
        // POH and manual PDFs from the uploads are read on this iPad (PROCEDURES, ASK).
        .onChange(of: cloud.inboxItems) {
            Task { await poh.syncFromUploads(cloud: cloud) }
        }
        // Engine model and limits come from the POH as soon as it has been read, then the profile locks.
        .task(id: ([poh.index?.document.filename].compactMap { $0 } + poh.manuals.map(\.document.filename)).joined(separator: ",")) {
            aircraft.applyDocuments(poh: poh.index, manuals: poh.manuals)
        }
        // Profile edits are uploaded when the owner leaves the profile screen (it stamps updatedAt).
        .onChange(of: aircraft.profile.updatedAt) {
            Task { await cloud.sync(profile: aircraft.profile, logs: flightLogs) }
        }
        .onAppear {
            let store = maintenance, logs = flightLogs
            store.onChange = { [weak store, weak logs] in
                guard let store, let logs else { return }
                MaintenanceReminders.reschedule(store: store, summaries: Array(logs.summaries.values))
            }
        }
    }
}
