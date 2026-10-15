import Foundation

/// Step-by-step approach guides for the Perspective / GFC 700 in N63KA (Resources/Data/approach_cards.json).
/// Training aids: steps marked APPROVED restate the POH; everything else must be checked by a CFII
/// against the GFC 700 AFM supplement and the Cockpit Reference Guide.
struct ApproachGuideBook: Codable, Sendable {
    let title: String
    let revision: String
    let basis: String
    let cards: [ApproachCard]
    /// What each Perspective / GFC 700 control does.
    let keyReference: [KeyGroup]?
    let keyReferenceNote: String?

    static func decode(_ data: Data) throws -> ApproachGuideBook {
        try JSONDecoder().decode(ApproachGuideBook.self, from: data)
    }
}

struct ApproachCard: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    /// "DA" or "MDA".
    let minimaType: String
    /// Navigation source on final: "GPS", "LOC1" or "VOR1".
    let navSource: String
    let verticalGuidance: String
    let keyTrap: String
    let phases: [ApproachPhase]
    let notes: [String]
    let authority: SourceAuthority
    let revision: String
    /// The in-flight card: brief items done before the approach, then only what you do while flying it.
    let quick: QuickSet?

    func quickCard(for mode: FlyingMode) -> QuickCard? {
        switch mode {
        case .autopilot: quick?.autopilot
        case .handFlown: quick?.manual
        }
    }

    /// Phases with only the steps for the chosen way of flying.
    func phases(for mode: FlyingMode) -> [ApproachPhase] {
        phases.map { ApproachPhase(title: $0.title, steps: $0.steps.filter { $0.applies(to: mode) }) }
            .filter { !$0.steps.isEmpty }
    }

    func stepCount(for mode: FlyingMode) -> Int { phases(for: mode).reduce(0) { $0 + $1.steps.count } }
}

struct QuickSet: Codable, Hashable, Sendable {
    let autopilot: QuickCard
    let manual: QuickCard
}

struct KeyGroup: Codable, Hashable, Sendable {
    struct Item: Codable, Hashable, Sendable {
        let key: String
        let does: String
    }
    let group: String
    let items: [Item]
}

/// One set-up task with the exact buttons, in order.
struct SetupItem: Codable, Hashable, Sendable {
    let task: String
    let keys: [String]
    let note: String?
}

struct QuickCard: Codable, Hashable, Sendable {
    /// Perspective set-up, done before starting the approach (enroute or on vectors).
    let brief: [SetupItem]
    /// One line per moment of the approach: when, at most three actions, one thing to see.
    let fly: [QuickLine]
}

struct QuickLine: Codable, Hashable, Sendable {
    let when: String
    let `do`: [String]
    let check: String?
}

struct ApproachPhase: Codable, Hashable, Sendable {
    let title: String
    let steps: [ApproachStep]
}

struct ApproachStep: Codable, Identifiable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable { case both, autopilot, manual }

    let id: String
    let action: String
    /// Buttons, knobs and softkeys to use, in order.
    let controls: [String]
    /// When to do it (e.g. "At the FAF").
    let when: String?
    /// What to check afterwards (FMA, HSI, altimeter).
    let verify: String?
    let mode: Mode
    let source: String?
    let authority: SourceAuthority

    func applies(to flying: FlyingMode) -> Bool {
        switch (mode, flying) {
        case (.both, _), (.autopilot, .autopilot), (.manual, .handFlown): return true
        default: return false
        }
    }
}

enum FlyingMode: String, CaseIterable, Identifiable, Sendable {
    case autopilot = "Autopilot"
    case handFlown = "Hand-flown"
    var id: String { rawValue }
}

enum ApproachPrinter {
    /// Large-type quick card for the kneeboard: brief items, then the fly lines.
    static func quickHTML(_ card: ApproachCard, mode: FlyingMode) -> String? {
        guard let q = card.quickCard(for: mode) else { return nil }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var h = """
        <html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,Helvetica;margin:14px;color:#000}
        h1{font-size:20pt;margin:0} .brief{font-size:9.5pt;margin:4px 0 8px;color:#222} .brief ol{margin:2px 0;padding-left:16px}
        table{border-collapse:collapse;width:100%} td{border-top:2px solid #000;padding:7px 6px;vertical-align:top}
        .when{font-size:15pt;font-weight:800;width:26%} .do{font-size:16pt;font-weight:600} .chk{font-size:11pt;color:#333}
        .missed td{background:#eee} .foot{font-size:7pt;color:#555;margin-top:8px}
        </style></head><body>
        <h1>\(esc(card.title)) · \(mode.rawValue)</h1>
        <div class="brief"><b>Set up before the approach</b><ol>\(q.brief.map { "<li><b>\(esc($0.task)):</b> \($0.keys.map(esc).joined(separator: " › "))</li>" }.joined())</ol></div><table>
        """
        for line in q.fly {
            let missed = line.when == "MISSED" || line.when == "THEN"
            h += "<tr\(missed ? " class=\"missed\"" : "")><td class=\"when\">\(esc(line.when))</td><td><div class=\"do\">\(line.do.map(esc).joined(separator: " · "))</div>"
            if let c = line.check { h += "<div class=\"chk\">\(esc(c))</div>" }
            h += "</td></tr>"
        }
        h += "</table><div class=\"foot\">N63KA training aid \(esc(card.revision)). Speeds POH 4-3 / 4-21. Charts, POH and approved supplements control.</div></body></html>"
        return h
    }

    /// Printable one-page HTML for a card in one flying mode (AirPrint or "Save to Files" as PDF).
    static func html(_ card: ApproachCard, mode: FlyingMode, basis: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var h = """
        <html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,Helvetica;font-size:8.3pt;line-height:1.15;margin:8px;color:#000}
        h1{font-size:13pt;margin:0} .sub{color:#444;margin:1px 0 4px} .trap{border:1.5px solid #000;padding:3px 6px;font-weight:600;margin:4px 0}
        h2{font-size:9.5pt;margin:5px 0 1px;border-bottom:1px solid #999} ol{margin:0;padding-left:16px} li{margin:1px 0}
        .when{font-weight:700} .key{border:1px solid #000;border-radius:3px;padding:0 2px;font-size:7.8pt;white-space:nowrap}
        .verify{color:#333;font-style:italic} .appr{font-size:7.5pt;font-weight:700} .foot{font-size:7pt;color:#444;margin-top:3px}
        </style></head><body>
        <h1>N63KA &middot; \(esc(card.title)) &middot; \(mode.rawValue)</h1>
        <div class="sub">\(esc(card.subtitle)) &middot; Final on \(card.navSource) &middot; Vertical: \(esc(card.verticalGuidance))</div>
        <div class="trap">\(esc(card.keyTrap))</div>
        """
        for phase in card.phases(for: mode) {
            h += "<h2>\(esc(phase.title))</h2><ol>"
            for step in phase.steps {
                h += "<li>"
                if let when = step.when { h += "<span class=\"when\">\(esc(when)):</span> " }
                h += esc(step.action)
                if !step.controls.isEmpty {
                    h += " " + step.controls.map { "<span class=\"key\">\(esc($0))</span>" }.joined(separator: " ")
                }
                if let verify = step.verify { h += "<br><span class=\"verify\">Check: \(esc(verify))</span>" }
                if step.authority == .approved, let source = step.source { h += " <span class=\"appr\">[APPROVED \(esc(source))]</span>" }
                h += "</li>"
            }
            h += "</ol>"
        }
        for note in card.notes { h += "<div class=\"foot\">\(esc(note))</div>" }
        h += "<div class=\"foot\">TRAINING AID \(esc(card.revision)). \(esc(basis)) Current charts, NOTAMs, the POH and approved supplements control.</div></body></html>"
        return h
    }
}
