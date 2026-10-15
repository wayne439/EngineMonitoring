import SwiftUI
import UIKit
import PDFKit

/// Makes the one-page kneeboard PDFs on the iPad from the approach cards (approach_cards.json),
/// so the PDFs always match the in-app cards. Replaces the old bundled one-page PDFs.
enum KneeboardPDF {
    /// Half-letter (5.5 x 8.5 in) portrait, kneeboard size. Prints two-up or full page.
    static let pageSize = CGSize(width: 396, height: 612)
    static let margin: CGFloat = 18

    /// PDF data for one card, or several cards one after another (each starts on a new page).
    @MainActor
    static func render(_ cards: [ApproachCard], mode: FlyingMode) -> Data? {
        let htmls = cards.compactMap { ApproachPrinter.quickHTML($0, mode: mode) }
        guard !htmls.isEmpty else { return nil }
        let page = CGRect(origin: .zero, size: pageSize)
        let renderer = UIPrintPageRenderer()
        // Page size must be set before the formatters are added, so the page count is right.
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page, forKey: "printableRect")
        for html in htmls {
            let formatter = UIMarkupTextPrintFormatter(markupText: html)
            formatter.perPageContentInsets = UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
            renderer.addPrintFormatter(formatter, startingAtPageAt: renderer.numberOfPages)
        }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, [kCGPDFContextTitle as String: "Kneeboard cards",
                                                     kCGPDFContextAuthor as String: "EngineAI"])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data.length > 0 ? data as Data : nil
    }

    /// Writes the PDF to a temporary file with a readable name, for sharing / saving to Files.
    static func file(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// FLY section: one-page kneeboard PDFs made from the approach cards.
struct KneeboardPDFSection: View {
    @EnvironmentObject private var guides: ApproachGuideStore

    var body: some View {
        Section {
            if let book = guides.book {
                NavigationLink {
                    KneeboardPDFScreen(cards: book.cards, title: "All Approach Cards")
                } label: {
                    Label("All approach cards (one PDF)", systemImage: "doc.on.doc.fill").font(.headline)
                }
                ForEach(book.cards) { card in
                    NavigationLink {
                        KneeboardPDFScreen(cards: [card], title: card.title)
                    } label: {
                        Label(card.title, systemImage: "doc.richtext")
                    }
                }
            } else if let error = guides.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        } header: {
            Text("One-Page Kneeboard Cards (PDF)")
        } footer: {
            Text("Made on the iPad from the approach cards above, so they always match. Share to save in Files or print. Training aids: charts, the POH and approved supplements control.")
        }
    }
}

struct KneeboardPDFScreen: View {
    let cards: [ApproachCard]
    let title: String
    @State private var mode: FlyingMode = .autopilot
    @State private var data: Data?
    @State private var fileURL: URL?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Flying", selection: $mode) {
                ForEach(FlyingMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            if let data {
                PDFDataViewer(data: data)
            } else if failed {
                ContentUnavailableView("PDF could not be made", systemImage: "doc.questionmark",
                                       description: Text("Use the printer button on the approach card instead."))
            } else {
                ProgressView("Making PDF…").frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let fileURL {
                    ShareLink(item: fileURL) { Label("Share or Save PDF", systemImage: "square.and.arrow.up") }
                }
                if let data {
                    Button {
                        let controller = UIPrintInteractionController.shared
                        let info = UIPrintInfo(dictionary: nil)
                        info.jobName = "\(title) \(mode.rawValue)"
                        controller.printInfo = info
                        controller.printingItem = data
                        controller.present(animated: true)
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                }
            }
        }
        .task(id: mode) { make() }
    }

    private func make() {
        data = nil
        fileURL = nil
        guard let pdf = KneeboardPDF.render(cards, mode: mode) else { failed = true; return }
        failed = false
        data = pdf
        let base = cards.count == 1 ? cards[0].id : "all"
        fileURL = KneeboardPDF.file(pdf, name: "Card_\(base)_\(mode == .autopilot ? "autopilot" : "handflown").pdf")
    }
}

/// PDFKit view for PDF data made in memory.
struct PDFDataViewer: UIViewRepresentable {
    let data: Data

    final class Coordinator { var shown: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(data: data)
        context.coordinator.shown = data
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.shown != data else { return }
        view.document = PDFDocument(data: data)
        view.autoScales = true
        context.coordinator.shown = data
    }
}
