import Foundation

/// What the app knows about the owner's aircraft. Built from the aircraft profile the owner enters;
/// nothing about any specific aircraft is bundled with the app.
enum AircraftKnowledge {
    struct Fact: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let value: String
        let source: String
    }

    private static var profile: AircraftProfile { AircraftProfileSnapshot.shared.profile }

    static var facts: [Fact] {
        let p = profile
        var out: [Fact] = [Fact(label: "Aircraft", value: p.displayName, source: "Aircraft profile")]
        if !p.serialNumber.isEmpty { out.append(Fact(label: "Serial number", value: p.serialNumber, source: "Aircraft profile")) }
        let induction = p.isTurbocharged ? "turbocharged/turbonormalized" : "normally aspirated"
        out.append(Fact(label: "Engine", value: "\(p.engineModel.isEmpty ? "Not entered" : p.engineModel), \(p.cylinders) cylinders, \(induction)", source: "Aircraft profile"))
        if !p.propeller.isEmpty { out.append(Fact(label: "Propeller", value: p.propeller, source: "Aircraft profile")) }
        out.append(Fact(label: "Engine monitor", value: p.monitor.rawValue, source: "Aircraft profile"))
        if !p.homeAirport.isEmpty { out.append(Fact(label: "Home airport", value: p.homeAirport, source: "Aircraft profile")) }
        out.append(Fact(label: "Oil changes", value: "Every \(Int(p.oilChangeIntervalHours)) hours", source: "Aircraft profile"))
        out.append(Fact(label: "Limits", value: p.limitsConfirmedByOwner ? "Confirmed by owner (\(p.limits.limitsSource))" : "Template values - confirm against your POH/AFM",
                        source: "Aircraft profile"))
        return out
    }

    // MARK: - Engine limits and references

    /// A limit or reference value the post-flight report checks recorded data against.
    struct EngineLimit: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable { case warning = "WARNING", caution = "CAUTION", reference = "REFERENCE" }
        let id: String
        let metric: FlightMetric
        let label: String
        let low: Double?
        let high: Double?
        let kind: Kind
        /// Only applies while the engine RPM is above this value (nil = whenever the engine runs).
        let minRPM: Double?
        /// Only applies in these phases (empty = all phases with the engine running).
        let phases: Set<FlightPhase>
        let authority: SourceAuthority
        let source: String
        /// Only counted when continuously outside for at least this many seconds (as the annunciation logic does).
        var minDuration: Int = 1
        /// Ignored for this many seconds after the engine starts (oil pressure may take 30 s to show, POH 4-10).
        var startGrace: Int = 0
    }

    /// Limits and technique references checked after every flight, from the aircraft profile.
    static var limits: [EngineLimit] { profile.engineLimits() }

    /// The owner's cruise TIT target (hotter TIT). Pilot reference only, never an approved limit. NaN when not set.
    static var cruiseTITTarget: Double { profile.limits.cruiseTITTarget ?? .nan }
    static let cruiseTITTargetSource = "Owner's cruise TIT target from the aircraft profile; not an approved limit"

    // MARK: - Oil analysis

    struct OilSample: Identifiable, Hashable {
        var id: String { date }
        let date: String
        let iron, copper, nickel, chromium, aluminum, silicon: Double
    }

    /// Oil analysis results. Entered or imported by the owner (coming in a later version).
    static let oilSamples: [OilSample] = []

    /// General machinery alert guide (ppm). Not an engine-manufacturer limit.
    static let oilAlertGuide: [String: Double] = ["Iron": 100, "Copper": 15, "Nickel": 5, "Chromium": 10, "Aluminum": 20, "Silicon": 25]

    // MARK: - Maintenance watch list (to confirm with the shop)

    struct WatchItem: Identifiable, Hashable {
        var id: String { item }
        let item: String
        let detail: String
        let source: String
    }

    /// Open questions from the aircraft's records. Filled from the owner's records in a later version.
    static let watchList: [WatchItem] = []

    // MARK: - Online resources (need internet; not available in flight)

    struct Resource: Identifiable, Hashable {
        var id: String { url }
        let title: String
        let detail: String
        let url: String
        let authority: SourceAuthority
    }

    /// Cirrus owner resources; shown only when the profile is a Cirrus.
    static var onlineResources: [Resource] { profile.isCirrus ? cirrusResources : [] }

    private static let cirrusResources: [Resource] = [
        Resource(title: "COPA.fyi", detail: "COPA's Cirrus training workbook: Cirrus documents, avionics guides, FAA publications", url: "https://www.copa.fyi", authority: .experience),
        Resource(title: "COPA Commander", detail: "COPA's AI assistant on Cirrus documentation (members unlimited; 3 free questions a day)", url: "https://commander.copa.fyi", authority: .experience),
        Resource(title: "Ask COPA U", detail: "Answers from COPA instructors and experts (COPA membership)", url: "https://answers.copa.fyi", authority: .experience),
        Resource(title: "COPA forum", detail: "Owner and pilot discussions", url: "https://forum.cirruspilots.org", authority: .experience),
        Resource(title: "Cirrus Tech Pubs", detail: "Cirrus manuals, service information and POH revisions", url: "https://techpubs.cirrusaircraft.com/tech/pubs", authority: .manufacturer),
    ]

    /// A ready-to-paste question for COPA Commander, built from a finding.
    static func copaQuestion(about topic: String, details: String) -> String {
        let p = profile
        let induction = p.isTurbocharged ? "turbocharged/turbonormalized" : "normally aspirated"
        return "\(p.year > 0 ? "\(p.year) " : "")\(p.make) \(p.model), \(p.engineModel) (\(induction)), \(p.monitor.rawValue). \(topic). \(details) What should I check, and which documents apply?"
    }
}
