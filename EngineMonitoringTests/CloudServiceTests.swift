import XCTest
@testable import EngineMonitoring

final class CloudServiceTests: XCTestCase {
    func testSessionParsesSupabaseTokenResponse() throws {
        let json = #"{"access_token":"abc","token_type":"bearer","expires_in":3600,"refresh_token":"r1","user":{"id":"00000000-0000-0000-0000-00000000000a","email":"pilot@example.com"}}"#
        let s = try CloudAPI.session(from: Data(json.utf8))
        XCTAssertEqual(s.accessToken, "abc")
        XCTAssertEqual(s.refreshToken, "r1")
        XCTAssertEqual(s.userID, "00000000-0000-0000-0000-00000000000a")
        XCTAssertEqual(s.email, "pilot@example.com")
        XCTAssertGreaterThan(s.expiresAt.timeIntervalSinceNow, 3500)
    }

    func testBadTokenResponseThrows() {
        XCTAssertThrowsError(try CloudAPI.session(from: Data(#"{"error":"invalid_grant"}"#.utf8)))
    }

    func testAircraftRowCarriesProfileAndNulls() throws {
        var p = AircraftProfile.sr22TurboTemplate
        p.tailNumber = "N12345"
        let id = UUID()
        let row = try CloudAPI.aircraftRow(id: id, profile: p)
        XCTAssertEqual(row["id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(row["tail_number"] as? String, "N12345")
        XCTAssertEqual(row["cylinders"] as? Int, 6)
        XCTAssertTrue(row["year"] is NSNull, "year 0 is sent as null")
        let profile = try XCTUnwrap(row["profile"] as? [String: Any])
        XCTAssertEqual(profile["tailNumber"] as? String, "N12345")
        // The whole row must be valid JSON for the REST call.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: [row]))
    }

    func testLogPathStartsWithTheUsersFolder() {
        let a = UUID()
        let path = CloudAPI.logPath(userID: "ABC-123", aircraftID: a, filename: "log_1.csv")
        XCTAssertEqual(path, "abc-123/\(a.uuidString.lowercased())/log_1.csv")
    }

    func testNonceAndHash() {
        let n = CloudAPI.randomNonce()
        XCTAssertEqual(n.count, 32)
        XCTAssertNotEqual(n, CloudAPI.randomNonce())
        XCTAssertEqual(CloudAPI.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testBlankConfigMeansLocalOnly() {
        // The test host's Info.plist ships with blank keys.
        let config = CloudConfig.fromBundle(.main)
        let url = Bundle.main.object(forInfoDictionaryKey: "EMSupabaseURL") as? String ?? ""
        if url.isEmpty { XCTAssertNil(config) } else { XCTAssertNotNil(config) }
    }
}
