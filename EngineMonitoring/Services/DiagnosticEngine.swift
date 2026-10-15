import Foundation

/// Turns an event marker (and, when available, the matching Perspective log) into a finding.
///
/// Design rule: the engine reports what was RECORDED. It never assigns a cause, never compares
/// values against limits it has not been given from controlling documents, and never presents a
/// hypothesis as a procedure. "Possible causes" are fixed lists of things to investigate.
struct DiagnosticEngine {
    /// Seconds of data before the marker to examine. Pilots tap after noticing something.
    var lookBack: TimeInterval = 120
    /// Seconds of data after the marker to examine.
    var lookAhead: TimeInterval = 60
    /// Engine-start search reaches further back, since the start may precede the tap by minutes.
    var startSearchLookBack: TimeInterval = 300

    func finding(for event: DiagnosticEvent, log: PerspectiveLog?) -> DiagnosticFinding {
        let pilotNote = EvidenceItem(label: "Pilot note", value: event.note.isEmpty ? "No observation entered" : event.note)

        guard let log, log.covers(event.timestamp, tolerance: lookBack) else {
            var evidence = [pilotNote]
            if let log {
                evidence.append(EvidenceItem(label: "Attached log", value: "\(log.filename) does not cover the event time"))
            }
            return template(for: event.system, evidence: evidence, confidence: .insufficient, dataSource: nil,
                            limitations: "No recorded data covers this event yet. Attach the Perspective log from the flight. "
                                + "No cause is assigned without recorded data and controlling aircraft documentation.")
        }

        let tz = event.captureTimeZone
        let window = log.indices(from: event.timestamp.addingTimeInterval(-lookBack),
                                 to: event.timestamp.addingTimeInterval(lookAhead))
        var evidence = [pilotNote]
        if let first = window.first, let last = window.last {
            evidence.append(EvidenceItem(
                label: "Data window",
                value: "\(window.count) samples, \(Self.clock(log.times[first], tz)) to \(Self.clock(log.times[last], tz))"))
        }

        switch event.system {
        case .engineStart: evidence += engineStartEvidence(log: log, event: event, tz: tz)
        case .autopilot: evidence += autopilotEvidence(log: log, window: window, tz: tz)
        case .electrical: evidence += electricalEvidence(log: log, window: window, tz: tz)
        case .avionics: evidence += avionicsEvidence(log: log, window: window, tz: tz)
        case .engine: evidence += engineEvidence(log: log, window: window, tz: tz)
        case .other: evidence += generalEvidence(log: log, window: window)
        }

        let measured = evidence.count > 2
        return template(for: event.system, evidence: evidence,
                        confidence: measured ? .low : .insufficient,
                        dataSource: log.filename,
                        limitations: "Values are shown as recorded by the Perspective data log (1-second samples). "
                            + "They are not compared against N63KA limits; check them against the AFM/POH. "
                            + "Confidence stays LOW because no cause is assigned by the app.")
    }

    // MARK: - Templates (possible causes and next checks are investigation lists, not conclusions)

    private func template(for system: DiagnosticSystem, evidence: [EvidenceItem], confidence: DiagnosticConfidence,
                          dataSource: String?, limitations: String) -> DiagnosticFinding {
        switch system {
        case .engineStart:
            return DiagnosticFinding(
                title: "Engine start event",
                confidence: confidence, evidence: evidence,
                possibleCauses: ["Prime/fuel-delivery pattern", "Ignition/combustion establishment",
                                 "Cranking/electrical performance", "Hot/cold start conditions"],
                nextChecks: ["Compare RPM, fuel flow, EGT rise and bus voltage across the start",
                             "Correlate with the approved N63KA starting procedure and ambient/engine conditions",
                             "Compare with a normal start from another log"],
                limitations: limitations + " Over-prime versus under-prime must be supported by the actual event signature.",
                dataSource: dataSource)
        case .autopilot:
            return DiagnosticFinding(
                title: "Autopilot event",
                confidence: confidence, evidence: evidence,
                possibleCauses: ["Initialization or communication interruption", "Electrical/power interruption",
                                 "Controller, servo or network/LRU issue", "Mode/configuration state"],
                nextChecks: ["Record the FMA/annunciations and whether the controller was illuminated",
                             "Check the bus voltage at the event time",
                             "Check applicable Garmin/Cirrus approved troubleshooting information and maintenance history"],
                limitations: limitations + " The Perspective log does not contain GFC 700 internal fault data.",
                dataSource: dataSource)
        case .electrical:
            return DiagnosticFinding(
                title: "Electrical event",
                confidence: confidence, evidence: evidence,
                possibleCauses: ["Alternator or voltage-regulation issue", "Connection or bus-distribution issue",
                                 "Load change (equipment switched on/off)", "Battery condition"],
                nextChecks: ["Note annunciations (ALT, VOLTS, AMPS) at the time",
                             "Compare bus voltages with a normal flight",
                             "Refer to the approved electrical abnormal procedures and maintenance"],
                limitations: limitations,
                dataSource: dataSource)
        case .avionics:
            return DiagnosticFinding(
                title: "Avionics / navigation event",
                confidence: confidence, evidence: evidence,
                possibleCauses: ["GPS signal or integrity change", "Power interruption", "LRU or database issue"],
                nextChecks: ["Record the alert or message text shown", "Check NOTAMs/RAIM or WAAS status for the time",
                             "Refer to the Perspective pilot guide and maintenance"],
                limitations: limitations + " Most avionics faults need maintenance-level data the log does not contain.",
                dataSource: dataSource)
        case .engine:
            return DiagnosticFinding(
                title: "In-flight engine event",
                confidence: confidence, evidence: evidence,
                possibleCauses: ["Fuel delivery or mixture change", "Ignition", "Induction/turbonormalizer behavior",
                                 "Indication/sensor issue"],
                nextChecks: ["Compare the cylinder pattern (one cylinder vs. all)", "Note power setting and phase of flight",
                             "Refer to the approved abnormal procedures and an A&P"],
                limitations: limitations,
                dataSource: dataSource)
        case .other:
            return DiagnosticFinding(
                title: "Aircraft event",
                confidence: confidence, evidence: evidence,
                possibleCauses: ["Requires system-specific evidence"],
                nextChecks: ["Add observed annunciations and symptoms", "Cross-reference controlling N63KA documentation"],
                limitations: limitations,
                dataSource: dataSource)
        }
    }

    // MARK: - Evidence extraction

    /// Locates the most recent start before the marker: RPM rising from below 100 to 500 or more.
    func engineStartEvidence(log: PerspectiveLog, event: DiagnosticEvent, tz: TimeZone) -> [EvidenceItem] {
        let range = log.indices(from: event.timestamp.addingTimeInterval(-startSearchLookBack),
                                to: event.timestamp.addingTimeInterval(lookAhead))
        let rpm = log.samples(PerspectiveChannel.rpm, in: range)
        guard !rpm.isEmpty else { return [EvidenceItem(label: "RPM", value: "Not recorded in this window")] }

        var items: [EvidenceItem] = []

        // Cranking episodes: RPM rose above 100 but fell back below 100 without reaching 500.
        var startIndex: Int?
        var attempts = 0
        var inEpisode = false, reached500 = false
        var wasStopped = rpm.first!.value < 100
        for s in rpm {
            if s.value >= 100 && !inEpisode { inEpisode = true; reached500 = false }
            if inEpisode && s.value >= 500 && !reached500 {
                reached500 = true
                if wasStopped { startIndex = s.index }
            }
            if s.value < 100 {
                if inEpisode && !reached500 { attempts += 1 }
                inEpisode = false
                wasStopped = true
            }
        }

        guard let start = startIndex else {
            items.append(EvidenceItem(label: "Engine start",
                                      value: "No RPM rise from below 100 to 500+ found in the \(Int(startSearchLookBack / 60)) min before the marker"))
            if attempts > 0 {
                items.append(EvidenceItem(label: "Cranking episodes", value: "\(attempts) (RPM above 100 without reaching 500)"))
            }
            if let maxRPM = rpm.map(\.value).max() {
                items.append(EvidenceItem(label: "Max RPM in window", value: Self.number(maxRPM, 0)))
            }
            return items
        }

        let startTime = log.times[start]
        let lead = event.timestamp.timeIntervalSince(startTime)
        items.append(EvidenceItem(label: "Engine start (RPM ≥ 500)",
                                  value: "\(Self.clock(startTime, tz)) (\(Self.relative(lead)) the marker)"))
        if attempts > 0 {
            items.append(EvidenceItem(label: "Cranking episodes before start", value: "\(attempts) (RPM above 100 without reaching 500)"))
        }

        let crank = log.indices(from: startTime.addingTimeInterval(-30), to: startTime)
        let after = log.indices(from: startTime, to: startTime.addingTimeInterval(30))

        if let minVolts = log.samples(PerspectiveChannel.volt1, in: crank).map(\.value).min() {
            items.append(EvidenceItem(label: "Lowest bus 1 voltage, 30 s before start", value: "\(Self.number(minVolts, 1)) V"))
        }
        let ff = log.samples(PerspectiveChannel.fuelFlow, in: crank.lowerBound..<after.upperBound).map(\.value)
        if let maxFF = ff.max() {
            items.append(EvidenceItem(label: "Peak fuel flow, ±30 s of start", value: "\(Self.number(maxFF, 1)) gph"))
        }
        let rpmAfter = log.samples(PerspectiveChannel.rpm, in: after).map(\.value)
        if let peak = rpmAfter.max(), let last = rpmAfter.last {
            items.append(EvidenceItem(label: "RPM in first 30 s", value: "peak \(Self.number(peak, 0)), then \(Self.number(last, 0))"))
        }
        if let rise = egtRise(log: log, from: start, range: after) {
            items.append(rise)
        }
        return items
    }

    /// Per-cylinder EGT increase from the start sample to the highest value in the following range.
    private func egtRise(log: PerspectiveLog, from start: Int, range: Range<Int>) -> EvidenceItem? {
        var rises: [(cyl: Int, rise: Double)] = []
        for (n, channel) in PerspectiveChannel.egt.enumerated() {
            guard let base = log.value(channel, at: start),
                  let peak = log.samples(channel, in: range).map(\.value).max() else { continue }
            rises.append((n + 1, peak - base))
        }
        guard !rises.isEmpty else { return nil }
        let text = rises.map { "\($0.cyl): +\(Self.number($0.rise, 0))" }.joined(separator: ", ")
        return EvidenceItem(label: "EGT rise in first 30 s (°F, by cylinder)", value: text)
    }

    func autopilotEvidence(log: PerspectiveLog, window: Range<Int>, tz: TimeZone) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
        var lastOn: Double?
        var engageChanges: [String] = []
        for s in log.samples(PerspectiveChannel.afcsOn, in: window) {
            if let prev = lastOn, prev != s.value {
                engageChanges.append("\(Self.clock(log.times[s.index], tz)) \(s.value >= 1 ? "engaged" : "disengaged")")
            }
            lastOn = s.value
        }
        if !log.hasChannel(PerspectiveChannel.afcsOn) {
            items.append(EvidenceItem(label: "AFCS state", value: "Not recorded in this log"))
        } else if engageChanges.isEmpty {
            items.append(EvidenceItem(label: "AFCS state", value: lastOn.map { $0 >= 1 ? "Engaged throughout" : "Not engaged throughout" } ?? "Blank in this window"))
        } else {
            items.append(EvidenceItem(label: "AFCS engage changes", value: engageChanges.prefix(6).joined(separator: "; ")))
        }

        let modes = modeChanges(log: log, window: window, tz: tz)
        if !modes.isEmpty {
            items.append(EvidenceItem(label: "Mode changes (roll / pitch)", value: modes.prefix(8).joined(separator: "; ")))
        }
        items += voltageEvidence(log: log, window: window)
        return items
    }

    private func modeChanges(log: PerspectiveLog, window: Range<Int>, tz: TimeZone) -> [String] {
        var changes: [String] = []
        var last: String?
        for i in window {
            let roll = log.textValue(PerspectiveChannel.rollMode, at: i) ?? "-"
            let pitch = log.textValue(PerspectiveChannel.pitchMode, at: i) ?? "-"
            let current = "\(roll) / \(pitch)"
            if let last, last != current { changes.append("\(Self.clock(log.times[i], tz)) \(current)") }
            last = current
        }
        return changes
    }

    func electricalEvidence(log: PerspectiveLog, window: Range<Int>, tz: TimeZone) -> [EvidenceItem] {
        var items = voltageEvidence(log: log, window: window)
        let amps = log.samples(PerspectiveChannel.amp1, in: window).map(\.value)
        if let lo = amps.min(), let hi = amps.max() {
            items.append(EvidenceItem(label: "Current (amp1)", value: "\(Self.number(lo, 1)) to \(Self.number(hi, 1)) A"))
        }
        if let drop = largestStepDown(log: log, channel: PerspectiveChannel.volt1, window: window) {
            items.append(EvidenceItem(label: "Largest 1-s bus 1 voltage drop",
                                      value: "\(Self.number(drop.size, 1)) V at \(Self.clock(log.times[drop.index], tz))"))
        }
        return items
    }

    func avionicsEvidence(log: PerspectiveLog, window: Range<Int>, tz: TimeZone) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
        var changes: [String] = []
        var last: String?
        for i in window {
            let fix = log.textValue(PerspectiveChannel.gpsFix, at: i) ?? "blank"
            if let last, last != fix { changes.append("\(Self.clock(log.times[i], tz)) \(fix)") }
            last = fix
        }
        if let last {
            items.append(EvidenceItem(label: "GPS fix", value: changes.isEmpty ? "\(last) throughout" : changes.prefix(6).joined(separator: "; ")))
        }
        items += voltageEvidence(log: log, window: window)
        return items
    }

    func engineEvidence(log: PerspectiveLog, window: Range<Int>, tz: TimeZone) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
        let ranged: [(String, String, String, Int)] = [
            ("RPM", PerspectiveChannel.rpm, "", 0),
            ("Manifold pressure", PerspectiveChannel.manifoldPressure, " inHg", 1),
            ("Fuel flow", PerspectiveChannel.fuelFlow, " gph", 1),
            ("Oil pressure", PerspectiveChannel.oilPressure, " psi", 0),
            ("Oil temperature", PerspectiveChannel.oilTemp, " °F", 0),
            ("TIT", PerspectiveChannel.tit1, " °F", 0),
        ]
        for (label, channel, unit, digits) in ranged {
            let v = log.samples(channel, in: window).map(\.value)
            if let lo = v.min(), let hi = v.max() {
                items.append(EvidenceItem(label: label, value: "\(Self.number(lo, digits)) to \(Self.number(hi, digits))\(unit)"))
            }
        }
        if let hottest = hottest(log: log, channels: PerspectiveChannel.cht, window: window) {
            items.append(EvidenceItem(label: "Highest CHT", value: "Cyl \(hottest.cyl): \(Self.number(hottest.value, 0)) °F at \(Self.clock(log.times[hottest.index], tz))"))
        }
        if let spread = maxSpread(log: log, channels: PerspectiveChannel.egt, window: window) {
            items.append(EvidenceItem(label: "Largest EGT spread across cylinders",
                                      value: "\(Self.number(spread.size, 0)) °F at \(Self.clock(log.times[spread.index], tz))"))
        }
        if let rpmDrop = largestStepDown(log: log, channel: PerspectiveChannel.rpm, window: window) {
            items.append(EvidenceItem(label: "Largest 1-s RPM drop",
                                      value: "\(Self.number(rpmDrop.size, 0)) at \(Self.clock(log.times[rpmDrop.index], tz))"))
        }
        return items
    }

    func generalEvidence(log: PerspectiveLog, window: Range<Int>) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
        for (label, channel, unit) in [("RPM", PerspectiveChannel.rpm, ""), ("Indicated airspeed", PerspectiveChannel.ias, " kt"),
                                       ("Baro altitude", PerspectiveChannel.altBaro, " ft")] {
            let v = log.samples(channel, in: window).map(\.value)
            if let lo = v.min(), let hi = v.max() {
                items.append(EvidenceItem(label: label, value: "\(Self.number(lo, 0)) to \(Self.number(hi, 0))\(unit)"))
            }
        }
        return items + voltageEvidence(log: log, window: window)
    }

    private func voltageEvidence(log: PerspectiveLog, window: Range<Int>) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
        for (label, channel) in [("Bus 1 voltage", PerspectiveChannel.volt1), ("Bus 2 voltage", PerspectiveChannel.volt2)] {
            let v = log.samples(channel, in: window).map(\.value)
            if let lo = v.min(), let hi = v.max() {
                items.append(EvidenceItem(label: label, value: "\(Self.number(lo, 1)) to \(Self.number(hi, 1)) V"))
            }
        }
        return items
    }

    // MARK: - Helpers

    private func largestStepDown(log: PerspectiveLog, channel: String, window: Range<Int>) -> (size: Double, index: Int)? {
        let s = log.samples(channel, in: window)
        var best: (Double, Int)?
        for (a, b) in zip(s, s.dropFirst()) where b.index == a.index + 1 {
            let drop = a.value - b.value
            if drop > 0, drop > (best?.0 ?? 0) { best = (drop, b.index) }
        }
        return best.map { (size: $0.0, index: $0.1) }
    }

    private func hottest(log: PerspectiveLog, channels: [String], window: Range<Int>) -> (cyl: Int, value: Double, index: Int)? {
        var best: (Int, Double, Int)?
        for (n, channel) in channels.enumerated() {
            for s in log.samples(channel, in: window) where s.value > (best?.1 ?? -.infinity) {
                best = (n + 1, s.value, s.index)
            }
        }
        return best.map { (cyl: $0.0, value: $0.1, index: $0.2) }
    }

    private func maxSpread(log: PerspectiveLog, channels: [String], window: Range<Int>) -> (size: Double, index: Int)? {
        var best: (Double, Int)?
        for i in window {
            let values = channels.compactMap { log.value($0, at: i) }
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else { continue }
            if hi - lo > (best?.0 ?? -1) { best = (hi - lo, i) }
        }
        return best.map { (size: $0.0, index: $0.1) }
    }

    static func clock(_ date: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static func number(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v)
    }

    /// "42 s before" / "15 s after"
    static func relative(_ secondsBeforeMarker: TimeInterval) -> String {
        let s = Int(secondsBeforeMarker.rounded())
        return s >= 0 ? "\(s) s before" : "\(-s) s after"
    }
}
