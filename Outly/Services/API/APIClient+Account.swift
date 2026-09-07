import Foundation

// Poti za racun: pozabljeno geslo, dokoncanje racuna, zanri, brisanje.
// Vse poti obstajajo na backendu (index.js) in so bile preizkusene s curl.

extension APIClient {

    // MARK: - Skupni posiljatelj

    /// Poslje zahtevo in vrne surove podatke ali vrze APIError.requestFailed(status, besedilo).
    /// Vsa nova koda naj gre skozi to, da se obravnava napak ne razide po datotekah.
    func send(
        path: String,
        method: String,
        token: String? = nil,
        json: [String: Any]? = nil,
        query: [URLQueryItem] = []
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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    // MARK: - Pozabljeno geslo

    /// POST /auth/forgot-password. Streznik VEDNO vrne 200 (tudi ce racuna ni),
    /// da se ne da ugotavljati, kateri e-naslovi so registrirani.
    func forgotPassword(email: String) async throws {
        _ = try await send(path: "auth/forgot-password", method: "POST", json: ["email": email])
    }

    /// POST /auth/reset-password. Koda je 6-mestna, geslo najmanj 8 znakov.
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        _ = try await send(path: "auth/reset-password", method: "POST",
                           json: ["email": email, "code": code, "newPassword": newPassword])
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

    /// DELETE /me. Zahteva geslo. Ob obstoju narocil streznik anonimizira namesto izbrise.
    /// 409 z "club_has_orders": lastnik kluba s prodanimi vstopnicami mora klub najprej predati.
    func deleteAccount(token: String, password: String) async throws {
        _ = try await send(path: "me", method: "DELETE", token: token, json: ["password": password])
    }
}
