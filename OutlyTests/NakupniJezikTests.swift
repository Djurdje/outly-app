import XCTest
import Foundation
@testable import Outly

/// `locale` v telesu nakupnih klicev (Stripe Checkout se odpre v jeziku APLIKACIJE): "sl" za slovenscino, sicer "en".
/// Star backend polje spregleda, novi ga posreduje Stripu.
@MainActor
final class NakupniJezikTests: XCTestCase {

    func testSlovenscinaDaSl() {
        XCTAssertEqual(Jezik.stripeLocale("sl"), "sl")
    }

    func testAnglescinaInVseDrugoDaEn() {
        XCTAssertEqual(Jezik.stripeLocale("en"), "en")
        XCTAssertEqual(Jezik.stripeLocale("de"), "en")
        XCTAssertEqual(Jezik.stripeLocale(""), "en")
    }

    func testVsakPodprtJezikDaVeljavenLocale() {
        for koda in Jezik.podprti {
            XCTAssertTrue(["sl", "en"].contains(Jezik.stripeLocale(koda)), "jezik \(koda)")
        }
    }

    func testTeloVstopnicNosiKolicinoInLocale() {
        let telo = APIClient.telesoNakupaVstopnic(quantity: 3, locale: "sl")
        XCTAssertEqual(telo["quantity"] as? Int, 3)
        XCTAssertEqual(telo["locale"] as? String, "sl")
        XCTAssertEqual(telo.count, 2)
    }

    func testTeloMizeBrezPaketaInCeneImaSamoLocale() {
        let telo = APIClient.telesoNakupaMize(packageId: nil, expectedPriceCents: nil, locale: "en")
        XCTAssertEqual(telo["locale"] as? String, "en")
        XCTAssertNil(telo["package_id"])
        XCTAssertNil(telo["expected_price_cents"])
        XCTAssertEqual(telo.count, 1)
    }

    func testTeloMizeNosiPaketCenoInLocale() {
        let telo = APIClient.telesoNakupaMize(packageId: 7, expectedPriceCents: 25000, locale: "sl")
        XCTAssertEqual(telo["package_id"] as? Int, 7)
        XCTAssertEqual(telo["expected_price_cents"] as? Int, 25000)
        XCTAssertEqual(telo["locale"] as? String, "sl")
    }

    func testPonovitevMizeIstegaNakupaPosljeIstoTelo() {
        // »Continue to payment« (isti Idempotency-Key): vsebina in locale sta enaka prvemu poskusu.
        let prvo = APIClient.telesoNakupaMize(packageId: 7, expectedPriceCents: 25000, locale: "sl")
        let ponovitev = APIClient.telesoNakupaMize(packageId: 7, expectedPriceCents: 25000, locale: "sl")
        XCTAssertEqual(NSDictionary(dictionary: prvo), NSDictionary(dictionary: ponovitev))
    }

    func testLocaleGreVJsonTelesZahtevka() throws {
        let r = try APIClient.shared.sestaviZahtevek(
            path: "events/12/orders", method: "POST", token: "tok",
            json: APIClient.telesoNakupaVstopnic(quantity: 2, locale: "sl"),
            query: [], clubId: nil, timeout: nil, idempotencyKey: "k-1", dodatneGlave: APIClient.nakupneGlave)
        let telo = try XCTUnwrap(r.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: telo) as? [String: Any])
        XCTAssertEqual(json["locale"] as? String, "sl")
        XCTAssertEqual(json["quantity"] as? Int, 2)
    }
}
