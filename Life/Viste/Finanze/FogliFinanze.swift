import SwiftUI
import UniformTypeIdentifiers

// I fogli di Finanze: dettaglio, in arrivo, categoria, pocket, ricariche, lista d'attesa,
// obiettivo, cuscinetto, giorno di paga, stipendio, ricorrenti, chiusura.

/// Un campo importo in una riga di Form.
struct CampoEuro: View {
    let etichetta: String
    @Binding var testo: String
    var body: some View {
        HStack {
            Text(etichetta)
            TextField("0,00", text: $testo)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onChange(of: testo) { _, v in
                    let p = pulisciImporto(v)
                    if p != v { testo = p }
                }
            Text("€").foregroundStyle(Color.secondarioLife)
        }
    }
}

/// Elimina in due tocchi, come sul sito.
struct BottoneElimina: View {
    var testo = "Elimina"
    var azione: () -> Void
    @State private var sicuro = false
    var body: some View {
        Button(role: .destructive) {
            if sicuro {
                azione()
            } else {
                sicuro = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { sicuro = false }
            }
        } label: {
            Text(sicuro ? "Tocca di nuovo per eliminare" : testo).frame(maxWidth: .infinity)
        }
    }
}

private func cifraGrande(_ t: String, colore: Color? = nil) -> some View {
    Text(t).font(.system(size: 40, weight: .semibold)).monospacedDigit().foregroundStyle(colore ?? Color.primary).lineLimit(1).minimumScaleFactor(0.6)
}

private func tre(_ voci: [(String, String)]) -> some View {
    HStack(spacing: 8) {
        ForEach(voci, id: \.0) { v in
            VStack(alignment: .leading, spacing: 1) {
                Text(v.0).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1)
                Text(v.1).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: Dettaglio

struct FoglioDettaglio: View {
    let id: String
    @ObservedObject private var logica = Logica.s
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let _ = logica.versione
        let m = fin("dati.movimentiVivi").list.first { $0.id.t == id } ?? .null
        let eStipendio = m.tipo.t == "in" && (m.stip.vero || m.nota.t.lowercased().contains("stipendio"))
        if m.isNull {
            Foglio(titolo: "Movimento") { Text("Non c'è più.").foregroundStyle(Color.secondarioLife) }
        } else if eStipendio, !fin("paga.pagaCompleta", m.data).vero {
            FoglioPaga(dataStip: m.data.t, entrata: m.imp.d)
                .onAppear {
                    // Un'entrata scritta a mano «Stipendio» senza il segno diventa stipendio
                    if !m.stip.vero {
                        var c = m
                        c["stip"] = true
                        fin("dati.salvaMovimento", c)
                    }
                }
        } else {
            contenuto(m, eStipendio)
        }
    }

    private func contenuto(_ m: J, _ eStipendio: Bool) -> some View {
        let tipo = m.tipo.t
        let c = fin("dati.categoriaPerId", m.cat)
        let eff = fin("calcolo.importoEffettivo", m).d
        let ctx = fin("calcolo.contestoMovimento", m)
        let (y, mese, g) = Tempo.parti(m.data.t)
        let data = "\(Tempo.settimanaLunga[Tempo.giornoSettimana(m.data.t)]) \(g) \(Tempo.mesiLunghi[mese - 1].lowercased()) \(y)"
        let natura = tipo == "out" ? (m.ecc.vero ? "Straordinaria · fuori budget" : "Ordinaria · dentro il budget") : tipo == "extra" ? "Sforamento del sistema pocket" : tipo == "giro" ? "Giroconto · neutro sul budget" : etichettaTipo(tipo)
        let entra = ["in", "rimb", "reso"].contains(tipo)
        let agganciato: String? = m.rif.vero ? (fin("dati.movimentiVivi").list.first { $0.id == m.rif }?.nota.str ?? "spesa non trovata") : nil
        return NavigationStack {
            Pagina {
                VStack(spacing: 6) {
                    cifraGrande(euro(entra || tipo == "giro" ? eff : -eff, segno: entra), colore: entra ? verdeEntrata : tipo == "giro" ? nil : .pericoloLife)
                    if eff != m.imp.d { Text("lordo \(euro(m.imp)) · rimborsato \(euro(m.imp.d - eff))").font(.footnote).foregroundStyle(Color.secondarioLife) }
                    Text(m.nota.vero ? m.nota.t : etichettaTipo(tipo)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    if !c.isNull {
                        HStack(spacing: 5) {
                            Circle().fill(coloreCat(m.cat.str)).frame(width: 8, height: 8)
                            Text(c.nome.t + (m.sub.vero ? " · \(m.sub.t)" : ""))
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(coloreCat(m.cat.str).opacity(0.15), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                Carta {
                    RigaFin(titolo: "Data", valore: data)
                    RigaFin(titolo: "Natura", valore: natura)
                    if tipo == "out", ctx.simili.d > 1 {
                        let sc = ctx.scostamento.num
                        RigaFin(titolo: "Media \(m.sub.str ?? c.nome.str ?? "categoria")", valore: euro(ctx.media) + (sc.map { abs($0) >= 5 ? " (\($0 > 0 ? "+" : "")\(Int($0))%)" : "" } ?? ""))
                    }
                    if tipo == "out", !ctx.quotaSulMese.isNull { RigaFin(titolo: "Peso sul mese", valore: "\(ctx.quotaSulMese.int ?? 0)% della spesa ordinaria") }
                    if tipo == "out", ctx.simili.d > 0 { RigaFin(titolo: "Frequenza", valore: "\(plurale(ctx.simili, "volta", "volte")) in archivio") }
                    if !ctx.rimborsi.list.isEmpty { RigaFin(titolo: "Rimborsi", valore: "\(ctx.rimborsi.list.count) · \(euro(ctx.rimborsi.list.reduce(0) { $0 + $1.imp.d }))") }
                    if let agganciato { RigaFin(titolo: "Agganciato a", valore: agganciato) }
                }
                if !ctx.rimborsi.list.isEmpty {
                    Sezione("Rimborsi agganciati") {
                        Carta(padding: 12) { ForEach(ctx.rimborsi.list, id: \.id) { RigaMovimento(m: $0) } }
                    }
                }
                if eStipendio {
                    PulsantePieno(testo: "La divisione dello stipendio", colore: accentoFinanze) { Fogli.s.apri(.paga(m.data.t, m.imp.d)) }
                }
                BottoneElimina {
                    fin("dati.eliminaMovimento", m.id)
                    avviso("Eliminato.")
                    chiudi()
                }
            }
            .navigationTitle(tipo == "out" ? "Uscita" : etichettaTipo(tipo))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } }
                ToolbarItem(placement: .primaryAction) { Button("Modifica") { Fogli.s.apri(.movimento(m, tipo, nil)) } }
            }
        }
    }
}

// MARK: In arrivo

struct FoglioArrivo: View {
    let voce: J
    @State private var testo = ""
    @Environment(\.dismiss) private var chiudi

    private var imp: Int { centesimi(testo) ?? 0 }

    var body: some View {
        let oggi = Logica.s.chiama("ui.oggiISO")
        let fra = voce.fra.int ?? 0
        let quando = fra == 0 ? "oggi" : fra == 1 ? "domani" : fra < 0 ? "\(abs(fra)) giorni fa" : "fra \(fra) giorni"
        let umana = dataUmana(voce.quando.t)
        let sotto = "\(umana.maiuscola)\(umana.lowercased() == quando ? "" : " · \(quando)")"
        var pagata = voce
        pagata["importo"] = .n(imp > 0 ? imp : voce.importo.int ?? 0)
        let cop = voce.entrata.vero ? J.null : fin("calcolo.coperturaDi", pagata)
        return NavigationStack {
            Form {
                Section {
                    VStack(spacing: 4) {
                        cifraGrande((voce.entrata.vero ? "+" : "") + euro(voce.importo), colore: voce.entrata.vero ? verdeEntrata : nil)
                        Text(sotto).font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                if voce.entrata.vero {
                    Section {
                        LabeledContent("Entra su", value: nomePocket(voce.pocket.str))
                        LabeledContent("Tipo", value: "Entrata attesa")
                        if voce.nota.vero { LabeledContent("Nota", value: voce.nota.t) }
                    }
                    Section {
                        CampoEuro(etichetta: "Arrivati", testo: $testo)
                    } footer: {
                        Text("Già scritto quello atteso. Correggilo se è arrivata un'altra cifra.")
                    }
                    Section {
                        Button("È arrivato") { arrivato(oggi) }.fontWeight(.semibold)
                        Button("Era già registrato, non aggiungere niente") { giaPagata() }
                        BottoneElimina(testo: "Non arriverà: elimina") { elimina() }
                    } footer: {
                        Text("Registra l'entrata di oggi su \(nomePocket(voce.pocket.str)), che sale da subito, e toglie la voce da «In arrivo».")
                    }
                } else {
                    Section {
                        LabeledContent("Esce da", value: nomePocket(voce.pocket.str))
                        LabeledContent("Tipo", value: voce.origine.t == "previsto" ? "Una tantum" : etichettaCadenza(voce))
                        if voce.cat.vero { LabeledContent("Categoria", value: fin("dati.categoriaPerId", voce.cat).nome.str ?? voce.cat.t) }
                        if voce.stimato.vero { LabeledContent("Importo", value: "stimato") }
                        if voce.nota.vero { LabeledContent("Nota", value: voce.nota.t) }
                    }
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: cop.coperto.vero ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").font(.title2).foregroundStyle(cop.coperto.vero ? Color.successoLife : Color.pericoloLife)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cop.coperto.vero ? "I soldi ci sono" : "Mancano \(euro(cop.manca, tondo: true))").font(.subheadline.weight(.semibold))
                                Text("\(nomePocket(cop.pocket.str)): \(euro(cop.saldo)) disponibili").font(.caption).foregroundStyle(Color.secondarioLife)
                            }
                        }
                    }
                    Section {
                        CampoEuro(etichetta: "Pagato", testo: $testo)
                    } footer: {
                        Text("Già scritto quello previsto. Correggilo se la cifra vera è un'altra.")
                    }
                    Section {
                        Button("Paga") { paga(oggi) }.fontWeight(.semibold)
                        Button("Era già pagata, non registrare niente") { giaPagata() }
                        BottoneElimina(testo: voce.origine.t == "previsto" ? "Non ci sarà: elimina" : "Elimina il ricorrente") { elimina() }
                    } footer: {
                        Text("«Paga» registra il movimento di oggi. \(voce.origine.t == "previsto" ? "Il pagamento previsto non torna più." : "Il ricorrente resta, e riparte dalla prossima scadenza.")")
                    }
                }
            }
            .navigationTitle(voce.nome.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } } }
        }
        .onAppear { if testo.isEmpty { testo = testoDa(voce.importo.d) } }
    }

    private func arrivato(_ oggi: J) {
        guard imp > 0 else { return avviso("Serve un importo.", errore: true) }
        fin("dati.salvaMovimento", ["id": .str(nuovoIdLogica("m")), "data": oggi, "tipo": "in", "imp": .n(imp), "nota": voce.nome, "cat": nil, "sub": nil, "pocket": .str(voce.pocket.str ?? "principale"), "ecc": false, "pian": voce.id])
        fin("dati.segnaPrevistoPagato", voce.id, oggi)
        celebra("Arrivato")
        chiudi()
    }

    private func paga(_ oggi: J) {
        guard imp > 0 else { return avviso("Serve un importo.", errore: true) }
        fin("dati.salvaMovimento", ["id": .str(nuovoIdLogica("m")), "data": oggi, "tipo": "out", "imp": .n(imp), "nota": voce.nome, "cat": .str(voce.cat.str ?? "fisse"), "sub": nil, "pocket": .str(voce.pocket.str ?? "principale"), "ecc": false, "pian": voce.id])
        if voce.origine.t == "previsto" {
            fin("dati.segnaPrevistoPagato", voce.id, oggi)
        } else {
            fin("dati.segnaScadenzaPagata", voce.id, voce.quando)
        }
        celebra(voce.nome.t.count <= 22 ? voce.nome.t : "Pagato")
        chiudi()
    }

    private func elimina() {
        if voce.origine.t == "previsto" || voce.entrata.vero {
            fin("dati.eliminaPrevisto", voce.id)
        } else {
            fin("dati.eliminaRicorrente", voce.id)
        }
        avviso("Eliminato.")
        chiudi()
    }

    private func giaPagata() {
        if voce.origine.t == "previsto" {
            fin("dati.segnaPrevistoPagato", voce.id, voce.quando)
        } else {
            fin("dati.segnaScadenzaPagata", voce.id, voce.quando)
        }
        avviso("Segnata come pagata. Nessun movimento aggiunto.")
        chiudi()
    }
}

func etichettaCadenza(_ r: J) -> String {
    let nomi = ["mensile": "Ogni mese", "bimestrale": "Ogni 2 mesi", "trimestrale": "Ogni 3 mesi", "semestrale": "Ogni 6 mesi", "annuale": "Ogni anno"]
    let c = nomi[r.cadenza.t] ?? r.cadenza.t
    if r.cadenza.t == "mensile" { return "\(c) il \(r.giorno.t)" }
    return "\(c) · \(r.giorno.t) \(Tempo.mesiLunghi[max(0, (r.mese.int ?? 1) - 1)].lowercased())"
}

// MARK: Categoria e sottocategoria

struct FoglioCategoria: View {
    let catId: String
    let mese: String
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let c = fin("dati.categoriaPerId", .str(catId))
        let ciclo = fin("analisi.cicloPerIndice", .str(mese))
        let st = fin("calcolo.statisticheDelCiclo", ciclo)
        let x = st.perCat[catId]
        let tot = x.tot.d
        let movs = x.movs.list
        let budget = (fin("dati.profiloDi")["b"][catId].d * 100).rounded()
        let medio = movs.isEmpty ? 0 : (tot / Double(movs.count)).rounded()
        let sei = fin("calcolo.categoriaSuSeiCicli", ciclo, .str(catId))
        let sub = x.sub.dict.sorted { $0.value.tot.d > $1.value.tot.d }
        let oggi = Logica.s.chiama("ui.oggiISO").t
        let inCorso = ciclo.da.t <= oggi && oggi <= ciclo["a"].t
        let nome = fin("calcolo.nomeCiclo", ciclo).t
        return Foglio(titolo: c.nome.t) {
            Pagina {
                tre([(inCorso ? "Questo ciclo" : nome, euro(tot)), ("Budget", budget > 0 ? euro(budget, tondo: true) : "—"), ("Scontrino medio", movs.isEmpty ? "—" : euro(medio))])
                if budget > 0 {
                    Barra(valore: tot / budget, colore: tot >= budget ? .pericoloLife : tot >= budget * 0.9 ? arancioneAvviso : coloreCat(catId))
                    Text("\(Int((tot / budget * 100).rounded()))% del budget · \(tot <= budget ? "restano \(euro(budget - tot))" : "sforato di \(euro(tot - budget))")").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
                Sezione("Sei cicli") {
                    Carta {
                        GraficoBarre(valori: sei.valori.list.map(\.d), etichette: sei.etichette.list.map(\.t), evidenzia: 5, retta: budget > 0 ? budget : nil, colore: coloreCat(catId))
                    }
                }
                if !sub.isEmpty {
                    Sezione("Sottocategorie") {
                        Carta(padding: 12) {
                            ForEach(sub, id: \.key) { s in
                                RigaFin(titolo: s.key, sotto: "\(plurale(s.value.n, "volta", "volte")) · medio \(euro((s.value.tot.d / max(1, s.value.n.d)).rounded()))", valore: euro(s.value.tot), freccia: true) {
                                    Fogli.s.apri(.sub(catId, s.key, mese))
                                }
                            }
                        }
                    }
                }
                Sezione("Movimenti del ciclo") {
                    if movs.isEmpty { Text("Nessun movimento fra il \(nome).").font(.footnote).foregroundStyle(Color.secondarioLife) }
                    if !movs.isEmpty { Carta(padding: 12) { ForEach(movs, id: \.id) { RigaMovimento(m: $0) } } }
                }
            }
        }
    }
}

struct FoglioSub: View {
    let catId: String
    let sub: String
    let mese: String

    var body: some View {
        let ciclo = fin("analisi.cicloPerIndice", .str(mese))
        let tutti = fin("calcolo.movimentiSottocategoria", .str(catId), .str(sub)).list
        let dentro: (J) -> Bool = { $0.data.t >= ciclo.da.t && $0.data.t <= ciclo["a"].t }
        let delMese = tutti.filter(dentro)
        let tot: ([J]) -> Double = { $0.reduce(0) { $0 + fin("calcolo.importoEffettivo", $1).d } }
        let prima = Array(tutti.filter { !dentro($0) }.prefix(12))
        let totMese = tot(delMese)
        let nome = fin("calcolo.nomeCiclo", ciclo).t
        return Foglio(titolo: sub) {
            Pagina {
                Text(fin("dati.categoriaPerId", .str(catId)).nome.t).font(.footnote).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity)
                tre([("Questo ciclo", euro(totMese)), ("Volte", "\(delMese.count)"), ("Medio", delMese.isEmpty ? "—" : euro((totMese / Double(delMese.count)).rounded()))])
                Sezione("Movimenti del ciclo") {
                    if delMese.isEmpty { Text("Nessun movimento fra il \(nome).").font(.footnote).foregroundStyle(Color.secondarioLife) }
                    if !delMese.isEmpty { Carta(padding: 12) { ForEach(delMese, id: \.id) { RigaMovimento(m: $0) } } }
                }
                if !prima.isEmpty {
                    Sezione("Prima di questo ciclo") {
                        Carta(padding: 12) { ForEach(prima, id: \.id) { RigaMovimento(m: $0) } }
                    }
                    Text("In archivio: \(tutti.count) movimenti per \(euro(tot(tutti))) in totale.").font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
        }
    }
}

// MARK: Pocket

struct FoglioPocket: View {
    private struct Voce: Identifiable {
        let id: String
        let nome: String
        var testo: String
    }
    @State private var voci: [Voce] = []
    @State private var cassa = ""
    private let note = [
        "principale": "Revolut · la settimana corrente. È l'unico conto da cui si spende.",
        "cassa": "Revolut · le settimane future del mese. Parcheggio, non spendibile.",
        "fisse": "Revolut · gli addebiti automatici. Non si tocca.",
        "ing": "Il deposito. Riserva: alimenta gli altri, non si spende da qui.",
    ]

    var body: some View {
        Foglio(titolo: "Saldi dei pocket", fatto: "Salva", azione: salva) {
            Form {
                Section {
                    Text("Qui c'è quello che l'app crede di avere. Apri il conto e confronta: se combacia, non toccare niente. Se no, scrivi il numero che vedi adesso: alle spese già segnate oggi ci pensa l'app.").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
                ForEach($voci) { $v in
                    Section {
                        CampoEuro(etichetta: v.nome, testo: $v.testo)
                    } footer: {
                        if let n = note[v.id] { Text(n) }
                    }
                }
                Section {
                    CampoEuro(etichetta: "Ogni lunedì", testo: $cassa)
                } header: {
                    Text("Il travaso del lunedì")
                } footer: {
                    Text("Quanto passa dalla Cassa al Principale ogni lunedì. È il budget della settimana.")
                }
            }
        }
        .onAppear {
            if voci.isEmpty {
                voci = fin("calcolo.pocketConSaldi").list.map { Voce(id: $0.id.t, nome: $0.nome.t, testo: testoDa($0.saldoVero.d)) }
                cassa = testoDa(fin("dati.stato").config.cassaSettimanale.d)
            }
        }
    }

    private func salva() {
        let oggi = Logica.s.chiama("ui.oggiISO")
        for v in voci {
            let delta = fin("calcolo.deltaPocket", .str(v.id), oggi).d
            fin("dati.riancoraPocket", .str(v.id), .num(Double(centesimi(v.testo) ?? 0) - delta), oggi)
        }
        fin("ponte.meta", ["config", "cassaSettimanale"], .n(centesimi(cassa) ?? 0))
        avviso("Saldi aggiornati.")
    }
}

// MARK: Ricariche

struct FoglioRicariche: View {
    let quale: String
    @State private var testo = ""
    @State private var fonte = "cassa"
    @State private var perche = ""
    @Environment(\.dismiss) private var chiudi

    private var imp: Double { Double(centesimi(testo) ?? 0) }

    var body: some View {
        let oggi = Logica.s.chiama("ui.oggiISO")
        let r = fin("travasi.ricaricaLunedi", oggi)
        let saldoCassa = fin("calcolo.saldoPocket", "cassa").d
        let daIng = saldoCassa <= 0
        let massimo = daIng ? fin("calcolo.saldoPocket", "ing").d : saldoCassa
        let principale = fin("calcolo.saldoPocket", "principale").d
        let s = fin("calcolo.settimana", oggi)
        let sf = fin("calcolo.sforamenti", fin("calcolo.cicloDi", oggi))
        return NavigationStack {
            Form {
                if quale == "ricaricaSett" {
                    Section {
                        LabeledContent(daIng ? "ING" : "Cassa", value: euro(massimo))
                        LabeledContent("Principale", value: euro(principale))
                    }
                    if daIng {
                        Section { Text("Cassa vuota. La ricarica arriva da ING e viene contata come sforamento.").font(.footnote).foregroundStyle(arancioneAvviso) }
                    } else if saldoCassa < r.importo.d {
                        Section { Text("In Cassa ci sono solo \(euro(saldoCassa)). Puoi trasferire quello che c'è, oppure prendere il resto da ING: quello sì conta come sforamento.").font(.footnote).foregroundStyle(arancioneAvviso) }
                    }
                    Section {
                        CampoEuro(etichetta: "Trasferisci", testo: $testo)
                    } header: {
                        Text("Quota \(euro(r.quota)) × \(plurale(r.giorni, "giorno", "giorni")) fino al \(dataBreve(r.fino.t)) = \(euro(r.bersaglio)). In tasca \(euro(r.saldo)).").textCase(nil)
                    } footer: {
                        Text("Dopo: \(daIng ? "ING" : "Cassa") \(euro(massimo - min(imp, massimo))) · Principale \(euro(principale + min(imp, massimo)))")
                    }
                    Section {
                        Button(imp > 0 ? "Trasferisci \(euro(min(imp, massimo)))" : "Quanto?") {
                            let x = min(imp, massimo)
                            fin("dati.salvaMovimento", ["id": .str(nuovoIdLogica("m")), "data": oggi, "tipo": daIng ? "extra" : "giro", "imp": .num(x), "pocket": daIng ? "ing" : "cassa", "pocketTo": "principale", "cat": nil, "sub": nil, "nota": daIng ? "Ricarica settimanale — Cassa vuota" : "Ricarica settimanale"])
                            fin("dati.segnaRicarica", oggi)
                            celebra("Settimana ricaricata")
                            chiudi()
                        }
                        .disabled(imp <= 0 || imp > massimo)
                        .fontWeight(.semibold)
                    } footer: {
                        Text(principale > 0 ? "Sul Principale ci sono ancora \(euro(principale)) della settimana scorsa: non si azzerano, si sommano." : "Quello che avanza a fine settimana resta sul Principale e si somma alla prossima ricarica.")
                    }
                } else if quale == "ricarica" {
                    Section {
                        Text("Restano \(plurale(s.giorniRimasti, "giorno", "giorni")) a lunedì. \(sf.n.d == 0 ? "Questo ciclo non hai ancora ricaricato." : "Questo ciclo hai già ricaricato \(plurale(sf.n, "volta", "volte")).")").font(.footnote).foregroundStyle(Color.secondarioLife)
                        Picker("Da dove", selection: $fonte) {
                            Text("Dalla Cassa").tag("cassa")
                            Text("Da ING").tag("ing")
                        }
                        .pickerStyle(.segmented)
                        Text(fonte == "ing" ? "Intacchi la riserva. Viene contato come sforamento." : imp > 0 ? "Anticipi la prossima settimana: lunedì avrai \(euro(max(0, s.budget.d - imp))) invece di \(euro(s.budget))." : "Nella Cassa ci sono \(euro(saldoCassa)).").font(.footnote).foregroundStyle(fonte == "ing" ? Color.pericoloLife : Color.secondarioLife)
                    }
                    Section {
                        CampoEuro(etichetta: "Importo", testo: $testo)
                        TextField("Perché: cena fuori non prevista", text: $perche)
                    } footer: {
                        Text("Il motivo è obbligatorio. A fine mese rileggere i motivi vale più dei totali.")
                    }
                    Section {
                        let ok = imp > 0 && perche.trimmingCharacters(in: .whitespaces).count >= 3
                        Button(ok ? "Ricarica \(euro(imp))" : imp > 0 ? "Scrivi perché, anche due parole" : "Quanto ti serve?") {
                            let motivo = perche.trimmingCharacters(in: .whitespaces)
                            fin("dati.salvaMovimento", ["id": .str(nuovoIdLogica("m")), "data": oggi, "tipo": fonte == "cassa" ? "giro" : "extra", "imp": .num(imp), "pocket": .str(fonte), "pocketTo": "principale", "cat": nil, "sub": nil, "nota": .str(fonte == "cassa" ? "Anticipo — \(motivo)" : motivo)])
                            avviso(fonte == "cassa" ? "Anticipo registrato." : "Sforamento registrato.")
                            chiudi()
                        }
                        .disabled(!ok)
                        .fontWeight(.semibold)
                    }
                } else {
                    Section {
                        Text("ING è una riserva che sta fuori dall'app: il saldo non si deduce dai movimenti, si copia dall'estratto conto. Si riancora a stasera, e da domani i travasi ripartono da qui.").font(.footnote).foregroundStyle(Color.secondarioLife)
                        CampoEuro(etichetta: "Saldo", testo: $testo)
                    }
                    Section {
                        Button("Salva") {
                            fin("dati.riancoraPocket", "ing", .num(imp), Logica.s.chiama("ui.piuGiorni", oggi, 1))
                            avviso("Saldo riancorato.")
                            chiudi()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle(quale == "ricaricaSett" ? "Ricarica settimanale" : quale == "ricarica" ? "Ricarica fuori ciclo" : "Saldo ING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } } }
        }
        .onAppear {
            guard testo.isEmpty else { return }
            if quale == "ricaricaSett" {
                testo = testoDa(min(r.importo.d, massimo))
            } else if quale == "saldoING" {
                testo = testoDa(fin("dati.pocketPerId", "ing").saldo.d)
            }
        }
    }
}

// MARK: Lista d'attesa

struct FoglioLista: View {
    @ObservedObject private var logica = Logica.s
    @State private var nome = ""
    @State private var testo = ""
    @State private var aggiungo = false
    @State private var scelta: String?
    @Environment(\.dismiss) private var chiudi

    private func coloreStato(_ v: String) -> Color {
        switch v {
        case "sbloccata": return .successoLife
        case "comprata": return accentoFinanze
        case "scartata": return .terziarioLife
        default: return .secondarioLife
        }
    }

    private func stato(_ v: String) -> some View {
        Text(["attesa": "in attesa", "sbloccata": "sbloccata", "comprata": "comprata", "scartata": "scartata"][v] ?? v)
            .font(.caption2.weight(.medium))
            .foregroundStyle(coloreStato(v))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(coloreStato(v).opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }

    var body: some View {
        let _ = logica.versione
        let adesso = J.num(Date().timeIntervalSince1970 * 1000)
        let iso = Logica.s.chiama("ui.oggiISO")
        let voci = fin("dati.vociLista").list.map { v -> J in
            var c = v
            c["vista"] = fin("dati.statoVoce", v, adesso)
            c["ore"] = fin("dati.oreAttesa", v, adesso)
            return c
        }
        .sorted { $0.ts.d > $1.ts.d }
        let attive = voci.filter { $0.vista.t == "attesa" || $0.vista.t == "sbloccata" }
        let chiuse = voci.filter { $0.vista.t == "comprata" || $0.vista.t == "scartata" }
        let aperta = scelta.flatMap { s in voci.first { $0.id.t == s } }
        return NavigationStack {
            Pagina {
                if let aperta {
                    Button { scelta = nil } label: { Label("Lista", systemImage: "chevron.left").font(.subheadline) }.tint(accentoFinanze)
                    PesaVoce(voce: aperta, p: fin("pesa.pesaVoce", aperta.imp, iso, ["id": aperta.id]), stato: AnyView(stato(aperta.vista.t))) {
                        fin("dati.cambiaStatoVoce", aperta.id, "scartata")
                        scelta = nil
                        avviso("Scartata.")
                    } compra: { compra(aperta) }
                } else {
                    if attive.isEmpty, !aggiungo {
                        Text("Una cosa sopra soglia si scrive qui, aspetta ventiquattro ore e poi si compra. È l'unico modo di comprarla senza che finisca in «Fuori piano».").font(.subheadline).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center).padding(.vertical, 24)
                    }
                    ForEach(attive, id: \.id) { v in rigaAttiva(v, iso) }
                    if aggiungo {
                        Carta {
                            TextField("Stampante, scarpe, biglietti…", text: $nome)
                            Divider()
                            CampoEuro(etichetta: "Prezzo", testo: $testo)
                        }
                        HStack(spacing: 8) {
                            PulsantePieno(testo: "Annulla", colore: Color(uiColor: .systemGray)) { aggiungo = false }
                            PulsantePieno(testo: "Metti in lista", colore: accentoFinanze, azione: aggiungi)
                        }
                    } else {
                        PulsantePieno(testo: "Aggiungi", colore: accentoFinanze) { aggiungo = true }
                    }
                    if !chiuse.isEmpty {
                        Sezione("Chiuse") {
                            Carta(padding: 12) {
                                ForEach(chiuse.prefix(12), id: \.id) { v in
                                    HStack {
                                        Text(v.nome.t).font(.subheadline).lineLimit(1)
                                        Spacer()
                                        Text(euro(v.imp)).font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife)
                                        stato(v.vista.t)
                                        Button { fin("dati.eliminaVoce", v.id) } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).foregroundStyle(Color.secondarioLife)
                                    }
                                }
                            }
                        }
                        Text("Restano per ricordare cosa hai lasciato perdere: è la parte della lista che si dimentica, ed è quella che la giustifica.").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                }
            }
            .navigationTitle(aperta?.nome.t ?? "Lista d'attesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } } }
        }
    }

    private func rigaAttiva(_ v: J, _ iso: J) -> some View {
        let e = fin("piano.effettoVoce", v.imp, iso)
        return Carta {
            Button { scelta = v.id.t } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(v.nome.t).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(euro(v.imp)).font(.subheadline).monospacedDigit()
                        stato(v.vista.t)
                    }
                    if v.vista.t == "attesa" { Text("Ancora \(plurale(v.ore, "ora", "ore")).").font(.caption).foregroundStyle(Color.secondarioLife) }
                    RigaValore(etichetta: "quota del giorno", valore: "da \(euro(e.settimana.da)) a \(euro(e.settimana["a"]))", colore: e.settimana["a"].d <= 0 ? .pericoloLife : nil)
                    RigaValore(etichetta: "minimo di ING", valore: "da \(euro(e.ing.da, tondo: true)) a \(euro(e.ing["a"], tondo: true))")
                    if !e.fondo.isNull { RigaValore(etichetta: "gap dell'obiettivo", valore: "da \(euro(e.fondo.da, tondo: true)) a \(euro(e.fondo["a"], tondo: true))") }
                    Label("Da dove escono, e se ha senso", systemImage: "chevron.right").font(.caption).foregroundStyle(accentoFinanze)
                }
            }
            .buttonStyle(.plain)
            HStack {
                Spacer()
                Button("Scarta") {
                    fin("dati.cambiaStatoVoce", v.id, "scartata")
                    avviso("Scartata.")
                }
                .buttonStyle(.bordered)
                Button("Compra") { compra(v) }.buttonStyle(.borderedProminent).tint(accentoFinanze).disabled(v.vista.t != "sbloccata")
            }
            .font(.footnote)
        }
    }

    private func aggiungi() {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return avviso("Manca il nome.", errore: true) }
        guard let imp = centesimi(testo) else { return avviso("Manca il prezzo.", errore: true) }
        fin("dati.salvaVoce", ["id": .str(nuovoIdLogica("w")), "nome": .str(n), "imp": .n(imp)])
        nome = ""
        testo = ""
        aggiungo = false
        avviso("In lista. Sbloccata fra \(plurale(fin("dati.ATTESA_ORE"), "ora", "ore")).")
    }

    private func compra(_ v: J) {
        fin("dati.cambiaStatoVoce", v.id, "comprata")
        Fogli.s.apri(.movimento(nil, "out", ["imp": v.imp, "nota": v.nome, "lista": v.id]))
    }
}

/// «Da dove escono, e se ha senso».
struct PesaVoce: View {
    let voce: J
    let p: J
    let stato: AnyView
    let scarta: () -> Void
    let compra: () -> Void

    private func giorni(_ n: J) -> String { plurale(n, "giorno", "giorni") }
    private func meno(_ c: Double) -> String { c > 0 ? "−\(euro(c))" : euro(0.0) }
    private func uno(_ n: Double) -> String { String(format: "%.1f", n).replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: ",0", with: "") }

    var body: some View {
        let sett = p.per.settimana
        let stip = p.per.stipendio
        let ing = p.per.ing
        let c = p.consiglio
        let (titolo, testo, colore, icona): (String, String, Color, String) = {
            switch c.tipo.t {
            case "adesso": return ("Ha senso adesso", "Dalla settimana: la razione scende da \(euro(sett.da)) a \(euro(sett["a"])) al giorno, per \(giorni(sett.giorni)).", .successoLife, "checkmark")
            case "aspetta":
                let t = sett.verdetto.t == "no"
                    ? "Adesso non ci sta: la settimana resterebbe a \(euro(sett["a"])) al giorno. Il \(glm(stip.paga.t)), fra \(giorni(p.attesa)), la razione del ciclo scende solo da \(euro(stip.da)) a \(euro(stip["a"]))."
                    : "Adesso la razione scenderebbe a \(euro(sett["a"])) al giorno. Aspettando \(giorni(p.attesa)), il ciclo dopo scende solo da \(euro(stip.da)) a \(euro(stip["a"]))."
                return ("Aspetta lo stipendio", t, accentoFinanze, "clock")
            case "stringi": return ("Si può, ma stringi", "Ti restano \(euro(sett["a"])) al giorno per \(giorni(sett.giorni)): sotto la soglia di \(euro(p.minima, tondo: true)).", arancioneAvviso, "exclamationmark.triangle")
            case "riserva": return ("Solo dalla riserva", "Né la settimana né il prossimo ciclo reggono. Da ING il minimo previsto scende a \(euro(ing["a"], tondo: true)).", arancioneAvviso, "exclamationmark.triangle")
            default: return ("Non ora", "Nessuna fonte regge senza svuotare la settimana, la riserva o il Naso.", .pericoloLife, "exclamationmark.triangle")
            }
        }()
        return Group {
            HStack(spacing: 10) {
                Text(euro(voce.imp)).font(.system(size: 32, weight: .semibold)).monospacedDigit()
                stato
                if voce.vista.t == "attesa" { Text("ancora \(plurale(voce.ore, "ora", "ore"))").font(.caption).foregroundStyle(Color.secondarioLife) }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icona).foregroundStyle(colore)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titolo).font(.subheadline.weight(.semibold))
                    Text(testo).font(.footnote).foregroundStyle(Color.secondarioLife)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colore.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 8) {
                if !p.vale.ore.isNull { valeCasella("\(uno(p.vale.ore.d)) h", "di lavoro") }
                if !p.vale.giorni.isNull { valeCasella("\(uno(p.vale.giorni.d)) gg", "di razione") }
                if !p.vale.giorniFondo.isNull { valeCasella("\(Int(p.vale.giorniFondo.d.rounded())) gg", "di \(p.vale.nomeFondo.str ?? "Fondo")") }
            }
            Text("A \(euro(p.vale.allOra)) l'ora netti, con la razione del piano di \(euro(p.vale.razionePiano)) al giorno.").font(.caption).foregroundStyle(Color.secondarioLife)
            Sezione("Da dove possono uscire") {
                Carta(padding: 12) {
                    ForEach(p.fonti.list, id: \.id) { f in fonte(f) }
                }
            }
            Sezione("I conti · dalla settimana") {
                Carta(padding: 12) {
                    RigaFin(titolo: "Principale, Contanti, Cassa", sotto: "stamattina", valore: euro(sett.conti.inizio))
                    RigaFin(titolo: "Già impegnati", sotto: "uscite fino al \(glm(sett.conti.fine.t))", valore: meno(sett.conti.impegni.d))
                    RigaFin(titolo: "Liberi", valore: euro(sett.conti.spendibile))
                    RigaFin(titolo: voce.nome.t, valore: meno(p.prezzo.d))
                    RigaFin(titolo: "Liberi dopo", valore: euro(sett.conti.dopo))
                    RigaFin(titolo: "÷ \(giorni(sett.conti.giorni))", valore: "\(euro(sett["a"])) al giorno")
                }
            }
            Sezione("I conti · dopo lo stipendio") {
                Carta(padding: 12) {
                    RigaFin(titolo: "Vita del ciclo", sotto: "dal \(glm(stip.paga.t))", valore: euro(stip.conti.vita))
                    RigaFin(titolo: voce.nome.t, valore: meno(p.prezzo.d))
                    RigaFin(titolo: "÷ \(giorni(stip.conti.giorni))", valore: "\(euro(stip["a"])) al giorno")
                }
            }
            Sezione("Non è sola") {
                Carta(padding: 12) {
                    if p.contesto.altre.d > 0 {
                        RigaFin(titolo: "Con il resto della lista", sotto: "\(plurale(p.contesto.altre, "altra voce", "altre voci")) · tutte oggi: \(euro(p.contesto.tutteRazione)) al giorno", valore: euro(p.contesto.tutte))
                    }
                    RigaFin(titolo: "Fuori piano in questo ciclo", sotto: p.contesto.fuoriPianoN.vero ? plurale(p.contesto.fuoriPianoN, "spesa", "spese") : "nessuna, finora", valore: euro(p.contesto.fuoriPiano))
                    if p.contesto.scartate.d > 0 {
                        RigaFin(titolo: "Lasciate perdere", sotto: "\(plurale(p.contesto.scartate, "voce", "voci")) dalla lista", valore: euro(p.contesto.risparmiato))
                    }
                }
            }
            HStack(spacing: 8) {
                PulsantePieno(testo: "Scarta", colore: Color(uiColor: .systemGray), azione: scarta)
                PulsantePieno(testo: voce.vista.t == "sbloccata" ? "Compra" : "Fra \(plurale(voce.ore, "ora", "ore"))", colore: accentoFinanze, azione: compra)
                    .disabled(voce.vista.t != "sbloccata")
                    .opacity(voce.vista.t == "sbloccata" ? 1 : 0.5)
            }
        }
    }

    private func valeCasella(_ a: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(a).font(.headline).monospacedDigit()
            Text(b).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func fonte(_ f: J) -> some View {
        let nomi = ["settimana": "Dalla settimana", "stipendio": "Dopo lo stipendio", "ing": "Da ING", "fondo": "Dal Fondo"]
        let tag = ["regge": "regge", "stretto": "stretto", "no": "non regge"]
        let scelta = p.consiglio.fonte == f.id
        let v = f.verdetto.t
        let coloreTag: Color = v == "regge" ? .successoLife : v == "stretto" ? arancioneAvviso : .pericoloLife
        let dettaglio: String = {
            switch f.id.t {
            case "settimana": return "razione da \(euro(f.da)) a \(euro(f["a"])) al giorno, per \(giorni(f.giorni))"
            case "stipendio": return "\(glm(f.paga.t)), fra \(giorni(f.attesa)) · razione del ciclo da \(euro(f.da)) a \(euro(f["a"]))"
            case "ing": return "minimo previsto da \(euro(f.da, tondo: true)) a \(euro(f["a"], tondo: true)), \(glm(f.quando.t))"
            default: return "gap da \(euro(f.da, tondo: true)) a \(euro(f["a"], tondo: true))" + (f.ritardo.vero ? " · \(f.nome.t) circa \(giorni(.num(f.ritardo.d.rounded()))) più tardi" : "")
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nomi[f.id.t] ?? f.id.t).font(.subheadline.weight(.medium))
                Spacer()
                Text(scelta ? "consigliata" : tag[v] ?? v)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(scelta ? Color.white : coloreTag)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scelta ? accentoFinanze : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 5))
            }
            Text(dettaglio).font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife)
            ForEach(f.mosse.list, id: \.self) { m in
                HStack(spacing: 6) {
                    Text(nomePocket(m.da.str))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Color.secondarioLife)
                    Text(nomePocket(m["a"].str))
                    Spacer()
                    Text(euro(m.imp, tondo: true)).fontWeight(.semibold).monospacedDigit()
                }
                .font(.footnote)
            }
            if f.id.t == "settimana", f.manca.d > 0 { Text("Mancano \(euro(f.manca, tondo: true)) anche con tutta la Cassa.").font(.caption).foregroundStyle(Color.pericoloLife) }
            if f.id.t == "settimana", !(f.manca.d > 0), f.mosse.list.isEmpty, v != "no" { Text("Nessun travaso: il Principale basta già.").font(.caption).foregroundStyle(Color.secondarioLife) }
            if f.id.t == "stipendio" { Text("Nessun travaso adesso: lo paghi dal Principale dopo quelli dello stipendio.").font(.caption).foregroundStyle(Color.secondarioLife) }
            if f.id.t == "ing", f.giaSotto.vero { Text("Il minimo è già sotto i \(euro(f.pavimento, tondo: true)) che servono a bollo e assicurazione.").font(.caption).foregroundStyle(Color.secondarioLife) }
            if f.id.t == "fondo", v == "no" { Text("Il Fondo non è un salvadanaio di scorta: ogni euro tolto sposta il traguardo.").font(.caption).foregroundStyle(Color.secondarioLife) }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Obiettivo

struct FoglioObiettivo: View {
    @ObservedObject private var logica = Logica.s
    @State private var nomeExtra = ""
    @State private var impExtra = ""
    @State private var meseExtra = ""
    @State private var nome = ""
    @State private var target = ""
    @State private var versamento = ""
    @State private var caricato = false
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let _ = logica.versione
        let iso = Logica.s.chiama("ui.oggiISO")
        let o = fin("piano.obiettivo")
        let s = fin("piano.tiroObiettivo", iso)
        let cfg = fin("dati.statoConfig", fin("calcolo.ultimoStipendio", iso))
        let fondo = fin("piano.serieFondo", iso)
        let passo = fin("piano.passoObiettivo", iso)
        let nomeFondo = fin("dati.stato").pockets.list.first { $0.id.t == (o.pocket.str ?? "fondo") }?.nome.str ?? "Fondo"
        return NavigationStack {
            Form {
                if !s.isNull { sezioniStato(s, fondo: fondo, passo: passo, iso: iso.t, o: o, nomeFondo: nomeFondo) }
                if cfg.bloccata.vero {
                    Section {
                        Text("Configurazione bloccata. Si modifica nelle 48 ore dopo lo stipendio, oppure con uno sblocco motivato da «Altro».").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                }
                Section("Il traguardo") {
                    HStack {
                        Text("Nome")
                        TextField("Obiettivo", text: $nome).multilineTextAlignment(.trailing).onSubmit { scrivi(cfg, "nome", .str(nome.isEmpty ? "Obiettivo" : nome)) }
                    }
                    CampoEuro(etichetta: "Target", testo: $target)
                    Toggle("Il target è una stima", isOn: Binding(get: { o.provvisorio.vero }, set: { scrivi(cfg, "provvisorio", .bool($0)) }))
                    DatePicker("Entro il", selection: Binding(get: { Tempo.istante(o.data.str ?? Tempo.oggi(), "12:00") }, set: { scrivi(cfg, "data", .str(Tempo.dataRoma($0))) }), displayedComponents: .date)
                    CampoEuro(etichetta: "Versamento per stipendio", testo: $versamento)
                    Button("Salva target e versamento") {
                        scrivi(cfg, "nome", .str(nome.isEmpty ? "Obiettivo" : nome))
                        scrivi(cfg, "target", .n(centesimi(target) ?? 0))
                        scrivi(cfg, "versamento", .n(centesimi(versamento) ?? 0))
                        avviso("Salvato.")
                    }
                }
                Section {
                    ForEach(o.extra.list, id: \.id) { x in
                        LabeledContent(x.nome.t, value: "\(x.quando.t)\(x.stimato.vero ? " · stima" : "") · \(euro(x.imp, tondo: true))")
                    }
                    .onDelete { i in
                        var l = o.extra.list
                        l.remove(atOffsets: i)
                        scrivi(cfg, "extra", .arr(l))
                    }
                    TextField("Nome", text: $nomeExtra)
                    CampoEuro(etichetta: "Importo", testo: $impExtra)
                    TextField("Mese (es. 2026-12)", text: $meseExtra).keyboardType(.numbersAndPunctuation)
                    Button("Aggiungi") {
                        let e: J = ["id": .str(nuovoIdLogica("x")), "nome": .str(nomeExtra.trimmingCharacters(in: .whitespaces)), "imp": .n(centesimi(impExtra) ?? 0), "quando": .str(meseExtra), "stimato": true]
                        scrivi(cfg, "extra", .arr(o.extra.list + [e]))
                        nomeExtra = ""
                        impExtra = ""
                        meseExtra = ""
                    }
                    .disabled(nomeExtra.isEmpty || centesimi(impExtra) == nil || meseExtra.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) == nil)
                } header: {
                    Text("Extra previsti")
                } footer: {
                    Text("Entrate una tantum che finiscono nel fondo: la tredicesima, un rimborso. Entrano nella proiezione, non nel «previsto a oggi».")
                }
            }
            .environment(\.timeZone, Tempo.roma)
            .navigationTitle("Obiettivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } } }
            .onAppear {
                guard !caricato else { return }
                caricato = true
                nome = o.nome.t
                target = testoDa(o.target.d)
                versamento = testoDa(o.versamento.d)
            }
        }
    }

    private func scrivi(_ cfg: J, _ campo: String, _ valore: J) {
        if cfg.bloccata.vero { return avviso("Configurazione bloccata.", errore: true) }
        fin("ponte.obiettivo", .str(campo), valore)
    }

    @ViewBuilder
    private func sezioniStato(_ s: J, fondo: J, passo: J, iso: String, o: J, nomeFondo: String) -> some View {
        Section {
            VStack(spacing: 4) {
                cifraGrande(euro(s.saldo, tondo: true))
                Text("di \(euro(s.target, tondo: true)) entro il \(dataBreve(s.data.t))").font(.footnote).foregroundStyle(Color.secondarioLife)
                Text(s.cela.vero ? "ci arrivi · \(euro(s.proiezione, tondo: true)) alla data" : "mancano \(euro(s.gap, tondo: true)) · a questo ritmo arrivi a \(euro(s.proiezione, tondo: true))").font(.footnote).foregroundStyle(s.cela.vero ? Color.successoLife : arancioneAvviso).multilineTextAlignment(.center)
                if !s.cominciato.vero {
                    Text("Il primo versamento è al prossimo stipendio: finora non ce n'erano da fare.").font(.caption).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center)
                } else if s.scarto.d < 0 {
                    Text("Nel frattempo sei indietro di \(euro(-s.scarto.d, tondo: true)) sui versamenti già dovuti.").font(.caption).foregroundStyle(arancioneAvviso).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        Section("Come funziona") {
            Text("È un salvadanaio a parte. Il pocket «\(nomeFondo)» tiene i soldi per «\(s.nome.t)». Non è spendibile e non entra nella quota del giorno.").font(.footnote)
            Text("Ci versi tu, a ogni stipendio: \(euro(s.versamento, tondo: true)) dal Principale al fondo, poi spunti la riga nel «Giorno di paga».").font(.footnote)
            Text("Il resto lo calcola l'app: se sei in linea, quanto avrai alla data, quanto manca.").font(.footnote)
            if passo.tipo.t == "da-fare" {
                RigaFin(titolo: "Il versamento di questo ciclo manca", sotto: "\(euro(passo.imp, tondo: true)) · apri il giorno di paga e spunta il fondo", accento: true, freccia: true) { Fogli.s.apri(.paga(passo.dataStip.t, nil)) }
            }
            RigaFin(titolo: "Versa un extra adesso", sotto: "Un giroconto dal Principale al fondo, fuori dal giorno di paga", accento: true, freccia: true) {
                Fogli.s.apri(.movimento(nil, "giro", ["tipo": "giro", "pocket": "principale", "pocketTo": .str(o.pocket.str ?? "fondo"), "nota": "Versamento al fondo"]))
            }
        }
        if !fondo.isNull {
            Section {
                GraficoFondo(punti: fondo.punti.list, target: fondo.target.d)
            } header: {
                Text("La strada")
            } footer: {
                Text("Linea piena: quello che c'è. Tratteggio: i versamenti programmati. In alto, il traguardo.")
            }
        }
        Section("Dove arriva") {
            LabeledContent("Versamenti rimasti", value: "\(plurale(s.versamenti, "stipendio", "stipendi")) × \(euro(s.versamento, tondo: true)) = \(euro(s.daiVersamenti, tondo: true))")
            LabeledContent("Extra previsti", value: euro(s.daiExtra, tondo: true))
            LabeledContent("Proiezione", value: euro(s.proiezione, tondo: true))
            LabeledContent(s.gap.d > 0 ? "Mancano" : "Avanza", value: euro(abs(s.target.d - s.proiezione.d), tondo: true))
        }
        if s.gap.d > 0, s.inPiu.d > 0 {
            Section {
                LabeledContent("Versare di più", value: "+\(euro(s.inPiu, tondo: true))")
                LabeledContent("Prenderci più tempo", value: "+\(plurale(s.stipendiInPiu, "stipendio", "stipendi"))")
                LabeledContent("Abbassare il traguardo", value: euro(s.proiezione, tondo: true))
            } header: {
                Text("Cosa serve")
            } footer: {
                Text("Tre vie per lo stesso buco. L'app non ne sceglie una: le mette in fila con il loro prezzo.")
            }
        }
        if !fondo.isNull {
            Section("I prossimi versamenti") {
                ForEach(fondo.punti.list.dropFirst().filter { $0.quando.t > iso }.prefix(6), id: \.self) { p in
                    LabeledContent(glma(p.quando.t), value: euro(p.piano, tondo: true))
                }
            }
        }
    }
}

struct FoglioCuscinetto: View {
    var body: some View {
        let c = fin("piano.cuscinetto", Logica.s.chiama("ui.oggiISO"))
        let punti = c.punti.list
        let grafico: [J] = punti.enumerated().map { i, p in ["quando": p.quando, "piano": p.saldo, "reale": i == 0 ? p.saldo : nil] }
        return Foglio(titolo: "Cuscinetto ING") {
            Form {
                Section {
                    VStack(spacing: 4) {
                        cifraGrande(euro(c.saldo))
                        Text("di \(euro(c.target, tondo: true))\(c.regola.vero ? " · \(c.regola.t)" : "")").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                Section {
                    let dopo = punti.first { $0.quando == c.quando && $0.delta.d < 0 }?.nome.t.lowercased() ?? "le uscite"
                    RigaFin(titolo: "Minimo previsto", sotto: "dopo \(dopo) · \(glma(c.quando.t))", valore: euro(c.minimo))
                    RigaFin(titolo: "Sopra target", sotto: "poi non scende più sotto", valore: c.sopraDal.str.map { $0 == punti.first?.quando.t ? "già" : "dal \(glma($0))" } ?? "non nei 12 mesi")
                    if !c.prossimo.isNull { RigaFin(titolo: "Prossimo versamento", sotto: glm(c.prossimo.quando.t), valore: euro(c.prossimo.imp, tondo: true)) }
                    RigaFin(titolo: "A regime", sotto: "la riga «Cuscinetto ING» del budget", valore: "\(euro(c.versamento, tondo: true)) a stipendio")
                }
                if grafico.count > 1 {
                    Section("Dodici mesi") { GraficoFondo(punti: grafico, target: c.target.d) }
                }
                Section {
                    ForEach(punti.dropFirst(), id: \.self) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.nome.t).font(.footnote).lineLimit(1)
                                Text(glma(p.quando.t)).font(.caption2).foregroundStyle(Color.secondarioLife)
                            }
                            Spacer()
                            Text("\(p.delta.d < 0 ? "−" : "+")\(euro(abs(p.delta.d)))").font(.footnote).monospacedDigit().foregroundStyle(p.delta.d < 0 ? Color.pericoloLife : Color.successoLife)
                            Text(euro(p.saldo)).font(.footnote.weight(.medium)).monospacedDigit()
                        }
                        .listRowBackground(p.saldo.d < c.target.d ? arancioneAvviso.opacity(0.07) : Color.cartaLife)
                    }
                } header: {
                    Text("La proiezione")
                } footer: {
                    Text("Versamenti a ogni stipendio, entrate attese su ING, e le uscite che ci passano. Il target è un mese di spese fisse: se cambia il budget delle Fisse, cambia anche lui.")
                }
                if !c.fuori.list.isEmpty {
                    Section {
                        ForEach(c.fuori.list, id: \.self) { x in
                            RigaFin(titolo: x.nome.t, sotto: x.stimato.vero ? "stimata" : nil, valore: euro(x.imp, tondo: true))
                        }
                    } header: {
                        Text("Fuori dalla proiezione")
                    } footer: {
                        Text("Entra nel conto quando arriva, con l'importo vero: contarla prima vorrebbe dire dirsi sopra target con soldi stimati.")
                    }
                }
            }
        }
    }
}

// MARK: Giorno di paga

struct FoglioPaga: View {
    let dataStip: String
    var entrata: Double? = nil
    @ObservedObject private var logica = Logica.s
    @State private var scritti: [String: String] = [:]
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let _ = logica.versione
        let data = J.str(dataStip)
        let t = fin("paga.travasiPaga", data, entrata.map { .num($0) } ?? nil)
        let tred = fin("paga.travasoTredicesima", data)
        let righe = t.righe.list + (tred.isNull ? [] : [tred])
        let fatti = Set(fin("paga.travasiFatti", data).list.map(\.t))
        let restano = righe.filter { !fatti.contains($0.id.t) }.count
        return Foglio(titolo: "Giorno di paga") {
            Pagina {
                VStack(spacing: 4) {
                    Text(glm(dataStip)).font(.footnote).foregroundStyle(Color.secondarioLife)
                    cifraGrande(euro(t.entrate), colore: verdeEntrata)
                    if t.eccezione.vero { Text("importi scritti a mano per questo stipendio").font(.caption).foregroundStyle(Color.secondarioLife) }
                }
                .frame(maxWidth: .infinity)
                Sezione("I travasi") {
                    Carta(padding: 12) {
                        ForEach(righe, id: \.id) { r in riga(r, fatto: fatti.contains(r.id.t)) }
                    }
                }
                Text(restano > 0 ? "Ogni spunta crea il giro. \(plurale(Double(restano), "ne manca", "ne mancano"))." : "Fatti tutti.").font(.caption).foregroundStyle(Color.secondarioLife)
                if !t.eccezione.vero, !t.fisse.dettaglio.list.isEmpty {
                    Sezione("Cosa copre il travaso alle Fisse") {
                        Carta(padding: 12) {
                            ForEach(t.fisse.dettaglio.list, id: \.self) { x in
                                RigaFin(titolo: x.nome.t + (x.quota.vero ? " · quota 1/\(x.su.t)" : ""), sotto: glm(x.quando.t), valore: euro(x.imp))
                            }
                            Divider()
                            RigaFin(titolo: "scadenze \(euro(t.fisse.scadenze, tondo: true)) + quote \(euro(t.fisse.quote, tondo: true)) − saldo \(euro(t.fisse.saldo, tondo: true))", valore: euro(t.fisse.importo))
                        }
                    }
                }
                PulsantePieno(testo: restano > 0 ? "Chiudi, finisco dopo" : "Fatto", colore: restano > 0 ? Color(uiColor: .systemGray) : accentoFinanze) { chiudi() }
            }
        }
    }

    private func riga(_ r: J, fatto: Bool) -> some View {
        let id = r.id.t
        return HStack(spacing: 10) {
            Button { fai(r, fatto: fatto) } label: {
                Image(systemName: fatto ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(fatto ? Color.successoLife : Color.terziarioLife)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.nome.t).font(.subheadline)
                Text("\(r.tipo.t == "resta" ? "resta sul Principale" : "\(nomePocket(r.da.str)) → \(nomePocket(r["a"].str))") · \(r.perche.t)").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            Spacer(minLength: 4)
            if fatto {
                Text(euro(r.imp)).font(.subheadline).monospacedDigit()
            } else {
                HStack(spacing: 3) {
                    TextField("0,00", text: Binding(get: { scritti[id] ?? testoDa(r.imp.d) }, set: { scritti[id] = $0 }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 76, height: 32)
                        .padding(.horizontal, 6)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(r.allarme.vero ? Color.pericoloLife : Color.primary)
                    Text("€").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
            }
        }
        .opacity(fatto ? 0.6 : 1)
    }

    private func spunta(_ id: J, _ on: Bool) { fin("ponte.spuntaPaga", .str(dataStip), id, .bool(on)) }

    private func fai(_ r: J, fatto: Bool) {
        if fatto {
            // Spuntato per sbaglio: si toglie la spunta e il giro che aveva creato
            let giro = fin("dati.movimentiVivi").list
                .filter { $0.data.t == dataStip && $0.tipo == r.tipo && $0.pocket == r.da && $0.pocketTo == r["a"] && $0.nota == r.nota }
                .sorted { $0.ts.d > $1.ts.d }
                .first
            if let giro { fin("dati.eliminaMovimento", giro.id) }
            spunta(r.id, false)
            tocco()
            avviso("\(r.nome.t): spunta tolta\(giro != nil ? ", giro eliminato" : "")")
            return
        }
        let imp = scritti[r.id.t].map { Double(centesimi($0) ?? 0) } ?? r.imp.d
        if imp <= 0 || r.tipo.t == "resta" {
            fin("dati.segnaTravaso", .str(dataStip), r.id)
            spunta(r.id, true)
            tocco()
            return
        }
        var m: J = ["id": .str(nuovoIdLogica("m")), "tipo": r.tipo, "imp": .num(imp), "nota": r.nota, "cat": nil, "sub": nil, "pocket": r.da, "pocketTo": r["a"], "data": .str(dataStip), "rif": nil, "ecc": false]
        if r.tipo.t == "extra" { m["pianificata"] = true }
        fin("dati.salvaMovimento", m)
        fin("dati.segnaTravaso", .str(dataStip), r.id)
        spunta(r.id, true)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        avviso("\(r.nome.t) · \(euro(imp))")
    }
}

// MARK: Stipendio

struct FoglioStipendio: View {
    @State private var testo = ""
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let s = fin("stipendio.stipendioAtteso")
        let imp = centesimi(testo) ?? 0
        let cambiato = imp > 0 && Double(imp) != s.importo.d
        let fra = s.fra.int ?? 0
        let quando = fra == 0 ? "oggi" : fra == 1 ? "domani" : fra < 0 ? (fra == -1 ? "ieri" : "\(-fra) giorni fa") : "fra \(fra) giorni"
        let umana = dataUmana(s.data.t)
        return Foglio(titolo: "Stipendio") {
            Form {
                Section {
                    VStack(spacing: 4) {
                        cifraGrande("+\(euro(imp > 0 ? Double(imp) : s.importo.d))", colore: verdeEntrata)
                        Text("\(umana.maiuscola)\(umana.lowercased() == quando ? "" : " · \(quando)")").font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                Section {
                    CampoEuro(etichetta: "Importo", testo: $testo)
                } footer: {
                    Text("L'importo atteso resta per i prossimi stipendi: cambialo qui quando cambia la busta paga.")
                }
                Section {
                    LabeledContent("Entra su", value: "Principale")
                    LabeledContent("Data prevista", value: umana)
                }
                Section {
                    Button("Aggiungi lo stipendio") {
                        guard imp > 0 else { return avviso("Serve un importo.", errore: true) }
                        let oggi = Logica.s.chiama("ui.oggiISO")
                        // Arrivato in anticipo o in ritardo: la data vera è oggi, ed è da lì che parte il ciclo
                        fin("dati.salvaMovimento", ["id": .str(nuovoIdLogica("m")), "data": oggi, "tipo": "in", "imp": .n(imp), "nota": "Stipendio", "cat": nil, "sub": nil, "pocket": "principale", "ecc": false, "stip": true])
                        if cambiato { fin("ponte.meta", ["config", "importoStipendio"], .n(imp)) }
                        celebra("Stipendio")
                        Fogli.s.apri(.paga(oggi.t, Double(imp)))
                    }
                    .fontWeight(.semibold)
                    if cambiato {
                        Button("Salva solo il nuovo importo") {
                            fin("ponte.meta", ["config", "importoStipendio"], .n(imp))
                            avviso("Importo atteso: \(euro(Double(imp)))")
                        }
                    }
                } footer: {
                    Text("Registra l'entrata di oggi sul Principale, marcata come stipendio (il ciclo parte da qui), e apre i travasi del giorno di paga.")
                }
            }
        }
        .onAppear { if testo.isEmpty { testo = testoDa(s.importo.d) } }
    }
}

// MARK: Ricorrente e previsto

struct FoglioRicorrente: View {
    let genere: String
    let esistente: J?
    @State private var b: J = .null
    @State private var imp = ""
    @State private var minimo = ""
    @State private var massimo = ""
    @Environment(\.dismiss) private var chiudi

    private var previsto: Bool { genere == "previsto" }
    private var entrata: Bool { previsto && b.tipo.t == "in" }
    private var pockets: [J] { fin("dati.stato").pockets.list.filter { !$0.archiviato.vero } }
    private var cadenze: [(String, String)] { [("mensile", "Ogni mese"), ("bimestrale", "Ogni 2 mesi"), ("trimestrale", "Ogni 3 mesi"), ("semestrale", "Ogni 6 mesi"), ("annuale", "Ogni anno")] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(previsto ? "Maxi rata affitto" : "Rata prestito", text: Binding(get: { b.nome.t }, set: { b["nome"] = .str($0) }))
                }
                if previsto {
                    Section {
                        Picker("Tipo", selection: Binding(get: { entrata ? "in" : "out" }, set: { v in
                            b["tipo"] = .str(v)
                            if v == "in", !b.pocket.vero { b["pocket"] = "principale" }
                        })) {
                            Text("Uscita").tag("out")
                            Text("Entrata").tag("in")
                        }
                        .pickerStyle(.segmented)
                        CampoEuro(etichetta: "Importo", testo: $imp)
                        DatePicker(entrata ? "Quando arriva" : "Quando esce", selection: dataBinding("quando"), displayedComponents: .date)
                    }
                } else {
                    Section {
                        Picker("Tipo", selection: Binding(get: { b.tipo.t }, set: { b["tipo"] = .str($0) })) {
                            Text("Certo").tag("fissa")
                            Text("Stimato").tag("variabile")
                        }
                        .pickerStyle(.segmented)
                        if b.tipo.t == "fissa" {
                            CampoEuro(etichetta: "Importo", testo: $imp)
                        } else {
                            CampoEuro(etichetta: "Minimo", testo: $minimo)
                            CampoEuro(etichetta: "Massimo", testo: $massimo)
                        }
                    } header: {
                        Text("Importo")
                    } footer: {
                        if b.tipo.t == "variabile" { Text("Nelle proiezioni vale il massimo: una bolletta sottostimata è esattamente il caso in cui il pocket non basta.") }
                    }
                    Section {
                        Picker("Ogni quanto", selection: Binding(get: { b.cadenza.t }, set: { b["cadenza"] = .str($0) })) {
                            ForEach(cadenze, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Stepper("Giorno del mese: \(b.giorno.int ?? 1)", value: Binding(get: { b.giorno.int ?? 1 }, set: { b["giorno"] = .n($0) }), in: 1...31)
                        Toggle("Ha una prima scadenza", isOn: Binding(get: { b.da.vero }, set: { b["da"] = $0 ? .str(Tempo.oggi()) : nil }))
                        if b.da.vero { DatePicker("Prima scadenza", selection: dataBinding("da"), displayedComponents: .date) }
                        if b.cadenza.t != "mensile", !b.da.vero {
                            Picker("Mese", selection: Binding(get: { b.mese.int ?? 1 }, set: { b["mese"] = .n($0) })) {
                                ForEach(1...12, id: \.self) { Text(Tempo.mesiLunghi[$0 - 1]).tag($0) }
                            }
                        }
                        if b.pagato.vero {
                            HStack {
                                LabeledContent("Ultima saldata", value: dataUmana(b.pagato.t))
                                Button("Annulla") { b["pagato"] = nil }.buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("Ogni quanto")
                    } footer: {
                        Text(b.da.vero ? "Prima della prima scadenza il ricorrente non esiste, e la cadenza conta da lì." : "Senza prima scadenza vale da subito.")
                    }
                }
                Section(entrata ? "Su quale pocket entra" : "Da quale pocket esce") {
                    Picker("Pocket", selection: Binding(get: { b.pocket.t }, set: { b["pocket"] = .str($0) })) {
                        ForEach(pockets, id: \.id) { Text($0.nome.t).tag($0.id.t) }
                    }
                    .labelsHidden()
                }
                if previsto, !entrata, let c = centesimi(imp) {
                    let cop = copertura(c)
                    Section {
                        Text("\(cop.coperto.vero ? "I soldi ci sono" : "Mancano \(euro(cop.manca, tondo: true))") · \(nomePocket(cop.pocket.str)): \(euro(cop.saldo)) disponibili").font(.footnote).foregroundStyle(cop.coperto.vero ? Color.successoLife : Color.pericoloLife)
                    }
                }
                if !entrata {
                    Section("Categoria") {
                        Picker("Categoria", selection: Binding(get: { b.cat.t }, set: { b["cat"] = .str($0) })) {
                            ForEach(fin("dati.stato").cats.list, id: \.id) { Text($0.nome.t).tag($0.id.t) }
                        }
                        .labelsHidden()
                    }
                }
                if previsto {
                    Section { TextField("Nota facoltativa", text: Binding(get: { b.nota.t }, set: { b["nota"] = .str($0) })) }
                } else {
                    Section {
                        Toggle("Attivo", isOn: Binding(get: { b.attivo.vero }, set: { b["attivo"] = .bool($0) }))
                    } footer: {
                        Text("Un ricorrente sospeso resta configurato ma sparisce da «In arrivo».")
                    }
                }
                if esistente != nil {
                    Section {
                        BottoneElimina {
                            fin(previsto ? "dati.eliminaPrevisto" : "dati.eliminaRicorrente", b.id)
                            avviso("Eliminato.")
                            chiudi()
                        }
                    }
                }
            }
            .environment(\.timeZone, Tempo.roma)
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: salva).fontWeight(.semibold) }
            }
        }
        .onAppear(perform: carica)
    }

    private var titolo: String {
        if previsto {
            return entrata ? (esistente != nil ? "Entrata attesa" : "Nuova entrata attesa") : (esistente != nil ? "Pagamento previsto" : "Nuovo pagamento")
        }
        return esistente != nil ? "Ricorrente" : "Nuovo ricorrente"
    }

    private func dataBinding(_ k: String) -> Binding<Date> {
        Binding(get: { Tempo.istante(b[k].str ?? Tempo.oggi(), "12:00") }, set: { b[k] = .str(Tempo.dataRoma($0)) })
    }

    private func copertura(_ c: Int) -> J {
        var x = b
        x["imp"] = .n(c)
        return fin("calcolo.coperturaDi", x)
    }

    private func carica() {
        guard b.isNull else { return }
        if let esistente {
            b = esistente
        } else if previsto {
            b = ["id": .str(nuovoIdLogica("p")), "nome": "", "imp": 0, "quando": Logica.s.chiama("ui.oggiISO"), "pocket": "ing", "cat": "fisse", "nota": "", "pagatoIl": nil]
        } else {
            b = ["id": .str(nuovoIdLogica("r")), "nome": "", "imp": 0, "cat": "fisse", "pocket": "fisse", "tipo": "fissa", "cadenza": "mensile", "giorno": 1, "mese": 1, "da": nil, "pagato": nil, "stimaMin": 0, "stimaMax": 0, "attivo": true]
        }
        imp = testoDa(b.imp.d)
        minimo = testoDa(b.stimaMin.d)
        massimo = testoDa(b.stimaMax.d)
    }

    private func salva() {
        let nome = b.nome.t.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return avviso("Serve un nome.", errore: true) }
        var x = b
        x["nome"] = .str(nome)
        x["imp"] = .n(centesimi(imp) ?? 0)
        x["stimaMin"] = .n(centesimi(minimo) ?? 0)
        x["stimaMax"] = .n(centesimi(massimo) ?? 0)
        if previsto {
            guard centesimi(imp) != nil else { return avviso("Serve un importo.", errore: true) }
            fin("dati.salvaPrevisto", x)
        } else {
            fin("dati.salvaRicorrente", x)
        }
        avviso("Salvato.")
        chiudi()
    }
}

// MARK: Chiusura settimanale

struct FoglioChiusura: View {
    @ObservedObject private var logica = Logica.s
    @State private var passo = 1
    @State private var ric: J = .null
    @State private var errore = ""
    @State private var testoIng = ""
    @State private var fatto = false
    @State private var ricaricato = false
    @State private var scegliFile = false
    @Environment(\.dismiss) private var chiudi

    private let passi = ["Estratto", "Pagella", "Report", "Ricarica"]

    private var ing: J {
        let t = testoIng.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let c = centesimi(t) else { return nil }
        return .n(c)
    }

    var body: some View {
        let _ = logica.versione
        let iso = Logica.s.chiama("ui.oggiISO")
        let sett = fin("chiusura.settimanaDi", iso)
        let p = fin("chiusura.pagella", iso)
        let piano = fin("travasi.pianoTravasi", iso)
        return Foglio(titolo: "Chiudi la settimana") {
            Pagina {
                HStack(spacing: 6) {
                    ForEach(passi.indices, id: \.self) { i in
                        Button { passo = i + 1 } label: {
                            VStack(spacing: 3) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(passo >= i + 1 ? Color.white : Color.secondarioLife)
                                    .background(passo == i + 1 ? accentoFinanze : passo > i + 1 ? Color.successoLife : Color(uiColor: .tertiarySystemFill), in: Circle())
                                Text(passi[i]).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("\(gm(sett.da.t)) → \(gm(sett["a"].t))").font(.caption).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity)
                switch passo {
                case 1: estratto(iso)
                case 2: pagella(p)
                case 3: reportVista(iso)
                default: ricarica(piano, iso, sett)
                }
            }
        }
        .fileImporter(isPresented: $scegliFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text], onCompletion: carica)
    }

    @ViewBuilder
    private func estratto(_ iso: J) -> some View {
        if ric.isNull {
            Sezione("Carica il CSV") {
                Carta {
                    Button { scegliFile = true } label: { Label("Scegli il file", systemImage: "square.and.arrow.down") }.tint(accentoFinanze)
                }
            }
            Text("Dall'app Revolut: Conto → estratto conto → Excel. L'app mostra solo le differenze; i saldi dei pocket li riancora da sé.").font(.caption).foregroundStyle(Color.secondarioLife)
            if !errore.isEmpty { Text(errore).font(.footnote).foregroundStyle(Color.pericoloLife) }
        } else {
            if ric.zero.vero {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Color.successoLife)
                    Text("Zero differenze").font(.headline)
                    Text("\(ric.abbinati.list.count) movimenti abbinati · \(gm(ric.periodo.da.t)) → \(gm(ric.periodo["a"].t))").font(.footnote).foregroundStyle(Color.secondarioLife)
                }
                .frame(maxWidth: .infinity)
            }
            if !ric.nuovi.list.isEmpty {
                Sezione("Nell'estratto e non nell'app") {
                    Carta(padding: 12) {
                        ForEach(Array(ric.nuovi.list.enumerated()), id: \.offset) { i, r in rigaNuova(i, r) }
                    }
                }
            }
            if !ric.correzioni.list.isEmpty {
                Sezione("Importi da correggere") {
                    Carta(padding: 12) {
                        ForEach(ric.correzioni.list, id: \.self) { c in
                            RigaFin(titolo: c.mov.nota.str ?? "—", sotto: gm(c.mov.data.t), valore: "\(euro(c.mov.imp)) → \(euro(c.riga.imp))")
                        }
                    }
                }
            }
            if !ric.mancanti.list.isEmpty {
                Sezione("Nell'app e non nell'estratto") {
                    Carta(padding: 12) {
                        ForEach(ric.mancanti.list, id: \.self) { m in
                            RigaFin(titolo: m.nota.str ?? "—", sotto: "\(gm(m.data.t)) · \(nomePocket(m.pocket.str))", valore: euro(m.imp))
                        }
                    }
                }
            }
            Sezione("Saldi dall'estratto") {
                Carta(padding: 12) {
                    ForEach(ric.disponibili.dict.sorted { $0.key < $1.key }, id: \.key) { k, v in
                        RigaFin(titolo: nomePocket(k), sotto: ric.saldi[k] != v ? "completato \(euro(ric.saldi[k]))" : nil, valore: euro(v))
                    }
                    CampoEuro(etichetta: "Saldo ING oggi", testo: $testoIng)
                }
            }
            PulsantePieno(testo: ric.zero.vero ? "Riancora e continua" : "Applica \(ric.nuovi.list.filter(\.inc.vero).count + ric.correzioni.list.count) modifiche", colore: accentoFinanze) {
                let e = fin("chiusura.applicaEstratto", ric, ["saldoIng": ing, "iso": iso])
                avviso("\(e.aggiunti.int ?? 0) aggiunti, \(e.corretti.int ?? 0) corretti. Saldi riancorati.")
                passo = 2
            }
        }
        Button("Salta, l'estratto lo carico dopo") { passo = 2 }.frame(maxWidth: .infinity).font(.subheadline)
    }

    private func rigaNuova(_ i: Int, _ r: J) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Includi", isOn: Binding(get: { r.inc.vero }, set: { cambia(i, "inc", .bool($0)) })).labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(r.nota.t).font(.subheadline)
                Text("\(gm(r.data.t)) · \(nomePocket(r.pocket.str))\(r.pocketTo.vero ? " → \(nomePocket(r.pocketTo.str))" : "")\(r.pending.vero ? " · in sospeso" : "")\(r.auto.vero ? " · auto\(r.sub.vero ? ": \(r.sub.t)" : "")" : "")").font(.caption).foregroundStyle(Color.secondarioLife)
                if r.tipo.t == "out" {
                    Picker("Categoria", selection: Binding(get: { r.cat.t }, set: { v in
                        cambia(i, "cat", v.isEmpty ? nil : .str(v))
                        cambia(i, "sub", nil)
                    })) {
                        Text("— categoria —").tag("")
                        ForEach(fin("dati.stato").cats.list, id: \.id) { Text($0.nome.t).tag($0.id.t) }
                    }
                    .labelsHidden()
                }
            }
            Spacer(minLength: 2)
            Text("\(r.tipo.t == "out" || r.tipo.t == "extra" ? "−" : r.tipo.t == "giro" ? "" : "+")\(euro(r.imp))").font(.footnote).monospacedDigit()
        }
    }

    private func cambia(_ i: Int, _ k: String, _ v: J) {
        var l = ric.nuovi.list
        guard l.indices.contains(i) else { return }
        l[i][k] = v
        ric["nuovi"] = .arr(l)
    }

    private func carica(_ esito: Result<URL, Error>) {
        errore = ""
        do {
            let url = try esito.get()
            let accesso = url.startAccessingSecurityScopedResource()
            defer { if accesso { url.stopAccessingSecurityScopedResource() } }
            let testo = try String(contentsOf: url, encoding: .utf8)
            let e = fin("revolut.leggiEstratto", .str(testo))
            guard !e.righe.list.isEmpty else {
                errore = "Nessuna riga riconosciuta. È il CSV dell'estratto conto?"
                return
            }
            ric = fin("revolut.riconcilia", e)
        } catch {
            errore = error.localizedDescription
        }
    }

    @ViewBuilder
    private func pagella(_ p: J) -> some View {
        Sezione("Come è andata") {
            Carta(padding: 12) {
                RigaFin(titolo: "Vita", valore: "\(euro(p.vita.speso)) / \(euro(p.vita.budget))", coloreValore: p.vita.speso.d > p.vita.budget.d ? .pericoloLife : nil)
                RigaFin(titolo: "Fuori piano", valore: "\(p.fuoriPiano.n.int ?? 0)\(p.fuoriPiano.n.vero ? " · \(euro(p.fuoriPiano.totale))" : "")", coloreValore: p.fuoriPiano.n.vero ? .pericoloLife : .successoLife)
                RigaFin(titolo: "Ricariche ING", valore: "\(p.ricariche.n.int ?? 0)\(p.ricariche.n.vero ? " · \(euro(p.ricariche.totale))" : "")", coloreValore: p.ricariche.n.vero ? .pericoloLife : .successoLife)
                if !p.fondo.isNull {
                    RigaFin(titolo: "Fondo", valore: p.fondo.inLinea.vero ? "in linea" : "indietro di \(euro(-p.fondo.scarto.d))", coloreValore: p.fondo.inLinea.vero ? .successoLife : .pericoloLife)
                }
            }
        }
        if !p.fuoriPiano.voci.list.isEmpty {
            Sezione("Le uscite fuori piano di questa settimana") {
                Carta(padding: 12) {
                    ForEach(p.fuoriPiano.voci.list, id: \.id) { m in
                        RigaFin(titolo: m.nota.str ?? "—", sotto: gm(m.data.t), valore: euro(fin("calcolo.importoEffettivo", m)))
                    }
                }
            }
        }
        PulsantePieno(testo: "Avanti", colore: accentoFinanze) { passo = 3 }
    }

    @ViewBuilder
    private func reportVista(_ iso: J) -> some View {
        let r = fin("chiusura.report", iso).t
        Sezione("Report") {
            Carta {
                Text(r).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
        Text("Una dozzina di righe da incollare. Contiene anche le modifiche alla configurazione: un report che non le contiene si può fabbricare.").font(.caption).foregroundStyle(Color.secondarioLife)
        Button {
            UIPasteboard.general.string = r
            avviso("Report copiato.")
        } label: { Label("Copia report", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
        PulsantePieno(testo: "Avanti", colore: accentoFinanze) { passo = 4 }
    }

    @ViewBuilder
    private func ricarica(_ piano: J, _ iso: J, _ sett: J) -> some View {
        Sezione("I travasi della settimana") {
            if ricaricato {
                Text("Travasi registrati.").font(.footnote).foregroundStyle(Color.secondarioLife)
            } else {
                VistaPianoTravasi(piano: piano) { ricaricato = true }
            }
        }
        if fatto {
            VStack(spacing: 2) {
                Text("\(fin("dati.serieChiusure", sett.domenica).int ?? 0)").font(.system(size: 44, weight: .semibold)).foregroundStyle(accentoFinanze)
                Text("settimane chiuse di fila").font(.footnote).foregroundStyle(Color.secondarioLife)
            }
            .frame(maxWidth: .infinity)
            PulsantePieno(testo: "Chiudi", colore: accentoFinanze) { chiudi() }
        } else {
            PulsantePieno(testo: "Chiudi la settimana", colore: accentoFinanze) {
                fin("chiusura.chiudi", iso, ing)
                fatto = true
                avviso("Settimana chiusa.")
            }
        }
    }
}

// MARK: - Altro (impostazioni)

struct ImpostazioniFinanze: View {
    @State private var motivo = ""
    @State private var righe: [J] = []
    @State private var testoImport = ""
    @State private var scegliFile = false
    @State private var dimentica = false
    @State private var budgetAperto: String?
    private var f: Fogli { .s }

    var body: some View {
        let mese = fin("calcolo.meseDi")
        let s = fin("dati.stato")
        let iso = Logica.s.chiama("ui.oggiISO")
        let c = fin("calcolo.cicloDi", iso)
        let p = fin("dati.profiloDi", mese)
        let chiave = fin("dati.chiaveProfilo", mese).t
        let q = fin("calcolo.quadratura", mese)
        let soglie = fin("dati.SOGLIE_PREDEFINITE").dict.merging(s.soglie.dict) { $1 }
        let giorno = s.config.giornoStipendio.int ?? 23
        let ric = s.config.ricarica.isNull ? (["giorno": 1, "ora": "08:00"] as J) : s.config.ricarica
        let pk = fin("calcolo.pocketConSaldi").list
        let ricorrenti = fin("dati.ricorrentiVivi").list
        let prev = (fin("dati.previsti").list + fin("dati.entratePreviste").list).sorted { $0.quando.t < $1.quando.t }
        let regole = s.rules.dict.count
        let ultimo = fin("calcolo.ultimoStipendio", iso)
        let prossimo = fin("calcolo.prossimoStipendio", iso)
        let cfg = fin("dati.statoConfig", ultimo)
        let obi = fin("piano.statoObiettivo", iso)
        let cus = fin("piano.cuscinetto", iso)
        let vita = fin("piano.budgetVita").d
        let quotaPiano = (vita / max(1, c.giorni.d)).rounded()
        let ing = fin("piano.ingPrevisto", iso)
        let sblocchi = s.config.sblocchi.list.filter { $0.ciclo == c.indice }.count
        let daImportare = righe.filter { $0.inc.vero && !$0.doppione.vero }.count
        let protetto: (@escaping () -> Void) -> Void = { fn in
            if cfg.bloccata.vero {
                avviso("Configurazione bloccata. Sbloccala con un motivo.", errore: true)
            } else {
                fn()
            }
        }

        return VStack(alignment: .leading, spacing: 16) {
            Sezione("Configurazione", coda: { Text(cfg.bloccata.vero ? "bloccata" : cfg.perche.t == "finestra" ? "libera" : "sbloccata").foregroundStyle(cfg.bloccata.vero ? Color.pericoloLife : Color.successoLife) }) {
                Carta(padding: 12) {
                    RigaFin(titolo: "Ultimo stipendio", sotto: "il prossimo il \(dataBreve(prossimo.t))", valore: dataBreve(ultimo.t))
                    if cfg.bloccata.vero {
                        HStack {
                            TextField("Perché la stai cambiando?", text: $motivo)
                            Button("Sblocca") {
                                if fin("dati.sbloccaConfig", .str(motivo), c.indice).vero {
                                    motivo = ""
                                    avviso("Sbloccata per un'ora.")
                                }
                            }
                            .disabled(motivo.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else if cfg.perche.t == "sblocco" {
                        Text("Sbloccata. Si richiude da sé.").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                    if sblocchi > 0 { RigaFin(titolo: "Sblocchi in questo ciclo", valore: "\(sblocchi)") }
                }
            }
            Text("Budget, soglie, obiettivo e categorie si cambiano liberamente nelle \(fin("dati.ORE_LIBERE").int ?? 48) ore dopo lo stipendio. Fuori da quella finestra serve un motivo, e il motivo finisce nel report settimanale.").font(.caption).foregroundStyle(Color.secondarioLife)

            Sezione("Obiettivo") {
                Carta(padding: 12) {
                    if !cus.isNull {
                        RigaFin(titolo: cus.nome.t, sotto: "target \(euro(cus.target, tondo: true))", valore: "\(Int((cus.frazione.d * 100).rounded()))%", freccia: true) { f.apri(.obiettivo) }
                        RigaFin(titolo: "Versamento per stipendio", valore: euro(cus.versamento, tondo: true))
                    } else if !obi.isNull {
                        RigaFin(titolo: obi.nome.t, sotto: "\(euro(obi.saldo, tondo: true)) di \(euro(obi.target, tondo: true)) entro il \(dataBreve(obi.data.t))", valore: obi.inLinea.vero ? "in linea" : "-\(euro(-obi.scarto.d, tondo: true))", freccia: true) { f.apri(.obiettivo) }
                        RigaFin(titolo: "Versamento per stipendio", valore: euro(obi.versamento, tondo: true))
                        RigaFin(titolo: "Proiezione alla data", sotto: obi.gap.d > 0 ? "mancano \(euro(obi.gap, tondo: true))" : "arriva", valore: euro(obi.proiezione, tondo: true))
                    } else {
                        RigaFin(titolo: "Nessun obiettivo", accento: true, freccia: true) { f.apri(.obiettivo) }
                    }
                }
            }

            Sezione("Budget · profilo \(p.nome.t)") {
                Carta(padding: 12) {
                    ForEach(s.cats.list.filter { $0.id.t != "acc" && $0.id.t != "risp" }, id: \.id) { cat in
                        let id = cat.id.t
                        let attiva = p.cassaCats.list.contains(cat.id)
                        HStack(spacing: 8) {
                            Circle().fill(coloreCat(id)).frame(width: 10, height: 10)
                            Text(cat.nome.t).font(.subheadline)
                            Spacer()
                            Button("vita") { protetto { fin("ponte.alternaVita", .str(chiave), cat.id) } }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .tint(attiva ? accentoFinanze : .secondary)
                            CampoNumero(valore: p["b"][id].d, unita: "€") { n in protetto { fin("ponte.profili", ["profili", .str(chiave), "b", .str(id)], .num(max(0, n))) } }
                        }
                    }
                    HStack {
                        Circle().fill(accentoFinanze).frame(width: 10, height: 10)
                        Text("Cuscinetto ING").font(.subheadline)
                        Spacer()
                        CampoNumero(valore: p["b"].ing.d, unita: "€") { n in protetto { fin("ponte.profili", ["profili", .str(chiave), "b", "ing"], .num(max(0, n))) } }
                    }
                    HStack {
                        Text("Entrate mensili attese").font(.subheadline)
                        Spacer()
                        CampoNumero(valore: s.config.entrate.d, unita: "€") { n in protetto { fin("ponte.meta", ["config", "entrate"], .num(max(0, n))) } }
                    }
                    RigaFin(titolo: "Vita", sotto: "le categorie marcate · quota di piano \(euro(quotaPiano))/g", valore: euro(vita, tondo: true))
                    let diff = q.differenza.d
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(diff < 0 ? "Sfori le entrate di" : "Ti resta") \(Int(abs(diff))) €").font(.subheadline.weight(.medium)).foregroundStyle(diff < 0 ? Color.pericoloLife : Color.primary)
                        Text(diff < 0 ? "Il budget non quadra: taglia qualche voce finché non rientri." : diff == 0 ? "Budget allocato al centesimo." : "Margine non allocato: puoi destinarlo al cuscinetto.").font(.caption).foregroundStyle(Color.secondarioLife)
                    }
                }
            }

            Sezione("Il ciclo dello stipendio") {
                Carta(padding: 12) {
                    Stepper("Giorno dello stipendio: \(giorno)", value: Binding(get: { giorno }, set: { n in protetto { fin("ponte.meta", ["config", "giornoStipendio"], .n(min(28, max(1, n)))) } }), in: 1...28).font(.subheadline)
                    RigaFin(titolo: "Prossimo stipendio", valore: dataBreve(prossimo.t))
                    RigaFin(titolo: "Ciclo in corso", valore: fin("calcolo.nomeCiclo", c).t)
                }
            }

            Sezione("La ricarica settimanale") {
                Carta(padding: 12) {
                    Picker("Giorno", selection: Binding(get: { ric.giorno.int ?? 1 }, set: { fin("ponte.meta", ["config", "ricarica", "giorno"], .n($0)) })) {
                        ForEach([(1, "Lun"), (2, "Mar"), (3, "Mer"), (4, "Gio"), (5, "Ven"), (6, "Sab"), (0, "Dom")], id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("08:00", text: Binding(get: { ric.ora.str ?? "08:00" }, set: { v in
                        if v.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil { fin("ponte.meta", ["config", "ricarica", "ora"], .str(v)) }
                    }))
                    .keyboardType(.numbersAndPunctuation)
                    PulsantePieno(testo: "Ricarica adesso", colore: accentoFinanze) { f.apri(.ricarica("ricaricaSett")) }
                    Button("Ricarica fuori ciclo") { f.apri(.ricarica("ricarica")) }.font(.subheadline)
                    Button("Saldo ING") { f.apri(.ricarica("saldoING")) }.font(.subheadline)
                }
            }

            Sezione("I pocket") {
                Carta(padding: 12) {
                    ForEach(pk, id: \.id) { x in
                        RigaFin(titolo: x.nome.t, sotto: fin("dati.TIPI_POCKET")[x.tipo.t].nome.t + (x.external.vero ? " · saldo a mano" : ""), valore: euro(x.saldoVero))
                    }
                    RigaFin(titolo: "Correggi i saldi", accento: true) { f.apri(.pocket) }
                }
            }

            Sezione("Uscite ricorrenti") {
                Carta(padding: 12) {
                    ForEach(ricorrenti, id: \.id) { r in
                        RigaFin(titolo: r.nome.t, sotto: "\(etichettaCadenza(r)) · \(nomePocket(r.pocket.str))\(r.attivo.vero ? "" : " · sospeso")", valore: r.tipo.t == "variabile" ? "\(euro(r.stimaMin, tondo: true))–\(euro(r.stimaMax, tondo: true))" : euro(r.imp, tondo: true), freccia: true) {
                            f.apri(.ricorrente("ricorrente", r))
                        }
                    }
                    RigaFin(titolo: "Aggiungi un ricorrente", accento: true) { f.apri(.ricorrente("ricorrente", nil)) }
                }
            }

            Sezione("Pagamenti previsti") {
                Carta(padding: 12) {
                    ForEach(prev, id: \.id) { x in
                        if x.tipo.t == "in" {
                            RigaFin(titolo: x.nome.t, sotto: "\(dataBreve(x.quando.t)) · su \(nomePocket(x.pocket.str)) · entrata", valore: "+\(euro(x.imp))", freccia: true) { f.apri(.ricorrente("previsto", x)) }
                        } else {
                            let cop = fin("calcolo.coperturaDi", x)
                            RigaFin(titolo: x.nome.t, sotto: "\(dataBreve(x.quando.t)) · \(nomePocket(x.pocket.str))\(cop.coperto.vero ? "" : " · mancano \(euro(cop.manca, tondo: true))")", valore: euro(x.imp, tondo: true), freccia: true) { f.apri(.ricorrente("previsto", x)) }
                        }
                    }
                    RigaFin(titolo: "Aggiungi un pagamento previsto", accento: true) { f.apri(.previsto) }
                }
            }

            Sezione("Soglie") {
                Carta(padding: 12) {
                    rigaSoglia("Fuori piano, sopra", soglie["fuoriPiano"]?.d ?? 0, "fuoriPiano", protetto)
                    rigaSoglia("Quota minima accettabile", soglie["quotaMinima"]?.d ?? 0, "quotaMinima", protetto)
                    rigaSoglia("ING, minimo sotto cui avvisare", soglie["ingPrevistoMin"]?.d ?? 0, "ingPrevistoMin", protetto)
                    RigaFin(titolo: "Minimo previsto adesso", sotto: ing.quando.t, valore: euro(ing.minimo, tondo: true))
                    Text("Avviso di categoria, a che punto del budget").font(.caption).foregroundStyle(Color.secondarioLife)
                    Picker("Avviso", selection: Binding(get: { soglie["catAvviso"]?.d ?? 0.85 }, set: { v in protetto { fin("ponte.soglia", "catAvviso", .num(v)) } })) {
                        Text("75%").tag(0.75)
                        Text("85%").tag(0.85)
                        Text("95%").tag(0.95)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Sezione("Chiusura settimanale") {
                Carta(padding: 12) {
                    RigaFin(titolo: "Chiudi la settimana", accento: true, freccia: true) { f.apri(.chiusura) }
                }
            }

            Sezione("Import dell'estratto conto") {
                Carta(padding: 12) {
                    Button { scegliFile = true } label: { Label("Carica un CSV", systemImage: "square.and.arrow.down") }.tint(accentoFinanze)
                    TextField("…oppure incolla qui le righe", text: $testoImport, axis: .vertical).lineLimit(3...8)
                    Button("Analizza il testo") { righe = fin("importa.preparaImport", .str(testoImport)).list }.disabled(testoImport.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text("CSV Revolut, CSV italiani col punto e virgola, oppure righe incollate tipo «27/07 Barbiere 15,00». I doppioni si riconoscono e si scartano; la categoria si assegna dalle note.").font(.caption).foregroundStyle(Color.secondarioLife)
            if !righe.isEmpty {
                Sezione("\(righe.count) righe") {
                    Carta(padding: 12) {
                        ForEach(righe.indices, id: \.self) { i in rigaImport(i, s) }
                    }
                }
                PulsantePieno(testo: daImportare > 0 ? "Importa \(daImportare) movimenti" : "Nessuna riga selezionata", colore: accentoFinanze) {
                    let q = fin("importa.eseguiImport", .arr(righe)).quante.int ?? 0
                    righe = []
                    testoImport = ""
                    avviso(q > 0 ? "\(q) movimenti importati." : "Niente da importare.")
                }
                .disabled(daImportare == 0)
            }

            Sezione("Autocategorizzazione") {
                Carta(padding: 12) {
                    Text("\(regole) corrispondenze apprese dalle tue correzioni.").font(.footnote).foregroundStyle(Color.secondarioLife)
                    Button(dimentica ? "Tocca di nuovo per dimenticare" : "Dimentica tutto", role: .destructive) {
                        if dimentica {
                            fin("ponte.dimenticaRegole")
                            avviso("Regole dimenticate.")
                        }
                        dimentica.toggle()
                    }
                }
            }

            Sezione("Esporta per l'analisi") {
                Carta(padding: 12) {
                    Text("Tutto in un JSON: movimenti, categorie, ricorrenti, saldi, budget e totali. Contiene tutte le tue spese: dallo a un modello solo se ti sta bene che le legga.").font(.footnote).foregroundStyle(Color.secondarioLife)
                    Button("Copia negli appunti") {
                        Task { @MainActor in
                            let n = await Logica.s.chiamaAsync("finanze.esporta.copiaAnalisi").d
                            avviso("Copiato · \(Int(n / 1024)) KB")
                        }
                    }
                    .tint(accentoFinanze)
                }
            }
        }
        .fileImporter(isPresented: $scegliFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { esito in
            guard let url = try? esito.get() else { return }
            let accesso = url.startAccessingSecurityScopedResource()
            defer { if accesso { url.stopAccessingSecurityScopedResource() } }
            if let testo = try? String(contentsOf: url, encoding: .utf8) { righe = fin("importa.preparaImport", .str(testo)).list }
        }
    }

    private func rigaSoglia(_ t: String, _ v: Double, _ k: String, _ protetto: @escaping (@escaping () -> Void) -> Void) -> some View {
        HStack {
            Text(t).font(.subheadline)
            Spacer()
            CampoNumero(valore: v / 100, unita: "€", decimali: true) { n in protetto { fin("ponte.soglia", .str(k), .num((n * 100).rounded())) } }
        }
    }

    private func rigaImport(_ i: Int, _ s: J) -> some View {
        let r = righe[i]
        let badge = ["out": "uscita", "in": "entrata", "extra": "sforamento", "reso": "reso", "giro": "giroconto", "rimb": "rimborso"]
        return HStack(alignment: .top, spacing: 8) {
            Toggle("Includi", isOn: Binding(get: { r.inc.vero && !r.doppione.vero }, set: { righe[i]["inc"] = .bool($0) })).labelsHidden().disabled(r.doppione.vero)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.nota.t).font(.subheadline)
                Text("\(r.data.t) · \(badge[r.tipo.t] ?? r.tipo.t)\(r.doppione.vero ? " · già presente" : r.auto.vero ? " · auto\(r.sub.vero ? ": \(r.sub.t)" : "")" : "")").font(.caption).foregroundStyle(Color.secondarioLife)
                if r.tipo.t == "out", !r.doppione.vero {
                    Picker("Categoria", selection: Binding(get: { r.cat.t }, set: { v in
                        righe[i]["cat"] = v.isEmpty ? nil : .str(v)
                        righe[i]["sub"] = nil
                    })) {
                        Text("— categoria —").tag("")
                        ForEach(s.cats.list, id: \.id) { Text($0.nome.t).tag($0.id.t) }
                    }
                    .labelsHidden()
                }
            }
            Spacer(minLength: 2)
            Text("\(r.tipo.t == "in" ? "+" : r.tipo.t == "giro" ? "" : "−")\(euro(r.imp))").font(.footnote).monospacedDigit()
        }
        .opacity(r.doppione.vero ? 0.5 : 1)
    }
}

/// Un numero modificabile in riga: si salva quando il campo perde il fuoco.
struct CampoNumero: View {
    let valore: Double
    var unita = ""
    var decimali = false
    let salva: (Double) -> Void
    @State private var testo = ""
    @FocusState private var fuoco: Bool

    private var formattato: String {
        decimali ? String(format: "%.2f", valore).replacingOccurrences(of: ".", with: ",") : String(Int(valore))
    }

    var body: some View {
        HStack(spacing: 3) {
            TextField("0", text: $testo)
                .keyboardType(decimali ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: decimali ? 70 : 56)
                .focused($fuoco)
                .onAppear { testo = formattato }
                .onChange(of: valore) { _, _ in if !fuoco { testo = formattato } }
                .onChange(of: fuoco) { _, f in
                    if !f, testo != formattato, let n = Double(testo.replacingOccurrences(of: ",", with: ".")) { salva(n) }
                }
            if !unita.isEmpty { Text(unita).font(.footnote).foregroundStyle(Color.secondarioLife) }
        }
    }
}
