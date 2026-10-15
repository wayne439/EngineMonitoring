import SwiftUI
import Charts

/// One-line early-warning status (DIAGNOSTICS > Engine Analysis).
struct EarlyWarningRow: View {
    let report: EarlyWarningReport

    var body: some View {
        LabeledContent {
            if let level = report.level {
                Text("\(level.rawValue) · \(report.patterns.count)").foregroundStyle(level == .actSoon ? Color.red : Color.orange)
            } else if report.analyses.isEmpty {
                Text("Needs \(EarlyWarning.baselineMin + EarlyWarning.recent) flights").foregroundStyle(.secondary)
            } else {
                Text("Nothing drifting").foregroundStyle(.secondary)
            }
        } label: {
            Label("Early Warning & Trends", systemImage: "chart.line.uptrend.xyaxis")
        }
    }
}

/// Early warning across flights, with a trend chart for every value it follows.
struct EarlyWarningView: View {
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        let report = EarlyWarning.analyze(Array(logStore.summaries.values))
        List {
            Section {
                if report.analyses.isEmpty {
                    Text("Needs at least \(EarlyWarning.baselineMin + EarlyWarning.recent) flights with 5 minutes of steady cruise (\(report.flightsUsed) so far).")
                        .foregroundStyle(.secondary)
                } else if report.patterns.isEmpty {
                    Label("Nothing drifting: every value below is within this aircraft's normal and not trending the wrong way.", systemImage: "checkmark.circle")
                }
                ForEach(report.patterns) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(p.level.rawValue): \(p.title)" + (p.cylinder.map { " - cylinder \($0)" } ?? ""))
                            .font(.headline).foregroundStyle(p.level == .actSoon ? Color.red : Color.orange)
                        Text(p.advice).font(.callout)
                        ForEach(p.metrics, id: \.self) { id in
                            if let a = report.analysis(id) {
                                Text("\(a.metric.label): " + EarlyWarning.describe(a)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Early Warning")
            } footer: {
                Text("\(report.flightsUsed) flights with steady cruise, " + String(format: "%.0f", report.hoursCovered)
                     + " flight hours. Compares the newest 5 flights with the 40 before them, corrected for outside air temperature and fuel flow. Advisory: look closer and ask your A&P; the POH governs.")
            }

            if !report.analyses.isEmpty {
                Section {
                    CylinderOverviewChart(report: report, prefix: "cht", threshold: 400, unit: "°F")
                } header: {
                    Text("All Cylinders - CHT In Cruise")
                } footer: {
                    Text("Each flight, corrected to this aircraft's typical outside air temperature and fuel flow. Dashed line: 400 °F.")
                }
                Section {
                    CylinderOverviewChart(report: report, prefix: "cycle", threshold: ValveWatch.minPeakToPeak, unit: "°F")
                } header: {
                    Text("All Cylinders - Valve-Watch Cycle")
                } footer: {
                    Text("Largest single-cylinder EGT cycle per flight. Dashed line: the 30 °F valve-watch threshold.")
                }
            }

            ForEach(TrendMetric.Group.allCases, id: \.self) { group in
                let items = report.analyses.filter { $0.metric.group == group }
                if !items.isEmpty {
                    Section(group.rawValue) {
                        ForEach(items) { a in
                            NavigationLink {
                                TrendDetailView(metricID: a.metric.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(a.metric.label).font(.subheadline)
                                        Spacer()
                                        if let l = a.level {
                                            Text(l.rawValue).font(.caption.bold()).foregroundStyle(l == .actSoon ? Color.red : Color.orange)
                                        } else {
                                            Text(a.metric.format(a.recentValue)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    TrendChart(analysis: a, compact: true)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Early Warning & Trends")
    }
}

/// One metric across flights, full size, with what the early warning concluded.
struct TrendDetailView: View {
    let metricID: String
    @EnvironmentObject private var logStore: FlightLogStore

    var body: some View {
        let report = EarlyWarning.analyze(Array(logStore.summaries.values))
        List {
            if let a = report.analysis(metricID) {
                Section {
                    TrendChart(analysis: a, compact: false)
                } footer: {
                    Text("Dots: each flight\(a.metric.corrected ? ", corrected to typical outside air temperature and fuel flow" : ""). Green band: this aircraft's normal (from the \(a.baselineFlights) flights before the newest 5). Line: trend over the newest 10 flights; dashed: where it leads at this rate.")
                }
                Section("Reading") {
                    LabeledContent("Newest 5 flights", value: a.metric.format(a.recentValue))
                    LabeledContent("Compared with normal", value: String(format: "%+.1f sigma", a.shiftSigma))
                    LabeledContent("Trend", value: String(format: "%+.\(a.metric.digits + 1)f %@ per flight hour", a.slopePerHour, a.metric.unit))
                    if let t = a.metric.threshold {
                        LabeledContent("Threshold", value: a.metric.format(t))
                        if let s = a.metric.thresholdSource { Text(s).font(.caption).foregroundStyle(.secondary) }
                    }
                    if let h = a.hoursToThreshold {
                        LabeledContent("At this rate", value: String(format: "about %.0f flight hours to the threshold", h))
                    }
                    if let l = a.level {
                        Text("\(l.rawValue): " + EarlyWarning.describe(a)).foregroundStyle(l == .actSoon ? Color.red : Color.orange)
                    } else {
                        Label("Within normal and not trending the wrong way.", systemImage: "checkmark.circle")
                    }
                }
                Section("Flights (Newest First)") {
                    ForEach(a.points.reversed()) { p in
                        LabeledContent(p.date.formatted(date: .abbreviated, time: .shortened), value: a.metric.format(p.value))
                    }
                }
            } else {
                Text("Not enough flights with steady cruise for this value yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(TrendMetric.named(metricID)?.label ?? "Trend")
    }
}

/// Flights (x = flight hours), N63KA's normal band, the trend line and its projection, and the threshold.
struct TrendChart: View {
    let analysis: TrendAnalysis
    let compact: Bool

    var body: some View {
        let a = analysis
        let line = a.trendLine
        let lo = Swift.min(a.points.map(\.adjusted).min() ?? a.normalLow, a.normalLow, line.map(\.value).min() ?? a.normalLow)
        let hi = Swift.max(a.points.map(\.adjusted).max() ?? a.normalHigh, a.normalHigh, line.map(\.value).max() ?? a.normalHigh,
                           a.level != nil ? (a.metric.threshold ?? -Double.infinity) : -Double.infinity)
        let pad = Swift.max((hi - lo) * 0.1, a.metric.minimumSigma)
        let flagged = a.level != nil
        Chart {
            RectangleMark(yStart: .value("Low", a.normalLow), yEnd: .value("High", a.normalHigh))
                .foregroundStyle(Color.green.opacity(0.15))
            ForEach(a.points) { p in
                PointMark(x: .value("Flight hours", p.hours), y: .value(a.metric.unit, p.adjusted))
                    .symbolSize(compact ? 12 : 24)
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
            ForEach(Array(line.enumerated()), id: \.offset) { _, t in
                LineMark(x: .value("Flight hours", t.hours), y: .value(a.metric.unit, t.value), series: .value("Line", "trend"))
                    .foregroundStyle(flagged ? (a.level == .actSoon ? Color.red : Color.orange) : Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: t.projected ? [5, 4] : []))
            }
            if flagged, let t = a.metric.threshold {
                RuleMark(y: .value("Threshold", t))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Threshold " + a.metric.format(t)).font(.caption2).foregroundStyle(.red)
                    }
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(compact ? .hidden : .automatic)
        .chartXAxisLabel(compact ? "" : "Flight hours in the logs")
        .frame(height: compact ? 70 : 240)
    }
}

/// Six cylinders on one chart (adjusted values per flight).
struct CylinderOverviewChart: View {
    let report: EarlyWarningReport
    let prefix: String
    let threshold: Double
    let unit: String

    private struct Pt: Identifiable {
        let cylinder: String
        let hours: Double
        let value: Double
        var id: String { "\(cylinder)-\(hours)" }
    }

    var body: some View {
        let pts: [Pt] = (1...6).flatMap { c in
            (report.analysis("\(prefix)\(c)")?.points ?? []).map { Pt(cylinder: "Cyl \(c)", hours: $0.hours, value: $0.adjusted) }
        }
        let top = Swift.max(pts.map(\.value).max() ?? threshold, threshold)
        let bottom = pts.map(\.value).min() ?? 0
        Chart {
            ForEach(pts) { p in
                LineMark(x: .value("Flight hours", p.hours), y: .value(unit, p.value), series: .value("Cylinder", p.cylinder))
                    .foregroundStyle(by: .value("Cylinder", p.cylinder))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Threshold", threshold))
                .foregroundStyle(Color.red.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: (Swift.min(bottom, threshold) - 5)...(top + 5))
        .chartXAxisLabel("Flight hours in the logs")
        .frame(height: 220)
    }
}

/// All six EGTs and CHTs through one flight (post-flight report).
struct FlightCylinderCharts: View {
    let series: CylinderSeries

    private struct Pt: Identifiable {
        let cylinder: String
        let time: Date
        let value: Double
        var id: String { "\(cylinder)-\(time.timeIntervalSince1970)" }
    }

    private func points(_ values: [[Double?]]) -> [Pt] {
        var out: [Pt] = []
        for (i, t) in series.times.enumerated() {
            for c in 0..<6 where i < values[c].count {
                if let v = values[c][i] { out.append(Pt(cylinder: "Cyl \(c + 1)", time: t, value: v)) }
            }
        }
        return out
    }

    var body: some View {
        Section {
            chart(points(series.egt), unit: "EGT °F")
            chart(points(series.cht), unit: "CHT °F")
        } header: {
            Text("Cylinders Through The Flight")
        } footer: {
            Text("Every cylinder's EGT (top) and CHT (bottom), sampled every \(Int(series.step)) s. One line moving away from the others is what the probe check, valve watch and early warning look for.")
        }
    }

    private func chart(_ pts: [Pt], unit: String) -> some View {
        Chart(pts) { p in
            LineMark(x: .value("Time", p.time), y: .value(unit, p.value), series: .value("Cylinder", p.cylinder))
                .foregroundStyle(by: .value("Cylinder", p.cylinder))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYAxisLabel(unit)
        .frame(height: 200)
    }
}
