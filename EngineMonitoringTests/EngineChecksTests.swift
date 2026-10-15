import XCTest
@testable import EngineMonitoring

/// Synthetic flight for the v0.9.7 checks: taxi, run-up (R then L), full-power takeoff, climb, cruise with an optional
/// lean sweep, a low-power descent and taxi. 1 Hz, Perspective format.
enum EngineFlight {
    struct RunUp {
        var rDrop: Double = 60
        var lDrop: Double = 80
        /// Cylinder whose EGT stays flat on that mag ("R" or "L").
        var cold: (cylinder: Int, mag: String)? = nil
    }

    /// Fuel flow at peak EGT per cylinder (cylinder 3 richest, 5 leanest: spread 0.8 gph).
    static let peaks: [Double] = [15.6, 15.4, 15.9, 15.5, 15.1, 15.3]

    static func egt(_ c: Int, ff: Double) -> Double {
        let d = ff - peaks[c - 1]
        return 1500 - (d > 0 ? 25 : 40) * d * d
    }

    static func csv(day: Int = 1, runUp: RunUp? = RunUp(), takeoffFF: Double = 36, leanRate: Double? = nil,
                    lowPowerHotCylinder: Int? = nil) -> String {
        let lines = PerspectiveFixture.csv.split(separator: "\n", omittingEmptySubsequences: false)
        let header = lines.prefix(3).joined(separator: "\n")
        let columns = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let leanStart = 1800, leanSeconds = leanRate.map { Int(4.0 / $0) } ?? 0
        var rows: [String] = []
        for t in 0..<3360 {
            var v: [String: String] = [:]
            let h = 8 + t / 3600, m = (t / 60) % 60, s = t % 60
            v["Lcl Date"] = String(format: "2026-08-%02ld", day)
            v["Lcl Time"] = String(format: "%02ld:%02ld:%02ld", h, m, s)
            v["UTCOfst"] = "-07:00"
            var rpm = 1000.0, map = 15.0, ff = 8.0, ias = 0.0, vs = 0.0, alt = 1000.0
            var egts = (1...6).map { 1300.0 + Double($0) * 5 }
            switch t {
            case 60..<120:   // run-up
                rpm = 1700
                if let r = runUp {
                    for (mag, start, drop) in [("R", 75, r.rDrop), ("L", 90, r.lDrop)] where (start..<(start + 5)).contains(t) {
                        rpm = 1700 - drop
                        for c in 1...6 { egts[c - 1] += (r.cold?.cylinder == c && r.cold?.mag == mag) ? -5 : 40 }
                    }
                }
            case 180..<195:  // takeoff roll
                rpm = 2700; map = 30.5; ff = takeoffFF; ias = 40
            case 195..<900:  // climb
                rpm = t < 255 ? 2700 : 2600; map = 30.5 - Double(t - 195) * 0.0005; ff = t < 255 ? takeoffFF : 30
                ias = 110; vs = 900; alt = 1000 + Double(t - 195) * 15
            case 900..<2700: // cruise
                rpm = 2500; map = 29.5; ias = 150; alt = 11575
                ff = 15.5
                if leanRate != nil {
                    if (leanStart - 30)..<leanStart ~= t { ff = 17.5 }
                    if let r = leanRate, (leanStart..<(leanStart + leanSeconds + 30)).contains(t) { ff = 17.5 - r * Double(Swift.min(t - leanStart, leanSeconds)) }
                }
                egts = (1...6).map { egt($0, ff: ff) }
            case 2700..<3300: // descent at low manifold pressure
                rpm = 2300; map = 18; ff = 9; ias = 140; vs = -700; alt = 11575 - Double(t - 2700) * 11.7
                egts = (1...6).map { 1300.0 + Double($0) * 5 + ($0 == lowPowerHotCylinder ? 150 : 0) }
            default:
                break
            }
            v["E1 RPM"] = String(format: "%.0f", rpm)
            v["E1 MAP"] = String(format: "%.2f", map)
            v["E1 FFlow"] = String(format: "%.2f", ff)
            v["IAS"] = String(format: "%.0f", ias)
            v["TAS"] = String(format: "%.0f", ias * 1.2)
            v["VSpd"] = String(format: "%.0f", vs)
            v["AltB"] = String(format: "%.0f", alt)
            v["E1 %Pwr"] = t >= 900 && t < 2700 ? "0.75" : "0.40"
            v["E1 OilT"] = "190"; v["E1 OilP"] = "55"
            v["volt1"] = "27.8"; v["volt2"] = "28.8"; v["amp1"] = "3.0"
            v["E1 TIT1"] = "1480"; v["E1 TIT2"] = "1520"
            for c in 1...6 {
                v["E1 CHT\(c)"] = String(330 + c)
                v["E1 EGT\(c)"] = String(format: "%.1f", egts[c - 1])
            }
            rows.append(columns.map { v[$0] ?? "" }.joined(separator: ", "))
        }
        return header + "\n" + rows.joined(separator: "\n") + "\n"
    }

    static func checks(_ csv: String, name: String = "e.csv") throws -> EngineCheckResult {
        let log = try PerspectiveLogParser.parse(text: csv, filename: name)
        return EngineChecks.analyze(log, phases: PhaseClassifier.classify(log))
    }

    /// Summary with only a flight card (fast, for the cross-flight checks).
    static func summary(_ i: Int, card: FlightCard, runups: [MagRunup] = []) -> FlightSummary {
        let start = Date(timeIntervalSince1970: 1_780_000_000 + Double(i) * 86400)
        return FlightSummary(filename: "log_\(i).csv", start: start, end: start.addingTimeInterval(3600), phaseSeconds: [.cruise: 1800],
                             stats: [:], engineChecks: EngineCheckResult(runups: runups, gami: [], card: card))
    }
}

final class EngineChecksTests: XCTestCase {
    func testMagCheckWithinLimits() throws {
        let r = try EngineFlight.checks(EngineFlight.csv())
        XCTAssertEqual(r.runups.count, 1)
        XCTAssertEqual(r.runups.first?.drop("R"), 60)
        XCTAssertEqual(r.runups.first?.drop("L"), 80)
        XCTAssertTrue(r.magFindings.isEmpty)
    }

    func testMagDropOverLimitAndSplit() throws {
        let r = try EngineFlight.checks(EngineFlight.csv(runUp: .init(rDrop: 170, lDrop: 60)))
        XCTAssertTrue(r.magFindings.contains { $0.kind == .drop && $0.mag == "R" })
        XCTAssertTrue(r.magFindings.contains { $0.kind == .split })
        let log = try PerspectiveLogParser.parse(text: EngineFlight.csv(runUp: .init(rDrop: 170, lDrop: 60)), filename: "e.csv")
        XCTAssertTrue(EngineChecks.issues(r, log: log).contains { $0.kind == "mag.drop" && $0.severity == .caution })
    }

    func testColdCylinderOnOneMag() throws {
        let r = try EngineFlight.checks(EngineFlight.csv(runUp: .init(cold: (5, "L"))))
        let f = r.magFindings.first { $0.kind == .coldCylinder }
        XCTAssertEqual(f?.cylinder, 5)
        XCTAssertEqual(f?.mag, "L")
        XCTAssertEqual(r.magFindings.filter { $0.kind == .coldCylinder }.count, 1)
    }

    func testNoRunUpNoMagCheck() throws {
        XCTAssertTrue(try EngineFlight.checks(EngineFlight.csv(runUp: nil)).runups.isEmpty)
    }

    func testGAMISpreadFromASlowLean() throws {
        let r = try EngineFlight.checks(EngineFlight.csv(leanRate: 0.04))
        XCTAssertEqual(r.gami.count, 1)
        let t = try XCTUnwrap(r.gami.first)
        XCTAssertEqual(t.spread, 0.8, accuracy: 0.15)
        XCTAssertEqual(t.richest, 3)
        XCTAssertEqual(t.leanest, 5)
    }

    func testBigMixturePullIsNotALeanTest() throws {
        XCTAssertTrue(try EngineFlight.checks(EngineFlight.csv(leanRate: 0.5)).gami.isEmpty)
        XCTAssertTrue(try EngineFlight.checks(EngineFlight.csv()).gami.isEmpty)
    }

    func testFlightCard() throws {
        let c = try XCTUnwrap(EngineFlight.checks(EngineFlight.csv()).card)
        XCTAssertEqual(c.takeoffRPM ?? 0, 2700, accuracy: 1)
        XCTAssertEqual(c.takeoffFF ?? 0, 36, accuracy: 0.1)
        XCTAssertFalse(c.deckMAP.isEmpty)
        XCTAssertGreaterThanOrEqual(c.cruiseSeconds, FlightCardBuilder.minCruiseSeconds)
        XCTAssertEqual(c.cruisePower ?? 0, 75, accuracy: 0.5)
        XCTAssertEqual(c.cruiseNMPG ?? 0, 180 / 15.5, accuracy: 0.1)
        XCTAssertEqual(c.cruiseTITGap ?? 0, -40, accuracy: 0.1)
        XCTAssertNotNil(c.inductionShift)
    }

    func testInductionShiftShowsTheLeakingCylinder() throws {
        let normal = try XCTUnwrap(EngineFlight.checks(EngineFlight.csv()).card?.inductionShift)
        let leak = try XCTUnwrap(EngineFlight.checks(EngineFlight.csv(lowPowerHotCylinder: 6)).card?.inductionShift)
        XCTAssertGreaterThan(leak[5] - normal[5], 100)
        XCTAssertLessThan(abs(leak[0] - normal[0]), 40)
    }

    func testLowTakeoffFuelFlowIsFlagged() {
        var s = (0..<12).map { i in EngineFlight.summary(i, card: FlightCard(airborneHours: 1, takeoffRPM: 2700, takeoffMAP: 30.5, takeoffFF: 36 + Double(i % 3) * 0.3)) }
        XCTAssertTrue(TurboCheck.issues(s).isEmpty)
        s.append(EngineFlight.summary(12, card: FlightCard(airborneHours: 1, takeoffRPM: 2700, takeoffMAP: 30.5, takeoffFF: 31)))
        XCTAssertEqual(TurboCheck.issues(s).map(\.kind), ["turbo.takeoff-ff"])
    }

    func testInductionIssueNeedsConsecutiveFlights() {
        func card(_ hot: Double) -> FlightCard {
            FlightCard(airborneHours: 1, cruiseEGTDev: [0, 0, 0, 0, 0, 0], lowPowerEGTDev: [0, 0, 0, 0, 0, hot])
        }
        var s = (0..<12).map { i in EngineFlight.summary(i, card: card(Double(i % 4) * 5)) }
        s.append(EngineFlight.summary(12, card: card(120)))
        XCTAssertTrue(TurboCheck.issues(s).isEmpty, "one flight is not enough")
        s.append(EngineFlight.summary(13, card: card(130)))
        XCTAssertEqual(TurboCheck.issues(s).map(\.kind), ["turbo.induction.cyl6"])
    }

    func testReportCardPercentile() {
        var s = (0..<10).map { i in EngineFlight.summary(i, card: FlightCard(airborneHours: 1, cruiseTAS: 160 + Double(i))) }
        s.append(EngineFlight.summary(10, card: FlightCard(airborneHours: 1, cruiseTAS: 175)))
        let row = ReportCard.rows(for: s[10], in: s).first { $0.metric.id == "cruiseTAS" }
        XCTAssertEqual(row?.percentile, 100)
        XCTAssertEqual(row?.earlier, 10)
        XCTAssertEqual(row.flatMap(ReportCard.reading), "among the best")
        XCTAssertEqual(ReportCard.daysSincePrevious(s[10], in: s) ?? 0, 1 - 1.0 / 24, accuracy: 0.01)
    }

    func testPreShopReportListsARepeatedColdCylinder() {
        let cold = MagFinding(kind: .coldCylinder, mag: "L", cylinder: 5, value: -3, other: 40)
        let u = { (i: Int) in
            MagRunup(time: Date(timeIntervalSince1970: 1_780_000_000 + Double(i) * 86400), rpm: 1700, seconds: 40,
                     mags: [MagDrop(mag: "R", time: Date(), drop: 60, seconds: 5, rise: [40, 40, 40, 40, 40, 40]),
                            MagDrop(mag: "L", time: Date(), drop: 80, seconds: 5, rise: [40, 40, 40, 40, -3, 40])],
                     findings: [cold])
        }
        let s = (0..<3).map { EngineFlight.summary($0, card: FlightCard(airborneHours: 1), runups: [u($0)]) }
        let text = PreShopReport.text(summaries: s)
        XCTAssertTrue(text.contains("cylinder 5 on the L mag"))
        XCTAssertTrue(text.contains("PLEASE LOOK AT"))
        XCTAssertEqual(MagCheck.cylinderPattern(s.compactMap { $0.engineChecks?.runups.first })["L"]?[4] ?? nil, -43)
    }

    func testEngineChecksRoundTripThroughJSON() throws {
        let r = try EngineFlight.checks(EngineFlight.csv(runUp: .init(cold: (2, "R")), leanRate: 0.04))
        let data = try EventPersistence.encoder.encode(r)
        XCTAssertEqual(try EventPersistence.decoder.decode(EngineCheckResult.self, from: data), r)
    }
}
