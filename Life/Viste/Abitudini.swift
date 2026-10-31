import SwiftUI

// Abitudini: la giornata (con le parti e gli orari), i progressi, il dettaglio, la modifica.
// Le regole sono quelle di ATLAS, nel bundle JS.

func abi(_ f: String, _ a: J...) -> J { Logica.s.chiama("abitudini.\(f)", argomenti: a) }
func tinta(_ t: J) -> Color { Color(hex: Logica.s.chiama("tinta", t).str ?? "#0A84FF") }
private let accentoAbi = Color(hex: "#5E5CE6")

/// La spunta tonda, anche parziale.
struct Spunta: View {
    var fatta: Bool
    var parziale: Double = 0
    var misura: CGFloat = 32
    var colore: Color = accentoAbi
    var body: some View {
        ZStack {
            Circle().stroke(fatta ? colore : Color(uiColor: .systemGray3), lineWidth: 2)
            if fatta {
                Circle().fill(colore)
                Image(systemName: "checkmark").font(.system(size: misura * 0.45, weight: .bold)).foregroundStyle(.white)
            } else if parziale > 0 {
                Circle().trim(from: 0, to: CGFloat(parziale)).stroke(colore, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            }
        }
        .frame(width: misura, height: misura)
        .animation(.spring(duration: 0.25), value: fatta)
    }
}

struct AbitudineAperta: Identifiable {
    let id: String
}
struct AbitudineDaModificare: Identifiable {
    let idAbitudine: String?
    var id: String { idAbitudine ?? "nuova" }
}

struct VistaAbitudini: View {
    @ObservedObject private var logica = Logica.s
    @State private var scheda = "oggi"
    @State private var giorno = Logica.s.chiama("ui.oggiISO").t
    @State private var dettaglio: AbitudineAperta?
    @State private var modifica: AbitudineDaModificare?
    @State private var apriSpente = false

    var body: some View {
        let _ = logica.versione
        let oggi = logica.chiama("ui.oggiISO").t
        let tutte = abi("dati.abitudiniVive").list
        return Pagina {
            Picker("Scheda", selection: $scheda) {
                Text("Oggi").tag("oggi")
                Text("Progressi").tag("progressi")
                Text("Altro").tag("altro")
            }
            .pickerStyle(.segmented)
            if scheda == "progressi" {
                progressi(tutte, oggi)
            } else if scheda == "altro" {
                altro(tutte)
            } else if tutte.isEmpty {
                VStack(spacing: 10) {
                    Text("Nessuna abitudine").font(.headline)
                    Text("Aggiungi la prima: una cosa piccola, da fare ogni giorno.").font(.subheadline).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center)
                    PulsantePieno(testo: "Nuova abitudine", colore: accentoAbi) { modifica = AbitudineDaModificare(idAbitudine: nil) }
                }
                .padding(.vertical, 30)
            } else {
                settimana(oggi)
                eroe(oggi)
                lista(tutte)
            }
        }
        .navigationTitle("Abitudini")
        .toolbar {
            Button { modifica = AbitudineDaModificare(idAbitudine: nil) } label: { Image(systemName: "plus") }
        }
        .sheet(item: $dettaglio) { d in
            DettaglioAbitudine(id: d.id) { id in
                dettaglio = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { modifica = AbitudineDaModificare(idAbitudine: id) }
            }
        }
        .sheet(item: $modifica) { m in ModificaAbitudine(id: m.idAbitudine) }
    }

    // MARK: La settimana in alto

    private func settimana(_ oggi: String) -> some View {
        let giorni = abi("calcolo.giorniSettimana", .str(giorno)).list.map(\.t)
        return HStack(spacing: 4) {
            ForEach(giorni, id: \.self) { d in
                let x = abi("calcolo.progressoGiorno", .str(d))
                let (_, _, n) = Tempo.parti(d)
                let lettera = ["D", "L", "M", "M", "G", "V", "S"][Tempo.giornoSettimana(d)]
                let futuro = d > oggi
                let frazione = x.frazione.d
                Button {
                    tocco()
                    giorno = d
                } label: {
                    VStack(spacing: 3) {
                        Text(lettera).font(.caption2.weight(.medium)).foregroundStyle(Color.secondarioLife)
                        ZStack {
                            if !futuro, !x.riposo.vero { Anello(valore: frazione, misura: 34, spessore: 3, colore: frazione >= 1 ? .successoLife : accentoAbi) }
                            Text("\(n)").font(.footnote.weight(d == giorno ? .bold : .regular)).monospacedDigit().foregroundStyle(d == oggi ? accentoAbi : futuro ? Color.terziarioLife : Color.primary)
                        }
                        .frame(width: 36, height: 36)
                        .background(d == giorno ? Color(uiColor: .tertiarySystemFill) : .clear, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func eroe(_ oggi: String) -> some View {
        let eOggi = giorno == oggi
        let hhmm = {
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }()
        let voci = abi("calcolo.giornataOggi", .str(giorno)).list
        let aperte = voci.filter { !$0.fatta.vero && !$0.saltata.vero }
        let fatte = voci.count - aperte.count
        let frazione = voci.isEmpty ? 0 : Double(fatte) / Double(voci.count)
        let ritardo = eOggi ? aperte.first { $0.ora.vero && $0.ora.t <= hhmm } : nil
        let prossima = ritardo ?? aperte.first { $0.ora.vero && (!eOggi || $0.ora.t > hhmm) } ?? aperte.first
        let migliore = abi("dati.abitudiniVive").list.map { abi("calcolo.serie", $0).d }.max() ?? 0
        let pieno = !voci.isEmpty && fatte >= voci.count
        var testo = ""
        if voci.isEmpty {
            testo = "nessuna abitudine prevista"
        } else if pieno {
            testo = "tutto fatto"
        } else if let p = prossima {
            testo = "\(ritardo != nil ? "da fare" : "poi"): \(p.emoji.t) \(p.nome.t)\(p.ora.vero ? " · \(p.ora.t)" : "")"
        }
        return Blocco(eti: eOggi ? "Oggi" : dataUmana(giorno).maiuscola, etiDx: migliore > 1 ? "serie migliore \(plurale(migliore, "giorno", "giorni"))" : nil) {
            HStack(spacing: 14) {
                Anello(valore: frazione, misura: 62, spessore: 9, colore: pieno ? .successoLife : accentoAbi)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(fatte)").font(.largeTitle.weight(.semibold)).monospacedDigit() + Text(" di \(voci.count)").font(.body).foregroundColor(Color.secondarioLife)
                    Text(testo).font(.footnote).foregroundStyle(ritardo != nil ? arancioneAvviso : Color.secondarioLife).lineLimit(1)
                }
            }
        }
    }

    // MARK: La lista

    private func primaOra(_ h: J) -> String {
        let ore = ([h.remind.str] + abi("dati.partiDi", h).list.map { abi("dati.oraDiParte", h, $0).str }).compactMap { $0 }.filter { !$0.isEmpty }
        return ore.sorted().first ?? "99:99"
    }

    @ViewBuilder
    private func lista(_ tutte: [J]) -> some View {
        let previste = tutte.filter { abi("calcolo.eAttesa", $0, .str(giorno)).vero }.sorted { a, b in
            let x = primaOra(a)
            let y = primaOra(b)
            return x == y ? a.order.d < b.order.d : x < y
        }
        let spente = tutte.filter { !abi("calcolo.eAttesa", $0, .str(giorno)).vero }
        ForEach(previste, id: \.id) { riga($0, spenta: false) }
        if !spente.isEmpty {
            Button { withAnimation { apriSpente.toggle() } } label: {
                HStack {
                    Text(spente.count == 1 ? "Una non prevista oggi" : "\(spente.count) non previste oggi")
                    Spacer()
                    Image(systemName: apriSpente ? "chevron.down" : "chevron.right")
                }
                .font(.footnote)
                .foregroundStyle(Color.secondarioLife)
            }
            .buttonStyle(.plain)
            if apriSpente { ForEach(spente, id: \.id) { riga($0, spenta: true) } }
        }
    }

    private func riga(_ h: J, spenta: Bool) -> some View {
        let id = h.id
        let parti = abi("dati.partiDi", h).list
        let gruppi = parti.isEmpty ? [] : abi("dati.gruppiParti", h).list
        let fattaParte: (J) -> Bool = { abi("dati.parteFatta", id, $0.id, .str(giorno)).vero }
        let mie = gruppi.reduce(0) { $0 + $1.parti.list.count }
        let quante = gruppi.reduce(0) { $0 + $1.parti.list.filter(fattaParte).count }
        let fatta = abi("calcolo.fattaIl", h, .str(giorno)).vero
        let saltata = abi("dati.eSaltata", id, .str(giorno)).vero
        let piano = abi("calcolo.pianoDi", h)
        let sotto = saltata ? "Oggi no" : (piano.type.t != "daily" && piano.type.vero) ? abi("calcolo.etichettaPiano", h).t : (h.remind.vero && parti.isEmpty) ? "alle \(h.remind.t)" : ""
        let serie = abi("calcolo.serie", h).int ?? 0
        let dettagli = [sotto, mie > 0 ? "\(quante) di \(mie)" : "", serie > 1 ? "🔥 \(serie) giorni" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let colore = tinta(h.tint)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { dettaglio = AbitudineAperta(id: id.t) } label: {
                    HStack(spacing: 12) {
                        Text(h.emoji.str ?? "⭐️").font(.title2).frame(width: 44, height: 44).background(colore.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.name.t).font(.body.weight(.semibold)).foregroundStyle(fatta ? Color.secondarioLife : Color.primary).lineLimit(1)
                            if !dettagli.isEmpty { Text(dettagli).font(.footnote).foregroundStyle(Color.secondarioLife).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    guard parti.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: fatta ? .light : .medium).impactOccurred()
                    abi("dati.alterna", id, .str(giorno))
                } label: {
                    Spunta(fatta: fatta, parziale: mie > 0 ? Double(quante) / Double(mie) : 0, colore: colore)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            if !gruppi.isEmpty {
                Divider()
                ForEach(gruppi, id: \.chiave) { g in
                    let suoi = g.parti.list
                    let fatte = suoi.filter(fattaParte).count
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(g.nome.t.uppercased()).font(.caption2.weight(.semibold))
                            Spacer()
                            if g.ora.vero { Label(g.ora.t, systemImage: "bell").font(.caption2) }
                            Text("\(fatte)/\(suoi.count)").font(.caption2).monospacedDigit().foregroundStyle(fatte == suoi.count ? colore : Color.secondarioLife)
                        }
                        .foregroundStyle(Color.secondarioLife)
                        .padding(.bottom, 2)
                        ForEach(Array(suoi.enumerated()), id: \.element.id) { i, p in
                            let fp = fattaParte(p)
                            Button {
                                UIImpactFeedbackGenerator(style: fp ? .light : .medium).impactOccurred()
                                abi("dati.alternaParte", id, p.id, .str(giorno))
                            } label: {
                                HStack(spacing: 10) {
                                    Spunta(fatta: fp, misura: 22, colore: colore)
                                    if h.sequenza.vero { Text("\(i + 1)").font(.caption).monospacedDigit().foregroundStyle(Color.terziarioLife) }
                                    Text(p.nome.t).font(.subheadline).strikethrough(fp).foregroundStyle(fp ? Color.secondarioLife : Color.primary)
                                    Spacer()
                                }
                                .frame(height: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }
        }
        .background(fatta ? colore.opacity(0.09) : Color.cartaLife, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(spenta ? 0.55 : saltata ? 0.6 : 1)
        .contextMenu {
            Button { abi("dati.alternaSaltata", id, .str(giorno)) } label: { Label("Oggi no", systemImage: "forward") }
        }
    }

    // MARK: Progressi

    private struct RigaProgressi {
        let h: J
        let n: Int
        let record: Int
        let cost: Int
        let fatta: Bool
        let attesa: Bool
    }

    @ViewBuilder
    private func progressi(_ tutte: [J], _ oggi: String) -> some View {
        let righe = tutte.map { h in
            RigaProgressi(h: h, n: abi("calcolo.serie", h, .str(oggi)).int ?? 0, record: abi("calcolo.serieMigliore", h, .str(oggi)).int ?? 0, cost: abi("calcolo.costanza", h, 30, .str(oggi)).int ?? 0, fatta: abi("calcolo.fattaIl", h, .str(oggi)).vero, attesa: abi("calcolo.eAttesa", h, .str(oggi)).vero)
        }
        .sorted { $0.n == $1.n ? $0.record > $1.record : $0.n > $1.n }
        if let m = righe.first {
            let rischio = righe.filter { $0.n > 0 && $0.attesa && !$0.fatta }
            Blocco(eti: "La più lunga") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(m.n)").font(.system(size: 48, weight: .semibold)).monospacedDigit().foregroundStyle(accentoAbi)
                    Text(m.n == 1 ? "giorno" : "giorni").foregroundStyle(Color.secondarioLife)
                }
                Text(m.n > 0 ? m.h.name.t : "Nessuna serie aperta. Se spunti qualcosa oggi ne parte una.").font(.subheadline)
                if let r = rischio.first {
                    Text(rischio.count == 1 ? "Se stasera salti \(r.h.name.t.lowercased()) perdi \(plurale(Double(r.n), "giorno", "giorni"))." : "\(plurale(Double(rischio.count), "serie aperta", "serie aperte")) da difendere oggi.").font(.footnote).foregroundStyle(arancioneAvviso)
                }
            }
            Sezione("Tutte le serie", coda: { Text("corrente · record") }) {
                Carta(padding: 12) {
                    ForEach(righe, id: \.h.id) { r in
                        let rischia = r.n > 0 && r.attesa && !r.fatta
                        Button { dettaglio = AbitudineAperta(id: r.h.id.t) } label: {
                            HStack(spacing: 10) {
                                Text(r.h.emoji.str ?? "⭐️").frame(width: 36, height: 36).background(tinta(r.h.tint).opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.h.name.t).font(.subheadline).lineLimit(1)
                                    Text("\(r.cost)% negli ultimi 30 giorni").font(.caption).foregroundStyle(Color.secondarioLife)
                                    Barra(valore: r.record > 0 ? Double(r.n) / Double(r.record) : 0, colore: tinta(r.h.tint), altezza: 4).frame(maxWidth: 200)
                                }
                                Spacer()
                                Text("\(r.n)").fontWeight(.semibold).monospacedDigit().foregroundStyle(rischia ? arancioneAvviso : r.n > 0 ? Color.primary : Color.secondarioLife) + Text(" / \(r.record)").foregroundColor(Color.secondarioLife)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Sezione("Ultime quattro settimane") {
                Carta(padding: 12) {
                    ForEach(righe, id: \.h.id) { r in
                        HStack(spacing: 8) {
                            Text(r.h.emoji.str ?? "⭐️").font(.subheadline).frame(width: 24)
                            HStack(spacing: 2) {
                                ForEach(0..<28, id: \.self) { i in
                                    let g = Tempo.piuGiorni(oggi, -(27 - i))
                                    let prevista = abi("calcolo.ePrevista", r.h, .str(g)).vero
                                    let fatta = abi("calcolo.fattaIl", r.h, .str(g)).vero
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(prevista && fatta ? tinta(r.h.tint) : prevista ? Color(uiColor: .tertiarySystemFill) : .clear)
                                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.lineaLife.opacity(prevista && fatta ? 0 : 0.6), lineWidth: 0.5))
                                        .aspectRatio(1, contentMode: .fit)
                                        .opacity(prevista ? 1 : 0.4)
                                }
                            }
                        }
                    }
                }
            }
            Text("Una riga per abitudine, una casella per giorno. Serve a vedere dove si rompono: quasi sempre è lo stesso giorno della settimana.").font(.caption).foregroundStyle(Color.secondarioLife)
        } else {
            Text("Le serie compaiono appena aggiungi un'abitudine.").font(.subheadline).foregroundStyle(Color.secondarioLife).padding(.vertical, 30)
        }
    }

    // MARK: Altro

    @ViewBuilder
    private func altro(_ vive: [J]) -> some View {
        let inizio = abi("dati.stato").meta.weekStart.int ?? 1
        let archiviate = abi("dati.abitudiniVive", ["conArchiviate": true]).list.filter(\.archived.vero)
        Sezione("La settimana comincia") {
            Carta {
                Picker("Inizio", selection: Binding(get: { inizio }, set: { v in
                    abi("dati.scriviMeta", ["weekStart": .n(v)])
                    avviso("Salvato.")
                })) {
                    Text("Lunedì").tag(1)
                    Text("Domenica").tag(0)
                }
                .pickerStyle(.segmented)
                Text("Conta per le abitudini settimanali: cambia quando si azzera il conteggio delle volte.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
        }
        Sezione("Le tue abitudini") {
            Carta(padding: 12) {
                ForEach(vive, id: \.id) { h in rigaAltro(h, nota: abi("calcolo.etichettaPiano", h).t) }
                RigaFin(titolo: "Aggiungi un'abitudine", accento: true) { modifica = AbitudineDaModificare(idAbitudine: nil) }
            }
        }
        if !archiviate.isEmpty {
            Sezione("Archiviate") {
                Carta(padding: 12) { ForEach(archiviate, id: \.id) { h in rigaAltro(h, nota: "archiviata") } }
            }
            Text("Archiviare toglie un'abitudine dal giorno senza cancellarne lo storico: riattivandola riparte da dov'era.").font(.caption).foregroundStyle(Color.secondarioLife)
        }
    }

    private func rigaAltro(_ h: J, nota: String) -> some View {
        Button { modifica = AbitudineDaModificare(idAbitudine: h.id.t) } label: {
            HStack(spacing: 10) {
                Text(h.emoji.str ?? "⭐️").frame(width: 32, height: 32).background(tinta(h.tint).opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(h.name.t).font(.subheadline)
                    Text(nota).font(.caption).foregroundStyle(Color.secondarioLife)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.terziarioLife)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dettaglio

struct DettaglioAbitudine: View {
    let id: String
    let modifica: (String) -> Void
    @ObservedObject private var logica = Logica.s
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let _ = logica.versione
        let h = abi("dati.abitudinePerId", .str(id))
        let oggi = logica.chiama("ui.oggiISO").t
        let p = abi("calcolo.pianoDi", h)
        let attuale = abi("calcolo.serie", h).int ?? 0
        let record = abi("calcolo.serieMigliore", h).int ?? 0
        let colore = tinta(h.tint)
        let orari: [(String, String)] = !abi("dati.partiDi", h).list.isEmpty
            ? abi("dati.gruppiParti", h).list.filter(\.ora.vero).map { ($0.nome.t, $0.ora.t) }
            : h.remind.vero ? [("Promemoria", h.remind.t)] : []
        return NavigationStack {
            Pagina {
                HStack(spacing: 12) {
                    Text(h.emoji.str ?? "⭐️").font(.largeTitle).frame(width: 56, height: 56).background(colore.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name.t).font(.title3.weight(.semibold))
                        Text(abi("calcolo.etichettaPiano", h).t).font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                }
                HStack(spacing: 8) {
                    casella("Serie attuale", "\(attuale)", p.type.t == "weekly" ? "settimane di fila" : "giorni di fila")
                    casella("Record", "\(record)", record > attuale ? "da battere" : "sei al massimo")
                }
                Sezione("Ultimi 30 giorni") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10), spacing: 5) {
                        ForEach(0..<30, id: \.self) { i in
                            let g = Tempo.piuGiorni(oggi, -(29 - i))
                            let fatta = abi("calcolo.fattaIl", h, .str(g)).vero
                            let prevista = abi("calcolo.ePrevista", h, .str(g)).vero
                            Text("\(Tempo.parti(g).2)")
                                .font(.caption2)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .foregroundStyle(fatta ? Color.white : Color.primary)
                                .background(fatta ? colore : prevista ? Color(uiColor: .tertiarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .opacity(!fatta && !prevista ? 0.35 : 1)
                        }
                    }
                }
                Text("\(abi("calcolo.costanza", h, 30).int ?? 0)% dei giorni previsti.").font(.caption).foregroundStyle(Color.secondarioLife)
                if p.type.t == "weekly" {
                    Carta { RigaFin(titolo: "Volte questa settimana", valore: "\(abi("calcolo.conteggioSettimana", h, .str(oggi)).int ?? 0) di \(p.times.int ?? 1)") }
                }
                if !orari.isEmpty {
                    Sezione("Promemoria") {
                        Carta(padding: 12) { ForEach(orari, id: \.0) { RigaFin(titolo: $0.0, valore: $0.1) } }
                    }
                }
            }
            .navigationTitle(h.name.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } }
                ToolbarItem(placement: .primaryAction) { Button("Modifica") { modifica(id) } }
            }
        }
    }

    private func casella(_ e: String, _ v: String, _ n: String) -> some View {
        Carta(padding: 12) {
            Text(e).font(.caption).foregroundStyle(Color.secondarioLife)
            Text(v).font(.largeTitle.weight(.semibold)).monospacedDigit()
            Text(n).font(.caption).foregroundStyle(Color.secondarioLife)
        }
    }
}

// MARK: - Modifica

struct ModificaAbitudine: View {
    let id: String?
    private struct Parte: Identifiable {
        let id: String
        var nome: String
        var fascia: String
        var ora: Date?
    }
    @State private var b: J = .null
    @State private var parti: [Parte] = []
    @State private var esistente = false
    @State private var remind: Date?
    @Environment(\.dismiss) private var chiudi

    private let emoji: [(String, [String])] = [
        ("Salute", ["💊", "🩺", "🦷", "🧘", "😴", "🛌", "💧", "🥤", "🧴", "🧼", "🌡️", "🫀", "🧠", "👁️", "🦴"]),
        ("Movimento", ["🏃", "🚴", "🏋️", "🤸", "🧗", "🏊", "⚽", "🎾", "🥊", "⛹️", "🚶", "🧎", "🤾", "🏸", "🛹"]),
        ("Cibo", ["🥗", "🍎", "🥦", "🍳", "🥑", "🐟", "🍚", "🥜", "☕", "🍵", "🚫", "🍺", "🍫", "🧂", "🥛"]),
        ("Mente", ["📖", "✍️", "📝", "🎧", "🎸", "🎹", "🎨", "🧩", "♟️", "🗣️", "🌍", "💭", "📚", "🔬", "💡"]),
        ("Lavoro", ["💻", "📊", "📅", "✅", "📈", "🧾", "📮", "🗂️", "⏰", "🎯", "🚀", "🛠️", "🔑", "📌", "💼"]),
        ("Casa", ["🧹", "🧺", "🪴", "🐕", "🐈", "🍽️", "🛒", "🔧", "🚗", "🗑️", "🛏️", "🚿", "🪟", "🧽", "📦"]),
        ("Umore", ["⭐️", "🔥", "❤️", "🙏", "😌", "🌙", "☀️", "🌱", "🏆", "💎", "🎉", "🤝", "🕯️", "🧿", "✨"]),
    ]

    private func ora(_ s: String?) -> Date? {
        guard let s, s.count >= 4 else { return nil }
        return Tempo.istante(Tempo.oggi(), s)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(b.emoji.str ?? "⭐️").font(.largeTitle).frame(width: 60, height: 60).background(tinta(b.tint).opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        TextField("Nome dell'abitudine", text: Binding(get: { b.name.t }, set: { b["name"] = .str($0) })).font(.title3)
                    }
                }
                Section("Colore") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(abi("dati.TINTE").list, id: \.self) { t in
                                Button { b["tint"] = t } label: {
                                    Circle().fill(tinta(t)).frame(width: 32, height: 32).overlay(Circle().stroke(Color.primary, lineWidth: b.tint == t ? 2 : 0).padding(-3))
                                }
                                .buttonStyle(.plain)
                                .padding(3)
                            }
                        }
                    }
                }
                Section("Simbolo") {
                    ForEach(emoji, id: \.0) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.0).font(.caption).foregroundStyle(Color.secondarioLife)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 4) {
                                ForEach(g.1, id: \.self) { e in
                                    Button { b["emoji"] = .str(e) } label: {
                                        Text(e).font(.title3).frame(width: 36, height: 36).background(b.emoji.t == e ? Color(uiColor: .tertiarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section("Quando") {
                    Picker("Quando", selection: Binding(get: { b.sched.type.t }, set: { b["sched"]["type"] = .str($0) })) {
                        Text("Ogni giorno").tag("daily")
                        Text("Certi giorni").tag("days")
                        Text("A settimana").tag("weekly")
                    }
                    .pickerStyle(.segmented)
                    if b.sched.type.t == "days" {
                        HStack(spacing: 6) {
                            ForEach([(1, "L"), (2, "M"), (3, "M"), (4, "G"), (5, "V"), (6, "S"), (0, "D")], id: \.0) { d in
                                let attivo = b.sched.days.list.contains(.n(d.0))
                                Button {
                                    var l = b.sched.days.list
                                    if attivo { l.removeAll { $0 == .n(d.0) } } else { l.append(.n(d.0)) }
                                    b["sched"]["days"] = .arr(l)
                                } label: {
                                    Text(d.1).font(.footnote.weight(.semibold)).frame(width: 36, height: 36).foregroundStyle(attivo ? Color.white : Color.primary).background(attivo ? accentoAbi : Color(uiColor: .tertiarySystemFill), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if b.sched.type.t == "weekly" {
                        Stepper("\(b.sched.times.int ?? 3) volte a settimana", value: Binding(get: { b.sched.times.int ?? 3 }, set: { b["sched"]["times"] = .n($0) }), in: 1...6)
                        Text("Il giorno lo scegli tu. L'app la chiede solo quando saltarla ti farebbe mancare la quota.").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                }
                Section {
                    ForEach($parti) { $p in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Cleanser", text: $p.nome)
                            Toggle("A un'ora precisa", isOn: Binding(get: { p.ora != nil }, set: { p.ora = $0 ? (p.ora ?? Tempo.istante(Tempo.oggi(), "08:00")) : nil })).font(.footnote)
                            if let o = p.ora {
                                DatePicker("Ora", selection: Binding(get: { o }, set: { p.ora = $0 }), displayedComponents: .hourAndMinute).font(.footnote)
                            }
                        }
                    }
                    .onDelete { parti.remove(atOffsets: $0) }
                    .onMove { parti.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        parti.append(Parte(id: nuovoIdLogica("pt"), nome: "", fascia: "qualsiasi", ora: nil))
                    } label: { Label("Aggiungi una parte", systemImage: "plus") }
                } header: {
                    Text("Parti")
                } footer: {
                    Text(parti.isEmpty ? "Facoltative. Servono quando una spunta sola nasconde più cose in momenti diversi della giornata." : "Ognuna con la sua ora. Quelle alla stessa ora arrivano in una notifica sola, e solo se non le hai già spuntate.")
                }
                Section {
                    if parti.isEmpty {
                        Toggle("Promemoria", isOn: Binding(get: { remind != nil }, set: { remind = $0 ? (remind ?? Tempo.istante(Tempo.oggi(), "08:00")) : nil }))
                        if let r = remind {
                            DatePicker("Ora", selection: Binding(get: { r }, set: { remind = $0 }), displayedComponents: .hourAndMinute)
                        }
                    } else {
                        Toggle("L'ordine conta", isOn: Binding(get: { b.sequenza.vero }, set: { b["sequenza"] = .bool($0) }))
                    }
                } footer: {
                    Text(parti.isEmpty ? "Vuoto = nessuna notifica. Arriva solo se non l'hai ancora segnata." : "Con l'ordine, i passaggi si numerano e si spuntano in sequenza.")
                }
                if esistente {
                    Section {
                        Toggle("Archiviata", isOn: Binding(get: { b.archived.vero }, set: { b["archived"] = .bool($0) }))
                    } footer: {
                        Text("Archiviata sparisce dal giorno ma tiene lo storico: riattivandola riparte da dov'era.")
                    }
                    Section {
                        BottoneElimina(testo: "Elimina abitudine") {
                            abi("dati.eliminaAbitudine", b.id)
                            avviso("Eliminata.")
                            chiudi()
                        }
                    }
                }
            }
            .environment(\.timeZone, Tempo.roma)
            .navigationTitle(esistente ? "Modifica" : "Nuova abitudine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: salva).fontWeight(.semibold) }
            }
        }
        .onAppear(perform: carica)
    }

    private func carica() {
        guard b.isNull else { return }
        let h = id.map { abi("dati.abitudinePerId", .str($0)) } ?? .null
        if h.isNull {
            b = ["id": .str(nuovoIdLogica("h")), "name": "", "emoji": "⭐️", "tint": "blue", "sched": ["type": "daily", "days": [1, 2, 3, 4, 5, 6, 0], "times": 3], "remind": "", "archived": false, "parti": [], "orari": [:]]
        } else {
            esistente = true
            b = h
            b["sched"] = abi("calcolo.pianoDi", h)
            parti = h.parti.list.map { p in
                Parte(id: p.id.t, nome: p.nome.t, fascia: p.fascia.str ?? "qualsiasi", ora: ora(abi("dati.oraDiParte", h, p).str))
            }
            remind = ora(h.remind.str)
        }
    }

    private func salva() {
        let nome = b.name.t.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return avviso("Serve un nome.", errore: true) }
        var orari: [String: J] = [:]
        let scritte: [J] = parti.filter { !$0.nome.trimmingCharacters(in: .whitespaces).isEmpty }.map { p in
            let n = p.nome.trimmingCharacters(in: .whitespaces)
            guard let o = p.ora else { return ["id": .str(p.id), "nome": .str(n), "fascia": .str(p.fascia)] }
            let hhmm = Tempo.oraRoma(o)
            let f = abi("dati.fasciaDiOra", .str(hhmm)).t
            if orari[f] == nil || hhmm < orari[f]!.t { orari[f] = .str(hhmm) }
            return ["id": .str(p.id), "nome": .str(n), "fascia": .str(f), "ora": .str(hhmm)]
        }
        var x = b
        x["name"] = .str(nome)
        x["parti"] = .arr(scritte)
        if !scritte.isEmpty { x["orari"] = .obj(orari) }
        x["remind"] = .str(remind.map { Tempo.oraRoma($0) } ?? "")
        abi("dati.salvaAbitudine", x)
        avviso(esistente ? "Modificata." : "Aggiunta.")
        chiudi()
    }
}
