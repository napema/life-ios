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
}
