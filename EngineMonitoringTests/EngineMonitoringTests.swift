import XCTest
@testable import EngineMonitoring

final class SourceAuthorityTests: XCTestCase {
    func testAuthorityLabelsAreStable() {
        XCTAssertEqual(SourceAuthority.approved.rawValue, "APPROVED")
        XCTAssertEqual(SourceAuthority.manufacturer.rawValue, "MANUFACTURER")
        XCTAssertEqual(SourceAuthority.training.rawValue, "TRAINING")
        XCTAssertEqual(SourceAuthority.experience.rawValue, "EXPERIENCE")
    }

    func testOldCatalogEntriesWithoutRevisionFieldsStillDecode() throws {
        let json = #"[{"id":"a","title":"T","subtitle":"S","category":"C","authority":"TRAINING","bundledFilename":"x.pdf","isCockpitCritical":true}]"#
        let docs = try DocumentRepository.decodeCatalog(Data(json.utf8))
        XCTAssertEqual(docs.first?.revision, nil)
        XCTAssertTrue(docs[0].needsVerification(), "Unreviewed cockpit-critical content must be flagged")
    }

    func testReviewOverdue() {
        let doc = KnowledgeDocument(id: "a", title: "T", subtitle: "", category: "C", authority: .training,
                                    bundledFilename: nil, isCockpitCritical: true, reviewDueDate: "2026-01-01",
                                    reviewedBy: "CFII")
        XCTAssertTrue(doc.isReviewOverdue(asOf: KnowledgeDocument.dayFormatter.date(from: "2026-06-01")!))
        XCTAssertFalse(doc.isReviewOverdue(asOf: KnowledgeDocument.dayFormatter.date(from: "2025-06-01")!))
    }
}

final class PerspectiveLogParserTests: XCTestCase {
    private func fixture() throws -> PerspectiveLog {
        try PerspectiveLogParser.parse(text: PerspectiveFixture.csv, filename: PerspectiveFixture.filename)
    }

    /// 2026-07-15 hh:mm:ss at UTC-7.
    private func local(_ hms: String) -> Date {
        PerspectiveLogParser.timestamp(date: "2026-07-15", time: hms, offset: "-07:00", fallbackSeconds: 0)!
    }

    func testMetadataAndShape() throws {
        let log = try fixture()
        XCTAssertEqual(log.airframeName, "Cirrus SR22 Turbo Normalized")
        XCTAssertEqual(log.systemID, "0000TEST0")
        XCTAssertEqual(log.softwareVersion, "15.26")
        XCTAssertEqual(log.sampleCount, 121)
        XCTAssertTrue(log.columns.contains("E1 RPM"))
        XCTAssertTrue(log.columns.contains("VPLwas"))
    }

    func testTimestampsUseLogUTCOffset() throws {
        let log = try fixture()
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(log.start, iso.date(from: "2026-07-15T16:00:00Z"))
        XCTAssertEqual(log.end, iso.date(from: "2026-07-15T16:02:00Z"))
    }

    func testOffsetParsing() {
        XCTAssertEqual(PerspectiveLogParser.parseOffset("-07:00"), -25200)
        XCTAssertEqual(PerspectiveLogParser.parseOffset("+05:30"), 19800)
        XCTAssertNil(PerspectiveLogParser.parseOffset(""))
    }

    func testFastTimestampMatchesFormatterPath() {
        for (date, time, offset) in [("2026-07-15", "09:16:52", "-07:00"), ("2024-02-29", "23:59:59", "+00:00"),
                                     ("2025-12-31", "00:00:00", "+05:30"), ("2026-03-08", "02:30:00", "-05:00")] {
            XCTAssertEqual(PerspectiveLogParser.fastTimestamp(date: date[...], time: time[...], offset: offset[...], fallbackSeconds: 0),
                           PerspectiveLogParser.timestamp(date: date, time: time, offset: offset, fallbackSeconds: 0),
                           "\(date) \(time) \(offset)")
        }
        // Blank offset uses the fallback.
        XCTAssertEqual(PerspectiveLogParser.fastTimestamp(date: "2026-07-15", time: "09:00:00", offset: "", fallbackSeconds: -25200),
                       ISO8601DateFormatter().date(from: "2026-07-15T16:00:00Z"))
    }

    func testBlankCellsAreNil() throws {
        let log = try fixture()
        XCTAssertNil(log.value("Latitude", at: 0))
        XCTAssertEqual(log.value(PerspectiveChannel.rpm, at: 32), 650)
        XCTAssertEqual(log.textValue(PerspectiveChannel.rollMode, at: 0), "ROL")
    }

    func testIndexWindow() throws {
        let log = try fixture()
        let r = log.indices(from: local("09:00:10"), to: local("09:00:19"))
        XCTAssertEqual(r, 10..<20)
    }

    func testRejectsNonLogFiles() {
        XCTAssertThrowsError(try PerspectiveLogParser.parse(text: "", filename: "x.csv")) { error in
            XCTAssertEqual(error as? PerspectiveLogError, .noHeaderRow)
        }
        XCTAssertThrowsError(try PerspectiveLogParser.parse(text: "a,b\n1,2\n", filename: "x.csv")) { error in
            XCTAssertEqual(error as? PerspectiveLogError, .missingTimeColumns)
        }
    }

    func testCRLFLineEndings() throws {
        let crlf = PerspectiveFixture.csv.replacingOccurrences(of: "\n", with: "\r\n")
        let log = try PerspectiveLogParser.parse(text: crlf, filename: "crlf.csv")
        XCTAssertEqual(log.sampleCount, 121)
        XCTAssertEqual(log.value(PerspectiveChannel.rpm, at: 40), 1000)
    }
}

final class DiagnosticEngineTests: XCTestCase {
    private let phoenix = TimeZone(identifier: "America/Phoenix")!
    private var log: PerspectiveLog!

    override func setUpWithError() throws {
        log = try PerspectiveLogParser.parse(text: PerspectiveFixture.csv, filename: PerspectiveFixture.filename)
    }

    private func at(_ hms: String) -> Date {
        PerspectiveLogParser.timestamp(date: "2026-07-15", time: hms, offset: "-07:00", fallbackSeconds: 0)!
    }

    private func value(_ finding: DiagnosticFinding, _ label: String) -> String? {
        finding.evidence.first { $0.label == label }?.value
    }

    func testNoLogMeansInsufficientData() {
        let event = DiagnosticEvent(timestamp: at("09:00:50"), timeZone: phoenix, system: .engineStart)
        let f = DiagnosticEngine().finding(for: event, log: nil)
        XCTAssertEqual(f.confidence, .insufficient)
        XCTAssertNil(f.dataSource)
    }

    func testLogNotCoveringEventIsIgnored() {
        let event = DiagnosticEvent(timestamp: at("11:00:00"), timeZone: phoenix, system: .engineStart)
        let f = DiagnosticEngine().finding(for: event, log: log)
        XCTAssertEqual(f.confidence, .insufficient)
        XCTAssertNotNil(value(f, "Attached log"))
    }

    func testEngineStartEvidence() {
        let event = DiagnosticEvent(timestamp: at("09:00:50"), timeZone: phoenix, system: .engineStart)
        let f = DiagnosticEngine().finding(for: event, log: log)
        XCTAssertEqual(f.confidence, .low, "Evidence found but no cause assigned")
        XCTAssertEqual(f.dataSource, PerspectiveFixture.filename)
        XCTAssertEqual(value(f, "Engine start (RPM ≥ 500)"), "09:00:32 (18 s before the marker)")
        XCTAssertEqual(value(f, "Cranking episodes before start"), "1 (RPM above 100 without reaching 500)")
        XCTAssertEqual(value(f, "Lowest bus 1 voltage, 30 s before start"), "20.1 V")
        XCTAssertEqual(value(f, "Peak fuel flow, ±30 s of start"), "8.0 gph")
        XCTAssertEqual(value(f, "EGT rise in first 30 s (°F, by cylinder)"),
                       "1: +400, 2: +400, 3: +300, 4: +400, 5: +400, 6: +400")
    }

    func testEngineStartNotFound() {
        // Window that begins after the start: no stopped-to-running transition.
        var engine = DiagnosticEngine()
        engine.startSearchLookBack = 20
        let event = DiagnosticEvent(timestamp: at("09:01:50"), timeZone: phoenix, system: .engineStart)
        let f = engine.finding(for: event, log: log)
        XCTAssertTrue(value(f, "Engine start")?.hasPrefix("No RPM rise") ?? false)
    }

    func testAutopilotEvidence() {
        let event = DiagnosticEvent(timestamp: at("09:01:35"), timeZone: phoenix, system: .autopilot)
        let f = DiagnosticEngine().finding(for: event, log: log)
        XCTAssertEqual(value(f, "AFCS engage changes"), "09:01:00 engaged; 09:01:30 disengaged")
        XCTAssertTrue(value(f, "Mode changes (roll / pitch)")?.contains("09:01:10 HDG / PIT") ?? false)
    }

    func testElectricalStepDown() {
        var engine = DiagnosticEngine()
        engine.lookBack = 20
        let event = DiagnosticEvent(timestamp: at("09:01:45"), timeZone: phoenix, system: .electrical)
        let f = engine.finding(for: event, log: log)
        XCTAssertEqual(value(f, "Largest 1-s bus 1 voltage drop"), "2.1 V at 09:01:40")
        XCTAssertEqual(value(f, "Bus 1 voltage"), "26.0 to 28.1 V")
    }

    func testNeverAssignsHighConfidence() {
        for system in DiagnosticSystem.allCases {
            let event = DiagnosticEvent(timestamp: at("09:01:00"), timeZone: phoenix, system: system)
            let f = DiagnosticEngine().finding(for: event, log: log)
            XCTAssertNotEqual(f.confidence, .high)
            XCTAssertNotEqual(f.confidence, .medium)
        }
    }
}

final class PersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testEventRoundTrip() throws {
        let store = EventPersistence(directory: dir)
        let tz = TimeZone(identifier: "America/Phoenix")!
        let event = DiagnosticEvent(timestamp: Date(timeIntervalSince1970: 1_790_000_000), timeZone: tz,
                                    system: .autopilot, note: "AP disconnect", flightLogFilename: "log.csv",
                                    detailsEntered: true)
        try store.save([event])
        let loaded = try store.load()
        XCTAssertEqual(loaded, [event])
        XCTAssertEqual(loaded[0].utcOffsetSeconds, -25200)
        XCTAssertEqual(loaded[0].timeZoneIdentifier, "America/Phoenix")
    }

    func testLegacyV1EventsDecode() throws {
        // Shape written by the v0.2 build into UserDefaults (default JSONEncoder: dates as seconds since 2001).
        let json = #"[{"id":"7E2B1D3A-1111-4C2B-9C1A-1234567890AB","timestamp":781000000,"system":"Engine \/ Start","note":"rough start"}]"#
        let events = try EventPersistence.decodeLegacy(Data(json.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].system, .engineStart)
        XCTAssertEqual(events[0].note, "rough start")
        XCTAssertTrue(events[0].detailsEntered)
        XCTAssertNil(events[0].flightLogFilename)
    }

    func testLogImportIndexAndMatch() throws {
        let library = FlightLogLibrary(baseDirectory: dir)
        let result = try library.importLog(data: Data(PerspectiveFixture.csv.utf8),
                                           originalFilename: PerspectiveFixture.filename, existing: [])
        XCTAssertEqual(result.entry.sampleCount, 121)
        XCTAssertEqual(try library.loadIndex(), result.index)

        let inside = result.entry.start.addingTimeInterval(30)
        XCTAssertEqual(FlightLogLibrary.bestMatch(for: inside, in: result.index), result.entry)
        let farAway = result.entry.end.addingTimeInterval(3600)
        XCTAssertNil(FlightLogLibrary.bestMatch(for: farAway, in: result.index))

        // Re-import replaces rather than duplicates.
        let again = try library.importLog(data: Data(PerspectiveFixture.csv.utf8),
                                          originalFilename: PerspectiveFixture.filename, existing: result.index)
        XCTAssertEqual(again.index.count, 1)

        let remaining = try library.delete(again.entry, from: again.index)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStoredFilenameIsSafe() {
        XCTAssertEqual(FlightLogLibrary.storedFilename(for: "../../log 1.csv"), "log_1.csv")
        XCTAssertEqual(FlightLogLibrary.storedFilename(for: "data"), "data.csv")
        XCTAssertEqual(FlightLogLibrary.storedFilename(for: ".hidden.csv"), "log_.hidden.csv")
    }

    func testCSVExportEscapes() {
        let event = DiagnosticEvent(timestamp: Date(timeIntervalSince1970: 1_790_000_000),
                                    timeZone: TimeZone(identifier: "UTC")!, system: .other,
                                    note: "said \"rough\", then smooth")
        let csv = EventExporter.csv([event])
        XCTAssertTrue(csv.contains("\"said \"\"rough\"\", then smooth\""))
        XCTAssertTrue(csv.hasPrefix("id,timestamp_utc,"))
    }
}

@MainActor
final class DiagnosticEventStoreTests: XCTestCase {
    func testMarkNowCapturesTapTimeNotSaveTime() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "EMTests-\(UUID().uuidString)")!
        let store = DiagnosticEventStore(directory: dir, defaults: defaults)

        let tap = Date(timeIntervalSince1970: 1_790_000_000)
        var event = store.markNow(at: tap)
        XCTAssertFalse(event.detailsEntered)

        // Pilot adds details later; the timestamp must not move.
        event.system = .engine
        event.note = "  surge  "
        event.detailsEntered = true
        store.update(event)
        XCTAssertEqual(store.events.first?.timestamp, tap)
        XCTAssertEqual(store.events.first?.note, "surge")

        // Persisted across a new store instance.
        let reopened = DiagnosticEventStore(directory: dir, defaults: defaults)
        XCTAssertEqual(reopened.events.first?.timestamp, tap)

        reopened.delete(ids: [event.id])
        XCTAssertTrue(reopened.events.isEmpty)
    }

    func testMigratesV1EventsFromUserDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "EMTests-\(UUID().uuidString)")!
        let json = #"[{"id":"7E2B1D3A-1111-4C2B-9C1A-1234567890AB","timestamp":781000000,"system":"Other","note":"old"}]"#
        defaults.set(Data(json.utf8), forKey: "EM.DiagnosticEvents.v1")

        let store = DiagnosticEventStore(directory: dir, defaults: defaults)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertNil(defaults.data(forKey: "EM.DiagnosticEvents.v1"), "Legacy data removed after migration")
        XCTAssertEqual(DiagnosticEventStore(directory: dir, defaults: defaults).events.count, 1)
    }
}
