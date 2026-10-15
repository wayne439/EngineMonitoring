import Foundation

/// One sensor fault on one channel in one flight.
struct ProbeFault: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case dropout, spike, step, flatline, offScale, apart

        var label: String {
            switch self {
            case .dropout: "Blank readings"
            case .spike: "One-second spikes"
            case .step: "Jumped and stayed"
            case .flatline: "Stuck reading"
            case .offScale: "Off-scale reading"
            case .apart: "Far from the other cylinders"
            }
        }
    }

    /// Perspective column, e.g. "E1 EGT3".
    let channel: String
    let kind: Kind
    /// Number of events (dropouts, spikes, steps) or 1.
    let count: Int
    /// Seconds affected.
    let seconds: Int
    let first: Date
    /// Reading at the first event (step: the size of the jump).
    let value: Double?

    var channelLabel: String { ProbeCheck.label(channel) }
}

/// Probe and wiring check for one flight.
struct ProbeCheckResult: Codable, Hashable, Sendable {
    /// Sensor channels with data in this log (EGT, CHT, TIT, oil temperature, oil pressure).
    let channelsChecked: Int
    let faults: [ProbeFault]

    var checked: Bool { channelsChecked > 0 }
    /// Channels with at least one fault, in display order.
    var faultyChannels: [String] { ProbeCheck.channels.filter { ch in faults.contains { $0.channel == ch } } }
}

/// Finds sensor faults (probe, clamp, connector, wiring) so they are not mistaken for engine problems, and so a failing
/// probe is caught early. Readings are judged against the other channels of their group where possible (EGT vs the
/// other EGTs, CHT vs the other CHTs, TIT1 vs TIT2): a real engine change moves the group together, a probe fault moves
/// one channel alone. Same method as tools/n63ka_probes.py. Recorded values only; never an engine diagnosis.
enum ProbeCheck {
    enum Group: Sendable { case egt, cht, tit, oilTemp, oilPressure }

    static let channels: [String] = PerspectiveChannel.egt + PerspectiveChannel.cht
        + [PerspectiveChannel.tit1, PerspectiveChannel.tit2, PerspectiveChannel.oilTemp, PerspectiveChannel.oilPressure]
    /// The Perspective often writes a partial last row when the card or power is removed.
    static let tailSeconds = 3
    static let flatSeconds = 60, flatMove = 5.0
    static let apartSeconds = 60
    static let minSpikes = 3
    static let steadyHalfWindow = 30
    static let air: Set<FlightPhase> = [.climb, .cruise, .descent]

    static func group(_ ch: String) -> Group? {
        if PerspectiveChannel.egt.contains(ch) { return .egt }
        if PerspectiveChannel.cht.contains(ch) { return .cht }
        if ch == PerspectiveChannel.tit1 || ch == PerspectiveChannel.tit2 { return .tit }
        if ch == PerspectiveChannel.oilTemp { return .oilTemp }
        if ch == PerspectiveChannel.oilPressure { return .oilPressure }
        return nil
    }

    static func members(_ g: Group) -> [String] {
        switch g {
        case .egt: PerspectiveChannel.egt
        case .cht: PerspectiveChannel.cht
        case .tit: [PerspectiveChannel.tit1, PerspectiveChannel.tit2]
        case .oilTemp, .oilPressure: []
        }
    }

    static func spikeThreshold(_ g: Group) -> Double {
        switch g {
        case .egt, .tit: 100
        case .cht: 40
        case .oilTemp: 20
        case .oilPressure: 25
        }
    }

    static func stepThreshold(_ g: Group) -> Double? {
        switch g {
        case .egt, .tit: 150
        case .cht: 50
        case .oilTemp, .oilPressure: nil
        }
    }

    static func apartThreshold(_ g: Group) -> Double? {
        switch g {
        case .egt: 400
        case .cht: 120
        case .tit: 300
        case .oilTemp, .oilPressure: nil
        }
    }

    static func scale(_ g: Group) -> ClosedRange<Double> {
        switch g {
        case .egt, .tit: 300...1900
        case .cht: 80...600
        case .oilTemp: 50...300
        case .oilPressure: 0...120
        }
    }

    /// "E1 EGT3" -> "EGT 3", "E1 OilP" -> "Oil pressure".
    static func label(_ ch: String) -> String {
        switch ch {
        case PerspectiveChannel.oilTemp: return "Oil temperature"
        case PerspectiveChannel.oilPressure: return "Oil pressure"
        default:
            let s = ch.replacingOccurrences(of: "E1 ", with: "")
            guard let digit = s.last, digit.isNumber else { return s }
            return String(s.dropLast()) + " " + String(digit)
        }
    }

    static func unit(_ ch: String) -> String { ch == PerspectiveChannel.oilPressure ? " psi" : " °F" }

    // MARK: - Analysis

    static func analyze(_ log: PerspectiveLog, phases: [FlightPhase]) -> ProbeCheckResult {
        let all = log.sampleCount
        let empty = ProbeCheckResult(channelsChecked: 0, faults: [])
        guard all >= 120, phases.count == all else { return empty }
        let n = all - tailSeconds
        let running = (0..<all).map { (log.value(PerspectiveChannel.rpm, at: $0) ?? 0) >= 500 }
        guard running.filter({ $0 }).count >= 60 else { return empty }
        let steady = steadyMask(log, phases: phases)

        var data: [String: [Double?]] = [:]
        for ch in channels where log.hasChannel(ch) {
            let v = (0..<all).map { log.value(ch, at: $0) }
            if v[0..<n].contains(where: { $0 != nil }) { data[ch] = v }
        }

        var faults: [ProbeFault] = []
        var stepCandidates: [String: [(index: Int, size: Double)]] = [:]
        for ch in channels {
            guard let v = data[ch], let g = group(ch) else { continue }
            let others = members(g).filter { $0 != ch && data[$0] != nil }
            // Reading relative to the median of the other channels of its group (or the raw reading).
            let res: [Double?] = others.isEmpty ? v : (0..<all).map { k in
                guard let x = v[k] else { return nil }
                let o = others.compactMap { data[$0]?[k] ?? nil }
                return o.isEmpty ? nil : x - median(o)
            }

            // Dropouts: blanks in the middle of the log while the engine runs.
            var drops: [(start: Int, length: Int)] = []
            var seen = false
            var k = 0
            while k < n {
                if v[k] != nil { seen = true; k += 1; continue }
                if running[k] && seen {
                    var j = k
                    while j < n && v[j] == nil { j += 1 }
                    if j < n { drops.append((k, j - k)) }
                    k = j
                } else {
                    k += 1
                }
            }
            if let d = drops.first {
                faults.append(ProbeFault(channel: ch, kind: .dropout, count: drops.count,
                                         seconds: drops.reduce(0) { $0 + $1.length }, first: log.times[d.start], value: nil))
            }

            // Spikes: airborne, one reading sticking out on the same side of its neighbours before and after.
            let threshold = spikeThreshold(g)
            var spikes: [Int] = []
            if n > 7 {
                for k in 3..<(n - 3) where air.contains(phases[k]) {
                    guard let r = res[k] else { continue }
                    let left = (k - 3..<k).compactMap { res[$0] }
                    let right = (k + 1...k + 3).compactMap { res[$0] }
                    guard left.count >= 2, right.count >= 2 else { continue }
                    let dl = r - median(left), dr = r - median(right)
                    if dl * dr > 0, abs(dl) > threshold, abs(dr) > threshold { spikes.append(k) }
                }
            }
            if spikes.count >= minSpikes {
                faults.append(ProbeFault(channel: ch, kind: .spike, count: spikes.count, seconds: spikes.count,
                                         first: log.times[spikes[0]], value: v[spikes[0]]))
            }

            if !others.isEmpty {
                // Steps: in steady cruise, the channel alone jumps against its group and stays.
                if let st = stepThreshold(g), n > 20 {
                    var cands: [(index: Int, size: Double)] = []
                    var k = 10
                    while k < n - 10 {
                        if steady[k],
                           let a = medianOrNil(res[(k - 10)..<k].compactMap { $0 }),
                           let b = medianOrNil(res[k..<(k + 10)].compactMap { $0 }),
                           abs(b - a) > st {
                            cands.append((k, b - a))
                            k += 60
                            continue
                        }
                        k += 1
                    }
                    if !cands.isEmpty { stepCandidates[ch] = cands }
                }

                // Flatline: identical readings while the other channels of the group move.
                var best = 1, cur = 1, start = 0, bestStart = 0
                for k in 1..<n {
                    if running[k], let a = v[k], let b = v[k - 1], a == b {
                        cur += 1
                        if cur == 2 { start = k - 1 }
                        if cur > best {
                            let moving = others.contains { o in
                                let w = (start...k).compactMap { data[o]?[$0] ?? nil }
                                return (w.max() ?? 0) - (w.min() ?? 0) >= flatMove
                            }
                            if moving { best = cur; bestStart = start }
                        }
                    } else {
                        cur = 1
                    }
                }
                if best >= flatSeconds {
                    faults.append(ProbeFault(channel: ch, kind: .flatline, count: 1, seconds: best,
                                             first: log.times[bestStart], value: v[bestStart]))
                }
            }

            // Off-scale, airborne.
            let range = scale(g)
            let bad = (0..<n).filter { air.contains(phases[$0]) && v[$0].map { !range.contains($0) } == true }
            if let b = bad.first {
                faults.append(ProbeFault(channel: ch, kind: .offScale, count: 1, seconds: bad.count, first: log.times[b], value: v[b]))
            }

            // Far from the group, in steady cruise, for a minute or more.
            if !others.isEmpty, let limit = apartThreshold(g) {
                var run = 0, bestRun = 0, from = 0
                for k in 0..<n {
                    if steady[k], let r = res[k], abs(r) > limit {
                        run += 1
                        if run > bestRun { bestRun = run; from = k - run + 1 }
                    } else {
                        run = 0
                    }
                }
                if bestRun >= apartSeconds {
                    faults.append(ProbeFault(channel: ch, kind: .apart, count: 1, seconds: bestRun, first: log.times[from], value: v[from]))
                }
            }
        }

        // A step is a probe fault only if no other channel stepped within 30 s (otherwise the engine changed).
        for ch in channels {
            guard let steps = stepCandidates[ch] else { continue }
            let own = steps.filter { s in
                !stepCandidates.contains { other, list in other != ch && list.contains { abs($0.index - s.index) <= 30 } }
            }
            if let s = own.first {
                faults.append(ProbeFault(channel: ch, kind: .step, count: own.count, seconds: 0, first: log.times[s.index], value: s.size))
            }
        }

        let order = Dictionary(uniqueKeysWithValues: channels.enumerated().map { ($1, $0) })
        faults.sort { (order[$0.channel] ?? 0, $0.first) < (order[$1.channel] ?? 0, $1.first) }
        return ProbeCheckResult(channelsChecked: data.count, faults: faults)
    }

    /// True where the engine is in cruise with steady power for ±30 s (RPM 60, fuel flow 1.5 gph, MAP 1.5 inHg).
    static func steadyMask(_ log: PerspectiveLog, phases: [FlightPhase]) -> [Bool] {
        let n = log.sampleCount, h = steadyHalfWindow
        var out = [Bool](repeating: false, count: n)
        guard n > 2 * h else { return out }
        let series: [(String, Double)] = [(PerspectiveChannel.rpm, 60), (PerspectiveChannel.fuelFlow, 1.5),
                                          (PerspectiveChannel.manifoldPressure, 1.5)]
        let values = series.map { ch, _ in (0..<n).map { log.value(ch, at: $0) } }
        for k in h..<(n - h) where phases[k] == .cruise {
            var ok = true
            for (s, (_, limit)) in series.enumerated() {
                let w = values[s][(k - h)...(k + h)].compactMap { $0 }
                guard w.count >= 2 * h, let lo = w.min(), let hi = w.max(), hi - lo <= limit else { ok = false; break }
            }
            out[k] = ok
        }
        return out
    }

    // MARK: - Issues and report

    /// Issue kind for a channel: "probe.egt3", "probe.oilp".
    static func issueKind(_ ch: String) -> String {
        "probe." + label(ch).lowercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "temperature", with: "t").replacingOccurrences(of: "pressure", with: "p")
    }

    static func describe(_ f: ProbeFault, timeZone: TimeZone) -> String {
        let t = DateFormatter()
        t.locale = Locale(identifier: "en_US_POSIX")
        t.timeZone = timeZone
        t.dateFormat = "HH:mm:ss"
        let at = t.string(from: f.first)
        let u = unit(f.channel)
        switch f.kind {
        case .dropout:
            return "blank for \(f.seconds) s (\(f.count) time\(f.count == 1 ? "" : "s")), first at \(at)"
        case .spike:
            return "\(f.count) one-second spikes, first at \(at)" + (f.value.map { String(format: " (%.0f%@)", $0, u) } ?? "")
        case .step:
            return String(format: "jumped %+.0f%@ against the other cylinders and stayed, at %@", f.value ?? 0, u, at)
        case .flatline:
            return "stuck" + (f.value.map { String(format: " at %.1f%@", $0, u) } ?? "") + " for \(f.seconds) s while the others moved, from \(at)"
        case .offScale:
            return (f.value.map { String(format: "read %.0f%@", $0, u) } ?? "off-scale") + " (outside what a working probe shows) for \(f.seconds) s, from \(at)"
        case .apart:
            return "far from the other cylinders for \(f.seconds) s in steady cruise, from \(at)"
        }
    }

    /// One WATCH issue per faulty channel; the issue list groups them by channel across flights.
    static func issues(_ result: ProbeCheckResult, log: PerspectiveLog) -> [FlightIssue] {
        let tz = log.timeZone
        return result.faultyChannels.compactMap { ch -> FlightIssue? in
            let fs = result.faults.filter { $0.channel == ch }
            guard let first = fs.map(\.first).min() else { return nil }
            return FlightIssue(
                kind: issueKind(ch), system: .engine, severity: .watch, origin: .engineData, source: log.filename, time: first,
                title: "\(label(ch)) probe or wiring: " + fs.map { $0.kind.label.lowercased() }.joined(separator: ", "),
                detail: fs.map { describe($0, timeZone: tz) }.joined(separator: "; "))
        }
    }

    static func markdown(_ result: ProbeCheckResult?, timeZone: TimeZone) -> String {
        guard let result else { return "Not checked (summary built before v0.9.5).\n\n" }
        guard result.checked else { return "Not checked (engine not running long enough).\n\n" }
        if result.faults.isEmpty {
            return "\(result.channelsChecked) sensor channels checked (EGT, CHT, TIT, oil): no dropouts, spikes, jumps, stuck or off-scale readings.\n\n"
        }
        var md = ""
        for ch in result.faultyChannels {
            let fs = result.faults.filter { $0.channel == ch }
            md += "- **WATCH \(label(ch)):** " + fs.map { describe($0, timeZone: timeZone) }.joined(separator: "; ")
            md += ". Check the probe, clamp, connector and wiring; until then don't rely on this reading alone.\n"
        }
        return md + "\n"
    }

    // MARK: - Helpers

    static func median(_ v: [Double]) -> Double { medianOrNil(v) ?? 0 }

    static func medianOrNil(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}
