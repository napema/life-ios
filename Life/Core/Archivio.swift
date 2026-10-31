import Foundation
import SwiftUI

/// Come src/data/db.ts + sync.ts: copia locale, coda delle modifiche, push e pull verso Supabase.
/// L'app legge sempre da qui, anche offline. Vince l'ultima scrittura che arriva;
/// le modifiche locali ancora in coda non vengono mai sovrascritte.
final class Archivio: ObservableObject {
    static let s = Archivio()

    static let tabelle = ["areas", "projects", "headings", "tasks", "calendars", "events", "reminders", "calendar_subscriptions"]
    private static let colonne: [String: [String]] = [
        "areas": ["id", "name", "sort_order", "deleted_at"],
        "projects": ["id", "name", "color", "emoji", "is_inbox", "sort_order", "area_id", "notes", "completed_at", "archived_at", "deleted_at"],
        "headings": ["id", "project_id", "title", "sort_order", "archived_at", "deleted_at"],
        "tasks": ["id", "project_id", "heading_id", "title", "notes", "due_at", "due_has_time", "evening", "someday", "deadline", "checklist", "tags", "priority", "rrule", "series_id", "completed_at", "sort_order", "deleted_at"],
        "calendars": ["id", "name", "color", "is_default", "hidden", "sort_order", "deleted_at"],
        "events": ["id", "calendar_id", "title", "notes", "location", "start_at", "end_at", "all_day", "rrule", "deleted_at", "origine"],
        "reminders": ["id", "task_id", "event_id", "remind_at", "offset_minutes", "deleted_at"],
        "calendar_subscriptions": ["id", "name", "url", "color", "enabled", "hidden", "deleted_at"],
    ]

    enum StatoSync: Equatable { case fermo, inCorso, offline, errore(String) }

    /// Cresce a ogni scrittura: le schermate si ridisegnano.
    @Published private(set) var versione = 0
    @Published private(set) var stato: StatoSync = .fermo
    @Published private(set) var inCoda = 0
    @Published private(set) var ultimaSync: Date?

    private var righe: [String: [String: J]] = [:]
    private var eventiIcs: [J] = []
    private var coda: [String] = [] // "tabella|id"
    private var cursori: [String: String] = [:]
    private var eventiSporchi = true
    private var eventiScaricati = Date.distantPast
    private var salvataggio: DispatchWorkItem?
    private var inEsecuzione = false
    private var ancora = false
    private var timerSync: Timer?
    private var attesa: DispatchWorkItem?

    private let cartella: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("archivio", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    init() { carica() }

    // MARK: Lettura

    func tutte(_ tabella: String) -> [J] { Array((righe[tabella] ?? [:]).values) }
    func riga(_ tabella: String, _ id: String) -> J? { righe[tabella]?[id] }
    var ics: [J] { eventiIcs }

    // MARK: Scrittura

    /// Scrive in locale e mette in coda per il server.
    func scrivi(_ tabella: String, _ nuove: [J], sincronizza: Bool = true) {
        var t = righe[tabella] ?? [:]
        for r in nuove {
            guard let id = r.id.str else { continue }
            t[id] = r
            coda.append("\(tabella)|\(id)")
        }
        righe[tabella] = t
        inCoda = coda.count
        tocca()
        if tabella == "events" { Logica.s.eventiCambiati() }
        if sincronizza { pianifica(0.4) }
    }

    func scrivi(_ tabella: String, _ r: J) { scrivi(tabella, [r]) }

    private func tocca() {
        versione &+= 1
        salvaPresto()
    }

    // MARK: Persistenza

    private func file(_ nome: String) -> URL { cartella.appendingPathComponent("\(nome).json") }

    private func carica() {
        for t in Self.tabelle {
            guard let d = try? Data(contentsOf: file(t)) else { continue }
            var mappa: [String: J] = [:]
            for r in J.parse(d).list { if let id = r.id.str { mappa[id] = r } }
            righe[t] = mappa
        }
        if let d = try? Data(contentsOf: file("calendar_events")) { eventiIcs = J.parse(d).list }
        if let d = try? Data(contentsOf: file("meta")) {
            let m = J.parse(d)
            coda = m.coda.list.compactMap(\.str)
            cursori = m.cursori.dict.compactMapValues(\.str)
        }
        inCoda = coda.count
    }

    private func salvaPresto() {
        salvataggio?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.salvaOra() }
        salvataggio = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func salvaOra() {
        salvataggio?.cancel()
        let istantanea = righe
        let ics = eventiIcs
        let meta: J = ["coda": .arr(coda.map { .str($0) }), "cursori": .obj(cursori.mapValues { .str($0) })]
        let dir = cartella
        DispatchQueue.global(qos: .utility).async {
            for (t, m) in istantanea {
                try? J.arr(Array(m.values)).codificato.write(to: dir.appendingPathComponent("\(t).json"), options: .atomic)
            }
            try? J.arr(ics).codificato.write(to: dir.appendingPathComponent("calendar_events.json"), options: .atomic)
            try? meta.codificato.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        }
    }

    func svuota() {
        righe = [:]
        eventiIcs = []
        coda = []
        cursori = [:]
        inCoda = 0
        for t in Self.tabelle + ["calendar_events", "meta"] { try? FileManager.default.removeItem(at: file(t)) }
        versione &+= 1
    }

    // MARK: Sincronizzazione

    func avvia() {
        timerSync?.invalidate()
        // Rete di sicurezza: il realtime qui non c'è, si guarda ogni 30 secondi con l'app aperta
        timerSync = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.pianifica(0) }
        pianifica(0)
    }

    func ferma() { timerSync?.invalidate() }

    func segnaEventiSporchi() { eventiSporchi = true }

    func pianifica(_ ritardo: TimeInterval) {
        attesa?.cancel()
        let w = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.sincronizza() }
        }
        attesa = w
        DispatchQueue.main.asyncAfter(deadline: .now() + ritardo, execute: w)
    }

    @MainActor
    func sincronizza() async {
        if inEsecuzione {
            ancora = true
            return
        }
        guard Rete.s.connesso else { return }
        inEsecuzione = true
        stato = .inCorso
        do {
            try await push()
            try await pull()
            stato = .fermo
            ultimaSync = Date()
            Notifiche.s.riprogramma()
        } catch {
            let e = error as NSError
            stato = e.domain == NSURLErrorDomain ? .offline : .errore(error.localizedDescription)
        }
        inEsecuzione = false
        inCoda = coda.count
        salvaPresto()
        if ancora {
            ancora = false
            pianifica(1)
        }
    }

    @MainActor
    private func push() async throws {
        let inviati = coda
        guard !inviati.isEmpty else { return }
        for t in Self.tabelle {
            let ids = Set(inviati.filter { $0.hasPrefix("\(t)|") }.map { String($0.dropFirst(t.count + 1)) })
            guard !ids.isEmpty, let cols = Self.colonne[t] else { continue }
            let lista: [J] = ids.compactMap { righe[t]?[$0] }.map { r in
                var o: [String: J] = [:]
                for c in cols {
                    if let v = r.dict[c] { o[c] = v }
                }
                return .obj(o)
            }
            var i = 0
            while i < lista.count {
                try await Rete.s.upsert(t, Array(lista[i..<min(i + 200, lista.count)]))
                i += 200
            }
        }
        // Ciò che è arrivato in coda mentre si inviava resta per il prossimo giro
        coda.removeFirst(min(inviati.count, coda.count))
        inCoda = coda.count
    }

    @MainActor
    private func pull() async throws {
        var cambiati = false
        for t in Self.tabelle {
            let cursore = cursori[t] ?? "1970-01-01T00:00:00Z"
            // 2 minuti di sovrapposizione: transazioni che terminano fuori ordine
            let base = Tempo.data(cursore) ?? Date(timeIntervalSince1970: 0)
            let da = Tempo.iso(base.addingTimeInterval(-120))
            var ultimo = cursore
            var inizio = 0
            while true {
                let enc = da.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? da
                let pagina = try await Rete.s.righe(t, "select=*&updated_at=gt.\(enc)&order=updated_at.asc", da: inizio, a: inizio + 999)
                if pagina.isEmpty { break }
                // Il controllo della coda va fatto adesso, non a inizio giro: un tocco arrivato mentre
                // la rete rispondeva verrebbe sovrascritto dalla copia vecchia del server
                let inAttesa = Set(coda)
                var mappa = righe[t] ?? [:]
                for r in pagina {
                    guard let id = r.id.str, !inAttesa.contains("\(t)|\(id)") else { continue }
                    mappa[id] = Tempo.normalizza(r)
                    cambiati = true
                    if t == "calendar_subscriptions" { eventiSporchi = true }
                }
                righe[t] = mappa
                if let u = pagina.last?.updated_at.str, u > ultimo { ultimo = u }
                if pagina.count < 1000 { break }
                inizio += 1000
            }
            cursori[t] = ultimo
        }
        if cambiati {
            tocca()
            Logica.s.eventiCambiati()
        }

        // Eventi di calendario .ics: finestra completa, se cambiati o ogni 15 minuti
        guard eventiSporchi || Date().timeIntervalSince(eventiScaricati) > 15 * 60 else { return }
        eventiSporchi = false
        eventiScaricati = Date()
        let daData = Tempo.iso(Date().addingTimeInterval(-31 * 86400))
        let enc = daData.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? daData
        var tutti: [J] = []
        var inizio = 0
        while true {
            let pagina = try await Rete.s.righe("calendar_events", "select=id,subscription_id,uid,summary,description,location,start_at,end_at,all_day,status&end_at=gte.\(enc)&order=start_at.asc", da: inizio, a: inizio + 999)
            tutti += pagina.map(Tempo.normalizza)
            if pagina.count < 1000 { break }
            inizio += 1000
        }
        eventiIcs = tutti
        tocca()
    }

    /// Chiede al server di riscaricare subito i calendari.
    @MainActor
    func aggiornaCalendari() async throws {
        await sincronizza()
        try await Rete.s.funzione("refresh-calendars")
        eventiSporchi = true
        pianifica(0)
    }

    /// Svuota il cestino davvero, anche dal server.
    @MainActor
    func eliminaDefinitivamente(tasks ids: [String]) async throws {
        await sincronizza()
        var i = 0
        while i < ids.count {
            let pezzo = Array(ids[i..<min(i + 100, ids.count)])
            try await Rete.s.elimina("tasks", ids: pezzo)
            for id in pezzo { righe["tasks"]?[id] = nil }
            i += 100
        }
        tocca()
    }
}
