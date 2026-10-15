import Foundation

/// What the app knows about N63KA, compiled from the SharePoint records (Cirrus folder) on 2026-10-06.
/// Every item names its source. Update this file when records change.
enum AircraftKnowledge {
    static let compiledOn = "2026-10-06"

    struct Fact: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let value: String
        let source: String
    }

    static let facts: [Fact] = [
        Fact(label: "Airframe", value: "2009 Cirrus SR22 G3, S/N 3444 (22-3444), mfd 21 May 2009", source: "Status sheet, Nov 2025"),
        Fact(label: "Engine", value: "Continental IO-550-N, Tornado Alley turbonormalizer (TAT IO-550-N60), S/N 692204", source: "Status sheet; AD record"),
        Fact(label: "Engine history", value: "Overhauled 12 Mar 2022; reinstalled 11 Apr 2022 and 28 Apr 2023", source: "Oil Analysis (2).xlsx notes"),
        Fact(label: "Propeller", value: "Hartzell PHC-J3Y1F-1N; S/N NJ91B (status sheet) vs NJ97B (AD record) - check data plate", source: "Status sheet; AD record"),
        Fact(label: "Avionics", value: "Cirrus Perspective, system software 0764.38, system ID 2157B6FAB; GFC 700", source: "airframe_info.xml"),
        Fact(label: "Hours (Nov 2025)", value: "1,940.3; annual/100-hr 1,884.3 (10 Jan 2025); 50-hr 1,912.2 (18 Jun 2025)", source: "Status sheet"),
        Fact(label: "Oil", value: "Phillips XC 20W-50, 8 qt, about 25-hour changes", source: "Blackstone report Nov 2025"),
        Fact(label: "CAPS", value: "Rocket and parachute due 31 Jul 2028; reefing line cutters were due 31 Mar 2026", source: "Status sheet"),
        Fact(label: "POH on file", value: "SR22 POH 13772-002 Reissue A (Perspective). Tornado Alley AFM supplement NOT on file", source: "POH.pdf"),
    ]

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

    /// APPROVED values come from POH Section 2 (basic SR22). Turbonormalizer-specific limits
    /// (TIT, manifold pressure) need the Tornado Alley AFM supplement and are not included.
    static let limits: [EngineLimit] = [
        // POH 2-8: Engine Speed Warning when RPM is 2,710-2,730 for more than 10 s, or above 2,730 for more than 5 s.
        EngineLimit(id: "rpm-max", metric: .rpm, label: "Engine speed above 2,710 RPM for more than 10 s", low: nil, high: 2710, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-8", minDuration: 11),
        EngineLimit(id: "rpm-overspeed", metric: .rpm, label: "Engine speed above 2,730 RPM for more than 5 s", low: nil, high: 2730, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-8", minDuration: 6),
        EngineLimit(id: "oilt-max", metric: .oilTemp, label: "Oil temperature above 240 °F", low: nil, high: 240, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-6 / 2-8"),
        EngineLimit(id: "oilp-max", metric: .oilPressure, label: "Oil pressure above 100 psi", low: nil, high: 100, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-8"),
        EngineLimit(id: "oilp-min", metric: .oilPressure, label: "Oil pressure below 10 psi", low: 10, high: nil, kind: .warning,
                    minRPM: 1000, phases: [], authority: .approved, source: "POH 2-8", minDuration: 2, startGrace: 30),
        EngineLimit(id: "oilp-caution", metric: .oilPressure, label: "Oil pressure 10-29 psi above 1,000 RPM in flight", low: 30, high: nil, kind: .caution,
                    minRPM: 1000, phases: [.climb, .cruise, .descent], authority: .approved, source: "POH 2-8 / 3A-6", minDuration: 2, startGrace: 30),
        // Same annunciation on the ground: POH 3A-6 Low Idle Oil Pressure (usually hot oil at about 1,000 RPM idle).
        EngineLimit(id: "oilp-idle", metric: .oilPressure, label: "Oil pressure 10-29 psi above 1,000 RPM on the ground (OIL PRESS caution)", low: 30, high: nil, kind: .caution,
                    minRPM: 1000, phases: [.ground], authority: .approved, source: "POH 2-8 / 3A-6", minDuration: 5, startGrace: 30),
        EngineLimit(id: "cht-warning", metric: .chtMax, label: "CHT above 460 °F", low: nil, high: 460, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-8"),
        EngineLimit(id: "cht-caution", metric: .chtMax, label: "CHT above 420 °F", low: nil, high: 420, kind: .caution,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-8"),
        // POH 2-9 electrical markings: main bus 24.5-32 V normal; 0-24.4 caution (M BUS), above 32 warning.
        // Checked in flight only (alternators are OFF for the start, POH 4-10), for 10 s or more.
        EngineLimit(id: "volt1-low", metric: .volt1, label: "Bus 1 voltage below 24.5 V in flight (M BUS 1 caution range)", low: 24.5, high: nil, kind: .caution,
                    minRPM: 1500, phases: [.climb, .cruise, .descent], authority: .approved, source: "POH 2-9", minDuration: 10),
        EngineLimit(id: "volt2-low", metric: .volt2, label: "Bus 2 voltage below 24.5 V in flight (M BUS 2 caution range)", low: 24.5, high: nil, kind: .caution,
                    minRPM: 1500, phases: [.climb, .cruise, .descent], authority: .approved, source: "POH 2-9", minDuration: 10),
        EngineLimit(id: "volt1-high", metric: .volt1, label: "Bus 1 voltage above 32 V (M BUS 1 warning range)", low: nil, high: 32, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-9", minDuration: 3),
        EngineLimit(id: "volt2-high", metric: .volt2, label: "Bus 2 voltage above 32 V (M BUS 2 warning range)", low: nil, high: 32, kind: .warning,
                    minRPM: nil, phases: [], authority: .approved, source: "POH 2-9", minDuration: 3),
        // Technique references (Jim Barker flight profile, A&P/IA). Not approved limits.
        EngineLimit(id: "barker-cht", metric: .chtMax, label: "CHT above 370 °F in climb (technique: add airspeed or boost pump HIGH)", low: nil, high: 370, kind: .reference,
                    minRPM: 2000, phases: [.climb], authority: .experience, source: "Barker flight profile 2023"),
        EngineLimit(id: "barker-tit", metric: .tit, label: "Hotter TIT above 1,325 °F in climb (technique: enrich or add airspeed)", low: nil, high: 1325, kind: .reference,
                    minRPM: 2000, phases: [.climb], authority: .experience, source: "Barker flight profile 2023"),
    ]

    /// Wayne's cruise TIT target (hotter of TIT 1 and 2). Pilot reference only: the basic POH has no TIT values;
    /// confirm against the Tornado Alley AFM supplement when it is on file.
    static let cruiseTITTarget = 1575.0
    static let cruiseTITTargetSource = "Pilot target; not in the POH (needs the Tornado Alley AFM supplement)"

    // MARK: - Oil analysis

    struct OilSample: Identifiable, Hashable {
        var id: String { date }
        let date: String
        let iron, copper, nickel, chromium, aluminum, silicon: Double
    }

    /// Blackstone results from Records/Oil Analysis (2).xlsx (ppm).
    static let oilSamples: [OilSample] = [
        OilSample(date: "2024-06-30", iron: 16, copper: 3, nickel: 2, chromium: 2, aluminum: 2, silicon: 7),
        OilSample(date: "2024-09-16", iron: 18, copper: 3, nickel: 3, chromium: 2, aluminum: 2, silicon: 5),
        OilSample(date: "2025-01-02", iron: 17, copper: 2, nickel: 3, chromium: 3, aluminum: 2, silicon: 5),
        OilSample(date: "2025-06-17", iron: 17, copper: 2, nickel: 4, chromium: 3, aluminum: 2, silicon: 4),
        OilSample(date: "2025-11-14", iron: 20, copper: 2, nickel: 5, chromium: 3, aluminum: 3, silicon: 4),
        OilSample(date: "2026-04-28", iron: 22, copper: 3, nickel: 11, chromium: 5, aluminum: 3, silicon: 3),
        OilSample(date: "2026-08-25", iron: 22, copper: 3, nickel: 6, chromium: 4, aluminum: 2, silicon: 3),
    ]

    /// "General machinery alert limits" row of the same spreadsheet (ppm).
    static let oilAlertGuide: [String: Double] = ["Iron": 100, "Copper": 15, "Nickel": 5, "Chromium": 10, "Aluminum": 20, "Silicon": 25]

    // MARK: - Maintenance watch list (to confirm with the shop)

    struct WatchItem: Identifiable, Hashable {
        var id: String { item }
        let item: String
        let detail: String
        let source: String
    }

    static let watchList: [WatchItem] = [
        WatchItem(item: "Oil analysis nickel", detail: "11 ppm in Apr 2026 (alert guide 5), 6 in Aug 2026; iron 16 to 22 since 2024", source: "Oil Analysis (2).xlsx"),
        WatchItem(item: "Tornado Alley AFM supplement", detail: "Not in POH.pdf; needed for approved TIT and MAP limits", source: "POH.pdf"),
        WatchItem(item: "Fuel injector nozzles inspect/clean", detail: "Shown 35 hr past due on Nov 2025 status sheet", source: "Status sheet"),
        WatchItem(item: "TAT flexible turbo lines", detail: "120-month replacement shown past due on Nov 2025 status sheet", source: "Status sheet"),
        WatchItem(item: "Magneto pressurization filter", detail: "Shown past due on Nov 2025 status sheet", source: "Status sheet"),
        WatchItem(item: "Turbo wastegate oil leak; prop governor leak", detail: "Prebuy discrepancies, Nov 2025", source: "Pre Buy Discrepancy List"),
        WatchItem(item: "CAPS reefing line cutters", detail: "Due 31 Mar 2026; install record PDF exists - confirm logbook entry", source: "Status sheet"),
        WatchItem(item: "Propeller serial", detail: "NJ91B vs NJ97B between documents", source: "Status sheet; AD record"),
    ]

    // MARK: - Online resources (need internet; not available in flight)

    struct Resource: Identifiable, Hashable {
        var id: String { url }
        let title: String
        let detail: String
        let url: String
        let authority: SourceAuthority
    }

    static let onlineResources: [Resource] = [
        Resource(title: "COPA.fyi", detail: "COPA's Cirrus training workbook: Cirrus documents, avionics guides, FAA publications", url: "https://www.copa.fyi", authority: .experience),
        Resource(title: "COPA Commander", detail: "COPA's AI assistant on Cirrus documentation (members unlimited; 3 free questions a day)", url: "https://commander.copa.fyi", authority: .experience),
        Resource(title: "Ask COPA U", detail: "Answers from COPA instructors and experts (COPA membership)", url: "https://answers.copa.fyi", authority: .experience),
        Resource(title: "COPA forum", detail: "Owner and pilot discussions", url: "https://forum.cirruspilots.org", authority: .experience),
        Resource(title: "Cirrus Tech Pubs", detail: "Cirrus manuals, service information and POH revisions", url: "https://techpubs.cirrusaircraft.com/tech/pubs", authority: .manufacturer),
    ]

    /// A ready-to-paste question for COPA Commander, built from a finding.
    static func copaQuestion(about topic: String, details: String) -> String {
        "Cirrus SR22 G3 Perspective, 2009, Continental IO-550-N with Tornado Alley turbonormalizer, GFC 700. \(topic). \(details) What should I check, and which Cirrus or Tornado Alley documents apply?"
    }
}
