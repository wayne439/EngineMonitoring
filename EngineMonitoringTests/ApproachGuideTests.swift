import XCTest
@testable import EngineMonitoring

final class ApproachGuideTests: XCTestCase {
    private func step(_ id: String, _ mode: ApproachStep.Mode, approved: Bool = false) -> ApproachStep {
        ApproachStep(id: id, action: "Press <APR> & check", controls: ["APR"], when: "At the FAF", verify: "FMA: GP",
                     mode: mode, source: approved ? "POH 4-21" : nil, authority: approved ? .approved : .training)
    }

    private var card: ApproachCard {
        ApproachCard(id: "t", title: "VOR", subtitle: "s", minimaType: "MDA", navSource: "VOR1", verticalGuidance: "None",
                     keyTrap: "Switch the CDI", phases: [
                        ApproachPhase(title: "Arm", steps: [step("a", .both), step("b", .autopilot), step("c", .manual)]),
                        ApproachPhase(title: "AP only", steps: [step("d", .autopilot)]),
                        ApproachPhase(title: "Missed", steps: [step("e", .both, approved: true)]),
                     ], notes: ["n"], authority: .training, revision: "v4", quick: nil)
    }

    func testModeFiltering() {
        XCTAssertEqual(card.phases(for: .autopilot).flatMap(\.steps).map(\.id), ["a", "b", "d", "e"])
        XCTAssertEqual(card.phases(for: .handFlown).flatMap(\.steps).map(\.id), ["a", "c", "e"])
        XCTAssertEqual(card.phases(for: .handFlown).map(\.title), ["Arm", "Missed"], "Empty phases are hidden")
    }

    func testPrintableHTMLEscapesAndMarksApprovedSteps() {
        let html = ApproachPrinter.html(card, mode: .autopilot, basis: "basis")
        XCTAssertTrue(html.contains("Press &lt;APR&gt; &amp; check"))
        XCTAssertTrue(html.contains("[APPROVED POH 4-21]"))
        XCTAssertTrue(html.contains("TRAINING AID"))
        XCTAssertFalse(html.contains("<APR>"))
    }

    func testQuickCardHTML() {
        let q = QuickSet(autopilot: QuickCard(brief: [SetupItem(task: "Load", keys: ["PROC", "ENT"], note: nil)], fly: [QuickLine(when: "FAF", do: ["VS −700"], check: "ALTS white"),
                                                                           QuickLine(when: "MISSED", do: ["Power full"], check: nil)]),
                         manual: QuickCard(brief: [], fly: []))
        let c = ApproachCard(id: "q", title: "VOR", subtitle: "", minimaType: "MDA", navSource: "VOR1", verticalGuidance: "None",
                             keyTrap: "", phases: [], notes: [], authority: .training, revision: "v5", quick: q)
        let html = ApproachPrinter.quickHTML(c, mode: .autopilot) ?? ""
        XCTAssertTrue(html.contains("VS −700"))
        XCTAssertTrue(html.contains("PROC › ENT"))
        XCTAssertTrue(html.contains("class=\"missed\""))
        XCTAssertNil(ApproachPrinter.quickHTML(card, mode: .autopilot), "no quick card -> nil")
    }
}
