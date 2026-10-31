import SwiftUI

/// Impostazioni dell'app iPhone (come SettingsView.tsx, senza ciò che esiste solo su Windows).
struct VistaImpostazioni: View {
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var preferenze = Preferenze.s
    @ObservedObject private var notifiche = Notifiche.s
    @ObservedObject private var rete = Rete.s
    @State private var password = ""
    @State private var esitoPassword: String?
    @State private var nomeCalendario = ""
    @State private var urlCalendario = ""
    @State private var coloreCalendario = "#34C759"
    @State private var esitoCalendario: String?
    @State private var iconaPer: J?

    var body: some View {
        let _ = archivio.versione
        return Form {
            Section {
                HStack {
                    Text("Notifiche")
                    Spacer()
                    Text(statoNotifiche).foregroundStyle(notifiche.permesso == .authorized ? Color.successoLife : Color.secondarioLife)
                }
                if notifiche.permesso == .notDetermined {
                    Button("Attiva le notifiche") { notifiche.chiediPermesso() }
                } else if notifiche.permesso == .denied {
                    Button("Apri le Impostazioni di iOS") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }
                Toggle("Promemoria all'ora della scadenza per i nuovi task con orario", isOn: $preferenze.promemoriaAutomatico)
            } header: {
                Text("Promemoria e notifiche")
            } footer: {
                Text("I promemoria vengono programmati su questo iPhone a ogni sincronizzazione, e suonano anche ad app chiusa. Se ne crei uno dal PC, l'iPhone lo scopre quando apri Life o quando iOS le concede di aggiornarsi.")
            }

            Section("Progetti") {
                ForEach(Azioni.progetti, id: \.id) { p in
                    HStack(spacing: 10) {
                        Button { iconaPer = p } label: { IconaProgetto(progetto: p, tasks: Azioni.tasks) }
                            .buttonStyle(.plain)
                            .disabled(p.is_inbox.vero)
                        TextField("Nome", text: Binding(get: { p.is_inbox.vero ? "In entrata" : p.name.t }, set: { n in
                            if !n.isEmpty, !p.is_inbox.vero { Azioni.aggiorna(progetto: p.id.t, ["name": .str(n)]) }
                        }))
                        .disabled(p.is_inbox.vero)
                        if !p.is_inbox.vero {
                            Menu {
                                ForEach(Palette.colori, id: \.0) { c in
                                    Button(c.1) { Azioni.aggiorna(progetto: p.id.t, ["color": .str(c.0)]) }
                                }
                            } label: {
                                Circle().fill(Color.life(p.color.str)).frame(width: 18, height: 18)
                            }
                        }
                    }
                    .swipeActions {
                        if !p.is_inbox.vero {
                            Button("Elimina", role: .destructive) {
                                Domanda.conferma(titolo: "Eliminare il progetto «\(p.name.t)» e i suoi task?") { Azioni.elimina(progetto: p) }
                            }
                        }
                    }
                }
                Button {
                    Domanda.chiedi(titolo: "Nuova area") { n in
                        if !n.isEmpty { Azioni.creaArea(n) }
                    }
                } label: { Label("Nuova area", systemImage: "square.grid.2x2") }
            }

            Section {
                ForEach(Azioni.iscrizioni, id: \.id) { c in
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(Palette.colori, id: \.0) { col in
                                Button(col.1) { Azioni.aggiornaRiga("calendar_subscriptions", c.id.t, ["color": .str(col.0)]) }
                            }
                        } label: {
                            Circle().fill(Color.life(c.color.str)).frame(width: 14, height: 14)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name.t).font(.subheadline.weight(.medium))
                            if let e = c.last_error.str {
                                Text("Errore: \(e)").font(.caption).foregroundStyle(Color.pericoloLife).lineLimit(2)
                            } else if let g = Tempo.dataRoma(c.last_fetched_at.str) {
                                Text("Aggiornato \(Tempo.etichetta(g)) \(Tempo.oraRoma(c.last_fetched_at.str) ?? "")").font(.caption).foregroundStyle(Color.secondarioLife)
                            } else {
                                Text("In attesa del primo aggiornamento").font(.caption).foregroundStyle(Color.secondarioLife)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Elimina", role: .destructive) {
                            Domanda.conferma(titolo: "Rimuovere il calendario «\(c.name.t)»?") {
                                Azioni.aggiornaRiga("calendar_subscriptions", c.id.t, ["deleted_at": Azioni.adesso()])
                            }
                        }
                    }
                }
                TextField("Nome", text: $nomeCalendario)
                TextField("https://… o webcal://…", text: $urlCalendario)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Aggiungi il calendario") {
                    let u = urlCalendario.trimmingCharacters(in: .whitespaces)
                    guard u.range(of: #"^(https?|webcal)://.+"#, options: .regularExpression) != nil else {
                        esitoCalendario = "L'indirizzo deve iniziare con https:// o webcal://"
                        return
                    }
                    Azioni.aggiungiCalendario(nome: nomeCalendario.isEmpty ? "Calendario" : nomeCalendario, url: u, colore: coloreCalendario)
                    nomeCalendario = ""
                    urlCalendario = ""
                    aggiornaCalendari(messaggio: "Calendario aggiunto.")
                }
                .disabled(urlCalendario.isEmpty)
                if !Azioni.iscrizioni.isEmpty {
                    Button { aggiornaCalendari(messaggio: "Aggiornamento chiesto al server.") } label: { Label("Aggiorna ora", systemImage: "arrow.clockwise") }
                }
                if let esitoCalendario { Text(esitoCalendario).font(.footnote).foregroundStyle(Color.secondarioLife) }
            } header: {
                Text("Calendari (.ics)")
            } footer: {
                Text("Sottoscrizioni in sola lettura. Il server le aggiorna ogni 30 minuti.")
            }

            Section("Calendari di Life") {
                ForEach(Azioni.calendariPropri, id: \.id) { c in
                    HStack {
                        Menu {
                            ForEach(Palette.colori, id: \.0) { col in
                                Button(col.1) { Azioni.aggiornaRiga("calendars", c.id.t, ["color": .str(col.0)]) }
                            }
                        } label: {
                            Circle().fill(Color.life(c.color.str)).frame(width: 14, height: 14)
                        }
                        Text(c.name.t)
                        Spacer()
                        if c.is_default.vero { Text("Predefinito").font(.footnote).foregroundStyle(Color.terziarioLife) }
                    }
                }
                Button {
                    Domanda.chiedi(titolo: "Nome del calendario") { n in
                        if !n.isEmpty { Azioni.creaCalendario(nome: n, colore: "#0A84FF") }
                    }
                } label: { Label("Nuovo calendario", systemImage: "plus") }
            }

            Section("Aspetto") {
                Picker("Aspetto", selection: $preferenze.aspetto) {
                    Text("Sistema").tag("system")
                    Text("Chiaro").tag("light")
                    Text("Scuro").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                SecureField("Nuova password", text: $password).textContentType(.newPassword)
                Button("Imposta la password") { impostaPassword() }.disabled(password.isEmpty)
                if let esitoPassword { Text(esitoPassword).font(.footnote).foregroundStyle(Color.secondarioLife) }
            } header: {
                Text("Password di accesso")
            } footer: {
                Text("Per entrare su un altro dispositivo, o dopo aver reinstallato l'app, senza aspettare l'email.")
            }

            Section("Sincronizzazione") {
                Text(descrizioneSync).font(.subheadline).foregroundStyle(Color.secondarioLife)
                Button {
                    Task { @MainActor in await Archivio.s.sincronizza() }
                    Logica.s.sincronizza()
                } label: { Label("Sincronizza ora", systemImage: "arrow.clockwise") }
                Button("Disconnetti questo dispositivo", role: .destructive) { esci() }
            }

            Section {
                HStack {
                    Text("Versione")
                    Spacer()
                    Text(versione).foregroundStyle(Color.secondarioLife)
                }
                if let e = rete.sessione?.email {
                    HStack {
                        Text("Account")
                        Spacer()
                        Text(e).foregroundStyle(Color.secondarioLife)
                    }
                }
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { iconaPer.map { TaskAperto(task: $0) } }, set: { iconaPer = $0?.task })) { a in
            SceltaEmoji(titolo: "Icona di «\(a.task.name.t)»", togli: a.task.emoji.vero ? { Azioni.aggiorna(progetto: a.task.id.t, ["emoji": nil]) } : nil) { e in
                Azioni.aggiorna(progetto: a.task.id.t, ["emoji": .str(e)])
            }
        }
    }

    private var versione: String {
        let d = Bundle.main.infoDictionary
        return "\(d?["CFBundleShortVersionString"] as? String ?? "?") (\(d?["CFBundleVersion"] as? String ?? "?"))"
    }

    private var statoNotifiche: String {
        switch notifiche.permesso {
        case .authorized, .provisional, .ephemeral: return "Attive"
        case .denied: return "Bloccate"
        default: return "Non attive"
        }
    }

    private var descrizioneSync: String {
        var s = archivio.inCoda > 0 ? "\(archivio.inCoda) modifiche in attesa" : "Tutto sincronizzato"
        if let u = archivio.ultimaSync { s += " · ultima \(Tempo.oraRoma(u))" }
        if case .errore(let e) = archivio.stato { s += " · \(e)" }
        if case .offline = archivio.stato { s += " · offline" }
        return s
    }

    private func aggiornaCalendari(messaggio: String) {
        esitoCalendario = messaggio
        Task { @MainActor in
            do {
                try await Archivio.s.aggiornaCalendari()
            } catch {
                esitoCalendario = "L'aggiornamento immediato non è riuscito: \(error.localizedDescription). Riproverà il server tra poco."
            }
        }
    }

    private func impostaPassword() {
        guard password.count >= 8 else {
            esitoPassword = "Almeno 8 caratteri."
            return
        }
        let p = password
        Task { @MainActor in
            do {
                try await rete.cambiaPassword(p)
                esitoPassword = "Password impostata."
                password = ""
            } catch {
                esitoPassword = error.localizedDescription
            }
        }
    }

    private func esci() {
        let esegui = {
            UNUserNotificationCenterSvuota.tutto()
            rete.esci()
            Archivio.s.svuota()
            Logica.s.azzeraMemoria()
        }
        if archivio.inCoda > 0 {
            Domanda.conferma(titolo: "Ci sono modifiche non ancora sincronizzate", messaggio: "Uscendo andranno perse.", azione: "Esci", fatto: esegui)
        } else {
            Domanda.conferma(titolo: "Disconnettere questo iPhone?", azione: "Esci", fatto: esegui)
        }
    }
}

import UserNotifications
enum UNUserNotificationCenterSvuota {
    static func tutto() { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
}
