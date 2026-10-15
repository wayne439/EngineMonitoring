import Foundation

/// Offline text index of the N63KA POH, generated from POH.pdf (one entry per PDF page).
/// Text is machine-extracted: always verify against the printed POH page before acting.
struct POHIndex: Codable, Sendable {
    struct DocumentInfo: Codable, Sendable {
        let title: String
        let partNumber: String
        let revision: String
        let filename: String
        let pageCount: Int
        let authority: SourceAuthority
        let note: String
    }

    struct Page: Codable, Sendable, Identifiable, Hashable {
        var id: Int { pdfPage }
        /// 1-based page number within POH.pdf.
        let pdfPage: Int
        /// Printed page label, e.g. "3-17" or "TPOH 25-03 p1".
        let label: String
        let section: String
        let text: String
    }

    struct Procedure: Codable, Sendable, Identifiable, Hashable {
        enum Kind: String, Codable, Sendable { case emergency, abnormal }
        let id: String
        let title: String
        let group: String
        let kind: Kind
        /// Printed page label where the procedure starts.
        let label: String
        let pdfPage: Int
    }

    let document: DocumentInfo
    let procedures: [Procedure]
    let pages: [Page]

    func page(_ pdfPage: Int) -> Page? {
        pages.first { $0.pdfPage == pdfPage }
    }

    struct ProcedureGroup: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        var items: [Procedure]
    }

    /// Procedures grouped in POH order.
    func groupedProcedures(_ kind: Procedure.Kind) -> [ProcedureGroup] {
        var result: [ProcedureGroup] = []
        for p in procedures where p.kind == kind {
            if let last = result.last, last.name == p.group {
                result[result.count - 1].items.append(p)
            } else {
                result.append(ProcedureGroup(name: p.group, items: [p]))
            }
        }
        return result
    }

    /// The procedure's text: from its title on its start page up to the next procedure's title
    /// (at most two further pages), so the pilot sees that checklist without the rest of the section.
    func text(for procedure: Procedure) -> String {
        let ordered = procedures.filter { $0.kind == procedure.kind }
        let next = ordered.drop { $0.id != procedure.id }.dropFirst().first
        let lastPage = min(procedure.pdfPage + 2, next?.pdfPage ?? procedure.pdfPage + 2)
        var text = ""
        let section = page(procedure.pdfPage)?.section
        for n in procedure.pdfPage...max(procedure.pdfPage, lastPage) {
            guard let p = page(n), p.section == section else { break }
            text += (text.isEmpty ? "" : "\n\n[POH page \(p.label)]\n") + p.text
        }
        // Start at the title where the checklist begins (followed soon by step "1." or an annunciation),
        // not where it appears in a running header.
        if let r = Self.checklistStart(of: procedure.title, in: text) {
            text = String(text[r.lowerBound...])
        }
        if let next, next.title.caseInsensitiveCompare(procedure.title) != .orderedSame {
            let from = text.index(text.startIndex, offsetBy: min(procedure.title.count, text.count))
            if let r = text.range(of: next.title, options: .caseInsensitive, range: from..<text.endIndex) {
                text = String(text[..<r.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func checklistStart(of title: String, in text: String) -> Range<String.Index>? {
        var candidates: [Range<String.Index>] = []
        var from = text.startIndex
        while let r = text.range(of: title, options: .caseInsensitive, range: from..<text.endIndex) {
            candidates.append(r)
            from = r.upperBound
        }
        let starts = candidates.first { r in
            let tail = text[r.upperBound...].prefix(160)
            return tail.contains(" 1.") || tail.contains("Warning") || tail.contains("Caution")
        }
        return starts ?? candidates.first
    }

    static func decode(_ data: Data) throws -> POHIndex {
        try JSONDecoder().decode(POHIndex.self, from: data)
    }
}

/// Keyword search over POH pages. Every query word must appear on the page.
enum POHSearch {
    struct Hit: Identifiable, Hashable, Sendable {
        var id: Int { page.pdfPage }
        let page: POHIndex.Page
        let score: Int
        let snippet: String
    }

    /// Pilot shorthand expanded to the words the POH uses.
    static let synonyms: [String: [String]] = [
        "cht": ["cylinder head temperature", "cht"],
        "egt": ["exhaust gas temperature", "egt"],
        "tit": ["turbine inlet temperature", "tit"],
        "alt": ["alternator", "alt"],
        "ap": ["autopilot"],
        "a/p": ["autopilot"],
        "caps": ["caps", "parachute"],
        "volts": ["voltage", "volts"],
        "oilp": ["oil pressure"],
        "map": ["manifold pressure", "map"],
        "ff": ["fuel flow"],
    ]

    static func search(_ query: String, in index: POHIndex, limit: Int = 30) -> [Hit] {
        let terms = tokenize(query)
        guard !terms.isEmpty else { return [] }
        let procedurePages = Set(index.procedures.map(\.pdfPage))
        var hits: [Hit] = []
        for page in index.pages {
            let lower = page.text.lowercased()
            var score = 0
            var firstMatch: String.Index?
            var allFound = true
            for alternatives in terms {
                var found = false
                for alt in alternatives {
                    var count = 0
                    var searchRange = lower.startIndex..<lower.endIndex
                    while let r = lower.range(of: alt, range: searchRange) {
                        searchRange = r.upperBound..<lower.endIndex
                        // Short terms ("tit", "map", "ff") must be whole words, not parts of "quantity".
                        if alt.count <= 4, !isWholeWord(r, in: lower) { continue }
                        count += 1
                        if firstMatch == nil || r.lowerBound < firstMatch! { firstMatch = r.lowerBound }
                        if count > 20 { break }
                    }
                    if count > 0 { found = true; score += count * (alt.count > 3 ? 2 : 1) }
                }
                if !found { allFound = false; break }
            }
            guard allFound else { continue }
            let phrase = query.lowercased().trimmingCharacters(in: .whitespaces)
            if phrase.contains(" "), lower.contains(phrase) { score += 25 }
            if procedurePages.contains(page.pdfPage) { score += 10 }
            if page.section.hasPrefix("Section 3") { score += 8 }
            if page.text.contains("Intentionally Left Blank"), page.text.count < 200 { continue }
            hits.append(Hit(page: page, score: score, snippet: snippet(page.text, lower: lower, at: firstMatch)))
        }
        return Array(hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.page.pdfPage < $1.page.pdfPage }.prefix(limit))
    }

    static func isWholeWord(_ r: Range<String.Index>, in s: String) -> Bool {
        let before = r.lowerBound > s.startIndex ? s[s.index(before: r.lowerBound)] : " "
        let after = r.upperBound < s.endIndex ? s[r.upperBound] : " "
        return !before.isLetter && !after.isLetter
    }

    /// Each query word becomes a list of acceptable spellings (synonyms).
    static func tokenize(_ query: String) -> [[String]] {
        query.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "/" || $0 == "-") }
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
            .map { synonyms[$0] ?? [$0] }
    }

    static let stopWords: Set<String> = ["the", "and", "or", "of", "to", "in", "on", "a", "an", "is", "what", "do", "how", "if", "my", "for", "with"]

    static func snippet(_ text: String, lower: String, at index: String.Index?, radius: Int = 110) -> String {
        guard let index else { return String(text.prefix(radius * 2)) }
        let offset = lower.distance(from: lower.startIndex, to: index)
        let startOffset = max(0, offset - radius)
        let start = text.index(text.startIndex, offsetBy: min(startOffset, text.count))
        let end = text.index(start, offsetBy: min(radius * 2, text.distance(from: start, to: text.endIndex)))
        return (startOffset > 0 ? "…" : "") + text[start..<end].trimmingCharacters(in: .whitespaces) + (end < text.endIndex ? "…" : "")
    }
}

enum POHFormatter {
    /// Puts each numbered checklist step and lettered sub-step on its own line; collapses dot leaders.
    static func readable(_ text: String) -> String {
        var s = text
        // "Fuel Pump ........... BOOST" -> "Fuel Pump ... BOOST"
        s = s.replacingOccurrences(of: #"\s*\.{4,}\s*"#, with: " … ", options: .regularExpression)
        // Numbered steps "1." .. "19." and sub-steps "a." / "(1)" start new lines.
        s = s.replacingOccurrences(of: #"\s+(\d{1,2}\.)\s+"#, with: "\n$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([a-h]\.)\s+(?=[A-Z])"#, with: "\n    $1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+(\(\d\))\s+"#, with: "\n        $1 ", options: .regularExpression)
        for word in ["Amplification", "• WARNING •", "• Caution •", "• Note •", "If alternator", "After Deployment:"] {
            s = s.replacingOccurrences(of: " " + word, with: "\n\n" + word)
        }
        return s
    }
}
