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

    private func voceEvento(_ e: J, sorgenti: [Sorgente], adessoIso: String) -> VoceAgenda {
        let l = e.own_event_id.isNull ? Lezione.di(e) : nil
        let inizio = Tempo.oraRoma(e.start_at.str) ?? "00:00"
        let fine = Tempo.oraRoma(e.end_at.str) ?? "00:00"
        let orario = e.all_day.vero ? "Tutto il giorno" : "\(inizio) – \(fine)"
        let colore = Color.life(sorgenti.first { $0.id == e.subscription_id.t }?.colore)
        let nome = l?.titolo ?? (e.summary.t.isEmpty ? "(senza titolo)" : e.summary.t)
        let sotto = [orario, l?.dove ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let fatta = !e.all_day.vero && e.end_at.t < adessoIso
        return VoceAgenda(id: "e:\(e.id.t)", quando: e.all_day.vero ? -1 : min(inizio), etichetta: e.all_day.vero ? "tutto" : inizio, fine: e.all_day.vero ? nil : fine, nome: nome, sotto: sotto, colore: colore, fatta: fatta) { cambiaScheda("calendario") }
    }

    /// Le prove non si fondono mai: restano da sole.
    private func eProva(_ e: J, sorgenti: [Sorgente]) -> Bool {
        let titolo = e.summary.t.lowercased()
        let cal = (sorgenti.first { $0.id == e.subscription_id.t }?.nome ?? "").lowercased()
        return titolo.contains("accertament") || titolo.contains("esame") || titolo.contains("valutazion") || cal.contains("valutazion") || cal.contains("accertament")
    }

    /// La giornata compatta (come sul PC): i periodi consecutivi dello stesso calendario, con al massimo
    /// 15 minuti di pausa, diventano un blocco solo: «SUE · 08:20 – 18:30 · 11 periodi».
    private func compatta(_ eventi: [J], sorgenti: [Sorgente], adessoIso: String, oraMin: Int) -> [VoceAgenda] {
        var fuori: [VoceAgenda] = []
        var perCal: [String: [J]] = [:]
        var ordine: [String] = []
        for e in eventi {
            if e.all_day.vero || eProva(e, sorgenti: sorgenti) {
                fuori.append(voceEvento(e, sorgenti: sorgenti, adessoIso: adessoIso))
                continue
            }
            let c = e.subscription_id.t
            if perCal[c] == nil { ordine.append(c) }
            perCal[c, default: []].append(e)
        }
        for c in ordine {
            let lista = (perCal[c] ?? []).sorted { $0.start_at.t < $1.start_at.t }
            var catene: [[J]] = []
            var catena: [J] = []
            for e in lista {
                if let ultima = catena.last {
                    let pausa = min(Tempo.oraRoma(e.start_at.str) ?? "00:00") - min(Tempo.oraRoma(ultima.end_at.str) ?? "00:00")
                    if pausa > 15 {
                        catene.append(catena)
                        catena = []
                    }
                }
                catena.append(e)
            }
            if !catena.isEmpty { catene.append(catena) }
            for gruppo in catene {
                if gruppo.count == 1 {
                    fuori.append(voceEvento(gruppo[0], sorgenti: sorgenti, adessoIso: adessoIso))
                    continue
                }
                let figli = gruppo.map { voceEvento($0, sorgenti: sorgenti, adessoIso: adessoIso) }
                let da = Tempo.oraRoma(gruppo[0].start_at.str) ?? "00:00"
                let fineIso = gruppo.map { $0.end_at.t }.max() ?? gruppo[0].end_at.t
                let a = Tempo.oraRoma(fineIso) ?? "00:00"
                let nomeCal = sorgenti.first { $0.id == c }?.nome ?? "Calendario"
                let inCorso = figli.first { !$0.fatta && $0.quando <= oraMin }
                let coda = inCorso.map { " · ora: \($0.nome)" } ?? ""
                let sotto = "\(da) – \(a) · \(gruppo.count) periodi" + coda
                fuori.append(VoceAgenda(id: "b:\(c):\(gruppo[0].id.t)", quando: min(da), etichetta: da, fine: a, nome: nomeCal, sotto: sotto, colore: Color.life(sorgenti.first { $0.id == c }?.colore), fatta: fineIso < adessoIso) { cambiaScheda("calendario") })
            }
        }
        return fuori
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

        var agenda: [VoceAgenda] = compatta(eventi, sorgenti: sorgenti, adessoIso: adessoIso, oraMin: oraMin)
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
            VStack(alignment: .leading, spacing: 26) {
                eroe(q, prossima, oraMin, restano: restano.count)

                // Il colpo d'occhio: tre tessere uguali, sempre sulla stessa riga
                HStack(alignment: .top, spacing: 12) {
                    tesseraFinanze(fin)
                    tesseraAbitudini(gettoni, fatte: fatteAbi)
                    tesseraPasti(oggi, oraMin)
                }

                if gettoni.contains(where: { !$0.fatta.vero && !$0.saltata.vero }) {
                    blocco("Abitudini di oggi", coda: "\(fatteAbi)/\(gettoni.count)") { fileAbitudini(gettoni) }
                }

                blocco("La giornata", coda: passate > 0 ? "\(passate) passate" : "", apri: { cambiaScheda("calendario") }) {
                    elencoAgenda(restano, totale: agenda.count)
                }

                blocco("To do", coda: tasks.isEmpty ? "" : "\(tasks.count)", apri: { cambiaScheda("oggi") }) {
                    elencoTodo(tasks)
                }

                let righe = righeModuli(tra: tra, mob: mob, rnk: rnk)
                if !righe.isEmpty {
                    blocco("Le tue app") {
                        Elenco {
                            ForEach(Array(righe.enumerated()), id: \.offset) { i, r in
                                if i > 0 { Divider().padding(.leading, 58) }
                                rigaModulo(r)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 36)
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

    // MARK: I mattoni (tutti con le stesse misure: 16 di margine, angoli da 22)

    /// Un blocco con il titolo a sinistra e, a destra, il conteggio (toccando il titolo si apre l'app).
    private func blocco<C: View>(_ titolo: String, coda: String = "", apri: (() -> Void)? = nil, @ViewBuilder contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { apri?() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(titolo).font(.title3.weight(.bold)).foregroundStyle(Color.primary)
                    if apri != nil { Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.terziarioLife) }
                    Spacer()
                    Text(coda).font(.subheadline).monospacedDigit().foregroundStyle(Color.secondarioLife)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(apri == nil)
            contenuto()
        }
    }

    private struct Elenco<C: View>: View {
        @ViewBuilder var contenuto: () -> C
        var body: some View {
            VStack(spacing: 0) { contenuto() }
                .frame(maxWidth: .infinity)
                .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// Il quadratino colorato con il simbolo, come nelle Impostazioni di iOS.
    private func simbolo(_ icona: String, _ colore: Color, lato: CGFloat = 30) -> some View {
        Image(systemName: icona)
            .font(.system(size: lato * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: lato, height: lato)
            .background(colore.gradient, in: RoundedRectangle(cornerRadius: lato * 0.28, style: .continuous))
    }

    // MARK: Adesso

    @ViewBuilder
    private func eroe(_ q: J, _ prossima: VoceAgenda?, _ oraMin: Int, restano: Int) -> some View {
        if let v = q.prio.list.first {
            let tardi = v.quando.str == "tardi"
            let m = Modulo.di(v.modulo.t)
            let s = [v.dentro.str, v.nomeFascia.str].compactMap { $0 }.joined(separator: " · ")
            schedaEroe(etichetta: tardi ? "In ritardo" : "Adesso", colore: tardi ? .pericoloLife : Color(hex: m?.colore ?? "#0A84FF"), icona: m?.icona ?? "bolt.fill", titolo: v.nome.t, sotto: s) {
                if v.habitId.vero {
                    pulsanteEroe("Fatto", colore: Color(hex: m?.colore ?? "#0A84FF")) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        logica.chiama("home.fai", v)
                    }
                } else if v.apre.vero, let m {
                    pulsanteEroe(v.apre.t.contains("/inizia") ? "Avvia" : "Apri", colore: Color(hex: m.colore)) { apriModulo(m) }
                }
            }
        } else if let p = prossima, p.etichetta.contains(":"), p.quando - oraMin > -60, p.quando - oraMin < 240 {
            let fra = p.quando - oraMin
            schedaEroe(etichetta: fra <= 0 ? "Adesso" : fra < 60 ? "Tra \(fra) min" : "Alle \(p.etichetta)", colore: p.colore, icona: "calendar", titolo: p.nome, sotto: p.sotto ?? "") {
                pulsanteEroe("Apri", colore: p.colore, azione: p.apre)
            }
        } else {
            schedaEroe(etichetta: "Oggi", colore: .accentoLife, icona: "sun.max.fill", titolo: restano == 0 ? "Niente in programma" : "\(restano) \(restano == 1 ? "cosa" : "cose") da fare", sotto: restano == 0 ? "Giornata libera: goditela." : "La prossima è più avanti.") {
                EmptyView()
            }
        }
    }

    private func schedaEroe<A: View>(etichetta: String, colore: Color, icona: String, titolo: String, sotto: String, @ViewBuilder azione: () -> A) -> some View {
        HStack(alignment: .center, spacing: 14) {
            simbolo(icona, colore, lato: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(etichetta.uppercased()).font(.caption.weight(.bold)).foregroundStyle(colore)
                Text(titolo).font(.title3.weight(.semibold)).lineLimit(2)
                if !sotto.isEmpty { Text(sotto).font(.subheadline).foregroundStyle(Color.secondarioLife).lineLimit(2) }
            }
            Spacer(minLength: 8)
            azione()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            LinearGradient(colors: [colore.opacity(0.22), Color.cartaLife], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(colore.opacity(0.25), lineWidth: 1))
    }

    private func pulsanteEroe(_ testo: String, colore: Color, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(testo).font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 16).frame(height: 34).background(colore, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Le tessere

    private func tessera<C: View>(_ titolo: String, icona: String, colore: Color, apri: @escaping () -> Void, @ViewBuilder contenuto: () -> C) -> some View {
        Button(action: apri) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icona).font(.caption.weight(.semibold)).foregroundStyle(colore)
                    Text(titolo).font(.caption.weight(.semibold)).foregroundStyle(Color.secondarioLife).lineLimit(1)
                }
                contenuto()
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
            .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tesseraFinanze(_ fin: J) -> some View {
        tessera("Oggi", icona: "eurosign.circle.fill", colore: Color(hex: "#FF9500"), apri: { Modulo.di("finanze").map(apriModulo) }) {
            Text(fin.isNull ? "—" : (fin.oggiPuoi.str ?? fin.valore.str ?? "—"))
                .font(.title2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(fin.oggiMale.vero ? Color.pericoloLife : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(fin.oggiMale.vero ? "oltre il budget" : "da spendere").font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
        }
    }

    private func tesseraAbitudini(_ gettoni: [J], fatte: Int) -> some View {
        tessera("Abitudini", icona: "checkmark.seal.fill", colore: Color(hex: "#5E5CE6"), apri: { Modulo.di("abitudini").map(apriModulo) }) {
            HStack(spacing: 8) {
                Anello(valore: gettoni.isEmpty ? 0 : Double(fatte) / Double(gettoni.count), misura: 34, spessore: 5, colore: Color(hex: "#5E5CE6"))
                Text("\(fatte)").font(.title2.weight(.semibold)).monospacedDigit()
                    + Text("/\(gettoni.count)").font(.subheadline).foregroundColor(Color.secondarioLife)
            }
            Text(gettoni.isEmpty ? "niente oggi" : fatte == gettoni.count ? "tutte fatte" : "da fare \(gettoni.count - fatte)").font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
        }
    }

    private func tesseraPasti(_ oggi: String, _ oraMin: Int) -> some View {
        let b = logica.chiama("pasti.calcolo.bersagli")
        let g = logica.chiama("pasti.calcolo.giornata", .str(oggi))
        let kcal = Int(g.totale.kcal.d)
        let obiettivo = b.kcal.int ?? 0
        return tessera("Pasti", icona: "fork.knife", colore: Color(hex: "#FF2D55"), apri: { Modulo.di("pasti").map(apriModulo) }) {
            HStack(spacing: 8) {
                Anello(valore: obiettivo > 0 ? Double(kcal) / Double(obiettivo) : 0, misura: 34, spessore: 5, colore: Color(hex: "#FF2D55"))
                Text("\(kcal)").font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(obiettivo > 0 ? "di \(obiettivo) kcal" : "kcal oggi").font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1)
        }
    }

    // MARK: Abitudini di oggi (si segnano da qui)

    private func fileAbitudini(_ gettoni: [J]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(gettoni, id: \.self) { r in
                    let fatta = r.fatta.vero || r.saltata.vero
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        var v = r
                        v["modulo"] = "abitudini"
                        logica.chiama("home.fai", v)
                    } label: {
                        VStack(spacing: 6) {
                            Text(r.emoji.str ?? "⭐️").font(.system(size: 24))
                                .frame(width: 54, height: 54)
                                .background(fatta ? Color(hex: "#5E5CE6").opacity(0.25) : Color.cartaLife, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    if fatta {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, Color(hex: "#5E5CE6")).offset(x: 4, y: 4)
                                    }
                                }
                            Text(r.ora.str ?? r.nome.t).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1).frame(width: 60)
                        }
                        .opacity(fatta ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: La giornata

    @ViewBuilder
    private func elencoAgenda(_ restano: [VoceAgenda], totale: Int) -> some View {
        Elenco {
            if restano.isEmpty {
                Text(totale > 0 ? "Per oggi è tutto." : "Giornata libera.").font(.subheadline).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(restano.prefix(8).enumerated()), id: \.element.id) { i, v in
                if i > 0 { Divider().padding(.leading, 76) }
                Button(action: v.apre) {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(v.etichetta == "tutto" ? "tutto" : v.etichetta).font(.subheadline.weight(.semibold)).monospacedDigit()
                            if let f = v.fine { Text(f).font(.caption).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                        }
                        .frame(width: 46, alignment: .trailing)
                        Capsule().fill(v.colore).frame(width: 4, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.nome).font(.body.weight(i == 0 ? .semibold : .regular)).lineLimit(1)
                            if let s = v.sotto, !s.isEmpty { Text(s).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if restano.count > 8 {
                Divider().padding(.leading, 76)
                Button { cambiaScheda("calendario") } label: {
                    Text("Altre \(restano.count - 8)").font(.subheadline.weight(.medium)).foregroundStyle(Color.accentoLife).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 76).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: To do

    private func elencoTodo(_ tasks: [J]) -> some View {
        let ordinati = tasks.sorted(by: Azioni.ordina)
        return Elenco {
            if tasks.isEmpty {
                Text("Tutto fatto.").font(.subheadline).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(ordinati.prefix(6).enumerated()), id: \.element.id) { i, t in
                if i > 0 { Divider().padding(.leading, 48) }
                HStack(spacing: 12) {
                    Casella(task: t, lato: 22)
                    Text(t.title.t.isEmpty ? "Senza titolo" : t.title.t).font(.body).lineLimit(1)
                    Spacer(minLength: 0)
                    if let o = Azioni.ora(t) { Text(o).font(.subheadline).monospacedDigit().foregroundStyle(Color.secondarioLife) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
                .onTapGesture { taskAperto = TaskAperto(task: t) }
            }
            if tasks.count > 6 {
                Divider().padding(.leading, 48)
                Button { cambiaScheda("oggi") } label: {
                    Text("Altri \(tasks.count - 6)").font(.subheadline.weight(.medium)).foregroundStyle(Color.accentoLife).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 48).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Le altre app

    private struct RigaModulo {
        let modulo: Modulo
        let valore: String
        let sotto: String
        let colore: Color?
    }

    private func righeModuli(tra: J, mob: J, rnk: J) -> [RigaModulo] {
        var r: [RigaModulo] = []
        if !tra.isNull, let m = Modulo.di("allenamenti") { r.append(RigaModulo(modulo: m, valore: tra.valore.t, sotto: tra.dettaglio.t, colore: nil)) }
        if !mob.isNull, let m = Modulo.di("mobilita") { r.append(RigaModulo(modulo: m, valore: mob.valore.t, sotto: mob.dettaglio.t, colore: mob.fatto.vero ? .successoLife : nil)) }
        if let m = Modulo.di("rank") {
            if let o = rnk.ontrack.list.first {
                r.append(RigaModulo(modulo: m, valore: o.titolo.t, sotto: [o.quando.t, o.riga.t].filter { !$0.isEmpty }.joined(separator: " · "), colore: Color(hex: o.colore.t)))
            } else if !rnk.isNull {
                r.append(RigaModulo(modulo: m, valore: rnk.valore.t, sotto: [rnk.prova.t, rnk.dettaglio.t].filter { !$0.isEmpty }.joined(separator: " · "), colore: rnk.urgente.vero ? .pericoloLife : nil))
            }
        }
        return r
    }

    private func rigaModulo(_ r: RigaModulo) -> some View {
        Button { apriModulo(r.modulo) } label: {
            HStack(spacing: 14) {
                simbolo(r.modulo.icona, Color(hex: r.modulo.colore))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.modulo.nome).font(.body)
                    if !r.sotto.isEmpty { Text(r.sotto).font(.caption).foregroundStyle(Color.secondarioLife).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(r.valore.isEmpty ? "—" : r.valore).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(r.colore ?? Color.secondarioLife).lineLimit(1)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.terziarioLife)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
