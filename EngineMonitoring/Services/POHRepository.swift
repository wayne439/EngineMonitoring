import Foundation

@MainActor
final class POHRepository: ObservableObject {
    @Published private(set) var index: POHIndex?
    @Published private(set) var loadError: String?

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        Task { await load() }
    }

    func load() async {
        guard let url = bundle.url(forResource: "poh_index", withExtension: "json") else {
            loadError = "poh_index.json is missing from this build."
            return
        }
        do {
            index = try await Task.detached(priority: .userInitiated) {
                try POHIndex.decode(Data(contentsOf: url))
            }.value
        } catch {
            loadError = "The POH index could not be read: \(error.localizedDescription)"
        }
    }

    /// POH.pdf, if it has been added to the app bundle (Resources/PDFs). Optional: the text index works without it.
    var pdfURL: URL? {
        guard let name = index?.document.filename else { return bundle.url(forResource: "POH", withExtension: "pdf") }
        return DocumentRepository.resourceURL(named: name, in: bundle)
    }

    func search(_ query: String) -> [POHSearch.Hit] {
        guard let index else { return [] }
        return POHSearch.search(query, in: index)
    }
}
