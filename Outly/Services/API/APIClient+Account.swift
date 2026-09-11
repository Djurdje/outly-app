import Foundation

// Poti za racun: /me, dokoncanje racuna, zanri, brisanje. Prijava, registracija,
// potrditev e-naslova, geslo in odjava so od 11. 9. 2026 pri Supabase
// (SupabaseAuth.swift) — backend teh poti za aplikacijo nima vec.

/// Most med APIClient in SessionStore za osvezitev poteklega zetona (S-06).
/// SessionStore ob zagonu nastavi handler; send() ga poklice ob 401 in klic ponovi.
/// Vrne nov dostopni zeton ali nil, ce osvezitev ni mogoca (uporabnik je odjavljen).
@MainActor
enum SessionRefresh {
    /// Osvezi dostopni zeton; vrne novega ali nil.
    static var handler: (() async -> String?)? = nil
    /// Ali je uporabnik (se) prijavljen. Loci "osvezitev ni uspela zaradi omrezja"
    /// od "seja je dokoncno zavrnjena".
    static var isLoggedIn: (() -> Bool)? = nil
}

/// Streznik vrne 401 tudi za napacno geslo ("Invalid credentials."). Osvezujemo
/// samo, ko gre za ZETON ("Missing token." / "Invalid token.").
private func jeNapakaZetona(_ raw: String) -> Bool {
    let t = raw.lowercased()
    return t.contains("token")
}

extension APIClient {

    // MARK: - Skupni posiljatelj

    /// Poslje zahtevo in vrne surove podatke ali vrze APIError.requestFailed(status, besedilo).
    /// Vsa nova koda naj gre skozi to, da se obravnava napak ne razide po datotekah.
    ///
    /// Ce je klic avtoriziran in streznik vrne 401, se ENKRAT poskusi osveziti
    /// dostopni zeton (SessionRefresh.handler) in klic ponovi z novim. Ce osvezitev
    /// ne uspe, 401 pride do klicatelja — SessionStore je uporabnika ze odjavil.
    func send(
        path: String,
        method: String,
        token: String? = nil,
        json: [String: Any]? = nil,
        query: [URLQueryItem] = [],
        retryOn401: Bool = true
    ) async throws -> Data {
        do {
            return try await sendOnce(path: path, method: method, token: token, json: json, query: query)
        } catch let api as APIError {
            guard retryOn401,
                  let token, !token.isEmpty,
                  case let .requestFailed(code, raw) = api, code == 401, jeNapakaZetona(raw),
                  let handler = await SessionRefresh.handler
            else { throw api }

            guard let fresh = await handler(), fresh != token else {
                // Osvezitev ni uspela. Ce je uporabnik se prijavljen, je slo za omrezje/streznik
                // -> ne vracamo 401 (pogledi bi ga odjavili), ampak napako povezave.
                if let stillIn = await SessionRefresh.isLoggedIn, stillIn() {
                    throw APIError.requestFailed(-1, "Could not refresh session")
                }
                throw api
            }
            return try await sendOnce(path: path, method: method, token: fresh, json: json, query: query)
        }
    }

    private func sendOnce(
        path: String,
        method: String,
        token: String?,
        json: [String: Any]?,
        query: [URLQueryItem]
    ) async throws -> Data {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.requestFailed(http.statusCode, msg)
        }
        return data
    }

    // MARK: - Uporabnik

    /// GET /me. Ob prvem klicu s Supabasovim zetonom backend racun poveze (po
    /// e-naslovu) ali ustvari (username iz registracije).
    func me(token: String) async throws -> Me {
        let data = try await send(path: "me", method: "GET", token: token)
        return try decode(Me.self, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    // MARK: - Zanri

    private struct GenresResponse: Decodable { let genres: [String] }

    /// GET /genres — zaprt seznam 21 zanrov. Streznik zavrne vse, kar ni na njem.
    func fetchGenres() async throws -> [String] {
        let data = try await send(path: "genres", method: "GET")
        return try decode(GenresResponse.self, from: data).genres
    }

    // MARK: - Dokoncanje racuna

    /// Polja za PATCH /me. Posljemo samo tista, ki so nastavljena (nil = ne spreminjaj).
    struct MeUpdate {
        var username: String? = nil
        var phone: String?? = nil        // .some(nil) = izbrisi
        var dateOfBirth: String? = nil   // "YYYY-MM-DD"
        var country: String? = nil       // "SI"
        var genres: [String]? = nil

        var json: [String: Any] {
            var j: [String: Any] = [:]
            if let username { j["username"] = username }
            if let phone {
                if let p = phone { j["phone"] = p } else { j["phone"] = NSNull() }
            }
            if let dateOfBirth { j["dateOfBirth"] = dateOfBirth }
            if let country { j["country"] = country }
            if let genres { j["genres"] = genres }
            return j
        }
    }

    /// PATCH /me. Vrne posodobljenega uporabnika (z onboarded_at, ce je racun zdaj dokoncan).
    func updateMe(token: String, _ update: MeUpdate) async throws -> Me {
        let data = try await send(path: "me", method: "PATCH", token: token, json: update.json)
        return try decode(Me.self, from: data)
    }

    // MARK: - Brisanje racuna

    /// DELETE /me. Zahteva geslo (backend ga preveri pri Supabase, nato izbrise lokalne
    /// podatke IN Supabasov racun). Ob obstoju narocil streznik anonimizira namesto izbrise.
    /// 409 z "club_has_orders": lastnik kluba s prodanimi vstopnicami mora klub najprej predati.
    func deleteAccount(token: String, password: String) async throws {
        _ = try await send(path: "me", method: "DELETE", token: token, json: ["password": password])
    }
}
