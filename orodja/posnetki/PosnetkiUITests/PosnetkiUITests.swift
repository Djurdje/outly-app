import XCTest

/// Posnetki zaslona za App Store: zazene namesceno Outly (si.outly.app) kot gost in posname glavne zaslone.
/// Vsak korak shrani PNG (polna locljivost naprave) in opis drevesa elementov (za razhroscevanje) v POSNETKI_DIR.
final class PosnetkiUITests: XCTestCase {
    private let mapa = ProcessInfo.processInfo.environment["POSNETKI_DIR"] ?? "/tmp/posnetki"
    private var app: XCUIApplication!

    private func posnemi(_ ime: String) {
        let slika = XCUIScreen.main.screenshot()
        try? FileManager.default.createDirectory(atPath: mapa, withIntermediateDirectories: true)
        try? slika.pngRepresentation.write(to: URL(fileURLWithPath: mapa).appendingPathComponent(ime + ".png"))
        try? app.debugDescription.write(toFile: mapa + "/" + ime + ".txt", atomically: true, encoding: .utf8)
        let priloga = XCTAttachment(screenshot: slika)
        priloga.name = ime
        priloga.lifetime = .keepAlways
        add(priloga)
    }

    /// Zapre sistemska opozorila (obvestila, lokacija), ce se pokazejo.
    private func zapriOpozorila() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for gumb in ["Allow While Using App", "Allow", "Don’t Allow", "Don't Allow", "OK"] {
            let b = springboard.buttons[gumb]
            if b.exists { b.tap(); sleep(1) }
        }
    }

    private func element(_ besedilo: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", besedilo))
            .firstMatch
    }

    @discardableResult
    private func tapni(_ besedilo: String, cakaj: TimeInterval = 8) -> Bool {
        let e = element(besedilo)
        guard e.waitForExistence(timeout: cakaj) else { return false }
        if e.isHittable { e.tap() } else { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        return true
    }

    private func zavihek(_ ime: String) -> Bool {
        let b = app.tabBars.buttons[ime]
        if b.waitForExistence(timeout: 4) { b.tap(); return true }
        return tapni(ime, cakaj: 4)
    }

    private func nazaj() {
        let gumb = app.navigationBars.buttons.element(boundBy: 0)
        if gumb.exists && gumb.isHittable { gumb.tap() } else {
            let zacetek = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            zacetek.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
        sleep(2)
    }

    func testPosnetki() throws {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "si.outly.app")
        // Aplikacijo zazene workflow (simctl launch); launch() iz testa je na runnerju potekel (Timed out attempting to launch app).
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 60)
        sleep(4)
        zapriOpozorila()
        sleep(12)            // zivi podatki z backenda in plakati
        zapriOpozorila()
        posnemi("1-home")

        // Dogodek QUICKIE
        if tapni("QUICKIE") {
            sleep(8)
            zapriOpozorila()
            posnemi("2-dogodek")
            app.swipeUp()
            sleep(3)
            posnemi("3-dogodek-podrobnosti")
            nazaj()
        } else {
            posnemi("2-dogodek-NI-NAJDEN")
        }

        if zavihek("Search") {
            sleep(6)
            posnemi("4-search")
        }

        if zavihek("Map") {
            sleep(4)
            zapriOpozorila()
            sleep(8)
            posnemi("5-map")
        }

        // Klub Outly iz iskanja
        if zavihek("Search") {
            sleep(3)
            if tapni("Outly", cakaj: 5) {
                sleep(8)
                posnemi("6-klub")
                nazaj()
            }
        }

        if zavihek("Profile") {
            sleep(4)
            posnemi("7-profil")
        }
    }
}
