import SwiftUI

struct ContentView: View {
    @State private var selection: SectionItem? = .fly
    @EnvironmentObject private var flightLogs: FlightLogStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var cloud: CloudStore

    enum SectionItem: String, CaseIterable, Identifiable {
        case fly = "FLY"
        case procedures = "PROCEDURES"
        case diagnostics = "DIAGNOSTICS"
        case myFlying = "MY FLYING"
        case maintenance = "MAINTENANCE"
        case aircraft = "AIRCRAFT"
        case ask = "ASK"
        case account = "ACCOUNT"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .fly: "airplane"
            case .procedures: "exclamationmark.triangle"
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
            .navigationTitle("Engine Monitoring")
            .safeAreaInset(edge: .bottom) {
                // Shows which build is running, so an old install is easy to spot.
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        } detail: {
            NavigationStack {
                switch selection ?? .fly {
                case .fly: FlyView()
                case .procedures: ProceduresView()
                case .diagnostics: DiagnosticsView()
                case .myFlying: MyFlyingView()
                case .maintenance: MaintenanceView()
                case .aircraft: AircraftView()
                case .ask: AskView()
                case .account: AccountView()
                }
            }
            // A fresh stack per section, so switching sections never leaves a stale pushed screen.
            .id(selection ?? .fly)
        }
        // Issue history follows the flight summaries (bundled history plus every imported log).
        .task(id: flightLogs.summaries.count) {
            await issues.refresh(summaries: Array(flightLogs.summaries.values))
            MaintenanceReminders.reschedule(store: maintenance, summaries: Array(flightLogs.summaries.values))
            EarlyWarningNotifier.check(summaries: Array(flightLogs.summaries.values))
            // New logs go to the subscriber's cloud account (no-op when signed out or not configured).
            await cloud.sync(profile: aircraft.profile, logs: flightLogs)
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
