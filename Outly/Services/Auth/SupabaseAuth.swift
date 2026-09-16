import Foundation

// Supabase Auth je od 11. 9. 2026 edina identiteta Outlyja (aplikacija + outly.si).
// Backend lastnih zetonov ne izdaja vec: preveri Supabasov JWT in uporabnika
// poveze/ustvari sam (migracija 010). Tu je tanek odjemalec za GoTrue REST API
// (/auth/v1) brez supabase-swift: rabimo pet klicev, SDK bi prinesel realtime,
// postgrest in storage, ki jih aplikacija ne uporablja — in brez Xcoda paketa
// ne moremo zanesljivo dodati v projekt.
//
// URL in objavljeni kljuc sta JAVNA (ista kot v supabase-config.js na outly.si);
// varnost je v Supabasovih pravilih, ne v kljucu. service_role kljuca tu NI.

struct SupabaseSession: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// Napaka Supabase Auth. `code` je GoTrue error_code (npr. "invalid_credentials",
/// "email_not_confirmed", "user_already_exists", "otp_expired"), `status` HTTP koda.
struct SupabaseAuthError: Error, Sendable {
    let status: Int
    let code: String
    let message: String

    var userMessage: String {
        switch code {
        case "invalid_credentials":            return String(localized: "Wrong email or password.")
        case "email_not_confirmed":            return String(localized: "Your email is not verified yet.")
        case "user_already_exists", "email_exists": return String(localized: "That email is already registered. Sign in instead.")
        case "weak_password":                  return String(localized: "Password must be at least 8 characters.")
        case "otp_expired", "otp_disabled":    return String(localized: "The code is wrong or has expired. Request a new one.")
        case "over_email_send_rate_limit", "over_request_rate_limit":
            return String(localized: "Too many attempts. Please wait a minute and try again.")
        case "same_password":                  return String(localized: "New password must be different from the current one.")
        case "session_expired", "refresh_token_not_found", "refresh_token_already_used", "bad_jwt":
            return String(localized: "Your session has expired. Please log in again.")
        case "user_not_found":                 return String(localized: "No account with this email.")
        case "validation_failed":              return String(localized: "Please check what you entered and try again.")
        default:
            if status >= 500 { return String(localized: "The server is having trouble. Please try again later.") }
            if message.lowercased().contains("invalid login credentials") { return String(localized: "Wrong email or password.") }
            if message.lowercased().contains("already registered") { return String(localized: "That email is already registered. Sign in instead.") }
            return String(localized: "Something went wrong. Please try again.")
        }
    }
}

final class SupabaseAuth: Sendable {
    static let shared = SupabaseAuth()
    private init() {}

    let baseURL = URL(string: "https://zbewqcxnvrwebxonvebx.supabase.co/auth/v1")!
    let publishableKey = "sb_publishable_NzgXZhG7RGs0mZMjGYtyig_XfOvepXS"

    // MARK: - Klici

    /// Prijava z e-naslovom in geslom.
    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let data = try await post("token?grant_type=password", json: ["email": email, "password": password])
        return try decode(SupabaseSession.self, from: data)
    }

    /// Registracija. Ker je v Supabase vklopljena potrditev e-naslova, seja NI vrnjena;
    /// uporabnik dobi mail s kodo in povezavo. Vrne true, ce je bil racun ustvarjen,
    /// false, ce e-naslov ze obstaja (Supabase takrat vrne "uporabnika" brez identitet,
    /// da se registriranih naslovov ne da ugotavljati).
    func signUp(email: String, password: String, username: String) async throws -> Bool {
        let data = try await post("signup", json: [
            "email": email,
            "password": password,
            "data": ["username": username],
        ])
        struct Odgovor: Decodable {
            struct Uporabnik: Decodable { let identities: [Ident]? }
            struct Ident: Decodable { let id: String? }
            let user: Uporabnik?
            let identities: [Ident]?
        }
        let o = try decode(Odgovor.self, from: data)
        let idents = o.user?.identities ?? o.identities ?? []
        return !idents.isEmpty
    }

    /// Potrditev e-naslova (type "signup") ali ponastavitve gesla (type "recovery")
    /// s 6-mestno kodo iz maila. Vrne sejo — uporabnik je s tem prijavljen.
    func verify(email: String, code: String, type: String) async throws -> SupabaseSession {
        let data = try await post("verify", json: ["email": email, "token": code, "type": type])
        return try decode(SupabaseSession.self, from: data)
    }

    /// Ponovno poslje potrditveni mail (type "signup").
    func resend(email: String, type: String = "signup") async throws {
        _ = try await post("resend", json: ["email": email, "type": type])
    }

    /// Mail za ponastavitev gesla (koda + povezava). Supabase vedno odgovori 200,
    /// da se ne da ugotavljati, kateri naslovi so registrirani.
    func requestPasswordReset(email: String) async throws {
        _ = try await post("recover", json: ["email": email])
    }

    /// Nastavi novo geslo prijavljenemu uporabniku (po prijavi ali po "recovery" kodi).
    func updatePassword(token: String, newPassword: String) async throws {
        _ = try await send("user", method: "PUT", token: token, json: ["password": newPassword])
    }

    /// Nov par zetonov. Stari osvezevalni zeton je s tem porabljen.
    func refresh(refreshToken: String) async throws -> SupabaseSession {
        let data = try await post("token?grant_type=refresh_token", json: ["refresh_token": refreshToken])
        return try decode(SupabaseSession.self, from: data)
    }

    /// Odjava. scope "local" = ta seja, "global" = vse naprave.
    func signOut(token: String, scope: String = "local") async throws {
        _ = try await send("logout?scope=\(scope)", method: "POST", token: token, json: nil)
    }

    // MARK: - HTTP

    private func post(_ path: String, json: [String: Any]) async throws -> Data {
        try await send(path, method: "POST", token: nil, json: json)
    }

    private func send(_ path: String, method: String, token: String?, json: [String: Any]?) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + "/" + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue(publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else {
            req.httpBody = Data("{}".utf8)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            throw SupabaseAuth.napaka(status: http.statusCode, data: data)
        }
        return data
    }

    /// GoTrue vraca napake v vec oblikah: { "code": 400, "error_code": "...", "msg": "..." },
    /// { "error": "...", "error_description": "..." } ali { "message": "..." }.
    private static func napaka(status: Int, data: Data) -> SupabaseAuthError {
        var code = ""
        var msg = ""
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            code = (o["error_code"] as? String) ?? (o["error"] as? String) ?? ""
            msg = (o["msg"] as? String) ?? (o["error_description"] as? String) ?? (o["message"] as? String) ?? ""
        }
        if msg.isEmpty { msg = String(data: data, encoding: .utf8) ?? "" }
        return SupabaseAuthError(status: status, code: code, message: msg)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decodingFailed }
    }
}

extension SupabaseAuth {
    /// Ali je zeton Supabasov (ES256)? Stari lastni zetoni backenda so HS256;
    /// SessionStore jih ob prvem zagonu nove razlicice zavrze.
    static func jeSupabaseZeton(_ token: String) -> Bool {
        let deli = token.split(separator: ".")
        guard deli.count == 3 else { return false }
        var s = String(deli[0]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return (o["alg"] as? String) == "ES256"
    }
}
