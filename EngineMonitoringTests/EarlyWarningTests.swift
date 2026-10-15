import XCTest
@testable import EngineMonitoring

final class EarlyWarningTests: XCTestCase {
    /// Deterministic pseudo-random noise in -1...1.
    private struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 2001) / 1000 - 1
        }
    }

    /// `n` one-hour flights a day apart, with optional changes applied to the newest flights.
    private func history(_ n: Int = 45, seed: UInt64 = 7,
                         cht3Rise: Double = 0, oilPressureDrop: Double = 0, egt3TowardBalance: Bool = false) -> [FlightSummary] {
        var noise = Noise(state: seed)
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        return (0..<n).map { i in
            let oat = 10 + 10 * noise.next(), ff = 15.5 + noise.next()
            let late = Double(max(0, i - (n - 10)))   // 0 except the newest 10 flights
            let cht: [Double?] = (1...6).map { c in
                330 + Double(c) * 3 + 0.8 * oat + 3 * noise.next() + (c == 3 ? cht3Rise * late : 0)
            }
            let dev: [Double?] = (1...6).map { c in
                (c == 3 ? (egt3TowardBalance ? 45 - 4 * late : 45) : -9) + 3 * noise.next()
            }
            let t = EngineTrendMetrics(steadySeconds: 1800, oat: oat, fuelFlow: ff, cht: cht, egtDev: dev,
                                       chtSpread: 40 + 3 * noise.next(), egtSpread: 70 + 4 * noise.next(),
                                       oilTemp: 185 + 0.6 * oat + 2 * noise.next(),
                                       oilPressure: 53 + noise.next() - oilPressureDrop * late,
                                       titDiff: -30 + 5 * noise.next(), volt1: 27.9 + 0.03 * noise.next(), volt2: 28.7 + 0.03 * noise.next())
            let s = start.addingTimeInterval(Double(i) * 86_400)
            return FlightSummary(filename: "log_\(i).csv", start: s, end: s.addingTimeInterval(3600),
                                 phaseSeconds: [.cruise: 3600], stats: [:], engineTrend: t)
        }
    }

    func testNormalHistoryHasNoWarnings() {
        let r = EarlyWarning.analyze(history())
        XCTAssertFalse(r.analyses.isEmpty)
        XCTAssertTrue(r.findings.isEmpty, "\(r.findings.map(\.metric.id))")
        XCTAssertNil(r.level)
    }

    func testRisingCylinderCHTIsCaught() throws {
        let r = EarlyWarning.analyze(history(cht3Rise: 4))
        XCTAssertEqual(r.findings.map(\.metric.id), ["cht3"])
        let p = try XCTUnwrap(r.patterns.first)
        XCTAssertEqual(p.cylinder, 3)
        XCTAssertTrue(p.title.contains("hotter"))
        XCTAssertEqual(EarlyWarning.issues(r).map(\.kind), ["early.cht3"])
    }

    func testFallingOilPressureIsCaught() {
        let r = EarlyWarning.analyze(history(oilPressureDrop: 0.8))
        XCTAssertTrue(r.findings.contains { $0.metric.id == "oilp" })
        XCTAssertTrue(r.patterns.contains { $0.title.contains("Oil pressure") })
    }

    func testMovingTowardBalanceIsNotAWarning() {
        let r = EarlyWarning.analyze(history(egt3TowardBalance: true))
        XCTAssertFalse(r.findings.contains { $0.metric.id == "egtgap3" })
    }

    func testNeedsEnoughFlights() {
        let r = EarlyWarning.analyze(history(20))
        XCTAssertTrue(r.analyses.isEmpty)
        XCTAssertEqual(r.flightsUsed, 20)
    }

    func testStatistics() {
        XCTAssertGreaterThan(EarlyWarning.mannKendall((0..<10).map(Double.init)), 2.75)
        XCTAssertEqual(EarlyWarning.mannKendall([1, 1, 1, 1]), 0)
        let c = EarlyWarning.leastSquares([[1, 2], [2, 1], [3, 5], [4, 3]], [1 + 2 * 1 + 3 * 2, 1 + 2 * 2 + 3 * 1, 1 + 2 * 3 + 3 * 5, 1 + 2 * 4 + 3 * 3])
        XCTAssertEqual(c[0], 1, accuracy: 1e-3)
        XCTAssertEqual(c[1], 2, accuracy: 1e-3)
        XCTAssertEqual(c[2], 3, accuracy: 1e-3)
        XCTAssertEqual(EarlyWarning.theilSen([0, 1, 2, 3], [1, 3, 5, 7]), 2, accuracy: 1e-9)
    }

    func testFlightSummaryCarriesTrendMetrics() throws {
        let s = FlightSummarizer.summarize(try SyntheticFlight.log("log_260801_080000_18AZ.csv", SyntheticFlight.csv()))
        let t = try XCTUnwrap(s.engineTrend)
        XCTAssertGreaterThan(t.steadySeconds, 1000)
        XCTAssertEqual(t.cht.count, 6)
        XCTAssertEqual(t.oilPressure ?? 0, 55, accuracy: 0.1)
        XCTAssertNotNil(TrendMetric.named("cht3")?.value(in: s))
    }

    func testPlaybookGuide() {
        XCTAssertTrue(IssuePlaybook.guide(for: "early.oilp").title.contains("Oil pressure"))
    }
}
