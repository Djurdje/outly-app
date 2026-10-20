import XCTest
import Foundation
@testable import Outly

/// 2. krog pregleda #114: vrata ne cakajo na osvezitev seznama po rocnem vpisu, »Try again« ob napaki dela prav tudi po
/// spremembi iskanja, cena po 409 velja tudi na zaslonu dogodka. Vse cisto: brez omrezja, deljenega stanja in cakanja.
@MainActor
final class Popravki2KrogTests: XCTestCase {

    private func stran(_ json: String) throws -> SeznamVstopnicDogodka {
        try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(json.utf8))
    }

    // MARK: - Rocni vpis ne blokira vrat

    func testVpisJeVidenTakojPredOsvezitvijo() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "counts": {"all": 2, "expected": 2}, "total": 2}"#),
                   iskanje: "")
        let t1 = s.vrstice[0], t2 = s.vrstice[1]
        XCTAssertFalse(s.jeVpisana(t1))
        s.oznaciVpisano(t1.id)                  // odgovor strezniga je prisel, osvezitev seznama se ni
        XCTAssertTrue(s.jeVpisana(t1))
        XCTAssertFalse(s.jeVpisana(t2))         // druga vstopnica ostane vpisljiva
    }

    func testOsvezitevPrevzameStreznikovoStanje() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciVpisano(1)
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "used"}], "counts": {"all": 1, "checked_in": 1}, "total": 1}"#)], iskanje: "")
        XCTAssertTrue(s.vpisani.isEmpty)
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))   // zdaj po streznikovem statusu
        XCTAssertEqual(s.stevci?.checkedIn, 1)
    }

    func testLoadMoreNePobriseLokalnihVpisov() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 2, "has_more": true, "next_offset": 1}"#), iskanje: "")
        s.oznaciVpisano(1)
        XCTAssertTrue(s.pripni(try stran(#"{"tickets": [{"id": 2, "status": "valid"}], "total": 2}"#), iskanje: "", odmik: 1))
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))
        XCTAssertFalse(s.jeVpisana(s.vrstice[1]))
    }

    func testKateriRezultatPomeniVpisano() {
        XCTAssertTrue(VrataSeznam.vpisaniRezultat("ok"))
        XCTAssertTrue(VrataSeznam.vpisaniRezultat("already_used"))
        for r in ["invalid", "unknown", "wrong_club", "unpaid", "void", "refunded", "event_cancelled", "not_today", "payment_disputed"] {
            XCTAssertFalse(VrataSeznam.vpisaniRezultat(r), r)
        }
    }

    // MARK: - »Try again« (VrataPonovitev)

    func testPonovitevOsvezitveObdrziMestoNaSeznamu() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "total": 400, "has_more": true, "next_offset": 200}"#), iskanje: "ana")
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: "ana"), .osvezitev)
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: " ana "), .osvezitev)     // ocisceno je isto iskanje
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: "ana"), .naslednjaStran)
        XCTAssertEqual(s.ponovitev(.prvaStran, iskanje: "ana"), .prvaStran)
    }

    func testSpremembaIskanjaMedNapakoNeNaredeMrtvegaGumba() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "total": 400, "has_more": true, "next_offset": 200}"#), iskanje: "ana")
        // Uporabnik tipka dalje: seznam velja za »ana«, »Try again« za »anja« ne sme klicati »Load more« ali osvezitve starega iskanja.
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: "anja"), .prvaStran)
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: "anja"), .prvaStran)
    }

    func testPonovitevBrezNalozenegaSeznama() {
        let s = VrataSeznam()
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: ""), .prvaStran)
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: ""), .prvaStran)
    }

    func testZadnjaStranNimaVecNaslednje() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "total": 1, "has_more": false}"#), iskanje: "")
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: ""), .prvaStran)
    }

    // MARK: - Cena po 409 na zaslonu dogodka

    private func dogodek(priceCents: Int?, currency: String? = "EUR") throws -> APIEvent {
        let cena = priceCents.map { "\($0)" } ?? "null"
        let valuta = currency.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "id": 1, "club_id": 1, "title": "T", "description": "", "poster_url": "",
            "start_at": "2026-01-01T00:00:00.000Z", "end_at": null, "min_age": 18, "genres": [],
            "status": "published", "time_status": "coming_soon",
            "ticket_price_cents": \(cena), "currency": \(valuta), "ticket_url": null,
            "capacity": null, "sold_count": 0, "availability": null
        }
        """
        return try JSONDecoder().decode(APIEvent.self, from: Data(json.utf8))
    }

    func testSvezaCenaPo409NadomestiCenoDogodka() throws {
        let e = try dogodek(priceCents: 1600)
        XCTAssertEqual(e.displayPrice, "€16.00")
        XCTAssertEqual(e.napisCene(cenaCents: nil), "€16.00")
        XCTAssertEqual(e.napisCene(cenaCents: 1800), "€18.00")
        XCTAssertEqual(e.veljavnaCenaCents(cenaCents: 1800), 1800)
        XCTAssertEqual(e.veljavnaCenaCents(cenaCents: nil), 1600)
    }

    func testSvezaCenaNullaJeFree() throws {
        let e = try dogodek(priceCents: 1600)
        XCTAssertEqual(e.veljavnaCenaCents(cenaCents: 0), 0)      // cena padla na 0: zaslon kaze FREE (ticketState)
        XCTAssertEqual(e.napisCene(cenaCents: 0), "€0.00")
    }

    func testDogodekBrezCeneOstaneBrezCeneTudiPo409() throws {
        let e = try dogodek(priceCents: nil)
        XCTAssertNil(e.displayPrice)
        XCTAssertNil(e.napisCene(cenaCents: 1800))
        XCTAssertNil(e.veljavnaCenaCents(cenaCents: 1800))
    }
}
