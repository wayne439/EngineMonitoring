import XCTest
@testable import EngineMonitoring

/// Builds Perspective-format logs of a simple flight: 2 min ground, 10 min climb, 30 min cruise, 8 min descent.
enum SyntheticFlight {
    /// `egtCycle`: one cylinder's EGT swinging in cruise (valve watch); `commonEGTCycle`: all cylinders swinging together
    /// (peak to peak, 55 s); `egtSpikeCylinder`: a 400 °F probe spike on that cylinder every 400 s.
    static func csv(day: Int = 1, chtOffset: Double = 0, cruiseRPM: Double = 2500, overspeedSeconds: Int = 0, oilTempPeak: Double = 200,
                    egtCycle: (cylinder: Int, peakToPeak: Double, period: Double)? = nil, commonEGTCycle: Double = 0,
                    egtSpikeCylinder: Int? = nil) -> String {
        let lines = PerspectiveFixture.csv.split(separator: "\n", omittingEmptySubsequences: false)
        let header = lines.prefix(3).joined(separator: "\n")
        let columns = lines[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var rows: [String] = []
        let total = 50 * 60
        for t in 0..<total {
            var v: [String: String] = [:]
            let h = 8 + t / 3600, m = (t / 60) % 60, s = t % 60
            v["Lcl Date"] = String(format: "2026-08-%02d", day)
            v["Lcl Time"] = String(format: "%02d:%02d:%02d", h, m, s)
            v["UTCOfst"] = "-07:00"
            let phase: String
            switch t {
            case ..<120: phase = "ground"
            case ..<720: phase = "climb"
            case ..<2520: phase = "cruise"
            default: phase = "descent"
            }
            var rpm = phase == "ground" ? 1000 : (phase == "climb" ? 2700 : (phase == "cruise" ? cruiseRPM : 2300))
            if phase == "cruise", t - 720 < overspeedSeconds { rpm = 2740 }
            v["E1 RPM"] = String(rpm)
            v["IAS"] = phase == "ground" ? "0" : "130"
            v["VSpd"] = phase == "climb" ? "900" : (phase == "descent" ? "-700" : "0")
            v["E1 OilT"] = String(phase == "cruise" ? oilTempPeak : 190)
            v["E1 OilP"] = "55"
            v["volt1"] = "27.8"; v["volt2"] = "28.8"; v["amp1"] = "3.0"
            v["E1 FFlow"] = phase == "climb" ? "35" : "15"
            v["E1 MAP"] = "29.0"
            v["E1 TIT1"] = phase == "climb" ? "1270" : "1500"
            for c in 1...6 {
                let base = phase == "cruise" ? 340.0 : 320.0
                v["E1 CHT\(c)"] = String(base + Double(c) + (c == 3 ? chtOffset : 0))
                var egt = Double(1400 + c * 10)
                if phase == "cruise" {
                    egt += commonEGTCycle / 2 * sin(2 * Double.pi * Double(t) / 55)
                    if let e = egtCycle, e.cylinder == c { egt += e.peakToPeak / 2 * sin(2 * Double.pi * Double(t) / e.period) }
                    if egtSpikeCylinder == c, t % 400 == 0 { egt += 400 }
                }
                v["E1 EGT\(c)"] = String(format: "%.1f", egt)
            }
            rows.append(columns.map { v[$0] ?? "" }.joined(separator: ", "))
        }
        return header + "\n" + rows.joined(separator: "\n") + "\n"
    }

    static func log(_ name: String, _ csv: String) throws -> PerspectiveLog {
        try PerspectiveLogParser.parse(text: csv, filename: name)
    }
}

final class FlightAnalysisTests: XCTestCase {
    func testPhaseClassification() throws {
        let log = try SyntheticFlight.log("a.csv", SyntheticFlight.csv())
        let s = FlightSummarizer.summarize(log)
        XCTAssertEqual(s.phaseSeconds[.ground], 120)
        XCTAssertEqual(s.phaseSeconds[.climb] ?? 0, 600, accuracy: 10)
        XCTAssertEqual(s.phaseSeconds[.cruise] ?? 0, 1800, accuracy: 10)
        XCTAssertTrue(s.isFlight)
        XCTAssertEqual(s.stats[.cruise]?[.rpm]?.p50, 2500)
        XCTAssertEqual(s.stats[.cruise]?[.cht3]?.p50, 343)
    }

    func testSummaryRoundTripsThroughJSON() throws {
        let s = FlightSummarizer.summarize(try SyntheticFlight.log("a.csv", SyntheticFlight.csv()))
        let data = try EventPersistence.encoder.encode(s)
        XCTAssertEqual(try EventPersistence.decoder.decode(FlightSummary.self, from: data), s)
    }

    func testNoFlagsForANormalFlight() throws {
        let history = try (1...6).map { FlightSummarizer.summarize(try SyntheticFlight.log("h\($0).csv", SyntheticFlight.csv(day: $0))) }
        let report = FlightReport.build(log: try SyntheticFlight.log("new.csv", SyntheticFlight.csv(day: 20)), history: history)
        XCTAssertEqual(report.baselineFlights, 6)
        XCTAssertTrue(report.approvedExceedances.isEmpty)
        XCTAssertTrue(report.deviations.isEmpty)
    }

    func testHotCylinderIsFlaggedAgainstNormal() throws {
        let history = try (1...6).map { FlightSummarizer.summarize(try SyntheticFlight.log("h\($0).csv", SyntheticFlight.csv(day: $0, chtOffset: Double($0)))) }
        let report = FlightReport.build(log: try SyntheticFlight.log("new.csv", SyntheticFlight.csv(day: 20, chtOffset: 30)), history: history)
        let cruise = report.deviations.first { $0.phase == .cruise && $0.metric == .cht3 }
        XCTAssertNotNil(cruise)
        XCTAssertEqual(cruise?.direction, "above")
        XCTAssertFalse(report.deviations.contains { $0.metric == .cht1 })
    }

    func testBaselineNeedsFiveFlights() throws {
        let history = try (1...4).map { FlightSummarizer.summarize(try SyntheticFlight.log("h\($0).csv", SyntheticFlight.csv(day: $0))) }
        XCTAssertTrue(Baseline.build(from: history).ranges.isEmpty)
    }

    func testReportExcludesTheFlightItselfFromItsBaseline() throws {
        let csv = SyntheticFlight.csv(day: 9)
        let own = FlightSummarizer.summarize(try SyntheticFlight.log("same.csv", csv))
        let report = FlightReport.build(log: try SyntheticFlight.log("same.csv", csv), history: [own])
        XCTAssertEqual(report.baselineFlights, 0)
    }

    func testOverspeedNeedsTheAnnunciationDuration() throws {
        // 4 s above 2,730 RPM: below the POH's "more than 5 s", so no warning.
        let short = FlightReport.build(log: try SyntheticFlight.log("s.csv", SyntheticFlight.csv(overspeedSeconds: 4)), history: [])
        XCTAssertFalse(short.approvedExceedances.contains { $0.limit.id == "rpm-overspeed" })
        // 20 s: warning, with the duration and peak reported.
        let long = FlightReport.build(log: try SyntheticFlight.log("l.csv", SyntheticFlight.csv(overspeedSeconds: 20)), history: [])
        let e = long.approvedExceedances.first { $0.limit.id == "rpm-overspeed" }
        XCTAssertEqual(e?.seconds, 20)
        XCTAssertEqual(e?.extreme, 2740)
    }

    func testOilTemperatureLimit() throws {
        let report = FlightReport.build(log: try SyntheticFlight.log("o.csv", SyntheticFlight.csv(oilTempPeak: 245)), history: [])
        XCTAssertTrue(report.approvedExceedances.contains { $0.limit.id == "oilt-max" })
        XCTAssertTrue(report.markdown().contains("Oil temperature above 240"))
    }

    func testTechniqueReferencesAreNotApprovedLimits() {
        for limit in AircraftKnowledge.limits where limit.source.contains("Barker") {
            XCTAssertEqual(limit.authority, .experience)
            XCTAssertEqual(limit.kind, .reference)
        }
        XCTAssertFalse(AircraftKnowledge.limits.contains { $0.metric == .tit && $0.authority == .approved },
                       "No approved TIT limit: TIT is a technique reference only")
    }

    func testMarkdownReportMentionsMissingSupplement() throws {
        let report = FlightReport.build(log: try SyntheticFlight.log("m.csv", SyntheticFlight.csv()), history: [])
        let md = report.markdown()
        XCTAssertTrue(md.contains("TIT and manifold-pressure limits are not checked"))
        XCTAssertTrue(md.contains("No cause is assigned"))
    }

    func testSummariesPersistWithImport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = FlightLogLibrary(baseDirectory: dir)
        let result = try library.importLog(data: Data(SyntheticFlight.csv().utf8), originalFilename: "log_x.csv", existing: [])
        XCTAssertNotNil(library.loadSummary(for: result.entry.filename))
        XCTAssertEqual(library.loadOrBuildSummaries(for: result.index).count, 1)
        _ = try library.delete(result.entry, from: result.index)
        XCTAssertNil(library.loadSummary(for: result.entry.filename))
    }
}

final class SystemHistoryTests: XCTestCase {
    private func fixtureSummary() throws -> FlightSummary {
        FlightSummarizer.summarize(try PerspectiveLogParser.parse(text: PerspectiveFixture.csv, filename: PerspectiveFixture.filename))
    }

    func testEngineStartsAreKeptInTheSummary() throws {
        let s = try fixtureSummary()
        XCTAssertEqual(s.starts.count, 1)
        let start = try XCTUnwrap(s.starts.first)
        XCTAssertEqual(start.crankingEpisodes, 1)
        XCTAssertEqual(start.minVolt1, 20.1)
        XCTAssertEqual(start.peakFuelFlow, 8.0)
        XCTAssertEqual(start.rpmAfter30s, 1000)
        XCTAssertEqual(start.weakestCylinder?.cylinder, 3)
        XCTAssertEqual(start.weakestCylinder?.rise, 300)
    }

    func testAutopilotChangesAreKept() throws {
        let s = try fixtureSummary()
        XCTAssertEqual(s.afcsChanges.map(\.engaged), [true, false])
        XCTAssertEqual(s.afcsDisengagements, 1)
    }

    func testLogStartingWithEngineRunningHasNoStart() throws {
        let log = try SyntheticFlight.log("r.csv", SyntheticFlight.csv())
        // The synthetic flight begins at 1,000 RPM: the start happened before the log.
        XCTAssertTrue(FlightSummarizer.summarize(log).starts.isEmpty)
    }

    func testOldSummariesAreRebuilt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = FlightLogLibrary(baseDirectory: dir)
        let result = try library.importLog(data: Data(PerspectiveFixture.csv.utf8), originalFilename: PerspectiveFixture.filename, existing: [])
        // Simulate a v0.4 summary: no version, no starts.
        let url = library.directory.appendingPathComponent("Summaries/\(result.entry.filename).summary.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        for key in ["version", "starts", "afcsChanges"] { json[key] = nil }
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertEqual(library.loadSummary(for: result.entry.filename)?.isCurrent, false)
        let rebuilt = library.loadOrBuildSummaries(for: result.index)
        XCTAssertEqual(rebuilt.first?.starts.count, 1)
        XCTAssertEqual(library.loadSummary(for: result.entry.filename)?.isCurrent, true)
    }
}

final class POHTests: XCTestCase {
    /// Small hand-made index; the real one is checked in BundledContentTests.
    private let index = POHIndex(
        document: .init(title: "POH", partNumber: "13772-002", revision: "A", filename: "POH.pdf", pageCount: 3,
                        authority: .approved, note: ""),
        procedures: [
            .init(id: "3-engine-partial-power-loss", title: "Engine Partial Power Loss", group: "Engine", kind: .emergency, label: "3-17", pdfPage: 1),
            .init(id: "3-oil-pressure-out-of-range", title: "Oil Pressure Out of Range", group: "Engine", kind: .emergency, label: "3-19", pdfPage: 2),
        ],
        pages: [
            .init(pdfPage: 1, label: "3-17", section: "Section 3 - Emergency Procedures",
                  text: "Cirrus Design Section 3 SR22 Emergency Procedures 3-17 Engine Partial Power Loss 1. Fuel Pump ........ BOOST 2. Fuel Selector ........ SWITCH TANKS"),
            .init(pdfPage: 2, label: "3-18", section: "Section 3 - Emergency Procedures",
                  text: "Cirrus Design Section 3 SR22 Emergency Procedures 3-18 continued text. Oil Pressure Out of Range OIL PRESS Warning 1. Oil Pressure Gage ........ CHECK"),
            .init(pdfPage: 3, label: "7-30", section: "Section 7 - Systems Description",
                  text: "Cirrus Design Section 7 Systems Fuel quantity is measured by float sensors."),
        ])

    func testProcedureTextStopsAtNextProcedure() {
        let text = index.text(for: index.procedures[0])
        XCTAssertTrue(text.hasPrefix("Engine Partial Power Loss"))
        XCTAssertTrue(text.contains("continued text"))
        XCTAssertFalse(text.contains("Oil Pressure Gage"))
    }

    func testSearchRequiresAllWordsAndRanksProcedures() {
        let hits = POHSearch.search("oil pressure", in: index)
        XCTAssertEqual(hits.first?.page.label, "3-18")
        XCTAssertTrue(POHSearch.search("oil zebra", in: index).isEmpty)
    }

    func testShortTermsMatchWholeWordsOnly() {
        // "tit" must not match "quantity".
        XCTAssertTrue(POHSearch.search("tit", in: index).isEmpty)
    }

    func testSynonyms() {
        XCTAssertEqual(POHSearch.tokenize("CHT"), [["cylinder head temperature", "cht"]])
    }

    func testReadableFormatting() {
        let out = POHFormatter.readable("Engine Partial Power Loss 1. Fuel Pump ........ BOOST 2. Fuel Selector ........ SWITCH TANKS")
        XCTAssertEqual(out, "Engine Partial Power Loss\n1. Fuel Pump … BOOST\n2. Fuel Selector … SWITCH TANKS")
    }

    func testGroupedProceduresKeepOrder() {
        let groups = index.groupedProcedures(.emergency)
        XCTAssertEqual(groups.map(\.name), ["Engine"])
        XCTAssertEqual(groups[0].items.map(\.label), ["3-17", "3-19"])
    }
}
