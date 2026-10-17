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

    // MARK: - Starostna meja (PrenosStarosti)

    func testLimitZeroMeansNoCheckbox() {
        XCTAssertEqual(PrenosStarosti.meja(minAge: 0, imaPaket: false, izStrezniku: nil), 0)
    }

    func testLimitIsMinAgeWithoutPackage() {
        XCTAssertEqual(PrenosStarosti.meja(minAge: 16, imaPaket: false, izStrezniku: nil), 16)
    }

    func testPackageRaisesLimitToAtLeast18() {
        XCTAssertEqual(PrenosStarosti.meja(minAge: 0, imaPaket: true, izStrezniku: nil), 18)
        XCTAssertEqual(PrenosStarosti.meja(minAge: 16, imaPaket: true, izStrezniku: nil), 18)
    }

    func testPackageWithHigherMinAgeKeepsMinAge() {
        XCTAssertEqual(PrenosStarosti.meja(minAge: 21, imaPaket: true, izStrezniku: nil), 21)
    }

    func testServerLimitOverrides() {
        XCTAssertEqual(PrenosStarosti.meja(minAge: 0, imaPaket: false, izStrezniku: 18), 18)
        XCTAssertEqual(PrenosStarosti.meja(minAge: 21, imaPaket: true, izStrezniku: 18), 18)
    }

    func testParsesMinAgeFromAgeConfirmationError() {
        let napaka = APIError.requestFailed(400, "{\"error\":\"age_confirmation_required\",\"min_age\":21}")
        XCTAssertEqual(PrenosStarosti.izNapake(napaka), 21)
    }

    func testIgnoresOtherErrors() {
        XCTAssertNil(PrenosStarosti.izNapake(APIError.requestFailed(403, "{\"error\":\"guest_transfer_disabled\"}")))
        XCTAssertNil(PrenosStarosti.izNapake(APIError.requestFailed(400, "{\"error\":\"age_confirmation_required\"}")))
        XCTAssertNil(PrenosStarosti.izNapake(APIError.requestFailed(404, "No Outly account with this email")))
        XCTAssertNil(PrenosStarosti.izNapake(APIError.decodingFailed))
    }

    func testFriendBodyHasUserIdAndAgeConfirmed() {
        let telo = APIClient.prenosTeloPrijatelju(userId: 7, ageConfirmed: true)
        XCTAssertEqual(Set(telo.keys), ["user_id", "age_confirmed"])
        XCTAssertEqual(telo["user_id"] as? Int, 7)
        XCTAssertEqual(telo["age_confirmed"] as? Bool, true)
    }

    // MARK: outly-app#111: izgubljen odgovor + ponovitev

    func testNejasenPoskusJeOmrezjeRokIn5xxNeZavrnitev() {
        XCTAssertTrue(PrenosStarosti.jeNejasenPoskus(URLError(.timedOut)))
        XCTAssertTrue(PrenosStarosti.jeNejasenPoskus(URLError(.networkConnectionLost)))
        XCTAssertTrue(PrenosStarosti.jeNejasenPoskus(APIError.requestFailed(502, "")))
        XCTAssertTrue(PrenosStarosti.jeNejasenPoskus(APIError.requestFailed(-1, "No HTTP response")))
        XCTAssertFalse(PrenosStarosti.jeNejasenPoskus(APIError.requestFailed(429, "")))
        XCTAssertFalse(PrenosStarosti.jeNejasenPoskus(APIError.requestFailed(409, "Ticket was already used.")))
        XCTAssertFalse(PrenosStarosti.jeNejasenPoskus(APIError.requestFailed(400, "Invalid user_id.")))
        XCTAssertFalse(PrenosStarosti.jeNejasenPoskus(URLError(.cancelled)))
    }

    func testTicketNotFoundPoNejasnemPoskusuJeVerjetnoZePoslana() {
        let nf = APIError.requestFailed(404, "Ticket not found.")
        XCTAssertTrue(PrenosStarosti.jeVerjetnoZePoslana(nf, prejsnjiNejasen: true))
        XCTAssertFalse(PrenosStarosti.jeVerjetnoZePoslana(nf, prejsnjiNejasen: false))   // prvi poskus: navadno sporocilo
        // druge 404 in druge napake ne
        XCTAssertFalse(PrenosStarosti.jeVerjetnoZePoslana(APIError.requestFailed(404, "You can only send a ticket by user to one of your friends."),
                                                          prejsnjiNejasen: true))
        XCTAssertFalse(PrenosStarosti.jeVerjetnoZePoslana(APIError.requestFailed(409, "Ticket was already used."), prejsnjiNejasen: true))
        XCTAssertFalse(PrenosStarosti.jeVerjetnoZePoslana(URLError(.timedOut), prejsnjiNejasen: true))
    }
}
