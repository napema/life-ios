import Foundation
import Security

/// La sessione di Supabase, nel portachiavi dell'iPhone.
struct Sessione: Codable {
    var access: String
    var refresh: String
    var scade: Double
    var userId: String
    var email: String?
}

struct ErroreRete: LocalizedError {
    let messaggio: String
    var errorDescription: String? { messaggio }
}

/// Accesso e REST di Supabase, senza dipendenze: le stesse chiamate che fa il sito.
final class Rete: ObservableObject {
    static let s = Rete()

    @Published private(set) var sessione: Sessione?

    private let urlBase = Config.supabaseUrl
    private let sessioneURL: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    private var rinnovo: Task<Void, Error>?

    init() {
        sessione = Self.leggiPortachiavi()
    }

    var connesso: Bool { sessione != nil }
    var tokenCorrente: String? { sessione?.access }

    // MARK: Accesso

    func inviaCodice(email: String) async throws {
        _ = try await auth("otp", corpo: ["email": .str(email), "create_user": false])
    }

    func verificaCodice(email: String, codice: String) async throws {
        let r = try await auth("verify", corpo: ["email": .str(email), "token": .str(codice), "type": "email"])
        try salva(r)
    }

    /// Il link dell'email incollato: contiene il token monouso.
    func verificaLink(_ testo: String) async throws {
        if let cancelletto = testo.firstIndex(of: "#") {
            let frammento = String(testo[testo.index(after: cancelletto)...])
            var v: [String: String] = [:]
            for p in frammento.split(separator: "&") {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { v[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
            if let refresh = v["refresh_token"] {
                let r = try await auth("token?grant_type=refresh_token", corpo: ["refresh_token": .str(refresh)])
                try salva(r)
                return
            }
            if let e = v["error_description"] {
                throw ErroreRete(messaggio: "Link non valido o scaduto: \(e.replacingOccurrences(of: "+", with: " ")).")
            }
        }
        guard let c = URLComponents(string: testo),
              let token = c.queryItems?.first(where: { $0.name == "token" || $0.name == "token_hash" })?.value
        else { throw ErroreRete(messaggio: "Link non riconosciuto: copia il link dell'email.") }
        let tipo = c.queryItems?.first(where: { $0.name == "type" })?.value ?? "email"
        do {
            try salva(try await auth("verify", corpo: ["token_hash": .str(token), "type": "email"]))
        } catch {
            try salva(try await auth("verify", corpo: ["token_hash": .str(token), "type": .str(tipo)]))
        }
    }

    func accedi(email: String, password: String) async throws {
        do {
            let r = try await auth("token?grant_type=password", corpo: ["email": .str(email), "password": .str(password)])
            try salva(r)
        } catch {
            if error.localizedDescription.contains("Invalid login") {
                throw ErroreRete(messaggio: "Email o password sbagliate. La password si imposta da Impostazioni su un dispositivo dove sei già dentro.")
            }
            throw error
        }
    }

    func cambiaPassword(_ nuova: String) async throws {
        let (_, _) = try await chiedi("\(urlBase)/auth/v1/user", metodo: "PUT", corpo: (["password": .str(nuova)] as J).codificato, autenticato: true)
    }

    func esci() {
        ClienteWidget.collega(indirizzo: nil)
        sessione = nil
        Self.scriviPortachiavi(nil)
    }

    private func auth(_ percorso: String, corpo: J) async throws -> J {
        let (d, _) = try await chiedi("\(urlBase)/auth/v1/\(percorso)", metodo: "POST", corpo: corpo.codificato, autenticato: false)
        return J.parse(d)
    }

    private func salva(_ r: J) throws {
        guard let access = r.access_token.str, let refresh = r.refresh_token.str else {
            throw ErroreRete(messaggio: "Risposta di accesso non valida.")
        }
        let durata = r.expires_in.num ?? 3600
        let s = Sessione(access: access, refresh: refresh, scade: Date().timeIntervalSince1970 + durata, userId: r.user.id.t, email: r.user.email.str)
        sessione = s
        Self.scriviPortachiavi(s)
    }

    /// Un token valido, rinnovandolo se serve.
    func token() async throws -> String {
        guard let s = sessione else { throw ErroreRete(messaggio: "Accesso non fatto") }
        if s.scade - Date().timeIntervalSince1970 > 60 { return s.access }
        if let rinnovo {
            try await rinnovo.value
        } else {
            let t = Task { @MainActor in
                let r = try await self.auth("token?grant_type=refresh_token", corpo: ["refresh_token": .str(s.refresh)])
                try self.salva(r)
            }
            rinnovo = t
            defer { rinnovo = nil }
            try await t.value
        }
        return sessione?.access ?? s.access
    }

    // MARK: REST

    func chiedi(_ url: String, metodo: String, corpo: Data? = nil, intestazioni: [String: String] = [:], autenticato: Bool = true) async throws -> (Data, HTTPURLResponse) {
        guard let u = URL(string: url) else { throw ErroreRete(messaggio: "Indirizzo non valido") }
        var q = URLRequest(url: u)
        q.httpMethod = metodo
        q.httpBody = corpo
        q.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if autenticato { q.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization") }
        for (k, v) in intestazioni { q.setValue(v, forHTTPHeaderField: k) }
        let (d, r) = try await sessioneURL.data(for: q)
        guard let h = r as? HTTPURLResponse else { throw ErroreRete(messaggio: "Risposta non valida") }
        if !(200..<300).contains(h.statusCode) {
            let e = J.parse(d)
            throw ErroreRete(messaggio: e.msg.str ?? e.message.str ?? e.error_description.str ?? e.error.str ?? "Errore \(h.statusCode)")
        }
        return (d, h)
    }

    /// Una pagina di righe: `tabella?filtri`, con l'intervallo.
    func righe(_ tabella: String, _ query: String, da: Int, a: Int) async throws -> [J] {
        let (d, _) = try await chiedi("\(urlBase)/rest/v1/\(tabella)?\(query)", metodo: "GET", intestazioni: ["Range": "\(da)-\(a)", "Range-Unit": "items"])
        return J.parse(d).list
    }

    func upsert(_ tabella: String, _ righe: [J], conflitto: String = "id") async throws {
        _ = try await chiedi("\(urlBase)/rest/v1/\(tabella)?on_conflict=\(conflitto)", metodo: "POST", corpo: J.arr(righe).codificato, intestazioni: ["Prefer": "resolution=merge-duplicates"])
    }

    func elimina(_ tabella: String, ids: [String]) async throws {
        let lista = ids.joined(separator: ",")
        _ = try await chiedi("\(urlBase)/rest/v1/\(tabella)?id=in.(\(lista))", metodo: "DELETE")
    }

    func funzione(_ nome: String) async throws {
        _ = try await chiedi("\(urlBase)/functions/v1/\(nome)", metodo: "POST", corpo: Data("{}".utf8))
    }

    // MARK: Portachiavi

    private static let servizio = "life.sessione"

    private static func leggiPortachiavi() -> Sessione? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servizio, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return try? JSONDecoder().decode(Sessione.self, from: d)
    }

    private static func scriviPortachiavi(_ s: Sessione?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servizio]
        SecItemDelete(base as CFDictionary)
        guard let s, let d = try? JSONEncoder().encode(s) else { return }
        var nuovo = base
        nuovo[kSecValueData as String] = d
        nuovo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(nuovo as CFDictionary, nil)
    }
}
