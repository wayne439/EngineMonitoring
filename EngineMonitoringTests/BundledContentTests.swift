import XCTest
import PDFKit
@testable import EngineMonitoring

/// Checks the app bundle itself. Runs inside the host app, so Bundle.main is Engine Monitoring.
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
        XCTAssertNotNil(DocumentRepository.resourceURL(named: "approach_cards.json", in: .main))
    }

    func testEveryKneeboardCardIsOnePage() throws {
        let book = try XCTUnwrap(ApproachGuideStore(bundle: .main).book)
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

    func testPOHIndexIsBundledAndConsistent() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "poh_index", withExtension: "json"))
        let index = try POHIndex.decode(Data(contentsOf: url))
        XCTAssertEqual(index.pages.count, index.document.pageCount)
        XCTAssertGreaterThanOrEqual(index.procedures.count, 60)
        for p in index.procedures {
            let page = try XCTUnwrap(index.page(p.pdfPage), p.id)
            XCTAssertEqual(page.label, p.label, p.id)
            XCTAssertFalse(index.text(for: p).isEmpty, p.id)
        }
        for id in ["3-engine-failure-in-flight", "3-engine-partial-power-loss", "3-oil-pressure-out-of-range", "3-caps-deployment", "3a-low-alternator-1-output"] {
            XCTAssertTrue(index.procedures.contains { $0.id == id }, id)
        }
        XCTAssertEqual(POHSearch.search("oil pressure", in: index).first?.page.label, "3-19")
    }

    func testApproachGuidesAreBundledAndComplete() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "approach_cards", withExtension: "json"))
        let book = try ApproachGuideBook.decode(Data(contentsOf: url))
        let ids = book.cards.map(\.id)
        for required in ["ils", "loc", "vor", "vor-dme", "lpv", "lnav-vnav", "lnav", "lnav-plus-v", "lp"] {
            XCTAssertTrue(ids.contains(required), required)
        }
        for card in book.cards {
            for mode in FlyingMode.allCases {
                let phases = card.phases(for: mode)
                XCTAssertTrue(phases.contains { $0.title == "Missed approach" }, "\(card.id) \(mode)")
                XCTAssertGreaterThan(card.stepCount(for: mode), 15, "\(card.id) \(mode)")
            }
            let all = card.phases.flatMap(\.steps)
            XCTAssertEqual(Set(all.map(\.id)).count, all.count, "unique step ids in \(card.id)")
            for s in all where s.authority == .approved {
                XCTAssertTrue(s.source?.hasPrefix("POH") ?? false, "approved step \(s.id) must cite the POH")
            }
        }
        // In-flight quick cards stay short: few lines, at most three actions each, MISSED always present.
        for card in book.cards {
            for mode in FlyingMode.allCases {
                let q = try XCTUnwrap(card.quickCard(for: mode), "\(card.id) \(mode)")
                XCTAssertLessThanOrEqual(q.fly.count, 6, "\(card.id) \(mode)")
                XCTAssertTrue(q.fly.allSatisfy { $0.do.count <= 3 }, "\(card.id) \(mode)")
                XCTAssertTrue(q.fly.contains { $0.when == "MISSED" }, "\(card.id) \(mode)")
                XCTAssertTrue(q.brief.contains { $0.task == "Load the approach" && $0.keys.first == "PROC" }, "\(card.id) \(mode)")
                XCTAssertTrue(q.brief.contains { $0.task == "Set minimums" }, "\(card.id) \(mode)")
            }
        }
        XCTAssertFalse(book.keyReference?.isEmpty ?? true, "Key reference is bundled")
        // VOR approaches must tell the pilot to switch the CDI to VOR1.
        for id in ["vor", "vor-dme"] {
            let card = try XCTUnwrap(book.cards.first { $0.id == id })
            XCTAssertTrue(card.phases.flatMap(\.steps).contains { $0.action.contains("VOR1") && $0.controls.contains("CDI softkey") })
        }
    }

    func testBundledFlightHistoryLoadsInTheApp() async {
        let store = FlightLogStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertNotNil(store.bundled, "flight_history.json missing from the app bundle")
        XCTAssertGreaterThan(store.summaries.count, 100)
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
