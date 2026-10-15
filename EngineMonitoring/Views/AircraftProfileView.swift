import SwiftUI

/// The owner's description of their aircraft. Every check in the app reads its limits and
/// engine layout from here. The onboarding questionnaire (next version) fills the same fields.
struct AircraftProfileView: View {
    @EnvironmentObject private var store: AircraftProfileStore

    var body: some View {
        Form {
            Section {
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
                TextField("Serial number", text: $store.profile.serialNumber)
                TextField("Home airport (e.g. KSDL)", text: $store.profile.homeAirport)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Toggle("Known ice protection (FIKI)", isOn: $store.profile.hasFIKI)
            } header: {
                Text("Aircraft")
            }

            Section {
                TextField("Engine model (e.g. Continental IO-550-N)", text: $store.profile.engineModel)
                Stepper("Cylinders: \(store.profile.cylinders)", value: $store.profile.cylinders, in: 4...8, step: 2)
                Toggle("Turbocharged or turbonormalized", isOn: $store.profile.isTurbocharged)
                if store.profile.isTurbocharged {
                    Stepper("TIT probes: \(store.profile.titProbes)", value: $store.profile.titProbes, in: 1...2)
                }
                TextField("Propeller model", text: $store.profile.propeller)
                Picker("Engine monitor", selection: $store.profile.monitor) {
                    ForEach(EngineMonitorType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Wireless data link", selection: Binding(get: { store.profile.dataLink ?? .notSure },
                                                                set: { store.profile.dataLink = $0 })) {
                    ForEach(DataLink.allCases) { Text($0.rawValue).tag($0) }
                }
                DataPathAdviceView(advice: DataPathAdvice.advise(monitor: store.profile.monitor, link: store.profile.dataLink,
                                                                 make: store.profile.make))
            } header: {
                Text("Engine")
            } footer: {
                if store.profile.monitor.isSupported {
                    Text("Log files from this monitor can be imported.")
                } else {
                    Text("Importing this monitor's files is planned for a later version. Garmin Perspective and G1000 CSV logs work today.")
                }
            }

            Section {
                NumberRow(label: "Max RPM (10 s)", unit: "RPM", value: $store.profile.limits.rpmMax)
                NumberRow(label: "Overspeed RPM (5 s)", unit: "RPM", value: $store.profile.limits.rpmOverspeed)
                NumberRow(label: "CHT caution above", unit: "°F", value: $store.profile.limits.chtCaution)
                NumberRow(label: "CHT warning above", unit: "°F", value: $store.profile.limits.chtWarning)
                NumberRow(label: "Oil temperature max", unit: "°F", value: $store.profile.limits.oilTempMax)
                NumberRow(label: "Oil pressure min", unit: "psi", value: $store.profile.limits.oilPressureMin)
                NumberRow(label: "Oil pressure caution below", unit: "psi", value: $store.profile.limits.oilPressureCautionBelow)
                NumberRow(label: "Oil pressure max", unit: "psi", value: $store.profile.limits.oilPressureMax)
                NumberRow(label: "Bus voltage low", unit: "V", value: $store.profile.limits.busVoltsLow)
                NumberRow(label: "Bus voltage high", unit: "V", value: $store.profile.limits.busVoltsHigh)
                TextField("Where these came from (e.g. POH Section 2)", text: $store.profile.limits.limitsSource)
                Toggle("I checked every value against my POH/AFM", isOn: $store.profile.limitsConfirmedByOwner)
            } header: {
                Text("Limits")
            } footer: {
                Text("Enter the limits from your own POH/AFM and approved supplements. Until you confirm them, the app marks them as template values. The app is advisory only: your POH/AFM, your engine monitor and your A&P remain the authority.")
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

            Section {
                Button("Reset to the SR22 Turbo template", role: .destructive) {
                    store.profile = AircraftProfile.sr22TurboTemplate
                }
            } footer: {
                Text("Clears everything above and starts again from the template values.")
            }
        }
        .navigationTitle("Aircraft Profile")
        .onDisappear { store.touch() }
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
