import XCTest
import Foundation
@testable import Outly

/// Placilo VIP mize na vratih (backend 23. 10. 2026): `vip_payment`, `payment`, `hold.source`, rezervacija kupca, `vip_reservations`.
/// Vsa nova polja imajo privzetek: star backend jih ne poslje.
@MainActor
final class VipVrataTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testStarBackendPrivzetoPlaciloVAplikaciji() throws {
        let e = try decode(APIEvent.self, #"{"id": 1}"#)
        XCTAssertEqual(e.vipPayment, "app")
        XCTAssertEqual(e.vipReservations, 0)
        let v = try decode(EventVip.self, #"{"event_id": 1}"#)
        XCTAssertEqual(v.vipPayment, "app")
        XCTAssertFalse(v.placiloNaVratih)
        let b = try decode(BusinessEventVip.self, #"{"event_id": 1}"#)
        XCTAssertEqual(b.payment, "app")
    }

    func testPlaciloNaVratihInNeznanaVrednost() throws {
        XCTAssertTrue(try decode(EventVip.self, #"{"event_id": 1, "vip_payment": "door"}"#).placiloNaVratih)
        XCTAssertEqual(try decode(EventVip.self, #"{"event_id": 1, "vip_payment": "kaj-novega"}"#).vipPayment, "app")
        XCTAssertEqual(try decode(APIEvent.self, #"{"id": 1, "vip_payment": "door", "vip_reservations": 3}"#).vipReservations, 3)
        XCTAssertEqual(try decode(BusinessEventVip.self, #"{"event_id": 1, "payment": "door"}"#).payment, "door")
    }

    func testHoldPoTelefonuInIzAplikacije() throws {
        let telefon = try decode(VipHold.self, #"{"guest_name": "Ana", "note": "6 guests", "created_at": "2026-10-23T10:00:00Z"}"#)
        XCTAssertEqual(telefon.source, "phone")
        XCTAssertFalse(telefon.jeIzAplikacije)
        XCTAssertNil(telefon.priceCents)
        XCTAssertNil(telefon.prikazanoUporabniskoIme)

        let app = try decode(VipHold.self, """
        {"guest_name": "Luka", "source": "app", "username": "luka_x", "package_name": "Jameson 0,7 l",
         "package_description": "z mesalci", "price_cents": 25000, "created_at": "2026-10-23T10:00:00Z"}
        """)
        XCTAssertTrue(app.jeIzAplikacije)
        XCTAssertEqual(app.prikazanoUporabniskoIme, "@luka_x")
        XCTAssertEqual(app.packageName, "Jameson 0,7 l")
        XCTAssertEqual(app.priceCents, 25000)
    }

    func testBookingTotalCents() throws {
        let b = try decode(VipBooking.self, #"{"order_id": 1, "buyer_username": "ana", "total_cents": 30000}"#)
        XCTAssertEqual(b.totalCents, 30000)
        XCTAssertNil(try decode(VipBooking.self, #"{"order_id": 1}"#).totalCents)   // star backend
    }

    func testRezervacijaKupcaDekodira() throws {
        let r = try decode(TableReservation.self, """
        {"id": 12, "event_id": 35, "event_title": "QUICKIE", "event_start_at": "2999-01-01T20:00:00.000Z", "club_id": 6,
         "club_name": "Outly", "table_id": 4, "table_label": "T4", "seats": 6, "package_id": 2, "package_name": "Jameson 0,7 l",
         "package_description": "", "price_cents": 25000, "currency": "EUR", "guest_name": "Luka", "created_at": "2026-10-23T10:00:00Z"}
        """)
        XCTAssertEqual(r.id, 12)
        XCTAssertEqual(r.tableLabel, "T4")
        XCTAssertEqual(r.priceCents, 25000)
        XCTAssertNotNil(r.znesekNaVratih)
        XCTAssertTrue(r.jeMogocPreklic())
        // Prazen objekt: privzetki, brez preklica (datum neberljiv).
        let prazna = try decode(TableReservation.self, "{}")
        XCTAssertEqual(prazna.priceCents, 0)
        XCTAssertNil(prazna.znesekNaVratih)
        XCTAssertFalse(prazna.jeMogocPreklic())
    }

    func testTelesaKlicev() {
        let brezPaketa = APIClient.telesoRezervacijeMize(packageId: nil, guestName: "  ", expectedPriceCents: 25000)
        XCTAssertTrue(brezPaketa["package_id"] is NSNull)
        XCTAssertNil(brezPaketa["guest_name"])
        XCTAssertEqual(brezPaketa["expected_price_cents"] as? Int, 25000)

        let spaketom = APIClient.telesoRezervacijeMize(packageId: 2, guestName: " Luka ", expectedPriceCents: nil)
        XCTAssertEqual(spaketom["package_id"] as? Int, 2)
        XCTAssertEqual(spaketom["guest_name"] as? String, "Luka")
        XCTAssertNil(spaketom["expected_price_cents"])

        let dolgo = APIClient.telesoRezervacijeMize(packageId: nil, guestName: String(repeating: "a", count: 100), expectedPriceCents: nil)
        XCTAssertEqual((dolgo["guest_name"] as? String)?.count, TableReservation.najvecImena)

        // PUT /business/events/:id/vip: `tables` ni v telesu (cene in izklopi po mizah se ne povozijo).
        let samoVklop = APIClient.telesoNastavitveVip(enabled: true, payment: nil)
        XCTAssertEqual(samoVklop["enabled"] as? Bool, true)
        XCTAssertNil(samoVklop["payment"])
        XCTAssertNil(samoVklop["tables"])
        XCTAssertEqual(APIClient.telesoNastavitveVip(enabled: true, payment: "door")["payment"] as? String, "door")
    }

    func testRezervacijeDogodkovPrihajajociNajprej() throws {
        let zdaj = Date(timeIntervalSince1970: 1_800_000_000)
        func e(_ id: Int, _ start: String) throws -> APIEvent { try decode(APIEvent.self, #"{"id": \#(id), "start_at": "\#(start)"}"#) }
        let seznam = [try e(1, "2020-01-01T10:00:00.000Z"), try e(2, "2999-02-01T10:00:00.000Z"), try e(3, "2999-01-01T10:00:00.000Z"), try e(4, "2021-01-01T10:00:00.000Z")]
        let urejeni = RezervacijeDogodkiView.uredi(seznam, zdaj: zdaj)
        XCTAssertEqual(urejeni.map(\.id), [3, 2, 4, 1])
    }

    func testNapakeRezervacije() {
        func napaka(_ besedilo: String) -> APIError { .requestFailed(409, besedilo) }
        XCTAssertTrue(napaka(#"{"error":"vip_pay_in_app","message":"x"}"#).osveziTlorisPoRezervaciji)
        XCTAssertTrue(napaka("This table is already booked.").osveziTlorisPoRezervaciji)
        XCTAssertFalse(napaka(#"{"error":"reservation_limit","message":"x"}"#).osveziTlorisPoRezervaciji)
        XCTAssertFalse(napaka(#"{"error":"demo_club","message":"x"}"#).osveziTlorisPoRezervaciji)
        XCTAssertFalse(APIError.requestFailed(500, "").osveziTlorisPoRezervaciji)
        XCTAssertEqual(napaka(#"{"error":"reservation_limit","message":"You already have a table reserved for this event."}"#).userMessage,
                       String(localized: "You already have a table reserved for this event."))
    }
}
