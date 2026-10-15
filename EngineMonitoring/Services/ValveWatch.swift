import Foundation

/// Valve watch for one cylinder in one flight.
struct CylinderValveCheck: Codable, Hashable, Sendable {
    let cylinder: Int
    /// The early exhaust-valve signature was seen in enough steady cruise windows.
    let flagged: Bool
    /// Steady cruise windows in which this cylinder showed the signature.
    let hitWindows: Int
    /// Largest single-cylinder EGT cycle seen (peak to peak, °F), and its period (s).
    let largestCycle: Double?
    let periodSeconds: Double?
    /// How many times larger than the other cylinders' cycles in that window.
    let dominance: Double?
    /// Start of the first window with the signature.
    let firstHit: Date?
}

/// Result of the valve watch for one flight.
struct ValveWatchResult: Codable, Hashable, Sendable {
    /// Number of 8-minute steady cruise windows checked (0 = no steady cruise long enough).
    let steadyWindows: Int
    let cylinders: [CylinderValveCheck]

    var flagged: [CylinderValveCheck] { cylinders.filter(\.flagged) }
    var checked: Bool { steadyWindows > 0 }
}

/// Looks for the early exhaust-valve signature published by Savvy Aviation for FEVA (AOPA, Aug 2014):
/// a slow, rhythmic EGT oscillation on ONE cylinder, about one cycle per minute, 30-100 °F, in steady cruise.
/// A valve that is not seating fully leaks some exhaust; as the valve rotator turns it the leak comes and goes,
/// and that cylinder's EGT swings slowly. Built from that description (not Savvy's model).
/// Same method as tools/n63ka_valves.py. Advisory (TRAINING): a flag means "ask the A&P to borescope".
enum ValveWatch {
    static let windowSeconds = 480          // 8 minutes
    static let stepSeconds = 120
    static let periodRange = 40.0...100.0   // seconds per cycle
    static let maxRPMRange = 60.0, maxFuelFlowRange = 1.5, maxMAPRange = 1.5
    /// A lone EGT sample this far from its neighbours is a probe or wiring spike, not a valve.
    static let spikeThreshold = 100.0
    static let maxSpikesPerWindow = 5
    static let minPeakToPeak = 30.0
    static let minPeriodicity = 0.35
    static let minDominance = 2.0
    static let flightShare = 0.25, flightMinHits = 2
    /// Share of a window that must be classified as cruise.
    static let minCruiseShare = 0.8
    static let source = "Signature published by Savvy Aviation (FEVA), AOPA Aug 2014"

    static func analyze(_ log: PerspectiveLog, phases: [FlightPhase]) -> ValveWatchResult {
        let n = log.sampleCount
        let egtChannels = PerspectiveChannel.egt
        guard n >= windowSeconds, phases.count == n, egtChannels.allSatisfy(log.hasChannel) else {
            return ValveWatchResult(steadyWindows: 0, cylinders: [])
        }
        let windows = steadyWindows(log, phases: phases)
        var hits = [Int](repeating: 0, count: 6)
        var best = [(p2p: Double, period: Double, dominance: Double)?](repeating: nil, count: 6)
        var firstHit = [Date?](repeating: nil, count: 6)
        let basis = Basis(length: windowSeconds)
        for start in windows {
            let range = start..<(start + windowSeconds)
            let egt = egtChannels.map { ch in despike(range.map { log.value(ch, at: $0) ?? .nan }) }
            var cycles: [(p2p: Double, period: Double, share: Double)] = []
            for c in 0..<6 {
                let own = detrend((0..<windowSeconds).map { t in
                    let others = (0..<6).filter { $0 != c }.map { egt[$0][t] }
                    return egt[c][t] - median(others)
                })
                cycles.append(basis.strongestCycle(own))
            }
            for c in 0..<6 {
                let rest = Swift.max(median((0..<6).filter { $0 != c }.map { cycles[$0].p2p }), 0.1)
                let dominance = cycles[c].p2p / rest
                if best[c].map({ cycles[c].p2p > $0.p2p }) ?? true {
                    best[c] = (cycles[c].p2p, cycles[c].period, dominance)
                }
                if cycles[c].p2p >= minPeakToPeak, cycles[c].share >= minPeriodicity, dominance >= minDominance {
                    hits[c] += 1
                    if firstHit[c] == nil { firstHit[c] = log.times[start] }
                }
            }
        }
        let cylinders: [CylinderValveCheck] = (0..<6).map { c in
            CylinderValveCheck(
                cylinder: c + 1,
                flagged: hits[c] >= flightMinHits && Double(hits[c]) >= flightShare * Double(windows.count),
                hitWindows: hits[c], largestCycle: best[c]?.p2p, periodSeconds: best[c]?.period,
                dominance: best[c]?.dominance, firstHit: firstHit[c])
        }
        return ValveWatchResult(steadyWindows: windows.count, cylinders: cylinders)
    }

    /// One WATCH issue per flagged cylinder; the issue list groups them by cylinder across flights.
    static func issues(_ result: ValveWatchResult, log: PerspectiveLog) -> [FlightIssue] {
        let t = DateFormatter()
        t.locale = Locale(identifier: "en_US_POSIX")
        t.timeZone = log.timeZone
        t.dateFormat = "HH:mm"
        return result.flagged.map { c in
            FlightIssue(
                kind: "valve.cyl\(c.cylinder)", system: .engine, severity: .watch, origin: .engineData,
                source: log.filename, time: c.firstHit ?? log.start ?? Date(),
                title: "Cylinder \(c.cylinder) EGT cycling in steady cruise (valve watch)",
                detail: String(format: "EGT %ld swung about %.0f °F peak to peak every %.0f s, %.1fx the other cylinders, in %ld of %ld steady cruise windows",
                               c.cylinder, c.largestCycle ?? 0, c.periodSeconds ?? 0, c.dominance ?? 0, c.hitWindows, result.steadyWindows)
                    + (c.firstHit.map { " (from \(t.string(from: $0)))" } ?? ""))
        }
    }

    /// Plain-text section for the shared post-flight report.
    static func markdown(_ result: ValveWatchResult?, timeZone: TimeZone) -> String {
        guard let result else { return "Not checked (summary built before v0.9.3).\n\n" }
        guard result.checked else {
            return "No steady cruise of 8 minutes or more (steady RPM, fuel flow and manifold pressure), so the valves were not checked.\n\n"
        }
        var md = "\(result.steadyWindows) steady cruise windows of 8 minutes checked for one cylinder's EGT cycling about once a minute "
        md += "(\(source)).\n\n"
        if result.flagged.isEmpty {
            let top = result.cylinders.max { ($0.largestCycle ?? 0) < ($1.largestCycle ?? 0) }
            md += "No valve signature." + (top.map { String(format: " Largest single-cylinder cycle: cylinder %ld, %.0f °F.", $0.cylinder, $0.largestCycle ?? 0) } ?? "") + "\n\n"
        }
        for c in result.flagged {
            md += String(format: "- **WATCH cylinder %ld:** EGT cycling about %.0f °F peak to peak every %.0f s, %.1fx the other cylinders, in %ld of %ld windows. ",
                         c.cylinder, c.largestCycle ?? 0, c.periodSeconds ?? 0, c.dominance ?? 0, c.hitWindows, result.steadyWindows)
            md += "Possible early exhaust-valve leak. If it repeats, ask the A&P to borescope cylinder \(c.cylinder).\n"
        }
        if !result.flagged.isEmpty { md += "\n" }
        return md
    }

    // MARK: - Steps

    /// Start indices of 8-minute steady-cruise windows (stepping 2 minutes; 30 s past an unsteady stretch).
    static func steadyWindows(_ log: PerspectiveLog, phases: [FlightPhase]) -> [Int] {
        var out: [Int] = []
        var i = 0
        while i + windowSeconds <= log.sampleCount {
            let range = i..<(i + windowSeconds)
            if levelEnough(phases, range),
               steady(log, PerspectiveChannel.rpm, range, maxRPMRange),
               steady(log, PerspectiveChannel.fuelFlow, range, maxFuelFlowRange),
               steady(log, PerspectiveChannel.manifoldPressure, range, maxMAPRange),
               PerspectiveChannel.egt.allSatisfy({ usableEGT(log, $0, range) }) {
                out.append(i)
                i += stepSeconds
            } else {
                i += 30
            }
        }
        return out
    }

    /// Airborne for the whole window and mostly level. Brief climbs or descents (step climbs, turbulence) are fine:
    /// power must still be steady, and altitude changes move every cylinder's EGT together.
    private static func levelEnough(_ phases: [FlightPhase], _ range: Range<Int>) -> Bool {
        var cruise = 0
        for i in range {
            switch phases[i] {
            case .cruise: cruise += 1
            case .climb, .descent: continue
            default: return false
            }
        }
        return Double(cruise) >= minCruiseShare * Double(range.count)
    }

    private static func steady(_ log: PerspectiveLog, _ channel: String, _ range: Range<Int>, _ maxRange: Double) -> Bool {
        let v = log.samples(channel, in: range).map(\.value)
        guard Double(v.count) >= 0.95 * Double(range.count), let lo = v.min(), let hi = v.max() else { return false }
        return hi - lo <= maxRange
    }

    private static func usableEGT(_ log: PerspectiveLog, _ channel: String, _ range: Range<Int>) -> Bool {
        let v = range.map { log.value(channel, at: $0) }
        guard v.allSatisfy({ $0 != nil }) else { return false }
        return spikes(v.map { $0! }).count <= maxSpikesPerWindow
    }

    /// Indices of samples more than `spikeThreshold` from the median of their ±3 s neighbours.
    static func spikes(_ v: [Double]) -> [Int] {
        v.indices.filter { k in
            let nb = (Swift.max(0, k - 3)..<Swift.min(v.count, k + 4)).filter { $0 != k }.map { v[$0] }
            return !nb.isEmpty && abs(v[k] - median(nb)) > spikeThreshold
        }
    }

    static func despike(_ v: [Double]) -> [Double] {
        var out = v
        for k in spikes(v) {
            out[k] = median((Swift.max(0, k - 3)..<Swift.min(v.count, k + 4)).filter { $0 != k }.map { v[$0] })
        }
        return out
    }

    static func detrend(_ v: [Double]) -> [Double] {
        let n = Double(v.count)
        let xm = (n - 1) / 2, ym = v.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (k, y) in v.enumerated() { sxy += (Double(k) - xm) * (y - ym); sxx += (Double(k) - xm) * (Double(k) - xm) }
        let b = sxx > 0 ? sxy / sxx : 0
        return v.enumerated().map { k, y in y - (ym + b * (Double(k) - xm)) }
    }

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Sine/cosine tables for the cycle periods checked (quarter-bin steps of a window-length Fourier transform).
    struct Basis {
        let length: Int
        let periods: [Double]
        let cosTable: [[Double]]
        let sinTable: [[Double]]

        init(length: Int) {
            self.length = length
            let n = Double(length)
            let kMin = (n / ValveWatch.periodRange.upperBound).rounded(.up)
            let kMax = (n / ValveWatch.periodRange.lowerBound).rounded(.down)
            let ks = Array(stride(from: kMin, through: kMax, by: 0.25))
            periods = ks.map { n / $0 }
            cosTable = ks.map { k in (0..<length).map { t in cos(2 * Double.pi * k * Double(t) / n) } }
            sinTable = ks.map { k in (0..<length).map { t in sin(2 * Double.pi * k * Double(t) / n) } }
        }

        /// Strongest cycle in the period range: peak to peak (°F), period (s) and share of the variance it explains.
        func strongestCycle(_ v: [Double]) -> (p2p: Double, period: Double, share: Double) {
            let n = Double(length)
            let variance = v.reduce(0) { $0 + $1 * $1 } / n
            guard variance > 0 else { return (0, periods.first ?? 60, 0) }
            var bestAmp = 0.0, bestPeriod = periods.first ?? 60
            for j in periods.indices {
                var re = 0.0, im = 0.0
                for t in 0..<length { re += v[t] * cosTable[j][t]; im += v[t] * sinTable[j][t] }
                let amp = 2 * (re * re + im * im).squareRoot() / n
                if amp > bestAmp { bestAmp = amp; bestPeriod = periods[j] }
            }
            return (2 * bestAmp, bestPeriod, Swift.min(bestAmp * bestAmp / 2 / variance, 1))
        }
    }
}
