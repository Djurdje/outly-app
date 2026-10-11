import XCTest
import Foundation
@testable import Outly

/// Zasebnost porocanja zrusitev (Sentry Cocoa 9.30.1): stalna oznaka naprave in omrezne sledi ne smejo ven.
/// Preizkusamo samo cista pomocna pravila (brez Sentry tipov: test cilj Sentry ne vkljucuje).
final class NapakeSentryTests: XCTestCase {

    func testOdstraniOznakoNaprave() {
        let kontekst: [String: [String: Any]] = [
            "app": ["device_app_hash": "da39a3ee5e6b4b0d3255bfef95601890afd80709", "app_version": "1.2"],
            "os": ["name": "iOS"]
        ]
        let rezultat = Napake.ocistiKontekst(kontekst)
        XCTAssertNil(rezultat?["app"]?["device_app_hash"])
        XCTAssertEqual(rezultat?["app"]?["app_version"] as? String, "1.2")
        XCTAssertEqual(rezultat?["os"]?["name"] as? String, "iOS")
    }

    func testKontekstBrezAppInNilOstaneNespremenjen() {
        XCTAssertNil(Napake.ocistiKontekst(nil))
        let rezultat = Napake.ocistiKontekst(["device": ["model": "iPhone15,2"]])
        XCTAssertEqual(rezultat?["device"]?["model"] as? String, "iPhone15,2")
        XCTAssertNil(rezultat?["app"])
    }

    func testOmreznaSledSeZavrzeNeglednaPoizvedbo() {
        // Tudi pot brez query niza (DELETE /me/devices/:zeton) je lahko identifikator.
        XCTAssertTrue(Napake.jeOmreznaSled(vrsta: "http", kategorija: "http"))
        XCTAssertTrue(Napake.jeOmreznaSled(vrsta: nil, kategorija: "HTTP"))
        XCTAssertTrue(Napake.jeOmreznaSled(vrsta: nil, kategorija: "xhr"))
        XCTAssertTrue(Napake.jeOmreznaSled(vrsta: "HTTP", kategorija: "ostalo"))
    }

    func testNeomrezneSlediSeObdrzijo() {
        XCTAssertFalse(Napake.jeOmreznaSled(vrsta: "navigation", kategorija: "navigation"))
        XCTAssertFalse(Napake.jeOmreznaSled(vrsta: nil, kategorija: "ui.lifecycle"))
        XCTAssertFalse(Napake.jeOmreznaSled(vrsta: "default", kategorija: "app.lifecycle"))
    }
}
