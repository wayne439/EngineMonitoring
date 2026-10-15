import SwiftUI

/// Emergency (Section 3) and abnormal (Section 3A) procedures from the POH, one tap away. Works offline.
struct ProceduresView: View {
    @EnvironmentObject private var poh: POHRepository

    var body: some View {
        List {
            if let index = poh.index {
                Section {
                    Label("Text from the N63KA POH (\(index.document.partNumber), \(index.document.revision)). Verify against the printed POH; the turbonormalizer supplement is not loaded.",
                          systemImage: "checkmark.shield")
                        .font(.footnote)
                }
                procedureSections(index, kind: .emergency, title: "Emergency Procedures - Section 3")
                procedureSections(index, kind: .abnormal, title: "Abnormal Procedures - Section 3A")
            } else if let error = poh.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else {
                ProgressView("Loading POH…")
            }
        }
        .navigationTitle("PROCEDURES")
    }

    @ViewBuilder
    private func procedureSections(_ index: POHIndex, kind: POHIndex.Procedure.Kind, title: String) -> some View {
        Section {
            Text(title).font(.title3.bold())
        }
        ForEach(index.groupedProcedures(kind)) { group in
            Section(group.name) {
                ForEach(group.items) { procedure in
                    NavigationLink {
                        ProcedureView(procedure: procedure)
                    } label: {
                        HStack {
                            Text(procedure.title).font(.headline)
                            Spacer()
                            Text(procedure.label).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
}

struct ProcedureView: View {
    let procedure: POHIndex.Procedure
    @EnvironmentObject private var poh: POHRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AuthorityBadge(authority: .approved)
                    Text("POH page \(procedure.label)").font(.caption.bold())
                    Spacer()
                }
                Text("Extracted from the POH text. Charts and figures appear only on the POH page itself. If anything differs from the printed page, the printed POH governs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let index = poh.index {
                    Text(POHFormatter.readable(index.text(for: procedure)))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle(procedure.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = poh.pdfURL {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        POHPDFScreen(url: url, pdfPage: procedure.pdfPage, title: "POH \(procedure.label)")
                    } label: {
                        Label("Open POH Page", systemImage: "doc.richtext")
                    }
                }
            }
        }
    }
}

struct POHPageView: View {
    let page: POHIndex.Page
    var highlight: String = ""
    @EnvironmentObject private var poh: POHRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AuthorityBadge(authority: .approved)
                    Text("\(page.section) - page \(page.label)").font(.caption.bold())
                    Spacer()
                }
                Text(POHFormatter.readable(page.text))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("POH \(page.label)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = poh.pdfURL {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        POHPDFScreen(url: url, pdfPage: page.pdfPage, title: "POH \(page.label)")
                    } label: {
                        Label("Open POH Page", systemImage: "doc.richtext")
                    }
                }
            }
        }
    }
}

struct POHPDFScreen: View {
    let url: URL
    let pdfPage: Int
    let title: String
    @AppStorage("N63KA.pdfNightMode") private var nightMode = false

    var body: some View {
        PDFViewer(url: url, initialPage: pdfPage)
            .colorInvertIf(nightMode)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        nightMode.toggle()
                    } label: {
                        Label(nightMode ? "Day Mode" : "Night Mode", systemImage: nightMode ? "sun.max" : "moon")
                    }
                }
            }
    }
}

extension View {
    @ViewBuilder
    func colorInvertIf(_ enabled: Bool) -> some View {
        if enabled { self.colorInvert() } else { self }
    }
}
