import XCTest
import Foundation
@testable import Outly

/// Sporocila napak nakupne poti (ZVPot-1 7/1, outly-backend#100): strezniski angleski niz se nikoli ne pokaze surov, ampak gre skozi
/// lokalizacijo. Testi tece v angleskem jeziku (privzeto), zato preverjajo izbiro sporocila in vrednost iz sporocila (meja starosti).
@MainActor
final class NakupnaSporocilaTests: XCTestCase {

    private func sporocilo(_ koda: Int, _ besedilo: String) -> String {
        APIError.requestFailed(koda, besedilo).userMessage
    }

    func testMejaStarostiIzSporocilaBrezSurovegaStreznikovegaNiza() {
        XCTAssertEqual(sporocilo(403, "You must be at least 18 to buy tickets for this event."),
                       "You must be at least 18 to buy tickets for this event.")
        XCTAssertEqual(sporocilo(403, "You must be at least 21 to buy tickets for this event."),
                       "You must be at least 21 to buy tickets for this event.")
    }

    func testMejaStarostiPriVipMiziSPaketom() {
        XCTAssertEqual(sporocilo(403, "You must be at least 18 to buy a table with a bottle package."),
                       "You must be at least 18 to buy a table with a bottle package.")
    }

    func testStarostBrezStevilkeDobiSplosnoSporocilo() {
        XCTAssertEqual(sporocilo(403, "You must be at least old enough."), "You are too young to buy this.")
    }

    func testNakupBrezDatumaRojstvaPokazePravoNavodilo() {
        // Prej ga je splosni blok »date of birth« pocistil v »Enter a valid date of birth.«
        XCTAssertEqual(sporocilo(403, "Add your date of birth to buy tickets for this event."),
                       "Add your date of birth in Personal info to buy tickets.")
        XCTAssertEqual(sporocilo(403, "Add your date of birth to buy a table with a bottle package."),
                       "Add your date of birth in Personal info to buy tickets.")
    }

    func testPopravljanjeDatumaRojstvaOstaneSplosno() {
        XCTAssertEqual(sporocilo(400, "dateOfBirth cannot be in the future."), "Date of birth cannot be in the future.")
        XCTAssertEqual(sporocilo(400, "Invalid date of birth."), "Enter a valid date of birth.")
    }

    func testKlubBrezSpletnegaPlacilaNiVecSplosnoZeVUporabi() {
        XCTAssertEqual(sporocilo(409, "This club does not accept online payments yet."),
                       "This club doesn't accept online payments yet.")
    }
}
