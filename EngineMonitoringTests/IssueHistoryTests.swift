import XCTest
@testable import EngineMonitoring

/// Builds Perspective CSVs second by second for issue-detection tests.
enum IssueFixture {
    static func csv(seconds: Int, _ values: (Int) -> [String: String]) -> String {
        let lines = PerspectiveFixture.csv.split(separator: "\n", omittingEmptySubsequences: false)
        let header = lines.prefix(3).joined(separator: "\n")
        let columns = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var rows: [String] = []
        for t in 0..<seconds {
            var v: [String: String] = ["Lcl Date": "2026-08-01", "UTCOfst": "-07:00",
                                       "volt1": "27.8", "volt2": "28.8", "amp1": "3.0", "E1 OilT": "190",
                                       "IAS": "0", "VSpd": "0", "E1 FFlow": "10", "E1 MAP": "20"]
            v["Lcl Time"] = String(format: "%02d:%02d:%02d", 8 + t / 3600, (t / 60) % 60, t % 60)
            for c in 1...6 { v["E1 CHT\(c)"] = "300"; v["E1 EGT\(c)"] = "1300" }
            for (k, x) in values(t) { v[k] = x }
            rows.append(columns.map { v[$0] ?? "" }.joined(separator: ", "))
        }
        return header + "\n" + rows.joined(separator: "\n") + "\n"
    }

    static func summary(_ name: String, seconds: Int, _ values: (Int) -> [String: String]) throws -> FlightSummary {
        FlightSummarizer.summarize(try PerspectiveLogParser.parse(text: csv(seconds: seconds, values), filename: name))
    }
}

final class IssueHistoryTests: XCTestCase {
    /// Caught, stopped, caught again (like a real start seen in testing).
    func testStartThatStopsIsRecorded() throws {
        let s = try IssueFixture.summary("start.csv", seconds: 200) { t in
            let rpm: Double
            switch t {
            case ..<10: rpm = 0
            case ..<15: rpm = 700      // caught
            case ..<60: rpm = 0        // stopped
            case ..<64: rpm = 200      // cranking
            default: rpm = 1000        // running
            }
            return ["E1 RPM": String(rpm), "E1 OilP": t > 70 ? "60" : "0"]
        }
        let kinds = s.issues.map(\.kind)
        XCTAssertTrue(kinds.contains("start.stopped"), "\(kinds)")
        XCTAssertFalse(kinds.contains("limit.oilp-min"), "oil pressure gets 30 s after a start")
        XCTAssertEqual(s.issues.first { $0.kind == "start.stopped" }?.system, .engineStart)
    }

    func testOilPressureSlowAfterStart() throws {
        let s = try IssueFixture.summary("oil.csv", seconds: 120) { t in
            ["E1 RPM": t < 10 ? "0" : "1000", "E1 OilP": t < 45 ? "5" : "60"]
        }
        XCTAssertTrue(s.issues.contains { $0.kind == "start.oil-pressure" })
    }

    func testIdleOilPressureOnGroundIsWatchNotCaution() throws {
        let s = try IssueFixture.summary("idle.csv", seconds: 300) { t in
            ["E1 RPM": t < 5 ? "0" : "1050", "E1 OilP": t < 100 ? "60" : "27"]
        }
        let idle = s.issues.first { $0.kind == "limit.oilp-idle" }
        XCTAssertEqual(idle?.severity, .watch)
        XCTAssertFalse(s.issues.contains { $0.kind == "limit.oilp-caution" })
    }

    func testLowBusVoltageOnlyCountsInFlight() throws {
        // Alternators off after the start (POH 4-10): low volts on the ground are not an issue.
        let ground = try IssueFixture.summary("g.csv", seconds: 300) { t in
            ["E1 RPM": t < 5 ? "0" : "1600", "E1 OilP": "60", "volt2": "23.8"]
        }
        XCTAssertFalse(ground.issues.contains { $0.kind == "limit.volt2-low" })
        let air = try IssueFixture.summary("a.csv", seconds: 900) { t in
            ["E1 RPM": "2500", "E1 OilP": "60", "IAS": "140", "VSpd": "0", "volt2": t > 300 && t < 400 ? "23.8" : "28.8"]
        }
        XCTAssertTrue(air.issues.contains { $0.kind == "limit.volt2-low" && $0.severity == .caution })
    }

    func testCleanSyntheticFlightHasNoApprovedIssues() throws {
        let s = FlightSummarizer.summarize(try SyntheticFlight.log("clean.csv", SyntheticFlight.csv()))
        XCTAssertTrue(s.issues.filter { $0.kind.hasPrefix("limit.") }.isEmpty, "\(s.issues.map(\.kind))")
    }

    func testOverspeedBecomesWarningIssue() throws {
        let s = FlightSummarizer.summarize(try SyntheticFlight.log("os.csv", SyntheticFlight.csv(overspeedSeconds: 20)))
        let i = s.issues.first { $0.kind == "limit.rpm-overspeed" }
        XCTAssertEqual(i?.severity, .warning)
        XCTAssertEqual(IssuePlaybook.guide(for: "limit.rpm-overspeed").pohProcedureID, "3-engine-speed-high")
    }

    func testSummaryRoundTripsIssues() throws {
        let s = FlightSummarizer.summarize(try SyntheticFlight.log("os.csv", SyntheticFlight.csv(overspeedSeconds: 20)))
        XCTAssertEqual(s.version, FlightSummary.currentVersion)
        let back = try EventPersistence.decoder.decode(FlightSummary.self, from: EventPersistence.encoder.encode(s))
        XCTAssertEqual(back.issues, s.issues)
        XCTAssertEqual(back.utcOffsetSeconds, -25200)
    }

    private func oilSlow(_ name: String, day: Int = 1) throws -> FlightSummary {
        let csv = IssueFixture.csv(seconds: 120) { t in ["E1 RPM": t < 10 ? "0" : "1000", "E1 OilP": t < 45 ? "5" : "60"] }
            .replacingOccurrences(of: "2026-08-01", with: String(format: "2026-08-%02d", day))
        return FlightSummarizer.summarize(try PerspectiveLogParser.parse(text: csv, filename: name))
    }

    func testUnreviewedWatchItemNeedsReview() throws {
        let g = try XCTUnwrap(IssueHistory.build(summaries: [oilSlow("a.csv")], records: [:], includeRecords: false)
            .first { $0.kind == "start.oil-pressure" })
        XCTAssertTrue(g.needsReview)
        XCTAssertEqual(g.newOccurrences.count, 1)
    }

    func testReviewCoversOccurrencesAndNewOnesComeBack() throws {
        let first = try oilSlow("a.csv", day: 1)
        var record = IssueStatusRecord(status: .open)
        let covered = try XCTUnwrap(first.issues.first { $0.kind == "start.oil-pressure" }).time
        record.apply(IssueReview(date: Date(), action: .reviewed, reviewedBy: "Pilot", discovered: "Sender connector loose",
                                 actionTaken: "", reference: "", coversThrough: covered))
        var g = try XCTUnwrap(IssueHistory.build(summaries: [first], records: ["start.oil-pressure": record], includeRecords: false)
            .first { $0.kind == "start.oil-pressure" })
        XCTAssertFalse(g.needsReview)
        XCTAssertEqual(g.effectiveStatus, .reviewed)

        // A later flight with the same issue is NEW and needs review again.
        let second = try oilSlow("b.csv", day: 5)
        g = try XCTUnwrap(IssueHistory.build(summaries: [first, second], records: ["start.oil-pressure": record], includeRecords: false)
            .first { $0.kind == "start.oil-pressure" })
        XCTAssertTrue(g.needsReview)
        XCTAssertEqual(g.newOccurrences.map(\.source), ["b.csv"])
        XCTAssertEqual(g.effectiveStatus, .reviewed)
    }

    func testCompletedThenRecurredIsOpen() throws {
        let first = try oilSlow("a.csv", day: 1)
        var record = IssueStatusRecord(status: .open)
        let covered = try XCTUnwrap(first.issues.first { $0.kind == "start.oil-pressure" }).time
        record.apply(IssueReview(date: covered.addingTimeInterval(3600), action: .completed, reviewedBy: "A&P",
                                 discovered: "Sender failed", actionTaken: "Sender replaced", reference: "WO 123", coversThrough: covered))
        XCTAssertEqual(record.status, .completed)
        XCTAssertNotNil(record.completedOn)
        var g = try XCTUnwrap(IssueHistory.build(summaries: [first], records: ["start.oil-pressure": record], includeRecords: false).first)
        XCTAssertEqual(g.effectiveStatus, .completed)
        XCTAssertFalse(g.recurredAfterCompletion)
        g = try XCTUnwrap(IssueHistory.build(summaries: [first, try oilSlow("b.csv", day: 9)], records: ["start.oil-pressure": record],
                                             includeRecords: false).first)
        XCTAssertTrue(g.recurredAfterCompletion)
        XCTAssertEqual(g.effectiveStatus, .open)
        XCTAssertTrue(g.needsReview)
    }

    func testReviewLogExportListsFindings() throws {
        let first = try oilSlow("a.csv")
        var record = IssueStatusRecord(status: .open)
        record.apply(IssueReview(date: Date(), action: .monitoring, reviewedBy: "Pilot", discovered: "Cold morning, short prime",
                                 actionTaken: "Longer prime next time", reference: "", coversThrough: first.end))
        let groups = IssueHistory.build(summaries: [first], records: ["start.oil-pressure": record], includeRecords: false)
        let md = IssueHistory.reviewLogMarkdown(groups)
        XCTAssertTrue(md.contains("start.oil-pressure"))
        XCTAssertTrue(md.contains("Discovered: Cold morning, short prime"))
        XCTAssertTrue(md.contains("Monitoring"))
    }

    func testV06StatusFileStillLoads() throws {
        let json = #"{"start.stopped":{"status":"Resolved","note":"Injectors cleaned","resolvedOn":"2026-10-01T12:00:00Z","updated":"2026-10-01T12:00:00Z"}}"#
        let records = try EventPersistence.decoder.decode([String: IssueStatusRecord].self, from: Data(json.utf8))
        let r = try XCTUnwrap(records["start.stopped"])
        XCTAssertEqual(r.status, .completed)
        XCTAssertEqual(r.reviews.first?.discovered, "Injectors cleaned")
        XCTAssertNotNil(r.reviewedThrough)
        let back = try EventPersistence.decoder.decode(IssueStatusRecord.self, from: EventPersistence.encoder.encode(r))
        XCTAssertEqual(back, r)
    }

    func testRecordsItemsAreIncludedWithGuides() {
        let groups = IssueHistory.build(summaries: [], records: [:])
        XCTAssertTrue(groups.contains { $0.kind == "record.oil-nickel" })
        for g in groups { XCTAssertFalse(g.guide.toResolve.isEmpty, g.kind) }
    }

    func testEveryDetectedKindHasASpecificGuide() {
        let generic = IssuePlaybook.guide(for: "no.such.kind").title
        for kind in ["start.stopped", "start.extra-cranking", "start.oil-pressure", "limit.oilp-idle", "limit.oilp-caution",
                     "limit.oilp-min", "limit.cht-caution", "limit.volt1-low", "limit.volt2-low", "electrical.voltage-drop",
                     "avionics.gps-loss", "trend.Cruise.oilTemp.high", "technique.barker-tit"] {
            XCTAssertNotEqual(IssuePlaybook.guide(for: kind).title, generic, kind)
        }
        for limit in AircraftKnowledge.limits where limit.authority == .approved {
            XCTAssertNotEqual(IssuePlaybook.guide(for: "limit." + limit.id).title, generic, limit.id)
        }
    }

    // MARK: - OAT and TIT

    private func cruise(_ name: String, oat: Double, oilT: Double, tit1: Double = 1480, tit2: Double = 1540) -> FlightSummary {
        let stats: [FlightMetric: MetricStats] = [.oat: MetricStats(Array(repeating: oat, count: 100))!,
                                                  .oilTemp: MetricStats(Array(repeating: oilT, count: 100))!]
        return FlightSummary(filename: name, start: Date(), end: Date(), phaseSeconds: [.cruise: 1800], stats: [.cruise: stats])
    }

    func testOilTemperatureIsComparedAtTheSameOAT() throws {
        // the aircraft pattern: oil temperature rises about 1 °F per °C of OAT.
        var flights: [FlightSummary] = []
        for (i, oat) in stride(from: 0.0, through: 36.0, by: 3.0).enumerated() {
            flights.append(cruise("f\(i).csv", oat: oat, oilT: 174 + oat + (i.isMultiple(of: 2) ? 2 : -2)))
        }
        let baseline = Baseline.build(from: flights)
        let hotDay = try XCTUnwrap(baseline.range(.cruise, .oilTemp, oat: 38))
        let coldDay = try XCTUnwrap(baseline.range(.cruise, .oilTemp, oat: 2))
        XCTAssertEqual(hotDay.oat, 38)
        // 212 °F is normal at 38 °C but well above normal at 2 °C.
        XCTAssertTrue(212 >= hotDay.low - 1 && 212 <= hotDay.high + 1, "\(hotDay)")
        XCTAssertGreaterThan(212, coldDay.high)
        let plain = try XCTUnwrap(baseline.ranges[.cruise]?[.oilTemp])
        XCTAssertNil(plain.oat)
    }

    func testTrendUsesOATAdjustedRange() {
        var flights: [FlightSummary] = []
        for (i, oat) in stride(from: 0.0, through: 36.0, by: 3.0).enumerated() {
            flights.append(cruise("f\(i).csv", oat: oat, oilT: 174 + oat + (i.isMultiple(of: 2) ? 2 : -2)))
        }
        flights.append(cruise("hot_day_KPHX.csv", oat: 38, oilT: 212))
        flights.append(cruise("cold_day_KPRC.csv", oat: 2, oilT: 212))
        let trends = IssueDetector.trendIssues(flights)
        XCTAssertFalse(trends.contains { $0.source == "hot_day_KPHX.csv" })
        let cold = trends.first { $0.source == "cold_day_KPRC.csv" && $0.kind == "trend.Cruise.oilTemp.high" }
        XCTAssertNotNil(cold)
        XCTAssertTrue(cold?.detail.contains("for OAT 2 °C") ?? false)
        XCTAssertTrue(cold?.detail.contains("from KPRC") ?? false)
    }

    func testTITUsesTheHotterTurbo() throws {
        let csv = IssueFixture.csv(seconds: 100) { _ in ["E1 RPM": "2500", "E1 TIT1": "1480", "E1 TIT2": "1545", "E1 OilP": "55", "OAT": "12"] }
        let log = try PerspectiveLogParser.parse(text: csv, filename: "t.csv")
        XCTAssertEqual(FlightMetric.tit.value(in: log, at: 10), 1545)
        XCTAssertEqual(FlightMetric.tit1.value(in: log, at: 10), 1480)
        XCTAssertEqual(FlightMetric.tit2.value(in: log, at: 10), 1545)
        XCTAssertEqual(FlightMetric.oat.value(in: log, at: 10), 12)
    }

    func testDepartureAirportFromFilename() {
        XCTAssertEqual(cruise("log_260715_063701_KPRC.csv", oat: 0, oilT: 0).departure, "KPRC")
        XCTAssertEqual(cruise("log_260616_121550_18AZ.csv", oat: 0, oilT: 0).departure, "18AZ")
        XCTAssertNil(cruise("log_260616_121550______.csv", oat: 0, oilT: 0).departure)
    }
}
