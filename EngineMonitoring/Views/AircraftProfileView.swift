import SwiftUI

/// The owner's description of their aircraft. Every check in the app reads its limits and
/// engine layout from here. The onboarding questionnaire (next version) fills the same fields.
struct AircraftProfileView: View {
    @EnvironmentObject private var store: AircraftProfileStore
    @EnvironmentObject private var poh: POHRepository
    @State private var showUnlock = false
    @State private var unlockCode = ""
    @State private var unlockMessage: String?

    private var locked: Bool { store.profile.isLocked }

    var body: some View {
        Form {
            statusSection

            Section {
                if locked {
                    LockedRow(label: "Tail number", value: store.profile.tailNumber)
                    LockedRow(label: "Make", value: store.profile.make)
                    LockedRow(label: "Model", value: store.profile.model)
                    LockedRow(label: "Year", value: store.profile.year > 0 ? String(store.profile.year) : "Not entered")
                    LockedRow(label: "Serial number", value: store.profile.serialNumber)
                } else {
                    TextField("Tail number (e.g. N12345)", text: $store.profile.tailNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Make (e.g. Cirrus, Beechcraft, Mooney)", text: $store.profile.make)
                    TextField("Model (e.g. SR22 Turbo, A36, M20R)", text: $store.profile.model)
                    HStack {
                        Text("Year")
                        Spacer()
                        TextField("Year", value: $store.profile.year, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                    TextField("Serial number (from the data plate or registration)", text: $store.profile.serialNumber)
                }
                TextField("Home airport (e.g. KSDL)", text: $store.profile.homeAirport)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Toggle("Known ice protection (FIKI)", isOn: $store.profile.hasFIKI)
            } header: {
                Text("Aircraft")
            }

            Section {
                if locked {
                    LockedRow(label: "Engine", value: store.profile.engineModel, source: source("engineModel"))
                    LockedRow(label: "Cylinders", value: String(store.profile.cylinders))
                    LockedRow(label: "Turbocharged", value: store.profile.isTurbocharged ? "Yes" : "No")
                } else {
                    TextField("Engine model (e.g. Continental IO-550-N)", text: $store.profile.engineModel)
                    Stepper("Cylinders: \(store.profile.cylinders)", value: $store.profile.cylinders, in: 4...8, step: 2)
                    Toggle("Turbocharged or turbonormalized", isOn: $store.profile.isTurbocharged)
                }
                if store.profile.isTurbocharged {
                    Stepper("TIT probes: \(store.profile.titProbes)", value: $store.profile.titProbes, in: 1...2)
                }
                TextField("Propeller model", text: $store.profile.propeller)
                Picker("Engine monitor", selection: $store.profile.monitor) {
                    ForEach(EngineMonitorType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Wireless data link", selection: Binding(get: { store.profile.dataLink ?? .notSure },
                                                                set: { store.profile.dataLink = $0 })) {
                    ForEach(DataLink.offered) { Text($0.rawValue).tag($0) }
                }
                DataPathAdviceView(advice: DataPathAdvice.advise(monitor: store.profile.monitor, link: store.profile.dataLink,
                                                                 make: store.profile.make))
            } header: {
                Text("Engine")
            } footer: {
                switch store.profile.monitor.support {
                case .full: Text("Log files from this monitor are imported and analysed.")
                case .beta: Text("Log files from this monitor are imported (new: if a file doesn't read, email it to sales@enginepulse.net).")
                case .planned: Text("Importing this monitor's files is planned. Send us a file at sales@enginepulse.net.")
                }
            }

            Section {
                limitRow("Max RPM (10 s)", "RPM", \.rpmMax, key: "rpmMax")
                limitRow("Overspeed RPM (5 s)", "RPM", \.rpmOverspeed, key: "rpmOverspeed")
                limitRow("CHT caution above", "°F", \.chtCaution, key: "chtCaution")
                limitRow("CHT max (warning above)", "°F", \.chtWarning, key: "chtWarning")
                limitRow("Oil temperature max", "°F", \.oilTempMax, key: "oilTempMax")
                limitRow("Oil pressure min", "psi", \.oilPressureMin, key: "oilPressureMin")
                limitRow("Oil pressure caution below", "psi", \.oilPressureCautionBelow, key: "oilPressureCautionBelow")
                limitRow("Oil pressure max", "psi", \.oilPressureMax, key: "oilPressureMax")
                limitRow("Bus voltage low", "V", \.busVoltsLow, key: "busVoltsLow")
                limitRow("Bus voltage high", "V", \.busVoltsHigh, key: "busVoltsHigh")
                if store.profile.isTurbocharged {
                    optionalLimitRow("TIT max", "°F", \.titMax, key: "titMax")
                    optionalLimitRow("Manifold pressure max", "inHg", \.mapMax, key: "mapMax")
                }
                LabeledContent("Source", value: store.profile.limits.limitsSource)
            } header: {
                Text("Limits")
            } footer: {
                Text("Read from your POH Section 2 where it can be found (the page is shown under each value). Anything not found comes from the model template until you enter it. Advisory only: your POH/AFM, your engine monitor and your A&P remain the authority.")
            }

            if let checks = store.profile.limitCrossChecks, !checks.isEmpty {
                Section {
                    ForEach(checks) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.label).font(.subheadline.bold())
                                Spacer()
                                Label(c.status.rawValue, systemImage: icon(c.status))
                                    .font(.caption.bold())
                                    .foregroundStyle(tint(c.status))
                            }
                            HStack(spacing: 16) {
                                Text("POH: " + (c.poh.map { "\($0.formatted(.number)) \(c.unit)" } ?? "not stated"))
                                Text("Supplement: " + (c.supplement.map { "\($0.formatted(.number)) \(c.unit)" } ?? "not stated"))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text([c.pohPage, c.supplementPage].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("POH and Supplement Cross-Check")
                } footer: {
                    Text("Each limit read from your POH is compared with your AFM supplement. Where they differ, the supplement governs and its value is used above. Check any \"Supplement governs\" line against both printed documents.")
                }
            }

            Section {
                OptionalNumberRow(label: "Climb CHT reference", unit: "°F", value: $store.profile.limits.climbCHTReference)
                if store.profile.isTurbocharged {
                    OptionalNumberRow(label: "Climb TIT reference", unit: "°F", value: $store.profile.limits.climbTITReference)
                    OptionalNumberRow(label: "Cruise TIT target", unit: "°F", value: $store.profile.limits.cruiseTITTarget)
                }
            } header: {
                Text("Technique References (optional)")
            } footer: {
                Text("Your own targets, shown as notes after each flight and never as limits. Leave blank (0) to turn one off.")
            }

            Section {
                NumberRow(label: "Oil change every", unit: "hours", value: $store.profile.oilChangeIntervalHours)
            } header: {
                Text("Maintenance")
            }

            TechniqueSpeedsSection()
        }
        .navigationTitle("Aircraft Profile")
        .onDisappear { store.touch() }
        .task {
            store.applyDocuments(poh: poh.index, manuals: poh.manuals)
        }
        .alert("Unlock with support code", isPresented: $showUnlock) {
            TextField("6-character code", text: $unlockCode)
                .textInputAutocapitalization(.characters)
            Button("Unlock") {
                unlockMessage = store.unlock(code: unlockCode) ? "Unlocked. Make your correction, then lock again." : "That code doesn't match this aircraft."
                unlockCode = ""
            }
            Button("Cancel", role: .cancel) { unlockCode = "" }
        } message: {
            Text("Email sales@enginepulse.net with your tail number and the correction. We'll send a code that unlocks the profile once.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if locked {
                Label("Locked. Required details come from your POH and registration and can't be changed here.", systemImage: "lock.fill")
                    .foregroundStyle(.green)
                if let date = store.profile.lockedAt {
                    Text("Locked \(date.formatted(date: .abbreviated, time: .shortened)).").font(.caption).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "mailto:sales@enginepulse.net?subject=Engine%20Pulse%20profile%20change%20\(store.profile.tailNumber.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")") ?? URL(string: "mailto:sales@enginepulse.net")!) {
                    Label("Request a change", systemImage: "envelope")
                }
                Button {
                    showUnlock = true
                } label: {
                    Label("I have a support code", systemImage: "key")
                }
                NavigationLink {
                    TransferAircraftView()
                } label: {
                    Label("Sold this aircraft? Transfer it to the new owner", systemImage: "arrow.right.arrow.left")
                }
            } else {
                let missing = store.profile.missingRequired
                if poh.index == nil {
                    Label("Upload your POH (AIRCRAFT > Documents and uploads). The engine model and limits are read from it automatically.", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.orange)
                } else if poh.isBuilding {
                    Label("Reading your POH…", systemImage: "hourglass")
                }
                if missing.isEmpty {
                    Button {
                        store.lock()
                    } label: {
                        Label("Everything matches my POH: lock the profile", systemImage: "lock")
                            .font(.headline)
                    }
                } else {
                    Label("Still needed: \(missing.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            if let unlockMessage { Text(unlockMessage).font(.footnote) }
        } header: {
            Text("Status")
        } footer: {
            if !locked {
                Text("Once locked, the tail number, serial number, engine and limits can only be changed through support, so every flight is checked against the same approved numbers.")
            }
        }
    }

    private func source(_ key: String) -> String? { store.profile.pohSources?[key] }

    private func icon(_ s: LimitCrossCheck.Status) -> String {
        switch s {
        case .match: "checkmark.circle.fill"
        case .supplementGoverns: "arrow.triangle.swap"
        case .pohOnly, .supplementOnly: "doc.text"
        }
    }

    private func tint(_ s: LimitCrossCheck.Status) -> Color {
        switch s {
        case .match: .green
        case .supplementGoverns: .orange
        case .pohOnly, .supplementOnly: .secondary
        }
    }

    @ViewBuilder
    private func optionalLimitRow(_ label: String, _ unit: String, _ path: WritableKeyPath<EngineLimitSettings, Double?>, key: String) -> some View {
        let value = store.profile.limits[keyPath: path]
        if locked || source(key) != nil {
            LockedRow(label: label, value: value.map { "\($0.formatted(.number)) \(unit)" } ?? "Not in your documents",
                      source: source(key) ?? (locked ? "Locked" : nil))
        } else {
            NumberRow(label: label, unit: unit, value: Binding(
                get: { store.profile.limits[keyPath: path] ?? 0 },
                set: { store.profile.limits[keyPath: path] = $0 > 0 ? $0 : nil }))
        }
    }

    @ViewBuilder
    private func limitRow(_ label: String, _ unit: String, _ path: WritableKeyPath<EngineLimitSettings, Double>, key: String) -> some View {
        let value = store.profile.limits[keyPath: path]
        if locked || source(key) != nil {
            LockedRow(label: label, value: "\(value.formatted(.number)) \(unit)",
                      source: source(key) ?? (locked ? "Locked" : nil))
        } else {
            NumberRow(label: label, unit: unit, value: Binding(
                get: { store.profile.limits[keyPath: path] },
                set: { store.profile.limits[keyPath: path] = $0 }))
        }
    }
}

/// A value that can't be edited here, with where it came from.
private struct LockedRow: View {
    let label: String
    let value: String
    var source: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value.isEmpty ? "Not entered" : value).foregroundStyle(.secondary)
                if let source {
                    Label(source, systemImage: "lock.fill").font(.caption2).foregroundStyle(.tint)
                }
            }
        }
    }
}

/// A labeled number field with its unit.
private struct NumberRow: View {
    let label: String
    let unit: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// A number field where 0 or empty means "not used".
private struct OptionalNumberRow: View {
    let label: String
    let unit: String
    @Binding var value: Double?

    var body: some View {
        NumberRow(label: label, unit: unit, value: Binding(
            get: { value ?? 0 },
            set: { value = $0 > 0 ? $0 : nil }))
    }
}

/// Approach and climb speeds from POH Section 4, used by MY FLYING to grade takeoffs and landings.
struct TechniqueSpeedsSection: View {
    @EnvironmentObject private var store: AircraftProfileStore
    @State private var draft = TechniqueSpeeds(approachLow: 0, approachHigh: 0, vref: 0, rotate: 0, vy: 0, climbLow: 0, climbHigh: 0)
    @State private var editing = false

    var body: some View {
        Section {
            if let current = store.profile.effectiveTechniqueSpeeds, !editing {
                LabeledContent("Final approach (flaps full)", value: "\(Int(current.speeds.approachLow))-\(Int(current.speeds.approachHigh)) KIAS")
                LabeledContent("Vref / short field", value: "\(Int(current.speeds.vref)) KIAS")
                LabeledContent("Rotate", value: "\(Int(current.speeds.rotate)) KIAS")
                LabeledContent("Vy", value: "\(Int(current.speeds.vy)) KIAS")
                LabeledContent("Normal climb", value: "\(Int(current.speeds.climbLow))-\(Int(current.speeds.climbHigh)) KIAS")
                Button("Edit speeds") { draft = current.speeds; editing = true }
            } else if !editing {
                Text("Not set: MY FLYING grades sink rate, bank, float and takeoff power, but not speeds.")
                    .font(.footnote)
                Button("Enter speeds from my POH") { editing = true }
            } else {
                speedField("Final approach, low", \.approachLow)
                speedField("Final approach, high", \.approachHigh)
                speedField("Vref / short field", \.vref)
                speedField("Rotate", \.rotate)
                speedField("Vy (best rate of climb)", \.vy)
                speedField("Normal climb, low", \.climbLow)
                speedField("Normal climb, high", \.climbHigh)
                Button("Save") {
                    store.profile.techniqueSpeeds = draft
                    store.touch()
                    editing = false
                }
                .disabled(!draft.isSensible)
                Button("Cancel", role: .cancel) { editing = false }
                if store.profile.techniqueSpeeds != nil {
                    Button("Remove my speeds", role: .destructive) {
                        store.profile.techniqueSpeeds = nil
                        store.touch()
                        editing = false
                    }
                }
            }
        } header: {
            Text("Technique speeds (MY FLYING)")
        } footer: {
            Text(store.profile.techniqueSpeeds == nil && store.profile.effectiveTechniqueSpeeds != nil
                 ? "SR22 POH Section 4 values. Edit them if your POH differs. Coaching targets, not limits."
                 : "From your POH Section 4 (normal procedures), in knots indicated. Coaching targets, not limits.")
        }
    }

    private func speedField(_ label: String, _ key: WritableKeyPath<TechniqueSpeeds, Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("KIAS", value: Binding(get: { draft[keyPath: key] == 0 ? nil : draft[keyPath: key] },
                                             set: { draft[keyPath: key] = $0 ?? 0 }), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}
