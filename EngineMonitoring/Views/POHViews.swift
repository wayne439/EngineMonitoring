import SwiftUI
import UniformTypeIdentifiers

/// Emergency (Section 3) and abnormal (Section 3A) procedures from the POH, one tap away. Works offline.
struct ProceduresView: View {
    @EnvironmentObject private var poh: POHRepository
    @EnvironmentObject private var cloud: CloudStore
    @State private var picking = false

    var body: some View {
        List {
            if poh.isBuilding {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(poh.buildStatus ?? "Reading your POH…")
                    }
                } footer: {
                    Text("Your POH is being read on this iPad. Large manuals take a minute or two.")
                }
            }
            if let index = poh.index, !index.procedures.isEmpty {
                Section {
                    Label("Text from your POH (\(index.document.partNumber), \(index.document.revision)). Verify against the printed POH and any approved supplements.",
                          systemImage: "checkmark.shield")
                        .font(.footnote)
                }
                procedureSections(index, kind: .emergency, title: "Emergency Procedures - Section 3")
                procedureSections(index, kind: .abnormal, title: "Abnormal Procedures - Section 3A")
            } else if let index = poh.index {
                Section {
                    Label("Your POH (\(index.document.title)) is loaded and searchable in ASK, but its emergency checklists could not be picked out automatically.",
                          systemImage: "info.circle")
                    if let url = poh.pdfURL(for: index.document) {
                        NavigationLink {
                            POHPDFScreen(url: url, pdfPage: firstPage(of: "Section 3 ", in: index), title: "POH Section 3")
                        } label: {
                            Label("Open POH at Section 3", systemImage: "doc.richtext")
                        }
                    }
                }
            } else if !poh.isBuilding {
                Section {
                    Label(poh.loadError ?? POHRepository.noPOHMessage, systemImage: "book.closed")
                    if cloud.isSignedIn {
                        Button {
                            Task {
                                await cloud.refreshInbox()
                                await poh.syncFromUploads(cloud: cloud)
                            }
                        } label: {
                            Label("Load my POH from my uploads", systemImage: "arrow.down.doc")
                        }
                    }
                    NavigationLink {
                        DocumentsView()
                    } label: {
                        Label("Documents and uploads", systemImage: "tray.and.arrow.up")
                    }
                }
            }
            Section {
                Button {
                    picking = true
                } label: {
                    Label(poh.index == nil ? "Choose a POH PDF from Files" : "Replace with a POH PDF from Files", systemImage: "folder")
                }
                .disabled(poh.isBuilding)
            }
        }
        .navigationTitle("PROCEDURES")
        .task { await poh.syncFromUploads(cloud: cloud) }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                Task { await poh.installFromFiles(url) }
            }
        }
    }

    private func firstPage(of prefix: String, in index: POHIndex) -> Int {
        index.pages.first { $0.section.hasPrefix(prefix) }?.pdfPage ?? 1
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
    var document: POHIndex.DocumentInfo?
    var highlight: String = ""
    @EnvironmentObject private var poh: POHRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AuthorityBadge(authority: document?.authority ?? .approved)
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
            if let url = document.flatMap({ poh.pdfURL(for: $0) }) ?? poh.pdfURL {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        POHPDFScreen(url: url, pdfPage: page.pdfPage, title: "\(document?.authority == .manufacturer ? "Page" : "POH") \(page.label)")
                    } label: {
                        Label("Open Page", systemImage: "doc.richtext")
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
    @AppStorage("EM.pdfNightMode") private var nightMode = false

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
