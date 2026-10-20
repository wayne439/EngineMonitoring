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
    /// Twin-engine: the app analyses the left engine (engine 1) for now.
    var twin: Bool = false

    var name: String { "\(make) \(model)" }

    static let other = AircraftModelOption(id: "other", make: "", model: "", cylinders: 6, turbo: false, monitor: .other)

    /// Common piston aircraft, by make, with the avionics or engine monitor they most often have (factory
    /// glass by year where it changed, otherwise the most common retrofit monitor). The pilot picks their
    /// own avionics next, so a different panel is one tap. Pick Other for anything not listed.
    static let catalog: [AircraftModelOption] = [
        .init(id: "sr20av", make: "Cirrus", model: "SR20 (G1-G3, Avidyne Entegra)", cylinders: 6, turbo: false, monitor: .avidyne),
        .init(id: "sr20", make: "Cirrus", model: "SR20 (G3-G5, Perspective)", cylinders: 6, turbo: false, monitor: .garminPerspective),
        .init(id: "sr20g6", make: "Cirrus", model: "SR20 G6", cylinders: 4, turbo: false, monitor: .garminPerspectivePlus),
        .init(id: "sr20g7", make: "Cirrus", model: "SR20 G7", cylinders: 4, turbo: false, monitor: .garminPerspectiveTouchPlus),
        .init(id: "sr22av", make: "Cirrus", model: "SR22 (G1-G3, Avidyne Entegra)", cylinders: 6, turbo: false, monitor: .avidyne),
        .init(id: "sr22", make: "Cirrus", model: "SR22 (G3-G5, Perspective)", cylinders: 6, turbo: false, monitor: .garminPerspective),
        .init(id: "sr22g6", make: "Cirrus", model: "SR22 G6", cylinders: 6, turbo: false, monitor: .garminPerspectivePlus),
        .init(id: "sr22g7", make: "Cirrus", model: "SR22 G7", cylinders: 6, turbo: false, monitor: .garminPerspectiveTouchPlus),
        .init(id: "sr22tnav", make: "Cirrus", model: "SR22 Turbo (turbonormalized, Avidyne)", cylinders: 6, turbo: true, monitor: .avidyne),
        .init(id: "sr22tn", make: "Cirrus", model: "SR22 Turbo (turbonormalized, Perspective)", cylinders: 6, turbo: true, monitor: .garminPerspective),
        .init(id: "sr22t", make: "Cirrus", model: "SR22T (G5)", cylinders: 6, turbo: true, monitor: .garminPerspective),
        .init(id: "sr22tg6", make: "Cirrus", model: "SR22T G6", cylinders: 6, turbo: true, monitor: .garminPerspectivePlus),
        .init(id: "sr22tg7", make: "Cirrus", model: "SR22T G7", cylinders: 6, turbo: true, monitor: .garminPerspectiveTouchPlus),
        .init(id: "c150", make: "Cessna", model: "150 / 152", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "c170", make: "Cessna", model: "170", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "c172old", make: "Cessna", model: "172 Skyhawk (before 2005)", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "c172", make: "Cessna", model: "172 Skyhawk (G1000 / NXi, 2005 on)", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "c177", make: "Cessna", model: "177 / 177RG Cardinal", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "c180", make: "Cessna", model: "180 / 185 Skywagon", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "c182old", make: "Cessna", model: "182 Skylane (before 2005)", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "c182", make: "Cessna", model: "182 Skylane (G1000 / NXi, 2005 on)", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "t182old", make: "Cessna", model: "T182 / TR182 Turbo Skylane (before 2005)", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "t182", make: "Cessna", model: "T182T Turbo Skylane (G1000)", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "c206old", make: "Cessna", model: "205 / 206 Stationair (before 2005)", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "c206", make: "Cessna", model: "206 Stationair (G1000 / NXi, 2005 on)", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "t206old", make: "Cessna", model: "T206 Turbo Stationair (before 2005)", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "t206", make: "Cessna", model: "T206 Turbo Stationair (G1000 / NXi)", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "c207", make: "Cessna", model: "207 Skywagon / Stationair 7", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "c210", make: "Cessna", model: "210 Centurion", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "t210", make: "Cessna", model: "T210 / P210 Turbo Centurion", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "c350", make: "Cessna", model: "350 / Columbia 350 (Corvalis)", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "c400", make: "Cessna", model: "400 / TTx (Columbia)", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "c310", make: "Cessna", model: "310 / T310", cylinders: 6, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "c337", make: "Cessna", model: "337 Skymaster", cylinders: 6, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "c340", make: "Cessna", model: "340 / 414 / 421", cylinders: 6, turbo: true, monitor: .jpiEDM, twin: true),
        .init(id: "j3", make: "Piper", model: "J-3 Cub", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "pa18", make: "Piper", model: "PA-18 Super Cub", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "pa22", make: "Piper", model: "PA-22 Tri-Pacer / Colt", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "pa24", make: "Piper", model: "PA-24 Comanche", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "pa28", make: "Piper", model: "PA-28 Cherokee / Warrior / Archer (steam gauges)", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "pa28g", make: "Piper", model: "PA-28 Warrior / Archer (G1000 / NXi)", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "pa28r", make: "Piper", model: "PA-28R Arrow", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "pa28rt", make: "Piper", model: "PA-28RT Turbo Arrow", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "pa28d", make: "Piper", model: "PA-28-236 Dakota", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "pa32", make: "Piper", model: "PA-32 Cherokee Six / Saratoga / Lance", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "pa32t", make: "Piper", model: "PA-32 Turbo Saratoga / Turbo Lance", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "pa32g", make: "Piper", model: "Saratoga II (G1000)", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "pa46", make: "Piper", model: "PA-46 Malibu / Mirage (before G1000)", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "m350", make: "Piper", model: "M350 / Mirage / Matrix (G1000)", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "pa30", make: "Piper", model: "PA-30 / PA-39 Twin Comanche", cylinders: 4, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "pa23", make: "Piper", model: "PA-23 Aztec", cylinders: 6, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "pa34", make: "Piper", model: "PA-34 Seneca", cylinders: 6, turbo: true, monitor: .jpiEDM, twin: true),
        .init(id: "pa34g", make: "Piper", model: "Seneca V (G1000 NXi)", cylinders: 6, turbo: true, monitor: .garminG1000NXi, twin: true),
        .init(id: "pa44", make: "Piper", model: "PA-44 Seminole", cylinders: 4, turbo: false, monitor: .garminG1000, twin: true),
        .init(id: "pa31", make: "Piper", model: "PA-31 Navajo / Chieftain", cylinders: 6, turbo: true, monitor: .jpiEDM, twin: true),
        .init(id: "b19", make: "Beechcraft", model: "Musketeer / Sundowner / Sierra", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "b33", make: "Beechcraft", model: "Debonair / Bonanza 33", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "b35", make: "Beechcraft", model: "Bonanza 35 (V-tail)", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "a36old", make: "Beechcraft", model: "Bonanza A36 (steam gauges)", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "a36", make: "Beechcraft", model: "Bonanza G36 (G1000 / NXi)", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "b36tc", make: "Beechcraft", model: "Bonanza B36TC Turbo", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "b55", make: "Beechcraft", model: "Baron 55 / 58", cylinders: 6, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "g58", make: "Beechcraft", model: "Baron G58 (G1000 / NXi)", cylinders: 6, turbo: false, monitor: .garminG1000, twin: true),
        .init(id: "b76", make: "Beechcraft", model: "Duchess", cylinders: 4, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "b95", make: "Beechcraft", model: "Travel Air", cylinders: 4, turbo: false, monitor: .jpiEDM, twin: true),
        .init(id: "m20c", make: "Mooney", model: "M20C Ranger / M20E / M20F", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "m20j", make: "Mooney", model: "M20J 201", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "m20k", make: "Mooney", model: "M20K 231 / 252 / Encore", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "m20m", make: "Mooney", model: "M20M Bravo", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "m20r", make: "Mooney", model: "M20R Ovation (before G1000)", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "m20ov", make: "Mooney", model: "M20R Ovation (G1000)", cylinders: 6, turbo: false, monitor: .garminG1000),
        .init(id: "m20ac", make: "Mooney", model: "M20TN Acclaim (G1000)", cylinders: 6, turbo: true, monitor: .garminG1000),
        .init(id: "m20u", make: "Mooney", model: "M20U Ovation Ultra / M20V Acclaim Ultra (NXi)", cylinders: 6, turbo: false, monitor: .garminG1000NXi),
        .init(id: "da20", make: "Diamond", model: "DA20 Katana / Eclipse", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "da40", make: "Diamond", model: "DA40 (Lycoming, G1000)", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "da40xl", make: "Diamond", model: "DA40 XLS / XLT (G1000)", cylinders: 4, turbo: false, monitor: .garminG1000),
        .init(id: "aa1", make: "Grumman American", model: "AA-1 Yankee / Trainer / Lynx", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "aa5", make: "Grumman American", model: "AA-5 Traveler / Cheetah / Tiger", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "ac112", make: "Commander", model: "112 / 114 / 114B", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "ac114tc", make: "Commander", model: "114TC", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "tb20", make: "Socata", model: "TB-9 / TB-10 / TB-20 Tobago / Trinidad", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "tb21", make: "Socata", model: "TB-21 Trinidad TC", cylinders: 6, turbo: true, monitor: .jpiEDM),
        .init(id: "lake", make: "Lake", model: "LA-4 / Renegade", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "maule", make: "Maule", model: "M-5 / M-6 / M-7 / M-9", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "husky", make: "Aviat", model: "Husky", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "acs", make: "American Champion", model: "Citabria / Decathlon / Scout", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "navion", make: "Navion", model: "Navion", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "bellanca", make: "Bellanca", model: "Viking / Super Viking", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "ercoupe", make: "Ercoupe", model: "415 / Aircoupe", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "luscombe", make: "Luscombe", model: "8 Silvaire", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "stinson", make: "Stinson", model: "108 Voyager / Station Wagon", cylinders: 6, turbo: false, monitor: .jpiEDM),
        .init(id: "champ", make: "Aeronca", model: "Champ / Chief", cylinders: 4, turbo: false, monitor: .jpiEDM),
        .init(id: "extra", make: "Extra", model: "300 / 330 / NG", cylinders: 6, turbo: false, monitor: .garminG3X),
        .init(id: "p2010", make: "Tecnam", model: "P2010 (G1000 NXi)", cylinders: 4, turbo: false, monitor: .garminG1000NXi),
        .init(id: "p2008", make: "Tecnam", model: "P2008 / P92 (Rotax)", cylinders: 4, turbo: false, monitor: .garminG3X),
        .init(id: "rv", make: "Van's", model: "RV-6 / RV-7 / RV-8 / RV-9", cylinders: 4, turbo: false, monitor: .garminG3X),
        .init(id: "rv10", make: "Van's", model: "RV-10", cylinders: 6, turbo: false, monitor: .garminG3X),
        .init(id: "rv14", make: "Van's", model: "RV-14", cylinders: 4, turbo: false, monitor: .garminG3X),
        .init(id: "rv12", make: "Van's", model: "RV-12 (Rotax)", cylinders: 4, turbo: false, monitor: .dynonSkyView),
        .init(id: "rv4", make: "Van's", model: "RV-3 / RV-4", cylinders: 4, turbo: false, monitor: .dynonSkyView),
        .init(id: "carboncub", make: "CubCrafters", model: "Carbon Cub / XCub / NXCub", cylinders: 4, turbo: false, monitor: .garminG3X),
        .init(id: "glasair", make: "Glasair", model: "Sportsman / Glasair III", cylinders: 6, turbo: false, monitor: .garminG3X),
        .init(id: "lancair", make: "Lancair", model: "Legacy / ES / IV", cylinders: 6, turbo: false, monitor: .garminG3X),
        .init(id: "kitfox", make: "Kitfox", model: "Kitfox (all models)", cylinders: 4, turbo: false, monitor: .dynonSkyView),
        .init(id: "zenith", make: "Zenith", model: "CH 650 / CH 701 / CH 750", cylinders: 4, turbo: false, monitor: .dynonSkyView),
        .init(id: "sonex", make: "Sonex", model: "Sonex / Waiex / Onex", cylinders: 4, turbo: false, monitor: .mgl),
        .init(id: "bearhawk", make: "Bearhawk", model: "Bearhawk / Patrol / Companion", cylinders: 4, turbo: false, monitor: .garminG3X),
        .init(id: "velocity", make: "Velocity", model: "Velocity / Long-EZ / Cozy", cylinders: 4, turbo: false, monitor: .grt),
        other,
    ]

    /// Makes in catalog order, then Other.
    static var makes: [String] {
        var seen = Set<String>()
        return catalog.compactMap { $0.make.isEmpty || !seen.insert($0.make).inserted ? nil : $0.make }
    }

    static func models(of make: String) -> [AircraftModelOption] { catalog.filter { $0.make == make } }

    /// The profile after choosing this aircraft. Limits stay unconfirmed so the owner enters them from the POH.
    func applied(to profile: AircraftProfile, tailNumber: String) -> AircraftProfile {
        var p = profile
        p.tailNumber = tailNumber.uppercased().trimmingCharacters(in: .whitespaces)
        if id != Self.other.id {
            p.make = make
            p.model = model
            p.cylinders = cylinders
            p.isTurbocharged = turbo
            p.titProbes = id.hasPrefix("sr22tn") ? 2 : 1
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
        let logs = monitor.downloadSteps.joined(separator: " ") + " The last 20 or more flights give the best baseline."
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
        // Monitors that aren't Garmin glass: download from the monitor itself (data links carry Garmin data only).
        if !monitor.isGarmin {
            return DataPathAdvice(
                title: "Export from your engine monitor",
                automatic: false,
                steps: monitor.downloadSteps + (monitor.support == .beta
                    ? ["Reading this monitor's files is new: if a file doesn't import, email it to sales@enginepulse.net and we'll fix it."]
                    : []))
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
