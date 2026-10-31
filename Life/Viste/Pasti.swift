import SwiftUI

// Pasti: la giornata, la settimana, la pianificazione, l'import dalla chat, le impostazioni.
// Fabbisogno, piano e catalogo sono quelli di ATLAS, nel bundle JS.

func pas(_ f: String, _ a: J...) -> J { Logica.s.chiama("pasti.\(f)", argomenti: a) }
private let accentoPas = Color(hex: "#FF2D55")
private let macro: [(k: String, nome: String, breve: String, emoji: String, colore: Color)] = [
    ("p", "Proteine", "Prot.", "🥩", Color(hex: "#0A84FF")),
    ("c", "Carboidrati", "Carb.", "🍞", Color(hex: "#FFCC00")),
    ("g", "Grassi", "Grassi", "🥑", Color(hex: "#5E5CE6")),
]
private let emojiFascia = ["colazione": "🍳", "spuntino1": "🍎", "pranzo": "🥗", "spuntino2": "🥜", "cena": "🍝"]
private func kcal(_ n: Double) -> String { Logica.s.chiama("ui.numero", .num(n.rounded())).t }
private func kcal(_ n: J) -> String { kcal(n.d) }
private func oraAdesso() -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}
private func minutiDi(_ s: String) -> Int {
    let p = s.split(separator: ":").map { Int($0) ?? 0 }
    return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
}
private func fasciaDallOra() -> String {
    let adesso = minutiDi(oraAdesso())
    let fasce = pas("dati.FASCE").list
    return fasce.min { abs(minutiDi($0.ora.t) - adesso) < abs(minutiDi($1.ora.t) - adesso) }?.id.t ?? "pranzo"
}
private var pianificazioneProposta = false

struct FasciaScelta: Identifiable {
    let iso: String
    let fascia: String
    var id: String { "\(iso)|\(fascia)" }
}
struct AggiuntaScelta: Identifiable {
    let iso: String
    let fascia: String?
    let tipo: String
    var id: String { "\(iso)|\(fascia ?? "")|\(tipo)" }
}
struct GiorniPiano: Identifiable {
    let giorni: [String]
    var id: String { giorni.joined() }
}

struct VistaPasti: View {
    @ObservedObject private var logica = Logica.s
    @State private var scheda = "oggi"
    @State private var fascia: FasciaScelta?
    @State private var scegli: FasciaScelta?
    @State private var aggiungi: AggiuntaScelta?
    @State private var importa = false
    @State private var avanti = 0
    @State private var pianifica: GiorniPiano?

    private var iso: String { logica.chiama("ui.oggiISO").t }

    var body: some View {
        let _ = logica.versione
        let lunedi = Tempo.piuGiorni(pas("dati.lunediDi", .str(iso)).t, avanti * 7)
        let daPianificare = pianoDaProporre
        return Pagina {
            Picker("Scheda", selection: $scheda) {
                Text("Oggi").tag("oggi")
                Text("Settimana").tag("settimana")
                Text("Altro").tag("altro")
            }
            .pickerStyle(.segmented)
            switch scheda {
            case "settimana":
                selettoreSettimana(lunedi)
                settimana(lunedi)
            case "altro":
                ImpostazioniPasti(importa: { importa = true }, pianifica: { pianifica = GiorniPiano(giorni: $0) }, restanti: giorniRestanti, prossima: giorniProssima)
            default:
                bilancio
                if let daPianificare {
                    Button { pianifica = GiorniPiano(giorni: giorniProssima) } label: {
                        Carta {
                            HStack(spacing: 10) {
                                Text("📅").font(.title)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Pianifica la settimana").font(.subheadline.weight(.semibold))
                                    Text("Da \(dataUmana(daPianificare)). Un giorno per schermata, cinque minuti.").font(.footnote).foregroundStyle(Color.secondarioLife)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.terziarioLife)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                giornata
            }
        }
        .navigationTitle("Pasti")
        .toolbar {
            Button { importa = true } label: { Image(systemName: "square.and.arrow.down") }
        }
        .onAppear {
            // La domenica dalle 15 propone la settimana che arriva, una volta per apertura
            if daPianificare != nil, !pianificazioneProposta {
                pianificazioneProposta = true
                pianifica = GiorniPiano(giorni: giorniProssima)
            }
        }
        .sheet(item: $fascia) { f in
            FoglioFascia(iso: f.iso, fascia: f.fascia, scegli: {
                fascia = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scegli = f }
            }, altro: {
                fascia = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { aggiungi = AggiuntaScelta(iso: f.iso, fascia: f.fascia, tipo: "cambio") }
            })
            .presentationDetents([.medium])
        }
        .sheet(item: $scegli) { f in FoglioScegli(iso: f.iso, fascia: f.fascia) }
        .sheet(item: $aggiungi) { a in FoglioAggiungi(iso: a.iso, fascia: a.fascia, tipo: a.tipo) }
        .sheet(isPresented: $importa) {
            FoglioImportPasti { date in
                guard let primo = date.first, let ultimo = date.last else { return }
                var g: [String] = []
                var d = primo
                while d <= ultimo, g.count < 31 {
                    g.append(d)
                    d = Tempo.piuGiorni(d, 1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pianifica = GiorniPiano(giorni: g) }
            }
        }
        .fullScreenCover(item: $pianifica) { p in Pianifica(giorni: p.giorni) }
    }

    private var pianoDaProporre: String? {
        let c = Calendar.current.dateComponents([.weekday, .hour], from: Date())
        guard c.weekday == 1, (c.hour ?? 0) >= 15 else { return nil }
        let lun = Tempo.piuGiorni(pas("dati.lunediDi", .str(iso)).t, 7)
        return pas("dati.pianoSettimana", .str(lun)).confermato.vero ? nil : lun
    }

    private var giorniProssima: [String] {
        let lun = Tempo.piuGiorni(pas("dati.lunediDi", .str(iso)).t, 7)
        return (0..<7).map { Tempo.piuGiorni(lun, $0) }
    }

    private var giorniRestanti: [String] {
        let fine = Tempo.piuGiorni(pas("dati.lunediDi", .str(iso)).t, 6)
        var g: [String] = []
        var d = iso
        while d <= fine {
            g.append(d)
            d = Tempo.piuGiorni(d, 1)
        }
        return g.isEmpty ? [iso] : g
    }

    // MARK: Oggi

    private var bilancio: some View {
        let b = pas("calcolo.bersagli")
        let g = pas("calcolo.giornata", .str(iso))
        let t = g.totale
        let manca = b.kcal.d - t.kcal.d
        return VStack(spacing: 12) {
            Blocco(eti: "Il bilancio") {
                HStack(spacing: 18) {
                    ZStack {
                        Anello(valore: b.kcal.vero ? t.kcal.d / b.kcal.d : 0, misura: 116, spessore: 12, colore: accentoPas)
                        VStack(spacing: 0) {
                            Text(kcal(t.kcal)).font(.title3.weight(.semibold)).monospacedDigit()
                            Text("su \(kcal(b.kcal))").font(.caption2).foregroundStyle(Color.secondarioLife)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(manca >= 0 ? "Mancano" : "Oltre di").font(.footnote).foregroundStyle(Color.secondarioLife)
                        Text(kcal(abs(manca))).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(manca < 0 ? arancioneAvviso : Color.primary)
                        Text("kcal").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(macro, id: \.k) { m in
                        let fatto = t[m.k].d.rounded()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(m.emoji) \(m.breve)").font(.caption2).foregroundStyle(Color.secondarioLife)
                            (Text("\(Int(fatto))").font(.subheadline.weight(.semibold)).monospacedDigit() + Text("/\(b[m.k].int ?? 0) g").font(.caption2).foregroundColor(Color.secondarioLife))
                            Barra(valore: b[m.k].vero ? fatto / b[m.k].d : 0, colore: m.colore, altezza: 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                let incerte = g.incerte.list.count
                if incerte > 0 { Text("\(plurale(Double(incerte), "fascia ancora da decidere", "fasce ancora da decidere")): il totale è parziale.").font(.caption).foregroundStyle(Color.secondarioLife) }
            }
            PulsantePieno(testo: "Ho mangiato qualcos'altro", colore: accentoPas, icona: "plus") { aggiungi = AggiuntaScelta(iso: iso, fascia: nil, tipo: "aggiunta") }
        }
    }

    @ViewBuilder
    private var giornata: some View {
        let b = pas("calcolo.bersagli")
        let g = pas("calcolo.giornata", .str(iso))
        let fasce = pas("dati.FASCE").list
        let extra = g.scostamenti.list.filter { $0.tipo.t == "aggiunta" }
        Sezione("La giornata") {
            Carta(padding: 12) {
                ForEach(g.fasce.list, id: \.fascia) { f in
                    let sost = g.scostamenti.list.first { $0.fascia == f.fascia && ($0.tipo.t == "cambio" || $0.tipo.t == "salto") }
                    let saltato = sost?.tipo.t == "salto"
                    let m = (sost != nil && !saltato) ? sost! : f.contato
                    let info = fasce.first { $0.id == f.fascia } ?? .null
                    let conti = saltato || (f.regime.t == "salto" && sost == nil) ? J.null : m
                    let cosa = saltato ? "Saltato" : sost?.nome.t ?? (f.nome.vero ? f.nome.t : f.regime.t == "salto" ? "Non la fai" : "Da scegliere")
                    let senza = saltato || (!f.nome.vero && sost == nil)
                    Button {
                        tocco()
                        fascia = FasciaScelta(iso: iso, fascia: f.fascia.t)
                    } label: {
                        HStack(spacing: 10) {
                            Text(emojiFascia[f.fascia.t] ?? "🍽️").font(.title2).frame(width: 44, height: 44).background(senza ? Color(uiColor: .tertiarySystemFill) : accentoPas.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).opacity(senza ? 0.6 : 1)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(info.nome.t).font(.caption.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                                    Text(info.ora.t).font(.caption2).monospacedDigit().foregroundStyle(Color.terziarioLife)
                                }
                                Text(cosa).font(.subheadline).foregroundStyle(senza ? Color.secondarioLife : Color.primary).lineLimit(2)
                                if !conti.isNull {
                                    HStack(spacing: 6) {
                                        ForEach(macro, id: \.k) { x in
                                            VStack(alignment: .leading, spacing: 1) {
                                                Barra(valore: b[x.k].vero ? conti[x.k].d / b[x.k].d : 0, colore: x.colore, altezza: 3)
                                                Text("\(Int(conti[x.k].d.rounded()))g \(x.breve)").font(.system(size: 10)).monospacedDigit().foregroundStyle(Color.secondarioLife).lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                            Spacer(minLength: 4)
                            if !conti.isNull {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(kcal(conti.kcal)).font(.headline).monospacedDigit()
                                    Text("kcal").font(.caption2).foregroundStyle(Color.terziarioLife)
                                }
                            } else {
                                Image(systemName: "plus").foregroundStyle(accentoPas).frame(width: 32, height: 32).background(Color(uiColor: .tertiarySystemFill), in: Circle())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !extra.isEmpty {
            Sezione("In più, oggi") {
                Carta(padding: 12) {
                    ForEach(extra, id: \.id) { s in
                        RigaFin(titolo: "\(emojiFascia[s.fascia.t] ?? "🍽") \(s.nome.t)", sotto: [s.ora.str, pas("dati.SCOSTAMENTI")[s.tipo.t].str].compactMap { $0 }.joined(separator: " · "), valore: "\(kcal(s.kcal)) kcal") {
                            pas("dati.eliminaScostamento", s.id)
                            avviso("Tolto.")
                        }
                    }
                }
            }
            Text("Tocca una riga per toglierla.").font(.caption).foregroundStyle(Color.secondarioLife)
        }
    }

    // MARK: Settimana

    private func selettoreSettimana(_ lunedi: String) -> some View {
        HStack {
            Button { avanti -= 1 } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(avanti == 0 ? "Questa settimana" : avanti == 1 ? "La prossima" : avanti == -1 ? "La scorsa" : "\(dataBreve(lunedi)) – \(dataBreve(Tempo.piuGiorni(lunedi, 6)))").font(.subheadline.weight(.semibold))
            if avanti != 0 { Button("Oggi") { avanti = 0 }.font(.footnote) }
            Spacer()
            Button { avanti += 1 } label: { Image(systemName: "chevron.right") }
        }
    }

    @ViewBuilder
    private func settimana(_ lunedi: String) -> some View {
        let b = pas("calcolo.bersagli")
        let s = pas("calcolo.settimana", .str(lunedi))
        let piano = pas("dati.pianoSettimana", .str(lunedi))
        let oggi = iso
        let fasce = pas("dati.FASCE").list
        ForEach(s.giorni.list, id: \.iso) { x in
            let g = x.iso.t
            let dentro = pas("calcolo.giornata", x.iso)
            let nome = Tempo.settimanaLunga[Tempo.giornoSettimana(g)].maiuscola
            Sezione("\(nome) \(Tempo.parti(g).2)\(g == oggi ? " · oggi" : "")", coda: { Text("\(kcal(dentro.totale.kcal)) / \(kcal(b.kcal)) kcal").monospacedDigit() }) {
                Carta(padding: 12) {
                    ForEach(fasce, id: \.id) { f in
                        let c = dentro.fasce.list.first { $0.fascia == f.id } ?? .null
                        let regime = pas("dati.regimeDi", x.iso, f.id).t
                        let k = c.contato.kcal.d
                        Button { fascia = FasciaScelta(iso: g, fascia: f.id.t) } label: {
                            HStack(spacing: 10) {
                                Text(emojiFascia[f.id.t] ?? "🍽")
                                Group {
                                    if regime == "salto" {
                                        Text("Non la fai").foregroundStyle(Color.terziarioLife)
                                    } else if regime == "fuori" {
                                        Text("Fuori").foregroundStyle(arancioneAvviso)
                                    } else if !c.voci.list.isEmpty {
                                        Text(c.nome.t)
                                    } else {
                                        Text("Da mettere").foregroundStyle(Color.terziarioLife)
                                    }
                                }
                                .font(.subheadline)
                                .lineLimit(1)
                                Spacer()
                                if k > 0 { Text(kcal(k)).font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                            }
                            .contentShape(Rectangle())
                            .opacity(g < oggi ? 0.7 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        Sezione("Media della settimana") {
            Carta {
                rigaMedia("Calorie", s.media.kcal.d, b.kcal.d, "kcal", accentoPas)
                ForEach(macro, id: \.k) { m in rigaMedia(m.nome, s.media[m.k].d, b[m.k].d, "g", m.colore) }
            }
        }
        Text("La media conta più del singolo giorno: una cena saltata il martedì non è un problema se la settimana torna.").font(.caption).foregroundStyle(Color.secondarioLife)
        PulsantePieno(testo: piano.isNull ? "Genera la settimana" : "Rigenera la settimana", colore: accentoPas) {
            let e = piano.isNull ? pas("piano.assicuraPiano", .str(lunedi)) : pas("piano.rigenera", .str(lunedi))
            avviso(e.creato.vero ? "Settimana rifatta." : "Non fatto: \(e.motivo.t).", errore: !e.creato.vero)
        }
        if piano.bloccato.vero {
            Text("Questa settimana l'hai modificata a mano, quindi il generatore la lascia stare. Rigenerandola perdi le modifiche.").font(.caption).foregroundStyle(Color.secondarioLife)
        }
    }

    private func rigaMedia(_ n: String, _ v: Double, _ b: Double, _ u: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(n).font(.footnote)
                Spacer()
                Text("\(kcal(v)) / \(kcal(b)) \(u)").font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife)
            }
            Barra(valore: b > 0 ? v / b : 0, colore: c)
        }
    }
}

// MARK: - La scelta dei componenti

/// Pillole che vanno a capo.
struct AcapoLayout: Layout {
    var spazio: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        disponi(proposal.width ?? 320, subviews).1
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (punti, _) = disponi(bounds.width, subviews)
        for (i, p) in punti.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func disponi(_ larghezza: CGFloat, _ subviews: Subviews) -> ([CGPoint], CGSize) {
        var punti: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var riga: CGFloat = 0
        var massimo: CGFloat = 0
        for v in subviews {
            let m = v.sizeThatFits(.unspecified)
            if x > 0, x + m.width > larghezza {
                x = 0
                y += riga + spazio
                riga = 0
            }
            punti.append(CGPoint(x: x, y: y))
            x += m.width + spazio
            massimo = max(massimo, x - spazio)
            riga = max(riga, m.height)
        }
        return (punti, CGSize(width: massimo, height: y + riga))
    }
}

struct SceltaComponenti: View {
    @Binding var scelti: [String]
    let fascia: String
    var bersaglio: Double = 0
    @State private var tutto = false

    var body: some View {
        let c = pas("dati.componentiPerFascia", .str(fascia))
        let elenco = tutto ? c.dentro.list + c.fuori.list : c.dentro.list
        let voci = scelti.map { pas("dati.pasto", .str($0)) }.filter { !$0.isNull }
        let tot = (kcal: voci.reduce(0) { $0 + $1.kcal.d }, p: voci.reduce(0) { $0 + $1["p"].d }, c: voci.reduce(0) { $0 + $1["c"].d }, g: voci.reduce(0) { $0 + $1["g"].d })
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if voci.isEmpty {
                    Text("Tocca quello che c'è nel piatto. Il conto si fa da sé.").font(.footnote).foregroundStyle(Color.secondarioLife)
                } else {
                    AcapoLayout {
                        ForEach(voci, id: \.id) { v in
                            Button { alterna(v.id.t) } label: {
                                HStack(spacing: 4) {
                                    Text(v.nome.t).font(.footnote)
                                    if v.porzione.vero { Text(v.porzione.t).font(.caption2).foregroundStyle(Color.secondarioLife) }
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.secondarioLife)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(accentoPas.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        (Text(kcal(tot.kcal)).font(.title3.weight(.semibold)).monospacedDigit() + Text(" kcal").font(.caption).foregroundColor(Color.secondarioLife))
                        Text("\(Int(tot.p.rounded()))g Prot. · \(Int(tot.c.rounded()))g Carb. · \(Int(tot.g.rounded()))g Grassi").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                    if bersaglio > 0 { Barra(valore: tot.kcal / bersaglio, colore: accentoPas, altezza: 5) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            ForEach(pas("dati.GRUPPI_COMPONENTI").list, id: \.id) { g in
                let suoi = elenco.filter { $0.gruppo == g.id }
                if !suoi.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(g.emoji.t) \(g.nome.t)").font(.footnote.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                        AcapoLayout {
                            ForEach(suoi, id: \.id) { v in
                                let preso = scelti.contains(v.id.t)
                                Button { alterna(v.id.t) } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(v.nome.t).font(.footnote)
                                        Text("\(v.porzione.vero ? "\(v.porzione.t) · " : "")\(kcal(v.kcal)) kcal").font(.caption2).opacity(0.75)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(preso ? Color.white : Color.primary)
                                    .background(preso ? accentoPas : Color.cartaLife, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Button(tutto ? "Mostra solo quelli di questa fascia" : "Mostra tutto il resto") { tutto.toggle() }.font(.footnote)
        }
    }

    private func alterna(_ id: String) {
        tocco()
        if scelti.contains(id) { scelti.removeAll { $0 == id } } else { scelti.append(id) }
    }
}

// MARK: - Fogli

struct FoglioFascia: View {
    let iso: String
    let fascia: String
    let scegli: () -> Void
    let altro: () -> Void
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let regime = pas("dati.regimeDi", .str(iso), .str(fascia)).t
        let nome = pas("dati.nomeFascia", .str(fascia)).t
        return Foglio(titolo: "\(nome) · \(dataUmana(iso))") {
            Form {
                Section {
                    if regime == "casa" {
                        Button(action: scegli) { Label("Cambia il pasto pianificato", systemImage: "pencil") }
                    }
                    Button(action: altro) { Label("Ho mangiato altro, al posto di questo", systemImage: "fork.knife") }
                    Button {
                        pas("dati.registraScostamento", ["tipo": "salto", "data": .str(iso), "fascia": .str(fascia)])
                        avviso("\(nome) saltato.")
                        chiudi()
                    } label: { Label("L'ho saltato", systemImage: "forward") }
                } footer: {
                    Text("Questa fascia è «\(pas("dati.REGIMI")[regime].str ?? regime)» nella tua settimana tipo. Si cambia nelle impostazioni.")
                }
            }
        }
    }
}

struct FoglioScegli: View {
    let iso: String
    let fascia: String
    @State private var scelti: [String] = []
    @State private var caricato = false

    private var lunedi: String { pas("dati.lunediDi", .str(iso)).t }

    var body: some View {
        Foglio(titolo: pas("dati.nomeFascia", .str(fascia)).t, fatto: "Salva", azione: {
            pas("dati.scegliVoci", .str(lunedi), .str(iso), .str(fascia), .arr(scelti.map { .str($0) }))
            avviso(scelti.isEmpty ? "Fascia svuotata." : "Piano aggiornato.")
        }) {
            Pagina {
                SceltaComponenti(scelti: $scelti, fascia: fascia, bersaglio: pas("calcolo.bersagli").kcal.d)
                Text("Cambiando un pasto a mano questa settimana diventa tua: il generatore non ci torna più sopra.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
        }
        .onAppear {
            guard !caricato else { return }
            caricato = true
            scelti = pas("dati.vociPiano", pas("dati.pianoSettimana", .str(lunedi)), .str(iso), .str(fascia)).list.map(\.t)
        }
    }
}

struct FoglioAggiungi: View {
    let iso: String
    let fascia: String?
    let tipo: String
    @State private var scelta = ""
    @State private var nome = ""
    @State private var k = ""
    @State private var p = ""
    @State private var c = ""
    @State private var g = ""
    @State private var errore = ""
    @State private var pezzi: [String] = []
    @Environment(\.dismiss) private var chiudi

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        let attiva = scelta.isEmpty ? (fascia ?? fasciaDallOra()) : scelta
        let proposte = Array(pas("importa.propostePerFascia", .str(attiva), ["tendenze": pas("calcolo.tendenze"), "pasti": pas("dati.pastiVivi")]).list.prefix(14))
        return Foglio(titolo: tipo == "cambio" ? "Al posto di…" : "Ho mangiato") {
            Pagina {
                if fascia == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(pas("dati.FASCE").list, id: \.id) { f in
                                Pillola(testo: f.nome.t, attiva: attiva == f.id.t, colore: accentoPas) { scelta = f.id.t }
                            }
                        }
                    }
                }
                if !proposte.isEmpty {
                    Sezione("Lo fai spesso") {
                        Carta(padding: 12) {
                            ForEach(proposte, id: \.nome) { v in
                                RigaFin(titolo: v.nome.t, sotto: v.origine.t == "tendenza" ? "lo fai spesso · \(plurale(v.volte, "volta", "volte"))" : "\(v["p"].t) g di proteine", valore: "\(kcal(v.kcal)) kcal") { segna(v, attiva) }
                            }
                        }
                    }
                }
                Sezione("Mettilo insieme") {
                    SceltaComponenti(scelti: $pezzi, fascia: attiva, bersaglio: pas("calcolo.bersagli").kcal.d)
                }
                if !pezzi.isEmpty {
                    PulsantePieno(testo: "Segna quello che hai messo", colore: accentoPas) {
                        let voci = pezzi.map { pas("dati.pasto", .str($0)) }.filter { !$0.isNull }
                        guard !voci.isEmpty else { return }
                        let somma: (String) -> J = { key in .num(voci.reduce(0) { $0 + $1[key].d }) }
                        segna(["nome": .str(voci.map(\.nome.t).joined(separator: " + ")), "kcal": somma("kcal"), "p": somma("p"), "c": somma("c"), "g": somma("g"), "pastoId": voci.count == 1 ? voci[0].id : nil], attiva)
                    }
                }
                Sezione("Non è in lista") {
                    Carta(padding: 12) {
                        TextField("pizzetta, panino…", text: $nome).onSubmit(leggi)
                        Divider()
                        campo("kcal", $k, "")
                        campo("Proteine", $p, "g")
                        campo("Carboidrati", $c, "g")
                        campo("Grassi", $g, "g")
                    }
                }
                Text(errore.isEmpty ? "Scrivi pure tutto in una riga: «panino 300 kcal 18p»." : errore).font(.caption).foregroundStyle(errore.isEmpty ? Color.secondarioLife : Color.pericoloLife)
                PulsantePieno(testo: "Segna", colore: accentoPas) {
                    leggi()
                    guard !nome.trimmingCharacters(in: .whitespaces).isEmpty else {
                        errore = "Manca il nome."
                        return
                    }
                    guard num(k) > 0 else {
                        errore = "Mancano le calorie: senza, il conto della giornata direbbe una bugia."
                        return
                    }
                    segna(["nome": .str(nome.trimmingCharacters(in: .whitespaces)), "kcal": .num(num(k)), "p": .num(num(p)), "c": .num(num(c)), "g": .num(num(g))], attiva)
                }
            }
        }
    }

    private func campo(_ e: String, _ b: Binding<String>, _ u: String) -> some View {
        HStack {
            Text(e).font(.subheadline)
            TextField("0", text: b).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
            if !u.isEmpty { Text(u).font(.footnote).foregroundStyle(Color.secondarioLife) }
        }
    }

    private func leggi() {
        let l = pas("importa.scostamentoDaTesto", .str(nome))
        if l.completo.vero, k.isEmpty {
            nome = l.nome.t
            k = l.kcal.t
            p = l["p"].vero ? l["p"].t : ""
            c = l["c"].vero ? l["c"].t : ""
            g = l["g"].vero ? l["g"].t : ""
        }
    }

    private func segna(_ v: J, _ f: String) {
        pas("dati.registraScostamento", ["tipo": .str(tipo), "data": .str(iso), "ora": .str(oraAdesso()), "fascia": .str(f), "nome": v.nome, "kcal": v.kcal, "p": v["p"], "c": v["c"], "g": v["g"], "pastoId": v.pastoId])
        avviso("Segnato.")
        chiudi()
    }
}

struct FoglioImportPasti: View {
    let verifica: ([String]) -> Void
    @State private var testo = ""
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let letto = testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? J.null : pas("importa.pianoDaJSON", .str(testo), ["noti": pas("dati.pastiVivi")])
        let giorni = letto.giorni.list
        let quanti = giorni.reduce(0) { $0 + $1.pasti.list.count }
        return Foglio(titolo: "Importa il piano") {
            Pagina {
                Text("Chiedi alla chat il piano dei giorni che vuoi e incolla qui la risposta. Le staccionate ``` vanno bene: le tolgo io.").font(.footnote).foregroundStyle(Color.secondarioLife)
                Button {
                    UIPasteboard.general.string = pas("importa.PROMPT_CHAT").t
                    avviso("Prompt copiato.")
                } label: { Label("Copia il prompt per la chat", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                TextEditor(text: $testo)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if !giorni.isEmpty {
                    Sezione("Cosa entra") {
                        Carta(padding: 12) {
                            RigaFin(titolo: "Giorni", valore: "\(giorni.count) · \(dataUmana(giorni[0].data.t)) → \(dataUmana(giorni[giorni.count - 1].data.t))")
                            RigaFin(titolo: "Pasti", valore: "\(quanti)")
                            RigaFin(titolo: "Cibi nuovi", valore: letto.nuovi.list.isEmpty ? "nessuno" : "\(letto.nuovi.list.count)")
                        }
                    }
                    Text("Niente è ancora scritto. Dopo «Importa» ti faccio verificare giorno per giorno.").font(.caption).foregroundStyle(Color.secondarioLife)
                    if !letto.nuovi.list.isEmpty {
                        Sezione("Entrano nel database") {
                            Carta(padding: 12) {
                                ForEach(letto.nuovi.list.prefix(12), id: \.nome) { n in
                                    RigaFin(titolo: n.nome.t, sotto: n.porzione.str, valore: "\(kcal(n.kcal)) kcal")
                                }
                                if letto.nuovi.list.count > 12 { Text("e altri \(letto.nuovi.list.count - 12).").font(.footnote).foregroundStyle(Color.secondarioLife) }
                            }
                        }
                    }
                    Sezione("I giorni") {
                        Carta(padding: 12) {
                            ForEach(giorni, id: \.data) { g in
                                RigaFin(titolo: dataUmana(g.data.t), sotto: g.pasti.list.map { pas("dati.nomeFascia", $0.fascia).t }.joined(separator: " · "), valore: "\(g.pasti.list.reduce(0) { $0 + $1.componenti.list.count }) voci")
                            }
                        }
                    }
                }
                if !letto.problemi.list.isEmpty {
                    Sezione(giorni.isEmpty ? "Non ci siamo" : "Righe saltate") {
                        Carta(padding: 12) {
                            ForEach(letto.problemi.list.prefix(8), id: \.self) { p in Text(p.t).font(.footnote).foregroundStyle(Color.pericoloLife) }
                        }
                    }
                }
                PulsantePieno(testo: giorni.isEmpty ? "Importa" : "Importa \(plurale(Double(giorni.count), "giorno", "giorni")) e verifica", colore: accentoPas) {
                    let r = pas("importa.applicaPiano", letto)
                    avviso("\(plurale(r.fasce, "pasto messo", "pasti messi")) in \(plurale(Double(r.date.list.count), "giorno", "giorni")).")
                    let date = r.date.list.map(\.t)
                    chiudi()
                    verifica(date)
                }
                .disabled(giorni.isEmpty)
                .opacity(giorni.isEmpty ? 0.5 : 1)
            }
        }
    }
}

// MARK: - Pianifica

struct Pianifica: View {
    let giorni: [String]
    @ObservedObject private var logica = Logica.s
    @State private var passo = -1
    @State private var aperta: String?
    @State private var bozza: [String: [String]] = [:]
    @State private var giornoInBozza: String?
    @Environment(\.dismiss) private var chiudi

    private var lunedi: String { pas("dati.lunediDi", .str(giorni[0])).t }
    private var iso: String? { passo >= 0 && passo < giorni.count ? giorni[passo] : nil }
    private var fasce: [J] { pas("dati.FASCE").list }

    var body: some View {
        let _ = logica.versione
        let b = pas("calcolo.bersagli")
        return NavigationStack {
            Pagina {
                if passo >= 0 {
                    HStack(spacing: 4) {
                        ForEach(giorni.indices, id: \.self) { i in
                            Capsule().fill(i <= passo ? accentoPas : Color(uiColor: .tertiarySystemFill)).frame(height: 4)
                        }
                    }
                }
                if passo < 0 {
                    introduzione(b)
                } else if passo >= giorni.count {
                    riepilogo(b)
                } else {
                    giorno(b)
                }
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Pasti") {
                        salvaGiorno()
                        chiudi()
                    }
                }
            }
        }
        .onChange(of: passo) { _, _ in caricaBozza() }
    }

    private var titolo: String {
        guard let iso else { return passo < 0 ? "Pianifica" : "Ci siamo" }
        let u = dataUmana(iso)
        if ["oggi", "ieri", "domani"].contains(u) { return u.maiuscola }
        return "\(Tempo.settimanaLunga[Tempo.giornoSettimana(iso)].maiuscola) \(Tempo.parti(iso).2)"
    }

    private func caricaBozza() {
        guard let iso, giornoInBozza != iso else { return }
        let piano = pas("dati.pianoSettimana", .str(lunedi))
        var nuova: [String: [String]] = [:]
        for f in pas("dati.ID_FASCE").list { nuova[f.t] = pas("dati.vociPiano", piano, .str(iso), f).list.map(\.t) }
        bozza = nuova
        giornoInBozza = iso
        aperta = fasce.first { pas("dati.regimeDi", .str(iso), $0.id).t == "casa" && (nuova[$0.id.t] ?? []).isEmpty }?.id.t
    }

    private func salvaGiorno() {
        guard let iso else { return }
        for f in pas("dati.ID_FASCE").list {
            let prima = pas("dati.vociPiano", pas("dati.pianoSettimana", .str(lunedi)), .str(iso), f).list.map(\.t)
            let adesso = bozza[f.t] ?? []
            if prima != adesso { pas("dati.scegliVoci", .str(lunedi), .str(iso), f, .arr(adesso.map { .str($0) })) }
        }
    }

    private func vai(_ d: Int) {
        salvaGiorno()
        tocco()
        aperta = nil
        passo = max(-1, min(giorni.count, passo + d))
    }

    @ViewBuilder
    private func introduzione(_ b: J) -> some View {
        Carta {
            Text("📅").font(.largeTitle)
            Text(giorni.count == 7 ? "La settimana che viene" : "I prossimi \(giorni.count) giorni").font(.title2.bold())
            Text("Da \(dataUmana(giorni[0])) a \(dataUmana(giorni[giorni.count - 1])). Un giorno per schermata: tocchi quello che c'è nel piatto e il conto si fa da sé. Si salva mentre vai, quindi puoi fermarti e riprendere.").font(.subheadline).foregroundStyle(Color.secondarioLife)
            Text("Il bersaglio è \(kcal(b.kcal)) kcal e \(b["p"].t) g di proteine al giorno.").font(.footnote).foregroundStyle(Color.secondarioLife)
        }
        PulsantePieno(testo: "Cominciamo", colore: accentoPas) { vai(1) }
        PulsantePieno(testo: "Riempi tu, correggo io", colore: Color(uiColor: .systemGray)) {
            let e = pas("piano.assicuraPiano", .str(lunedi), ["forza": true])
            giornoInBozza = nil
            avviso(e.creato.vero ? "Riempita. Ora correggi quello che non ti va." : "Non fatto: \(e.motivo.t).", errore: !e.creato.vero)
        }
    }

    @ViewBuilder
    private func riepilogo(_ b: J) -> some View {
        let piano = pas("dati.pianoSettimana", .str(lunedi))
        let righe = giorni.enumerated().map { i, g -> (Int, String, Double, Double, Int) in
            let casa = fasce.filter { pas("dati.regimeDi", .str(g), $0.id).t == "casa" }
            let voci = casa.flatMap { pas("dati.vociPiano", piano, .str(g), $0.id).list }.map { pas("dati.pasto", $0) }.filter { !$0.isNull }
            let vuote = casa.filter { pas("dati.vociPiano", piano, .str(g), $0.id).list.isEmpty }.count
            return (i, g, voci.reduce(0) { $0 + $1.kcal.d }, voci.reduce(0) { $0 + $1["p"].d }, vuote)
        }
        let mancanti = righe.reduce(0) { $0 + $1.4 }
        Sezione("Come è venuta") {
            Carta(padding: 12) {
                ForEach(righe, id: \.0) { r in
                    Button {
                        aperta = nil
                        passo = r.0
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Tempo.settimanaLunga[Tempo.giornoSettimana(r.1)].maiuscola).font(.subheadline.weight(.semibold))
                                Text(dataUmana(r.1)).font(.caption).foregroundStyle(Color.secondarioLife)
                            }
                            .frame(width: 92, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Barra(valore: b.kcal.vero ? r.2 / b.kcal.d : 0, colore: accentoPas, altezza: 5)
                                Text("\(kcal(r.2)) kcal · \(Int(r.3.rounded())) g prot.").font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife)
                            }
                            if r.4 > 0 { Text("\(r.4) da fare").font(.caption2).foregroundStyle(arancioneAvviso).padding(.horizontal, 5).background(arancioneAvviso.opacity(0.14), in: RoundedRectangle(cornerRadius: 4)) }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.terziarioLife)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Text(mancanti > 0 ? "\(mancanti) fasce sono ancora vuote. Puoi confermare lo stesso: quelle restano da decidere." : "Tutte le fasce hanno qualcosa. Da qui in poi la settimana è tua e il generatore non ci torna sopra.").font(.caption).foregroundStyle(Color.secondarioLife)
        PulsantePieno(testo: "Conferma la settimana", colore: accentoPas) {
            salvaGiorno()
            pas("dati.confermaPiano", .str(lunedi))
            avviso("Settimana pianificata.")
            chiudi()
        }
        Button("Torna all'ultimo giorno") { vai(-1) }.frame(maxWidth: .infinity).font(.subheadline)
    }

    @ViewBuilder
    private func giorno(_ b: J) -> some View {
        if let iso {
            let casa = fasce.filter { pas("dati.regimeDi", .str(iso), $0.id).t == "casa" }
            let voci = bozza.values.flatMap { $0 }.map { pas("dati.pasto", .str($0)) }.filter { !$0.isNull }
            let tot = (kcal: voci.reduce(0) { $0 + $1.kcal.d }, p: voci.reduce(0) { $0 + $1["p"].d }, c: voci.reduce(0) { $0 + $1["c"].d }, g: voci.reduce(0) { $0 + $1["g"].d })
            Text("Giorno \(passo + 1) di \(giorni.count)").font(.footnote).foregroundStyle(Color.secondarioLife)
            ForEach(casa, id: \.id) { f in
                let id = f.id.t
                let dentro = (bozza[id] ?? []).map { pas("dati.pasto", .str($0)) }.filter { !$0.isNull }
                let riassunto = dentro.map(\.nome.t).joined(separator: " + ")
                let conto = dentro.reduce(0) { $0 + $1.kcal.d }
                Carta(padding: 12) {
                    Button {
                        tocco()
                        aperta = aperta == id ? nil : id
                    } label: {
                        HStack(spacing: 10) {
                            Text(emojiFascia[id] ?? "🍽").frame(width: 36, height: 36).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(f.nome.t) \(f.ora.t)").font(.caption.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                                Text(riassunto.isEmpty ? "Da mettere" : riassunto).font(.subheadline).foregroundStyle(riassunto.isEmpty ? Color.secondarioLife : Color.primary).lineLimit(2)
                            }
                            Spacer()
                            if conto > 0 { Text("\(kcal(conto)) kcal").font(.footnote.weight(.semibold)).monospacedDigit() }
                            Image(systemName: aperta == id ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(Color.terziarioLife)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if aperta == id {
                        SceltaComponenti(scelti: Binding(get: { bozza[id] ?? [] }, set: { bozza[id] = $0 }), fascia: id, bersaglio: b.kcal.d)
                    }
                }
            }
            Blocco(eti: "Il giorno") {
                (Text(kcal(tot.kcal)).font(.title2.weight(.semibold)).monospacedDigit() + Text(" / \(kcal(b.kcal)) kcal").font(.subheadline).foregroundColor(Color.secondarioLife))
                Text("\(Int(tot.p.rounded()))/\(b["p"].t) g Prot. · \(Int(tot.c.rounded()))/\(b["c"].t) g Carb. · \(Int(tot.g.rounded()))/\(b["g"].t) g Grassi").font(.caption).foregroundStyle(Color.secondarioLife)
                Barra(valore: b.kcal.vero ? tot.kcal / b.kcal.d : 0, colore: accentoPas)
            }
            HStack(spacing: 8) {
                if passo > 0 {
                    PulsantePieno(testo: "Come ieri", colore: Color(uiColor: .systemGray)) {
                        let piano = pas("dati.pianoSettimana", .str(lunedi))
                        var nuova = bozza
                        for f in casa { nuova[f.id.t] = pas("dati.vociPiano", piano, .str(giorni[passo - 1]), f.id).list.map(\.t) }
                        bozza = nuova
                    }
                }
                PulsantePieno(testo: passo == giorni.count - 1 ? "Vedi il riepilogo" : "Avanti", colore: accentoPas) { vai(1) }
            }
            if passo > 0 { Button("Indietro") { vai(-1) }.frame(maxWidth: .infinity).font(.subheadline) }
        }
    }
}

// MARK: - Altro

struct ImpostazioniPasti: View {
    let importa: () -> Void
    let pianifica: ([String]) -> Void
    let restanti: [String]
    let prossima: [String]
    @State private var fasciaDb: IdTesto?

    private func scrivi(_ m: J) { pas("dati.scriviProfilo", m) }

    var body: some View {
        let p = pas("dati.profilo")
        let b = pas("calcolo.bersagli")
        let cop = pas("calcolo.copertura")
        let promuovere = pas("calcolo.daPromuovere").list
        let fasce = pas("dati.FASCE").list
        let fuori = pas("dati.ID_FASCE").list.filter { f in p.settimanaTipo.list.contains { $0[f.t].t == "fuori" } }
        return VStack(alignment: .leading, spacing: 16) {
            Sezione("Te") {
                Carta(padding: 12) {
                    numero("Peso", pas("dati.pesoAttuale").d, "kg", decimali: true) { n in
                        if n > 0 {
                            pas("dati.registraPeso", .num(n))
                            avviso("Pesata segnata.")
                        }
                    }
                    numero("Altezza", p.altezzaCm.d, "cm") { scrivi(["altezzaCm": .num($0)]) }
                    numero("Età", pas("calcolo.eta", p).d, "anni") { scrivi(["etaDichiarata": .num($0), "etaDichiarataIl": Logica.s.chiama("ui.oggiISO"), "nascita": ""]) }
                }
            }
            Text("Il peso è una serie, non un numero: ne hai \(plurale(Double(pas("dati.serieePesi").list.count), "pesata", "pesate")). Il fabbisogno cresce insieme a te.").font(.caption).foregroundStyle(Color.secondarioLife)
            Sezione("La settimana") {
                Carta(padding: 12) {
                    RigaFin(titolo: "Pianifica i giorni che restano", sotto: "Un giorno per schermata, tocchi quello che c'è nel piatto", freccia: true) { pianifica(restanti) }
                    RigaFin(titolo: "Pianifica la settimana prossima", sotto: "Da lunedì, tutti e sette", freccia: true) { pianifica(prossima) }
                }
            }
            Sezione("Obiettivo") {
                Carta(padding: 12) {
                    Picker("Obiettivo", selection: Binding(get: { p.obiettivo.t }, set: { scrivi(["obiettivo": .str($0)]) })) {
                        ForEach(pas("dati.OBIETTIVI").dict.sorted { $0.key < $1.key }, id: \.key) { k, v in Text(v.nome.t).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    Text("Attività").font(.caption).foregroundStyle(Color.secondarioLife)
                    Picker("Attività", selection: Binding(get: { p.attivita.t }, set: { scrivi(["attivita": .str($0)]) })) {
                        ForEach(pas("dati.ATTIVITA").dict.sorted { $0.key < $1.key }, id: \.key) { k, v in Text(v.nome.t).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    numero("Surplus", p.surplusKcal.d, "kcal") { scrivi(["surplusKcal": .num($0)]) }
                    numero("Proteine", p.proteineGkg.d, "g/kg", decimali: true) { scrivi(["proteineGkg": .num($0)]) }
                    numero("Grassi", p.grassiGkg.d, "g/kg", decimali: true) { scrivi(["grassiGkg": .num($0)]) }
                }
            }
            Sezione("Il tuo fabbisogno") {
                Carta(padding: 12) {
                    RigaFin(titolo: "Metabolismo basale", valore: "\(kcal(pas("calcolo.metabolismoBasale"))) kcal")
                    RigaFin(titolo: "Mantenimento", valore: "\(kcal(pas("calcolo.mantenimento"))) kcal")
                    RigaFin(titolo: "Bersaglio", valore: "\(kcal(b.kcal)) kcal", coloreValore: accentoPas)
                    RigaFin(titolo: "Proteine", valore: "\(Int(b["p"].d.rounded())) g")
                    RigaFin(titolo: "Carboidrati", valore: "\(Int(b["c"].d.rounded())) g")
                    RigaFin(titolo: "Grassi", valore: "\(Int(b["g"].d.rounded())) g")
                }
            }
            Text("Proteine e grassi si fissano sul peso perché sono fabbisogni; i carboidrati prendono quello che resta, perché sono il carburante.").font(.caption).foregroundStyle(Color.secondarioLife)
            Sezione("La settimana tipo") {
                Carta(padding: 12) {
                    Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                        GridRow {
                            Color.clear.frame(height: 1)
                            ForEach(0..<7, id: \.self) { i in Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.caption2).foregroundStyle(Color.secondarioLife) }
                        }
                        ForEach(fasce, id: \.id) { f in
                            GridRow {
                                Text(f.nome.t).font(.footnote).lineLimit(1).minimumScaleFactor(0.7).gridColumnAlignment(.leading)
                                ForEach(0..<7, id: \.self) { i in
                                    let r = p.settimanaTipo[i][f.id.t].str ?? "salto"
                                    Button { gira(p, i, f.id.t) } label: {
                                        RoundedRectangle(cornerRadius: 7).fill(coloreRegime(r)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.lineaLife, lineWidth: r == "salto" ? 0.5 : 0)).frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        ForEach([("casa", "A casa"), ("fuori", "Fuori"), ("salto", "Non lo faccio")], id: \.0) { r in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3).fill(coloreRegime(r.0)).frame(width: 12, height: 12)
                                Text(r.1).font(.caption2).foregroundStyle(Color.secondarioLife)
                            }
                        }
                    }
                }
            }
            Text("Tocca una casella per girare fra casa, fuori e saltato.").font(.caption).foregroundStyle(Color.secondarioLife)
            if !fuori.isEmpty {
                Sezione("Quando mangi fuori") {
                    Carta(padding: 12) {
                        ForEach(fuori, id: \.self) { f in
                            let s = p.stimeFuori[f.t]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pas("dati.nomeFascia", f).t).font(.footnote.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                                HStack {
                                    ForEach([("kcal", "kcal"), ("p", "Prot."), ("c", "Carb."), ("g", "Grassi")], id: \.0) { k, et in
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(et).font(.caption2).foregroundStyle(Color.secondarioLife)
                                            CampoNumero(valore: s[k].d) { n in
                                                var nuova = s.isNull ? (["kcal": 0, "p": 0, "c": 0, "g": 0] as J) : s
                                                nuova[k] = .num(n)
                                                var tutte = p.stimeFuori
                                                if tutte.isNull { tutte = [:] }
                                                tutte[f.t] = nuova
                                                scrivi(["stimeFuori": tutte])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text("Una stima, non una misura. Ma uno zero al posto del pranzo renderebbe bugiardo il bilancio di quattro giorni su sette.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            Sezione("Il database") {
                Carta(padding: 12) {
                    ForEach(Array(cop.avvisi.list.enumerated()), id: \.offset) { _, a in Text(a.testo.t).font(.footnote).foregroundStyle(arancioneAvviso) }
                    ForEach(fasce, id: \.id) { f in
                        RigaFin(titolo: f.nome.t, valore: plurale(Double(pas("dati.pastiPerFascia", f.id).list.count), "pasto", "pasti"), freccia: true) { fasciaDb = IdTesto(id: f.id.t) }
                    }
                    RigaFin(titolo: "Importa dalla chat", accento: true, azione: importa)
                }
            }
            if !promuovere.isEmpty {
                Sezione("Lo mangi spesso") {
                    Carta(padding: 12) {
                        ForEach(promuovere, id: \.nome) { t in
                            RigaFin(titolo: t.nome.t, sotto: "\(plurale(t.volte, "volta", "volte"))\(t.ora.vero ? " · verso le \(t.ora.t)" : "")", valore: "aggiungi") {
                                var voce: J = ["nome": t.nome, "fasce": t.fascia.vero ? [t.fascia] : [], "fonte": "appreso"]
                                for (k, v) in t.macro.dict { voce[k] = v }
                                pas("dati.salvaPasti", [voce])
                                avviso("Nel database.")
                            }
                        }
                    }
                }
                Text("Queste cose tornano da sole. Aggiungile al database e il generatore potrà usarle.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
        }
        .sheet(item: $fasciaDb) { f in DatabaseFascia(fascia: f.id) }
    }

    private func numero(_ t: String, _ v: Double, _ u: String, decimali: Bool = false, _ salva: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(t).font(.subheadline)
            Spacer()
            CampoNumero(valore: v, unita: u, decimali: decimali, salva: salva)
        }
    }

    private func coloreRegime(_ r: String) -> Color {
        r == "casa" ? accentoPas : r == "fuori" ? arancioneAvviso : Color(uiColor: .tertiarySystemFill)
    }

    private func gira(_ p: J, _ i: Int, _ fascia: String) {
        let ordine = ["casa", "fuori", "salto"]
        var l = p.settimanaTipo.list
        guard l.indices.contains(i) else { return }
        let ora = l[i][fascia].str ?? "salto"
        l[i][fascia] = .str(ordine[((ordine.firstIndex(of: ora) ?? 2) + 1) % 3])
        tocco()
        scrivi(["settimanaTipo": .arr(l)])
    }
}

struct DatabaseFascia: View {
    let fascia: String
    @ObservedObject private var logica = Logica.s

    var body: some View {
        let _ = logica.versione
        let voci = pas("dati.pastiVivi").list.filter { $0.fasce.list.contains(.str(fascia)) }
        return Foglio(titolo: pas("dati.nomeFascia", .str(fascia)).t) {
            List {
                if voci.isEmpty {
                    Text("Niente qui dentro. Importane dalla chat.").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
                ForEach(voci, id: \.id) { x in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(x.nome.t).font(.subheadline)
                        Text("\(kcal(x.kcal)) kcal · \(x["p"].t) P · \(x["c"].t) C · \(x["g"].t) G\(x.attivo == false ? " · spento" : "")").font(.caption).foregroundStyle(Color.secondarioLife)
                        HStack {
                            Button(x.attivo == false ? "Riattiva" : "Spegni") { pas("dati.alternaAttivo", x.id) }.buttonStyle(.bordered)
                            Button("Elimina", role: .destructive) {
                                pas("dati.eliminaPasto", x.id)
                                avviso("Eliminato.")
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                }
                Text("«Spegni» lo lascia nello storico ma il generatore non lo usa più. «Elimina» lo toglie e basta.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
        }
    }
}
