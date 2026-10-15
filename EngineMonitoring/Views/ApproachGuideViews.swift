import SwiftUI
import UIKit

@MainActor
final class ApproachGuideStore: ObservableObject {
    @Published private(set) var book: ApproachGuideBook?
    @Published private(set) var loadError: String?

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "approach_cards", withExtension: "json") else {
            loadError = "Approach guides are not included in this version."
            return
        }
        do { book = try ApproachGuideBook.decode(Data(contentsOf: url)) } catch {
            loadError = "Approach guides could not be read: \(error.localizedDescription)"
        }
    }
}

/// Rows for the FLY screen: one per approach type.
struct ApproachGuideSection: View {
    @EnvironmentObject private var guides: ApproachGuideStore

    var body: some View {
        Section {
            if let book = guides.book {
                ForEach(book.cards) { card in
                    NavigationLink {
                        ApproachCardView(card: card, basis: book.basis)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(card.title).font(.headline)
                                Spacer()
                                Text(card.minimaType)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            Text(card.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if let error = guides.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            NavigationLink {
                PerspectiveKeysView()
            } label: {
                Label("Perspective and autopilot keys", systemImage: "keyboard")
            }
        } header: {
            Text("Approach Guides - What to Push and When")
        } footer: {
            Text("Big-type card for flying the approach in IMC; all steps are one tap deeper for study. Training aids for review with your CFII.")
        }
    }
}

/// The in-flight card: big type, only what you do while flying the approach, one moment at a time.
/// Tap the current line when it is done; the next one is highlighted. MISSED is always on screen.
struct ApproachCardView: View {
    let card: ApproachCard
    let basis: String
    @AppStorage("N63KA.approachMode") private var modeRaw = FlyingMode.autopilot.rawValue
    @State private var current = 0
    @State private var briefDone: Set<Int> = []
    @State private var showBrief = true

    private var mode: FlyingMode { FlyingMode(rawValue: modeRaw) ?? .autopilot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("How you will fly it", selection: $modeRaw) {
                    ForEach(FlyingMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .onChange(of: modeRaw) { _, _ in current = 0 }

                if let q = card.quickCard(for: mode) {
                    briefSection(q.brief)
                    ForEach(Array(q.fly.enumerated()), id: \.offset) { index, line in
                        QuickLineRow(line: line,
                                     state: index < current ? .done : (index == current ? .current : .upcoming),
                                     isMissed: line.when == "MISSED" || line.when == "THEN")
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    current = index == current ? min(current + 1, q.fly.count) : index
                                }
                            }
                    }
                } else {
                    Text("No quick card for this approach.").foregroundStyle(.secondary)
                }

                Text(card.keyTrap)
                    .font(.footnote.bold())
                    .foregroundStyle(Color.orange)

                NavigationLink {
                    ApproachDetailView(card: card, basis: basis)
                } label: {
                    Label("All steps (study on the ground)", systemImage: "list.number")
                }
                Text("Training aid. Speeds from POH 4-3 / 4-21. Charts, the POH and approved supplements control.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(card.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    current = 0
                    briefDone.removeAll()
                    showBrief = true
                } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                }
                Button {
                    printQuick()
                } label: {
                    Label("Print Kneeboard Card", systemImage: "printer")
                }
            }
        }
    }

    @ViewBuilder
    private func briefSection(_ items: [SetupItem]) -> some View {
        DisclosureGroup(isExpanded: $showBrief) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    Button {
                        if briefDone.contains(i) { briefDone.remove(i) } else { briefDone.insert(i) }
                        if briefDone.count == items.count { withAnimation { showBrief = false } }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: briefDone.contains(i) ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(briefDone.contains(i) ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.task).font(.headline)
                                KeycapRow(controls: item.keys)
                                if let note = item.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .opacity(briefDone.contains(i) ? 0.45 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    PerspectiveKeysView()
                } label: {
                    Label("What each Perspective key does", systemImage: "keyboard")
                        .font(.subheadline)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("SET UP PERSPECTIVE  \(briefDone.count)/\(items.count)")
                .font(.subheadline.bold())
        }
    }

    private func printQuick() {
        guard let html = ApproachPrinter.quickHTML(card, mode: mode) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "\(card.title) \(mode.rawValue) card"
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = UIMarkupTextPrintFormatter(markupText: html)
        controller.present(animated: true)
    }
}

private struct QuickLineRow: View {
    enum LineState { case done, current, upcoming }
    let line: QuickLine
    let state: LineState
    let isMissed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(line.when)
                .font(state == .current ? .title2.weight(.heavy) : .title3.weight(.bold))
                .foregroundStyle(isMissed ? Color.red : (state == .current ? Color.accentColor : Color.primary))
                .frame(width: 150, alignment: .leading)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                if !line.do.isEmpty {
                    Text(line.do.joined(separator: "  ·  "))
                        .font(state == .current ? .title.weight(.bold) : .title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let check = line.check {
                    Text(check)
                        .font(state == .current ? .title3 : .body)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(state == .current ? 16 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(state == .current ? Color.accentColor.opacity(0.15) : (isMissed ? Color.red.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(state == .current ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: state == .current ? 3 : 1)
        )
        .opacity(state == .done ? 0.35 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(state == .current ? "Double tap when done" : "")
    }
}

struct ApproachDetailView: View {
    let card: ApproachCard
    let basis: String
    @AppStorage("N63KA.approachMode") private var modeRaw = FlyingMode.autopilot.rawValue
    @State private var done: Set<String> = []

    private var mode: FlyingMode { FlyingMode(rawValue: modeRaw) ?? .autopilot }

    var body: some View {
        List {
            Section {
                Picker("How you will fly it", selection: $modeRaw) {
                    ForEach(FlyingMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Label(card.keyTrap, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.orange)
                HStack(spacing: 12) {
                    InfoChip(label: "Final on", value: card.navSource)
                    InfoChip(label: "Minima", value: card.minimaType)
                    InfoChip(label: "Vertical", value: card.verticalGuidance)
                }
            }

            ForEach(Array(card.phases(for: mode).enumerated()), id: \.offset) { _, phase in
                Section(phase.title) {
                    ForEach(phase.steps) { step in
                        StepRow(step: step, isDone: done.contains(step.id)) {
                            if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) }
                        }
                    }
                }
            }

            Section {
                ForEach(card.notes, id: \.self) { Text($0) }
                HStack {
                    AuthorityBadge(authority: card.authority)
                    Text("Revision \(card.revision)").font(.caption).foregroundStyle(.secondary)
                }
                Text(basis).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Notes")
            } footer: {
                Text("Steps marked APPROVED restate the POH. All other steps are a training aid: current charts, NOTAMs, the POH and approved supplements control.")
            }
        }
        .navigationTitle("\(card.title) - All Steps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    done.removeAll()
                } label: {
                    Label("Reset Checks", systemImage: "arrow.counterclockwise")
                }
                .disabled(done.isEmpty)
                Button {
                    printCard()
                } label: {
                    Label("Print or Save PDF", systemImage: "printer")
                }
            }
        }
    }

    /// AirPrint, or "Save to Files" from the print sheet to keep a one-page PDF.
    private func printCard() {
        let formatter = UIMarkupTextPrintFormatter(markupText: ApproachPrinter.html(card, mode: mode, basis: basis))
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "\(card.title) \(mode.rawValue)"
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = formatter
        controller.present(animated: true)
    }
}

private struct InfoChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
        }
    }
}

private struct StepRow: View {
    let step: ApproachStep
    let isDone: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    if let when = step.when {
                        Text(when.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(step.action)
                        .font(.body)
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                    if !step.controls.isEmpty {
                        KeycapRow(controls: step.controls)
                    }
                    if let verify = step.verify {
                        Label(verify, systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if step.authority == .approved, let source = step.source {
                        Label("APPROVED - \(source)", systemImage: "checkmark.shield.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.green)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Buttons, knobs and softkeys drawn as keycaps, in the order to use them.
private struct KeycapRow: View {
    let controls: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { caps }
            VStack(alignment: .leading, spacing: 6) { caps }
        }
    }

    @ViewBuilder
    private var caps: some View {
        ForEach(Array(controls.enumerated()), id: \.offset) { index, control in
            HStack(spacing: 4) {
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                Text(control)
                    .font(.caption.weight(.semibold).monospaced())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.5), lineWidth: 1))
            }
        }
    }
}

/// What each Perspective / GFC 700 key and knob does.
struct PerspectiveKeysView: View {
    @EnvironmentObject private var guides: ApproachGuideStore

    var body: some View {
        List {
            ForEach(guides.book?.keyReference ?? [], id: \.group) { group in
                Section(group.group) {
                    ForEach(group.items, id: \.key) { item in
                        HStack(alignment: .top, spacing: 12) {
                            KeycapRow(controls: [item.key])
                                .frame(width: 150, alignment: .leading)
                            Text(item.does)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if let note = guides.book?.keyReferenceNote {
                Section { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Perspective Keys")
    }
}
