import Foundation

// Dogodki za poslovni racun: seznam lastnega kluba, ustvarjanje, urejanje, odpoved.
// Backend: GET /business/clubs/me, GET /business/events, POST /events,
// PATCH /events/:id, DELETE /events/:id.

extension APIClient {

    /// GET /business/clubs/me — klub prijavljenega poslovnega uporabnika.
    func fetchMyBusinessClub(token: String) async throws -> APIClub {
        let data = try await send(path: "business/clubs/me", method: "GET", token: token)
        do { return try JSONDecoder().decode(APIClub.self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    /// GET /business/events — VSI dogodki lastnega kluba (tudi osnutki in odpovedani),
    /// ki jih javni GET /events ne vraca.
    func fetchMyBusinessEvents(token: String) async throws -> [APIEvent] {
        let data = try await send(path: "business/events", method: "GET", token: token)
        do { return try JSONDecoder().decode([APIEvent].self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    /// Polja obrazca za dogodek. Zneski v centih kot celo stevilo — nikoli v plavajoci vejici.
    struct EventDraft {
        var title: String
        var description: String
        var startAt: Date
        var endAt: Date?
        var minAge: Int
        /// nil = polja `genres` ne posljemo (PATCH zanrov ne spremeni, POST podeduje zanre kluba). Glej `ZanriDogodka`.
        var genres: [String]?
        var ticketPriceCents: Int?
        var ticketUrl: String
        var posterUrl: String
        var status: String   // "draft" | "published" | "cancelled"
        /// Zaloga (Figma "Create event": Capacity). nil = brez omejitve.
        var capacity: Int? = nil

        /// Prizorisce (backend 037, organizatorji brez lastnega kluba). `posljiPrizorisce` = false
        /// (privzeto, navaden klub): kljucev prizorisca sploh ne posljemo, da PATCH ne povozi obstojecih.
        /// Organizator jih posilja vedno, da lahko preklopi med klubom gostiteljem in prosto lokacijo.
        var posljiPrizorisce: Bool = false
        var venueClubId: Int? = nil
        var venueName: String = ""
        var venueAddress: String = ""
        var venueCity: String = ""
        var venueLat: Double? = nil
        var venueLng: Double? = nil

        static let isoOut: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        var json: [String: Any] {
            var j: [String: Any] = [
                "title": title,
                "description": description,
                "startAt": Self.isoOut.string(from: startAt),
                "minAge": minAge,
                "status": status,
                "currency": "EUR",
                "ticketUrl": ticketUrl,
                "posterUrl": posterUrl,
            ]
            if let genres { j["genres"] = genres }
            if let endAt { j["endAt"] = Self.isoOut.string(from: endAt) } else { j["endAt"] = NSNull() }
            if let ticketPriceCents { j["ticketPriceCents"] = ticketPriceCents } else { j["ticketPriceCents"] = NSNull() }
            if let capacity { j["capacity"] = capacity } else { j["capacity"] = NSNull() }
            if posljiPrizorisce {
                if let venueClubId {
                    // Klub gostitelj: streznik venue_name/address/city/lat/lng ignorira.
                    j["venueClubId"] = venueClubId
                    j["venueName"] = ""
                    j["venueAddress"] = ""
                    j["venueCity"] = ""
                    j["venueLat"] = NSNull()
                    j["venueLng"] = NSNull()
                } else {
                    j["venueClubId"] = NSNull()
                    j["venueName"] = venueName
                    j["venueAddress"] = venueAddress
                    j["venueCity"] = venueCity
                    // Koordinati gresta v paru.
                    if let venueLat, let venueLng {
                        j["venueLat"] = venueLat
                        j["venueLng"] = venueLng
                    } else {
                        j["venueLat"] = NSNull()
                        j["venueLng"] = NSNull()
                    }
                }
            }
            return j
        }
    }

    /// POST /events. Vrne ustvarjeni dogodek.
    func createEvent(token: String, clubId: Int, draft: EventDraft) async throws -> APIEvent {
        var body = draft.json
        body["clubId"] = clubId
        let data = try await send(path: "events", method: "POST", token: token, json: body)
        do { return try JSONDecoder().decode(APIEvent.self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    /// PATCH /events/:id. Vrne posodobljeni dogodek.
    func updateEvent(token: String, id: Int, draft: EventDraft) async throws -> APIEvent {
        let data = try await send(path: "events/\(id)", method: "PATCH", token: token, json: draft.json)
        do { return try JSONDecoder().decode(APIEvent.self, from: data) }
        catch { throw APIError.decodingFailed }
    }

    /// DELETE /events/:id. Dogodek s prodanimi vstopnicami streznik odpove namesto izbrise.
    /// Vrne true, ce je bil izbrisan, false, ce je bil odpovedan.
    func deleteEvent(token: String, id: Int) async throws -> Bool {
        let data = try await send(path: "events/\(id)", method: "DELETE", token: token)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["event"] != nil {
            return false
        }
        return true
    }
}
