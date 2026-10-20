import Foundation

// Engine logs from monitors other than Garmin's G1000 family are converted, on import, into the Garmin
// CSV layout the rest of the app reads (same column names and units: engine temperatures in °F, OAT in
// °C, fuel flow in gal/h). The converted file is what is stored and uploaded, so analysis, cloud sync
// and restore work the same for every monitor.
//
// Supported:
// - Garmin CSV data logs (G1000 / NXi, Perspective, Perspective+ / Touch+, G3X Touch, TXi, GI 275): passed through.
// - J.P. Instruments EDM binary downloads (.JPI, .DAT): decoded here. Port of the JPI-Parser filespec
//   (MIT, Unicornlines 2026) with record semantics from edmtools (Apache-2.0, Keith Wannamaker 2015).
// - JPI CSV exports (EzTrends / EZSave) and other CSV engine logs (EI MVP / CGR, Dynon SkyView,
//   Avidyne R9 C_ENGINE.CSV, GRT, AFS and similar): columns are recognised by name.

enum EngineLogImportError: LocalizedError, Equatable {
    case unrecognized
    case noTimestamps
    case noFlights
    case damaged(String)

    var errorDescription: String? {
        switch self {
        case .unrecognized:
            return "This file doesn't look like an engine log Engine Pulse can read yet (no engine columns such as CHT, EGT or RPM were found). Email it to sales@enginepulse.net and we'll add support for it."
        case .noTimestamps:
            return "The engine columns were found, but not the date and time of each sample. Email the file to sales@enginepulse.net and we'll add support for it."
        case .noFlights:
            return "The file has no flights with the engine running."
        case .damaged(let detail):
            return "The engine data file could not be read (\(detail)). Download it from the monitor again, or email it to sales@enginepulse.net."
        }
    }
}

/// One flight in Garmin CSV layout, ready to store like a Garmin log.
struct ConvertedEngineLog: Sendable {
    let filename: String
    let data: Data
    /// Where it came from, e.g. "JPI EDM-830" or "CSV (EI / Dynon / other)".
    let source: String
}

enum EngineLogConverter {
    /// Returns the flights in the file in Garmin CSV layout. Garmin logs come back unchanged.
    static func convert(data: Data, filename: String, timeZone: TimeZone = .current) throws -> [ConvertedEngineLog] {
        let bytes = [UInt8](data)
        if JPIFile.looksLikeJPI(bytes) || ["jpi", "dat"].contains((filename as NSString).pathExtension.lowercased()) && JPIFile.findHeader(bytes) != nil {
            return try JPIFile(bytes: bytes).convertedFlights(originalFilename: filename, timeZone: timeZone)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw EngineLogImportError.unrecognized
        }
        if isGarminLog(text) {
            return [ConvertedEngineLog(filename: filename, data: data, source: "Garmin")]
        }
        return try GenericEngineCSV.convert(text: text, filename: filename, timeZone: timeZone)
    }

    /// True for Garmin data logs (a header row with Lcl Date and Lcl Time in the first lines).
    static func isGarminLog(_ text: String) -> Bool {
        var n = 0
        var found = false
        text.enumerateLines { line, stop in
            n += 1
            if line.contains("Lcl Date") && line.contains("Lcl Time") { found = true; stop = true }
            if n > 40 { stop = true }
        }
        return found
    }

    /// Extensions offered for engine logs (SD card / USB folders, Files, share sheet).
    static let logExtensions: Set<String> = ["csv", "jpi", "dat"]
}

// MARK: - Garmin CSV writer

/// Canonical (Garmin) column names written by the converters.
enum CanonicalChannel {
    static func egt(_ n: Int) -> String { "E1 EGT\(n)" }
    static func cht(_ n: Int) -> String { "E1 CHT\(n)" }
    static func tit(_ n: Int) -> String { "E1 TIT\(n)" }
    static let rpm = "E1 RPM"
    static let map = "E1 MAP"
    static let fuelFlow = "E1 FFlow"
    static let oilTemp = "E1 OilT"
    static let oilPressure = "E1 OilP"
    static let fuelPressure = "E1 FPres"
    static let percentPower = "E1 %Pwr"
    static let oat = "OAT"
    static let volts = "volt1"
    static let amps = "amp1"
    static let ias = "IAS"
    static let altitude = "AltB"
    static let verticalSpeed = "VSpd"

    /// Column order in the written file.
    static let order: [String] = (1...9).map(egt) + (1...9).map(cht) + [tit(1), tit(2), rpm, map, fuelFlow, oilTemp,
        oilPressure, fuelPressure, percentPower, oat, volts, amps, ias, altitude, verticalSpeed]
}

struct GarminCSVWriter {
    var airframeName: String
    var systemID: String
    var convertedFrom: String
    var timeZone: TimeZone

    /// `rows`: (time, values by canonical column). Columns with no value in any row are left out.
    func write(times: [Date], columns: [String: [Double?]]) -> Data {
        let present = CanonicalChannel.order.filter { name in columns[name]?.contains { $0 != nil } ?? false }
        var out = "#airframe_info, log_version=\"1.00\", airframe_name=\"\(clean(airframeName))\", system_id=\"\(clean(systemID))\", converted_from=\"\(clean(convertedFrom))\",\n"
        out += (["Lcl Date", "Lcl Time", "UTCOfst"] + present).joined(separator: ",") + "\n"
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        for (i, t) in times.enumerated() {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: t)
            let offset = timeZone.secondsFromGMT(for: t)
            let sign = offset < 0 ? "-" : "+"
            let oh = abs(offset) / 3600, om = abs(offset) % 3600 / 60
            var fields = [
                String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0),
                sign + String(format: "%02d:%02d", oh, om),
            ]
            for name in present {
                fields.append(Self.format(columns[name]?[i] ?? nil))
            }
            out += fields.joined(separator: ",") + "\n"
        }
        return Data(out.utf8)
    }

    private func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: ",", with: " ")
    }

    static func format(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "" }
        if v == v.rounded() && abs(v) < 1e9 { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}

enum UnitConvert {
    static func fToC(_ f: Double) -> Double { (f - 32) * 5 / 9 }
    static func cToF(_ c: Double) -> Double { c * 9 / 5 + 32 }
}

// MARK: - J.P. Instruments EDM binary (.JPI / .DAT)

struct JPIFile {
    let bytes: [UInt8]
    var tail = ""
    var model = 0
    var swVersion = 0
    var protocolID: Int?
    var fuelUnit = 0
    var engineInF = true
    var oatInF = true
    var edmType = false
    var flights: [(id: Int, size: Int)] = []
    var dataStart = 0

    static func findHeader(_ b: [UInt8]) -> Int? {
        guard b.count > 2 else { return nil }
        for i in 0..<min(b.count - 1, 4096) where b[i] == 0x24 && b[i + 1] == 0x55 { return i }   // "$U"
        return nil
    }

    /// "$U," near the start and a "$L" record: a JPI download.
    static func looksLikeJPI(_ b: [UInt8]) -> Bool {
        guard let start = findHeader(b), start < 512 else { return false }
        let window = b[start..<min(b.count, start + 4096)]
        return zip(window, window.dropFirst()).contains { $0 == 0x24 && $1 == 0x4C }   // "$L"
    }

    init(bytes: [UInt8]) throws {
        self.bytes = bytes
        guard let start = Self.findHeader(bytes) else { throw EngineLogImportError.damaged("no $U header") }
        var ptr = start
        var sawL = false
        while ptr < bytes.count {
            var text = ""
            var star = ptr
            while star < bytes.count && bytes[star] != 0x2A {           // '*'
                if bytes[star] != 0 { text.append(Character(UnicodeScalar(bytes[star]))) }
                star += 1
            }
            guard star < bytes.count else { break }
            let fields = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let kind = fields.first ?? ""
            func int(_ i: Int) -> Int? { i < fields.count ? Int(fields[i]) ?? Double(fields[i]).map { Int($0.rounded()) } : nil }
            switch kind {
            case "$U":
                tail = fields.count > 1 ? fields[1].replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces) : ""
            case "$C":
                model = int(1) ?? 0
                let last = fields.count - 1
                if last == 8 || last == 9 { swVersion = int(last - 2) ?? 0 } else { swVersion = int(last) ?? 0 }
                if let e = int(3) { engineInF = e & 0x1000 != 0 }
                if let o = int(5) { oatInF = o & 0x2000 != 0 }
                edmType = model >= 900
            case "$P":
                protocolID = int(1)
                edmType = true
            case "$F":
                fuelUnit = int(1) ?? 0
            case "$D":
                if let id = int(1), let half = int(2) { flights.append((id, half * 2)) }
            case "$L":
                dataStart = star + 5
                sawL = true
            default:
                break
            }
            if sawL { break }
            ptr = star + 5
        }
        guard sawL, !flights.isEmpty else { throw EngineLogImportError.damaged("no flight directory") }
    }

    var modelName: String { model > 0 ? "JPI EDM-\(model)" : "JPI EDM" }

    private func word(_ at: Int) -> Int? {
        guard at >= 0, at + 1 < bytes.count else { return nil }
        return Int(bytes[at]) << 8 | Int(bytes[at + 1])
    }

    /// Each flight's bytes, allowing for the ±1 byte slips JPI files are known for.
    func flightBlocks() -> [(id: Int, data: ArraySlice<UInt8>)] {
        var ptr = dataStart
        var out: [(Int, ArraySlice<UInt8>)] = []
        for f in flights {
            var shift: Int?
            if word(ptr) == f.id { shift = 0 } else if word(ptr - 1) == f.id { shift = -1 } else {
                for d in -30...30 where word(ptr + d) == f.id { shift = d; break }
            }
            ptr += shift ?? 0
            let start = max(0, min(ptr, bytes.count)), end = max(start, min(ptr + f.size, bytes.count))
            if shift != nil { out.append((f.id, bytes[start..<end])) }
            ptr += f.size
        }
        return out
    }

    func decodeAll() -> [JPIFlight] {
        flightBlocks().compactMap { JPIFlightDecoder(file: self, id: $0.id, data: Array($0.data)).decode() }
    }

    func convertedFlights(originalFilename: String, timeZone: TimeZone) throws -> [ConvertedEngineLog] {
        let decoded = decodeAll()
        guard !decoded.isEmpty else { throw EngineLogImportError.damaged("no readable flights") }
        let base = (originalFilename as NSString).deletingPathExtension
        let flights = decoded.filter { $0.engineRan }
        guard !flights.isEmpty else { throw EngineLogImportError.noFlights }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return flights.map { f in
            let times = f.offsets.map { f.start(in: timeZone).addingTimeInterval(TimeInterval($0)) }
            var cols: [String: [Double?]] = [:]
            func put(_ code: String, _ name: String, _ transform: (Double) -> Double = { $0 }) {
                guard let series = f.series[code] else { return }
                cols[name] = series.map { $0.map(transform) }
            }
            let engine: (Double) -> Double = engineInF ? { $0 } : UnitConvert.cToF
            for n in 1...9 {
                put("E\(n)", CanonicalChannel.egt(n), engine)
                put("C\(n)", CanonicalChannel.cht(n), engine)
            }
            put("T1", CanonicalChannel.tit(1), engine)
            put("T2", CanonicalChannel.tit(2), engine)
            put("OILT", CanonicalChannel.oilTemp, engine)
            put("OILP", CanonicalChannel.oilPressure)
            put("RPM", CanonicalChannel.rpm)
            put("MAP", CanonicalChannel.map)
            put("HP", CanonicalChannel.percentPower)
            put("BAT", CanonicalChannel.volts)
            put("AMP", CanonicalChannel.amps)
            put("FP", CanonicalChannel.fuelPressure)
            put("OAT", CanonicalChannel.oat, oatInF ? UnitConvert.fToC : { $0 })
            // Fuel flow in gal/h (fuel unit 0). Other units are left out rather than guessed.
            if fuelUnit == 0 { put("FF", CanonicalChannel.fuelFlow) }
            let writer = GarminCSVWriter(airframeName: modelName, systemID: tail, convertedFrom: originalFilename, timeZone: timeZone)
            let stamp = times.first.map { t -> String in
                let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: t)
                return String(format: "%04d%02d%02d_%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            } ?? "0"
            let safeBase = base.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            return ConvertedEngineLog(filename: "jpi_\(safeBase)_\(stamp)_f\(f.id).csv",
                                      data: writer.write(times: times, columns: cols), source: modelName)
        }
    }
}

/// One decoded JPI flight: sample offsets (seconds from start) and values per JPI code (E1, C1, RPM, ...).
struct JPIFlight {
    let id: Int
    let startComponents: DateComponents
    let interval: Int
    var offsets: [Int] = []
    var series: [String: [Double?]] = [:]

    func start(in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: startComponents) ?? Date(timeIntervalSince1970: 0)
    }

    /// At least a minute of samples with the engine running (RPM 500+, or a hot EGT when RPM isn't recorded).
    var engineRan: Bool {
        guard offsets.count >= 10 else { return false }
        if let rpm = series["RPM"], rpm.contains(where: { $0 != nil }) {
            return rpm.filter { ($0 ?? 0) >= 500 }.count >= max(2, 60 / max(interval, 1))
        }
        let egt = (1...9).compactMap { series["E\($0)"] }.first ?? []
        return egt.filter { ($0 ?? 0) >= 800 }.count >= max(2, 60 / max(interval, 1))
    }
}

/// Decodes one flight's delta-compressed records.
struct JPIFlightDecoder {
    let file: JPIFile
    let id: Int
    let data: [UInt8]

    /// code, enable bit (Cfg_Word index, bit), scale, low slot (byte, bit), optional high slot (byte, bit).
    struct Metric {
        let code: String
        let cfgWord: Int
        let cfgBit: Int
        let scale: Double
        let lo: (Int, Int)
        let hi: (Int, Int)?
    }

    static func metrics(newFormat: Bool, fuelUnit: Int) -> [Metric] {
        var m: [Metric] = []
        let egtSlots: [(Int, Int, Int, Int)] = [(0, 0, 6, 0), (0, 1, 6, 1), (0, 2, 6, 2), (0, 3, 6, 3), (0, 4, 6, 4), (0, 5, 6, 5),
                                                (3, 0, 7, 0), (3, 1, 7, 1), (3, 2, 7, 2)]
        for (i, s) in egtSlots.enumerated() {
            m.append(Metric(code: "E\(i + 1)", cfgWord: 0, cfgBit: 2 + i, scale: 1, lo: (s.0, s.1), hi: (s.2, s.3)))
        }
        let chtSlots: [(Int, Int, Int, Int)] = [(0, 11, 1, 0), (0, 12, 1, 1), (0, 13, 1, 2), (0, 14, 1, 3), (0, 15, 1, 4),
                                                (1, 0, 1, 5), (1, 1, 3, 3), (1, 2, 3, 4), (1, 3, 3, 5)]
        for (i, s) in chtSlots.enumerated() {
            m.append(Metric(code: "C\(i + 1)", cfgWord: s.0, cfgBit: s.1, scale: 1, lo: (s.2, s.3), hi: nil))
        }
        let gal = fuelUnit == 0
        m += [
            Metric(code: "T1", cfgWord: 1, cfgBit: 5, scale: 1, lo: (0, 6), hi: (6, 6)),
            Metric(code: "T2", cfgWord: 1, cfgBit: 6, scale: 1, lo: (0, 7), hi: (6, 7)),
            Metric(code: "OAT", cfgWord: 1, cfgBit: 9, scale: 1, lo: (2, 5), hi: nil),
            Metric(code: "CDT", cfgWord: 1, cfgBit: 7, scale: 1, lo: (2, 2), hi: nil),
            Metric(code: "IAT", cfgWord: 1, cfgBit: 8, scale: 1, lo: (2, 3), hi: nil),
            Metric(code: "MAP", cfgWord: 1, cfgBit: 14, scale: 10, lo: (5, 0), hi: nil),
            Metric(code: "RPM", cfgWord: 1, cfgBit: 10, scale: 1, lo: (5, 1), hi: (5, 2)),
            Metric(code: "HP", cfgWord: 1, cfgBit: 10, scale: 1, lo: (3, 6), hi: nil),
            Metric(code: "FF", cfgWord: 1, cfgBit: 11, scale: gal ? 10 : 1, lo: (2, 7), hi: nil),
            Metric(code: "OILP", cfgWord: 1, cfgBit: 13, scale: 1, lo: (2, 1), hi: nil),
            Metric(code: "OILT", cfgWord: 1, cfgBit: 4, scale: 1, lo: (1, 7), hi: nil),
            Metric(code: "BAT", cfgWord: 0, cfgBit: 0, scale: 10, lo: (2, 4), hi: nil),
            Metric(code: "MARK", cfgWord: 0, cfgBit: 0, scale: 1, lo: (2, 0), hi: nil),
        ]
        if newFormat {
            m += [
                Metric(code: "AMP", cfgWord: 0, cfgBit: 1, scale: 1, lo: (8, 0), hi: nil),
                Metric(code: "FP", cfgWord: 1, cfgBit: 15, scale: 10, lo: (8, 5), hi: nil),
            ]
        }
        return m
    }

    private struct Reader {
        let d: [UInt8]
        var p = 0
        mutating func byte() -> Int? {
            guard p < d.count else { return nil }
            defer { p += 1 }
            return Int(d[p])
        }
        mutating func word() -> Int? {
            guard p + 1 < d.count else { return nil }
            defer { p += 2 }
            return Int(d[p]) << 8 | Int(d[p + 1])
        }
    }

    func decode() -> JPIFlight? {
        var r = Reader(d: data)
        guard let first = r.word() else { return nil }
        if first != id { r.p -= 1; _ = r.word() }
        var cfg = [Int](repeating: 0, count: 7)
        guard let c0 = r.word(), let c1 = r.word() else { return nil }
        cfg[0] = c0; cfg[1] = c1
        let wide: Set<Int> = [711, 730, 740, 830, 831]
        var newFormat = false
        if file.edmType {
            var x: UInt8 = 0
            for i in 0..<min(15, data.count) { x ^= data[i] }
            newFormat = !(wide.contains(file.model) && x == 0)
            if newFormat {
                guard let c2 = r.word(), let c3 = r.word() else { return nil }
                cfg[2] = c2; cfg[3] = c3
                if isNewHeader(at: r.p) {
                    cfg[4] = r.word() ?? 0
                    if wide.contains(file.model) { r.p += 8 }   // start latitude and longitude
                }
            }
        }
        guard r.byte() != nil, r.byte() != nil,                          // fuel unit, rated HP
              let interval = r.word(), let dw = r.word(), let tw = r.word(), r.byte() != nil else { return nil }
        let yy = dw >> 9
        var start = DateComponents()
        start.year = yy < 75 ? 2000 + yy : 1900 + yy
        start.month = (dw >> 5) & 0x0F
        start.day = dw & 0x1F
        start.hour = tw >> 11
        start.minute = (tw >> 5) & 0x3F
        start.second = (tw & 0x1F) * 2
        guard (1...12).contains(start.month ?? 0), (1...31).contains(start.day ?? 0),
              (0...23).contains(start.hour ?? -1), (0...59).contains(start.minute ?? -1) else { return nil }

        let all = Self.metrics(newFormat: newFormat, fuelUnit: file.fuelUnit)
        let active = all.filter { ($0.cfgWord == 0 && $0.cfgBit == 0) || (cfg[$0.cfgWord] & (1 << $0.cfgBit)) != 0 }
        var total: [String: Double] = [:]
        for m in all { total[m.code] = m.code == "HP" ? 0 : 240 }
        var notAvailable = Set<String>()
        var seen = Set<String>()
        var flight = JPIFlight(id: id, startComponents: start, interval: max(interval, 1))
        for m in active where m.code != "MARK" { flight.series[m.code] = [] }
        var t = 0
        var step = max(interval, 1)
        var last: [String: Double?]?
        let wideRecords = newFormat

        while r.p < data.count - 4 {
            let w1: Int?, w2: Int?
            if wideRecords { w1 = r.word(); w2 = r.word() } else { w1 = r.byte(); w2 = r.byte() }
            guard let mask = w1, mask == w2, let repeatCount = r.byte() else { break }
            var ctl = [Int?](repeating: nil, count: 16)
            var sgn = [Int](repeating: 0, count: 16)
            var ok = true
            for i in 0..<16 where mask & (1 << i) != 0 {
                guard let b = r.byte() else { ok = false; break }
                ctl[i] = b
            }
            for i in 0..<16 where (i < 6 || i > 7) && mask & (1 << i) != 0 {
                guard let b = r.byte() else { ok = false; break }
                sgn[i] = b
            }
            guard ok else { break }
            // (value, valid, negative) per (byte, bit) slot this record.
            var slots: [Int: (Int, Bool, Bool)] = [:]
            for i in 0..<16 {
                guard let c = ctl[i] else { continue }
                let s = i == 6 ? sgn[0] : (i == 7 ? sgn[3] : sgn[i])
                for j in 0..<8 where c & (1 << j) != 0 {
                    var mult = 1
                    var signMask = 1 << j
                    if i == 5 && (j == 2 || j == 4) { mult = 256; signMask /= 2 }
                    else if i == 6 || i == 7 { mult = 256 }
                    else if i == 10 && (j == 1 || j == 2) { mult = 256; signMask *= 32 }
                    else if (i == 9 || i == 12) && (j == 4 || j == 5) { mult = 256; signMask /= 16 }
                    else if (i == 9 || i == 12) && j == 7 { mult = 256 }
                    else if (i == 13 || i == 14) && (4...6).contains(j) { mult = 256; signMask /= 16 }
                    guard let v = r.byte() else { ok = false; break }
                    slots[i * 8 + j] = (v * mult, v != 0, s & signMask != 0)
                }
                if !ok { break }
            }
            guard ok, r.byte() != nil else { break }       // record checksum

            if let last, repeatCount > 0 {
                for _ in 0..<repeatCount { append(last, at: t, to: &flight); t += step }
            }
            var row: [String: Double?] = [:]
            var mark = 0
            for m in active {
                let lo = slots[m.lo.0 * 8 + m.lo.1]
                let hi = m.hi.flatMap { slots[$0.0 * 8 + $0.1] }
                if let lo, !lo.1, !(hi?.1 ?? false) {
                    notAvailable.insert(m.code)                 // an explicit 0: sensor not available
                } else {
                    var delta = 0
                    if let lo { delta += lo.2 ? -lo.0 : lo.0 }
                    if let hi { delta += hi.2 ? -hi.0 : hi.0 }
                    if lo != nil || hi != nil { notAvailable.remove(m.code); seen.insert(m.code) }
                    total[m.code, default: 240] += Double(delta)
                }
                let n = (total[m.code] ?? 0).rounded()
                if m.code == "MARK" { mark = Int(n) & 7; continue }
                if notAvailable.contains(m.code) || !seen.contains(m.code) { row[m.code] = .some(nil); continue }
                row[m.code] = m.scale == 1 ? n : n / m.scale
            }
            append(row, at: t, to: &flight)
            last = row
            if mark == 2 { step = 1 } else if mark == 3 { step = max(interval, 1) }
            t += step
        }
        return flight.offsets.isEmpty ? nil : flight
    }

    private func append(_ row: [String: Double?], at t: Int, to flight: inout JPIFlight) {
        flight.offsets.append(t)
        for key in flight.series.keys { flight.series[key]!.append(row[key] ?? nil) }
    }

    /// EzTrends' test for the longer flight header (extra config word and GPS start position).
    private func isNewHeader(at p: Int) -> Bool {
        let d = data
        func at(_ i: Int) -> UInt8? { i >= 0 && i < d.count ? d[i] : nil }
        if let a = at(p + 19), let b = at(p + 21), let c = at(p + 20), let e = at(p + 22), a == b && c == e { return true }
        if (0..<4).allSatisfy({ k in at(p + 21 + k) != nil && at(p + 21 + k) == at(p - 8 + k) }) { return true }
        if let a = at(p + 11), let b = at(p + 13), a == b { return true }
        if let a = at(p + 12), let b = at(p + 14), a == b { return true }
        return false
    }
}

// MARK: - Other CSV engine logs (JPI CSV export, EI, Dynon, Avidyne, GRT, AFS, ...)

enum GenericEngineCSV {
    enum Role: Equatable {
        case channel(String)
        case date, time, dateTime, elapsed
        case groundSpeed
    }

    enum TempUnit { case f, c, unknown }

    struct Column {
        let index: Int
        let role: Role
        let unit: TempUnit
        let fuelPerGallon: Double   // divide by this to get gal/h (1 = gal/h)
    }

    /// Lower-case name without units: "EGT 1 (deg F)" -> "egt 1", "EGT1;*F" -> "egt1", "[RPM]" -> "rpm".
    static func baseName(_ raw: String) -> String {
        var s = raw.lowercased()
        if let semi = s.firstIndex(of: ";") { s = String(s[..<semi]) }
        while let open = s.firstIndex(of: "("), let close = s[open...].firstIndex(of: ")") { s.removeSubrange(open...close) }
        while let open = s.firstIndex(of: "["), let close = s[open...].firstIndex(of: "]") {
            let inner = s[s.index(after: open)..<close]
            s.replaceSubrange(open...close, with: inner.count <= 6 ? " \(inner) " : " ")
        }
        s = s.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "#", with: " ")
        return s.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    static func tempUnit(_ raw: String) -> TempUnit {
        let s = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if s.contains("degc") || s.contains("°c") || s.contains("*c") || s.hasSuffix("(c)") || s.contains("celsius") { return .c }
        if s.contains("degf") || s.contains("°f") || s.contains("*f") || s.hasSuffix("(f)") || s.contains("fahrenheit") { return .f }
        return .unknown
    }

    static func fuelDivisor(_ raw: String) -> Double {
        let s = raw.lowercased()
        if s.contains("l/h") || s.contains("lph") || s.contains("liter") || s.contains("litre") { return 3.78541 }
        if s.contains("lb") || s.contains("pph") { return 6.0 }
        if s.contains("kg") { return 2.72 }
        return 1
    }

    private static func number(after prefixes: [String], in s: String) -> Int? {
        for p in prefixes where s.hasPrefix(p) {
            let rest = s.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
            let digits = rest.prefix { $0.isNumber }
            let tail = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
            guard let n = Int(digits), (1...9).contains(n), ["", "l", "left", "lh", "e1"].contains(tail) else { continue }
            return n
        }
        return nil
    }

    /// The role of one column, by name. `jpiStyle`: bare E1/C1 mean EGT/CHT (JPI exports).
    static func role(of raw: String, jpiStyle: Bool) -> Role? {
        var s = baseName(raw)
        for prefix in ["left ", "l ", "e1 ", "eng1 ", "eng 1 ", "engine 1 ", "engine "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)); break
        }
        switch s {
        case "lcl date", "date", "local date", "gps date", "utc date", "date (local)": return .date
        case "lcl time", "time", "local time", "system time", "gps time", "clock", "utc time", "time (local)", "lcltime": return .time
        case "gps date & time", "date time", "date & time", "datetime", "timestamp", "date/time", "time stamp", "local date time": return .dateTime
        case "session time", "elapsed", "elapsed time", "time (s)", "seconds", "time s", "sec", "flight time": return .elapsed
        case "rpm", "rpml", "rpm l", "rpm left", "rpm 1", "rpm1", "tach", "engine rpm", "rpm (l)", "prop rpm": return .channel(CanonicalChannel.rpm)
        case "map", "mp", "mpl", "map l", "manifold pressure", "manifold press", "man press", "manifold", "map 1", "map1": return .channel(CanonicalChannel.map)
        case "ff", "ffl", "ff l", "ff1", "fflow", "fuel flow", "fuel flow 1", "fuel flow rate", "fuelflow", "fuel flow l", "ff gph": return .channel(CanonicalChannel.fuelFlow)
        case "oilt", "oil t", "oil temp", "oil temperature", "oil temp 1", "oilt1", "ot", "oil temp l": return .channel(CanonicalChannel.oilTemp)
        case "oilp", "oil p", "oil press", "oil pressure", "oil pressure 1", "oilp1", "op", "oil pres", "oil press l": return .channel(CanonicalChannel.oilPressure)
        case "fp", "fuel press", "fuel pressure", "fuel pres", "fpres": return .channel(CanonicalChannel.fuelPressure)
        case "oat", "outside air temp", "outside air temperature", "oat 1", "oat1", "ambient temp": return .channel(CanonicalChannel.oat)
        case "bat", "bat1", "volts", "volt", "voltage", "volts 1", "volts1", "volt1", "bus volts", "bus voltage", "battery", "main bus", "v1", "voltage 1", "bus 1 volts": return .channel(CanonicalChannel.volts)
        case "amp", "amps", "amps 1", "amps1", "amp1", "amperage", "ammeter", "current", "amps 1 (a)": return .channel(CanonicalChannel.amps)
        case "hp", "%pwr", "% pwr", "% power", "percent power", "%hp", "power", "pwr %", "% hp": return .channel(CanonicalChannel.percentPower)
        case "ias", "indicated airspeed", "airspeed", "asi", "ias kt": return .channel(CanonicalChannel.ias)
        case "gndspd", "ground speed", "gs", "spd", "gps ground speed", "groundspeed": return .groundSpeed
        case "altb", "pressure altitude", "baro altitude", "altitude", "alt", "palt", "indicated altitude", "pressure alt": return .channel(CanonicalChannel.altitude)
        case "vspd", "vertical speed", "vsi", "vs", "vert speed": return .channel(CanonicalChannel.verticalSpeed)
        default: break
        }
        if let n = number(after: ["egt"], in: s) { return .channel(CanonicalChannel.egt(n)) }
        if let n = number(after: ["cht"], in: s) { return .channel(CanonicalChannel.cht(n)) }
        if let n = number(after: ["tit"], in: s) { return .channel(CanonicalChannel.tit(n)) }
        if s == "tit" || s == "tit l" { return .channel(CanonicalChannel.tit(1)) }
        if jpiStyle {
            if let n = number(after: ["e"], in: s) { return .channel(CanonicalChannel.egt(n)) }
            if let n = number(after: ["c"], in: s) { return .channel(CanonicalChannel.cht(n)) }
            if let n = number(after: ["t"], in: s), n <= 2 { return .channel(CanonicalChannel.tit(n)) }
        }
        return nil
    }

    static func split(_ line: String, delimiter: Character) -> [String] {
        // Quoted fields may contain the delimiter.
        var out: [String] = []
        var cur = ""
        var quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle(); continue }
            if ch == delimiter && !quoted { out.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\u{FEFF}")) }
    }

    private static func isEngine(_ role: Role?) -> Bool {
        guard case .channel(let name)? = role else { return false }
        return name.contains("EGT") || name.contains("CHT") || name == CanonicalChannel.rpm || name == CanonicalChannel.oilTemp
    }

    static func convert(text: String, filename: String, timeZone: TimeZone) throws -> [ConvertedEngineLog] {
        var lines: [String] = []
        text.enumerateLines { line, _ in lines.append(line) }
        // Header: the early line naming the most engine channels.
        var best: (index: Int, score: Int, delimiter: Character, jpi: Bool)?
        for (i, line) in lines.prefix(120).enumerated() {
            let delimiter: Character = line.filter { $0 == "\t" }.count > line.filter { $0 == "," }.count ? "\t" : ","
            let fields = split(line, delimiter: delimiter)
            guard fields.count >= 3 else { continue }
            let lower = fields.map { baseName($0) }
            let jpi = lower.contains { $0.range(of: #"^c[1-9]$"#, options: .regularExpression) != nil }
                && lower.contains { $0.range(of: #"^e[1-9]$"#, options: .regularExpression) != nil }
            let score = fields.filter { isEngine(role(of: $0, jpiStyle: jpi)) }.count
            if score >= 2, score > (best?.score ?? 0) { best = (i, score, delimiter, jpi) }
        }
        guard let header = best else { throw EngineLogImportError.unrecognized }
        let headerFields = split(lines[header.index], delimiter: header.delimiter)
        let preamble = lines[..<header.index].joined(separator: "\n")
        let preambleLower = preamble.lowercased()
        // Units stated before the table (JPI: "Eng Deg F OAT Deg F"; EI headers).
        let engineDefault: TempUnit = preambleLower.contains("eng deg c") ? .c : .f
        let oatDefault: TempUnit = preambleLower.contains("oat deg f") ? .f : (preambleLower.contains("oat deg c") ? .c : .unknown)

        var columns: [Column] = []
        var taken = Set<String>()
        var hasIAS = false
        for (i, raw) in headerFields.enumerated() {
            guard let r = role(of: raw, jpiStyle: header.jpi) else { continue }
            if case .channel(let name) = r {
                if taken.contains(name) { continue }
                taken.insert(name)
                if name == CanonicalChannel.ias { hasIAS = true }
            }
            columns.append(Column(index: i, role: r, unit: tempUnit(raw), fuelPerGallon: fuelDivisor(raw)))
        }
        // Ground speed stands in for airspeed when there is none (flight-phase detection only needs 50 kt).
        if !hasIAS, let gs = columns.firstIndex(where: { $0.role == .groundSpeed }) {
            let c = columns[gs]
            columns[gs] = Column(index: c.index, role: .channel(CanonicalChannel.ias), unit: c.unit, fuelPerGallon: 1)
        }
        let dateCol = columns.first { $0.role == .date }?.index
        let timeCol = columns.first { $0.role == .time }?.index
        let dateTimeCol = columns.first { $0.role == .dateTime }?.index
        let elapsedCol = columns.first { $0.role == .elapsed }?.index
        guard dateTimeCol != nil || timeCol != nil || elapsedCol != nil else { throw EngineLogImportError.noTimestamps }
        let baseDay = DateParsing.day(in: preamble) ?? DateParsing.day(inFilename: filename)
        let baseStart = DateParsing.dateTime(in: preamble, zone: timeZone)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let headerLine = lines[header.index].trimmingCharacters(in: .whitespaces)

        // Repeated header rows split the file into flights (EzTrends exports several flights in one file).
        var segments: [[String]] = [[]]
        for line in lines[(header.index + 1)...] {
            if line.trimmingCharacters(in: .whitespaces) == headerLine { segments.append([]); continue }
            segments[segments.count - 1].append(line)
        }

        var results: [ConvertedEngineLog] = []
        for (segIndex, segment) in segments.enumerated() {
            var times: [Date] = []
            var values: [String: [Double?]] = [:]
            let channels = columns.compactMap { c -> (Column, String)? in
                if case .channel(let n) = c.role { return (c, n) } else { return nil }
            }
            for (_, n) in channels { values[n] = [] }
            var lastTime: Date?
            var dayOffset = 0
            for line in segment {
                let f = split(line, delimiter: header.delimiter)
                guard f.count >= max(3, headerFields.count / 2) else { continue }
                func field(_ i: Int?) -> String? {
                    guard let i, i < f.count else { return nil }
                    let v = f[i].trimmingCharacters(in: CharacterSet(charactersIn: "[]<>X "))
                    return v.isEmpty ? nil : v
                }
                var t: Date?
                // A "time" column holding plain seconds is elapsed time.
                let clockText = field(timeCol)
                let elapsedText = field(elapsedCol) ?? clockText.flatMap { DateParsing.clock($0) == nil && Double($0) != nil ? $0 : nil }
                if let s = field(dateTimeCol) {
                    t = DateParsing.dateTime(s, zone: timeZone)
                } else if let ts = clockText, let clock = DateParsing.clock(ts) {
                    let day = field(dateCol).flatMap { DateParsing.day($0) } ?? baseDay
                    if let day {
                        var c = day
                        c.hour = clock.h; c.minute = clock.m; c.second = Int(clock.s)
                        t = cal.date(from: c).map { $0.addingTimeInterval(clock.s - Double(Int(clock.s)) + Double(dayOffset) * 86_400) }
                        // A clock-only log that runs past midnight.
                        if let tt = t, let prev = lastTime, field(dateCol) == nil, tt < prev.addingTimeInterval(-43_200) {
                            dayOffset += 1
                            t = tt.addingTimeInterval(86_400)
                        }
                    }
                } else if let es = elapsedText, let secs = Double(es) {
                    let noon: Date? = baseDay.flatMap { (d: DateComponents) -> Date? in
                        var c = d
                        c.hour = 12
                        return cal.date(from: c)
                    }
                    t = (baseStart ?? noon)?.addingTimeInterval(secs)
                }
                guard let time = t else { continue }
                lastTime = time
                times.append(time)
                for (c, name) in channels {
                    var v = field(c.index).flatMap { Double($0) }
                    if let x = v {
                        if name.contains("EGT") || name.contains("CHT") || name.contains("TIT") || name == CanonicalChannel.oilTemp {
                            let unit = c.unit == .unknown ? engineDefault : c.unit
                            if unit == .c { v = UnitConvert.cToF(x) }
                        } else if name == CanonicalChannel.oat {
                            let unit = c.unit == .unknown ? oatDefault : c.unit
                            if unit == .f { v = UnitConvert.fToC(x) }
                        } else if name == CanonicalChannel.fuelFlow, c.fuelPerGallon != 1 {
                            v = x / c.fuelPerGallon
                        }
                    }
                    values[name]?.append(v)
                }
            }
            guard times.count >= 10 else { continue }
            if values[CanonicalChannel.verticalSpeed] == nil, let alt = values[CanonicalChannel.altitude] {
                values[CanonicalChannel.verticalSpeed] = verticalSpeed(times: times, altitude: alt)
            }
            let stamp: String = {
                let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: times[0])
                return String(format: "%04d%02d%02d_%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            }()
            let base = ((filename as NSString).deletingPathExtension).filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            let tail = DateParsing.tail(in: preamble) ?? ""
            let source = header.jpi ? "JPI EDM (CSV)" : "CSV engine log"
            let writer = GarminCSVWriter(airframeName: source, systemID: tail, convertedFrom: filename, timeZone: timeZone)
            let name = segments.count > 1 ? "\(base)_\(stamp)_\(segIndex + 1).csv" : "\(base)_\(stamp).csv"
            results.append(ConvertedEngineLog(filename: name, data: writer.write(times: times, columns: values), source: source))
        }
        guard !results.isEmpty else { throw EngineLogImportError.noTimestamps }
        return results
    }

    /// ft/min from altitude, over about ±10 s.
    static func verticalSpeed(times: [Date], altitude: [Double?]) -> [Double?] {
        let n = times.count
        var out = [Double?](repeating: nil, count: n)
        var lo = 0, hi = 0
        for i in 0..<n {
            while times[i].timeIntervalSince(times[lo]) > 10 { lo += 1 }
            while hi + 1 < n && times[hi + 1].timeIntervalSince(times[i]) <= 10 { hi += 1 }
            guard let a = altitude[lo], let b = altitude[hi] else { continue }
            let dt = times[hi].timeIntervalSince(times[lo])
            if dt >= 2 { out[i] = (b - a) / dt * 60 }
        }
        return out
    }
}

enum DateParsing {
    /// "2024-07-15", "2024/07/15", "07/15/2024", "7/15/24", "07-15-2024", "20240715".
    static func day(_ s: String) -> DateComponents? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).map(String.init)
        var y = 0, m = 0, d = 0
        if parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) {
            if parts[0].count == 4 { y = a; m = b; d = c } else { m = a; d = b; y = c < 100 ? 2000 + c : c }
        } else if t.count == 8, let v = Int(t) {
            y = v / 10_000; m = v / 100 % 100; d = v % 100
        } else { return nil }
        guard (1990...2100).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }
        return DateComponents(year: y, month: m, day: d)
    }

    /// "22:58:04", "9:05:02.5", "10:22 PM", "10:22:01 pm".
    static func clock(_ s: String) -> (h: Int, m: Int, s: Double)? {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        var pm: Bool?
        if t.hasSuffix("pm") { pm = true; t = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        else if t.hasSuffix("am") { pm = false; t = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        let p = t.split(separator: ":")
        guard p.count >= 2, var h = Int(p[0]), let m = Int(p[1]) else { return nil }
        let sec = p.count > 2 ? Double(p[2]) ?? 0 : 0
        if let pm { if pm && h < 12 { h += 12 } else if !pm && h == 12 { h = 0 } }
        guard (0...23).contains(h), (0...59).contains(m), sec >= 0, sec < 61 else { return nil }
        return (h, m, sec)
    }

    static func dateTime(_ s: String, zone: TimeZone) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
        let parts = t.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, var c = day(parts[0]), let k = clock(parts[1]) else { return nil }
        c.hour = k.h; c.minute = k.m; c.second = Int(k.s)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: c)?.addingTimeInterval(k.s - Double(Int(k.s)))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    static func day(in preamble: String) -> DateComponents? {
        if let s = firstMatch(#"\b(19|20)\d{2}[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])\b"#, in: preamble) { return day(s) }
        if let s = firstMatch(#"\b(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])/(\d{4}|\d{2})\b"#, in: preamble) { return day(s) }
        return nil
    }

    /// "Flt0001_20130123P.csv", "2014-08-07-N123X-...csv", "log_240715_101500.csv"
    static func day(inFilename name: String) -> DateComponents? {
        if let s = firstMatch(#"(19|20)\d{2}-\d{2}-\d{2}"#, in: name), let d = day(s) { return d }
        if let s = firstMatch(#"(19|20)\d{6}"#, in: name), let d = day(s) { return d }
        if let s = firstMatch(#"(?<=_)\d{6}(?=_)"#, in: name), let v = Int(s) {
            return DateComponents(year: 2000 + v / 10_000, month: v / 100 % 100, day: v % 100)
        }
        return nil
    }

    /// A start time in the preamble: "Flight #72 6/14/2013 10:58:04 PM", "Local Time: 2013-01-23 10:22:01".
    static func dateTime(in preamble: String, zone: TimeZone) -> Date? {
        let pattern = #"(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}/\d{1,2}/\d{2,4})[ T,]+(\d{1,2}:\d{2}(:\d{2})?( ?[AaPp][Mm])?)"#
        guard let s = firstMatch(pattern, in: preamble) else { return nil }
        let normalized = s.replacingOccurrences(of: ",", with: " ").split(separator: " ", omittingEmptySubsequences: true)
        guard normalized.count >= 2 else { return nil }
        return dateTime(String(normalized[0]) + " " + normalized.dropFirst().joined(separator: " "), zone: zone)
    }

    /// "Aircraft Number N12345", "Aircraft ID: N12345", "Tail: N12345".
    static func tail(in preamble: String) -> String? {
        guard let s = firstMatch(#"(aircraft (number|id)|tail( number)?|registration)\s*[:=]?\s*[A-Z0-9-]{2,10}"#, in: preamble) else { return nil }
        return s.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "=" }).last.map(String.init)
    }
}
