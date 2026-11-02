import SwiftUI
import UIKit

// Sezione: il quadro del capo sezione. I calcoli sono quelli del sito (moduli/sezione/dati.ts, nella
// logica): qui ci sono solo le schermate. Il giorno e l'ora guardati sono gli stessi in tutte le schede.

enum Sez {
    static let colori: [String: String] = ["P": "#34C759", "A": "#FF453A", "I": "#FF9F0A", "L": "#5E5CE6"]
    static let nomi: [String: String] = ["P": "Presente", "A": "Assente", "I": "Indisponibile", "L": "Limitazione"]
    static let oraMessaggio = 7 * 60 + 15
    static let titoloInvio = "Inviare i dati di forza al Comandante"
    static let titoloPrepara = "Preparare i dati di forza di domani"

    static func colore(_ t: String) -> Color { Color(hex: colori[t] ?? "#8E8E93") }
    static func nome(_ t: String) -> String { nomi[t] ?? t }

    @discardableResult
    static func chiama(_ f: String, _ a: J...) -> J { Logica.s.chiama("sezione.dati.\(f)", argomenti: a) }

    static func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
    static func minuti(_ s: String?) -> Int {
        let p = (s ?? "0:0").split(separator: ":").map { Int($0) ?? 0 }
        return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
    }
    static var adesso: Int { minuti(Tempo.oraRoma(Date())) }

    /** «D'INTINO» → «D'Intino», come sul sito. */
    static func maiuscole(_ s: String) -> String {
        var out = ""
        var inizio = true
        for c in s.lowercased() {
            out.append(inizio ? Character(String(c).uppercased()) : c)
            inizio = c == " " || c == "'" || c == "’" || c == "-"
        }
        return out
    }

    static func nomeCompleto(_ p: J) -> String { [p.grado.t, maiuscole(p.cognome.t), p.nome.t].filter { !$0.isEmpty }.joined(separator: " ") }

    static func etichettaGiorno(_ g: String) -> String {
        let oggi = Tempo.oggi()
        let (_, m, d) = Tempo.parti(g)
        let lungo = "\(Tempo.settimanaLunga[Tempo.giornoSettimana(g)]) \(d) \(Tempo.mesiLunghi[m - 1].lowercased())"
        if g == oggi { return "Oggi, \(lungo)" }
        if g == Tempo.piuGiorni(oggi, 1) { return "Domani, \(lungo)" }
        if g == Tempo.piuGiorni(oggi, -1) { return "Ieri, \(lungo)" }
        return lungo.maiuscola
    }

    /** «fino alle 13:30» dentro il giorno, «fino al 5 nov» se dura di più. */
    static func quando(_ s: J, _ g: String) -> String {
        if s.al.t == g, let a = s.oraAl.str, !a.isEmpty { return " fino alle \(a)" }
        if let al = s.al.str, !al.isEmpty { return " · fino al \(Tempo.breve(al))" }
        return ""
    }

    static func iso(_ d: Date) -> String { Tempo.dataRoma(d) }

    private static let lavoro = try! NSRegularExpression(pattern: "^(work|lavoro|sue)$|accertament", options: .caseInsensitive)
    static func eLavoro(_ nome: String) -> Bool { lavoro.firstMatch(in: nome, range: NSRange(nome.startIndex..., in: nome)) != nil }
    /** I calendari delle novità: quelli scelti, o quelli che si chiamano Work, Accertamenti, SUE. */
    static func calendariNovita() -> Set<String> {
        let scelti = Set(chiama("config").calendari.list.map(\.t))
        return scelti.isEmpty ? Set(Azioni.sorgenti.filter { eLavoro($0.nome) }.map(\.id)) : scelti
    }
    static func novita(_ g: String) -> [J] {
        let ids = calendariNovita()
        let (x0, x1) = Tempo.intervallo(g)
        return Azioni.eventi(da: x0, a: x1).filter { ids.contains($0.subscription_id.t) }
    }
}

/// Il giorno e l'ora guardati, comuni a tutte le schede.
final class StatoSezione: ObservableObject {
    static let s = StatoSezione()
    /** Di sera si prepara il messaggio di domattina: dalle 14 il giorno è domani. */
    @Published var giorno: String = Calendar.current.component(.hour, from: Date()) >= 14 ? Tempo.piuGiorni(Tempo.oggi(), 1) : Tempo.oggi() {
        didSet { if giorno != oldValue { istante = nil } }
    }
    /** Vuoto = adesso (oggi) o l'ora dei dati di forza (gli altri giorni). */
    @Published var istante: Int?

    var minuto: Int { istante ?? (giorno == Tempo.oggi() ? Sez.adesso : Sez.oraMessaggio) }
}

struct VistaSezione: View {
    let scheda: String
    var body: some View {
        switch scheda {
        case "giornata": SezGiornata()
        case "messaggio": SezMessaggio()
        case "appunti": SezAppunti()
        case "altro": SezAltro()
        default: SezQuadro()
        }
    }
}

// MARK: - Giorno e ora

private struct BarraTempo: View {
    @ObservedObject private var stato = StatoSezione.s

    var body: some View {
        let oggi = stato.giorno == Tempo.oggi()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { tocco(); stato.giorno = Tempo.piuGiorni(stato.giorno, -1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                Text(Sez.etichettaGiorno(stato.giorno)).font(.headline).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                Button { tocco(); stato.giorno = Tempo.piuGiorni(stato.giorno, 1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            HStack(spacing: 10) {
                Text("Situazione alle").font(.subheadline).foregroundStyle(Color.secondarioLife)
                DatePicker("", selection: Binding(
                    get: { Tempo.istante(stato.giorno, Sez.hhmm(stato.minuto)) },
                    set: { stato.istante = Sez.minuti(Tempo.oraRoma($0)) }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.timeZone, Tempo.roma)
                .environment(\.locale, Locale(identifier: "it_IT"))
                Spacer(minLength: 0)
                if stato.istante != nil {
                    Button(oggi ? "Adesso" : "Alle 07:15") { tocco(); stato.istante = nil }.font(.subheadline.weight(.semibold))
                } else if oggi {
                    Label("adesso", systemImage: "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.pericoloLife).labelStyle(.titleAndIcon).imageScale(.small)
                } else {
                    Text("ora dei dati").font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
            if !oggi && stato.giorno != Tempo.piuGiorni(Tempo.oggi(), 1) {
                Button("Torna a oggi") { tocco(); stato.giorno = Tempo.oggi() }.font(.footnote.weight(.medium))
            }
        }
    }
}

// MARK: - Il quadro

private struct PaxAperti: Identifiable {
    let pax: [J]
    var id: String { pax.map(\.id.t).joined(separator: ",") }
}

struct SezQuadro: View {
    @ObservedObject private var logica = Logica.s
    @ObservedObject private var stato = StatoSezione.s
    @State private var scelti: Set<String>?
    @State private var aperti: PaxAperti?

    var body: some View {
        let _ = logica.versione
        let g = stato.giorno
        let m = stato.minuto
        let righe = Sez.chiama("quadro", .str(g), .n(m)).list
        let f = Sez.chiama("forza", .str(g), .n(m))
        let cambi = Sez.chiama("cambiDomani", .str(g))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if righe.isEmpty {
                    SezIncolla()
                } else {
                    BarraTempo()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        numero("Effettiva", f.effettiva.int ?? 0, nil)
                        numero("Presenti", f.presenti.int ?? 0, Sez.colore("P"))
                        numero("Disponibili", f.disponibili.int ?? 0, Sez.colore("P"))
                        numero("Assenti", f.assenti.list.count, f.assenti.list.isEmpty ? nil : Sez.colore("A"))
                        numero("Indisponibili", f.indisponibili.list.count, f.indisponibili.list.isEmpty ? nil : Sez.colore("I"))
                        numero("Limitazioni", f.limitati.list.count, f.limitati.list.isEmpty ? nil : Sez.colore("L"))
                    }
                    strisce(cambi, g)
                    HStack {
                        Text("Organico").font(.title3.weight(.semibold))
                        Spacer()
                        if let scelti {
                            Button(scelti.count == righe.count ? "Nessuno" : "Tutti") {
                                self.scelti = scelti.count == righe.count ? [] : Set(righe.map(\.p.id.t))
                            }
                            .font(.subheadline)
                        } else {
                            Text("\(f.presenti.int ?? 0) su \(f.effettiva.int ?? 0)").font(.subheadline).foregroundStyle(Color.secondarioLife)
                        }
                    }
                    .padding(.horizontal, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(righe, id: \.p.id) { r in
                            Quadratino(riga: r, g: g, m: m, scelto: scelti.map { $0.contains(r.p.id.t) }) {
                                tocco()
                                if scelti != nil {
                                    if scelti!.contains(r.p.id.t) { scelti!.remove(r.p.id.t) } else { scelti!.insert(r.p.id.t) }
                                } else {
                                    aperti = PaxAperti(pax: [r.p])
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.sfondoLife)
        .navigationTitle("Sezione")
        .toolbar {
            if !righe.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(scelti == nil ? "Seleziona" : "Annulla") {
                        tocco()
                        scelti = scelti == nil ? [] : nil
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if let scelti {
                Button {
                    aperti = PaxAperti(pax: righe.map(\.p).filter { scelti.contains($0.id.t) })
                    self.scelti = nil
                } label: {
                    Text(scelti.isEmpty ? "Tocca chi cambiare insieme" : "Imposta lo stato di \(scelti.count)").font(.headline).frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(scelti.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $aperti) { a in SezSchedaPax(pax: a.pax, g: g, m: m) }
        .task {
            if ProcessInfo.processInfo.environment["LIFE_DEMO"] != nil, Sez.chiama("organico").list.isEmpty { SezPromemoria.datiDiProva() }
            await SezPromemoria.assicura()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if stato.istante == nil, stato.giorno == Tempo.oggi() { stato.objectWillChange.send() }
        }
    }

    private func numero(_ eti: String, _ n: Int, _ colore: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eti).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(n)").font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(colore ?? Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func strisce(_ cambi: J, _ g: String) -> some View {
        let quando = g == Tempo.oggi() ? "domani" : "il \(Tempo.breve(Tempo.piuGiorni(g, 1)))"
        let rientri = cambi.rientri.list
        let partenze = cambi.partenze.list
        if !rientri.isEmpty {
            striscia("arrow.uturn.left", Sez.colore("P"), "Rientr\(rientri.count == 1 ? "a" : "ano") \(quando): " + rientri.map { Sez.maiuscole($0.cognome.t) }.joined(separator: ", "))
        }
        if !partenze.isEmpty {
            striscia("arrow.right", Sez.colore("A"), "Da \(quando): " + partenze.map { "\(Sez.maiuscole($0.p.cognome.t)) \(($0.s.motivo.str ?? Sez.nome($0.s.tipo.t)).lowercased())" }.joined(separator: ", "))
        }
    }

    private func striscia(_ icona: String, _ colore: Color, _ testo: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icona).foregroundStyle(colore)
            Text(testo).font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(colore.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Quadratino: View {
    let riga: J
    let g: String
    let m: Int
    let scelto: Bool?
    let azione: () -> Void

    var body: some View {
        let p = riga.p
        let s = riga.s
        let tipo = s.isNull ? "P" : s.tipo.t
        let c = Sez.colore(tipo)
        Button(action: azione) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(c).frame(width: 8, height: 8)
                    Text(Sez.maiuscole(p.cognome.t)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let scelto {
                        Image(systemName: scelto ? "checkmark.circle.fill" : "circle").foregroundStyle(scelto ? Color.accentColor : Color.terziarioLife)
                    } else if !riga.l.isNull {
                        Text(riga.l.motivo.t == "Altro" ? "Lim." : riga.l.motivo.t)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Sez.colore("L"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                Text(p.nome.t.isEmpty ? (p.grado.t.isEmpty ? " " : p.grado.t) : p.nome.t).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    if !s.isNull {
                        Text((s.motivo.str ?? Sez.nome(tipo)) + Sez.quando(s, g)).foregroundStyle(c)
                    } else if !riga.poi.isNull {
                        Text("\(riga.poi.motivo.str ?? Sez.nome(riga.poi.tipo.t)) dalle \(riga.poi.oraDal.t)").foregroundStyle(Sez.colore(riga.poi.tipo.t))
                    } else {
                        Text("Presente").foregroundStyle(Color.secondarioLife)
                    }
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(tipo == "P" ? Color.cartaLife : c.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(scelto == true ? Color.accentColor : (tipo == "P" ? Color.clear : c.opacity(0.4)), lineWidth: scelto == true ? 2 : 1))
            .opacity(scelto == false ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Una o più persone

struct SezSchedaPax: View {
    let pax: [J]
    let g: String
    let m: Int
    @State private var tipo: String
    @State private var motivo: String
    @State private var dettaglio: String
    @State private var dal: Date
    @State private var conOraDal = false
    @State private var oraDal: Date
    @State private var conFine: Bool
    @State private var al: Date
    @State private var conOraAl: Bool
    @State private var oraAl: Date
    @Environment(\.dismiss) private var chiudi
    @ObservedObject private var logica = Logica.s

    init(pax: [J], g: String, m: Int) {
        self.pax = pax
        self.g = g
        self.m = m
        let attuale = pax.count == 1 ? Sez.chiama("statoDi", pax[0].id, .str(g), .n(m)) : J.null
        _tipo = State(initialValue: attuale.isNull ? "P" : attuale.tipo.t)
        _motivo = State(initialValue: attuale.motivo.t)
        _dettaglio = State(initialValue: attuale.dettaglio.t)
        _dal = State(initialValue: Tempo.istante(g, "12:00"))
        _oraDal = State(initialValue: Tempo.istante(g, Sez.hhmm(m)))
        let al = attuale.al.str
        _conFine = State(initialValue: al != nil)
        _al = State(initialValue: Tempo.istante(al ?? g, "12:00"))
        _conOraAl = State(initialValue: al != nil && attuale.oraAl.str != nil)
        _oraAl = State(initialValue: Tempo.istante(al ?? g, attuale.oraAl.str ?? "13:00"))
    }

    private var uno: J? { pax.count == 1 ? pax[0] : nil }
    private var motivi: [J] { tipo == "P" ? [] : Sez.chiama("MOTIVI")[tipo].list }
    private var frase: String { motivi.first { $0[0].t == motivo }?[1].t ?? "" }
    private var pronto: Bool { tipo == "P" || (!motivo.isEmpty && (motivo != "Altro" || !dettaglio.trimmingCharacters(in: .whitespaces).isEmpty)) }

    var body: some View {
        let _ = logica.versione
        NavigationStack {
            Form {
                if uno == nil {
                    Section { Text(pax.map { Sez.maiuscole($0.cognome.t) }.joined(separator: ", ")).font(.subheadline).foregroundStyle(Color.secondarioLife) }
                }
                Section {
                    Picker("Stato", selection: $tipo) {
                        Text("Presente").tag("P")
                        Text("Indisp.").tag("I")
                        Text("Assente").tag("A")
                        Text("Limitaz.").tag("L")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tipo) { _, _ in motivo = "" }
                } footer: {
                    if tipo == "L" { Text("Resta presente e disponibile: la limitazione si vede sul quadratino e nella giornata.") }
                }
                if let uno, tipo != "L" {
                    let l = Sez.chiama("limitazioneDi", uno.id, .str(g), .n(m))
                    if !l.isNull {
                        Section("Limitazione") {
                            HStack {
                                Circle().fill(Sez.colore("L")).frame(width: 8, height: 8)
                                Text(l.motivo.t + Sez.quando(l, g))
                                Spacer()
                                Button("Togli", role: .destructive) { Sez.chiama("impostaStato", uno.id, .str(g), "PL") }
                            }
                        }
                    }
                }
                if tipo != "P" {
                    Section("Motivo") {
                        Picker("Motivo", selection: $motivo) {
                            Text("Scegli").tag("")
                            ForEach(motivi, id: \.self) { x in Text(x[0].t).tag(x[0].t) }
                        }
                        TextField(motivo == "Altro" ? "Scrivi il motivo" : "Dettaglio, es. in Francia", text: $dettaglio)
                    }
                }
                Section {
                    DatePicker("Dal", selection: $dal, displayedComponents: .date)
                    Toggle(tipo == "P" ? "Rientra a un'ora precisa" : "Da un'ora precisa", isOn: $conOraDal)
                    if conOraDal { DatePicker("Dalle", selection: $oraDal, displayedComponents: .hourAndMinute) }
                    if tipo != "P" {
                        Toggle("Con una fine", isOn: $conFine)
                        if conFine {
                            DatePicker("Fino al", selection: $al, in: dal..., displayedComponents: .date)
                            Toggle("Fino a un'ora precisa", isOn: $conOraAl)
                            if conOraAl { DatePicker("Alle", selection: $oraAl, displayedComponents: .hourAndMinute) }
                        }
                    }
                } header: {
                    Text(tipo == "P" ? "Da quando" : "Quando")
                } footer: {
                    Text(tipo == "P" ? "Per un rientro in giornata metti l'ora: «rientra alle 13:00»." : conFine ? "" : "Senza una fine vale fino a nuovo ordine.")
                }
                if tipo != "P" {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                scorciatoia("Fino a pranzo") { finestra(nil, "13:00") }
                                scorciatoia("Il pomeriggio") { finestra("14:00", nil) }
                                scorciatoia("Tutto il giorno") { conOraDal = false; conFine = true; al = dal; conOraAl = false }
                                scorciatoia("Una settimana") { conOraDal = false; conFine = true; al = dal.addingTimeInterval(6 * 86400); conOraAl = false }
                                scorciatoia("Fino a nuovo ordine") { conFine = false; conOraAl = false }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }
                if let uno, tipo == "A" || tipo == "I" {
                    Section("Nel messaggio") {
                        Text([Sez.nomeCompleto(uno), frase, dettaglio.trimmingCharacters(in: .whitespaces), conFine && conOraAl && Sez.iso(al) == Sez.iso(dal) ? "fino alle \(Tempo.oraRoma(oraAl))" : ""].filter { !$0.isEmpty }.joined(separator: " "))
                            .font(.subheadline)
                    }
                }
                if let uno {
                    let storia = Sez.chiama("storiaDi", uno.id).list
                    if !storia.isEmpty {
                        Section("Storico") {
                            ForEach(storia.prefix(10), id: \.id) { s in
                                HStack(spacing: 10) {
                                    Circle().fill(Sez.colore(s.tipo.t)).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.motivo.str ?? Sez.nome(s.tipo.t)).font(.subheadline)
                                        Text("\(Tempo.breve(s.dal.t))\(s.oraDal.str.map { " " + $0 } ?? "") → \(s.al.str.map { Tempo.breve($0) + (s.oraAl.str.map { " " + $0 } ?? "") } ?? "nuovo ordine")\(s.dettaglio.t.isEmpty ? "" : " · " + s.dettaglio.t)")
                                            .font(.caption).foregroundStyle(Color.secondarioLife)
                                    }
                                }
                                .swipeActions { Button("Cancella", role: .destructive) { Sez.chiama("cancellaStato", s.id) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle(uno.map { Sez.maiuscole($0.cognome.t) } ?? "\(pax.count) persone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: salva).fontWeight(.semibold).disabled(!pronto) }
            }
            .environment(\.timeZone, Tempo.roma)
            .environment(\.locale, Locale(identifier: "it_IT"))
        }
    }

    private func scorciatoia(_ t: String, _ fai: @escaping () -> Void) -> some View {
        Button { tocco(); fai() } label: {
            Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(height: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func finestra(_ da: String?, _ a: String?) {
        let giorno = Sez.iso(dal)
        conOraDal = da != nil
        if let da { oraDal = Tempo.istante(giorno, da) }
        conFine = true
        al = dal
        conOraAl = a != nil
        if let a { oraAl = Tempo.istante(giorno, a) }
    }

    private func salva() {
        let giorno = Sez.iso(dal)
        for p in pax {
            let prima = Sez.chiama("statoDi", p.id, .str(g), .n(m))
            let stesso = motivo.isEmpty && !prima.isNull && prima.tipo.t == tipo
            let campi: J = [
                "motivo": .str(motivo.isEmpty ? (stesso ? prima.motivo.t : "") : motivo),
                "frase": .str(motivo.isEmpty ? (stesso ? prima.frase.t : "") : frase),
                "dettaglio": .str(dettaglio),
                "al": conFine && tipo != "P" ? .str(Sez.iso(al)) : .null,
                "oraDal": conOraDal ? .str(Tempo.oraRoma(oraDal)) : .null,
                "oraAl": conFine && conOraAl && tipo != "P" ? .str(Tempo.oraRoma(oraAl)) : .null,
            ]
            Sez.chiama("impostaStato", p.id, .str(giorno), .str(tipo), campi)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        chiudi()
    }
}

// MARK: - La giornata, ora per ora

struct SezGiornata: View {
    @ObservedObject private var logica = Logica.s
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var stato = StatoSezione.s
    @State private var aperti: PaxAperti?

    private let da = 6 * 60
    private let a = 22 * 60

    var body: some View {
        let _ = logica.versione
        let _ = archivio.versione
        let g = stato.giorno
        let m = stato.minuto
        let righe = Sez.chiama("giornata", .str(g)).list
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BarraTempo()
                Carta {
                    Text("ORA PER ORA").font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                    if righe.isEmpty {
                        Text("Nessuno fuori, per tutto il giorno.").font(.subheadline).foregroundStyle(Color.secondarioLife)
                    } else {
                        ore
                        ForEach(righe, id: \.p.id) { r in
                            Button { aperti = PaxAperti(pax: [r.p]) } label: { riga(r, m) }.buttonStyle(.plain)
                        }
                    }
                }
                novita(g)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.sfondoLife)
        .navigationTitle("Giornata")
        .sheet(item: $aperti) { x in SezSchedaPax(pax: x.pax, g: g, m: m) }
    }

    private func x(_ v: Int, _ w: CGFloat) -> CGFloat { CGFloat(min(a, max(da, v)) - da) / CGFloat(a - da) * w }

    private var ore: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 92)
            GeometryReader { geo in
                ForEach([6, 9, 12, 15, 18, 21], id: \.self) { h in
                    Text(String(format: "%02d", h)).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Color.secondarioLife)
                        .position(x: x(h * 60, geo.size.width), y: 6)
                }
            }
            .frame(height: 12)
        }
    }

    private func riga(_ r: J, _ m: Int) -> some View {
        HStack(spacing: 8) {
            Text(Sez.maiuscole(r.p.cognome.t)).font(.footnote.weight(.medium)).lineLimit(1).frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
                    ForEach(r.stati.list, id: \.id) { s in
                        let inizio = x(s.da.int ?? 0, w)
                        let fine = x(s.a.int ?? 1440, w)
                        let limite = s.tipo.t == "L"
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Sez.colore(s.tipo.t))
                            .overlay(alignment: .leading) {
                                if !limite, fine - inizio >= 44 {
                                    Text(s.motivo.str ?? Sez.nome(s.tipo.t)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 4)
                                }
                            }
                            .frame(width: max(4, fine - inizio), height: limite ? 6 : 24)
                            .offset(x: inizio, y: limite ? 22 : 2)
                    }
                    Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 28).offset(x: x(m, w))
                }
            }
            .frame(height: 28)
        }
    }

    @ViewBuilder
    private func novita(_ g: String) -> some View {
        let eventi = Sez.novita(g)
        let colori = Dictionary(Azioni.sorgenti.map { ($0.id, $0.colore) }, uniquingKeysWith: { p, _ in p })
        Carta {
            Text("NOVITÀ DEL GIORNO").font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
            if eventi.isEmpty {
                Text("Niente in calendario").font(.subheadline).foregroundStyle(Color.secondarioLife)
            }
            ForEach(eventi, id: \.self) { e in
                HStack(spacing: 10) {
                    Capsule().fill(Color.life(colori[e.subscription_id.t])).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.summary.t.isEmpty ? "(senza titolo)" : e.summary.t).font(.subheadline).lineLimit(2)
                        Text(e.all_day.vero ? "Tutto il giorno" : "\(Tempo.oraRoma(e.start_at.str) ?? "")–\(Tempo.oraRoma(e.end_at.str) ?? "")").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                }
            }
        }
    }
}

// MARK: - Il messaggio

struct SezMessaggio: View {
    @ObservedObject private var logica = Logica.s
    @ObservedObject private var stato = StatoSezione.s
    @State private var attivita = ""
    @FocusState private var fuoco: Bool

    var body: some View {
        let _ = logica.versione
        let g = stato.giorno
        let testo = Sez.chiama("messaggio", .str(g)).t
        let inviato = Sez.chiama("giorno", .str(g)).inviato.str
        let config = Sez.chiama("config")
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Button { tocco(); stato.giorno = Tempo.piuGiorni(g, -1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }.buttonStyle(.glass).buttonBorderShape(.circle)
                    Text(Sez.etichettaGiorno(g)).font(.headline).frame(maxWidth: .infinity)
                    Button { tocco(); stato.giorno = Tempo.piuGiorni(g, 1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }.buttonStyle(.glass).buttonBorderShape(.circle)
                }
                if let inviato {
                    Label("Inviati alle \(Tempo.oraRoma(inviato) ?? "")", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.successoLife)
                } else {
                    Label(g == Tempo.oggi() ? "Da inviare alle 07:15" : "Per il \(g.suffix(2))/\(g.dropFirst(5).prefix(2))", systemImage: "clock").font(.subheadline).foregroundStyle(Color.secondarioLife)
                }
                Carta {
                    Text(testo).font(.callout).textSelection(.enabled)
                }
                Carta {
                    Text("ATTIVITÀ PARTICOLARI").font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                    TextField("NIL", text: $attivita, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($fuoco)
                        .onChange(of: fuoco) { _, f in if !f { salvaAttivita(g) } }
                    Button("Usa le novità del calendario") { usaNovita(g) }.font(.footnote.weight(.medium))
                }
                if config.reparto.t.isEmpty || config.firma.t.isEmpty {
                    Text("Mancano reparto o firma: si scrivono in Altro.").font(.footnote).foregroundStyle(Color.orange)
                }
                Button {
                    salvaAttivita(g)
                    UIPasteboard.general.string = Sez.chiama("messaggio", .str(g)).t
                    Sez.chiama("segnaInviato", .str(g), .str(Tempo.iso(Date())))
                    if g <= Tempo.oggi() { SezPromemoria.spuntaInvio() }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label(inviato == nil ? "Copia e segna inviato" : "Copia di nuovo", systemImage: "doc.on.doc").font(.headline).frame(maxWidth: .infinity).frame(height: 46)
                }
                .buttonStyle(.glassProminent)
                ShareLink(item: testo) {
                    Label("Condividi", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.glass)
                if inviato != nil {
                    Button("Segna come non inviato") { Sez.chiama("segnaInviato", .str(g), .null) }.font(.footnote).foregroundStyle(Color.secondarioLife)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.sfondoLife)
        .navigationTitle("Dati di forza")
        .onAppear { attivita = Sez.chiama("attivitaDi", .str(g)).t }
        .onChange(of: stato.giorno) { _, n in attivita = Sez.chiama("attivitaDi", .str(n)).t }
        .onDisappear { salvaAttivita(g) }
    }

    private func salvaAttivita(_ g: String) {
        if attivita != Sez.chiama("attivitaDi", .str(g)).t { Sez.chiama("impostaAttivita", .str(g), .str(attivita)) }
    }

    private func usaNovita(_ g: String) {
        let righe = Sez.novita(g).map { e in
            ((e.all_day.vero ? "" : (Tempo.oraRoma(e.start_at.str) ?? "") + " ") + e.summary.t).trimmingCharacters(in: .whitespaces)
        }
        guard !righe.isEmpty else { return }
        attivita = righe.joined(separator: "\n")
        Sez.chiama("impostaAttivita", .str(g), .str(attivita))
    }
}

// MARK: - Appunti al volo

struct SezAppunti: View {
    @ObservedObject private var logica = Logica.s
    @State private var testo = ""
    @FocusState private var fuoco: Bool

    var body: some View {
        let _ = logica.versione
        let note = Sez.chiama("leggi").note.list.filter { !$0.del.vero }.sorted { $0.quando.t > $1.quando.t }
        List {
            Section {
                HStack {
                    TextField("A rapporto, una richiesta, un nome…", text: $testo, axis: .vertical)
                        .focused($fuoco)
                        .submitLabel(.done)
                        .onSubmit(aggiungi)
                    Button(action: aggiungi) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(testo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                if note.isEmpty { Text("Nessun appunto").foregroundStyle(Color.secondarioLife) }
                ForEach(note, id: \.id) { n in
                    HStack(alignment: .top, spacing: 10) {
                        Button { tocco(); Sez.chiama("cambiaNota", n.id, ["fatta": .bool(!n.fatta.vero)]) } label: {
                            Image(systemName: n.fatta.vero ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(n.fatta.vero ? Color.accentColor : Color.terziarioLife)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.testo.t).strikethrough(n.fatta.vero).foregroundStyle(n.fatta.vero ? Color.secondarioLife : Color.primary)
                            Text("\(n.giorno.t == Tempo.oggi() ? "" : Tempo.breve(n.giorno.t) + " · ")\(Tempo.oraRoma(n.quando.str) ?? "")").font(.caption).foregroundStyle(Color.secondarioLife)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Elimina", role: .destructive) { Sez.chiama("cambiaNota", n.id, ["del": true]) }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Azioni.creaTask(testo: n.testo.t, contesto: ["due_at": Azioni.scadenza(Tempo.oggi(), nil).0], interpreta: false)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Label("In To do", systemImage: "checkmark.square") }
                        .tint(Color(hex: "#34C759"))
                    }
                }
            } footer: {
                if !note.isEmpty { Text("Scorri a destra per mandare un appunto in To do, a sinistra per eliminarlo.") }
            }
        }
        .navigationTitle("Appunti")
    }

    private func aggiungi() {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tocco()
        Sez.chiama("aggiungiNota", .str(t), .str(Tempo.oggi()))
        testo = ""
    }
}

// MARK: - Altro: messaggio, calendari, organico, storico, promemoria

struct SezAltro: View {
    @ObservedObject private var logica = Logica.s
    @State private var incolla = false

    var body: some View {
        let _ = logica.versione
        let config = Sez.chiama("config")
        let pax = Sez.chiama("organico").list
        let scelti = Sez.calendariNovita()
        List {
            Section {
                NavigationLink { SezStorico() } label: { Label("Storico degli ultimi 30 giorni", systemImage: "clock.arrow.circlepath") }
            }
            Section {
                campo("Saluto", "saluto", config)
                campo("Prima riga", "intro", config)
                campo("Reparto", "reparto", config)
                campo("Firma", "firma", config)
                campo("Uno", "singolare", config)
                campo("Più di uno", "plurale", config)
            } header: { Text("Messaggio") } footer: { Text("Il testo che apre e firma i dati di forza. La data si mette da sola.") }
            Section {
                ForEach(Azioni.sorgenti) { s in
                    let attivo = scelti.contains(s.id)
                    Button {
                        var n = scelti
                        if n.contains(s.id) { n.remove(s.id) } else { n.insert(s.id) }
                        Sez.chiama("impostaConfig", ["calendari": .arr(n.sorted().map { .str($0) })])
                    } label: {
                        HStack {
                            Circle().fill(Color.life(s.colore)).frame(width: 10, height: 10)
                            Text(s.nome).foregroundStyle(Color.primary)
                            Spacer()
                            if attivo { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            } header: { Text("Novità dal calendario") }
            Section {
                ForEach(pax, id: \.id) { p in
                    NavigationLink { SezModificaPax(p: p) } label: { Text(Sez.nomeCompleto(p)) }
                }
                .onMove { da, a in
                    var l = pax
                    l.move(fromOffsets: da, toOffset: a)
                    for (i, p) in l.enumerated() where (p.ordine.int ?? 0) != i + 1 { Sez.chiama("cambiaPax", p.id, ["ordine": .n(i + 1)]) }
                }
                .onDelete { i in for n in i { Sez.chiama("cambiaPax", pax[n].id, ["del": true]) } }
                Button { incolla = true } label: { Label("Aggiungi o incolla nomi", systemImage: "plus") }
            } header: {
                HStack { Text("Organico · \(pax.count)"); Spacer(); EditButton().font(.caption) }
            }
            Section {
                let invio = SezPromemoria.task(Sez.titoloInvio)
                let prepara = SezPromemoria.task(Sez.titoloPrepara)
                HStack { Text("Ogni sera alle 21:00"); Spacer(); Text(prepara == nil ? "Manca" : "Attivo").foregroundStyle(Color.secondarioLife) }
                HStack { Text("Ogni mattina alle 07:15"); Spacer(); Text(invio.map { "\(Azioni.promemoria(task: $0.id.t).count) avvisi" } ?? "Manca").foregroundStyle(Color.secondarioLife) }
                if invio == nil || prepara == nil {
                    Button("Crea i promemoria mancanti") { SezPromemoria.crea() }
                }
            } header: { Text("Promemoria") } footer: { Text("Il task delle 07:15 ha cinque avvisi prima (06:30, 06:45, 07:00, 07:05, 07:10). «Copia e segna inviato» lo spunta e gli avvisi rimasti tacciono.") }
        }
        .navigationTitle("Altro")
        .sheet(isPresented: $incolla) { NavigationStack { ScrollView { SezIncolla(chiudi: { incolla = false }).padding(16) }.navigationTitle("Organico").navigationBarTitleDisplayMode(.inline) } }
    }

    private func campo(_ eti: String, _ k: String, _ config: J) -> some View {
        HStack {
            Text(eti)
            TextField(eti, text: Binding(get: { config[k].t }, set: { Sez.chiama("impostaConfig", [k: .str($0)]) }))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.secondarioLife)
        }
    }
}

private struct SezModificaPax: View {
    let p: J
    @State private var grado = ""
    @State private var cognome = ""
    @State private var nome = ""
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        Form {
            Section {
                TextField("Grado", text: $grado)
                TextField("Cognome", text: $cognome)
                TextField("Nome", text: $nome)
            }
            Section {
                Button("Togli dall'organico", role: .destructive) {
                    Sez.chiama("cambiaPax", p.id, ["del": true])
                    chiudi()
                }
            }
        }
        .navigationTitle(Sez.maiuscole(p.cognome.t))
        .onAppear {
            grado = p.grado.t
            cognome = p.cognome.t
            nome = p.nome.t
        }
        .onDisappear {
            guard !cognome.trimmingCharacters(in: .whitespaces).isEmpty, grado != p.grado.t || cognome != p.cognome.t || nome != p.nome.t else { return }
            Sez.chiama("cambiaPax", p.id, ["grado": .str(grado), "cognome": .str(cognome), "nome": .str(nome)])
        }
    }
}

struct SezIncolla: View {
    var chiudi: (() -> Void)? = nil
    @State private var testo = ""

    var body: some View {
        let letti = testo.isEmpty ? [] : Sez.chiama("leggiOrganico", .str(testo)).list
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "person.3.fill").font(.system(size: 36)).foregroundStyle(Color(hex: "#A2845E"))
            Text("L'organico della sezione").font(.title2.weight(.semibold))
            Text("Incolla l'elenco così com'è: grado, cognome, nome, una persona per riga. Resta solo nel tuo account.").font(.subheadline).foregroundStyle(Color.secondarioLife)
            TextEditor(text: $testo)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                Sez.chiama("aggiungiPax", .arr(letti))
                testo = ""
                chiudi?()
            } label: {
                Text(letti.isEmpty ? "Aggiungi" : "Aggiungi \(letti.count) \(letti.count == 1 ? "persona" : "persone")").font(.headline).frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(letti.isEmpty)
        }
    }
}

private struct SezStorico: View {
    @ObservedObject private var logica = Logica.s

    var body: some View {
        let _ = logica.versione
        let oggi = Tempo.oggi()
        List {
            ForEach(0..<30, id: \.self) { i in
                let g = Tempo.piuGiorni(oggi, 1 - i)
                let f = Sez.chiama("forza", .str(g))
                let inviato = Sez.chiama("giorno", .str(g)).inviato.str
                Button {
                    StatoSezione.s.giorno = g
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(Sez.etichettaGiorno(g)).foregroundStyle(Color.primary)
                            Spacer()
                            Text(inviato.map { "inviati \(Tempo.oraRoma($0) ?? "")" } ?? (g <= oggi ? "—" : "")).font(.caption).foregroundStyle(inviato == nil ? Color.secondarioLife : Color.successoLife)
                        }
                        let fuori = f.assenti.list.map { Sez.maiuscole($0.p.cognome.t) } + f.indisponibili.list.map { Sez.maiuscole($0.p.cognome.t) + " (indisp.)" }
                        Text("\(f.presenti.int ?? 0)/\(f.effettiva.int ?? 0) presenti\(fuori.isEmpty ? "" : " · " + fuori.joined(separator: ", "))").font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Storico")
    }
}

// MARK: - I promemoria dei dati di forza (come promemoria.ts sul sito)

enum SezPromemoria {
    static let minutiPrima = [45, 30, 15, 10, 5]

    static func task(_ titolo: String) -> J? {
        Azioni.tasks.first { $0.title.t == titolo && $0.completed_at.isNull && $0.deleted_at.isNull }
    }

    /** Il task delle 07:15 ha sempre i suoi cinque avvisi prima: li aggiunge se mancano. */
    @MainActor
    static func assicura() async {
        try? await Task.sleep(for: .seconds(2))
        guard let t = task(Sez.titoloInvio), t.due_has_time.vero else { return }
        let gia = Set(Azioni.promemoria(task: t.id.t).compactMap { $0.offset_minutes.int })
        for m in minutiPrima where !gia.contains(m) { Azioni.aggiungiPromemoria(t, minutiPrima: m) }
    }

    /** Solo per gli screenshot della compilazione (LIFE_DEMO): nomi inventati. */
    static func datiDiProva() {
        let nomi: [J] = ["Bianchi Luca", "Conti Marco", "Esposito Anna", "Ferri Paolo", "Galli Sara", "Greco Luigi", "Lombardi Elena", "Marino Davide", "Ricci Giulia", "Romano Pietro", "Russo Chiara", "Villa Matteo"].map { n in
            let p = n.split(separator: " ")
            return ["grado": "S.Ten.", "cognome": .str(p[0].uppercased()), "nome": .str(String(p[1]))]
        }
        Sez.chiama("aggiungiPax", .arr(nomi))
        let pax = Sez.chiama("organico").list
        let oggi = Tempo.oggi()
        guard pax.count >= 11 else { return }
        Sez.chiama("impostaStato", pax[1].id, .str(oggi), "A", ["motivo": "Servizio isolato", "frase": "in servizio isolato", "dettaglio": "in Francia"])
        Sez.chiama("impostaStato", pax[3].id, .str(oggi), "A", ["motivo": "Permesso", "frase": "in permesso", "al": .str(oggi), "oraAl": "13:00"])
        Sez.chiama("impostaStato", pax[5].id, .str(oggi), "I", ["motivo": "Visita medica", "frase": "a visita medica", "al": .str(oggi), "oraDal": "10:00", "oraAl": "11:30"])
        Sez.chiama("impostaStato", pax[7].id, .str(oggi), "L", ["motivo": "EsAF", "frase": "esente dall'attività fisica", "al": .str(Tempo.piuGiorni(oggi, 6))])
        for i in [8, 9, 10] { Sez.chiama("impostaStato", pax[i].id, .str(oggi), "A", ["motivo": "Altra attività", "frase": "impegnato in altra attività", "al": .str(oggi), "oraDal": "11:55", "oraAl": "13:30"]) }
    }

    static func spuntaInvio() {
        let oggi = Tempo.oggi()
        for t in Azioni.tasks where t.title.t == Sez.titoloInvio && t.completed_at.isNull && t.deleted_at.isNull {
            if let g = Azioni.giorno(t), g <= oggi { Azioni.completa(t) }
        }
    }

    static func crea() {
        let ora = Sez.adesso
        if task(Sez.titoloPrepara) == nil {
            let g = ora < 21 * 60 ? Tempo.oggi() : Tempo.piuGiorni(Tempo.oggi(), 1)
            let (d, h) = Azioni.scadenza(g, "21:00")
            Azioni.creaTask(testo: Sez.titoloPrepara, contesto: ["due_at": d, "due_has_time": .bool(h), "rrule": "FREQ=DAILY"], interpreta: false)
        }
        if task(Sez.titoloInvio) == nil {
            let g = ora < Sez.oraMessaggio ? Tempo.oggi() : Tempo.piuGiorni(Tempo.oggi(), 1)
            let (d, h) = Azioni.scadenza(g, "07:15")
            if let t = Azioni.creaTask(testo: Sez.titoloInvio, contesto: ["due_at": d, "due_has_time": .bool(h), "rrule": "FREQ=DAILY", "priority": 1], interpreta: false) {
                for m in minutiPrima { Azioni.aggiungiPromemoria(t, minutiPrima: m) }
            }
        }
    }
}
