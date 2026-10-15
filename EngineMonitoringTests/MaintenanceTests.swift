import XCTest
@testable import EngineMonitoring

final class MaintenanceTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }
    private func item(_ id: String) -> MaintenanceItem { MaintenanceSchedule.defaults.first { $0.id == id }! }
    private func flight(_ start: String, hours: Double) -> FlightSummary {
        FlightSummary(filename: "log_\(start).csv", start: day(start), end: day(start).addingTimeInterval(hours * 3600),
                      phaseSeconds: [.cruise: Int(hours * 3600), .engineOff: 600], stats: [:])
    }

    func testNeverRecordedNeedsAttention() {
        let s = MaintenanceSchedule.status(of: item("fiki-test"), entries: [], summaries: [], now: day("2026-10-07"))
        XCTAssertEqual(s.state, .neverDone)
    }

    func testThirtyDayCheckBecomesDueSoonThenOverdue() {
        let fiki = item("fiki-test")
        let e = MaintenanceEntry(itemID: fiki.id, date: day("2026-09-10"), values: ["result": "pass", "surfaces": "yes"], notes: "", by: "Pilot")
        XCTAssertEqual(MaintenanceSchedule.status(of: fiki, entries: [e], summaries: [], now: day("2026-09-20"), calendar: cal).state, .ok)
        let soon = MaintenanceSchedule.status(of: fiki, entries: [e], summaries: [], now: day("2026-10-07"), calendar: cal)
        XCTAssertEqual(soon.state, .dueSoon)
        XCTAssertEqual(soon.daysLeft, 3)
        XCTAssertEqual(MaintenanceSchedule.status(of: fiki, entries: [e], summaries: [], now: day("2026-10-12"), calendar: cal).state, .overdue)
    }

    func testFailedCheckStaysOnTopUntilAPass() {
        let fiki = item("fiki-test")
        let fail = MaintenanceEntry(itemID: fiki.id, date: day("2026-10-01"), values: ["result": "fail", "surfaces": "no"], notes: "Left wing panel dry", by: "Pilot")
        var s = MaintenanceSchedule.status(of: fiki, entries: [fail], summaries: [], now: day("2026-10-02"), calendar: cal)
        XCTAssertEqual(s.state, .failed)
        XCTAssertEqual(s.problems.count, 2)
        let pass = MaintenanceEntry(itemID: fiki.id, date: day("2026-10-05"), values: ["result": "pass", "surfaces": "yes"], notes: "", by: "Pilot")
        s = MaintenanceSchedule.status(of: fiki, entries: [fail, pass], summaries: [], now: day("2026-10-06"), calendar: cal)
        XCTAssertEqual(s.state, .ok)
    }

    func testTirePressureOutOfRangeFails() {
        let tires = item("tire-pressure")
        let e = MaintenanceEntry(itemID: tires.id, date: day("2026-10-01"), values: ["nose": "28", "left": "62", "right": "63", "condition": "yes"], notes: "", by: "")
        XCTAssertEqual(e.problems(for: tires).count, 1)
        XCTAssertTrue(e.problems(for: tires)[0].contains("Nose 28 psi below"))
        let ok = MaintenanceEntry(itemID: tires.id, date: day("2026-10-01"), values: ["nose": "32", "left": "62", "right": "63", "condition": "yes"], notes: "", by: "")
        XCTAssertTrue(ok.passed(for: tires))
    }

    func testServiceDueByFlightHoursFromLogs() {
        let oil = item("oil-change")
        XCTAssertEqual(oil.intervalHours, 30)
        let e = MaintenanceEntry(itemID: oil.id, date: day("2026-09-01"), values: ["filter": "yes"], notes: "", by: "Shop")
        let flights = [flight("2026-08-20", hours: 3), flight("2026-09-05", hours: 12), flight("2026-09-20", hours: 16)]
        let s = MaintenanceSchedule.status(of: oil, entries: [e], summaries: flights, now: day("2026-09-25"), calendar: cal)
        XCTAssertEqual(s.hoursSince ?? 0, 28, accuracy: 0.01, "only logs after the service count; engine-off time is excluded")
        XCTAssertEqual(s.hoursLeft ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(s.state, .dueSoon)
        let over = MaintenanceSchedule.status(of: oil, entries: [e], summaries: flights + [flight("2026-09-24", hours: 3)], now: day("2026-09-25"), calendar: cal)
        XCTAssertEqual(over.state, .overdue)
    }

    func testTachAnchorFromTheLatestService() throws {
        let oil = item("oil-change")
        let entries = [MaintenanceEntry(itemID: "annual", date: day("2025-12-22"), values: ["tach": "1940.3"], notes: "", by: "Logbook"),
                       MaintenanceEntry(itemID: oil.id, date: day("2026-08-25"), values: ["tach": "2002.1"], notes: "", by: "Logbook")]
        let flights = [flight("2026-09-10", hours: 6.0), flight("2026-09-30", hours: 4.3)]
        let t = try XCTUnwrap(MaintenanceSchedule.estimatedTach(entries: entries, summaries: flights))
        XCTAssertEqual(t.value, 2012.4, accuracy: 0.01)
        let s = MaintenanceSchedule.status(of: oil, entries: entries, summaries: flights, now: day("2026-10-07"), calendar: cal)
        XCTAssertEqual(s.hoursLeft ?? 0, 19.7, accuracy: 0.01)
        XCTAssertEqual(s.state, .ok)
    }

    func testLogbookBaseline() {
        // A new subscriber starts with no maintenance records; nothing from any other aircraft is seeded.
        XCTAssertTrue(MaintenanceSchedule.baselineEntries().isEmpty)
    }

    func testEntriesRoundTrip() throws {
        let e = MaintenanceEntry(itemID: "tire-pressure", date: day("2026-10-01"), values: ["nose": "32"], notes: "ok", by: "Pilot")
        let back = try EventPersistence.decoder.decode([MaintenanceEntry].self, from: EventPersistence.encoder.encode([e]))
        XCTAssertEqual(back.first?.values["nose"], "32")
        let items = try EventPersistence.decoder.decode([MaintenanceItem].self, from: EventPersistence.encoder.encode(MaintenanceSchedule.defaults))
        XCTAssertEqual(items.map(\.id), ["oil-change", "fiki-test", "tire-pressure", "annual"])
    }
}
