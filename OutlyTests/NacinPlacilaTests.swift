import XCTest
import Foundation
@testable import Outly

/// `payment_mode` (backend#203): dekodiranje (star backend polja ne poslje), razvrstitev in kdaj se kaze napis »Test mode«.
@MainActor
final class NacinPlacilaTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testRazvrstitev() {
        XCTAssertEqual(NacinPlacila(nil), .neznan)
        XCTAssertEqual(NacinPlacila("test"), .test)
        XCTAssertEqual(NacinPlacila("stripe"), .stripe)
        XCTAssertEqual(NacinPlacila("unavailable"), .nedosegljivo)
        XCTAssertEqual(NacinPlacila("kaj-novega"), .stripe)   // neznana vrednost: napisa o brezplacnem nakupu ne kazemo
    }

    func testTestniNapis() {
        // star backend: kot doslej
        XCTAssertTrue(NacinPlacila.neznan.kazeTestniNapis(brezplacno: false))
        XCTAssertTrue(NacinPlacila.neznan.kazeTestniNapis(brezplacno: true))
        // test: samo pri ceni > 0
        XCTAssertTrue(NacinPlacila.test.kazeTestniNapis(brezplacno: false))
        XCTAssertFalse(NacinPlacila.test.kazeTestniNapis(brezplacno: true))
        // stripe, unavailable: nikoli
        XCTAssertFalse(NacinPlacila.stripe.kazeTestniNapis(brezplacno: false))
        XCTAssertFalse(NacinPlacila.nedosegljivo.kazeTestniNapis(brezplacno: false))
    }

    func testSamoNedosegljivoBlokiraProdajo() {
        XCTAssertTrue(NacinPlacila.nedosegljivo.prodajaNedosegljiva)
        for n in [NacinPlacila.test, .stripe, .neznan] { XCTAssertFalse(n.prodajaNedosegljiva) }
    }

    func testDogodekDekodiraPaymentModeInStarBackendDaNil() throws {
        let e = try decode(APIEvent.self, #"{"id": 1, "payment_mode": "stripe"}"#)
        XCTAssertEqual(e.paymentMode, "stripe")
        XCTAssertEqual(e.nacinPlacila, .stripe)
        let star = try decode(APIEvent.self, #"{"id": 1}"#)
        XCTAssertNil(star.paymentMode)
        XCTAssertEqual(star.nacinPlacila, .neznan)
        XCTAssertNil(try decode(APIEvent.self, #"{"id": 1, "payment_mode": 3}"#).paymentMode)   // napacen tip ne podre seznama
    }

    func testVipOdgovorDekodiraPaymentMode() throws {
        let v = try decode(EventVip.self, #"{"event_id": 1, "enabled": true, "on_sale": true, "currency": "EUR", "payment_mode": "unavailable"}"#)
        XCTAssertEqual(v.paymentMode, "unavailable")
        XCTAssertNil(try decode(EventVip.self, #"{"event_id": 1}"#).paymentMode)
    }

    func testDashboardNapisTemeljiNaPaymentModeSicerNaMode() throws {
        let osnova = #""summary": {"gross_cents": 0, "fee_cents": 0, "net_cents": 0, "tickets_sold": 0, "orders": 0, "buyers": 0, "gross_7d_cents": 0, "tickets_7d": 0}"#
        // novi backend: payment_mode odloca (globalni mode je lahko "test", klub pa ima Stripe)
        let stripe = try decode(BusinessSales.self, #"{"mode": "test", "payment_mode": "stripe", \#(osnova)}"#)
        XCTAssertFalse(stripe.jeTestni)
        let test = try decode(BusinessSales.self, #"{"mode": "stripe", "payment_mode": "test", \#(osnova)}"#)
        XCTAssertTrue(test.jeTestni)
        let nedosegljivo = try decode(BusinessSales.self, #"{"mode": "stripe", "payment_mode": "unavailable", \#(osnova)}"#)
        XCTAssertFalse(nedosegljivo.jeTestni)
        // star backend: kot doslej po `mode`
        XCTAssertTrue(try decode(BusinessSales.self, #"{"mode": "test", \#(osnova)}"#).jeTestni)
        XCTAssertFalse(try decode(BusinessSales.self, #"{"mode": "stripe", \#(osnova)}"#).jeTestni)
    }

    func testDashboardOpozoriloSamoPriUnavailable() throws {
        let osnova = #""summary": {"gross_cents": 0, "fee_cents": 0, "net_cents": 0, "tickets_sold": 0, "orders": 0, "buyers": 0, "gross_7d_cents": 0, "tickets_7d": 0}"#
        XCTAssertTrue(try decode(BusinessSales.self, #"{"mode": "stripe", "payment_mode": "unavailable", \#(osnova)}"#).nacinPlacila.prodajaNedosegljiva)
        XCTAssertFalse(try decode(BusinessSales.self, #"{"mode": "stripe", "payment_mode": "stripe", \#(osnova)}"#).nacinPlacila.prodajaNedosegljiva)
        XCTAssertFalse(try decode(BusinessSales.self, #"{"mode": "stripe", \#(osnova)}"#).nacinPlacila.prodajaNedosegljiva)
    }

    // MARK: - payment_unavailable_reason (backend#221)

    private let osnovaProdaje = #""summary": {"gross_cents": 0, "fee_cents": 0, "net_cents": 0, "tickets_sold": 0, "orders": 0, "buyers": 0, "gross_7d_cents": 0, "tickets_7d": 0}"#

    func testRazlogDekodiranjePrisotnoManjkaNull() throws {
        let prisoten = try decode(BusinessSales.self, #"{"mode": "live", "payment_mode": "unavailable", "payment_unavailable_reason": "seller_incomplete", \#(osnovaProdaje)}"#)
        XCTAssertEqual(prisoten.paymentUnavailableReason, "seller_incomplete")
        XCTAssertEqual(prisoten.razlogNedosegljivosti, .prodajalecNepopoln)

        let star = try decode(BusinessSales.self, #"{"mode": "live", "payment_mode": "unavailable", \#(osnovaProdaje)}"#)   // star backend: polja ni
        XCTAssertNil(star.paymentUnavailableReason)
        XCTAssertEqual(star.razlogNedosegljivosti, .stripeNiPripravljen)

        let nic = try decode(BusinessSales.self, #"{"mode": "live", "payment_mode": "stripe", "payment_unavailable_reason": null, \#(osnovaProdaje)}"#)
        XCTAssertNil(nic.paymentUnavailableReason)

        let napacenTip = try decode(BusinessSales.self, #"{"mode": "live", "payment_unavailable_reason": 3, \#(osnovaProdaje)}"#)   // napacen tip ne podre dashboarda
        XCTAssertNil(napacenTip.paymentUnavailableReason)
    }

    func testRazlogIzbiraBesedila() {
        XCTAssertEqual(RazlogNedosegljivosti("seller_incomplete"), .prodajalecNepopoln)
        XCTAssertEqual(RazlogNedosegljivosti("payments_not_configured"), .placilaNenastavljena)
        XCTAssertEqual(RazlogNedosegljivosti("stripe_not_ready"), .stripeNiPripravljen)
        // nil in neznana vrednost: obstojece besedilo (vedenje se ne spremeni)
        XCTAssertEqual(RazlogNedosegljivosti(nil), .stripeNiPripravljen)
        XCTAssertEqual(RazlogNedosegljivosti("kaj-novega"), .stripeNiPripravljen)
        XCTAssertEqual(RazlogNedosegljivosti(""), .stripeNiPripravljen)
        // vsak razlog ima svoje besedilo (neodvisno od jezika naprave)
        let besedila = Set([RazlogNedosegljivosti.prodajalecNepopoln, .placilaNenastavljena, .stripeNiPripravljen].map(\.besedilo))
        XCTAssertEqual(besedila.count, 3)
    }
}
