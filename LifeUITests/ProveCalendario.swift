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
        XCTAssertEqual(prima, visibile(app), "\(modo): tornando indietro non si torna al punto di prima")
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

    /// Gli orari scritti nei blocchi: «09:00 – 10:30».
    private func orari(_ app: XCUIApplication) -> Set<String> {
        Set(app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.contains(" – ") })
    }

    private func riunione(_ app: XCUIApplication) -> XCUIElement {
        let r = app.staticTexts["Riunione"].firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 8), "L'evento di prova non si vede")
        return r
    }

    /// Tieni premuto e trascina: l'evento cambia ora, resta lungo uguale, e non si apre niente.
    func testSpostaEvento() {
        let app = apri("day")
        let da = riunione(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let prima = orari(app)
        da.press(forDuration: 0.7, thenDragTo: da.withOffset(CGVector(dx: 0, dy: 90)), withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1)
        foto("sposta-1-dopo")
        let dopo = orari(app)
        XCTAssertNotEqual(prima, dopo, "L'evento non si è spostato")
        XCTAssertFalse(app.navigationBars["Nuovo evento"].exists, "Il trascinamento ha aperto un nuovo evento")
        print("ORARI prima \(prima.sorted()) dopo \(dopo.sorted())")
        app.terminate()
    }

    /// Tieni premuto e lascia: compaiono i bordi, e tirandone uno cambia solo la fine.
    func testTiraIlBordo() {
        let app = apri("day")
        let da = riunione(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let prima = orari(app)
        da.press(forDuration: 0.7)
        Thread.sleep(forTimeInterval: 0.6)
        foto("bordi-1-selezionato")
        XCTAssertEqual(prima, orari(app), "Solo tenendo premuto l'evento non deve spostarsi")
        let bordo = qualunque(app, "calendario.bordo.fine")
        XCTAssertTrue(bordo.waitForExistence(timeout: 3), "I bordi non compaiono")
        let c = bordo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        c.press(forDuration: 0.1, thenDragTo: c.withOffset(CGVector(dx: 0, dy: 50)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1)
        foto("bordi-2-tirato")
        let dopo = orari(app)
        XCTAssertNotEqual(prima, dopo, "Il bordo non ha cambiato la durata")
        print("ORARI prima \(prima.sorted()) dopo \(dopo.sorted())")
        app.terminate()
    }

    /// Su più giorni il blocco passa alla colonna dopo.
    func testSpostaSulGiornoDopo() {
        let app = apri("three")
        let r = riunione(app)
        let xPrima = r.frame.minX
        let da = r.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let colonna = (app.frame.width - 50) / 3
        da.press(forDuration: 0.7, thenDragTo: da.withOffset(CGVector(dx: colonna, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1)
        foto("sposta-2-giorno-dopo")
        XCTAssertGreaterThan(riunione(app).frame.minX, xPrima + colonna / 2, "L'evento è rimasto nel suo giorno")
        app.terminate()
    }

    /// Lo scorrimento resta vivo: dopo aver preso e lasciato un evento, i giorni scorrono ancora.
    func testSiScorreAncora() {
        let app = apri("day")
        let da = riunione(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
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
        let puntini = qualunque(app, "Altre azioni")
        XCTAssertTrue(puntini.waitForExistence(timeout: 8))
        puntini.tap()
        Thread.sleep(forTimeInterval: 0.8)
        foto("finanze-menu")
        XCTAssertTrue(qualunque(app, "Lista d'attesa").exists)
        XCTAssertTrue(qualunque(app, "Pagamento previsto").exists)
        app.terminate()
    }
}
