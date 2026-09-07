import Foundation

// Poslovni racun: lasten klub. fetchMyBusinessClub je v APIClient+Events.swift.

extension APIClient {

    /// PATCH /business/clubs/me. Posljemo samo podane kljuce (snake_case, kot jih backend pricakuje).
    /// Vrne posodobljen klub.
    func updateMyBusinessClub(token: String, fields: [String: Any]) async throws -> APIClub {
        let data = try await send(path: "business/clubs/me", method: "PATCH", token: token, json: fields)
        return try decode(APIClub.self, from: data)
    }
}
