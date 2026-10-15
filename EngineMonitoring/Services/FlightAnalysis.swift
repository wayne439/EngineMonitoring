import Foundation

/// Values the post-flight analysis tracks, derived from Perspective log columns.
enum FlightMetric: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable, Hashable {
    case rpm, manifoldPressure, fuelFlow, oilPressure, oilTemp, tit, tit1, tit2, volt1, volt2, amps, oat
    case chtMax, egtSpread
    case cht1, cht2, cht3, cht4, cht5, cht6

    var label: String {
        switch self {
        case .rpm: "RPM"
        case .manifoldPressure: "Manifold pressure"
        case .fuelFlow: "Fuel flow"
        case .oilPressure: "Oil pressure"
        case .oilTemp: "Oil temperature"
        case .tit: "TIT (hotter of 1 and 2)"
        case .tit1: "TIT 1"
        case .tit2: "TIT 2"
        case .oat: "OAT"
        case .volt1: "Bus 1 voltage"
        case .volt2: "Bus 2 voltage"
        case .amps: "Alternator current"
        case .chtMax: "Hottest CHT"
        case .egtSpread: "EGT spread"
        case .cht1: "CHT cyl 1"
        case .cht2: "CHT cyl 2"
        case .cht3: "CHT cyl 3"
        case .cht4: "CHT cyl 4"
        case .cht5: "CHT cyl 5"
        case .cht6: "CHT cyl 6"
        }
    }

    var unit: String {
        switch self {
        case .rpm: ""
        case .manifoldPressure: " inHg"
        case .fuelFlow: " gph"
        case .oilPressure: " psi"
        case .oat: " °C"
        case .oilTemp, .tit, .tit1, .tit2, .chtMax, .egtSpread, .cht1, .cht2, .cht3, .cht4, .cht5, .cht6: " °F"
        case .volt1, .volt2: " V"
        case .amps: " A"
        }
    }

    var digits: Int {
        switch self {
        case .manifoldPressure, .fuelFlow, .volt1, .volt2, .amps: 1
        default: 0
        }
    }

    /// Label for use inside a sentence: "oil temperature", but "TIT", "CHT cyl 3", "EGT spread".
    var sentenceLabel: String {
        let l = label
        guard l.count > 1, l.dropFirst().first?.isLowercase == true else { return l }
        return l.prefix(1).lowercased() + l.dropFirst()
    }

    func format(_ v: Double) -> String { String(format: "%.\(digits)f", v) + unit }

    /// Reads this metric from one log sample.
    func value(in log: PerspectiveLog, at i: Int) -> Double? {
        switch self {
        case .rpm: return log.value(PerspectiveChannel.rpm, at: i)
        case .manifoldPressure: return log.value(PerspectiveChannel.manifoldPressure, at: i)
        case .fuelFlow: return log.value(PerspectiveChannel.fuelFlow, at: i)
        case .oilPressure: return log.value(PerspectiveChannel.oilPressure, at: i)
        case .oilTemp: return log.value(PerspectiveChannel.oilTemp, at: i)
        case .tit:
            // The TN engine has two turbochargers; the hotter TIT is the one that matters.
            let a = log.value(PerspectiveChannel.tit1, at: i), b = log.value(PerspectiveChannel.tit2, at: i)
            switch (a, b) {
            case let (x?, y?): return Swift.max(x, y)
            default: return a ?? b
            }
        case .tit1: return log.value(PerspectiveChannel.tit1, at: i)
        case .tit2: return log.value(PerspectiveChannel.tit2, at: i)
        case .oat: return log.value(PerspectiveChannel.oat, at: i)
        case .volt1: return log.value(PerspectiveChannel.volt1, at: i)
        case .volt2: return log.value(PerspectiveChannel.volt2, at: i)
        case .amps: return log.value(PerspectiveChannel.amp1, at: i)
        case .chtMax: return PerspectiveChannel.cht.compactMap { log.value($0, at: i) }.max()
        case .egtSpread:
            let v = PerspectiveChannel.egt.compactMap { log.value($0, at: i) }
            guard v.count >= 2, let lo = v.min(), let hi = v.max() else { return nil }
            return hi - lo
        case .cht1: return log.value(PerspectiveChannel.cht[0], at: i)
        case .cht2: return log.value(PerspectiveChannel.cht[1], at: i)
        case .cht3: return log.value(PerspectiveChannel.cht[2], at: i)
        case .cht4: return log.value(PerspectiveChannel.cht[3], at: i)
        case .cht5: return log.value(PerspectiveChannel.cht[4], at: i)
        case .cht6: return log.value(PerspectiveChannel.cht[5], at: i)
        }
    }
}

enum FlightPhase: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable, Hashable {
    case engineOff = "Engine off"
    case ground = "Ground (engine running)"
    case climb = "Climb"
    case cruise = "Cruise"
    case descent = "Descent"

    /// Phases compared against the aircraft's normal ranges.
    static let compared: [FlightPhase] = [.climb, .cruise]
}

enum PhaseClassifier {
    /// Classifies every sample. Vertical speed is smoothed over 15 s so turbulence does not flip phases.
    static func classify(_ log: PerspectiveLog) -> [FlightPhase] {
        let n = log.sampleCount
        let vspd: [Double?] = (0..<n).map { log.value("VSpd", at: $0) }
        var phases = [FlightPhase](repeating: .engineOff, count: n)
        for i in 0..<n {
            let rpm = log.value(PerspectiveChannel.rpm, at: i) ?? 0
            guard rpm >= 500 else { phases[i] = .engineOff; continue }
            let ias = log.value(PerspectiveChannel.ias, at: i) ?? 0
            guard ias >= 50 else { phases[i] = .ground; continue }
            let window = vspd[max(0, i - 7)...min(n - 1, i + 7)].compactMap { $0 }
            let vs = window.isEmpty ? 0 : window.reduce(0, +) / Double(window.count)
            phases[i] = vs > 300 ? .climb : (vs < -300 ? .descent : .cruise)
        }
        return phases
    }
}

/// Distribution of one metric in one phase of one flight.
struct MetricStats: Codable, Hashable, Sendable {
    let count: Int
    let p05: Double
    let p50: Double
    let p95: Double
    let max: Double

    init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        count = s.count
        p05 = Self.percentile(s, 0.05)
        p50 = Self.percentile(s, 0.50)
        p95 = Self.percentile(s, 0.95)
        max = s.last!
    }

    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }
}

/// One engine start found in a log (RPM rising from below 100 to 500 or more).
struct StartRecord: Codable, Hashable, Sendable {
    let time: Date
    /// RPM rose above 100 but fell back without reaching 500, since the engine was last stopped.
    let crankingEpisodes: Int
    /// Lowest bus 1 voltage in the 30 s before the start.
    let minVolt1: Double?
    /// Peak fuel flow within 30 s either side of the start.
    let peakFuelFlow: Double?
    /// RPM 30 s after the start.
    let rpmAfter30s: Double?
    /// EGT rise per cylinder (1-6) in the first 30 s; nil where not recorded.
    let egtRise: [Double?]

    var weakestCylinder: (cylinder: Int, rise: Double)? {
        let pairs = egtRise.enumerated().compactMap { i, v in v.map { (i + 1, $0) } }
        return pairs.min { $0.1 < $1.1 }.map { (cylinder: $0.0, rise: $0.1) }
    }
}

/// An autopilot engage or disengage recorded in a log.
struct AFCSChange: Codable, Hashable, Sendable {
    let time: Date
    let engaged: Bool
}

/// Compact description of one flight, kept for every imported log. Baselines and the
/// per-system history screens are built from these, so logs need not be re-parsed.
struct FlightSummary: Codable, Hashable, Sendable {
    /// Bumped when the summary gains fields; older summaries are rebuilt from their logs.
    static let currentVersion = 9

    let version: Int
    let filename: String
    let start: Date
    let end: Date
    /// Seconds spent in each phase.
    let phaseSeconds: [FlightPhase: Int]
    /// phase -> metric -> stats (only phases with enough samples).
    let stats: [FlightPhase: [FlightMetric: MetricStats]]
    // System highlights (version 2)
    let starts: [StartRecord]
    let afcsChanges: [AFCSChange]
    /// Lowest bus voltages while the engine ran above 1,000 RPM.
    let minVolt1Running: Double?
    let minVolt2Running: Double?
    /// Largest one-second bus 1 voltage drop while the engine ran.
    let largestVolt1Drop: Double?
    /// Times the GPS fix changed from a solution to no solution while airborne.
    let gpsFixLosses: Int
    // Version 3
    /// Issues found in this log (POH limits, starts, electrical, GPS). Trends are added later from all flights.
    let issues: [FlightIssue]
    /// Log's offset from UTC in seconds (for showing local times of bundled flights).
    let utcOffsetSeconds: Int?
    // Version 5
    /// Takeoff and landing quality (TechniqueAnalyzer).
    let landings: [LandingRecord]
    let takeoffs: [TakeoffRecord]
    // Version 6
    /// Exhaust-valve watch (ValveWatch); nil for summaries built before v0.9.3.
    let valveWatch: ValveWatchResult?
    // Version 7
    /// Probe and wiring check (ProbeCheck); nil for summaries built before v0.9.5.
    let probeCheck: ProbeCheckResult?
    // Version 8
    /// Steady-cruise engine values for the early warning and trend charts; nil for summaries built before v0.9.6.
    let engineTrend: EngineTrendMetrics?
    // Version 9
    /// Run-up mag check, GAMI lean test and the flight card (report card, turbo and induction); nil before v0.9.7.
    let engineChecks: EngineCheckResult?

    init(filename: String, start: Date, end: Date, phaseSeconds: [FlightPhase: Int],
         stats: [FlightPhase: [FlightMetric: MetricStats]], starts: [StartRecord] = [], afcsChanges: [AFCSChange] = [],
         minVolt1Running: Double? = nil, minVolt2Running: Double? = nil, largestVolt1Drop: Double? = nil, gpsFixLosses: Int = 0,
         issues: [FlightIssue] = [], utcOffsetSeconds: Int? = nil,
         landings: [LandingRecord] = [], takeoffs: [TakeoffRecord] = [], valveWatch: ValveWatchResult? = nil,
         probeCheck: ProbeCheckResult? = nil, engineTrend: EngineTrendMetrics? = nil,
         engineChecks: EngineCheckResult? = nil) {
        self.version = Self.currentVersion
        self.filename = filename
        self.start = start
        self.end = end
        self.phaseSeconds = phaseSeconds
        self.stats = stats
        self.starts = starts
        self.afcsChanges = afcsChanges
        self.minVolt1Running = minVolt1Running
        self.minVolt2Running = minVolt2Running
        self.largestVolt1Drop = largestVolt1Drop
        self.gpsFixLosses = gpsFixLosses
        self.issues = issues
        self.utcOffsetSeconds = utcOffsetSeconds
        self.landings = landings
        self.takeoffs = takeoffs
        self.valveWatch = valveWatch
        self.probeCheck = probeCheck
        self.engineTrend = engineTrend
        self.engineChecks = engineChecks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        filename = try c.decode(String.self, forKey: .filename)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        phaseSeconds = try c.decode([FlightPhase: Int].self, forKey: .phaseSeconds)
        stats = try c.decode([FlightPhase: [FlightMetric: MetricStats]].self, forKey: .stats)
        starts = try c.decodeIfPresent([StartRecord].self, forKey: .starts) ?? []
        afcsChanges = try c.decodeIfPresent([AFCSChange].self, forKey: .afcsChanges) ?? []
        minVolt1Running = try c.decodeIfPresent(Double.self, forKey: .minVolt1Running)
        minVolt2Running = try c.decodeIfPresent(Double.self, forKey: .minVolt2Running)
        largestVolt1Drop = try c.decodeIfPresent(Double.self, forKey: .largestVolt1Drop)
        gpsFixLosses = try c.decodeIfPresent(Int.self, forKey: .gpsFixLosses) ?? 0
        issues = try c.decodeIfPresent([FlightIssue].self, forKey: .issues) ?? []
        utcOffsetSeconds = try c.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)
        landings = try c.decodeIfPresent([LandingRecord].self, forKey: .landings) ?? []
        takeoffs = try c.decodeIfPresent([TakeoffRecord].self, forKey: .takeoffs) ?? []
        valveWatch = try c.decodeIfPresent(ValveWatchResult.self, forKey: .valveWatch)
        probeCheck = try c.decodeIfPresent(ProbeCheckResult.self, forKey: .probeCheck)
        engineTrend = try c.decodeIfPresent(EngineTrendMetrics.self, forKey: .engineTrend)
        engineChecks = try c.decodeIfPresent(EngineCheckResult.self, forKey: .engineChecks)
    }

    var timeZone: TimeZone { utcOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current }

    /// Departure airport from the Perspective file name (log_YYMMDD_HHMMSS_KPRC.csv), if recorded.
    var departure: String? { Self.departure(fromFilename: filename) }

    static func departure(fromFilename filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        guard let last = stem.split(separator: "_").last, last.count >= 3, last.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let s = String(last)
        return s.allSatisfy(\.isNumber) ? nil : s
    }

    var isCurrent: Bool { version >= Self.currentVersion }
    var airborneSeconds: Int { (phaseSeconds[.climb] ?? 0) + (phaseSeconds[.cruise] ?? 0) + (phaseSeconds[.descent] ?? 0) }
    var isFlight: Bool { airborneSeconds >= 300 }
    var afcsDisengagements: Int { afcsChanges.filter { !$0.engaged }.count }

    static let minSamplesPerPhase = 60
}

enum FlightSummarizer {
    static func summarize(_ log: PerspectiveLog, phases: [FlightPhase]? = nil) -> FlightSummary {
        let phases = phases ?? PhaseClassifier.classify(log)
        var seconds: [FlightPhase: Int] = [:]
        var buckets: [FlightPhase: [FlightMetric: [Double]]] = [:]
        for i in 0..<log.sampleCount {
            let phase = phases[i]
            seconds[phase, default: 0] += 1
            guard phase != .engineOff else { continue }
            for metric in FlightMetric.allCases {
                if let v = metric.value(in: log, at: i) { buckets[phase, default: [:]][metric, default: []].append(v) }
            }
        }
        var stats: [FlightPhase: [FlightMetric: MetricStats]] = [:]
        for (phase, metrics) in buckets {
            for (metric, values) in metrics where values.count >= FlightSummary.minSamplesPerPhase {
                stats[phase, default: [:]][metric] = MetricStats(values)
            }
        }
        // Electrical and GPS highlights.
        var minV1: Double?, minV2: Double?, maxDrop: Double?
        var lastV1: (index: Int, value: Double)?
        var gpsLosses = 0
        var lastFixOK: Bool?
        var afcs: [AFCSChange] = []
        var lastAFCS: Double?
        for i in 0..<log.sampleCount {
            let rpm = log.value(PerspectiveChannel.rpm, at: i) ?? 0
            if rpm > 1000 {
                if let v = log.value(PerspectiveChannel.volt1, at: i) {
                    minV1 = Swift.min(minV1 ?? v, v)
                    if let last = lastV1, last.index == i - 1, last.value - v > (maxDrop ?? 0) { maxDrop = last.value - v }
                    lastV1 = (i, v)
                }
                if let v = log.value(PerspectiveChannel.volt2, at: i) { minV2 = Swift.min(minV2 ?? v, v) }
            }
            if phases[i] == .climb || phases[i] == .cruise || phases[i] == .descent,
               let fix = log.textValue(PerspectiveChannel.gpsFix, at: i) {
                let ok = !fix.lowercased().contains("nosoln")
                if lastFixOK == true && !ok { gpsLosses += 1 }
                lastFixOK = ok
            }
            if let on = log.value(PerspectiveChannel.afcsOn, at: i) {
                if let prev = lastAFCS, prev != on, afcs.count < 100 { afcs.append(AFCSChange(time: log.times[i], engaged: on >= 1)) }
                lastAFCS = on
            }
        }
        let starts = starts(in: log)
        let issues = IssueDetector.detect(log: log, phases: phases, starts: starts,
                                          largestVolt1Drop: maxDrop, gpsFixLosses: gpsLosses)
        let technique = TechniqueAnalyzer.analyze(log, departure: FlightSummary.departure(fromFilename: log.filename))
        let valves = ValveWatch.analyze(log, phases: phases)
        let probes = ProbeCheck.analyze(log, phases: phases)
        let trend = EngineTrendMetrics.compute(log, phases: phases)
        let checks = EngineChecks.analyze(log, phases: phases)
        return FlightSummary(filename: log.filename, start: log.start ?? Date(), end: log.end ?? Date(),
                             phaseSeconds: seconds, stats: stats, starts: starts, afcsChanges: afcs,
                             minVolt1Running: minV1, minVolt2Running: minV2, largestVolt1Drop: maxDrop,
                             gpsFixLosses: gpsLosses, issues: issues + ValveWatch.issues(valves, log: log) + ProbeCheck.issues(probes, log: log)
                                 + EngineChecks.issues(checks, log: log),
                             utcOffsetSeconds: log.timeZone.secondsFromGMT(for: log.start ?? Date()),
                             landings: technique.landings, takeoffs: technique.takeoffs, valveWatch: valves,
                             probeCheck: probes, engineTrend: trend, engineChecks: checks)
    }

    /// Every engine start in a log: RPM from below 100 to 500 or more.
    static func starts(in log: PerspectiveLog) -> [StartRecord] {
        var records: [StartRecord] = []
        var stopped = true
        var episodes = 0
        var inEpisode = false
        var seenFirst = false
        for i in 0..<log.sampleCount {
            guard let rpm = log.value(PerspectiveChannel.rpm, at: i) else { continue }
            if !seenFirst {
                // A log that begins with the engine already running does not contain that start.
                seenFirst = true
                if rpm >= 500 { stopped = false; continue }
            }
            if rpm < 100 {
                if inEpisode { episodes += 1 }
                inEpisode = false
                stopped = true
                continue
            }
            if stopped && rpm >= 500 {
                records.append(startRecord(log: log, index: i, episodes: episodes))
                stopped = false
                inEpisode = false
                episodes = 0
                continue
            }
            if stopped && rpm >= 100 { inEpisode = true }
        }
        return records
    }

    private static func startRecord(log: PerspectiveLog, index: Int, episodes: Int) -> StartRecord {
        let t = log.times[index]
        let crank = log.indices(from: t.addingTimeInterval(-30), to: t)
        let after = log.indices(from: t, to: t.addingTimeInterval(30))
        let around = log.indices(from: t.addingTimeInterval(-30), to: t.addingTimeInterval(30))
        let minV = log.samples(PerspectiveChannel.volt1, in: crank).map(\.value).min()
        let ff = log.samples(PerspectiveChannel.fuelFlow, in: around).map(\.value).max()
        let rpm30 = log.samples(PerspectiveChannel.rpm, in: after).last?.value
        let rise: [Double?] = PerspectiveChannel.egt.map { ch in
            guard let base = log.value(ch, at: index), let peak = log.samples(ch, in: after).map(\.value).max() else { return nil }
            return peak - base
        }
        return StartRecord(time: t, crankingEpisodes: episodes, minVolt1: minV, peakFuelFlow: ff, rpmAfter30s: rpm30, egtRise: rise)
    }
}

/// the aircraft's normal range for each metric and phase, learned from past flights.
struct Baseline: Hashable, Sendable {
    struct Range: Codable, Hashable, Sendable {
        /// 10th and 90th percentile of the per-flight medians.
        let low: Double
        let high: Double
        /// Median of per-flight medians.
        let typical: Double
        let flights: Int
        /// Set when the range was adjusted for outside air temperature.
        var oat: Double? = nil
    }

    /// Phase median of a metric as a straight line of the phase median OAT: value = a + b * OAT,
    /// with the 10th-90th percentile of the residuals. Oil and cylinder temperatures rise on hot days,
    /// so comparing them with flights at a similar OAT avoids flagging every summer flight.
    struct OATModel: Hashable, Sendable {
        let a: Double
        let b: Double
        let residualLow: Double
        let residualHigh: Double
        let flights: Int
        func expected(at oat: Double) -> Double { a + b * oat }
        func range(at oat: Double) -> Range {
            let e = expected(at: oat)
            return Range(low: e + residualLow, high: e + residualHigh, typical: e, flights: flights, oat: oat)
        }
    }

    /// Metrics compared at the flight's OAT once enough flights cover a useful OAT spread.
    static let oatAdjusted: Set<FlightMetric> = [.oilTemp, .chtMax, .cht1, .cht2, .cht3, .cht4, .cht5, .cht6]
    static let minimumOATFlights = 8
    static let minimumOATSpread = 8.0  // °C between the 10th and 90th percentile flight

    let flightCount: Int
    let ranges: [FlightPhase: [FlightMetric: Range]]
    var oatModels: [FlightPhase: [FlightMetric: OATModel]] = [:]

    /// Minimum number of past flights before a range is used to flag anything.
    static let minimumFlights = 5

    /// The range to compare a flight with: OAT-adjusted when possible, otherwise the plain range.
    func range(_ phase: FlightPhase, _ metric: FlightMetric, oat: Double?) -> Range? {
        if let oat, let m = oatModels[phase]?[metric] { return m.range(at: oat) }
        return ranges[phase]?[metric]
    }

    static func build(from summaries: [FlightSummary]) -> Baseline {
        let flights = summaries.filter(\.isFlight)
        var ranges: [FlightPhase: [FlightMetric: Range]] = [:]
        var models: [FlightPhase: [FlightMetric: OATModel]] = [:]
        for phase in FlightPhase.compared {
            for metric in FlightMetric.allCases {
                let medians = flights.compactMap { $0.stats[phase]?[metric]?.p50 }.sorted()
                guard medians.count >= minimumFlights else { continue }
                ranges[phase, default: [:]][metric] = Range(low: MetricStats.percentile(medians, 0.10),
                                                            high: MetricStats.percentile(medians, 0.90),
                                                            typical: MetricStats.percentile(medians, 0.50),
                                                            flights: medians.count)
            }
            for metric in oatAdjusted {
                let pairs = flights.compactMap { f -> (Double, Double)? in
                    guard let o = f.stats[phase]?[.oat]?.p50, let v = f.stats[phase]?[metric]?.p50 else { return nil }
                    return (o, v)
                }
                if let m = fit(pairs) { models[phase, default: [:]][metric] = m }
            }
        }
        return Baseline(flightCount: flights.count, ranges: ranges, oatModels: models)
    }

    static func fit(_ pairs: [(Double, Double)]) -> OATModel? {
        guard pairs.count >= minimumOATFlights else { return nil }
        let oats = pairs.map(\.0).sorted()
        guard MetricStats.percentile(oats, 0.9) - MetricStats.percentile(oats, 0.1) >= minimumOATSpread else { return nil }
        let n = Double(pairs.count)
        let mx = pairs.reduce(0) { $0 + $1.0 } / n, my = pairs.reduce(0) { $0 + $1.1 } / n
        let sxx = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
        guard sxx > 0 else { return nil }
        let b = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
        let a = my - b * mx
        let residuals = pairs.map { $0.1 - (a + b * $0.0) }.sorted()
        return OATModel(a: a, b: b, residualLow: MetricStats.percentile(residuals, 0.10),
                        residualHigh: MetricStats.percentile(residuals, 0.90), flights: pairs.count)
    }
}

/// A recorded value outside a limit, with how long and when.
struct Exceedance: Hashable, Sendable {
    let limit: AircraftKnowledge.EngineLimit
    let seconds: Int
    let first: Date
    let extreme: Double
}

/// A flight-phase median outside the aircraft's normal range.
struct Deviation: Hashable, Sendable {
    let phase: FlightPhase
    let metric: FlightMetric
    let value: Double
    let range: Baseline.Range

    var direction: String { value > range.high ? "above" : "below" }

    /// How far outside the range, in units of the range's own width (minimum width 1 unit).
    var severity: Double {
        let width = max(range.high - range.low, 1)
        return value > range.high ? (value - range.high) / width : (range.low - value) / width
    }
}

struct FlightReport: Sendable {
    let summary: FlightSummary
    let exceedances: [Exceedance]
    let deviations: [Deviation]
    let baselineFlights: Int
    let markers: [DiagnosticEvent]
    let timeZone: TimeZone
    /// Every cylinder's EGT and CHT through the flight, for the charts.
    var cylinderSeries: CylinderSeries? = nil
    /// Early warning across all flights, this one included.
    var earlyWarning: EarlyWarningReport? = nil

    /// Builds the report for one log. `history` = summaries of OTHER flights (this one is excluded).
    static func build(log: PerspectiveLog, history: [FlightSummary], markers: [DiagnosticEvent] = [],
                      limits: [AircraftKnowledge.EngineLimit] = AircraftKnowledge.limits,
                      timeZone: TimeZone = .current) -> FlightReport {
        let phases = PhaseClassifier.classify(log)
        let summary = FlightSummarizer.summarize(log, phases: phases)
        let baseline = Baseline.build(from: history.filter { $0.filename != log.filename })

        let exceedances = IssueDetector.exceedances(log: log, phases: phases, limits: limits)

        var deviations: [Deviation] = []
        for phase in FlightPhase.compared {
            for (metric, stats) in summary.stats[phase] ?? [:] {
                guard metric != .oat,
                      let range = baseline.range(phase, metric, oat: summary.stats[phase]?[.oat]?.p50) else { continue }
                if stats.p50 > range.high || stats.p50 < range.low {
                    deviations.append(Deviation(phase: phase, metric: metric, value: stats.p50, range: range))
                }
            }
        }
        deviations.sort { $0.severity > $1.severity }

        let inFlight = markers.filter { log.covers($0.timestamp, tolerance: 120) }
        return FlightReport(summary: summary, exceedances: exceedances, deviations: deviations,
                            baselineFlights: baseline.flightCount, markers: inFlight, timeZone: timeZone,
                            cylinderSeries: CylinderSeries.build(log),
                            earlyWarning: EarlyWarning.analyze(history.filter { $0.filename != log.filename } + [summary]))
    }

    var approvedExceedances: [Exceedance] { exceedances.filter { $0.limit.authority == .approved } }
    var techniqueNotes: [Exceedance] { exceedances.filter { $0.limit.authority != .approved } }

    /// Plain-text report to share (e.g. upload to the owner's records for the Claude post-flight review).
    func markdown() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let t = DateFormatter()
        t.locale = Locale(identifier: "en_US_POSIX")
        t.timeZone = timeZone
        t.dateFormat = "HH:mm:ss"
        func minutes(_ s: Int) -> String { "\(s / 60) min" }

        var md = "# Post-flight report\n\n"
        md += "- Log: \(summary.filename)\n"
        md += "- From \(f.string(from: summary.start)) to \(t.string(from: summary.end)) (\(timeZone.identifier))\n"
        let phaseLine = FlightPhase.allCases.compactMap { p in summary.phaseSeconds[p].map { "\(p.rawValue) \(minutes($0))" } }
        md += "- Phases: " + phaseLine.joined(separator: ", ") + "\n"
        md += "- Compared with \(baselineFlights) earlier flights\n\n"

        md += "## Limits (from your Aircraft Profile)\n\n"
        if approvedExceedances.isEmpty {
            md += "No recorded value outside the POH limits checked by the app.\n\n"
        } else {
            for e in approvedExceedances {
                md += "- **\(e.limit.kind.rawValue): \(e.limit.label)** for \(e.seconds) s, first at \(t.string(from: e.first)); extreme \(e.limit.metric.format(e.extreme)) (\(e.limit.source))\n"
            }
            md += "\n"
        }
        md += "TIT and manifold-pressure limits are not checked: follow your POH/AFM and any turbo supplement.\n\n"

        md += "## Compared with this aircraft's normal\n\n"
        if baselineFlights < Baseline.minimumFlights {
            md += "Not enough earlier flights yet (\(baselineFlights) of \(Baseline.minimumFlights)).\n\n"
        } else if deviations.isEmpty {
            md += "Every climb and cruise median is inside this aircraft's usual range.\n\n"
        } else {
            for d in deviations {
                let at = d.range.oat.map { String(format: " for OAT %.0f °C", $0) } ?? ""
                md += "- \(d.phase.rawValue) \(d.metric.label): median \(d.metric.format(d.value)), \(d.direction) the usual \(d.metric.format(d.range.low))-\(d.metric.format(d.range.high))\(at) (\(d.range.flights) flights)\n"
            }
            md += "\n"
        }

        if !techniqueNotes.isEmpty {
            md += "## Technique references (EXPERIENCE, not limits)\n\n"
            for e in techniqueNotes {
                md += "- \(e.limit.label): \(e.seconds) s, peak \(e.limit.metric.format(e.extreme)) (\(e.limit.source))\n"
            }
            md += "\n"
        }

        if !summary.takeoffs.isEmpty || !summary.landings.isEmpty {
            md += "## Takeoff and landing\n\n"
            for tk in summary.takeoffs {
                md += "- Takeoff \(t.string(from: tk.time)): \(tk.score.passed)/\(tk.score.of) checks. "
                md += tk.checks.map { "\($0.name) \($0.value)\($0.pass == false ? " (outside target)" : "")" }.joined(separator: "; ") + "\n"
            }
            for l in summary.landings {
                md += "- Landing \(t.string(from: l.touchdown)): \(l.score.passed)/\(l.score.of) checks. "
                md += l.checks.map { "\($0.name) \($0.value)\($0.pass == false ? " (outside target)" : "")" }.joined(separator: "; ") + "\n"
            }
            md += "\n\(TechniqueStandards.source)\n\n"
        }
        md += "## Valve watch (exhaust valves)\n\n"
        md += ValveWatch.markdown(summary.valveWatch, timeZone: timeZone)
        md += "## Probes and wiring\n\n"
        md += ProbeCheck.markdown(summary.probeCheck, timeZone: timeZone)
        md += "## Run-up and lean test\n\n"
        md += EngineChecks.markdown(summary.engineChecks, timeZone: timeZone)
        if let ew = earlyWarning {
            md += "## Early warning (all flights)\n\n"
            md += EarlyWarning.markdown(ew)
        }
        if let t = summary.stats[.cruise]?[.tit] {
            md += "## Cruise TIT\n\n"
            md += String(format: "Hotter TIT median %.0f °F (TIT 1 %.0f, TIT 2 %.0f) vs your target of about %.0f °F. ", t.p50,
                         summary.stats[.cruise]?[.tit1]?.p50 ?? .nan, summary.stats[.cruise]?[.tit2]?.p50 ?? .nan, AircraftKnowledge.cruiseTITTarget)
            md += "\(AircraftKnowledge.cruiseTITTargetSource).\n\n"
        }
        md += "## Phase values (median, 95th percentile, max)\n\n"
        for phase in FlightPhase.compared {
            guard let stats = summary.stats[phase] else { continue }
            md += "### \(phase.rawValue)\n\n| Metric | Median | P95 | Max |\n| --- | --- | --- | --- |\n"
            for metric in FlightMetric.allCases {
                guard let s = stats[metric] else { continue }
                md += "| \(metric.label) | \(metric.format(s.p50)) | \(metric.format(s.p95)) | \(metric.format(s.max)) |\n"
            }
            md += "\n"
        }

        if !markers.isEmpty {
            md += "## Pilot event markers\n\n"
            for m in markers {
                md += "- \(t.string(from: m.timestamp)) \(m.detailsEntered ? m.system.rawValue : "marker"): \(m.note.isEmpty ? "no note" : m.note)\n"
            }
            md += "\n"
        }
        md += "_Recorded values only. No cause is assigned. The POH, approved checklists and your A&P govern._\n"
        return md
    }
}
