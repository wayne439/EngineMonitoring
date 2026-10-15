import Foundation

// Builds Resources/Data/flight_history.json from a folder of Perspective CSV logs
// (the SharePoint Cirrus/Engine Data/data_log folder), using the app's own summarizer and issue detector.
// Usage: historygen <logs folder> <flight_history.json> [issue_history.md]

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: historygen <logs dir> <out.json> [report.md]"); exit(2) }
let dir = URL(fileURLWithPath: args[1])
let files = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter { $0.pathExtension.lowercased() == "csv" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

final class Box: @unchecked Sendable {
    var results: [FlightSummary?]
    var errors: [String] = []
    let lock = NSLock()
    init(_ n: Int) { results = Array(repeating: nil, count: n) }
}
let box = Box(files.count)
let started = Date()
DispatchQueue.concurrentPerform(iterations: files.count) { i in
    let url = files[i]
    do {
        let data = try Data(contentsOf: url)
        let name = FlightLogLibrary.storedFilename(for: url.lastPathComponent)
        let log = try PerspectiveLogParser.parse(data: data, filename: name)
        guard log.sampleCount > 0 else { throw PerspectiveLogError.noSamples }
        let s = FlightSummarizer.summarize(log)
        box.lock.lock(); box.results[i] = s; box.lock.unlock()
    } catch {
        box.lock.lock(); box.errors.append("\(url.lastPathComponent): \(error)"); box.lock.unlock()
    }
}
let summaries = box.results.compactMap { $0 }.sorted { $0.start < $1.start }
let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
let history = BundledFlightHistory(generatedOn: f.string(from: Date()),
                                   sourceFolder: "SharePoint Cirrus/Engine Data/data_log",
                                   logCount: summaries.count, summaries: summaries)
let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
try enc.encode(history).write(to: URL(fileURLWithPath: args[2]))
print("logs \(files.count), summarized \(summaries.count), failed \(box.errors.count), flights \(summaries.filter(\.isFlight).count), \(Int(Date().timeIntervalSince(started))) s")
for e in box.errors.prefix(20) { print("  skip", e) }

// Issue report (markdown) for SharePoint.
let groups = IssueHistory.build(summaries: summaries, records: [:])
let local = DateFormatter(); local.locale = Locale(identifier: "en_US_POSIX"); local.dateFormat = "yyyy-MM-dd HH:mm"
var md = "# N63KA issue history from the engine data card\n\n"
md += "Built \(f.string(from: Date())) from \(summaries.count) logs in SharePoint Cirrus/Engine Data/data_log "
if let a = summaries.first, let b = summaries.last { md += "(\(f.string(from: a.start)) to \(f.string(from: b.start)))" }
md += ", \(summaries.filter(\.isFlight).count) flights. Recorded values only; no cause is assigned. POH, approved checklists and your A&P govern.\n\n"
md += "| Severity | Issue | System | Flights | Latest |\n| --- | --- | --- | --- | --- |\n"
for g in groups {
    local.timeZone = .init(secondsFromGMT: -7 * 3600)
    md += "| \(g.severity.rawValue) | \(g.guide.title) | \(g.system.rawValue) | \(g.flightCount) | \(f.string(from: g.latest.time)) |\n"
}
md += "\n"
for g in groups {
    md += "## \(g.guide.title) (\(g.severity.rawValue), \(g.system.rawValue))\n\n\(g.guide.meaning)\n\n"
    if let r = g.guide.pohReference { md += "**In flight (\(r)):**\n\n" } else { md += "**In flight:**\n\n" }
    for s in g.guide.inFlight { md += "- \(s)\n" }
    md += "\n**To resolve:**\n\n"
    for s in g.guide.toResolve { md += "- \(s)\n" }
    md += "\n**Occurrences (\(g.occurrences.count)):**\n\n"
    for o in g.occurrences.prefix(40) {
        let tz = summaries.first { $0.filename == o.source }?.timeZone ?? TimeZone(secondsFromGMT: -7 * 3600)!
        local.timeZone = tz
        md += "- \(local.string(from: o.time)) · \(o.source) · \(o.detail)\n"
    }
    if g.occurrences.count > 40 { md += "- … and \(g.occurrences.count - 40) more\n" }
    md += "\n"
}
if args.count > 3 { try md.write(toFile: args[3], atomically: true, encoding: .utf8) }
for g in groups { print(g.severity.rawValue, g.flightCount, g.kind, "-", g.guide.title) }
