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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(repository)
                .environmentObject(diagnosticEvents)
                .environmentObject(flightLogs)
                .environmentObject(poh)
                .environmentObject(guides)
                .environmentObject(issues)
                .environmentObject(maintenance)
        }
    }
}
