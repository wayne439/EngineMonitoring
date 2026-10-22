import Foundation

/// Battery health from engine starts: how far bus 1 voltage dips while cranking, compared with this aircraft's
/// own earlier starts. A battery losing capacity sags further under the starter load long before it fails to
/// turn the engine over, so a dip that keeps getting deeper is an early sign worth a battery check.
///
/// Logs record once a second, so the lowest value is approximate (the true dip can be a little deeper).
/// Cold starts sag more; when the recent starts were much colder than the earlier ones, the comparison says so.
/// Advisory (TRAINING): a reason to have the battery checked, never a diagnosis.
struct BatteryStartPoint: Identifiable, Hashable {
    var id: Date { time }
    let time: Date
    let lowVolts: Double
    let restVolts: Double?
    let drop: Double?
    let crankSeconds: Double?
    let oat: Double?
}

struct BatteryWatchReport {
    enum Level { case noData, learning, normal, watch }

    /// Starts with a recorded cranking voltage, newest first.
    let points: [BatteryStartPoint]
    /// 12 or 24 V battery (from the resting voltage).
    let nominal: Double
    let level: Level
    /// Median lowest cranking voltage of the newest starts and of the earlier ones.
    let recentLow: Double?
    let baselineLow: Double?
    let recentDrop: Double?
    let baselineDrop: Double?
    /// Change the analysis treats as meaningful (1 V on a 24 V system, 0.5 V on 12 V).
    let threshold: Double
    let summary: String
    let notes: [String]
}

enum BatteryWatch {
    static let recent = 3
    static let baselineMax = 20
    static let baselineMin = 5

    static func analyze(_ summaries: [FlightSummary]) -> BatteryWatchReport {
        let points = summaries.flatMap { $0.starts }
            .compactMap { r -> BatteryStartPoint? in
                guard let low = r.minVolt1, low > 5 else { return nil }
                return BatteryStartPoint(time: r.time, lowVolts: low, restVolts: r.restVolt1, drop: r.voltDrop,
                                         crankSeconds: r.crankSeconds, oat: r.oat)
            }
            .sorted { $0.time > $1.time }

        let rests = points.compactMap(\.restVolts)
        let reference = median(rests) ?? median(points.map(\.lowVolts)).map { $0 + 3 }
        let nominal: Double = (reference ?? 24) > 18 ? 24 : 12
        let threshold: Double = nominal > 18 ? 1.0 : 0.5
        var notes: [String] = []
        if AircraftProfileSnapshot.shared.profile.isCirrusG7 {
            notes.append("G7: battery 1 is lithium-ion, mounted inside the instrument panel. It holds a steadier voltage than a lead-acid battery, so even a small change from its own normal is worth a look.")
        }
        notes.append("Logs record once a second, so the lowest cranking voltage is approximate.")

        guard !points.isEmpty else {
            return BatteryWatchReport(points: [], nominal: nominal, level: .noData, recentLow: nil, baselineLow: nil,
                                      recentDrop: nil, baselineDrop: nil, threshold: threshold,
                                      summary: "No engine starts with bus voltage recorded yet. Start-voltage tracking needs logs that begin before the engine is started.",
                                      notes: notes)
        }
        let newest = Array(points.prefix(recent))
        let earlier = Array(points.dropFirst(recent).prefix(baselineMax))
        let recentLow = median(newest.map(\.lowVolts))
        let recentDrop = median(newest.compactMap(\.drop))
        guard earlier.count >= baselineMin, let r = recentLow, let b = median(earlier.map(\.lowVolts)) else {
            let need = recent + baselineMin
            return BatteryWatchReport(points: points, nominal: nominal, level: .learning, recentLow: recentLow, baselineLow: nil,
                                      recentDrop: recentDrop, baselineDrop: nil, threshold: threshold,
                                      summary: "Learning this battery's normal: \(points.count) of \(need) starts recorded.",
                                      notes: notes)
        }
        let baselineDrop = median(earlier.compactMap(\.drop))
        let lower = b - r
        let deeper = (recentDrop ?? 0) - (baselineDrop ?? recentDrop ?? 0)
        let watch = lower >= threshold || deeper >= threshold

        if let ro = median(newest.compactMap(\.oat)), let bo = median(earlier.compactMap(\.oat)), bo - ro >= 10 {
            notes.insert(String(format: "The latest starts were about %.0f °C colder than the earlier ones; cold batteries dip further. Compare again on a warmer day before replacing anything.", bo - ro), at: 0)
        }
        let summary: String
        if watch {
            let dropText = deeper >= threshold ? String(format: " (drop %.1f V vs %.1f V)", recentDrop ?? 0, baselineDrop ?? 0) : ""
            summary = String(format: "Cranking voltage is dipping further than this battery's normal: lowest %.1f V on the last %ld starts vs %.1f V before",
                              r, newest.count, b) + dropText + ". Have the battery capacity-tested and check the cables and connections."
        } else {
            summary = String(format: "Normal for this battery: lowest %.1f V on the last %ld starts vs %.1f V over the %ld before.",
                              r, newest.count, b, earlier.count)
        }
        return BatteryWatchReport(points: points, nominal: nominal, level: watch ? .watch : .normal, recentLow: r, baselineLow: b,
                                  recentDrop: recentDrop, baselineDrop: baselineDrop, threshold: threshold,
                                  summary: summary, notes: notes)
    }

    private static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
