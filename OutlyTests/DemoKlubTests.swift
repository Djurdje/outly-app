import XCTest
import Foundation
@testable import Outly

/// Demo klubi (outly-backend#243): `is_demo` na klubih in dogodkih se se dekodira (star backend -> false), 409 `demo_club` ne
/// sproži osvezitve tlorisa in ni nerazresen izid kljuca. Demo prikazov v aplikaciji ni vec (5. 11. 2026).
@MainActor
final class DemoKlubTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let telo = #"{"error":"demo_club","message":"This is a demo club. Tickets can't be bought."}"#
    private var napaka: APIError { .requestFailed(409, telo) }

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

    // MARK: - 409 demo_club

    func testSamo409SeStejeZaDemoKlub() {
        XCTAssertTrue(napaka.jeDemoKlub)
        XCTAssertFalse(APIError.requestFailed(400, telo).jeDemoKlub)
        XCTAssertFalse(APIError.requestFailed(409, "Already booked").jeDemoKlub)
        XCTAssertFalse(APIError.requestFailed(409, #"{"error":"seller_incomplete"}"#).jeDemoKlub)
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

    func testRazlogDemoKlubaPadeNaObstojeceBesedilo() {
        // `demo_club` ni vec posebna veja (brez demo prikazov): kot neznan razlog.
        XCTAssertEqual(RazlogNedosegljivosti("demo_club"), .stripeNiPripravljen)
        // Obstojece razloge ni spremenilo.
        XCTAssertEqual(RazlogNedosegljivosti("seller_incomplete"), .prodajalecNepopoln)
        XCTAssertEqual(RazlogNedosegljivosti(nil), .stripeNiPripravljen)
    }
}
