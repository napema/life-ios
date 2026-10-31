import Foundation

/// Come src/data/actions.ts, lists.ts e agenda.ts: le operazioni sui dati e le regole delle liste.
/// Scrivono sempre in locale (funzionano offline) e accodano la sincronizzazione.
enum Azioni {
    private static var a: Archivio { Archivio.s }
    static func nuovoId() -> String { UUID().uuidString.lowercased() }
    static func adesso() -> J { .str(Tempo.adessoIso()) }

    // MARK: Annulla

    static var ultimoAnnulla: (() -> Void)?

    private static func annullabile(_ etichetta: String, _ fai: @escaping () -> Void) {
        ultimoAnnulla = fai
        Annulla.s.mostra(etichetta, fai)
    }

    // MARK: Regole delle liste

    static func giorno(_ t: J) -> String? { Tempo.dataRoma(t.due_at.str) }
    static func ora(_ t: J) -> String? { t.due_has_time.vero ? Tempo.oraRoma(t.due_at.str) : nil }
    static func aperto(_ t: J) -> Bool { t.deleted_at.isNull && t.completed_at.isNull }

    static func inOggi(_ t: J, _ oggi: String) -> Bool {
        guard aperto(t), !t.someday.vero else { return false }
        if let d = giorno(t), d <= oggi { return true }
        if let s = t.deadline.str, !s.isEmpty, s <= oggi { return true }
        return false
    }

    static func inEntrata(_ t: J, _ inbox: String?) -> Bool {
        aperto(t) && t.project_id.str == inbox && t.due_at.isNull && !t.someday.vero && !t.deadline.vero
    }

    static func inProgrammate(_ t: J, _ oggi: String) -> Bool {
        guard aperto(t), !t.someday.vero else { return false }
        if let d = giorno(t), d > oggi { return true }
        if let s = t.deadline.str, !s.isEmpty, s > oggi { return true }
        return false
    }

    static func inQualsiasi(_ t: J, _ oggi: String, _ inbox: String?) -> Bool {
        guard aperto(t), !t.someday.vero else { return false }
        if t.project_id.str == inbox, t.due_at.isNull { return false }
        guard let d = giorno(t) else { return true }
        return d <= oggi
    }

    static func inCestino(_ t: J) -> Bool {
        guard let d = Tempo.data(t.deleted_at.str) else { return false }
        return Date().timeIntervalSince(d) < 30 * 86400
    }

    static func inRitardo(_ t: J, _ oggi: String) -> Bool {
        guard aperto(t) else { return false }
        if let d = giorno(t), d < oggi { return true }
        if let s = t.deadline.str, !s.isEmpty, s < oggi { return true }
        return false
    }

    static func ordina(_ x: J, _ y: J) -> Bool {
        if x.sort_order.d != y.sort_order.d { return x.sort_order.d < y.sort_order.d }
        if x.priority.d != y.priority.d { return x.priority.d < y.priority.d }
        return x.created_at.t < y.created_at.t
    }

    static func avanzamento(_ tasks: [J], _ progetto: String) -> Double {
        let tutti = tasks.filter { $0.project_id.str == progetto && $0.deleted_at.isNull }
        guard !tutti.isEmpty else { return 0 }
        return Double(tutti.filter { !$0.completed_at.isNull }.count) / Double(tutti.count)
    }

    // MARK: Letture

    static var tasks: [J] { a.tutte("tasks") }
    static var progetti: [J] {
        a.tutte("projects")
            .filter { $0.deleted_at.isNull && $0.archived_at.isNull && $0.completed_at.isNull }
            .sorted { x, y in
                if x.is_inbox.vero { return true }
                if y.is_inbox.vero { return false }
                return x.sort_order.d < y.sort_order.d
            }
    }
    static var inbox: J? { progetti.first { $0.is_inbox.vero } }
    static var aree: [J] { a.tutte("areas").filter { $0.deleted_at.isNull }.sorted { $0.sort_order.d < $1.sort_order.d } }
    static func intestazioni(_ progetto: String) -> [J] {
        a.tutte("headings").filter { $0.project_id.str == progetto && $0.deleted_at.isNull }.sorted { $0.sort_order.d < $1.sort_order.d }
    }
    static var calendariPropri: [J] { a.tutte("calendars").filter { $0.deleted_at.isNull }.sorted { $0.sort_order.d < $1.sort_order.d } }
    static var iscrizioni: [J] { a.tutte("calendar_subscriptions").filter { $0.deleted_at.isNull } }

    /// Calendari propri e iscrizioni .ics, insieme.
    static var sorgenti: [Sorgente] {
        calendariPropri.map { Sorgente(id: $0.id.t, propria: true, nome: $0.name.t, colore: $0.color.t, nascosto: $0.hidden.vero, predefinito: $0.is_default.vero, errore: nil) }
            + iscrizioni.filter { $0.enabled.vero }.map { Sorgente(id: $0.id.t, propria: false, nome: $0.name.t, colore: $0.color.t, nascosto: $0.hidden.vero, predefinito: false, errore: $0.last_error.str) }
    }

    static func promemoria(task id: String) -> [J] {
        a.tutte("reminders").filter { $0.task_id.str == id && $0.deleted_at.isNull }.sorted { $0.remind_at.t < $1.remind_at.t }
    }
    static func promemoria(evento id: String) -> [J] {
        a.tutte("reminders").filter { $0.event_id.str == id && $0.deleted_at.isNull }
    }

    /// Eventi (propri + .ics) che toccano [da, a), solo calendari visibili, ripetizioni espanse.
    private static var eventiRicordati: [String: [J]] = [:]
    private static var versioneEventi = -1

    static func eventi(da: String, a fine: String) -> [J] {
        if versioneEventi != a.versione {
            versioneEventi = a.versione
            eventiRicordati = [:]
        }
        let chiave = "\(da)|\(fine)"
        if let noti = eventiRicordati[chiave] { return noti }
        let calcolati = calcolaEventi(da: da, a: fine)
        if eventiRicordati.count > 40 { eventiRicordati = [:] }
        eventiRicordati[chiave] = calcolati
        return calcolati
    }

    private static func calcolaEventi(da: String, a fine: String) -> [J] {
        let visibiliIcs = Set(iscrizioni.filter { $0.enabled.vero && !$0.hidden.vero }.map(\.id.t))
        let visibili = Set(calendariPropri.filter { !$0.hidden.vero }.map(\.id.t))
        var out = a.ics.filter { $0.start_at.t < fine && $0.end_at.t > da && visibiliIcs.contains($0.subscription_id.t) }
        for e in a.tutte("events") where e.deleted_at.isNull && visibili.contains(e.calendar_id.t) {
            out += espandi(e, da, fine)
        }
        return out.sorted { $0.start_at.t < $1.start_at.t }
    }

    static func espandi(_ e: J, _ da: String, _ fine: String) -> [J] {
        let base: J = ["id": e.id, "own_event_id": e.id, "subscription_id": e.calendar_id, "uid": e.id, "summary": e.title, "description": e.notes, "location": e.location, "start_at": e.start_at, "end_at": e.end_at, "all_day": e.all_day, "status": nil]
        guard let regola = e.rrule.str, !regola.isEmpty else {
            return e.end_at.t > da && e.start_at.t < fine ? [base] : []
        }
        guard let inizio = Tempo.data(e.start_at.t), let finale = Tempo.data(e.end_at.t) else { return [] }
        let durata = finale.timeIntervalSince(inizio)
        let ora = e.all_day.vero ? nil : Tempo.oraRoma(inizio)
        var giorno = Tempo.dataRoma(inizio)
        var out: [J] = []
        for _ in 0..<1000 {
            let s = Tempo.istante(giorno, ora)
            let si = Tempo.iso(s)
            if si >= fine { break }
            let f = Tempo.iso(s.addingTimeInterval(durata))
            if f > da {
                var c = base
                c["id"] = .str("\(e.id.t)@\(giorno)")
                c["start_at"] = .str(si)
                c["end_at"] = .str(f)
                out.append(c)
            }
            guard let prossimo = Logica.s.chiama("ricorrenze.nextOccurrence", .str(regola), .str(giorno)).str else { break }
            giorno = prossimo
        }
        return out
    }

    // MARK: Task

    static func scadenza(_ giorno: String?, _ ora: String?) -> (J, Bool) {
        guard let giorno, !giorno.isEmpty else { return (nil, false) }
        return (.str(Tempo.iso(Tempo.istante(giorno, ora))), ora != nil)
    }

    private static func vuoto(progetto: String, ordine: Double) -> J {
        ["id": .str(nuovoId()), "project_id": .str(progetto), "heading_id": nil, "title": "", "notes": nil, "due_at": nil, "due_has_time": false, "evening": false, "someday": false, "deadline": nil, "checklist": [], "tags": [], "priority": 4, "rrule": nil, "series_id": nil, "completed_at": nil, "sort_order": .num(ordine), "deleted_at": nil]
    }

    static var ordineInCima: Double { (tasks.map(\.sort_order.d).min() ?? 0) - 1 }

    /// Crea un task. Il testo si interpreta in linguaggio naturale («domani alle 15 #Studio !2»).
    @discardableResult
    static func creaTask(testo: String, contesto: [String: J] = [:], interpreta: Bool = true) -> J? {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pulito.isEmpty else { return nil }
        let base = contesto["project_id"]?.str ?? inbox?.id.str ?? ""
        var t = vuoto(progetto: base, ordine: ordineInCima)
        for (k, v) in contesto { t[k] = v }
        t["title"] = .str(pulito)
        var conOra = t.due_has_time.vero
        if interpreta {
            let nomi = progetti.map { J.str($0.name.t) }
            let p = Logica.s.chiama("parser.parseTask", .str(pulito), ["projects": .arr(nomi)])
            if let titolo = p.title.str, !titolo.isEmpty { t["title"] = .str(titolo) }
            if let g = p.date.str {
                let (d, h) = scadenza(g, p.time.str)
                t["due_at"] = d
                t["due_has_time"] = .bool(h)
                t["someday"] = false
                t["evening"] = false
                conOra = h
            }
            if let r = p.rrule.str { t["rrule"] = .str(r) }
            if let n = p.priority.num { t["priority"] = .num(n) }
            if p.projectFound.vero, let pr = progetti.first(where: { $0.name.t == p.project.t }) {
                t["project_id"] = pr.id
                t["heading_id"] = nil
            }
        }
        a.scrivi("tasks", t)
        if conOra, Preferenze.s.promemoriaAutomatico { aggiungiPromemoria(t, minutiPrima: 0) }
        return t
    }

    /// Crea un task vuoto e lo restituisce (si scrive nella sua scheda).
    static func creaVuoto(contesto: [String: J]) -> J {
        var t = vuoto(progetto: contesto["project_id"]?.str ?? inbox?.id.str ?? "", ordine: ordineInCima)
        for (k, v) in contesto { t[k] = v }
        a.scrivi("tasks", t)
        return t
    }

    static func aggiorna(_ id: String, _ modifica: [String: J]) {
        guard var t = a.riga("tasks", id) else { return }
        let prima = t
        for (k, v) in modifica { t[k] = v }
        a.scrivi("tasks", t)
        // I promemoria relativi seguono la scadenza
        guard let nuova = modifica["due_at"], nuova != prima.due_at else { return }
        let rem = promemoria(task: id)
        var spostati: [J] = []
        for r in rem {
            guard let m = r.offset_minutes.num else { continue }
            var c = r
            if t.due_at.isNull || !t.due_has_time.vero {
                c["deleted_at"] = adesso()
            } else if let d = Tempo.data(t.due_at.str) {
                c["remind_at"] = .str(Tempo.iso(d.addingTimeInterval(-m * 60)))
                c["status"] = "pending"
            }
            spostati.append(c)
        }
        if !spostati.isEmpty { a.scrivi("reminders", spostati) }
        if !t.due_at.isNull, t.due_has_time.vero, !prima.due_has_time.vero, rem.isEmpty, Preferenze.s.promemoriaAutomatico {
            aggiungiPromemoria(t, minutiPrima: 0)
        }
    }

    /// Modifica annullabile.
    static func modifica(_ id: String, _ m: [String: J], _ etichetta: String) {
        guard let prima = a.riga("tasks", id) else { return }
        var indietro: [String: J] = [:]
        for k in m.keys { indietro[k] = prima[k] }
        if m["due_at"] != nil { indietro["due_has_time"] = prima.due_has_time }
        aggiorna(id, m)
        annullabile(etichetta) { aggiorna(id, indietro) }
    }

    static func completa(_ t: J) {
        guard let id = t.id.str else { return }
        if !t.completed_at.isNull {
            aggiorna(id, ["completed_at": nil])
            annullabile("Task riaperto") { aggiorna(id, ["completed_at": t.completed_at]) }
            return
        }
        aggiorna(id, ["completed_at": adesso()])
        var generato: J?
        // Ricorrente: genera la prossima occorrenza come nuovo task (stessa serie)
        if let regola = t.rrule.str, !regola.isEmpty, let giornoDue = giorno(t), let dueData = Tempo.data(t.due_at.str) {
            let ora = t.due_has_time.vero ? Tempo.oraRoma(dueData) : nil
            if let g = Logica.s.chiama("ricorrenze.nextAfterCompletion", .str(regola), .str(giornoDue), .str(Tempo.oggi())).str {
                let prossima = Tempo.istante(g, ora)
                var n = t
                n["id"] = .str(nuovoId())
                n["due_at"] = .str(Tempo.iso(prossima))
                n["series_id"] = t.series_id.isNull ? t.id : t.series_id
                n["completed_at"] = nil
                n["created_at"] = nil
                n["updated_at"] = nil
                a.scrivi("tasks", n)
                let scarto = prossima.timeIntervalSince(dueData)
                let copie: [J] = promemoria(task: id).compactMap { r in
                    guard let vecchio = Tempo.data(r.remind_at.str) else { return nil }
                    let quando = r.offset_minutes.num.map { prossima.addingTimeInterval(-$0 * 60) } ?? vecchio.addingTimeInterval(scarto)
                    return ["id": .str(nuovoId()), "task_id": n.id, "offset_minutes": r.offset_minutes, "remind_at": .str(Tempo.iso(quando)), "status": "pending", "deleted_at": nil]
                }
                if !copie.isEmpty { a.scrivi("reminders", copie) }
                generato = n
            }
        }
        annullabile("Completato: \(t.title.t)") {
            aggiorna(id, ["completed_at": nil])
            if let generato { eliminaInSilenzio(generato) }
        }
    }

    @discardableResult
    private static func eliminaInSilenzio(_ t: J) -> [J] {
        let ora = adesso()
        var c = a.riga("tasks", t.id.t) ?? t
        c["deleted_at"] = ora
        a.scrivi("tasks", c)
        let rem = promemoria(task: t.id.t)
        if !rem.isEmpty {
            a.scrivi("reminders", rem.map { r in
                var x = r
                x["deleted_at"] = ora
                return x
            })
        }
        return rem
    }

    static func elimina(_ t: J) {
        let rem = eliminaInSilenzio(t)
        annullabile("Eliminato: \(t.title.t)") {
            if var c = a.riga("tasks", t.id.t) {
                c["deleted_at"] = nil
                a.scrivi("tasks", c)
            }
            if !rem.isEmpty {
                a.scrivi("reminders", rem.map { r in
                    var x = r
                    x["deleted_at"] = nil
                    return x
                })
            }
        }
    }

    static func duplica(_ t: J) {
        var c = t
        c["id"] = .str(nuovoId())
        c["completed_at"] = nil
        c["series_id"] = nil
        c["created_at"] = nil
        c["updated_at"] = nil
        c["sort_order"] = .num(t.sort_order.d - 0.5)
        a.scrivi("tasks", c)
        annullabile("Task duplicato") { eliminaInSilenzio(c) }
    }

    static func ripristina(_ t: J) {
        var c = t
        c["deleted_at"] = nil
        a.scrivi("tasks", c)
    }

    static func scartaSeVuoto(_ id: String) {
        guard let t = a.riga("tasks", id), t.title.t.trimmingCharacters(in: .whitespaces).isEmpty, !t.notes.vero, t.checklist.list.isEmpty, t.deleted_at.isNull else { return }
        var c = t
        c["deleted_at"] = adesso()
        a.scrivi("tasks", c)
    }

    enum Quando {
        case oggi, sera, unGiorno, nessuno
        case data(String, String?)
    }

    static func quando(_ t: J, _ q: Quando) {
        let tieniOra = t.due_has_time.vero ? Tempo.oraRoma(t.due_at.str) : nil
        var m: [String: J] = ["evening": false, "someday": false]
        var etichetta = "Programmato"
        switch q {
        case .oggi:
            let (d, h) = scadenza(Tempo.oggi(), tieniOra)
            m["due_at"] = d
            m["due_has_time"] = .bool(h)
            etichetta = "Oggi"
        case .sera:
            let (d, h) = scadenza(Tempo.oggi(), tieniOra)
            m["due_at"] = d
            m["due_has_time"] = .bool(h)
            m["evening"] = true
            etichetta = "Questa sera"
        case .unGiorno:
            m["due_at"] = nil
            m["due_has_time"] = false
            m["someday"] = true
            etichetta = "Un giorno"
        case .nessuno:
            m["due_at"] = nil
            m["due_has_time"] = false
            etichetta = "Data rimossa"
        case .data(let g, let o):
            let (d, h) = scadenza(g, o)
            m["due_at"] = d
            m["due_has_time"] = .bool(h)
        }
        modifica(t.id.t, m, etichetta)
    }

    static func sposta(_ t: J, progetto: String, intestazione: String? = nil) {
        let nome = a.riga("projects", progetto)?.name.t ?? "progetto"
        modifica(t.id.t, ["project_id": .str(progetto), "heading_id": .opz(intestazione)], "Spostato in \(nome)")
    }

    // MARK: Promemoria

    static func aggiungiPromemoria(_ t: J, minutiPrima: Int) {
        guard let d = Tempo.data(t.due_at.str) else { return }
        let r: J = ["id": .str(nuovoId()), "task_id": t.id, "remind_at": .str(Tempo.iso(d.addingTimeInterval(Double(-minutiPrima) * 60))), "offset_minutes": .n(minutiPrima), "status": "pending", "deleted_at": nil]
        a.scrivi("reminders", r)
    }

    static func aggiungiPromemoria(_ t: J, alle: Date) {
        let r: J = ["id": .str(nuovoId()), "task_id": t.id, "remind_at": .str(Tempo.iso(alle)), "offset_minutes": nil, "status": "pending", "deleted_at": nil]
        a.scrivi("reminders", r)
    }

    static func togliPromemoria(_ r: J) {
        var c = r
        c["deleted_at"] = adesso()
        a.scrivi("reminders", c)
    }

    // MARK: Progetti, aree, intestazioni

    @discardableResult
    static func creaProgetto(_ nome: String, colore: String = "#0A84FF", area: String? = nil) -> J {
        let ordine = (a.tutte("projects").map(\.sort_order.d).max() ?? 0) + 1
        let p: J = ["id": .str(nuovoId()), "name": .str(nome.trimmingCharacters(in: .whitespaces)), "color": .str(colore), "area_id": .opz(area), "notes": nil, "completed_at": nil, "is_inbox": false, "sort_order": .num(ordine), "archived_at": nil, "deleted_at": nil]
        a.scrivi("projects", p)
        return p
    }

    static func aggiorna(progetto id: String, _ m: [String: J]) { aggiornaRiga("projects", id, m) }
    static func aggiorna(area id: String, _ m: [String: J]) { aggiornaRiga("areas", id, m) }
    static func aggiorna(intestazione id: String, _ m: [String: J]) { aggiornaRiga("headings", id, m) }

    static func aggiornaRiga(_ tabella: String, _ id: String, _ m: [String: J]) {
        guard var r = a.riga(tabella, id) else { return }
        for (k, v) in m { r[k] = v }
        a.scrivi(tabella, r)
    }

    static func elimina(progetto p: J) {
        guard !p.is_inbox.vero else { return }
        for t in tasks where t.project_id == p.id && t.deleted_at.isNull { eliminaInSilenzio(t) }
        aggiornaRiga("projects", p.id.t, ["deleted_at": adesso()])
    }

    static func completa(progetto p: J) {
        let ora = adesso()
        let aperti = tasks.filter { $0.project_id == p.id && aperto($0) }
        for t in aperti { aggiorna(t.id.t, ["completed_at": ora]) }
        aggiornaRiga("projects", p.id.t, ["completed_at": ora])
        annullabile("Progetto completato: \(p.name.t)") {
            aggiornaRiga("projects", p.id.t, ["completed_at": nil])
            for t in aperti { aggiorna(t.id.t, ["completed_at": nil]) }
        }
    }

    @discardableResult
    static func creaArea(_ nome: String) -> J {
        let ordine = (a.tutte("areas").map(\.sort_order.d).max() ?? 0) + 1
        let r: J = ["id": .str(nuovoId()), "name": .str(nome.trimmingCharacters(in: .whitespaces)), "sort_order": .num(ordine), "deleted_at": nil]
        a.scrivi("areas", r)
        return r
    }

    static func elimina(area r: J) {
        let suoi = a.tutte("projects").filter { $0.area_id == r.id }
        for p in suoi { aggiornaRiga("projects", p.id.t, ["area_id": nil]) }
        aggiornaRiga("areas", r.id.t, ["deleted_at": adesso()])
        annullabile("Area eliminata: \(r.name.t)") {
            aggiornaRiga("areas", r.id.t, ["deleted_at": nil])
            for p in suoi { aggiornaRiga("projects", p.id.t, ["area_id": r.id]) }
        }
    }

    @discardableResult
    static func creaIntestazione(_ progetto: String, _ titolo: String) -> J {
        let ordine = (intestazioni(progetto).map(\.sort_order.d).max() ?? 0) + 1
        let h: J = ["id": .str(nuovoId()), "project_id": .str(progetto), "title": .str(titolo.isEmpty ? "Nuova intestazione" : titolo), "sort_order": .num(ordine), "archived_at": nil, "deleted_at": nil]
        a.scrivi("headings", h)
        return h
    }

    static func elimina(intestazione h: J) {
        let suoi = tasks.filter { $0.heading_id == h.id }
        for t in suoi { aggiorna(t.id.t, ["heading_id": nil]) }
        aggiornaRiga("headings", h.id.t, ["deleted_at": adesso()])
    }

    static func archivia(intestazione h: J) {
        let ora = adesso()
        for t in tasks where t.heading_id == h.id && aperto(t) { aggiorna(t.id.t, ["completed_at": ora]) }
        aggiornaRiga("headings", h.id.t, ["archived_at": ora])
    }

    // MARK: Eventi

    static var calendarioPredefinito: String? {
        (calendariPropri.first { $0.is_default.vero } ?? calendariPropri.first)?.id.str
    }

    static func salvaEvento(id: String?, valori: [String: J], minutiPromemoria: [Int]) {
        if let id, var e = a.riga("events", id) {
            let prima = e
            for (k, v) in valori { e[k] = v }
            a.scrivi("events", e)
            impostaPromemoria(e, minutiPromemoria)
            annullabile("Evento modificato") { a.scrivi("events", prima) }
        } else {
            var e: J = ["id": .str(nuovoId()), "notes": nil, "location": nil, "rrule": nil, "deleted_at": nil]
            for (k, v) in valori { e[k] = v }
            a.scrivi("events", e)
            impostaPromemoria(e, minutiPromemoria)
            annullabile("Evento creato: \(e.title.t)") { aggiornaRiga("events", e.id.t, ["deleted_at": adesso()]) }
        }
    }

    static func impostaPromemoria(_ e: J, _ minuti: [Int]) {
        let esistenti = promemoria(evento: e.id.t)
        let ora = adesso()
        var via = esistenti.filter { r in !(r.offset_minutes.int.map { minuti.contains($0) } ?? false) }
        let tenuti = esistenti.filter { r in !via.contains(r) }
        if !e.rrule.vero, let inizio = Tempo.data(e.start_at.str) {
            let nuovi: [J] = minuti.filter { m in !tenuti.contains { $0.offset_minutes.int == m } }.map { m in
                ["id": .str(nuovoId()), "task_id": nil, "event_id": e.id, "offset_minutes": .n(m), "remind_at": .str(Tempo.iso(inizio.addingTimeInterval(Double(-m) * 60))), "status": "pending", "deleted_at": nil]
            }
            if !nuovi.isEmpty { a.scrivi("reminders", nuovi) }
            // I promemoria relativi seguono l'inizio
            let spostati: [J] = tenuti.compactMap { r in
                guard let m = r.offset_minutes.num else { return nil }
                var c = r
                c["remind_at"] = .str(Tempo.iso(inizio.addingTimeInterval(-m * 60)))
                c["status"] = "pending"
                return c
            }
            if !spostati.isEmpty { a.scrivi("reminders", spostati) }
        } else {
            via = esistenti
        }
        if !via.isEmpty {
            a.scrivi("reminders", via.map { r in
                var c = r
                c["deleted_at"] = ora
                return c
            })
        }
    }

    static func eliminaEvento(_ id: String) {
        aggiornaRiga("events", id, ["deleted_at": adesso()])
        let nome = a.riga("events", id)?.title.t ?? "Evento"
        annullabile("Evento eliminato: \(nome)") { aggiornaRiga("events", id, ["deleted_at": nil]) }
    }

    static func aggiungiCalendario(nome: String, url: String, colore: String) {
        let r: J = ["id": .str(nuovoId()), "name": .str(nome), "url": .str(url), "color": .str(colore), "enabled": true, "deleted_at": nil]
        a.scrivi("calendar_subscriptions", r)
    }

    @discardableResult
    static func creaCalendario(nome: String, colore: String) -> J {
        let ordine = (a.tutte("calendars").map(\.sort_order.d).max() ?? 0) + 1
        let c: J = ["id": .str(nuovoId()), "name": .str(nome), "color": .str(colore), "is_default": false, "hidden": false, "sort_order": .num(ordine), "deleted_at": nil]
        a.scrivi("calendars", c)
        return c
    }

    static func cambia(sorgente s: Sorgente, _ m: [String: J]) {
        aggiornaRiga(s.propria ? "calendars" : "calendar_subscriptions", s.id, m)
    }
}

struct Sorgente: Identifiable, Hashable {
    let id: String
    let propria: Bool
    let nome: String
    let colore: String
    let nascosto: Bool
    let predefinito: Bool
    let errore: String?
}

/// Il «Annulla» in fondo allo schermo.
final class Annulla: ObservableObject {
    static let s = Annulla()
    @Published var etichetta: String?
    private var azione: (() -> Void)?
    private var chiudi: DispatchWorkItem?

    func mostra(_ testo: String, _ fai: @escaping () -> Void) {
        azione = fai
        etichetta = testo
        chiudi?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.etichetta = nil }
        chiudi = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    func esegui() {
        azione?()
        azione = nil
        etichetta = nil
    }
}

/// Le preferenze di questo dispositivo.
final class Preferenze: ObservableObject {
    static let s = Preferenze()
    private let d = UserDefaults.standard

    @Published var aspetto: String { didSet { d.set(aspetto, forKey: "aspetto") } }
    @Published var promemoriaAutomatico: Bool { didSet { d.set(promemoriaAutomatico, forKey: "promemoriaAutomatico") } }
    @Published var promemoriaInCalendario: Bool { didSet { d.set(promemoriaInCalendario, forKey: "promemoriaInCalendario") } }
    @Published var modoCalendario: String { didSet { d.set(modoCalendario, forKey: "modoCalendario") } }

    init() {
        aspetto = d.string(forKey: "aspetto") ?? "system"
        promemoriaAutomatico = d.object(forKey: "promemoriaAutomatico") as? Bool ?? true
        promemoriaInCalendario = d.object(forKey: "promemoriaInCalendario") as? Bool ?? true
        modoCalendario = d.string(forKey: "modoCalendario") ?? "day"
    }
}
