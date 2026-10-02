import Foundation

// Sledenje klubom in obvestila o novih dogodkih (backend migracija 019, PR #55).
// PUT    /clubs/:id/follow          -> { following, followers_count }
// DELETE /clubs/:id/follow          -> { following, followers_count }
// GET    /me/clubs/following        -> { ids: [Int], clubs: [APIClub] }
// GET    /me/club-events            -> { notifications: [ClubEventNotification] }
// POST   /me/club-events/:id/seen
// GET    /events?clubId=X&popular=true -> [APIEvent] (najvec 3 koncani, po prodanih vstopnicah)
//
// Lajkanja kluba NI: srcek ostane samo na dogodkih (FavoritesStore). Glej DECISIONS 22. 9. 2026.

/// Odgovor obeh poti za sledenje.
struct FollowState: Decodable {
    let following: Bool
    let followersCount: Int

    enum CodingKeys: String, CodingKey {
        case following
        case followersCount = "followers_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        following = (try? c.decodeIfPresent(Bool.self, forKey: .following)) ?? false
        followersCount = (try? c.decodeIfPresent(Int.self, forKey: .followersCount)) ?? 0
    }
}

/// Eno obvestilo "klub, ki mu slediš, je objavil dogodek".
struct ClubEventNotification: Decodable, Identifiable {
    let id: Int
    let eventId: Int
    let eventTitle: String
    let startAt: String
    let posterUrl: String
    let clubId: Int
    let clubName: String
    let clubLogoUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case eventTitle = "event_title"
        case startAt = "start_at"
        case posterUrl = "poster_url"
        case clubId = "club_id"
        case clubName = "club_name"
        case clubLogoUrl = "club_logo_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(Int.self, forKey: .id)
        eventId     = (try? c.decodeIfPresent(Int.self, forKey: .eventId)) ?? 0
        eventTitle  = (try? c.decodeIfPresent(String.self, forKey: .eventTitle)) ?? ""
        startAt     = (try? c.decodeIfPresent(String.self, forKey: .startAt)) ?? ""
        posterUrl   = (try? c.decodeIfPresent(String.self, forKey: .posterUrl)) ?? ""
        clubId      = (try? c.decodeIfPresent(Int.self, forKey: .clubId)) ?? 0
        clubName    = (try? c.decodeIfPresent(String.self, forKey: .clubName)) ?? ""
        clubLogoUrl = (try? c.decodeIfPresent(String.self, forKey: .clubLogoUrl)) ?? ""
    }

    /// "Sat 26 Sep · 22:00" ali prazen niz, ce datuma ne moremo razbrati.
    var displayDayTime: String {
        guard let d = DateParsing.parseBackendDate(startAt) else { return "" }
        let f = DateFormatter()
        f.locale = Jezik.shared.locale
        f.dateFormat = "EEE d MMM · HH:mm"
        return f.string(from: d)
    }
}

extension APIClient {

    private struct FollowingResponse: Decodable {
        let ids: [Int]
        let clubs: [APIClub]
    }

    private struct ClubEventsResponse: Decodable {
        let notifications: [ClubEventNotification]
    }

    /// Sledi / prenehaj slediti. Obe poti sta na strezniku idempotentni.
    @discardableResult
    func setFollowClub(token: String, clubId: Int, follow: Bool) async throws -> FollowState {
        let data = try await send(path: "clubs/\(clubId)/follow", method: follow ? "PUT" : "DELETE", token: token)
        return try decode(FollowState.self, from: data)
    }

    /// Klubi, ki jim sledim.
    func fetchFollowedClubs(token: String) async throws -> (ids: [Int], clubs: [APIClub]) {
        let data = try await send(path: "me/clubs/following", method: "GET", token: token)
        let r = try decode(FollowingResponse.self, from: data)
        return (r.ids, r.clubs)
    }

    /// Neprebrana obvestila o dogodkih klubov, ki jim sledim.
    func fetchClubEventNotifications(token: String) async throws -> [ClubEventNotification] {
        let data = try await send(path: "me/club-events", method: "GET", token: token)
        return try decode(ClubEventsResponse.self, from: data).notifications
    }

    /// Obvestilo je prebrano (zvonec ga ne kaze vec).
    func markClubEventSeen(token: String, id: Int) async throws {
        _ = try await send(path: "me/club-events/\(id)/seen", method: "POST", token: token)
    }

    /// Najvec 3 "popular" (koncani) dogodki kluba, po prodanih vstopnicah.
    /// Loceno od fetchEvents(clubId:upcoming:false), ki drzi okno 7 dni.
    func fetchPopularEvents(clubId: Int) async throws -> [APIEvent] {
        let data = try await send(path: "events", method: "GET", query: [
            URLQueryItem(name: "clubId", value: "\(clubId)"),
            URLQueryItem(name: "popular", value: "true"),
            URLQueryItem(name: "lite", value: "true"),   // seznam: brez `description` (EventDetailView ga nalozi sam)
        ])
        return try decode([APIEvent].self, from: data)
    }

    /// Posnetek koncanega dogodka (PATCH /events/:id, samo polje recapVideoUrl).
    /// Prazen niz odstrani posnetek. Streznik zavrne dogodek, ki ni koncan ali ni med prvimi tremi.
    @discardableResult
    func setRecapVideo(token: String, eventId: Int, url: String) async throws -> APIEvent {
        let data = try await send(path: "events/\(eventId)", method: "PATCH", token: token,
                                  json: ["recapVideoUrl": url])
        return try decode(APIEvent.self, from: data)
    }
}
