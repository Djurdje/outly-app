import XCTest
import Foundation
@testable import Outly

/// VIP mize (backend 025): novi modeli in nova polja na starih modelih. Star backend polj nima ->
/// privzete vrednosti, dekodiranje ne sme pasti (CLAUDE.md pravilo 2).
final class VipDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - APIEvent

    func testEventDecodesVipFields() throws {
        let e = try decode(APIEvent.self, #"{"id": 1, "vip_enabled": true, "vip_from_cents": 30000}"#)
        XCTAssertTrue(e.vipEnabled)
        XCTAssertEqual(e.vipFromCents, 30000)
    }

    func testEventDecodesWithoutVipFields() throws {
        let e = try decode(APIEvent.self, #"{"id": 1, "club_id": 3, "title": "Stari dogodek"}"#)
        XCTAssertFalse(e.vipEnabled)
        XCTAssertNil(e.vipFromCents)
    }

    func testEventVipFromCentsNullWhenNotVip() throws {
        let e = try decode(APIEvent.self, #"{"id": 1, "vip_enabled": false, "vip_from_cents": null}"#)
        XCTAssertFalse(e.vipEnabled)
        XCTAssertNil(e.vipFromCents)
    }

    // MARK: - APITicket / APIOrder

    func testVipTicketDecodes() throws {
        let t = try decode(APITicket.self, """
        {"id": 5, "serial": "S", "status": "valid", "qr": "q", "is_vip": true, "table_label": "T1",
         "table_seats": 6, "package_name": "Jameson 0,7 l", "package_description": "4x Red Bull"}
        """)
        XCTAssertTrue(t.isVip)
        XCTAssertEqual(t.tableLabel, "T1")
        XCTAssertEqual(t.tableSeats, 6)
        XCTAssertEqual(t.packageName, "Jameson 0,7 l")
        XCTAssertEqual(t.packageDescription, "4x Red Bull")
    }

    func testOldTicketJsonDecodesAsNonVip() throws {
        let t = try decode(APITicket.self, #"{"id": 2, "serial": "X", "status": "valid", "qr": "q"}"#)
        XCTAssertFalse(t.isVip)
        XCTAssertNil(t.tableLabel)
        XCTAssertNil(t.tableSeats)
        XCTAssertNil(t.packageName)
        XCTAssertNil(t.packageDescription)
    }

    func testTicketWithNullVipFieldsIsNonVip() throws {
        let t = try decode(APITicket.self, """
        {"id": 3, "is_vip": false, "table_label": null, "table_seats": null, "package_name": null, "package_description": null}
        """)
        XCTAssertFalse(t.isVip)
        XCTAssertNil(t.tableLabel)
    }

    func testVipPurchaseResponseDecodes() throws {
        let r = try decode(PurchaseResponse.self, """
        {"mode": "test",
         "order": {"id": 91, "public_ref": "OUT-7K3M9QPX", "quantity": 1, "total_cents": 30000, "currency": "EUR",
                   "is_vip": true, "table_id": 5, "table_label": "T1", "table_seats": 2,
                   "package_name": "Jameson 0,7 l", "package_description": ""},
         "tickets": [{"id": 1, "is_vip": true, "table_label": "T1", "table_seats": 2},
                     {"id": 2, "is_vip": true, "table_label": "T1", "table_seats": 2}]}
        """)
        XCTAssertEqual(r.mode, "test")
        XCTAssertTrue(r.order.isVip)
        XCTAssertEqual(r.order.tableId, 5)
        XCTAssertEqual(r.order.tableLabel, "T1")
        XCTAssertEqual(r.order.totalCents, 30000)
        XCTAssertEqual(r.tickets.count, 2)
        XCTAssertTrue(r.tickets.allSatisfy { $0.isVip })
    }

    func testOldOrderJsonDecodesAsNonVip() throws {
        let o = try decode(APIOrder.self, #"{"id": 4, "quantity": 2}"#)
        XCTAssertFalse(o.isVip)
        XCTAssertNil(o.tableId)
        XCTAssertNil(o.tableLabel)
        XCTAssertNil(o.packageName)
    }

    // MARK: - ScanResult

    func testScanResultDecodesVipTicket() throws {
        let r = try decode(ScanResult.self, """
        {"result": "ok", "message": "Welcome", "used_at": null,
         "ticket": {"is_vip": true, "table_label": "T1", "table_seats": 6, "package_name": "Jameson 0,7 l"}}
        """)
        XCTAssertEqual(r.result, "ok")
        XCTAssertEqual(r.ticket?.isVip, true)
        XCTAssertEqual(VipOznaka.vrstica(tableLabel: r.ticket?.tableLabel, packageName: r.ticket?.packageName),
                       "VIP · \(VipOznaka.miza("T1")) · Jameson 0,7 l")
    }

    func testScanResultWithoutTicketStillDecodes() throws {
        let r = try decode(ScanResult.self, #"{"result": "invalid", "message": "Bad code"}"#)
        XCTAssertEqual(r.result, "invalid")
        XCTAssertNil(r.ticket)
    }

    func testScanResultIgnoresMalformedTicket() throws {
        let r = try decode(ScanResult.self, #"{"result": "ok", "message": "m", "ticket": "not-an-object"}"#)
        XCTAssertEqual(r.result, "ok")
        XCTAssertNil(r.ticket)
    }

    // MARK: - GET /events/:id/vip

    func testEventVipDecodes() throws {
        let v = try decode(EventVip.self, """
        {"event_id": 12, "enabled": true, "on_sale": true, "currency": "EUR",
         "plan": {"width": 24, "height": 16, "elements": [{"type": "stage", "x": 8, "y": 0, "w": 8, "h": 3, "label": ""}]},
         "tables": [{"id": 5, "label": "T1", "x": 2, "y": 5, "w": 2, "h": 2, "shape": "round", "seats": 6,
                     "price_cents": 30000, "available": true},
                    {"id": 6, "label": "T2", "x": 6, "y": 5, "w": 2, "h": 2, "shape": "rect", "seats": 4,
                     "price_cents": 20000, "available": false}],
         "packages": [{"id": 3, "name": "Jameson 0,7 l", "description": "4x Red Bull"}]}
        """)
        XCTAssertTrue(v.isUsable)
        XCTAssertTrue(v.onSale)
        XCTAssertEqual(v.plan?.width, 24)
        XCTAssertEqual(v.plan?.elements.first?.type, "stage")
        XCTAssertEqual(v.tables.count, 2)
        XCTAssertTrue(v.tables[0].available)
        XCTAssertFalse(v.tables[1].available)
        XCTAssertEqual(v.tables[0].priceCents, 30000)
        XCTAssertEqual(v.packages.first?.name, "Jameson 0,7 l")
    }

    func testEventVipDisabledHasNoTables() throws {
        let v = try decode(EventVip.self, #"{"event_id": 12, "enabled": false, "on_sale": false, "currency": "EUR", "plan": null, "tables": [], "packages": []}"#)
        XCTAssertFalse(v.isUsable)
        XCTAssertNil(v.plan)
        XCTAssertTrue(v.tables.isEmpty)
    }

    // MARK: - GET /business/events/:id/vip

    func testBusinessEventVipDecodesBookings() throws {
        let v = try decode(BusinessEventVip.self, """
        {"event_id": 12, "enabled": true, "currency": "EUR",
         "plan": {"width": 24, "height": 16, "elements": []},
         "tables": [
           {"id": 6, "label": "T10", "seats": 4, "price_cents": 20000, "default_price_cents": 20000, "disabled": false, "booking": null},
           {"id": 5, "label": "T2", "seats": 6, "price_cents": 35000, "default_price_cents": 30000, "disabled": false,
            "booking": {"order_id": 91, "public_ref": "OUT-7K3M9QPX", "buyer_username": "ana",
                        "package_name": "Jameson 0,7 l", "package_description": "", "guests": 6, "checked_in": 2,
                        "created_at": "2026-10-01T10:00:00.000Z"}}
         ],
         "packages": []}
        """)
        XCTAssertTrue(v.isSetUp)
        XCTAssertEqual(v.bookings.count, 1)
        XCTAssertEqual(v.bookings.first?.label, "T2")
        XCTAssertEqual(v.bookings.first?.booking?.buyerUsername, "ana")
        XCTAssertEqual(v.bookings.first?.booking?.checkedIn, 2)
        XCTAssertEqual(v.bookings.first?.booking?.guests, 6)
    }

    func testBusinessTableArchivedFlagDefaultsToFalse() throws {
        let nova = try decode(VipBusinessTable.self, #"{"id": 1, "label": "T1", "seats": 4}"#)
        XCTAssertFalse(nova.archived)
        let arh = try decode(VipBusinessTable.self, #"{"id": 2, "label": "T2", "seats": 4, "archived": true}"#)
        XCTAssertTrue(arh.archived)
    }

    func testBookingsShownEvenWhenVipDisabled() throws {
        let v = try decode(BusinessEventVip.self, """
        {"event_id": 12, "enabled": false, "currency": "EUR", "plan": null,
         "tables": [{"id": 5, "label": "T1", "seats": 6, "archived": true,
                     "booking": {"order_id": 1, "buyer_username": "ana", "guests": 6, "checked_in": 0}}],
         "packages": []}
        """)
        XCTAssertFalse(v.isSetUp)
        XCTAssertEqual(v.bookings.count, 1)
    }

    func testBusinessEventVipWithoutPlanIsNotSetUp() throws {
        let v = try decode(BusinessEventVip.self, #"{"event_id": 12, "enabled": true, "currency": "EUR", "plan": null, "tables": [], "packages": []}"#)
        XCTAssertFalse(v.isSetUp)
        XCTAssertTrue(v.bookings.isEmpty)
    }

    // MARK: - Rezervacija po telefonu (hold, 4. 10. 2026)

    func testTableDecodesHoldPresent() throws {
        let m = try decode(VipBusinessTable.self, """
        {"id": 7, "label": "T3", "seats": 4,
         "hold": {"guest_name": "Ana Novak", "note": "6 guests, arriving 23:00", "created_at": "2026-10-04T18:00:00.000Z"}}
        """)
        XCTAssertEqual(m.hold?.guestName, "Ana Novak")
        XCTAssertEqual(m.hold?.note, "6 guests, arriving 23:00")
        XCTAssertEqual(m.hold?.prikazanaOpomba, "6 guests, arriving 23:00")
        XCTAssertEqual(m.hold?.createdAt, "2026-10-04T18:00:00.000Z")
        XCTAssertFalse(m.jeProsta)
    }

    func testTableDecodesHoldNull() throws {
        let m = try decode(VipBusinessTable.self, #"{"id": 7, "label": "T3", "seats": 4, "booking": null, "hold": null}"#)
        XCTAssertNil(m.hold)
        XCTAssertTrue(m.jeProsta)
    }

    func testTableDecodesWithoutHoldField() throws {
        // Star backend polja ne pozna: dekodiranje ne sme pasti.
        let m = try decode(VipBusinessTable.self, #"{"id": 7, "label": "T3", "seats": 4}"#)
        XCTAssertNil(m.hold)
        XCTAssertTrue(m.jeProsta)
    }

    func testHoldWithNullNoteHasNoDisplayNote() throws {
        let m = try decode(VipBusinessTable.self, #"{"id": 7, "label": "T3", "hold": {"guest_name": "Ana", "note": null, "created_at": "x"}}"#)
        XCTAssertNil(m.hold?.note)
        XCTAssertNil(m.hold?.prikazanaOpomba)
        let prazna = try decode(VipHold.self, #"{"guest_name": "Ana", "note": "  "}"#)
        XCTAssertNil(prazna.prikazanaOpomba)
        let brez = try decode(VipHold.self, "{}")
        XCTAssertEqual(brez.guestName, "")
    }

    func testBusinessEventVipListsHoldsAndFreeTables() throws {
        let v = try decode(BusinessEventVip.self, """
        {"event_id": 12, "enabled": true, "currency": "EUR",
         "plan": {"width": 24, "height": 16, "elements": []},
         "tables": [
           {"id": 1, "label": "T10", "seats": 4},
           {"id": 2, "label": "T2", "seats": 4, "hold": {"guest_name": "Ana", "note": null, "created_at": "x"}},
           {"id": 3, "label": "T3", "seats": 6, "booking": {"order_id": 9, "buyer_username": "bor", "guests": 6, "checked_in": 0}},
           {"id": 4, "label": "T4", "seats": 4, "disabled": true},
           {"id": 5, "label": "T5", "seats": 4, "archived": true},
           {"id": 6, "label": "T9", "seats": 4}
         ],
         "packages": []}
        """)
        XCTAssertEqual(v.holds.map(\.label), ["T2"])
        XCTAssertEqual(v.bookings.map(\.label), ["T3"])
        XCTAssertEqual(v.rezervirane.map(\.label), ["T2", "T3"])
        // Prosta = ni arhivirana, prodana ali rezervirana (izklop za spletno prodajo ne velja); po oznaki (T9 pred T10).
        XCTAssertEqual(v.prosteMize.map(\.label), ["T4", "T9", "T10"])
    }

    // MARK: - Oznake

    func testVipOznakaSkipsEmptyParts() {
        XCTAssertEqual(VipOznaka.vrstica(tableLabel: nil, packageName: nil), "VIP")
        XCTAssertEqual(VipOznaka.vrstica(tableLabel: "", packageName: "Absolut"), "VIP · Absolut")
    }

    func testDefaultElementNames() {
        XCTAssertEqual(VipOznaka.privzetNaziv(tip: "dancefloor"), "Dance floor")
        XCTAssertEqual(VipOznaka.privzetNaziv(tip: "wc"), "WC")
        XCTAssertNil(VipOznaka.privzetNaziv(tip: "label"))
        XCTAssertNil(VipOznaka.privzetNaziv(tip: "wall"))
    }
}
