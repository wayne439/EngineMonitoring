import SwiftUI

@main
struct EngineMonitoringApp: App {
    @StateObject private var repository = DocumentRepository()
    @StateObject private var diagnosticEvents = DiagnosticEventStore()
    @StateObject private var flightLogs = FlightLogStore()
    @StateObject private var poh = POHRepository()
    @StateObject private var guides = ApproachGuideStore()
    @StateObject private var issues = IssueStore()
    @StateObject private var maintenance = MaintenanceStore()
    @StateObject private var aircraft = AircraftProfileStore()
    @StateObject private var cloud = CloudStore()
    @StateObject private var subscription = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
            // Landing page (register / log in / about) until signed in or exploring, then the app.
            RootView()
                .environmentObject(repository)
                .environmentObject(diagnosticEvents)
                .environmentObject(flightLogs)
                .environmentObject(poh)
                .environmentObject(guides)
                .environmentObject(issues)
                .environmentObject(maintenance)
                .environmentObject(aircraft)
                .environmentObject(cloud)
                .environmentObject(subscription)
        }
    }
}
