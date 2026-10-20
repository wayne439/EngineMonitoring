// Linux check of the engine-log importers (run by .github/workflows/import-check.yml).
// Compiles EngineLogImport.swift and PerspectiveLog.swift with this file and checks every converter.
import Foundation

var failures = 0
func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    if !ok { failures += 1; print("::error::\(message())") }
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tools/linuxcheck/testdata"
let utc = TimeZone(secondsFromGMT: 0)!
var cal = Calendar(identifier: .gregorian)
cal.timeZone = utc

/// JPI EZSave CSV reference rows: time -> column -> value.
func reference(_ path: String) -> [(Date, [String: String])] {
    let text = try! String(contentsOfFile: path, encoding: .utf8)
    var cols: [String] = []
    var rows: [(Date, [String: String])] = []
    for line in text.components(separatedBy: .newlines) {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " []")) }
        if f.first == "Date" { cols = f; continue }
        guard !cols.isEmpty, f.count >= cols.count - 1, let d = DateParsing.day(f[0]), let k = DateParsing.clock(f[1]) else { continue }
        var c = d; c.hour = k.h; c.minute = k.m; c.second = Int(k.s)
        rows.append((cal.date(from: c)!, Dictionary(uniqueKeysWithValues: zip(cols, f).map { ($0, $1) })))
    }
    return rows
}

typealias Mapping = (jpi: String, garmin: String, convert: (Double) -> Double)
var jpiToGarmin: [Mapping] = []
for n in 1...6 {
    jpiToGarmin.append(("E\(n)", "E1 EGT\(n)", { $0 }))
    jpiToGarmin.append(("C\(n)", "E1 CHT\(n)", { $0 }))
}
let same: (Double) -> Double = { $0 }
jpiToGarmin.append(("OILT", "E1 OilT", same))
jpiToGarmin.append(("OILP", "E1 OilP", same))
jpiToGarmin.append(("RPM", "E1 RPM", same))
jpiToGarmin.append(("MAP", "E1 MAP", same))
jpiToGarmin.append(("HP", "E1 %Pwr", same))
jpiToGarmin.append(("BAT", "volt1", same))
jpiToGarmin.append(("FF", "E1 FFlow", same))
jpiToGarmin.append(("OAT", "OAT", { ($0 - 32) * 5 / 9 }))

func compare(_ logs: [ConvertedEngineLog], label: String) {
    let refs = [45: reference(dir + "/edm830.45.txt"), 72: reference(dir + "/edm830.72.txt")]
    check(logs.count == 2, "\(label): expected 2 flights, got \(logs.count)")
    var cells = 0
    for converted in logs {
        let log: PerspectiveLog
        do { log = try PerspectiveLogParser.parse(data: converted.data, filename: converted.filename) } catch {
            check(false, "\(label): converted \(converted.filename) did not parse: \(error)"); continue
        }
        guard let start = log.start, let ref = refs.values.first(where: { $0.first?.0 == start }) else {
            check(false, "\(label): \(converted.filename) start \(String(describing: log.start)) matches no reference flight"); continue
        }
        check(log.sampleCount == ref.count, "\(label): \(converted.filename) has \(log.sampleCount) samples, reference \(ref.count)")
        for (i, (t, row)) in ref.enumerated() where i < log.sampleCount {
            check(log.times[i] == t, "\(label): sample \(i) time \(log.times[i]) vs \(t)")
            for (jpi, garmin, f) in jpiToGarmin {
                guard let r = row[jpi], let rv = Double(r) else { continue }
                cells += 1
                let v = log.value(garmin, at: i)
                check(v != nil && abs(v! - f(rv)) < 0.06, "\(label): \(converted.filename) #\(i) \(garmin) = \(String(describing: v)), reference \(f(rv))")
            }
        }
    }
    print("::notice::\(label): compared \(cells) values, \(failures) failures so far")
}

// 1. JPI binary download.
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: dir + "/edm830.jpi"))
    let logs = try EngineLogConverter.convert(data: data, filename: "U130614.JPI", timeZone: utc)
    print("JPI binary: \(logs.map(\.filename))")
    compare(logs, label: "JPI binary")
} catch { check(false, "JPI binary failed: \(error)") }

// 2. JPI CSV exports (EZSave), one file per flight.
do {
    var logs: [ConvertedEngineLog] = []
    for name in ["edm830.45.txt", "edm830.72.txt"] {
        let data = try Data(contentsOf: URL(fileURLWithPath: dir + "/" + name))
        logs += try EngineLogConverter.convert(data: data, filename: name.replacingOccurrences(of: ".txt", with: ".csv"), timeZone: utc)
    }
    print("JPI CSV: \(logs.map(\.filename)) from \(logs.map(\.source))")
    compare(logs, label: "JPI CSV")
} catch { check(false, "JPI CSV failed: \(error)") }

func rows(_ n: Int, _ make: (Int) -> String) -> String { (0..<n).map(make).joined(separator: "\n") }

// 3. Garmin G3X: long-name row before the short-name header, Volts1 / Amps1, m/d/yy dates.
do {
    let text = """
    #airframe_info, log_version="1.00", log_content_version="1.02", product="GDU 460", aircraft_ident="N123RV",
    Date (yyyy-mm-dd),Time (hh:mm:ss),UTC Time (hh:mm:ss),UTC Offset (hh:mm),Oil Temp (deg F),Oil Press (PSI),RPM,Manifold Press (inch Hg),Volts,Amps,Fuel Flow (gal/hour),CHT1 (deg F),CHT2 (deg F),EGT1 (deg F),EGT2 (deg F)
    Lcl Date,Lcl Time,UTC Time,UTCOfst,E1 OilT,E1 OilP,E1 RPM,E1 MAP,Volts1,Amps1,E1 FFlow,E1 CHT1,E1 CHT2,E1 EGT1,E1 EGT2

    """ + rows(30) { "5/19/23,9:05:\(String(format: "%02d", $0)),13:05:\(String(format: "%02d", $0)),-04:00,180,60,2400,24.1,14.1,5,9.5,350,355,1350,1360" }
    let logs = try EngineLogConverter.convert(data: Data(text.utf8), filename: "log_230519_090500_N123RV.csv")
    check(logs.count == 1 && logs[0].source == "Garmin", "G3X: should pass through as Garmin")
    let log = try PerspectiveLogParser.parse(data: logs[0].data, filename: "g3x.csv")
    check(log.sampleCount == 30, "G3X: \(log.sampleCount) samples")
    check(log.value("E1 RPM", at: 0) == 2400, "G3X: RPM")
    check(log.value("volt1", at: 3) == 14.1, "G3X: Volts1 alias")
    let expected = cal.date(from: DateComponents(year: 2023, month: 5, day: 19, hour: 13, minute: 5, second: 0))!
    check(log.start == expected, "G3X: start \(String(describing: log.start)) vs \(expected)")
} catch { check(false, "G3X failed: \(error)") }

// 4. Dynon SkyView style: "Name (Units)", GPS Date & Time, temperatures in °C, pressure altitude.
do {
    let text = "GPS Date & Time,Session Time,Indicated Airspeed (knots),Pressure Altitude (ft.),RPM L,Manifold Pressure (inHg),Fuel Flow 1 (gal/hr),Oil Temperature (deg C),Oil Pressure (PSI),EGT 1 (deg C),EGT 2 (deg C),CHT 1 (deg C),CHT 2 (deg C),OAT (deg C),Volts (Volts)\n"
        + rows(40) { "2024-03-02 15:10:\(String(format: "%02d", $0)),\($0),110,\(5000 + $0 * 10),2500,23.5,10.2,90,62,700,710,180,185,5,13.9" }
    let logs = try EngineLogConverter.convert(data: Data(text.utf8), filename: "2024-03-02-N456D-SN1234-USER-LOG-DATA.csv", timeZone: utc)
    let log = try PerspectiveLogParser.parse(data: logs[0].data, filename: logs[0].filename)
    check(log.sampleCount == 40, "Dynon: \(log.sampleCount) samples")
    check(abs((log.value("E1 CHT1", at: 0) ?? 0) - 356) < 0.01, "Dynon: CHT1 °C -> °F: \(String(describing: log.value("E1 CHT1", at: 0)))")
    check(abs((log.value("E1 OilT", at: 0) ?? 0) - 194) < 0.01, "Dynon: oil temp °C -> °F")
    check(log.value("OAT", at: 0) == 5, "Dynon: OAT stays °C")
    check(log.value("IAS", at: 5) == 110, "Dynon: IAS")
    check(abs((log.value("VSpd", at: 20) ?? 0) - 600) < 1, "Dynon: vertical speed from altitude: \(String(describing: log.value("VSpd", at: 20)))")
    check(log.value("E1 RPM", at: 0) == 2500 && log.value("volt1", at: 0) == 13.9, "Dynon: RPM and volts")
} catch { check(false, "Dynon failed: \(error)") }

// 5. EI CGR-30P style: header block, TIME only (date from the file name), units after ';'.
do {
    let text = """
    Electronics International Inc.
    CGR-30P Flight Data Report
    Aircraft ID: N789EI
    Flight Number: 1

    TIME,RPML,RPM,MP,EGT1;*F,EGT2;*F,CHT1;*F,CHT2;*F,OILT;*F,OILP;PSI,FF;GPH,OAT;*F,VOLTS

    """ + rows(25) { "10:22:\(String(format: "%02d", $0 * 2)),2300,2300,21.0,1400,1410,330,335,185,70,9.8,59,14.0" }
    let logs = try EngineLogConverter.convert(data: Data(text.utf8), filename: "Flt0001_20130123F.csv", timeZone: utc)
    let log = try PerspectiveLogParser.parse(data: logs[0].data, filename: logs[0].filename)
    check(log.sampleCount == 25, "EI: \(log.sampleCount) samples")
    let expected = cal.date(from: DateComponents(year: 2013, month: 1, day: 23, hour: 10, minute: 22, second: 0))!
    check(log.start == expected, "EI: start \(String(describing: log.start))")
    check(log.value("E1 EGT1", at: 0) == 1400 && log.value("E1 CHT2", at: 0) == 335, "EI: EGT/CHT")
    check(abs((log.value("OAT", at: 0) ?? 0) - 15) < 0.01, "EI: OAT °F -> °C")
    check(log.value("E1 FFlow", at: 0) == 9.8 && log.value("E1 OilP", at: 0) == 70, "EI: FF and oil pressure")
    check(logs[0].data.count > 0 && String(data: logs[0].data, encoding: .utf8)!.contains("N789EI"), "EI: tail from header")
} catch { check(false, "EI failed: \(error)") }

// 6. Not an engine log.
do {
    _ = try EngineLogConverter.convert(data: Data("Name,Phone\nBob,555\n".utf8), filename: "contacts.csv")
    check(false, "contacts.csv should be rejected")
} catch let e as EngineLogImportError { check(e == .unrecognized, "contacts.csv: \(e)") } catch { check(false, "contacts.csv: \(error)") }

print(failures == 0 ? "::notice::ALL IMPORT CHECKS PASSED" : "::notice::\(failures) IMPORT CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
