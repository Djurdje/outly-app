import XCTest
import Foundation
@testable import Outly

/// Klub brez popolnih podatkov prodajalca (outly-backend#219): 409 `{"error":"seller_incomplete","message":"…"}` na
/// POST /events/:id/orders in /events/:id/tables/:tableId/orders. Lastno sporocilo v OBEH poteh (`userMessage`, `nakupUserMessage`),
/// ne splosni 409 »already in use«; narocilo ni nastalo, zato kljuc ostane (kot pri `free_limit`) in tloris se ne osvezi.
@MainActor
final class ProdajalecNepopolenTests: XCTestCase {

    private let telo = #"{"error":"seller_incomplete","message":"This organizer has not completed seller details yet. Purchase is not available."}"#
    private var napaka: APIError { .requestFailed(409, telo) }
    private let sporocilo = String(localized: "Purchases aren't available yet: the organizer hasn't completed their seller details.")

    func testDaLastnoSporociloVUserMessageInNakupUserMessage() {
        XCTAssertEqual(napaka.userMessage, sporocilo)
        XCTAssertEqual(napaka.nakupUserMessage, sporocilo)
        XCTAssertNotEqual(napaka.userMessage, String(localized: "This is already in use."))
        XCTAssertNotEqual(napaka.userMessage, telo)
    }

    func testDrug409OstaneNespremenjen() {
        let drug = APIError.requestFailed(409, #"{"error":"something_else"}"#)
        XCTAssertEqual(drug.userMessage, String(localized: "This is already in use."))
        XCTAssertEqual(drug.nakupUserMessage, drug.userMessage)
        XCTAssertEqual(APIError.requestFailed(409, "Already booked").userMessage, String(localized: "This table is already booked."))
        XCTAssertEqual(APIError.requestFailed(409, "Already booked").nakupUserMessage, String(localized: "This table is already booked."))
        XCTAssertFalse(drug.jeProdajalecNepopoln)
        XCTAssertFalse(APIError.requestFailed(409, "Already booked").jeProdajalecNepopoln)
    }

    func testSamo409SeStejeZaProdajalecNepopoln() {
        XCTAssertTrue(napaka.jeProdajalecNepopoln)
        XCTAssertFalse(APIError.requestFailed(400, telo).jeProdajalecNepopoln)
    }

    func testNiNerazresenIzidKljucaInTlorisSeNeOsvezi() {
        // Narocilo ni nastalo: ne »v obdelavi«, ne »neaktivno«, ne »nejasen« -> navadna napaka, kljuc ostane.
        XCTAssertEqual(napaka.nakupniIzid, .navadna)
        XCTAssertNil(napaka.nakupPremorNanosekund)
        XCTAssertFalse(napaka.jeBrezplacnaMeja)
        XCTAssertFalse(napaka.osveziTlorisPoNapaki)
        // Primerjava: splosni 409 (miza prodana ...) tloris osvezi.
        XCTAssertTrue(APIError.requestFailed(409, "Already booked").osveziTlorisPoNapaki)
    }

    func testKljucOstaneInPonovenPritiskJeIstiNakup() {
        var kljuc = NakupniKljuc(ustvari: { UUID().uuidString })
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = kljuc.zaNakup(vsebina)
        kljuc.poNapaki(napaka.nakupniIzid)
        XCTAssertEqual(kljuc.zaNakup(vsebina), k1)
    }
}
