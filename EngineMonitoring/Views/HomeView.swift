import SwiftUI
import Charts

/// HOME: the engine at a glance. A live pulse line and health score, the last flight,
/// cruise trends, what needs attention, setup progress and quick actions.
struct HomeView: View {
    /// Switches the sidebar section (e.g. to DIAGNOSTICS).
    var go: (ContentView.SectionItem) -> Void = { _ in }

    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @EnvironmentObject private var issues: IssueStore
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var poh: POHRepository

    private var flights: [FlightSummary] {
        logs.summaries.values.sorted { $0.start > $1.start }
    }

    private var attention: [IssueGroup] {
        issues.groups.filter(\.needsReview).sorted { $0.severity < $1.severity }
    }

    private struct DueItem: Identifiable {
        let item: MaintenanceItem
        let status: MaintenanceStatus
        var id: String { item.id }
    }

    private var maintenanceDue: [DueItem] {
        let all = Array(logs.summaries.values)
        return maintenance.items.map { DueItem(item: $0, status: maintenance.status($0, summaries: all)) }
            .filter { $0.status.state == .overdue || $0.status.state == .failed || $0.status.state == .dueSoon }
            .sorted { $0.status.state < $1.status.state }
    }

    /// Engine health from the recent flights themselves (not from what is waiting for review).
    @State private var engineHealth = EngineHealth(score: nil, status: .noData, flights: [], deductions: [], slopePerFlight: nil)
    @State private var earlyWarning: EarlyWarningReport?
    @State private var batteryWatch: BatteryWatchReport?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                if logs.entries.isEmpty { GetStartedCard() }
                statTiles
                if let last = flights.first { lastFlightCard(last) }
                if !flights.isEmpty { EarlyWarningCard(report: earlyWarning, flights: flights, attention: attention) }
                if flights.count >= 2 { trendCard }
                if !flights.isEmpty { BatteryStartCard(report: batteryWatch) }
                attentionCard
                setupCard
                quickActions
                Text("Advisory only. Your POH/AFM, your engine monitor and your A&P remain the authority.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .task(id: logs.summaries.count) {
            let all = Array(logs.summaries.values)
            engineHealth = EngineHealth.compute(all)
            earlyWarning = EarlyWarning.analyze(all)
            batteryWatch = BatteryWatch.analyze(all)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.04, green: 0.11, blue: 0.23), Color(red: 0.07, green: 0.19, blue: 0.37)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            PulseLine(color: engineHealth.status.color)
                .frame(height: 90)
                .padding(.top, 120)
                .opacity(0.9)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(aircraft.profile.tailNumber.isEmpty ? "Your aircraft" : aircraft.profile.tailNumber)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text([aircraft.profile.year > 0 ? String(aircraft.profile.year) : "", aircraft.profile.make, aircraft.profile.model, aircraft.profile.engineModel.isEmpty ? "" : "· \(aircraft.profile.engineModel)"]
                        .filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    NavigationLink { HealthBreakdownView(health: engineHealth) } label: {
                        HStack(spacing: 6) {
                            Label(engineHealth.status.label, systemImage: engineHealth.status.icon)
                            if let t = engineHealth.trendText {
                                Text("· " + t).font(.subheadline.weight(.semibold))
                            }
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }
                        .font(.headline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(engineHealth.status.color.opacity(0.22), in: Capsule())
                        .foregroundStyle(engineHealth.status.color)
                    }
                    .buttonStyle(TileButtonStyle())
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                NavigationLink { HealthBreakdownView(health: engineHealth) } label: {
                    VStack(spacing: 6) {
                        ScoreGauge(score: engineHealth.score, color: engineHealth.status.color)
                            .frame(width: 132, height: 132)
                        if let arrow = engineHealth.trendArrow {
                            Label(engineHealth.trendShort ?? "", systemImage: arrow)
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .buttonStyle(TileButtonStyle())
            }
            .padding(24)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        return "\(part) · Engine Pulse"
    }

    // MARK: - Tiles

    private var statTiles: some View {
        let hours = flights.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
        let oil = maintenance.items.first { $0.id == "oil-change" }.map { maintenance.status($0, summaries: Array(logs.summaries.values)) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            Button { go(.diagnostics) } label: {
                StatTile(title: "Flights analyzed", value: "\(flights.count)", icon: "airplane.departure", tint: .cyan)
            }
            .buttonStyle(TileButtonStyle())
            Button { go(.myFlying) } label: {
                StatTile(title: "Engine hours logged", value: String(format: "%.1f", hours), icon: "clock.fill", tint: .indigo)
            }
            .buttonStyle(TileButtonStyle())
            NavigationLink { IssueHistoryView() } label: {
                StatTile(title: "Open items", value: "\(attention.count)", icon: "exclamationmark.triangle.fill",
                         tint: attention.isEmpty ? .green : .orange)
            }
            .buttonStyle(TileButtonStyle())
            Button { go(.maintenance) } label: {
                StatTile(title: "Oil change", value: oil.map { $0.state == .ok ? ($0.summary.isEmpty ? "OK" : $0.summary) : $0.state.label } ?? "Not set",
                         icon: "drop.fill", tint: oil.map { $0.state == .ok ? Color.green : ($0.state == .dueSoon ? .orange : .red) } ?? .secondary)
            }
            .buttonStyle(TileButtonStyle())
        }
    }

    // MARK: - Last flight

    private func lastFlightCard(_ f: FlightSummary) -> some View {
        let minutes = Int(f.end.timeIntervalSince(f.start) / 60)
        let t = f.engineTrend
        let chtMax = t?.cht.compactMap { $0 }.max()
        let flagged = f.issues.filter { $0.severity != .info }
        return Card(title: "Last flight", icon: "airplane") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(f.start.formatted(date: .abbreviated, time: .shortened)).font(.title3.bold())
                    Text("· \(minutes / 60)h \(minutes % 60)m").foregroundStyle(.secondary)
                    Text("· \(f.start.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Reading(label: "Cruise CHT max", value: chtMax.map { "\(Int($0))°F" }, limit: aircraft.profile.limits.chtCaution, raw: chtMax)
                    Reading(label: "Oil temp", value: t?.oilTemp.map { "\(Int($0))°F" }, limit: aircraft.profile.limits.oilTempMax - 20, raw: t?.oilTemp)
                    Reading(label: "Oil pressure", value: t?.oilPressure.map { "\(Int($0)) psi" }, limit: nil, raw: nil)
                    Reading(label: "Fuel flow", value: t?.fuelFlow.map { String(format: "%.1f gph", $0) }, limit: nil, raw: nil)
                }
                HStack {
                    if flagged.isEmpty {
                        Label("No limits or cautions on this flight", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("\(flagged.count) item\(flagged.count == 1 ? "" : "s") flagged on this flight", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    NavigationLink {
                        FlightSummaryView(summary: f)
                    } label: {
                        Text("Open flight").font(.subheadline.bold())
                    }
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Trends

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let series: String
        let value: Double
    }

    private var trendCard: some View {
        let recent = Array(flights.prefix(12).reversed())
        var points: [TrendPoint] = []
        for f in recent {
            guard let t = f.engineTrend else { continue }
            if let c = t.cht.compactMap({ $0 }).max() { points.append(TrendPoint(date: f.start, series: "CHT max", value: c)) }
            if let o = t.oilTemp { points.append(TrendPoint(date: f.start, series: "Oil temp", value: o)) }
        }
        return Card(title: "Cruise trend, last \(recent.count) flights", icon: "chart.xyaxis.line") {
            if points.isEmpty {
                Text("Trends appear after flights with a few minutes of steady cruise.").foregroundStyle(.secondary)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Flight", p.date), y: .value("°F", p.value))
                        .foregroundStyle(by: .value("Series", p.series))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Flight", p.date), y: .value("°F", p.value))
                        .foregroundStyle(by: .value("Series", p.series))
                        .symbolSize(24)
                }
                .chartForegroundStyleScale(["CHT max": Color.orange, "Oil temp": Color.cyan])
                .chartYAxisLabel("°F")
                .frame(height: 180)
                NavigationLink { EarlyWarningView() } label: {
                    HStack {
                        Text("Open engine trends and early warnings").font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                }
            }
        }
    }

    // MARK: - Attention

    private var attentionCard: some View {
        Card(title: "Needs attention", icon: "bell.badge.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if attention.isEmpty && maintenanceDue.isEmpty {
                    Label(flights.isEmpty ? "Nothing yet. Import a flight to start." : "All clear. Nothing waiting for review.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(attention.prefix(4)) { g in
                    NavigationLink {
                        IssueDetailView(kind: g.kind)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(color(for: g.severity)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.latest.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text("\(g.severity.rawValue) · \(g.flightCount) flight\(g.flightCount == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                ForEach(maintenanceDue.prefix(3)) { due in
                    Button { go(.maintenance) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(due.status.state == .dueSoon ? Color.orange : Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(due.item.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text([due.status.state.label, due.status.summary].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                if attention.count > 4 {
                    Button("See all \(attention.count) in DIAGNOSTICS") { go(.diagnostics) }.font(.subheadline)
                }
            }
        }
    }

    private func color(for s: IssueSeverity) -> Color {
        switch s {
        case .warning: .red
        case .caution: .orange
        case .watch: .yellow
        case .info: .secondary
        }
    }

    // MARK: - Setup

    private struct SetupStep {
        let title: String
        let done: Bool
        let section: ContentView.SectionItem
    }

    private var setupSteps: [SetupStep] {
        let oilDone = maintenance.items.first { $0.id == "oil-change" }
            .map { maintenance.status($0, summaries: Array(logs.summaries.values)).state != .neverDone } ?? false
        return [
            SetupStep(title: "Signed in to your account", done: cloud.isSignedIn, section: .account),
            SetupStep(title: "POH uploaded and read", done: poh.index != nil, section: .aircraft),
            SetupStep(title: "Aircraft profile locked", done: aircraft.profile.isLocked, section: .aircraft),
            SetupStep(title: "First flight imported", done: !flights.isEmpty, section: .diagnostics),
            SetupStep(title: "Oil change recorded", done: oilDone, section: .maintenance),
        ]
    }

    @ViewBuilder
    private var setupCard: some View {
        let steps = setupSteps
        let done = steps.filter { $0.done }.count
        if done < steps.count {
            Card(title: "Getting set up · \(done) of \(steps.count)", icon: "list.bullet.clipboard") {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: Double(done), total: Double(steps.count)).tint(.cyan)
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        Button { go(step.section) } label: {
                            HStack {
                                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.done ? Color.green : Color.secondary)
                                Text(step.title).foregroundStyle(step.done ? Color.secondary : Color.primary)
                                    .strikethrough(step.done)
                                Spacer()
                                if !step.done { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                            }
                        }
                        .disabled(step.done)
                    }
                }
            }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
            ActionTile(title: "Import flights", icon: "square.and.arrow.down.fill", tint: .cyan) { go(.diagnostics) }
            NavigationLink { DocumentsView() } label: {
                ActionTileLabel(title: "Upload documents", icon: "tray.and.arrow.up.fill", tint: .indigo)
            }
            .buttonStyle(.plain)
            NavigationLink { ADCheckView() } label: {
                ActionTileLabel(title: "AD check", icon: "checkmark.seal.fill", tint: .teal)
            }
            .buttonStyle(.plain)
            ActionTile(title: "Ask about your engine", icon: "bubble.left.and.text.bubble.right.fill", tint: .purple) { go(.ask) }
        }
    }
}

// MARK: - Pieces

/// An ECG-style trace that scrolls continuously, colored by engine health.
private struct PulseLine: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let period: CGFloat = 260
                let offset = CGFloat(t * 70).truncatingRemainder(dividingBy: period)
                var path = Path()
                let mid = size.height * 0.6
                var x: CGFloat = -period + offset
                path.move(to: CGPoint(x: -period, y: mid))
                while x < size.width + period {
                    // flat, small bump, sharp spike, dip, recovery
                    path.addLine(to: CGPoint(x: x + 90, y: mid))
                    path.addQuadCurve(to: CGPoint(x: x + 120, y: mid), control: CGPoint(x: x + 105, y: mid - 12))
                    path.addLine(to: CGPoint(x: x + 135, y: mid))
                    path.addLine(to: CGPoint(x: x + 145, y: mid + 14))
                    path.addLine(to: CGPoint(x: x + 158, y: mid - size.height * 0.55))
                    path.addLine(to: CGPoint(x: x + 170, y: mid + 22))
                    path.addLine(to: CGPoint(x: x + 182, y: mid))
                    path.addQuadCurve(to: CGPoint(x: x + 225, y: mid), control: CGPoint(x: x + 203, y: mid - 18))
                    path.addLine(to: CGPoint(x: x + period, y: mid))
                    x += period
                }
                ctx.addFilter(.shadow(color: color.opacity(0.8), radius: 6))
                ctx.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color, color.opacity(0.2)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Health score as an instrument arc, like an engine gauge.
private struct ScoreGauge: View {
    let score: Int?
    let color: Color
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.125, to: 0.125 + 0.75 * shown / 100)
                .stroke(AngularGradient(colors: [.red, .orange, .yellow, .green], center: .center,
                                        startAngle: .degrees(135), endAngle: .degrees(405)),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "--")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("HEALTH").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(color)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { shown = Double(score ?? 0) } }
        .onChange(of: score) { withAnimation(.easeOut(duration: 0.8)) { shown = Double(score ?? 0) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Engine health \($0) of 100" } ?? "No score yet")
    }
}

/// Tiles press down slightly when tapped, so they read as buttons.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct Reading: View {
    let label: String
    let value: String?
    /// Value above which the reading is shown in amber.
    let limit: Double?
    let raw: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "--")
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(warn ? Color.orange : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var warn: Bool {
        guard let limit, let raw, limit > 0 else { return false }
        return raw >= limit
    }
}

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ActionTile: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTileLabel(title: title, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionTileLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.white)
            Text(title).font(.subheadline.bold()).foregroundStyle(.white).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}


// MARK: - Engine health

/// Engine health from the last 10 flights: limits and cautions found in each flight (newer flights count
/// more) and any early-warning trend. Items waiting for review don't count; that's the "Open items" tile.
struct EngineHealth {
    enum Status {
        case healthy, watch, attention, noData
        var label: String {
            switch self {
            case .healthy: "Healthy"
            case .watch: "Watch"
            case .attention: "Needs attention"
            case .noData: "Waiting for your first flight"
            }
        }
        var color: Color {
            switch self {
            case .healthy: .green
            case .watch: .yellow
            case .attention: .red
            case .noData: .cyan
            }
        }
        var icon: String {
            switch self {
            case .healthy: "checkmark.seal.fill"
            case .watch: "eye.fill"
            case .attention: "exclamationmark.octagon.fill"
            case .noData: "waveform.path.ecg"
            }
        }
    }

    struct Deduction: Identifiable {
        let id = UUID()
        let points: Double
        let title: String
        let detail: String
        let severity: IssueSeverity
    }

    struct FlightScore: Identifiable {
        let id = UUID()
        let date: Date
        let score: Double
    }

    let score: Int?
    let status: Status
    let flights: [FlightScore]          // oldest first
    let deductions: [Deduction]
    /// Change in flight score per flight across the recent flights (least-squares slope).
    let slopePerFlight: Double?

    static let window = 10
    static func weight(_ s: IssueSeverity) -> Double {
        switch s {
        case .warning: 20
        case .caution: 8
        case .watch: 3
        case .info: 0
        }
    }

    static func compute(_ summaries: [FlightSummary]) -> EngineHealth {
        let recent = Array(summaries.sorted { $0.start > $1.start }.prefix(window))   // newest first
        guard !recent.isEmpty else {
            return EngineHealth(score: nil, status: .noData, flights: [], deductions: [], slopePerFlight: nil)
        }
        // Newest flight weighs most (10, 9, 8 ...).
        let weights = recent.indices.map { Double(window - $0) }
        let totalWeight = weights.reduce(0, +)
        var perFlight: [FlightScore] = []
        var byKind: [String: (points: Double, flights: Int, title: String, severity: IssueSeverity)] = [:]
        for (i, f) in recent.enumerated() {
            var seen: [String: FlightIssue] = [:]
            for issue in f.issues where issue.origin != .records && issue.severity != .info {
                if let old = seen[issue.kind], old.severity <= issue.severity { continue }
                seen[issue.kind] = issue
            }
            let penalty = min(100, seen.values.reduce(0) { $0 + weight($1.severity) })
            perFlight.append(FlightScore(date: f.start, score: 100 - penalty))
            let scale = penalty > 0 ? min(1, 100 / max(penalty, 1)) : 1
            for issue in seen.values {
                let pts = weights[i] * weight(issue.severity) * scale / totalWeight
                var e = byKind[issue.kind] ?? (0, 0, issue.title, issue.severity)
                e.points += pts
                e.flights += 1
                if i == 0 || e.title.isEmpty { e.title = issue.title }
                e.severity = min(e.severity, issue.severity)
                byKind[issue.kind] = e
            }
        }
        var deductions = byKind.values.map {
            Deduction(points: $0.points, title: $0.title,
                      detail: "\($0.severity.rawValue) · \($0.flights) of the last \(recent.count) flight\(recent.count == 1 ? "" : "s")",
                      severity: $0.severity)
        }
        var score = perFlight.enumerated().reduce(0.0) { $0 + weights[$1.offset] * $1.element.score } / totalWeight

        // Slow changes across flights (early warning) also count.
        let report = EarlyWarning.analyze(summaries)
        var trendPenalty = 0.0
        for a in report.findings {
            let pts: Double = a.level == .actSoon ? 15 : 6
            trendPenalty += pts
            deductions.append(Deduction(points: pts, title: "\(a.metric.label) trend",
                                        detail: "\(a.level?.rawValue ?? "") · changing across recent flights",
                                        severity: a.level == .actSoon ? .warning : .watch))
        }
        score -= min(30, trendPenalty)
        let final = Int(max(0, min(100, score)).rounded())

        let newest3HaveWarning = recent.prefix(3).contains { $0.issues.contains { $0.severity == .warning && $0.origin != .records } }
        let status: Status
        if final < 70 || newest3HaveWarning || report.level == .actSoon { status = .attention }
        else if final < 85 { status = .watch }
        else { status = .healthy }

        let chronological = Array(perFlight.reversed())
        return EngineHealth(score: final, status: status, flights: chronological,
                            deductions: deductions.filter { $0.points >= 0.5 }.sorted { $0.points > $1.points },
                            slopePerFlight: slope(chronological.map(\.score)))
    }

    static func slope(_ ys: [Double]) -> Double? {
        guard ys.count >= 3 else { return nil }
        let n = Double(ys.count)
        let xs = ys.indices.map(Double.init)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        return den == 0 ? nil : num / den
    }

    /// Points gained or lost across the recent flights, from the slope.
    var trendChange: Double? {
        guard let s = slopePerFlight else { return nil }
        return s * Double(max(flights.count - 1, 1))
    }

    var trendArrow: String? {
        guard let c = trendChange else { return nil }
        if c >= 5 { return "arrow.up.right" }
        if c <= -5 { return "arrow.down.right" }
        return "arrow.right"
    }

    var trendShort: String? {
        guard let c = trendChange else { return nil }
        if abs(c) < 5 { return "Steady" }
        return c > 0 ? "Improving" : "Declining"
    }

    var trendText: String? {
        guard let c = trendChange, let short = trendShort else { return nil }
        return abs(c) < 5 ? short : "\(short) \(c > 0 ? "+" : "")\(Int(c.rounded()))"
    }
}

/// Tap on the health gauge: the score, the trend across recent flights, and exactly what took points off.
struct HealthBreakdownView: View {
    let health: EngineHealth

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Text(health.score.map(String.init) ?? "--")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(health.status.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(health.status.label, systemImage: health.status.icon)
                            .font(.title3.bold())
                            .foregroundStyle(health.status.color)
                        if let t = health.trendText, let arrow = health.trendArrow {
                            Label("\(t) over the last \(health.flights.count) flights", systemImage: arrow)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Green 85-100: healthy. Yellow 70-84: watch. Red below 70, a warning in the last 3 flights, or an ACT SOON trend: needs attention.")
            }

            if health.flights.count >= 2 {
                Section("Score by flight") {
                    Chart {
                        RuleMark(y: .value("Healthy", 85.0))
                            .foregroundStyle(Color.green.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        RuleMark(y: .value("Watch", 70.0))
                            .foregroundStyle(Color.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(health.flights) { f in
                            LineMark(x: .value("Flight", f.date), y: .value("Score", f.score))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.cyan)
                            PointMark(x: .value("Flight", f.date), y: .value("Score", f.score))
                                .foregroundStyle(f.score >= 85 ? Color.green : (f.score >= 70 ? Color.yellow : Color.red))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 200)
                }
            }

            Section {
                if health.deductions.isEmpty {
                    Label("Nothing took points off. Every recent flight stayed inside your limits.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                ForEach(health.deductions) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(.subheadline.bold())
                            Text(d.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("-\(Int(d.points.rounded()))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(d.severity == .warning ? Color.red : (d.severity == .caution ? Color.orange : Color.secondary))
                    }
                }
            } header: {
                Text("What took points off")
            } footer: {
                Text("Each flight starts at 100: a warning costs 20, a caution 8 and a watch item 3. Newer flights count more. Early-warning trends cost 6 (15 if ACT SOON). Reviewing items doesn't change the score; flying within limits does.")
            }

            Section {
                NavigationLink { IssueHistoryView() } label: {
                    Label("Review open items", systemImage: "checklist")
                }
                NavigationLink { EarlyWarningView() } label: {
                    Label("Engine trends and early warnings", systemImage: "chart.xyaxis.line")
                }
            }
        }
        .navigationTitle("Engine Health")
    }
}


// MARK: - Early warning dashboard

/// HOME's early-warning panel: open warnings by severity, then one row per key trend with a sparkline,
/// its normal band, the latest value, the direction and its status.
private struct EarlyWarningCard: View {
    let report: EarlyWarningReport?
    let flights: [FlightSummary]          // newest first
    let attention: [IssueGroup]

    static let keyMetrics = ["oilt", "oilp", "chtspread", "egtspread", "titgap", "volt1", "volt2"]

    private var rows: [TrendAnalysis] {
        guard let report else { return [] }
        let flagged = report.findings.sorted { ($0.level == .actSoon ? 0 : 1) < ($1.level == .actSoon ? 0 : 1) }
        var out = flagged
        // Hottest cylinder's CHT, then the key engine metrics.
        if let hottest = report.analyses.filter({ $0.metric.id.hasPrefix("cht") && $0.metric.cylinder != nil })
            .max(by: { $0.recentValue < $1.recentValue }) {
            out.append(hottest)
        }
        out += Self.keyMetrics.compactMap { report.analysis($0) }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(7))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Early warning", systemImage: "waveform.badge.exclamationmark").font(.headline)
                Spacer()
                LevelChip(level: report?.level, hasData: !(report?.analyses.isEmpty ?? true))
            }
            HStack(spacing: 8) {
                CountChip(label: "Warnings", count: attention.filter { $0.severity == .warning }.count, color: .red)
                CountChip(label: "Cautions", count: attention.filter { $0.severity == .caution }.count, color: .orange)
                CountChip(label: "Watch", count: attention.filter { $0.severity == .watch }.count, color: .yellow)
                CountChip(label: "Trends", count: report?.findings.count ?? 0, color: .purple)
            }
            if rows.isEmpty {
                fallback
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { a in
                        NavigationLink { TrendDetailView(metricID: a.metric.id) } label: { TrendRow(analysis: a) }
                            .buttonStyle(.plain)
                        if a.id != rows.last?.id { Divider() }
                    }
                }
            }
            NavigationLink { EarlyWarningView() } label: {
                HStack {
                    Text("All trends and early warnings").font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Before there are enough flights for the early-warning baseline: raw cruise values per flight.
    @ViewBuilder
    private var fallback: some View {
        let recent = Array(flights.prefix(15).reversed())
        let series: [RawSeries] = [
            RawSeries(name: "Hottest CHT", unit: "°F", values: recent.compactMap { $0.engineTrend?.cht.compactMap { $0 }.max() }),
            RawSeries(name: "Oil temperature", unit: "°F", values: recent.compactMap { $0.engineTrend?.oilTemp }),
            RawSeries(name: "Oil pressure", unit: "psi", values: recent.compactMap { $0.engineTrend?.oilPressure }),
            RawSeries(name: "CHT spread", unit: "°F", values: recent.compactMap { $0.engineTrend?.chtSpread }),
        ]
        VStack(spacing: 10) {
            ForEach(series.filter { $0.values.count >= 2 }) { item in
                HStack(spacing: 12) {
                    Text(item.name).font(.subheadline).frame(width: 130, alignment: .leading)
                    Sparkline(values: item.values, band: nil, color: .cyan).frame(height: 28)
                    Text("\(Int(item.values.last ?? 0)) \(item.unit)").font(.subheadline.monospacedDigit().bold())
                        .frame(width: 72, alignment: .trailing)
                }
            }
            Text("Early-warning analysis starts once there are about 25 flights with steady cruise (\(flights.count) so far). Until then these are your raw cruise values.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RawSeries: Identifiable {
    let name: String
    let unit: String
    let values: [Double]
    var id: String { name }
}

private struct TrendRow: View {
    let analysis: TrendAnalysis

    private var label: String {
        analysis.metric.label.replacingOccurrences(of: " in cruise", with: "")
            .replacingOccurrences(of: "Gap between TIT 1 and TIT 2", with: "TIT 1 vs 2 gap")
    }

    /// Direction of the recent trend, coloured by whether it's moving the bad way.
    private var direction: (icon: String, color: Color) {
        let bad = analysis.slopePerHour * analysis.metric.badDirection
        let span = max(analysis.normalHigh - analysis.normalLow, 0.001)
        if abs(analysis.slopePerHour) * 10 < span * 0.1 { return ("arrow.right", .secondary) }
        let up = analysis.slopePerHour > 0
        return (up ? "arrow.up.right" : "arrow.down.right", bad > 0 ? .orange : .green)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).lineLimit(1)
                Text("Normal \(fmt(analysis.normalLow))-\(fmt(analysis.normalHigh)) \(analysis.metric.unit)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            Sparkline(values: analysis.points.suffix(15).map(\.adjusted), band: analysis.normalLow...analysis.normalHigh,
                      color: analysis.level == nil ? .cyan : (analysis.level == .actSoon ? .red : .orange))
                .frame(height: 30)
            Image(systemName: direction.icon).font(.caption.bold()).foregroundStyle(direction.color)
            Text("\(fmt(analysis.recentValue)) \(analysis.metric.unit)")
                .font(.subheadline.monospacedDigit().bold())
                .frame(width: 74, alignment: .trailing)
            LevelChip(level: analysis.level, hasData: true, compact: true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func fmt(_ v: Double) -> String {
        analysis.metric.unit == "V" ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }
}

/// A tiny line chart with the normal band shaded.
private struct Sparkline: View {
    let values: [Double]
    let band: ClosedRange<Double>?
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let lo = min(values.min() ?? 0, band?.lowerBound ?? .infinity)
            let hi = max(values.max() ?? 1, band?.upperBound ?? -.infinity)
            let range = max(hi - lo, 0.001)
            let y: (Double) -> CGFloat = { geo.size.height * (1 - CGFloat(($0 - lo) / range)) }
            ZStack {
                if let band {
                    Rectangle()
                        .fill(Color.green.opacity(0.12))
                        .frame(height: max(1, y(band.lowerBound) - y(band.upperBound)))
                        .position(x: geo.size.width / 2, y: (y(band.lowerBound) + y(band.upperBound)) / 2)
                }
                Path { p in
                    for (i, v) in values.enumerated() {
                        let pt = CGPoint(x: values.count < 2 ? 0 : geo.size.width * CGFloat(i) / CGFloat(values.count - 1), y: y(v))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = values.last {
                    Circle().fill(color).frame(width: 6, height: 6)
                        .position(x: geo.size.width, y: y(last))
                }
            }
        }
    }
}

private struct LevelChip: View {
    let level: TrendAnalysis.Level?
    let hasData: Bool
    var compact = false

    private var text: String {
        guard hasData else { return "Building baseline" }
        switch level {
        case .actSoon: return "ACT SOON"
        case .earlyWarning: return compact ? "WATCH" : "EARLY WARNING"
        case nil: return "Normal"
        }
    }

    private var color: Color {
        guard hasData else { return .secondary }
        switch level {
        case .actSoon: return .red
        case .earlyWarning: return .orange
        case nil: return .green
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .fixedSize()
    }
}

private struct CountChip: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.subheadline.bold().monospacedDigit())
            Text(label).font(.caption)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((count > 0 ? color : Color.secondary).opacity(0.15), in: Capsule())
        .foregroundStyle(count > 0 ? color : Color.secondary)
    }
}

/// HOME's battery panel: the lowest bus 1 voltage on each engine start, compared with this battery's own normal.
struct BatteryStartCard: View {
    let report: BatteryWatchReport?

    private var chip: (String, Color) {
        switch report?.level {
        case .watch?: ("Check battery", .orange)
        case .normal?: ("Normal", .green)
        case .learning?: ("Learning", .blue)
        default: ("No data", .secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Battery at engine start", systemImage: "battery.75percent").font(.headline)
                Spacer()
                Text(chip.0).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(chip.1.opacity(0.15), in: Capsule()).foregroundStyle(chip.1)
            }
            if let report {
                let pts = Array(report.points.prefix(20))
                if pts.count >= 2 {
                    Chart {
                        ForEach(pts) { p in
                            LineMark(x: .value("Start", p.time), y: .value("Lowest V", p.lowVolts))
                            PointMark(x: .value("Start", p.time), y: .value("Lowest V", p.lowVolts))
                        }
                        if let b = report.baselineLow {
                            RuleMark(y: .value("Normal", b)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 110)
                }
                if let last = report.points.first {
                    Text(lastLine(last)).font(.subheadline)
                }
                Text(report.summary).font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { SystemHistoryView(system: .engineStart) } label: {
                HStack {
                    Text("All engine starts").font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func lastLine(_ p: BatteryStartPoint) -> String {
        var parts = [String(format: "Last start: lowest %.1f V", p.lowVolts)]
        if let r = p.restVolts, let d = p.drop { parts.append(String(format: "from %.1f V (dip %.1f V)", r, d)) }
        if let c = p.crankSeconds { parts.append(String(format: "cranked %.0f s", c)) }
        if let o = p.oat { parts.append(String(format: "OAT %.0f °C", o)) }
        return parts.joined(separator: " · ")
    }
}
