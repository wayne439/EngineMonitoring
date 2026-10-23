import XCTest
@testable import EngineMonitoring

/// A synthetic departure and return to the same field (elevation 2,500 ft).
enum TechniqueFixture {
    static func circuit(finalIAS: Double = 82, finalSink: Double = 700, bankAt300: Double = 0, climbIAS: Double = 112) -> String {
        IssueFixture.csv(seconds: 900) { t in
            var v: [String: String] = ["E1 OilP": "60", "E1 MAP": "29", "E1 FFlow": "35", "Latitude": "33.8", "Longitude": "-111.9"]
            var ias = 0.0, alt = 2500.0, vs = 0.0, rpm = 1000.0, roll = 0.0
            switch t {
            case ..<60: rpm = 1000                                         // taxi
            case ..<80: rpm = 2700; ias = Double(t - 60) * 4              // takeoff roll to 80 kt
            case ..<230: rpm = 2700; ias = climbIAS; vs = 800; alt = 2500 + Double(t - 80) * 800 / 60
            case ..<600: rpm = 2400; ias = 140; alt = 4500                // cruise
            case ..<700: rpm = 2000; ias = 110; vs = -1200; alt = 4500 - Double(t - 600) * 20  // descend to 2,500 AGL... 
            default: break
            }
            if t >= 700 && t < 800 {
                // Final: 1,000 ft above the field down to touchdown at t = 800.
                let remaining = Double(800 - t)
                alt = 2500 + remaining * 10
                ias = finalIAS; vs = -finalSink; rpm = 1800
                if alt - 2500 < 330 && alt - 2500 > 270 { roll = bankAt300 }
            }
            if t >= 800 && t < 900 { rpm = 1000; ias = max(0, 60 - Double(t - 800) * 3); alt = 2500 }
            if t >= 600 && t < 700 { alt = max(3500, alt) }
            v["E1 RPM"] = String(rpm); v["IAS"] = String(ias); v["AltB"] = String(alt); v["VSpd"] = String(vs); v["Roll"] = String(roll)
            v["GndSpd"] = String(ias)
            return v
        }
    }
}

final class TechniqueTests: XCTestCase {
    /// G1000 outside Cirrus names the altitude AltInd; some logs have no VSpd column.
    func testG1000AltIndWithoutVerticalSpeedStillFindsTakeoffAndLanding() throws {
        var lines = TechniqueFixture.circuit().components(separatedBy: "\n")
        let header = try XCTUnwrap(lines.firstIndex { $0.contains("Lcl Date") })
        var names = lines[header].components(separatedBy: ",")
        let vsCol = try XCTUnwrap(names.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "VSpd" })
        names = names.map { $0.trimmingCharacters(in: .whitespaces) == "AltB" ? " AltInd" : $0 }
        names[vsCol] = " Unused"
        lines[header] = names.joined(separator: ",")
        let log = try PerspectiveLogParser.parse(text: lines.joined(separator: "\n"), filename: "log_260801_080000_18AZ.csv")
        XCTAssertTrue(log.columns.contains("AltB"))
        let r = TechniqueAnalyzer.analyze(log, departure: "18AZ")
        XCTAssertEqual(r.takeoffs.count, 1)
        XCTAssertEqual(r.landings.count, 1)
    }

    func testRecordMergeKeepsBothSidesAndHonoursDeletes() {
        let a = MaintenanceEntry(itemID: "oil", date: Date(), values: [:], notes: "iPad", by: "Pilot")
        let b = MaintenanceEntry(itemID: "oil", date: Date(), values: [:], notes: "iPhone", by: "Pilot")
        let gone = MaintenanceEntry(itemID: "oil", date: Date(), values: [:], notes: "deleted", by: "Pilot")
        var changed = a
        changed.notes = "iPad, edited"
        let merged = AppSyncMerge.union([changed, gone], [a, b, gone], localWins: true, deleted: [gone.id])
        XCTAssertEqual(Set(merged.map(\.notes)), ["iPad, edited", "iPhone"])
        let empty = AppSyncMerge.union([MaintenanceEntry](), [a, b], localWins: true, deleted: [])
        XCTAssertEqual(empty.count, 2, "an empty device never wipes the account's records")
    }

    func testCircuitGivesOneTakeoffAndOneLanding() throws {
        let log = try PerspectiveLogParser.parse(text: TechniqueFixture.circuit(), filename: "log_260801_080000_18AZ.csv")
        let r = TechniqueAnalyzer.analyze(log, departure: "18AZ")
        XCTAssertEqual(r.takeoffs.count, 1)
        XCTAssertEqual(r.landings.count, 1)
        let l = try XCTUnwrap(r.landings.first)
        XCTAssertEqual(l.fieldElevation, 2500, accuracy: 1)
        XCTAssertEqual(l.airport, "18AZ", "returned to the departure field")
        XCTAssertEqual(l.ias50 ?? 0, 82, accuracy: 0.5)
        XCTAssertEqual(l.onSpeedAt50, true)
        XCTAssertEqual(l.stableAt300, true)
        XCTAssertEqual(l.score.passed, l.score.of)
        XCTAssertFalse(l.profile.isEmpty)
        let t = try XCTUnwrap(r.takeoffs.first)
        XCTAssertEqual(t.fullPower, true)
        XCTAssertEqual(t.climbIAS ?? 0, 112, accuracy: 0.5)
        XCTAssertEqual(t.climbOnSpeed, true)
    }

    func testFastSteepBankedFinalFailsTheGates() throws {
        let log = try PerspectiveLogParser.parse(text: TechniqueFixture.circuit(finalIAS: 97, finalSink: 1200, bankAt300: 25),
                                                 filename: "log_260801_080000_18AZ.csv")
        let l = try XCTUnwrap(TechniqueAnalyzer.analyze(log, departure: nil).landings.first)
        XCTAssertEqual(l.onSpeedAt50, false)
        XCTAssertEqual(l.stableAt300, false)
        XCTAssertEqual(l.stableAt500, false)
    }

    func testSummaryCarriesTechniqueAndRoundTrips() throws {
        let s = FlightSummarizer.summarize(try PerspectiveLogParser.parse(text: TechniqueFixture.circuit(), filename: "log_260801_080000_18AZ.csv"))
        XCTAssertEqual(s.landings.count, 1)
        XCTAssertEqual(s.takeoffs.count, 1)
        let back = try EventPersistence.decoder.decode(FlightSummary.self, from: EventPersistence.encoder.encode(s))
        XCTAssertEqual(back.landings, s.landings)
        XCTAssertEqual(back.takeoffs, s.takeoffs)
    }
}
