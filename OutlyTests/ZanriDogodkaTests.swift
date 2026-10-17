import XCTest
import Foundation
@testable import Outly

/// Zanri v obrazcu dogodka (outly-app #97): ce se seznam zanrov ni nalozil, polja `genres` ne posljemo,
/// da urejanje opisa ne izbrise zanrov dogodka.
@MainActor
final class ZanriDogodkaTests: XCTestCase {

    private let vsi = ["rock", "house", "techno", "pop"]

    private func osnutek(genres: [String]?) -> APIClient.EventDraft {
        APIClient.EventDraft(
            title: "Noc",
            description: "Nov opis",
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: nil,
            minAge: 18,
            genres: genres,
            ticketPriceCents: nil,
            ticketUrl: "",
            posterUrl: "",
            status: "published"
        )
    }

    // MARK: - zaPosiljanje

    func testNalozenSeznamPosljeIzbraneVRedoSeznama() {
        let r = ZanriDogodka.zaPosiljanje(vsi: vsi, izbrani: ["pop", "rock"])
        XCTAssertEqual(r, ["rock", "pop"], "vrstni red s streznika, ne iz mnozice")
    }

    func testNalozenSeznamBrezIzbirePosljePrazno() {
        // Uporabnik je zavestno odstranil vse zanre: to je prava sprememba in mora na streznik.
        XCTAssertEqual(ZanriDogodka.zaPosiljanje(vsi: vsi, izbrani: []), [])
    }

    func testNalozenSeznamIzpustiNeznaneIzbrane() {
        XCTAssertEqual(ZanriDogodka.zaPosiljanje(vsi: vsi, izbrani: ["rock", "stari-zanr"]), ["rock"])
    }

    func testNenalozenSeznamNePosljeNicesar() {
        // Urejanje dogodka z zanri [rock, house], seznam GET /genres ni uspel.
        XCTAssertNil(ZanriDogodka.zaPosiljanje(vsi: [], izbrani: ["rock", "house"]))
        // Nov dogodek brez izbire: strezniku zanrov ne posljemo, dogodek podeduje zanre kluba.
        XCTAssertNil(ZanriDogodka.zaPosiljanje(vsi: [], izbrani: []))
    }

    // MARK: - EventDraft.json

    func testJsonBrezZanrovNimaKljucaGenres() {
        let j = osnutek(genres: nil).json
        XCTAssertNil(j["genres"], "PATCH brez `genres` zanrov ne spremeni")
        XCTAssertEqual(j["description"] as? String, "Nov opis")
        XCTAssertEqual(j["minAge"] as? Int, 18)
    }

    func testJsonSPraznimSeznamomPosljePrazenSeznam() {
        let g = osnutek(genres: []).json["genres"] as? [String]
        XCTAssertEqual(g, [])
    }

    func testJsonSZanriPosljeZanre() {
        let g = osnutek(genres: ["rock", "pop"]).json["genres"] as? [String]
        XCTAssertEqual(g, ["rock", "pop"])
    }

    func testUrejanjeOpisaBrezNalozenihZanrovNeIzbriseZanrov() {
        // Celoten tok iz issuea: seznam se ni nalozen, uporabnik spremeni samo opis.
        let zanri = ZanriDogodka.zaPosiljanje(vsi: [], izbrani: ["rock", "house"])
        let j = osnutek(genres: zanri).json
        XCTAssertNil(j["genres"])
    }
}
