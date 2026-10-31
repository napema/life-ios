import Foundation
import WidgetKit

/// Il contenitore che app e widget condividono. Chi firma l'app col proprio Apple ID aggiunge il suo
/// team all'identificativo, e così cambia anche il nome del gruppo: va ricavato, non scritto.
enum GruppoLife {
    private static var idApp: String {
        let id = Bundle.main.bundleIdentifier ?? "it.life.app"
        guard Bundle.main.bundleURL.pathExtension == "appex" else { return id }
        return id.split(separator: ".").dropLast().joined(separator: ".")
    }

    static let contenitore: URL? = {
        let dichiarati = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        for gruppo in dichiarati + ["group.\(idApp)"] {
            if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppo) { return u }
        }
        return nil
    }()

    static func file(_ nome: String) -> URL? { contenitore?.appendingPathComponent(nome) }
}

/// Dove porta ogni tocco su un widget.
enum LinkLife {
    private static func url(_ s: String) -> URL { URL(string: "life://\(s)")! }
    static let todo = url("todo")
    static let calendario = url("calendario")
    static let nuovoTask = url("nuovo-task")
    static let uscita = url("finanze/uscita")
    static let entrata = url("finanze/entrata")
    static func task(_ id: String?) -> URL { id.map { url("task/\($0)") } ?? todo }
    static func evento(_ e: DatiWidget.Evento, oggi: String) -> URL {
        guard let id = e.id else { return calendario }
        return url("evento/\(id)/\(e.data ?? oggi)")
    }
}

/// La stessa risposta che legge il widget di Scriptable (funzione `claude`, indirizzo personale).
struct DatiWidget: Codable {
    struct Evento: Codable, Hashable {
        var id: String?
        var titolo: String
        var inizio: String?
        var fine: String?
        var colore: String?
        var calendario: String?
        var luogo: String?
        var data: String?
        var giorno: String?
    }
    struct Task: Codable, Hashable {
        var id: String?
        var titolo: String
        var ora: String?
        var lista: String?
        var colore: String?
        var inRitardo: Bool?
        var sera: Bool?
    }
    struct Mese: Codable {
        var nome: String
        var anno: Int
        var giorni: Int
        var primoGiornoSettimana: Int
        var conEventi: [Int]?
    }
    var oggi: String
    var titolo: String
    var mese: Mese
    var prossimi: [Evento]
    var eventi: [Evento]
    var domani: [Evento]?
    var task: [Task]

    static let esempio = DatiWidget(
        oggi: "2026-10-31",
        titolo: "Sabato 31 ottobre",
        mese: Mese(nome: "ottobre", anno: 2026, giorni: 31, primoGiornoSettimana: 3, conEventi: [2, 9, 16, 23, 28]),
        prossimi: [
            Evento(id: "e1", titolo: "Lezione", inizio: "09:00", fine: "10:30", colore: "#5E5CE6", luogo: "Aula 3", data: "2026-10-31", giorno: "Oggi"),
            Evento(id: "e2", titolo: "Palestra", inizio: "18:30", fine: "19:30", colore: "#FF453A", data: "2026-10-31", giorno: "Oggi"),
            Evento(id: "e3", titolo: "Cena", inizio: "20:30", fine: "22:00", colore: "#34C759", data: "2026-11-01", giorno: "Domani"),
        ],
        eventi: [
            Evento(id: "e1", titolo: "Lezione", inizio: "09:00", fine: "10:30", colore: "#5E5CE6", luogo: "Aula 3", data: "2026-10-31"),
            Evento(id: "e2", titolo: "Palestra", inizio: "18:30", fine: "19:30", colore: "#FF453A", data: "2026-10-31"),
        ],
        domani: [],
        task: [
            Task(id: "t1", titolo: "Chiamare il dentista", ora: "17:30", lista: "In entrata", colore: "#0A84FF", inRitardo: false),
            Task(id: "t2", titolo: "Comprare il pane", lista: "In entrata", colore: "#0A84FF", inRitardo: false),
            Task(id: "t3", titolo: "Preparare la borsa", lista: "Casa", colore: "#34C759", inRitardo: true),
            Task(id: "t4", titolo: "Rivedere gli appunti", lista: "In entrata", colore: "#0A84FF", sera: true),
        ]
    )
}

/// Legge e scrive per i widget: funziona anche ad app chiusa, perché parla direttamente col server.
enum ClienteWidget {
    private struct Collegamento: Codable { var indirizzo: String }
    private static let decodifica: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private static let codifica: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // L'app salva qui l'indirizzo personale dei dati, appena ha fatto l'accesso
    static func collega(indirizzo: String?) {
        guard let f = GruppoLife.file("collegamento.json") else { return }
        if let indirizzo, let d = try? JSONEncoder().encode(Collegamento(indirizzo: indirizzo)) {
            try? d.write(to: f, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: f)
            if let c = GruppoLife.file("dati.json") { try? FileManager.default.removeItem(at: c) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var indirizzo: URL? {
        guard let f = GruppoLife.file("collegamento.json"), let d = try? Data(contentsOf: f),
              let c = try? JSONDecoder().decode(Collegamento.self, from: d) else { return nil }
        return URL(string: c.indirizzo)
    }

    static var cache: DatiWidget? {
        guard let f = GruppoLife.file("dati.json"), let d = try? Data(contentsOf: f) else { return nil }
        return try? decodifica.decode(DatiWidget.self, from: d)
    }

    private static func salvaCache(_ dati: DatiWidget) {
        guard let f = GruppoLife.file("dati.json"), let d = try? codifica.encode(dati) else { return }
        try? d.write(to: f, options: .atomic)
    }

    private static var coda: [String] {
        get {
            guard let f = GruppoLife.file("coda.json"), let d = try? Data(contentsOf: f) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: d)) ?? []
        }
        set {
            guard let f = GruppoLife.file("coda.json"), let d = try? JSONEncoder().encode(newValue) else { return }
            try? d.write(to: f, options: .atomic)
        }
    }

    static func scarica() async -> DatiWidget? {
        await svuotaCoda()
        guard let url = indirizzo else { return nil }
        var q = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        q.httpMethod = "GET"
        guard let (d, _) = try? await URLSession.shared.data(for: q), var dati = try? decodifica.decode(DatiWidget.self, from: d) else { return nil }
        let inAttesa = Set(coda)
        dati.task.removeAll { $0.id.map(inAttesa.contains) ?? false }
        salvaCache(dati)
        return dati
    }

    /// La spunta dal widget: sparisce subito, e al server arriva ora o al prossimo aggiornamento.
    static func completa(_ id: String) async {
        if var dati = cache {
            dati.task.removeAll { $0.id == id }
            salvaCache(dati)
        }
        if await invia(id) == false { coda = coda + [id] }
    }

    private static func svuotaCoda() async {
        for id in coda where await invia(id) {
            coda = coda.filter { $0 != id }
        }
    }

    private static func invia(_ id: String) async -> Bool {
        guard let url = indirizzo, let corpo = try? JSONSerialization.data(withJSONObject: ["azione": "completa", "id": id]) else { return false }
        var q = URLRequest(url: url, timeoutInterval: 12)
        q.httpMethod = "POST"
        q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        q.httpBody = corpo
        guard let (_, r) = try? await URLSession.shared.data(for: q) else { return false }
        return (r as? HTTPURLResponse)?.statusCode == 200
    }
}
