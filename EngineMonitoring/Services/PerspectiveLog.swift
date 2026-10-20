import Foundation

/// Column names used by the Garmin Perspective / G1000 CSV data log (log_YYMMDD_HHMMSS_XXXX.csv).
enum PerspectiveChannel {
    static let date = "Lcl Date"
    static let time = "Lcl Time"
    static let utcOffset = "UTCOfst"

    static let rpm = "E1 RPM"
    static let fuelFlow = "E1 FFlow"
    static let manifoldPressure = "E1 MAP"
    static let oilPressure = "E1 OilP"
    static let oilTemp = "E1 OilT"
    static let percentPower = "E1 %Pwr"
    static let tit1 = "E1 TIT1"
    static let tit2 = "E1 TIT2"
    static let cht = (1...6).map { "E1 CHT\($0)" }
    static let egt = (1...6).map { "E1 EGT\($0)" }

    static let volt1 = "volt1"
    static let volt2 = "volt2"
    static let amp1 = "amp1"

    static let ias = "IAS"
    static let altBaro = "AltB"
    static let oat = "OAT"
    static let afcsOn = "AfcsOn"
    static let rollMode = "RollM"
    static let pitchMode = "PitchM"
    static let gpsFix = "GPSfix"

    /// Columns kept as text rather than numbers.
    static let textColumns: Set<String> = [date, time, utcOffset, "AtvWpt", "HSIS", rollMode, pitchMode, gpsFix]
}

/// A parsed Perspective data log. Numeric channels hold `Double.nan` where the log cell was blank.
struct PerspectiveLog: Sendable {
    let filename: String
    let metadata: [String: String]
    let columns: [String]
    let times: [Date]
    private let numeric: [String: [Double]]
    private let text: [String: [String]]

    init(filename: String, metadata: [String: String], columns: [String], times: [Date],
         numeric: [String: [Double]], text: [String: [String]]) {
        self.filename = filename
        self.metadata = metadata
        self.columns = columns
        self.times = times
        self.numeric = numeric
        self.text = text
    }

    var airframeName: String? { metadata["airframe_name"] }
    var systemID: String? { metadata["system_id"] }
    var softwareVersion: String? { metadata["unit_software_version"] }
    var sampleCount: Int { times.count }
    var start: Date? { times.first }
    var end: Date? { times.last }

    /// Local time zone of the log, from the first UTCOfst cell (e.g. "-07:00").
    var timeZone: TimeZone {
        let offset = (0..<min(sampleCount, 50)).lazy
            .compactMap { self.textValue(PerspectiveChannel.utcOffset, at: $0).flatMap(PerspectiveLogParser.parseOffset) }.first
        return offset.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
    }

    func hasChannel(_ name: String) -> Bool { numeric[name] != nil || text[name] != nil }

    /// Value of a numeric channel at a sample index, or nil if blank or absent.
    func value(_ channel: String, at index: Int) -> Double? {
        guard let column = numeric[channel], index >= 0, index < column.count else { return nil }
        let v = column[index]
        return v.isNaN ? nil : v
    }

    func textValue(_ channel: String, at index: Int) -> String? {
        guard let column = text[channel], index >= 0, index < column.count else { return nil }
        let v = column[index]
        return v.isEmpty ? nil : v
    }

    /// Indices of samples whose time is within the closed interval.
    func indices(from lower: Date, to upper: Date) -> Range<Int> {
        let lo = firstIndex(notBefore: lower)
        let hi = firstIndex(notBefore: upper.addingTimeInterval(0.001))
        return lo..<max(lo, hi)
    }

    /// Non-blank values of a channel over a range of sample indices, with their indices.
    func samples(_ channel: String, in range: Range<Int>) -> [(index: Int, value: Double)] {
        guard let column = numeric[channel] else { return [] }
        return range.compactMap { i in
            guard i < column.count, !column[i].isNaN else { return nil }
            return (i, column[i])
        }
    }

    /// Whether `date` falls within the log, allowing `tolerance` seconds either side.
    func covers(_ date: Date, tolerance: TimeInterval = 0) -> Bool {
        guard let start, let end else { return false }
        return date >= start.addingTimeInterval(-tolerance) && date <= end.addingTimeInterval(tolerance)
    }

    /// Seconds between `date` and the nearest edge of the log (0 if inside).
    func distance(to date: Date) -> TimeInterval {
        guard let start, let end else { return .infinity }
        if date < start { return start.timeIntervalSince(date) }
        if date > end { return date.timeIntervalSince(end) }
        return 0
    }

    private func firstIndex(notBefore date: Date) -> Int {
        var lo = 0, hi = times.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < date { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

enum PerspectiveLogError: LocalizedError, Equatable {
    case unreadable
    case noHeaderRow
    case missingTimeColumns
    case noSamples

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file could not be read as text."
        case .noHeaderRow: return "This doesn't look like an avionics engine log (no column header row found). If it came from Garmin Pilot or flyGarmin, email it to sales@enginepulse.net and we'll add support for it."
        case .missingTimeColumns: return "The log has no Lcl Date / Lcl Time columns. If it came from Garmin Pilot, try flyGarmin > Download > Original CSV instead, or email it to sales@enginepulse.net and we'll add support for it."
        case .noSamples: return "The log contains no timestamped samples."
        }
    }
}

enum PerspectiveLogParser {
    /// Parses a Perspective / G1000 CSV log.
    /// - Parameter fallbackUTCOffsetSeconds: used only for rows whose UTCOfst cell is blank.
    static func parse(data: Data, filename: String, fallbackUTCOffsetSeconds: Int = 0) throws -> PerspectiveLog {
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw PerspectiveLogError.unreadable
        }
        return try parse(text: content, filename: filename, fallbackUTCOffsetSeconds: fallbackUTCOffsetSeconds)
    }

    static func parse(text content: String, filename: String, fallbackUTCOffsetSeconds: Int = 0) throws -> PerspectiveLog {
        var metadata: [String: String] = [:]
        var header: [String]?
        var columnIndex: [String: Int] = [:]
        var numericCols: [(name: String, index: Int)] = []
        var textCols: [(name: String, index: Int)] = []
        var numericStore: [[Double]] = []
        var textStore: [[String]] = []
        var times: [Date] = []

        var dateIdx = -1, timeIdx = -1, offsetIdx = -1

        content.enumerateLines { rawLine, _ in
            let fields = splitFields(rawLine)
            guard let first = fields.first else { return }
            if fields.count == 1 && first.isEmpty { return }

            if first.hasPrefix("#") {
                if first.hasPrefix("#airframe_info") { metadata.merge(parseMetadata(rawLine)) { $1 } }
                return // "#yyy-mm-dd, ..." units row and other comments
            }

            if header == nil {
                // First non-comment row is the header.
                let names = fields.map(String.init)
                header = names
                for (i, name) in names.enumerated() where !name.isEmpty && columnIndex[name] == nil {
                    columnIndex[name] = i
                    if PerspectiveChannel.textColumns.contains(name) { textCols.append((name, i)) } else { numericCols.append((name, i)) }
                }
                numericStore = Array(repeating: [], count: numericCols.count)
                textStore = Array(repeating: [], count: textCols.count)
                dateIdx = columnIndex[PerspectiveChannel.date] ?? -1
                timeIdx = columnIndex[PerspectiveChannel.time] ?? -1
                offsetIdx = columnIndex[PerspectiveChannel.utcOffset] ?? -1
                return
            }

            guard dateIdx >= 0, timeIdx >= 0, dateIdx < fields.count, timeIdx < fields.count else { return }
            let offset = offsetIdx >= 0 && offsetIdx < fields.count ? fields[offsetIdx] : ""
            guard let date = fastTimestamp(date: fields[dateIdx], time: fields[timeIdx], offset: offset,
                                           fallbackSeconds: fallbackUTCOffsetSeconds) else { return }

            times.append(date)
            for k in numericCols.indices {
                let i = numericCols[k].index
                numericStore[k].append(i < fields.count ? Double(fields[i]) ?? .nan : .nan)
            }
            for k in textCols.indices {
                let i = textCols[k].index
                textStore[k].append(i < fields.count ? String(fields[i]) : "")
            }
        }

        guard let header else { throw PerspectiveLogError.noHeaderRow }
        guard dateIdx >= 0, timeIdx >= 0 else { throw PerspectiveLogError.missingTimeColumns }
        guard !times.isEmpty else { throw PerspectiveLogError.noSamples }

        var numeric: [String: [Double]] = [:]
        for (k, col) in numericCols.enumerated() { numeric[col.name] = numericStore[k] }
        var text: [String: [String]] = [:]
        for (k, col) in textCols.enumerated() { text[col.name] = textStore[k] }

        // Logs are written in time order, but guard against out-of-order rows so binary search stays valid.
        if zip(times, times.dropFirst()).contains(where: { $0 > $1 }) {
            let order = times.indices.sorted { times[$0] < times[$1] }
            times = order.map { times[$0] }
            for key in numeric.keys { numeric[key] = order.map { numeric[key]![$0] } }
            for key in text.keys { text[key] = order.map { text[key]![$0] } }
        }

        return PerspectiveLog(filename: filename, metadata: metadata, columns: header.filter { !$0.isEmpty },
                              times: times, numeric: numeric, text: text)
    }

    /// Splits a CSV line on commas and trims spaces, tabs, CR and BOM, without allocating new strings.
    static func splitFields(_ line: String) -> [Substring] {
        var result: [Substring] = []
        result.reserveCapacity(80)
        for raw in line.split(separator: ",", omittingEmptySubsequences: false) {
            var field = raw[...]
            while let c = field.first, c == " " || c == "\t" || c == "\r" || c == "\u{FEFF}" { field = field.dropFirst() }
            while let c = field.last, c == " " || c == "\t" || c == "\r" { field = field.dropLast() }
            result.append(field)
        }
        return result
    }

    /// Fast path for "yyyy-MM-dd" + "HH:mm:ss" + "-07:00"; falls back to DateFormatter for anything else.
    static func fastTimestamp(date: Substring, time: Substring, offset: Substring, fallbackSeconds: Int) -> Date? {
        let d = date.split(separator: "-"), t = time.split(separator: ":")
        guard d.count == 3, t.count == 3,
              let y = Int(d[0]), let mo = Int(d[1]), let day = Int(d[2]),
              let h = Int(t[0]), let mi = Int(t[1]), let sec = Double(t[2]),
              (1...12).contains(mo), (1...31).contains(day), (0...23).contains(h), (0...59).contains(mi) else {
            return timestamp(date: String(date), time: String(time), offset: String(offset), fallbackSeconds: fallbackSeconds)
        }
        let offsetSeconds = parseOffset(String(offset)) ?? fallbackSeconds
        let days = daysFromCivil(year: y, month: mo, day: day)
        let utc = Double(days) * 86_400 + Double(h * 3600 + mi * 60) + sec - Double(offsetSeconds)
        return Date(timeIntervalSince1970: utc)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's algorithm).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// `#airframe_info, log_version="1.00", airframe_name="Cirrus SR22 Turbo Normalized", ..., mode=NORMAL,`
    static func parseMetadata(_ line: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in line.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces)
            let value = pair[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            result[key] = value
        }
        return result
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Builds an absolute time from the log's local date, local time and "-07:00" style offset.
    static func timestamp(date: String, time: String, offset: String, fallbackSeconds: Int) -> Date? {
        guard !date.isEmpty, !time.isEmpty, let asUTC = formatter.date(from: "\(date) \(time)") else { return nil }
        let offsetSeconds = parseOffset(offset) ?? fallbackSeconds
        return asUTC.addingTimeInterval(TimeInterval(-offsetSeconds))
    }

    /// "-07:00" -> -25200, "+05:30" -> 19800, "" -> nil
    static func parseOffset(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let parts = trimmed.dropFirst().split(separator: ":")
        guard let h = Int(parts.first ?? "") else { return nil }
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let total = h * 3600 + m * 60
        return sign == "-" ? -total : total
    }
}
