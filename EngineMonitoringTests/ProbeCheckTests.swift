import XCTest
@testable import EngineMonitoring

final class ProbeCheckTests: XCTestCase {
    /// Changes one column of a SyntheticFlight CSV for the seconds where `when` is true (t = seconds from the start).
    private func modify(_ csv: String, _ column: String, when: (Int) -> Bool, _ change: (Double) -> String) -> String {
        var lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let c = header.firstIndex(of: column) else { XCTFail("no column \(column)"); return csv }
        for i in 3..<lines.count where !lines[i].isEmpty && when(i - 3) {
            var f = lines[i].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            f[c] = " " + change(Double(f[c].trimmingCharacters(in: .whitespaces)) ?? 0)
            lines[i] = f.joined(separator: ",")
        }
        return lines.joined(separator: "\n")
    }

    private func check(_ csv: String) throws -> (ProbeCheckResult, FlightSummary) {
        let s = FlightSummarizer.summarize(try SyntheticFlight.log("log_260801_080000_18AZ.csv", csv))
        return (try XCTUnwrap(s.probeCheck), s)
    }

    func testNormalFlightHasNoFaults() throws {
        let (r, s) = try check(SyntheticFlight.csv(commonEGTCycle: 40))
        XCTAssertTrue(r.checked)
        XCTAssertTrue(r.faults.isEmpty, "\(r.faults)")
        XCTAssertFalse(s.issues.contains { $0.kind.hasPrefix("probe.") })
    }

    func testSpikesOnOneCHT() throws {
        let csv = modify(SyntheticFlight.csv(), "E1 CHT2", when: { [1500, 1800, 2100].contains($0) }) { String(format: "%.1f", $0 + 80) }
        let (r, s) = try check(csv)
        XCTAssertEqual(r.faults.map(\.kind), [.spike])
        XCTAssertEqual(r.faults.first?.count, 3)
        XCTAssertEqual(s.issues.filter { $0.kind.hasPrefix("probe.") }.map(\.kind), ["probe.cht2"])
    }

    func testDropoutInFlight() throws {
        let csv = modify(SyntheticFlight.csv(), "E1 EGT4", when: { (1600..<1605).contains($0) }) { _ in "" }
        let (r, _) = try check(csv)
        XCTAssertEqual(r.faults.first { $0.kind == .dropout }?.seconds, 5)
        XCTAssertEqual(r.faultyChannels, ["E1 EGT4"])
    }

    func testStuckEGTWhileOthersMove() throws {
        let csv = modify(SyntheticFlight.csv(commonEGTCycle: 40), "E1 EGT3", when: { (1600..<1700).contains($0) }) { _ in "1430.0" }
        let (r, _) = try check(csv)
        XCTAssertGreaterThanOrEqual(r.faults.first { $0.kind == .flatline }?.seconds ?? 0, 60)
        XCTAssertEqual(r.faultyChannels, ["E1 EGT3"])
    }

    func testOneEGTJumpsAndStays() throws {
        let csv = modify(SyntheticFlight.csv(), "E1 EGT5", when: { $0 >= 1600 && $0 < 2520 }) { String(format: "%.1f", $0 + 200) }
        let (r, _) = try check(csv)
        let step = try XCTUnwrap(r.faults.first { $0.kind == .step })
        XCTAssertEqual(step.channel, "E1 EGT5")
        XCTAssertEqual(step.value ?? 0, 200, accuracy: 5)
    }

    func testDeadCHTProbe() throws {
        let csv = modify(SyntheticFlight.csv(), "E1 CHT6", when: { (1500..<1800).contains($0) }) { _ in "40.0" }
        let (r, _) = try check(csv)
        let kinds = Set(r.faults.filter { $0.channel == "E1 CHT6" }.map(\.kind))
        XCTAssertTrue(kinds.contains(.offScale))
        XCTAssertTrue(kinds.contains(.apart))
    }

    func testLabelsAndKinds() {
        XCTAssertEqual(ProbeCheck.label("E1 EGT3"), "EGT 3")
        XCTAssertEqual(ProbeCheck.label("E1 TIT2"), "TIT 2")
        XCTAssertEqual(ProbeCheck.issueKind("E1 OilP"), "probe.oilp")
        XCTAssertEqual(ProbeCheck.issueKind("E1 OilT"), "probe.oilt")
        XCTAssertTrue(IssuePlaybook.guide(for: "probe.egt3").title.contains("EGT 3"))
        XCTAssertTrue(IssuePlaybook.guide(for: "probe.oilp").title.contains("sender"))
    }

    func testReportHasAProbeSection() throws {
        let log = try SyntheticFlight.log("log_260801_080000_18AZ.csv", SyntheticFlight.csv())
        XCTAssertTrue(FlightReport.build(log: log, history: []).markdown().contains("## Probes and wiring"))
    }
}
