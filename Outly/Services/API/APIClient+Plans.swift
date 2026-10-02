import Foundation

// "I'm in" / nacrti prijateljev za dogodek (backend migracija 020, se gradi vzporedno). Martin, 23. 9. 2026.
// PUT    /events/:id/interest { plan: "going" | "interested" }  -> { plan }
// DELETE /events/:id/interest                                    -> { plan: null }  (409 event_ended na koncanem dogodku)
// GET    /events/:id (zeton neobvezen) dobi dodatna polja: my_plan, friends_going, friends_interested
// GET    /me/friends/plans: vsak dogodek ima poleg `friends` (= going) se `interested` in `my_plan`
// GET    /me/plans -> { events: [dogodek + club_name, club_logo_url, my_plan] }  (moji nacrti; UI za to ni v tem sklopu)
//
// Vsa nova polja imajo privzete vrednosti (pravilo 2: star backend jih se nima).

/// Moj odnos do dogodka. Neznana vrednost (star/nov backend s cim drugim) se dekodira kot nil,
/// da ne podre "I'm in" gumba na eno napacno vrstico.
enum EventPlan: String, Codable {
    case going
    case interested
}

/// Odgovor na PUT/DELETE /events/:id/interest.
private struct EventInterestResponse: Decodable {
    let plan: EventPlan?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p: EventPlan?? = try? c.decodeIfPresent(EventPlan.self, forKey: .plan)
        plan = p ?? nil
    }
    enum CodingKeys: String, CodingKey { case plan }
}

/// Tri nova polja iz GET /events/:id (+ `description`, ker ga lahki seznam GET /events?lite=true ne vrne),
/// dekodirana loceno od APIEvent (manj tvegano kot siriti obstojece dekodiranje, ki ga uporablja
/// fetchEvent(id:) brez zetona na vec mestih).
struct EventPlanInfo: Decodable {
    let myPlan: EventPlan?
    let friendsGoing: [FriendUser]
    let friendsInterested: [FriendUser]
    /// Opis dogodka; manjkajoc ali null -> "" (pravilo 2: privzeta vrednost).
    let description: String

    enum CodingKeys: String, CodingKey {
        case description
        case myPlan = "my_plan"
        case friendsGoing = "friends_going"
        case friendsInterested = "friends_interested"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p: EventPlan?? = try? c.decodeIfPresent(EventPlan.self, forKey: .myPlan)
        myPlan = p ?? nil
        friendsGoing = try c.decodeIfPresent([FriendUser].self, forKey: .friendsGoing) ?? []
        friendsInterested = try c.decodeIfPresent([FriendUser].self, forKey: .friendsInterested) ?? []
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
    }
}

extension APIClient {

    /// GET /events/:id z zetonom — samo za `my_plan` + prijatelje, ki gredo/jih zanima.
    /// Locena od fetchEvent(id:) v APIClient+Discover (ta ostane brez zetona, kot je bila).
    func fetchEventPlan(id: Int, token: String) async throws -> EventPlanInfo {
        let data = try await send(path: "events/\(id)", method: "GET", token: token)
        return try decode(EventPlanInfo.self, from: data)
    }

    /// PUT /events/:id/interest — nastavi "grem" ali "zanima me". 409 (event_ended) klicatelj
    /// prevede prek APIErrorMessages/userMessage kot za vsak drug klic.
    @discardableResult
    func setEventInterest(token: String, eventId: Int, plan: EventPlan) async throws -> EventPlan? {
        let data = try await send(path: "events/\(eventId)/interest", method: "PUT", token: token,
                                  json: ["plan": plan.rawValue])
        return try decode(EventInterestResponse.self, from: data).plan
    }

    /// DELETE /events/:id/interest — umakne "I'm in"/"Interested".
    func clearEventInterest(token: String, eventId: Int) async throws {
        _ = try await send(path: "events/\(eventId)/interest", method: "DELETE", token: token)
    }

    /// GET /me/plans — moji lastni nacrti (isti model kot FriendPlan: `friends`/`interested` bosta
    /// tu prazna, ker gre za moje dogodke, ne prijateljeve). UI zanj ni v tem sklopu (Martin, 23. 9.).
    func fetchMyPlans(token: String) async throws -> [FriendPlan] {
        let data = try await send(path: "me/plans", method: "GET", token: token)
        return try decode(MyPlansResponse.self, from: data).events
    }
}

private struct MyPlansResponse: Decodable {
    let events: [FriendPlan]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([FriendPlan].self, forKey: .events) ?? []
    }
    enum CodingKeys: String, CodingKey { case events }
}
