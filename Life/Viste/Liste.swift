import SwiftUI

// Le viste delle liste in stile Things (come ThingsViews.tsx e ListsView.tsx).

/// Filtro per tag in cima alla lista.
struct FiltroTag: View {
    let tasks: [J]
    @Binding var tag: String?
    var body: some View {
        let tutti = Array(Set(tasks.flatMap { $0.tags.list.map(\.t) })).sorted()
        if !tutti.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Pillola(testo: "Tutti", attiva: tag == nil) { tag = nil }
                    ForEach(tutti, id: \.self) { t in
                        Pillola(testo: t, attiva: tag == t) { tag = tag == t ? nil : t }
                    }
                }
            }
        }
    }
}

private func perTag(_ tag: String?) -> (J) -> Bool {
    { t in tag == nil || t.tags.list.contains(.str(tag!)) }
}

// MARK: Oggi

struct VistaOggi: View {
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var notifiche = Notifiche.s
    @State private var tag: String?

    var body: some View {
        let _ = archivio.versione
        let oggi = Tempo.oggi()
        let tasks = Azioni.tasks
        let tutti = tasks.filter { Azioni.inOggi($0, oggi) }
        let visibili = tutti.filter(perTag(tag))
        let ritardo = visibili.filter { !$0.evening.vero && Azioni.inRitardo($0, oggi) }.sorted(by: Azioni.ordina)
        let delGiorno = visibili.filter { !$0.evening.vero && !Azioni.inRitardo($0, oggi) }
        let conOra = delGiorno.filter(\.due_has_time.vero).sorted { $0.due_at.t < $1.due_at.t }
        let senzaOra = delGiorno.filter { !$0.due_has_time.vero }.sorted(by: Azioni.ordina)
        let sera = visibili.filter(\.evening.vero).sorted(by: Azioni.ordina)
        let (due, _) = Azioni.scadenza(oggi, nil)
        let ctx: [String: J] = ["due_at": due, "due_has_time": false, "someday": false, "evening": false]
        var ctxSera = ctx
        ctxSera["evening"] = true
        let fatti = tasks.filter { !$0.completed_at.isNull && $0.deleted_at.isNull && Tempo.dataRoma($0.completed_at.str) == oggi }.count
        let (_, m, d) = Tempo.parti(oggi)
        var sotto = "\(Tempo.settimanaLunga[Tempo.giornoSettimana(oggi)].maiuscola) \(d) \(Tempo.mesiBrevi[m - 1]) · "
        sotto += tutti.isEmpty ? "niente da fare" : "\(tutti.count) da fare"
        if fatti > 0 { sotto += " · \(fatti) fatti" }
        var gruppi: [GruppoTask] = []
        if !ritardo.isEmpty { gruppi.append(GruppoTask(id: "late", titolo: "In ritardo  \(ritardo.count)", coloreTitolo: .pericoloLife, tasks: ritardo, contesto: ctx)) }
        if !conOra.isEmpty { gruppi.append(GruppoTask(id: "timed", titolo: "Con un orario  \(conOra.count)", tasks: conOra, contesto: ctx)) }
        gruppi.append(GruppoTask(id: "today", titolo: ritardo.isEmpty && conOra.isEmpty ? nil : "Da fare oggi  \(senzaOra.count)", tasks: senzaOra, contesto: ctx))
        if !sera.isEmpty { gruppi.append(GruppoTask(id: "evening", titolo: "Questa sera  \(sera.count)", tasks: sera, contesto: ctxSera)) }

        return ListaTask(
            gruppi: gruppi,
            opzioni: OpzioniRiga(mostraProgetto: true),
            vuoto: "Niente in programma per oggi",
            iconaVuoto: "star",
            contestoNuovo: ctx,
            testata: AnyView(VStack(alignment: .leading, spacing: 10) {
                Text(sotto).font(.subheadline).foregroundStyle(Color.secondarioLife)
                if notifiche.permesso == .notDetermined {
                    Button {
                        notifiche.chiediPermesso()
                    } label: {
                        Label("Attiva le notifiche dei promemoria", systemImage: "bell.badge")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.accentoLife.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                FiltroTag(tasks: tutti, tag: $tag)
            })
        )
        .navigationTitle("Oggi")
    }
}

// MARK: Programmate

struct VistaProgrammate: View {
    @ObservedObject private var archivio = Archivio.s
    @State private var tag: String?

    private func giornoDi(_ t: J, _ oggi: String) -> String {
        if let d = Azioni.giorno(t), d > oggi { return d }
        return t.deadline.t
    }

    var body: some View {
        let _ = archivio.versione
        let oggi = Tempo.oggi()
        let primo = Tempo.piuGiorni(oggi, 1)
        let ultimo = Tempo.piuGiorni(oggi, 14)
        let tutti = Azioni.tasks.filter { Azioni.inProgrammate($0, oggi) }
        let visibili = tutti.filter(perTag(tag))
        let eventi = Azioni.eventi(da: Tempo.intervallo(primo).0, a: Tempo.intervallo(ultimo).1)
        var gruppi: [GruppoTask] = []
        for i in 1...14 {
            let g = Tempo.piuGiorni(oggi, i)
            let (da, a) = Tempo.intervallo(g)
            let (due, _) = Azioni.scadenza(g, nil)
            gruppi.append(GruppoTask(
                id: g,
                titolo: i == 1 ? "Domani" : Tempo.settimanaLunga[Tempo.giornoSettimana(g)].maiuscola,
                grande: String(Tempo.parti(g).2),
                tasks: visibili.filter { giornoDi($0, oggi) == g }.sorted(by: Azioni.ordina),
                eventi: eventi.filter { $0.start_at.t < a && $0.end_at.t > da },
                contesto: ["due_at": due, "due_has_time": false, "evening": false, "someday": false]
            ))
        }
        // Oltre due settimane: per mese
        let dopo = visibili.filter { giornoDi($0, oggi) > ultimo }.sorted { x, y in
            let a = giornoDi(x, oggi)
            let b = giornoDi(y, oggi)
            return a == b ? Azioni.ordina(x, y) : a < b
        }
        let mesi = dopo.map { String(giornoDi($0, oggi).prefix(7)) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for ym in mesi {
            let (y, m, _) = Tempo.parti("\(ym)-01")
            let (due, _) = Azioni.scadenza("\(ym)-01", nil)
            gruppi.append(GruppoTask(
                id: ym,
                titolo: Tempo.mesiLunghi[m - 1] + (y == Tempo.parti(oggi).0 ? "" : " \(y)"),
                tasks: dopo.filter { giornoDi($0, oggi).hasPrefix(ym) },
                contesto: ["due_at": due, "due_has_time": false, "evening": false, "someday": false]
            ))
        }
        return ListaTask(
            gruppi: gruppi,
            opzioni: OpzioniRiga(mostraProgetto: true),
            contestoNuovo: gruppi.first?.contesto,
            testata: AnyView(FiltroTag(tasks: tutti, tag: $tag))
        )
        .navigationTitle("Programmate")
    }
}

// MARK: Liste

struct VistaListe: View {
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var preferenze = Preferenze.s
    @State private var cerca = ""

    var body: some View {
        let _ = archivio.versione
        let tasks = Azioni.tasks
        let progetti = Azioni.progetti
        let aperti = tasks.filter(Azioni.aperto)
        let oggi = Tempo.oggi()
        let inbox = Azioni.inbox?.id.str
        return List {
            if !cerca.isEmpty {
                let t = cerca.lowercased()
                let trovati = tasks.filter { $0.deleted_at.isNull && ($0.title.t.lowercased().contains(t) || $0.notes.t.lowercased().contains(t)) }.prefix(60)
                Section("Task") {
                    ForEach(Array(trovati), id: \.id) { r in
                        RigaTaskApribile(task: r)
                    }
                }
                let progettiTrovati = progetti.filter { $0.name.t.lowercased().contains(t) }
                if !progettiTrovati.isEmpty {
                    Section("Progetti") {
                        ForEach(progettiTrovati, id: \.id) { riga($0, tasks, aperti) }
                    }
                }
            } else {
                Section {
                    NavigationLink { VistaEntrata() } label: {
                        conConteggio("In entrata", "tray.fill", .accentoLife, tasks.filter { Azioni.inEntrata($0, inbox) }.count)
                    }
                    NavigationLink { VistaQualsiasi() } label: {
                        conConteggio("In qualsiasi momento", "square.stack.3d.up.fill", Color(hex: "#30B0C7"), tasks.filter { Azioni.inQualsiasi($0, oggi, inbox) }.count)
                    }
                    NavigationLink { VistaUnGiorno() } label: {
                        conConteggio("Un giorno", "archivebox.fill", Color(hex: "#C9A15B"), tasks.filter { Azioni.aperto($0) && $0.someday.vero }.count)
                    }
                    NavigationLink { VistaRegistro() } label: {
                        conConteggio("Registro", "checkmark.square.fill", .successoLife, 0)
                    }
                }
                Section("Progetti") {
                    ForEach(progetti.filter { !$0.is_inbox.vero && $0.area_id.isNull }, id: \.id) { riga($0, tasks, aperti) }
                    Button {
                        Domanda.chiedi(titolo: "Nome del progetto") { n in
                            if !n.isEmpty { Azioni.creaProgetto(n) }
                        }
                    } label: { Label("Nuovo progetto", systemImage: "plus") }
                }
                ForEach(Azioni.aree, id: \.id) { a in
                    Section(a.name.t) {
                        NavigationLink { VistaArea(idArea: a.id.t) } label: { Label("Tutta l'area", systemImage: "square.grid.2x2").foregroundStyle(Color.primary) }
                        ForEach(progetti.filter { $0.area_id == a.id }, id: \.id) { riga($0, tasks, aperti) }
                    }
                }
                Section("Calendari") {
                    ForEach(Azioni.sorgenti) { c in
                        Button { Azioni.cambia(sorgente: c, ["hidden": .bool(!c.nascosto)]) } label: { rigaCalendario(c.nome, .life(c.colore), !c.nascosto, c.predefinito ? "Predefinito" : nil) }
                    }
                    Button { preferenze.promemoriaInCalendario.toggle() } label: {
                        rigaCalendario("Promemoria", .accentoLife, preferenze.promemoriaInCalendario, "To do")
                    }
                }
                Section {
                    NavigationLink { VistaCestino() } label: { Label("Cestino", systemImage: "trash").foregroundStyle(Color.primary) }
                } footer: {
                    Text(statoSync).frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                }
            }
        }
        .navigationTitle("Liste")
        .searchable(text: $cerca, prompt: "Cerca")
    }

    private var statoSync: String {
        switch archivio.stato {
        case .offline: return "Offline · le modifiche verranno sincronizzate"
        case .errore: return "Sincronizzazione non riuscita"
        default: return archivio.inCoda > 0 ? "\(archivio.inCoda) modifiche da inviare" : "Sincronizzato"
        }
    }

    private func conConteggio(_ nome: String, _ icona: String, _ colore: Color, _ n: Int) -> some View {
        HStack {
            Label {
                Text(nome)
            } icon: {
                Image(systemName: icona).foregroundStyle(colore)
            }
            Spacer()
            if n > 0 { Text("\(n)").foregroundStyle(Color.secondarioLife) }
        }
    }

    private func riga(_ p: J, _ tasks: [J], _ aperti: [J]) -> some View {
        NavigationLink { VistaProgetto(idProgetto: p.id.t) } label: {
            HStack(spacing: 10) {
                IconaProgetto(progetto: p, tasks: tasks)
                Text(p.name.t)
                Spacer()
                let n = aperti.filter { $0.project_id == p.id }.count
                if n > 0 { Text("\(n)").foregroundStyle(Color.secondarioLife) }
            }
        }
    }

    private func rigaCalendario(_ nome: String, _ colore: Color, _ acceso: Bool, _ nota: String?) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(colore, lineWidth: 2).background(Circle().fill(acceso ? colore : .clear))
                if acceso { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
            }
            .frame(width: 20, height: 20)
            Text(nome).foregroundStyle(acceso ? Color.primary : Color.secondarioLife)
            Spacer()
            if let nota { Text(nota).font(.footnote).foregroundStyle(Color.terziarioLife) }
        }
    }
}

/// Una riga che si apre in un foglio (ricerca, cestino).
struct RigaTaskApribile: View {
    let task: J
    var coda: AnyView? = nil
    @State private var aperto = false
    var body: some View {
        RigaTask(task: task, opzioni: OpzioniRiga(mostraProgetto: true), coda: coda)
            .contentShape(Rectangle())
            .onTapGesture { aperto = true }
            .sheet(isPresented: $aperto) { SchedaTask(idTask: task.id.t) }
    }
}

struct VistaEntrata: View {
    @ObservedObject private var archivio = Archivio.s
    var body: some View {
        let _ = archivio.versione
        let inbox = Azioni.inbox?.id.str
        let lista = Azioni.tasks.filter { Azioni.inEntrata($0, inbox) }.sorted(by: Azioni.ordina)
        let ctx: [String: J] = ["project_id": .opz(inbox), "heading_id": nil, "due_at": nil, "due_has_time": false, "someday": false]
        return ListaTask(gruppi: [GruppoTask(id: "inbox", tasks: lista, contesto: ctx)], opzioni: OpzioniRiga(mostraQuando: true), vuoto: "La tua In entrata è vuota", iconaVuoto: "tray", contestoNuovo: ctx)
            .navigationTitle("In entrata")
    }
}

/// Gruppi per progetto, come useProjectGroups.
private func gruppiPerProgetto(_ tasks: [J], contesto: [String: J]) -> [GruppoTask] {
    let progetti = Azioni.progetti
    let ordine = progetti.filter(\.is_inbox.vero) + progetti.filter { !$0.is_inbox.vero && $0.area_id.isNull } + Azioni.aree.flatMap { a in progetti.filter { $0.area_id == a.id } }
    var out: [GruppoTask] = []
    for p in ordine {
        let l = tasks.filter { $0.project_id == p.id }.sorted(by: Azioni.ordina)
        if l.isEmpty { continue }
        var c = contesto
        c["project_id"] = p.id
        out.append(GruppoTask(id: p.id.t, titolo: p.is_inbox.vero ? "In entrata" : p.name.t, tasks: l, contesto: c))
    }
    return out
}

struct VistaQualsiasi: View {
    @ObservedObject private var archivio = Archivio.s
    @State private var tag: String?
    var body: some View {
        let _ = archivio.versione
        let oggi = Tempo.oggi()
        let inbox = Azioni.inbox?.id.str
        let tutti = Azioni.tasks.filter { Azioni.inQualsiasi($0, oggi, inbox) }
        return ListaTask(gruppi: gruppiPerProgetto(tutti.filter(perTag(tag)), contesto: ["someday": false]), opzioni: OpzioniRiga(mostraQuando: true), vuoto: "Nessun task attivo", iconaVuoto: "square.stack.3d.up", contestoNuovo: ["someday": false], testata: AnyView(FiltroTag(tasks: tutti, tag: $tag)))
            .navigationTitle("In qualsiasi momento")
    }
}

struct VistaUnGiorno: View {
    @ObservedObject private var archivio = Archivio.s
    @State private var tag: String?
    var body: some View {
        let _ = archivio.versione
        let tutti = Azioni.tasks.filter { Azioni.aperto($0) && $0.someday.vero }
        let ctx: [String: J] = ["someday": true, "due_at": nil, "due_has_time": false]
        return ListaTask(gruppi: gruppiPerProgetto(tutti.filter(perTag(tag)), contesto: ctx), vuoto: "Niente messo da parte per un giorno", iconaVuoto: "archivebox", contestoNuovo: ctx, testata: AnyView(FiltroTag(tasks: tutti, tag: $tag)))
            .navigationTitle("Un giorno")
    }
}

struct VistaRegistro: View {
    @ObservedObject private var archivio = Archivio.s
    var body: some View {
        let _ = archivio.versione
        let fatti = Azioni.tasks.filter { $0.deleted_at.isNull && !$0.completed_at.isNull }.sorted { $0.completed_at.t > $1.completed_at.t }.prefix(500)
        var giorni: [String] = []
        for t in fatti {
            if let g = Tempo.dataRoma(t.completed_at.str), !giorni.contains(g) { giorni.append(g) }
        }
        let gruppi = giorni.map { g in GruppoTask(id: g, titolo: Tempo.etichetta(g).maiuscola, tasks: fatti.filter { Tempo.dataRoma($0.completed_at.str) == g }) }
        return ListaTask(gruppi: gruppi, opzioni: OpzioniRiga(mostraProgetto: true), vuoto: "Qui finiscono i task completati", iconaVuoto: "checkmark.square")
            .navigationTitle("Registro")
    }
}

struct VistaCestino: View {
    @ObservedObject private var archivio = Archivio.s
    var body: some View {
        let _ = archivio.versione
        let cestinati = Azioni.tasks.filter(Azioni.inCestino).sorted { $0.deleted_at.t > $1.deleted_at.t }
        return List {
            if cestinati.isEmpty {
                Text("Il cestino è vuoto").foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            }
            ForEach(cestinati, id: \.id) { t in
                HStack {
                    Text(t.title.t.isEmpty ? "Nuovo task" : t.title.t).foregroundStyle(Color.secondarioLife).lineLimit(2)
                    Spacer()
                    Button("Ripristina") { Azioni.ripristina(t) }.font(.footnote).buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("Cestino")
        .toolbar {
            if !cestinati.isEmpty {
                Button("Svuota", role: .destructive) {
                    Domanda.conferma(titolo: "Eliminare definitivamente \(cestinati.count) task?", messaggio: "Non si potrà annullare.") {
                        let ids = Azioni.tasks.filter { !$0.deleted_at.isNull }.map(\.id.t)
                        Task { @MainActor in
                            do {
                                try await Archivio.s.eliminaDefinitivamente(tasks: ids)
                            } catch {
                                Logica.s.mostra(error.localizedDescription, "errore")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Progetto e area

struct VistaProgetto: View {
    let idProgetto: String
    @ObservedObject private var archivio = Archivio.s
    @State private var tag: String?
    @State private var mostraFatti = false
    @State private var note = ""
    @State private var sceltaEmoji = false
    @FocusState private var scriveNote: Bool
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let _ = archivio.versione
        let progetto = archivio.riga("projects", idProgetto) ?? .null
        if progetto.isNull || !progetto.deleted_at.isNull {
            Text("Progetto non trovato").foregroundStyle(Color.secondarioLife)
        } else if progetto.is_inbox.vero {
            VistaEntrata()
        } else {
            contenuto(progetto)
        }
    }

    private func contenuto(_ p: J) -> some View {
        let miei = Azioni.tasks.filter { $0.project_id.str == idProgetto && $0.deleted_at.isNull }
        let aperti = miei.filter(Azioni.aperto)
        let visibili = aperti.filter(perTag(tag))
        let fatti = miei.filter { !$0.completed_at.isNull }.sorted { $0.completed_at.t > $1.completed_at.t }
        let intestazioni = Azioni.intestazioni(idProgetto).filter { $0.archived_at.isNull }
        let ids = Set(intestazioni.map(\.id.t))
        var gruppi = [GruppoTask(id: "none", tasks: visibili.filter { !ids.contains($0.heading_id.t) }.sorted(by: Azioni.ordina), contesto: ["project_id": .str(idProgetto), "heading_id": nil])]
        for h in intestazioni {
            gruppi.append(GruppoTask(id: h.id.t, tasks: visibili.filter { $0.heading_id == h.id }.sorted(by: Azioni.ordina), contesto: ["project_id": .str(idProgetto), "heading_id": h.id], intestazione: h))
        }
        if mostraFatti { gruppi.append(GruppoTask(id: "done", titolo: "Completati", tasks: fatti)) }
        return ListaTask(
            gruppi: gruppi,
            opzioni: OpzioniRiga(mostraQuando: true),
            contestoNuovo: ["project_id": .str(idProgetto), "heading_id": nil],
            testata: AnyView(VStack(alignment: .leading, spacing: 10) {
                TextField("Note", text: $note, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondarioLife)
                    .focused($scriveNote)
                    .onChange(of: scriveNote) { _, f in
                        if !f, note != p.notes.t {
                            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            Azioni.aggiorna(progetto: idProgetto, ["notes": n.isEmpty ? nil : .str(n)])
                        }
                    }
                FiltroTag(tasks: aperti, tag: $tag)
                if !fatti.isEmpty {
                    Button(mostraFatti ? "Nascondi \(fatti.count) completati" : "Mostra \(fatti.count) completati") { mostraFatti.toggle() }
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.secondarioLife)
                }
            })
        )
        .navigationTitle(p.name.t)
        .onAppear { note = p.notes.t }
        .toolbar {
            Menu {
                Button { rinomina(p) } label: { Label("Rinomina", systemImage: "pencil") }
                Button { sceltaEmoji = true } label: { Label("Icona", systemImage: "face.smiling") }
                Button { nuovaIntestazione() } label: { Label("Nuova intestazione", systemImage: "text.badge.plus") }
                Menu {
                    Button("Nessuna area") { Azioni.aggiorna(progetto: idProgetto, ["area_id": nil]) }
                    ForEach(Azioni.aree, id: \.id) { a in
                        Button(a.name.t) { Azioni.aggiorna(progetto: idProgetto, ["area_id": a.id]) }
                    }
                } label: { Label("Sposta in un'area", systemImage: "square.grid.2x2") }
                Menu {
                    ForEach(Palette.colori, id: \.0) { c in
                        Button(c.1) { Azioni.aggiorna(progetto: idProgetto, ["color": .str(c.0)]) }
                    }
                } label: { Label("Colore", systemImage: "paintpalette") }
                Button {
                    Azioni.completa(progetto: p)
                    chiudi()
                } label: { Label("Completa il progetto", systemImage: "checkmark.circle") }
                Button(role: .destructive) {
                    Domanda.conferma(titolo: "Eliminare il progetto «\(p.name.t)» e i suoi task?") {
                        Azioni.elimina(progetto: p)
                        chiudi()
                    }
                } label: { Label("Elimina", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $sceltaEmoji) {
            SceltaEmoji(titolo: "Icona del progetto", togli: p.emoji.vero ? { Azioni.aggiorna(progetto: idProgetto, ["emoji": nil]) } : nil) { e in
                Azioni.aggiorna(progetto: idProgetto, ["emoji": .str(e)])
            }
        }
    }

    private func rinomina(_ p: J) {
        Domanda.chiedi(titolo: "Rinomina il progetto", valore: p.name.t) { n in
            if !n.isEmpty { Azioni.aggiorna(progetto: idProgetto, ["name": .str(n)]) }
        }
    }

    private func nuovaIntestazione() {
        Domanda.chiedi(titolo: "Nuova intestazione") { n in
            if !n.isEmpty { Azioni.creaIntestazione(idProgetto, n) }
        }
    }
}

struct VistaArea: View {
    let idArea: String
    @ObservedObject private var archivio = Archivio.s
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        let _ = archivio.versione
        let area = archivio.riga("areas", idArea) ?? .null
        let tasks = Azioni.tasks
        let progetti = Azioni.progetti.filter { $0.area_id.str == idArea }
        return List {
            ForEach(progetti, id: \.id) { p in
                NavigationLink { VistaProgetto(idProgetto: p.id.t) } label: {
                    HStack(spacing: 10) {
                        IconaProgetto(progetto: p, tasks: tasks)
                        Text(p.name.t)
                    }
                }
            }
            Button {
                Domanda.chiedi(titolo: "Nome del progetto") { n in
                    if !n.isEmpty { Azioni.creaProgetto(n, area: idArea) }
                }
            } label: { Label("Nuovo progetto", systemImage: "plus") }
        }
        .navigationTitle(area.name.t)
        .toolbar {
            Menu {
                Button("Rinomina") {
                    Domanda.chiedi(titolo: "Rinomina l'area", valore: area.name.t) { n in
                        if !n.isEmpty { Azioni.aggiorna(area: idArea, ["name": .str(n)]) }
                    }
                }
                Button("Elimina l'area", role: .destructive) {
                    Azioni.elimina(area: area)
                    chiudi()
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
}

enum Palette {
    static let colori: [(String, String)] = [
        ("#8E8E93", "Grigio"), ("#5AC8FA", "Azzurro"), ("#0A84FF", "Blu"), ("#5E5CE6", "Indaco"), ("#AF52DE", "Viola"),
        ("#FF2D55", "Rosa"), ("#FF3B30", "Rosso"), ("#FF9500", "Arancione"), ("#FFCC00", "Giallo"), ("#34C759", "Verde"),
        ("#2E7D32", "Verde scuro"), ("#30B0C7", "Turchese"), ("#8B2C2C", "Bordeaux"), ("#A2845E", "Marrone"),
    ]
}

/// Scelta di un'emoji: quelle più usate, più un campo per la tastiera emoji di iOS.
struct SceltaEmoji: View {
    let titolo: String
    var togli: (() -> Void)? = nil
    let scegli: (String) -> Void
    @State private var testo = ""
    @Environment(\.dismiss) private var chiudi
    private let comuni = ["🎯", "📚", "💼", "🏠", "💡", "🧠", "💪", "🏃", "🥗", "💰", "✈️", "🎓", "🛠️", "🧹", "🛒", "❤️", "🎨", "🎵", "🌱", "⭐️", "🔥", "📅", "📝", "📦", "🚗", "🐶", "🧘", "☀️", "🌙", "🎁", "🏋️", "⚽️", "💻", "📱", "🧾", "🗂️"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("Scrivi un'emoji", text: $testo)
                        .multilineTextAlignment(.center)
                        .campo()
                        .onChange(of: testo) { _, v in
                            if let c = v.last, c.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0xFF }) {
                                scegli(String(c))
                                chiudi()
                            }
                        }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(comuni, id: \.self) { e in
                            Button {
                                scegli(e)
                                chiudi()
                            } label: {
                                Text(e).font(.system(size: 30)).frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let togli {
                        Button("Togli l'icona", role: .destructive) {
                            togli()
                            chiudi()
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
