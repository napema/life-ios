import SwiftUI

// Il calendario: giorno, 3 giorni, settimana, mese (come CalendarView.tsx, per il tocco).

/// Le lezioni della scuola: il titolo è illeggibile, la descrizione è ordinata (come lib/lezione.ts).
struct Lezione {
    let materia: String
    let tipo: String?
    let docenti: [String]
    let aule: [String]
    let gruppi: [String]
    let campi: [(String, String)]

    private static var ricordate: [String: Lezione?] = [:]

    /// Riconoscere una lezione costa: si ricorda finché la descrizione è la stessa.
    static func di(_ e: J) -> Lezione? {
        let chiave = e.description.t
        if let nota = ricordate[chiave] { return nota }
        if ricordate.count > 5000 { ricordate = [:] }
        let l = Lezione(e)
        ricordate[chiave] = .some(l)
        return l
    }

    init?(_ e: J) {
        let d = e.description.t
        guard d.range(of: #"(?im)^\s*Materia\s*:"#, options: .regularExpression) != nil else { return nil }
        var c: [(String, String)] = []
        for riga in d.split(whereSeparator: \.isNewline) {
            guard let i = riga.firstIndex(of: ":") else { continue }
            let k = riga[..<i].trimmingCharacters(in: .whitespaces)
            let v = riga[riga.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !v.isEmpty { c.append((k, v)) }
        }
        let campo: ([String]) -> String? = { nomi in c.first { nomi.contains($0.0.lowercased()) }?.1 }
        let lista: (String?) -> [String] = { s in (s ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        materia = campo(["materia"]) ?? e.summary.str ?? "Lezione"
        tipo = campo(["tipo"])
        docenti = lista(campo(["docenti", "docente"]))
        aule = lista(campo(["aula", "aule"]) ?? e.location.str)
        gruppi = lista(campo(["gruppi", "gruppo", "corsi", "corso"]))
        campi = c
    }

    var titolo: String { tipo.map { "\(materia) · \($0)" } ?? materia }

    var dove: String {
        let mia = materia.lowercased() == "francese tecn. prof." && aule.contains("L3") ? "L3" : nil
        var aula = ""
        if let mia {
            aula = "Aula \(mia)"
        } else if aule.count > 1 {
            aula = "Aule \(aule[0]) +\(aule.count - 1)"
        } else if let a = aule.first {
            aula = a.range(of: #"^(\d|L\d)"#, options: [.regularExpression, .caseInsensitive]) != nil ? "Aula \(a)" : a
        }
        let prof = docenti.count > 3 ? "\(docenti.prefix(2).joined(separator: ", ")) +\(docenti.count - 2)" : docenti.joined(separator: ", ")
        return [aula, prof].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct EventoAperto: Identifiable {
    let evento: J
    var id: String { evento.id.t }
}

struct NuovoEventoBersaglio: Identifiable {
    let id = UUID()
    var idEvento: String? = nil
    var giorno: String? = nil
    var inizio: String? = nil
    var fine: String? = nil
    var tuttoIlGiorno = false
}

// MARK: - Dettaglio

/// Il menu che esce tenendo premuto un evento (griglia, mese, liste).
struct MenuEvento: View {
    let e: J
    var apri: (() -> Void)? = nil

    var body: some View {
        let proprio = e.own_event_id.str
        let singolo = proprio != nil && !e.id.t.contains("@")
        Button {
            if let apri { apri() } else { Instradatore.s.evento = Instradatore.LinkEvento(id: e.id.t, giorno: Tempo.dataRoma(e.start_at.str) ?? Tempo.oggi()) }
        } label: { Label("Apri", systemImage: "arrow.up.forward.square") }
        Button { UIPasteboard.general.string = e.summary.t } label: { Label("Copia il titolo", systemImage: "doc.on.doc") }
        if !e.location.t.isEmpty {
            Button { UIPasteboard.general.string = e.location.t } label: { Label("Copia il luogo", systemImage: "mappin.and.ellipse") }
        }
        if let id = proprio {
            Button { Azioni.duplicaEvento(id) } label: { Label("Duplica", systemImage: "plus.square.on.square") }
            if singolo {
                Button { Azioni.spostaEvento(id, giorni: 1) } label: { Label("Un giorno dopo", systemImage: "sunrise") }
                Button { Azioni.spostaEvento(id, giorni: 7) } label: { Label("Una settimana dopo", systemImage: "calendar.badge.plus") }
            }
            Button(role: .destructive) { Azioni.eliminaEvento(id) } label: { Label(singolo ? "Elimina" : "Elimina tutta la serie", systemImage: "trash") }
        }
    }
}

struct DettaglioEvento: View {
    let evento: J
    let modifica: (String) -> Void
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let sorgente = Azioni.sorgenti.first { $0.id == evento.subscription_id.t }
        let proprio = !evento.own_event_id.isNull
        let ripetuto = proprio && evento.id.t.contains("@")
        let lezione = proprio ? nil : Lezione(evento)
        let primo = Tempo.dataRoma(evento.start_at.str) ?? ""
        let fine = Tempo.data(evento.end_at.str)
        let ultimo = evento.all_day.vero ? fine.map { Tempo.dataRoma($0.addingTimeInterval(-1)) } ?? primo : Tempo.dataRoma(evento.end_at.str) ?? primo
        let orario = evento.all_day.vero ? "Tutto il giorno" : "\(Tempo.oraRoma(evento.start_at.str) ?? "") – \(Tempo.oraRoma(evento.end_at.str) ?? "")"
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(Color.life(sorgente?.colore)).frame(width: 10, height: 10)
                        Text(sorgente?.nome ?? "Calendario").foregroundStyle(Color.secondarioLife)
                        if !proprio { Text("· sola lettura").foregroundStyle(Color.terziarioLife) }
                    }
                    .font(.subheadline)
                    Text(lezione?.titolo ?? (evento.summary.t.isEmpty ? "(senza titolo)" : evento.summary.t)).font(.title3.weight(.semibold))
                    Label("\(Tempo.etichetta(primo).maiuscola)\(ultimo != primo ? " – \(Tempo.etichetta(ultimo))" : "") · \(orario)", systemImage: "clock")
                    if ripetuto { Label("Si ripete", systemImage: "repeat").foregroundStyle(Color.secondarioLife) }
                    if lezione == nil, evento.location.vero { Label(evento.location.t, systemImage: "mappin.and.ellipse") }
                }
                if let lezione {
                    Section {
                        ForEach(lezione.campi.filter { $0.0.lowercased() != "materia" }, id: \.0) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.0).font(.caption).foregroundStyle(Color.secondarioLife)
                                Text(c.1).font(.subheadline).textSelection(.enabled)
                            }
                        }
                    }
                } else if evento.description.vero {
                    Section { Text(evento.description.t).font(.subheadline).foregroundStyle(Color.secondarioLife).textSelection(.enabled) }
                }
                if proprio {
                    Section {
                        Button {
                            let id = evento.own_event_id.t
                            chiudi()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { modifica(id) }
                        } label: { Label("Modifica", systemImage: "pencil") }
                        Button(role: .destructive) {
                            Azioni.eliminaEvento(evento.own_event_id.t)
                            chiudi()
                        } label: { Label(ripetuto ? "Elimina (tutta la serie)" : "Elimina", systemImage: "trash") }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { chiudi() } } }
        }
    }
}

// MARK: - Editor

/// Creazione e modifica di un evento proprio, e la scelta «Evento o Task» creando.
struct EditorEvento: View {
    let bersaglio: NuovoEventoBersaglio
    @State private var tipo = "evento"
    @State private var titolo = ""
    @State private var calendario = ""
    @State private var progetto = ""
    @State private var tuttoIlGiorno = false
    @State private var inizio = Date()
    @State private var fine = Date().addingTimeInterval(3600)
    @State private var conOraTask = false
    @State private var luogo = ""
    @State private var note = ""
    @State private var ripeti = ""
    @State private var regola: String?
    @State private var promemoria: Set<Int> = []
    @State private var calAMano = false
    @State private var calAuto = false
    @State private var caricato = false
    @FocusState private var fuocoTitolo: Bool
    @Environment(\.dismiss) private var chiudi

    private let opzioniPromemoria = [(0, "All'inizio"), (5, "5 min"), (10, "10 min"), (30, "30 min"), (60, "1 ora"), (1440, "1 giorno")]
    private var nuovo: Bool { bersaglio.idEvento == nil }

    var body: some View {
        NavigationStack {
            Form {
                if nuovo {
                    Picker("Tipo", selection: $tipo) {
                        Text("Evento").tag("evento")
                        Text("Task").tag("task")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField(tipo == "task" ? "Cosa devi fare?" : "Titolo dell'evento", text: $titolo)
                        .font(.title3.weight(.semibold))
                        .focused($fuocoTitolo)
                        .onChange(of: titolo) { _, v in scegliCalendario(v) }
                }
                if tipo == "evento" {
                    Section {
                        Toggle("Tutto il giorno", isOn: $tuttoIlGiorno)
                        DatePicker("Inizia", selection: $inizio, displayedComponents: tuttoIlGiorno ? .date : [.date, .hourAndMinute])
                            .onChange(of: inizio) { vecchio, nuovo in
                                // La fine segue l'inizio
                                fine = fine.addingTimeInterval(nuovo.timeIntervalSince(vecchio))
                            }
                        DatePicker("Finisce", selection: $fine, in: inizio..., displayedComponents: tuttoIlGiorno ? .date : [.date, .hourAndMinute])
                    }
                    Section("Calendario") {
                        Picker("Calendario", selection: Binding(get: { calendario }, set: {
                            calendario = $0
                            calAMano = true
                            calAuto = false
                        })) {
                            ForEach(Azioni.calendariPropri, id: \.id) { c in
                                HStack {
                                    Circle().fill(Color.life(c.color.str)).frame(width: 10, height: 10)
                                    Text(c.name.t)
                                }
                                .tag(c.id.t)
                            }
                        }
                        .labelsHidden()
                        if calAuto { Text("Scelto dal titolo").font(.footnote).foregroundStyle(Color.secondarioLife) }
                    }
                    sezioneRipeti
                    Section {
                        TextField("Luogo", text: $luogo)
                        TextField("Note", text: $note, axis: .vertical).lineLimit(1...8)
                    }
                    Section("Promemoria") {
                        if regola != nil {
                            Text("I promemoria non sono disponibili per gli eventi che si ripetono.").font(.footnote).foregroundStyle(Color.secondarioLife)
                        } else {
                            ForEach(opzioniPromemoria, id: \.0) { o in
                                Button {
                                    if promemoria.contains(o.0) { promemoria.remove(o.0) } else { promemoria.insert(o.0) }
                                } label: {
                                    HStack {
                                        Text(o.1).foregroundStyle(Color.primary)
                                        Spacer()
                                        if promemoria.contains(o.0) { Image(systemName: "checkmark").foregroundStyle(Color.accentoLife) }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        DatePicker("Giorno", selection: $inizio, displayedComponents: .date)
                        Toggle("A un'ora precisa", isOn: $conOraTask)
                        if conOraTask { DatePicker("Ora", selection: $inizio, displayedComponents: .hourAndMinute) }
                        TextField("Note", text: $note, axis: .vertical).lineLimit(1...8)
                    }
                    sezioneRipeti
                    Section("Lista") {
                        Picker("Lista", selection: $progetto) {
                            ForEach(Azioni.progetti, id: \.id) { p in
                                Text(p.is_inbox.vero ? "In entrata" : p.name.t).tag(p.id.t)
                            }
                        }
                        .labelsHidden()
                    }
                }
                if !nuovo {
                    Section {
                        Button("Elimina l'evento", role: .destructive) {
                            if let id = bersaglio.idEvento { Azioni.eliminaEvento(id) }
                            chiudi()
                        }
                    }
                }
            }
            .navigationTitle(nuovo ? (tipo == "task" ? "Nuovo task" : "Nuovo evento") : "Modifica evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(nuovo ? (tipo == "task" ? "Aggiungi" : "Crea") : "Salva", action: salva).fontWeight(.semibold)
                }
            }
        }
        .environment(\.timeZone, Tempo.roma)
        .onAppear(perform: carica)
    }

    private var sezioneRipeti: some View {
        Section {
            TextField("Non si ripete (es. ogni lunedì)", text: $ripeti)
                .onChange(of: ripeti) { _, v in
                    let t = v.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        regola = nil
                    } else {
                        regola = Logica.s.chiama("parser.parseTask", .str(t.hasPrefix("ogni") || t.hasPrefix("tutti") ? t : "ogni \(t)"), [:]).rrule.str
                    }
                }
            if !ripeti.isEmpty {
                Text(regola.map { Logica.s.chiama("ricorrenze.describeRrule", .str($0)).t.maiuscola } ?? "Non capita").font(.footnote).foregroundStyle(regola == nil ? Color.pericoloLife : Color.accentoLife)
            }
        }
    }

    private func carica() {
        guard !caricato else { return }
        caricato = true
        progetto = Azioni.inbox?.id.str ?? Azioni.progetti.first?.id.str ?? ""
        calendario = Azioni.calendarioPredefinito ?? ""
        if let id = bersaglio.idEvento, let e = Archivio.s.riga("events", id) {
            titolo = e.title.t
            calendario = e.calendar_id.t
            tuttoIlGiorno = e.all_day.vero
            inizio = Tempo.data(e.start_at.str) ?? Date()
            let f = Tempo.data(e.end_at.str) ?? Date()
            fine = e.all_day.vero ? f.addingTimeInterval(-1) : f
            luogo = e.location.t
            note = e.notes.t
            regola = e.rrule.str
            if let r = e.rrule.str { ripeti = Logica.s.chiama("ricorrenze.describeRrule", .str(r)).t }
            promemoria = Set(Azioni.promemoria(evento: id).map { $0.offset_minutes.int ?? 0 })
        } else {
            let g = bersaglio.giorno ?? Tempo.oggi()
            inizio = Tempo.istante(g, bersaglio.inizio ?? "09:00")
            fine = Tempo.istante(g, bersaglio.fine ?? "10:00")
            tuttoIlGiorno = bersaglio.tuttoIlGiorno
            fuocoTitolo = true
        }
    }

    /// Il calendario si sceglie da solo dal titolo, finché non lo tocchi tu.
    private func scegliCalendario(_ testo: String) {
        guard nuovo, !calAMano else { return }
        let calendari = J.arr(Azioni.calendariPropri)
        let passati = J.arr(Archivio.s.tutte("events").filter { $0.deleted_at.isNull })
        if let id = Logica.s.chiama("calendarioDaTitolo.calendarioDaTitolo", .str(testo), calendari, passati).str {
            calendario = id
            calAuto = true
        } else if calAuto {
            calAuto = false
            calendario = Azioni.calendarioPredefinito ?? calendario
        }
    }

    private func salva() {
        let t = titolo.trimmingCharacters(in: .whitespaces)
        let n: J = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .str(note)
        if tipo == "task" {
            guard !t.isEmpty else {
                fuocoTitolo = true
                return
            }
            let (due, conOra) = Azioni.scadenza(Tempo.dataRoma(inizio), conOraTask ? Tempo.oraRoma(inizio) : nil)
            Azioni.creaTask(testo: t, contesto: ["project_id": .str(progetto), "notes": n, "due_at": due, "due_has_time": .bool(conOra), "rrule": .opz(regola)], interpreta: false)
            chiudi()
            return
        }
        guard !calendario.isEmpty else { return }
        var s = inizio
        var f = fine
        if tuttoIlGiorno {
            let gi = Tempo.dataRoma(inizio)
            var gf = Tempo.dataRoma(fine)
            if gf < gi { gf = gi }
            s = Tempo.istante(gi)
            f = Tempo.istante(Tempo.piuGiorni(gf, 1))
        } else if f <= s {
            f = s.addingTimeInterval(3600)
        }
        let valori: [String: J] = [
            "title": .str(t), "calendar_id": .str(calendario), "all_day": .bool(tuttoIlGiorno),
            "start_at": .str(Tempo.iso(s)), "end_at": .str(Tempo.iso(f)),
            "location": luogo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .str(luogo), "notes": n, "rrule": .opz(regola),
        ]
        Azioni.salvaEvento(id: bersaglio.idEvento, valori: valori, minutiPromemoria: Array(promemoria))
        if !promemoria.isEmpty { Notifiche.s.chiediPermesso() }
        chiudi()
    }
}
