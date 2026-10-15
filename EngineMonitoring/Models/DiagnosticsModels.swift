import Foundation

enum DiagnosticSystem: String, CaseIterable, Identifiable, Codable {
    case engineStart = "Engine / Start"
    case autopilot = "GFC 700 / Autopilot"
    case electrical = "Electrical / Bus"
    case avionics = "Avionics / Navigation"
    case engine = "Engine / In Flight"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .engineStart: return "engine.combustion"
        case .autopilot: return "airplane.circle"
        case .electrical: return "bolt.circle"
        case .avionics: return "dot.radiowaves.left.and.right"
        case .engine: return "waveform.path.ecg"
        case .other: return "questionmark.circle"
        }
    }

    /// What the app looks at for this system once a Perspective log is attached.
    var evaluationSummary: String {
        switch self {
        case .engineStart:
            return "Start sequence: RPM establishment, fuel flow, EGT response, bus voltage and current during cranking."
        case .autopilot:
            return "AFCS engaged state, active roll/pitch modes and bus voltage around the event. Internal GFC 700 faults are not in the Perspective log."
        case .electrical:
            return "Bus 1 and bus 2 voltage and alternator current around the event."
        case .avionics:
            return "GPS fix state and bus voltage around the event. Most avionics faults need maintenance-level data."
        case .engine:
            return "RPM, manifold pressure, fuel flow, oil pressure/temperature, CHT and EGT around the event."
        case .other:
            return "Recorded symptoms and the logged values around the event time."
        }
    }
}

enum DiagnosticConfidence: String, Codable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case insufficient = "INSUFFICIENT DATA"
}

struct DiagnosticEvent: Identifiable, Codable, Hashable {
    let id: UUID
    /// The instant the pilot tapped "Something Happened". Captured before any details are entered.
    let timestamp: Date
    /// Device time-zone offset from UTC, in seconds, at the moment of capture.
    let utcOffsetSeconds: Int
    /// Device time-zone identifier at capture, e.g. "America/Phoenix".
    let timeZoneIdentifier: String
    var system: DiagnosticSystem
    var note: String
    /// Filename (within the app's log store) of the Perspective log attached to this event.
    var flightLogFilename: String?
    /// False until the pilot has added details after the quick marker.
    var detailsEntered: Bool

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         timeZone: TimeZone = .current,
         system: DiagnosticSystem = .other,
         note: String = "",
         flightLogFilename: String? = nil,
         detailsEntered: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.utcOffsetSeconds = timeZone.secondsFromGMT(for: timestamp)
        self.timeZoneIdentifier = timeZone.identifier
        self.system = system
        self.note = note
        self.flightLogFilename = flightLogFilename
        self.detailsEntered = detailsEntered
    }

    // v1 events (UserDefaults, v0.2 build) had no offset/time zone/details fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        utcOffsetSeconds = try c.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)
            ?? TimeZone.current.secondsFromGMT(for: timestamp)
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? TimeZone.current.identifier
        system = try c.decodeIfPresent(DiagnosticSystem.self, forKey: .system) ?? .other
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        flightLogFilename = try c.decodeIfPresent(String.self, forKey: .flightLogFilename)
        detailsEntered = try c.decodeIfPresent(Bool.self, forKey: .detailsEntered) ?? true
    }

    /// The capture time-zone, falling back to a fixed offset if the identifier is unknown.
    var captureTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
    }
}

/// One measured fact taken from recorded data or from the pilot's own entry.
struct EvidenceItem: Hashable {
    let label: String
    let value: String
}

struct DiagnosticFinding: Hashable {
    let title: String
    let confidence: DiagnosticConfidence
    /// Recorded facts only. Never conclusions.
    let evidence: [EvidenceItem]
    /// Hypotheses to investigate. Not proven by the evidence above.
    let possibleCauses: [String]
    let nextChecks: [String]
    let limitations: String
    /// The log the evidence came from, if any.
    let dataSource: String?
}
