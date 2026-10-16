import SwiftUI

/// FAA airworthiness directives published in the Federal Register that mention this aircraft's
/// model, engine or propeller. A starting list to review with the A&P, not a compliance record.
struct AirworthinessDirective: Identifiable, Hashable, Sendable {
    var id: String { documentNumber }
    let documentNumber: String
    let title: String
    let abstract: String
    let published: String
    let url: URL
    /// What it matched: "Airframe (SR22)", "Engine (IO-550)", "Propeller (...)".
    var matches: [String]
    var isCorrection: Bool { title.lowercased().contains("correction") || abstract.lowercased().hasPrefix("this document corrects") }
}

enum ADLookup {
    struct Term: Hashable {
        let label: String
        let query: String
    }

    /// Search terms for the profile: the model designation, the engine family and the propeller.
    static func terms(for p: AircraftProfile) -> [Term] {
        var out: [Term] = []
        if let m = p.model.split(separator: " ").first.map(String.init), m.count >= 2 {
            out.append(Term(label: "Airframe (\(m))", query: "\"\(m)\""))
        }
        // "Continental IO-550-N" -> "IO-550": ADs usually name the engine family.
        if let r = p.engineModel.range(of: #"[A-Z]{1,5}-\d{3}"#, options: .regularExpression) {
            let family = String(p.engineModel[r])
            out.append(Term(label: "Engine (\(family))", query: "\"\(family)\""))
        }
        let prop = p.propeller.trimmingCharacters(in: .whitespaces)
        if let r = prop.range(of: #"[A-Z0-9]{2,}[-A-Z0-9]*"#, options: .regularExpression) {
            let model = String(prop[r])
            out.append(Term(label: "Propeller (\(model))", query: "\"\(model)\""))
        }
        return out
    }

    static func search(_ terms: [Term]) async throws -> [AirworthinessDirective] {
        var byNumber: [String: AirworthinessDirective] = [:]
        for term in terms {
            var c = URLComponents(string: "https://www.federalregister.gov/api/v1/documents.json")!
            c.queryItems = [
                URLQueryItem(name: "conditions[term]", value: term.query),
                URLQueryItem(name: "conditions[agencies][]", value: "federal-aviation-administration"),
                URLQueryItem(name: "conditions[type][]", value: "RULE"),
                URLQueryItem(name: "order", value: "newest"),
                URLQueryItem(name: "per_page", value: "100"),
            ]
            let (data, response) = try await URLSession.shared.data(from: c.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            for row in root?["results"] as? [[String: Any]] ?? [] {
                guard let number = row["document_number"] as? String, let title = row["title"] as? String,
                      title.hasPrefix("Airworthiness Directives"),
                      let link = (row["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
                if byNumber[number] != nil {
                    byNumber[number]?.matches.append(term.label)
                } else {
                    byNumber[number] = AirworthinessDirective(
                        documentNumber: number, title: title, abstract: row["abstract"] as? String ?? "",
                        published: row["publication_date"] as? String ?? "", url: link, matches: [term.label])
                }
            }
        }
        return byNumber.values.sorted { $0.published > $1.published }
    }
}

struct ADCheckView: View {
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @State private var results: [AirworthinessDirective] = []
    @State private var loading = false
    @State private var error: String?
    @State private var checkedAt: Date?
    @State private var showCorrections = false
    @AppStorage("EM.adReviewed") private var reviewedRaw = ""

    private var reviewed: Set<String> { Set(reviewedRaw.split(separator: ",").map(String.init)) }
    private var terms: [ADLookup.Term] { ADLookup.terms(for: aircraft.profile) }
    private var shown: [AirworthinessDirective] { results.filter { showCorrections || !$0.isCorrection } }

    var body: some View {
        List {
            Section {
                if terms.isEmpty {
                    Label("Add your model and engine in Aircraft Profile first.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                } else {
                    Text("Searching for: " + terms.map(\.label).joined(separator: ", "))
                        .font(.subheadline)
                    Button {
                        Task { await run() }
                    } label: {
                        if loading {
                            HStack { ProgressView(); Text("Checking the Federal Register…") }
                        } else {
                            Label(results.isEmpty ? "Check for ADs" : "Check again", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(loading)
                    if let checkedAt {
                        Text("\(shown.count) ADs found, \(shown.filter { reviewed.contains($0.id) }.count) reviewed. Checked \(checkedAt.formatted(date: .omitted, time: .shortened)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            } header: {
                Text("Airworthiness Directives")
            } footer: {
                Text("ADs are mandatory. Whether each one applies depends on your serial numbers and installed equipment, and your logbooks show whether it has been complied with. Review this list with your A&P or IA.")
            }

            if !results.isEmpty {
                Section {
                    Toggle("Show correction notices", isOn: $showCorrections)
                }
                Section("Results, newest first") {
                    ForEach(shown) { ad in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(ad.title.replacingOccurrences(of: "Airworthiness Directives; ", with: ""))
                                    .font(.headline)
                                Spacer()
                                if reviewed.contains(ad.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            Text("Published \(ad.published) · matches \(ad.matches.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                            if !ad.abstract.isEmpty {
                                Text(ad.abstract).font(.caption).lineLimit(4)
                            }
                            HStack {
                                Link("Read the AD", destination: ad.url).font(.caption.bold())
                                Spacer()
                                Button(reviewed.contains(ad.id) ? "Reviewed" : "Mark reviewed with A&P") {
                                    toggleReviewed(ad.id)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Link(destination: URL(string: "https://drs.faa.gov")!) {
                    Label("FAA Dynamic Regulatory System (official AD search)", systemImage: "globe")
                }
                if aircraft.profile.isCirrus {
                    Link(destination: URL(string: "https://www.cirrusaircraft.com/")!) {
                        Label("Cirrus service bulletins (Cirrus owner account)", systemImage: "globe")
                    }
                }
            } header: {
                Text("Service Bulletins and Official Sources")
            } footer: {
                Text("This search covers ADs published in the Federal Register since 1994; the FAA's DRS is the official source. Service bulletins come from the manufacturer and are required for Part 91 owners only when an AD calls for them. Upload your AD compliance record and any SB list under Documents and uploads (Logbook entries).")
            }
        }
        .navigationTitle("AD Check")
        .task { if results.isEmpty && !terms.isEmpty { await run() } }
    }

    private func run() async {
        loading = true
        defer { loading = false }
        do {
            results = try await ADLookup.search(terms)
            checkedAt = Date()
            error = nil
        } catch {
            self.error = "Could not reach the Federal Register: \(error.localizedDescription)"
        }
    }

    private func toggleReviewed(_ id: String) {
        var set = reviewed
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        reviewedRaw = set.sorted().joined(separator: ",")
    }
}
