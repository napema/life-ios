import SwiftUI

// Il calendario: i giorni scorrono sotto il dito, la griglia è una sola, gli eventi hanno i colori di Windows.

let margineOreCalendario: CGFloat = 50

/// Il giorno guardato, lo zoom delle ore e i dati già pronti per ogni giorno.
final class StatoCalendario: ObservableObject {
    static let s = StatoCalendario()

    @Published var ancora: String?
    @Published var altezzaOra: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "calendario.altezzaOra")
        return v > 0 ? v : 60
    }() {
        didSet { UserDefaults.standard.set(altezzaOra, forKey: "calendario.altezzaOra") }
    }

    struct Giorno {
        var blocchi: [BloccoEvento] = []
        var interi: [VoceIntera] = []
        var eventi: [J] = []
        var tasks: [J] = []
        var haQualcosa: Bool { !blocchi.isEmpty || !interi.isEmpty }
    }

    private var versioneDati = -1
    private var conPromemoria = true
    private var finestra: ClosedRange<String>?
    private var perGiorno: [String: [J]] = [:]
    private var taskPerGiorno: [String: [J]] = [:]
    private var pronti: [String: Giorno] = [:]
    private(set) var colori: [String: String] = [:]

    func colore(_ e: J) -> String? { colori[e.subscription_id.t] }

    /// Tre mesi prima e dopo: il resto si carica quando ci arrivi.
    private func prepara(_ g: String) {
        let da = Tempo.piuGiorni(g, -92)
        let a = Tempo.piuGiorni(g, 92)
        let (x, _) = Tempo.intervallo(da)
        let (_, y) = Tempo.intervallo(a)
        colori = Dictionary(Azioni.sorgenti.map { ($0.id, $0.colore) }, uniquingKeysWith: { p, _ in p })
        var mappa: [String: [J]] = [:]
        for e in Azioni.eventi(da: x, a: y) {
            guard var d = Tempo.dataRoma(e.start_at.str), let f = Tempo.data(e.end_at.str) else { continue }
            let ultimo = Tempo.dataRoma(f.addingTimeInterval(-1))
            if d < da { d = da }
            var passi = 0
            while d <= ultimo, d <= a, passi < 200 {
                mappa[d, default: []].append(e)
                d = Tempo.piuGiorni(d, 1)
                passi += 1
            }
        }
        var compiti: [String: [J]] = [:]
        if Preferenze.s.promemoriaInCalendario {
            for t in Azioni.tasks where t.deleted_at.isNull {
                if let d = Azioni.giorno(t) { compiti[d, default: []].append(t) }
            }
        }
        perGiorno = mappa
        taskPerGiorno = compiti
        pronti = [:]
        finestra = da...a
    }

    func giorno(_ g: String) -> Giorno {
        if versioneDati != Archivio.s.versione || conPromemoria != Preferenze.s.promemoriaInCalendario {
            versioneDati = Archivio.s.versione
            conPromemoria = Preferenze.s.promemoriaInCalendario
            finestra = nil
        }
        if finestra?.contains(g) != true { prepara(g) }
        if let p = pronti[g] { return p }
        let eventi = perGiorno[g] ?? []
        let tasks = taskPerGiorno[g] ?? []
        let (x, y) = Tempo.intervallo(g)
        var voci: [BloccoEvento] = []
        var interi: [VoceIntera] = []
        for e in eventi {
            if e.all_day.vero {
                interi.append(VoceIntera(id: "e:\(e.id.t)", titolo: Lezione.di(e)?.titolo ?? e.summary.t, colore: colore(e), evento: e, task: nil))
            } else {
                let dentroInizio = e.start_at.t < x ? 0 : minutiCalendario(Tempo.oraRoma(e.start_at.str) ?? "00:00")
                let dentroFine = e.end_at.t >= y ? 24 * 60 : minutiCalendario(Tempo.oraRoma(e.end_at.str) ?? "23:59")
                voci.append(BloccoEvento(id: "e:\(e.id.t)", inizio: dentroInizio, fine: dentroFine, evento: e, task: nil))
            }
        }
        for t in tasks {
            if t.due_has_time.vero, let o = Azioni.ora(t) {
                let m = minutiCalendario(o)
                voci.append(BloccoEvento(id: "t:\(t.id.t)", inizio: m, fine: m + 30, evento: nil, task: t))
            } else {
                interi.append(VoceIntera(id: "t:\(t.id.t)", titolo: t.title.t, colore: nil, evento: nil, task: t))
            }
        }
        let g2 = Giorno(blocchi: disponi(voci), interi: interi, eventi: eventi, tasks: tasks)
        pronti[g] = g2
        return g2
    }
}

func minutiCalendario(_ hhmm: String) -> Int {
    let p = hhmm.split(separator: ":").map { Int($0) ?? 0 }
    return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
}

struct VoceIntera: Identifiable {
    let id: String
    let titolo: String
    let colore: String?
    let evento: J?
    let task: J?
}

struct BloccoEvento: Identifiable {
    let id: String
    let inizio: Int
    let fine: Int
    let evento: J?
    let task: J?
    var colonna = 0
    var colonne = 1
    var larghezza = 1
    /// Sotto questa durata il blocco si disegna comunque leggibile: conta anche per le sovrapposizioni.
    var fineVisiva: Int { max(fine, inizio + 25) }
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
            while gruppo[i].colonna + l < n, !gruppo.contains(where: { $0.colonna == gruppo[i].colonna + l && $0.inizio < gruppo[i].fineVisiva && $0.fineVisiva > gruppo[i].inizio }) { l += 1 }
            gruppo[i].larghezza = l
        }
        out += gruppo
        gruppo = []
    }
    for var b in ordinati {
        if b.inizio >= fineGruppo, !gruppo.isEmpty {
            chiudi()
            fineGruppo = -1
        }
        let occupate = Set(gruppo.filter { $0.fineVisiva > b.inizio }.map(\.colonna))
        var c = 0
        while occupate.contains(c) { c += 1 }
        b.colonna = c
        gruppo.append(b)
        fineGruppo = max(fineGruppo, b.fineVisiva)
    }
    if !gruppo.isEmpty { chiudi() }
    return out
}

/// I colori di un evento, con le stesse dosi di Windows: fondo pieno, testo scuro o chiaro, linea piena.
struct TintaEvento {
    let fondo: Color
    let testo: Color
    let linea: Color

    private static var memo: [String: TintaEvento] = [:]

    static func di(_ c: String?) -> TintaEvento {
        let chiave = c ?? ""
        if let t = memo[chiave] { return t }
        let base = UIColor(Color.life(c))
        let mescola: (UIColor, CGFloat, UIColor) -> UIColor = { a, q, b in
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 * q + r2 * (1 - q), green: g1 * q + g2 * (1 - q), blue: b1 * q + b2 * (1 - q), alpha: 1)
        }
        let scuroFondo = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        let chiaroInchiostro = UIColor(red: 0.063, green: 0.086, blue: 0.122, alpha: 1)
        let fondo = UIColor { $0.userInterfaceStyle == .dark ? mescola(base, 0.30, scuroFondo) : mescola(base, 0.16, .white) }
        let testo = UIColor { $0.userInterfaceStyle == .dark ? mescola(base, 0.55, .white) : mescola(base, 0.55, chiaroInchiostro) }
        let t = TintaEvento(fondo: Color(uiColor: fondo), testo: Color(uiColor: testo), linea: Color(uiColor: base))
        memo[chiave] = t
        return t
    }
}

/// Lo scorrimento orizzontale, a parte: così a ogni frame si ridisegna solo la testata.
private final class ScorrimentoCalendario: ObservableObject {
    @Published var x: CGFloat = 0
}

// MARK: - La schermata

struct VistaCalendario: View {
    /// Ogni scheda della barra ha la sua vista: quelle nascoste non seguono le altre.
    let modo: String
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var preferenze = Preferenze.s
    @ObservedObject private var stato = StatoCalendario.s
    @Namespace private var zoom
    @State private var aperto: EventoAperto?
    @State private var taskAperto: TaskAperto?
    @State private var editor: NuovoEventoBersaglio?
    @State private var visibile: String?

    var body: some View {
        let _ = archivio.versione
        Group {
            if modo == "month" {
                VistaMese(visibile: $visibile, apriEvento: { aperto = EventoAperto(evento: $0) }, apriTask: { taskAperto = TaskAperto(task: $0) })
            } else {
                GrigliaGiorni(
                    quanti: modo == "week" ? 7 : modo == "three" ? 3 : 1,
                    visibile: $visibile,
                    zoom: zoom,
                    apriEvento: { aperto = EventoAperto(evento: $0) },
                    apriTask: { taskAperto = TaskAperto(task: $0) },
                    nuovo: { editor = $0 },
                    bozza: editor
                )
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(titolo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Oggi") {
                    tocco()
                    stato.ancora = nil
                    withAnimation(.snappy) { visibile = allinea(Tempo.oggi()) }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    tocco()
                    let g = visibile ?? stato.ancora ?? Tempo.oggi()
                    editor = NuovoEventoBersaglio(giorno: g, inizio: "09:00", fine: "10:00")
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $aperto) { a in
            DettaglioEvento(evento: a.evento) { id in
                editor = NuovoEventoBersaglio(idEvento: id)
            }
            .presentationDetents([.medium, .large])
            .navigationTransition(.zoom(sourceID: a.evento.id.t, in: zoom))
        }
        .sheet(item: $taskAperto) { a in SchedaTask(idTask: a.task.id.t) }
        .sheet(item: $editor) { b in EditorEvento(bersaglio: b) }
        .onAppear { if visibile == nil { visibile = allinea(stato.ancora ?? Tempo.oggi()) } }
        .onChange(of: visibile) { _, v in
            if let v, v != stato.ancora { stato.ancora = v }
        }
        .onChange(of: stato.ancora) { _, a in
            // Un collegamento da fuori (widget, ricerca) porta a quel giorno
            guard let a, modo != "month", allinea(a) != visibile else { return }
            visibile = allinea(a)
        }
    }

    private func allinea(_ g: String) -> String {
        if modo == "week" { return Tempo.lunediDi(g) }
        return g
    }

    private var titolo: String {
        let (y, m, _) = Tempo.parti(visibile ?? stato.ancora ?? Tempo.oggi())
        return "\(Tempo.mesiLunghi[m - 1]) \(y)"
    }
}

// MARK: - La griglia

private struct GrigliaGiorni: View {
    let quanti: Int
    @Binding var visibile: String?
    let zoom: Namespace.ID
    let apriEvento: (J) -> Void
    let apriTask: (J) -> Void
    let nuovo: (NuovoEventoBersaglio) -> Void
    let bozza: NuovoEventoBersaglio?

    @ObservedObject private var stato = StatoCalendario.s
    @StateObject private var scorrimento = ScorrimentoCalendario()
    @State private var altezzaInizio: CGFloat?

    /// Una riga di giorni che comincia di lunedì: la settimana si aggancia giusta.
    private static let giorni: [String] = {
        let primo = Tempo.lunediDi(Tempo.piuGiorni(Tempo.oggi(), -7 * 60))
        return (0..<(7 * 120)).map { Tempo.piuGiorni(primo, $0) }
    }()
    private static let indice: [String: Int] = Dictionary(uniqueKeysWithValues: giorni.enumerated().map { ($1, $0) })

    var body: some View {
        GeometryReader { geo in
            let larghezzaGiorni = geo.size.width - margineOreCalendario
            let colonna = larghezzaGiorni / CGFloat(quanti)
            VStack(spacing: 0) {
                if quanti == 1 {
                    StrisciaSettimana(visibile: $visibile)
                } else {
                    TestataGiorni(giorni: Self.giorni, indice: Self.indice, colonna: colonna, quanti: quanti, visibile: $visibile, scorrimento: scorrimento)
                }
                RigaIntera(giorni: Self.giorni, indice: Self.indice, colonna: colonna, quanti: quanti, visibile: visibile, scorrimento: scorrimento, apriEvento: apriEvento, apriTask: apriTask)
                Divider()
                corpo(colonna: colonna)
            }
        }
    }

    private func corpo(colonna: CGFloat) -> some View {
        ScrollViewReader { lettore in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    ColonnaOre(altezza: stato.altezzaOra)
                    orizzontale(colonna: colonna)
                }
                .frame(height: stato.altezzaOra * 24)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        let base = altezzaInizio ?? stato.altezzaOra
                        altezzaInizio = base
                        stato.altezzaOra = min(130, max(34, base * v.magnification))
                    }
                    .onEnded { _ in altezzaInizio = nil }
            )
            .onAppear {
                let h = max(0, minutiCalendario(Tempo.oraRoma(Date())) / 60 - 1)
                lettore.scrollTo("ora\(min(h, 18))", anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func orizzontale(colonna: CGFloat) -> some View {
        let contenuto = ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.giorni, id: \.self) { g in
                    ColonnaGiorno(g: g, altezza: stato.altezzaOra, unica: quanti == 1, zoom: zoom, apriEvento: apriEvento, apriTask: apriTask, nuovo: nuovo, bozza: bozza?.giorno == g ? bozza : nil)
                        .frame(width: colonna)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibile, anchor: .leading)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }, action: { _, x in scorrimento.x = x })

        if quanti == 3 {
            contenuto.scrollTargetBehavior(.viewAligned)
        } else {
            contenuto.scrollTargetBehavior(.paging)
        }
    }
}

/// Le ore a sinistra e, sopra, l'ora di adesso.
private struct ColonnaOre: View {
    let altezza: CGFloat
    var body: some View {
        ZStack(alignment: .topTrailing) {
            TimelineView(.periodic(from: .now, by: 60)) { c in
                let adesso = minutiCalendario(Tempo.oraRoma(c.date))
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(h == 0 ? "" : String(format: "%02d:00", h))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.secondarioLife)
                            .opacity(abs(adesso - h * 60) < 16 ? 0 : 1)
                            .frame(width: margineOreCalendario - 8, height: altezza, alignment: .topTrailing)
                            .offset(y: -7)
                            .id("ora\(h)")
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { c in
                let ora = Tempo.oraRoma(c.date)
                Text(ora)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(height: 17)
                    .background(Color.rosaLife, in: Capsule())
                    .offset(x: -3, y: CGFloat(minutiCalendario(ora)) / 60 * altezza - 8.5)
            }
        }
        .frame(width: margineOreCalendario, height: altezza * 24, alignment: .topTrailing)
    }
}

/// Un giorno: le linee delle ore, gli eventi, il tocco sul vuoto, il rilascio di ciò che trascini.
private struct ColonnaGiorno: View {
    let g: String
    let altezza: CGFloat
    let unica: Bool
    let zoom: Namespace.ID
    let apriEvento: (J) -> Void
    let apriTask: (J) -> Void
    let nuovo: (NuovoEventoBersaglio) -> Void
    let bozza: NuovoEventoBersaglio?

    private var oggi: Bool { g == Tempo.oggi() }

    var body: some View {
        let dati = StatoCalendario.s.giorno(g)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                sfondo
                ForEach(dati.blocchi) { b in
                    let w = (geo.size.width - 2) / CGFloat(b.colonne)
                    let altezzaBlocco = max(22, CGFloat(b.fineVisiva - b.inizio) / 60 * altezza - 1.5)
                    bloccoVista(b, larghezza: w * CGFloat(b.larghezza) - 1.5, altezza: altezzaBlocco)
                        .offset(x: w * CGFloat(b.colonna) + 1, y: CGFloat(b.inizio) / 60 * altezza + 0.75)
                }
                if let bozza, let i = bozza.inizio, let f = bozza.fine, bozza.idEvento == nil {
                    let m = minutiCalendario(i)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentoLife.opacity(0.22))
                        .overlay(alignment: .topLeading) {
                            Text("Nuovo evento").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentoLife).padding(6)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentoLife, lineWidth: 1))
                        .frame(width: geo.size.width - 2, height: CGFloat(minutiCalendario(f) - m) / 60 * altezza)
                        .offset(x: 1, y: CGFloat(m) / 60 * altezza)
                        .allowsHitTesting(false)
                }
                if oggi { lineaAdesso(larghezza: geo.size.width) }
            }
        }
        .frame(height: altezza * 24)
        .dropDestination(for: String.self) { voci, punto in
            guard let v = voci.first else { return false }
            return rilascia(v, y: punto.y)
        }
    }

    private var sfondo: some View {
        Canvas { ctx, misura in
            var linee = Path()
            for h in 0...24 {
                let y = CGFloat(h) * altezza
                linee.move(to: CGPoint(x: 0, y: y))
                linee.addLine(to: CGPoint(x: misura.width, y: y))
            }
            ctx.stroke(linee, with: .color(Color.lineaLife.opacity(0.55)), lineWidth: 0.5)
            if !unica {
                var sinistra = Path()
                sinistra.move(to: .zero)
                sinistra.addLine(to: CGPoint(x: 0, y: misura.height))
                ctx.stroke(sinistra, with: .color(Color.lineaLife.opacity(0.55)), lineWidth: 0.5)
            }
        }
        .background(oggi && !unica ? Color.rosaLife.opacity(0.035) : Color.clear)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { v in
            tocco()
            let m = Int(v.location.y / altezza * 60) / 30 * 30
            let f = min(24 * 60 - 1, m + 60)
            nuovo(NuovoEventoBersaglio(giorno: g, inizio: String(format: "%02d:%02d", m / 60, m % 60), fine: String(format: "%02d:%02d", f / 60, f % 60)))
        })
    }

    private func lineaAdesso(larghezza: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { c in
            let y = CGFloat(minutiCalendario(Tempo.oraRoma(c.date))) / 60 * altezza
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.rosaLife).frame(width: larghezza, height: 1.5)
                Circle().fill(Color.rosaLife).frame(width: 8, height: 8)
            }
            .frame(height: 8)
            .offset(y: y - 4)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func bloccoVista(_ b: BloccoEvento, larghezza: CGFloat, altezza h: CGFloat) -> some View {
        if let e = b.evento {
            let proprio = !e.own_event_id.isNull
            let ripetuto = e.id.t.contains("@")
            let vista = BloccoEventoVista(evento: e, larghezza: larghezza, altezza: h, durata: b.fine - b.inizio)
                .frame(width: max(10, larghezza), height: h)
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    tocco()
                    apriEvento(e)
                }
                .matchedTransitionSource(id: e.id.t, in: zoom)
                .contextMenu {
                    Button { apriEvento(e) } label: { Label("Apri", systemImage: "arrow.up.left.and.arrow.down.right") }
                    if proprio, !ripetuto {
                        Button { sposta(e, minuti: 30) } label: { Label("Più tardi di 30 minuti", systemImage: "clock.arrow.circlepath") }
                        Button { sposta(e, giorni: 1) } label: { Label("A domani", systemImage: "arrow.right") }
                        Button(role: .destructive) { Azioni.eliminaEvento(e.own_event_id.t) } label: { Label("Elimina", systemImage: "trash") }
                    }
                }
            if proprio, !ripetuto {
                vista.draggable("evento:\(e.own_event_id.t)")
            } else {
                vista
            }
        } else if let t = b.task {
            BloccoTaskVista(task: t, stretto: larghezza < 70)
                .frame(width: max(10, larghezza), height: min(h, 26))
                .onTapGesture { apriTask(t) }
                .draggable("task:\(t.id.t)")
        }
    }

    private func sposta(_ e: J, minuti: Int = 0, giorni: Int = 0) {
        guard let id = e.own_event_id.str, let s = Tempo.data(e.start_at.str), let f = Tempo.data(e.end_at.str) else { return }
        let d = TimeInterval(minuti * 60 + giorni * 86400)
        Azioni.salvaEvento(id: id, valori: ["start_at": .str(Tempo.iso(s.addingTimeInterval(d))), "end_at": .str(Tempo.iso(f.addingTimeInterval(d)))], minutiPromemoria: Azioni.promemoria(evento: id).compactMap { $0.offset_minutes.int })
    }

    private func rilascia(_ v: String, y: CGFloat) -> Bool {
        let m = min(24 * 60 - 15, max(0, Int(y / altezza * 60) / 15 * 15))
        let ora = String(format: "%02d:%02d", m / 60, m % 60)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if v.hasPrefix("evento:") {
            let id = String(v.dropFirst(7))
            guard let e = Archivio.s.riga("events", id), let s = Tempo.data(e.start_at.str), let f = Tempo.data(e.end_at.str) else { return false }
            let nuovoInizio = Tempo.istante(g, ora)
            let fine = nuovoInizio.addingTimeInterval(f.timeIntervalSince(s))
            Azioni.salvaEvento(id: id, valori: ["start_at": .str(Tempo.iso(nuovoInizio)), "end_at": .str(Tempo.iso(fine))], minutiPromemoria: Azioni.promemoria(evento: id).compactMap { $0.offset_minutes.int })
            return true
        }
        if v.hasPrefix("task:") {
            let id = String(v.dropFirst(5))
            Azioni.modifica(id, ["due_at": .str(Tempo.iso(Tempo.istante(g, ora))), "due_has_time": true], "Task spostato")
            return true
        }
        return false
    }
}

/// Un evento nella griglia: il testo si adatta allo spazio, come su Windows.
private struct BloccoEventoVista: View {
    let evento: J
    let larghezza: CGFloat
    let altezza: CGFloat
    let durata: Int

    var body: some View {
        let lezione = evento.own_event_id.isNull ? Lezione.di(evento) : nil
        let tinta = TintaEvento.di(StatoCalendario.s.colore(evento))
        let titolo = lezione?.titolo ?? (evento.summary.t.isEmpty ? "(senza titolo)" : evento.summary.t)
        let inizio = Tempo.oraRoma(evento.start_at.str) ?? ""
        let fine = Tempo.oraRoma(evento.end_at.str) ?? ""
        let dove = lezione?.dove ?? evento.location.t
        let stretto = larghezza < 70
        let piccolo: CGFloat = stretto ? 10 : 11
        let passato = evento.end_at.t < Tempo.iso(Date())
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tinta.fondo)
            UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7, style: .continuous)
                .fill(tinta.linea)
                .frame(width: 3.5)
            VStack(alignment: .leading, spacing: 1) {
                if altezza < 34 {
                    HStack(spacing: 4) {
                        Text(titolo).font(.system(size: stretto ? 10.5 : 12, weight: .semibold)).lineLimit(1)
                        if larghezza > 150 { Text(inizio).font(.system(size: 11)).monospacedDigit().opacity(0.75) }
                    }
                } else {
                    let righeTitolo = max(1, min(stretto ? 4 : 3, Int((altezza - (altezza > 62 ? 30 : 8)) / 15)))
                    Text(titolo).font(.system(size: stretto ? 10 : 12.5, weight: .semibold)).lineLimit(righeTitolo).minimumScaleFactor(stretto ? 0.8 : 1)
                    if altezza > 46, !stretto { Text("\(inizio) – \(fine)").font(.system(size: piccolo)).monospacedDigit().opacity(0.8).lineLimit(1) }
                    if altezza > 62, !dove.isEmpty { Text(dove).font(.system(size: piccolo)).opacity(0.8).lineLimit(stretto ? 1 : 2) }
                }
            }
            .foregroundStyle(tinta.testo)
            .padding(.leading, stretto ? 5.5 : 8)
            .padding(.trailing, stretto ? 1 : 3)
            .padding(.top, altezza < 34 ? 3 : 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(uiColor: .systemBackground), lineWidth: 0.75))
        .opacity(passato ? 0.6 : 1)
    }
}

private struct BloccoTaskVista: View {
    let task: J
    var stretto = false
    var body: some View {
        HStack(spacing: 4) {
            if !stretto {
                Casella(task: task, lato: 15).frame(width: 18, height: 18)
            }
            Text(task.title.t).font(.system(size: stretto ? 10 : 11.5, weight: .medium)).foregroundStyle(Color.accentoLife).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentoLife.opacity(0.65), lineWidth: 1))
        .opacity(task.completed_at.isNull ? 1 : 0.5)
    }
}

// MARK: - Sopra la griglia

/// Vista giorno: la settimana in alto, che scorre, come in Calendario di Apple.
private struct StrisciaSettimana: View {
    @Binding var visibile: String?
    @State private var settimana: String?

    private static let settimane: [String] = {
        let primo = Tempo.lunediDi(Tempo.piuGiorni(Tempo.oggi(), -7 * 60))
        return (0..<120).map { Tempo.piuGiorni(primo, $0 * 7) }
    }()

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.settimane, id: \.self) { lunedi in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            cella(Tempo.piuGiorni(lunedi, i))
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $settimana)
        .frame(height: 62)
        .onAppear { settimana = Tempo.lunediDi(visibile ?? Tempo.oggi()) }
        .onChange(of: visibile) { _, v in
            guard let v else { return }
            let l = Tempo.lunediDi(v)
            if l != settimana { withAnimation(.snappy) { settimana = l } }
        }
    }

    private func cella(_ g: String) -> some View {
        let (_, _, n) = Tempo.parti(g)
        let oggi = g == Tempo.oggi()
        let scelto = g == visibile
        let dati = StatoCalendario.s.giorno(g)
        return Button {
            tocco()
            withAnimation(.snappy) { visibile = g }
        } label: {
            VStack(spacing: 3) {
                Text(Tempo.settimanaBreve[Tempo.giornoSettimana(g)].prefix(1).uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondarioLife)
                Text("\(n)")
                    .font(.system(size: 17, weight: scelto || oggi ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(scelto ? Color.white : oggi ? Color.rosaLife : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(scelto ? (oggi ? Color.rosaLife : Color.primary) : Color.clear, in: Circle())
                Circle()
                    .fill(dati.haQualcosa && !scelto ? Color.secondarioLife : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Più giorni: i numeri seguono la griglia mentre scorre.
private struct TestataGiorni: View {
    let giorni: [String]
    let indice: [String: Int]
    let colonna: CGFloat
    let quanti: Int
    @Binding var visibile: String?
    @ObservedObject var scorrimento: ScorrimentoCalendario

    var body: some View {
        let base = Int(scorrimento.x / max(1, colonna))
        let da = max(0, base - 2)
        let a = min(giorni.count - 1, base + quanti + 2)
        ZStack(alignment: .topLeading) {
            ForEach(da...a, id: \.self) { i in
                cella(giorni[i])
                    .frame(width: colonna)
                    .offset(x: CGFloat(i) * colonna - scorrimento.x)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 50)
        .clipped()
        .padding(.leading, margineOreCalendario)
    }

    private func cella(_ g: String) -> some View {
        let (_, _, n) = Tempo.parti(g)
        let oggi = g == Tempo.oggi()
        return Button {
            tocco()
            StatoCalendario.s.ancora = g
            Preferenze.s.modoCalendario = "day"
        } label: {
            VStack(spacing: 1) {
                Text(Tempo.settimanaBreve[Tempo.giornoSettimana(g)].prefix(quanti == 7 ? 1 : 3).uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(oggi ? Color.rosaLife : Color.secondarioLife)
                Text("\(n)")
                    .font(.system(size: 16, weight: oggi ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(oggi ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(oggi ? Color.rosaLife : Color.clear, in: Circle())
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Le cose di tutto il giorno, sempre in vista.
private struct RigaIntera: View {
    let giorni: [String]
    let indice: [String: Int]
    let colonna: CGFloat
    let quanti: Int
    let visibile: String?
    @ObservedObject var scorrimento: ScorrimentoCalendario
    let apriEvento: (J) -> Void
    let apriTask: (J) -> Void
    @State private var espansa = false

    var body: some View {
        let base = Int((scorrimento.x / max(1, colonna)).rounded(.down))
        let da = max(0, base - 1)
        let a = min(giorni.count - 1, base + quanti + 1)
        let dati = (da...a).map { (i: $0, voci: StatoCalendario.s.giorno(giorni[$0]).interi) }
        let massimo = dati.filter { $0.i >= base && $0.i < base + quanti }.map(\.voci.count).max() ?? 0
        let tetto = espansa ? 8 : 2
        let righe = min(massimo, tetto) + (massimo > tetto ? 1 : 0)
        if righe > 0 {
            VStack(spacing: 0) {
                Divider()
                ZStack(alignment: .topLeading) {
                    ForEach(dati, id: \.i) { d in
                        colonnaVoci(d.voci, tetto: tetto)
                            .frame(width: colonna)
                            .offset(x: CGFloat(d.i) * colonna - scorrimento.x)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: CGFloat(righe) * 25 + 4)
                .clipped()
                .padding(.leading, margineOreCalendario)
                .overlay(alignment: .topLeading) {
                    Text("tutto il\ngiorno")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.secondarioLife)
                        .multilineTextAlignment(.trailing)
                        .frame(width: margineOreCalendario - 8, alignment: .trailing)
                        .padding(.top, 5)
                }
            }
            .animation(.snappy(duration: 0.2), value: espansa)
        }
    }

    private func colonnaVoci(_ voci: [VoceIntera], tetto: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(voci.prefix(tetto)) { v in
                pillola(v)
            }
            if voci.count > tetto {
                Button {
                    tocco()
                    espansa = true
                } label: {
                    Text("+\(voci.count - tetto)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.secondarioLife).frame(height: 21)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 3)
        .padding(.horizontal, 1)
    }

    private func pillola(_ v: VoceIntera) -> some View {
        let tinta = TintaEvento.di(v.colore)
        let task = v.task
        return Button {
            tocco()
            if let e = v.evento { apriEvento(e) } else if let task { apriTask(task) }
        } label: {
            HStack(spacing: 4) {
                if let task, colonna >= 70 { Casella(task: task, lato: 14).frame(width: 17, height: 17) }
                Text(v.titolo.isEmpty ? "(senza titolo)" : v.titolo).font(.system(size: colonna < 70 ? 10 : 11.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .foregroundStyle(task != nil ? Color.accentoLife : tinta.testo)
            .background(task != nil ? Color.accentoLife.opacity(0.12) : tinta.fondo, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(task?.completed_at.isNull == false ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mese

private struct VistaMese: View {
    @Binding var visibile: String?
    let apriEvento: (J) -> Void
    let apriTask: (J) -> Void

    @State private var mese: String?
    @State private var scelto = Tempo.oggi()

    private static let mesi: [String] = {
        let (y, m, _) = Tempo.parti(Tempo.oggi())
        let primo = Tempo.piuMesi(Tempo.ymd(y, m, 1), -36)
        return (0..<72).map { Tempo.piuMesi(primo, $0) }
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "G", "V", "S", "D"][i])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(i >= 5 ? Color.terziarioLife : Color.secondarioLife)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.mesi, id: \.self) { m in
                        griglia(m).containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $mese)
            .frame(height: 6 * 58)
            Divider()
            agenda
        }
        .onAppear {
            let (y, m, _) = Tempo.parti(visibile ?? Tempo.oggi())
            mese = Tempo.ymd(y, m, 1)
            if let v = visibile { scelto = v }
        }
        .onChange(of: mese) { _, v in
            guard let v else { return }
            visibile = v
            // Sfogliando, il giorno scelto segue il mese
            let (y, m, _) = Tempo.parti(v)
            let (ys, ms, _) = Tempo.parti(Tempo.oggi())
            scelto = y == ys && m == ms ? Tempo.oggi() : v
        }
    }

    private func griglia(_ primo: String) -> some View {
        let (_, m, _) = Tempo.parti(primo)
        let inizio = Tempo.lunediDi(primo)
        return VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        cella(Tempo.piuGiorni(inizio, r * 7 + c), mese: m)
                    }
                }
                .frame(height: 58)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.lineaLife.opacity(0.35)).frame(height: 0.5) }
            }
        }
    }

    private func cella(_ g: String, mese m: Int) -> some View {
        let (_, mg, n) = Tempo.parti(g)
        let oggi = g == Tempo.oggi()
        let selezionato = g == scelto
        let d = StatoCalendario.s.giorno(g)
        let voci = vociChip(d)
        return Button {
            tocco()
            withAnimation(.snappy(duration: 0.2)) { scelto = g }
        } label: {
            VStack(spacing: 1) {
                Text("\(n)")
                    .font(.system(size: 13, weight: oggi || selezionato ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(oggi ? Color.white : selezionato ? Color.primary : mg == m ? Color.primary : Color.terziarioLife)
                    .frame(width: 22, height: 22)
                    .background(oggi ? Color.rosaLife : selezionato ? Color(uiColor: .tertiarySystemFill) : Color.clear, in: Circle())
                ForEach(0..<min(2, voci.count), id: \.self) { i in
                    chip(voci[i].titolo, voci[i].colore, task: voci[i].task, attenuato: mg != m)
                }
                if voci.count > 2 {
                    Text("+\(voci.count - 2)").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.secondarioLife).frame(height: 8)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct VoceChip {
        let titolo: String
        let colore: String?
        let task: Bool
    }

    private func vociChip(_ d: StatoCalendario.Giorno) -> [VoceChip] {
        var out: [VoceChip] = d.interi.map { VoceChip(titolo: $0.titolo, colore: $0.colore, task: $0.task != nil) }
        for b in d.blocchi {
            if let e = b.evento {
                out.append(VoceChip(titolo: Lezione.di(e)?.materia ?? e.summary.t, colore: StatoCalendario.s.colore(e), task: false))
            } else if let t = b.task {
                out.append(VoceChip(titolo: t.title.t, colore: nil, task: true))
            }
        }
        return out
    }

    private func chip(_ t: String, _ c: String?, task: Bool, attenuato: Bool) -> some View {
        let tinta = TintaEvento.di(c)
        return Text(t)
            .font(.system(size: 8.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 11)
            .foregroundStyle(task ? Color.accentoLife : tinta.testo)
            .background(task ? Color.accentoLife.opacity(0.12) : tinta.fondo, in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .opacity(attenuato ? 0.45 : 1)
    }

    private var agenda: some View {
        let d = StatoCalendario.s.giorno(scelto)
        return List {
            Section {
                if d.eventi.isEmpty && d.tasks.isEmpty {
                    Text("Niente in questo giorno").foregroundStyle(Color.secondarioLife)
                }
                ForEach(d.eventi, id: \.self) { e in
                    Button { apriEvento(e) } label: { rigaEvento(e) }.buttonStyle(.plain)
                }
                ForEach(d.tasks, id: \.id) { t in
                    Button { apriTask(t) } label: {
                        HStack(spacing: 10) {
                            Casella(task: t, lato: 18)
                            Text(t.title.t).font(.subheadline).lineLimit(1)
                            Spacer()
                            if let o = Azioni.ora(t) { Text(o).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(Tempo.etichetta(scelto).maiuscola)
            }
        }
        .listStyle(.plain)
    }

    private func rigaEvento(_ e: J) -> some View {
        let l = e.own_event_id.isNull ? Lezione.di(e) : nil
        let tinta = TintaEvento.di(StatoCalendario.s.colore(e))
        return HStack(spacing: 10) {
            Capsule().fill(tinta.linea).frame(width: 3.5, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(l?.titolo ?? (e.summary.t.isEmpty ? "(senza titolo)" : e.summary.t)).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(e.all_day.vero ? "Tutto il giorno" : "\(Tempo.oraRoma(e.start_at.str) ?? "") – \(Tempo.oraRoma(e.end_at.str) ?? "")").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
