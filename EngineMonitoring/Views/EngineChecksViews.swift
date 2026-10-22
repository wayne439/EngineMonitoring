import SwiftUI
import Charts
import UIKit

// MARK: - Post-flight report sections

/// Run-up mag check and lean test for one flight (post-flight report and bundled-flight summary).
struct EngineChecksSection: View {
    let result: EngineCheckResult?
    let timeZone: TimeZone

    var body: some View {
        Section {
            if let result {
                if result.runups.isEmpty {
                    Text("No run-up mag check found in this log.").foregroundStyle(.secondary)
                }
                ForEach(result.runups, id: \.self) { u in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MagCheck.describe(u, timeZone: timeZone)).font(.subheadline)
                        if u.findings.isEmpty {
                            Text("Within \(POHRef.page("4-14")): drops under 150 RPM, difference under 75 RPM, every cylinder's EGT rose.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(u.findings, id: \.self) { f in
                            Text("\(MagCheck.severity(f).rawValue): " + MagCheck.describe(f))
                                .font(.caption).foregroundStyle(MagCheck.severity(f) == .info ? Color.secondary : Color.orange)
                        }
                    }
                }
                ForEach(result.gami, id: \.self) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "fuel spread %.1f gph: %@", t.spread, GAMICheck.rating(t.spread))).font(.subheadline)
                        Text(GAMICheck.describe(t)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { MagCheckHistoryView() } label: { Label("Run-up mag checks, all flights", systemImage: "bolt.horizontal") }
            } else {
                Text("Not checked (summary built before v0.9.7).").foregroundStyle(.secondary)
            }
        } header: {
            Text("Run-Up Mag Check")
        } footer: {
            Text("\(POHRef.page("4-14")): at 1,700 RPM, R then L; drop no more than 150 RPM, difference no more than 75 RPM. Each cylinder's EGT should rise on each mag; one that stays flat is not firing on that mag.")
        }
    }
}

/// Report card link with the headline numbers (post-flight report).
struct ReportCardSection: View {
    let summary: FlightSummary
    let summaries: [FlightSummary]

    var body: some View {
        let rows = ReportCard.rows(for: summary, in: summaries)
        if !rows.isEmpty {
            Section {
                NavigationLink {
                    ReportCardView(filename: summary.filename)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Report Card", systemImage: "list.number").font(.headline)
                        let notable = rows.compactMap { r in ReportCard.reading(r).map { "\(r.metric.label): \($0)" } }
                        Text(notable.isEmpty ? "Every number within this aircraft's usual range." : notable.prefix(3).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Compared With Every Earlier Flight")
            }
        }
    }
}

// MARK: - Report card

struct ReportCardView: View {
    /// Flight to show; nil = newest flight.
    var filename: String? = nil
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        let all = Array(logStore.summaries.values)
        let flights = ReportCard.flights(all)
        List {
            if let s = filename.flatMap({ logStore.summaries[$0] }) ?? flights.last {
                let rows = ReportCard.rows(for: s, in: all)
                Section {
                    LabeledContent("Flight", value: s.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Log", value: s.filename)
                    if let h = s.engineChecks?.card?.airborneHours { LabeledContent("Airborne", value: String(format: "%.1f h", h)) }
                    if let d = ReportCard.daysSincePrevious(s, in: all) {
                        LabeledContent("Days since previous flight", value: String(format: "%.0f", d))
                    }
                } footer: {
                    Text("Percentile: where this flight sits among this aircraft's earlier flights (50 = typical). Bars turn orange at the far ends; for CHT, TIT and spreads lower is better, for speed, mpg and climb higher is better.")
                }
                ForEach(ReportCard.groups, id: \.self) { g in
                    let items = rows.filter { $0.metric.group == g }
                    if !items.isEmpty {
                        Section(g) {
                            ForEach(items) { r in ReportCardRowView(row: r) }
                        }
                    }
                }
                if rows.isEmpty {
                    Text("Less than 10 minutes airborne: no report card.").foregroundStyle(.secondary)
                }
            } else {
                Text("No flights with 10 minutes airborne yet.").foregroundStyle(.secondary)
            }
            if flights.count > 1 {
                Section("Other Flights") {
                    ForEach(Array(flights.reversed().prefix(30)), id: \.filename) { f in
                        NavigationLink {
                            ReportCardView(filename: f.filename)
                        } label: {
                            Text(f.start.formatted(date: .abbreviated, time: .shortened) + (f.departure.map { " · \($0)" } ?? ""))
                        }
                    }
                }
            }
        }
        .navigationTitle("Report Card")
    }
}

struct ReportCardRowView: View {
    let row: ReportCardRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.metric.label)
                Spacer()
                Text(row.metric.format(row.value)).monospacedDigit().bold()
            }
            if let p = row.percentile {
                HStack(spacing: 8) {
                    ProgressView(value: p, total: 100).tint(p >= 95 || p <= 5 ? Color.orange : Color.accentColor)
                    Text(String(format: "%.0f%%ile", p)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if let lo = row.low, let hi = row.high, let m = row.median {
                    Text("Normal: \(row.metric.format(lo)) to \(row.metric.format(hi)), typical \(row.metric.format(m)) (\(row.earlier) flights)"
                         + (ReportCard.reading(row).map { " · \($0)" } ?? ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Needs \(ReportCard.minEarlier) earlier flights for a percentile.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Mag check history

struct MagCheckHistoryView: View {
    @EnvironmentObject private var logStore: FlightLogStore

    private struct DropPoint: Identifiable {
        let time: Date
        let mag: String
        let drop: Double
        var id: String { "\(mag)-\(time.timeIntervalSince1970)" }
    }

    var body: some View {
        let all = Array(logStore.summaries.values)
        let history = MagCheck.history(all)
        let pattern = MagCheck.cylinderPattern(history.map { $0.runup })
        List {
            Section {
                if history.isEmpty {
                    Text("No run-up mag checks found yet.").foregroundStyle(.secondary)
                } else {
                    let pts = history.flatMap { h in h.runup.mags.map { DropPoint(time: h.runup.time, mag: $0.mag, drop: $0.drop) } }
                    Chart {
                        ForEach(pts) { p in
                            PointMark(x: .value("Date", p.time), y: .value("RPM drop", p.drop))
                                .foregroundStyle(by: .value("Mag", p.mag))
                                .symbolSize(20)
                        }
                        RuleMark(y: .value("POH limit", MagCheck.maxDrop))
                            .foregroundStyle(Color.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .chartYAxisLabel("RPM drop")
                    .frame(height: 200)
                    let r = history.compactMap { $0.runup.drop("R") }, l = history.compactMap { $0.runup.drop("L") }
                    LabeledContent("Run-ups with a mag check", value: "\(history.count)")
                    LabeledContent("Typical drop", value: "R \(Int(EngineChecks.median(r) ?? 0)) · L \(Int(EngineChecks.median(l) ?? 0)) RPM")
                }
            } header: {
                Text("Mag Drops")
            } footer: {
                Text("Dashed line: the 150 RPM drop limit\(POHRef.isSR22 ? " (POH 4-14)" : " (check your POH)"). The run-up is found automatically (on the ground, 1,600-2,150 RPM held 20 s or more); a dip counts as a mag check when the EGTs rise together.")
            }

            if !history.isEmpty {
                Section {
                    Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text("Cyl").bold()
                            ForEach(1...6, id: \.self) { Text("\($0)").bold() }
                        }
                        ForEach(["R", "L"], id: \.self) { mag in
                            GridRow {
                                Text(mag).bold()
                                ForEach(0..<6, id: \.self) { c in
                                    let v = pattern[mag]?[c] ?? nil
                                    Text(v.map { String(format: "%+.0f", $0) } ?? "-")
                                        .monospacedDigit()
                                        .foregroundStyle((v ?? 0) <= -MagCheck.coldMargin ? Color.orange : Color.primary)
                                }
                            }
                        }
                    }
                    .font(.callout)
                } header: {
                    Text("EGT Rise vs The Other Cylinders (°F)")
                } footer: {
                    Text("Median over every run-up: how much less (−) or more (+) each cylinder's EGT rises on each mag than the others. A cylinder well below the others on one mag points at that mag's plug or lead for that cylinder.")
                }
            }

            Section("Run-Ups (Newest First)") {
                ForEach(history.prefix(60), id: \.runup) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.runup.time.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                        Text(MagCheck.describe(h.runup)).font(.caption)
                        ForEach(h.runup.findings, id: \.self) { f in
                            Text("\(MagCheck.severity(f).rawValue): " + MagCheck.describe(f)).font(.caption)
                                .foregroundStyle(MagCheck.severity(f) == .info ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("Run-Up Mag Check")
    }
}

// MARK: - lean test

struct GAMIView: View {
    @EnvironmentObject private var logStore: FlightLogStore

    private struct Peak: Identifiable {
        let cylinder: String
        let flow: Double
        var id: String { cylinder }
    }

    var body: some View {
        let tests = GAMICheck.history(Array(logStore.summaries.values))
        List {
            Section {
                if let t = tests.first?.test {
                    let peaks = t.peakFlow.enumerated().compactMap { i, f in f.map { Peak(cylinder: "Cyl \(i + 1)", flow: $0) } }
                    Text(String(format: "Latest spread %.1f gph: %@", t.spread, GAMICheck.rating(t.spread))).font(.headline)
                    Chart(peaks) { p in
                        BarMark(x: .value("Cylinder", p.cylinder), y: .value("Fuel flow at peak EGT", p.flow))
                    }
                    .chartYScale(domain: ((peaks.map(\.flow).min() ?? 0) - 0.5)...((peaks.map(\.flow).max() ?? 1) + 0.3))
                    .chartYAxisLabel("gph at peak EGT")
                    .frame(height: 180)
                    Text(GAMICheck.describe(t)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No lean test in the logs yet. This aircraft's logs show big-mixture-pull leaning, which is too fast to measure the spread. Fly the test below once; the app finds it in the next log you import.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Fuel Spread")
            } footer: {
                Text("Fuel flow at which each cylinder reaches peak EGT. Spread 0.5 gph or less: well balanced, smooth lean of peak. About 1.0 gph or more: mismatched injectors (clean/flow them, or fit a matched injector set).")
            }

            Section {
                ForEach(Array(GAMICheck.procedure.enumerated()), id: \.offset) { i, step in
                    Text("\(i + 1). \(step)")
                }
            } header: {
                Text("Guided Lean Test")
            } footer: {
                Text("Technique, not a POH procedure. Engine limits in your POH/AFM and approved supplements apply throughout.")
            }

            if tests.count > 1 {
                Section("Earlier Tests") {
                    ForEach(tests.dropFirst(), id: \.test) { h in
                        LabeledContent(h.test.time.formatted(date: .abbreviated, time: .omitted),
                                       value: String(format: "%.1f gph (cyl %ld rich, %ld lean)", h.test.spread, h.test.richest, h.test.leanest))
                    }
                }
            }
        }
        .navigationTitle("Lean Test")
    }
}

// MARK: - Turbo and induction

struct TurboChecksView: View {
    @EnvironmentObject private var logStore: FlightLogStore

    private struct TakeoffPoint: Identifiable {
        let time: Date
        let ff: Double
        var id: Double { time.timeIntervalSince1970 }
    }

    var body: some View {
        let all = Array(logStore.summaries.values)
        let backtest = TurboCheck.backtest(all)
        let cards = backtest.compactMap { b in b.summary.engineChecks?.card.map { (b.summary, $0) } }
        let recent = backtest.suffix(20).filter { !$0.findings.isEmpty }.reversed()
        List {
            Section {
                if recent.isEmpty {
                    Label("Takeoff power, full-throttle MAP and low-power EGTs within this aircraft's normal on the last 20 flights.", systemImage: "checkmark.circle")
                }
                ForEach(Array(recent), id: \.summary.filename) { b in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.summary.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                        ForEach(b.findings) { f in Text(f.text).font(.caption).foregroundStyle(.orange) }
                    }
                }
            } header: {
                Text("Findings (Last 20 Flights)")
            } footer: {
                Text("Each flight against the 40 before it (median ± 3 robust sigma, with a minimum margin). An induction finding becomes an issue only when the same cylinder shows it on consecutive flights.")
            }

            Section {
                let pts = cards.compactMap { s, c in c.takeoffFF.map { TakeoffPoint(time: s.start, ff: $0) } }
                if pts.count >= 2 {
                    Chart(pts) { p in
                        PointMark(x: .value("Date", p.time), y: .value("gph", p.ff)).symbolSize(16)
                    }
                    .chartYAxisLabel("Takeoff fuel flow, gph")
                    .frame(height: 160)
                }
                if let c = cards.last(where: { $0.1.takeoffFF != nil })?.1 {
                    LabeledContent("Latest takeoff", value: String(format: "%.0f RPM · %.1f inHg · %.1f gph", c.takeoffRPM ?? 0, c.takeoffMAP ?? 0, c.takeoffFF ?? 0))
                }
                let rpm = cards.compactMap { $0.1.takeoffRPM }, map = cards.compactMap { $0.1.takeoffMAP }, ff = cards.compactMap { $0.1.takeoffFF }
                if !rpm.isEmpty {
                    LabeledContent("Normal", value: String(format: "%.0f RPM · %.1f inHg · %.1f gph", EngineChecks.median(rpm) ?? 0,
                                                                 EngineChecks.median(map) ?? 0, EngineChecks.median(ff) ?? 0))
                }
            } header: {
                Text("Takeoff Power")
            } footer: {
                Text("Full power from 20 s before lift-off to 60 s after. \(POHRef.page("4-16")): about 2,700 RPM. Low fuel flow means less cooling fuel; low MAP points at the turbonormalizer or a leak.")
            }

            Section {
                let table = TurboCheck.deckTable(all)
                if table.isEmpty { Text("Not enough climbs yet.").foregroundStyle(.secondary) }
                ForEach(table, id: \.band) { row in
                    LabeledContent("\(row.band / 1000)-\(row.band / 1000 + 2)k ft") {
                        Text(String(format: "%.1f inHg normal", row.normal) + (row.latest.map { String(format: " · latest %.1f", $0) } ?? ""))
                            .monospacedDigit()
                            .foregroundStyle((row.latest ?? row.normal) < row.normal - TurboCheck.deckFloor ? Color.orange : Color.secondary)
                    }
                }
            } header: {
                Text("Full-Throttle MAP By Altitude")
            } footer: {
                Text("Highest manifold pressure in climb per 2,000 ft band. A turbonormalized engine holds sea-level MAP to its critical altitude; sagging earlier than normal points at the wastegate, controller or a leak.")
            }

            Section {
                let shifts = cards.compactMap { $0.1.inductionShift }
                let latest = cards.last(where: { $0.1.inductionShift != nil })?.1.inductionShift
                if shifts.count < TurboCheck.historyMin {
                    Text("Needs \(TurboCheck.historyMin) flights with steady cruise and a descent (\(shifts.count) so far).").foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text("Cyl").bold()
                            ForEach(1...6, id: \.self) { Text("\($0)").bold() }
                        }
                        GridRow {
                            Text("Normal").bold()
                            ForEach(0..<6, id: \.self) { c in Text(String(format: "%+.0f", EngineChecks.median(shifts.map { $0[c] }) ?? 0)).monospacedDigit() }
                        }
                        if let latest {
                            GridRow {
                                Text("Latest").bold()
                                ForEach(0..<6, id: \.self) { c in Text(String(format: "%+.0f", latest[c])).monospacedDigit() }
                            }
                        }
                    }
                    .font(.callout)
                    ForEach(TurboCheck.persistentInduction(all), id: \.cylinder) { p in
                        Text(String(format: "Cylinder %ld runs %.0f °F hotter (vs the others) at low MAP than in cruise on most flights (others %+.0f): a long-standing pattern. Have the intake couplers and gaskets at cylinder %ld checked at the next annual.",
                                    p.cylinder, p.shift, p.others, p.cylinder))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Induction Leak Check (°F)")
            } footer: {
                Text("Each cylinder's EGT vs the others at low manifold pressure (under 20 inHg, airborne) minus the same in steady cruise. An induction leak between the throttle and a cylinder leans it most at low MAP, so its number rises.")
            }
        }
        .navigationTitle("Turbo & Induction")
    }
}

// MARK: - A&P pre-shop report

struct PreShopReportView: View {
    @EnvironmentObject private var logStore: FlightLogStore
    @EnvironmentObject private var issues: IssueStore
    @State private var fileURL: URL?

    var body: some View {
        let text = PreShopReport.text(summaries: Array(logStore.summaries.values), openIssues: issues.groups)
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("A&P Pre-Shop Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let fileURL {
                    ShareLink(item: fileURL) { Label("Share PDF", systemImage: "doc.richtext") }
                }
                ShareLink(item: text, subject: Text("Pre-shop engine report"), preview: SharePreview("Pre-shop engine report")) {
                    Label("Share Text", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: text) {
            if let data = PreShopPDF.render(text) {
                fileURL = KneeboardPDF.file(data, name: "Pre-shop engine report.pdf")
            }
        }
    }
}

/// Letter-size PDF of the pre-shop report (same print path as the kneeboard cards).
enum PreShopPDF {
    static let pageSize = CGSize(width: 612, height: 792)

    @MainActor
    static func render(_ text: String) -> Data? {
        let page = CGRect(origin: .zero, size: pageSize)
        let renderer = UIPrintPageRenderer()
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page, forKey: "printableRect")
        let formatter = UIMarkupTextPrintFormatter(markupText: html(text))
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 40, bottom: 36, right: 40)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, [kCGPDFContextTitle as String: "Pre-shop engine report",
                                                     kCGPDFContextAuthor as String: "Engine Pulse"])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data.length > 0 ? data as Data : nil
    }

    /// Headings (all-caps lines) bold, "- " lines as bullets, numbered lines kept; 9 pt so it fits one page.
    static func html(_ text: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var body = ""
        var inList = false
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let isItem = line.hasPrefix("- ")
            if inList && !isItem { body += "</ul>"; inList = false }
            if line.isEmpty { continue }
            if i == 0 {
                body += "<h1>\(esc(line))</h1>"
            } else if isItem {
                if !inList { body += "<ul>"; inList = true }
                body += "<li>\(esc(String(line.dropFirst(2))))</li>"
            } else if line == line.uppercased() && line.count < 60 && line.contains(where: { $0.isLetter }) {
                body += "<h2>\(esc(line))</h2>"
            } else {
                body += "<p>\(esc(line))</p>"
            }
        }
        if inList { body += "</ul>" }
        return """
        <html><head><style>
        body { font-family: -apple-system, Helvetica; font-size: 9pt; line-height: 1.25; }
        h1 { font-size: 13pt; margin: 0 0 4pt 0; } h2 { font-size: 10pt; margin: 8pt 0 2pt 0; border-bottom: 0.5pt solid #999; }
        ul { margin: 0 0 0 12pt; padding: 0; } li { margin: 0 0 1pt 0; } p { margin: 0 0 3pt 0; }
        </style></head><body>\(body)</body></html>
        """
    }
}

// MARK: - Diagnostics rows

/// DIAGNOSTICS > Engine Analysis rows for the v0.9.7 checks.
struct EngineChecksRows: View {
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        let all = Array(logStore.summaries.values)
        let runups = MagCheck.history(all)
        let lastRunup = runups.first?.runup
        NavigationLink {
            ReportCardView()
        } label: {
            LabeledContent {
                Text(ReportCard.flights(all).last.map { $0.start.formatted(date: .abbreviated, time: .omitted) } ?? "No flights").foregroundStyle(.secondary)
            } label: {
                Label("Report Card", systemImage: "list.number")
            }
        }
        NavigationLink {
            MagCheckHistoryView()
        } label: {
            LabeledContent {
                if let u = lastRunup {
                    Text(u.mags.map { "\($0.mag) \(Int($0.drop))" }.joined(separator: " · "))
                        .foregroundStyle(u.findings.contains { MagCheck.severity($0) != .info } ? Color.orange : Color.secondary)
                } else {
                    Text("None found").foregroundStyle(.secondary)
                }
            } label: {
                Label("Run-Up Mag Check", systemImage: "bolt.horizontal")
            }
        }
        NavigationLink {
            GAMIView()
        } label: {
            LabeledContent {
                if let t = GAMICheck.history(all).first?.test {
                    Text(String(format: "%.1f gph", t.spread)).foregroundStyle(t.spread >= GAMICheck.poorSpread ? Color.orange : Color.secondary)
                } else {
                    Text("Fly the test").foregroundStyle(.secondary)
                }
            } label: {
                Label("Lean Test", systemImage: "drop.halffull")
            }
        }
        NavigationLink {
            TurboChecksView()
        } label: {
            let n = TurboCheck.backtest(all).suffix(10).filter { !$0.findings.isEmpty }.count
            LabeledContent {
                Text(n == 0 ? "Normal" : "\(n) of last 10 flights").foregroundStyle(n == 0 ? Color.secondary : Color.orange)
            } label: {
                Label("Turbo & Induction", systemImage: "fanblades")
            }
        }
        NavigationLink {
            PreShopReportView()
        } label: {
            Label("A&P Pre-Shop Report", systemImage: "wrench.and.screwdriver")
        }
    }
}
