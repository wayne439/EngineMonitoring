import Foundation
import UserNotifications

/// Steady-cruise engine values for one flight, used to follow N63KA's engine across flights (early warning, trend charts).
/// Only samples in cruise with steady power (±30 s) count, so flights are compared like for like.
struct EngineTrendMetrics: Codable, Hashable, Sendable {
    /// Seconds of steady cruise in the flight (metrics are nil below `EarlyWarning.minSteadySeconds`).
    let steadySeconds: Int
    let oat: Double?
    let fuelFlow: Double?
    /// CHT per cylinder (index 0 = cylinder 1).
    let cht: [Double?]
    /// EGT per cylinder minus the mean of all six.
    let egtDev: [Double?]
    let chtSpread: Double?
    let egtSpread: Double?
    let oilTemp: Double?
    let oilPressure: Double?
    /// TIT 1 minus TIT 2.
    let titDiff: Double?
    let volt1: Double?
    let volt2: Double?

    static func compute(_ log: PerspectiveLog, phases: [FlightPhase]) -> EngineTrendMetrics? {
        guard log.sampleCount >= 600, phases.count == log.sampleCount else { return nil }
        let steady = ProbeCheck.steadyMask(log, phases: phases)
        let idx = steady.indices.filter { steady[$0] }
        guard idx.count >= EarlyWarning.minSteadySeconds else {
            return EngineTrendMetrics(steadySeconds: idx.count, oat: nil, fuelFlow: nil, cht: [], egtDev: [], chtSpread: nil,
                                      egtSpread: nil, oilTemp: nil, oilPressure: nil, titDiff: nil, volt1: nil, volt2: nil)
        }
        func med(_ ch: String) -> Double? { EarlyWarning.median(idx.compactMap { log.value(ch, at: $0) }) }
        let chts = PerspectiveChannel.cht.map { ch in EarlyWarning.median(idx.compactMap { log.value(ch, at: $0) }) }
        var chtSpread: [Double] = [], egtSpread: [Double] = []
        var dev = [[Double]](repeating: [], count: 6)
        for k in idx {
            let c = PerspectiveChannel.cht.compactMap { log.value($0, at: k) }
            let e = PerspectiveChannel.egt.compactMap { log.value($0, at: k) }
            if c.count == 6, let hi = c.max(), let lo = c.min() { chtSpread.append(hi - lo) }
            if e.count == 6, let hi = e.max(), let lo = e.min() {
                egtSpread.append(hi - lo)
                let mean = e.reduce(0, +) / 6
                for i in 0..<6 { dev[i].append(e[i] - mean) }
            }
        }
        let tit = idx.compactMap { k -> Double? in
            guard let a = log.value(PerspectiveChannel.tit1, at: k), let b = log.value(PerspectiveChannel.tit2, at: k) else { return nil }
            return a - b
        }
        return EngineTrendMetrics(
            steadySeconds: idx.count, oat: med(PerspectiveChannel.oat), fuelFlow: med(PerspectiveChannel.fuelFlow), cht: chts,
            egtDev: dev.map { EarlyWarning.median($0) }, chtSpread: EarlyWarning.median(chtSpread),
            egtSpread: EarlyWarning.median(egtSpread), oilTemp: med(PerspectiveChannel.oilTemp),
            oilPressure: med(PerspectiveChannel.oilPressure), titDiff: EarlyWarning.median(tit),
            volt1: med(PerspectiveChannel.volt1), volt2: med(PerspectiveChannel.volt2))
    }
}

/// One value followed across flights.
struct TrendMetric: Hashable, Identifiable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case cylinders = "Cylinder Temperatures"
        case balance = "Cylinder Balance"
        case valves = "Valve Watch"
        case oil = "Oil"
        case turbo = "Turbochargers"
        case electrical = "Electrical"
    }

    let id: String
    let label: String
    let unit: String
    /// +1: higher is the concern; -1: lower is the concern.
    let badDirection: Double
    let threshold: Double?
    let thresholdSource: String?
    /// Corrected for outside air temperature and fuel flow.
    let corrected: Bool
    let group: Group
    let cylinder: Int?

    static let all: [TrendMetric] = {
        var m: [TrendMetric] = []
        for c in 1...6 {
            m.append(TrendMetric(id: "cht\(c)", label: "Cylinder \(c) CHT in cruise", unit: "°F", badDirection: 1, threshold: 400,
                                 thresholdSource: "400 °F cruise CHT (engine-monitor practice; POH caution 420 °F)",
                                 corrected: true, group: .cylinders, cylinder: c))
        }
        for c in 1...6 {
            m.append(TrendMetric(id: "egtgap\(c)", label: "Cylinder \(c) EGT distance from the others", unit: "°F", badDirection: 1,
                                 threshold: nil, thresholdSource: nil, corrected: true, group: .balance, cylinder: c))
        }
        for c in 1...6 {
            m.append(TrendMetric(id: "cycle\(c)", label: "Cylinder \(c) valve-watch EGT cycle", unit: "°F", badDirection: 1,
                                 threshold: ValveWatch.minPeakToPeak, thresholdSource: "30 °F valve-watch threshold",
                                 corrected: false, group: .valves, cylinder: c))
        }
        m += [
            TrendMetric(id: "chtspread", label: "CHT spread in cruise", unit: "°F", badDirection: 1, threshold: 100,
                        thresholdSource: "100 °F hottest-to-coolest CHT (engine-monitor practice)", corrected: true, group: .balance, cylinder: nil),
            TrendMetric(id: "egtspread", label: "EGT spread in cruise", unit: "°F", badDirection: 1, threshold: nil,
                        thresholdSource: nil, corrected: true, group: .balance, cylinder: nil),
            TrendMetric(id: "oilt", label: "Oil temperature in cruise", unit: "°F", badDirection: 1, threshold: 240,
                        thresholdSource: "240 °F POH limit", corrected: true, group: .oil, cylinder: nil),
            TrendMetric(id: "oilp", label: "Oil pressure in cruise", unit: "psi", badDirection: -1, threshold: 30,
                        thresholdSource: "30 psi POH caution", corrected: true, group: .oil, cylinder: nil),
            TrendMetric(id: "titgap", label: "Gap between TIT 1 and TIT 2 in cruise", unit: "°F", badDirection: 1, threshold: nil,
                        thresholdSource: nil, corrected: true, group: .turbo, cylinder: nil),
            TrendMetric(id: "volt1", label: "Bus 1 voltage in cruise", unit: "V", badDirection: -1, threshold: 24.5,
                        thresholdSource: "24.5 V M BUS 1 caution (POH 2-9)", corrected: false, group: .electrical, cylinder: nil),
            TrendMetric(id: "volt2", label: "Bus 2 voltage in cruise", unit: "V", badDirection: -1, threshold: 24.5,
                        thresholdSource: "24.5 V M BUS 2 caution (POH 2-9)", corrected: false, group: .electrical, cylinder: nil),
        ]
        return m
    }()

    static func named(_ id: String) -> TrendMetric? { all.first { $0.id == id } }

    var minimumSigma: Double { unit == "V" ? 0.1 : (unit == "psi" ? 1 : 2) }
    var digits: Int { unit == "V" ? 1 : 0 }
    func format(_ v: Double) -> String { String(format: "%.\(digits)f %@", v, unit) }

    func value(in s: FlightSummary) -> Double? {
        if id.hasPrefix("cycle"), let c = cylinder {
            guard let vw = s.valveWatch, vw.checked else { return nil }
            return vw.cylinders.first { $0.cylinder == c }?.largestCycle
        }
        guard let t = s.engineTrend, t.steadySeconds >= EarlyWarning.minSteadySeconds else { return nil }
        func at(_ a: [Double?], _ c: Int) -> Double? { c - 1 < a.count ? a[c - 1] : nil }
        switch id {
        case "chtspread": return t.chtSpread
        case "egtspread": return t.egtSpread
        case "oilt": return t.oilTemp
        case "oilp": return t.oilPressure
        case "titgap": return t.titDiff.map { abs($0) }
        case "volt1": return t.volt1
        case "volt2": return t.volt2
        default:
            guard let c = cylinder else { return nil }
            if id.hasPrefix("cht") { return at(t.cht, c) }
            if id.hasPrefix("egtgap") { return at(t.egtDev, c).map { abs($0) } }
            return nil
        }
    }
}

/// One flight's value of a metric, with the condition correction applied.
struct TrendPoint: Hashable, Identifiable, Sendable {
    let filename: String
    let date: Date
    /// Flight hours from the first log to the end of this flight.
    let hours: Double
    let value: Double
    /// Value corrected to N63KA's typical outside air temperature and fuel flow (equals `value` for uncorrected metrics).
    let adjusted: Double
    var id: String { filename }
}

/// One metric followed across flights, and what the early warning concluded.
struct TrendAnalysis: Hashable, Identifiable, Sendable {
    enum Level: String, Sendable { case earlyWarning = "EARLY WARNING", actSoon = "ACT SOON" }
    enum Finding: String, Sendable { case shift, drift }

    let metric: TrendMetric
    let points: [TrendPoint]
    /// Number of flights in the baseline (the flights before the newest five).
    let baselineFlights: Int
    /// Normal band on the adjusted scale.
    let normalLow: Double
    let normalHigh: Double
    let sigma: Double
    let shiftSigma: Double
    let slopePerHour: Double
    let trendZ: Double
    let findings: [Finding]
    let level: Level?
    /// Median raw value of the newest five flights.
    let recentValue: Double
    let hoursToThreshold: Double?
    /// Trend line through the newest flights (adjusted scale): start and end (projected) points as (hours, value).
    let trendLine: [TrendLinePoint]

    var id: String { metric.id }
}

struct TrendLinePoint: Hashable, Sendable {
    let hours: Double
    let value: Double
    let projected: Bool
}

/// What may be developing, from one or more metrics.
struct EarlyWarningPattern: Hashable, Identifiable, Sendable {
    let cylinder: Int?
    let title: String
    let advice: String
    let metrics: [String]
    let level: TrendAnalysis.Level
    var id: String { title + (cylinder.map { " \($0)" } ?? "") }
}

struct EarlyWarningReport: Sendable {
    let flightsUsed: Int
    let hoursCovered: Double
    /// Every metric with enough flights to judge.
    let analyses: [TrendAnalysis]
    let patterns: [EarlyWarningPattern]
    let newestFlight: FlightSummary?

    var findings: [TrendAnalysis] { analyses.filter { $0.level != nil } }
    var level: TrendAnalysis.Level? {
        findings.contains { $0.level == .actSoon } ? .actSoon : (findings.isEmpty ? nil : .earlyWarning)
    }
    func analysis(_ id: String) -> TrendAnalysis? { analyses.first { $0.metric.id == id } }
}

/// Early warning across flights: looks for the slow changes that come BEFORE a failure (same method as
/// tools/n63ka_early_warning.py, tuned on N63KA's 324 logs). For each metric: correct for outside air temperature and
/// fuel flow on a rolling baseline (the 40 flights before the newest 5; at least 20 needed); SHIFT = newest 5 flights
/// more than 2.5 sigma from normal the bad way; DRIFT = over the newest 10 flights a significant Mann-Kendall trend
/// (z > 2.75), a fitted change over 1.5 sigma and the newest 3 flights already 1 sigma out. Hours to the threshold come
/// from the trend (only when it covers 8+ flight hours). ACT SOON if over 4 sigma or within 10 flight hours of the
/// threshold. Advisory (TRAINING): look closer and ask the A&P; never a diagnosis, never overrides the POH.
enum EarlyWarning {
    static let minSteadySeconds = 300
    static let baselineMin = 20, baselineMax = 40, recent = 5, driftFlights = 10
    static let shiftSigma = 2.5, actSigma = 4.0
    static let driftZ = 2.75, driftChangeSigma = 1.5, driftRecentSigma = 1.0
    static let actHours = 10.0, minProjectSpanHours = 8.0, projectionHorizonHours = 25.0
    static let source = "N63KA's own history, corrected for outside air temperature and fuel flow; method in tools/n63ka_early_warning.py"

    struct Flight {
        let summary: FlightSummary
        let hours: Double
    }

    static func analyze(_ summaries: [FlightSummary]) -> EarlyWarningReport {
        let sorted = summaries.sorted { $0.start < $1.start }
        var cum = 0.0
        var flights: [Flight] = []
        for s in sorted {
            cum += Double(s.airborneSeconds) / 3600
            flights.append(Flight(summary: s, hours: cum))
        }
        let usable = flights.filter { ($0.summary.engineTrend?.steadySeconds ?? 0) >= minSteadySeconds }
        let analyses = TrendMetric.all.compactMap { evaluate($0, usable) }
        return EarlyWarningReport(flightsUsed: usable.count, hoursCovered: cum, analyses: analyses,
                                  patterns: patterns(analyses.filter { $0.level != nil }), newestFlight: usable.last?.summary)
    }

    static func evaluate(_ metric: TrendMetric, _ flights: [Flight]) -> TrendAnalysis? {
        let pts = flights.compactMap { f -> (Flight, Double, Double, Double)? in
            guard let v = metric.value(in: f.summary), let t = f.summary.engineTrend, let oat = t.oat, let ff = t.fuelFlow else { return nil }
            return (f, v, oat, ff)
        }
        guard pts.count >= baselineMin + recent else { return nil }
        let base = Array(pts.dropLast(recent).suffix(baselineMax))
        let newest = Array(pts.suffix(recent))

        // Condition correction: value ~ a + b·OAT + c·fuel flow, fitted on the baseline.
        var fit: (Double, Double) -> Double = { _, _ in 0 }
        var typical = 0.0
        if metric.corrected {
            let coef = leastSquares(base.map { [$0.2, $0.3] }, base.map { $0.1 })
            fit = { oat, ff in coef[0] + coef[1] * oat + coef[2] * ff }
            typical = fit(median(base.map { $0.2 }) ?? 0, median(base.map { $0.3 }) ?? 0)
        } else {
            let m0 = median(base.map { $0.1 }) ?? 0
            fit = { _, _ in m0 }
            typical = m0
        }
        let residual = { (p: (Flight, Double, Double, Double)) in p.1 - fit(p.2, p.3) }
        let br = base.map(residual)
        let centre = median(br) ?? 0
        let sigma = Swift.max(1.4826 * (median(br.map { abs($0 - centre) }) ?? 0), metric.minimumSigma)
        let shift = ((median(newest.map(residual)) ?? centre) - centre) / sigma

        let last = Array(pts.suffix(driftFlights))
        let lr = last.map(residual)
        let slope = theilSen(last.map { $0.0.hours }, lr)
        let z = mannKendall(lr)
        let span = (last.last?.0.hours ?? 0) - (last.first?.0.hours ?? 0)
        let near = ((median(Array(lr.suffix(3))) ?? centre) - centre) / sigma
        let sgn = metric.badDirection
        var findings: [TrendAnalysis.Finding] = []
        if sgn * shift > shiftSigma { findings.append(.shift) }
        if sgn * z > driftZ, sgn * slope * span > driftChangeSigma * sigma, sgn * near > driftRecentSigma { findings.append(.drift) }

        let level = median(newest.map { $0.1 }) ?? 0
        var hoursLeft: Double?
        if let thr = metric.threshold, sgn * slope > 0, span >= minProjectSpanHours {
            hoursLeft = Swift.max(sgn > 0 ? thr - level : level - thr, 0) / (sgn * slope)
        }
        var result: TrendAnalysis.Level?
        if !findings.isEmpty {
            result = (sgn * shift > actSigma || (hoursLeft.map { $0 <= actHours } ?? false)) ? .actSoon : .earlyWarning
        }

        // Chart data on the adjusted scale (value at typical conditions).
        let points = pts.map { p in
            TrendPoint(filename: p.0.summary.filename, date: p.0.summary.start, hours: p.0.hours, value: p.1,
                       adjusted: residual(p) + typical)
        }
        let la = last.map { residual($0) + typical }
        let intercept = median(zip(last, la).map { $1 - slope * $0.0.hours }) ?? typical
        var line: [TrendLinePoint] = []
        if let h0 = last.first?.0.hours, let h1 = last.last?.0.hours {
            line = [TrendLinePoint(hours: h0, value: intercept + slope * h0, projected: false),
                    TrendLinePoint(hours: h1, value: intercept + slope * h1, projected: false)]
            if !findings.isEmpty {
                let ahead = Swift.min(hoursLeft ?? projectionHorizonHours, projectionHorizonHours)
                line.append(TrendLinePoint(hours: h1 + ahead, value: intercept + slope * (h1 + ahead), projected: true))
            }
        }
        return TrendAnalysis(metric: metric, points: points, baselineFlights: base.count,
                             normalLow: centre + typical - 2 * sigma, normalHigh: centre + typical + 2 * sigma, sigma: sigma,
                             shiftSigma: shift, slopePerHour: slope, trendZ: z, findings: findings, level: result,
                             recentValue: level, hoursToThreshold: findings.isEmpty ? nil : hoursLeft, trendLine: line)
    }

    // MARK: - Patterns: what may be developing

    static func patterns(_ found: [TrendAnalysis]) -> [EarlyWarningPattern] {
        let by = Dictionary(uniqueKeysWithValues: found.map { ($0.metric.id, $0) })
        var out: [EarlyWarningPattern] = []
        func add(_ cyl: Int?, _ title: String, _ advice: String, _ ev: [TrendAnalysis]) {
            let level: TrendAnalysis.Level = ev.contains { $0.level == .actSoon } ? .actSoon : .earlyWarning
            out.append(EarlyWarningPattern(cylinder: cyl, title: title, advice: advice, metrics: ev.map(\.metric.id), level: level))
        }
        for c in 1...6 {
            let cht = by["cht\(c)"], gap = by["egtgap\(c)"], cyc = by["cycle\(c)"]
            if let cyc {
                add(c, "Exhaust valve starting to leak",
                    "The valve-watch cycle on this cylinder is growing. Ask the A&P to borescope the exhaust valve.",
                    [cyc] + [gap, cht].compactMap { $0 })
            }
            if let gap, let cht {
                add(c, "Cylinder moving out of balance and running hotter (injector, induction leak, timing)",
                    "EGT moving away from the other cylinders with CHT rising. Clean/flow the injector, check the intake coupling for leaks, check timing; a GAMI lean test confirms.",
                    [gap, cht])
            } else if let gap {
                add(c, "Fuel/air balance change on this cylinder (injector or induction)",
                    "One EGT moving away from the others. Check that injector and intake; check the probe if Probes & Wiring flagged it.", [gap])
            } else if let cht {
                add(c, "Cylinder running hotter for the conditions",
                    "Check baffles and seals near this cylinder and the CHT probe; compare with the oil analysis.", [cht])
            }
        }
        if let s = by["chtspread"], !out.contains(where: { $0.cylinder != nil }) {
            add(nil, "Cylinders drifting apart (cooling or fuel distribution)", "Check baffles and injectors; a GAMI lean test shows fuel distribution.", [s])
        }
        if let s = by["egtspread"], !out.contains(where: { $0.cylinder != nil }) {
            add(nil, "EGTs spreading apart (fuel distribution or induction)", "A GAMI lean test shows whether the injectors are matched; check intake couplings.", [s])
        }
        if let s = by["oilt"] {
            add(nil, "Oil running hotter for the weather (oil cooler, baffles, winterization plate)", "Check the oil cooler and its baffles/plate; compare with the oil analysis.", [s])
        }
        if let s = by["oilp"] {
            add(nil, "Oil pressure sagging (oil level, relief valve, sender, internal wear)", "Check quantity and leaks, then the pressure relief setting and sender; watch iron and copper in the oil analysis.", [s])
        }
        if let s = by["titgap"] {
            add(nil, "The two turbo sides separating (exhaust leak, wastegate or TIT probe)", "Inspect the exhaust and turbo system and both TIT probes.", [s])
        }
        for b in ["volt1", "volt2"] {
            if let s = by[b] {
                add(nil, "Bus \(b.suffix(1)) voltage declining (alternator, regulator, battery, connections)", "Have the alternator output, regulator and battery checked.", [s])
            }
        }
        return out
    }

    // MARK: - Issues (Issue History) and notifications

    /// Current early warnings as issues: one per metric, kind "early.<metric>".
    static func issues(_ report: EarlyWarningReport) -> [FlightIssue] {
        guard let newest = report.newestFlight else { return [] }
        return report.findings.map { a in
            FlightIssue(kind: "early.\(a.metric.id)", system: a.metric.group == .electrical ? .electrical : .engine, severity: .watch,
                        origin: .trend, source: newest.filename, time: newest.start,
                        title: "\(a.level?.rawValue ?? "EARLY WARNING"): \(a.metric.label) \(a.metric.badDirection > 0 ? "rising" : "falling")",
                        detail: describe(a))
        }
    }

    static func describe(_ a: TrendAnalysis) -> String {
        var s = "Newest flights \(a.metric.format(a.recentValue)), " + String(format: "%+.1f", a.shiftSigma) + " sigma from N63KA's normal"
        s += a.findings.contains(.drift) ? String(format: ", trending %+.\(a.metric.digits + 1)f %@ per flight hour", a.slopePerHour, a.metric.unit) : ""
        if let h = a.hoursToThreshold, let t = a.metric.threshold {
            s += String(format: "; about %.0f flight hours to %@ at this rate", h, a.metric.format(t))
        }
        return s
    }

    static func markdown(_ report: EarlyWarningReport) -> String {
        var md = "Over \(report.flightsUsed) flights with steady cruise (" + String(format: "%.0f", report.hoursCovered) + " flight hours).\n\n"
        if report.findings.isEmpty { return md + "Nothing drifting: every tracked value is within N63KA's normal and not trending the wrong way.\n\n" }
        for p in report.patterns {
            md += "- **\(p.level.rawValue): \(p.title)**" + (p.cylinder.map { " (cylinder \($0))" } ?? "") + ". \(p.advice)\n"
        }
        for a in report.findings { md += "  - \(a.metric.label): " + describe(a) + "\n" }
        return md + "\n"
    }

    // MARK: - Statistics

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Least squares with intercept (and a tiny ridge for stability): returns [intercept, b1, b2, ...].
    static func leastSquares(_ x: [[Double]], _ y: [Double]) -> [Double] {
        let k = (x.first?.count ?? 0) + 1
        let rows = x.map { [1.0] + $0 }
        var m = [[Double]](repeating: [Double](repeating: 0, count: k + 1), count: k)
        for i in 0..<k {
            for j in 0..<k { m[i][j] = zip(rows, rows).reduce(0) { $0 + $1.0[i] * $1.1[j] } + (i == j ? 1e-6 : 0) }
            m[i][k] = zip(rows, y).reduce(0) { $0 + $1.0[i] * $1.1 }
        }
        for i in 0..<k {
            let p = (i..<k).max { abs(m[$0][i]) < abs(m[$1][i]) } ?? i
            m.swapAt(i, p)
            guard abs(m[i][i]) > 1e-12 else { continue }
            for r in 0..<k where r != i {
                let f = m[r][i] / m[i][i]
                for c in 0...k { m[r][c] -= f * m[i][c] }
            }
        }
        return (0..<k).map { abs(m[$0][$0]) > 1e-12 ? m[$0][k] / m[$0][$0] : 0 }
    }

    static func theilSen(_ xs: [Double], _ ys: [Double]) -> Double {
        var s: [Double] = []
        for i in 0..<xs.count { for j in (i + 1)..<xs.count where xs[j] != xs[i] { s.append((ys[j] - ys[i]) / (xs[j] - xs[i])) } }
        return median(s) ?? 0
    }

    /// Mann-Kendall trend statistic as a z-score (positive = rising).
    static func mannKendall(_ ys: [Double]) -> Double {
        let n = ys.count
        var s = 0
        for i in 0..<n { for j in (i + 1)..<n { s += ys[j] > ys[i] ? 1 : (ys[j] < ys[i] ? -1 : 0) } }
        let v = Double(n * (n - 1) * (2 * n + 5)) / 18
        guard s != 0, v > 0 else { return 0 }
        return (Double(s) - (s > 0 ? 1 : -1)) / v.squareRoot()
    }
}

/// Every cylinder's EGT and CHT through one flight, thinned for charting (post-flight report).
struct CylinderSeries: Sendable {
    let times: [Date]
    /// [cylinder][sample]
    let egt: [[Double?]]
    let cht: [[Double?]]
    let step: Double

    /// Samples every `step` seconds while the engine runs.
    static func build(_ log: PerspectiveLog, step: Int = 10) -> CylinderSeries? {
        let idx = stride(from: 0, to: log.sampleCount, by: Swift.max(step, 1))
            .filter { (log.value(PerspectiveChannel.rpm, at: $0) ?? 0) >= 500 }
        guard idx.count >= 6 else { return nil }
        return CylinderSeries(times: idx.map { log.times[$0] },
                              egt: PerspectiveChannel.egt.map { ch in idx.map { log.value(ch, at: $0) } },
                              cht: PerspectiveChannel.cht.map { ch in idx.map { log.value(ch, at: $0) } },
                              step: Double(step))
    }
}

/// Tells the pilot on the iPad when a NEW early warning appears (after an import or app start); quiet otherwise.
enum EarlyWarningNotifier {
    static let defaultsKey = "earlyWarningNotified"

    static func check(summaries: [FlightSummary]) {
        let report = EarlyWarning.analyze(summaries)
        let current = Set(report.findings.map { "\($0.metric.id)|\($0.level?.rawValue ?? "")" })
        let defaults = UserDefaults.standard
        let previous = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
        defaults.set(Array(current), forKey: defaultsKey)
        guard !current.subtracting(previous).isEmpty, let first = report.patterns.first else { return }
        let content = UNMutableNotificationContent()
        content.title = "N63KA early warning"
        content.body = "\(first.level.rawValue): \(first.title)" + (first.cylinder.map { " (cylinder \($0))" } ?? "")
            + ". Open DIAGNOSTICS > Early Warning & Trends."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "early-warning-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil))
    }
}
