import Foundation

/// Takeoff and landing quality from the engine data card (1 Hz, baro altitude).
/// Speeds are from POH 4-3 (APPROVED). The stabilized-approach gates are a common training standard (TRAINING),
/// to review with a CFII. Recorded values only; this is a coaching aid, not a grade of airmanship.
enum TechniqueStandards {
    // POH 4-3 Airspeeds for Normal Operation
    static let finalFlaps100 = 80.0...85.0      // Normal approach, flaps 100%
    static let vref = 77.0                      // Short field, flaps 100%
    static let rotate = 70.0                    // Normal takeoff rotation, flaps 50%
    static let climbNormal = 110.0...120.0      // Enroute climb, flaps up
    static let vy = 101.0                       // Best rate of climb, SL
    static let maxRPM = 2700.0                  // POH 2-6

    /// Speed over the threshold (50 ft) counted "on speed": Vref to 5 kt above the POH final speed.
    static let onSpeedAt50 = 77.0...90.0
    /// Stable at 300 ft AGL: speed, sink and bank.
    static let stableSpeed = 75.0...95.0
    static let maxSink = 1000.0
    static let maxBankLow = 15.0
    /// 500 ft AGL: speed and sink only (in a VFR pattern you may still be turning final).
    static let stableSpeed500 = 75.0...100.0
    /// More than this from 50 ft to touchdown is a long float.
    static let maxFloatSeconds = 10
    /// Initial climb 100-1,000 ft AGL: between Vy and the top of the normal climb band.
    static let initialClimb = 95.0...125.0
    static let fullPowerRPM = 2650.0

    static let source = "Speeds: POH 4-3 (APPROVED). Stable-approach gates: training standard (TRAINING) - review with your CFII."
}

/// One sample of an approach or departure profile (rounded to keep the bundled history small).
struct ProfilePoint: Codable, Hashable, Sendable {
    /// Seconds from touchdown (landing, negative before) or from brake release (takeoff).
    let t: Int
    /// Feet above the field (baro).
    let agl: Int
    let ias: Int
    /// Vertical speed, fpm.
    let vs: Int
    /// Bank, degrees (+ right).
    let roll: Int
}

struct TechniqueCheck: Hashable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let value: String
    let target: String
    /// nil = information only.
    let pass: Bool?
}

struct LandingRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(log)|\(Int(touchdown.timeIntervalSince1970))" }
    let log: String
    let touchdown: Date
    /// Field elevation (baro altitude on the rollout), ft.
    let fieldElevation: Double
    /// Same airport as the takeoff in this log (pattern work or return), if known.
    let airport: String?
    let ias500: Double?, sink500: Double?, bank500: Double?
    let ias300: Double?, sink300: Double?, bank300: Double?
    let ias50: Double?, sink50: Double?
    let iasTouchdown: Double?
    let secondsFrom50: Int?
    let oat: Double?
    let profile: [ProfilePoint]

    var onSpeedAt50: Bool? { ias50.map { TechniqueStandards.onSpeedAt50.contains($0) } }
    var stableAt300: Bool? {
        guard let s = ias300, let v = sink300, let b = bank300 else { return nil }
        return TechniqueStandards.stableSpeed.contains(s) && -v <= TechniqueStandards.maxSink && abs(b) <= TechniqueStandards.maxBankLow
    }
    var stableAt500: Bool? {
        guard let s = ias500, let v = sink500 else { return nil }
        return TechniqueStandards.stableSpeed500.contains(s) && -v <= TechniqueStandards.maxSink
    }
    var noLongFloat: Bool? { secondsFrom50.map { $0 <= TechniqueStandards.maxFloatSeconds } }

    var checks: [TechniqueCheck] {
        func kt(_ v: Double?) -> String { v.map { String(format: "%.0f KIAS", $0) } ?? "-" }
        func fpm(_ v: Double?) -> String { v.map { String(format: "%.0f fpm", -$0) } ?? "-" }
        func deg(_ v: Double?) -> String { v.map { String(format: "%.0f°", abs($0)) } ?? "-" }
        var c: [TechniqueCheck] = [
            TechniqueCheck(name: "500 ft: speed and sink", value: "\(kt(ias500)), \(fpm(sink500))", target: "75-100 KIAS, sink 1,000 fpm or less", pass: stableAt500),
            TechniqueCheck(name: "300 ft: stable", value: "\(kt(ias300)), \(fpm(sink300)), bank \(deg(bank300))", target: "75-95 KIAS, sink 1,000 or less, bank 15° or less", pass: stableAt300),
            TechniqueCheck(name: "50 ft: over the fence", value: kt(ias50), target: "80-85 KIAS (POH 4-3); 77-90 counted on speed", pass: onSpeedAt50),
            TechniqueCheck(name: "Flare: 50 ft to touchdown", value: secondsFrom50.map { "\($0) s" } ?? "-", target: "10 s or less (no long float)", pass: noLongFloat),
        ]
        c.append(TechniqueCheck(name: "Touchdown speed (approx.)", value: kt(iasTouchdown), target: "Power off, mains first (POH 4-20)", pass: nil))
        return c
    }

    /// Checks passed of the checks that could be measured.
    var score: (passed: Int, of: Int) {
        let r = [stableAt500, stableAt300, onSpeedAt50, noLongFloat].compactMap { $0 }
        return (r.filter { $0 }.count, r.count)
    }
}

struct TakeoffRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(log)|\(Int(time.timeIntervalSince1970))" }
    let log: String
    /// When the airspeed came alive (50 KIAS).
    let time: Date
    let fieldElevation: Double
    let airport: String?
    let maxRPM: Double?
    let maxMAP: Double?
    let maxFuelFlow: Double?
    /// Airspeed when about 20 ft up and climbing (approximate at 1 Hz).
    let iasLiftoff: Double?
    /// 100-1,000 ft AGL medians.
    let climbIAS: Double?
    let climbRate: Double?
    let secondsTo1000: Int?
    let oat: Double?
    let profile: [ProfilePoint]

    var fullPower: Bool? { maxRPM.map { $0 >= TechniqueStandards.fullPowerRPM && $0 <= TechniqueStandards.maxRPM + 10 } }
    var climbOnSpeed: Bool? { climbIAS.map { TechniqueStandards.initialClimb.contains($0) } }

    var checks: [TechniqueCheck] {
        [
            TechniqueCheck(name: "Takeoff power", value: [maxRPM.map { String(format: "%.0f RPM", $0) }, maxMAP.map { String(format: "%.1f in", $0) }]
                .compactMap { $0 }.joined(separator: ", "), target: "Full power, 2,650-2,710 RPM (POH 2-6 max 2,700)", pass: fullPower),
            TechniqueCheck(name: "Fuel flow at takeoff", value: maxFuelFlow.map { String(format: "%.1f gph", $0) } ?? "-",
                           target: "Per Tornado Alley supplement (not on file)", pass: nil),
            TechniqueCheck(name: "Speed passing ~20 ft", value: iasLiftoff.map { String(format: "%.0f KIAS", $0) } ?? "-",
                           target: "Rotate 70 KIAS flaps 50% (POH 4-3)", pass: nil),
            TechniqueCheck(name: "Initial climb 100-1,000 ft", value: [climbIAS.map { String(format: "%.0f KIAS", $0) }, climbRate.map { String(format: "%.0f fpm", $0) }]
                .compactMap { $0 }.joined(separator: ", "), target: "Vy 101 to 110-120 KIAS normal (POH 4-3)", pass: climbOnSpeed),
            TechniqueCheck(name: "Time to 1,000 ft above field", value: secondsTo1000.map { "\($0) s" } ?? "-", target: "Information", pass: nil),
        ]
    }

    var score: (passed: Int, of: Int) {
        let r = [fullPower, climbOnSpeed].compactMap { $0 }
        return (r.filter { $0 }.count, r.count)
    }
}

enum TechniqueAnalyzer {
    private static let groundSpeed = "GndSpd"
    private static let roll = "Roll"
    private static let lat = "Latitude"
    private static let lon = "Longitude"

    static func analyze(_ log: PerspectiveLog, departure: String?) -> (landings: [LandingRecord], takeoffs: [TakeoffRecord]) {
        let n = log.sampleCount
        guard n >= 120 else { return ([], []) }
        let ias = (0..<n).map { log.value(PerspectiveChannel.ias, at: $0) ?? 0 }
        let alt = (0..<n).map { log.value(PerspectiveChannel.altBaro, at: $0) }
        let vs = (0..<n).map { log.value("VSpd", at: $0) }
        let rpm = (0..<n).map { log.value(PerspectiveChannel.rpm, at: $0) ?? 0 }
        let rollV = (0..<n).map { log.value(roll, at: $0) }
        let oat = (0..<n).map { log.value(PerspectiveChannel.oat, at: $0) }
        func pos(_ i: Int) -> (Double, Double)? {
            guard let a = log.value(lat, at: i), let b = log.value(lon, at: i) else { return nil }
            return (a, b)
        }
        func nm(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
            let dLat = (a.0 - b.0) * 60, dLon = (a.1 - b.1) * 60 * cos(a.0 * .pi / 180)
            return (dLat * dLat + dLon * dLon).squareRoot()
        }
        func median(_ v: [Double]) -> Double? {
            guard !v.isEmpty else { return nil }
            let s = v.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }

        // Takeoffs: airspeed through 50 KIAS with takeoff power.
        var takeoffs: [TakeoffRecord] = []
        var takeoffPositions: [(Double, Double)] = []
        var i = 1
        while i < n {
            if ias[i] >= 50 && ias[i - 1] < 50 && rpm[i] > 2300, let field = alt[i] {
                let end = min(n, i + 180)
                let seg = Array(i..<end)
                guard seg.count >= 60 else { i += 1; continue }
                let lift = seg.first { k in (alt[k].map { $0 - field > 20 } ?? false) && (vs[k] ?? 0) > 200 }
                let climb = seg.filter { k in alt[k].map { $0 - field > 100 && $0 - field < 1000 } ?? false }
                let early = Array(i..<min(n, i + 20))
                let t1000 = seg.firstIndex { k in alt[k].map { $0 - field >= 1000 } ?? false }
                let start = max(0, i - 20)
                let profile = (start..<min(n, i + (t1000 ?? 120) + 5)).compactMap { k -> ProfilePoint? in
                    // Every 2 s keeps the bundled history small.
                    guard let a = alt[k], (k - i) % 2 == 0 else { return nil }
                    return ProfilePoint(t: k - i, agl: Int((a - field).rounded()), ias: Int(ias[k].rounded()),
                                        vs: Int((vs[k] ?? 0).rounded()), roll: Int((rollV[k] ?? 0).rounded()))
                }
                takeoffs.append(TakeoffRecord(
                    log: log.filename, time: log.times[i], fieldElevation: field, airport: departure,
                    maxRPM: early.map { rpm[$0] }.max(),
                    maxMAP: early.compactMap { log.value(PerspectiveChannel.manifoldPressure, at: $0) }.max(),
                    maxFuelFlow: early.compactMap { log.value(PerspectiveChannel.fuelFlow, at: $0) }.max(),
                    iasLiftoff: lift.map { ias[$0] },
                    climbIAS: median(climb.map { ias[$0] }), climbRate: median(climb.compactMap { vs[$0] }),
                    secondsTo1000: t1000, oat: oat[i], profile: profile))
                if let p = pos(i) { takeoffPositions.append(p) }
                i += 120
                continue
            }
            i += 1
        }

        // Landings: airspeed below 40 KIAS after flying (above 65 KIAS within 90 s).
        var landings: [LandingRecord] = []
        i = 1
        while i < n {
            if ias[i] < 40 && ias[i - 1] >= 40 && ias[max(0, i - 90)..<i].contains(where: { $0 > 65 }) {
                let after = (i..<min(n, i + 10)).compactMap { alt[$0] }
                guard let field = median(after) else { i += 1; continue }
                func agl(_ k: Int) -> Double? { alt[k].map { $0 - field } }
                var td: Int?
                for k in max(0, i - 120)...i { if let a = agl(k), a > 15 { td = k + 1 } }
                guard let touchdown = td, touchdown < n else { i += 1; continue }
                func gate(_ ft: Double) -> Int? {
                    (max(0, touchdown - 240)..<touchdown).last { k in agl(k).map { $0 >= ft } ?? false }
                }
                let g500 = gate(500), g300 = gate(300), g50 = gate(50)
                let first = (max(0, touchdown - 240)..<touchdown).first { k in agl(k).map { $0 <= 1000 } ?? false } ?? max(0, touchdown - 150)
                let profile = (first..<min(n, touchdown + 10)).compactMap { k -> ProfilePoint? in
                    // Every second for the last 20 s, every 2 s before that.
                    guard let a = agl(k), touchdown - k <= 20 || (touchdown - k) % 2 == 0 else { return nil }
                    return ProfilePoint(t: k - touchdown, agl: Int(max(0, a).rounded()), ias: Int(ias[k].rounded()),
                                        vs: Int((vs[k] ?? 0).rounded()), roll: Int((rollV[k] ?? 0).rounded()))
                }
                var airport: String?
                if let p = pos(touchdown), takeoffPositions.contains(where: { nm($0, p) < 3 }) { airport = departure }
                landings.append(LandingRecord(
                    log: log.filename, touchdown: log.times[touchdown], fieldElevation: field, airport: airport,
                    ias500: g500.map { ias[$0] }, sink500: g500.flatMap { vs[$0] }, bank500: g500.flatMap { rollV[$0] },
                    ias300: g300.map { ias[$0] }, sink300: g300.flatMap { vs[$0] }, bank300: g300.flatMap { rollV[$0] },
                    ias50: g50.map { ias[$0] }, sink50: g50.flatMap { vs[$0] },
                    iasTouchdown: ias[touchdown], secondsFrom50: g50.map { touchdown - $0 },
                    oat: oat[touchdown], profile: profile))
                i += 30
                continue
            }
            i += 1
        }
        return (landings, takeoffs)
    }
}
