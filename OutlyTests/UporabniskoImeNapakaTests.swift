import XCTest
import Foundation
@testable import Outly

/// Prepovedano uporabnisko ime (PATCH /me, outly-backend#218, Apple App Review 1.2):
/// 400 `{"error":"username_not_allowed"}` mora dobiti lastno sporocilo, ne splosnega 400.
final class UporabniskoImeNapakaTests: XCTestCase {

    func testPrepovedanoImeDobiLastnoSporocilo() {
        let napaka = APIError.requestFailed(400, #"{"error":"username_not_allowed"}"#)
        XCTAssertEqual(napaka.userMessage, String(localized: "That username isn't allowed. Choose another."))
        XCTAssertNotEqual(napaka.userMessage, String(localized: "Please check what you entered and try again."))
    }

    func testSplosni400OstaneSplosen() {
        let napaka = APIError.requestFailed(400, #"{"error":"something_else"}"#)
        XCTAssertEqual(napaka.userMessage, String(localized: "Please check what you entered and try again."))
    }

    func testDrugaUporabniskaImenaNapakeOstanejoNespremenjena() {
        XCTAssertEqual(APIError.requestFailed(409, "Username already in use").userMessage,
                       String(localized: "That username is already taken."))
        XCTAssertEqual(APIError.requestFailed(400, "Username too short").userMessage,
                       String(localized: "Username must be at least 3 characters."))
    }
}
