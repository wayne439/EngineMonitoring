import SwiftUI

/// MAINTENANCE: what is due (by days and engine hours from the logs), the checks you do yourself
/// (FIKI test, tire pressure) with their results, and the history of every check and service.
private struct MaintenanceRowData: Identifiable {
    let item: MaintenanceItem
    let status: MaintenanceStatus
    var id: String { item.id }
}

struct MaintenanceView: View {
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var addingItem = false

    var body: some View {
        let summaries = Array(logStore.summaries.values)
        let rows = maintenance.items.map { MaintenanceRowData(item: $0, status: maintenance.status($0, summaries: summaries)) }
            .sorted { $0.status.state != $1.status.state ? $0.status.state < $1.status.state : $0.item.name < $1.item.name }
        List {
            let attention = rows.filter { $0.status.state != .ok }
            Section {
                if attention.isEmpty {
                    Label("Everything is up to date.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                ForEach(attention) { r in
                    NavigationLink { MaintenanceItemView(itemID: r.item.id) } label: { MaintenanceRow(item: r.item, status: r.status) }
                }
            } header: {
                Text("Needs Attention (\(attention.count))")
            }
            Section("Up To Date") {
                ForEach(rows.filter { $0.status.state == .ok }) { r in
                    NavigationLink { MaintenanceItemView(itemID: r.item.id) } label: { MaintenanceRow(item: r.item, status: r.status) }
                }
            }
            Section {
                if let t = maintenance.estimatedTach(summaries: summaries) {
                    LabeledContent("Estimated total time now", value: String(format: "%.1f h", t.value))
                    Text(String(format: "%.1f recorded %@ + %.1f flight hours from the logs since", t.anchor,
                                t.anchorDate.formatted(date: .abbreviated, time: .omitted), t.value - t.anchor))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Flight hours in the logs, last 30 days",
                               value: String(format: "%.1f h", MaintenanceSchedule.flightHours(since: Date().addingTimeInterval(-30 * 86400), summaries: summaries)))
                Button { addingItem = true } label: { Label("Add a check or service", systemImage: "plus.circle") }
            } footer: {
                Text("Hours come from the data card logs (airborne time, which tracks this aircraft's logbook total time within a few percent). Each service you record with its tach resets the estimate. Upload every card or the hour-based items fall behind. Reminders are a planning aid: the logbook and your A&P govern.")
            }
        }
        .navigationTitle("MAINTENANCE")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: maintenance.csv(), subject: Text("Maintenance log"), preview: SharePreview("Maintenance log")) {
                    Label("Export Log", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $addingItem) { MaintenanceItemEditor(item: nil) }
        .onAppear { MaintenanceReminders.requestPermission() }
        .alert("Storage problem", isPresented: Binding(get: { maintenance.lastError != nil }, set: { if !$0 { maintenance.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(maintenance.lastError ?? "") }
    }
}

struct MaintenanceRow: View {
    let item: MaintenanceItem
    let status: MaintenanceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(item.name).font(.headline)
                Spacer()
                Text(status.state.label).font(.caption.bold()).foregroundStyle(color)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if !status.problems.isEmpty {
                Text(status.problems.joined(separator: " · ")).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = [item.kind.rawValue]
        if let last = status.last { parts.append("last \(last.date.formatted(date: .abbreviated, time: .omitted))") }
        if !status.summary.isEmpty { parts.append(status.summary) }
        if status.last == nil { parts.append(item.intervalText) }
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        switch status.state {
        case .failed: "xmark.octagon.fill"
        case .overdue: "exclamationmark.triangle.fill"
        case .neverDone: "questionmark.circle"
        case .dueSoon: "clock.fill"
        case .ok: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch status.state {
        case .failed, .overdue: .red
        case .neverDone, .dueSoon: .orange
        case .ok: .green
        }
    }
}

struct MaintenanceItemView: View {
    let itemID: String
    @EnvironmentObject private var maintenance: MaintenanceStore
    @EnvironmentObject private var logStore: FlightLogStore
    @State private var recording = false
    @State private var editing = false

    var body: some View {
        Group {
            if let item = maintenance.item(itemID) {
                let status = maintenance.status(item, summaries: Array(logStore.summaries.values))
                List {
                    Section {
                        MaintenanceRow(item: item, status: status)
                        LabeledContent("Schedule", value: item.intervalText)
                        if let d = status.nextDate { LabeledContent("Next due by date", value: d.formatted(date: .abbreviated, time: .omitted)) }
                        if let h = status.hoursSince, let i = item.intervalHours {
                            LabeledContent("Hours since last", value: String(format: "%.1f of %.0f h", h, i))
                        }
                        Button { recording = true } label: {
                            Label(item.kind == .pilotCheck ? "Record Check Result" : "Record It Done", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Section {
                        ForEach(item.instructions, id: \.self) { Label($0, systemImage: "list.bullet").labelStyle(.titleAndIcon) }
                        if !item.fields.isEmpty {
                            ForEach(item.fields.filter { $0.rangeText != nil }) { f in
                                LabeledContent(f.label, value: f.rangeText ?? "")
                            }
                        }
                    } header: {
                        HStack { Text("How"); Spacer(); AuthorityBadge(authority: item.authority) }
                    } footer: {
                        Text(item.source)
                    }
                    Section("History (\(maintenance.entries(for: item.id).count))") {
                        let history = maintenance.entries(for: item.id)
                        if history.isEmpty { Text("Nothing recorded yet.").foregroundStyle(.secondary) }
                        ForEach(history) { e in MaintenanceEntryRow(item: item, entry: e) }
                            .onDelete { offsets in offsets.map { history[$0].id }.forEach(maintenance.deleteEntry) }
                    }
                }
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit Schedule") { editing = true } } }
                .sheet(isPresented: $recording) { MaintenanceEntryEditor(item: item) }
                .sheet(isPresented: $editing) { MaintenanceItemEditor(item: item) }
            } else {
                Text("This item was removed.").foregroundStyle(.secondary)
            }
        }
    }
}

struct MaintenanceEntryRow: View {
    let item: MaintenanceItem
    let entry: MaintenanceEntry

    var body: some View {
        let problems = entry.problems(for: item)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                Spacer()
                Text(problems.isEmpty ? "PASS" : "FAIL").font(.caption.bold()).foregroundStyle(problems.isEmpty ? Color.green : Color.red)
            }
            Text(item.fields.compactMap { f in entry.values[f.key].flatMap { $0.isEmpty ? nil : "\(f.label) \($0)\(f.kind == .number ? (f.unit.map { " \($0)" } ?? "") : "")" } }
                .joined(separator: " · "))
                .font(.caption)
            if !problems.isEmpty { Text(problems.joined(separator: " · ")).font(.caption).foregroundStyle(.red) }
            if !entry.notes.isEmpty { Text(entry.notes).font(.caption).foregroundStyle(.secondary) }
            if !entry.by.isEmpty { Text("By \(entry.by)").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Form for one result: a field per value, date, who, notes.
struct MaintenanceEntryEditor: View {
    let item: MaintenanceItem
    @EnvironmentObject private var maintenance: MaintenanceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reviewerName") private var by = ""
    @State private var date = Date()
    @State private var values: [String: String] = [:]
    @State private var notes = ""

    private var draft: MaintenanceEntry { MaintenanceEntry(itemID: item.id, date: date, values: values, notes: notes, by: by) }
    private var missing: [String] {
        item.fields.filter { !$0.optional && (values[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.map(\.label)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Done by (PIC, A&P, shop)", text: $by)
                }
                Section("Results") {
                    ForEach(item.fields) { f in fieldRow(f) }
                }
                Section("Notes") {
                    TextField("What you saw or what was done", text: $notes, axis: .vertical).lineLimit(2...6)
                }
                if !draft.problems(for: item).isEmpty {
                    Section {
                        ForEach(draft.problems(for: item), id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    } footer: {
                        Text("Saved as FAIL. It stays at the top of MAINTENANCE until a passing result is recorded.")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { maintenance.record(draft); dismiss() }.disabled(!missing.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ f: MaintenanceField) -> some View {
        let binding = Binding(get: { values[f.key] ?? "" }, set: { values[f.key] = $0 })
        switch f.kind {
        case .passFail:
            Picker(f.label, selection: binding) {
                Text("Select").tag("")
                Text("Pass").tag("pass")
                Text("Fail").tag("fail")
            }
        case .yesNo:
            Picker(f.label, selection: binding) {
                Text("Select").tag("")
                Text("Yes").tag("yes")
                Text("No").tag("no")
            }
        case .number:
            HStack {
                Text(f.label)
                Spacer()
                TextField(f.rangeText ?? (f.unit ?? ""), text: binding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                if let u = f.unit { Text(u).foregroundStyle(.secondary) }
            }
        case .text:
            TextField(f.label, text: binding)
        }
    }
}

/// Add your own check or service, or change the schedule of any item.
struct MaintenanceItemEditor: View {
    let item: MaintenanceItem?
    @EnvironmentObject private var maintenance: MaintenanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: MaintenanceItem.Kind = .pilotCheck
    @State private var useDays = true
    @State private var days = 30
    @State private var useHours = false
    @State private var hours = 25.0
    @State private var warnDays = 5
    @State private var steps = ""
    @State private var numberFields: [NumberDraft] = []
    @State private var loaded = false

    struct NumberDraft: Identifiable { let id = UUID(); var label = ""; var unit = ""; var low = ""; var high = "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Battery voltage check", text: $name).disabled(item?.builtIn == true)
                    Picker("Type", selection: $kind) { ForEach(MaintenanceItem.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .disabled(item?.builtIn == true)
                }
                Section("Schedule (whichever comes first)") {
                    Toggle("By days", isOn: $useDays)
                    if useDays { Stepper("Every \(days) days", value: $days, in: 1...1095) }
                    Toggle("By hours (total time)", isOn: $useHours)
                    if useHours { Stepper(String(format: "Every %.0f hours", hours), value: $hours, in: 1...2000, step: 1) }
                    Stepper("Due-soon warning \(warnDays) days before", value: $warnDays, in: 0...90)
                }
                if item?.builtIn != true {
                    Section {
                        TextField("Steps, one per line", text: $steps, axis: .vertical).lineLimit(3...10)
                    } header: { Text("How to do it") }
                    Section {
                        ForEach($numberFields) { $f in
                            VStack {
                                TextField("Value name, e.g. Battery voltage", text: $f.label)
                                HStack {
                                    TextField("Unit", text: $f.unit)
                                    TextField("Min", text: $f.low).keyboardType(.decimalPad)
                                    TextField("Max", text: $f.high).keyboardType(.decimalPad)
                                }
                            }
                        }
                        Button { numberFields.append(NumberDraft()) } label: { Label("Add a value to record", systemImage: "plus") }
                    } header: { Text("Values (a Pass/Fail result is always included)") }
                }
                if let item, !item.builtIn {
                    Section {
                        Button("Delete this item and its history", role: .destructive) { maintenance.removeItem(item.id); dismiss() }
                    }
                }
            }
            .navigationTitle(item == nil ? "New Check or Service" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (!useDays && !useHours))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else { return }
        name = item.name; kind = item.kind
        useDays = item.intervalDays != nil; days = item.intervalDays ?? 30
        useHours = item.intervalHours != nil; hours = item.intervalHours ?? 25
        warnDays = item.warnDays
        steps = item.instructions.joined(separator: "\n")
    }

    private func save() {
        if var existing = item {
            existing.intervalDays = useDays ? days : nil
            existing.intervalHours = useHours ? hours : nil
            existing.warnDays = warnDays
            if existing.builtIn { existing.userEdited = true }
            if !existing.builtIn {
                existing.name = name; existing.kind = kind
                existing.instructions = steps.split(separator: "\n").map(String.init)
            }
            maintenance.upsert(existing)
            return
        }
        var fields = [MaintenanceField(key: "result", label: "Result", kind: .passFail)]
        for (i, f) in numberFields.enumerated() where !f.label.trimmingCharacters(in: .whitespaces).isEmpty {
            fields.append(MaintenanceField(key: "v\(i)", label: f.label, kind: .number, unit: f.unit.isEmpty ? nil : f.unit,
                                           low: Double(f.low), high: Double(f.high)))
        }
        maintenance.upsert(MaintenanceItem(
            id: "custom-\(UUID().uuidString.prefix(8).lowercased())", name: name, kind: kind,
            intervalDays: useDays ? days : nil, intervalHours: useHours ? hours : nil,
            warnDays: warnDays, warnHours: useHours ? max(1, hours * 0.1) : 0,
            instructions: steps.split(separator: "\n").map(String.init), fields: fields,
            source: "Your own item, added in the app.", authority: .experience, builtIn: false))
    }
}
