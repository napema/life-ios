import Charts
import SwiftUI
import UniformTypeIdentifiers

// Finanze: Riepilogo, Movimenti, Analisi, Altro. I conti sono quelli di ATLAS, nel bundle JS.

/// Abbreviazioni per chiamare la logica di Finanze.
private let L = Logica.s
func fin(_ f: String, _ a: J...) -> J { Logica.s.chiama("finanze.\(f)", argomenti: a) }

/// Quale foglio è aperto (uno alla volta, come fogli.ts).
struct FoglioFinanze: Identifiable {
    enum Tipo {
        case movimento(J?, String, J?)
        case dettaglio(String)
        case arrivo(J)
        case categoria(String, String)
        case sub(String, String, String)
        case ricarica(String)
        case pocket
        case lista
        case obiettivo
        case paga(String, Double?)
        case stipendio
        case previsto
        case ricorrente(String, J?)
        case chiusura
    }
    let id = UUID()
    let tipo: Tipo
}

final class Fogli: ObservableObject {
    static let s = Fogli()
    @Published var aperto: FoglioFinanze?

    func apri(_ t: FoglioFinanze.Tipo) {
        // Un foglio aperto da un altro: prima si chiude quello, poi si apre questo
        if aperto != nil {
            aperto = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.aperto = FoglioFinanze(tipo: t) }
        } else {
            aperto = FoglioFinanze(tipo: t)
        }
    }
    func chiudi() { aperto = nil }
}

// MARK: Aiuti (come comune.ts)

let accentoFinanze = Color(hex: "#FF9500")
let verdeEntrata = Color(hex: "#34C759")
let arancioneAvviso = Color(hex: "#FF9F0A")

func coloreCat(_ id: String?) -> Color {
    let c = ["fisse": "#8E8E93", "casa": "#0A84FF", "auto": "#FF9500", "spesa": "#30B0C7", "trasporti": "#5E5CE6", "cibo": "#FF2D55", "cura": "#AF52DE", "svago": "#FFCC00", "acc": "#5AC8FA", "risp": "#2E7D32"]
    return Color(hex: c[id ?? ""] ?? "#8E8E93")
}
func nomePocket(_ id: String?) -> String {
    ["principale": "Principale", "contanti": "Contanti", "cassa": "Cassa", "fisse": "Fisse", "ing": "ING", "fondo": "Fondo"][id ?? ""] ?? id ?? ""
}
func etichettaTipo(_ t: String) -> String { fin("dati.TIPI")[t].nome.t }
func testoDa(_ c: Double) -> String { c == 0 ? "" : String(format: "%.2f", c / 100).replacingOccurrences(of: ".", with: ",") }
func pulisciImporto(_ v: String) -> String {
    var s = v.replacingOccurrences(of: ".", with: ",").filter { $0.isNumber || $0 == "," }
    if let i = s.firstIndex(of: ",") {
        let dopo = s[s.index(after: i)...].filter { $0 != "," }
        s = String(s[...i]) + String(dopo.prefix(2))
    }
    return s
}
private func parteData(_ iso: String) -> (String, Int, String, Int) {
    let (y, m, d) = Tempo.parti(iso)
    return (Tempo.settimanaBreve[Tempo.giornoSettimana(iso)], d, Tempo.mesiBrevi[max(0, m - 1)], y)
}
func gg(_ iso: String) -> String { let p = parteData(iso); return "\(p.0) \(p.1)" }
func gm(_ iso: String) -> String { let p = parteData(iso); return "\(p.1) \(p.2)" }
func glm(_ iso: String) -> String { let p = parteData(iso); return "\(p.0) \(p.1) \(p.2)" }
func glma(_ iso: String) -> String { let p = parteData(iso); return "\(p.1) \(p.2) \(p.3)" }
func plurale(_ n: Double, _ a: String, _ b: String) -> String { "\(Int(n)) \(Int(n) == 1 ? a : b)" }
func plurale(_ v: J, _ a: String, _ b: String) -> String { plurale(v.d, a, b) }
func dataUmana(_ iso: String) -> String { Logica.s.chiama("ui.dataUmana", .str(iso)).t }
func dataBreve(_ iso: String) -> String { Logica.s.chiama("ui.dataBreve", .str(iso)).t }
func nuovoIdLogica(_ p: String) -> String { Logica.s.chiama("ui.nuovoId", .str(p)).t }
func avviso(_ t: String, errore: Bool = false) { Logica.s.mostra(t, errore ? "errore" : "info") }
func celebra(_ t: String) { Logica.s.mostra(t, "festa") }

/// Riga di un blocco: titolo a sinistra, valore a destra, tocco opzionale.
struct RigaFin: View {
    let titolo: String
    var sotto: String? = nil
    var valore: String? = nil
    var coloreValore: Color? = nil
    var accento = false
    var freccia = false
    var azione: (() -> Void)? = nil

    var body: some View {
        let corpo = HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titolo).font(.subheadline).foregroundStyle(accento ? accentoFinanze : Color.primary)
                if let sotto, !sotto.isEmpty { Text(sotto).font(.caption).foregroundStyle(Color.secondarioLife) }
            }
            Spacer(minLength: 8)
            if let valore { Text(valore).font(.subheadline).monospacedDigit().foregroundStyle(coloreValore ?? Color.primary).multilineTextAlignment(.trailing) }
            if freccia { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.terziarioLife) }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        if let azione {
            Button(action: azione) { corpo }.buttonStyle(.plain)
        } else {
            corpo
        }
    }
}

/// Blocco con etichetta in maiuscolo e nota a destra.
struct Blocco<Contenuto: View>: View {
    var eti: String? = nil
    var etiDx: String? = nil
    var tono: Color? = nil
    @ViewBuilder var contenuto: () -> Contenuto
    var body: some View {
        Carta {
            if eti != nil || etiDx != nil {
                HStack {
                    if let eti { Text(eti.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(tono ?? Color.secondarioLife) }
                    Spacer()
                    if let etiDx { Text(etiDx).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                }
            }
            contenuto()
        }
    }
}

// MARK: - La schermata

struct VistaFinanze: View {
    private static var migrato = false
    init(scheda: String) { self.scheda = scheda }

    @ObservedObject private var logica = Logica.s
    @ObservedObject private var fogli = Fogli.s
    let scheda: String
    @State private var ciclo = ""
    @State private var filtro = "tutti"

    private let filtri = [("tutti", "Tutti"), ("out", "Uscite"), ("ecc", "Straordinari"), ("in", "Entrate"), ("extra", "Sforamenti"), ("altri", "Altri")]

    var body: some View {
        let _ = logica.versione
        return Pagina {

            if scheda == "movimenti" || scheda == "analisi" { selettoreCiclo }

            switch scheda {
            case "movimenti":
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filtri, id: \.0) { f in
                            Pillola(testo: f.1, attiva: filtro == f.0, colore: accentoFinanze) { filtro = f.0 }
                        }
                    }
                }
                ListaMovimenti(indice: cicloCorrente, filtro: filtro)
            case "analisi":
                AnalisiFinanze(indice: cicloCorrente)
            case "altro":
                ImpostazioniFinanze()
            default:
                Riepilogo()
            }
        }
        .navigationTitle(scheda == "movimenti" ? "Movimenti" : scheda == "analisi" ? "Analisi" : scheda == "altro" ? "Altro" : "Finanze")
        .toolbar {
            Button { fogli.apri(.pocket) } label: { Image(systemName: "wallet.pass") }
        }
        .onAppear {
            if !Self.migrato {
                Self.migrato = true
                fin("dati.migra")
            }
            if ciclo.isEmpty { ciclo = fin("calcolo.cicloDi").indice.t }
        }
    }

    private var cicloCorrente: String { ciclo.isEmpty ? fin("calcolo.cicloDi").indice.t : ciclo }

    private var selettoreCiclo: some View {
        let ora = fin("calcolo.cicloDi").indice.t
        let primo = fin("analisi.primoCiclo").indice.t
        let visto = fin("calcolo.spostaCiclo", .str(cicloCorrente), 0)
        return HStack {
            Button { ciclo = fin("calcolo.spostaCiclo", .str(cicloCorrente), -1).indice.t } label: { Image(systemName: "chevron.left") }
                .disabled(cicloCorrente <= primo)
            Spacer()
            Button { ciclo = ora } label: {
                Text(fin("calcolo.nomeCiclo", visto).t).font(.subheadline.weight(.semibold)).monospacedDigit()
                    + Text(cicloCorrente == ora ? " · in corso" : "").font(.subheadline).foregroundColor(Color.secondarioLife)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { ciclo = fin("calcolo.spostaCiclo", .str(cicloCorrente), 1).indice.t } label: { Image(systemName: "chevron.right") }
                .disabled(cicloCorrente >= ora)
        }
        .tint(accentoFinanze)
    }
}

/// Apre il foglio giusto.
struct FoglioFinanzeVista: View {
    let foglio: FoglioFinanze
    var body: some View {
        switch foglio.tipo {
        case .movimento(let m, let t, let p): FoglioMovimento(movimento: m, tipoIniziale: t, preset: p)
        case .dettaglio(let id): FoglioDettaglio(id: id)
        case .arrivo(let v): FoglioArrivo(voce: v)
        case .categoria(let c, let m): FoglioCategoria(catId: c, mese: m)
        case .sub(let c, let s, let m): FoglioSub(catId: c, sub: s, mese: m)
        case .ricarica(let q): FoglioRicariche(quale: q)
        case .pocket: FoglioPocket()
        case .lista: FoglioLista()
        case .obiettivo:
            if fin("piano.eCuscinetto").vero { FoglioCuscinetto() } else { FoglioObiettivo() }
        case .paga(let d, let e): FoglioPaga(dataStip: d, entrata: e)
        case .stipendio: FoglioStipendio()
        case .previsto: FoglioRicorrente(genere: "previsto", esistente: nil)
        case .ricorrente(let g, let e): FoglioRicorrente(genere: g, esistente: e)
        case .chiusura: FoglioChiusura()
        }
    }
}

// MARK: - Riepilogo

private let notaPocket = ["principale": "spendibile", "contanti": "in tasca", "cassa": "parcheggio", "fisse": "addebiti automatici", "ing": "riserva · cuscinetto", "fondo": "obiettivo"]

struct Riepilogo: View {
    private var fogli: Fogli { .s }

    var body: some View {
        let oggi = Logica.s.chiama("ui.oggiISO")
        let ciclo = fin("calcolo.cicloDi", oggi)
        let pk = fin("calcolo.pocketConSaldi").list
        let q = fin("piano.quotaDi", oggi)
        let configurato = pk.contains { $0.ancoraDa.vero || $0.saldo.vero }
        let obi = fin("piano.tiroObiettivo", oggi)
        let cus = fin("piano.cuscinetto", oggi)
        let passo = fin("piano.passoObiettivo", oggi)
        let domani = fin("piano.quotaDomani", oggi)
        let travasi = fin("travasi.pianoTravasi", oggi)
        let prossimo = fin("calcolo.prossimoStipendio", oggi)
        let versaProssimo = fin("paga.travasiPaga", prossimo).righe.list.first { $0.id.t == "fondo" }?.imp.d ?? 0
        let fp = fin("piano.fuoriPianoDelCiclo", ciclo, oggi)
        let ing = fin("piano.ingPrevisto", oggi)
        let arrivo = fin("piano.inArrivoDiviso", 14, oggi)
        let stipendio = fin("stipendio.stipendioAtteso", oggi)
        let ritmo = fin("gruppi.ritmoQuotidiano", ciclo, oggi)
        let dove = fin("gruppi.doveSiPerde", ciclo, 3).list
        let all = fin("chiusura.allineamento", oggi)
        let totale = pk.reduce(0) { $0 + $1.saldoVero.d }
        let nLista = fin("dati.stato").lista.list.filter { !$0.del.vero && ($0.stato.t == "attesa" || $0.stato.isNull) }.count
        let oltre = q.resta.d < 0
        let paga = arrivo.paga.t
        let prima = (arrivo.prima.voci.list + arrivo.entrate.list.filter { $0.quando.t < paga }).sorted { $0.quando.t < $1.quando.t }
        let dopo = (arrivo.dopo.list + arrivo.entrate.list.filter { $0.quando.t >= paga }).sorted { $0.quando.t < $1.quando.t }

        VStack(alignment: .leading, spacing: 14) {
            if !cus.isNull {
                bloccoCuscinetto(cus, oggi.t)
            } else if !obi.isNull {
                bloccoObiettivo(obi, passo: passo, versaProssimo: versaProssimo)
            }

            Blocco(eti: "Oggi", etiDx: configurato ? "\(plurale(q.giorni, "giorno", "giorni")) allo stipendio" : nil) {
                if !configurato {
                    Text("—").font(.largeTitle).foregroundStyle(Color.secondarioLife)
                    PulsantePieno(testo: "Imposta i saldi", colore: accentoFinanze) { fogli.apri(.pocket) }
                } else {
                    HStack(spacing: 14) {
                        Anello(valore: q.quota.d > 0 ? q.speso.d / q.quota.d : q.speso.d > 0 ? 1 : 0, misura: 62, spessore: 9, colore: oltre ? .pericoloLife : accentoFinanze)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(euro(q.resta)).font(.system(size: 36, weight: .semibold)).monospacedDigit().foregroundStyle(oltre ? Color.pericoloLife : Color.primary).lineLimit(1).minimumScaleFactor(0.6)
                            Text(oltre ? "oltre la razione di oggi" : "puoi ancora spendere").font(.footnote).foregroundStyle(oltre ? Color.pericoloLife : Color.secondarioLife)
                        }
                    }
                    HStack(spacing: 8) {
                        casellina("Razione", euro(q.quota))
                        casellina("Speso", euro(q.speso), oltre ? .pericoloLife : nil)
                        casellina(domani.isNull ? "Stipendio" : "Domani", domani.isNull ? "domani" : euro(domani.quota))
                    }
                }
            }

            if configurato { VistaPianoTravasi(piano: travasi) }

            Carta {
                RigaFin(titolo: "Lista d'attesa", valore: nLista > 0 ? "\(nLista)" : nil, freccia: true) { fogli.apri(.lista) }
            }

            if ritmo.budget.d > 0 { bloccoRitmo(ritmo, ciclo: ciclo, dove: dove) }

            Blocco(eti: "Fuori piano · questo ciclo", etiDx: fp.n.vero ? "\(fp.n.int ?? 0) · \(euro(fp.totale, tondo: true))" : "0", tono: fp.n.vero ? .pericoloLife : nil) {
                if !fp.n.vero {
                    Text("\(plurale(fp.giorniSenza, "giorno", "giorni")) senza fuori piano").font(.subheadline).foregroundStyle(Color.successoLife)
                } else {
                    ForEach(fp.voci.list.prefix(5), id: \.id) { m in
                        rigaElenco(data: gm(m.data.t), nome: m.nota.str ?? "—", nota: m.daRiserva.vero ? "da ING" : nil, cifra: euro(fin("calcolo.importoEffettivo", m))) { fogli.apri(.dettaglio(m.id.t)) }
                    }
                    if fp.voci.list.count > 5 { Text("+\(fp.voci.list.count - 5)").font(.caption).foregroundStyle(Color.secondarioLife) }
                    if !fp.pct.isNull {
                        Text(!cus.isNull ? "= \(Int((fp.pct.d * 100).rounded()))% del versamento mensile" : fp.pct.d >= 0.95 ? "vale \(String(format: "%.1f", fp.pct.d).replacingOccurrences(of: ".", with: ",")) versamenti al fondo" : "vale \(Int((fp.pct.d * 100).rounded()))% di un versamento al fondo").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    if fp.ricariche.n.d > 0 {
                        Text("ricariche da ING non pianificate: \(fp.ricariche.n.int ?? 0) · \(euro(fp.ricariche.totale, tondo: true))").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                }
            }

            Blocco(eti: "In arrivo · 14 giorni", etiDx: arrivo.prima.totale.vero ? euro(arrivo.prima.totale, tondo: true) : nil) {
                if stipendio.dovuto.vero { rigaStipendio(stipendio) }
                ForEach(prima, id: \.self) { v in
                    if v.entrata.vero {
                        rigaElenco(data: gg(v.quando.t), nome: v.nome.t, nota: "su \(nomePocket(v.pocket.str)) · in entrata", cifra: "+\(euro(v.importo))") { fogli.apri(.arrivo(v)) }
                    } else {
                        let cop = arrivo.prima.perPocket[v.pocket.str ?? "principale"]
                        let scoperto = !cop.isNull && !cop.coperto.vero
                        rigaElenco(data: gg(v.quando.t), nome: v.nome.t, nota: "\(nomePocket(v.pocket.str)) · \(scoperto ? "manca \(euro(cop.scoperto, tondo: true))" : "coperto")", notaMale: scoperto, cifra: euro(v.importo)) { fogli.apri(.arrivo(v)) }
                    }
                }
                // Lo stipendio e il giorno di paga: una riga sola, che separa prima e dopo
                if !stipendio.dovuto.vero { rigaStipendio(stipendio) }
                ForEach(dopo, id: \.self) { v in
                    rigaElenco(data: gg(v.quando.t), nome: v.nome.t, nota: v.entrata.vero ? "su \(nomePocket(v.pocket.str)) · in entrata" : nil, cifra: "\(v.entrata.vero ? "+" : "")\(euro(v.importo))", smorzata: !v.entrata.vero) { fogli.apri(.arrivo(v)) }
                }
            }

            Blocco(eti: "Pocket") {
                Button { fogli.apri(.chiusura) } label: {
                    Text(all.quando.str.map { "allineato all'estratto: \(gm($0))" } ?? "mai allineato").font(.caption).foregroundStyle(all.vecchio.vero ? arancioneAvviso : Color.secondarioLife)
                }
                .buttonStyle(.plain)
                ForEach(pk, id: \.id) { p in
                    rigaElenco(data: nil, nome: p.nome.t, nota: !obi.isNull && p.id == obi.pocket ? "salvadanaio · \(obi.nome.t)" : notaPocket[p.id.t] ?? fin("dati.TIPI_POCKET")[p.tipo.t].nome.t, cifra: euro(p.saldoVero), coloreCifra: p.saldoVero.d < 0 ? .pericoloLife : nil) { fogli.apri(.pocket) }
                }
                if cus.isNull {
                    Text("ING minimo previsto \(euro(ing.minimo, tondo: true)) · \(glm(ing.quando.t))").font(.footnote).foregroundStyle(ing.sotto.vero ? arancioneAvviso : Color.secondarioLife)
                }
                Text("tutto insieme: \(euro(totale, tondo: true))").font(.footnote).foregroundStyle(Color.secondarioLife)
            }
        }
    }

    private func casellina(_ e: String, _ v: String, _ colore: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(e).font(.caption2).foregroundStyle(Color.secondarioLife)
            Text(v).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(colore ?? Color.primary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Lo stipendio E il giorno di paga, una riga sola (prima erano due nello stesso giorno).
    private func rigaStipendio(_ s: J) -> some View {
        let fra = s.fra.int ?? 0
        let quando = fra == 0 ? "oggi" : fra == 1 ? "domani" : fra < 0 ? (fra == -1 ? "ieri" : "\(-fra) giorni fa") : "fra \(fra) giorni"
        return Button { fogli.apri(.stipendio) } label: {
            HStack(spacing: 10) {
                Text(gg(s.data.t)).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(verdeEntrata).frame(width: 54, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stipendio · giorno di paga").font(.subheadline.weight(.semibold))
                    Text("\(quando)\(s.dovuto.vero ? " · da aggiungere" : " · su Principale")\(s.soloQuesto.vero ? " · importo di questo mese" : "")")
                        .font(.caption).foregroundStyle(fra < 0 ? Color.pericoloLife : Color.secondarioLife)
                }
                Spacer(minLength: 6)
                Text("+\(euro(s.importo))").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(verdeEntrata)
            }
            .padding(8)
            .background(verdeEntrata.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bloccoCuscinetto(_ c: J, _ oggi: String) -> some View {
        Button { fogli.apri(.obiettivo) } label: {
            Blocco(eti: "ING · cuscinetto", etiDx: "target \(euro(c.target, tondo: true))\(c.regola.vero ? " · \(c.regola.t)" : "")", tono: c.livello.t == "male" ? .pericoloLife : c.livello.t == "avviso" ? arancioneAvviso : nil) {
                HStack(alignment: .firstTextBaseline) {
                    Text(euro(c.saldo)).font(.title2.weight(.semibold)).monospacedDigit()
                    Text("/ \(euro(c.target, tondo: true))").font(.footnote).foregroundStyle(Color.secondarioLife)
                    Spacer()
                    Text("\(Int((c.frazione.d * 100).rounded()))%").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Barra(valore: c.frazione.d, colore: accentoFinanze)
                Text("minimo previsto \(euro(c.minimo)) · \(gm(c.quando.t))").font(.footnote).monospacedDigit()
                if let d = c.sopraDal.str {
                    Text(d == oggi ? "sopra target" : "sopra target dal \(glma(d))").font(.footnote).foregroundStyle(Color.secondarioLife)
                } else {
                    Text("non resta sopra target nei prossimi 12 mesi").font(.footnote).foregroundStyle(arancioneAvviso)
                }
                if !c.prossimo.isNull {
                    Text("prossimo versamento \(euro(c.prossimo.imp, tondo: true)) · \(glm(c.prossimo.quando.t))").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func bloccoObiettivo(_ obi: J, passo: J, versaProssimo: Double) -> some View {
        let giusto = obi.inPiu.vero ? obi.versamento.d + obi.inPiu.d : obi.versamento.d
        let prossimo = passo.prossimo.str ?? obi.prossimo.str
        return Carta {
            Button { fogli.apri(.obiettivo) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(obi.nome.t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                        Spacer()
                        Text("entro \(glma(obi.data.t))").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                    HStack {
                        Text(euro(obi.saldo, tondo: true)).font(.title2.weight(.semibold)).monospacedDigit()
                        Text("di \(euro(obi.target, tondo: true))").font(.footnote).foregroundStyle(Color.secondarioLife)
                        Spacer()
                        Anello(valore: obi.frazione.d, misura: 38, spessore: 6, colore: accentoFinanze)
                    }
                }
            }
            .buttonStyle(.plain)
            if passo.tipo.t == "da-fare" {
                Button { fogli.apri(.paga(passo.dataStip.t, nil)) } label: {
                    HStack {
                        Text("Adesso: \(euro(passo.imp, tondo: true)) sul fondo").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(accentoFinanze, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if !passo.isNull {
                HStack(spacing: 8) {
                    Image(systemName: passo.tipo.t == "fatto" ? "checkmark" : "calendar")
                    if passo.tipo.t == "fatto" {
                        Text("Fatto per questo ciclo").fontWeight(.semibold) + Text(passo.prossimo.str.map { " · il prossimo \(glm($0))" } ?? "").foregroundColor(Color.secondarioLife)
                    } else {
                        Text("\(prossimo.map(glm) ?? "Al prossimo stipendio"): \(euro(versaProssimo, tondo: true)) sul fondo").fontWeight(.semibold)
                    }
                }
                .font(.footnote)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if obi.versamento.d > 0 {
                if obi.cela.vero {
                    Label {
                        Text("Così ci arrivi") + Text(obi.avanzo.d > 0 ? ", con \(euro(obi.avanzo, tondo: true)) di margine" : "").foregroundColor(Color.secondarioLife)
                    } icon: { Image(systemName: "checkmark") }
                    .font(.footnote)
                    .foregroundStyle(Color.successoLife)
                } else {
                    Label("Così arrivi a \(euro(obi.proiezione, tondo: true)), non a \(euro(obi.target, tondo: true)).", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(arancioneAvviso)
                    if obi.inPiu.d > 0 {
                        RigaFin(titolo: "Per arrivarci: \(euro(giusto, tondo: true)) a stipendio", freccia: true) { fogli.apri(.obiettivo) }
                    }
                }
            }
        }
    }

    private func bloccoRitmo(_ r: J, ciclo: J, dove: [J]) -> some View {
        let gia = min(1, r.quotidiano.d / r.budget.d)
        let passo = min(1, r.giorni.d / max(1, ciclo.giorni.d))
        let avanti = r.quotidiano.d > r.budget.d * passo
        return Blocco(eti: "Il ciclo · quotidiano", etiDx: "giorno \(r.giorni.int ?? 0) di \(ciclo.giorni.int ?? 0)") {
            HStack(alignment: .firstTextBaseline) {
                Text(euro(r.quotidiano, tondo: true)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("di \(euro(r.budget, tondo: true))").font(.footnote).foregroundStyle(Color.secondarioLife)
                Spacer()
                Text("\(Int((gia * 100).rounded()))%").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(avanti ? arancioneAvviso : Color.primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Barra(valore: gia, colore: avanti ? arancioneAvviso : accentoFinanze)
                    Capsule().fill(Color.primary).frame(width: 2, height: 14).offset(x: g.size.width * CGFloat(passo))
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            if r.attendibile.vero {
                HStack {
                    Text("\(euro(r.alGiorno))/g · piano \(euro(r.piano))/g").foregroundStyle(Color.secondarioLife)
                    Spacer()
                    if r.proiezione.d > 0 {
                        Text("+\(euro(r.proiezione, tondo: true)) a fine ciclo").foregroundStyle(arancioneAvviso)
                    } else {
                        Text("dentro il piano").foregroundStyle(Color.secondarioLife)
                    }
                }
                .font(.footnote)
            }
            if !dove.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(dove, id: \.self) { x in
                            HStack(spacing: 4) {
                                Text(x.sub.t)
                                Text(euro(x.totale, tondo: true)).fontWeight(.semibold)
                                Text("\(x.n.int ?? 0)×").foregroundStyle(Color.secondarioLife)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
        }
    }
}

/// Riga con data, nome, nota e cifra.
func rigaElenco(data: String?, nome: String, nota: String? = nil, notaMale: Bool = false, cifra: String, coloreCifra: Color? = nil, smorzata: Bool = false, azione: @escaping () -> Void) -> some View {
    Button(action: azione) {
        HStack(spacing: 10) {
            if let data { Text(data).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife).frame(width: 54, alignment: .leading) }
            VStack(alignment: .leading, spacing: 1) {
                Text(nome).font(.subheadline).lineLimit(1)
                if let nota, !nota.isEmpty { Text(nota).font(.caption).foregroundStyle(notaMale ? Color.pericoloLife : Color.secondarioLife).lineLimit(1) }
            }
            Spacer(minLength: 6)
            Text(cifra).font(.subheadline).monospacedDigit().foregroundStyle(coloreCifra ?? Color.primary)
        }
        .opacity(smorzata ? 0.55 : 1)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

struct VistaPianoTravasi: View {
    let piano: J
    var fatto: (() -> Void)? = nil

    var body: some View {
        if piano.esito.t != "stipendio" {
            let f = piano.f
            let quando = f.tronca.vero ? "fino allo stipendio" : f.prepara.vero ? "settimana \(gg(f.da.t)) – \(gg(f.a.t))" : "fino a \(gg(f.a.t))"
            let esito = piano.esito.t
            if piano.mosse.list.isEmpty, esito != "non-basta" {
                let stretto = esito == "stretto"
                Carta {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: stretto ? "exclamationmark.circle.fill" : "checkmark.circle.fill").font(.title3).foregroundStyle(stretto ? arancioneAvviso : Color.successoLife)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Niente da spostare").font(.subheadline.weight(.semibold))
                            Text(stretto ? "ma fino allo stipendio sono \(euro(piano.razione)) al giorno" : "il Principale arriva \(f.tronca.vero ? "allo stipendio" : "a \(gg(f.a.t))")").font(.footnote).foregroundStyle(Color.secondarioLife)
                        }
                    }
                }
            } else {
                Blocco(eti: "Da spostare", etiDx: quando, tono: esito == "non-basta" ? .pericoloLife : esito == "stretto" ? arancioneAvviso : nil) {
                    ForEach(piano.mosse.list, id: \.self) { m in mossa(m) }
                    if esito == "non-basta" {
                        Label {
                            Text("Mancano \(euro(piano.manca, tondo: true))").fontWeight(.semibold) + Text(" anche con tutta la Cassa. ") + Text("O li prendi da ING, o stringi a \(euro(piano.razioneMinima)) al giorno.").foregroundColor(Color.secondarioLife)
                        } icon: { Image(systemName: "exclamationmark.octagon") }
                        .font(.footnote)
                        .foregroundStyle(Color.pericoloLife)
                    } else {
                        HStack {
                            Text("\(euro(piano.razione)) al giorno fino allo stipendio").foregroundStyle(esito == "stretto" ? arancioneAvviso : Color.primary)
                            Spacer()
                            Text("ING non si tocca").foregroundStyle(Color.secondarioLife)
                        }
                        .font(.footnote)
                    }
                    if !piano.mosse.list.isEmpty {
                        PulsantePieno(testo: "Fatto su Revolut", colore: accentoFinanze) {
                            fin("travasi.eseguiTravasi", piano)
                            celebra("Travasi registrati")
                            fatto?()
                        }
                    }
                }
            }
        }
    }

    private func mossa(_ m: J) -> some View {
        let da = m.da.t
        return HStack(spacing: 8) {
            scatola(nomePocket(da), piano.dopo[da], piano.prima[da], tinta: false)
            VStack(spacing: 0) {
                Text(euro(m.imp, tondo: true)).font(.caption.weight(.semibold)).monospacedDigit()
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(accentoFinanze)
            scatola(nomePocket(m.a.t), piano.dopo[m.a.t], piano.prima[m.a.t], tinta: true)
        }
    }

    private func scatola(_ n: String, _ dopo: J, _ prima: J, tinta: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(n).font(.caption2).foregroundStyle(Color.secondarioLife)
            Text(euro(dopo)).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text("era \(euro(prima))").font(.caption2).foregroundStyle(Color.terziarioLife).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tinta ? accentoFinanze.opacity(0.12) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Movimenti

struct RigaMovimento: View {
    let m: J
    var body: some View {
        let tipo = m.tipo.t
        let cat = fin("dati.categoriaPerId", m.cat)
        let eff = fin("calcolo.importoEffettivo", m).d
        let origine: J = m.rif.vero ? (fin("dati.movimentiVivi").list.first { $0.id == m.rif } ?? .null) : .null
        let segno = ["in": "+", "out": "−", "extra": "−", "giro": "", "rimb": "+", "reso": "+"][tipo] ?? "−"
        let tinta: Color = tipo == "out" ? coloreCat(m.cat.str) : tipo == "in" ? verdeEntrata : tipo == "extra" ? .pericoloLife : Color(hex: "#8E8E93")
        let simbolo = tipo == "out" ? fin("dati.emojiCat", m.cat).t : tipo == "in" ? "↓" : tipo == "extra" ? "!" : tipo == "giro" ? "⇄" : "↩"
        let entra = ["in", "rimb", "reso"].contains(tipo)
        Button { Fogli.s.apri(.dettaglio(m.id.t)) } label: {
            HStack(spacing: 10) {
                Text(simbolo).font(.subheadline).foregroundStyle(tinta).frame(width: 32, height: 32).background(tinta.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(m.nota.vero ? m.nota.t : etichettaTipo(tipo)).font(.subheadline).lineLimit(1)
                        if tipo == "out", m.ecc.vero { etichetta("straordinaria", arancioneAvviso) }
                        if tipo == "extra" { etichetta("sforamento", .pericoloLife) }
                        if m.rivedi.vero { etichetta("da rivedere", Color(hex: "#AF52DE")) }
                    }
                    Text(descrivi(tipo, cat, origine)).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(segno)\(euro(tipo == "out" ? eff : m.imp.d))").font(.subheadline).monospacedDigit().foregroundStyle(entra ? verdeEntrata : Color.primary)
                    if tipo == "out", eff != m.imp.d { Text("lordo \(euro(m.imp))").font(.caption2).foregroundStyle(Color.secondarioLife) }
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { Fogli.s.apri(.dettaglio(m.id.t)) } label: { Label("Apri", systemImage: "arrow.up.forward.square") }
            Button { Fogli.s.apri(.movimento(m, tipo, nil)) } label: { Label("Modifica", systemImage: "pencil") }
            Button {
                Fogli.s.apri(.movimento(nil, tipo, ["imp": m.imp, "nota": m.nota, "cat": m.cat, "sub": m.sub, "pocket": m.pocket, "pocketTo": m.pocketTo]))
            } label: { Label("Duplica a oggi", systemImage: "plus.square.on.square") }
            Button { UIPasteboard.general.string = euro(m.imp) } label: { Label("Copia l'importo", systemImage: "doc.on.doc") }
            Button(role: .destructive) { fin("dati.eliminaMovimento", m.id) } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    private func etichetta(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.medium)).foregroundStyle(c).padding(.horizontal, 5).padding(.vertical, 1).background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }

    private func descrivi(_ t: String, _ cat: J, _ origine: J) -> String {
        switch t {
        case "out": return (cat.nome.str ?? "—") + (m.sub.vero ? " · \(m.sub.t)" : "")
        case "in": return "Entrata"
        case "giro": return "Giroconto tra pocket"
        case "extra": return "Ricarica fuori budget"
        default: return etichettaTipo(t) + (origine.isNull ? " · non agganciato" : " → \(origine.nota.t)")
        }
    }
}

struct ListaMovimenti: View {
    let indice: String
    let filtro: String
    var body: some View {
        var ms = fin("calcolo.movimentiDelCiclo", fin("analisi.cicloPerIndice", .str(indice))).list
        switch filtro {
        case "altri": ms = ms.filter { ["giro", "rimb", "reso"].contains($0.tipo.t) }
        case "ecc": ms = ms.filter { $0.tipo.t == "out" && $0.ecc.vero }
        case "out": ms = ms.filter { $0.tipo.t == "out" && !$0.ecc.vero }
        case "tutti": break
        default: ms = ms.filter { $0.tipo.t == filtro }
        }
        var giorni: [String] = []
        for m in ms where !giorni.contains(m.data.t) { giorni.append(m.data.t) }
        return Group {
            if giorni.isEmpty {
                Text("Nessun movimento. Con Uscita o Entrata qui in basso ne registri uno.").font(.subheadline).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity).padding(.vertical, 40).multilineTextAlignment(.center)
            }
            ForEach(giorni, id: \.self) { g in
                let del = ms.filter { $0.data.t == g }
                let netto = del.reduce(0.0) { $0 + ($1.tipo.t == "in" ? $1.imp.d : $1.tipo.t == "out" && !$1.ecc.vero ? -fin("calcolo.importoEffettivo", $1).d : 0) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dataUmana(g).maiuscola).font(.footnote.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                        Spacer()
                        if netto != 0 { Text(euro(netto, segno: true)).font(.footnote).monospacedDigit().foregroundStyle(netto > 0 ? verdeEntrata : Color.secondarioLife) }
                    }
                    .padding(.horizontal, 4)
                    Carta(padding: 12) {
                        ForEach(del, id: \.id) { RigaMovimento(m: $0) }
                    }
                }
            }
        }
    }
}

// MARK: - Grafici

struct GraficoBarre: View {
    let valori: [Double]
    let etichette: [String]
    var evidenzia = -1
    var retta: Double? = nil
    var colore: Color = accentoFinanze
    var body: some View {
        Chart {
            ForEach(valori.indices, id: \.self) { i in
                BarMark(x: .value("Ciclo", "\(i)·\(etichette.indices.contains(i) ? etichette[i] : "")"), y: .value("Euro", valori[i] / 100))
                    .foregroundStyle(i == evidenzia ? colore : Color.secondary.opacity(0.35))
                    .cornerRadius(5)
            }
            if let retta {
                RuleMark(y: .value("Budget", retta / 100)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.secondary)
            }
        }
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel {
                    if let s = v.as(String.self) { Text(s.split(separator: "·").last.map(String.init)?.uppercased() ?? "").font(.caption2) }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 140)
    }
}

struct GraficoCumulato: View {
    let cum: [Double]
    let budget: Double
    let giornoOggi: Int?
    let giorniMese: Int
    let punti: [J]
    var body: some View {
        let fino = min(giornoOggi ?? giorniMese, giorniMese)
        let sopra = budget > 0 && giornoOggi != nil && fino > 0 && fino <= cum.count && cum[fino - 1] > budget * Double(fino) / Double(max(1, giorniMese))
        let colore: Color = sopra ? .pericoloLife : .successoLife
        return Chart {
            if budget > 0 {
                LineMark(x: .value("Giorno", 1), y: .value("Piano", 0), series: .value("s", "piano")).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                LineMark(x: .value("Giorno", giorniMese), y: .value("Piano", budget / 100), series: .value("s", "piano")).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            ForEach(0..<min(fino, cum.count), id: \.self) { i in
                AreaMark(x: .value("Giorno", i + 1), y: .value("Euro", cum[i] / 100)).foregroundStyle(colore.opacity(0.15))
                LineMark(x: .value("Giorno", i + 1), y: .value("Euro", cum[i] / 100), series: .value("s", "speso")).foregroundStyle(colore).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(punti, id: \.self) { p in
                PointMark(x: .value("Giorno", p.giorno.int ?? 1), y: .value("Euro", p["y"].d / 100)).foregroundStyle(arancioneAvviso)
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
        .frame(height: 170)
    }
}

struct GraficoFondo: View {
    let punti: [J]
    let target: Double
    var body: some View {
        let reali = punti.enumerated().filter { !$0.element.reale.isNull }
        let indietro = reali.last.map { $0.element.reale.d < $0.element.piano.d } ?? false
        let colore: Color = indietro ? arancioneAvviso : .successoLife
        return Chart {
            RuleMark(y: .value("Traguardo", target / 100)).foregroundStyle(accentoFinanze).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ForEach(punti.indices, id: \.self) { i in
                LineMark(x: .value("i", i), y: .value("Piano", punti[i].piano.d / 100), series: .value("s", "piano")).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 4]))
            }
            ForEach(reali, id: \.offset) { r in
                LineMark(x: .value("i", r.offset), y: .value("Reale", r.element.reale.d / 100), series: .value("s", "reale")).foregroundStyle(colore).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let i = v.as(Int.self), punti.indices.contains(i) {
                        let q = punti[i].quando.t
                        Text("\(q.dropFirst(5).prefix(2))/\(q.dropFirst(2).prefix(2))").font(.caption2)
                    }
                }
            }
        }
        .frame(height: 170)
    }
}

// MARK: - Analisi

struct AnalisiFinanze: View {
    let indice: String
    @State private var gruppi: [String]?
    @State private var catSpente: [String] = []
    @State private var apertaSub: String?
    @State private var apertoGruppo: String?

    private func coloreGruppo(_ g: J, _ i: Int) -> Color {
        if !g.neutro.vero { return g.id.t == "fuoriPiano" ? Color(hex: "#FF9500") : accentoFinanze }
        return Color.primary.opacity(0.26 - Double(i) * 0.06)
    }

    var body: some View {
        let iso = Logica.s.chiama("ui.oggiISO")
        let ciclo = fin("analisi.cicloPerIndice", .str(indice), iso)
        let decise = fin("gruppi.DECISE").list.map(\.t)
        let attivi = gruppi ?? decise
        let r = fin("gruppi.ripartizione", ciclo)
        let testa = fin("gruppi.intestazione", ciclo, iso)
        let fette = fin("gruppi.fetteDi", ciclo, ["gruppi": .arr(attivi.map { .str($0) }), "catSpente": .arr(catSpente.map { .str($0) })])
        let ritmo = fin("gruppi.ritmoQuotidiano", ciclo, iso)
        let andamento = fin("gruppi.andamentoQuotidiano", ciclo)
        let perde = fin("gruppi.doveSiPerde", ciclo, 6).list
        let storico = fin("gruppi.storicoGruppi", ciclo, 6, fin("analisi.primoCiclo")).list
        let vuoto = r.totale.d == 0 && iso.t > ciclo["a"].t
        let elenco = fin("gruppi.GRUPPI").list

        if vuoto {
            Text("In questo ciclo non ci sono uscite. Registrale e qui trovi dove sono andati i soldi, il ritmo del quotidiano e dove si perde.").font(.subheadline).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center).padding(.vertical, 40)
        } else {
            Blocco(eti: testa.corrente.vero ? "Giorno \(testa.giorno.int ?? 0) di \(testa.giorni.int ?? 0)" : "Ciclo chiuso", etiDx: euro(r.totale, tondo: true)) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(r.gruppi.list.filter { $0.totale.d > 0 }.enumerated()), id: \.offset) { i, x in
                            Rectangle().fill(coloreGruppo(x, i)).frame(width: max(2, g.size.width * CGFloat(x.totale.d / max(1, r.totale.d)) - 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                ForEach(Array(r.gruppi.list.enumerated()), id: \.offset) { i, x in
                    VStack(alignment: .leading, spacing: 4) {
                        Button { apertoGruppo = apertoGruppo == x.id.t ? nil : x.id.t } label: {
                            HStack(spacing: 8) {
                                Circle().fill(coloreGruppo(x, i)).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(x.nome.t).font(.subheadline.weight(x.neutro.vero ? .regular : .semibold))
                                    Text(!x.n.vero ? "in questo ciclo niente" : x.id.t == "fuoriPiano" ? plurale(x.n, "acquisto", "acquisti") : x.id.t == "quotidiano" ? plurale(x.n, "movimento", "movimenti") : x.esempi.t).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
                                }
                                Spacer()
                                Text(x.n.vero ? euro(x.totale) : "—").font(.subheadline).monospacedDigit()
                                if x.n.vero { Image(systemName: apertoGruppo == x.id.t ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(Color.terziarioLife) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!x.n.vero)
                        .opacity(x.totale.d > 0 ? 1 : 0.5)
                        if apertoGruppo == x.id.t {
                            ForEach(x.voci.list.prefix(12), id: \.id) { m in
                                RigaFin(titolo: m.nota.str ?? "Senza nota", sotto: glm(m.data.t), valore: euro(m.imp), freccia: true) { Fogli.s.apri(.dettaglio(m.id.t)) }.padding(.leading, 18)
                            }
                            if x.voci.list.count > 12 { Text("+\(x.voci.list.count - 12) · le trovi in Movimenti").font(.caption).foregroundStyle(Color.secondarioLife).padding(.leading, 18) }
                        }
                    }
                }
                Divider()
                RigaValore(etichetta: "Decise da te", valore: euro(r.decise))
            }

            Sezione("Dove sono andati") {
                Carta {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(elenco, id: \.id) { g in
                                let id = g.id.t
                                Pillola(testo: g.nome.t, attiva: attivi.contains(id), colore: accentoFinanze) {
                                    gruppi = attivi.contains(id) ? attivi.filter { $0 != id } : attivi + [id]
                                    apertaSub = nil
                                }
                                .disabled(!r.perId[id].n.vero)
                                .opacity(r.perId[id].n.vero ? 1 : 0.4)
                            }
                        }
                    }
                    if fette.visibili.list.isEmpty {
                        Text("Niente da mostrare: hai spento tutto.").font(.footnote).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        Chart(fette.visibili.list, id: \.id) { c in
                            SectorMark(angle: .value("Totale", c.totale.d), innerRadius: .ratio(0.62), angularInset: 1).foregroundStyle(coloreCat(c.id.str)).cornerRadius(2)
                        }
                        .chartBackground { _ in
                            VStack(spacing: 0) {
                                Text(euro(fette.totale, tondo: true)).font(.headline).monospacedDigit()
                                Text("VISIBILE").font(.caption2).foregroundStyle(Color.secondarioLife)
                            }
                        }
                        .frame(height: 170)
                    }
                    ForEach(fette.tutte.list, id: \.id) { c in
                        let id = c.id.t
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Button { catSpente = catSpente.contains(id) ? catSpente.filter { $0 != id } : catSpente + [id] } label: {
                                    HStack(spacing: 8) {
                                        Circle().strokeBorder(coloreCat(id), lineWidth: 1.5).background(Circle().fill(c.spenta.vero ? .clear : coloreCat(id))).frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text("\(fin("dati.emojiCat", c.id).t) \(c.nome.t)").font(.subheadline).lineLimit(1)
                                            Text([c.spenta.vero ? "spenta" : "\(Int((c.quota.d * 100).rounded()))%", plurale(c.n, "volta", "volte"), c.fuoriPiano.vero ? "\(c.fuoriPiano.int ?? 0) fuori piano" : nil, c.budget.d > 0 ? "budget \(euro(c.budget, tondo: true))" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(euro(c.totale)).font(.subheadline).monospacedDigit()
                                    }
                                    .opacity(c.spenta.vero ? 0.55 : 1)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button { apertaSub = apertaSub == id ? nil : id } label: {
                                    Image(systemName: apertaSub == id ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(Color.terziarioLife).frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                            }
                            if apertaSub == id {
                                ForEach(fin("gruppi.sottoDi", ciclo, c.id, ["gruppi": .arr(attivi.map { .str($0) })]).list, id: \.self) { x in
                                    RigaFin(titolo: x.sub.t, sotto: "\(plurale(x.n, "volta", "volte")) · \(euro(x.medio)) in media", valore: euro(x.totale)) { Fogli.s.apri(.sub(id, x.sub.t, ciclo.indice.t)) }.padding(.leading, 18)
                                }
                            }
                        }
                    }
                }
            }

            let male = ritmo.proiezione.d > 0
            Blocco(eti: "Quotidiano", tono: male ? .pericoloLife : nil) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(euro(ritmo.alGiorno)).font(.title2.weight(.semibold)).monospacedDigit() + Text("/giorno").font(.footnote).foregroundColor(Color.secondarioLife)
                    Text("piano \(euro(ritmo.piano))").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
                Text(!ritmo.attendibile.vero ? "troppo presto per una proiezione" : ritmo.corrente.vero ? "se continui: \(male ? "+" : "−")\(euro(abs(ritmo.proiezione.d), tondo: true)) sul ciclo" : "chiuso a \(euro(ritmo.quotidiano, tondo: true)) su \(euro(ritmo.budget, tondo: true))")
                    .font(.footnote)
                    .foregroundStyle(!ritmo.attendibile.vero ? Color.secondarioLife : male ? Color.pericoloLife : Color.successoLife)
            }

            if ritmo.budget.d > 0 {
                Sezione("Andamento del quotidiano", coda: { Text("piano \(euro(ritmo.budget, tondo: true))") }) {
                    Carta {
                        GraficoCumulato(cum: andamento.cum.list.map(\.d), budget: ritmo.budget.d, giornoOggi: testa.corrente.vero ? testa.giorno.int : nil, giorniMese: ciclo.giorni.int ?? 30, punti: andamento.punti.list)
                    }
                }
            }

            if !perde.isEmpty {
                Sezione("Dove si perde") {
                    Carta {
                        ForEach(perde, id: \.self) { x in
                            RigaFin(titolo: x.sub.t, sotto: "\(plurale(x.n, "volta", "volte")) · \(euro(x.medio)) in media", valore: euro(x.totale), freccia: true) { Fogli.s.apri(.sub(x.catId.t, x.sub.t, ciclo.indice.t)) }
                        }
                    }
                }
            }

            if storico.count > 1 {
                Sezione("Ultimi cicli") {
                    Carta(padding: 12) {
                        ForEach(Array(storico.reversed()), id: \.self) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.nome.t).font(.footnote.weight(s.ciclo.indice == ciclo.indice ? .semibold : .regular))
                                HStack(spacing: 10) {
                                    Text("\(euro(s.alGiorno))/g").foregroundStyle(ritmo.piano.d > 0 && s.alGiorno.d > ritmo.piano.d ? Color.pericoloLife : Color.primary)
                                    Text(s.nFuoriPiano.vero ? "\(s.nFuoriPiano.int ?? 0) · \(euro(s.fuoriPiano, tondo: true))" : "—").foregroundStyle(s.nFuoriPiano.vero ? Color.pericoloLife : Color.secondarioLife)
                                    Text(s.riserva.vero ? "ris. \(euro(s.riserva, tondo: true))" : "—").foregroundStyle(Color.secondarioLife)
                                    Text(s.fisse.vero ? "fisse \(euro(s.fisse, tondo: true))" : "—").foregroundStyle(Color.secondarioLife)
                                }
                                .font(.caption)
                                .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Movimento

struct FoglioMovimento: View {
    let movimento: J?
    let tipoIniziale: String
    let preset: J?
    @State private var b: J = .null
    @State private var testo = ""
    @State private var manuale = false
    @State private var auto = false
    @State private var inLista = false
    @State private var inAttesa: (imp: Int, ecc: Bool)?
    @FocusState private var fuoco: Bool
    @Environment(\.dismiss) private var chiudi

    private var nuovo: Bool { movimento == nil }
    private var tipo: String { b.tipo.t }
    private var doppio: Bool { tipo == "giro" || tipo == "extra" }

    private let segnaposto = ["out": "Cosa hai pagato?", "in": "Da dove arriva?", "rimb": "Chi ti ha rimborsato?", "reso": "Cosa hai reso?", "giro": "Da quale a quale pocket?", "extra": "Da quale carta?"]

    private func predefiniti(_ t: String) -> (J, J) {
        switch t {
        case "extra": return ("ing", "principale")
        case "giro": return ("cassa", "principale")
        default: return ("principale", nil)
        }
    }

    private var pockets: [J] { fin("dati.stato").pockets.list.filter { !$0.archiviato.vero } }

    private var valido: Bool {
        centesimi(testo) != nil
            && (doppio || !b.nota.t.trimmingCharacters(in: .whitespaces).isEmpty)
            && !(tipo == "out" && !b.cat.vero)
            && !(doppio && (!b.pocket.vero || !b.pocketTo.vero || b.pocket == b.pocketTo))
            && b.data.vero
    }

    var body: some View {
        NavigationStack {
            Group {
                if inLista, let attesa = inAttesa { faseLista(attesa) } else { modulo }
            }
            .navigationTitle(inLista ? "Era in lista?" : !nuovo ? "Modifica" : tipo == "out" ? "Nuova uscita" : tipo == "in" ? "Nuova entrata" : "Nuovo movimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } } }
        }
        .onAppear(perform: carica)
    }

    private func carica() {
        guard b.isNull else { return }
        if let movimento {
            b = movimento
            manuale = movimento.cat.vero
        } else {
            let (da, a) = predefiniti(tipoIniziale)
            var n: J = ["id": .str(nuovoIdLogica("m")), "tipo": .str(tipoIniziale), "imp": 0, "nota": "", "cat": nil, "sub": nil, "rif": nil, "ecc": false, "data": Logica.s.chiama("ui.oggiISO"), "rimborsoDi": nil, "pocket": da, "pocketTo": a]
            for (k, v) in preset?.dict ?? [:] { n[k] = v }
            b = n
            manuale = preset?.cat.vero ?? false
        }
        testo = testoDa(b.imp.d)
        fuoco = true
        // (mentre il foglio sta ancora salendo il fuoco non attacca: si ripete appena è su,
        // così la tastiera dei numeri c'è sempre, anche arrivando da un widget)
        if nuovo { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fuoco = true } }
    }

    private var modulo: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(fin("dati.TIPI").dict.keys).sorted { ordineTipo($0) < ordineTipo($1) }, id: \.self) { k in
                            Pillola(testo: etichettaTipo(k), attiva: tipo == k, colore: k == "out" ? .pericoloLife : k == "in" ? .successoLife : accentoFinanze) { cambiaTipo(k) }
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0,00", text: $testo)
                        .keyboardType(.decimalPad)
                        .focused($fuoco)
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(["in", "rimb", "reso"].contains(tipo) ? verdeEntrata : Color.primary)
                        .onChange(of: testo) { _, v in
                            let p = pulisciImporto(v)
                            if p != v { testo = p }
                        }
                    Text("€").font(.title2).foregroundStyle(Color.secondarioLife)
                }
                TextField(segnaposto[tipo] ?? "Nota", text: Binding(get: { b.nota.t }, set: { cambiaNota($0) }))
            }
            if tipo == "out" {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(fin("dati.stato").cats.list, id: \.id) { c in
                            let scelta = b.cat == c.id
                            Button {
                                tocco()
                                b["cat"] = c.id
                                b["sub"] = nil
                                auto = false
                                manuale = true
                            } label: {
                                VStack(spacing: 3) {
                                    Text(fin("dati.emojiCat", c.id).t).font(.title3)
                                    Text(c.nome.t).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(scelta ? coloreCat(c.id.str).opacity(0.18) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(scelta ? coloreCat(c.id.str) : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Categoria")
                } footer: {
                    if auto { Text("Assegnata in automatico dalla nota: toccane un'altra per cambiarla.") }
                }
                let sotto = fin("dati.categoriaPerId", b.cat).sub.list
                if !sotto.isEmpty {
                    Section("Sottocategoria") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sotto, id: \.self) { s in
                                    Pillola(testo: s.t, attiva: b.sub == s, colore: accentoFinanze) {
                                        b["sub"] = b.sub == s ? nil : s
                                        manuale = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if tipo == "rimb" || tipo == "reso" {
                Section {
                    let recenti = fin("dati.movimentiVivi").list.filter { $0.tipo.t == "out" }.sorted { $0.data.t == $1.data.t ? $0.ts.d > $1.ts.d : $0.data.t > $1.data.t }.prefix(12)
                    if recenti.isEmpty {
                        Text("Nessuna spesa recente da agganciare.").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    ForEach(Array(recenti), id: \.id) { m in
                        Button { b["rif"] = b.rif == m.id ? nil : m.id } label: {
                            HStack {
                                Text("\(m.nota.t) · \(euro(m.imp))").font(.subheadline).foregroundStyle(Color.primary).lineLimit(1)
                                Spacer()
                                if b.rif == m.id { Image(systemName: "checkmark").foregroundStyle(accentoFinanze) }
                            }
                        }
                    }
                } header: {
                    Text("Aggancia alla spesa")
                } footer: {
                    Text("Senza aggancio il rimborso abbassa il totale ma non si sa da quale spesa venga.")
                }
            }
            Section(doppio ? "Da quale pocket esce" : tipo == "in" ? "Su quale pocket entra" : "Da quale pocket") {
                sceltaPocket(escludi: nil, valore: b.pocket) { v in
                    b["pocket"] = v
                    if doppio, b.pocketTo == v {
                        b["pocketTo"] = pockets.first { $0.id != v && $0.id.t == "principale" }?.id ?? pockets.first { $0.id != v }?.id ?? nil
                    }
                }
            }
            if doppio {
                Section("E su quale entra") {
                    sceltaPocket(escludi: b.pocket, valore: b.pocketTo) { b["pocketTo"] = $0 }
                }
            }
            Section {
                DatePicker("Data", selection: Binding(get: { Tempo.istante(b.data.str ?? Tempo.oggi(), "12:00") }, set: { b["data"] = .str(Tempo.dataRoma($0)) }), displayedComponents: .date)
                if tipo == "in" {
                    Toggle(isOn: Binding(get: { b.stip.vero }, set: { b["stip"] = .bool($0) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("È lo stipendio")
                            Text(b.stip.vero ? "Alla conferma si apre la checklist dei travasi." : "Il ciclo parte da questa data.").font(.caption).foregroundStyle(Color.secondarioLife)
                        }
                    }
                }
            }
            .environment(\.timeZone, Tempo.roma)
            if tipo == "out" {
                Section {} footer: {
                    Text("Ordinaria: capita spesso, conta nel budget. Straordinaria: una volta tanto, fuori dal budget.")
                }
            }
        }
        .environment(\.timeZone, Tempo.roma)
        // Salva sta sempre a portata di dito, sopra la tastiera: prima era in fondo al modulo, nascosto
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if tipo == "out" {
                    PulsantePieno(testo: "Ordinaria", colore: accentoFinanze) { salva(false) }
                    PulsantePieno(testo: "Straordinaria", colore: Color(hex: "#FF9F0A").opacity(0.8)) { salva(true) }
                } else {
                    PulsantePieno(testo: "Salva", colore: accentoFinanze) { salva(false) }
                }
            }
            .disabled(!valido)
            .opacity(valido ? 1 : 0.4)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func ordineTipo(_ k: String) -> Int { ["out", "in", "rimb", "reso", "giro", "extra"].firstIndex(of: k) ?? 9 }

    private func sceltaPocket(escludi: J?, valore: J, _ scegli: @escaping (J) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pockets.filter { escludi == nil || $0.id != escludi }, id: \.id) { p in
                    Pillola(testo: p.nome.t, attiva: valore == p.id, colore: accentoFinanze) { scegli(p.id) }
                }
            }
        }
    }

    private func cambiaTipo(_ t: String) {
        let (da, a) = predefiniti(t)
        b["tipo"] = .str(t)
        b["cat"] = nil
        b["sub"] = nil
        b["rif"] = nil
        b["pocket"] = da
        b["pocketTo"] = a
        auto = false
        manuale = false
    }

    /// La categoria proposta dalla nota (per un'uscita nuova, finché non l'hai scelta tu).
    private func cambiaNota(_ v: String) {
        b["nota"] = .str(v)
        guard tipo == "out", nuovo, !manuale else { return }
        let g = Logica.s.chiama("finanze.indovina", .str(v))
        if !g.isNull {
            b["cat"] = g.cat
            b["sub"] = g.sub
            auto = true
        } else if auto {
            b["cat"] = nil
            b["sub"] = nil
            auto = false
        }
    }

    private func scrivi(_ imp: Int, _ ecc: Bool, extra: [String: J] = [:]) {
        var m = b
        for (k, v) in extra { m[k] = v }
        m["imp"] = .n(imp)
        m["ecc"] = .bool(tipo == "out" ? ecc : false)
        fin("dati.salvaMovimento", m)
        if manuale, b.nota.vero, b.cat.vero { fin("dati.impara", b.nota, b.cat, b.sub) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        avviso(nuovo ? "Registrato." : "Aggiornato.")
        if tipo == "in", b.stip.vero {
            Fogli.s.apri(.paga(b.data.t, Double(imp)))
        } else {
            chiudi()
        }
    }

    private func salva(_ ecc: Bool) {
        guard let imp = centesimi(testo) else { return avviso("Manca l'importo.", errore: true) }
        if tipo == "out", !b.cat.vero { return avviso("Manca la categoria.", errore: true) }
        let st = fin("dati.stato")
        let soglia = st.soglie.fuoriPiano.num ?? fin("dati.SOGLIE_PREDEFINITE").fuoriPiano.d
        if nuovo, tipo == "out", !b.pian.vero, !b.lista.vero, b.cat.t != "spesa", Double(imp) >= soglia {
            inAttesa = (imp, ecc)
            inLista = true
            return
        }
        scrivi(imp, ecc)
    }

    private func faseLista(_ attesa: (imp: Int, ecc: Bool)) -> some View {
        let q = fin("piano.quotaDi")
        let gq = q.quota.d > 0 ? Double(attesa.imp) / q.quota.d : 0
        let adesso = Date().timeIntervalSince1970 * 1000
        let candidate = fin("dati.vociLista").list.map { v -> J in
            var c = v
            c["vista"] = fin("dati.statoVoce", v, .num(adesso))
            return c
        }
        .filter { $0.vista.t == "attesa" || $0.vista.t == "sbloccata" }
        .sorted { abs($0.imp.d - Double(attesa.imp)) < abs($1.imp.d - Double(attesa.imp)) }
        return Pagina {
            VStack(spacing: 4) {
                Text(euro(Double(attesa.imp))).font(.system(size: 42, weight: .semibold)).monospacedDigit()
                Text("\(gq >= 1 ? "\(String(format: "%.1f", gq).replacingOccurrences(of: ".", with: ",")) giorni di quota" : "il \(Int((gq * 100).rounded()))% della quota di oggi") · quota \(euro(q.quota))/g").font(.footnote).foregroundStyle(Color.secondarioLife)
            }
            .frame(maxWidth: .infinity)
            if !candidate.isEmpty {
                Sezione("Dalla lista") {
                    Carta(padding: 12) {
                        ForEach(candidate, id: \.id) { v in
                            RigaFin(titolo: v.nome.t, sotto: v.vista.t == "sbloccata" ? "sbloccata" : "in attesa", valore: euro(v.imp)) {
                                fin("dati.cambiaStatoVoce", v.id, "comprata")
                                scrivi(attesa.imp, attesa.ecc, extra: ["lista": v.id, "fuoriPiano": false])
                            }
                        }
                    }
                }
                Text("Una voce in lista da almeno ventiquattro ore è il piano, non uno strappo: la spesa resta dentro.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            HStack(spacing: 8) {
                PulsantePieno(testo: "Mettila in lista", colore: Color(uiColor: .systemGray)) {
                    fin("dati.salvaVoce", ["id": .str(nuovoIdLogica("w")), "nome": .str(b.nota.t.isEmpty ? "Spesa" : b.nota.t), "imp": .n(attesa.imp)])
                    avviso("In lista. Sbloccata fra 24 ore.")
                    chiudi()
                }
                PulsantePieno(testo: "No, registra", colore: accentoFinanze) { scrivi(attesa.imp, attesa.ecc, extra: ["fuoriPiano": true]) }
            }
            Text("«No, registra» la segna fuori piano. Non è un rimprovero: è l'unica voce su cui si può fare qualcosa, e per farci qualcosa deve essere contata.").font(.caption).foregroundStyle(Color.secondarioLife)
            Button("Torna indietro") { inLista = false }.frame(maxWidth: .infinity)
        }
    }
}
