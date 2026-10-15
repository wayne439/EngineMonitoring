import SwiftUI

struct DocumentList: View {
    let title: String
    let documents: [KnowledgeDocument]
    @EnvironmentObject private var repository: DocumentRepository

    var body: some View {
        List {
            if let error = repository.loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            } else if documents.isEmpty {
                Text("No documents in this category.").foregroundStyle(.secondary)
            }
            ForEach(documents) { doc in
                // Destination-based link: a value-based link (NavigationLink(value:) + navigationDestination)
                // inside a screen that was itself pushed by a destination link does nothing when tapped in the
                // NavigationSplitView detail column. That was the "cards won't open" bug.
                NavigationLink {
                    PDFDocumentScreen(document: doc)
                } label: {
                    DocumentRow(document: doc)
                }
            }
        }
        .navigationTitle(title)
    }
}

struct DocumentRow: View {
    let document: KnowledgeDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(document.title).font(.headline)
            Text(document.subtitle).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                AuthorityBadge(authority: document.authority)
                if let revision = document.revision {
                    Text("Rev \(revision)").font(.caption).foregroundStyle(.secondary)
                }
                if document.isCockpitCritical {
                    Image(systemName: "airplane").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Cockpit reference")
                }
            }
            if document.needsVerification() {
                Label(document.isReviewOverdue() ? "Review overdue" : "Not yet verified by an instructor",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlyView: View {

    var body: some View {
        List {
            ApproachGuideSection()
            KneeboardPDFSection()
            Section("Emergency") {
                NavigationLink {
                    ProceduresView()
                } label: {
                    Label("POH Emergency and Abnormal Procedures", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                }
            }
            Section("Rule") {
                Text("Buttons are requests; the Flight Mode Annunciator is the answer.")
                    .font(.headline)
            }
            Section {
                Text("Training aids only. Current charts, NOTAMs, the N63KA AFM/POH and approved supplements control.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("FLY")
    }
}
