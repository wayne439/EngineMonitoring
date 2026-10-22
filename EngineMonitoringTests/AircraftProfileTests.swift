import XCTest
@testable import EngineMonitoring

final class AircraftProfileTests: XCTestCase {
    func testTemplateLimitsMatchTheOriginalSR22List() {
        let limits = AircraftProfile.sr22TurboTemplate.engineLimits()
        let byID = Dictionary(uniqueKeysWithValues: limits.map { ($0.id, $0) })
        XCTAssertEqual(byID["rpm-max"]?.high, 2710)
        XCTAssertEqual(byID["rpm-overspeed"]?.high, 2730)
        XCTAssertEqual(byID["oilt-max"]?.high, 240)
        XCTAssertEqual(byID["oilp-min"]?.low, 10)
        XCTAssertEqual(byID["oilp-caution"]?.low, 30)
        XCTAssertEqual(byID["cht-caution"]?.high, 420)
        XCTAssertEqual(byID["cht-warning"]?.high, 460)
        XCTAssertEqual(byID["volt1-low"]?.low, 24.5)
        XCTAssertEqual(byID["barker-tit"]?.kind, .reference)
        XCTAssertEqual(byID["barker-tit"]?.authority, .experience)
        XCTAssertEqual(byID["oilt-max"]?.label, "Oil temperature above 240 °F")
        XCTAssertTrue(byID["oilt-max"]?.source.contains("template") ?? false, "Unconfirmed limits are marked as template values")
    }

    func testConfirmedProfileUsesOwnersValuesAndSource() {
        var p = AircraftProfile.sr22TurboTemplate
        p.limits.chtCaution = 400
        p.limits.limitsSource = "Bonanza POH 2-4"
        p.limitsConfirmedByOwner = true
        let caution = p.engineLimits().first { $0.id == "cht-caution" }
        XCTAssertEqual(caution?.high, 400)
        XCTAssertEqual(caution?.source, "Bonanza POH 2-4")
    }

    func testNormallyAspiratedProfileHasNoTITReference() {
        var p = AircraftProfile.sr22TurboTemplate
        p.isTurbocharged = false
        XCTAssertFalse(p.engineLimits().contains { $0.metric == .tit })
    }

    func testDisplayName() {
        var p = AircraftProfile.sr22TurboTemplate
        XCTAssertEqual(p.displayName, "Cirrus SR22 Turbo")
        p.tailNumber = "N12345"
        p.year = 2015
        XCTAssertEqual(p.displayName, "N12345 - 2015 Cirrus SR22 Turbo")
    }

    func testProfileRoundTripsThroughJSON() throws {
        var p = AircraftProfile.sr22TurboTemplate
        p.tailNumber = "N12345"
        p.monitor = .jpiEDM
        p.limits.cruiseTITTarget = nil
        let data = try EventPersistence.encoder.encode(p)
        XCTAssertEqual(try EventPersistence.decoder.decode(AircraftProfile.self, from: data), p)
        XCTAssertFalse(EngineMonitorType.jpiEDM.isSupported)
        XCTAssertTrue(EngineMonitorType.garminPerspective.isSupported)
    }

    // MARK: - Data path advice

    func testFlightStream210NeverCarriesEngineData() {
        let a = DataPathAdvice.advise(monitor: .garminG1000NXi, link: .flightStream210, make: "Cessna")
        XCTAssertFalse(a.automatic)
        XCTAssertTrue(a.title.contains("Flight Stream 210"))
    }

    func testFlightStream510DependsOnAvionics() {
        XCTAssertTrue(DataPathAdvice.advise(monitor: .garminG1000NXi, link: .flightStream510, make: "Cessna").automatic)
        XCTAssertTrue(DataPathAdvice.advise(monitor: .garminTXi, link: .flightStream510, make: "Beechcraft").automatic)
        XCTAssertFalse(DataPathAdvice.advise(monitor: .garminPerspective, link: .flightStream510, make: "Cirrus").automatic)
    }

    // MARK: - Aircraft transfer code

    func testTransferCodeIsReadableAndHashesLikeTheDatabase() {
        let code = TransferCode.make()
        XCTAssertEqual(code.count, 8)
        XCTAssertTrue(code.allSatisfy { "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains($0) })
        XCTAssertEqual(TransferCode.display("abcd2345"), "ABCD-2345")
        XCTAssertEqual(TransferCode.normalize(" abcd-2345 "), "ABCD2345")
        // Same value as encode(sha256('ABCD2345'), 'hex') in Postgres.
        XCTAssertEqual(TransferCode.hash("abcd-2345"), "a00d76646eba91b057841554d5c8334f498dc592ed744bce404f21fe271cd36e")
    }

    func testPerspectiveTouchPlusIsListedAndSupported() {
        let touch = EngineMonitorType.garminPerspectiveTouchPlus
        XCTAssertTrue(EngineMonitorType.allCases.contains(touch))
        XCTAssertTrue(touch.isSupported)
        XCTAssertTrue(touch.isPerspectivePlusFamily)
        XCTAssertEqual(EngineMonitorType.garminPerspectivePlus.label, "Cirrus Perspective+ (G6)")
        // Older profiles saved with the combined G6 / G7 name still decode.
        XCTAssertEqual(EngineMonitorType(rawValue: "Cirrus Perspective+ (G6 / G7)"), .garminPerspectivePlus)
        XCTAssertEqual(AircraftModelOption.catalog.first { $0.id == "sr22tg7" }?.monitor, touch)
        let advice = DataPathAdvice.advise(monitor: touch, link: .flightStream510, make: "Cirrus")
        XCTAssertTrue(advice.automatic)
        XCTAssertTrue(advice.steps.joined().contains("Perspective Touch+"))
    }

    // MARK: - All monitors

    func testCatalogIsConsistent() {
        let ids = AircraftModelOption.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate catalog ids")
        XCTAssertGreaterThan(AircraftModelOption.catalog.count, 90)
        for make in AircraftModelOption.makes { XCTAssertFalse(AircraftModelOption.models(of: make).isEmpty, make) }
        XCTAssertEqual(AircraftModelOption.catalog.first { $0.id == "sr22av" }?.monitor, .avidyne)
        XCTAssertEqual(AircraftModelOption.catalog.first { $0.id == "c182old" }?.monitor, .jpiEDM)
    }

    func testEveryMonitorHasDownloadStepsAndAdvice() {
        for m in EngineMonitorType.allCases {
            XCTAssertFalse(m.downloadSteps.isEmpty, m.rawValue)
            XCTAssertFalse(DataPathAdvice.advise(monitor: m, link: nil, make: "").steps.isEmpty, m.rawValue)
        }
        XCTAssertEqual(EngineMonitorType.jpiEDM.support, .full)
        XCTAssertTrue(EngineMonitorType.dynonSkyView.isSupported)
        XCTAssertTrue(DataPathAdvice.advise(monitor: .jpiEDM, link: nil, make: "Cessna").steps.joined().contains("DUMP"))
    }

    func testJPIStyleCSVImportsWithEngineOnlyPhases() throws {
        var text = "Aircraft Number N12345\nFlight #3 6/14/2023 10:00:00 AM\nEng Deg F OAT Deg F\nDate,TIME,E1,E2,C1,C2,OILT,OAT,BAT,FF,RPM,MAP,OILP\n"
        for i in 0..<120 {
            let rpm = i < 10 ? 1000 : (i < 30 ? 2700 : (i < 100 ? 2400 : 1000))
            let ff = i < 10 ? 3.0 : (i < 30 ? 26.0 : (i < 100 ? 15.0 : 3.0))
            let mm = (i * 6) / 60, ss = (i * 6) % 60
            text += String(format: "06/14/23,10:%02d:%02d,1300,1310,350,355,190,59,28.0,%.1f,%d,25.0,70\n", mm, ss, ff, rpm)
        }
        let converted = try EngineLogConverter.convert(data: Data(text.utf8), filename: "jpi_export.csv", timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(converted.count, 1)
        let log = try PerspectiveLogParser.parse(data: converted[0].data, filename: converted[0].filename)
        XCTAssertEqual(log.sampleCount, 120)
        XCTAssertEqual(log.value("E1 CHT2", at: 0), 355)
        XCTAssertEqual(log.value("OAT", at: 0), 15)
        let phases = PhaseClassifier.classify(log)
        XCTAssertEqual(phases[5], .ground)
        XCTAssertEqual(phases[25], .climb)
        XCTAssertEqual(phases[60], .cruise)
        XCTAssertEqual(phases[110], .ground)
    }

    func testG7BatteryNoteOnlyForG7() {
        var p = AircraftProfile.sr22TurboTemplate
        p.make = "Cirrus"; p.model = "SR22T G7"; p.monitor = .garminPerspectiveTouchPlus
        XCTAssertTrue(p.batteryNote?.contains("lithium-ion") ?? false)
        p.model = "SR22T G6"; p.monitor = .garminPerspectivePlus
        XCTAssertNil(p.batteryNote)
    }

    func testGarminLinksShowTheGarminGuide() {
        let plus = DataPathAdvice.advise(monitor: .garminPerspectivePlus, link: .flightStream510, make: "Cirrus")
        XCTAssertTrue(plus.showsGarminGuide)
        XCTAssertTrue(plus.steps.joined().contains("Garmin Pilot"))
        XCTAssertTrue(plus.steps.joined().contains("data card"))
        let gdl = DataPathAdvice.advise(monitor: .garminPerspectivePlus, link: .gdl60, make: "Cirrus")
        XCTAssertTrue(gdl.showsGarminGuide)
        XCTAssertTrue(gdl.steps.joined().contains("Original CSV"))
        XCTAssertFalse(DataPathAdvice.advise(monitor: .garminPerspective, link: .flightStream210, make: "Cirrus").showsGarminGuide)
    }

    func testNoLinkMeansDataCardAndCirrusHint() {
        let a = DataPathAdvice.advise(monitor: .garminPerspective, link: nil, make: "Cirrus")
        XCTAssertFalse(a.automatic)
        XCTAssertTrue(a.steps.joined().contains("Cirrus IQ"))
        XCTAssertTrue(DataPathAdvice.advise(monitor: .jpiEDM, link: .gdl60, make: "Mooney").title.contains("Export"))
    }

    func testOlderProfileWithoutDataLinkStillDecodes() throws {
        var p = AircraftProfile.sr22TurboTemplate
        p.dataLink = .gdl60
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: EventPersistence.encoder.encode(p)) as? [String: Any])
        json.removeValue(forKey: "dataLink")
        let decoded = try EventPersistence.decoder.decode(AircraftProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.dataLink)
    }

    // MARK: - SD card folder import

    @MainActor
    func testNewLogFilesSkipsAlreadyImportedAndNonCSV() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = dir.appendingPathComponent("data_log")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["log_1.csv", "log_2.csv", "notes.txt"] { try Data("x".utf8).write(to: sub.appendingPathComponent(name)) }
        let existing = FlightLogEntry(filename: "log_1.csv", originalFilename: "log_1.csv", start: Date(), end: Date(),
                                      sampleCount: 1, airframeName: nil, systemID: nil, importedAt: Date())
        let found = try XCTUnwrap(FlightLogStore.newLogFiles(in: dir, existing: [existing]))
        XCTAssertEqual(found.map(\.lastPathComponent), ["log_2.csv"])
        XCTAssertNil(FlightLogStore.newLogFiles(in: dir.appendingPathComponent("missing"), existing: []))
    }
}
