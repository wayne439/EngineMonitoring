import Foundation

// MARK: - Per-flight results (stored in FlightSummary.engineChecks, version 9)

/// One magneto during the run-up: the RPM drop and each cylinder's EGT rise.
struct MagDrop: Codable, Hashable, Sendable {
    /// "R" or "L" (POH 4-14 order: right first, then left).
    let mag: String
    let time: Date
    /// Run-up RPM minus the settled single-magneto RPM.
    let drop: Double
    let seconds: Int
    /// EGT rise per cylinder (index 0 = cylinder 1), °F.
    let rise: [Double?]
}

/// Something in the run-up mag check worth a look.
struct MagFinding: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A magneto drop over 150 RPM (POH 4-14).
        case drop
        /// The two drops differ by more than 75 RPM (POH 4-14).
        case split
        /// Only one magneto drop seen in a run-up of 30 s or more.
        case oneMag
        /// On one magneto a cylinder's EGT stayed flat or fell while the others rose.
        case coldCylinder
    }
    let kind: Kind
    let mag: String?
    let cylinder: Int?
    /// drop / oneMag: the drop; split: the first (R) drop; coldCylinder: that cylinder's EGT rise.
    let value: Double
    /// split: the second (L) drop; coldCylinder: the other cylinders' median rise.
    let other: Double?
}

/// One run-up (on the ground, RPM held 1,600-2,150 for 20 s or more) with its magneto checks.
struct MagRunup: Codable, Hashable, Sendable {
    let time: Date
    let rpm: Double
    let seconds: Int
    let mags: [MagDrop]
    let findings: [MagFinding]

    func drop(_ mag: String) -> Double? { mags.first { $0.mag == mag }?.drop }
}

/// One lean sweep found in the log (a GAMI lean test).
struct GAMITest: Codable, Hashable, Sendable {
    let time: Date
    let seconds: Int
    let ffStart: Double
    let ffEnd: Double
    /// Fuel flow at each cylinder's peak EGT (index 0 = cylinder 1; nil = did not clearly peak inside the sweep).
    let peakFlow: [Double?]
    /// Richest-peaking minus leanest-peaking cylinder's fuel flow, gph.
    let spread: Double
    let richest: Int
    let leanest: Int
}

/// The numbers behind the report card and the turbonormalizer / induction checks, for one flight.
struct FlightCard: Codable, Hashable, Sendable {
    var airborneHours: Double
    // Takeoff: full power from 20 s before lift-off to 60 s after.
    var takeoffRPM: Double? = nil
    var takeoffMAP: Double? = nil
    var takeoffFF: Double? = nil
    // Climb above 2,400 RPM.
    var climbSeconds: Int = 0
    var climbMaxCHT: Double? = nil
    var climbRate: Double? = nil
    var climbMaxTIT: Double? = nil
    var climbFF: Double? = nil
    /// Full-throttle manifold pressure (90th percentile in climb) by 2,000 ft pressure-altitude band ("0", "2000", ...).
    var deckMAP: [String: Double] = [:]
    // Steady cruise (RPM within 60, MAP 1.5 inHg, fuel flow 1.5 gph over ±30 s).
    var cruiseSeconds: Int = 0
    var cruisePower: Double? = nil
    var cruiseMAP: Double? = nil
    var cruiseRPM: Double? = nil
    var cruiseFF: Double? = nil
    var cruiseTAS: Double? = nil
    var cruiseNMPG: Double? = nil
    var cruiseAltitude: Double? = nil
    var cruiseCHTAvg: Double? = nil
    var cruiseCHTMax: Double? = nil
    var cruiseCHTSpread: Double? = nil
    var cruiseEGTSpread: Double? = nil
    var cruiseTIT: Double? = nil
    var cruiseTITGap: Double? = nil
    var cruiseOilT: Double? = nil
    var cruiseOilP: Double? = nil
    /// Each cylinder's EGT minus the median of the other five, in steady cruise.
    var cruiseEGTDev: [Double]? = nil
    // Airborne at low manifold pressure (under 20 inHg, above 1,800 RPM): the induction-leak check.
    var lowPowerSeconds: Int = 0
    var lowPowerEGTDev: [Double]? = nil
    var oilTMax: Double? = nil
    /// Bus 1 voltage, 2nd percentile while airborne.
    var voltMin: Double? = nil

    /// Per cylinder: how much hotter (relative to the others) it runs at low manifold pressure than in cruise.
    var inductionShift: [Double]? {
        guard let low = lowPowerEGTDev, let cruise = cruiseEGTDev, low.count == 6, cruise.count == 6 else { return nil }
        return (0..<6).map { low[$0] - cruise[$0] }
    }
}

struct EngineCheckResult: Codable, Hashable, Sendable {
    let runups: [MagRunup]
    let gami: [GAMITest]
    let card: FlightCard?

    var magFindings: [MagFinding] { runups.flatMap(\.findings) }
}

/// Run-up mag check, GAMI lean-test spread and the flight card for one log. Same methods as
/// tools/n63ka_magcheck.py, tools/n63ka_gami.py and tools/n63ka_reportcard.py.
enum EngineChecks {
    static let air: Set<FlightPhase> = [.climb, .cruise, .descent]

    static func analyze(_ log: PerspectiveLog, phases: [FlightPhase]) -> EngineCheckResult {
        EngineCheckResult(runups: MagCheck.analyze(log, phases: phases), gami: GAMICheck.analyze(log, phases: phases),
                          card: FlightCardBuilder.compute(log, phases: phases))
    }

    /// Issues from this flight alone (mag check and lean test). Turbo and induction checks need the other flights:
    /// see TurboCheck.issues.
    static func issues(_ r: EngineCheckResult, log: PerspectiveLog) -> [FlightIssue] {
        var out: [FlightIssue] = []
        for u in r.runups {
            for f in u.findings {
                let at = u.mags.first { $0.mag == f.mag }?.time ?? u.time
                switch f.kind {
                case .drop:
                    out.append(FlightIssue(kind: "mag.drop", system: .engineStart, severity: .caution, origin: .engineData, source: log.filename,
                                           time: at, title: "Run-up: \(f.mag ?? "") mag drop \(Int(f.value)) RPM (POH limit 150)",
                                           detail: MagCheck.describe(u)))
                case .split:
                    out.append(FlightIssue(kind: "mag.split", system: .engineStart, severity: .caution, origin: .engineData, source: log.filename,
                                           time: u.time, title: "Run-up: mag drops differ by \(Int(abs(f.value - (f.other ?? 0)))) RPM (POH limit 75)",
                                           detail: MagCheck.describe(u)))
                case .coldCylinder:
                    let c = f.cylinder ?? 0
                    out.append(FlightIssue(kind: "mag.cyl\(c)", system: .engineStart, severity: .watch, origin: .engineData, source: log.filename,
                                           time: at, title: "Run-up: cylinder \(c) EGT did not rise on the \(f.mag ?? "") mag",
                                           detail: String(format: "Cylinder %ld EGT %+.0f °F on the %@ mag while the others rose %.0f °F. ", c, f.value, f.mag ?? "", f.other ?? 0)
                                               + MagCheck.describe(u)))
                case .oneMag:
                    out.append(FlightIssue(kind: "mag.one", system: .engineStart, severity: .info, origin: .engineData, source: log.filename,
                                           time: u.time, title: "Run-up: only one mag drop recorded",
                                           detail: "One drop of \(Int(f.value)) RPM in a \(u.seconds) s run-up. No drop on the other mag can mean a P-lead grounding fault or advanced timing (POH 4-14); usually the check was quick or under 25 RPM. "
                                               + MagCheck.describe(u)))
                }
            }
        }
        for t in r.gami where t.spread >= GAMICheck.goodSpread {
            out.append(FlightIssue(kind: "gami.spread", system: .engine, severity: t.spread >= GAMICheck.poorSpread ? .watch : .info,
                                   origin: .engineData, source: log.filename, time: t.time,
                                   title: String(format: "GAMI spread %.1f gph (cylinder %ld richest, %ld leanest)", t.spread, t.richest, t.leanest),
                                   detail: GAMICheck.describe(t)))
        }
        return out
    }

    static func markdown(_ r: EngineCheckResult?, timeZone: TimeZone) -> String {
        guard let r else { return "Not checked (summary built before v0.9.7).\n\n" }
        var md = "### Run-up mag check\n\n"
        if r.runups.isEmpty { md += "No run-up mag check found in this log.\n\n" }
        for u in r.runups {
            md += "- " + MagCheck.describe(u, timeZone: timeZone) + "\n"
            for f in u.findings { md += "  - **\(MagCheck.severity(f).rawValue):** " + MagCheck.describe(f) + "\n" }
        }
        md += "\n### GAMI lean test\n\n"
        if r.gami.isEmpty { md += "No slow lean sweep in this log (a big-mixture-pull lean is too fast to measure the spread).\n\n" }
        for t in r.gami { md += "- " + GAMICheck.describe(t) + "\n" }
        return md + "\n"
    }

    // MARK: helpers

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Linear-interpolated percentile (q 0...1), like tools/n63ka_flight.py pct().
    static func percentile(_ v: [Double], _ q: Double) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        let p = q * Double(s.count - 1)
        let lo = Int(p), hi = Swift.min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (p - Double(lo))
    }

    static func series(_ log: PerspectiveLog, _ ch: String) -> [Double?] {
        (0..<log.sampleCount).map { log.value(ch, at: $0) }
    }
}

// MARK: - Run-up mag check

/// POH 4-14 (Before Takeoff, 1,700 RPM, R then L): RPM drop must not exceed 150 RPM for either magneto, the differential
/// must not exceed 75 RPM; an absence of RPM drop may indicate faulty grounding or advanced timing. A dip counts as a
/// mag check only when the EGTs rise together (single-plug combustion is slower and hotter at the probe); a dip with
/// falling EGTs is a power change. A cylinder whose EGT does not rise on one mag is not firing on that mag.
enum MagCheck {
    static let maxDrop = 150.0, maxSplit = 75.0
    static let minDip = 25.0, dipHold = 15.0, minEGTRise = 10.0
    static let coldMargin = 25.0, coldMax = 5.0

    static func analyze(_ log: PerspectiveLog, phases: [FlightPhase]) -> [MagRunup] {
        let n = log.sampleCount
        guard n >= 120, phases.count == n else { return [] }
        let rpm = EngineChecks.series(log, PerspectiveChannel.rpm).map { v -> Double? in (v ?? 0) == 0 ? nil : v }
        let egt = PerspectiveChannel.egt.map { EngineChecks.series(log, $0) }
        var out: [MagRunup] = []
        var k = 0
        while k < n {
            guard phases[k] == .ground, let r0 = rpm[k], r0 >= 1600, r0 <= 2150 else { k += 1; continue }
            var j = k
            while j < n, phases[j] == .ground, let r = rpm[j], r >= 1450, r <= 2200 { j += 1 }
            if j - k >= 20, let base = EngineChecks.median(rpm[k..<j].compactMap { $0 }) {
                var dips: [(start: Int, end: Int)] = []
                var m = k
                while m < j {
                    if let r = rpm[m], base - r >= minDip {
                        var e = m
                        while e < j, let r2 = rpm[e], base - r2 >= dipHold { e += 1 }
                        if (2...25).contains(e - m) { dips.append((m, e)) }
                        m = Swift.max(e, m + 1)
                    } else {
                        m += 1
                    }
                }
                if let u = evaluate(log: log, rpm: rpm, egt: egt, start: k, end: j, base: base, dips: dips) { out.append(u) }
            }
            k = j + 1
        }
        return out
    }

    private static func evaluate(log: PerspectiveLog, rpm: [Double?], egt: [[Double?]], start k: Int, end j: Int, base: Double,
                                 dips: [(start: Int, end: Int)]) -> MagRunup? {
        let n = log.sampleCount
        var mags: [MagDrop] = []
        for (m, e) in dips {
            var rise: [Double?] = []
            for c in 0..<6 {
                let pre = egt[c][Swift.max(k, m - 6)..<m].compactMap { $0 }
                let during = egt[c][m..<Swift.min(n, e + 4)].compactMap { $0 }
                if let p = EngineChecks.median(pre), let top = during.max() { rise.append(top - p) } else { rise.append(nil) }
            }
            let r = rise.compactMap { $0 }
            guard r.count >= 4, let mr = EngineChecks.median(r), mr >= minEGTRise else { continue }   // power change
            let low = rpm[m..<e].compactMap { $0 }.sorted()
            guard let settled = EngineChecks.median(Array(low.prefix(Swift.max(1, (low.count + 1) / 2)))) else { continue }
            mags.append(MagDrop(mag: mags.isEmpty ? "R" : "L", time: log.times[m], drop: (base - settled).rounded(), seconds: e - m, rise: rise))
            if mags.count == 2 { break }
        }
        guard !mags.isEmpty else { return nil }
        var f: [MagFinding] = []
        for mg in mags {
            if mg.drop > maxDrop { f.append(MagFinding(kind: .drop, mag: mg.mag, cylinder: nil, value: mg.drop, other: nil)) }
            for c in 0..<6 {
                guard let x = mg.rise[c] else { continue }
                let others = mg.rise.enumerated().compactMap { $0.offset == c ? nil : $0.element }
                if let mo = EngineChecks.median(others), x < coldMax, mo - x >= coldMargin {
                    f.append(MagFinding(kind: .coldCylinder, mag: mg.mag, cylinder: c + 1, value: x, other: mo))
                }
            }
        }
        if mags.count == 2, abs(mags[0].drop - mags[1].drop) > maxSplit {
            f.append(MagFinding(kind: .split, mag: nil, cylinder: nil, value: mags[0].drop, other: mags[1].drop))
        }
        if mags.count == 1, j - k >= 30 {
            f.append(MagFinding(kind: .oneMag, mag: mags[0].mag, cylinder: nil, value: mags[0].drop, other: nil))
        }
        return MagRunup(time: log.times[k], rpm: base.rounded(), seconds: j - k, mags: mags, findings: f)
    }

    static func severity(_ f: MagFinding) -> IssueSeverity {
        switch f.kind {
        case .drop, .split: .caution
        case .coldCylinder: .watch
        case .oneMag: .info
        }
    }

    static func describe(_ f: MagFinding) -> String {
        switch f.kind {
        case .drop: return "\(f.mag ?? "") mag drop \(Int(f.value)) RPM, over the POH 150 RPM limit (POH 4-14)."
        case .split: return "Drops \(Int(f.value)) (R) and \(Int(f.other ?? 0)) (L) RPM differ by \(Int(abs(f.value - (f.other ?? 0)))), over the POH 75 RPM limit (POH 4-14)."
        case .oneMag: return "Only one mag drop (\(Int(f.value)) RPM) recorded. An absence of drop can mean faulty grounding or advanced timing (POH 4-14); repeat the check slowly if unsure."
        case .coldCylinder:
            return String(format: "Cylinder %ld EGT %+.0f °F on the %@ mag while the others rose %.0f °F: that cylinder is likely not firing on that mag (plug, lead or mag).",
                          f.cylinder ?? 0, f.value, f.mag ?? "", f.other ?? 0)
        }
    }

    static func describe(_ u: MagRunup, timeZone: TimeZone? = nil) -> String {
        let t = DateFormatter()
        t.locale = Locale(identifier: "en_US_POSIX")
        t.timeZone = timeZone ?? .current
        t.dateFormat = "HH:mm"
        var s = "Run-up at \(Int(u.rpm)) RPM (\(timeZone == nil ? "" : t.string(from: u.time) + ", ")\(u.seconds) s): "
        s += u.mags.map { "\($0.mag) drop \(Int($0.drop))" }.joined(separator: ", ")
        if u.mags.count == 2 { s += ", difference \(Int(abs(u.mags[0].drop - u.mags[1].drop)))" }
        return s + " RPM."
    }

    /// Run-ups from all flights, newest first.
    static func history(_ summaries: [FlightSummary]) -> [(summary: FlightSummary, runup: MagRunup)] {
        summaries.flatMap { s in (s.engineChecks?.runups ?? []).map { (summary: s, runup: $0) } }.sorted { $0.runup.time > $1.runup.time }
    }

    /// Per magneto and cylinder: the median EGT rise relative to the other cylinders over the given run-ups.
    /// A cylinder consistently well below the others on one mag points at that mag's plug or lead for that cylinder.
    static func cylinderPattern(_ runups: [MagRunup]) -> [String: [Double?]] {
        var out: [String: [Double?]] = [:]
        for mag in ["R", "L"] {
            let drops = runups.compactMap { u in u.mags.first { $0.mag == mag } }
            out[mag] = (0..<6).map { c in
                EngineChecks.median(drops.compactMap { d -> Double? in
                    guard let x = d.rise[c] else { return nil }
                    let others = d.rise.enumerated().compactMap { $0.offset == c ? nil : $0.element }
                    return EngineChecks.median(others).map { x - $0 }
                })
            }
        }
        return out
    }
}

// MARK: - GAMI lean test

/// GAMI spread: lean slowly at constant RPM and MAP until every cylinder passes peak EGT; the fuel flow at each
/// cylinder's peak shows how evenly the injectors feed the cylinders. Spread = richest-peaking minus leanest-peaking
/// cylinder's fuel flow. GAMI: 0.5 gph or less is well balanced; about 1.0 gph or more means mismatched injectors.
/// Found automatically when the log holds a slow enough lean (no faster than about 0.1 gph per second through the
/// peaks); a big-mixture-pull lean to lean-of-peak is too fast for 1-second EGT data and is skipped.
enum GAMICheck {
    static let minDrop = 1.5, maxRate = 0.15, minPeakSide = 10.0, minCylinders = 4
    static let local = 8, maxLocalRate = 0.1, peakFlowStep = 0.2, fitWithin = 25.0
    static let goodSpread = 0.5, poorSpread = 1.0

    static func analyze(_ log: PerspectiveLog, phases: [FlightPhase]) -> [GAMITest] {
        let n = log.sampleCount
        guard n >= 300, phases.count == n else { return [] }
        let ff = smooth(EngineChecks.series(log, PerspectiveChannel.fuelFlow))
        let egt = PerspectiveChannel.egt.map { smooth(EngineChecks.series(log, $0)) }
        var out: [GAMITest] = []
        for (k, j) in sweeps(log, phases: phases, ff: ff) {
            var peaks: [Int: (flow: Double, index: Int)] = [:]
            for c in 0..<6 {
                let seg = Array(egt[c][k..<j])
                guard !seg.contains(where: { $0 == nil }) else { continue }
                let e = seg.map { $0 ?? 0 }
                var p = 0
                for i in e.indices where e[i] > e[p] { p = i }
                let a = k + p
                guard a - local >= 0, a + local < n, let f0 = ff[a - local], let f1 = ff[a + local], let fa = ff[a] else { continue }
                guard (f0 - f1) / Double(2 * local) <= maxLocalRate else { continue }
                guard let before = (0..<p).last(where: { e[p] - e[$0] >= minPeakSide }),
                      let after = ((p + 1)..<e.count).first(where: { e[p] - e[$0] >= minPeakSide }),
                      let fb = ff[k + before], let fz = ff[k + after],
                      fb - fa >= peakFlowStep, fa - fz >= peakFlowStep else { continue }
                peaks[c + 1] = (vertex(flow: Array(ff[k..<j]), egt: e, peak: p), a)
            }
            if peaks.count > 1, Set(peaks.values.map { $0.index }).count == 1 { continue }
            guard peaks.count >= minCylinders,
                  let rich = peaks.max(by: { $0.value.flow < $1.value.flow }),
                  let lean = peaks.min(by: { $0.value.flow < $1.value.flow }),
                  let fs = ff[k], let fe = ff[j - 1] else { continue }
            out.append(GAMITest(time: log.times[k], seconds: j - k, ffStart: fs, ffEnd: fe,
                                peakFlow: (1...6).map { peaks[$0]?.flow }, spread: rich.value.flow - lean.value.flow,
                                richest: rich.key, leanest: lean.key))
        }
        return out
    }

    /// Airborne stretches with RPM within 40 and MAP within 1.0 inHg while fuel flow (5 s median) keeps falling.
    static func sweeps(_ log: PerspectiveLog, phases: [FlightPhase], ff: [Double?]) -> [(Int, Int)] {
        let n = log.sampleCount
        let rpm = EngineChecks.series(log, PerspectiveChannel.rpm)
        let mp = EngineChecks.series(log, PerspectiveChannel.manifoldPressure)
        var out: [(Int, Int)] = []
        var k = 0
        while k < n - 30 {
            guard EngineChecks.air.contains(phases[k]), ff[k] != nil else { k += 1; continue }
            var j = k + 1
            var rLo = Double.infinity, rHi = -Double.infinity, mLo = Double.infinity, mHi = -Double.infinity
            func add(_ i: Int) {
                if let r = rpm[i], r != 0 { rLo = Swift.min(rLo, r); rHi = Swift.max(rHi, r) }
                if let m = mp[i], m != 0 { mLo = Swift.min(mLo, m); mHi = Swift.max(mHi, m) }
            }
            add(k)
            while j < n, EngineChecks.air.contains(phases[j]), let f = ff[j], let fp = ff[j - 1], f <= fp + 0.05 {
                add(j)
                if rHi < rLo || mHi < mLo || rHi - rLo > 40 || mHi - mLo > 1.0 { break }
                j += 1
            }
            let drop = (ff[k] ?? 0) - (ff[j - 1] ?? ff[k] ?? 0)
            if drop >= minDrop, j - k >= 15, drop / Double(j - k) <= maxRate {
                out.append((k, j))
                k = j
            } else {
                k += 1
            }
        }
        return out
    }

    static func smooth(_ v: [Double?], half: Int = 2) -> [Double?] {
        v.indices.map { k in
            EngineChecks.median(v[Swift.max(0, k - half)..<Swift.min(v.count, k + half + 1)].compactMap { $0 })
        }
    }

    /// Fuel flow at the top of a parabola fitted to EGT vs fuel flow (samples within 25 °F of the highest EGT):
    /// the single highest 1 Hz sample wanders on the flat top; the fit does not.
    static func vertex(flow f: [Double?], egt e: [Double], peak p: Int) -> Double {
        let fallback = f[p] ?? 0
        let pts = e.indices.compactMap { i -> (Double, Double)? in
            guard let x = f[i], e[p] - e[i] <= fitWithin else { return nil }
            return (x, e[i])
        }
        guard pts.count >= 5 else { return fallback }
        let xm = pts.map { $0.0 }.reduce(0, +) / Double(pts.count)
        var a = [[Double]](repeating: [0, 0, 0], count: 3)
        var b = [Double](repeating: 0, count: 3)
        for (x, y) in pts {
            let v = [1.0, x - xm, (x - xm) * (x - xm)]
            for r in 0..<3 {
                b[r] += v[r] * y
                for c in 0..<3 { a[r][c] += v[r] * v[c] }
            }
        }
        guard let s = solve3(a, b), s[2] < 0 else { return fallback }
        let x = xm - s[1] / (2 * s[2])
        guard let lo = pts.map { $0.0 }.min(), let hi = pts.map { $0.0 }.max(), x >= lo, x <= hi else { return fallback }
        return x
    }

    static func solve3(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = (0..<3).map { a[$0] + [b[$0]] }
        for c in 0..<3 {
            var piv = c
            for r in c..<3 where abs(m[r][c]) > abs(m[piv][c]) { piv = r }
            guard abs(m[piv][c]) > 1e-12 else { return nil }
            m.swapAt(c, piv)
            for r in 0..<3 where r != c {
                let k = m[r][c] / m[c][c]
                for i in 0..<4 { m[r][i] -= k * m[c][i] }
            }
        }
        return (0..<3).map { m[$0][3] / m[$0][$0] }
    }

    static func rating(_ spread: Double) -> String {
        spread < goodSpread ? "well balanced" : spread < poorSpread ? "fair" : "mismatched injectors likely"
    }

    static func describe(_ t: GAMITest) -> String {
        let peaks = t.peakFlow.enumerated().compactMap { i, f in f.map { String(format: "%ld: %.1f", i + 1, $0) } }.joined(separator: ", ")
        return String(format: "Lean sweep %.1f to %.1f gph over %ld s: GAMI spread %.1f gph (%@); cylinder %ld peaks richest, %ld leanest. Peak fuel flow by cylinder: %@.",
                      t.ffStart, t.ffEnd, t.seconds, t.spread, rating(t.spread), t.richest, t.leanest, peaks)
    }

    /// Lean tests from all flights, newest first.
    static func history(_ summaries: [FlightSummary]) -> [(summary: FlightSummary, test: GAMITest)] {
        summaries.flatMap { s in (s.engineChecks?.gami ?? []).map { (summary: s, test: $0) } }.sorted { $0.test.time > $1.test.time }
    }

    /// The guided lean test (GAMI's procedure, adapted to the Perspective's 1-second engine log).
    static let procedure: [String] = [
        "Level cruise, 2,500 RPM, full throttle (or a fixed MAP), autopilot on, smooth air. Note the time.",
        "Mixture: start about 50 °F rich of peak on the hottest-running cylinder (TIT at least 100 °F below the redline).",
        "Lean SLOWLY and steadily, about 0.1 gph every second or slower (roughly 1 gph per 10-15 s), watching the EGTs climb.",
        "Keep leaning through peak until every cylinder has peaked and its EGT has fallen 30-50 °F (lean of peak). Don't stop at the first peak.",
        "Keep RPM and MAP unchanged during the sweep. Then set your normal cruise mixture.",
        "After the flight, import the log: the app finds the sweep, the fuel flow at each cylinder's peak and the GAMI spread.",
        "Watch CHTs and TIT throughout; abandon the test if anything approaches a limit or the engine runs rough.",
    ]
}

// MARK: - Flight card (report card and turbo / induction inputs)

enum FlightCardBuilder {
    static let minAirborneSeconds = 600, minCruiseSeconds = 300, minLowPowerSeconds = 60
    static let bands = Array(stride(from: 0, to: 18000, by: 2000))

    static func compute(_ log: PerspectiveLog, phases: [FlightPhase]) -> FlightCard? {
        let n = log.sampleCount
        guard n >= 300, phases.count == n else { return nil }
        let air = (0..<n).filter { EngineChecks.air.contains(phases[$0]) }
        guard air.count >= minAirborneSeconds, let first = air.first else { return nil }
        func s(_ ch: String) -> [Double?] { EngineChecks.series(log, ch) }
        let rpm = s(PerspectiveChannel.rpm), mp = s(PerspectiveChannel.manifoldPressure), ff = s(PerspectiveChannel.fuelFlow)
        let alt = s(PerspectiveChannel.altBaro), vs = s("VSpd"), tas = s("TAS"), pw = s(PerspectiveChannel.percentPower)
        let cht = PerspectiveChannel.cht.map(s), egt = PerspectiveChannel.egt.map(s)
        let t1 = s(PerspectiveChannel.tit1), t2 = s(PerspectiveChannel.tit2)
        let oilT = s(PerspectiveChannel.oilTemp), oilP = s(PerspectiveChannel.oilPressure), v1 = s(PerspectiveChannel.volt1)
        let med = EngineChecks.median
        func maxCHT(_ i: Int) -> Double { cht.map { $0[i] ?? 0 }.max() ?? 0 }
        func hotTIT(_ i: Int) -> Double { Swift.max(t1[i] ?? 0, t2[i] ?? 0) }
        func egtDev(_ idx: [Int]) -> [Double]? {
            let dev = (0..<6).map { c in
                med(idx.compactMap { i -> Double? in
                    guard let x = egt[c][i], let o = med((0..<6).filter { $0 != c }.compactMap { egt[$0][i] }) else { return nil }
                    return x - o
                })
            }
            let d = dev.compactMap { $0 }
            return d.count == 6 ? d : nil
        }

        var card = FlightCard(airborneHours: Double(air.count) / 3600)

        let to = (Swift.max(0, first - 20)..<Swift.min(n, first + 60)).filter { (rpm[$0] ?? 0) > 2550 && (mp[$0] ?? 0) > 26 }
        if to.count >= 15 {
            card.takeoffRPM = med(to.compactMap { rpm[$0] })
            card.takeoffMAP = med(to.compactMap { mp[$0] })
            card.takeoffFF = med(to.compactMap { ff[$0] })
        }

        let climb = air.filter { phases[$0] == .climb && (rpm[$0] ?? 0) > 2400 && alt[$0] != nil && mp[$0] != nil }
        card.climbSeconds = climb.count
        if !climb.isEmpty {
            card.climbMaxCHT = climb.map(maxCHT).max()
            card.climbRate = med(climb.compactMap { vs[$0] })
            card.climbMaxTIT = climb.map(hotTIT).max()
            card.climbFF = med(climb.compactMap { ff[$0] })
            for b in bands {
                let v = climb.filter { (alt[$0] ?? -1) >= Double(b) && (alt[$0] ?? -1) < Double(b + 2000) }.compactMap { mp[$0] }
                if v.count >= 20, let p = EngineChecks.percentile(v, 0.9) { card.deckMAP[String(b)] = p }
            }
        }

        let cruise = air.filter { phases[$0] == .cruise && $0 >= 30 && $0 < n - 30 && steady(rpm, mp, ff, $0) }
        card.cruiseSeconds = cruise.count
        if cruise.count >= minCruiseSeconds {
            func m(_ v: [Double?]) -> Double? { med(cruise.compactMap { v[$0] }) }
            let full = cruise.filter { i in cht.allSatisfy { $0[i] != nil } }
            let fullEGT = cruise.filter { i in egt.allSatisfy { $0[i] != nil } }
            card.cruisePower = m(pw).map { $0 <= 1.5 ? $0 * 100 : $0 }
            card.cruiseMAP = m(mp)
            card.cruiseRPM = m(rpm)
            card.cruiseFF = m(ff)
            card.cruiseTAS = m(tas)
            if let t = card.cruiseTAS, let f = card.cruiseFF, f > 0 { card.cruiseNMPG = t / f }
            card.cruiseAltitude = m(alt)
            card.cruiseCHTAvg = med(full.map { i in cht.map { $0[i] ?? 0 }.reduce(0, +) / 6 })
            card.cruiseCHTMax = cruise.map(maxCHT).max()
            card.cruiseCHTSpread = med(full.map { i in let v = cht.map { $0[i] ?? 0 }; return (v.max() ?? 0) - (v.min() ?? 0) })
            card.cruiseEGTSpread = med(fullEGT.map { i in let v = egt.map { $0[i] ?? 0 }; return (v.max() ?? 0) - (v.min() ?? 0) })
            card.cruiseTIT = med(cruise.map(hotTIT))
            card.cruiseTITGap = med(cruise.compactMap { i in t1[i].flatMap { a in t2[i].map { a - $0 } } })
            card.cruiseOilT = m(oilT)
            card.cruiseOilP = m(oilP)
            card.cruiseEGTDev = egtDev(fullEGT)
        }

        let low = air.filter { i in (mp[i] ?? 99) < 20 && (rpm[i] ?? 0) > 1800 && egt.allSatisfy { $0[i] != nil } }
        card.lowPowerSeconds = low.count
        if low.count >= minLowPowerSeconds { card.lowPowerEGTDev = egtDev(low) }

        card.oilTMax = oilT.compactMap { $0 }.max()
        card.voltMin = EngineChecks.percentile(air.compactMap { v1[$0] }, 0.02)
        return card
    }

    /// Steady power over ±30 s: RPM within 60, MAP within 1.5 inHg, fuel flow within 1.5 gph (more than 50 readings each).
    static func steady(_ rpm: [Double?], _ mp: [Double?], _ ff: [Double?], _ i: Int) -> Bool {
        for (v, limit) in [(rpm, 60.0), (mp, 1.5), (ff, 1.5)] {
            let w = v[(i - 30)...(i + 30)].compactMap { $0 }
            guard w.count > 50, let lo = w.min(), let hi = w.max(), hi - lo <= limit else { return false }
        }
        return true
    }
}
