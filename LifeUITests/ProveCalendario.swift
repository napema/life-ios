import XCTest

/// Il dito vero sul simulatore: i giorni e le settimane devono scorrere.
final class ProveCalendario: XCTestCase {
    private let cartella = URL(fileURLWithPath: "/tmp/life-prove", isDirectory: true)

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
    }

    private func foto(_ nome: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: cartella.appendingPathComponent("\(nome).png"))
    }

    private func visibile(_ app: XCUIApplication) -> String {
        let e = app.otherElements["calendario.visibile"]
        _ = e.waitForExistence(timeout: 8)
        return e.label
    }

    private func trascina(_ app: XCUIApplication, da: CGFloat, a: CGFloat, y: CGFloat = 0.55) {
        let inizio = app.coordinate(withNormalizedOffset: CGVector(dx: da, dy: y))
        let fine = app.coordinate(withNormalizedOffset: CGVector(dx: a, dy: y))
        inizio.press(forDuration: 0.05, thenDragTo: fine, withVelocity: .fast, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func apri(_ modo: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LIFE_DEMO"] = "calendario:\(modo)"
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    private func provaScorrimento(_ modo: String, y: CGFloat = 0.55) {
        let app = apri(modo)
        let prima = visibile(app)
        foto("\(modo)-1-prima")
        trascina(app, da: 0.85, a: 0.2, y: y)
        let dopo = visibile(app)
        foto("\(modo)-2-dopo")
        XCTAssertNotEqual(prima, dopo, "\(modo): lo swipe non ha cambiato giorno")
        trascina(app, da: 0.2, a: 0.85, y: y)
        // Su tre giorni lo slancio può fermarsi un giorno più in là: conta che torni indietro
        if modo == "three" {
            XCTAssertLessThan(visibile(app), dopo, "\(modo): non torna indietro")
        } else {
            XCTAssertEqual(prima, visibile(app), "\(modo): tornando indietro non si torna al punto di prima")
        }
        app.terminate()
    }

    func testGiorno() { provaScorrimento("day") }
    func testTreGiorni() { provaScorrimento("three") }
    func testSettimana() { provaScorrimento("week") }
    func testMese() { provaScorrimento("month", y: 0.35) }

    /// Le schede già aperte non devono riportare indietro quella che stai guardando.
    func testDopoAverCambiatoScheda() {
        let app = apri("week")
        app.tabBars.buttons["Giorno"].tap()
        Thread.sleep(forTimeInterval: 1)
        let prima = visibile(app)
        trascina(app, da: 0.85, a: 0.2)
        trascina(app, da: 0.85, a: 0.2)
        let dopo = visibile(app)
        foto("giorno-dopo-settimana")
        XCTAssertNotEqual(prima, dopo)
        app.terminate()
    }

    private func avvia(_ demo: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LIFE_DEMO"] = demo
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    private func qualunque(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Dove l'app dice che è un blocco: il testo per l'accessibilità non cade esattamente sul blocco.
    private func rettangolo(_ app: XCUIApplication, _ nome: String = "Riunione") -> CGRect {
        let e = qualunque(app, "calendario.blocchi")
        XCTAssertTrue(e.waitForExistence(timeout: 8), "La griglia non dice dove sono i blocchi")
        for _ in 0..<16 {
            for voce in e.label.split(separator: ";") {
                let parti = voce.split(separator: "=")
                guard parti.count == 2, parti[0] == nome else { continue }
                let n = parti[1].split(separator: ",").compactMap { Double($0) }
                if n.count == 4 { return CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("\(nome) non è sulla griglia: \(e.label)")
        return .zero
    }

    private func punto(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// Tieni premuto e trascina: l'evento cambia ora, resta lungo uguale, e non si apre niente.
    func testSpostaEvento() {
        let app = apri("day")
        let r = rettangolo(app)
        let da = punto(app, r.midX, r.midY)
        da.press(forDuration: 0.7, thenDragTo: da.withOffset(CGVector(dx: 0, dy: 90)), withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1)
        foto("sposta-1-dopo")
        let dopo = rettangolo(app)
        // Un'ora è alta 60 punti: 90 punti di dito sono 90 minuti, a passi di 5
        XCTAssertEqual(dopo.minY, r.minY + 90, accuracy: 6, "L'evento non è andato dove l'ha portato il dito")
        XCTAssertEqual(dopo.height, r.height, accuracy: 1, "Spostandolo ha cambiato durata")
        XCTAssertFalse(app.navigationBars["Nuovo evento"].exists, "Il trascinamento ha aperto un nuovo evento")
        app.terminate()
    }

    /// Tieni premuto e lascia: compaiono i bordi, e tirandone uno cambia la durata.
    func testTiraIlBordo() {
        let app = apri("day")
        let r = rettangolo(app)
        punto(app, r.midX, r.midY).press(forDuration: 0.7)
        Thread.sleep(forTimeInterval: 0.6)
        foto("bordi-1-selezionato")
        XCTAssertEqual(rettangolo(app).minY, r.minY, accuracy: 1, "Solo tenendo premuto l'evento non deve spostarsi")
        let c = punto(app, r.maxX - 16, r.maxY)
        c.press(forDuration: 0.1, thenDragTo: c.withOffset(CGVector(dx: 0, dy: 50)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1)
        foto("bordi-2-tirato")
        let dopo = rettangolo(app)
        XCTAssertGreaterThan(dopo.height, r.height + 30, "Il bordo non ha cambiato la durata")
        XCTAssertEqual(dopo.minY, r.minY, accuracy: 1, "Tirando la fine si è mosso l'inizio")
        app.terminate()
    }

    /// Su più giorni il blocco passa alla colonna dopo.
    func testSpostaSulGiornoDopo() {
        let app = apri("three")
        let r = rettangolo(app)
        let colonna = (app.frame.width - 50) / 3
        let da = punto(app, r.midX, r.midY)
        da.press(forDuration: 0.7, thenDragTo: da.withOffset(CGVector(dx: colonna, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1)
        foto("sposta-2-giorno-dopo")
        XCTAssertGreaterThan(rettangolo(app).minX, r.minX + colonna / 2, "L'evento è rimasto nel suo giorno")
        app.terminate()
    }

    /// Lo scorrimento resta vivo: dopo aver spostato un evento, i giorni scorrono ancora.
    func testSiScorreAncora() {
        let app = apri("day")
        let r = rettangolo(app)
        let da = punto(app, r.midX, r.midY)
        da.press(forDuration: 0.7, thenDragTo: da.withOffset(CGVector(dx: 0, dy: 45)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1)
        let prima = visibile(app)
        trascina(app, da: 0.85, a: 0.2)
        XCTAssertNotEqual(prima, visibile(app), "Dopo il trascinamento la griglia non scorre più")
        app.terminate()
    }

    /// Il pannello del «+»: sale dal basso, tutte le opzioni si vedono, e il task nasce con quello che scegli.
    func testNuovoTask() {
        let app = avvia("todo")
        let piu = qualunque(app, "Nuovo task")
        XCTAssertTrue(piu.waitForExistence(timeout: 8))
        piu.tap()
        Thread.sleep(forTimeInterval: 1.2)
        foto("task-1-pannello")
        for voce in ["Scadenza", "Priorità", "Tag", "Ripeti", "Promemoria", "Checklist", "Note"] {
            XCTAssertTrue(qualunque(app, voce).exists, "Manca \(voce)")
        }
        app.typeText("Comprare il latte")
        qualunque(app, "Priorità").tap()
        Thread.sleep(forTimeInterval: 0.6)
        foto("task-2-menu")
        qualunque(app, "Alta").tap()
        Thread.sleep(forTimeInterval: 0.5)
        qualunque(app, "Checklist").tap()
        app.typeText("Intero")
        Thread.sleep(forTimeInterval: 0.5)
        foto("task-3-riempito")
        qualunque(app, "Aggiungi").tap()
        Thread.sleep(forTimeInterval: 1.2)
        foto("task-4-aggiunto")
        XCTAssertTrue(app.staticTexts["Comprare il latte"].waitForExistence(timeout: 4), "Il task non è in lista")
        app.terminate()
    }

    /// I tre puntini di Finanze aprono il menu col resto.
    func testMenuFinanze() {
        let app = avvia("finanze")
        XCTAssertTrue(qualunque(app, "Altre azioni").waitForExistence(timeout: 8))
        // Il dito dove si vedono i puntini: a destra, nella barra sopra le schede
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.853, dy: 0.868)).tap()
        Thread.sleep(forTimeInterval: 1)
        foto("finanze-menu")
        XCTAssertTrue(qualunque(app, "Lista d'attesa").exists)
        XCTAssertTrue(qualunque(app, "Pagamento previsto").exists)
        app.terminate()
    }
}
