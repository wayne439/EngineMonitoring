import SwiftUI
import PDFKit

struct PDFViewer: UIViewRepresentable {
    let url: URL
    /// 1-based page to show first.
    var initialPage: Int? = nil

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        let document = PDFDocument(url: url)
        view.document = document
        if let initialPage, let page = document?.page(at: max(0, initialPage - 1)) {
            // Wait one layout pass; PDFView ignores go(to:) before it has a size.
            DispatchQueue.main.async { view.go(to: page) }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Reload if SwiftUI reuses this view for a different document.
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

struct PDFDocumentScreen: View {
    let document: KnowledgeDocument
    @EnvironmentObject private var repository: DocumentRepository
    /// Inverts page colors for night use. Stored per device.
    @AppStorage("EM.pdfNightMode") private var nightMode = false
    @State private var showingInfo = false

    var body: some View {
        Group {
            if let url = repository.localURL(for: document) {
                PDFViewer(url: url)
                    .invertedColors(if: nightMode)
                    .background(nightMode ? Color.black : Color(.systemBackground))
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("Document unavailable", systemImage: "doc.questionmark",
                                       description: Text("This document is not bundled in this build."))
            }
        }
        .safeAreaInset(edge: .top) {
            if document.authority != .approved {
                Text(document.authority.explanation)
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(.thinMaterial)
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    nightMode.toggle()
                } label: {
                    Label(nightMode ? "Day Mode" : "Night Mode", systemImage: nightMode ? "sun.max" : "moon")
                }
                Button {
                    showingInfo = true
                } label: {
                    Label("Document Info", systemImage: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingInfo) { DocumentInfoSheet(document: document) }
    }
}

private extension View {
    @ViewBuilder
    func invertedColors(if enabled: Bool) -> some View {
        if enabled { self.colorInvert() } else { self }
    }
}

struct DocumentInfoSheet: View {
    let document: KnowledgeDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Source") {
                    AuthorityBadge(authority: document.authority)
                    Text(document.authority.explanation).foregroundStyle(.secondary)
                }
                Section("Revision") {
                    LabeledContent("Revision", value: document.revision ?? "Not recorded")
                    LabeledContent("Effective", value: document.effectiveDate ?? "Not recorded")
                    LabeledContent("Review due", value: document.reviewDueDate ?? "Not set")
                    LabeledContent("Verified by", value: document.reviewedBy ?? "Not yet verified")
                }
                if document.needsVerification() {
                    Section {
                        Label("This cockpit reference has not been verified, or its review is overdue.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
