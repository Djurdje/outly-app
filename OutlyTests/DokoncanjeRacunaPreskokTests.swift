import XCTest
import Foundation
@testable import Outly

/// »Skip for later« pri dokoncanju racuna (23. 10. 2026): telo PATCH /me nosi `complete_onboarding` samo, ce je nastavljen
/// (obstojeci klici updateMe ga ne smejo posiljati), in 400 `date_of_birth_required` ima svoje sporocilo (ne »Enter a valid date of birth«).
@MainActor
final class DokoncanjeRacunaPreskokTests: XCTestCase {

    func testBrezPoljaTeloNimaKljuca() {
        var u = APIClient.MeUpdate()
        u.genres = ["house"]
        XCTAssertNil(u.json["complete_onboarding"])
        XCTAssertNil(APIClient.MeUpdate().json["complete_onboarding"])
        XCTAssertTrue(APIClient.MeUpdate().json.isEmpty)
    }

    func testObstojeciKlicNeposljePolja() {
        var u = APIClient.MeUpdate()
        u.sharePlansWithFriends = true
        u.dateOfBirth = "2000-01-01"
        u.country = "SI"
        u.phone = .some(nil)
        XCTAssertEqual(Set(u.json.keys), ["share_plans_with_friends", "dateOfBirth", "country", "phone"])
    }

    func testPreskokPosljeSamoCompleteOnboarding() {
        var u = APIClient.MeUpdate()
        u.completeOnboarding = true
        XCTAssertEqual(Set(u.json.keys), ["complete_onboarding"])
        XCTAssertEqual(u.json["complete_onboarding"] as? Bool, true)
    }

    func testContinueNosiZanreInComplete() {
        var u = APIClient.MeUpdate()
        u.genres = ["house", "techno"]
        u.completeOnboarding = true
        XCTAssertEqual(Set(u.json.keys), ["genres", "complete_onboarding"])
    }

    func testDatumRojstvaObvezenSporocilo() {
        let raw = #"{"error":"date_of_birth_required","message":"Date of birth is required."}"#
        let m = APIError.requestFailed(400, raw).userMessage
        XCTAssertEqual(m, String(localized: "Date of birth is required."))
        XCTAssertNotEqual(m, String(localized: "Enter a valid date of birth."))
    }
}
