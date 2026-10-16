import Foundation
import PDFKit

/// The pilot's own POH and manuals, built on this iPad from the PDFs they uploaded.
/// The POH feeds PROCEDURES and ASK; other manuals (for example a Garmin pilot's guide) are searchable in ASK.
@MainActor
final class POHRepository: ObservableObject {
    @Published private(set) var index: POHIndex?
    @Published private(set) var manuals: [POHIndex] = []
    @Published private(set) var loadError: String?
    @Published private(set) var isBuilding = false
    @Published private(set) var buildStatus: String?

    private let bundle: Bundle
    private var manifest: [ManualEntry] = []

    /// One uploaded PDF that has been indexed. `sourceID` is the upload's id (or "file-…" for Files picks).
    struct ManualEntry: Codable, Hashable {
        let sourceID: String
        let filename: String
        let procedureCount: Int
        let pageCount: Int
        let looksLikePOH: Bool
    }

    static let noPOHMessage = "No POH yet. Upload your POH / AFM PDF under AIRCRAFT > Documents and uploads (POH / AFM item) or on the website, or choose it from Files below. It is read on this iPad in a minute or two."

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        Task { await load() }
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Manuals", isDirectory: true)
    }

    private static var manifestURL: URL { folder.appendingPathComponent("manuals.json") }

    func load() async {
        let folder = Self.folder
        let entries = (try? JSONDecoder().decode([ManualEntry].self, from: Data(contentsOf: Self.manifestURL))) ?? []
        let decoded: [(ManualEntry, POHIndex)] = await Task.detached(priority: .userInitiated) {
            entries.compactMap { e in
                let url = folder.appendingPathComponent(e.sourceID + ".json")
                guard let data = try? Data(contentsOf: url), let idx = try? POHIndex.decode(data) else { return nil }
                return (e, idx)
            }
        }.value
        manifest = decoded.map(\.0)
        apply(decoded)
        if index == nil, let url = bundle.url(forResource: "poh_index", withExtension: "json"),
           let data = try? Data(contentsOf: url), let idx = try? POHIndex.decode(data) {
            index = idx
        }
        loadError = index == nil ? Self.noPOHMessage : nil
    }

    /// Picks the POH (most emergency/abnormal procedures found) and keeps the rest as manuals.
    private func apply(_ items: [(ManualEntry, POHIndex)]) {
        let ranked = items.sorted {
            ($0.0.looksLikePOH ? 1 : 0, $0.0.procedureCount, $0.0.pageCount) > ($1.0.looksLikePOH ? 1 : 0, $1.0.procedureCount, $1.0.pageCount)
        }
        if let best = ranked.first, best.0.looksLikePOH || best.0.procedureCount > 0 {
            index = best.1
            manuals = ranked.dropFirst().map(\.1)
        } else {
            index = nil
            manuals = ranked.map(\.1)
        }
    }

    /// Brings in POH and manual PDFs uploaded in the app or on the website that are not indexed yet.
    func syncFromUploads(cloud: CloudStore) async {
        guard cloud.isSignedIn, !isBuilding else { return }
        let known = Set(manifest.map(\.sourceID))
        let wanted = cloud.inboxItems.filter { item in
            ["poh-limits", "turbo", "other"].contains(item.category)
                && item.filename.lowercased().hasSuffix(".pdf")
                && item.status != "failed"
                && !known.contains(item.id)
        }
        guard !wanted.isEmpty else { return }
        isBuilding = true
        defer { isBuilding = false; buildStatus = nil }
        for item in wanted {
            buildStatus = "Reading \(item.filename)…"
            guard let url = await cloud.download(item) else { continue }
            await install(pdf: url, sourceID: item.id, filename: item.filename)
        }
    }

    /// Indexes a PDF picked from Files.
    func installFromFiles(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        isBuilding = true
        buildStatus = "Reading \(url.lastPathComponent)…"
        defer { isBuilding = false; buildStatus = nil }
        await install(pdf: url, sourceID: "file-" + UUID().uuidString, filename: url.lastPathComponent)
    }

    private func install(pdf url: URL, sourceID: String, filename: String) async {
        let folder = Self.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pdfName = sourceID + ".pdf"
            let dest = folder.appendingPathComponent(pdfName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            let built = try await Task.detached(priority: .userInitiated) {
                try POHBuilder.build(pdfURL: dest, storedFilename: pdfName, originalFilename: filename)
            }.value
            try JSONEncoder().encode(built.index).write(to: folder.appendingPathComponent(sourceID + ".json"), options: .atomic)
            let entry = ManualEntry(sourceID: sourceID, filename: pdfName, procedureCount: built.index.procedures.count,
                                    pageCount: built.index.pages.count, looksLikePOH: built.looksLikePOH)
            manifest.removeAll { $0.sourceID == sourceID }
            manifest.append(entry)
            try JSONEncoder().encode(manifest).write(to: Self.manifestURL, options: .atomic)
            await load()
        } catch {
            loadError = "Could not read \(filename): \(error.localizedDescription)"
        }
    }

    /// The PDF behind an index (uploaded copy, or one bundled with the app).
    func pdfURL(for document: POHIndex.DocumentInfo) -> URL? {
        let local = Self.folder.appendingPathComponent(document.filename)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return DocumentRepository.resourceURL(named: document.filename, in: bundle)
    }

    /// True when the POH or an uploaded manual has turbo limits (TIT and turbo / turbonormalizer text).
    var coversTurbo: Bool {
        ([index].compactMap { $0 } + manuals).contains { doc in
            doc.pages.contains { p in
                let t = p.text.lowercased()
                return (t.contains("turbine inlet temperature") || t.contains(" tit "))
                    && (t.contains("turbo") || t.contains("turbonormal"))
                    && (t.contains("limit") || t.contains("maximum"))
            }
        }
    }

    /// The POH's PDF, for "Open POH Page".
    var pdfURL: URL? {
        guard let index else { return bundle.url(forResource: "POH", withExtension: "pdf") }
        return pdfURL(for: index.document)
    }

    /// Searches the POH first, then every other manual.
    func search(_ query: String) -> [POHSearch.Hit] {
        let all = [index].compactMap { $0 } + manuals
        return all.flatMap { POHSearch.search(query, in: $0) }
    }
}

/// Turns a POH / AFM PDF into a POHIndex: text per page, page labels like "3-17", GAMA sections,
/// and the Section 3 / 3A procedures (from the PDF's bookmarks, or from checklist headings).
enum POHBuilder {
    struct Result {
        let index: POHIndex
        let looksLikePOH: Bool
    }

    enum BuildError: LocalizedError {
        case unreadable, noText
        var errorDescription: String? {
            switch self {
            case .unreadable: "the file is not a readable PDF."
            case .noText: "the PDF has no text (it may be a scan). Upload a text PDF from the manufacturer if you can."
            }
        }
    }

    static let sectionNames: [String: String] = [
        "1": "Section 1 - General", "2": "Section 2 - Limitations", "3": "Section 3 - Emergency Procedures",
        "3A": "Section 3A - Abnormal Procedures", "4": "Section 4 - Normal Procedures", "5": "Section 5 - Performance Data",
        "6": "Section 6 - Weight and Balance", "7": "Section 7 - Systems Description",
        "8": "Section 8 - Handling, Servicing and Maintenance", "9": "Section 9 - Supplements", "10": "Section 10 - Safety Information",
    ]

    static func rank(_ key: String) -> Double {
        key == "3A" ? 3.5 : Double(key) ?? 0
    }

    static func build(pdfURL: URL, storedFilename: String, originalFilename: String) throws -> Result {
        guard let doc = PDFDocument(url: pdfURL) else { throw BuildError.unreadable }
        let labelRegex = try NSRegularExpression(pattern: #"(?<![\w/-])(10|[1-9]A?)-(\d{1,3})(?![\w-])"#)

        var rawLines: [[String]] = []
        var texts: [String] = []
        var rawKeys: [String?] = []
        var labels: [String] = []
        for i in 0..<doc.pageCount {
            let raw = doc.page(at: i)?.string ?? ""
            let lines = raw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let text = lines.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            rawLines.append(lines)
            texts.append(text)
            let found = pageLabel(in: text, regex: labelRegex, pdfLabel: doc.page(at: i)?.label)
            rawKeys.append(found?.key)
            labels.append(found?.label ?? "\(i + 1)")
        }
        // A page's section counts only when a neighboring labelled page agrees, so a revision list
        // in the front matter ("4-23, 8-22 ...") doesn't start a section early.
        var keys: [String?] = []
        var currentKey: String?
        for i in rawKeys.indices {
            if let k = rawKeys[i] {
                let prev = rawKeys[..<i].last { $0 != nil } ?? nil
                let next = rawKeys[(i + 1)...].first { $0 != nil } ?? nil
                if k == prev || k == next { currentKey = k }
            }
            keys.append(currentKey)
        }
        guard texts.contains(where: { $0.count > 40 }) else { throw BuildError.noText }

        let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? (originalFilename as NSString).deletingPathExtension
        let labelled = rawKeys.compactMap { $0 }.count
        let sectioned = labelled > doc.pageCount / 4
        let pages: [POHIndex.Page] = texts.indices.map { i in
            let section = sectioned ? (keys[i].flatMap { sectionNames[$0] } ?? "Front Matter") : title
            return POHIndex.Page(pdfPage: i + 1, label: labels[i], section: section, text: texts[i])
        }

        var procedures = outlineProcedures(doc, keys: keys, labels: labels)
        if procedures.count < 3 {
            procedures = headingProcedures(rawLines: rawLines, keys: keys, labels: labels)
        }
        if !sectioned { procedures = [] }

        let front = texts.prefix(8).joined(separator: " ")
        let lowerFront = front.lowercased()
        let looksLikePOH = sectioned && (lowerFront.contains("operating handbook") || lowerFront.contains("flight manual")
            || pages.contains { $0.section.hasPrefix("Section 3 ") })
        let part = firstMatch(#"P/N\s*([0-9A-Z][0-9A-Z-]{3,})"#, in: front, group: 1) ?? ""
        let revision = firstMatch(#"(Original Issue|Reissue [A-Z]\b|Revision \d+|Rev\.? ?[A-Z0-9]{1,3}\b)"#, in: front, group: 1)
            ?? "uploaded \(Date().formatted(date: .abbreviated, time: .omitted))"

        let info = POHIndex.DocumentInfo(
            title: title, partNumber: part.isEmpty ? (originalFilename as NSString).deletingPathExtension : part,
            revision: revision, filename: storedFilename, pageCount: doc.pageCount,
            authority: looksLikePOH ? .approved : .manufacturer,
            note: "Read on this iPad from your uploaded \(originalFilename). Text is machine-extracted: verify against the printed page.")
        return Result(index: POHIndex(document: info, procedures: procedures, pages: pages), looksLikePOH: looksLikePOH)
    }

    /// The printed label ("3-17") that appears most often near the top or bottom of the page.
    static func pageLabel(in text: String, regex: NSRegularExpression, pdfLabel: String?) -> (label: String, key: String)? {
        func parse(_ s: String) -> (String, String)? {
            let ns = s as NSString
            guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
                  m.range.location == 0, m.range.length == ns.length else { return nil }
            return (s, ns.substring(with: m.range(at: 1)).uppercased())
        }
        if let pdfLabel, let p = parse(pdfLabel) { return (p.0, p.1) }
        let head = String(text.prefix(220)), tail = String(text.suffix(220))
        var counts: [String: Int] = [:]
        var order: [String] = []
        for part in [head, tail] {
            let ns = part as NSString
            for m in regex.matches(in: part, range: NSRange(location: 0, length: ns.length)) {
                let page = Int(ns.substring(with: m.range(at: 2))) ?? 999
                guard page <= 200 else { continue }
                let s = ns.substring(with: m.range).uppercased()
                if counts[s] == nil { order.append(s) }
                counts[s, default: 0] += 1
            }
        }
        let edges = String(text.prefix(40)) + " | " + String(text.suffix(40))
        guard let best = order.max(by: { counts[$0]! < counts[$1]! }),
              counts[best]! >= 2 || edges.uppercased().contains(best) else { return nil }
        let key = String(best[..<best.firstIndex(of: "-")!])
        return (best, key)
    }

    static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func makeProcedure(title: String, group: String, key: String, page: Int, labels: [String], used: inout Set<String>) -> POHIndex.Procedure {
        var id = "\(key.lowercased())-\(slug(title))"
        if used.contains(id) { id += "-\(page + 1)" }
        used.insert(id)
        return POHIndex.Procedure(id: id, title: title, group: group, kind: key == "3A" ? .abnormal : .emergency,
                                  label: labels[page], pdfPage: page + 1)
    }

    /// Procedures from the PDF bookmarks under Sections 3 and 3A.
    static func outlineProcedures(_ doc: PDFDocument, keys: [String?], labels: [String]) -> [POHIndex.Procedure] {
        guard let root = doc.outlineRoot else { return [] }
        var result: [POHIndex.Procedure] = []
        var used = Set<String>()
        func walk(_ node: PDFOutline, group: String?) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var pageIndex: Int?
                if let page = child.destination?.page { pageIndex = doc.index(for: page) }
                let key = pageIndex.flatMap { $0 < keys.count ? keys[$0] : nil }
                let inSection = key == "3" || key == "3A"
                let isSectionRoot = title.lowercased().hasPrefix("section")
                if child.numberOfChildren > 0 {
                    walk(child, group: inSection && !isSectionRoot ? title : nil)
                } else if inSection, let p = pageIndex, !title.isEmpty, !isSectionRoot {
                    result.append(makeProcedure(title: title, group: group ?? "General", key: key!, page: p, labels: labels, used: &used))
                }
            }
        }
        walk(root, group: nil)
        return result.sorted { $0.pdfPage < $1.pdfPage }
    }

    /// Fallback: a short title-case line on a Section 3 / 3A page followed within a few lines by step "1.".
    static func headingProcedures(rawLines: [[String]], keys: [String?], labels: [String]) -> [POHIndex.Procedure] {
        var result: [POHIndex.Procedure] = []
        var used = Set<String>()
        let skip = ["section", "p/n", "figure", "table", "continued", "intentionally", "note", "warning", "caution", "cirrus", "piper", "cessna", "beechcraft"]
        for (p, lines) in rawLines.enumerated() {
            guard let key = keys[p], key == "3" || key == "3A" else { continue }
            for (j, line) in lines.enumerated() {
                guard (4...70).contains(line.count), let first = line.first, first.isUppercase,
                      !line.hasSuffix("."), !line.contains("…"), !line.contains("...") else { continue }
                let lower = line.lowercased()
                guard !skip.contains(where: { lower.hasPrefix($0) }), line.filter(\.isLetter).count * 10 >= line.count * 7 else { continue }
                let next = lines[(j + 1)..<min(lines.count, j + 5)]
                guard next.contains(where: { $0.hasPrefix("1.") || $0.hasPrefix("1 ") && $0.count > 3 }) else { continue }
                let group = key == "3A" ? "Abnormal Procedures" : "Emergency Procedures"
                result.append(makeProcedure(title: line, group: group, key: key, page: p, labels: labels, used: &used))
            }
        }
        return result
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: group))
    }
}

/// Reads engine limits and the engine model from POH Section 2 (Limitations) text.
/// Each value keeps the printed page it came from so the owner can check it.
enum POHLimitExtractor {
    struct Value: Equatable, Sendable {
        let number: Double
        let page: String
    }

    struct Text: Equatable, Sendable {
        let text: String
        let page: String
    }

    struct Found: Equatable, Sendable {
        var engineModel: Text?
        var cylinders: Int?
        var turbocharged: Bool?
        var rpmMax: Value?
        var rpmOverspeed: Value?
        var oilTempMax: Value?
        var oilPressureMin: Value?
        var oilPressureMax: Value?
        var oilPressureCautionBelow: Value?
        var chtWarning: Value?
        var chtCaution: Value?
        var titMax: Value?
        var mapMax: Value?

        static let numberKeys: [(key: String, label: String, unit: String, path: WritableKeyPath<Found, Value?>)] = [
            ("rpmMax", "Max RPM", "RPM", \.rpmMax), ("rpmOverspeed", "Overspeed RPM", "RPM", \.rpmOverspeed),
            ("oilTempMax", "Oil temperature max", "°F", \.oilTempMax), ("oilPressureMin", "Oil pressure min", "psi", \.oilPressureMin),
            ("oilPressureMax", "Oil pressure max", "psi", \.oilPressureMax),
            ("oilPressureCautionBelow", "Oil pressure caution below", "psi", \.oilPressureCautionBelow),
            ("chtWarning", "CHT max", "°F", \.chtWarning), ("chtCaution", "CHT caution", "°F", \.chtCaution),
            ("titMax", "TIT max", "°F", \.titMax), ("mapMax", "Manifold pressure max", "inHg", \.mapMax),
        ]

        var count: Int {
            Self.numberKeys.filter { self[keyPath: $0.path] != nil }.count + (engineModel == nil ? 0 : 1)
        }

        /// Page labels prefixed with the document kind, e.g. "POH 2-6".
        func labelled(_ prefix: String) -> Found {
            var f = self
            for k in Self.numberKeys {
                if let v = f[keyPath: k.path] { f[keyPath: k.path] = Value(number: v.number, page: "\(prefix) \(v.page)") }
            }
            if let e = f.engineModel { f.engineModel = Text(text: e.text, page: "\(prefix) \(e.page)") }
            return f
        }

        /// Keeps this value where set, otherwise takes the other's.
        func filling(from other: Found) -> Found {
            var f = self
            for k in Self.numberKeys where f[keyPath: k.path] == nil { f[keyPath: k.path] = other[keyPath: k.path] }
            if f.engineModel == nil { f.engineModel = other.engineModel; f.cylinders = other.cylinders; f.turbocharged = other.turbocharged }
            return f
        }

        /// The other's values win where it has them (a supplement over the POH).
        func overridden(by other: Found) -> Found {
            other.filling(from: self)
        }
    }

    /// An AFM / POH supplement (for example a turbonormalizer STC supplement), as opposed to a pilot's guide.
    static func isSupplement(_ index: POHIndex) -> Bool {
        let front = index.pages.prefix(4).map(\.text).joined(separator: " ").lowercased() + " " + index.document.title.lowercased()
        return front.contains("supplement") && (front.contains("flight manual") || front.contains("afm") || front.contains("operating handbook") || front.contains("poh"))
    }

    /// The POH's Section 9 (supplements) as its own document, when it contains AFM supplements.
    static func section9(of index: POHIndex) -> POHIndex? {
        let pages = index.pages.filter { $0.section.hasPrefix("Section 9") }
        guard !pages.isEmpty, pages.contains(where: { $0.text.lowercased().contains("supplement") }) else { return nil }
        let d = index.document
        let info = POHIndex.DocumentInfo(title: "POH Section 9 supplements", partNumber: d.partNumber, revision: d.revision,
                                         filename: d.filename, pageCount: d.pageCount, authority: d.authority, note: d.note)
        return POHIndex(document: info, procedures: [], pages: pages)
    }

    static func crossCheck(poh: Found, supplement: Found) -> [LimitCrossCheck] {
        Found.numberKeys.compactMap { k in
            let a = poh[keyPath: k.path], b = supplement[keyPath: k.path]
            guard a != nil || b != nil else { return nil }
            return LimitCrossCheck(key: k.key, label: k.label, unit: k.unit, poh: a?.number, pohPage: a?.page,
                                   supplement: b?.number, supplementPage: b?.page)
        }
    }

    /// Dot leaders and colons between a label and its value ("Maximum RPM ....... 2700 RPM").
    static let lead = #"[\s.…:]*"#

    static func extract(from index: POHIndex) -> Found {
        let limitPages = index.pages.filter { $0.section.hasPrefix("Section 2 ") }
        let pages = limitPages.isEmpty ? index.pages : limitPages
        var f = Found()

        if let (m, page) = match(#"\b(Teledyne Continental|Continental|Lycoming|Rotax|Franklin)\b.{0,120}?\b([A-Z]{1,5}-\d{3}(?:-[A-Z0-9]{1,4})?)\b"#, in: pages) {
            let maker = m[1].contains("Continental") ? "Continental" : m[1]
            let model = m[2]
            f.engineModel = Text(text: "\(maker) \(model)", page: page)
            if let digits = model.split(separator: "-").dropFirst().first, let cc = Int(digits) {
                f.cylinders = cc >= 700 ? 8 : (cc >= 470 ? 6 : 4)
            }
            let prefix = model.split(separator: "-").first.map(String.init) ?? ""
            f.turbocharged = prefix.hasPrefix("T") || prefix.contains("TS") || prefix.hasPrefix("LT")
        }

        f.rpmMax = number(#"Maximum RPM"# + lead + #"(\d,?\d{3})\s*RPM"#, in: pages)
            ?? number(#"(?:Maximum (?:Engine )?Speed|Red ?line)"# + lead + #"(\d,?\d{3})\s*RPM"#, in: pages)
            ?? number(#"hp\s*@\s*(\d,?\d{3})\s*RPM"#, in: pages)
        f.rpmOverspeed = number(#"RPM\s+(?:is\s+)?greater than\s+(\d,?\d{3})\s+for more than 5 seconds"#, in: pages)
        f.oilTempMax = number(#"(?<!Minimum )Oil Temperature"# + lead + #"(\d{3})\s*°?\s*F?\s*(?:\(\d+\s*°?\s*C\)\s*)?maximum"#, in: pages)
            ?? number(#"Maximum Oil Temperature"# + lead + #"(\d{3})"#, in: pages)
        f.oilPressureMin = number(#"Oil Pressure.{0,40}?Minimum"# + lead + #"(\d{1,3})\s*psi"#, in: pages)
        f.oilPressureMax = number(#"Oil Pressure.{0,120}?Maximum"# + lead + #"(\d{2,3})\s*psi"#, in: pages)
        f.oilPressureCautionBelow = number(#"Oil Pressure\s*\([^)]*\)\s*0\s*[–-]\s*\d+\D{0,20}?\d+\s*[–-]\s*(\d+)"#, in: pages)

        if let (m, page) = match(#"Cylinder Head Temp\w*.{0,100}?(\d{3})\s*[–-]\s*(\d{3})\s*(?:\w+\s*)?>\s*(\d{3})"#, in: pages),
           let caution = Double(m[1]), let warning = Double(m[3]) {
            f.chtCaution = Value(number: caution, page: page)
            f.chtWarning = Value(number: warning, page: page)
        } else {
            f.chtWarning = number(#"Cylinder Head Temp\w*"# + lead + #"(\d{3})\s*°?\s*F?\s*(?:\(\d+\s*°?\s*C\)\s*)?max"#, in: pages)
        }
        f.titMax = number(#"(?:Maximum|Max\.?)[^.]{0,30}?(?:Turbine Inlet Temp\w*|\bTIT\b)"# + lead + #"(1[4-9]\d{2})\s*°?\s*F"#, in: pages)
            ?? number(#"(?:Turbine Inlet Temp\w*|\bTIT\b)[^.]{0,80}?(1[4-9]\d{2})\s*°?\s*F[^.]{0,20}?(?:max|limit|red)"#, in: pages)
            ?? number(#"(?:Turbine Inlet Temp\w*|\bTIT\b)\s*\([^)]*\)[^>]{0,80}?>\s*(1[4-9]\d{2})"#, in: pages)
        f.mapMax = number(#"(?:Maximum Manifold Pressure|Manifold Pressure[^.]{0,40}?Maximum)"# + lead + #"(\d{2}(?:\.\d)?)\s*(?:in\.?|inches|"|Hg|In)"#, in: pages)
        return f
    }

    /// First page whose text matches; returns the capture groups (0 = whole match) and the page label.
    static func match(_ pattern: String, in pages: [POHIndex.Page]) -> ([String], String)? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for page in pages {
            let ns = page.text as NSString
            guard let m = re.firstMatch(in: page.text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            return (groups, page.label)
        }
        return nil
    }

    static func number(_ pattern: String, in pages: [POHIndex.Page]) -> Value? {
        guard let (m, page) = match(pattern, in: pages), m.count > 1,
              let v = Double(m[1].replacingOccurrences(of: ",", with: "")) else { return nil }
        return Value(number: v, page: page)
    }
}
