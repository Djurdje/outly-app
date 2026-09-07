import Foundation

// Zemljevid in iskanje: GET /clubs/map, GET /search, GET /events/:id.

/// Lahek zapis kluba za pin na zemljevidu (GET /clubs/map).
struct MapClub: Identifiable, Decodable {
    let id: Int
    let name: String
    let lat: Double
    let lng: Double
    let logoUrl: String
    let city: String
    let minAge: Int
    let genres: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, lat, lng, city, genres
        case logoUrl = "logo_url"
        case minAge = "min_age"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(Int.self, forKey: .id)
        name    = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lat     = try c.decode(Double.self, forKey: .lat)
        lng     = try c.decode(Double.self, forKey: .lng)
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl) ?? ""
        city    = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        minAge  = try c.decodeIfPresent(Int.self, forKey: .minAge) ?? 18
        genres  = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
    }
}

/// Zadetki GET /search: klubi in dogodki hkrati.
struct SearchResults: Decodable {
    struct Club: Identifiable, Decodable {
        let id: Int
        let name: String
        let city: String
        let logoUrl: String

        enum CodingKeys: String, CodingKey {
            case id, name, city
            case logoUrl = "logo_url"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id      = try c.decode(Int.self, forKey: .id)
            name    = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            city    = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
            logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl) ?? ""
        }
    }

    struct Event: Identifiable, Decodable {
        let id: Int
        let clubId: Int
        let title: String
        let posterUrl: String
        let startAt: String
        let clubName: String

        enum CodingKeys: String, CodingKey {
            case id, title
            case clubId = "club_id"
            case posterUrl = "poster_url"
            case startAt = "start_at"
            case clubName = "club_name"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id        = try c.decode(Int.self, forKey: .id)
            clubId    = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
            title     = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl) ?? ""
            startAt   = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
            clubName  = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        }

        var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    }

    let clubs: [Club]
    let events: [Event]

    var isEmpty: Bool { clubs.isEmpty && events.isEmpty }
}

extension APIClient {

    /// GET /clubs/map — vsi klubi s koordinatami (najvec 1000).
    func fetchMapClubs() async throws -> [MapClub] {
        let data = try await send(path: "clubs/map", method: "GET")
        do { return try JSONDecoder().decode([MapClub].self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    /// GET /search?q= — streznik zahteva vsaj 2 znaka; isce klube in dogodke.
    func search(_ query: String) async throws -> SearchResults {
        let data = try await send(path: "search", method: "GET",
                                  query: [URLQueryItem(name: "q", value: query)])
        do { return try JSONDecoder().decode(SearchResults.self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    /// GET /events/:id — poln dogodek (za EventDetailView iz zadetka iskanja).
    func fetchEvent(id: Int) async throws -> APIEvent {
        let data = try await send(path: "events/\(id)", method: "GET")
        do { return try JSONDecoder().decode(APIEvent.self, from: data) }
        catch { throw APIError.decodingFailed }
    }
}
