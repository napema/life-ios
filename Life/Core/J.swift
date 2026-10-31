import Foundation

/// Un valore JSON. Le righe di Supabase e le risposte della logica JavaScript passano tutte da qui:
/// `movimento.imp.num`, `ciclo.da.str`, `pocket["nome"].str`.
@dynamicMemberLookup
enum J: Hashable {
    case null
    case bool(Bool)
    case num(Double)
    case str(String)
    case arr([J])
    case obj([String: J])

    subscript(dynamicMember chiave: String) -> J { self[chiave] }

    subscript(chiave: String) -> J {
        get {
            if case .obj(let o) = self { return o[chiave] ?? .null }
            return .null
        }
        set {
            if case .obj(var o) = self {
                o[chiave] = newValue
                self = .obj(o)
            }
        }
    }

    subscript(indice: Int) -> J {
        if case .arr(let a) = self, a.indices.contains(indice) { return a[indice] }
        return .null
    }

    var str: String? {
        switch self {
        case .str(let s): return s
        case .num(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        default: return nil
        }
    }
    /// Il testo, o vuoto: per le schermate.
    var t: String { str ?? "" }
    var num: Double? {
        switch self {
        case .num(let n): return n
        case .str(let s): return Double(s)
        default: return nil
        }
    }
    /// Il numero, o zero.
    var d: Double { num ?? 0 }
    var int: Int? { num.map { Int($0) } }
    /// Vero come in JavaScript: esiste e non è falso, zero o vuoto.
    var vero: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .num(let n): return n != 0 && !n.isNaN
        case .str(let s): return !s.isEmpty
        case .arr, .obj: return true
        }
    }
    var list: [J] {
        if case .arr(let a) = self { return a }
        return []
    }
    var dict: [String: J] {
        if case .obj(let o) = self { return o }
        return [:]
    }
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: JSON

    init(any: Any?) {
        switch any {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .num(n.doubleValue)
            }
        case let s as String: self = .str(s)
        case let a as [Any]: self = .arr(a.map { J(any: $0) })
        case let o as [String: Any]: self = .obj(o.mapValues { J(any: $0) })
        default: self = .null
        }
    }

    var grezzo: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .num(let n): return n
        case .str(let s): return s
        case .arr(let a): return a.map { $0.grezzo }
        case .obj(let o): return o.mapValues { $0.grezzo }
        }
    }

    static func parse(_ testo: String) -> J {
        guard let d = testo.data(using: .utf8) else { return .null }
        return parse(d)
    }

    static func parse(_ dati: Data) -> J {
        guard let v = try? JSONSerialization.jsonObject(with: dati, options: [.fragmentsAllowed]) else { return .null }
        return J(any: v)
    }

    var codificato: Data {
        (try? JSONSerialization.data(withJSONObject: grezzo, options: [.fragmentsAllowed])) ?? Data("null".utf8)
    }

    var testoJSON: String { String(decoding: codificato, as: UTF8.self) }
}

extension J: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral v: String) { self = .str(v) }
    init(integerLiteral v: Int) { self = .num(Double(v)) }
    init(floatLiteral v: Double) { self = .num(v) }
    init(booleanLiteral v: Bool) { self = .bool(v) }
    init(nilLiteral: ()) { self = .null }
    init(arrayLiteral e: J...) { self = .arr(e) }
    init(dictionaryLiteral e: (String, J)...) { self = .obj(Dictionary(e, uniquingKeysWith: { _, b in b })) }
}

extension J {
    /// Da un testo opzionale: nil diventa null.
    static func opz(_ s: String?) -> J { s.map { .str($0) } ?? .null }
    static func n(_ v: Int) -> J { .num(Double(v)) }
}
