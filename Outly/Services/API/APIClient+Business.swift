import Foundation

// Poslovni racun: lasten klub. fetchMyBusinessClub je v APIClient+Events.swift.

extension APIClient {

    /// POST /clubs — lastnik (vloga business) ustvari svoj klub (ob prvi prijavi po odobritvi).
    /// Kljuci so camelCase, kot jih pot pricakuje (name, logoUrl, address, city, lat, lng, minAge, genres,
    /// isOrganizer — organizator brez lastnega prizorisca: naslov in mesto neobvezna).
    func createClub(token: String, fields: [String: Any]) async throws -> APIClub {
        let data = try await send(path: "clubs", method: "POST", token: token, json: fields)
        return try decode(APIClub.self, from: data)
    }

    /// PATCH /business/clubs/me. Posljemo samo podane kljuce (snake_case, kot jih backend pricakuje).
    /// Vrne posodobljen klub.
    func updateMyBusinessClub(token: String, fields: [String: Any]) async throws -> APIClub {
        let data = try await send(path: "business/clubs/me", method: "PATCH", token: token, json: fields)
        return try decode(APIClub.self, from: data)
    }

    /// PATCH /business/clubs/me samo s `is_organizer` (stikalo "I organize events without my own venue").
    /// Vrne posodobljen klub.
    func setMyClubOrganizer(token: String, isOrganizer: Bool) async throws -> APIClub {
        try await updateMyBusinessClub(token: token, fields: ["is_organizer": isOrganizer])
    }
}
