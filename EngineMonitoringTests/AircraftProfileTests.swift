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
}
