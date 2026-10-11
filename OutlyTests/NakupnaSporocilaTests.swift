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

    /// Strezniski niz se mora RAZLIKOVATI od izhoda (velike crke, brez pike), sicer bi test presel tudi pri `return raw`.
    func testMejaStarostiGreSkozLokaliziranKljucNeSurovNiz() {
        let surov = "YOU MUST BE AT LEAST 21 TO BUY TICKETS FOR THIS EVENT"
        let izhod = sporocilo(403, surov)
        XCTAssertNotEqual(izhod, surov)
        XCTAssertEqual(izhod, String(localized: "You must be at least \(21) to buy tickets for this event."))
        XCTAssertEqual(sporocilo(403, "Hey! You must be at least 18 to buy tickets for this event"),
                       String(localized: "You must be at least \(18) to buy tickets for this event."))
    }

    func testMejaStarostiPriVipMiziSPaketomGreSkozLokaliziranKljuc() {
        let surov = "YOU MUST BE AT LEAST 18 TO BUY A TABLE WITH A BOTTLE PACKAGE"
        let izhod = sporocilo(403, surov)
        XCTAssertNotEqual(izhod, surov)
        XCTAssertEqual(izhod, String(localized: "You must be at least \(18) to buy a table with a bottle package."))
    }

    func testStarostBrezStevilkeDobiSplosnoSporocilo() {
        XCTAssertEqual(sporocilo(403, "You must be at least old enough."), "You are too young to buy this.")
    }

    func testNakupBrezDatumaRojstvaPokazePravoNavodilo() {
        // Prej ga je splosni blok »date of birth« pocistil v »Enter a valid date of birth.«
        XCTAssertEqual(sporocilo(403, "Add your date of birth to buy tickets for this event."),
                       "Add your date of birth in Personal info to buy tickets.")
        XCTAssertEqual(sporocilo(403, "Add your date of birth to buy a table with a bottle package."),
                       "Add your date of birth in Personal info to buy a table with a bottle package.")
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
