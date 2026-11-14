import Foundation
import CryptoKit

// Cista logika prijave z Applom in Googlom (brez omrezja, brez UI), da jo pokrijejo testi (DruzabnaPrijavaTests).
// Opomba: projekt ima SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, zato je vsaka funkcija izrecno `nonisolated`
// (isto kot SupabaseAuth.telesoRegistracije).

/// Izid povratnega URL-ja po prijavi z Googlom (`si.outly.app://auth-callback?code=...`).
enum PovratekPrijave: Equatable {
    /// PKCE koda, ki jo je treba zamenjati pri POST /token?grant_type=pkce.
    case koda(String)
    /// GoTrue je vrnil napako (`error`, `error_description`), npr. `access_denied`, ko uporabnik na Googlu pritisne Cancel.
    case napaka(String, String?)
    /// Brez kode in brez napake.
    case neveljaven
}

enum DruzabnaPrijavaLogika {

    /// Shema vrnitve (Supabase Redirect URL mora biti dodan: `si.outly.app://auth-callback`).
    nonisolated static let shemaVrnitve = "si.outly.app"
    nonisolated static let vrnitveniURL = "si.outly.app://auth-callback"

    private nonisolated static let znaki = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    // MARK: - Nakljucni nizi, SHA-256

    /// Nakljucen niz iz nerezerviranih znakov URL-ja (RFC 3986), kot jih zahtevata nonce in PKCE `code_verifier` (43–128 znakov).
    /// `SystemRandomNumberGenerator` je na Applovih platformah kriptografsko varen.
    nonisolated static func nakljucenNiz(dolzina: Int = 64) -> String {
        var g = SystemRandomNumberGenerator()
        return String((0..<max(dolzina, 1)).map { _ in znaki[Int.random(in: 0..<znaki.count, using: &g)] })
    }

    /// SHA-256 kot male šestnajstiške števke (to dobi Apple kot `nonce`; GoTrue primerja s `nonce` v id_tokenu).
    nonisolated static func sha256Hex(_ niz: String) -> String {
        SHA256.hash(data: Data(niz.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// PKCE `code_challenge` = base64url(sha256(verifier)) brez polnila (RFC 7636 §4.2, metoda S256).
    nonisolated static func pkceChallenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64URL(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Google (PKCE)

    /// `{baseURL}/authorize?provider=google&redirect_to=...&code_challenge=...&code_challenge_method=s256`
    nonisolated static func authorizeURL(baseURL: URL, provider: String, challenge: String,
                                         redirectTo: String = vrnitveniURL) -> URL? {
        guard var c = URLComponents(url: baseURL.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return c.url
    }

    /// Razclenitev povratnega URL-ja. GoTrue pri PKCE doda `code` v query; napake lahko pridejo v query ali v fragment.
    /// Vrednosti so v obliki `application/x-www-form-urlencoded` (presledek = `+`), ki je URLQueryItem ne pretvori sam.
    nonisolated static func razclenPovratek(_ url: URL) -> PovratekPrijave {
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var vrednosti = parametri(c?.percentEncodedQuery)
        for (k, v) in parametri(c?.percentEncodedFragment) where vrednosti[k] == nil { vrednosti[k] = v }
        if let e = vrednosti["error"] ?? vrednosti["error_code"], !e.isEmpty {
            return .napaka(e, vrednosti["error_description"])
        }
        if let k = vrednosti["code"], !k.isEmpty { return .koda(k) }
        return .neveljaven
    }

    private nonisolated static func parametri(_ niz: String?) -> [String: String] {
        var izid: [String: String] = [:]
        for par in (niz ?? "").split(separator: "&") {
            let deli = par.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let ime = deli.first.flatMap({ dekodiraj(String($0)) }), !ime.isEmpty, izid[ime] == nil else { continue }
            izid[ime] = deli.count > 1 ? dekodiraj(String(deli[1])) : ""
        }
        return izid
    }

    private nonisolated static func dekodiraj(_ s: String) -> String? {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// Telo POST /token?grant_type=pkce.
    nonisolated static func telesoPkce(authCode: String, codeVerifier: String) -> [String: Any] {
        ["auth_code": authCode, "code_verifier": codeVerifier]
    }

    // MARK: - Apple (id_token)

    /// Telo POST /token?grant_type=id_token. `nonce` je SUROV niz (Applu gre njegov sha256Hex).
    nonisolated static func telesoIdToken(provider: String, idToken: String, nonce: String) -> [String: Any] {
        ["provider": provider, "id_token": idToken, "nonce": nonce]
    }

    // MARK: - Privolitev (pogoji) za racun iz Googla/Appla

    /// Telo PUT /user: isti kljuci kot `SupabaseAuth.telesoRegistracije` (`terms_version`, `terms_accepted_at` v ISO 8601 UTC z
    /// milisekundami).
    nonisolated static func telesoPrivolitve(termsVersion: String, ob: Date = Date()) -> [String: Any] {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return ["data": ["terms_version": termsVersion, "terms_accepted_at": f.string(from: ob)] as [String: Any]]
    }

    /// Zahtevki (payload) Supabasovega JWT brez preverjanja podpisa: samo za odlocitev, kaj pokazati (nikoli o dostopu).
    nonisolated static func zahtevki(izZetona token: String) -> [String: Any]? {
        let deli = token.split(separator: ".", omittingEmptySubsequences: false)
        guard deli.count == 3 else { return nil }
        var b = String(deli[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        switch b.count % 4 {
        case 1: return nil
        case 2: b += "=="
        case 3: b += "="
        default: break
        }
        guard let d = Data(base64Encoded: b) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// Racun je bil ustvarjen z Googlom/Applom (`app_metadata.provider` ni `email`). Neznano = false (racun z geslom).
    nonisolated static func jeDruzabniRacun(zahtevki: [String: Any]?) -> Bool {
        guard let app = zahtevki?["app_metadata"] as? [String: Any],
              let p = app["provider"] as? String, !p.isEmpty else { return false }
        return p != "email"
    }

    /// Racun iz Googla/Appla brez `user_metadata.terms_version`: pogoje je treba zapisati (PUT /user).
    nonisolated static func potrebujePrivolitev(zahtevki: [String: Any]?) -> Bool {
        guard jeDruzabniRacun(zahtevki: zahtevki) else { return false }
        let um = zahtevki?["user_metadata"] as? [String: Any]
        let v = um?["terms_version"] as? String
        return (v ?? "").isEmpty
    }

    // MARK: - Uporabnisko ime

    /// Ime, ki ga backend ustvari brez izbire (pogodba backend ARCHITECTURE »Prijava z Googlom in Applom«, tocka 3): `user` (Applov
    /// skriti naslov, prepovedano ime) ali `user_NNNN` (trk imena). Polje za ime je takrat prazno, drugace predizpolnjeno.
    nonisolated static func predizpolnjenoIme(_ ime: String) -> String {
        if ime == "user" { return "" }
        if ime.hasPrefix("user_"), ime.dropFirst(5).allSatisfy({ $0.isASCII && $0.isNumber }), ime.count > 5 { return "" }
        return ime
    }

    /// Preverba uporabniskega imena (3–20 znakov, crke/stevke/podcrtaj; enaka pravila kot RegisterView). nil = veljavno.
    nonisolated static func napakaUporabniskegaImena(_ ime: String) -> UporabniskoImeNapaka? {
        if ime.count < 3 { return .prekratko }
        if ime.count > 20 { return .predolgo }
        let dovoljeno = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        if !ime.unicodeScalars.allSatisfy({ dovoljeno.contains($0) }) { return .znaki }
        return nil
    }
}

enum UporabniskoImeNapaka: Equatable {
    case prekratko, predolgo, znaki

    var sporocilo: String {
        switch self {
        case .prekratko: return String(localized: "Username must be at least 3 characters.")
        case .predolgo:  return String(localized: "Username can have at most 20 characters.")
        case .znaki:     return String(localized: "Username can contain only letters, numbers and underscore.")
        }
    }
}
