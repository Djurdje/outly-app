import Foundation

// Priljubljeni dogodki na strezniku (migracija 012).
// GET /me/favorites -> { ids: [Int], events: [APIEvent] }
// PUT /me/favorites/:id, DELETE /me/favorites/:id (oba idempotentna).

extension APIClient {
    struct FavoritesResponse: Decodable {
        let ids: [Int]
        let events: [APIEvent]
    }

    func fetchFavorites(token: String) async throws -> FavoritesResponse {
        let data = try await send(path: "me/favorites", method: "GET", token: token)
        return try decode(FavoritesResponse.self, from: data)
    }

    func setFavorite(token: String, eventId: Int, favorite: Bool) async throws {
        _ = try await send(path: "me/favorites/\(eventId)", method: favorite ? "PUT" : "DELETE", token: token)
    }
}
