import SwiftUI

/// Un gruppo di task in una lista.
struct GruppoTask: Identifiable {
    var id: String
    var titolo: String? = nil
    var coloreTitolo: Color? = nil
    var grande: String? = nil // il numero del giorno in Programmate
    var tasks: [J]
    var eventi: [J] = []
    var contesto: [String: J] = [:]
    var intestazione: J? = nil
}

/// Le opzioni di una riga.
struct OpzioniRiga {
    var mostraProgetto = false
    var mostraQuando = false
}

/// La casella tonda: la spunta scatta, poi la riga esce.
struct Casella: View {
    let task: J
    var lato: CGFloat = 22
    @State private var inCorso = false
    @State private var lavoro: DispatchWorkItem?

    private var colore: Color {
        if !task.completed_at.isNull || inCorso { return .accentoLife }
        switch task.priority.int ?? 4 {
        case 1: return Color(hex: "#FF453A")
        case 2: return Color(hex: "#FF9F0A")
        case 3: return .accentoLife
        default: return Color(uiColor: .tertiaryLabel)
        }
    }

    var body: some View {
        let fatto = !task.completed_at.isNull || inCorso
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if !task.completed_at.isNull {
                Azioni.completa(task)
                return
            }
            if inCorso {
                lavoro?.cancel()
                inCorso = false
                return
            }
            inCorso = true
            let w = DispatchWorkItem { Azioni.completa(task) }
            lavoro = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: w)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: lato * 0.28, style: .continuous)
                    .strokeBorder(colore, lineWidth: 1.6)
                    .background(RoundedRectangle(cornerRadius: lato * 0.28, style: .continuous).fill(fatto ? colore : .clear))
                if fatto {
                    Image(systemName: "checkmark").font(.system(size: lato * 0.55, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: lato, height: lato)
            .scaleEffect(inCorso ? 1.12 : 1)
            .animation(.spring(duration: 0.25), value: inCorso)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Una riga di task.
struct RigaTask: View {
    let task: J
    var opzioni = OpzioniRiga()
    var coda: AnyView? = nil

    var body: some View {
        let oggi = Tempo.oggi()
        let d = Azioni.giorno(task)
        let progetto = Archivio.s.riga("projects", task.project_id.t)
        let scaduto = d != nil && d! < oggi
        let checklist = task.checklist.list
        HStack(alignment: .top, spacing: 8) {
            Casella(task: task)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if opzioni.mostraQuando, let d, !task.someday.vero {
                        if d <= oggi {
                            Image(systemName: task.evening.vero ? "moon.fill" : "star.fill")
                                .font(.caption2)
                                .foregroundStyle(task.evening.vero ? Color.indigo : Color.yellow)
                        } else {
                            Text(Tempo.breve(d)).font(.caption2).padding(.horizontal, 5).padding(.vertical, 2).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(Color.secondarioLife)
                        }
                    }
                    if (task.priority.int ?? 4) < 4 {
                        Image(systemName: "flag.fill").font(.caption2).foregroundStyle((task.priority.int ?? 4) == 1 ? Color(hex: "#FF453A") : (task.priority.int ?? 4) == 2 ? Color(hex: "#FF9F0A") : Color.accentoLife)
                    }
                    Text(task.title.t.isEmpty ? "Nuovo task" : task.title.t)
                        .foregroundStyle(task.title.t.isEmpty ? Color.terziarioLife : !task.completed_at.isNull ? Color.secondarioLife : Color.primary)
                        .lineLimit(2)
                    if task.notes.vero { Image(systemName: "doc.text").font(.caption2).foregroundStyle(Color.terziarioLife) }
                    if !checklist.isEmpty { Image(systemName: "checklist").font(.caption2).foregroundStyle(Color.terziarioLife) }
                    if task.rrule.vero { Image(systemName: "repeat").font(.caption2).foregroundStyle(Color.terziarioLife) }
                    if let o = Azioni.ora(task) {
                        Text(o).font(.caption2).foregroundStyle(scaduto ? Color.pericoloLife : Color.terziarioLife)
                    }
                    Spacer(minLength: 0)
                    if let s = task.deadline.str, !s.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "flag")
                            Text(s == oggi ? "oggi" : s < oggi ? Tempo.etichetta(s) : Tempo.breve(s))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(s <= oggi ? Color.rosaLife : Color.secondarioLife)
                    }
                    coda
                }
                if !task.tags.list.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(task.tags.list, id: \.self) { t in
                                Text(t.t).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).overlay(Capsule().stroke(Color.lineaLife)).foregroundStyle(Color.secondarioLife)
                            }
                        }
                    }
                }
                if opzioni.mostraProgetto, let progetto, !progetto.is_inbox.vero {
                    Text(progetto.name.t).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1)
                }
                if scaduto, !opzioni.mostraQuando, !task.someday.vero, let d {
                    Text(Tempo.etichetta(d)).font(.caption2).foregroundStyle(Color.pericoloLife)
                }
                if task.someday.vero, opzioni.mostraQuando {
                    Text("Un giorno").font(.caption2).foregroundStyle(Color.terziarioLife)
                }
                if !checklist.isEmpty {
                    Text("\(checklist.filter(\.done.vero).count)/\(checklist.count)").font(.caption2).foregroundStyle(Color.terziarioLife)
                }
            }
            .padding(.top, 7)
            .padding(.bottom, 5)
        }
    }
}

/// La lista: righe scorrevoli con i gesti di iOS. Scorri a destra per completare, a sinistra per il resto.
struct ListaTask: View {
    let gruppi: [GruppoTask]
    var opzioni = OpzioniRiga()
    var vuoto: String? = nil
    var iconaVuoto = "tray"
    var contestoNuovo: [String: J]? = nil
    var testata: AnyView? = nil
    @State private var aperto: TaskAperto?
    @State private var scegliQuando: TaskAperto?
    @State private var scegliProgetto: TaskAperto?
    @State private var nuovo = false

    var body: some View {
        let tuttiVuoti = gruppi.allSatisfy { $0.tasks.isEmpty && $0.eventi.isEmpty }
        List {
            if let testata {
                testata.listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }
            if tuttiVuoti, let vuoto {
                VStack(spacing: 12) {
                    Image(systemName: iconaVuoto).font(.system(size: 40)).foregroundStyle(Color.terziarioLife)
                    Text(vuoto).font(.subheadline).foregroundStyle(Color.secondarioLife)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(gruppi) { g in
                if !g.tasks.isEmpty || !g.eventi.isEmpty || g.titolo != nil || g.grande != nil {
                    Section {
                        ForEach(g.eventi, id: \.self) { e in
                            RigaEventoLista(evento: e)
                        }
                        ForEach(g.tasks, id: \.id) { t in
                            riga(t)
                        }
                    } header: {
                        testataGruppo(g)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottomTrailing) {
            if contestoNuovo != nil {
                Button {
                    tocco()
                    nuovo = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentoLife, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 16)
            }
        }
        .sheet(item: $aperto) { a in SchedaTask(idTask: a.task.id.t) }
        .sheet(item: $scegliQuando) { a in SceltaQuando(task: a.task) }
        .sheet(item: $scegliProgetto) { a in SceltaProgetto(task: a.task) }
        .sheet(isPresented: $nuovo) { NuovoTask(contesto: contestoNuovo ?? [:]) }
    }

    @ViewBuilder
    private func testataGruppo(_ g: GruppoTask) -> some View {
        if let grande = g.grande {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(grande).font(.title2.bold()).monospacedDigit().foregroundStyle(Color.primary)
                if let t = g.titolo { Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(Color.secondarioLife) }
            }
        } else if let h = g.intestazione {
            Menu {
                Button("Rinomina") { rinominaIntestazione(h) }
                Button("Archivia (completa i suoi task)") { Azioni.archivia(intestazione: h) }
                Button("Elimina intestazione", role: .destructive) { Azioni.elimina(intestazione: h) }
            } label: {
                Text(h.title.t).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentoLife)
            }
        } else if let t = g.titolo {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(g.coloreTitolo ?? Color.secondarioLife)
        }
    }

    private func rinominaIntestazione(_ h: J) {
        Domanda.chiedi(titolo: "Rinomina intestazione", valore: h.title.t) { v in
            if !v.isEmpty { Azioni.aggiorna(intestazione: h.id.t, ["title": .str(v)]) }
        }
    }

    private func riga(_ t: J) -> some View {
        RigaTask(task: t, opzioni: opzioni)
            .contentShape(Rectangle())
            .onTapGesture { aperto = TaskAperto(task: t) }
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { Azioni.completa(t) } label: { Label("Fatto", systemImage: "checkmark") }.tint(.accentoLife)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { Azioni.elimina(t) } label: { Label("Elimina", systemImage: "trash") }
                Button { scegliQuando = TaskAperto(task: t) } label: { Label("Quando", systemImage: "calendar") }.tint(.orange)
            }
            .contextMenu {
                Button { Azioni.completa(t) } label: { Label(t.completed_at.isNull ? "Completa" : "Riapri", systemImage: "checkmark") }
                Button { Azioni.quando(t, .oggi) } label: { Label("Oggi", systemImage: "star") }
                Button { Azioni.quando(t, .sera) } label: { Label("Questa sera", systemImage: "moon") }
                Button { Azioni.quando(t, .data(Tempo.piuGiorni(Tempo.oggi(), 1), nil)) } label: { Label("Domani", systemImage: "sunrise") }
                Button { Azioni.quando(t, .unGiorno) } label: { Label("Un giorno", systemImage: "archivebox") }
                Button { scegliQuando = TaskAperto(task: t) } label: { Label("Scegli la data…", systemImage: "calendar") }
                Button { scegliProgetto = TaskAperto(task: t) } label: { Label("Sposta in…", systemImage: "folder") }
                Menu {
                    ForEach([(1, "Alta"), (2, "Media"), (3, "Bassa"), (4, "Nessuna")], id: \.0) { p in
                        Button(p.1) { Azioni.modifica(t.id.t, ["priority": .n(p.0)], "Priorità \(p.1.lowercased())") }
                    }
                } label: { Label("Priorità", systemImage: "flag") }
                Button { Azioni.duplica(t) } label: { Label("Duplica", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { Azioni.elimina(t) } label: { Label("Elimina", systemImage: "trash") }
            }
    }
}

/// Un evento nella riga di una lista (Programmate).
struct RigaEventoLista: View {
    let evento: J
    var body: some View {
        let colore = Azioni.sorgenti.first { $0.id == evento.subscription_id.t }?.colore
        HStack(spacing: 8) {
            Capsule().fill(Color.life(colore)).frame(width: 3, height: 18)
            Text(evento.all_day.vero ? "tutto" : Tempo.oraRoma(evento.start_at.str) ?? "")
                .font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife)
            Text(evento.summary.t.isEmpty ? "(senza titolo)" : evento.summary.t).font(.subheadline).foregroundStyle(Color.secondarioLife).lineLimit(1)
        }
        .listRowSeparator(.hidden)
    }
}

/// Le domande di testo (come `prompt` sul sito).
enum Domanda {
    static func chiedi(titolo: String, valore: String = "", conferma: String = "OK", fatto: @escaping (String) -> Void) {
        guard let scena = UIApplication.shared.connectedScenes.first as? UIWindowScene, var cima = scena.keyWindow?.rootViewController else { return }
        while let p = cima.presentedViewController { cima = p }
        let a = UIAlertController(title: titolo, message: nil, preferredStyle: .alert)
        a.addTextField { $0.text = valore; $0.clearButtonMode = .whileEditing }
        a.addAction(UIAlertAction(title: "Annulla", style: .cancel))
        a.addAction(UIAlertAction(title: conferma, style: .default) { _ in
            fatto((a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces))
        })
        cima.present(a, animated: true)
    }

    static func conferma(titolo: String, messaggio: String? = nil, azione: String = "Elimina", distruttiva: Bool = true, fatto: @escaping () -> Void) {
        guard let scena = UIApplication.shared.connectedScenes.first as? UIWindowScene, var cima = scena.keyWindow?.rootViewController else { return }
        while let p = cima.presentedViewController { cima = p }
        let a = UIAlertController(title: titolo, message: messaggio, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Annulla", style: .cancel))
        a.addAction(UIAlertAction(title: azione, style: distruttiva ? .destructive : .default) { _ in fatto() })
        cima.present(a, animated: true)
    }
}

// MARK: - Nuovo task

struct NuovoTask: View {
    let contesto: [String: J]
    @State private var testo = ""
    @FocusState private var fuoco: Bool
    @Environment(\.dismiss) private var chiudi

    private var anteprima: String {
        let t = testo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "" }
        let p = Logica.s.chiama("parser.parseTask", .str(t), ["projects": .arr(Azioni.progetti.map { .str($0.name.t) })])
        let d = Logica.s.chiama("parser.describeParse", p).t
        return d.isEmpty ? "" : "\(p.title.t) · \(d)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Cosa devi fare?", text: $testo, axis: .vertical)
                    .font(.title3)
                    .focused($fuoco)
                    .submitLabel(.done)
                    .onSubmit(salva)
                if !anteprima.isEmpty {
                    Text(anteprima).font(.footnote).foregroundStyle(Color.accentoLife)
                } else {
                    Text("Scrivi anche «domani alle 15 #Studio !2»: lo capisco.").font(.footnote).foregroundStyle(Color.terziarioLife)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Nuovo task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) { Button("Aggiungi", action: salva).fontWeight(.semibold).disabled(testo.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
        .presentationDetents([.medium])
        .onAppear { fuoco = true }
    }

    private func salva() {
        Azioni.creaTask(testo: testo, contesto: contesto)
        chiudi()
    }
}

// MARK: - La scheda del task

struct SchedaTask: View {
    let idTask: String
    @ObservedObject private var archivio = Archivio.s
    @State private var titolo = ""
    @State private var note = ""
    @State private var ripeti = ""
    @State private var nuovoTag = ""
    @State private var caricato = false
    @State private var sceltaQuando = false
    @State private var sceltaScadenza = false
    @State private var sceltaProgetto = false
    @State private var sceltaPromemoria = false
    @State private var quandoPromemoria = Date()
    @Environment(\.dismiss) private var chiudi

    private var task: J { archivio.riga("tasks", idTask) ?? .null }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 4) {
                        Casella(task: task)
                        TextField("Titolo", text: $titolo, axis: .vertical).font(.title3.weight(.medium)).padding(.top, 5)
                    }
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...12).foregroundStyle(Color.secondarioLife)
                }
                Section {
                    Button { sceltaQuando = true } label: {
                        HStack {
                            Label("Quando", systemImage: "calendar")
                            Spacer()
                            Text(etichettaQuando).foregroundStyle(Color.secondarioLife)
                        }
                    }
                    Button { sceltaScadenza = true } label: {
                        HStack {
                            Label("Scadenza", systemImage: "flag")
                            Spacer()
                            Text(task.deadline.str.map(Tempo.etichetta) ?? "Nessuna").foregroundStyle(Color.secondarioLife)
                        }
                    }
                    Button { sceltaProgetto = true } label: {
                        HStack {
                            Label("Lista", systemImage: "folder")
                            Spacer()
                            let p = archivio.riga("projects", task.project_id.t)
                            Text(p?.is_inbox.vero == true ? "In entrata" : p?.name.t ?? "").foregroundStyle(Color.secondarioLife)
                        }
                    }
                    Picker(selection: Binding(get: { task.priority.int ?? 4 }, set: { Azioni.aggiorna(idTask, ["priority": .n($0)]) })) {
                        Text("Alta").tag(1)
                        Text("Media").tag(2)
                        Text("Bassa").tag(3)
                        Text("Nessuna").tag(4)
                    } label: {
                        Label("Priorità", systemImage: "exclamationmark.circle")
                    }
                }
                .foregroundStyle(Color.primary)
                Section {
                    HStack {
                        Label("Ripeti", systemImage: "repeat")
                        TextField("es. ogni lunedì", text: $ripeti)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: ripeti) { _, v in cambiaRipeti(v) }
                    }
                    if task.rrule.vero {
                        Text(Logica.s.chiama("ricorrenze.describeRrule", task.rrule).t.maiuscola).font(.footnote).foregroundStyle(Color.accentoLife)
                    } else if !ripeti.isEmpty {
                        Text("Non capito: prova «ogni 2 settimane»").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                }
                Section("Checklist") {
                    ForEach(task.checklist.list, id: \.id) { v in
                        HStack {
                            Button { segna(v) } label: {
                                Image(systemName: v.done.vero ? "checkmark.circle.fill" : "circle").foregroundStyle(v.done.vero ? Color.accentoLife : Color.terziarioLife)
                            }
                            .buttonStyle(.plain)
                            TextField("Elemento", text: Binding(get: { v.title.t }, set: { rinomina(v, $0) }))
                                .strikethrough(v.done.vero)
                                .foregroundStyle(v.done.vero ? Color.secondarioLife : Color.primary)
                        }
                    }
                    .onDelete { i in
                        var l = task.checklist.list
                        l.remove(atOffsets: i)
                        Azioni.aggiorna(idTask, ["checklist": .arr(l)])
                    }
                    .onMove { da, a in
                        var l = task.checklist.list
                        l.move(fromOffsets: da, toOffset: a)
                        Azioni.aggiorna(idTask, ["checklist": .arr(l)])
                    }
                    Button {
                        Azioni.aggiorna(idTask, ["checklist": .arr(task.checklist.list + [["id": .str(Azioni.nuovoId()), "title": "", "done": false]])])
                    } label: {
                        Label("Aggiungi", systemImage: "plus")
                    }
                }
                Section("Tag") {
                    if !task.tags.list.isEmpty {
                        ForEach(task.tags.list, id: \.self) { t in Text(t.t) }
                            .onDelete { i in
                                var l = task.tags.list
                                l.remove(atOffsets: i)
                                Azioni.aggiorna(idTask, ["tags": .arr(l)])
                            }
                    }
                    TextField("Aggiungi tag…", text: $nuovoTag)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit(aggiungiTag)
                    let noti = tagSuggeriti
                    if !noti.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(noti, id: \.self) { s in
                                    Pillola(testo: s) {
                                        nuovoTag = s
                                        aggiungiTag()
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Promemoria") {
                    ForEach(Azioni.promemoria(task: idTask), id: \.id) { r in
                        HStack {
                            let g = Tempo.dataRoma(r.remind_at.str) ?? ""
                            Text("\(Tempo.etichetta(g)) \(Tempo.oraRoma(r.remind_at.str) ?? "")\(r.status.str == "sent" ? " ✓" : "")")
                        }
                    }
                    .onDelete { i in
                        let l = Azioni.promemoria(task: idTask)
                        for n in i { Azioni.togliPromemoria(l[n]) }
                    }
                    if sceltaPromemoria {
                        DatePicker("Alle", selection: $quandoPromemoria)
                        Button("Aggiungi promemoria") {
                            Azioni.aggiungiPromemoria(task, alle: quandoPromemoria)
                            sceltaPromemoria = false
                            Notifiche.s.chiediPermesso()
                        }
                    } else {
                        Button { sceltaPromemoria = true } label: { Label("Aggiungi", systemImage: "bell") }
                    }
                }
                Section {
                    Button { Azioni.duplica(task); chiudi() } label: { Label("Duplica", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) {
                        Azioni.elimina(task)
                        chiudi()
                    } label: { Label("Elimina", systemImage: "trash") }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { salva(); chiudi() }.fontWeight(.semibold) }
            }
            .sheet(isPresented: $sceltaQuando) { SceltaQuando(task: task) }
            .sheet(isPresented: $sceltaScadenza) { SceltaScadenza(task: task) }
            .sheet(isPresented: $sceltaProgetto) { SceltaProgetto(task: task) }
        }
        .onAppear {
            guard !caricato else { return }
            caricato = true
            titolo = task.title.t
            note = task.notes.t
            if task.rrule.vero { ripeti = Logica.s.chiama("ricorrenze.describeRrule", task.rrule).t }
        }
        .onDisappear(perform: salva)
    }

    private var etichettaQuando: String {
        if task.someday.vero { return "Un giorno" }
        guard let d = Azioni.giorno(task) else { return "Nessuna data" }
        let oggi = Tempo.oggi()
        var s = d == oggi ? (task.evening.vero ? "Questa sera" : "Oggi") : Tempo.etichetta(d)
        if let o = Azioni.ora(task) { s += " \(o)" }
        return s
    }

    private var tagSuggeriti: [String] {
        let miei = Set(task.tags.list.map(\.t))
        let tutti = Set(Azioni.tasks.flatMap { $0.tags.list.map(\.t) })
        return tutti.subtracting(miei).filter { nuovoTag.isEmpty || $0.lowercased().contains(nuovoTag.lowercased()) }.sorted().prefix(8).map { $0 }
    }

    private func aggiungiTag() {
        let t = nuovoTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !task.tags.list.contains(.str(t)) { Azioni.aggiorna(idTask, ["tags": .arr(task.tags.list + [.str(t)])]) }
        nuovoTag = ""
    }

    private func cambiaRipeti(_ v: String) {
        let t = v.trimmingCharacters(in: .whitespaces)
        guard caricato else { return }
        if t.isEmpty {
            if task.rrule.vero { Azioni.aggiorna(idTask, ["rrule": nil]) }
            return
        }
        let p = Logica.s.chiama("parser.parseTask", .str(t.hasPrefix("ogni") || t.hasPrefix("tutti") ? t : "ogni \(t)"), [:])
        if p.rrule != task.rrule { Azioni.aggiorna(idTask, ["rrule": p.rrule]) }
    }

    private func segna(_ v: J) {
        tocco()
        Azioni.aggiorna(idTask, ["checklist": .arr(task.checklist.list.map { x in
            guard x.id == v.id else { return x }
            var c = x
            c["done"] = .bool(!x.done.vero)
            return c
        })])
    }

    private func rinomina(_ v: J, _ testo: String) {
        Azioni.aggiorna(idTask, ["checklist": .arr(task.checklist.list.map { x in
            guard x.id == v.id else { return x }
            var c = x
            c["title"] = .str(testo)
            return c
        })])
    }

    private func salva() {
        guard !task.isNull else { return }
        let t = titolo.trimmingCharacters(in: .whitespacesAndNewlines)
        let n: J = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .str(note)
        if t != task.title.t || n != task.notes { Azioni.aggiorna(idTask, ["title": .str(t), "notes": n]) }
        Azioni.scartaSeVuoto(idTask)
    }
}

// MARK: - Scelte

/// «Quando», come il JumpStart: oggi, stasera, domani, un giorno, una data.
struct SceltaQuando: View {
    let task: J
    @State private var giorno = Date()
    @State private var conOra = false
    @State private var ora = Date()
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { fai(.oggi) } label: { Label("Oggi", systemImage: "star.fill").foregroundStyle(Color.primary) }
                    Button { fai(.sera) } label: { Label("Questa sera", systemImage: "moon.fill").foregroundStyle(Color.primary) }
                    Button { fai(.data(Tempo.piuGiorni(Tempo.oggi(), 1), nil)) } label: { Label("Domani", systemImage: "sunrise.fill").foregroundStyle(Color.primary) }
                    Button { fai(.unGiorno) } label: { Label("Un giorno", systemImage: "archivebox.fill").foregroundStyle(Color.primary) }
                    if !task.due_at.isNull || task.someday.vero {
                        Button(role: .destructive) { fai(.nessuno) } label: { Label("Togli la data", systemImage: "xmark.circle") }
                    }
                }
                Section {
                    DatePicker("Giorno", selection: $giorno, displayedComponents: .date).datePickerStyle(.graphical)
                    Toggle("A un'ora precisa", isOn: $conOra)
                    if conOra { DatePicker("Ora", selection: $ora, displayedComponents: .hourAndMinute) }
                    Button("Scegli questa data") {
                        fai(.data(Tempo.dataRoma(giorno), conOra ? Tempo.oraRoma(ora) : nil))
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("Quando")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } } }
        }
        .environment(\.timeZone, Tempo.roma)
        .onAppear {
            if let d = Tempo.data(task.due_at.str) {
                giorno = d
                ora = d
                conOra = task.due_has_time.vero
            }
        }
    }

    private func fai(_ q: Azioni.Quando) {
        tocco()
        Azioni.quando(task, q)
        chiudi()
    }
}

struct SceltaScadenza: View {
    let task: J
    @State private var giorno = Date()
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Scadenza", selection: $giorno, displayedComponents: .date).datePickerStyle(.graphical)
                    Button("Imposta la scadenza") {
                        Azioni.modifica(task.id.t, ["deadline": .str(Tempo.dataRoma(giorno))], "Scadenza impostata")
                        chiudi()
                    }
                    .fontWeight(.semibold)
                    if task.deadline.vero {
                        Button("Togli la scadenza", role: .destructive) {
                            Azioni.modifica(task.id.t, ["deadline": nil], "Scadenza rimossa")
                            chiudi()
                        }
                    }
                }
            }
            .navigationTitle("Scadenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } } }
        }
        .environment(\.timeZone, Tempo.roma)
        .onAppear {
            if let s = task.deadline.str { giorno = Tempo.istante(s, "12:00") }
        }
    }
}

struct SceltaProgetto: View {
    let task: J
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            List {
                ForEach(Azioni.progetti, id: \.id) { p in
                    Section {
                        Button {
                            Azioni.sposta(task, progetto: p.id.t)
                            chiudi()
                        } label: {
                            HStack {
                                IconaProgetto(progetto: p, tasks: Azioni.tasks)
                                Text(p.is_inbox.vero ? "In entrata" : p.name.t).foregroundStyle(Color.primary)
                                Spacer()
                                if task.project_id == p.id && task.heading_id.isNull { Image(systemName: "checkmark").foregroundStyle(Color.accentoLife) }
                            }
                        }
                        ForEach(Azioni.intestazioni(p.id.t).filter { $0.archived_at.isNull }, id: \.id) { h in
                            Button {
                                Azioni.sposta(task, progetto: p.id.t, intestazione: h.id.t)
                                chiudi()
                            } label: {
                                HStack {
                                    Text(h.title.t).font(.subheadline).foregroundStyle(Color.accentoLife).padding(.leading, 28)
                                    Spacer()
                                    if task.heading_id == h.id { Image(systemName: "checkmark").foregroundStyle(Color.accentoLife) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sposta in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } } }
        }
    }
}

/// L'emoji del progetto o il cerchio del suo avanzamento.
struct IconaProgetto: View {
    let progetto: J
    let tasks: [J]
    var misura: CGFloat = 20
    var body: some View {
        if progetto.is_inbox.vero {
            Image(systemName: "tray.fill").foregroundStyle(Color.accentoLife).frame(width: misura, height: misura)
        } else if let e = progetto.emoji.str, !e.isEmpty {
            Text(e).font(.system(size: misura - 2)).frame(width: misura, height: misura)
        } else {
            Anello(valore: Azioni.avanzamento(tasks, progetto.id.t), misura: misura - 2, spessore: 2.5, colore: .life(progetto.color.str))
                .frame(width: misura, height: misura)
        }
    }
}
