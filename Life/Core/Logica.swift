import Foundation
import JavaScriptCore
import UIKit

/// La logica di Life (finanze, abitudini, training, mobilità, pasti, parser dei task) è la stessa
/// del sito: gira qui dentro, in JavaScriptCore. Le schermate la chiamano con
/// `Logica.s.chiama("finanze.calcolo.pocketConSaldi")`. Tutto sul thread principale.
final class Logica: ObservableObject {
    static let s = Logica()

    /// Cresce quando un dato dei moduli cambia: chi lo osserva si ridisegna.
    @Published private(set) var versione = 0
    @Published var avviso: Avviso?

    struct Avviso: Identifiable, Equatable {
        let id = UUID()
        let testo: String
        let tipo: String
    }

    private let contesto: JSContext
    private var timer: [Int: Timer] = [:]
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
        contesto = JSContext()
        contesto.exceptionHandler = { _, e in
            print("[js] \(e?.toString() ?? "?")")
        }
        if let d = try? Data(contentsOf: fileMemoria), let m = try? JSONDecoder().decode([String: String].self, from: d) {
            memoria = m
        }
        installaNativo()
        guard let url = Bundle.main.url(forResource: "logica", withExtension: "js"), let codice = try? String(contentsOf: url, encoding: .utf8) else {
            print("[logica] bundle mancante")
            return
        }
        contesto.evaluateScript(codice)
    }

    // MARK: Chiamate

    /// Chiama una funzione della logica (o legge un valore). `percorso` come «finanze.dati.stato».
    @discardableResult
    func chiama(_ percorso: String, _ argomenti: J...) -> J { chiama(percorso, argomenti: argomenti) }

    @discardableResult
    func chiama(_ percorso: String, argomenti: [J]) -> J {
        guard let f = contesto.objectForKeyedSubscript("__chiama"),
              let r = f.call(withArguments: [percorso, J.arr(argomenti).testoJSON])?.toString()
        else { return .null }
        let risposta = J.parse(r)
        if let e = risposta.errore.str { print("[logica] \(percorso): \(e)") }
        return risposta.ok
    }

    /// Per le funzioni che rispondono con una promessa.
    func chiamaAsync(_ percorso: String, _ argomenti: J...) async -> J {
        await withCheckedContinuation { (c: CheckedContinuation<J, Never>) in
            let fatto: @convention(block) (String) -> Void = { testo in
                c.resume(returning: J.parse(testo).ok)
            }
            contesto.objectForKeyedSubscript("__chiamaAsync")?.call(withArguments: [percorso, J.arr(argomenti).testoJSON, unsafeBitCast(fatto, to: AnyObject.self)])
        }
    }

    func avvia() { contesto.objectForKeyedSubscript("__avvia")?.call(withArguments: []) }
    func sincronizza() { contesto.objectForKeyedSubscript("__sincronizza")?.call(withArguments: []) }
    func battito() { contesto.objectForKeyedSubscript("__battito")?.call(withArguments: []) }
    func eventiCambiati() { contesto.objectForKeyedSubscript("__eventiCambiati")?.call(withArguments: []) }
    func visibile(_ si: Bool) { contesto.objectForKeyedSubscript("__visibile")?.call(withArguments: [si]) }

    // MARK: Memoria locale

    func salvaMemoriaOra() {
        salvataggio?.cancel()
        let m = memoria
        let f = fileMemoria
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(m) { try? d.write(to: f, options: .atomic) }
        }
    }

    /// All'uscita dall'account i dati dei moduli di questo telefono se ne vanno.
    func azzeraMemoria() {
        memoria = [:]
        try? FileManager.default.removeItem(at: fileMemoria)
    }

    private func salvaMemoriaPresto() {
        salvataggio?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.salvaMemoriaOra() }
        salvataggio = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    // MARK: Il ponte

    private func installaNativo() {
        let n = JSValue(newObjectIn: contesto)!

        let leggi: @convention(block) (String) -> Any = { [weak self] k in
            if let v = self?.memoria[k] { return v }
            return NSNull()
        }
        let scrivi: @convention(block) (String, String) -> Void = { [weak self] k, v in
            self?.memoria[k] = v
            self?.salvaMemoriaPresto()
        }
        let togli: @convention(block) (String) -> Void = { [weak self] k in
            self?.memoria[k] = nil
            self?.salvaMemoriaPresto()
        }
        let chiavi: @convention(block) () -> String = { [weak self] in
            J.arr((self?.memoria.keys.sorted() ?? []).map { .str($0) }).testoJSON
        }
        let base64: @convention(block) (String) -> String = { t in Data(t.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }).base64EncodedString() }
        let log: @convention(block) (String) -> Void = { print("[js] \($0)") }
        let avvisa: @convention(block) (String, String) -> Void = { [weak self] testo, tipo in
            self?.mostra(testo, tipo)
        }
        let copia: @convention(block) (String) -> Void = { UIPasteboard.general.string = $0 }
        let uuid: @convention(block) () -> String = { UUID().uuidString.lowercased() }
        let token: @convention(block) () -> Any = { Rete.s.tokenCorrente ?? NSNull() }
        let utente: @convention(block) () -> Any = {
            guard let s = Rete.s.sessione else { return NSNull() }
            return (["id": .str(s.userId), "email": J.opz(s.email)] as J).testoJSON
        }
        let configurazione: @convention(block) (String) -> String = { $0 == "url" ? Config.supabaseUrl : Config.supabaseKey }
        let datiCambiati: @convention(block) () -> Void = { [weak self] in self?.segnala() }
        let tabella: @convention(block) (String) -> String = { J.arr(Archivio.s.tutte($0)).testoJSON }
        let scriviRighe: @convention(block) (String, String) -> Void = { nome, json in
            let righe = J.parse(json).list
            DispatchQueue.main.async { Archivio.s.scrivi(nome, righe) }
        }
        let nuovoTimer: @convention(block) (Double, Bool, JSValue) -> Int = { [weak self] ms, ripeti, fn in
            guard let self else { return 0 }
            let id = self.prossimoTimer
            self.prossimoTimer += 1
            let t = Timer(timeInterval: max(0.001, ms / 1000), repeats: ripeti) { [weak self] _ in
                if !ripeti { self?.timer[id] = nil }
                fn.call(withArguments: [])
            }
            self.timer[id] = t
            RunLoop.main.add(t, forMode: .common)
            return id
        }
        let fermaTimer: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timer[id]?.invalidate()
            self?.timer[id] = nil
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
        segnale?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.versione &+= 1 }
        segnale = w
        DispatchQueue.main.async(execute: w)
    }

    func mostra(_ testo: String, _ tipo: String = "info") {
        chiudiAvviso?.cancel()
        avviso = Avviso(testo: testo, tipo: tipo)
        if tipo == "errore" {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else if tipo == "festa" {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let w = DispatchWorkItem { [weak self] in self?.avviso = nil }
        chiudiAvviso = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (tipo == "errore" ? 5 : 2.6), execute: w)
    }
}
