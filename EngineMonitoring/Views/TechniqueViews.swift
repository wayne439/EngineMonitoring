import SwiftUI
import Charts

/// Every takeoff and landing from the bundled history and imported logs, newest first,
/// with the landing airport filled in from the next log's departure when the log itself does not say.
struct TechniqueIndex {
    struct Landing: Identifiable { let record: LandingRecord; let airport: String?; var id: String { record.id } }
    let landings: [Landing]
    let takeoffs: [TakeoffRecord]

    init(_ summaries: [FlightSummary]) {
        let ordered = summaries.sorted { $0.start < $1.start }
        var ls: [Landing] = []
        for (i, s) in ordered.enumerated() {
            for l in s.landings {
                var airport = l.airport
                if airport == nil {
                    // The next log that starts within 24 h departs from where this flight landed.
                    airport = ordered[(i + 1)...].first { $0.start > l.touchdown && $0.start.timeIntervalSince(l.touchdown) < 86_400 && $0.departure != nil }?.departure
                }
                ls.append(Landing(record: l, airport: airport))
            }
        }
        landings = ls.sorted { $0.record.touchdown > $1.record.touchdown }
        takeoffs = ordered.flatMap(\.takeoffs).sorted { $0.time > $1.time }
    }

    static func rate(_ values: [Bool?]) -> (passed: Int, of: Int) {
        let v = values.compactMap { $0 }
        return (v.filter { $0 }.count, v.count)
    }
}

/// MY FLYING: quality of takeoffs and landings with charts and tables.
private struct DatedPoint: Identifiable {
    let date: Date
    let value: Double
    let ok: Bool
    var id: Date { date }
}

private struct Gate: Identifiable {
    let name: String
    let t: Int
    var id: String { name }
}

struct MyFlyingView: View {
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var list: ListKind = .landings

    enum ListKind: String, CaseIterable, Identifiable {
        case landings = "Landings"
        case takeoffs = "Takeoffs"
        var id: String { rawValue }
    }

    var body: some View {
        let index = TechniqueIndex(Array(logStore.summaries.values))
        List {
            if index.landings.isEmpty && index.takeoffs.isEmpty {
                MyFlyingEmptySection(flights: logStore.entries.count)
            }
            summarySection(index)
            landingCharts(index)
            takeoffChart(index)
            Section {
                Picker("Show", selection: $list) {
                    ForEach(ListKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch list {
                case .landings:
                    ForEach(index.landings) { l in
                        NavigationLink { LandingDetailView(landing: l.record, airport: l.airport) } label: { LandingRow(landing: l.record, airport: l.airport) }
                    }
                case .takeoffs:
                    ForEach(index.takeoffs) { t in
                        NavigationLink { TakeoffDetailView(takeoff: t) } label: { TakeoffRow(takeoff: t) }
                    }
                }
            } header: {
                Text("Every \(list == .landings ? "Landing" : "Takeoff") (\(list == .landings ? index.landings.count : index.takeoffs.count))")
            } footer: {
                Text(TechniqueStandards.source + " From the engine data card at 1 sample per second with baro altitude: values are approximate. A coaching aid, not a grade.")
            }
        }
        .navigationTitle("MY FLYING")
    }

    @ViewBuilder
    private func summarySection(_ index: TechniqueIndex) -> some View {
        let recent = Array(index.landings.prefix(10)).map(\.record)
        let all = index.landings.map(\.record)
        Section {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Last 10").font(.caption.bold())
                    Text("All (\(all.count))").font(.caption.bold())
                }
                Divider()
                rateRow("On speed at 50 ft", recent.map(\.onSpeedAt50), all.map(\.onSpeedAt50))
                rateRow("Stable at 300 ft", recent.map(\.stableAt300), all.map(\.stableAt300))
                rateRow("Speed and sink at 500 ft", recent.map(\.stableAt500), all.map(\.stableAt500))
                rateRow("No long float", recent.map(\.noLongFloat), all.map(\.noLongFloat))
                Divider()
                let rt = Array(index.takeoffs.prefix(10)), at = index.takeoffs
                rateRow("Takeoff: full power", rt.map(\.fullPower), at.map(\.fullPower))
                rateRow("Takeoff: climb speed", rt.map(\.climbOnSpeed), at.map(\.climbOnSpeed))
            }
        } header: {
            Text("Takeoff And Landing Quality")
        }
    }

    private func rateRow(_ name: String, _ recent: [Bool?], _ all: [Bool?]) -> some View {
        let r = TechniqueIndex.rate(recent), a = TechniqueIndex.rate(all)
        func cell(_ x: (passed: Int, of: Int)) -> some View {
            let pct = x.of == 0 ? 0 : Double(x.passed) / Double(x.of)
            return Text(x.of == 0 ? "-" : "\(x.passed)/\(x.of)")
                .monospacedDigit().bold()
                .foregroundStyle(x.of == 0 ? Color.secondary : (pct >= 0.8 ? Color.green : (pct >= 0.6 ? Color.orange : Color.red)))
        }
        return GridRow {
            Text(name)
            cell(r)
            cell(a)
        }
    }

    @ViewBuilder
    private func landingCharts(_ index: TechniqueIndex) -> some View {
        let pts = index.landings.compactMap { l in l.record.ias50.map { DatedPoint(date: l.record.touchdown, value: $0, ok: l.record.onSpeedAt50 ?? false) } }
        if pts.count >= 2 {
            Section {
                Chart {
                    if TechniqueStandards.hasSpeeds {
                        RectangleMark(yStart: .value("Low", TechniqueStandards.finalFlaps100.lowerBound),
                                      yEnd: .value("High", TechniqueStandards.finalFlaps100.upperBound))
                            .foregroundStyle(Color.green.opacity(0.15))
                        RuleMark(y: .value("Vref", TechniqueStandards.vref))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .bottom, alignment: .leading) { Text("Vref \(Int(TechniqueStandards.vref))").font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(pts) { p in
                        PointMark(x: .value("Date", p.date), y: .value("KIAS", p.value))
                            .foregroundStyle(p.ok ? Color.green : Color.orange)
                            .symbolSize(30)
                    }
                }
                .chartYScale(domain: max(30, (pts.map(\.value).min() ?? 65) - 10)...((pts.map(\.value).max() ?? 105) + 10))
                .frame(height: 190)
            } header: {
                Text("Speed Over The Fence (50 ft)")
            } footer: {
                Text(TechniqueStandards.hasSpeeds
                     ? "Green band: POH final approach \(TechniqueStandards.kt(TechniqueStandards.finalFlaps100)). Orange: outside \(TechniqueStandards.kt(TechniqueStandards.onSpeedAt50))."
                     : "Enter your approach speeds in AIRCRAFT > Technique speeds to grade these.")
            }
        }
        let months = monthly(index.landings.map(\.record))
        if months.count >= 2 {
            Section {
                Chart(months, id: \.month) { m in
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Stable %", m.percent))
                        .foregroundStyle(m.percent >= 80 ? Color.green : (m.percent >= 60 ? Color.orange : Color.red))
                        .annotation(position: .top) { Text("\(m.stable)/\(m.count)").font(.caption2) }
                }
                .chartYScale(domain: 0...110)
                .chartYAxis { AxisMarks(values: [0, 50, 80, 100]) }
                .frame(height: 180)
            } header: {
                Text("Stable At 300 ft, By Month")
            } footer: {
                Text("Stable = 75-95 KIAS, sink 1,000 fpm or less, bank 15° or less at 300 ft above the field.")
            }
        }
    }

    private struct Month { let month: Date; let stable: Int; let count: Int; var percent: Double { count == 0 ? 0 : 100 * Double(stable) / Double(count) } }

    private func monthly(_ landings: [LandingRecord]) -> [Month] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: landings.filter { $0.stableAt300 != nil }) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.touchdown)) ?? $0.touchdown
        }
        return groups.map { Month(month: $0.key, stable: $0.value.filter { $0.stableAt300 == true }.count, count: $0.value.count) }
            .sorted { $0.month < $1.month }
    }

    @ViewBuilder
    private func takeoffChart(_ index: TechniqueIndex) -> some View {
        let pts = index.takeoffs.compactMap { t in t.climbIAS.map { DatedPoint(date: t.time, value: $0, ok: t.climbOnSpeed ?? false) } }
        if pts.count >= 2 {
            Section {
                Chart {
                    if TechniqueStandards.hasSpeeds {
                        RectangleMark(yStart: .value("Low", TechniqueStandards.climbNormal.lowerBound),
                                      yEnd: .value("High", TechniqueStandards.climbNormal.upperBound))
                            .foregroundStyle(Color.green.opacity(0.15))
                        RuleMark(y: .value("Vy", TechniqueStandards.vy))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .bottom, alignment: .leading) { Text("Vy \(Int(TechniqueStandards.vy))").font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(pts) { p in
                        PointMark(x: .value("Date", p.date), y: .value("KIAS", p.value))
                            .foregroundStyle(p.ok ? Color.green : Color.orange)
                            .symbolSize(30)
                    }
                }
                .chartYScale(domain: 80...135)
                .frame(height: 170)
            } header: {
                Text("Initial Climb Speed (100-1,000 ft)")
            } footer: {
                Text(TechniqueStandards.hasSpeeds
                     ? "Green band: POH normal climb \(TechniqueStandards.kt(TechniqueStandards.climbNormal)). Vy \(Int(TechniqueStandards.vy)) KIAS at sea level."
                     : "Enter your climb speeds in AIRCRAFT > Technique speeds to grade these.")
            }
        }
    }
}

struct LandingRow: View {
    let landing: LandingRecord
    let airport: String?

    var body: some View {
        let s = landing.score
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(landing.touchdown.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                if let airport { Text(airport).font(.subheadline.bold()).foregroundStyle(.secondary) }
                Spacer()
                ScoreBadge(passed: s.passed, of: s.of)
            }
            HStack(spacing: 6) {
                CheckChip(label: "500", pass: landing.stableAt500)
                CheckChip(label: "300", pass: landing.stableAt300)
                CheckChip(label: landing.ias50.map { String(format: "%.0f kt", $0) } ?? "50 ft", pass: landing.onSpeedAt50)
                CheckChip(label: "Flare", pass: landing.noLongFloat)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TakeoffRow: View {
    let takeoff: TakeoffRecord

    var body: some View {
        let s = takeoff.score
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(takeoff.time.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                if let a = takeoff.airport { Text(a).font(.subheadline.bold()).foregroundStyle(.secondary) }
                Spacer()
                ScoreBadge(passed: s.passed, of: s.of)
            }
            HStack(spacing: 6) {
                CheckChip(label: takeoff.maxRPM.map { String(format: "%.0f RPM", $0) } ?? "Power", pass: takeoff.fullPower)
                CheckChip(label: takeoff.climbIAS.map { String(format: "Climb %.0f kt", $0) } ?? "Climb", pass: takeoff.climbOnSpeed)
                if let t = takeoff.secondsTo1000 { CheckChip(label: "1,000 ft in \(t) s", pass: nil) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ScoreBadge: View {
    let passed: Int
    let of: Int
    var body: some View {
        Text(of == 0 ? "-" : "\(passed)/\(of)")
            .font(.caption.bold()).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((of > 0 && passed == of ? Color.green : (passed + 1 >= of ? Color.orange : Color.red)).opacity(0.2), in: Capsule())
    }
}

struct CheckChip: View {
    let label: String
    let pass: Bool?
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: pass == nil ? "info.circle" : (pass! ? "checkmark.circle.fill" : "xmark.circle.fill"))
            Text(label)
        }
        .font(.caption2)
        .foregroundStyle(pass == nil ? Color.secondary : (pass! ? Color.green : Color.orange))
    }
}

/// Checks table for one takeoff or landing.
struct TechniqueChecksTable: View {
    let checks: [TechniqueCheck]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(checks) { c in
                GridRow(alignment: .top) {
                    Image(systemName: c.pass == nil ? "info.circle" : (c.pass! ? "checkmark.circle.fill" : "xmark.circle.fill"))
                        .foregroundStyle(c.pass == nil ? Color.secondary : (c.pass! ? Color.green : Color.orange))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.subheadline.bold())
                        Text(c.target).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(c.value).font(.subheadline).monospacedDigit().gridColumnAlignment(.trailing)
                }
            }
        }
    }
}

struct LandingDetailView: View {
    let landing: LandingRecord
    let airport: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Touchdown", value: landing.touchdown.formatted(date: .abbreviated, time: .standard))
                if let airport { LabeledContent("Airport", value: airport) }
                LabeledContent("Field elevation (baro)", value: String(format: "%.0f ft", landing.fieldElevation))
                if let o = landing.oat { LabeledContent("OAT", value: String(format: "%.0f °C", o)) }
                LabeledContent("Log", value: landing.log)
            }
            Section {
                TechniqueChecksTable(checks: landing.checks)
            } header: {
                Text("Checks (\(landing.score.passed)/\(landing.score.of))")
            } footer: {
                Text(TechniqueStandards.source)
            }
            if landing.profile.count >= 5 {
                Section("Height Above The Field") {
                    profileChart(\.agl, label: "ft") {
                        RuleMark(y: .value("50 ft", 50.0)).foregroundStyle(.secondary.opacity(0.5))
                        RuleMark(y: .value("300 ft", 300.0)).foregroundStyle(.secondary.opacity(0.5))
                        RuleMark(y: .value("500 ft", 500.0)).foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                Section {
                    profileChart(\.ias, label: "KIAS", domain: max(30.0, TechniqueStandards.vref - 30)...(TechniqueStandards.finalFlaps100.upperBound + 40)) {
                        if TechniqueStandards.hasSpeeds {
                            RectangleMark(yStart: .value("Low", TechniqueStandards.finalFlaps100.lowerBound),
                                          yEnd: .value("High", TechniqueStandards.finalFlaps100.upperBound))
                                .foregroundStyle(Color.green.opacity(0.15))
                            RuleMark(y: .value("Vref", TechniqueStandards.vref)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                } header: {
                    Text("Airspeed")
                } footer: {
                    Text(TechniqueStandards.hasSpeeds
                         ? "Green band \(TechniqueStandards.kt(TechniqueStandards.finalFlaps100)) (POH final approach); dashed line Vref \(Int(TechniqueStandards.vref))."
                         : "Enter your approach speeds in AIRCRAFT > Technique speeds to see the target band.")
                }
                Section {
                    profileChart(\.vs, label: "fpm") {
                        RuleMark(y: .value("-1000", -1000.0)).foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                } header: {
                    Text("Vertical Speed")
                } footer: {
                    Text("Dashed line: 1,000 fpm sink. Baro vertical speed lags in the flare.")
                }
                Section("Bank") {
                    profileChart(\.roll, label: "°", domain: -40.0...40.0) {
                        RuleMark(y: .value("15", 15.0)).foregroundStyle(.secondary.opacity(0.5))
                        RuleMark(y: .value("-15", -15.0)).foregroundStyle(.secondary.opacity(0.5))
                    }
                }
            }
        }
        .navigationTitle("Landing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: shareText, subject: Text("Landing")) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }

    private var gateTimes: [Gate] {
        [("500", 500), ("300", 300), ("50", 50)].compactMap { name, ft in
            landing.profile.last(where: { $0.t < 0 && $0.agl >= ft }).map { Gate(name: name, t: $0.t) }
        }
    }

    @ViewBuilder
    private func profileChart<C: ChartContent>(_ key: KeyPath<ProfilePoint, Int>, label: String, domain: ClosedRange<Double>? = nil,
                                              @ChartContentBuilder extra: () -> C) -> some View {
        let chart = Chart {
            extra()
            ForEach(gateTimes) { g in
                RuleMark(x: .value("Gate", Double(g.t)))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(position: .top) { Text("\(g.name) ft").font(.caption2).foregroundStyle(.secondary) }
            }
            RuleMark(x: .value("Touchdown", 0.0)).foregroundStyle(Color.blue.opacity(0.4))
            ForEach(landing.profile, id: \.t) { p in
                LineMark(x: .value("Seconds", Double(p.t)), y: .value("Value", Double(p[keyPath: key])))
            }
        }
        .chartXAxisLabel("seconds to touchdown")
        .chartYAxisLabel(label)
        .frame(height: 150)
        if let domain { chart.chartYScale(domain: domain) } else { chart }
    }

    private var shareText: String {
        var s = "Landing \(landing.touchdown.formatted(date: .abbreviated, time: .shortened))"
        if let airport { s += " \(airport)" }
        s += " - \(landing.score.passed)/\(landing.score.of) checks\n"
        for c in landing.checks { s += "\(c.pass == nil ? "-" : (c.pass! ? "OK" : "X")) \(c.name): \(c.value) (target \(c.target))\n" }
        return s
    }
}


struct TakeoffDetailView: View {
    let takeoff: TakeoffRecord

    var body: some View {
        List {
            Section {
                LabeledContent("Airspeed alive", value: takeoff.time.formatted(date: .abbreviated, time: .standard))
                if let a = takeoff.airport { LabeledContent("Airport", value: a) }
                LabeledContent("Field elevation (baro)", value: String(format: "%.0f ft", takeoff.fieldElevation))
                if let o = takeoff.oat { LabeledContent("OAT", value: String(format: "%.0f °C", o)) }
                LabeledContent("Log", value: takeoff.log)
            }
            Section {
                TechniqueChecksTable(checks: takeoff.checks)
            } header: {
                Text("Checks (\(takeoff.score.passed)/\(takeoff.score.of))")
            } footer: {
                Text(TechniqueStandards.source)
            }
            if takeoff.profile.count >= 5 {
                Section {
                    Chart {
                        if TechniqueStandards.hasSpeeds {
                            RuleMark(y: .value("Rotate", TechniqueStandards.rotate)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .bottom, alignment: .leading) { Text("Rotate \(Int(TechniqueStandards.rotate))").font(.caption2) }
                            RectangleMark(yStart: .value("Low", TechniqueStandards.climbNormal.lowerBound),
                                          yEnd: .value("High", TechniqueStandards.climbNormal.upperBound))
                                .foregroundStyle(Color.green.opacity(0.15))
                        }
                        ForEach(takeoff.profile, id: \.t) { p in
                            LineMark(x: .value("Seconds", Double(p.t)), y: .value("KIAS", Double(p.ias)))
                        }
                    }
                    .chartXAxisLabel("seconds from airspeed alive")
                    .frame(height: 170)
                } header: {
                    Text("Airspeed")
                } footer: {
                    Text(TechniqueStandards.hasSpeeds
                         ? "Dashed: rotate \(Int(TechniqueStandards.rotate)) KIAS. Green band: normal climb \(TechniqueStandards.kt(TechniqueStandards.climbNormal)) (POH)."
                         : "Enter your rotate and climb speeds in AIRCRAFT > Technique speeds to see the targets.")
                }
                Section("Height Above The Field") {
                    Chart(takeoff.profile, id: \.t) { p in
                        LineMark(x: .value("Seconds", Double(p.t)), y: .value("ft", Double(p.agl)))
                    }
                    .chartXAxisLabel("seconds from airspeed alive")
                    .frame(height: 150)
                }
            }
        }
        .navigationTitle("Takeoff")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Section for a flight's report or summary: its takeoffs and landings.
struct FlightTechniqueSection: View {
    let summary: FlightSummary

    var body: some View {
        if !summary.takeoffs.isEmpty || !summary.landings.isEmpty {
            Section("Takeoff And Landing") {
                ForEach(summary.takeoffs) { t in
                    NavigationLink { TakeoffDetailView(takeoff: t) } label: { TakeoffRow(takeoff: t) }
                }
                ForEach(summary.landings) { l in
                    NavigationLink { LandingDetailView(landing: l, airport: l.airport) } label: { LandingRow(landing: l, airport: l.airport) }
                }
            }
        }
    }
}

/// Why MY FLYING is empty, and what to do.
private struct MyFlyingEmptySection: View {
    let flights: Int
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var aircraft: AircraftProfileStore

    var body: some View {
        Section {
            if flights == 0 {
                Label("No flights on this device yet.", systemImage: "airplane.departure").font(.headline)
                Text("Import your engine logs in DIAGNOSTICS > Flight Logs, or upload them from a computer at enginepulse.net/upload. Uploads come in when the app opens while you're signed in with the same email.")
                    .font(.subheadline)
                if cloud.isSignedIn {
                    LabeledContent("Signed in as", value: cloud.session?.email ?? "Apple ID (email hidden)")
                    Button("Check for uploaded flights now") {
                        Task {
                            await cloud.restore(aircraft: aircraft, logs: logs)
                            await cloud.pullInbox(logs: logs)
                        }
                    }
                    .disabled(cloud.isBusy)
                    if let status = cloud.status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    if let error = cloud.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
                } else {
                    Text("Sign in (ACCOUNT) with the email you used on the website to bring in your uploads.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } else {
                Label("\(flights) flight\(flights == 1 ? "" : "s"), but no takeoffs or landings found.", systemImage: "info.circle").font(.headline)
                Text("Takeoffs and landings need airspeed and altitude in the log (Garmin glass records both). Engine-only monitors such as JPI and most EI units don't, so this page stays empty for them; engine health, reports and early warning still work.")
                    .font(.subheadline)
            }
        } header: {
            Text("Getting started")
        }
    }
}
