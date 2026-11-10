import SwiftUI

// Il calendario: i giorni scorrono sotto il dito, la griglia è una sola, gli eventi hanno i colori di Windows.

let margineOreCalendario: CGFloat = 50

extension Color {
    /// Un rosso solo in tutto il Calendario: lo stesso dell'app, dei pulsanti e della barra.
    static let rossoCalendario = Color(hex: Modulo.calendario.colore)
}

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
        let baseScura = UIColor(red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255, alpha: 1)
        let inchiostro = UIColor(red: 0x10 / 255, green: 0x16 / 255, blue: 0x1F / 255, alpha: 1)
        let fondo = UIColor { $0.userInterfaceStyle == .dark ? mescola(base, 0.26, baseScura) : mescola(base, 0.16, .white) }
        let testo = UIColor { $0.userInterfaceStyle == .dark ? mescola(base, 0.62, .white) : mescola(base, 0.50, inchiostro) }
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
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["LIFE_DEMO"] != nil, preferenze.modoCalendario == modo {
                Color.clear.frame(width: 2, height: 2)
                    .accessibilityElement()
                    .accessibilityIdentifier("calendario.visibile")
                    .accessibilityLabel(visibile ?? "")
                EtichettaBlocchi()
            }
        }
        .overlay(alignment: .bottom) {
            if modo != "month", preferenze.modoCalendario == modo {
                BarraBloccoScelto { aperto = EventoAperto(evento: $0) }
            }
        }
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
            // Solo la scheda aperta decide il giorno: quelle nascoste la seguono e basta
            if let v, preferenze.modoCalendario == modo, v != stato.ancora { stato.ancora = v }
        }
        .onChange(of: stato.ancora) { _, a in
            // Un collegamento da fuori (widget, ricerca) porta a quel giorno
            guard let a, modo != "month", allinea(a) != visibile.map(allinea) else { return }
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
                .background(AgganciaDito(giorni: Self.giorni, colonna: colonna, quanti: quanti, scorrimento: scorrimento, visibile: $visibile))
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
                    .background(Color.rossoCalendario, in: Capsule())
                    .offset(x: -3, y: CGFloat(minutiCalendario(ora)) / 60 * altezza - 8.5)
            }
            OraPresa(altezza: altezza)
        }
        .frame(width: margineOreCalendario, height: altezza * 24, alignment: .topTrailing)
    }
}

/// Un giorno: le linee delle ore, gli eventi, il tocco sul vuoto.
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
                StratoPresa(g: g, altezza: altezza, larghezza: geo.size.width)
            }
        }
        .frame(height: altezza * 24)
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
        .background(oggi && !unica ? Color.rossoCalendario.opacity(0.035) : Color.clear)
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
                Rectangle().fill(Color.rossoCalendario).frame(width: larghezza, height: 1.5)
                Circle().fill(Color.rossoCalendario).frame(width: 8, height: 8)
            }
            .frame(height: 8)
            .offset(y: y - 4)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func bloccoVista(_ b: BloccoEvento, larghezza: CGFloat, altezza h: CGFloat) -> some View {
        if let e = b.evento {
            SeNonPreso(id: b.id) {
                BloccoEventoVista(evento: e, larghezza: larghezza, altezza: h, durata: b.fine - b.inizio, colonna: b.colonna)
                    .frame(width: max(10, larghezza), height: h)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tocco()
                        apriEvento(e)
                    }
                    // Tenendo premuto: chi si sposta col dito ha la barra delle azioni (BarraBloccoScelto),
                    // gli altri (lezioni, calendari esterni, ricorrenti) il menu di sistema
                    .menuEvento(e, se: !eventoSpostabile(e)) { apriEvento(e) }
                    .matchedTransitionSource(id: e.id.t, in: zoom)
            }
        } else if let t = b.task {
            SeNonPreso(id: b.id) {
                BloccoTaskVista(task: t, stretto: larghezza < 70)
                    .frame(width: max(10, larghezza), height: min(h, 26))
                    .onTapGesture { apriTask(t) }
            }
        }
    }
}

/// Si può spostare col dito: un evento tuo, non ricorrente, dentro una sola giornata.
private func eventoSpostabile(_ e: J) -> Bool {
    guard !e.own_event_id.isNull, !e.id.t.contains("@"), !e.all_day.vero, let f = Tempo.data(e.end_at.str) else { return false }
    return Tempo.dataRoma(e.start_at.str) == Tempo.dataRoma(f.addingTimeInterval(-1))
}

private extension View {
    @ViewBuilder
    func menuEvento(_ e: J, se attivo: Bool, apri: @escaping () -> Void) -> some View {
        if attivo { contextMenu { MenuEvento(e: e, apri: apri) } } else { self }
    }
}

/// Con un blocco selezionato (tieni premuto e lascia): le sue azioni, in una barra di vetro in basso.
private struct BarraBloccoScelto: View {
    let apri: (J) -> Void
    @ObservedObject private var t = Trascinamento.s

    var body: some View {
        if t.selezionata, let e = t.presa?.evento, let id = e.own_event_id.str {
            HStack(spacing: 2) {
                voce("Apri", "arrow.up.forward.square") { apri(e) }
                voce("Duplica", "plus.square.on.square") { Azioni.duplicaEvento(id) }
                voce("+1 giorno", "sunrise") { Azioni.spostaEvento(id, giorni: 1) }
                voce("Elimina", "trash", rosso: true) { Azioni.eliminaEvento(id) }
                voce("Fine", "xmark") {}
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.bottom, 10)
            .accessibilityIdentifier("calendario.azioni")
        }
    }

    private func voce(_ titolo: String, _ icona: String, rosso: Bool = false, _ fai: @escaping () -> Void) -> some View {
        Button {
            tocco()
            ControlloreDito.ultimo?.lascia()
            fai()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icona).font(.system(size: 17, weight: .medium))
                Text(titolo).font(.caption2)
            }
            .frame(width: 60, height: 44)
            .foregroundStyle(rosso ? Color.pericoloLife : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Spostare con il dito

/// Il blocco preso: tieni premuto e trascina per spostarlo (anche su un altro giorno); tieni premuto e
/// lascia per tirarne i bordi. Si muove di 5 minuti, di 1 con le ore ingrandite.
private final class Trascinamento: ObservableObject {
    static let s = Trascinamento()

    struct Presa: Equatable {
        let id: String
        let evento: J?
        let task: J?
        let giornoOrigine: String
        let inizioOrigine: Int
        let fineOrigine: Int
        var giorno: String
        var inizio: Int
        var fine: Int
        var cambiata: Bool { giorno != giornoOrigine || inizio != inizioOrigine || fine != fineOrigine }
    }

    @Published var presa: Presa?
    @Published var selezionata = false
}

/// A parte, così i blocchi fermi non si ridisegnano a ogni passo del dito.
private final class BloccoPreso: ObservableObject {
    static let s = BloccoPreso()
    @Published var id: String?
}

/// Solo per le prove automatiche: dice dove sono i blocchi sullo schermo.
private struct EtichettaBlocchi: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Color.clear.frame(width: 2, height: 2).accessibilityElement().accessibilityIdentifier("calendario.blocchi").accessibilityLabel(ControlloreDito.ultimo?.blocchiSulloSchermo() ?? "")
        }
    }
}

private func oraCalendario(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

private struct SeNonPreso<Contenuto: View>: View {
    let id: String
    @ViewBuilder var contenuto: () -> Contenuto
    @ObservedObject private var preso = BloccoPreso.s
    var body: some View { contenuto().opacity(preso.id == id ? 0.3 : 1) }
}

/// Il blocco che segue il dito, nel giorno e all'ora in cui cadrebbe.
private struct StratoPresa: View {
    let g: String
    let altezza: CGFloat
    let larghezza: CGFloat
    @ObservedObject private var t = Trascinamento.s

    var body: some View {
        if let p = t.presa, p.giorno == g {
            let w = larghezza - 2
            let h = max(22, CGFloat(p.fine - p.inizio) / 60 * altezza - 1.5)
            Group {
                if let e = p.evento.map({ conOrari($0, p) }) {
                    BloccoEventoVista(evento: e, larghezza: w, altezza: h, durata: p.fine - p.inizio, sollevato: true)
                        .frame(width: w, height: h)
                        .overlay(alignment: .topLeading) { if t.selezionata { bordo(e, "calendario.bordo.inizio").offset(x: 14, y: -5) } }
                        .overlay(alignment: .bottomTrailing) { if t.selezionata { bordo(e, "calendario.bordo.fine").offset(x: -14, y: 5) } }
                } else if let task = p.task {
                    BloccoTaskVista(task: task, stretto: w < 70).frame(width: w, height: 26)
                }
            }
            .scaleEffect(t.selezionata ? 1 : 1.02)
            .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
            .offset(x: 1, y: CGFloat(p.inizio) / 60 * altezza + 0.75)
            .animation(.interactiveSpring(duration: 0.12), value: p.inizio)
            .allowsHitTesting(false)
        }
    }

    /// L'evento con l'ora a cui cadrebbe: il blocco la scrive mentre si muove.
    private func conOrari(_ evento: J, _ p: Trascinamento.Presa) -> J {
        let inizio = Tempo.istante(g, oraCalendario(p.inizio))
        var e = evento
        e["start_at"] = .str(Tempo.iso(inizio))
        e["end_at"] = .str(Tempo.iso(inizio.addingTimeInterval(Double(p.fine - p.inizio) * 60)))
        return e
    }

    private func bordo(_ e: J, _ id: String) -> some View {
        Circle()
            .fill(Color(uiColor: .systemBackground))
            .overlay(Circle().strokeBorder(TintaEvento.di(StatoCalendario.s.colore(e)).linea, lineWidth: 2))
            .frame(width: 11, height: 11)
            .accessibilityElement()
            .accessibilityIdentifier(id)
    }
}

/// L'ora a cui cadrà, nella colonna delle ore.
private struct OraPresa: View {
    let altezza: CGFloat
    @ObservedObject private var t = Trascinamento.s

    var body: some View {
        if let p = t.presa {
            let tinta = TintaEvento.di(p.evento.flatMap { StatoCalendario.s.colore($0) })
            let tiraLaFine = p.inizio == p.inizioOrigine && p.fine != p.fineOrigine
            let m = tiraLaFine ? p.fine : p.inizio
            Text(oraCalendario(m == 24 * 60 ? 0 : m))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(height: 17)
                .background(p.evento == nil ? Color.accentoLife : tinta.linea, in: Capsule())
                .offset(x: -3, y: CGFloat(m) / 60 * altezza - 8.5)
        }
    }
}

/// Il gesto vive sulla ScrollView delle ore: resta vivo anche quando i giorni scorrono sotto il dito,
/// e se sotto non c'è niente da prendere la ScrollView scorre come sempre.
private struct AgganciaDito: UIViewRepresentable {
    let giorni: [String]
    let colonna: CGFloat
    let quanti: Int
    let scorrimento: ScorrimentoCalendario
    @Binding var visibile: String?

    func makeUIView(context: Context) -> SondaDito { SondaDito() }

    func updateUIView(_ v: SondaDito, context: Context) {
        let dito = v.dito
        dito.giorni = giorni
        dito.colonna = colonna
        dito.quanti = quanti
        dito.scorrimentoX = { [scorrimento] in scorrimento.x }
        let visibile = $visibile
        dito.vai = { g in withAnimation(.snappy) { visibile.wrappedValue = g } }
    }
}

private final class SondaDito: UIView {
    let dito = ControlloreDito()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            dito.lascia()
            return
        }
        var v = superview
        while let c = v {
            if let s = c as? UIScrollView {
                dito.aggancia(s, superficie: self)
                return
            }
            v = c.superview
        }
    }
}

private final class ControlloreDito: NSObject, UIGestureRecognizerDelegate {
    enum Gesto { case sposta, inizio, fine }

    var giorni: [String] = []
    var colonna: CGFloat = 1
    var quanti = 1
    var scorrimentoX: () -> CGFloat = { 0 }
    var vai: (String) -> Void = { _ in }

    private weak var scroll: UIScrollView?
    private weak var interno: UIScrollView?
    /// La griglia stessa: le sue coordinate sono ore e colonne, comunque scorra.
    private weak var superficie: UIView?
    /// Tieni premuto su un blocco per prenderlo.
    private let lunga = UILongPressGestureRecognizer()
    /// Con un blocco selezionato, ogni tocco è per lui: i bordi, lo spostamento, o lasciarlo.
    private let subito = UILongPressGestureRecognizer()
    private weak var attivo: UIGestureRecognizer?
    private var gesto = Gesto.sposta
    private var appiglio = 0.0
    private var partenza = CGPoint.zero
    private var mosso = false
    private var mia = false
    private var collegamento: CADisplayLink?
    private var alBordoDa: CFTimeInterval?
    private let passi = UISelectionFeedbackGenerator()

    private var stato: Trascinamento { .s }
    private var altezza: CGFloat { StatoCalendario.s.altezzaOra }

    override init() {
        super.init()
        lunga.minimumPressDuration = 0.28
        lunga.allowableMovement = 10
        lunga.delegate = self
        lunga.addTarget(self, action: #selector(gestoLungo(_:)))
        subito.minimumPressDuration = 0
        subito.allowableMovement = .greatestFiniteMagnitude
        subito.isEnabled = false
        subito.addTarget(self, action: #selector(gestoSubito(_:)))
    }

    func aggancia(_ s: UIScrollView, superficie: UIView) {
        ControlloreDito.ultimo = self
        self.superficie = superficie
        guard scroll !== s else { return }
        scroll = s
        s.addGestureRecognizer(lunga)
        s.addGestureRecognizer(subito)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive tocco: UITouch) -> Bool {
        guard let superficie, stato.presa == nil else { return false }
        return bloccoSotto(tocco.location(in: superficie)) != nil
    }

    // MARK: Cosa c'è sotto il dito

    private func indiceColonna(_ x: CGFloat) -> Int {
        Int(((x - margineOreCalendario + scorrimentoX()) / max(1, colonna)).rounded(.down))
    }

    private func spostabile(_ b: BloccoEvento) -> Bool {
        if b.task != nil { return true }
        guard let e = b.evento, !e.own_event_id.isNull, !e.id.t.contains("@"), !e.all_day.vero, let f = Tempo.data(e.end_at.str) else { return false }
        return Tempo.dataRoma(e.start_at.str) == Tempo.dataRoma(f.addingTimeInterval(-1))
    }

    private func bloccoSotto(_ p: CGPoint) -> (blocco: BloccoEvento, giorno: String)? {
        guard p.x >= margineOreCalendario else { return nil }
        let i = indiceColonna(p.x)
        guard giorni.indices.contains(i) else { return nil }
        let x = p.x - margineOreCalendario + scorrimentoX() - CGFloat(i) * colonna
        for b in StatoCalendario.s.giorno(giorni[i]).blocchi.reversed() {
            let w = (colonna - 2) / CGFloat(b.colonne)
            let sinistra = w * CGFloat(b.colonna) + 1
            let alto = CGFloat(b.inizio) / 60 * altezza
            let h = b.task != nil ? 26 : max(22, CGFloat(b.fineVisiva - b.inizio) / 60 * altezza)
            if x >= sinistra, x <= sinistra + w * CGFloat(b.larghezza), p.y >= alto, p.y <= alto + h {
                return spostabile(b) ? (b, giorni[i]) : nil
            }
        }
        return nil
    }

    private func rettangoloPresa() -> CGRect? {
        guard let p = stato.presa, let i = giorni.firstIndex(of: p.giorno) else { return nil }
        let x = margineOreCalendario + CGFloat(i) * colonna - scorrimentoX() + 1
        let y = CGFloat(p.inizio) / 60 * altezza
        return CGRect(x: x, y: y, width: colonna - 2, height: max(22, CGFloat(p.fine - p.inizio) / 60 * altezza))
    }

    // MARK: I gesti

    @objc private func gestoLungo(_ g: UILongPressGestureRecognizer) {
        guard let superficie else { return }
        let p = g.location(in: superficie)
        switch g.state {
        case .began:
            guard let (b, giorno) = bloccoSotto(p) else {
                g.isEnabled = false
                g.isEnabled = true
                return
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            stato.presa = Trascinamento.Presa(id: b.id, evento: b.evento, task: b.task, giornoOrigine: giorno, inizioOrigine: b.inizio, fineOrigine: b.fine, giorno: giorno, inizio: b.inizio, fine: b.fine)
            BloccoPreso.s.id = b.id
            mia = true
            comincia(g, .sposta, p)
        case .changed: muovi(p)
        case .ended: rilascia()
        case .cancelled, .failed: lascia()
        default: break
        }
    }

    @objc private func gestoSubito(_ g: UILongPressGestureRecognizer) {
        guard let superficie else { return }
        let p = g.location(in: superficie)
        switch g.state {
        case .began:
            guard let r = rettangoloPresa(), stato.presa != nil else {
                lascia()
                return
            }
            let conBordi = stato.presa?.evento != nil
            if conBordi, abs(p.y - r.minY) < 22, r.insetBy(dx: -10, dy: -22).contains(p) {
                comincia(g, .inizio, p)
            } else if conBordi, abs(p.y - r.maxY) < 22, r.insetBy(dx: -10, dy: -22).contains(p) {
                comincia(g, .fine, p)
            } else if r.contains(p) {
                comincia(g, .sposta, p)
            } else {
                lascia()
            }
        case .changed: muovi(p)
        case .ended: rilascia()
        case .cancelled, .failed: if attivo != nil { fermaDito() }
        default: break
        }
    }

    private func comincia(_ g: UIGestureRecognizer, _ tipo: Gesto, _ p: CGPoint) {
        attivo = g
        gesto = tipo
        partenza = p
        mosso = false
        alBordoDa = nil
        appiglio = Double(p.y) / Double(altezza) * 60 - Double(stato.presa?.inizio ?? 0)
        interno = interno ?? primaScrollDentro(scroll)
        scroll?.isScrollEnabled = false
        interno?.isScrollEnabled = false
        passi.prepare()
        let c = CADisplayLink(target: self, selector: #selector(battito))
        c.add(to: .main, forMode: .common)
        collegamento = c
    }

    private func primaScrollDentro(_ v: UIView?) -> UIScrollView? {
        for s in v?.subviews ?? [] {
            if let x = s as? UIScrollView { return x }
            if let x = primaScrollDentro(s) { return x }
        }
        return nil
    }

    private func arrotonda(_ m: Double) -> Int {
        let passo = altezza >= 90 ? 1.0 : 5.0
        return Int((m / passo).rounded() * passo)
    }

    private func muovi(_ p: CGPoint) {
        guard var n = stato.presa else { return }
        // Un dito fermo trema: finché non parte davvero, il blocco non si muove
        if !mosso {
            guard hypot(p.x - partenza.x, p.y - partenza.y) > 8 else { return }
            mosso = true
        }
        let minuti = Double(p.y) / Double(altezza) * 60
        switch gesto {
        case .sposta:
            let durata = n.fine - n.inizio
            n.inizio = min(24 * 60 - durata, max(0, arrotonda(minuti - appiglio)))
            n.fine = n.inizio + durata
            let primo = Int((scorrimentoX() / max(1, colonna)).rounded())
            let i = min(primo + quanti - 1, max(primo, indiceColonna(p.x)))
            if giorni.indices.contains(i) { n.giorno = giorni[i] }
        case .inizio:
            n.inizio = max(0, min(n.fine - 5, arrotonda(minuti)))
        case .fine:
            n.fine = min(24 * 60, max(n.inizio + 5, arrotonda(minuti)))
        }
        if n != stato.presa {
            stato.presa = n
            passi.selectionChanged()
        }
    }

    /// Al bordo la griglia va avanti da sola: su e giù per le ore, di lato per i giorni.
    @objc private func battito() {
        guard let scroll, let superficie, let attivo else { return }
        let p = attivo.location(in: scroll)
        let visibile = scroll.bounds.height - scroll.adjustedContentInset.bottom
        let y = p.y - scroll.contentOffset.y
        let fascia: CGFloat = 56
        var v: CGFloat = 0
        if y < fascia { v = -(fascia - y) / fascia * 9 } else if y > visibile - fascia { v = (y - (visibile - fascia)) / fascia * 9 }
        if v != 0, mosso {
            let massimo = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.contentOffset.y = min(massimo, max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + v))
        }
        if gesto == .sposta, mosso {
            let aSinistra = p.x < margineOreCalendario + 20
            let aDestra = p.x > scroll.bounds.width - 20
            if aSinistra || aDestra {
                let ora = CACurrentMediaTime()
                if let da = alBordoDa {
                    if ora - da > 0.55 {
                        alBordoDa = ora
                        let primo = Int((scorrimentoX() / max(1, colonna)).rounded())
                        let salto = quanti == 7 ? 7 : 1
                        let i = primo + (aDestra ? salto : -salto)
                        if giorni.indices.contains(i) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            vai(giorni[i])
                        }
                    }
                } else {
                    alBordoDa = ora
                }
            } else {
                alBordoDa = nil
            }
        }
        muovi(attivo.location(in: superficie))
    }

    // MARK: Per le prove automatiche

    static weak var ultimo: ControlloreDito?

    /// Dove sono davvero i blocchi sullo schermo: «nome=x,y,l,a;…».
    func blocchiSulloSchermo() -> String {
        guard let superficie, colonna > 1 else { return "" }
        let primo = Int((scorrimentoX() / colonna).rounded())
        var out: [String] = []
        for i in primo..<(primo + quanti) where giorni.indices.contains(i) {
            for b in StatoCalendario.s.giorno(giorni[i]).blocchi {
                let w = (colonna - 2) / CGFloat(b.colonne)
                let locale = CGRect(x: margineOreCalendario + CGFloat(i) * colonna - scorrimentoX() + w * CGFloat(b.colonna) + 1, y: CGFloat(b.inizio) / 60 * altezza, width: w * CGFloat(b.larghezza), height: max(22, CGFloat(b.fineVisiva - b.inizio) / 60 * altezza))
                let r = superficie.convert(locale, to: nil)
                out.append("\(b.evento?.summary.t ?? b.task?.title.t ?? "")=\(r.minX),\(r.minY),\(r.width),\(r.height)")
            }
        }
        return out.joined(separator: ";")
    }

    private func fermaDito() {
        collegamento?.invalidate()
        collegamento = nil
        attivo = nil
        scroll?.isScrollEnabled = true
        interno?.isScrollEnabled = true
    }

    private func rilascia() {
        fermaDito()
        guard let p = stato.presa else { return }
        if p.cambiata {
            salva(p)
            lascia()
        } else if !stato.selezionata {
            // Preso e lasciato lì: si possono tirare i bordi
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if p.evento != nil {
                stato.selezionata = true
                subito.isEnabled = true
            } else {
                lascia()
            }
        }
    }

    func lascia() {
        fermaDito()
        subito.isEnabled = false
        guard mia else { return }
        mia = false
        stato.presa = nil
        stato.selezionata = false
        BloccoPreso.s.id = nil
    }

    private func salva(_ p: Trascinamento.Presa) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let inizio = Tempo.istante(p.giorno, oraCalendario(p.inizio))
        if let e = p.evento, let id = e.own_event_id.str {
            let fine = inizio.addingTimeInterval(Double(p.fine - p.inizio) * 60)
            Azioni.salvaEvento(id: id, valori: ["start_at": .str(Tempo.iso(inizio)), "end_at": .str(Tempo.iso(fine))], minutiPromemoria: Azioni.promemoria(evento: id).compactMap { $0.offset_minutes.int })
        } else if let t = p.task {
            Azioni.modifica(t.id.t, ["due_at": .str(Tempo.iso(inizio)), "due_has_time": true], "Task spostato")
        }
    }
}

/// Un evento nella griglia, come su Windows: fondo tinto, linea di lato dritta, solo le righe che
/// entrano intere (titolo, aula e docente, gruppi, ora).
private struct BloccoEventoVista: View {
    let evento: J
    let larghezza: CGFloat
    let altezza: CGFloat
    let durata: Int
    var colonna = 0
    var sollevato = false

    var body: some View {
        let lezione = evento.own_event_id.isNull ? Lezione.di(evento) : nil
        let tinta = TintaEvento.di(StatoCalendario.s.colore(evento))
        let passato = evento.end_at.t < Tempo.iso(Date())
        let forma = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .leading) {
            tinta.fondo
            tinta.linea.frame(width: 3)
            testi(lezione)
                .foregroundStyle(tinta.testo)
                .padding(.leading, stretto ? 6 : 8)
                .padding(.trailing, stretto ? 2 : 6)
                .padding(.top, compatto ? 0 : 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compatto ? .leading : .topLeading)
        }
        .clipShape(forma)
        .overlay {
            // Solo chi si sovrappone a un altro ha il contorno che li separa
            if colonna > 0 { forma.strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.5) }
        }
        .opacity(passato && !sollevato ? 0.6 : 1)
    }

    private var stretto: Bool { larghezza < 70 }
    private var compatto: Bool { altezza < 34 }
    private var riga: CGFloat { stretto ? 13.5 : 15 }
    private var posti: Int { max(1, Int((altezza - (compatto ? 2 : 6)) / riga)) }
    private var grande: CGFloat { stretto ? 11 : 12 }
    private var piccolo: CGFloat { stretto ? 10 : 11 }

    private func titolo(_ t: String, righe: Int) -> some View {
        Text(t)
            .font(.system(size: grande, weight: .semibold))
            .lineLimit(righe)
            .minimumScaleFactor(stretto ? 0.8 : 1)
    }

    private func dettaglio(_ t: String) -> some View {
        Text(t).font(.system(size: piccolo)).monospacedDigit().opacity(0.75).lineLimit(1).frame(height: riga)
    }

    @ViewBuilder
    private func testi(_ lezione: Lezione?) -> some View {
        let orario = "\(Tempo.oraRoma(evento.start_at.str) ?? "") – \(Tempo.oraRoma(evento.end_at.str) ?? "")"
        if let lezione {
            let righeTitolo = posti >= 3 ? 2 : 1
            let dove = lezione.dove
            let gruppi = lezione.gruppi.joined(separator: ", ")
            let resto = posti - righeTitolo
            let conDove = !dove.isEmpty && resto >= 1
            let usate = conDove ? 1 : 0
            let conGruppi = !gruppi.isEmpty && resto - usate >= 1
            let conOra = resto - usate - (conGruppi ? 1 : 0) >= 1
            VStack(alignment: .leading, spacing: 0) {
                titolo(lezione.titolo, righe: righeTitolo)
                if conDove { dettaglio(dove) }
                if conGruppi { dettaglio(gruppi) }
                if conOra { dettaglio(orario) }
            }
        } else {
            let nome = evento.summary.t.isEmpty ? "(senza titolo)" : evento.summary.t
            let righeTitolo = posti >= 2 ? min(3, posti - 1) : 1
            VStack(alignment: .leading, spacing: 0) {
                titolo(nome, righe: righeTitolo)
                if posti >= 2 { dettaglio(orario) }
            }
        }
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
                    .foregroundStyle(scelto ? (oggi ? Color.white : Color(uiColor: .systemBackground)) : oggi ? Color.rossoCalendario : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(scelto ? (oggi ? Color.rossoCalendario : Color.primary) : Color.clear, in: Circle())
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
        .frame(height: 50, alignment: .top)
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
                    .foregroundStyle(oggi ? Color.rossoCalendario : Color.secondarioLife)
                Text("\(n)")
                    .font(.system(size: 16, weight: oggi ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(oggi ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(oggi ? Color.rossoCalendario : Color.clear, in: Circle())
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
        let base = Int((scorrimento.x / max(1, colonna)).rounded())
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
                .frame(height: CGFloat(righe) * 25 + 6, alignment: .top)
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
        .contextMenu {
            if let e = v.evento { MenuEvento(e: e) { apriEvento(e) } }
        }
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
                    .background(oggi ? Color.rossoCalendario : selezionato ? Color(uiColor: .tertiarySystemFill) : Color.clear, in: Circle())
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
        .contextMenu { MenuEvento(e: e) }
    }
}
