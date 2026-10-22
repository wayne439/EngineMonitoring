import Foundation

// MARK: - Report card

/// One line of a flight's report card: the value and where it sits among the aircraft's earlier flights.
struct ReportCardRow: Identifiable, Hashable, Sendable {
    let metric: ReportCard.Metric
    let value: Double
    /// 0-100: share of earlier flights with a lower value (ties count half). Nil with fewer than 5 earlier flights.
    let percentile: Double?
    let low: Double?
    let median: Double?
    let high: Double?
    let earlier: Int

    var id: String { metric.id }
}

/// About twenty numbers per flight, each with its percentile against the aircraft's own earlier flights, so "is this normal
/// for this airplane?" has an answer at a glance. Same numbers as the reference implementation.
enum ReportCard {
    struct Metric: Hashable, Sendable {
        let id: String
        let group: String
        let label: String
        let unit: String
        let digits: Int
        /// true: lower is better; false: higher is better; nil: neither (only unusual is interesting).
        let lowerIsBetter: Bool?

        func format(_ v: Double) -> String { String(format: "%.\(digits)f", v) + (unit.isEmpty ? "" : " " + unit) }
    }

    static let minEarlier = 5

    static let metrics: [Metric] = [
        Metric(id: "takeoffRPM", group: "Takeoff", label: "Full-power RPM", unit: "RPM", digits: 0, lowerIsBetter: nil),
        Metric(id: "takeoffMAP", group: "Takeoff", label: "Manifold pressure", unit: "inHg", digits: 1, lowerIsBetter: nil),
        Metric(id: "takeoffFF", group: "Takeoff", label: "Fuel flow", unit: "gph", digits: 1, lowerIsBetter: nil),
        Metric(id: "climbMaxCHT", group: "Climb", label: "Hottest CHT", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "climbMaxTIT", group: "Climb", label: "Hottest TIT", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "climbRate", group: "Climb", label: "Climb rate", unit: "fpm", digits: 0, lowerIsBetter: false),
        Metric(id: "cruisePower", group: "Cruise", label: "Power", unit: "%", digits: 0, lowerIsBetter: nil),
        Metric(id: "cruiseTAS", group: "Cruise", label: "True airspeed", unit: "kt", digits: 0, lowerIsBetter: false),
        Metric(id: "cruiseFF", group: "Cruise", label: "Fuel flow", unit: "gph", digits: 1, lowerIsBetter: nil),
        Metric(id: "cruiseNMPG", group: "Cruise", label: "Miles per gallon", unit: "nm/gal", digits: 1, lowerIsBetter: false),
        Metric(id: "cruiseCHTAvg", group: "Cruise", label: "Average CHT", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "cruiseCHTMax", group: "Cruise", label: "Hottest CHT", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "cruiseCHTSpread", group: "Cruise", label: "CHT spread", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "cruiseEGTSpread", group: "Cruise", label: "EGT spread", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "cruiseTIT", group: "Cruise", label: "Hotter TIT", unit: "°F", digits: 0, lowerIsBetter: nil),
        Metric(id: "cruiseOilT", group: "Oil And Electrical", label: "Oil temperature (cruise)", unit: "°F", digits: 0, lowerIsBetter: nil),
        Metric(id: "cruiseOilP", group: "Oil And Electrical", label: "Oil pressure (cruise)", unit: "psi", digits: 1, lowerIsBetter: nil),
        Metric(id: "oilTMax", group: "Oil And Electrical", label: "Hottest oil", unit: "°F", digits: 0, lowerIsBetter: true),
        Metric(id: "voltMin", group: "Oil And Electrical", label: "Lowest bus 1 voltage", unit: "V", digits: 1, lowerIsBetter: false),
        Metric(id: "magR", group: "Run-Up", label: "R mag drop", unit: "RPM", digits: 0, lowerIsBetter: nil),
        Metric(id: "magL", group: "Run-Up", label: "L mag drop", unit: "RPM", digits: 0, lowerIsBetter: nil),
    ]

    static var groups: [String] {
        var seen: [String] = []
        for m in metrics where !seen.contains(m.group) { seen.append(m.group) }
        return seen
    }

    static func value(_ id: String, _ s: FlightSummary) -> Double? {
        let c = s.engineChecks?.card
        switch id {
        case "takeoffRPM": return c?.takeoffRPM
        case "takeoffMAP": return c?.takeoffMAP
        case "takeoffFF": return c?.takeoffFF
        case "climbMaxCHT": return (c?.climbSeconds ?? 0) >= 120 ? c?.climbMaxCHT : nil
        case "climbMaxTIT": return (c?.climbSeconds ?? 0) >= 120 ? c?.climbMaxTIT : nil
        case "climbRate": return (c?.climbSeconds ?? 0) >= 120 ? c?.climbRate : nil
        case "cruisePower": return c?.cruisePower
        case "cruiseTAS": return c?.cruiseTAS
        case "cruiseFF": return c?.cruiseFF
        case "cruiseNMPG": return c?.cruiseNMPG
        case "cruiseCHTAvg": return c?.cruiseCHTAvg
        case "cruiseCHTMax": return c?.cruiseCHTMax
        case "cruiseCHTSpread": return c?.cruiseCHTSpread
        case "cruiseEGTSpread": return c?.cruiseEGTSpread
        case "cruiseTIT": return c?.cruiseTIT
        case "cruiseOilT": return c?.cruiseOilT
        case "cruiseOilP": return c?.cruiseOilP
        case "oilTMax": return c?.oilTMax
        case "voltMin": return c?.voltMin
        case "magR": return s.engineChecks?.runups.last?.drop("R")
        case "magL": return s.engineChecks?.runups.last?.drop("L")
        default: return nil
        }
    }

    /// Flights with a card (airborne 10 minutes or more), oldest first.
    static func flights(_ summaries: [FlightSummary]) -> [FlightSummary] {
        summaries.filter { $0.engineChecks?.card != nil }.sorted { $0.start < $1.start }
    }

    static func rows(for s: FlightSummary, in summaries: [FlightSummary]) -> [ReportCardRow] {
        let earlier = flights(summaries).filter { $0.start < s.start && $0.filename != s.filename }
        return metrics.compactMap { m -> ReportCardRow? in
            guard let v = value(m.id, s) else { return nil }
            let past = earlier.compactMap { value(m.id, $0) }.sorted()
            var pct: Double?
            if past.count >= minEarlier {
                let below = Double(past.filter { $0 < v }.count), same = Double(past.filter { $0 == v }.count)
                pct = 100 * (below + same / 2) / Double(past.count)
            }
            return ReportCardRow(metric: m, value: v, percentile: pct, low: past.first, median: EngineChecks.median(past),
                                 high: past.last, earlier: past.count)
        }
    }

    /// Days since the previous flight (rust and corrosion risk grows with long gaps).
    static func daysSincePrevious(_ s: FlightSummary, in summaries: [FlightSummary]) -> Double? {
        guard let prev = flights(summaries).last(where: { $0.start < s.start && $0.filename != s.filename }) else { return nil }
        return s.start.timeIntervalSince(prev.end) / 86400
    }

    /// Plain-words reading of a percentile, using the metric's better direction.
    static func reading(_ r: ReportCardRow) -> String? {
        guard let p = r.percentile else { return nil }
        if p >= 95 || p <= 5 {
            let high = p >= 95
            switch r.metric.lowerIsBetter {
            case true?: return high ? "highest of this aircraft's flights" : "among the best"
            case false?: return high ? "among the best" : "lowest of this aircraft's flights"
            case nil: return high ? "unusually high for this aircraft" : "unusually low for this aircraft"
            }
        }
        return nil
    }

    static func markdown(_ s: FlightSummary, in summaries: [FlightSummary]) -> String {
        let rows = rows(for: s, in: summaries)
        guard !rows.isEmpty else { return "No report card (less than 10 minutes airborne).\n\n" }
        var md = ""
        if let d = daysSincePrevious(s, in: summaries) { md += String(format: "%.0f days since the previous flight.\n\n", d) }
        md += "| | This flight | Percentile | Normal range (median) |\n| --- | --- | --- | --- |\n"
        for r in rows {
            let range = r.low.map { lo in "\(r.metric.format(lo)) - \(r.metric.format(r.high ?? lo)) (\(r.metric.format(r.median ?? lo)))" } ?? "-"
            md += "| \(r.metric.group): \(r.metric.label) | \(r.metric.format(r.value)) | \(r.percentile.map { String(format: "%.0f", $0) } ?? "-") | \(range) |\n"
        }
        return md + "\n"
    }
}

// MARK: - Turbonormalizer and induction checks

struct TurboFinding: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case takeoffRPM = "takeoff-rpm", takeoffMAP = "takeoff-map", takeoffFF = "takeoff-ff", deck, induction
    }
    let kind: Kind
    let filename: String
    let time: Date
    var cylinder: Int? = nil
    /// Altitude band ("6000") for deck pressure.
    var band: String? = nil
    let value: Double
    let normal: Double

    var id: String { "\(kind.rawValue)|\(filename)|\(cylinder ?? 0)|\(band ?? "")" }

    var text: String {
        switch kind {
        case .takeoffRPM: return String(format: "Takeoff RPM %.0f, below this aircraft's normal %.0f (POH 4-16: about 2,700). Have the prop governor (high-RPM stop) checked.", value, normal)
        case .takeoffMAP: return String(format: "Takeoff manifold pressure %.1f inHg, below this aircraft's normal %.1f. Points at the turbonormalizer (wastegate, controller) or an induction or exhaust leak.", value, normal)
        case .takeoffFF: return String(format: "Takeoff fuel flow %.1f gph, below this aircraft's normal %.1f. Less fuel means less cooling at full power: check the mixture rigging, fuel servo, flow divider and injectors (and that the takeoff was not leaned).", value, normal)
        case .deck:
            let ft = Int(band ?? "0") ?? 0
            return String(format: "Full-throttle MAP %.1f inHg at %ld-%ld ft, below this aircraft's normal %.1f. A turbonormalized engine holds its MAP to the critical altitude; MAP sagging early points at the wastegate, controller or an exhaust/induction leak.",
                          value, ft, ft + 2000, normal)
        case .induction:
            return String(format: "Cylinder %ld runs %.0f °F hotter (vs the others) at low manifold pressure than in cruise; this aircraft's normal is %+.0f °F. A leak between the throttle and that cylinder leans it most at low MAP: check its intake tube couplers, gaskets and hoses.",
                          cylinder ?? 0, value, normal)
        }
    }
}

/// Takeoff power, full-throttle MAP by altitude (deck pressure) and the induction-leak check, each against the aircraft's
/// own earlier flights (robust median and spread of the last 40). Same rules as tools/turbo_bt.py.
enum TurboCheck {
    static let historyMax = 40, historyMin = 10
    static let rpmFloor = 30.0, mapFloor = 0.8, ffFloor = 2.0, deckFloor = 0.7, inductionFloor = 40.0

    static func robust(_ v: [Double]) -> (center: Double, sigma: Double)? {
        guard let m = EngineChecks.median(v), let mad = EngineChecks.median(v.map { abs($0 - m) }) else { return nil }
        return (m, 1.4826 * mad)
    }

    static func evaluate(_ s: FlightSummary, history: [FlightSummary]) -> [TurboFinding] {
        guard let c = s.engineChecks?.card else { return [] }
        let past = history.compactMap { $0.engineChecks?.card }
        var out: [TurboFinding] = []
        func low(_ kind: TurboFinding.Kind, _ v: Double?, _ hist: [Double], floor: Double) {
            guard let v, hist.count >= historyMin, let r = robust(Array(hist.suffix(historyMax))) else { return }
            if v < r.center - Swift.max(3 * r.sigma, floor) {
                out.append(TurboFinding(kind: kind, filename: s.filename, time: s.start, value: v, normal: r.center))
            }
        }
        low(.takeoffRPM, c.takeoffRPM, past.compactMap(\.takeoffRPM), floor: rpmFloor)
        low(.takeoffMAP, c.takeoffMAP, past.compactMap(\.takeoffMAP), floor: mapFloor)
        low(.takeoffFF, c.takeoffFF, past.compactMap(\.takeoffFF), floor: ffFloor)
        for (band, v) in c.deckMAP.sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
            let hist = past.compactMap { $0.deckMAP[band] }
            guard hist.count >= historyMin, let r = robust(Array(hist.suffix(historyMax))) else { continue }
            if v < r.center - Swift.max(3 * r.sigma, deckFloor) {
                out.append(TurboFinding(kind: .deck, filename: s.filename, time: s.start, band: band, value: v, normal: r.center))
            }
        }
        if let shift = c.inductionShift {
            let hist = past.compactMap(\.inductionShift)
            if hist.count >= historyMin {
                for cyl in 0..<6 {
                    guard let r = robust(Array(hist.suffix(historyMax)).map { $0[cyl] }) else { continue }
                    if shift[cyl] > r.center + Swift.max(3 * r.sigma, inductionFloor) {
                        out.append(TurboFinding(kind: .induction, filename: s.filename, time: s.start, cylinder: cyl + 1, value: shift[cyl], normal: r.center))
                    }
                }
            }
        }
        return out
    }

    /// Every flight checked against the flights before it, oldest first.
    static func backtest(_ summaries: [FlightSummary]) -> [(summary: FlightSummary, findings: [TurboFinding])] {
        let flights = ReportCard.flights(summaries)
        return flights.indices.map { i -> (summary: FlightSummary, findings: [TurboFinding]) in
            (summary: flights[i], findings: evaluate(flights[i], history: Array(flights[..<i])))
        }
    }

    /// WATCH issues. Takeoff and deck-pressure findings count on their own; an induction finding only when the same
    /// cylinder was also flagged on one of the two previous flights with low-power data (a single descent varies a lot).
    static func issues(_ summaries: [FlightSummary]) -> [FlightIssue] {
        var out: [FlightIssue] = []
        var inductionHistory: [Set<Int>] = []
        for (s, f) in backtest(summaries) {
            for x in f where x.kind != .induction {
                out.append(FlightIssue(kind: "turbo.\(x.kind.rawValue)", system: .engine, severity: .watch, origin: .trend,
                                       source: s.filename, time: s.start, title: title(x), detail: x.text))
            }
            guard s.engineChecks?.card?.inductionShift != nil else { continue }
            let now = Set(f.filter { $0.kind == .induction }.compactMap(\.cylinder))
            for x in f where x.kind == .induction {
                if let c = x.cylinder, inductionHistory.suffix(2).contains(where: { $0.contains(c) }) {
                    out.append(FlightIssue(kind: "turbo.induction.cyl\(c)", system: .engine, severity: .watch, origin: .trend,
                                           source: s.filename, time: s.start, title: title(x), detail: x.text + " Seen on consecutive flights."))
                }
            }
            inductionHistory.append(now)
        }
        return out
    }

    static func title(_ x: TurboFinding) -> String {
        switch x.kind {
        case .takeoffRPM: return String(format: "Takeoff RPM low (%.0f)", x.value)
        case .takeoffMAP: return String(format: "Takeoff manifold pressure low (%.1f inHg)", x.value)
        case .takeoffFF: return String(format: "Takeoff fuel flow low (%.1f gph)", x.value)
        case .deck: return String(format: "Full-throttle MAP low at %@ ft (%.1f inHg)", x.band ?? "", x.value)
        case .induction: return "Cylinder \(x.cylinder ?? 0) lean at low power (possible induction leak)"
        }
    }

    /// Cylinders that, across all flights, run much hotter relative to the others at low manifold pressure than in
    /// cruise (median shift at least 50 °F above the other cylinders' median shift). A long-standing pattern, not a
    /// change: fuel distribution at low MAP or a small induction leak at that cylinder. Worth a look at the next annual.
    static func persistentInduction(_ summaries: [FlightSummary]) -> [(cylinder: Int, shift: Double, others: Double, flights: Int)] {
        let shifts = summaries.compactMap { $0.engineChecks?.card?.inductionShift }
        guard shifts.count >= historyMin else { return [] }
        let med = (0..<6).map { c in EngineChecks.median(shifts.map { $0[c] }) ?? 0 }
        return (0..<6).compactMap { c -> (cylinder: Int, shift: Double, others: Double, flights: Int)? in
            let others = EngineChecks.median((0..<6).filter { $0 != c }.map { med[$0] }) ?? 0
            return med[c] - others >= 50 ? (c + 1, med[c], others, shifts.count) : nil
        }
    }

    /// the aircraft's normal full-throttle MAP per altitude band, and the newest flight's value.
    static func deckTable(_ summaries: [FlightSummary]) -> [(band: Int, normal: Double, flights: Int, latest: Double?)] {
        let cards = ReportCard.flights(summaries).compactMap { $0.engineChecks?.card }
        let latest = cards.last { !$0.deckMAP.isEmpty }
        return FlightCardBuilder.bands.compactMap { b -> (band: Int, normal: Double, flights: Int, latest: Double?)? in
            let v = cards.compactMap { $0.deckMAP[String(b)] }
            guard v.count >= 3, let m = EngineChecks.median(Array(v.suffix(historyMax))) else { return nil }
            return (b, m, v.count, latest?.deckMAP[String(b)])
        }
    }
}

// MARK: - A&P pre-shop report

/// One page for the A&P before an annual or a squawk visit: what the engine data shows, by system, and what to look at.
/// Recorded values and the aircraft's own history only; advisory, never a diagnosis.
enum PreShopReport {
    static func text(summaries: [FlightSummary], openIssues: [IssueGroup] = [], generated: Date = Date()) -> String {
        let flights = ReportCard.flights(summaries)
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "yyyy-MM-dd"
        let hours = flights.compactMap { $0.engineChecks?.card?.airborneHours }.reduce(0, +)
        var lookAt: [String] = []
        var t = "PRE-SHOP ENGINE REPORT\n"
        t += "\(AircraftKnowledge.aircraftSummary). Generated \(d.string(from: generated)) by Engine Pulse from "
        t += "\(flights.count) engine data logs"
        if let a = flights.first, let b = flights.last { t += " (\(d.string(from: a.start)) to \(d.string(from: b.start)), " + String(format: "%.0f", hours) + " flight hours)" }
        t += ". Recorded values compared with this airplane's own history; advisory only.\n\n"

        // Run-up magneto checks.
        let runups = MagCheck.history(summaries)
        t += "RUN-UP MAGNETO CHECKS\n"
        if runups.isEmpty {
            t += "- No run-up mag checks found in the logs.\n"
        } else {
            let r = runups.compactMap { $0.runup.drop("R") }, l = runups.compactMap { $0.runup.drop("L") }
            t += "- \(runups.count) run-ups with a mag check. Median drop R \(Int(EngineChecks.median(r) ?? 0)) RPM, L \(Int(EngineChecks.median(l) ?? 0)) RPM (POH: 150 max, 75 difference).\n"
            if let last = runups.first { t += "- Latest (\(d.string(from: last.runup.time))): " + MagCheck.describe(last.runup) + "\n" }
            let cautions = runups.filter { $0.runup.findings.contains { $0.kind == .drop || $0.kind == .split } }
            if !cautions.isEmpty {
                t += "- Over a POH limit on \(cautions.count) run-up(s): " + cautions.prefix(4).map { u in
                    d.string(from: u.runup.time) + " " + u.runup.mags.map { "\($0.mag) \(Int($0.drop))" }.joined(separator: "/")
                }.joined(separator: "; ") + ".\n"
            }
            var cold: [String: Int] = [:]
            for u in runups { for f in u.runup.findings where f.kind == .coldCylinder { cold["cylinder \(f.cylinder ?? 0) on the \(f.mag ?? "") mag", default: 0] += 1 } }
            for (k, n) in cold.sorted(by: { $0.value > $1.value }) {
                t += "- EGT did not rise for \(k) on \(n) run-up(s).\n"
                if n >= 2 { lookAt.append("Ignition: \(k) repeatedly not firing at run-up. Check that cylinder's plug(s) and lead(s) on that magneto; mag-to-plug wiring.") }
            }
            if !cautions.isEmpty { lookAt.append("Magnetos: drop or split over the POH limit on \(cautions.count) run-up(s). Check plugs, leads and mag timing.") }
        }

        // Fuel distribution.
        t += "\nFUEL DISTRIBUTION (LEAN TEST)\n"
        if let g = GAMICheck.history(summaries).first {
            t += "- \(d.string(from: g.test.time)): " + GAMICheck.describe(g.test) + "\n"
            if g.test.spread >= GAMICheck.poorSpread { lookAt.append(String(format: "Injectors: fuel spread %.1f gph (cylinder %ld richest, %ld leanest). Clean/flow the injectors; consider matched GAMIjectors.", g.test.spread, g.test.richest, g.test.leanest)) }
        } else {
            t += "- No slow lean sweep in the logs yet (big-pull leaning is too fast to measure). Fly the guided lean test in the app for a spread.\n"
        }

        // Cylinders and valves.
        t += "\nCYLINDERS, VALVES AND PROBES\n"
        let recent = flights.suffix(5).compactMap { $0.engineTrend }.filter { $0.cht.count == 6 }
        if !recent.isEmpty {
            let cht = (0..<6).map { c in EngineChecks.median(recent.compactMap { $0.cht[c] }) }
            t += "- Cruise CHT, last \(recent.count) flights (median): " + cht.enumerated().map { i, v in "\(i + 1): " + (v.map { String(format: "%.0f", $0) } ?? "-") }.joined(separator: ", ") + " °F.\n"
        }
        let vw = ValveWatchOverview(summaries)
        let flagged = vw.flaggedCylinders
        t += "- Valve watch (EGT cycling in steady cruise): \(vw.checked.count) flights checked, "
        t += flagged.isEmpty ? "no exhaust-valve signature.\n" : flagged.sorted { $0.key < $1.key }.map { "cylinder \($0.key) flagged on \($0.value) flight(s)" }.joined(separator: ", ") + ".\n"
        for (c, n) in flagged where n >= 2 { lookAt.append("Exhaust valve: borescope cylinder \(c) (valve-watch signature on \(n) flights).") }
        let probes = ProbeOverview(summaries)
        t += "- Probes and wiring: \(probes.checked.count) flights checked, "
        t += probes.faultyChannels.isEmpty ? "no sensor faults.\n" : probes.faultyChannels.map { "\(ProbeCheck.label($0.channel)) on \($0.flights)" }.joined(separator: ", ") + " flight(s).\n"
        for ch in probes.faultyChannels where ch.flights >= 2 { lookAt.append("Sensor: \(ProbeCheck.label(ch.channel)) probe, clamp, connector and wiring (faults on \(ch.flights) flights).") }
        let ew = EarlyWarning.analyze(summaries)
        if ew.patterns.isEmpty {
            t += "- Early warning: nothing drifting outside this aircraft's normal.\n"
        } else {
            for p in ew.patterns {
                t += "- \(p.level.rawValue): \(p.title)" + (p.cylinder.map { " (cylinder \($0))" } ?? "") + ". \(p.advice)\n"
                lookAt.append("\(p.title)" + (p.cylinder.map { ", cylinder \($0)" } ?? "") + ": \(p.advice)")
            }
        }

        // Turbo and induction.
        t += "\nTURBONORMALIZER AND INDUCTION\n"
        let cards = flights.compactMap { $0.engineChecks?.card }
        func norm(_ v: [Double]) -> String { EngineChecks.median(Array(v.suffix(TurboCheck.historyMax))).map { String(format: "%.1f", $0) } ?? "-" }
        if let last = cards.last(where: { $0.takeoffFF != nil }) {
            t += String(format: "- Takeoff (latest): %.0f RPM, %.1f inHg, %.1f gph. Normal: ", last.takeoffRPM ?? 0, last.takeoffMAP ?? 0, last.takeoffFF ?? 0)
            t += "\(norm(cards.compactMap(\.takeoffRPM))) RPM, \(norm(cards.compactMap(\.takeoffMAP))) inHg, \(norm(cards.compactMap(\.takeoffFF))) gph.\n"
        }
        let deck = TurboCheck.deckTable(summaries)
        if !deck.isEmpty {
            t += "- Full-throttle MAP in climb (normal): " + deck.map { String(format: "%ldk ft %.1f", $0.band / 1000, $0.normal) }.joined(separator: ", ") + " inHg.\n"
        }
        if let gap = cards.last(where: { $0.cruiseTITGap != nil })?.cruiseTITGap {
            t += String(format: "- TIT1 minus TIT2 in cruise (latest): %+.0f °F (normal %@).\n", gap, norm(cards.compactMap(\.cruiseTITGap)))
        }
        let recentTurbo = TurboCheck.backtest(summaries).suffix(10).flatMap { $0.findings }
        for x in recentTurbo where x.kind != .induction {
            t += "- " + x.text + "\n"
            lookAt.append("Turbo system: " + TurboCheck.title(x) + ". Inspect wastegate, controller, exhaust and induction for leaks.")
        }
        for p in TurboCheck.persistentInduction(summaries) {
            t += String(format: "- Cylinder %ld runs %.0f °F hotter vs the others at low manifold pressure than in cruise (others %+.0f), across %ld flights: a long-standing pattern.\n",
                        p.cylinder, p.shift, p.others, p.flights)
            lookAt.append("Induction: check intake couplers, gaskets and hoses at cylinder \(p.cylinder) (lean at low manifold pressure on most flights).")
        }
        for x in TurboCheck.issues(summaries).filter({ $0.kind.hasPrefix("turbo.induction") }).suffix(3) { t += "- " + x.detail + "\n" }

        // Oil and electrical.
        t += "\nOIL AND ELECTRICAL\n"
        if let c = cards.last(where: { $0.cruiseOilT != nil }) {
            t += String(format: "- Cruise oil (latest): %.0f °F, %.0f psi. Normal %@ °F, %@ psi.\n", c.cruiseOilT ?? 0, c.cruiseOilP ?? 0,
                        norm(cards.compactMap(\.cruiseOilT)), norm(cards.compactMap(\.cruiseOilP)))
        }
        if let v = cards.last?.voltMin { t += String(format: "- Lowest bus 1 voltage airborne (latest): %.1f V (normal %@ V).\n", v, norm(cards.compactMap(\.voltMin))) }

        // Open issues.
        let review = openIssues.filter(\.needsReview)
        if !review.isEmpty {
            t += "\nOPEN ITEMS IN THE APP'S ISSUE LIST (\(review.count))\n"
            for g in review.prefix(8) { t += "- \(g.severity.rawValue): \(g.guide.title) (\(g.occurrences.count)x, latest \(d.string(from: g.latest.time)))\n" }
        }

        t += "\nPLEASE LOOK AT\n"
        if lookAt.isEmpty { t += "- Nothing specific from the engine data. Routine annual: compressions, borescope, plugs, mags, induction and exhaust.\n" }
        for (i, s) in lookAt.prefix(10).enumerated() { t += "\(i + 1). \(s)\n" }
        t += "\nMethods: run-up per POH 4-14; fuel spread from a slow lean sweep; valve watch, probe check, early warning and turbo checks compare each flight with this aircraft's own normal. "
        t += "Logs: engine monitor data card, 1 sample per second.\n"
        return t
    }
}
