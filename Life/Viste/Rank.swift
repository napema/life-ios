import SwiftUI
import Charts

// Rank: il cruscotto dell'anno su iPhone — Quadro, Storico voti, Andamento (corsa + schema), Altro.
// I conti sono quelli condivisi del sito (moduli/rank + ios/logica/shim/rank.js).

@discardableResult
private func rk(_ f: String, _ a: J...) -> J { Logica.s.chiama("rank.\(f)", argomenti: a) }
private let gialloRank = Color(hex: "#FFD60A")
private let rossoRank = Color(hex: "#FF453A")
private let verdeRank = Color(hex: "#30D158")
private let bluAccert = Color(hex: "#0A84FF")
private let violaEsame = Color(hex: "#BF5AF2")
private let nomiBinario: [String: String] = ["accertamento": "Accertamento", "esame": "Esame", "fisica": "Prova fisica"]

private func coloreBinario(_ b: String) -> Color {
    switch b {
    case "accertamento": return bluAccert
    case "esame": return violaEsame
    case "fisica": return verdeRank
    default: return gialloRank
    }
}

private func coloreVoto(_ v: Double?) -> Color {
    guard let v else { return Color.secondarioLife }
    if v <= 23 { return rossoRank }
    if v <= 26 { return gialloRank }
    return verdeRank
}

private func testoVoto(_ v: Int?) -> String {
    guard let v else { return "—" }
    return v >= 31 ? "30L" : "\(v)"
}

private func virgola(_ n: Double, _ d: Int = 1) -> String {
    String(format: "%.\(d)f", n).replacingOccurrences(of: ".", with: ",")
}

private func segno(_ n: Double, _ d: Int = 1) -> String { (n >= 0 ? "+" : "−") + virgola(abs(n), d) }

private func mmss(_ s: Double) -> String {
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}

private func conto(_ fra: Int?) -> String {
    guard let f = fra else { return "—" }
    return f == 0 ? "oggi" : f == 1 ? "domani" : "\(f)g"
}

private func coloreConto(_ fra: Int?) -> Color {
    guard let f = fra else { return Color.primary }
    return f < 7 ? rossoRank : f <= 14 ? gialloRank : Color.primary
}

private func fraseTraguardo(_ stato: String, _ serve: Double, _ restanti: Int) -> String {
    if stato == "impossibile" { return "Con \(restanti) prove davanti non ci arrivi più: servirebbe \(virgola(serve)) di media." }
    if stato == "largo" { return "Ci sei comodo: nelle prossime \(restanti) ti basta la sufficienza." }
    let parola = restanti == 1 ? "prova" : "prove"
    return "Ti serve \(virgola(serve)) di media nelle prossime \(restanti) \(parola)."
}

struct ProvaAperta: Identifiable {
    let p: J
    var id: String { p.id.t }
}

struct AvanzamentoAperto: Identifiable {
    let r: J
    var id: String { r.id.t }
}

struct VistaRank: View {
    init(scheda: String) { self.scheda = scheda }

    @ObservedObject private var logica = Logica.s
    let scheda: String
    @State private var aperta: ProvaAperta?
    @State private var avanza: AvanzamentoAperto?
    @State private var mostraNuova = false
    @State private var filtroBinario = "tutti"
    @State private var ordineVoti = "recenti"

    private var titoloNav: String {
        switch scheda {
        case "voti": return "Storico voti"
        case "andamento": return "Andamento"
        case "altro": return "Impostazioni"
        default: return "Rank"
        }
    }

    var body: some View {
        let _ = logica.versione
        let q = rk("quadro")
        return Pagina {
            switch scheda {
            case "voti": storicoVoti(q)
            case "andamento": andamento(q)
            case "altro": impostazioni(q)
            default: quadro(q)
            }
        }
        .navigationTitle(titoloNav)
        .toolbar {
            if scheda == "quadro" || scheda == "voti" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        tocco()
                        mostraNuova = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(scheda == "voti" ? "Registra voto" : "Nuova prova")
                }
            }
        }
        .sheet(item: $aperta) { a in FoglioEsito(p: a.p) }
        .sheet(item: $avanza) { a in FoglioAvanzamento(r: a.r) }
        .sheet(isPresented: $mostraNuova) { FoglioNuovaProva(soloVoto: scheda == "voti") }
    }

    // MARK: - Tab 1: Quadro

    @ViewBuilder
    private func quadro(_ q: J) -> some View {
        riepilogoMedia(q)
        if !q.daRegistrare.list.isEmpty {
            Sezione("Da registrare", coda: { Text("\(q.daRegistrare.list.count) senza voto").foregroundStyle(gialloRank) }) {
                Carta(padding: 6) {
                    ForEach(q.daRegistrare.list, id: \.id) { p in rigaArrivo(p, registra: true) }
                }
            }
        }
        onTrack(q)
        if let p = q.inArrivo.list.first {
            prossimaCard(p)
        }
        if !q.inArrivo.list.isEmpty {
            Sezione("Prossime prove", coda: { Text("\(q.inArrivo.list.count)") }) {
                Carta(padding: 6) {
                    ForEach(q.inArrivo.list.prefix(8), id: \.id) { p in rigaArrivo(p, registra: false) }
                }
            }
        }
        if !q.fatte.list.isEmpty {
            Sezione("Ultimi voti", coda: { Text("\(q.fatte.list.count) totali") }) {
                Carta(padding: 6) {
                    ForEach(q.fatte.list.prefix(3), id: \.id) { p in rigaVoto(p) }
                }
            }
        }
    }

    @ViewBuilder
    private func riepilogoMedia(_ q: J) -> some View {
        let media = q.mediaTutti.num
        let col = media == nil ? Color.secondarioLife : coloreVoto(media)
        let frac = media.map { max(0.05, ($0 - 18) / 12) } ?? 0
        Carta {
            HStack(spacing: 16) {
                ZStack {
                    Anello(valore: frac, misura: 76, spessore: 8, colore: col)
                    VStack(spacing: 0) {
                        Text(media.map { virgola($0, 1) } ?? "—")
                            .font(.title3.weight(.bold)).monospacedDigit()
                        Text("/ 30").font(.caption2).foregroundStyle(Color.secondarioLife)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(media != nil ? "Media complessiva" : "Nessun voto registrato")
                        .font(.headline)
                    if let n = q.totaleVoti.int, n > 0 {
                        Text("\(n) \(n == 1 ? "voto registrato" : "voti registrati")")
                            .font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    if !q.mediaEsami.isNull, let m = q.mediaEsami.media.num {
                        Text("Esami: \(virgola(m, 2))")
                            .font(.footnote).foregroundStyle(violaEsame)
                    }
                }
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                pillolaMedia("Accertamenti", q.mediaAccertamenti.media.num, q.mediaAccertamenti.n.int ?? 0, bluAccert)
                pillolaMedia("Esami", q.mediaEsami.isNull ? nil : q.mediaEsami.media.num, q.mediaEsami.isNull ? 0 : (q.mediaEsami.n.int ?? 0), violaEsame)
                pillolaMedia("Fisiche", q.mediaFisiche.media.num, q.mediaFisiche.n.int ?? 0, verdeRank)
            }
        }
    }

    private func pillolaMedia(_ eti: String, _ media: Double?, _ n: Int, _ col: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eti).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1)
            Text(media.map { virgola($0, 1) } ?? "—")
                .font(.headline).monospacedDigit()
                .foregroundStyle(media != nil ? col : Color.terziarioLife)
            Text(n > 0 ? "\(n) voti" : "nessuno").font(.caption2).foregroundStyle(Color.terziarioLife)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func prossimaCard(_ p: J) -> some View {
        Button { aperta = ProvaAperta(p: p) } label: {
            Carta {
                HStack(alignment: .firstTextBaseline) {
                    Text("PROSSIMA PROVA").font(.caption.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                    Spacer()
                    if let g = p.giorno.str {
                        Text(Tempo.breve(g)).font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                }
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.titolo.t).font(.title3.weight(.bold)).foregroundStyle(Color.primary).lineLimit(2)
                        Text([nomiBinario[p.binario.t] ?? "", p.ora.t, p.obiettivo.t.isEmpty ? "" : "ob. \(p.obiettivo.t)"].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    Spacer()
                    Text(p.fra.int.map { $0 == 0 ? "oggi" : $0 == 1 ? "domani" : "\($0)g" } ?? "")
                        .font(.title.weight(.bold)).monospacedDigit()
                        .foregroundStyle(coloreConto(p.fra.int))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func onTrack(_ q: J) -> some View {
        let righe = q.ontrack.list
        if !righe.isEmpty {
            Sezione("In preparazione", coda: { Text("\(righe.count) \(righe.count == 1 ? "attiva" : "attive")") }) {
                Carta {
                    ForEach(Array(righe.enumerated()), id: \.element.id) { idx, r in
                        if idx > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(r.titolo.t).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                if let s = r.nomeStato.str {
                                    Text(s)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(hex: r.colore.t))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: r.colore.t).opacity(0.15), in: Capsule())
                                }
                            }
                            if let fatte = r.fatte.num, let tot = r.totali.num, tot > 0 {
                                Barra(valore: fatte / tot, colore: Color(hex: r.colore.t), altezza: 5)
                            }
                            Text(r.frase.t).font(.footnote).foregroundStyle(Color.secondarioLife)
                            if !r.nota.t.isEmpty {
                                Text(r.nota.t).font(.caption).foregroundStyle(Color.terziarioLife)
                            }
                            if r.fase.t == "lavoro" || r.fase.t == "test" {
                                Button(r.fase.t == "test" ? "Registra un test" : "Registra \(r.unitaTipo.str ?? "pagine")") {
                                    avanza = AvanzamentoAperto(r: r)
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(gialloRank)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    ForEach(q.conflitti.list.indices, id: \.self) { i in
                        Text(q.conflitti[i].t).font(.footnote).foregroundStyle(rossoRank)
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Storico voti

    @ViewBuilder
    private func storicoVoti(_ q: J) -> some View {
        let tutti = q.fatte.list
        let filtrati: [J] = {
            let base = filtroBinario == "tutti" ? tutti : tutti.filter { $0.binario.t == filtroBinario }
            switch ordineVoti {
            case "alti": return base.sorted { ($0.voto.int ?? -1) > ($1.voto.int ?? -1) }
            case "bassi": return base.sorted { ($0.voto.int ?? 99) < ($1.voto.int ?? 99) }
            default: return base
            }
        }()
        let conVoto = filtrati.compactMap { $0.voto.int }
        let lode = q.lode.int ?? 30
        let mediaF: Double? = conVoto.isEmpty ? nil : Double(conVoto.reduce(0) { $0 + ($1 >= 31 ? lode : $1) }) / Double(conVoto.count)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Pillola(testo: "Tutti (\(tutti.count))", attiva: filtroBinario == "tutti", colore: gialloRank) { filtroBinario = "tutti" }
                Pillola(testo: "Accertamenti", attiva: filtroBinario == "accertamento", colore: bluAccert) { filtroBinario = "accertamento" }
                Pillola(testo: "Esami", attiva: filtroBinario == "esame", colore: violaEsame) { filtroBinario = "esame" }
                Pillola(testo: "Fisiche", attiva: filtroBinario == "fisica", colore: verdeRank) { filtroBinario = "fisica" }
            }
        }

        Picker("Ordine", selection: $ordineVoti) {
            Text("Recenti").tag("recenti")
            Text("Migliori").tag("alti")
            Text("Peggiori").tag("bassi")
        }
        .pickerStyle(.segmented)

        // Media + distribuzione
        if !conVoto.isEmpty {
            let alti = conVoto.filter { $0 >= 27 }.count
            let medi = conVoto.filter { $0 >= 24 && $0 <= 26 }.count
            let bassi = conVoto.filter { $0 <= 23 }.count
            let tot = Double(conVoto.count)
            Carta {
                HStack(spacing: 14) {
                    ZStack {
                        Anello(valore: mediaF.map { max(0.05, ($0 - 18) / 12) } ?? 0, misura: 68, spessore: 7, colore: coloreVoto(mediaF))
                        Text(mediaF.map { virgola($0, 1) } ?? "—").font(.headline.weight(.bold)).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        barraFascia("27–30L", alti, tot, verdeRank)
                        barraFascia("24–26", medi, tot, gialloRank)
                        barraFascia("18–23", bassi, tot, rossoRank)
                    }
                }
            }
        }

        // Grafico andamento
        let serie = filtroBinario == "fisica" ? q.fisiche : q.studio
        let votiGraf = serie.voti.list
        if votiGraf.count >= 2 && (filtroBinario == "tutti" || filtroBinario == "fisica") {
            Sezione("Andamento", coda: { Text(serie.pendenza.num.map { "\(segno($0, 2))/prova" } ?? "") }) {
                Carta {
                    Chart {
                        if let ob = q.obiettivo.int, filtroBinario != "fisica" {
                            RuleMark(y: .value("Obiettivo", ob))
                                .foregroundStyle(verdeRank.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        ForEach(votiGraf.indices, id: \.self) { i in
                            if let r = votiGraf[i].retta.num {
                                LineMark(x: .value("Prova", i), y: .value("Retta", r), series: .value("s", "retta"))
                                    .foregroundStyle(Color.secondary)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            }
                            PointMark(x: .value("Prova", i), y: .value("Voto", votiGraf[i].v.d))
                                .foregroundStyle(coloreVoto(votiGraf[i].v.num))
                                .symbolSize(65)
                        }
                    }
                    .chartYScale(domain: 17...31)
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .trailing, values: [18, 24, 27, 30]) }
                    .frame(height: 150)
                }
            }
        }

        if filtroBinario != "fisica" {
            traguardo(q)
        }

        if filtrati.isEmpty {
            Carta {
                VStack(spacing: 8) {
                    Text("Nessun voto registrato").font(.headline)
                    Text("Tocca + in alto a destra per registrare un voto.")
                        .font(.footnote).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } else {
            Sezione("Voti", coda: { Text("\(filtrati.count)") }) {
                Carta(padding: 6) {
                    ForEach(filtrati, id: \.id) { p in rigaVoto(p) }
                }
            }
        }
    }

    private func barraFascia(_ eti: String, _ n: Int, _ tot: Double, _ col: Color) -> some View {
        HStack(spacing: 8) {
            Text(eti).font(.caption2).foregroundStyle(Color.secondarioLife).frame(width: 48, alignment: .leading).monospacedDigit()
            Barra(valore: Double(n) / max(1, tot), colore: col, altezza: 6)
            Text("\(n)").font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife).frame(width: 22, alignment: .trailing).monospacedDigit()
        }
    }

    // MARK: - Tab 3: Andamento (Corsa + Schema)

    @ViewBuilder
    private func andamento(_ q: J) -> some View {
        if !q.corsa.isNull {
            corsa(q.corsa)
        } else {
            Carta {
                Text("Corsa").font(.headline)
                Text("Nessuna corsa registrata in Training.").font(.footnote).foregroundStyle(Color.secondarioLife)
            }
        }
        schemaCard(q.schema)
    }

    @ViewBuilder
    private func schemaCard(_ s: J) -> some View {
        let p = s.presto.media.num
        let m = s.medio.media.num
        let t = s.tardi.media.num
        Sezione("Il mio schema", coda: { Text("da avanzamenti e debrief") }) {
            Carta {
                if p == nil && m == nil && t == nil {
                    Text("Registra gli avanzamenti mentre studi e il debrief dopo ogni prova per vedere come cambia la tua media in base all'anticipo.")
                        .font(.footnote).foregroundStyle(Color.secondarioLife)
                } else {
                    HStack(spacing: 8) {
                        cellaSchema("10+ giorni", p, s.presto.n.int ?? 0)
                        cellaSchema("3–9 giorni", m, s.medio.n.int ?? 0)
                        cellaSchema("< 3 giorni", t, s.tardi.n.int ?? 0)
                    }
                    Divider()
                    RigaValore(etichetta: "Media al giorno", valore: s.alGiorno.num.map { virgola($0) } ?? "—")
                    RigaValore(etichetta: "Giorno migliore", valore: s.giornoMigliore.int.map { "\($0)" } ?? "—")
                    RigaValore(etichetta: "Capacità motore", valore: "\(s.calibrata.int ?? 15)/giorno")
                }
            }
        }
    }

    private func cellaSchema(_ eti: String, _ media: Double?, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eti).font(.caption2).foregroundStyle(Color.secondarioLife)
            Text(media.map { virgola($0, 1) } ?? "—").font(.headline.weight(.bold)).monospacedDigit().foregroundStyle(coloreVoto(media))
            Text(n > 0 ? "\(n) prove" : "—").font(.caption2).foregroundStyle(Color.terziarioLife)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func corsa(_ c: J) -> some View {
        let scarto = c.stima.num.map { $0 - c.obiettivo.d }
        Sezione("Corsa · 5000 m", coda: { Text("\(c.corse.int ?? 0) corse") }) {
            Carta {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                    KpiRank(
                        eti: "Il tuo 5000 oggi",
                        valore: c.stima.num.map(mmss) ?? "—",
                        sotto: scarto.map { $0 <= 0 ? "sotto obiettivo di \(mmss(-$0))" : "\(mmss($0)) sopra \(mmss(c.obiettivo.d))" } ?? "serve corsa ≥ 2 km",
                        colore: scarto.map { $0 <= 0 ? verdeRank : rossoRank }
                    )
                    KpiRank(
                        eti: "Efficienza",
                        valore: c.ef.num.map { virgola($0, 2) } ?? "—",
                        sotto: c.efPct.num.map { "\(segno($0))%" } ?? "m/min per battito",
                        colore: c.efPct.num.map { $0 >= 1 ? verdeRank : $0 <= -1 ? rossoRank : Color.secondarioLife }
                    )
                    KpiRank(
                        eti: "Forma",
                        valore: segno(c.forma.d, 0),
                        sotto: "fitness \(virgola(c.fitness.d, 0)) · fatica \(virgola(c.fatica.d, 0))",
                        colore: c.fitnessDelta.d < -1 ? rossoRank : c.fitnessDelta.d > 1 ? verdeRank : nil
                    )
                    KpiRank(
                        eti: "Ultima corsa",
                        valore: (c.giorniSenza.int ?? 0) == 0 ? "oggi" : (c.giorniSenza.int ?? 0) == 1 ? "ieri" : "\(c.giorniSenza.int ?? 0)g fa",
                        sotto: "\(virgola(c.ultimaKm.d)) km in \(mmss(c.ultimaSecondi.d))",
                        colore: (c.giorniSenza.int ?? 0) >= 7 ? rossoRank : (c.giorniSenza.int ?? 0) >= 4 ? gialloRank : verdeRank
                    )
                }
                let punti = c.equiv.list
                if punti.count >= 2 {
                    Divider()
                    Text("5000 equivalente").font(.subheadline.weight(.semibold))
                    Chart {
                        RuleMark(y: .value("Obiettivo", c.obiettivo.d)).foregroundStyle(verdeRank).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        ForEach(punti.indices, id: \.self) { i in
                            LineMark(x: .value("Corsa", i), y: .value("Secondi", punti[i].t5.d)).foregroundStyle(gialloRank)
                            PointMark(x: .value("Corsa", i), y: .value("Secondi", punti[i].t5.d)).foregroundStyle(gialloRank).symbolSize(26)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing) { v in
                            AxisGridLine()
                            AxisValueLabel { if let s = v.as(Double.self) { Text(mmss(s)).font(.caption2) } }
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
    }

    // MARK: - Tab 4: Impostazioni

    @ViewBuilder
    private func impostazioni(_ q: J) -> some View {
        let lode = q.lode.int ?? 30
        Sezione("Valutazione") {
            Carta {
                HStack {
                    Text("Valore della lode (30L)").font(.subheadline)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([30, 31, 33], id: \.self) { v in
                            Button("\(v)") {
                                tocco()
                                rk("impostaLode", J.n(v))
                            }
                            .font(.subheadline.weight(lode == v ? .bold : .regular)).monospacedDigit()
                            .frame(width: 40, height: 32)
                            .foregroundStyle(lode == v ? Color.black : Color.secondarioLife)
                            .background(lode == v ? gialloRank : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        traguardo(q)
        Text("Le prove trovate nel calendario si confermano da Life sul PC.").font(.footnote).foregroundStyle(Color.secondarioLife).padding(.horizontal, 4)
    }

    // MARK: - Componenti condivisi

    @ViewBuilder
    private func traguardo(_ q: J) -> some View {
        let ob = q.obiettivo.int
        let t = q.traguardo
        let restanti = q.restanti.int ?? 0
        Sezione("Obiettivo media", coda: { Text(ob.map { "\($0) / 30" } ?? "") }) {
            Carta {
                HStack(spacing: 6) {
                    ForEach(24...30, id: \.self) { v in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            rk("obiettivo", ob == v ? J.null : J.n(v))
                        } label: {
                            Text("\(v)")
                                .font(.subheadline.weight(ob == v ? .bold : .regular)).monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(ob == v ? Color.black : Color.secondarioLife)
                                .background(ob == v ? gialloRank : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if ob == nil {
                    Text("Scegli la media a cui vuoi chiudere: ti dico che voti servono.").font(.footnote).foregroundStyle(Color.secondarioLife)
                } else if let serve = t.serve.num {
                    let stato = t.stato.t
                    Text(fraseTraguardo(stato, serve, restanti))
                        .font(.subheadline)
                        .foregroundStyle(stato == "impossibile" ? rossoRank : stato == "largo" ? verdeRank : Color.primary)
                } else {
                    Text(t.stato.t == "raggiunto" ? "Obiettivo raggiunto, e non restano prove." : "Non restano prove in calendario per spostare la media.")
                        .font(.subheadline).foregroundStyle(Color.secondarioLife)
                }
            }
        }
    }

    private func rigaArrivo(_ p: J, registra: Bool) -> some View {
        Button { aperta = ProvaAperta(p: p) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    if registra {
                        Text(p.giorno.str.map { Tempo.breve($0) } ?? "—").font(.subheadline).monospacedDigit().foregroundStyle(Color.secondarioLife)
                    } else {
                        Text(conto(p.fra.int)).font(.headline).monospacedDigit().foregroundStyle(coloreConto(p.fra.int))
                        Text(p.giorno.str.map { Tempo.breve($0) } ?? "").font(.caption2).foregroundStyle(Color.secondarioLife)
                    }
                }
                .frame(width: 54, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.titolo.t).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(nomiBinario[p.binario.t] ?? "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(coloreBinario(p.binario.t))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(coloreBinario(p.binario.t).opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        if !p.obiettivo.t.isEmpty {
                            Text("ob. \(p.obiettivo.t)").font(.caption).foregroundStyle(Color.secondarioLife)
                        }
                    }
                }
                Spacer()
                if registra {
                    Text("Registra").font(.subheadline.weight(.medium)).foregroundStyle(gialloRank)
                } else {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.terziarioLife)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rigaVoto(_ p: J) -> some View {
        let haVoto = p.voto.int != nil
        let col = haVoto ? coloreVoto(p.voto.num) : coloreBinario(p.binario.t)
        let badge = haVoto ? testoVoto(p.voto.int) : (p.risultato.t.isEmpty ? "—" : p.risultato.t)
        let obInt = Int(p.obiettivo.t.trimmingCharacters(in: .whitespaces))
        let delta: Int? = (haVoto && obInt != nil) ? min(30, p.voto.int!) - obInt! : nil
        return Button { aperta = ProvaAperta(p: p) } label: {
            HStack(spacing: 12) {
                Text(badge)
                    .font(badge.count > 4 ? .caption.weight(.bold) : .headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(col)
                    .frame(width: 44, height: 44)
                    .background(col.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.titolo.t).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary).lineLimit(1)
                    HStack(spacing: 5) {
                        Text((p.giorno.str ?? p.esitoIl.str).map { Tempo.breve($0) } ?? "—").font(.caption).foregroundStyle(Color.secondarioLife)
                        Text("·").font(.caption).foregroundStyle(Color.terziarioLife)
                        Text(nomiBinario[p.binario.t] ?? "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(coloreBinario(p.binario.t))
                    }
                }
                Spacer()
                if let d = delta, let ob = obInt {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(d > 0 ? "+\(d)" : d == 0 ? "=" : "−\(abs(d))")
                            .font(.footnote.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(d >= 0 ? verdeRank : rossoRank)
                        Text("ob. \(ob)").font(.caption2).foregroundStyle(Color.terziarioLife).monospacedDigit()
                    }
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.terziarioLife)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct KpiRank: View {
    let eti: String
    let valore: String
    let sotto: String
    var colore: Color?
    var coloreValore: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eti).font(.caption).foregroundStyle(Color.secondarioLife)
            Text(valore).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(coloreValore ?? Color.primary).lineLimit(1).minimumScaleFactor(0.6)
            if !sotto.isEmpty {
                Text(sotto).font(.caption).foregroundStyle(colore ?? Color.secondarioLife).lineLimit(2)
            }
        }
    }
}

// MARK: - Fogli

private struct FoglioEsito: View {
    let p: J
    @Environment(\.dismiss) private var chiudi
    @State private var voto: Int?
    @State private var tempo: String

    init(p: J) {
        self.p = p
        _voto = State(initialValue: p.voto.int)
        _tempo = State(initialValue: p.risultato.t)
    }

    var body: some View {
        let fisica = p.binario.t == "fisica"
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text([nomiBinario[p.binario.t] ?? "", p.giorno.str.map { Tempo.breve($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Color.secondarioLife)
                    Text("Voto").font(.footnote).foregroundStyle(Color.secondarioLife)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(18...31, id: \.self) { v in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                voto = voto == v ? nil : v
                            } label: {
                                Text(v == 31 ? "30L" : "\(v)")
                                    .font(.headline).monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(voto == v ? Color.black : Color.primary)
                                    .background(voto == v ? coloreVoto(Double(v)) : Color.cartaLife, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if fisica {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tempo · se te lo ricordi").font(.footnote).foregroundStyle(Color.secondarioLife)
                            TextField("mm:ss", text: $tempo)
                                .keyboardType(.numbersAndPunctuation)
                                .font(.system(size: 34, weight: .bold)).monospacedDigit()
                        }
                        .padding(14)
                        .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Color.sfondoLife)
            .navigationTitle(p.titolo.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        rk("registra", J.str(p.id.t), voto.map { J.n($0) } ?? J.null, J.str(tempo))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        chiudi()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FoglioNuovaProva: View {
    let soloVoto: Bool
    @Environment(\.dismiss) private var chiudi
    @State private var binario = "accertamento"
    @State private var titolo = ""
    @State private var data = Date()
    @State private var voto: Int? = nil
    @State private var risultato = ""
    @State private var note = ""

    private var dataISO: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        return f.string(from: data)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Tipo", selection: $binario) {
                        Text("Accertamento").tag("accertamento")
                        Text("Esame").tag("esame")
                        Text("Prova fisica").tag("fisica")
                    }
                    .pickerStyle(.segmented)

                    TextField("Materia o prova", text: $titolo)
                        .font(.body)
                        .padding(12)
                        .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    DatePicker("Data", selection: $data, displayedComponents: .date)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text("Voto (opzionale)").font(.footnote).foregroundStyle(Color.secondarioLife)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(18...31, id: \.self) { v in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                voto = voto == v ? nil : v
                            } label: {
                                Text(v == 31 ? "30L" : "\(v)")
                                    .font(.headline).monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .foregroundStyle(voto == v ? Color.black : Color.primary)
                                    .background(voto == v ? coloreVoto(Double(v)) : Color.cartaLife, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if binario == "fisica" {
                        TextField("Tempo o risultato (es. 19:42)", text: $risultato)
                            .padding(12)
                            .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    TextField("Note (opzionale)", text: $note)
                        .padding(12)
                        .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(16)
            }
            .background(Color.sfondoLife)
            .navigationTitle(soloVoto ? "Registra voto" : "Nuova prova")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        rk("crea", J.str(binario), J.str(titolo), J.str(dataISO), voto.map { J.n($0) } ?? J.null, J.str(risultato), J.str(note))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        chiudi()
                    }
                    .disabled(titolo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct FoglioAvanzamento: View {
    let r: J
    @Environment(\.dismiss) private var chiudi
    @State private var quante = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(r.frase.t).font(.subheadline).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center)
                Text("\(quante)").font(.system(size: 64, weight: .bold)).monospacedDigit()
                Text(r.unitaTipo.str ?? "pagine").font(.headline).foregroundStyle(Color.secondarioLife)
                Stepper("Quante", value: $quante, in: 1...300).labelsHidden()
                HStack(spacing: 8) {
                    ForEach([1, 5, 10, 20], id: \.self) { n in
                        Button("+\(n)") { quante = min(300, quante + n) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
                Spacer()
            }
            .padding(20)
            .background(Color.sfondoLife)
            .navigationTitle(r.titolo.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registra") {
                        rk("avanza", J.str(r.id.t), J.n(quante))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        chiudi()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
