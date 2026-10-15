import XCTest
@testable import EngineMonitoring

final class ValveWatchTests: XCTestCase {
    private func result(_ csv: String) throws -> (ValveWatchResult, FlightSummary) {
        let log = try SyntheticFlight.log("log_260801_080000_18AZ.csv", csv)
        let summary = FlightSummarizer.summarize(log)
        return (try XCTUnwrap(summary.valveWatch), summary)
    }

    func testFlagsOneCylinderCyclingOnceAMinute() throws {
        let (r, s) = try result(SyntheticFlight.csv(egtCycle: (3, 50, 60)))
        XCTAssertGreaterThanOrEqual(r.steadyWindows, 10)
        XCTAssertEqual(r.flagged.map(\.cylinder), [3])
        let c = try XCTUnwrap(r.flagged.first)
        XCTAssertEqual(c.largestCycle ?? 0, 50, accuracy: 5)
        XCTAssertEqual(c.periodSeconds ?? 0, 60, accuracy: 4)
        XCTAssertEqual(s.issues.filter { $0.kind.hasPrefix("valve.") }.map(\.kind), ["valve.cyl3"])
        XCTAssertEqual(s.issues.first { $0.kind == "valve.cyl3" }?.severity, .watch)
    }

    func testFlagsASlowerNinetySecondCycle() throws {
        let (r, _) = try result(SyntheticFlight.csv(egtCycle: (5, 40, 90)))
        XCTAssertEqual(r.flagged.map(\.cylinder), [5])
        XCTAssertEqual(r.flagged.first?.periodSeconds ?? 0, 90, accuracy: 6)
    }

    func testNormalFlightIsNotFlagged() throws {
        let (r, s) = try result(SyntheticFlight.csv())
        XCTAssertTrue(r.checked)
        XCTAssertTrue(r.flagged.isEmpty)
        XCTAssertFalse(s.issues.contains { $0.kind.hasPrefix("valve.") })
    }

    func testAllCylindersSwingingTogetherIsNotAValve() throws {
        let (r, _) = try result(SyntheticFlight.csv(commonEGTCycle: 60))
        XCTAssertTrue(r.flagged.isEmpty)
    }

    func testSmallCycleBelowThirtyDegreesIsNotFlagged() throws {
        let (r, _) = try result(SyntheticFlight.csv(egtCycle: (2, 20, 60)))
        XCTAssertTrue(r.flagged.isEmpty)
    }

    func testProbeSpikesDoNotLookLikeAValve() throws {
        let (r, _) = try result(SyntheticFlight.csv(egtSpikeCylinder: 4))
        XCTAssertTrue(r.checked)
        XCTAssertTrue(r.flagged.isEmpty)
    }

    func testNoSteadyCruiseMeansNotChecked() throws {
        let log = try PerspectiveLogParser.parse(text: PerspectiveFixture.csv, filename: PerspectiveFixture.filename)
        let r = ValveWatch.analyze(log, phases: PhaseClassifier.classify(log))
        XCTAssertFalse(r.checked)
        XCTAssertTrue(r.flagged.isEmpty)
    }

    func testPlaybookExplainsLikelyCauses() {
        let g = IssuePlaybook.guide(for: "valve.cyl3")
        XCTAssertTrue(g.title.contains("Cylinder 3"))
        XCTAssertTrue(g.toResolve.contains { $0.contains("borescope cylinder 3") })
    }

    func testReportHasAValveSection() throws {
        let log = try SyntheticFlight.log("log_260801_080000_18AZ.csv", SyntheticFlight.csv(egtCycle: (3, 50, 60)))
        let md = FlightReport.build(log: log, history: []).markdown()
        XCTAssertTrue(md.contains("## Valve watch"))
        XCTAssertTrue(md.contains("WATCH cylinder 3"))
    }
}
