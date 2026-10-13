import XCTest
import Foundation
@testable import Outly

/// Demo klubi (outly-backend#243, 13. 10. 2026): `is_demo` na klubih in dogodkih (star backend -> false), 409 `demo_club` z lastnim
/// sporocilom v OBEH poteh (`userMessage`, `nakupUserMessage`), pravilo »demo = brez nakupa, razen admin« in razlog v dashboardu.
@MainActor
final class DemoKlubTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let telo = #"{"error":"demo_club","message":"This is a demo club. Tickets can't be bought."}"#
    private var napaka: APIError { .requestFailed(409, telo) }
    private let sporocilo = String(localized: "This is a demo club. Tickets can't be bought.")

    // MARK: - Dekodiranje

    func testIsDemoPrivzetoFalseInStarBackend() throws {
        XCTAssertFalse(try decode(APIEvent.self, #"{"id": 1}"#).isDemo)
        XCTAssertFalse(try decode(APIClub.self, #"{"id": 1}"#).isDemo)
        XCTAssertFalse(try decode(MapClub.self, #"{"id": 1, "lat": 46.05, "lng": 14.5}"#).isDemo)
        XCTAssertFalse(try decode(SearchResults.self, #"{"clubs": [{"id": 1}], "events": [{"id": 2}]}"#).clubs[0].isDemo)
        XCTAssertFalse(try decode(SearchResults.self, #"{"clubs": [{"id": 1}], "events": [{"id": 2}]}"#).events[0].isDemo)
        XCTAssertFalse(try decode(EventVip.self, #"{"event_id": 1}"#).isDemo)
    }

    func testIsDemoDekodiranPriVsehModelih() throws {
        XCTAssertTrue(try decode(APIEvent.self, #"{"id": 1, "is_demo": true, "payment_mode": "unavailable"}"#).isDemo)
        XCTAssertTrue(try decode(APIClub.self, #"{"id": 1, "is_demo": true}"#).isDemo)
        XCTAssertTrue(try decode(MapClub.self, #"{"id": 1, "lat": 46.05, "lng": 14.5, "is_demo": true}"#).isDemo)
        let r = try decode(SearchResults.self, #"{"clubs": [{"id": 1, "is_demo": true}], "events": [{"id": 2, "is_demo": true}]}"#)
        XCTAssertTrue(r.clubs[0].isDemo)
        XCTAssertTrue(r.events[0].isDemo)
        XCTAssertTrue(try decode(EventVip.self, #"{"event_id": 1, "is_demo": true}"#).isDemo)
    }

    func testPokvarjenIsDemoNePodreDekodiranja() throws {
        XCTAssertFalse(try decode(APIEvent.self, #"{"id": 1, "is_demo": "ne"}"#).isDemo)
        XCTAssertFalse(try decode(APIClub.self, #"{"id": 1, "is_demo": null}"#).isDemo)
    }

    // MARK: - Pravilo: demo = brez nakupa, razen admin

    func testBrezNakupaSamoZaDemoInNeAdmina() {
        XCTAssertTrue(DemoKlub.brezNakupa(isDemo: true, jeAdmin: false))
        XCTAssertFalse(DemoKlub.brezNakupa(isDemo: true, jeAdmin: true))
        XCTAssertFalse(DemoKlub.brezNakupa(isDemo: false, jeAdmin: false))
        XCTAssertFalse(DemoKlub.brezNakupa(isDemo: false, jeAdmin: true))
    }

    func testProdajaNedosegljivaDemoOdlocaIsDemoNePaymentMode() {
        // Demo, ne admin: nedosegljivo tudi, ce je payment_mode »stripe« ali star backend (nil -> .neznan).
        for n in [NacinPlacila.test, .stripe, .neznan, .nedosegljivo] {
            XCTAssertTrue(DemoKlub.prodajaNedosegljiva(isDemo: true, jeAdmin: false, nacin: n))
        }
        // Demo, admin: gumb ostane, tudi ce je payment_mode »unavailable« (odgovor je za vse enak, streznik admina spusti).
        for n in [NacinPlacila.test, .stripe, .neznan, .nedosegljivo] {
            XCTAssertFalse(DemoKlub.prodajaNedosegljiva(isDemo: true, jeAdmin: true, nacin: n))
        }
        // Ni demo: kot doslej samo `unavailable` (seller_incomplete, stripe_not_ready ...), ne glede na vlogo.
        XCTAssertTrue(DemoKlub.prodajaNedosegljiva(isDemo: false, jeAdmin: false, nacin: .nedosegljivo))
        XCTAssertTrue(DemoKlub.prodajaNedosegljiva(isDemo: false, jeAdmin: true, nacin: .nedosegljivo))
        XCTAssertFalse(DemoKlub.prodajaNedosegljiva(isDemo: false, jeAdmin: false, nacin: .stripe))
        XCTAssertFalse(DemoKlub.prodajaNedosegljiva(isDemo: false, jeAdmin: false, nacin: .neznan))
    }

    func testMeIsAdminSamoZaVlogoAdmin() throws {
        func me(_ vloga: String) throws -> Me {
            try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "abc", "role": "\#(vloga)"}"#)
        }
        XCTAssertTrue(try me("admin").isAdmin)
        XCTAssertFalse(try me("user").isAdmin)
        XCTAssertFalse(try me("business").isAdmin)
    }

    // MARK: - 409 demo_club

    func testLastnoSporociloVUserMessageInNakupUserMessage() {
        XCTAssertEqual(napaka.userMessage, sporocilo)
        XCTAssertEqual(napaka.nakupUserMessage, sporocilo)
        XCTAssertNotEqual(napaka.userMessage, String(localized: "This is already in use."))
        // Prepoznava po kodi, ne samo po sporocilu strezniku.
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"demo_club"}"#).userMessage, sporocilo)
    }

    func testSamo409SeStejeZaDemoKlub() {
        XCTAssertTrue(napaka.jeDemoKlub)
        XCTAssertFalse(APIError.requestFailed(400, telo).jeDemoKlub)
        XCTAssertFalse(APIError.requestFailed(409, "Already booked").jeDemoKlub)
        XCTAssertFalse(APIError.requestFailed(409, #"{"error":"seller_incomplete"}"#).jeDemoKlub)
        XCTAssertNotEqual(APIError.requestFailed(409, #"{"error":"seller_incomplete"}"#).userMessage, sporocilo)
    }

    func testNiNerazresenIzidKljucaInTlorisSeNeOsvezi() {
        XCTAssertEqual(napaka.nakupniIzid, .navadna)
        XCTAssertNil(napaka.nakupPremorNanosekund)
        XCTAssertFalse(napaka.jeBrezplacnaMeja)
        XCTAssertFalse(napaka.jeProdajalecNepopoln)
        XCTAssertFalse(napaka.osveziTlorisPoNapaki)
        XCTAssertTrue(APIError.requestFailed(409, "Already booked").osveziTlorisPoNapaki)
    }

    // MARK: - Dashboard lastnika

    func testRazlogDemoKlubVDashboardu() {
        XCTAssertEqual(RazlogNedosegljivosti("demo_club"), .demoKlub)
        XCTAssertEqual(RazlogNedosegljivosti.demoKlub.besedilo(jeLastnik: true), sporocilo)
        XCTAssertEqual(RazlogNedosegljivosti.demoKlub.besedilo(jeLastnik: false), sporocilo)
        // Obstojece razloge ni spremenilo.
        XCTAssertEqual(RazlogNedosegljivosti("seller_incomplete"), .prodajalecNepopoln)
        XCTAssertEqual(RazlogNedosegljivosti(nil), .stripeNiPripravljen)
    }
}
