import SwiftUI
import Charts

// Rank: come stai andando negli accertamenti, negli esami, nelle prove fisiche e nella corsa.
// I conti sono quelli del sito (moduli/rank e moduli/rank/analisi, nel bundle JS: rank.quadro).
// Qui ci sono solo le schermate. Le prove trovate nel calendario si confermano dal sito.

@discardableResult
private func rk(_ f: String, _ a: J...) -> J { Logica.s.chiama("rank.\(f)", argomenti: a) }
private let gialloRank = Color(hex: "#FFD60A")
private let rossoRank = Color(hex: "#FF453A")
private let verdeRank = Color(hex: "#30D158")
private let nomiBinario: [String: String] = ["accertamento": "Accertamento", "esame": "Esame", "fisica": "Prova fisica"]

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
    return f == 0 ? "oggi" : f == 1 ? "domani" : "\(f) g"
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

struct VistaRank: View {
    init(scheda: String) { self.scheda = scheda }

    @ObservedObject private var logica = Logica.s
    let scheda: String
    @State private var aperta: ProvaAperta?

    var body: some View {
        let _ = logica.versione
        let q = rk("quadro")
        return Pagina {
            if scheda == "prove" {
                elencoProve(q)
            } else {
                quadro(q)
            }
        }
        .navigationTitle(scheda == "prove" ? "Prove" : "Rank")
        .sheet(item: $aperta) { a in FoglioEsito(p: a.p) }
    }

    // MARK: Quadro

    @ViewBuilder
    private func quadro(_ q: J) -> some View {
        prossima(q.inArrivo.list.first)
        if !q.daRegistrare.list.isEmpty {
            Sezione("Da registrare", coda: { Text("\(q.daRegistrare.list.count) senza esito") }) {
                Carta(padding: 6) {
                    ForEach(q.daRegistrare.list, id: \.id) { p in riga(p, registra: true) }
                }
            }
        }
        if !q.corsa.isNull { corsa(q.corsa) }
        if q.ciSonoFisiche.vero {
            pannelloVoti("Prove fisiche", q.fisiche, vuoto: "Registra il voto delle prove fisiche, anche senza il tempo: dal secondo vedi la tendenza.")
        }
        pannelloVoti("Studio", q.studio, vuoto: "Registra i voti degli accertamenti: dal secondo vedi la tendenza.")
        traguardo(q)
        if !q.inArrivo.list.isEmpty {
            Sezione("In arrivo", coda: { Text("\(q.inArrivo.list.count) prove") }) {
                Carta(padding: 6) {
                    ForEach(q.inArrivo.list.prefix(8), id: \.id) { p in riga(p, registra: false) }
                }
            }
        }
    }

    @ViewBuilder
    private func prossima(_ p: J?) -> some View {
        Carta {
            Text("Prossima prova").font(.footnote).foregroundStyle(Color.secondarioLife)
            if let p {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.titolo.t).font(.title2.weight(.bold)).lineLimit(2)
                        Text([nomiBinario[p.binario.t] ?? "", p.giorno.str.map { Tempo.breve($0) } ?? "", p.ora.t].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    Spacer()
                    Text(p.fra.int.map { $0 == 0 ? "oggi" : $0 == 1 ? "domani" : "\($0) giorni" } ?? "")
                        .font(.title.weight(.bold)).monospacedDigit()
                        .foregroundStyle(coloreConto(p.fra.int))
                }
            } else {
                Text("Nessuna prova in arrivo").font(.title3.weight(.semibold))
            }
        }
    }

    private func riga(_ p: J, registra: Bool) -> some View {
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
                .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.titolo.t).font(.subheadline).foregroundStyle(Color.primary).lineLimit(1)
                    Text(nomiBinario[p.binario.t] ?? "").font(.caption).foregroundStyle(Color.secondarioLife)
                }
                Spacer()
                if p.esito.vero {
                    Text(testoVoto(p.voto.int)).font(.headline).monospacedDigit().foregroundStyle(coloreVoto(p.voto.num))
                } else if registra {
                    Text("Registra").font(.subheadline).foregroundStyle(gialloRank)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Corsa

    @ViewBuilder
    private func corsa(_ c: J) -> some View {
        let scarto = c.stima.num.map { $0 - c.obiettivo.d }
        Sezione("Corsa", coda: { Text("\(c.corse.int ?? 0) corse") }) {
            Carta {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                    KpiRank(
                        eti: "Il tuo 5000 oggi",
                        valore: c.stima.num.map(mmss) ?? "—",
                        sotto: scarto.map { $0 <= 0 ? "sotto l'obiettivo di \(mmss(-$0))" : "\(mmss($0)) sopra l'obiettivo \(mmss(c.obiettivo.d))" } ?? "serve una corsa di almeno 2 km",
                        colore: scarto.map { $0 <= 0 ? verdeRank : rossoRank }
                    )
                    KpiRank(
                        eti: "Efficienza aerobica",
                        valore: c.ef.num.map { virgola($0, 2) } ?? "—",
                        sotto: c.efPct.num.map { "\(segno($0))% da quando registri" } ?? "metri al minuto per battito",
                        colore: c.efPct.num.map { $0 >= 1 ? verdeRank : $0 <= -1 ? rossoRank : Color.secondarioLife }
                    )
                    KpiRank(
                        eti: "Forma",
                        valore: segno(c.forma.d, 0),
                        sotto: "fitness \(virgola(c.fitness.d, 0)) (\(segno(c.fitnessDelta.d, 0)) in 2 sett.) · fatica \(virgola(c.fatica.d, 0))",
                        colore: c.fitnessDelta.d < -1 ? rossoRank : c.fitnessDelta.d > 1 ? verdeRank : nil
                    )
                    KpiRank(
                        eti: "Ultima corsa",
                        valore: (c.giorniSenza.int ?? 0) == 0 ? "oggi" : (c.giorniSenza.int ?? 0) == 1 ? "ieri" : "\(c.giorniSenza.int ?? 0) g fa",
                        sotto: "\(virgola(c.ultimaKm.d)) km in \(mmss(c.ultimaSecondi.d))",
                        colore: (c.giorniSenza.int ?? 0) >= 7 ? rossoRank : (c.giorniSenza.int ?? 0) >= 4 ? gialloRank : verdeRank
                    )
                }
                let punti = c.equiv.list
                if punti.count >= 2 {
                    Divider()
                    Text("Il 5000 che vale ogni corsa").font(.subheadline.weight(.semibold))
                    Text("Più in alto = più veloce. La linea tratteggiata è l'obiettivo.").font(.caption).foregroundStyle(Color.secondarioLife)
                    Chart {
                        RuleMark(y: .value("Obiettivo", c.obiettivo.d)).foregroundStyle(verdeRank).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        ForEach(punti.indices, id: \.self) { i in
                            LineMark(x: .value("Corsa", i), y: .value("Secondi", punti[i].t5.d)).foregroundStyle(gialloRank)
                            PointMark(x: .value("Corsa", i), y: .value("Secondi", punti[i].t5.d)).foregroundStyle(gialloRank).symbolSize(28)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing) { v in
                            AxisGridLine()
                            AxisValueLabel {
                                if let s = v.as(Double.self) { Text(mmss(s)).font(.caption2) }
                            }
                        }
                    }
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: Voti

    @ViewBuilder
    private func pannelloVoti(_ titolo: String, _ s: J, vuoto: String) -> some View {
        let voti = s.voti.list
        let ultimo = voti.last
        Sezione(titolo, coda: { Text(voti.count == 1 ? "1 voto" : "\(voti.count) voti") }) {
            Carta {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                    KpiRank(eti: "Ultimo voto", valore: ultimo.map { testoVoto($0.voto.int) } ?? "—", sotto: ultimo?.titolo.t ?? "", colore: nil, coloreValore: ultimo.map { coloreVoto($0.v.num) })
                    KpiRank(eti: "Media", valore: s.media.num.map { virgola($0, 2) } ?? "—", sotto: "su \(voti.count) \(voti.count == 1 ? "prova" : "prove")", colore: nil)
                    KpiRank(
                        eti: "Tendenza",
                        valore: s.pendenza.num.map { segno($0, 2) } ?? "—",
                        sotto: s.pendenza.isNull ? "servono almeno 2 voti" : "punti a prova",
                        colore: s.pendenza.num.map { $0 >= 0.3 ? verdeRank : $0 <= -0.3 ? rossoRank : Color.secondarioLife }
                    )
                    KpiRank(
                        eti: "Contro l'obiettivo",
                        valore: s.scarto.num.map { segno($0) } ?? "—",
                        sotto: s.scarto.isNull ? "metti un obiettivo nelle prove" : "in media",
                        colore: s.scarto.num.map { $0 >= 0 ? verdeRank : rossoRank }
                    )
                }
                if voti.isEmpty {
                    Text(vuoto).font(.footnote).foregroundStyle(Color.secondarioLife)
                } else {
                    Divider()
                    Chart {
                        ForEach(voti.indices, id: \.self) { i in
                            if let r = voti[i].retta.num {
                                LineMark(x: .value("Prova", i), y: .value("Retta", r), series: .value("s", "retta"))
                                    .foregroundStyle(Color.secondary)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            }
                            PointMark(x: .value("Prova", i), y: .value("Voto", voti[i].v.d))
                                .foregroundStyle(coloreVoto(voti[i].v.num))
                                .symbolSize(70)
                        }
                    }
                    .chartYScale(domain: 17...31)
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .trailing, values: [18, 24, 27, 30]) }
                    .frame(height: 150)
                }
            }
        }
    }

    @ViewBuilder
    private func traguardo(_ q: J) -> some View {
        let ob = q.obiettivo.int
        let t = q.traguardo
        let restanti = q.restanti.int ?? 0
        Carta {
            Text("Media a cui voglio chiudere").font(.subheadline.weight(.semibold))
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

    // MARK: Prove

    @ViewBuilder
    private func elencoProve(_ q: J) -> some View {
        if !q.daRegistrare.list.isEmpty {
            Sezione("Da registrare") {
                Carta(padding: 6) { ForEach(q.daRegistrare.list, id: \.id) { p in riga(p, registra: true) } }
            }
        }
        Sezione("In arrivo") {
            Carta(padding: 6) {
                if q.inArrivo.list.isEmpty {
                    Text("Nessuna prova in calendario.").font(.subheadline).foregroundStyle(Color.secondarioLife).padding(10)
                }
                ForEach(q.inArrivo.list, id: \.id) { p in riga(p, registra: false) }
            }
        }
        if !q.fatte.list.isEmpty {
            Sezione("Registrate") {
                Carta(padding: 6) { ForEach(q.fatte.list, id: \.id) { p in riga(p, registra: true) } }
            }
        }
        Text("Le prove trovate nel calendario si confermano da Life sul PC.").font(.footnote).foregroundStyle(Color.secondarioLife).padding(.horizontal, 4)
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

/// L'esito di una prova: il voto (anche per le prove fisiche) e, per le fisiche, il tempo se te lo ricordi.
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
