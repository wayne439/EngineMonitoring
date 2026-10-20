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

    /// Aircraft commonly flown with Garmin glass cockpits (pick Other for anything not listed).
    static let catalog: [AircraftModelOption] = [
        .init(id: "sr20", make: "Cirrus", model: "SR20 (G1-G5)", cylinders: 6, turbo: false, monitor: .garminPerspective),
        .init(id: "sr20g6", make: "Cirrus", model: "SR20 G6", cylinders: 4, turbo: false, monitor: .garminPerspectivePlus),
        .init(id: "sr20g7", make: "Cirrus", model: "SR20 G7", cylinders: 4, turbo: false, monitor: .garminPerspectiveTouchPlus),
        .init(id: "sr22", make: "Cirrus", model: "SR22 (G1-G5)", cylinders: 6, turbo: false, monitor: .garminPerspective),
        .init(id: "sr22g6", make: "Cirrus", model: "SR22 G6", cylinders: 6, turbo: false, monitor: .garminPerspectivePlus),
        .init(id: "sr22g7", make: "Cirrus", model: "SR22 G7", cylinders: 6, turbo: false, monitor: .garminPerspectiveTouchPlus),
        .init(id: "sr22tn", make: "Cirrus", model: "SR22 Turbo (turbonormalized)", cylinders: 6, turbo: true, monitor: .garminPerspective),
        .init(id: "sr22t", make: "Cirrus", model: "SR22T (G5)", cylinders: 6, turbo: true, monitor: .garminPerspective),
        .init(id: "sr22tg6", make: "Cirrus", model: "SR22T G6", cylinders: 6, turbo: true, monitor: .garminPerspectivePlus),
        .init(id: "sr22tg7", make: "Cirrus", model: "SR22T G7", cylinders: 6, turbo: true, monitor: .garminPerspectiveTouchPlus),
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
        case .garminPerspective, .garminPerspectivePlus, .garminPerspectiveTouchPlus, .garminG1000, .garminG1000NXi:
            logs = "Insert the top SD card on the ground; the avionics save a CSV per flight in the data_log folder. Copy them to the iPad with an SD card reader. The last 20 or more flights give the best baseline."
        case .garminG3X:
            logs = "Copy the flight data logs from the G3X SD card (CSV files). The last 20 or more flights give the best baseline. G3X import is coming soon."
        default:
            logs = "Export the engine monitor logs for your last 20 or more flights. Import for this monitor is coming soon; tell us what you have."
        }
        var list: [Item] = [
            Item(id: "tail", title: "Tail number and aircraft serial number", detail: "From the data plate or registration.", level: .required),
            Item(id: "logs", title: "Engine monitor log files", detail: logs, level: .required),
            Item(id: "limits", title: "Your POH / AFM as a PDF", detail: "The whole handbook including Section 9 supplements. Engine model and limits (including turbo limits) are read from it automatically.", level: .required),
            Item(id: "annual", title: "Date of the last annual inspection", detail: "From the airframe logbook.", level: .required),
            Item(id: "oil", title: "Last oil change: date and tach or total time", detail: "From the engine logbook, plus your usual oil change interval.", level: .required),
            Item(id: "engine-time", title: "Engine total time", detail: "From the latest engine logbook entry (and the overhaul entry, if it has been overhauled).", level: .recommended),
        ]
        list += [
            Item(id: "oil-analysis", title: "Recent oil analysis reports", detail: "PDF or photo of your lab reports, if you use oil analysis.", level: .optional),
            Item(id: "squawks", title: "Open squawks and recent engine work", detail: "Anything your A&P is watching, and work done since the last annual (cylinders, injectors, magnetos).", level: .optional),
        ]
        return list
    }
}

// MARK: - Getting data off the airplane

/// Wireless or cellular links that can carry engine data off the aircraft.
enum DataLink: String, Codable, CaseIterable, Identifiable, Sendable {
    case gdl60 = "Garmin GDL 60 datalink (PlaneSync)"
    case flightStream510 = "Garmin Flight Stream 510"
    case flightStream210 = "Garmin Flight Stream 210"
    case cirrusIQ = "Cirrus IQ data sync (2020+ Cirrus)"
    case airSync = "AirSync box"
    case notSure = "None / not sure"

    var id: String { rawValue }
}

/// The best way for this aircraft's engine data to reach the app, with honest notes on what works today.
struct DataPathAdvice: Equatable, Sendable {
    let title: String
    let automatic: Bool
    let steps: [String]
    /// Shows the "Get your flights from Garmin" guide link (Garmin Pilot and flyGarmin steps).
    var showsGarminGuide = false

    static let garminPilotShare = "After landing, in Garmin Pilot: More > Logbook > Entries, open the flight, tap Share, choose CSV, then Engine Pulse."
    static let flyGarminDownload = "Or on a computer: flyGarmin.com > Logbook, open the flight, Download > Original CSV, and drop it on enginepulse.net/upload."
    static let flyGarminComing = "Planned: fully automatic through Garmin's flyGarmin sharing program, once Garmin approves Engine Pulse. You would switch on sharing in flyGarmin once and every flight would arrive by itself."

    static let sdCardSteps = [
        "After the flight, take the data card out of the avionics (on the ground, per your POH/avionics guide).",
        "Plug it into the iPad with a USB-C SD card reader.",
        "In the app: DIAGNOSTICS > Flight Logs > Import new flights from SD card. The first time, choose the data_log folder; after that it is one tap and only new flights are added.",
    ]

    static func advise(monitor: EngineMonitorType, link: DataLink?, make: String) -> DataPathAdvice {
        let isCirrus = make.lowercased().contains("cirrus")
        if monitor == .jpiEDM || monitor == .eiMVP {
            return DataPathAdvice(
                title: "Export from your engine monitor",
                automatic: false,
                steps: [
                    monitor == .jpiEDM
                        ? "Download the flights from the EDM to a USB stick or with JPI's download cable/app (older EDMs use a serial cable)."
                        : "Export the flight data from the EI monitor to a USB stick.",
                    "Send the file to the iPad (AirDrop, Files, email) and choose Open in Engine Pulse.",
                    "Full analysis for this monitor is coming. While signed in, your files are saved to your account now and processed when it arrives.",
                ])
        }
        switch link ?? .notSure {
        case .gdl60:
            return DataPathAdvice(
                title: "GDL 60: your flights upload to flyGarmin after every shutdown",
                automatic: true,
                steps: [
                    "The GDL 60 uploads each flight's engine log to flyGarmin over LTE or Wi-Fi once you shut down (PlaneSync subscription).",
                    "Today: on flyGarmin.com > Logbook, open the flight, Download > Original CSV, and drop it on enginepulse.net/upload (or share the file to Engine Pulse on the iPad). It appears in the app with the full analysis.",
                    flyGarminComing,
                ],
                showsGarminGuide: true)
        case .flightStream510 where monitor.flightStream510CarriesEngineData || monitor.isPerspectivePlusFamily:
            var steps = [
                "Keep Garmin Pilot open on the iPad for the whole flight, connected to the Flight Stream 510. It receives the engine log over Bluetooth.",
                garminPilotShare,
                flyGarminDownload,
                flyGarminComing,
            ]
            if monitor.isPerspectivePlusFamily {
                steps.insert("Garmin doesn't list \(monitor == .garminPerspectiveTouchPlus ? "Perspective Touch+" : "Perspective+") engine logs over Flight Stream 510. If the Garmin Pilot logbook entry has no engine data, use the data card: " + sdCardSteps[2], at: 3)
            }
            return DataPathAdvice(
                title: "Flight Stream 510: from Garmin Pilot to Engine Pulse",
                automatic: true,
                steps: steps,
                showsGarminGuide: true)
        case .flightStream510:
            return DataPathAdvice(
                title: "Use the data card (Flight Stream 510 does not carry engine data on this avionics)",
                automatic: false,
                steps: ["Garmin lists Flight Stream 510 engine-log transfer for the G1000 NXi, TXi and GI 275 EIS. On other avionics it carries databases, weather and traffic, not engine logs."] + sdCardSteps)
        case .flightStream210:
            return DataPathAdvice(
                title: "Use the data card (Flight Stream 210 does not transfer engine data)",
                automatic: false,
                steps: ["The Flight Stream 210 streams weather, traffic, GPS and attitude to your iPad, not engine logs."]
                    + sdCardSteps
                    + ["Hands-free options: an AirSync box, or a Flight Stream 510 if you have a G1000 NXi or TXi."])
        case .cirrusIQ:
            return DataPathAdvice(
                title: "Share from the Cirrus IQ app",
                automatic: false,
                steps: [
                    "Cirrus IQ syncs your flights from the airplane (2020 and later G6 / G7).",
                    "In Cirrus IQ, open a flight, tap Share and choose Engine Pulse.",
                    "Or use the data card: " + sdCardSteps[2],
                ])
        case .airSync:
            return DataPathAdvice(
                title: "Automatic with AirSync",
                automatic: true,
                steps: [
                    "AirSync uploads your flights over LTE after shutdown.",
                    "We are working with AirSync to add Engine Pulse as an upload destination. Until then, use the data card: " + sdCardSteps[2],
                ])
        case .notSure:
            return DataPathAdvice(
                title: "Use the data card (about 2 minutes after each flight)",
                automatic: false,
                steps: sdCardSteps + [isCirrus
                    ? "Hands-free options: Cirrus IQ data sync on 2020+ Cirrus, or an AirSync box."
                    : "Hands-free option: an AirSync box, or a Garmin GDL 60 / Flight Stream 510 where your avionics support it."])
        }
    }
}

// MARK: - Documents to upload

/// One document a pilot uploads, each with its own upload slot (the same list and categories as the upload
/// website, so a file always lands in the right place).
struct DocumentRequirement: Identifiable, Hashable, Sendable {
    let id: String          // inbox_uploads.category
    let title: String
    let detail: String
    let level: DataChecklist.Level
    /// File types the picker offers for this item.
    let acceptsLogs: Bool

    /// What to upload, with nothing asked twice: the POH covers the engine model, the limits and
    /// (in Section 9) the turbo supplement; a separate turbo item appears only when the POH read on
    /// this iPad doesn't cover the turbo limits.
    static func list(turbo: Bool, turboSupplementMissing: Bool = false) -> [DocumentRequirement] {
        var items: [DocumentRequirement] = [
            .init(id: "logs", title: "Engine monitor log files",
                  detail: "The CSV files from your avionics data card (data_log folder). The last 20 or more flights give the best baseline.",
                  level: .required, acceptsLogs: true),
            .init(id: "poh-limits", title: "Your POH / AFM (the whole PDF)",
                  detail: "Including the Section 9 supplements. The engine model, all engine limits and any turbo limits are read from it, so nothing else about limits is needed.",
                  level: .required, acceptsLogs: false),
            .init(id: "logbook", title: "Last annual and last oil change",
                  detail: "Logbook entries (date and tach / total time), or record them under MAINTENANCE instead. Add your AD compliance record if you have one.",
                  level: .required, acceptsLogs: false),
            .init(id: "engine-time", title: "Engine total time",
                  detail: "The latest engine logbook entry showing total time. If the engine has been overhauled, include the overhaul entry.",
                  level: .recommended, acceptsLogs: false),
        ]
        if turbo && turboSupplementMissing {
            items.append(.init(id: "turbo", title: "Turbo supplement (not found in your POH)",
                               detail: "Your POH doesn't include the turbo or turbonormalizer limits. Upload the AFM supplement that has the TIT and manifold-pressure limits.",
                               level: .recommended, acceptsLogs: false))
        }
        items += [
            .init(id: "oil-analysis", title: "Oil analysis reports", detail: "Your lab reports, if you use oil analysis.",
                  level: .optional, acceptsLogs: false),
            .init(id: "squawks", title: "Open squawks and recent engine work",
                  detail: "Anything your A&P is watching, or work since the last annual.", level: .optional, acceptsLogs: false),
            .init(id: "other", title: "Anything else", detail: "Other records you want kept with the aircraft.",
                  level: .optional, acceptsLogs: false),
        ]
        return items
    }
}
