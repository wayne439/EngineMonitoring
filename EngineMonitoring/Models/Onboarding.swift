import Foundation

/// Aircraft offered in the registration drop-down. Choosing one fills the Aircraft Profile with the
/// basics (make, model, cylinders, turbo, usual engine monitor). The engine model and every limit are
/// left for the owner to enter from their own POH, because they vary by year and serial number.
struct AircraftModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let make: String
    let model: String
    let cylinders: Int
    let turbo: Bool
    let monitor: EngineMonitorType

    var name: String { "\(make) \(model)" }

    static let other = AircraftModelOption(id: "other", make: "", model: "", cylinders: 6, turbo: false, monitor: .other)

    /// Single-engine piston aircraft commonly flown with Garmin glass cockpits. Twins and turbines come later.
    static let catalog: [AircraftModelOption] = [
        .init(id: "sr20", make: "Cirrus", model: "SR20 (G1-G5)", cylinders: 6, turbo: false, monitor: .garminPerspective),
        .init(id: "sr20g6", make: "Cirrus", model: "SR20 G6", cylinders: 4, turbo: false, monitor: .garminPerspective),
        .init(id: "sr22", make: "Cirrus", model: "SR22", cylinders: 6, turbo: false, monitor: .garminPerspective),
        .init(id: "sr22tn", make: "Cirrus", model: "SR22 Turbo (turbonormalized)", cylinders: 6, turbo: true, monitor: .garminPerspective),
        .init(id: "sr22t", make: "Cirrus", model: "SR22T", cylinders: 6, turbo: true, monitor: .garminPerspective),
        .init(id: "c172", make: "Cessna", model: "172 Skyhawk", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "c182", make: "Cessna", model: "182 Skylane", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "t182", make: "Cessna", model: "T182 Turbo Skylane", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "c206", make: "Cessna", model: "206 Stationair", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "t206", make: "Cessna", model: "T206 Turbo Stationair", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "c400", make: "Cessna", model: "400 / TTx (Columbia)", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "a36", make: "Beechcraft", model: "Bonanza A36 / G36", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "m20ov", make: "Mooney", model: "M20 Ovation", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "m20ac", make: "Mooney", model: "M20 Acclaim", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "pa28", make: "Piper", model: "PA-28 Archer / Warrior", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "pa32", make: "Piper", model: "PA-32 Saratoga", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "m350", make: "Piper", model: "M350 / Malibu Mirage", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "da40", make: "Diamond", model: "DA40 (Lycoming)", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "rv", make: "Van's", model: "RV series", cylinders: 4, turbo: false, monitor: .garminG3X),
        other,
    ]

    /// The profile after choosing this aircraft. Limits stay unconfirmed so the owner enters them from the POH.
    func applied(to profile: AircraftProfile, tailNumber: String) -> AircraftProfile {
        var p = profile
        p.tailNumber = tailNumber.uppercased().trimmingCharacters(in: .whitespaces)
        if id != Self.other.id {
            p.make = make
            p.model = model
            p.cylinders = cylinders
            p.isTurbocharged = turbo
            p.titProbes = id == "sr22tn" ? 2 : 1
            p.monitor = monitor
            p.engineModel = ""
        }
        p.limitsConfirmedByOwner = false
        p.updatedAt = Date()
        return p
    }
}

/// What a new subscriber needs to gather so the analysis has everything it needs.
enum DataChecklist {
    enum Level: String, Sendable {
        case required = "Required"
        case recommended = "Recommended"
        case optional = "Optional"
    }

    struct Item: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let detail: String
        let level: Level
    }

    static func items(turbo: Bool, monitor: EngineMonitorType) -> [Item] {
        let logs: String
        switch monitor {
        case .garminPerspective, .garminG1000:
            logs = "Insert the top SD card on the ground; the avionics save a CSV per flight in the data_log folder. Copy them to the iPad with an SD card reader. The last 20 or more flights give the best baseline."
        case .garminG3X:
            logs = "Copy the flight data logs from the G3X SD card (CSV files). The last 20 or more flights give the best baseline. G3X import is coming soon."
        default:
            logs = "Export the engine monitor logs for your last 20 or more flights. Import for this monitor is coming soon; tell us what you have."
        }
        var list: [Item] = [
            Item(id: "tail", title: "Tail number and aircraft serial number", detail: "From the data plate or registration.", level: .required),
            Item(id: "logs", title: "Engine monitor log files", detail: logs, level: .required),
            Item(id: "limits", title: "Engine limits from your POH/AFM", detail: "Section 2 (Limitations): maximum RPM, CHT, oil temperature and oil pressure range, bus voltage.", level: .required),
            Item(id: "annual", title: "Date of the last annual inspection", detail: "From the airframe logbook.", level: .required),
            Item(id: "oil", title: "Last oil change: date and tach or total time", detail: "From the engine logbook, plus your usual oil change interval.", level: .required),
            Item(id: "engine-time", title: "Engine model, total time and time since overhaul", detail: "From the engine logbook or data plate.", level: .recommended),
        ]
        if turbo {
            list.append(Item(id: "turbo", title: "Turbo limits and supplement", detail: "TIT limit and manifold-pressure limits from your POH or turbo supplement.", level: .recommended))
        }
        list += [
            Item(id: "oil-analysis", title: "Recent oil analysis reports", detail: "PDF or photo of your lab reports, if you use oil analysis.", level: .optional),
            Item(id: "squawks", title: "Open squawks and recent engine work", detail: "Anything your A&P is watching, and work done since the last annual (cylinders, injectors, magnetos).", level: .optional),
        ]
        return list
    }
}
