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

    /// 100 = nothing open. Unreviewed warnings, cautions, watch items and overdue maintenance take points off.
    private var score: Int {
        var s = 100
        for g in attention {
            switch g.severity {
            case .warning: s -= 25
            case .caution: s -= 10
            case .watch: s -= 4
            case .info: break
            }
        }
        s -= maintenanceDue.filter { $0.status.state == .overdue || $0.status.state == .failed }.count * 10
        return max(0, min(100, s))
    }

    private var health: (label: String, color: Color, icon: String) {
        if flights.isEmpty { return ("Waiting for your first flight", .cyan, "waveform.path.ecg") }
        if attention.contains(where: { $0.severity == .warning }) { return ("Needs attention", .red, "exclamationmark.octagon.fill") }
        if score < 85 { return ("Keep an eye on it", .orange, "eye.fill") }
        return ("Running healthy", .green, "checkmark.seal.fill")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                statTiles
                if let last = flights.first { lastFlightCard(last) }
                if flights.count >= 2 { trendCard }
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
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.04, green: 0.11, blue: 0.23), Color(red: 0.07, green: 0.19, blue: 0.37)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            PulseLine(color: health.color)
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
                    NavigationLink { IssueHistoryView() } label: {
                        HStack(spacing: 6) {
                            Label(health.label, systemImage: health.icon)
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }
                        .font(.headline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(health.color.opacity(0.22), in: Capsule())
                        .foregroundStyle(health.color)
                    }
                    .buttonStyle(TileButtonStyle())
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                NavigationLink { IssueHistoryView() } label: {
                    ScoreGauge(score: flights.isEmpty ? nil : score, color: health.color)
                        .frame(width: 132, height: 132)
                }
                .buttonStyle(TileButtonStyle())
            }
            .padding(24)
        }
        .frame(height: 230)
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
                Text("PULSE").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(color)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { shown = Double(score ?? 0) } }
        .onChange(of: score) { withAnimation(.easeOut(duration: 0.8)) { shown = Double(score ?? 0) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Engine pulse score \($0) of 100" } ?? "No score yet")
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
