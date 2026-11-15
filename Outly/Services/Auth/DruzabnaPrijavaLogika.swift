import Foundation
import CryptoKit

// Cista logika prijave z Applom in Googlom (brez omrezja, brez UI), da jo pokrijejo testi (DruzabnaPrijavaTests).
// Opomba: projekt ima SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, zato je vsaka funkcija izrecno `nonisolated`
// (isto kot SupabaseAuth.telesoRegistracije).

/// Izid povratnega URL-ja po prijavi z Googlom (`com.googleusercontent.apps.<ID>:/oauthredirect?code=...&state=...`).
enum PovratekPrijave: Equatable {
    /// Avtorizacijska koda, ki jo je treba zamenjati pri Googlu (oauth2.googleapis.com/token).
    case koda(String)
    /// Google je vrnil napako (`error`, `error_description`), npr. `access_denied`, ko uporabnik pritisne Cancel.
    case napaka(String, String?)
    /// `state` v povratku ni enak poslanemu (zahteva ni nasa): koda se NE uporabi.
    case napacenState
    /// Brez kode in brez napake.
    case neveljaven
}

enum DruzabnaPrijavaLogika {

    /// iOS OAuth client ID za Google (Google Cloud Console, tip iOS, bundle `si.outly.app`), oblika `<stevilka>-<niz>.apps.googleusercontent.com`.
    /// JAVEN podatek (sme v kodo). Dokler je prazen, gumb »Continue with Google« NI prikazan (Apple ostane). Vpise menedzer, ko ga Martin ustvari.
    nonisolated static let googleIOSClientID = ""
    nonisolated static var googleKonfiguriran: Bool { !googleIOSClientID.isEmpty }
    private nonisolated static let googlePripona = ".apps.googleusercontent.com"
    nonisolated static let googleAvtorizacijaNaslov = "https://accounts.google.com/o/oauth2/v2/auth"
    nonisolated static let googleZetonNaslov = "https://oauth2.googleapis.com/token"

    /// Shema vrnitve = obrnjen client ID (`com.googleusercontent.apps.<ID>`); `callbackURLScheme` ASWebAuthenticationSession.
    nonisolated static func googleShema(clientID: String = googleIOSClientID) -> String {
        let id = clientID.hasSuffix(googlePripona) ? String(clientID.dropLast(googlePripona.count)) : clientID
        return "com.googleusercontent.apps." + id
    }

    nonisolated static func googleRedirectURI(clientID: String = googleIOSClientID) -> String {
        googleShema(clientID: clientID) + ":/oauthredirect"
    }

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

    // MARK: - Google (neposredno, brez Supabase /authorize)

    // Supabasov /authorize za Google vedno doda obseg `profile` (supabase/auth google.go:49-51): ime in slika bi se shranila (Martin 14. 11.:
    // ne zelimo). Zato od Googla zahtevamo samo `openid email`, id_token pa damo Supabasu (POST /token?grant_type=id_token).
    // Supabase primerja sha256 hex surovega noncea z `nonce` v zetonu (token_oidc.go:294-306): Googlu gre `sha256Hex(surov)`, Supabasu surov.

    /// `https://accounts.google.com/o/oauth2/v2/auth?...` (PKCE S256, `scope=openid email`, brez `profile`).
    nonisolated static func googleAvtorizacijaURL(clientID: String = googleIOSClientID, redirectURI: String? = nil,
                                                  challenge: String, nonceHash: String, state: String) -> URL? {
        guard var c = URLComponents(string: googleAvtorizacijaNaslov) else { return nil }
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI ?? googleRedirectURI(clientID: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonceHash),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return c.url
    }

    /// Telo POST oauth2.googleapis.com/token (`application/x-www-form-urlencoded`; iOS client nima secreta).
    nonisolated static func googleTeloIzmenjave(code: String, codeVerifier: String, clientID: String = googleIOSClientID,
                                                redirectURI: String? = nil) -> String {
        formKodirano([
            ("grant_type", "authorization_code"), ("code", code), ("code_verifier", codeVerifier),
            ("client_id", clientID), ("redirect_uri", redirectURI ?? googleRedirectURI(clientID: clientID)),
        ])
    }

    nonisolated static func formKodirano(_ pari: [(String, String)]) -> String {
        let dovoljeno = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func k(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: dovoljeno) ?? "" }
        return pari.map { k($0.0) + "=" + k($0.1) }.joined(separator: "&")
    }

    /// `id_token` iz odgovora Googlovega /token (nil, ce ga ni ali je prazen).
    nonisolated static func googleIdToken(izOdgovora data: Data) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let t = o["id_token"] as? String, !t.isEmpty else { return nil }
        return t
    }

    /// Telo DELETE /me brez gesla (backend I73).
    nonisolated static var teloIzbrisaPonudnik: [String: Any] { ["reauth": "provider"] }

    /// Telo DELETE /me brez gesla + Applov `authorizationCode` (backend Issue #427: streznik z njim preklice Applove zetone,
    /// Apple 5.1.1(v)). Brez kode (nil/prazna) = isto kot `teloIzbrisaPonudnik` (izbris je pravica uporabnika). Star backend polje prezre.
    nonisolated static func teloIzbrisaPonudnik(appleKoda: String?) -> [String: Any] {
        var telo: [String: Any] = teloIzbrisaPonudnik
        if let appleKoda, !appleKoda.isEmpty { telo["apple_authorization_code"] = appleKoda }
        return telo
    }

    /// `ASAuthorizationAppleIDCredential.authorizationCode` (Data?) kot niz; nil, ce ga ni, ni UTF-8 ali je prazen.
    /// Koda se NE shranjuje (ne UserDefaults/Keychain/dnevnik/Sentry): zivi samo do klica DELETE /me.
    nonisolated static func appleKoda(izPodatkov podatki: Data?) -> String? {
        guard let podatki, let s = String(data: podatki, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    /// 401 `reauth_required` pri DELETE /me (backend I73): seja je veljavna, treba je znova potrditi s ponudnikom. NE odjava.
    nonisolated static func jeReauthPotreben(_ odgovor: String) -> Bool {
        odgovor.contains("reauth_required")
    }

    /// `sub` (uporabnik) obeh zetonov je enak in neprazen. Pred izbrisom racuna po ponovni prijavi: druga seja (izbira drugega Google
    /// racuna ali Apple ID) bi sicer izbrisala TUJ racun. Manjkajoc ali pokvarjen zeton = ni enak.
    nonisolated static func istiUporabnik(zeton a: String, zeton b: String) -> Bool {
        func sub(_ t: String) -> String? {
            guard let s = (zahtevki(izZetona: t)?["sub"] as? String)?.lowercased(), !s.isEmpty else { return nil }
            return s
        }
        guard let x = sub(a), let y = sub(b) else { return false }
        return x == y
    }

    /// Ponudnik racuna za ponovno prijavo pred izbrisom: `apple` | `google`; nil za racun z geslom.
    nonisolated static func ponudnik(zahtevki: [String: Any]?) -> String? {
        guard jeDruzabniRacun(zahtevki: zahtevki),
              let p = (zahtevki?["app_metadata"] as? [String: Any])?["provider"] as? String else { return nil }
        return p
    }

    /// Razclenitev povratnega URL-ja. Google vrne `code` v query; napake lahko pridejo v query ali v fragment.
    /// Vrednosti so v obliki `application/x-www-form-urlencoded` (presledek = `+`), ki je URLQueryItem ne pretvori sam.
    /// `state`: ce je podan, mora biti enak `state` v povratku (sicer `.napacenState`, tudi ob napaki, ki je ne smemo zaupati).
    nonisolated static func razclenPovratek(_ url: URL, state: String? = nil) -> PovratekPrijave {
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var vrednosti = parametri(c?.percentEncodedQuery)
        for (k, v) in parametri(c?.percentEncodedFragment) where vrednosti[k] == nil { vrednosti[k] = v }
        if let state, vrednosti["state"] != state { return .napacenState }
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
