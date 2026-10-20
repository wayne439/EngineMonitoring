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
