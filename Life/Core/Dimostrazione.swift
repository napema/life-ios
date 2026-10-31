import Foundation

/// Dati finti per gli screenshot della compilazione (LIFE_DEMO): mai in uso sul telefono vero.
enum Dimostrazione {
    static func carica() {
        guard !Rete.s.connesso, Archivio.s.tutte("projects").isEmpty else { return }
        let oggi = Tempo.oggi()
        let inbox = "demo-inbox"
        let progetto = "demo-progetto"
        Archivio.s.scrivi("projects", [
            ["id": .str(inbox), "name": "In entrata", "color": "#0A84FF", "is_inbox": true, "sort_order": 0, "archived_at": nil, "deleted_at": nil, "completed_at": nil],
            ["id": .str(progetto), "name": "Casa", "color": "#34C759", "emoji": "🏠", "is_inbox": false, "sort_order": 1, "archived_at": nil, "deleted_at": nil, "completed_at": nil],
        ], sincronizza: false)
        Archivio.s.scrivi("calendars", ["id": "demo-cal", "name": "Personale", "color": "#5E5CE6", "is_default": true, "hidden": false, "sort_order": 0, "deleted_at": nil])
        let titoli = ["Chiamare il dentista", "Comprare il pane", "Preparare la borsa", "Rivedere gli appunti"]
        for (i, t) in titoli.enumerated() {
            let conOra = i == 0
            Archivio.s.scrivi("tasks", [
                ["id": .str("demo-t\(i)"), "project_id": .str(i == 2 ? progetto : inbox), "title": .str(t), "notes": nil, "due_at": .str(Tempo.iso(Tempo.istante(oggi, conOra ? "17:30" : nil))), "due_has_time": .bool(conOra), "evening": .bool(i == 3), "someday": false, "deadline": nil, "checklist": [], "tags": i == 1 ? ["spesa"] : [], "priority": i == 0 ? 2 : 4, "rrule": nil, "series_id": nil, "completed_at": nil, "sort_order": .n(i), "deleted_at": nil],
            ], sincronizza: false)
        }
        Archivio.s.scrivi("events", ["id": "demo-e1", "calendar_id": "demo-cal", "title": "Lezione", "notes": nil, "location": "Aula 3", "start_at": .str(Tempo.iso(Tempo.istante(oggi, "09:00"))), "end_at": .str(Tempo.iso(Tempo.istante(oggi, "10:30"))), "all_day": false, "rrule": nil, "deleted_at": nil])
        Archivio.s.scrivi("events", ["id": "demo-e2", "calendar_id": "demo-cal", "title": "Palestra", "notes": nil, "location": nil, "start_at": .str(Tempo.iso(Tempo.istante(oggi, "18:30"))), "end_at": .str(Tempo.iso(Tempo.istante(oggi, "19:30"))), "all_day": false, "rrule": nil, "deleted_at": nil])
        let oraProva = min(21, minutiCalendario(Tempo.oraRoma(Date())) / 60 + 1)
        Archivio.s.scrivi("events", ["id": "demo-e3", "calendar_id": "demo-cal", "title": "Riunione", "notes": nil, "location": nil, "start_at": .str(Tempo.iso(Tempo.istante(oggi, String(format: "%02d:00", oraProva)))), "end_at": .str(Tempo.iso(Tempo.istante(oggi, String(format: "%02d:30", oraProva + 1)))), "all_day": false, "rrule": nil, "deleted_at": nil])
    }
}
