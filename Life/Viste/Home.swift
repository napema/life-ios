import SwiftUI

/// La scheda «Oggi» di Life: adesso, la giornata e un colpo d'occhio su ogni mini-app.
struct Home: View {
    private func apriModulo(_ m: Modulo) { Instradatore.s.apri(m) }
    private func cambiaScheda(_ s: String) { Instradatore.s.apri(s == "calendario" ? .calendario : .todo) }
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var logica = Logica.s
    @State private var ora = Date()
    @State private var taskAperto: TaskAperto?

    private struct VoceAgenda: Identifiable {
        let id: String
        let quando: Int
        let etichetta: String
        let fine: String?
        let nome: String
        let sotto: String?
        let colore: Color
        let fatta: Bool
        let apre: () -> Void
    }

    private func min(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").map { Int($0) ?? 0 }
        return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
    }

    var body: some View {
        let _ = archivio.versione
        let _ = logica.versione
        let oggi = Tempo.oggi()
        let tasks = Azioni.tasks.filter { Azioni.inOggi($0, oggi) }
        let (da, a) = Tempo.intervallo(oggi)
        let eventi = Azioni.eventi(da: da, a: a)
        let sorgenti = Azioni.sorgenti
        let carte = logica.chiama("home.oggi")
        let q = logica.chiama("home.quadro")
        let oraMin = min(Tempo.oraRoma(ora))
        let adessoIso = Tempo.iso(ora)
        let fasce: [String: (Int, String)] = ["mattina": (7, "mattina"), "pomeriggio": (13, "pom."), "preWorkout": (17, "pre"), "sera": (20, "sera"), "qualsiasi": (23, "")]

        var agenda: [VoceAgenda] = eventi.map { e in
            let l = e.own_event_id.isNull ? Lezione.di(e) : nil
            let inizio = Tempo.oraRoma(e.start_at.str) ?? "00:00"
            let fine = Tempo.oraRoma(e.end_at.str) ?? "00:00"
            let orario = e.all_day.vero ? "Tutto il giorno" : "\(inizio) – \(fine)"
            return VoceAgenda(id: "e:\(e.id.t)", quando: e.all_day.vero ? -1 : min(inizio), etichetta: e.all_day.vero ? "tutto" : inizio, fine: e.all_day.vero ? nil : fine, nome: l?.titolo ?? (e.summary.t.isEmpty ? "(senza titolo)" : e.summary.t), sotto: [orario, l?.dove ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), colore: .life(sorgenti.first { $0.id == e.subscription_id.t }?.colore), fatta: !e.all_day.vero && e.end_at.t < adessoIso) { cambiaScheda("calendario") }
        }
        agenda += tasks.filter { $0.due_has_time.vero && !$0.due_at.isNull }.map { t in
            let o = Azioni.ora(t) ?? "00:00"
            return VoceAgenda(id: "t:\(t.id.t)", quando: min(o), etichetta: o, fine: nil, nome: t.title.t.isEmpty ? "Senza titolo" : t.title.t, sotto: "Task", colore: .successoLife, fatta: false) { cambiaScheda("oggi") }
        }
        for v in q.giornata.list where v.chiave.t != "oggi:lavoro" {
            if v.modulo.t == "allenamenti", eventi.contains(where: { $0.summary.t.trimmingCharacters(in: .whitespaces).lowercased() == v.nome.t.trimmingCharacters(in: .whitespaces).lowercased() }) { continue }
            let m = Modulo.di(v.modulo.t)
            let f = fasce[v.fascia.str ?? "qualsiasi"]
            agenda.append(VoceAgenda(id: "m:\(v.chiave.t)", quando: v.ora.str.map(min) ?? (f?.0 ?? 23) * 60, etichetta: v.ora.str ?? f?.1 ?? "", fine: nil, nome: v.nome.t, sotto: v.dentro.str, colore: Color(hex: m?.colore ?? "#8E8E93"), fatta: v.fatta.vero || v.saltata.vero) {
                if let m { apriModulo(m) }
            })
        }
        agenda.sort { $0.quando < $1.quando }
        let passate = agenda.filter(\.fatta).count
        let restano = agenda.filter { !$0.fatta }
        let prossima = agenda.first { !$0.fatta && ($0.fine.map(min) ?? $0.quando) >= oraMin }

        let fin = carte.finanze
        let abi = carte.abitudini
        let tra = carte.allenamenti
        let mob = carte.mobilita
        let rnk = carte.rank
        let gettoni = (abi.gettoni.isNull ? abi.giornata : abi.gettoni).list.sorted { ($0.ora.str ?? "99") < ($1.ora.str ?? "99") }
        let fatteAbi = gettoni.filter { $0.fatta.vero || $0.saltata.vero }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                adesso(q, prossima, oraMin)

                widgetAgenda(restano, passate: passate, totale: agenda.count)

                if !fin.isNull { widgetFinanze(fin, allarme: q.allarme.str) }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    if !abi.isNull { widgetAbitudini(gettoni, fatte: fatteAbi) }
                    widgetPasti(oggi, oraMin)
                    if !tra.isNull { widgetSemplice("allenamenti", valore: tra.valore.t, sotto: tra.dettaglio.t) }
                    if !mob.isNull { widgetSemplice("mobilita", valore: mob.valore.t, sotto: mob.dettaglio.t, colore: mob.fatto.vero ? .successoLife : nil) }
                    if !rnk.isNull { widgetSemplice("rank", valore: rnk.valore.t, sotto: [rnk.prova.t, rnk.dettaglio.t].filter { !$0.isEmpty }.joined(separator: " · "), colore: rnk.urgente.vero ? .pericoloLife : nil) }
                }

                widgetTodo(tasks)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.sfondoLife)
        .navigationTitle(logica.chiama("home.saluto", .n(Calendar.current.component(.hour, from: ora))).t)
        .navigationSubtitle(dataLunga(oggi))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { BottoneImpostazioni() }
        .sheet(item: $taskAperto) { a in SchedaTask(idTask: a.task.id.t) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { ora = $0 }
    }

    private func dataLunga(_ g: String) -> String {
        let (_, m, d) = Tempo.parti(g)
        return "\(Tempo.settimanaLunga[Tempo.giornoSettimana(g)].maiuscola) \(d) \(Tempo.mesiLunghi[m - 1].lowercased())"
    }

    // MARK: Adesso

    @ViewBuilder
    private func adesso(_ q: J, _ prossima: VoceAgenda?, _ oraMin: Int) -> some View {
        if let v = q.prio.list.first {
            let tardi = v.quando.str == "tardi"
            let m = Modulo.di(v.modulo.t)
            HStack(spacing: 12) {
                Capsule().fill(Color(hex: m?.colore ?? "#0A84FF")).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tardi ? "IN RITARDO" : "ADESSO").font(.caption2.weight(.semibold)).foregroundStyle(tardi ? Color.pericoloLife : Color.secondarioLife)
                    Text(v.nome.t).font(.title3.weight(.semibold))
                    let s = [v.dentro.str, v.nomeFascia.str].compactMap { $0 }.joined(separator: " · ")
                    if !s.isEmpty { Text(s).font(.footnote).foregroundStyle(Color.secondarioLife) }
                }
                Spacer()
                if v.habitId.vero {
                    Button("Fatto") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        logica.chiama("home.fai", v)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                } else if v.apre.vero, let m {
                    Button(v.apre.t.contains("/inizia") ? "Avvia" : "Apri") { apriModulo(m) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(14)
            .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if let p = prossima, !p.etichetta.isEmpty, p.etichetta.contains(":") {
            let fra = p.quando - oraMin
            if fra > -60, fra < 180 {
                HStack(spacing: 12) {
                    Capsule().fill(p.colore).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((fra <= 0 ? "Adesso" : fra < 60 ? "Tra \(fra) min" : "Alle \(p.etichetta)").uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                        Text(p.nome).font(.title3.weight(.semibold))
                        if let s = p.sotto { Text(s).font(.footnote).foregroundStyle(Color.secondarioLife) }
                    }
                    Spacer()
                    Button("Apri", action: p.apre).buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
                .padding(14)
                .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // MARK: I widget

    private func testata(_ nome: String, _ icona: String, _ colore: String, destra: String = "") -> some View {
        HStack(spacing: 5) {
            Image(systemName: icona).font(.caption).foregroundStyle(Color(hex: colore))
            Text(nome.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
            Spacer()
            Text(destra).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife)
        }
    }

    private func widgetAgenda(_ restano: [VoceAgenda], passate: Int, totale: Int) -> some View {
        Carta {
            Button { cambiaScheda("calendario") } label: {
                testata("Calendario", "calendar", "#FF453A", destra: passate > 0 ? "\(passate) già passate" : "")
            }
            .buttonStyle(.plain)
            Text(restano.isEmpty ? "Oggi" : "\(restano.count) \(restano.count == 1 ? "cosa" : "cose") oggi").font(.title3.weight(.semibold))
            if restano.isEmpty {
                Text(totale > 0 ? "Per oggi è tutto." : "Giornata libera.").font(.subheadline).foregroundStyle(Color.secondarioLife)
            }
            ForEach(Array(restano.prefix(8).enumerated()), id: \.element.id) { i, v in
                Button(action: v.apre) {
                    HStack(spacing: 10) {
                        Capsule().fill(v.colore).frame(width: 3, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.nome).font(.subheadline.weight(i == 0 ? .semibold : .regular)).lineLimit(1)
                            if let s = v.sotto, !s.isEmpty { Text(s).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1) }
                        }
                        Spacer()
                        Text(v.etichetta).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if restano.count > 8 { Text("e altre \(restano.count - 8)").font(.caption).foregroundStyle(Color.secondarioLife) }
        }
    }

    private func widgetFinanze(_ fin: J, allarme: String?) -> some View {
        Button { Modulo.di("finanze").map(apriModulo) } label: {
            Carta {
                testata("Finanze", "eurosign.circle.fill", "#FF9500", destra: fin.oggiFino.t)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fin.oggiEti.str ?? "Puoi spendere oggi").font(.footnote).foregroundStyle(fin.oggiMale.vero ? Color.pericoloLife : Color.secondarioLife)
                        Text(fin.oggiPuoi.str ?? fin.valore.str ?? "—")
                            .font(.system(size: 34, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(fin.oggiMale.vero ? Color.pericoloLife : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer()
                    let u = fin.urgenti[0]
                    if !u.isNull {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(u.giornoNome.t) \(u.giornoData.t)").font(.caption2).foregroundStyle(Color.secondarioLife)
                            Text(u.nome.t).font(.footnote).lineLimit(1)
                            Text(u.valore.t).font(.footnote.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
                if let allarme { Text(allarme).font(.footnote).foregroundStyle(Color.secondarioLife).lineLimit(2) }
            }
        }
        .buttonStyle(.plain)
    }

    private func widgetAbitudini(_ gettoni: [J], fatte: Int) -> some View {
        Carta(padding: 14) {
            Button { Modulo.di("abitudini").map(apriModulo) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    testata("Abitudini", "checkmark.seal.fill", "#5E5CE6", destra: gettoni.isEmpty ? "" : "\(fatte)/\(gettoni.count)")
                    HStack(spacing: 10) {
                        Anello(valore: gettoni.isEmpty ? 0 : Double(fatte) / Double(gettoni.count), misura: 42, spessore: 6, colore: Color(hex: "#5E5CE6"))
                        Text("\(fatte)").font(.title.weight(.semibold)).monospacedDigit()
                            + Text(" di \(gettoni.count)").font(.footnote).foregroundColor(Color.secondarioLife)
                    }
                }
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 4), alignment: .leading, spacing: 4) {
                ForEach(gettoni.prefix(8), id: \.self) { r in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        var v = r
                        v["modulo"] = "abitudini"
                        logica.chiama("home.fai", v)
                    } label: {
                        Text(r.emoji.str ?? "⭐️")
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .background(r.fatta.vero ? Color(hex: "#5E5CE6").opacity(0.22) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .opacity(r.fatta.vero || r.saltata.vero ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetPasti(_ oggi: String, _ oraMin: Int) -> some View {
        let b = logica.chiama("pasti.calcolo.bersagli")
        if b.kcal.vero {
            let g = logica.chiama("pasti.calcolo.giornata", .str(oggi))
            let fasce = logica.chiama("pasti.dati.FASCE").list
            let conPasto = fasce.map { f -> (J, J) in (f, g.fasce.list.first { $0.fascia == f.id } ?? .null) }
            let prossimo = conPasto.first { $0.1.nome.vero && min($0.0.ora.t) >= oraMin - 60 } ?? conPasto.first { $0.1.nome.vero }
            Button { Modulo.di("pasti").map(apriModulo) } label: {
                Carta(padding: 14) {
                    testata("Pasti", "fork.knife", "#FF2D55", destra: "\(Int(g.totale.kcal.d)) / \(b.kcal.int ?? 0)")
                    HStack(spacing: 10) {
                        Anello(valore: g.totale.kcal.d / max(1, b.kcal.d), misura: 42, spessore: 6, colore: Color(hex: "#FF2D55"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(prossimo.map { "\($0.0.nome.t) · \($0.0.ora.t)" } ?? "Oggi").font(.caption2).foregroundStyle(Color.secondarioLife)
                            Text(prossimo?.1.nome.t ?? "Da decidere").font(.subheadline.weight(.semibold)).lineLimit(2)
                        }
                    }
                    Text("\(max(0, Int(b["p"].d - g.totale["p"].d))) g di proteine da prendere").font(.caption).foregroundStyle(Color.secondarioLife)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func widgetSemplice(_ id: String, valore: String, sotto: String, colore: Color? = nil) -> some View {
        let m = Modulo.di(id)
        return Button { m.map(apriModulo) } label: {
            Carta(padding: 14) {
                testata(m?.nome ?? "", m?.icona ?? "circle", m?.colore ?? "#8E8E93")
                Text(valore.isEmpty ? "—" : valore).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(colore ?? Color.primary).lineLimit(1).minimumScaleFactor(0.6)
                Text(sotto).font(.footnote).foregroundStyle(Color.secondarioLife).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }

    private func widgetTodo(_ tasks: [J]) -> some View {
        let ordinati = tasks.sorted(by: Azioni.ordina)
        return Carta {
            Button { cambiaScheda("oggi") } label: {
                testata("To do", "checkmark.square.fill", "#34C759", destra: tasks.isEmpty ? "" : "\(tasks.count)")
            }
            .buttonStyle(.plain)
            if tasks.isEmpty {
                Text("Tutto fatto.").font(.subheadline).foregroundStyle(Color.secondarioLife)
            }
            ForEach(ordinati.prefix(5), id: \.id) { t in
                HStack(spacing: 6) {
                    Casella(task: t, lato: 19)
                    Text(t.title.t.isEmpty ? "Senza titolo" : t.title.t).font(.subheadline).lineLimit(1)
                    Spacer()
                    if let o = Azioni.ora(t) { Text(o).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                }
                .contentShape(Rectangle())
                .onTapGesture { taskAperto = TaskAperto(task: t) }
            }
            if tasks.count > 5 { Text("+\(tasks.count - 5) altri").font(.caption).foregroundStyle(Color.secondarioLife) }
        }
    }
}
