import Foundation

/// Come src/lib/time.ts: gli istanti sono in UTC, la UI ragiona in Europe/Rome.
/// Le date di calendario sono stringhe 'yyyy-MM-dd', gli orari 'HH:mm'.
enum Tempo {
    static let roma = TimeZone(identifier: "Europe/Rome")!
    static var calRoma: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = roma
        c.firstWeekday = 2
        return c
    }()
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private static let isoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoSec: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let settimanaBreve = ["dom", "lun", "mar", "mer", "gio", "ven", "sab"]
    static let settimanaLunga = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]
    static let mesiBrevi = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
    static let mesiLunghi = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"]

    /// Un istante scritto come `toISOString()`: sempre «.000Z», così confrontare stringhe è confrontare istanti.
    static func iso(_ d: Date) -> String { isoMs.string(from: d) }
    static func adessoIso() -> String { iso(Date()) }

    static func data(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = isoMs.date(from: s) ?? isoSec.date(from: s) { return d }
        // «2026-10-25 23:00:00+00», microsecondi e simili: si porta a una forma standard
        var t = s.replacingOccurrences(of: " ", with: "T")
        if let r = t.range(of: #"\.\d+"#, options: .regularExpression) {
            let frazione = String(t[r].prefix(4)).padding(toLength: 4, withPad: "0", startingAt: 0)
            t.replaceSubrange(r, with: frazione)
        }
        if let r = t.range(of: #"[+-]\d{2}$"#, options: .regularExpression) { t.replaceSubrange(r, with: String(t[r]) + ":00") }
        if let r = t.range(of: #"([+-]\d{2})(\d{2})$"#, options: .regularExpression) {
            let v = String(t[r])
            t.replaceSubrange(r, with: v.prefix(3) + ":" + v.suffix(2))
        }
        return isoMs.date(from: t) ?? isoSec.date(from: t)
    }

    /// Riporta gli istanti al formato unico. Lascia stare tutto il resto.
    static func normalizza(_ riga: J) -> J {
        guard case .obj(var o) = riga else { return riga }
        for (k, v) in o {
            guard case .str(let s) = v, s.count >= 16, s.contains(":"), s.first?.isNumber == true else { continue }
            guard s.range(of: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$"#, options: .regularExpression) != nil else { continue }
            if s.hasSuffix("Z"), s.count == 24 { continue }
            if let d = data(s) { o[k] = .str(iso(d)) }
        }
        return .obj(o)
    }

    static func ymd(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }

    static func parti(_ s: String) -> (Int, Int, Int) {
        let p = s.split(separator: "-").map { Int($0) ?? 0 }
        return (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }

    static func oggi(_ adesso: Date = Date()) -> String { dataRoma(adesso) }

    static func dataRoma(_ d: Date) -> String {
        let c = calRoma.dateComponents([.year, .month, .day], from: d)
        return ymd(c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }
    static func dataRoma(_ iso: String?) -> String? { data(iso).map { dataRoma($0) } }

    static func oraRoma(_ d: Date) -> String {
        let c = calRoma.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    static func oraRoma(_ iso: String?) -> String? { data(iso).map { oraRoma($0) } }

    /// Data (e ora) di Roma → istante. Senza ora: mezzanotte di Roma.
    static func istante(_ giorno: String, _ ora: String? = nil) -> Date {
        let (y, m, d) = parti(giorno)
        var c = DateComponents(year: y, month: m, day: d, hour: 0, minute: 0)
        if let ora {
            let o = ora.split(separator: ":").map { Int($0) ?? 0 }
            c.hour = o.first ?? 0
            c.minute = o.count > 1 ? o[1] : 0
        }
        return calRoma.date(from: c) ?? Date()
    }

    static func piuGiorni(_ giorno: String, _ n: Int) -> String {
        let (y, m, d) = parti(giorno)
        let base = utc.date(from: DateComponents(year: y, month: m, day: d + n)) ?? Date()
        let c = utc.dateComponents([.year, .month, .day], from: base)
        return ymd(c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    static func piuMesi(_ giorno: String, _ n: Int) -> String {
        let (y, m, d) = parti(giorno)
        let totale = y * 12 + (m - 1) + n
        let ny = Int((Double(totale) / 12).rounded(.down))
        let nm = totale - ny * 12 + 1
        return ymd(ny, nm, min(d, giorniNelMese(ny, nm)))
    }

    static func giorniNelMese(_ y: Int, _ m: Int) -> Int {
        let base = utc.date(from: DateComponents(year: y, month: m, day: 1)) ?? Date()
        return utc.range(of: .day, in: .month, for: base)?.count ?? 30
    }

    /// 0 = domenica … 6 = sabato
    static func giornoSettimana(_ giorno: String) -> Int {
        let (y, m, d) = parti(giorno)
        let base = utc.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
        return (utc.component(.weekday, from: base) + 6) % 7
    }

    static func lunediDi(_ giorno: String) -> String { piuGiorni(giorno, -((giornoSettimana(giorno) + 6) % 7)) }

    static func giorniTra(_ a: String, _ b: String) -> Int {
        let (y1, m1, d1) = parti(a)
        let (y2, m2, d2) = parti(b)
        let da = utc.date(from: DateComponents(year: y1, month: m1, day: d1)) ?? Date()
        let fine = utc.date(from: DateComponents(year: y2, month: m2, day: d2)) ?? Date()
        return Int((fine.timeIntervalSince(da) / 86400).rounded())
    }

    /// Intervallo UTC del giorno di Roma [inizio, fine)
    static func intervallo(_ giorno: String) -> (String, String) {
        (iso(istante(giorno)), iso(istante(piuGiorni(giorno, 1))))
    }

    /// "oggi", "domani", "lun 19 ott", "mer 3 feb 2027"
    static func etichetta(_ giorno: String) -> String {
        let o = oggi()
        if giorno == o { return "oggi" }
        if giorno == piuGiorni(o, 1) { return "domani" }
        if giorno == piuGiorni(o, -1) { return "ieri" }
        let (y, m, d) = parti(giorno)
        let base = "\(settimanaBreve[giornoSettimana(giorno)]) \(d) \(mesiBrevi[max(0, m - 1)])"
        return y == parti(o).0 ? base : "\(base) \(y)"
    }

    static func breve(_ giorno: String) -> String {
        let (_, m, d) = parti(giorno)
        return "\(d) \(mesiBrevi[max(0, m - 1)])"
    }
}

extension String {
    /// Prima lettera maiuscola.
    var maiuscola: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
