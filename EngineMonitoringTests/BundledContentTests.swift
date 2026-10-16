import XCTest
import PDFKit
@testable import EngineMonitoring

/// Checks the app bundle itself. Runs inside the host app, so Bundle.main is Engine Pulse.
@MainActor
final class BundledContentTests: XCTestCase {
    func testCatalogDecodesAndEveryDocumentIsBundled() {
        let repository = DocumentRepository(bundle: .main)
        XCTAssertNil(repository.loadError)
        // v0.7.2: the old bundled one-page PDFs were removed (kneeboard PDFs are now made from the approach cards).
        XCTAssertEqual(repository.missingDocuments().map(\.id), [], "Catalog lists files missing from the build")
    }

    func testDocumentIDsAreUnique() {
        let ids = DocumentRepository(bundle: .main).documents.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testSelfAuthoredCardsAreNotLabeledApprovedOrManufacturer() {
        // The bundled approach cards are self-authored training aids ("Training aid only").
        for doc in DocumentRepository(bundle: .main).documents where doc.category == "Garmin / Perspective" {
            XCTAssertEqual(doc.authority, .training, "\(doc.id) must be labeled TRAINING until verified")
        }
    }

    func testResourceURLUsesLastDot() {
        XCTAssertNil(DocumentRepository.resourceURL(named: "noextension", in: .main))
        XCTAssertNil(DocumentRepository.resourceURL(named: nil, in: .main))
        XCTAssertNotNil(DocumentRepository.resourceURL(named: "documents.json", in: .main))
    }

    func testEveryKneeboardCardIsOnePage() throws {
        // 0.2.0: approach cards are no longer bundled.
        guard let book = ApproachGuideStore(bundle: .main).book else { throw XCTSkip("No approach cards bundled") }
        for card in book.cards {
            for mode in FlyingMode.allCases {
                let data = try XCTUnwrap(KneeboardPDF.render([card], mode: mode), card.id)
                XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1, "\(card.id) \(mode.rawValue) is not one page")
            }
        }
        let all = try XCTUnwrap(KneeboardPDF.render(book.cards, mode: .autopilot))
        XCTAssertEqual(PDFDocument(data: all)?.pageCount, book.cards.count)
    }

    func testPrivacyManifestIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testInfoPlistValuesAreSubstituted() {
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["CFBundleExecutable", "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"] {
            let value = info[key] as? String ?? ""
            XCTAssertFalse(value.isEmpty, "\(key) is empty")
            XCTAssertFalse(value.contains("$"), "\(key) was not substituted: \(value)")
        }
    }

    /// Engine Pulse ships no data about any particular aircraft: no flight history,
    /// no POH text and no approach cards. Owners supply their own.
    func testNoAircraftSpecificDataIsBundled() {
        for name in ["flight_history", "poh_index", "approach_cards"] {
            XCTAssertNil(Bundle.main.url(forResource: name, withExtension: "json"), "\(name).json must not be bundled")
        }
        XCTAssertTrue(IssuePlaybook.recordIssues.isEmpty)
        XCTAssertTrue(AircraftKnowledge.oilSamples.isEmpty)
        XCTAssertTrue(AircraftKnowledge.watchList.isEmpty)
    }

    func testNoBundledFlightHistory() async {
        let store = FlightLogStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertNil(store.bundled)
        XCTAssertTrue(store.summaries.isEmpty)
    }

    func testIssueReviewsPersist() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = IssueStore(baseDirectory: dir)
        a.addReview(IssueReview(date: Date(), action: .completed, reviewedBy: "A&P", discovered: "Nozzles dirty",
                                actionTaken: "Injectors cleaned", reference: "WO 42", coversThrough: Date()), for: "start.stopped")
        let b = IssueStore(baseDirectory: dir)
        XCTAssertEqual(b.records["start.stopped"]?.status, .completed)
        XCTAssertEqual(b.records["start.stopped"]?.reviews.first?.discovered, "Nozzles dirty")
        XCTAssertNotNil(b.records["start.stopped"]?.completedOn)
    }
}
