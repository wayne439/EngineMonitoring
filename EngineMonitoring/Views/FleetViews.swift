import SwiftUI

/// Everything needed to switch the selected aircraft, shared by the aircraft menu, AIRCRAFT and the import screens.
struct FleetActions {
    let cloud: CloudStore
    let aircraft: AircraftProfileStore
    let logs: FlightLogStore
    let maintenance: MaintenanceStore
    let issues: IssueStore
    let events: DiagnosticEventStore
    let poh: POHRepository

    @MainActor
    func switchTo(_ id: UUID, newProfile: AircraftProfile? = nil) async {
        await AircraftSwitcher.switchTo(id, cloud: cloud, aircraft: aircraft, logs: logs, maintenance: maintenance,
                                        issues: issues, events: events, poh: poh, newProfile: newProfile)
    }
}

/// Reads the stores from the environment and hands a FleetActions to its content.
struct WithFleetActions<Content: View>: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var events: DiagnosticEventStore
    @EnvironmentObject private var poh: POHRepository
    let content: (FleetActions) -> Content

    var body: some View {
        content(FleetActions(cloud: cloud, aircraft: aircraft, logs: logs, maintenance: maintenance,
                             issues: issues, events: events, poh: poh))
    }
}

/// The selected aircraft's tail, with a menu to pick another or add one.
struct AircraftMenu: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @State private var adding = false
    @State private var switching = false

    private var currentTitle: String {
        let tail = aircraft.profile.tailNumber.trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? "Your aircraft" : tail
    }

    var body: some View {
        WithFleetActions { actions in
          VStack(alignment: .leading, spacing: 2) {
            Menu {
                if cloud.fleet.count > 1 {
                    Section("Switch aircraft") {
                        ForEach(cloud.fleet) { plane in
                            Button {
                                Task {
                                    switching = true
                                    await actions.switchTo(plane.id)
                                    switching = false
                                }
                            } label: {
                                if plane.id == cloud.aircraftID {
                                    Label(plane.title + (plane.subtitle.isEmpty ? "" : " · " + plane.subtitle), systemImage: "checkmark")
                                } else {
                                    Text(plane.title + (plane.subtitle.isEmpty ? "" : " · " + plane.subtitle))
                                }
                            }
                            .disabled(plane.id == cloud.aircraftID)
                        }
                    }
                }
                Button {
                    adding = true
                } label: {
                    Label("Add another aircraft…", systemImage: "plus")
                }
                .disabled(!cloud.isSignedIn)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "airplane")
                    Text(currentTitle).font(.headline.monospaced())
                    if switching || cloud.isBusy { ProgressView().controlSize(.small) } else { Image(systemName: "chevron.up.chevron.down").font(.caption) }
                }
            }
            .disabled(cloud.isBusy || switching)
            // Why the menu is grey: say what the app is doing (switching waits for it to finish).
            if cloud.isBusy || switching, let status = cloud.status {
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
          }
            .sheet(isPresented: $adding) {
                NavigationStack { AddAircraftView(actions: actions) }
            }
        }
        .task(id: cloud.session?.userID) { await cloud.refreshFleet() }
    }
}

/// Adds an aircraft to the account and switches to it. The current aircraft stays and can be picked again.
struct AddAircraftView: View {
    let actions: FleetActions
    @Environment(\.dismiss) private var dismiss
    @State private var make = ""
    @State private var modelID = ""
    @State private var tail = ""
    @State private var monitor: EngineMonitorType = .garminG1000
    @State private var working = false
    @State private var error: String?

    private var selected: AircraftModelOption? { AircraftModelOption.catalog.first { $0.id == modelID } }
    private var ready: Bool { !modelID.isEmpty && !tail.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                Picker("Make", selection: $make) {
                    Text("Select the make").tag("")
                    ForEach(AircraftModelOption.makes, id: \.self) { Text($0).tag($0) }
                    Text("Other (enter details later)").tag(AircraftModelOption.other.id)
                }
                .pickerStyle(.menu)
                if !make.isEmpty && make != AircraftModelOption.other.id {
                    Picker("Model", selection: $modelID) {
                        Text("Select the model").tag("")
                        ForEach(AircraftModelOption.models(of: make)) { Text($0.model).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                TextField("Tail number (e.g. N12345)", text: $tail)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Picker("Avionics / engine monitor", selection: $monitor) {
                    ForEach(EngineMonitorType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Only the make, model and tail number are needed now. The POH, logs and records can come later: the aircraft is saved straight away, and HOME shows what's left to set up whenever it's selected. Your current aircraft and everything recorded for it stay; switch between aircraft from the aircraft menu.")
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack { Spacer(); if working { ProgressView() } else { Text("Add aircraft").bold() }; Spacer() }
                }
                .disabled(!ready || working)
            }
        }
        .navigationTitle("Add an aircraft")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onChange(of: make) { modelID = make == AircraftModelOption.other.id ? AircraftModelOption.other.id : "" }
        .onChange(of: modelID) { if let selected, selected.id != AircraftModelOption.other.id { monitor = selected.monitor } }
    }

    private func add() async {
        guard let selected else { return }
        working = true
        defer { working = false }
        var profile = selected.applied(to: AircraftProfile.sr22TurboTemplate, tailNumber: tail.trimmingCharacters(in: .whitespaces).uppercased())
        profile.monitor = monitor
        guard let id = await actions.cloud.createAircraft(profile: profile) else {
            error = actions.cloud.lastError ?? "The aircraft could not be added."
            return
        }
        await actions.switchTo(id, newProfile: profile)
        dismiss()
    }
}

/// AIRCRAFT: every aircraft in the account, with switch, add and remove.
struct FleetSection: View {
    @EnvironmentObject private var cloud: CloudStore
    @State private var adding = false
    @State private var removing: FleetAircraft?
    @State private var switching = false

    var body: some View {
        WithFleetActions { actions in
            Section {
                ForEach(cloud.fleet) { plane in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plane.title).font(.headline.monospaced())
                            if !plane.subtitle.isEmpty { Text(plane.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if plane.id == cloud.aircraftID {
                            if actions.aircraft.needsSetup {
                                NavigationLink { AircraftProfileView() } label: {
                                    Text("Finish setup").font(.caption.bold()).foregroundStyle(.orange)
                                }
                                .fixedSize()
                            } else {
                                Text("Selected").font(.caption.bold()).foregroundStyle(.green)
                            }
                        } else {
                            Button("Switch") {
                                Task { switching = true; await actions.switchTo(plane.id); switching = false }
                            }
                            .buttonStyle(.bordered)
                            .disabled(cloud.isBusy || switching)
                        }
                    }
                    .swipeActions {
                        if plane.id != cloud.aircraftID {
                            Button("Remove", role: .destructive) { removing = plane }
                        }
                    }
                }
                Button {
                    adding = true
                } label: {
                    Label("Add another aircraft", systemImage: "plus.circle")
                }
                .disabled(!cloud.isSignedIn || cloud.isBusy)
            } header: {
                Text("Your aircraft")
            } footer: {
                Text(cloud.isSignedIn
                     ? "Each aircraft keeps its own flights, POH, maintenance and notes. Uploads go to the selected aircraft; on enginepulse.net/upload you choose the aircraft before uploading. Swipe left to remove an aircraft you no longer fly."
                     : "Sign in to add more aircraft.")
            }
            .sheet(isPresented: $adding) { NavigationStack { AddAircraftView(actions: actions) } }
            .confirmationDialog("Remove \(removing?.title ?? "this aircraft")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Remove aircraft, its flights and uploads", role: .destructive) {
                    if let plane = removing { Task { _ = await cloud.removeAircraft(plane.id) } }
                }
            } message: {
                Text("This deletes the aircraft's flights, uploads and records from your account on every device. It can't be undone. If you sold it, use Transfer to the new owner instead.")
            }
        }
        .task { await cloud.refreshFleet() }
    }
}

/// Shown above import and upload buttons: which aircraft new files go to, with a quick switch.
struct ImportTargetRow: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @State private var switching = false

    var body: some View {
        WithFleetActions { actions in
            HStack {
                Label("Adding to", systemImage: "airplane")
                Spacer()
                if cloud.fleet.count > 1 {
                    Picker("Aircraft", selection: Binding(get: { cloud.aircraftID }, set: { id in
                        Task { switching = true; await actions.switchTo(id); switching = false }
                    })) {
                        ForEach(cloud.fleet) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .disabled(cloud.isBusy || switching)
                } else {
                    Text(aircraft.profile.tailNumber.isEmpty ? "Your aircraft" : aircraft.profile.tailNumber).font(.body.monospaced())
                }
                if switching { ProgressView().controlSize(.small) }
            }
        }
    }
}
