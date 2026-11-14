import XCTest
import Foundation
@testable import Outly

/// Prijava z Applom in Googlom (14. 11. 2026): cista logika brez omrezja -- nonce, PKCE, povratni URL, telesa zahtevkov,
/// branje zahtevkov JWT in preverba uporabniskega imena.
final class DruzabnaPrijavaTests: XCTestCase {

    // MARK: - SHA-256, nonce

    func testSha256HexZnanVektor() {
        XCTAssertEqual(DruzabnaPrijavaLogika.sha256Hex("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNakljucenNizDolzinaZnakiInRazlicnost() {
        let a = DruzabnaPrijavaLogika.nakljucenNiz()
        let b = DruzabnaPrijavaLogika.nakljucenNiz()
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, b)
        let dovoljeno = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(a.unicodeScalars.allSatisfy { dovoljeno.contains($0) })
        XCTAssertEqual(DruzabnaPrijavaLogika.nakljucenNiz(dolzina: 43).count, 43)
    }

    // MARK: - PKCE

    /// Testni vektor iz RFC 7636, dodatek B.
    func testPkceChallengeRfc7636() {
        XCTAssertEqual(DruzabnaPrijavaLogika.pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testAuthorizeURL() throws {
        let osnova = try XCTUnwrap(URL(string: "https://x.supabase.co/auth/v1"))
        let url = try XCTUnwrap(DruzabnaPrijavaLogika.authorizeURL(baseURL: osnova, provider: "google", challenge: "CH"))
        XCTAssertEqual(url.path, "/auth/v1/authorize")
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["provider"], "google")
        XCTAssertEqual(q["redirect_to"], "si.outly.app://auth-callback")
        XCTAssertEqual(q["code_challenge"], "CH")
        XCTAssertEqual(q["code_challenge_method"], "s256")
    }

    func testRazclenPovratekKoda() throws {
        let url = try XCTUnwrap(URL(string: "si.outly.app://auth-callback?code=abc-123"))
        XCTAssertEqual(DruzabnaPrijavaLogika.razclenPovratek(url), .koda("abc-123"))
    }

    func testRazclenPovratekNapakaVQueryInFragmentu() throws {
        let a = try XCTUnwrap(URL(string: "si.outly.app://auth-callback?error=access_denied&error_description=User+cancelled"))
        XCTAssertEqual(DruzabnaPrijavaLogika.razclenPovratek(a), .napaka("access_denied", "User cancelled"))
        let b = try XCTUnwrap(URL(string: "si.outly.app://auth-callback#error=server_error&error_description=Boom"))
        XCTAssertEqual(DruzabnaPrijavaLogika.razclenPovratek(b), .napaka("server_error", "Boom"))
    }

    func testRazclenPovratekNapakaImaPrednostPredKodo() throws {
        let url = try XCTUnwrap(URL(string: "si.outly.app://auth-callback?code=x&error=access_denied"))
        XCTAssertEqual(DruzabnaPrijavaLogika.razclenPovratek(url), .napaka("access_denied", nil))
    }

    func testRazclenPovratekBrezKode() throws {
        let url = try XCTUnwrap(URL(string: "si.outly.app://auth-callback"))
        XCTAssertEqual(DruzabnaPrijavaLogika.razclenPovratek(url), .neveljaven)
    }

    // MARK: - Telesa zahtevkov

    func testTeloIdToken() {
        let t = DruzabnaPrijavaLogika.telesoIdToken(provider: "apple", idToken: "JWT", nonce: "SUROV")
        XCTAssertEqual(t["provider"] as? String, "apple")
        XCTAssertEqual(t["id_token"] as? String, "JWT")
        XCTAssertEqual(t["nonce"] as? String, "SUROV")
        XCTAssertEqual(t.count, 3)
    }

    func testTeloPkce() {
        let t = DruzabnaPrijavaLogika.telesoPkce(authCode: "K", codeVerifier: "V")
        XCTAssertEqual(t["auth_code"] as? String, "K")
        XCTAssertEqual(t["code_verifier"] as? String, "V")
        XCTAssertEqual(t.count, 2)
    }

    /// Isti kljuci in oblika datuma kot pri registraciji (`telesoRegistracije`): outly-backend#215.
    func testTeloPrivolitveEnakoKotRegistracija() throws {
        let ob = Date(timeIntervalSince1970: 1_800_000_000.123)
        let p = DruzabnaPrijavaLogika.telesoPrivolitve(termsVersion: "9.9.9", ob: ob)
        let r = SupabaseAuth.telesoRegistracije(email: "a@b.si", password: "x", username: "u", termsVersion: "9.9.9", ob: ob)
        let pd = try XCTUnwrap(p["data"] as? [String: Any])
        let rd = try XCTUnwrap(r["data"] as? [String: Any])
        XCTAssertEqual(pd["terms_version"] as? String, "9.9.9")
        XCTAssertEqual(pd["terms_accepted_at"] as? String, rd["terms_accepted_at"] as? String)
        XCTAssertEqual(Set(pd.keys), ["terms_version", "terms_accepted_at"])
    }

    // MARK: - Zahtevki JWT

    private func jwt(_ payload: [String: Any]) throws -> String {
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let glava = b64(Data(#"{"alg":"ES256"}"#.utf8))
        let telo = b64(try JSONSerialization.data(withJSONObject: payload))
        return "\(glava).\(telo).podpis"
    }

    func testRacunZGeslomNiDruzabni() throws {
        let z = DruzabnaPrijavaLogika.zahtevki(izZetona: try jwt(["app_metadata": ["provider": "email"],
                                                               "user_metadata": ["terms_version": "1.1.4"]]))
        XCTAssertFalse(DruzabnaPrijavaLogika.jeDruzabniRacun(zahtevki: z))
        XCTAssertFalse(DruzabnaPrijavaLogika.potrebujePrivolitev(zahtevki: z))
    }

    func testRacunIzGooglaBrezPogojevPotrebujePrivolitev() throws {
        let z = DruzabnaPrijavaLogika.zahtevki(izZetona: try jwt(["app_metadata": ["provider": "google"],
                                                               "user_metadata": ["name": "Ana"]]))
        XCTAssertTrue(DruzabnaPrijavaLogika.jeDruzabniRacun(zahtevki: z))
        XCTAssertTrue(DruzabnaPrijavaLogika.potrebujePrivolitev(zahtevki: z))
    }

    func testRacunIzApplaZPogojiNePotrebujePrivolitve() throws {
        let z = DruzabnaPrijavaLogika.zahtevki(izZetona: try jwt(["app_metadata": ["provider": "apple"],
                                                               "user_metadata": ["terms_version": "1.1.4"]]))
        XCTAssertTrue(DruzabnaPrijavaLogika.jeDruzabniRacun(zahtevki: z))
        XCTAssertFalse(DruzabnaPrijavaLogika.potrebujePrivolitev(zahtevki: z))
    }

    func testPrazenAliPokvarjenZetonNiDruzabniRacun() {
        XCTAssertNil(DruzabnaPrijavaLogika.zahtevki(izZetona: ""))
        XCTAssertNil(DruzabnaPrijavaLogika.zahtevki(izZetona: "a.b"))
        XCTAssertFalse(DruzabnaPrijavaLogika.jeDruzabniRacun(zahtevki: nil))
        XCTAssertFalse(DruzabnaPrijavaLogika.potrebujePrivolitev(zahtevki: nil))
    }

    // MARK: - Uporabnisko ime

    func testUporabniskoIme() {
        XCTAssertNil(DruzabnaPrijavaLogika.napakaUporabniskegaImena("ana_99"))
        XCTAssertNil(DruzabnaPrijavaLogika.napakaUporabniskegaImena("abc"))
        XCTAssertNil(DruzabnaPrijavaLogika.napakaUporabniskegaImena(String(repeating: "a", count: 20)))
        XCTAssertEqual(DruzabnaPrijavaLogika.napakaUporabniskegaImena("ab"), .prekratko)
        XCTAssertEqual(DruzabnaPrijavaLogika.napakaUporabniskegaImena(String(repeating: "a", count: 21)), .predolgo)
        XCTAssertEqual(DruzabnaPrijavaLogika.napakaUporabniskegaImena("ana.novak"), .znaki)
        XCTAssertEqual(DruzabnaPrijavaLogika.napakaUporabniskegaImena("črt_1"), .znaki)
    }

    /// Backend brez izbire ustvari `user` / `user_NNNN`: polje je takrat prazno, sicer predizpolnjeno.
    func testPredizpolnjenoImeJePrazno_ZaImenaBrezIzbire() {
        XCTAssertEqual(DruzabnaPrijavaLogika.predizpolnjenoIme("user"), "")
        XCTAssertEqual(DruzabnaPrijavaLogika.predizpolnjenoIme("user_1234"), "")
        XCTAssertEqual(DruzabnaPrijavaLogika.predizpolnjenoIme("ana_novak"), "ana_novak")
        XCTAssertEqual(DruzabnaPrijavaLogika.predizpolnjenoIme("user_"), "user_")
        XCTAssertEqual(DruzabnaPrijavaLogika.predizpolnjenoIme("user_ana"), "user_ana")
        XCTAssertEqual(DruzabnaPrijavaLogika.predizpolnjenoIme("username"), "username")
    }

    // MARK: - Napake Supabase

    func testProviderDisabledDobiLastnoSporocilo() {
        let e = SupabaseAuthError(status: 400, code: "provider_disabled", message: "")
        XCTAssertEqual(e.userMessage, String(localized: "This sign-in method is not available right now."))
    }
}
