import Foundation
import JavaScriptCore
import UIKit

/// La logica di Life (finanze, abitudini, training, mobilità, pasti, parser dei task) è la stessa
/// del sito: gira qui dentro, in JavaScriptCore. Le schermate la chiamano con
/// `Logica.s.chiama("finanze.calcolo.pocketConSaldi")`. Tutto sul thread principale.
/// Una lettura ricordata: funzione e argomenti.
struct ChiaveLettura: Hashable {
    let percorso: String
    let argomenti: [J]
}

/// Gli avvisi a parte: comparire non deve ridisegnare ogni schermata.
final class Avvisi: ObservableObject {
    static let s = Avvisi()
    @Published var avviso: Logica.Avviso?
}

/// Quanto costa davvero avviare e usare Life: si legge nelle Impostazioni.
final class Misure {
    static let s = Misure()
    private let serratura = NSLock()
    private let partenza = Date()
    private(set) var segnati: [String: Double] = [:]
    private var chiamate: [String: (n: Int, t: Double)] = [:]

    func segna(_ nome: String, _ secondi: Double) {
        serratura.lock()
        segnati[nome] = secondi * 1000
        serratura.unlock()
    }

    /// Dall'avvio del processo a adesso.
    func traguardo(_ nome: String) { segna(nome, Date().timeIntervalSince(partenza)) }

    func chiamata(_ percorso: String, _ secondi: Double) {
        serratura.lock()
        var c = chiamate[percorso] ?? (0, 0)
        c.n += 1
        c.t += secondi * 1000
        chiamate[percorso] = c
        serratura.unlock()
    }

    var riepilogo: String {
        serratura.lock()
        defer { serratura.unlock() }
        let primo = Int(segnati["primo frame"] ?? 0)
        let logica = Int(segnati["logica"] ?? 0)
        return "\(primo) ms (logica \(logica) ms)"
    }

    func salva() {
        serratura.lock()
        let top = chiamate.sorted { $0.value.t > $1.value.t }.prefix(40)
        let elenco: [String: Any] = [
            "tempi": segnati,
            "totale_ms": chiamate.values.reduce(0) { $0 + $1.t },
            "chiamate": chiamate.values.reduce(0) { $0 + $1.n },
            "peggiori": top.map { ["p": $0.key, "n": $0.value.n, "ms": Int($0.value.t)] as [String: Any] },
        ]
        serratura.unlock()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let d = try? JSONSerialization.data(withJSONObject: elenco, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: dir.appendingPathComponent("misure.json"))
        }
    }
}

final class Logica: ObservableObject {
    static let s = Logica()

    /// Cresce quando un dato dei moduli cambia: chi lo osserva si ridisegna.
    @Published private(set) var versione = 0

    struct Avviso: Identifiable, Equatable {
        let id = UUID()
        let testo: String
        let tipo: String
    }

    /// Il JavaScript si prepara in sottofondo: lo aspetta solo chi deve davvero eseguirlo.
    private var contestoPronto: JSContext!
    private let pronto = DispatchGroup()
    private var contesto: JSContext {
        pronto.wait()
        return contestoPronto
    }
    /// Ogni contesto ha il suo numero: quello sostituito da un aggiornamento non scrive più nulla.
    private var generazione = 0
    private var ultimaGenerazione = 0
    private var avviata = false
    /// Quando è stata costruita la logica in uso e se arriva da un aggiornamento.
    private(set) var versioneLogica: Int64 = 0
    private(set) var logicaScaricata = false
    var ultimoControllo: Date?
    private var timer: [Int: Timer] = [:]
    private let serratura = NSRecursiveLock()
    private var ricordati: [ChiaveLettura: J] = [:]
    private var giroRicordi = 0
    private var ultimoGiorno = ""
    private var ultimoRicalcolo = Date.distantPast
    private var ultimeLetture: [ChiaveLettura: Int] = [:]
    private var contatoreLetture = 0
    private var riscaldamento: DispatchWorkItem?
    private let fileLetture: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("letture-recenti.json")
    }()
    private var prossimoTimer = 1
    private var memoria: [String: String] = [:]
    private var salvataggio: DispatchWorkItem?
    private var chiudiAvviso: DispatchWorkItem?
    private var segnale: DispatchWorkItem?
    private let fileMemoria: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("memoria-locale.json")
    }()

    init() {
        if let d = try? Data(contentsOf: fileMemoria), let m = try? JSONDecoder().decode([String: String].self, from: d) {
            memoria = m
        }
        caricaLetture()
        ultimoGiorno = Tempo.oggi()
        ultimoRicalcolo = Date()
        pronto.enter()
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            let t0 = Date()
            caricaAllAvvio()
            Misure.s.segna("logica", Date().timeIntervalSince(t0))
            pronto.leave()
        }
    }

    // MARK: Il codice in uso

    private func caricaAllAvvio() {
        let delBundle = AggiornaLogica.codiceDelBundle()
        let versioneBundle = delBundle.flatMap(AggiornaLogica.testata)?.versione ?? 0
        if let scaricato = AggiornaLogica.codiceScaricato(), let t = AggiornaLogica.testata(scaricato),
           t.contratto == Logica.contratto, t.versione > versioneBundle, t.versione != AggiornaLogica.scartata {
            AggiornaLogica.inizioProva(t.versione)
            let nuovo = creaContesto(scaricato)
            AggiornaLogica.fineProva()
            if nuovo.funziona {
                contestoPronto = nuovo.contesto
                versioneLogica = t.versione
                logicaScaricata = true
                return
            }
            AggiornaLogica.scarta(t.versione)
            AggiornaLogica.togliScaricato()
        } else {
            AggiornaLogica.togliScaricato()
        }
        guard let delBundle else {
            print("[logica] bundle mancante")
            contestoPronto = JSContext()
            return
        }
        contestoPronto = creaContesto(delBundle).contesto
        versioneLogica = versioneBundle
    }

    /// Un contesto nuovo col codice dato, e la prova che risponda davvero.
    private func creaContesto(_ codice: String) -> (contesto: JSContext, funziona: Bool) {
        let c = JSContext()!
        var errore = false
        c.exceptionHandler = { _, e in
            errore = true
            print("[js] \(e?.toString() ?? "?")")
        }
        ultimaGenerazione += 1
        generazione = ultimaGenerazione
        installaNativo(in: c)
        c.evaluateScript(codice)
        let risposta = c.objectForKeyedSubscript("__chiama")?.call(withArguments: ["home.saluto", "[9]"])?.toString() ?? ""
        let funziona = !errore && !(J.parse(risposta).ok.str ?? "").isEmpty
        c.exceptionHandler = { _, e in print("[js] \(e?.toString() ?? "?")") }
        return (c, funziona)
    }

    /// Prova il codice appena scaricato e, se risponde, lo mette al posto di quello in uso.
    /// Come ricaricare il sito: i dati stanno in memoria e la sincronizzazione riparte dal suo giro.
    func sostituisci(codice: String, versione: Int64, scaricata: Bool) -> Bool {
        let vecchiaGenerazione = generazione
        let vecchiTimer = timer
        timer = [:]
        let nuovo = creaContesto(codice)
        guard nuovo.funziona else {
            timer.values.forEach { $0.invalidate() }
            timer = vecchiTimer
            generazione = vecchiaGenerazione
            return false
        }
        vecchiTimer.values.forEach { $0.invalidate() }
        contestoPronto = nuovo.contesto
        versioneLogica = versione
        logicaScaricata = scaricata
        if avviata {
            contesto.objectForKeyedSubscript("__avvia")?.call(withArguments: [])
            visibile(true)
        }
        segnalaCambio()
        return true
    }

    private func segnalaCambio() { versione &+= 1 }

    /// Dalle Impostazioni: lascia l'aggiornamento e torna alla logica compresa nell'app.
    func usaLogicaDelBundle() {
        guard let codice = AggiornaLogica.codiceDelBundle(), let t = AggiornaLogica.testata(codice) else { return }
        AggiornaLogica.scarta(versioneLogica)
        AggiornaLogica.togliScaricato()
        _ = sostituisci(codice: codice, versione: t.versione, scaricata: false)
    }

    // MARK: Chiamate

    /// Chiama una funzione della logica (o legge un valore). `percorso` come «finanze.dati.stato».
    @discardableResult
    func chiama(_ percorso: String, _ argomenti: J...) -> J { chiama(percorso, argomenti: argomenti) }

    @discardableResult
    func chiama(_ percorso: String, argomenti: [J]) -> J {
        guard Logica.eLettura(percorso) else {
            dimentica()
            let r = esegui(percorso, argomenti)
            dimentica()
            return r
        }
        let chiave = ChiaveLettura(percorso: percorso, argomenti: argomenti)
        serratura.lock()
        contatoreLetture &+= 1
        ultimeLetture[chiave] = contatoreLetture
        let noto = ricordati[chiave]
        let giro = giroRicordi
        serratura.unlock()
        if let noto { return noto }
        let r = esegui(percorso, argomenti)
        serratura.lock()
        if giro == giroRicordi { ricordati[chiave] = r }
        serratura.unlock()
        return r
    }

    private func esegui(_ percorso: String, _ argomenti: [J]) -> J {
        let t0 = Date()
        defer { Misure.s.chiamata(percorso, Date().timeIntervalSince(t0)) }
        guard let f = contesto.objectForKeyedSubscript("__chiama"),
              let r = f.call(withArguments: [percorso, J.arr(argomenti).testoJSON])?.toString()
        else { return .null }
        let risposta = J.parse(r)
        if let e = risposta.errore.str { print("[logica] \(percorso): \(e)") }
        return risposta.ok
    }

    // MARK: Le letture già pronte
    //
    // In un'app firmata così JavaScript gira senza compilatore veloce: ogni calcolo costa. Le letture
    // non cambiano nulla, quindi si ricordano finché un dato non cambia e si rifanno in sottofondo,
    // così quando apri una mini-app i numeri ci sono già.

    private static let scritture = try! NSRegularExpression(pattern: "^(alterna|elimina|salva|scrivi|aggiungi|cambia|modifica|ripara|ripristina|pianifica|scegli|togli|segna|sblocca|riancora|impara|migra|applica|chiudi|esegui|registra|conferma|assicura|rigenera|spunta|fai|dimentica|nuovoId|meta$|prepara|unisci)")
    private static var gia: [String: Bool] = [:]
    private static let serraturaPercorsi = NSLock()

    static func eLettura(_ percorso: String) -> Bool {
        serraturaPercorsi.lock()
        defer { serraturaPercorsi.unlock() }
        if let n = gia[percorso] { return n }
        let parti = percorso.split(separator: ".")
        let ultimo = String(parti.last ?? "")
        var lettura = scritture.firstMatch(in: ultimo, range: NSRange(ultimo.startIndex..., in: ultimo)) == nil
        if percorso.contains(".importa.") || percorso.contains(".revolut.") || percorso.contains(".hevy.") || percorso.contains(".garmin.") { lettura = false }
        if percorso.contains(".ponte."), ultimo != "getState" { lettura = false }
        gia[percorso] = lettura
        return lettura
    }

    /// Un dato è cambiato: ciò che era stato letto non vale più.
    func dimentica() {
        serratura.lock()
        ricordati.removeAll(keepingCapacity: true)
        giroRicordi &+= 1
        serratura.unlock()
        riscaldaPresto(1.2)
    }

    /// Dopo una scrittura dell'archivio: i moduli leggono anche da lì.
    func datiCambiati() { dimentica() }

    private func riscaldaPresto(_ ritardo: TimeInterval) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.riscaldaPresto(ritardo) }
            return
        }
        riscaldamento?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.riscalda() }
        riscaldamento = w
        DispatchQueue.main.asyncAfter(deadline: .now() + ritardo, execute: w)
    }

    /// Rifà in sottofondo le letture usate di recente, dalla più recente. Con `tutte` rifà anche quelle
    /// riprese dalla sessione precedente e poi ridisegna.
    func riscalda(tutte: Bool = false) {
        serratura.lock()
        let giro = giroRicordi
        let daFare = ultimeLetture.sorted { $0.value > $1.value }.lazy.map(\.key).filter { !$0.percorso.hasPrefix("ui.") && (tutte || self.ricordati[$0] == nil) }.prefix(300).map { $0 }
        serratura.unlock()
        guard !daFare.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for chiave in daFare {
                guard let self else { return }
                self.serratura.lock()
                let valido = self.giroRicordi == giro
                self.serratura.unlock()
                guard valido else { return }
                let r = self.esegui(chiave.percorso, chiave.argomenti)
                self.serratura.lock()
                if self.giroRicordi == giro { self.ricordati[chiave] = r }
                self.serratura.unlock()
            }
            if tutte { DispatchQueue.main.async { self?.versione &+= 1 } }
        }
    }

    /// All'avvio: le letture della volta scorsa e, se è lo stesso giorno, anche i loro risultati.
    /// Così la prima schermata si disegna subito; poi si ricontrolla tutto in sottofondo.
    private func caricaLetture() {
        guard let d = try? Data(contentsOf: fileLetture) else { return }
        let f = J.parse(d)
        let stessoGiorno = f.g.str == Tempo.oggi()
        var i = 0
        for voce in f.l.list.reversed() {
            guard let p = voce.p.str else { continue }
            i += 1
            let chiave = ChiaveLettura(percorso: p, argomenti: voce.a.list)
            ultimeLetture[chiave] = i
            if stessoGiorno, case .obj(let o) = voce, let v = o["v"] { ricordati[chiave] = v }
        }
        contatoreLetture = i
    }

    func salvaLetture() {
        serratura.lock()
        let voci = ultimeLetture.sorted { $0.value > $1.value }.prefix(500).map(\.key)
        ultimeLetture = Dictionary(uniqueKeysWithValues: voci.enumerated().map { ($1, voci.count - $0) })
        contatoreLetture = voci.count
        let valori = ricordati
        serratura.unlock()
        let f = fileLetture
        let giorno = Tempo.oggi()
        DispatchQueue.global(qos: .utility).async {
            let elenco: [J] = voci.map { chiave in
                var o: [String: J] = ["p": .str(chiave.percorso), "a": .arr(chiave.argomenti)]
                // I risultati enormi (tutti i movimenti) non valgono il tempo di rileggerli
                if let v = valori[chiave], v.codificato.count < 100_000 { o["v"] = v }
                return .obj(o)
            }
            let tutto: J = .obj(["g": .str(giorno), "l": .arr(elenco)])
            try? tutto.codificato.write(to: f, options: .atomic)
        }
    }

    /// Il primo giro, appena la prima schermata è in piedi.
    func preparaLetture() { riscalda(tutte: true) }

    func avvia() {
        avviata = true
        contesto.objectForKeyedSubscript("__avvia")?.call(withArguments: [])
    }
    func sincronizza() { contesto.objectForKeyedSubscript("__sincronizza")?.call(withArguments: []) }
    func battito() {
        // Molti calcoli dipendono dall'ora: si rifanno ogni tanto e quando cambia il giorno
        let oggi = Tempo.oggi()
        if oggi != ultimoGiorno || Date().timeIntervalSince(ultimoRicalcolo) > 240 {
            ultimoGiorno = oggi
            ultimoRicalcolo = Date()
            dimentica()
        }
        contesto.objectForKeyedSubscript("__battito")?.call(withArguments: [])
    }
    func eventiCambiati() { contesto.objectForKeyedSubscript("__eventiCambiati")?.call(withArguments: []) }
    func visibile(_ si: Bool) { contesto.objectForKeyedSubscript("__visibile")?.call(withArguments: [si]) }

    // MARK: Memoria locale

    func salvaMemoriaOra() {
        salvataggio?.cancel()
        salvaLetture()
        serratura.lock()
        let m = memoria
        serratura.unlock()
        let f = fileMemoria
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(m) { try? d.write(to: f, options: .atomic) }
        }
    }

    /// All'uscita dall'account i dati dei moduli di questo telefono se ne vanno.
    func azzeraMemoria() {
        serratura.lock()
        memoria = [:]
        ultimeLetture = [:]
        serratura.unlock()
        dimentica()
        try? FileManager.default.removeItem(at: fileMemoria)
    }

    private func salvaMemoriaPresto() {
        salvataggio?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.salvaMemoriaOra() }
        salvataggio = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    // MARK: Il ponte

    private func installaNativo(in contesto: JSContext) {
        let n = JSValue(newObjectIn: contesto)!
        let mia = generazione

        let leggi: @convention(block) (String) -> Any = { [weak self] k in
            guard let self else { return NSNull() }
            self.serratura.lock()
            defer { self.serratura.unlock() }
            if let v = self.memoria[k] { return v }
            return NSNull()
        }
        let scrivi: @convention(block) (String, String) -> Void = { [weak self] k, v in
            guard let self, self.generazione == mia else { return }
            self.serratura.lock()
            self.memoria[k] = v
            self.serratura.unlock()
            self.dimentica()
            self.salvaMemoriaPresto()
        }
        let togli: @convention(block) (String) -> Void = { [weak self] k in
            guard let self, self.generazione == mia else { return }
            self.serratura.lock()
            self.memoria[k] = nil
            self.serratura.unlock()
            self.dimentica()
            self.salvaMemoriaPresto()
        }
        let chiavi: @convention(block) () -> String = { [weak self] in
            guard let self else { return "[]" }
            self.serratura.lock()
            defer { self.serratura.unlock() }
            return J.arr(self.memoria.keys.sorted().map { .str($0) }).testoJSON
        }
        let base64: @convention(block) (String) -> String = { t in Data(t.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }).base64EncodedString() }
        let log: @convention(block) (String) -> Void = { print("[js] \($0)") }
        let avvisa: @convention(block) (String, String) -> Void = { [weak self] testo, tipo in
            DispatchQueue.main.async { self?.mostra(testo, tipo) }
        }
        let copia: @convention(block) (String) -> Void = { UIPasteboard.general.string = $0 }
        let uuid: @convention(block) () -> String = { UUID().uuidString.lowercased() }
        let token: @convention(block) () -> Any = { Rete.s.tokenCorrente ?? NSNull() }
        let utente: @convention(block) () -> Any = {
            guard let s = Rete.s.sessione else { return NSNull() }
            return (["id": .str(s.userId), "email": J.opz(s.email)] as J).testoJSON
        }
        let configurazione: @convention(block) (String) -> String = { $0 == "url" ? Config.supabaseUrl : Config.supabaseKey }
        let datiCambiati: @convention(block) () -> Void = { [weak self] in
            if self?.generazione == mia { self?.segnala() }
        }
        let tabella: @convention(block) (String) -> String = { J.arr(Archivio.s.tutte($0)).testoJSON }
        let scriviRighe: @convention(block) (String, String) -> Void = { [weak self] nome, json in
            guard self?.generazione == mia else { return }
            let righe = J.parse(json).list
            DispatchQueue.main.async { Archivio.s.scrivi(nome, righe) }
        }
        let nuovoTimer: @convention(block) (Double, Bool, JSValue) -> Int = { [weak self] ms, ripeti, fn in
            guard let self, self.generazione == mia else { return 0 }
            self.serratura.lock()
            let id = self.prossimoTimer
            self.prossimoTimer += 1
            let t = Timer(timeInterval: max(0.001, ms / 1000), repeats: ripeti) { [weak self] _ in
                guard let self, self.generazione == mia else { return }
                if !ripeti {
                    self.serratura.lock()
                    self.timer[id] = nil
                    self.serratura.unlock()
                }
                fn.call(withArguments: [])
            }
            self.timer[id] = t
            self.serratura.unlock()
            RunLoop.main.add(t, forMode: .common)
            return id
        }
        let fermaTimer: @convention(block) (Int) -> Void = { [weak self] id in
            guard let self else { return }
            self.serratura.lock()
            let t = self.timer[id]
            self.timer[id] = nil
            self.serratura.unlock()
            t?.invalidate()
        }
        let richiesta: @convention(block) (String, String, String, JSValue, JSValue) -> Void = { url, metodo, intestazioni, corpo, fatto in
            guard let u = URL(string: url) else {
                fatto.call(withArguments: [0, "", "Indirizzo non valido"])
                return
            }
            var q = URLRequest(url: u)
            q.httpMethod = metodo
            for (k, v) in J.parse(intestazioni).dict { q.setValue(v.t, forHTTPHeaderField: k) }
            if corpo.isString, let c = corpo.toString() { q.httpBody = Data(c.utf8) }
            Task { @MainActor in
                do {
                    // Il token può essere appena scaduto: lo si rinnova prima di partire
                    if Rete.s.connesso, let t = try? await Rete.s.token() { q.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
                    let (d, r) = try await URLSession.shared.data(for: q)
                    fatto.call(withArguments: [(r as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: d, as: UTF8.self), NSNull()])
                } catch {
                    fatto.call(withArguments: [0, "", error.localizedDescription])
                }
            }
        }

        let voci: [(String, Any)] = [
            ("base64", base64), ("leggi", leggi), ("scrivi", scrivi), ("togli", togli), ("chiavi", chiavi), ("log", log),
            ("avviso", avvisa), ("copia", copia), ("uuid", uuid), ("token", token), ("utente", utente),
            ("configurazione", configurazione), ("datiCambiati", datiCambiati), ("tabella", tabella),
            ("scriviRighe", scriviRighe), ("timer", nuovoTimer), ("fermaTimer", fermaTimer), ("fetch", richiesta),
        ]
        for (nome, blocco) in voci {
            n.setObject(blocco, forKeyedSubscript: nome as NSString)
        }
        contesto.setObject(n, forKeyedSubscript: "Nativo" as NSString)
    }

    private func segnala() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.segnala() }
            return
        }
        dimentica()
        segnale?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.versione &+= 1 }
        segnale = w
        DispatchQueue.main.async(execute: w)
    }

    func mostra(_ testo: String, _ tipo: String = "info") {
        chiudiAvviso?.cancel()
        Avvisi.s.avviso = Avviso(testo: testo, tipo: tipo)
        if tipo == "errore" {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else if tipo == "festa" {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let w = DispatchWorkItem { Avvisi.s.avviso = nil }
        chiudiAvviso = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (tipo == "errore" ? 5 : 2.6), execute: w)
    }
}
