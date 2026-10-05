import XCTest
import Foundation
@testable import Outly

/// Prenos vstopnice prijatelju brez racuna (5. 10. 2026): `Me.canTransferToGuest`, telo zahtevka in napake streznika.
@MainActor
final class PrenosGostuTests: XCTestCase {

    private func decodeMe(_ extra: String) throws -> Me {
        let json = """
        { "id": 1, "email": "test@outly.si", "username": "tester"\(extra) }
        """
        return try JSONDecoder().decode(Me.self, from: Data(json.utf8))
    }

    func testCanTransferToGuestDefaultsToFalse() throws {
        XCTAssertFalse(try decodeMe("").canTransferToGuest)
    }

    func testCanTransferToGuestReadFromResponse() throws {
        XCTAssertTrue(try decodeMe(", \"can_transfer_to_guest\": true").canTransferToGuest)
        XCTAssertFalse(try decodeMe(", \"can_transfer_to_guest\": false").canTransferToGuest)
    }

    func testCanTransferToGuestSurvivesEncodeDecode() throws {
        let me = try decodeMe(", \"can_transfer_to_guest\": true")
        let back = try JSONDecoder().decode(Me.self, from: JSONEncoder().encode(me))
        XCTAssertTrue(back.canTransferToGuest)
    }

    func testBodyWithoutGuestHasEmailAndAgeConfirmedOnly() {
        let telo = APIClient.prenosTelo(email: "a@b.si", allowGuest: false, ageConfirmed: true)
        XCTAssertEqual(Set(telo.keys), ["email", "age_confirmed"])
        XCTAssertEqual(telo["email"] as? String, "a@b.si")
        XCTAssertEqual(telo["age_confirmed"] as? Bool, true)
    }

    func testBodyWithGuestSendsAllowGuestAndAgeConfirmed() {
        let telo = APIClient.prenosTelo(email: "a@b.si", allowGuest: true, ageConfirmed: true)
        XCTAssertEqual(Set(telo.keys), ["email", "allow_guest", "age_confirmed"])
        XCTAssertEqual(telo["allow_guest"] as? Bool, true)
        XCTAssertEqual(telo["age_confirmed"] as? Bool, true)
        let brez = APIClient.prenosTelo(email: "a@b.si", allowGuest: true, ageConfirmed: false)
        XCTAssertEqual(brez["age_confirmed"] as? Bool, false)
    }

    func testGuestTransferErrorCodesGetFriendlyMessages() {
        let starost = APIError.requestFailed(400, "{\"error\":\"age_confirmation_required\",\"min_age\":18}")
        XCTAssertEqual(starost.userMessage, "Confirm that your friend is old enough for this event.")
        let izklop = APIError.requestFailed(403, "{\"error\":\"guest_transfer_disabled\",\"message\":\"x\"}")
        XCTAssertEqual(izklop.userMessage, "Sending tickets to people without an Outly account is not available yet.")
    }
}
