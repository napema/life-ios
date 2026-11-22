import BackgroundTasks
import Foundation
import UserNotifications

/// I promemoria come notifiche locali: con un Apple ID gratuito le push da server non esistono.
/// iOS ne tiene in coda al massimo 64, quindi si programmano le più vicine a ogni sincronizzazione.
final class Notifiche: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let s = Notifiche()
    static let attivita = "life.aggiornamento"
    private static let massimo = 60
    private static let prefisso = "promemoria:"

    @Published private(set) var permesso: UNAuthorizationStatus = .notDetermined
    /// Un task o un evento aperto toccando la notifica.
    @Published var daAprire: String?

    func avvia() {
        let centro = UNUserNotificationCenter.current()
        centro.delegate = self
        aggiornaPermesso()
    }

    func aggiornaPermesso() {
        UNUserNotificationCenter.current().getNotificationSettings { impostazioni in
            DispatchQueue.main.async { self.permesso = impostazioni.authorizationStatus }
        }
    }

    func chiediPermesso() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                self.aggiornaPermesso()
                self.riprogramma()
            }
        }
    }

    /// Mette in coda i promemoria futuri non cancellati e toglie quelli che non valgono più.
    func riprogramma() {
        let adesso = Date()
        let archivio = Archivio.s
        struct Voce { let id: String; let quando: Date; let titolo: String; let corpo: String; let apri: String }
        var voci: [Voce] = []
        for r in archivio.tutte("reminders") {
            guard r.deleted_at.isNull, let id = r.id.str, let quando = Tempo.data(r.remind_at.str), quando > adesso else { continue }
            if let t = r.task_id.str, let task = archivio.riga("tasks", t) {
                if !task.deleted_at.isNull || !task.completed_at.isNull { continue }
                var corpo = "Promemoria"
                if task.due_has_time.vero, let o = Tempo.oraRoma(task.due_at.str) { corpo = "Alle \(o)" }
                voci.append(Voce(id: id, quando: quando, titolo: task.title.str ?? "Task", corpo: corpo, apri: "task:\(t)"))
            } else if let e = r.event_id.str, let evento = archivio.riga("events", e) {
                if !evento.deleted_at.isNull { continue }
                let inizio = evento.all_day.vero ? Tempo.etichetta(Tempo.dataRoma(evento.start_at.str) ?? "") : (Tempo.oraRoma(evento.start_at.str) ?? "")
                voci.append(Voce(id: id, quando: quando, titolo: evento.title.str ?? "Evento", corpo: inizio, apri: "evento:\(e)"))
            }
        }
        // Rank: «oggi per Rank» la mattina, il debito la sera (al massimo 2 al giorno), calcolate dalla logica
        for n in Logica.s.chiama("rank.notifiche").list {
            guard let id = n.id.str, let g = n.giorno.str, let o = n.ora.str else { continue }
            let quando = Tempo.istante(g, o)
            if quando <= adesso { continue }
            voci.append(Voce(id: id, quando: quando, titolo: n.titolo.t, corpo: n.corpo.t, apri: "modulo:rank"))
        }
        voci.sort { $0.quando < $1.quando }
        let scelte = voci.prefix(Self.massimo)
        let centro = UNUserNotificationCenter.current()
        centro.getPendingNotificationRequests { attesa in
            let giusti = Set(scelte.map { Self.prefisso + $0.id })
            let via = attesa.map(\.identifier).filter { $0.hasPrefix(Self.prefisso) && !giusti.contains($0) }
            centro.removePendingNotificationRequests(withIdentifiers: via)
            for v in scelte {
                let c = UNMutableNotificationContent()
                c.title = v.titolo
                c.body = v.corpo
                c.sound = .default
                c.userInfo = ["apri": v.apri]
                let d = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: v.quando)
                let q = UNNotificationRequest(identifier: Self.prefisso + v.id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: false))
                centro.add(q)
            }
        }
    }

    // MARK: In primo piano e al tocco

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let apri = response.notification.request.content.userInfo["apri"] as? String
        await MainActor.run { self.daAprire = apri }
    }

    // MARK: Il vassoio: «Il PC ti ha mandato un file»

    private static let chiaveVassoio = "vassoio.avvisati"

    /// I file arrivati dal PC che non hai ancora visto: una notifica (toccandola si apre il vassoio).
    /// Gira in sottofondo (quando iOS lo concede) e ogni volta che Life torna in primo piano.
    func controllaVassoio() async {
        guard Rete.s.connesso, let righe = try? await Rete.s.righe("vassoio", "select=id,nome&da=eq.pc&ritirato_iphone=eq.false&order=creato.desc", da: 0, a: 19) else { return }
        let visti = Set(UserDefaults.standard.stringArray(forKey: Self.chiaveVassoio) ?? [])
        let nuovi = righe.filter { !visti.contains($0.id.t) }
        guard let primo = nuovi.first else { return }
        segnaVassoioVisto(nuovi.map { $0.id.t })
        let c = UNMutableNotificationContent()
        c.title = "Il PC ti ha mandato \(nuovi.count == 1 ? "un file" : "\(nuovi.count) file")"
        c.body = nuovi.count == 1 ? "\(primo.nome.t) · tocca per aprire il vassoio" : nuovi.prefix(3).map { $0.nome.t }.joined(separator: ", ")
        c.sound = .default
        c.userInfo = ["apri": "modulo:vassoio"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "vassoio:\(primo.id.t)", content: c, trigger: nil))
    }

    func segnaVassoioVisto(_ id: [String]) {
        var visti = UserDefaults.standard.stringArray(forKey: Self.chiaveVassoio) ?? []
        for i in id where !visti.contains(i) { visti.append(i) }
        UserDefaults.standard.set(Array(visti.suffix(300)), forKey: Self.chiaveVassoio)
    }

    // MARK: Aggiornamento in background

    func registraAttivita() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.attivita, using: nil) { attivita in
            guard let a = attivita as? BGAppRefreshTask else { return }
            self.pianificaAttivita()
            let lavoro = Task { @MainActor in
                await Archivio.s.sincronizza()
                Archivio.s.salvaOra()
                await self.controllaVassoio()
                a.setTaskCompleted(success: true)
            }
            a.expirationHandler = { lavoro.cancel() }
        }
    }

    /// iOS decide quando: chiediamo ogni mezz'ora, senza garanzie.
    func pianificaAttivita() {
        let q = BGAppRefreshTaskRequest(identifier: Self.attivita)
        q.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(q)
    }
}
