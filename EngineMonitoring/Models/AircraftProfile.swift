import Foundation

/// Engine monitors the app knows about. Only the Garmin CSV formats are imported today.
enum EngineMonitorType: String, Codable, CaseIterable, Identifiable, Sendable {
    case garminPerspective = "Cirrus Perspective (Garmin)"
    case garminPerspectivePlus = "Cirrus Perspective+ (G6 / G7)"
    // Raw value kept from 0.2 so saved profiles still decode.
    case garminG1000 = "Garmin G1000 / G1000 NXi"
    case garminG1000NXi = "Garmin G1000 NXi"
    case garminTXi = "Garmin G500 / G600 TXi"
    case garminGI275 = "Garmin GI 275 EIS"
    case garminG3X = "Garmin G3X Touch"
    case avidyne = "Avidyne Entegra"
    case jpiEDM = "J.P. Instruments EDM"
    case eiMVP = "Electronics International MVP / CGR"
    case other = "Other"

    var id: String { rawValue }

    /// Shown in pickers; the original combined entry reads as plain G1000 (NXi has its own entry).
    var label: String { self == .garminG1000 ? "Garmin G1000" : rawValue }

    /// True when the importer can read this monitor's log files in this version (Garmin CSV data logs).
    var isSupported: Bool {
        switch self {
        case .garminPerspective, .garminPerspectivePlus, .garminG1000, .garminG1000NXi: return true
        default: return false
        }
    }

    /// Garmin avionics whose engine data the Flight Stream 510 can carry (per Garmin: G1000 NXi and TXi).
    var flightStream510CarriesEngineData: Bool { self == .garminG1000NXi || self == .garminTXi }
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

    /// True until the owner has entered a tail number and confirmed the limits.
    var needsSetup: Bool {
        profile.tailNumber.trimmingCharacters(in: .whitespaces).isEmpty || !profile.limitsConfirmedByOwner
    }

    /// Stamps the edit time; call when the owner leaves the profile screen.
    func touch() {
        profile.updatedAt = Date()
    }
}
