import XCTest
import Foundation
@testable import Outly

/// Razclenitev odgovorov GoTrue (Supabase Auth) -- brez pravih omreznih klicev, samo
/// dekodiranje JSON-a/struktur, kot jih SupabaseAuth.swift dejansko uporablja.
final class SupabaseAuthParsingTests: XCTestCase {

    // MARK: - SupabaseSession (access_token / refresh_token / expires_in)

    func testSupabaseSessionDecodesFromGoTrueTokenResponse() throws {
        let json = """
        {
            "access_token": "eyJhbGciOi.header.payload",
            "token_type": "bearer",
            "expires_in": 3600,
            "expires_at": 1893456000,
            "refresh_token": "v1.MRefreshTokenValue",
            "user": { "id": "uuid-123" }
        }
        """
        let session = try JSONDecoder().decode(SupabaseSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.accessToken, "eyJhbGciOi.header.payload")
        XCTAssertEqual(session.refreshToken, "v1.MRefreshTokenValue")
        XCTAssertEqual(session.expiresIn, 3600)
    }

    /// `expiresIn` je edino neobvezno polje -- ce ga GoTrue ne vrne, dekodiranje ne sme pasti.
    func testSupabaseSessionDecodesWithoutExpiresIn() throws {
        let json = """
        {
            "access_token": "a",
            "refresh_token": "r"
        }
        """
        let session = try JSONDecoder().decode(SupabaseSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.accessToken, "a")
        XCTAssertEqual(session.refreshToken, "r")
        XCTAssertNil(session.expiresIn)
    }

    func testSupabaseSessionMissingAccessTokenFailsToDecode() {
        let json = #"{"refresh_token": "r"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(SupabaseSession.self, from: Data(json.utf8)))
    }

    // MARK: - SupabaseAuthError.userMessage

    func testUserMessageForKnownErrorCodes() {
        let invalidCreds = SupabaseAuthError(status: 400, code: "invalid_credentials", message: "")
        XCTAssertEqual(invalidCreds.userMessage, "Wrong email or password.")

        let notConfirmed = SupabaseAuthError(status: 400, code: "email_not_confirmed", message: "")
        XCTAssertEqual(notConfirmed.userMessage, "Your email is not verified yet.")

        let otpExpired = SupabaseAuthError(status: 400, code: "otp_expired", message: "")
        XCTAssertEqual(otpExpired.userMessage, "The code is wrong or has expired. Request a new one.")

        let weakPassword = SupabaseAuthError(status: 422, code: "weak_password", message: "")
        XCTAssertEqual(weakPassword.userMessage, "Password must be at least 8 characters.")
    }

    func testUserMessageFallsBackForServerErrors() {
        let serverError = SupabaseAuthError(status: 500, code: "unexpected", message: "boom")
        XCTAssertEqual(serverError.userMessage, "The server is having trouble. Please try again later.")
    }

    func testUserMessageFallsBackToGenericForUnknownClientError() {
        let unknown = SupabaseAuthError(status: 400, code: "some_new_gotrue_code", message: "nekaj novega")
        XCTAssertEqual(unknown.userMessage, "Something went wrong. Please try again.")
    }

    // MARK: - jeSupabaseZeton (ES256 vs HS256, po JWT headerju)

    /// Zgradi JWT-podoben niz iz podanega headerja (brez pravega podpisa -- funkcija bere samo header).
    private func fakeJWT(header: [String: String]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let headerB64 = headerData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(headerB64).payload.signature"
    }

    func testJeSupabaseZetonTrueForES256() {
        let token = fakeJWT(header: ["alg": "ES256", "typ": "JWT"])
        XCTAssertTrue(SupabaseAuth.jeSupabaseZeton(token))
    }

    /// Stari lastni zetoni backenda so bili HS256 -- SessionStore jih zavrze.
    func testJeSupabaseZetonFalseForHS256() {
        let token = fakeJWT(header: ["alg": "HS256", "typ": "JWT"])
        XCTAssertFalse(SupabaseAuth.jeSupabaseZeton(token))
    }

    func testJeSupabaseZetonFalseForMalformedToken() {
        XCTAssertFalse(SupabaseAuth.jeSupabaseZeton("not-a-jwt"))
        XCTAssertFalse(SupabaseAuth.jeSupabaseZeton(""))
        XCTAssertFalse(SupabaseAuth.jeSupabaseZeton("only.two"))
    }

    // MARK: - Telo registracije (privolitev v pogoje, backend#215)

    func testTeloRegistracijeNosiTermsVersionInCasSprejema() throws {
        let telo = SupabaseAuth.telesoRegistracije(email: "a@b.si", password: "geslo123", username: "janez",
                                                   ob: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(telo["email"] as? String, "a@b.si")
        let podatki = try XCTUnwrap(telo["data"] as? [String: Any])
        XCTAssertEqual(podatki["username"] as? String, "janez")
        XCTAssertEqual(podatki["terms_version"] as? String, LegalLinks.termsVersion)
        XCTAssertEqual(podatki["terms_accepted_at"] as? String, "1970-01-01T00:00:00.000Z")
        // Mora preziveti serializacijo v JSON (SupabaseAuth.send uporablja JSONSerialization).
        XCTAssertTrue(JSONSerialization.isValidJSONObject(telo))
    }
}
