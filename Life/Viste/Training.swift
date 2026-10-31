import SwiftUI
import UniformTypeIdentifiers

// Training: la settimana del piano, l'andamento, le corse, import e impostazioni.
// Conti e analisi sono quelli di ATLAS, nel bundle JS.

func tra(_ f: String, _ a: J...) -> J { Logica.s.chiama("allenamenti.\(f)", argomenti: a) }
private let accentoTra = Color(hex: "#FF453A")

private func kmT(_ v: J) -> String { tra("calcolo.km", v).t }
private func passoT(_ v: Double) -> String { tra("calcolo.passo", .num(v)).t }
private func mmss(_ v: Double) -> String { tra("calcolo.mmss", .num(v)).t }
private func durataT(_ v: Double) -> String { tra("analisi.durata", .num(v)).t }
private func virgola(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

private func colorFase(_ nome: String) -> Color {
    let n = nome.lowercased()
    if n.contains("ricostr") { return Color(hex: "#30B0C7") }
    if n.contains("svilupp") { return Color(hex: "#FF9500") }
    if n.contains("soglia") { return Color(hex: "#FFCC00") }
    if n.contains("specifico") { return Color(hex: "#FF9500") }
    if n.contains("test") { return Color(hex: "#34C759") }
    return Color(hex: "#5E5CE6")
}

private let nomiGruppi = ["petto": "Petto", "spalle": "Spalle", "bicipiti": "Bicipiti", "avambracci": "Avambracci", "addome": "Addome", "obliqui": "Obliqui", "quadricipiti": "Quadricipiti", "adduttori": "Adduttori", "tibiali": "Tibiali", "trapezio": "Trapezio", "dorsali": "Dorsali", "deltoidiPost": "Deltoidi post.", "tricipiti": "Tricipiti", "lombari": "Lombari", "glutei": "Glutei", "femorali": "Femorali", "polpacci": "Polpacci"]

private func quandoLungo(_ iso: String, _ oggi: String) -> String {
    guard !iso.isEmpty else { return "" }
    let (_, m, d) = Tempo.parti(iso)
    let data = "\(d) \(Tempo.mesiLunghi[max(0, m - 1)].lowercased())"
    let scarto = Tempo.giorniTra(oggi, iso)
    if scarto == 0 { return "oggi, \(data)" }
    if scarto == 1 { return "domani, \(data)" }
    if scarto == -1 { return "ieri, \(data)" }
    return "\(Tempo.settimanaLunga[Tempo.giornoSettimana(iso)]) \(data)"
}

private func quandoCorto(_ iso: String) -> String {
    "\(Tempo.settimanaBreve[Tempo.giornoSettimana(iso)]) \(Tempo.parti(iso).2)"
}

/// Il colore di una zona cardiaca, oppure nil.
private func coloreZona(_ fc: J) -> Color? {
    guard fc.vero, let c = tra("analisi.zonaDi", fc).colore.str else { return nil }
    return Color(hex: c)
}

struct IdTesto: Identifiable {
    let id: String
}

struct VistaTraining: View {
    init(scheda: String) { self.scheda = scheda }

    @ObservedObject private var logica = Logica.s
    let scheda: String
    @State private var settimana: Int = Logica.s.chiama("allenamenti.dati.settimanaCorrente").int ?? 1
    @State private var slot: IdTesto?
    @State private var corsa: IdTesto?
    @State private var importa: IdTesto?
    @State private var bonus = false

    var body: some View {
        let _ = logica.versione
        return Pagina {
            switch scheda {
            case "andamento": andamento
            case "altro": ImpostazioniTraining()
            default:
                striscia
                testataSettimana(settimana)
                contenutoSettimana
            }
        }
        .navigationTitle(scheda == "andamento" ? "Andamento" : scheda == "altro" ? "Altro" : "Training")
        .toolbar {
            Button { importa = IdTesto(id: scheda == "andamento" ? "corse" : "allenamenti") } label: { Image(systemName: "square.and.arrow.down") }
        }
        .sheet(item: $slot) { s in FoglioSlot(id: s.id) }
        .sheet(item: $corsa) { c in FoglioCorsa(id: c.id) }
        .sheet(item: $importa) { i in FoglioImport(quale: i.id) }
        .sheet(isPresented: $bonus) { FoglioBonus(settimana: settimana) }
        .onAppear(perform: ripara)
    }

    private static var riparato = false

    private func ripara() {
        guard !Self.riparato else { return }
        Self.riparato = true
        if tra("dati.riparaGiriComeRipetute").vero {
            avviso("Ho rimesso a posto gli allenamenti che una corsa aveva sovrascritto come «Ripetute».")
        }
        // L'analisi salvata nelle corse (quella che legge anche Claude) si rifà con le regole di adesso
        for c in tra("dati.corseVive").list where tra("analisi.analisiVecchia", c).vero {
            tra("dati.modificaCorsa", c.id, ["analisi": tra("analisi.analizzaCorsa", c)])
        }
    }

    // MARK: La striscia delle settimane

    private var striscia: some View {
        let attuale = tra("dati.settimanaDi", logica.chiama("ui.oggiISO")).int
        return ScrollViewReader { lettore in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tra("dati.PIANO").list, id: \.n) { p in
                        let n = p.n.int ?? 0
                        let pr = tra("calcolo.progressoSettimana", p.n)
                        let c = colorFase(p.fase.t)
                        Button {
                            tocco()
                            settimana = n
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(n)").font(.footnote.weight(n == attuale ? .bold : .regular)).monospacedDigit().foregroundStyle(n == attuale ? accentoTra : Color.secondarioLife)
                                Barra(valore: pr.frazione.d, colore: c, altezza: 4).frame(width: 24)
                            }
                            .frame(width: 40)
                            .padding(.vertical, 6)
                            .background(n == settimana ? Color.cartaLife : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(n)
                    }
                }
            }
            .onAppear { lettore.scrollTo(settimana, anchor: .center) }
            .onChange(of: settimana) { _, v in withAnimation { lettore.scrollTo(v, anchor: .center) } }
        }
    }

    private func testataSettimana(_ n: Int) -> some View {
        let oggi = logica.chiama("ui.oggiISO")
        let num = J.n(n)
        let p = tra("calcolo.progressoSettimana", num)
        let corrente = tra("dati.settimanaDi", oggi).int == n
        let ps = tra("calcolo.passoSettimana", num, oggi).t
        let piano = tra("dati.pianoDi", num)
        let totali = p.totali.int ?? 0
        let aperti = totali - (p.fatti.int ?? 0)
        let giorni = tra("calcolo.giorniRimasti", num, oggi)
        let fatti = tra("calcolo.kmFatti", num)
        let previsti = tra("calcolo.kmPrevisti", num)
        let cons = corrente ? tra("calcolo.consiglio", num, oggi) : J.null
        let daIniziare = oggi.t < tra("dati.inizioSettimana", num).t
        let alTest = Tempo.giorniTra(oggi.t, tra("dati.dataTest").t)
        let coloreFase = colorFase(piano.fase.t)
        let tonoCons: Color = cons.tono.t == "avviso" ? arancioneAvviso : cons.tono.t == "male" ? .pericoloLife : cons.tono.t == "ok" ? .successoLife : .secondarioLife
        return Carta {
            HStack(spacing: 8) {
                Text(tra("dati.FASE").t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(corrente && ps == "persa" ? Color.pericoloLife : corrente && ps == "indietro" ? arancioneAvviso : Color.secondarioLife)
                Text(piano.fase.t).font(.caption).foregroundStyle(coloreFase).padding(.horizontal, 8).padding(.vertical, 2).background(coloreFase.opacity(0.15), in: Capsule())
            }
            HStack {
                Text("Settimana \(n) di \(tra("dati.SETTIMANE").int ?? 0) · \(kmT(fatti)) / \(kmT(previsti))").font(.footnote).foregroundStyle(Color.secondarioLife)
                Spacer()
                if alTest >= 0 {
                    Text(alTest == 0 ? "Test oggi" : alTest == 1 ? "Test domani" : "Test tra \(alTest) giorni").font(.footnote.weight(.semibold)).foregroundStyle(accentoTra)
                }
            }
            Text(aperti == 0 ? "Chiusa" : "\(aperti)").font(.system(size: 40, weight: .semibold)).monospacedDigit().foregroundStyle(aperti == 0 ? Color.successoLife : Color.primary)
            Text(aperti == 0 ? "Tutti e \(totali) gli slot fatti." : daIniziare ? "\(plurale(p.totali, "allenamento", "allenamenti")), da lunedì." : "\(plurale(Double(aperti), "slot aperto", "slot aperti")) su \(totali)" + (corrente ? " · \(plurale(giorni, "giorno", "giorni")) per piazzarli" : "")).font(.footnote).foregroundStyle(Color.secondarioLife)
            Barra(valore: p.frazione.d, colore: p.frazione.d >= 1 ? .successoLife : accentoTra)
            HStack(spacing: 8) {
                casella("\(p.corse.int ?? 0)/\(p.corseTotali.int ?? 0)", "corse")
                casella(p.palestraTotali.vero ? "\(p.palestra.int ?? 0)/\(p.palestraTotali.int ?? 0)" : "—", "palestra")
                casella(kmT(fatti), "su \(kmT(previsti))")
            }
            if !cons.isNull { Label(cons.testo.t, systemImage: "info.circle").font(.footnote).foregroundStyle(tonoCons) }
            if piano.avvertenza.vero { Label(piano.avvertenza.t, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(arancioneAvviso) }
        }
    }

    private func casella(_ v: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(e).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: La settimana

    @ViewBuilder
    private var contenutoSettimana: some View {
        let oggi = logica.chiama("ui.oggiISO").t
        let num = J.n(settimana)
        let corseSett = tra("dati.corseVive").list.filter { tra("dati.settimanaDi", $0.data).int == settimana && !$0.slot.vero && !$0.manuale.vero }
        let corseOggi = corseSett.filter { $0.data.t == oggi }
        let tutti = tra("dati.slotDi", num).list
        var generi = ["corsa", "palestra", "altro"].filter { g in tutti.contains { $0.genere.t == g } || (g == "corsa" && !corseSett.isEmpty) }
        let _ = tutti.forEach { if !generi.contains($0.genere.t) { generi.append($0.genere.t) } }
        let diOggi = tutti.filter { tra("dati.giornoSlot", $0.id).t == oggi }
        let fattiOggi = diOggi.filter { tra("dati.fatto", $0.id).vero }.count
        let aperti = tutti.filter { !tra("dati.fatto", $0.id).vero }
        let senzaGiorno = aperti.filter { !tra("dati.giornoSlot", $0.id).vero }.count
        let daInizio = Tempo.giorniTra(oggi, tra("dati.inizioSettimana", 1).t)

        if settimana == tra("dati.settimanaCorrente").int {
            Blocco(eti: "Oggi", etiDx: diOggi.isEmpty ? nil : "\(fattiOggi)/\(diOggi.count) fatto", tono: (!diOggi.isEmpty && fattiOggi == diOggi.count) || (diOggi.isEmpty && !corseOggi.isEmpty) ? .successoLife : nil) {
                if diOggi.isEmpty && corseOggi.isEmpty {
                    Text(daInizio > 0
                        ? "La fase comincia \(quandoLungo(tra("dati.inizioSettimana", 1).t, oggi)). \(plurale(Double(aperti.count), "allenamento", "allenamenti")) nella prima settimana."
                        : "Niente in programma per oggi. " + (aperti.isEmpty ? "La settimana è chiusa." : "Restano \(plurale(Double(aperti.count), "allenamento", "allenamenti")) questa settimana\(senzaGiorno > 0 ? ", \(senzaGiorno) senza giorno" : "").")).font(.subheadline).foregroundStyle(Color.secondarioLife)
                }
                ForEach(corseOggi, id: \.id) { c in
                    Button { corsa = IdTesto(id: c.id.t) } label: {
                        RigaFin(titolo: c.titolo.str ?? "Corsa", sotto: "\(kmT(c.km))\(c.secondi.vero && c.km.vero ? " · \(passoT(c.secondi.d / c.km.d))" : "")\(c.fc.vero ? " · \(c.fc.int ?? 0) bpm" : "")", freccia: true)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(diOggi, id: \.id) { s in
                    Button { slot = IdTesto(id: s.id.t) } label: {
                        RigaFin(titolo: s.nome.t, sotto: "\(tra("dati.oraDi", s).t) · \(s.lift.vero ? s.lift.t : s.testo.t)", freccia: true).opacity(tra("dati.fatto", s.id).vero ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        ForEach(generi, id: \.self) { g in
            let miei = tutti.filter { $0.genere.t == g }
            let delPiano = miei.filter { !$0.bonus.vero && !$0.riposo.vero }
            let fatti = delPiano.filter { tra("dati.fatto", $0.id).vero }.count
            let bon = miei.filter(\.bonus.vero).count
            Sezione(["corsa": "Corsa", "palestra": "Palestra", "altro": "Altro"][g] ?? g, coda: {
                HStack(spacing: 8) {
                    Text("\(delPiano.isEmpty ? "—" : "\(fatti)/\(delPiano.count)")\(bon > 0 ? " + \(bon) bonus" : "")").monospacedDigit()
                    if g == "palestra" {
                        Button { bonus = true } label: { Image(systemName: "plus") }.tint(accentoTra)
                    }
                }
            }) {
                Carta(padding: 12) {
                    ForEach(miei, id: \.id) { s in rigaSlot(s, oggi) }
                    if g == "corsa" {
                        ForEach(corseSett, id: \.id) { c in rigaCorsaSettimana(c, oggi) }
                    }
                }
            }
        }
    }

    private func rigaCorsaSettimana(_ c: J, _ oggi: String) -> some View {
        Button { corsa = IdTesto(id: c.id.t) } label: {
            HStack(alignment: .top, spacing: 10) {
                Spunta(fatta: true, misura: 26, colore: accentoTra)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(c.titolo.str ?? "Corsa").font(.subheadline.weight(.medium))
                        Text("corsa fatta").font(.caption2).padding(.horizontal, 5).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(quandoLungo(c.data.t, oggi)).font(.caption).foregroundStyle(Color.secondarioLife)
                    Text("\(c.secondi.vero && c.km.vero ? passoT(c.secondi.d / c.km.d) : "—")\(c.fc.vero ? " · FC \(c.fc.int ?? 0)" : "")\(c.metriche.ascesa.vero ? " · +\(Int(c.metriche.ascesa.d)) m" : "")").font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife)
                }
                Spacer(minLength: 4)
                Text(kmT(c.km)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Togli corsa", role: .destructive) {
                tra("dati.eliminaCorsa", c.id)
                avviso("Corsa tolta.")
            }
        }
    }

    @ViewBuilder
    private func rigaSlot(_ s: J, _ oggi: String) -> some View {
        if s.riposo.vero {
            HStack(alignment: .top, spacing: 10) {
                Text("—").foregroundStyle(Color.secondarioLife).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.nome.t).font(.subheadline)
                    Text(s.testo.t).font(.footnote).foregroundStyle(Color.secondarioLife)
                }
            }
            .opacity(0.6)
        } else {
            let id = s.id
            let fatto = tra("dati.fatto", id).vero
            let giorno = tra("dati.giornoSlot", id).t
            let righe: [String] = (s.lift.vero ? [s.lift.t] + s.accessori.list.map(\.t) : s.genere.t == "palestra" ? s.testo.t.components(separatedBy: CharacterSet(charactersIn: "·;")) : []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let gruppi = righe.isEmpty ? [] : tra("muscoli.gruppiSeduta", .arr(righe.map { .str($0) })).list
            let pezzi = s.testo.t.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
            let capo = pezzi.first ?? ""
            let titoloVero: String? = capo.range(of: #"^(TEST\b|\d+ giorni? prima|Giorno prima|Inizio settimana|RIENTRO\b|(Lun|Mar|Mer|Gio|Ven|Sab|Dom)\b)"#, options: [.regularExpression, .caseInsensitive]) != nil ? capo : nil
            let testoSotto = titoloVero != nil ? pezzi.dropFirst().joined(separator: " · ") : s.testo.t
            let tetto = s.chiave.t == "lunga" ? tra("calcolo.tettoLunga", .str(oggi)) : J.null
            let oltre = tetto.vero && s.km.d > tetto.d
            let serie = righe.isEmpty ? 0 : tra("muscoli.serieTotali", .arr(righe.map { .str($0) })).d
            HStack(alignment: .top, spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: fatto ? .light : .medium).impactOccurred()
                    tra("dati.alternaSlot", id)
                } label: { Spunta(fatta: fatto, misura: 26, colore: accentoTra) }.buttonStyle(.plain)
                Button { slot = IdTesto(id: id.t) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(titoloVero ?? s.nome.t).font(.subheadline.weight(.medium)).strikethrough(fatto).lineLimit(2)
                            if titoloVero != nil { etichetta(s.nome.t) }
                            if s.stella.vero { Image(systemName: "scope").font(.caption2).foregroundStyle(accentoTra) }
                            if s.bonus.vero { etichetta("bonus", accentoTra) }
                            if s.cambiato.vero { etichetta(s.aMano.vero ? "cambiato" : "importato") }
                        }
                        if !giorno.isEmpty { Text("\(quandoLungo(giorno, oggi)) · \(tra("dati.oraDi", s).t)").font(.caption).foregroundStyle(Color.secondarioLife) }
                        Text(s.lift.vero ? s.lift.t : testoSotto).font(.footnote).foregroundStyle(Color.secondarioLife)
                        if tetto.vero {
                            Text("Massimo consigliato oggi \(kmT(tetto))\(oltre ? " — oggi il piano chiede di più" : "")").font(.caption).foregroundStyle(oltre ? arancioneAvviso : Color.secondarioLife)
                        }
                        if !gruppi.isEmpty {
                            Text(gruppi.prefix(3).map { nomiGruppi[$0.id.t] ?? $0.id.t }.joined(separator: " · ") + (gruppi.count > 3 ? " +\(gruppi.count - 3)" : "")).font(.caption).foregroundStyle(Color.terziarioLife)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .trailing, spacing: 0) {
                    if serie > 0 {
                        Text(serie == serie.rounded() ? "\(Int(serie))" : String(format: "%.1f", serie)).font(.headline).monospacedDigit()
                        Text("serie").font(.caption2).foregroundStyle(Color.terziarioLife)
                    } else if s.km.vero {
                        Text(kmT(s.km)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(oltre ? arancioneAvviso : Color.primary)
                    }
                }
            }
            .opacity(fatto ? 0.7 : 1)
            .contextMenu {
                Button(fatto ? "Riapri" : "Segna come fatto") { tra("dati.alternaSlot", id) }
                Button("Togli allenamento", role: .destructive) {
                    tra("dati.togliSlot", id)
                    avviso("\(s.nome.t) tolto dalla settimana.")
                }
            }
        }
    }

    private func etichetta(_ t: String, _ c: Color = .secondarioLife) -> some View {
        Text(t).font(.caption2).foregroundStyle(c).padding(.horizontal, 5).background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Andamento

    @ViewBuilder
    private var andamento: some View {
        let righe = tra("calcolo.andamento").list
        let massimo = max(1, righe.map { max($0.previsti.d, $0.fatti.d) }.max() ?? 1)
        let pr = tra("calcolo.proiezione")
        let ob = tra("dati.OBIETTIVO")
        let corse = Array(tra("dati.corseVive").list.suffix(12).reversed())
        let totale = righe.reduce(0) { $0 + $1.fatti.d }
        let sempre = tra("calcolo.kmTotali").d
        Sezione("Proiezione sui 5 km", coda: { Text("obiettivo \(mmss(ob.secondi.d))") }) {
            Carta {
                if pr.isNull {
                    Text("—").font(.largeTitle).foregroundStyle(Color.secondarioLife)
                    Text("Serve una prova A TUTTA (un test o una gara) sopra i 3 km, nelle ultime sei settimane. Una corsa col nome «test» o «gara» vale da sola; le altre le segni nella loro scheda («Prova a tutta»).").font(.footnote).foregroundStyle(Color.secondarioLife)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(mmss(pr.secondi.d)).font(.system(size: 40, weight: .semibold)).monospacedDigit().foregroundStyle(pr.dentro.vero ? Color.successoLife : Color.primary)
                        Text(passoT(pr.passo.d)).font(.subheadline).foregroundStyle(Color.secondarioLife)
                    }
                    Text(pr.dentro.vero ? "Sei dentro il muro di \(mmss(ob.secondi.d))." : "Mancano \(mmss(pr.scarto.d)) a \(mmss(ob.secondi.d)).").font(.subheadline)
                    Text("Da \(kmT(pr.da.km)) in \(mmss(pr.da.secondi.d)) del \(dataBreve(pr.da.data.t)), portati sui 5 km con la formula di Riegel.").font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
        }
        Sezione("Chilometri per settimana", coda: { Text("\(kmT(.num(totale))) nel blocco") }) {
            Carta {
                ForEach(righe, id: \.n) { r in
                    let c = colorFase(r.fase.t)
                    HStack(spacing: 8) {
                        Text("\(r.n.int ?? 0)").font(.caption.weight(r.corrente.vero ? .bold : .regular)).monospacedDigit().foregroundStyle(r.corrente.vero ? accentoTra : Color.secondarioLife).frame(width: 22, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                                Capsule().fill(c.opacity(0.28)).frame(width: g.size.width * CGFloat(r.previsti.d / massimo))
                                Capsule().fill(r.sopraIlTetto.vero ? arancioneAvviso : c).frame(width: g.size.width * CGFloat(r.fatti.d / massimo))
                            }
                        }
                        .frame(height: 12)
                        Text(r.fatti.d > 0 ? kmT(r.fatti).replacingOccurrences(of: " km", with: "") : "—").font(.caption).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                HStack(spacing: 12) {
                    leggenda(accentoTra.opacity(0.28), "piano")
                    leggenda(accentoTra, "fatto")
                    leggenda(arancioneAvviso, "oltre il +10%")
                }
                if sempre > totale { Text("In tutto, da quando registri: \(kmT(.num(sempre))).").font(.caption).foregroundStyle(Color.secondarioLife) }
            }
        }
        Sezione("Corse") {
            if corse.isEmpty {
                Text("Nessuna. Senza corse non c'è né andamento né previsione: importa l'export di Garmin, o scrivi a mano quello che hai fatto dallo slot.").font(.footnote).foregroundStyle(Color.secondarioLife)
            } else {
                Carta(padding: 12) {
                    ForEach(corse, id: \.id) { c in rigaCorsa(c, ob) }
                }
            }
        }
    }

    private func leggenda(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 8)
            Text(t).font(.caption2).foregroundStyle(Color.secondarioLife)
        }
    }

    private func rigaCorsa(_ c: J, _ ob: J) -> some View {
        let spezzata = c.giri.list.count > 1
        let eq = tra("analisi.eATutta", c).vero && c.giri.list.isEmpty ? tra("calcolo.equivalente5k", c) : J.null
        let fc = c.metriche.fc.vero ? c.metriche.fc : c.fc
        return Button { corsa = IdTesto(id: c.id.t) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.titolo.str ?? c.nome.str ?? "Corsa").font(.subheadline)
                    (Text("\(dataBreve(c.data.t)) · \(c.secondi.vero && c.km.vero ? passoT(c.secondi.d / c.km.d) : "—")\(spezzata ? " sui pezzi" : "") · \(kmT(c.km))") + (fc.vero ? Text(" · \(Int(fc.d)) bpm").foregroundColor(coloreZona(fc) ?? Color.secondarioLife) : Text("")) + Text(c.manuale.vero ? " · a mano" : ""))
                        .font(.footnote)
                        .foregroundStyle(Color.secondarioLife)
                    if spezzata { Text(tra("calcolo.descriviPezzi", c.giri).t).font(.caption).foregroundStyle(Color.secondarioLife) }
                }
                Spacer(minLength: 6)
                if !eq.isNull {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(mmss(eq.d)).font(.subheadline).monospacedDigit().foregroundStyle(eq.d <= ob.secondi.d ? Color.successoLife : Color.primary)
                        Text("sui 5 km").font(.caption2).foregroundStyle(Color.secondarioLife)
                    }
                } else {
                    Text(kmT(c.km)).font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.terziarioLife)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Togli corsa", role: .destructive) {
                tra("dati.eliminaCorsa", c.id)
                avviso("Corsa tolta.")
            }
        }
    }
}

// MARK: - La corsa

struct SchedaCorsa: View {
    let c: J
    var cambia: (([String: J]) -> Void)? = nil
    @State private var recupero = ""

    private let gruppi: [(String, [String])] = [
        ("Ritmo", ["passoMovimento", "passoRegolato", "passoMigliore", "tempoMovimento"]),
        ("Cuore", ["fc", "fcMax"]),
        ("Potenza", ["potenza", "potenzaMax", "wkg", "wkgMax"]),
        ("Tecnica di corsa", ["cadenza", "cadenzaMax", "lunghezzaPasso", "contatto", "bilanciamento", "oscillazione", "rapportoVerticale", "perditaVelocita", "perditaVelocitaPerc"]),
        ("Dislivello ed energia", ["ascesa", "discesa", "calorie", "temperatura"]),
    ]
    private let sensazioni = ["Facilissima", "Facile", "Giusta", "Dura", "Durissima"]

    var body: some View {
        let m = c.metriche
        let lap = c.lap.list
        let a = tra("analisi.analizzaCorsa", c)
        let dubbi = Set(a.fcDubbia.list.compactMap(\.int))
        let tempo = c.secondi.vero ? c.secondi.d : m.tempo.d
        let passo = m.passo.vero ? m.passo.d : (tempo > 0 && c.km.vero ? tempo / c.km.d : 0)
        let fc = a.fcAffidabile.vero ? a.fcAffidabile : m.fc.vero ? m.fc : c.fc
        let z = tra("analisi.zonaDi", fc)
        let ripetute = a.tipo.t == "ripetute"

        return VStack(alignment: .leading, spacing: 14) {
            if let cambia {
                Carta {
                    TextField("Titolo (es. Lenta Z2 al parco)", text: Binding(get: { c.titolo.t }, set: { cambia(["titolo": .str($0)]) })).font(.headline)
                    DatePicker("Giorno", selection: Binding(get: { Tempo.istante(c.data.t, "12:00") }, set: { cambia(["data": .str(Tempo.dataRoma($0))]) }), in: ...Date(), displayedComponents: .date)
                    if c.dataSupposta.vero { Text("Il file non ha la data: controllala.").font(.caption).foregroundStyle(arancioneAvviso) }
                    if ripetute {
                        HStack {
                            Text("Recupero fra le ripetute")
                            TextField("2:00", text: $recupero)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    let v = recupero.trimmingCharacters(in: .whitespaces)
                                    let p = v.components(separatedBy: CharacterSet(charactersIn: ":.,")).map { Int($0) }
                                    var sec = 0
                                    if p.count == 2, let x = p[0], let y = p[1] {
                                        sec = x * 60 + y
                                    } else if p.count == 1, let x = p[0] {
                                        sec = x <= 10 ? x * 60 : x
                                    }
                                    cambia(["recupero": sec > 0 ? .n(sec) : nil])
                                }
                        }
                        Text("Non è nei file: l'orologio era fermo.").font(.caption).foregroundStyle(Color.secondarioLife)
                    } else {
                        Toggle("Prova a tutta (test o gara)", isOn: Binding(get: { tra("analisi.eATutta", c).vero }, set: { cambia(["aTutta": .bool($0)]) }))
                        Text("Solo così vale il tempo sui 5 km.").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                }
                .environment(\.timeZone, Tempo.roma)
                .onAppear { if recupero.isEmpty, c.recupero.vero { recupero = mmss(c.recupero.d) } }
            }
            Carta {
                if cambia == nil { Text(dataUmana(c.data.t)).font(.footnote).foregroundStyle(Color.secondarioLife) }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(virgola(c.km.d)).font(.system(size: 44, weight: .semibold)).monospacedDigit()
                    Text("km").font(.title3).foregroundStyle(Color.secondarioLife)
                }
                HStack {
                    Dato(etichetta: "Tempo", valore: durataT(tempo))
                    Dato(etichetta: "Passo medio", valore: passo > 0 ? "\(mmss(passo))/km" : "—")
                    Dato(etichetta: dubbi.isEmpty ? "FC media" : "FC attendibile", valore: fc.vero ? "\(Int(fc.d.rounded())) bpm" : "—", colore: z.colore.str.map { Color(hex: $0) })
                }
                if !z.isNull || a.equivalente5k.vero {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let col = z.colore.str { chip(z.nome.t, Color(hex: col)) }
                            if a.equivalente5k.vero { chip("vale \(mmss(a.equivalente5k.d)) sui 5 km", .secondary) }
                            if a.efficienza.vero { chip("\(a.efficienza.t.replacingOccurrences(of: ".", with: ",")) m/battito", .secondary) }
                        }
                    }
                }
            }
            if c.tracce.list.count > 1 {
                Sezione(ripetute ? "\(a.ripetute.list.count) ripetute" : "Sessione in \(c.tracce.list.count) tracce", coda: { Text(ripetute ? "media \(mmss(a.mediaRipetute.d))/km · scarto \(a.scarto.t) s/km" : "le pause non contano") }) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(c.tracce.list, id: \.n) { t in traccia(t, a, ripetute) }
                    }
                }
            }
            if !a.frasi.list.isEmpty {
                Sezione("Cosa dice la corsa") {
                    Carta {
                        ForEach(a.frasi.list, id: \.self) { f in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(accentoTra).frame(width: 6, height: 6).padding(.top, 6)
                                Text(f.t).font(.subheadline)
                            }
                        }
                    }
                }
            }
            if lap.count > 1 {
                Sezione("Giri", coda: { Text("colore = zona cardiaca") }) {
                    Carta {
                        graficoGiri(lap, dubbi)
                        tabellaGiri(lap, dubbi)
                    }
                }
            }
            ForEach(gruppi, id: \.0) { g in
                let presenti = g.1.filter { !m[$0].isNull }
                if !presenti.isEmpty {
                    Sezione(g.0) {
                        Carta {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                ForEach(presenti, id: \.self) { k in
                                    let d = tra("dato", .str(k), m[k])
                                    if !d.isNull {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(d.nome.t).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
                                            (Text(d.valore.t).font(.title3.weight(.semibold)).monospacedDigit() + Text(d.unita.vero ? " \(d.unita.t)" : "").font(.caption).foregroundColor(Color.secondarioLife))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let cambia {
                Sezione("Com'è andata") {
                    Carta {
                        HStack(spacing: 4) {
                            ForEach(sensazioni.indices, id: \.self) { i in
                                Button {
                                    tocco()
                                    cambia(["sensazione": c.sensazione.int == i + 1 ? nil : .n(i + 1)])
                                } label: {
                                    Text(sensazioni[i]).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).frame(height: 34)
                                        .foregroundStyle(c.sensazione.int == i + 1 ? Color.white : Color.secondarioLife)
                                        .background(c.sensazione.int == i + 1 ? accentoTra : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        TextField("Note: com'eri messo, gambe, caldo, percorso…", text: Binding(get: { c.note.t }, set: { cambia(["note": .str($0)]) }), axis: .vertical).lineLimit(2...6)
                    }
                }
            } else if c.sensazione.vero || c.note.vero {
                Sezione("Com'è andata") {
                    Carta {
                        if let i = c.sensazione.int, sensazioni.indices.contains(i - 1) { Text(sensazioni[i - 1]).font(.subheadline.weight(.semibold)) }
                        if c.note.vero { Text(c.note.t).font(.subheadline) }
                    }
                }
            }
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption).monospacedDigit().foregroundStyle(c == .secondary ? Color.primary : c).padding(.horizontal, 8).frame(height: 24).background(c.opacity(0.16), in: Capsule())
    }

    private func traccia(_ t: J, _ a: J, _ ripetute: Bool) -> some View {
        let tm = t.metriche
        let rip = a.ripetute.list
        let r = ripetute ? rip.first { $0.n == t.n } : nil
        let fcT = ripetute ? (r?.fc ?? .null) : tm.fc
        let nome = ripetute ? (r != nil ? "Ripetuta \((rip.firstIndex { $0.n == t.n } ?? 0) + 1)" : t.n.int == 1 ? "Riscaldamento" : "Defaticamento") : "Traccia \(t.n.int ?? 0)"
        return Carta(padding: 12) {
            Text(nome).font(.caption.weight(.semibold)).foregroundStyle(Color.secondarioLife)
            (Text(virgola(t.km.d)).font(.title3.weight(.semibold)).monospacedDigit() + Text(" km").font(.caption).foregroundColor(Color.secondarioLife))
            Text("\(durataT(t.secondi.d))\(t.km.vero && t.secondi.vero ? " · \(mmss(t.secondi.d / t.km.d))/km" : "")").font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife)
            if fcT.vero {
                Text("FC \(Int(fcT.d.rounded()))\(!ripetute && tm.fcMax.vero ? " · max \(Int(tm.fcMax.d))" : "")").font(.caption).monospacedDigit().foregroundStyle(coloreZona(fcT) ?? Color.primary)
            } else if ripetute {
                Text("FC non affidabile").font(.caption).foregroundStyle(Color.terziarioLife)
            }
        }
        .opacity(ripetute && r == nil ? 0.7 : 1)
    }

    private func graficoGiri(_ lap: [J], _ dubbi: Set<Int>) -> some View {
        let conPasso = lap.filter { $0.passo.vero || ($0.tempo.vero && $0.km.vero) }
        let passoDi: (J) -> Double = { $0.passo.vero ? $0.passo.d : $0.tempo.d / max(0.001, $0.km.d) }
        let vel = conPasso.map { 1000 / max(1, passoDi($0)) }
        let basso = (vel.min() ?? 0) * 0.92
        let alto = vel.max() ?? 1
        return GeometryReader { g in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(conPasso.indices, id: \.self) { i in
                    let giro = conPasso[i]
                    let zona = dubbi.contains(giro.n.int ?? -1) ? nil : coloreZona(giro.fc)
                    let h = 0.18 + (vel[i] - basso) / max(0.0001, alto - basso) * 0.82
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4).fill(zona ?? Color(uiColor: .systemGray4)).frame(height: max(6, (g.size.height - 16) * CGFloat(h)))
                        Text("\(giro.n.int ?? 0)").font(.system(size: 9)).monospacedDigit().foregroundStyle(Color.secondarioLife).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 110)
    }

    private func tabellaGiri(_ lap: [J], _ dubbi: Set<Int>) -> some View {
        let colonne = [("km", "Km"), ("tempo", "Tempo"), ("passo", "Passo"), ("fc", "FC"), ("fcMax", "Max"), ("potenza", "W"), ("cadenza", "Cad."), ("ascesa", "↑ m")].filter { k in lap.contains { !$0[k.0].isNull } }
        let scrivi: (String, J) -> String = { k, v in
            guard !v.isNull else { return "—" }
            switch k {
            case "tempo": return durataT(v.d)
            case "passo": return mmss(v.d)
            case "km": return virgola(v.d)
            default: return "\(Int(v.d.rounded()))"
            }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Giro").gridColumnAlignment(.leading)
                    ForEach(colonne, id: \.0) { Text($0.1) }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondarioLife)
                ForEach(lap.indices, id: \.self) { i in
                    let g = lap[i]
                    let dubbia = dubbi.contains(g.n.int ?? -1)
                    GridRow {
                        HStack(spacing: 4) {
                            Circle().fill((dubbia ? nil : coloreZona(g.fc)) ?? Color(uiColor: .systemGray4)).frame(width: 7, height: 7)
                            Text("\(g.n.int ?? 0)\(g.traccia.vero && i > 0 && lap[i - 1].traccia != g.traccia ? " ·" : "")")
                        }
                        ForEach(colonne, id: \.0) { k in
                            HStack(spacing: 1) {
                                if dubbia, k.0 == "fc" { Text("⚠").foregroundStyle(arancioneAvviso) }
                                Text(scrivi(k.0, g[k.0])).foregroundStyle(dubbia && (k.0 == "fc" || k.0 == "fcMax") ? Color.terziarioLife : Color.primary)
                            }
                        }
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
        }
    }
}

struct FoglioCorsa: View {
    let id: String
    @ObservedObject private var logica = Logica.s
    @State private var quale = ""
    @State private var bozza: [String: J] = [:]
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let _ = logica.versione
        let cerca = quale.isEmpty ? id : quale
        let salvata = tra("dati.corseVive").list.first { $0.id.t == cerca } ?? .null
        var c = salvata
        for (k, v) in bozza { c[k] = v }
        return NavigationStack {
            Group {
                if salvata.isNull {
                    Text("Corsa non trovata").foregroundStyle(Color.secondarioLife)
                } else {
                    Pagina {
                        SchedaCorsa(c: c) { p in cambia(p, salvata, c) }
                        Button(role: .destructive) {
                            tra("dati.eliminaCorsa", salvata.id)
                            avviso("Corsa tolta.")
                            chiudi()
                        } label: { Text("Togli questa corsa").frame(maxWidth: .infinity) }
                    }
                }
            }
            .navigationTitle(c.titolo.str ?? "Corsa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        salva(salvata)
                        chiudi()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear { salva(salvata) }
        }
    }

    /// Titolo e note si scrivono qui e si salvano alla chiusura (non a ogni tasto).
    private func cambia(_ p: [String: J], _ salvata: J, _ c: J) {
        if p["titolo"] != nil || p["note"] != nil {
            for (k, v) in p { bozza[k] = v }
            return
        }
        var nuova = c
        for (k, v) in p { nuova[k] = v }
        var modifica = p
        modifica["analisi"] = tra("analisi.analizzaCorsa", nuova)
        let nuovoId = tra("dati.modificaCorsa", salvata.id, .obj(modifica))
        if let n = nuovoId.str, n != salvata.id.t { quale = n }
    }

    private func salva(_ salvata: J) {
        guard !bozza.isEmpty, !salvata.isNull else { return }
        var m = bozza
        let t = (bozza["titolo"]?.t ?? salvata.titolo.t).trimmingCharacters(in: .whitespaces)
        m["titolo"] = .str(t.isEmpty ? "Corsa" : t)
        tra("dati.modificaCorsa", salvata.id, .obj(m))
        bozza = [:]
    }
}

/// Prima di salvare: la corsa letta dai file, da controllare e completare.
struct AnteprimaCorsa: View {
    @State var lista: [J]
    let fatto: () -> Void
    let annulla: () -> Void
    @State private var mie: [String: J] = [:]
    @State private var conSalvata = true
    @State private var aggiungi = false

    var body: some View {
        let giorno = mie["data"]?.str ?? lista.first?.data.str ?? Logica.s.chiama("ui.oggiISO").t
        let salvata = tra("dati.corseVive").list.first { $0.data.t == giorno && !$0.manuale.vero && ($0.lap.vero || $0.metriche.vero) }
        let unisci = salvata != nil && conSalvata
        let conGiorno: [J] = lista.map { t in
            var x = t
            x["data"] = .str(giorno)
            return x
        }
        let sessione = tra("importa.unisciTracce", .arr((unisci ? [salvata!] : []) + conGiorno))
        var c = sessione
        for (k, v) in mie { c[k] = v }
        c["data"] = .str(giorno)
        if mie["data"] != nil { c["dataSupposta"] = false }
        return Pagina {
            Sezione(lista.count + (unisci ? 1 : 0) > 1 ? "Tracce della sessione" : "Traccia", coda: { Text("nell'ordine in cui le hai corse") }) {
                Carta(padding: 12) {
                    if unisci, let salvata {
                        Text("↺ \(salvata.titolo.str ?? "Corsa") già salvata · \(virgola(salvata.km.d)) km").font(.footnote)
                    }
                    ForEach(lista.indices, id: \.self) { i in
                        let t = lista[i]
                        HStack(spacing: 8) {
                            Text("\(i + 1 + (unisci ? 1 : 0))").font(.caption.weight(.semibold)).frame(width: 24, height: 24).background(Color(uiColor: .tertiarySystemFill), in: Circle())
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(virgola(t.km.d)) km · \(durataT(t.secondi.d))\(t.km.vero && t.secondi.vero ? " · \(mmss(t.secondi.d / t.km.d))/km" : "")\(t.metriche.fc.vero ? " · FC \(Int(t.metriche.fc.d))" : "")").font(.footnote).monospacedDigit()
                                if t.file.vero { Text(t.file.t).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1) }
                            }
                            Spacer()
                            Button { lista.swapAt(i, i - 1) } label: { Image(systemName: "arrow.up") }.disabled(i == 0)
                            Button { lista.swapAt(i, i + 1) } label: { Image(systemName: "arrow.down") }.disabled(i == lista.count - 1)
                            Button { lista.remove(at: i) } label: { Image(systemName: "xmark") }.disabled(lista.count == 1)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    Button { aggiungi = true } label: { Label("Aggiungi un'altra traccia della stessa sessione", systemImage: "plus").font(.footnote) }
                    if let salvata {
                        Toggle("Fa parte della corsa già salvata di questo giorno (\(salvata.titolo.str ?? "Corsa"), \(virgola(salvata.km.d)) km)", isOn: $conSalvata).font(.footnote)
                    }
                }
            }
            SchedaCorsa(c: c) { p in
                for (k, v) in p { mie[k] = v }
            }
            HStack(spacing: 8) {
                PulsantePieno(testo: "Annulla", colore: Color(uiColor: .systemGray), azione: annulla)
                PulsantePieno(testo: unisci ? "Unisci e salva" : "Salva la corsa", colore: accentoTra) { salva(c, salvata: unisci ? salvata : nil) }
            }
        }
        .fileImporter(isPresented: $aggiungi, allowedContentTypes: [.commaSeparatedText, .plainText, .text], allowsMultipleSelection: true) { esito in
            guard let urls = try? esito.get() else { return }
            let (tracce, altri) = leggiTracce(urls)
            lista += tracce
            if !altri.isEmpty { avviso("\(altri.joined(separator: ", ")): non è il file dei giri di una corsa.", errore: true) }
        }
    }

    private func salva(_ c: J, salvata: J?) {
        if let salvata { tra("dati.eliminaCorsa", salvata.id) }
        var r = c
        let t = c.titolo.t.trimmingCharacters(in: .whitespaces)
        r["titolo"] = .str(t.isEmpty ? "Corsa" : t)
        if case .obj(var o) = r {
            o["dataSupposta"] = nil
            o["file"] = nil
            o["analisi"] = nil
            r = .obj(o)
        }
        r["analisi"] = tra("analisi.analizzaCorsa", c)
        tra("dati.salvaCorse", [r])
        let n = c.tracce.list.count
        avviso("Corsa salvata: \(virgola(c.km.d)) km del \(dataUmana(c.data.t))\(n > 1 ? ", in \(n) tracce" : "").")
        fatto()
    }
}

/// I file scelti → le tracce (solo i file dei giri), nell'ordine in cui le hai corse.
func leggiTracce(_ urls: [URL]) -> ([J], [String]) {
    var tracce: [J] = []
    var altri: [String] = []
    for u in urls {
        let accesso = u.startAccessingSecurityScopedResource()
        defer { if accesso { u.stopAccessingSecurityScopedResource() } }
        let nome = u.lastPathComponent
        guard let testo = try? String(contentsOf: u, encoding: .utf8) else {
            altri.append(nome)
            continue
        }
        let r = tra("importa.corseDaCSV", .str(testo))
        if r.daGiri.vero, var c = r.corse.list.first {
            c["file"] = .str(nome)
            tracce.append(c)
        } else {
            altri.append(nome)
        }
    }
    tracce.sort { tra("importa.ordinePerNome", $0.file).d < tra("importa.ordinePerNome", $1.file).d }
    return (tracce, altri)
}

// MARK: - Lo slot

struct FoglioSlot: View {
    let id: String
    @ObservedObject private var logica = Logica.s
    @State private var cambio = false
    @State private var cNome = ""
    @State private var cTesto = ""
    @State private var cGenere = "altro"
    @State private var cDurata = ""
    @State private var pezzi: [Pezzo] = [Pezzo()]
    @State private var unisci = false
    @State private var conflitto: (String, [String])?
    @State private var creo = false
    @State private var scelto: Int?
    @State private var fit: FileCondiviso?
    @Environment(\.dismiss) private var chiudi

    struct Pezzo: Identifiable {
        let id = UUID()
        var dist = ""
        var tempo = ""
    }

    private func aKm(_ t: String) -> Double {
        let n = Double(t.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
        guard n > 0 else { return 0 }
        return n >= 80 ? n.rounded() / 1000 : (n * 1000).rounded() / 1000
    }

    private func aSecondi(_ t: String) -> Double {
        let p = t.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard !p.isEmpty, !p.contains(where: { $0 == nil }) else { return 0 }
        let v = p.compactMap { $0 }
        if v.count == 1 { return (v[0] * 60).rounded() }
        if v.count == 2 { return (v[0] * 60 + v[1]).rounded() }
        return (v[0] * 3600 + v[1] * 60 + v[2]).rounded()
    }

    var body: some View {
        let _ = logica.versione
        let n = Int(id.dropFirst(1).prefix(2)) ?? 0
        let s = tra("dati.slotDi", .n(n)).list.first { $0.id.t == id } ?? .null
        return NavigationStack {
            Group {
                if s.isNull {
                    Text("Allenamento non trovato").foregroundStyle(Color.secondarioLife)
                } else {
                    contenuto(s)
                }
            }
            .navigationTitle(s.nome.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { chiudi() } } }
        }
        .sheet(item: $fit) { f in CondividiFile(url: f.url) }
    }

    private func contenuto(_ s: J) -> some View {
        let sid = J.str(id)
        let f = tra("dati.fatto", sid).vero
        let giorno = tra("dati.giornoSlot", sid).t
        let rec = tra("dati.recordSlot", sid)
        let coperto = rec.testo.vero
        let righe: [String] = s.genere.t == "palestra" ? (s.lift.vero ? [s.lift.t] + s.accessori.list.map(\.t) : s.testo.t.components(separatedBy: CharacterSet(charactersIn: "·;"))).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : []
        let righeJ = J.arr(righe.map { .str($0) })
        let esercizi = righe.enumerated().map { i, r -> J in
            var e = tra("muscoli.leggiRiga", .str(r))
            e["principale"] = .bool(i == 0 && s.lift.vero)
            return e
        }
        let gruppi = righe.isEmpty ? [] : tra("muscoli.gruppiSeduta", righeJ).list
        let letto = s.genere.t == "corsa" ? tra("passi.leggiAllenamento", s.testo) : J.null
        return Pagina {
            if righe.isEmpty {
                Carta {
                    Text(s.testo.t).font(.subheadline)
                    if s.km.vero { Text("Circa \(kmT(s.km)) nel conteggio della settimana.").font(.caption).foregroundStyle(Color.secondarioLife) }
                }
            } else {
                seduta(s, esercizi, gruppi, righeJ)
            }
            PulsantePieno(testo: f ? "Riapri lo slot" : "Segna come fatto", colore: f ? Color(uiColor: .systemGray) : accentoTra, icona: f ? nil : "checkmark") {
                tra("dati.alternaSlot", sid)
                chiudi()
            }
            if cambio {
                formCambio(s, f: f, giorno: giorno)
            } else {
                Button(s.cambiato.vero && s.aMano.vero ? "Cambia di nuovo" : "Ho fatto un altro allenamento") { prepara(s, rec) }.frame(maxWidth: .infinity).font(.subheadline)
            }
            quando(s, giorno: giorno, rec: rec)
            if s.genere.t == "corsa", !letto.isNull {
                garmin(s, letto)
            } else if s.genere.t == "palestra" {
                hevyVista(s, righeJ)
            }
            if coperto, !cambio {
                Button("Rimetti il piano originale") {
                    tra("dati.ripristinaSlot", sid)
                    avviso("Rimesso il piano.")
                }
                .frame(maxWidth: .infinity)
                .font(.subheadline)
                Text("Torna la seduta scritta nel piano. La spunta e il giorno restano\(s.aMano.vero ? ", e la corsa a mano sparisce dai conti" : "").").font(.caption).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            if s.bonus.vero {
                Button("Togli questo allenamento", role: .destructive) {
                    tra("dati.togliBonus", sid)
                    avviso("Allenamento tolto.")
                    chiudi()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func seduta(_ s: J, _ esercizi: [J], _ gruppi: [J], _ righe: J) -> some View {
        let serie = tra("muscoli.serieTotali", righe).d
        let massimo = gruppi.first?.serie.d ?? 1
        let primari: [String] = scelto.map { esercizi[$0].primari.list.map(\.t) } ?? gruppi.filter { $0.serie.d >= massimo * 0.34 }.map(\.id.t)
        let secondari: [String] = scelto.map { esercizi[$0].secondari.list.map(\.t) } ?? gruppi.filter { $0.serie.d < massimo * 0.34 }.map(\.id.t)
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settimana \(s.sett.int ?? 0)").font(.caption).foregroundStyle(Color.secondarioLife)
                Text(serie == serie.rounded() ? "\(Int(serie))" : String(format: "%.1f", serie)).font(.system(size: 40, weight: .semibold)).monospacedDigit().foregroundStyle(accentoTra)
                Text("serie · \(plurale(Double(esercizi.count), "esercizio", "esercizi"))").font(.footnote).foregroundStyle(Color.secondarioLife)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(gruppi.prefix(4), id: \.id) { g in
                    Text("\(nomiGruppi[g.id.t] ?? g.id.t) \(g.serie.d == g.serie.d.rounded() ? "\(Int(g.serie.d))" : String(format: "%.1f", g.serie.d))").font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }
        }
        Sezione("Dove arriva") {
            Carta {
                CorpoMuscoli(primari: Set(primari), secondari: Set(secondari), colore: accentoTra).frame(maxWidth: .infinity).frame(height: 260)
            }
        }
        Text(scelto == nil ? "Pieno: il lavoro grosso. A metà: quello che partecipa. Tocca un esercizio qui sotto per vedere solo il suo." : "Solo \(esercizi[scelto!].nome.t). Tocca di nuovo per tornare a tutta la seduta.").font(.caption).foregroundStyle(Color.secondarioLife)
        Sezione("La seduta") {
            Carta(padding: 12) {
                ForEach(esercizi.indices, id: \.self) { i in
                    let e = esercizi[i]
                    Button {
                        tocco()
                        scelto = scelto == i ? nil : i
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(e.nome.t).font(.subheadline)
                                    if e.principale.vero { Text("principale").font(.caption2).padding(.horizontal, 5).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4)) }
                                }
                                let g = e.primari.list.map { nomiGruppi[$0.t] ?? $0.t } + e.secondari.list.map { "(\(nomiGruppi[$0.t] ?? $0.t))" }
                                if !g.isEmpty { Text(g.joined(separator: " · ")).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1) }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(e.serie.vero ? "\(e.serie.t)×\(e.ripetizioni.t)" : "—").font(.subheadline.weight(.medium)).monospacedDigit()
                                if e.carico.vero { Text(e.carico.t).font(.caption).foregroundStyle(Color.secondarioLife) }
                            }
                        }
                        .padding(.vertical, 3)
                        .background(scelto == i ? accentoTra.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func prepara(_ s: J, _ r: J) {
        cambio = true
        unisci = false
        cNome = r.nome.t
        cTesto = r.cambiato.vero ? r.testo.t : ""
        cGenere = r.genere.str ?? s.genere.t
        cDurata = r.durata.vero ? r.durata.t : ""
        let giri = r.cambiato.vero ? r.giri.list : []
        if giri.isEmpty {
            pezzi = [Pezzo(dist: r.cambiato.vero && r.km.vero ? r.km.t.replacingOccurrences(of: ".", with: ",") : "")]
        } else {
            pezzi = giri.map(pezzoDa)
        }
    }

    private func pezzoDa(_ g: J) -> Pezzo {
        Pezzo(dist: g.km.d < 1 ? "\(Int((g.km.d * 1000).rounded()))" : g.km.t.replacingOccurrences(of: ".", with: ","), tempo: g.secondi.vero ? mmss(g.secondi.d) : "")
    }

    @ViewBuilder
    private func formCambio(_ s: J, f: Bool, giorno: String) -> some View {
        let letti: [(km: Double, sec: Double, passo: Double)] = pezzi.map { p in
            let k = aKm(p.dist)
            let sec = aSecondi(p.tempo)
            return (k, sec, k > 0 && sec > 0 ? sec / k : 0)
        }
        let totKm = (letti.reduce(0) { $0 + $1.km } * 100).rounded() / 100
        let totSec = letti.reduce(0) { $0 + $1.sec }
        let corseDelDi = tra("dati.sedutaDelGiorno", .str(giorno.isEmpty ? Logica.s.chiama("ui.oggiISO").t : giorno))
        let alternative: [J] = tra("dati.slotDi", s.sett).list.filter { $0.id != s.id && !$0.bonus.vero && !$0.riposo.vero }.map { x in
            ["id": x.id, "nome": x.nome, "genere": x.genere, "corpo": .str(x.lift.vero ? ([x.lift.t] + x.accessori.list.map(\.t)).joined(separator: " · ") : x.testo.t), "km": x.km]
        } + [["id": "upperB", "nome": tra("dati.UPPER_B").nome, "genere": "palestra", "corpo": tra("dati.UPPER_B").testo, "km": 0]]
        Sezione("Cosa hai fatto davvero") {
            Carta {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(alternative, id: \.id) { a in
                            Pillola(testo: a.nome.t, colore: accentoTra) {
                                cNome = a.nome.t
                                cTesto = a.corpo.t
                                cGenere = a.genere.t
                                pezzi = [Pezzo(dist: a.km.vero ? a.km.t.replacingOccurrences(of: ".", with: ",") : "")]
                                unisci = false
                            }
                        }
                    }
                }
                TextField(s.nome.t, text: $cNome)
                Picker("Genere", selection: $cGenere) {
                    Text("Corsa").tag("corsa")
                    Text("Palestra").tag("palestra")
                    Text("Altro").tag("altro")
                }
                .pickerStyle(.segmented)
                if cGenere == "corsa" {
                    if !corseDelDi.isNull, !unisci {
                        RigaFin(titolo: "Prendi le corse di \(giorno.isEmpty ? "oggi" : quandoCorto(giorno))", sotto: "\(plurale(corseDelDi.quante, "corsa", "corse")) · \(kmT(corseDelDi.km))", accento: true) {
                            pezzi = corseDelDi.pezzi.list.map(pezzoDa)
                            unisci = true
                            cGenere = "corsa"
                            if cNome.isEmpty { cNome = corseDelDi.corse.list.first { $0.titolo.vero && $0.titolo.t != "Corsa" }?.titolo.t ?? "" }
                        }
                    }
                    ForEach($pezzi) { $p in
                        let i = pezzi.firstIndex { $0.id == p.id } ?? 0
                        HStack(spacing: 6) {
                            Text("\(i + 1)").font(.caption).foregroundStyle(Color.secondarioLife).frame(width: 14)
                            TextField("3000", text: $p.dist).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            TextField("12:06", text: $p.tempo).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                            Text(i < letti.count && letti[i].passo > 0 ? mmss(letti[i].passo) : "—").font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife).frame(width: 40)
                            if pezzi.count > 1 {
                                Button {
                                    pezzi.removeAll { $0.id == p.id }
                                    unisci = false
                                } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button("+ Aggiungi un pezzo") {
                        pezzi.append(Pezzo())
                        unisci = false
                    }
                    .font(.footnote)
                    Text(totKm > 0 ? "\(kmT(.num(totKm)))\(totSec > 0 ? " in \(mmss(totSec)) · media \(passoT(totSec / totKm))" : ""). Entra nell'andamento, nel tetto della lunga e nella proiezione." : "«3000» sono metri, «3» sono chilometri. Il tempo si scrive «12:06».").font(.caption).foregroundStyle(Color.secondarioLife)
                } else {
                    HStack {
                        Text("Durata (minuti)")
                        TextField(tra("dati.durataDi", s).t, text: $cDurata).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
                TextField("Gli esercizi separati da ·, oppure due parole", text: $cTesto, axis: .vertical).lineLimit(2...5)
            }
        }
        Text("Resta questo slot e si spunta da sé: lo stai compilando al passato. Cambiano il nome, il contenuto, i km e i conti della settimana.").font(.caption).foregroundStyle(Color.secondarioLife)
        HStack(spacing: 8) {
            PulsantePieno(testo: "Annulla", colore: Color(uiColor: .systemGray)) { cambio = false }
            PulsantePieno(testo: "Salva", colore: accentoTra) {
                let giri: [J] = cGenere == "corsa" ? letti.filter { $0.km > 0 }.map { ["km": .num($0.km), "secondi": .num($0.sec), "passo": .num($0.passo)] } : []
                let testo = cTesto.trimmingCharacters(in: .whitespaces).isEmpty && giri.count > 1 ? tra("calcolo.descriviPezzi", .arr(giri)).t : cTesto.trimmingCharacters(in: .whitespaces)
                var c: J = ["testo": .str(testo), "genere": .str(cGenere), "giri": .arr(giri), "durata": .num(Double(cDurata.replacingOccurrences(of: ",", with: ".")) ?? 0), "unisci": .bool(unisci && !giri.isEmpty)]
                if !cNome.trimmingCharacters(in: .whitespaces).isEmpty { c["nome"] = .str(cNome.trimmingCharacters(in: .whitespaces)) }
                if !giorno.isEmpty { c["data"] = .str(giorno) }
                tra("dati.cambiaSlot", s.id, c)
                if !f {
                    if giorno.isEmpty { tra("dati.alternaSlot", s.id) } else { tra("dati.alternaSlot", s.id, .str(giorno)) }
                }
                cambio = false
                avviso(totKm > 0 ? "\(f ? "Cambiato" : "Fatto"). \(kmT(.num(totKm))) nei conti della settimana." : f ? "Cambiato." : "Fatto.")
            }
            .disabled(cNome.isEmpty && cTesto.isEmpty)
        }
    }

    @ViewBuilder
    private func quando(_ s: J, giorno: String, rec: J) -> some View {
        let inizio = tra("dati.inizioSettimana", s.sett).t
        let fine = tra("dati.fineSettimana", s.sett).t
        let altri = tra("dati.slotDi", s.sett).list.filter { $0.id != s.id }
        let occupanti: [String: [String]] = altri.reduce(into: [:]) { m, x in
            let g = tra("dati.giornoSlot", x.id).t
            if !g.isEmpty { m[g, default: []].append(x.nome.t) }
        }
        let giorni = (0...max(0, Tempo.giorniTra(inizio, fine))).map { Tempo.piuGiorni(inizio, $0) }
        Sezione("Quando") {
            Carta {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(giorni, id: \.self) { d in
                            Pillola(testo: quandoCorto(d) + (occupanti[d] != nil ? " •" : ""), attiva: d == giorno, colore: accentoTra) {
                                if d == giorno {
                                    conflitto = nil
                                    tra("dati.scegliGiorno", s.id, "")
                                } else if let chi = occupanti[d] {
                                    conflitto = (d, chi)
                                } else {
                                    conflitto = nil
                                    tra("dati.scegliGiorno", s.id, .str(d))
                                }
                            }
                        }
                    }
                }
                if let c = conflitto {
                    Text("\(dataUmana(c.0).maiuscola) c'è già \(c.1.count == 1 ? c.1[0] : "\(c.1.count) allenamenti"). Ce lo metto lo stesso?").font(.footnote)
                    HStack {
                        Button("No") { conflitto = nil }.buttonStyle(.bordered)
                        Button("Sì, mettilo lì") {
                            tra("dati.scegliGiorno", s.id, .str(c.0))
                            conflitto = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentoTra)
                    }
                }
                DatePicker("Ora", selection: Binding(get: { Tempo.istante(Tempo.oggi(), tra("dati.oraDi", s).t) }, set: { tra("dati.scegliOra", s.id, .str(Tempo.oraRoma($0))) }), displayedComponents: .hourAndMinute)
                if !rec.ora.vero {
                    Text("Predefinita per \(s.genere.t == "corsa" ? "la corsa" : s.genere.t == "palestra" ? "la palestra" : "questo genere"): \(tra("dati.oraPredefinita", s.genere).t). Cambiandola qui vale solo per questo.").font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
            .environment(\.timeZone, Tempo.roma)
        }
    }

    @ViewBuilder
    private func garmin(_ s: J, _ letto: J) -> some View {
        Sezione("Porta su Garmin") {
            Carta {
                ForEach(Array(tra("passi.descrivi", letto.passi).list.enumerated()), id: \.offset) { i, r in
                    Text("\(i + 1). \(r.t)").font(.footnote)
                }
                if !letto.completo.vero {
                    Text("Una parte non l'ho saputa tradurre in passi: arriva come corsa libera, e il dettaglio resta qui.").font(.caption).foregroundStyle(Color.secondarioLife)
                } else if letto.assunzioni.vero {
                    Text("Gli allunghi senza durata li ho messi a 30\" con 60\" di pausa.").font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
        }
        Button {
            let j = tra("garmin.allenamentoJSON", .str("\(s.nome.t) · S\(s.sett.t)"), letto.passi, .str("Da ATLAS — \(tra("dati.OBIETTIVO").nome.t)"))
            UIPasteboard.general.string = j.testoJSON
            avviso("Copiato. Apri Connect → Allenamenti e tocca il segnalibro.")
        } label: { Label("Copia per Garmin Connect", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
        Button {
            let b64 = tra("fitBase64", .str("\(s.nome.t) S\(s.sett.t)"), letto.passi).t
            guard let d = Data(base64Encoded: b64) else { return avviso("Non riesco a costruire il file.", errore: true) }
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("atlas-s\(s.sett.t)-\(s.chiave.t).fit")
            try? d.write(to: u)
            fit = FileCondiviso(url: u)
        } label: { Label("Condividi il .FIT per l'orologio", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
        Text("Il .FIT va copiato dal PC, col cavo, nella cartella GARMIN/NewFiles. Non caricarlo su Connect: lì diventerebbe un percorso.").font(.caption).foregroundStyle(Color.secondarioLife)
    }

    @ViewBuilder
    private func hevyVista(_ s: J, _ righe: J) -> some View {
        let configurato = tra("hevy.configurato").vero
        Sezione("Porta su Hevy") {
            Button {
                creo = true
                Task { @MainActor in
                    let r = await Logica.s.chiamaAsync("allenamenti.hevy.creaRoutine", ["titolo": .str("\(s.nome.t) · Settimana \(s.sett.t)"), "note": .str("Da ATLAS — \(tra("dati.OBIETTIVO").nome.t)"), "righe": righe])
                    creo = false
                    let m = r.mancanti.list.map(\.t)
                    avviso(m.isEmpty ? "Routine creata su Hevy." : "Creata. \(m.count) esercizi non erano nel catalogo: \(m.joined(separator: ", ")).")
                    chiudi()
                }
            } label: { Label(creo ? "Creo…" : "Crea la routine su Hevy", systemImage: "icloud.and.arrow.up").frame(maxWidth: .infinity) }
            .disabled(!configurato || creo)
            Text(configurato ? "La routine compare nell'app, in «My Routines»." : "Serve la chiave API, una volta sola: Altro di Training.").font(.caption).foregroundStyle(Color.secondarioLife)
        }
    }
}

struct FileCondiviso: Identifiable {
    let id = UUID()
    let url: URL
}

/// Il foglio di condivisione di iOS.
struct CondividiFile: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

/// La sagoma del corpo con i muscoli accesi (come Corpo in comune.tsx, per il Canvas).
struct CorpoMuscoli: View {
    let primari: Set<String>
    let secondari: Set<String>
    let colore: Color

    private typealias E = (String, CGFloat, CGFloat, CGFloat, CGFloat)
    // Gruppo, centro x, centro y, raggio x, raggio y, nel disegno da 200×460 per sagoma
    private let fronte: [E] = [
        ("spalle", 57, 104, 17, 16), ("spalle", 143, 104, 17, 16),
        ("petto", 80, 112, 17, 20), ("petto", 120, 112, 17, 20),
        ("bicipiti", 45, 134, 12, 27), ("bicipiti", 155, 134, 12, 27),
        ("avambracci", 36, 208, 10, 30), ("avambracci", 164, 208, 10, 30),
        ("addome", 100, 176, 13, 36),
        ("obliqui", 76, 178, 9, 30), ("obliqui", 124, 178, 9, 30),
        ("quadricipiti", 76, 272, 18, 50), ("quadricipiti", 124, 272, 18, 50),
        ("adduttori", 93, 262, 7, 38), ("adduttori", 107, 262, 7, 38),
        ("tibiali", 82, 382, 8, 34), ("tibiali", 118, 382, 8, 34),
    ]
    private let retro: [E] = [
        ("trapezio", 100, 104, 34, 24),
        ("deltoidiPost", 57, 106, 16, 15), ("deltoidiPost", 143, 106, 16, 15),
        ("dorsali", 78, 152, 18, 34), ("dorsali", 122, 152, 18, 34),
        ("tricipiti", 45, 134, 12, 27), ("tricipiti", 155, 134, 12, 27),
        ("lombari", 93, 197, 6, 19), ("lombari", 107, 197, 6, 19),
        ("glutei", 78, 244, 21, 26), ("glutei", 122, 244, 21, 26),
        ("femorali", 76, 288, 18, 46), ("femorali", 124, 288, 18, 46),
        ("polpacci", 78, 378, 13, 34), ("polpacci", 122, 378, 13, 34),
    ]

    var body: some View {
        Canvas { ctx, size in
            let scala = min(size.width / 440, size.height / 460)
            let ox = (size.width - 440 * scala) / 2
            func disegna(_ dx: CGFloat, _ voci: [E]) {
                let x0 = ox + dx * scala
                let sagoma = Color(uiColor: .tertiarySystemFill)
                func ovale(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: x0 + (cx - rx) * scala, y: (cy - ry) * scala, width: rx * 2 * scala, height: ry * 2 * scala))
                }
                func rett(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                    Path(roundedRect: CGRect(x: x0 + x * scala, y: y * scala, width: w * scala, height: h * scala), cornerRadius: r * scala)
                }
                let parti = [
                    ovale(100, 38, 20, 25), rett(89, 56, 22, 26, 9), rett(52, 78, 96, 168, 22),
                    rett(30, 92, 27, 92, 13), rett(26, 176, 23, 82, 11), ovale(33, 268, 12, 12),
                    rett(143, 92, 27, 92, 13), rett(151, 176, 23, 82, 11), ovale(167, 268, 12, 12),
                    rett(56, 222, 42, 130, 20), rett(102, 222, 42, 130, 20),
                    rett(62, 338, 32, 104, 15), rett(106, 338, 32, 104, 15),
                ]
                for p in parti { ctx.fill(p, with: .color(sagoma)) }
                for v in voci {
                    let acceso = primari.contains(v.0)
                    let meta = secondari.contains(v.0)
                    let c: Color = acceso ? colore.opacity(0.95) : meta ? colore.opacity(0.4) : Color.secondary.opacity(0.14)
                    ctx.fill(ovale(v.1, v.2, v.3, v.4), with: .color(c))
                }
            }
            disegna(0, fronte)
            disegna(220, retro)
        }
    }
}

// MARK: - Bonus e import

struct FoglioBonus: View {
    let settimana: Int
    @State private var nome = ""
    @State private var testo = ""
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let p = tra("dati.pianoDi", .n(settimana))
        let taper = p.fase.t.lowercased().contains("taper") || p.fase.t.lowercased().contains("test")
        let u = tra("dati.UPPER_B")
        return Foglio(titolo: "Allenamento in più") {
            Form {
                if taper {
                    Section { Label("Settimana di \(p.fase.t.lowercased()): allenamento extra sconsigliato.", systemImage: "info.circle").font(.footnote).foregroundStyle(arancioneAvviso) }
                }
                Section {
                    Button { salva(u.nome.t, u.testo.t) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.nome.t).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                            Text(u.testo.t).font(.caption).foregroundStyle(Color.secondarioLife)
                        }
                    }
                } header: {
                    Text("Modello")
                } footer: {
                    Text("Si aggiunge in fondo alla Palestra di questa settimana, spuntabile come gli altri.")
                }
                Section("Personalizzato") {
                    TextField("Come si chiama", text: $nome)
                    TextField("Separa gli esercizi con ·", text: $testo, axis: .vertical).lineLimit(3...6)
                    Button("Aggiungi") { salva(nome.trimmingCharacters(in: .whitespaces).isEmpty ? "Bonus" : nome, testo) }.fontWeight(.semibold)
                }
            }
        }
    }

    private func salva(_ n: String, _ t: String) {
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return avviso("Manca il contenuto dell'allenamento.", errore: true) }
        tra("dati.aggiungiBonus", .n(settimana), ["nome": .str(n), "testo": .str(t)])
        avviso("\(n) aggiunto alla settimana \(settimana).")
        chiudi()
    }
}

private let promptFitness = "Dammi il lavoro in CSV con queste colonne, senza altro testo intorno:\nsettimana,nome,genere,testo,km\n`settimana` è un numero da 1 a 13. `nome` è come chiamo l'allenamento (Fartlek, Full body, Giro in bici: quello che è). `genere` è corsa, palestra o altro. `testo` è l'allenamento in una riga; per la palestra separa gli esercizi con · e scrivi le serie come 4×8. `km` solo per la corsa, col punto decimale. Una riga per allenamento: se la settimana ne ha tre, scrivi tre righe."

struct FoglioImport: View {
    let quale: String
    @State private var scelta = ""
    @State private var testo = ""
    @State private var anteprima: [J]?
    @State private var scegliFile = false
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            Group {
                if let a = anteprima {
                    AnteprimaCorsa(lista: a, fatto: { chiudi() }, annulla: { anteprima = nil })
                } else {
                    modulo
                }
            }
            .navigationTitle(anteprima != nil ? "La corsa" : "Importa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } } }
        }
        .onAppear { if scelta.isEmpty { scelta = quale } }
        .fileImporter(isPresented: $scegliFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text], allowsMultipleSelection: true, onCompletion: file)
    }

    private var modulo: some View {
        Pagina {
            Picker("Cosa", selection: $scelta) {
                Text("Corse fatte").tag("corse")
                Text("Allenamenti").tag("allenamenti")
            }
            .pickerStyle(.segmented)
            if scelta == "corse" {
                Text("Una corsa con tutti i dati: su Garmin Connect apri la corsa → ⚙ → «Esporta in CSV» (il file dei giri). Life legge passo, cuore, potenza, cadenza, dislivello e i giri, e la chat di Claude li vede.\nTante corse insieme: Attività → Tutte le attività → l'icona di esportazione in alto a destra.").font(.footnote).foregroundStyle(Color.secondarioLife)
            } else {
                Text("Una riga per allenamento. Il nome lo scegli tu: non ci sono tipi fissi. Quello che importi sostituisce la settimana: tre righe fanno tre allenamenti, sette ne fanno sette.").font(.footnote).foregroundStyle(Color.secondarioLife)
                Carta { Text(tra("importa.ESEMPIO_ALLENAMENTI").t).font(.system(.caption, design: .monospaced)) }
                Button {
                    UIPasteboard.general.string = promptFitness
                    avviso("Copiato: incollalo nella chat di fitness.")
                } label: { Label("Copia il formato per la chat", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
            }
            TextEditor(text: $testo)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button { scegliFile = true } label: {
                Label(scelta == "corse" ? "…oppure scegli il file (o più file: le tracce della stessa sessione)" : "…oppure scegli il file", systemImage: "square.and.arrow.down").font(.subheadline)
            }
            PulsantePieno(testo: scelta == "corse" ? "Importa le corse" : "Importa gli allenamenti", colore: accentoTra, azione: importa)
                .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    private func file(_ esito: Result<[URL], Error>) {
        guard let urls = try? esito.get(), let primo = urls.first else { return }
        if scelta == "corse" {
            let (tracce, altri) = leggiTracce(urls)
            if !tracce.isEmpty {
                if !altri.isEmpty { avviso("\(altri.joined(separator: ", ")): non è il file dei giri di una corsa, l'ho lasciato fuori.") }
                anteprima = tracce
                return
            }
        }
        let accesso = primo.startAccessingSecurityScopedResource()
        defer { if accesso { primo.stopAccessingSecurityScopedResource() } }
        if let t = try? String(contentsOf: primo, encoding: .utf8) {
            testo = t
            avviso("Letto \(primo.lastPathComponent).")
        } else {
            avviso("Non riesco a leggere il file.", errore: true)
        }
    }

    private func importa() {
        if scelta == "corse" {
            let r = tra("importa.corseDaCSV", .str(testo))
            guard !r.corse.list.isEmpty else { return avviso(r.motivo.str ?? "Non ho trovato corse.", errore: true) }
            if r.daGiri.vero {
                anteprima = [r.corse[0]]
                return
            }
            let s = tra("dati.salvaCorse", r.corse)
            avviso("\(s.nuove.int ?? 0) nuove, \(s.aggiornate.int ?? 0) già c'erano\(r.scartate.vero ? ", \(r.scartate.int ?? 0) scartate" : "").")
            chiudi()
        } else {
            let r = tra("importa.allenamentiDaCSV", .str(testo))
            guard !r.settimane.list.isEmpty else { return avviso(r.motivo.str ?? "Non ho trovato allenamenti.", errore: true) }
            var scritti = 0
            for w in r.settimane.list { scritti += tra("dati.pianificaSettimana", w.sett, w.voci).int ?? 0 }
            avviso("\(scritti) allenamenti in \(plurale(Double(r.settimane.list.count), "settimana", "settimane"))\(r.scartate.vero ? ", \(r.scartate.int ?? 0) righe scartate" : "").")
            chiudi()
        }
    }
}

// MARK: - Altro

struct ImpostazioniTraining: View {
    @State private var chiave = Logica.s.chiama("allenamenti.hevy.chiave").t
    @State private var provo = false
    @State private var catalogo = Logica.s.chiama("allenamenti.hevy.esercizinoti").list.count

    var body: some View {
        let z = tra("dati.zoneFC")
        let lim = tra("analisi.limitiZone")
        let ob = tra("dati.OBIETTIVO")
        let zone = tra("dati.ZONE")
        let colonne: [(String, String, String, String)] = [
            ("Z1", "recupero", "< \(lim.z1.t)", "#8a8a90"),
            ("Z2", "facile", "\(lim.z1.t)–\(lim.z2.t)", "#3dbf5c"),
            ("Z3", "medio", "\((lim.z2.int ?? 0) + 1)–\(lim.z3.t)", "#eab52a"),
            ("Z4", "soglia", "\((lim.z3.int ?? 0) + 1)–\(lim.z4.t)", "#f7902b"),
            ("Z5", "VO2max", "> \(lim.z4.t)", "#f5544d"),
        ]
        return VStack(alignment: .leading, spacing: 16) {
            Sezione("Zone cardiache") {
                Carta(padding: 12) {
                    HStack {
                        Text("FC massima").font(.subheadline)
                        Spacer()
                        CampoNumero(valore: z.fcMax.d, unita: "bpm") { n in if n >= 150, n <= 230 { tra("dati.scriviZoneFC", ["fcMax": .num(n)]) } }
                    }
                    HStack {
                        Text("Facile fino a").font(.subheadline)
                        Spacer()
                        CampoNumero(valore: z.facile.d, unita: "bpm") { n in if n >= 100, n < z.fcMax.d { tra("dati.scriviZoneFC", ["facile": .num(n)]) } }
                    }
                    HStack(spacing: 4) {
                        ForEach(colonne, id: \.0) { c in
                            VStack(spacing: 1) {
                                Text(c.0).font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: c.3))
                                Text(c.1).font(.system(size: 10)).foregroundStyle(Color.secondarioLife).lineLimit(1).minimumScaleFactor(0.7)
                                Text(c.2).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(hex: c.3).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            Text("Le zone delle corse si calcolano da qui, non da valori generici. Cambiandole, l'analisi delle corse si aggiorna.").font(.caption).foregroundStyle(Color.secondarioLife)
            Sezione("Segnalibro per Garmin") {
                Carta(padding: 12) {
                    ForEach(Array(["Copia il codice qui sotto.", "Salva un segnalibro qualunque, poi modificalo: chiamalo «ATLAS → Garmin» e incolla il codice al posto dell'indirizzo.", "In Training tocca «Copia per Garmin Connect» su un allenamento.", "Apri connect.garmin.com → Allenamenti e tocca il segnalibro.", "Nel riquadro che si apre incolla e tocca «Crea allenamento»."].enumerated()), id: \.offset) { i, t in
                        Text("\(i + 1). \(t)").font(.footnote)
                    }
                    RigaFin(titolo: "Copia il codice del segnalibro", accento: true) {
                        UIPasteboard.general.string = tra("garmin.SEGNALIBRO").t
                        avviso("Copiato. Salvalo come segnalibro.")
                    }
                }
            }
            Sezione("Hevy") {
                Carta(padding: 12) {
                    SecureField("Chiave API: incollala qui", text: $chiave)
                        .textInputAutocapitalization(.never)
                        .onSubmit { tra("hevy.scriviChiave", .str(chiave)) }
                    if catalogo > 0 { RigaFin(titolo: "Catalogo in memoria", valore: "\(catalogo) esercizi") }
                    Button(provo ? "Provo…" : "Prova la chiave", action: prova).disabled(chiave.isEmpty || provo)
                }
                .onAppear {
                    // Su un dispositivo nuovo la chiave può arrivare dall'account un attimo dopo
                    if chiave.isEmpty { chiave = Logica.s.chiama("allenamenti.hevy.chiave").t }
                }
            }
            Text("Hevy → Settings → Developer → Generate API Key (serve Pro). Si salva nel tuo account: basta scriverla una volta.").font(.caption).foregroundStyle(Color.secondarioLife)
            Sezione("Il blocco") {
                Carta(padding: 12) {
                    RigaFin(titolo: "Obiettivo", valore: "\(ob.nome.t) · \(ob.passo.t)")
                    RigaFin(titolo: "Inizio", valore: dataBreve(tra("dati.inizioSettimana", 1).t))
                    RigaFin(titolo: "Test", valore: dataBreve(tra("calcolo.giornoTest").t))
                    RigaFin(titolo: "Zone", valore: "\(zone.z2.fc.t) · \(zone.z3.fc.t)")
                }
            }
            Sezione("Le regole") {
                Carta(padding: 12) {
                    ForEach(tra("dati.REGOLE").list, id: \.self) { r in Text("• \(r.t)").font(.footnote) }
                    Text(tra("dati.VINCOLO").t).font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
        }
    }

    private func prova() {
        tra("hevy.scriviChiave", .str(chiave))
        provo = true
        Task { @MainActor in
            let (_, errore) = await Logica.s.chiamaAsyncConErrore("allenamenti.hevy.provaChiave")
            if let errore {
                provo = false
                avviso(errore, errore: true)
                return
            }
            let (risposta, errore2) = await Logica.s.chiamaAsyncConErrore("allenamenti.hevy.scaricaEsercizi", ["forza": true])
            let el = risposta.list
            catalogo = el.count
            provo = false
            avviso(errore2 ?? "Funziona. \(el.count) esercizi nel catalogo.", errore: errore2 != nil)
        }
    }
}
