import XCTest
import Foundation
@testable import Outly

/// 503 ob navali pri nakupu (outly-backend #111), opis dogodka iz lahkega seznama in vnos Instagrama kluba.
final class NavalInUrejanjeKlubaTests: XCTestCase {

    // MARK: - 503 pri nakupu

    func testNavalJe503BrezZnanegaBesedila() {
        XCTAssertTrue(APIError.requestFailed(503, "").jeNavalNakupa)
        XCTAssertTrue(APIError.requestFailed(503, "Server busy. Please try again.").jeNavalNakupa)
    }

    func testPlacilaInPrijavaStaDrugi503() {
        XCTAssertFalse(APIError.requestFailed(503, "Payments are not available yet.").jeNavalNakupa)
        XCTAssertFalse(APIError.requestFailed(503, "Auth service unavailable.").jeNavalNakupa)
    }

    func testDrugeKodeNisoNaval() {
        for koda in [400, 401, 403, 404, 409, 429, 500, 502, -1] {
            XCTAssertFalse(APIError.requestFailed(koda, "").jeNavalNakupa)
        }
        XCTAssertFalse(URLError(.timedOut).jeNavalNakupa)
    }

    func testNakupSporociloZaNavalInSplosnoZa503Drugje() {
        let naval = APIError.requestFailed(503, "").nakupUserMessage
        XCTAssertFalse(naval.isEmpty)
        // userMessage (drugi zasloni) za 503 ostane splosen.
        XCTAssertNotEqual(APIError.requestFailed(503, "").userMessage, naval)
        // Ne-naval ostane pri userMessage.
        XCTAssertEqual(APIError.requestFailed(409, "Already booked").nakupUserMessage, APIError.requestFailed(409, "Already booked").userMessage)
    }

    // MARK: - Opis iz GET /events/:id

    func testEventPlanInfoDescriptionDefaultsToEmpty() throws {
        let brez = try JSONDecoder().decode(EventPlanInfo.self, from: Data(#"{"id": 1}"#.utf8))
        XCTAssertEqual(brez.description, "")
        let z = try JSONDecoder().decode(EventPlanInfo.self, from: Data(#"{"id": 1, "description": "Opis večera"}"#.utf8))
        XCTAssertEqual(z.description, "Opis večera")
        let nul = try JSONDecoder().decode(EventPlanInfo.self, from: Data(#"{"description": null}"#.utf8))
        XCTAssertEqual(nul.description, "")
    }

    // MARK: - Instagram kluba

    func testInstagramNormalizacija() {
        XCTAssertEqual(InstagramVnos.normaliziraj(""), "")
        XCTAssertEqual(InstagramVnos.normaliziraj("   "), "")
        XCTAssertEqual(InstagramVnos.normaliziraj("velvet.lj"), "@velvet.lj")
        XCTAssertEqual(InstagramVnos.normaliziraj("  @velvet_lj "), "@velvet_lj")
        XCTAssertEqual(InstagramVnos.normaliziraj("https://instagram.com/velvet.lj"), "https://instagram.com/velvet.lj")
    }

    func testInstagramZavrneNeveljavno() {
        XCTAssertNil(InstagramVnos.normaliziraj("@"))
        XCTAssertNil(InstagramVnos.normaliziraj("ime s presledkom"))
        XCTAssertNil(InstagramVnos.normaliziraj("@ime!"))
        XCTAssertNil(InstagramVnos.normaliziraj("http://instagram.com/x"))
        XCTAssertNil(InstagramVnos.normaliziraj("https://instagram.com/a b"))
        XCTAssertNil(InstagramVnos.normaliziraj(String(repeating: "a", count: 31)))
    }
}
