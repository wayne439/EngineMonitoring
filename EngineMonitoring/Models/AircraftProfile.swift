import Foundation
import CryptoKit

/// Engine monitors and glass panels with engine data that the app knows about. Raw values are saved in
/// profiles, so existing ones never change; new ones are only added.
enum EngineMonitorType: String, Codable, CaseIterable, Identifiable, Sendable {
    case garminPerspective = "Cirrus Perspective (Garmin)"
    // Raw value kept from 0.2 so saved profiles still decode; shown as "Perspective+ (G6)".
    case garminPerspectivePlus = "Cirrus Perspective+ (G6 / G7)"
    case garminPerspectiveTouchPlus = "Cirrus Perspective Touch+ (G7)"
    // Raw value kept from 0.2 so saved profiles still decode.
    case garminG1000 = "Garmin G1000 / G1000 NXi"
    case garminG1000NXi = "Garmin G1000 NXi"
    case garminG3000 = "Garmin G3000"
    case garminTXi = "Garmin G500 / G600 TXi"
    case garminGI275 = "Garmin GI 275 EIS"
    case garminG3X = "Garmin G3X Touch"
    case avidyne = "Avidyne Entegra"
    case jpiEDM = "J.P. Instruments EDM"
    case eiMVP = "Electronics International MVP / CGR"
    case dynonSkyView = "Dynon SkyView / HDX"
    case grt = "GRT Avionics (EIS / Horizon)"
    case afs = "Advanced Flight Systems (AFS)"
    case mgl = "MGL Avionics"
    case insight = "Insight Graphic Engine Monitor (GEM)"
    case other = "Other"

    var id: String { rawValue }

    /// Shown in pickers; the original combined entry reads as plain G1000 (NXi has its own entry).
    var label: String {
        switch self {
        case .garminG1000: return "Garmin G1000"
        case .garminPerspectivePlus: return "Cirrus Perspective+ (G6)"
        default: return rawValue
        }
    }

    /// Cirrus Perspective+ and Perspective Touch+ (G6 and G7): same Garmin data logs and data links.
    var isPerspectivePlusFamily: Bool { self == .garminPerspectivePlus || self == .garminPerspectiveTouchPlus }

    /// Garmin glass whose engine data is logged in Garmin's CSV layout.
    var isGarmin: Bool {
        switch self {
        case .garminPerspective, .garminPerspectivePlus, .garminPerspectiveTouchPlus, .garminG1000, .garminG1000NXi,
             .garminG3000, .garminTXi, .garminGI275, .garminG3X: return true
        default: return false
        }
    }

    enum Support: String, Sendable {
        /// Imported and checked against real logs.
        case full
        /// Imported; checked against samples, tell us if a file doesn't read.
        case beta
        /// Files are saved to the account for when support arrives.
        case planned
    }

    var support: Support {
        switch self {
        case .garminPerspective, .garminPerspectivePlus, .garminPerspectiveTouchPlus, .garminG1000, .garminG1000NXi, .jpiEDM:
            return .full
        case .garminG3000, .garminTXi, .garminGI275, .garminG3X, .eiMVP, .dynonSkyView, .avidyne, .grt, .afs, .mgl, .other:
            return .beta
        case .insight:
            return .planned
        }
    }

    /// True when the importer can read this monitor's log files in this version.
    var isSupported: Bool { support != .planned }

    /// Garmin avionics whose engine data the Flight Stream 510 can carry (per Garmin: G1000 NXi, TXi and GI 275 EIS; Perspective+ and Perspective Touch+ not listed).
    var flightStream510CarriesEngineData: Bool { self == .garminG1000NXi || self == .garminTXi || self == .garminGI275 }

    /// How to get the engine logs off this monitor and into the app.
    var downloadSteps: [String] {
        switch self {
        case .garminPerspective, .garminPerspectivePlus, .garminPerspectiveTouchPlus, .garminG1000, .garminG1000NXi, .garminG3000:
            return ["On the ground, take the SD card out of the top slot of the MFD. The avionics save one CSV file per flight in its data_log folder.",
                    "Copy the files to the iPad with an SD card reader, or import the data_log folder: DIAGNOSTICS > Flight Logs > Import new flights from SD card."]
        case .garminG3X:
            return ["Keep an SD card in the G3X display's card slot. The G3X writes one CSV file per flight in the card's data_log folder.",
                    "On the ground, copy the files to the iPad with an SD card reader (DIAGNOSTICS > Flight Logs > Import new flights from SD card)."]
        case .garminTXi:
            return ["With engine indication (EIS) on the TXi, keep an SD card in the display. Engine and flight data are logged to the card as CSV files.",
                    "On the ground, copy the CSV files to the iPad with an SD card reader and import them (DIAGNOSTICS > Flight Logs)."]
        case .garminGI275:
            return ["With a GI 275 set up as the engine indicator, keep a microSD card in it. Its data logs are written to the card as CSV files.",
                    "On the ground, copy the CSV files to the iPad with a card reader and import them (DIAGNOSTICS > Flight Logs)."]
        case .jpiEDM:
            return ["Plug a USB stick into the EDM (units without USB need JPI's USB download box on the serial cable).",
                    "Hold STEP and LF for 5 seconds until PROGRAM shows, tap STEP until DUMP? appears, tap LF to choose NEW (or ALL), then tap STEP. Wait for DONE, then 10 more seconds.",
                    "Import the file (named like U241015.JPI, older units .DAT) in DIAGNOSTICS > Flight Logs, or share it to Engine Pulse. Every flight in it is added. JPI CSV exports work too."]
        case .eiMVP:
            return ["With the engine off, open the USB / Data Recording screen and download the flights to the USB data stick.",
                    "Import the CSV files (named like Flt0001_20241015F.csv) in DIAGNOSTICS > Flight Logs, or share them to Engine Pulse."]
        case .dynonSkyView:
            return ["Plug a USB stick into the SkyView display, then SETUP MENU > SYSTEM SOFTWARE > EXPORT USER DATA LOGS.",
                    "Import the file ending USER-LOG-DATA.csv in DIAGNOSTICS > Flight Logs, or share it to Engine Pulse."]
        case .avidyne:
            return ["Entegra Release 9: with the MFD on, insert an empty FAT32 USB stick (1 to 8 GB), go to SYS > Get Logs and choose Since Last Export or Full. Wait for Completed OK.",
                    "Import C_ENGINE.CSV in DIAGNOSTICS > Flight Logs. Older Entegra / EX5000 units write to a FAT16 stick of 2 GB or less: send us a file so we can add it."]
        case .grt, .afs, .mgl:
            return ["Export the engine / flight data log from the EFIS to a USB stick as a CSV file (see the EFIS manual, data logging section).",
                    "Import the CSV in DIAGNOSTICS > Flight Logs. Engine columns are recognised by name; if a file doesn't read, email it to sales@enginepulse.net."]
        case .insight:
            return ["Insight GEM data is downloaded with Insight's own software. Send us a downloaded file at sales@enginepulse.net and we'll add it."]
        case .other:
            return ["Export your engine monitor's flight data log as a CSV file (a USB stick or SD card, or the maker's app).",
                    "Import it in DIAGNOSTICS > Flight Logs. Engine columns (CHT, EGT, RPM, oil, fuel flow) are recognised by name; if a file doesn't read, email it to sales@enginepulse.net."]
        }
    }
}

/// Normal-procedure speeds from the POH (KIAS) that takeoffs and landings are compared with.
struct TechniqueSpeeds: Codable, Equatable, Sendable {
    /// Final approach, flaps full (POH range, e.g. 80-85).
    var approachLow: Double
    var approachHigh: Double
    /// Short-field / threshold speed.
    var vref: Double
    var rotate: Double
    /// Best rate of climb.
    var vy: Double
    /// Normal (cruise) climb range.
    var climbLow: Double
    var climbHigh: Double

    static let sr22 = TechniqueSpeeds(approachLow: 80, approachHigh: 85, vref: 77, rotate: 70, vy: 101, climbLow: 110, climbHigh: 120)

    var isSensible: Bool {
        [approachLow, approachHigh, vref, rotate, vy, climbLow, climbHigh].allSatisfy { $0 >= 30 && $0 <= 250 }
            && approachLow <= approachHigh && climbLow <= climbHigh
    }
}

/// Engine limits and pilot references for one aircraft. Values come from the owner's POH/AFM;
/// the app never treats a template as approved data until the owner confirms it.
struct EngineLimitSettings: Codable, Equatable, Sendable {
    var rpmMax: Double
    var rpmOverspeed: Double
    var oilTempMax: Double
    var oilPressureMax: Double
    var oilPressureMin: Double
    var oilPressureCautionBelow: Double
    var chtWarning: Double
    var chtCaution: Double
    var busVoltsLow: Double
    var busVoltsHigh: Double
    /// Technique references (not limits). nil = not used.
    var climbCHTReference: Double?
    var climbTITReference: Double?
    /// Owner's cruise TIT target (turbo aircraft only). Not an approved limit.
    var cruiseTITTarget: Double?
    /// Where the owner took the limits from, e.g. "POH Section 2".
    var limitsSource: String
    /// Turbo limits (from the POH or the turbo / turbonormalizer supplement). nil = not known.
    var titMax: Double? = nil
    var mapMax: Double? = nil
}

/// One limit compared between the POH and an AFM supplement. Where they differ the supplement governs.
struct LimitCrossCheck: Codable, Hashable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let label: String
    let unit: String
    let poh: Double?
    let pohPage: String?
    let supplement: Double?
    let supplementPage: String?

    enum Status: String { case match = "Match", supplementGoverns = "Supplement governs", pohOnly = "POH only", supplementOnly = "Supplement only" }

    var status: Status {
        switch (poh, supplement) {
        case let (p?, s?): return p == s ? .match : .supplementGoverns
        case (_?, nil): return .pohOnly
        default: return .supplementOnly
        }
    }
}

/// One aircraft as the owner describes it. Drives which checks run and what they compare against.
struct AircraftProfile: Codable, Equatable, Sendable {
    var tailNumber: String
    var make: String
    var model: String
    /// 0 = not entered.
    var year: Int
    var serialNumber: String
    var engineModel: String
    var cylinders: Int
    var isTurbocharged: Bool
    var titProbes: Int
    var monitor: EngineMonitorType
    var propeller: String
    var homeAirport: String
    var hasFIKI: Bool
    var oilChangeIntervalHours: Double
    var limits: EngineLimitSettings
    /// True once the owner has checked every limit against their own POH/AFM.
    var limitsConfirmedByOwner: Bool
    var updatedAt: Date
    /// How engine data can leave the airplane (nil = not answered yet).
    var dataLink: DataLink? = nil
    /// When the required details were locked (nil = still editable). Changes after that go through support.
    var lockedAt: Date? = nil
    /// Where each value read from the POH came from, e.g. ["rpmMax": "POH 2-6"].
    var pohSources: [String: String]? = nil
    /// The POH file the values were read from, so a new POH revision updates them once.
    var pohAppliedFrom: String? = nil
    /// The POH and supplements last read (file names), so new documents update the values once.
    var documentsAppliedFrom: String? = nil
    /// POH vs supplement comparison from the last read.
    var limitCrossChecks: [LimitCrossCheck]? = nil
    /// Approach and climb speeds (POH Section 4) for MY FLYING. nil: SR22 POH values for SR22s, otherwise not graded.
    var techniqueSpeeds: TechniqueSpeeds? = nil

    /// The speeds MY FLYING grades against, and where they come from.
    var effectiveTechniqueSpeeds: (speeds: TechniqueSpeeds, source: String)? {
        if let techniqueSpeeds { return (techniqueSpeeds, "your POH speeds (AIRCRAFT > Technique speeds)") }
        if model.uppercased().contains("SR22") { return (.sr22, "SR22 POH 4-3") }
        return nil
    }

    var isLocked: Bool { lockedAt != nil }

    /// Required details still missing before the profile can be locked.
    var missingRequired: [String] {
        var out: [String] = []
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
        if blank(tailNumber) { out.append("Tail number") }
        if blank(make) { out.append("Make") }
        if blank(model) { out.append("Model") }
        if blank(serialNumber) { out.append("Serial number") }
        if blank(engineModel) { out.append("Engine model") }
        if limits.rpmMax <= 0 { out.append("Max RPM") }
        if limits.oilTempMax <= 0 { out.append("Oil temperature max") }
        if limits.oilPressureMax <= 0 { out.append("Oil pressure max") }
        if limits.chtWarning <= 0 { out.append("CHT max") }
        return out
    }

    /// Fills the limits and engine details found in the POH and supplements. Each value's page already
    /// names its document ("POH 2-6", "Supplement 4"). Values found replace typed ones (the documents are
    /// the authority); values not found keep what is there. Returns how many were filled.
    @discardableResult
    mutating func apply(_ found: POHLimitExtractor.Found, summary: String) -> Int {
        var sources = pohSources ?? [:]
        var count = 0
        func set(_ key: String, _ v: POHLimitExtractor.Value?, _ assign: (Double) -> Void) {
            guard let v else { return }
            assign(v.number)
            sources[key] = v.page
            count += 1
        }
        if let e = found.engineModel {
            engineModel = e.text
            sources["engineModel"] = e.page
            count += 1
            if let c = found.cylinders { cylinders = c }
            if let t = found.turbocharged, t { isTurbocharged = true }
        }
        set("rpmMax", found.rpmMax) { limits.rpmMax = $0 }
        set("rpmOverspeed", found.rpmOverspeed) { limits.rpmOverspeed = $0 }
        if found.rpmOverspeed == nil, let m = found.rpmMax, limits.rpmOverspeed < m.number { limits.rpmOverspeed = m.number + 30 }
        set("oilTempMax", found.oilTempMax) { limits.oilTempMax = $0 }
        set("oilPressureMin", found.oilPressureMin) { limits.oilPressureMin = $0 }
        set("oilPressureMax", found.oilPressureMax) { limits.oilPressureMax = $0 }
        set("oilPressureCautionBelow", found.oilPressureCautionBelow) { limits.oilPressureCautionBelow = $0 }
        set("chtWarning", found.chtWarning) { limits.chtWarning = $0 }
        set("chtCaution", found.chtCaution) { limits.chtCaution = $0 }
        if found.chtCaution == nil, let w = found.chtWarning, limits.chtCaution >= w.number { limits.chtCaution = w.number - 40 }
        set("titMax", found.titMax) { limits.titMax = $0 }
        set("mapMax", found.mapMax) { limits.mapMax = $0 }
        if count > 0 { limits.limitsSource = summary }
        pohSources = sources
        return count
    }

    var displayName: String {
        let name = [year > 0 ? String(year) : "", make, model].filter { !$0.isEmpty }.joined(separator: " ")
        let tail = tailNumber.trimmingCharacters(in: .whitespaces)
        if tail.isEmpty { return name.isEmpty ? "Your aircraft" : name }
        return name.isEmpty ? tail : "\(tail) - \(name)"
    }

    var isCirrus: Bool { make.lowercased().contains("cirrus") }

    /// Starting point for a turbonormalized Cirrus SR22 (the aircraft the app was first built for).
    /// Values are the basic SR22 POH Section 2 numbers; the owner must confirm them for their own aircraft.
    static let sr22TurboTemplate = AircraftProfile(
        tailNumber: "",
        make: "Cirrus",
        model: "SR22 Turbo",
        year: 0,
        serialNumber: "",
        engineModel: "Continental IO-550-N (turbonormalized)",
        cylinders: 6,
        isTurbocharged: true,
        titProbes: 2,
        monitor: .garminPerspective,
        propeller: "",
        homeAirport: "",
        hasFIKI: false,
        oilChangeIntervalHours: 25,
        limits: EngineLimitSettings(
            rpmMax: 2710, rpmOverspeed: 2730,
            oilTempMax: 240, oilPressureMax: 100, oilPressureMin: 10, oilPressureCautionBelow: 30,
            chtWarning: 460, chtCaution: 420,
            busVoltsLow: 24.5, busVoltsHigh: 32,
            climbCHTReference: 370, climbTITReference: 1325, cruiseTITTarget: 1575,
            limitsSource: "SR22 POH Section 2"),
        limitsConfirmedByOwner: false,
        updatedAt: Date(timeIntervalSince1970: 0))

    // MARK: - Limits the post-flight checks use

    private static func n(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// The limit list checked after every flight, built from this profile.
    func engineLimits() -> [AircraftKnowledge.EngineLimit] {
        typealias L = AircraftKnowledge.EngineLimit
        let s = limits
        let n = Self.n
        let src = limitsConfirmedByOwner ? s.limitsSource : "\(s.limitsSource) (template - confirm in Aircraft Profile)"
        var out: [L] = [
            L(id: "rpm-max", metric: .rpm, label: "Engine speed above \(n(s.rpmMax)) RPM for more than 10 s", low: nil, high: s.rpmMax, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src, minDuration: 11),
            L(id: "rpm-overspeed", metric: .rpm, label: "Engine speed above \(n(s.rpmOverspeed)) RPM for more than 5 s", low: nil, high: s.rpmOverspeed, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src, minDuration: 6),
            L(id: "oilt-max", metric: .oilTemp, label: "Oil temperature above \(n(s.oilTempMax)) °F", low: nil, high: s.oilTempMax, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src),
            L(id: "oilp-max", metric: .oilPressure, label: "Oil pressure above \(n(s.oilPressureMax)) psi", low: nil, high: s.oilPressureMax, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src),
            L(id: "oilp-min", metric: .oilPressure, label: "Oil pressure below \(n(s.oilPressureMin)) psi", low: s.oilPressureMin, high: nil, kind: .warning,
              minRPM: 1000, phases: [], authority: .approved, source: src, minDuration: 2, startGrace: 30),
            L(id: "oilp-caution", metric: .oilPressure,
              label: "Oil pressure \(n(s.oilPressureMin))-\(n(s.oilPressureCautionBelow - 1)) psi above 1,000 RPM in flight",
              low: s.oilPressureCautionBelow, high: nil, kind: .caution,
              minRPM: 1000, phases: [.climb, .cruise, .descent], authority: .approved, source: src, minDuration: 2, startGrace: 30),
            L(id: "oilp-idle", metric: .oilPressure,
              label: "Oil pressure \(n(s.oilPressureMin))-\(n(s.oilPressureCautionBelow - 1)) psi above 1,000 RPM on the ground",
              low: s.oilPressureCautionBelow, high: nil, kind: .caution,
              minRPM: 1000, phases: [.ground], authority: .approved, source: src, minDuration: 5, startGrace: 30),
            L(id: "cht-warning", metric: .chtMax, label: "CHT above \(n(s.chtWarning)) °F", low: nil, high: s.chtWarning, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src),
            L(id: "cht-caution", metric: .chtMax, label: "CHT above \(n(s.chtCaution)) °F", low: nil, high: s.chtCaution, kind: .caution,
              minRPM: nil, phases: [], authority: .approved, source: src),
            // Bus voltage checked in flight only (alternators are off for the start), for 10 s or more.
            L(id: "volt1-low", metric: .volt1, label: "Bus 1 voltage below \(n(s.busVoltsLow)) V in flight", low: s.busVoltsLow, high: nil, kind: .caution,
              minRPM: 1500, phases: [.climb, .cruise, .descent], authority: .approved, source: src, minDuration: 10),
            L(id: "volt2-low", metric: .volt2, label: "Bus 2 voltage below \(n(s.busVoltsLow)) V in flight", low: s.busVoltsLow, high: nil, kind: .caution,
              minRPM: 1500, phases: [.climb, .cruise, .descent], authority: .approved, source: src, minDuration: 10),
            L(id: "volt1-high", metric: .volt1, label: "Bus 1 voltage above \(n(s.busVoltsHigh)) V", low: nil, high: s.busVoltsHigh, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src, minDuration: 3),
            L(id: "volt2-high", metric: .volt2, label: "Bus 2 voltage above \(n(s.busVoltsHigh)) V", low: nil, high: s.busVoltsHigh, kind: .warning,
              minRPM: nil, phases: [], authority: .approved, source: src, minDuration: 3),
        ]
        if isTurbocharged, let t = s.titMax {
            out.append(L(id: "tit-max", metric: .tit, label: "TIT above \(n(t)) °F", low: nil, high: t, kind: .warning,
                         minRPM: nil, phases: [], authority: .approved, source: src, minDuration: 3))
        }
        if let m = s.mapMax {
            out.append(L(id: "map-max", metric: .manifoldPressure, label: "Manifold pressure above \(n(m)) inHg", low: nil, high: m, kind: .warning,
                         minRPM: nil, phases: [], authority: .approved, source: src, minDuration: 5))
        }
        // Technique references: notes, never limits.
        if let c = s.climbCHTReference {
            out.append(L(id: "barker-cht", metric: .chtMax, label: "CHT above \(n(c)) °F in climb (technique: add airspeed or boost pump)", low: nil, high: c,
                         kind: .reference, minRPM: 2000, phases: [.climb], authority: .experience, source: "Climb technique reference (owner setting)"))
        }
        if isTurbocharged, let t = s.climbTITReference {
            out.append(L(id: "barker-tit", metric: .tit, label: "Hotter TIT above \(n(t)) °F in climb (technique: enrich or add airspeed)", low: nil, high: t,
                         kind: .reference, minRPM: 2000, phases: [.climb], authority: .experience, source: "Climb technique reference (owner setting)"))
        }
        return out
    }
}

/// Reads and writes the profile file. Plain (non-actor) so the shared snapshot can load it at startup.
enum AircraftProfileFile {
    static var url: URL {
        EventPersistence.defaultDirectory().appendingPathComponent("aircraft-profile.json")
    }

    static func load() -> AircraftProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? EventPersistence.decoder.decode(AircraftProfile.self, from: data)
    }

    static func save(_ profile: AircraftProfile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try EventPersistence.encoder.encode(profile).write(to: url, options: [.atomic])
    }
}

/// Thread-safe copy of the current profile, for analysis code that runs off the main actor.
final class AircraftProfileSnapshot: @unchecked Sendable {
    static let shared = AircraftProfileSnapshot()

    private let lock = NSLock()
    private var current: AircraftProfile

    private init() {
        current = AircraftProfileFile.load() ?? AircraftProfile.sr22TurboTemplate
    }

    var profile: AircraftProfile {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func update(_ profile: AircraftProfile) {
        lock.lock()
        current = profile
        lock.unlock()
    }
}

/// The aircraft profile for the UI. Every change is saved and copied to the shared snapshot.
@MainActor
final class AircraftProfileStore: ObservableObject {
    @Published var profile: AircraftProfile {
        didSet {
            guard profile != oldValue else { return }
            AircraftProfileSnapshot.shared.update(profile)
            try? AircraftProfileFile.save(profile)
        }
    }

    init() {
        profile = AircraftProfileSnapshot.shared.profile
    }

    /// True until the required details are filled in and locked.
    var needsSetup: Bool { !profile.isLocked }

    /// Reads the engine model and limits from the POH and any AFM supplements (e.g. a turbonormalizer
    /// supplement), cross-checks them, and locks the profile once nothing required is missing.
    /// Where the POH and a supplement differ, the supplement governs.
    func applyDocuments(poh: POHIndex?, manuals: [POHIndex]) {
        let signature = ([poh?.document.filename].compactMap { $0 } + manuals.map(\.document.filename).sorted()).joined(separator: ",")
        guard !signature.isEmpty, profile.documentsAppliedFrom != signature else { return }
        let pohFound = poh.map { POHLimitExtractor.extract(from: $0).labelled("POH") } ?? POHLimitExtractor.Found()
        // Supplements uploaded on their own override the POH where they differ. Supplements bound into the
        // POH's Section 9 can cover many options, so they only fill the turbo limits the POH lacks.
        let supplements = manuals.filter(POHLimitExtractor.isSupplement)
        var suppFound = POHLimitExtractor.Found()
        for m in supplements {
            suppFound = suppFound.filling(from: POHLimitExtractor.extract(from: m).labelled("Supplement"))
        }
        if let s9 = poh.flatMap(POHLimitExtractor.section9) {
            let sec9 = POHLimitExtractor.extract(from: s9).labelled("POH")
            if suppFound.titMax == nil { suppFound.titMax = sec9.titMax }
            if suppFound.mapMax == nil { suppFound.mapMax = sec9.mapMax }
        }
        let merged = pohFound.overridden(by: suppFound)
        var p = profile
        var docs = poh.map { "POH (\($0.document.partNumber), \($0.document.revision))" } ?? ""
        if let first = supplements.first {
            docs += (docs.isEmpty ? "" : " + ") + "supplement (\(first.document.title))"
        }
        let filled = p.apply(merged, summary: "Your " + docs)
        p.limitCrossChecks = supplements.isEmpty ? nil : POHLimitExtractor.crossCheck(poh: pohFound, supplement: suppFound)
        p.documentsAppliedFrom = signature
        p.pohAppliedFrom = poh?.document.filename
        if filled > 0, p.missingRequired.isEmpty {
            p.limitsConfirmedByOwner = true
            if p.lockedAt == nil { p.lockedAt = Date() }
        }
        p.updatedAt = Date()
        profile = p
    }

    /// Locks the required details (owner checked them). No-op while anything required is missing.
    func lock() {
        guard profile.missingRequired.isEmpty else { return }
        profile.limitsConfirmedByOwner = true
        profile.lockedAt = Date()
        profile.updatedAt = Date()
    }

    /// The code support gives an owner to unlock their profile for a correction.
    static func unlockCode(tail: String) -> String {
        let digest = SHA256.hash(data: Data((tail.uppercased().trimmingCharacters(in: .whitespaces) + "|engine-pulse-unlock").utf8))
        return digest.prefix(3).map { String(format: "%02X", $0) }.joined()
    }

    /// Unlocks for one round of edits when the support code matches.
    func unlock(code: String) -> Bool {
        guard code.trimmingCharacters(in: .whitespaces).uppercased() == Self.unlockCode(tail: profile.tailNumber) else { return false }
        profile.lockedAt = nil
        profile.pohSources = nil
        profile.documentsAppliedFrom = nil
        profile.updatedAt = Date()
        return true
    }

    /// Stamps the edit time; call when the owner leaves the profile screen.
    func touch() {
        profile.updatedAt = Date()
    }
}
