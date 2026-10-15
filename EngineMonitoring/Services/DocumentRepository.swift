import Foundation

@MainActor
final class DocumentRepository: ObservableObject {
    @Published private(set) var documents: [KnowledgeDocument] = []
    /// Set when the bundled catalog cannot be read, so the library shows why it is empty.
    @Published private(set) var loadError: String?

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        load()
    }

    func load() {
        guard let url = bundle.url(forResource: "documents", withExtension: "json") else {
            loadError = "documents.json is missing from this build."
            documents = []
            return
        }
        do {
            documents = try Self.decodeCatalog(Data(contentsOf: url))
            loadError = nil
        } catch {
            loadError = "The document catalog could not be read: \(error.localizedDescription)"
            documents = []
        }
    }

    nonisolated static func decodeCatalog(_ data: Data) throws -> [KnowledgeDocument] {
        try JSONDecoder().decode([KnowledgeDocument].self, from: data)
    }

    func documents(category: String) -> [KnowledgeDocument] {
        documents.filter { $0.category == category }
    }

    func localURL(for document: KnowledgeDocument) -> URL? {
        Self.resourceURL(named: document.bundledFilename, in: bundle)
    }

    /// Catalog entries whose bundled file is missing from the app bundle.
    func missingDocuments() -> [KnowledgeDocument] {
        documents.filter { $0.bundledFilename != nil && localURL(for: $0) == nil }
    }

    /// Resolves "Name.v3.pdf" correctly by splitting on the LAST dot.
    nonisolated static func resourceURL(named filename: String?, in bundle: Bundle) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        let ext = (filename as NSString).pathExtension
        let name = (filename as NSString).deletingPathExtension
        guard !ext.isEmpty, !name.isEmpty else { return nil }
        return bundle.url(forResource: name, withExtension: ext)
    }
}
