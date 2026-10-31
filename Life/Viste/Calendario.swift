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

private let altezzaOra: CGFloat = 56
private let margineOre: CGFloat = 46

struct BloccoEvento: Identifiable {
    let id: String
    let inizio: Int
    let fine: Int
    let evento: J
    var colonna = 0
    var colonne = 1
    var larghezza = 1
}

/// Colonne per gli eventi sovrapposti; ogni evento si allarga nelle colonne libere alla sua destra.
private func disponi(_ voci: [BloccoEvento]) -> [BloccoEvento] {
    let ordinati = voci.sorted { $0.inizio == $1.inizio ? $0.fine > $1.fine : $0.inizio < $1.inizio }
    var out: [BloccoEvento] = []
    var gruppo: [BloccoEvento] = []
    var fineGruppo = -1
    func chiudi() {
        let n = max(1, (gruppo.map(\.colonna).max() ?? 0) + 1)
        for i in gruppo.indices {
            gruppo[i].colonne = n
            var l = 1
            while gruppo[i].colonna + l < n, !gruppo.contains(where: { $0.colonna == gruppo[i].colonna + l && $0.inizio < gruppo[i].fine && $0.fine > gruppo[i].inizio }) { l += 1 }
            gruppo[i].larghezza = l
        }
        out += gruppo
        gruppo = []
    }
    for var b in ordinati {
        if b.inizio >= fineGruppo, !gruppo.isEmpty { chiudi() }
        let occupate = Set(gruppo.filter { $0.fine > b.inizio }.map(\.colonna))
        var c = 0
        while occupate.contains(c) { c += 1 }
        b.colonna = c
        gruppo.append(b)
        fineGruppo = max(fineGruppo, b.fine)
    }
    if !gruppo.isEmpty { chiudi() }
    return out
}

private func minuti(_ hhmm: String) -> Int {
    let p = hhmm.split(separator: ":").map { Int($0) ?? 0 }
    return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
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

struct VistaCalendario: View {
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var preferenze = Preferenze.s
    @State private var ancora: String?
    @State private var aperto: EventoAperto?
    @State private var taskAperto: TaskAperto?
    @State private var editor: NuovoEventoBersaglio?
    @State private var scorrimento: CGFloat = 0
    @State private var adesso = Date()

    private var modo: String { preferenze.modoCalendario }
    private var quanti: Int { modo == "week" ? 7 : modo == "three" ? 3 : 1 }
    private var inizio: String {
        let o = ancora ?? Tempo.oggi()
        return modo == "week" ? Tempo.lunediDi(o) : o
    }

    var body: some View {
        let _ = archivio.versione
        VStack(spacing: 0) {
            Picker("Vista", selection: $preferenze.modoCalendario) {
                Text("Giorno").tag("day")
                Text("3 giorni").tag("three")
                Text("Settimana").tag("week")
                Text("Mese").tag("month")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if modo == "month" {
                mese
            } else {
                griglia
            }
        }
        .navigationTitle(titolo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Oggi") { withAnimation { ancora = nil } }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { vai(-1) } label: { Image(systemName: "chevron.left") }
                Button { vai(1) } label: { Image(systemName: "chevron.right") }
                Button {
                    editor = NuovoEventoBersaglio(giorno: inizio, inizio: "09:00", fine: "10:00")
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $aperto) { a in
            DettaglioEvento(evento: a.evento) { id in
                editor = NuovoEventoBersaglio(idEvento: id)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $taskAperto) { a in SchedaTask(idTask: a.task.id.t) }
        .sheet(item: $editor) { b in EditorEvento(bersaglio: b) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { adesso = $0 }
    }

    private func vai(_ d: Int) {
        tocco()
        withAnimation(.snappy(duration: 0.25)) {
            ancora = modo == "month" ? Tempo.piuMesi(ancora ?? Tempo.oggi(), d) : Tempo.piuGiorni(inizio, d * quanti)
        }
    }

    private var titolo: String {
        let o = modo == "month" ? (ancora ?? Tempo.oggi()) : inizio
        let (y, m, d) = Tempo.parti(o)
        if modo == "month" { return "\(Tempo.mesiLunghi[m - 1]) \(y)" }
        if modo == "day" { return "\(Tempo.settimanaBreve[Tempo.giornoSettimana(o)].maiuscola) \(d) \(Tempo.mesiBrevi[m - 1])" }
        return "\(Tempo.mesiLunghi[m - 1]) \(y)"
    }

    private var tasksVisibili: [J] {
        preferenze.promemoriaInCalendario ? Azioni.tasks.filter { $0.deleted_at.isNull } : []
    }

    private func coloreSorgente(_ e: J) -> String? { Azioni.sorgenti.first { $0.id == e.subscription_id.t }?.colore }

    // MARK: Griglia

    private var griglia: some View {
        let giorni = (0..<quanti).map { Tempo.piuGiorni(inizio, $0) }
        let (da, _) = Tempo.intervallo(giorni[0])
        let (_, a) = Tempo.intervallo(giorni[giorni.count - 1])
        let eventi = Azioni.eventi(da: da, a: a)
        let tasks = tasksVisibili
        return VStack(spacing: 0) {
            // Le date
            HStack(spacing: 0) {
                Color.clear.frame(width: margineOre, height: 1)
                ForEach(giorni, id: \.self) { g in
                    let (_, _, n) = Tempo.parti(g)
                    let oggi = g == Tempo.oggi()
                    VStack(spacing: 1) {
                        Text(Tempo.settimanaBreve[Tempo.giornoSettimana(g)].maiuscola).font(.caption2).foregroundStyle(Color.secondarioLife)
                        Text("\(n)")
                            .font(.subheadline.weight(oggi ? .bold : .regular))
                            .foregroundStyle(oggi ? Color.white : Color.primary)
                            .frame(width: 28, height: 28)
                            .background(oggi ? Color.rosaLife : Color.clear, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        ancora = g
                        preferenze.modoCalendario = "day"
                    }
                }
            }
            .padding(.bottom, 4)
            // Tutto il giorno
            let interi = giorni.map { g -> [AnyHashable] in
                let (x, y) = Tempo.intervallo(g)
                let ev: [AnyHashable] = eventi.filter { $0.all_day.vero && $0.start_at.t < y && $0.end_at.t > x }
                let t: [AnyHashable] = tasks.filter { Azioni.giorno($0) == g && !$0.due_has_time.vero }
                return ev + t
            }
            if interi.contains(where: { !$0.isEmpty }) {
                ScrollView {
                    HStack(alignment: .top, spacing: 2) {
                        Text("tutto").font(.caption2).foregroundStyle(Color.terziarioLife).frame(width: margineOre - 2)
                        ForEach(giorni.indices, id: \.self) { i in
                            VStack(spacing: 2) {
                                ForEach(Array(interi[i].enumerated()), id: \.offset) { _, v in
                                    if let j = v.base as? J { pillolaIntera(j) }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: 92)
                .padding(.bottom, 4)
            }
            Divider()
            ScrollViewReader { lettore in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        righeOre
                        HStack(spacing: 0) {
                            Color.clear.frame(width: margineOre)
                            ForEach(giorni, id: \.self) { g in
                                colonna(g, eventi: eventi, tasks: tasks)
                                    .frame(maxWidth: .infinity)
                                    .overlay(alignment: .leading) { Rectangle().fill(Color.lineaLife.opacity(0.5)).frame(width: 0.5) }
                            }
                        }
                        lineaAdesso(giorni)
                    }
                    .frame(height: altezzaOra * 24)
                }
                .onAppear {
                    let h = max(0, Int(minuti(Tempo.oraRoma(adesso))) / 60 - 2)
                    lettore.scrollTo("ora\(min(h, 16))", anchor: .top)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { v in
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.5, abs(v.translation.width) > 50 else { return }
                        vai(v.translation.width < 0 ? 1 : -1)
                    }
            )
        }
    }

    private var righeOre: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 4) {
                    Text(h == 0 ? "" : String(format: "%02d:00", h))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.terziarioLife)
                        .frame(width: margineOre - 6, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle().fill(Color.lineaLife.opacity(0.5)).frame(height: 0.5)
                }
                .frame(height: altezzaOra, alignment: .top)
                .id("ora\(h)")
            }
        }
    }

    @ViewBuilder
    private func lineaAdesso(_ giorni: [String]) -> some View {
        let oggi = Tempo.oggi()
        if let i = giorni.firstIndex(of: oggi) {
            let y = CGFloat(minuti(Tempo.oraRoma(adesso))) / 60 * altezzaOra
            GeometryReader { g in
                let w = (g.size.width - margineOre) / CGFloat(giorni.count)
                let x = margineOre + w * CGFloat(i)
                Rectangle().fill(Color.rosaLife).frame(width: w, height: 1.5).offset(x: x, y: y)
                Circle().fill(Color.rosaLife).frame(width: 8, height: 8).offset(x: x - 4, y: y - 3.25)
            }
            .allowsHitTesting(false)
        }
    }

    private func colonna(_ g: String, eventi: [J], tasks: [J]) -> some View {
        let (x, y) = Tempo.intervallo(g)
        let del = eventi.filter { !$0.all_day.vero && $0.start_at.t < y && $0.end_at.t > x }
        let blocchi = disponi(del.map { e in
            let dentroInizio = e.start_at.t < x ? 0 : minuti(Tempo.oraRoma(e.start_at.str) ?? "00:00")
            let dentroFine = e.end_at.t >= y ? 24 * 60 : minuti(Tempo.oraRoma(e.end_at.str) ?? "23:59")
            return BloccoEvento(id: e.id.t, inizio: dentroInizio, fine: max(dentroInizio + 15, dentroFine), evento: e)
        })
        let conOra = tasks.filter { Azioni.giorno($0) == g && $0.due_has_time.vero }
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Toccare il vuoto crea un evento a quell'ora
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        let m = Int(v.location.y / altezzaOra * 60) / 30 * 30
                        let f = min(24 * 60 - 1, m + 60)
                        editor = NuovoEventoBersaglio(giorno: g, inizio: String(format: "%02d:%02d", m / 60, m % 60), fine: String(format: "%02d:%02d", f / 60, f % 60))
                    })
                ForEach(blocchi) { b in
                    let w = geo.size.width / CGFloat(b.colonne)
                    bloccoEvento(b)
                        .frame(width: max(10, w * CGFloat(b.larghezza) - 2), height: max(20, CGFloat(b.fine - b.inizio) / 60 * altezzaOra - 2))
                        .offset(x: w * CGFloat(b.colonna) + 1, y: CGFloat(b.inizio) / 60 * altezzaOra + 1)
                }
                ForEach(conOra, id: \.id) { t in
                    pillolaTask(t)
                        .frame(width: geo.size.width - 2, height: 22)
                        .offset(x: 1, y: CGFloat(minuti(Azioni.ora(t) ?? "00:00")) / 60 * altezzaOra + 1)
                }
            }
        }
    }

    private func bloccoEvento(_ b: BloccoEvento) -> some View {
        let e = b.evento
        let l = e.own_event_id.isNull ? Lezione(e) : nil
        let c = Color.life(coloreSorgente(e))
        let passato = e.end_at.t < Tempo.iso(adesso)
        return Button { aperto = EventoAperto(evento: e) } label: {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l?.titolo ?? (e.summary.t.isEmpty ? "(senza titolo)" : e.summary.t))
                        .font(.caption.weight(.semibold))
                        .lineLimit(b.fine - b.inizio < 45 ? 1 : 3)
                    if b.fine - b.inizio >= 45 {
                        Text("\(Tempo.oraRoma(e.start_at.str) ?? "") – \(Tempo.oraRoma(e.end_at.str) ?? "")").font(.caption2).lineLimit(1)
                        if let d = l?.dove, !d.isEmpty {
                            Text(d).font(.caption2).lineLimit(2)
                        } else if e.location.vero {
                            Text(e.location.t).font(.caption2).lineLimit(1)
                        }
                    }
                }
                .foregroundStyle(c)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(passato ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    private func pillolaTask(_ t: J) -> some View {
        Button { taskAperto = TaskAperto(task: t) } label: {
            HStack(spacing: 4) {
                Image(systemName: t.completed_at.isNull ? "square" : "checkmark.square.fill").font(.caption2)
                Text(t.title.t).font(.caption2.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .foregroundStyle(Color.accentoLife)
            .background(.background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.accentoLife.opacity(0.6)))
            .opacity(t.completed_at.isNull ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private func pillolaIntera(_ v: J) -> some View {
        let evento = v.title.isNull
        let c: Color = evento ? .life(coloreSorgente(v)) : .accentoLife
        return Button {
            if evento {
                aperto = EventoAperto(evento: v)
            } else {
                taskAperto = TaskAperto(task: v)
            }
        } label: {
            Text(evento ? v.summary.t : v.title.t)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(height: 20)
                .foregroundStyle(c)
                .background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .opacity(!evento && !v.completed_at.isNull ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Mese

    @State private var giornoMese: String?

    private var mese: some View {
        let base = ancora ?? Tempo.oggi()
        let (y, m, _) = Tempo.parti(base)
        let primo = Tempo.lunediDi(Tempo.ymd(y, m, 1))
        let giorni = (0..<42).map { Tempo.piuGiorni(primo, $0) }
        let eventi = Azioni.eventi(da: Tempo.intervallo(giorni[0]).0, a: Tempo.intervallo(giorni[41]).1)
        let tasks = tasksVisibili
        let scelto = giornoMese ?? (Tempo.parti(Tempo.oggi()).1 == m ? Tempo.oggi() : Tempo.ymd(y, m, 1))
        let (sx, sy) = Tempo.intervallo(scelto)
        return ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { i in
                        Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(giorni, id: \.self) { g in
                        let (dx, dy) = Tempo.intervallo(g)
                        let delGiorno = eventi.filter { $0.start_at.t < dy && $0.end_at.t > dx }
                        let suoi = tasks.filter { Azioni.giorno($0) == g && $0.completed_at.isNull }
                        cellaMese(g, mese: m, eventi: delGiorno, tasks: suoi, scelto: g == scelto)
                    }
                }
                Divider()
                let delScelto = eventi.filter { $0.start_at.t < sy && $0.end_at.t > sx }
                let taskScelti = tasks.filter { Azioni.giorno($0) == scelto }
                Text(Tempo.etichetta(scelto).maiuscola).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                if delScelto.isEmpty && taskScelti.isEmpty {
                    Text("Niente in questo giorno").font(.subheadline).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(delScelto, id: \.self) { e in
                    Button { aperto = EventoAperto(evento: e) } label: { rigaEventoGiorno(e) }.buttonStyle(.plain)
                }
                ForEach(taskScelti, id: \.id) { t in
                    Button { taskAperto = TaskAperto(task: t) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: t.completed_at.isNull ? "square" : "checkmark.square.fill").foregroundStyle(Color.accentoLife)
                            Text(t.title.t).font(.subheadline).lineLimit(1)
                            Spacer()
                            if let o = Azioni.ora(t) { Text(o).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 30)
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                giornoMese = nil
                vai(v.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private func rigaEventoGiorno(_ e: J) -> some View {
        let l = e.own_event_id.isNull ? Lezione(e) : nil
        return HStack(spacing: 10) {
            Capsule().fill(Color.life(coloreSorgente(e))).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(l?.titolo ?? (e.summary.t.isEmpty ? "(senza titolo)" : e.summary.t)).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(e.all_day.vero ? "Tutto il giorno" : "\(Tempo.oraRoma(e.start_at.str) ?? "") – \(Tempo.oraRoma(e.end_at.str) ?? "")").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func cellaMese(_ g: String, mese m: Int, eventi: [J], tasks: [J], scelto: Bool) -> some View {
        let (_, mg, n) = Tempo.parti(g)
        let oggi = g == Tempo.oggi()
        let colori = eventi.prefix(3).map { Color.life(coloreSorgente($0)) } + (tasks.isEmpty ? [] : [Color.accentoLife])
        return Button {
            tocco()
            giornoMese = g
        } label: {
            VStack(spacing: 3) {
                Text("\(n)")
                    .font(.subheadline.weight(oggi ? .bold : .regular))
                    .foregroundStyle(oggi ? Color.white : mg == m ? Color.primary : Color.terziarioLife)
                    .frame(width: 30, height: 30)
                    .background(oggi ? Color.rosaLife : scelto ? Color(uiColor: .tertiarySystemFill) : .clear, in: Circle())
                HStack(spacing: 2) {
                    ForEach(colori.indices.prefix(4), id: \.self) { i in
                        Circle().fill(colori[i]).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dettaglio

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
