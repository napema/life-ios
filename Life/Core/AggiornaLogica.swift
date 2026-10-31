import Foundation

extension Logica {
    /// Va alzato quando Swift e logica smettono di capirsi (una funzione nativa nuova, un dato che
    /// le schermate leggono in modo diverso): i telefoni con l'app vecchia ignorano gli aggiornamenti
    /// finché non installano l'IPA nuova. Da qui lo legge anche costruisci.mjs.
    static let contratto = 1
}

/// Calcoli, regole e testi della logica arrivano senza reinstallare: all'apertura, e ogni minuto
/// finché Life è aperta, si guarda se su GitHub c'è un logica.js nuovo. Le schermate in Swift no:
/// quelle richiedono l'IPA.
enum AggiornaLogica {
    private static let indirizzi = [
        // Risponde subito, ma ha un limite di richieste per rete; il secondo non ha limiti ma tiene la copia fino a 5 minuti
        "https://api.github.com/repos/napema/life-ios/contents/Life/Risorse/logica.js",
        "https://raw.githubusercontent.com/napema/life-ios/main/Life/Risorse/logica.js",
    ]
    private static let intervallo: TimeInterval = 50

    private static let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("logica-scaricata.js")
    }()

    private static var preferenze: UserDefaults { .standard }

    /// Segnato mentre si esegue codice scaricato: se all'avvio è ancora lì, quel codice ha bloccato l'app.
    static func inizioProva(_ versione: Int64) { preferenze.set(String(versione), forKey: "logica.inProva") }
    static func fineProva() { preferenze.removeObject(forKey: "logica.inProva") }

    static func codiceDelBundle() -> String? {
        guard let url = Bundle.main.url(forResource: "logica", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func codiceScaricato() -> String? {
        if let v = Int64(preferenze.string(forKey: "logica.inProva") ?? "") {
            fineProva()
            scarta(v)
        }
        return try? String(contentsOf: file, encoding: .utf8)
    }

    static func togliScaricato() { try? FileManager.default.removeItem(at: file) }

    /// Una versione scartata non si riprova: ne serve una più recente.
    static func scarta(_ versione: Int64) { preferenze.set(String(versione), forKey: "logica.scartata") }

    static var scartata: Int64 { Int64(preferenze.string(forKey: "logica.scartata") ?? "") ?? 0 }

    /// La prima riga del file: `// life-logica contratto=1 versione=1793…`.
    static func testata(_ codice: String) -> (contratto: Int, versione: Int64)? {
        let riga = codice.prefix(120).split(separator: "\n", maxSplits: 1).first ?? ""
        let parti = riga.split(separator: " ")
        guard parti.count == 4, parti[1] == "life-logica",
              let c = Int(parti[2].dropFirst("contratto=".count)),
              let v = Int64(parti[3].dropFirst("versione=".count))
        else { return nil }
        return (c, v)
    }

    @MainActor
    static func controlla() async {
        let ambiente = ProcessInfo.processInfo.environment
        var elenco = indirizzi
        if ambiente["LIFE_DEMO"] != nil {
            #if DEBUG
            // Le prove della compilazione: un file di prova, oppure «reale» per gli indirizzi veri
            guard let prova = ambiente["LIFE_LOGICA_URL"] else { return }
            if prova != "reale" { elenco = [prova] }
            #else
            return
            #endif
        }
        if let u = Logica.s.ultimoControllo, Date().timeIntervalSince(u) < intervallo { return }
        Logica.s.ultimoControllo = Date()

        for indirizzo in elenco {
            guard let url = URL(string: indirizzo) else { continue }
            var q = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            q.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
            let chiaveEtag = "logica.etag.\(indirizzo)"
            if let e = preferenze.string(forKey: chiaveEtag) { q.setValue(e, forHTTPHeaderField: "If-None-Match") }
            guard let (dati, risposta) = try? await URLSession.shared.data(for: q) else { continue }
            let http = risposta as? HTTPURLResponse
            let stato = http?.statusCode ?? 200 // un file di prova non ha uno stato
            if stato == 304 { return }
            guard stato == 200 else { continue }
            installa(String(decoding: dati, as: UTF8.self))
            if let e = http?.value(forHTTPHeaderField: "ETag") { preferenze.set(e, forKey: chiaveEtag) }
            return
        }
    }

    @MainActor
    private static func installa(_ codice: String) {
        guard let t = testata(codice), t.contratto == Logica.contratto,
              t.versione > Logica.s.versioneLogica, t.versione != scartata
        else { return }
        inizioProva(t.versione)
        let riuscito = Logica.s.sostituisci(codice: codice, versione: t.versione, scaricata: true)
        fineProva()
        guard riuscito else {
            scarta(t.versione)
            return
        }
        // Solo ora prende il posto di quella salvata: se la nuova non va, resta l'ultima buona
        try? codice.write(to: file, atomically: true, encoding: .utf8)
        Logica.s.mostra("Life aggiornata", "info")
    }
}
