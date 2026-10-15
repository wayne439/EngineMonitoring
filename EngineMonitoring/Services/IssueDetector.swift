import Foundation

/// Finds issues in recorded data. Records values only; never assigns a cause.
enum IssueDetector {
    /// One-second bus 1 drop (engine running) treated as worth a look.
    static let voltageDropThreshold = 2.0

    /// Issues in one log. Called when a log is summarized, so every imported log (and the bundled
    /// history built from the SharePoint data_log folder) carries its own issues.
    static func detect(log: PerspectiveLog, phases: [FlightPhase], starts: [StartRecord],
                       largestVolt1Drop: Double?, gpsFixLosses: Int) -> [FlightIssue] {
        let file = log.filename
        var issues: [FlightIssue] = []
        let t = DateFormatter()
        t.locale = Locale(identifier: "en_US_POSIX")
        t.timeZone = log.timeZone
        t.dateFormat = "HH:mm:ss"

        // POH limits (APPROVED) and technique references.
        for e in exceedances(log: log, phases: phases) {
            let approved = e.limit.authority == .approved
            // Ground idle oil pressure is a known pattern on hot days (POH 3A-6), tracked as WATCH.
            let severity: IssueSeverity = !approved ? .info : e.limit.id == "oilp-idle" ? .watch
                : (e.limit.kind == .warning ? .warning : .caution)
            issues.append(FlightIssue(
                kind: (approved ? "limit." : "technique.") + e.limit.id,
                system: system(for: e.limit.metric),
                severity: severity, origin: .engineData, source: file, time: e.first,
                title: e.limit.label,
                detail: "\(e.seconds) s from \(t.string(from: e.first)), extreme \(e.limit.metric.format(e.extreme)) (\(e.limit.source))"))
        }

        // Engine starts.
        for s in starts {
            let caught = (s.rpmAfter30s ?? 0) >= 500
            let volts = s.minVolt1.map { String(format: ", lowest %.1f V cranking", $0) } ?? ""
            if !caught {
                issues.append(FlightIssue(
                    kind: "start.stopped", system: .engineStart, severity: .watch, origin: .engineData, source: file, time: s.time,
                    title: "Engine caught, then stopped within 30 s",
                    detail: "Start at \(t.string(from: s.time)); RPM 30 s later \(Int(s.rpmAfter30s ?? 0))\(volts)"))
            } else if s.crankingEpisodes > 0 {
                issues.append(FlightIssue(
                    kind: "start.extra-cranking", system: .engineStart, severity: .watch, origin: .engineData, source: file, time: s.time,
                    title: "Extra cranking before the engine started",
                    detail: "\(s.crankingEpisodes) cranking attempt\(s.crankingEpisodes == 1 ? "" : "s") without a start before \(t.string(from: s.time))\(volts)"))
            }
            if caught {
                // POH 4-10: oil pressure should show within 30 s (warm) / about 60 s (very cold).
                let after = log.indices(from: s.time, to: s.time.addingTimeInterval(30))
                let oil = log.samples(PerspectiveChannel.oilPressure, in: after).map(\.value)
                if let peak = oil.max(), oil.count >= 20, peak < 10 {
                    issues.append(FlightIssue(
                        kind: "start.oil-pressure", system: .engineStart, severity: .caution, origin: .engineData, source: file, time: s.time,
                        title: "Oil pressure below 10 psi 30 s after start",
                        detail: String(format: "Highest %.0f psi in the first 30 s after the start at %@ (POH 4-10)", peak, t.string(from: s.time))))
                }
            }
        }

        if let drop = largestVolt1Drop, drop >= voltageDropThreshold {
            issues.append(FlightIssue(
                kind: "electrical.voltage-drop", system: .electrical, severity: .watch, origin: .engineData, source: file,
                time: log.start ?? Date(),
                title: "Sudden bus 1 voltage drop",
                detail: String(format: "Largest one-second drop %.1f V with the engine running", drop)))
        }
        if gpsFixLosses > 0 {
            issues.append(FlightIssue(
                kind: "avionics.gps-loss", system: .avionics, severity: .watch, origin: .engineData, source: file,
                time: log.start ?? Date(),
                title: "GPS fix lost in flight",
                detail: "GPS solution lost \(gpsFixLosses) time\(gpsFixLosses == 1 ? "" : "s") while airborne"))
        }
        return issues
    }

    /// Values outside a limit for at least the limit's minimum duration.
    static func exceedances(log: PerspectiveLog, phases: [FlightPhase],
                            limits: [AircraftKnowledge.EngineLimit] = AircraftKnowledge.limits) -> [Exceedance] {
        var exceedances: [Exceedance] = []
        for limit in limits {
            var seconds = 0
            var first: Date?
            var extreme: Double?
            // Contiguous run currently outside the limit; counted once it lasts minDuration.
            var run: [(Date, Double)] = []
            func closeRun() {
                if run.count >= limit.minDuration {
                    seconds += run.count
                    if first == nil { first = run[0].0 }
                    for (_, v) in run {
                        extreme = limit.high != nil ? Swift.max(extreme ?? v, v) : Swift.min(extreme ?? v, v)
                    }
                }
                run.removeAll()
            }
            var graceUntil = Date.distantPast
            for i in 0..<log.sampleCount {
                let phase = phases[i]
                var outside = false
                var value = 0.0
                if limit.startGrace > 0, (log.value(PerspectiveChannel.rpm, at: i) ?? 0) < 500 {
                    graceUntil = log.times[i].addingTimeInterval(TimeInterval(limit.startGrace))
                }
                if phase != .engineOff, log.times[i] > graceUntil, limit.phases.isEmpty || limit.phases.contains(phase),
                   limit.minRPM.map({ (log.value(PerspectiveChannel.rpm, at: i) ?? 0) > $0 }) ?? true,
                   let v = limit.metric.value(in: log, at: i) {
                    value = v
                    outside = (limit.high.map { v > $0 } ?? false) || (limit.low.map { v < $0 } ?? false)
                }
                if outside { run.append((log.times[i], value)) } else { closeRun() }
            }
            closeRun()
            if seconds > 0, let first, let extreme {
                exceedances.append(Exceedance(limit: limit, seconds: seconds, first: first, extreme: extreme))
            }
        }
        // A warning makes the matching caution redundant (same metric and direction).
        return exceedances.filter { e in
            !(e.limit.kind == .caution && exceedances.contains {
                $0.limit.kind == .warning && $0.limit.metric == e.limit.metric && ($0.limit.high != nil) == (e.limit.high != nil)
            })
        }
    }

    static func system(for metric: FlightMetric) -> DiagnosticSystem {
        switch metric {
        case .volt1, .volt2, .amps: .electrical
        default: .engine
        }
    }

    // MARK: - Trends against N63KA's own normal

    /// Directions that matter for each metric (the other direction is not a concern).
    private static let trendWatch: [FlightMetric: Bool] = [   // true = high is the concern
        .oilTemp: true, .oilPressure: false, .chtMax: true, .egtSpread: true,
        .cht1: true, .cht2: true, .cht3: true, .cht4: true, .cht5: true, .cht6: true,
        .volt1: false, .volt2: false, .tit: true,
    ]
    /// How far outside the 10th-90th percentile band (in band widths) before a trend is listed.
    static let trendThreshold = 0.5

    private static let cylinderMetrics: Set<FlightMetric> = [.chtMax, .cht1, .cht2, .cht3, .cht4, .cht5, .cht6]

    /// Climb/cruise medians clearly outside N63KA's normal, for every flight against all the others.
    /// The CHT metrics are combined into one "CHT" trend per flight (the cylinder furthest outside).
    static func trendIssues(_ summaries: [FlightSummary]) -> [FlightIssue] {
        let flights = summaries.filter(\.isFlight)
        guard flights.count > Baseline.minimumFlights else { return [] }
        var issues: [FlightIssue] = []
        for f in flights {
            let baseline = Baseline.build(from: flights.filter { $0.filename != f.filename })
            for phase in FlightPhase.compared {
                var worstCHT: (Deviation, FlightMetric)?
                for (metric, highIsBad) in trendWatch.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    guard let s = f.stats[phase]?[metric],
                          let r = baseline.range(phase, metric, oat: f.stats[phase]?[.oat]?.p50) else { continue }
                    let d = Deviation(phase: phase, metric: metric, value: s.p50, range: r)
                    guard (highIsBad ? s.p50 > r.high : s.p50 < r.low), d.severity >= trendThreshold else { continue }
                    if cylinderMetrics.contains(metric) {
                        if metric != .chtMax, worstCHT.map({ d.severity > $0.0.severity }) ?? true { worstCHT = (d, metric) }
                        continue
                    }
                    issues.append(trendIssue(f, d, metric, kindMetric: metric.rawValue, high: highIsBad))
                }
                if let (d, metric) = worstCHT {
                    issues.append(trendIssue(f, d, metric, kindMetric: "cht", high: true))
                }
            }
        }
        return issues
    }

    private static func trendIssue(_ f: FlightSummary, _ d: Deviation, _ metric: FlightMetric, kindMetric: String, high: Bool) -> FlightIssue {
        FlightIssue(
            kind: "trend.\(d.phase.rawValue).\(kindMetric).\(high ? "high" : "low")",
            system: system(for: metric), severity: .watch, origin: .trend, source: f.filename, time: f.start,
            title: "\(d.phase.rawValue) \(metric.sentenceLabel) \(high ? "higher" : "lower") than usual",
            detail: "\(metric.label) median \(metric.format(d.value)); N63KA usual \(metric.format(d.range.low))-\(metric.format(d.range.high))"
                + (d.range.oat.map { String(format: " for OAT %.0f °C", $0) } ?? "")
                + (f.departure.map { ", from \($0)" } ?? "") + " (\(d.range.flights) flights)")
    }
}
