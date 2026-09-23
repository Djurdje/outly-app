import Foundation

// Prijatelji (backend migracija 016, outly-backend PR #45). Martin, 20. 9. 2026.
// GET  /users/search?q=            -> { users: [UserSearchResult] }
// GET  /me/friends                 -> { friends: [FriendUser], requests_in: [FriendRequest], requests_out: [FriendRequest] }
// POST /me/friends/requests        -> 201 { request } ali 200 { friend } (nasprotna prosnja je ze cakala)
// POST /me/friends/requests/:id/accept | decline, DELETE /me/friends/requests/:id (preklic lastne)
// DELETE /me/friends/:userId
// GET  /me/friends/plans           -> { events: [FriendPlan] }  (samo prijatelji z vklopljenim deljenjem)
// POST /tickets/:id/transfer { user_id }  (samo prijatelju)
// GET  /me/tickets/received        -> { received: [ReceivedTicket] }  (neprebrana obvestila, migracija 017)
// POST /me/tickets/received/:id/seen
//
// O tujem uporabniku backend vrne SAMO id, username in avatar_url (invarianta I11) —
// modeli tu drugega ne pricakujejo. Vsa nova polja imajo privzete vrednosti (pravilo 2).

/// Tuj uporabnik, kot ga smemo videti: id, uporabnisko ime, slika.
struct FriendUser: Decodable, Identifiable, Hashable {
    let id: Int
    let username: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarUrl = "avatar_url"
    }

    init(id: Int, username: String, avatarUrl: String?) {
        self.id = id
        self.username = username
        self.avatarUrl = avatarUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
}

/// Zadetek iskanja: uporabnik + odnos do mene.
struct UserSearchResult: Decodable, Identifiable {
    /// "none" iz API-ja je tu `nobody`, da se ne meša z Optional.none.
    enum Relation: String, Decodable {
        case nobody = "none"
        case friends
        case requestSent = "request_sent"
        case requestReceived = "request_received"
    }

    let id: Int
    let username: String
    let avatarUrl: String?
    let relation: Relation

    enum CodingKeys: String, CodingKey {
        case id, username, relation
        case avatarUrl = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        let rel: Relation?? = try? c.decodeIfPresent(Relation.self, forKey: .relation)
        relation = (rel ?? nil) ?? Relation.nobody
    }

    var user: FriendUser { FriendUser(id: id, username: username, avatarUrl: avatarUrl) }
}

/// Cakajoca prosnja: id prosnje in drugi uporabnik (posiljatelj pri prejetih, naslovnik pri poslanih).
struct FriendRequest: Decodable, Identifiable {
    let id: Int
    let createdAt: String
    let user: FriendUser

    enum CodingKeys: String, CodingKey {
        case id, user
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        user = try c.decode(FriendUser.self, forKey: .user)
    }
}

struct MyFriendsResponse: Decodable {
    let friends: [FriendUser]
    let requestsIn: [FriendRequest]
    let requestsOut: [FriendRequest]

    enum CodingKeys: String, CodingKey {
        case friends
        case requestsIn = "requests_in"
        case requestsOut = "requests_out"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        friends = try c.decodeIfPresent([FriendUser].self, forKey: .friends) ?? []
        requestsIn = try c.decodeIfPresent([FriendRequest].self, forKey: .requestsIn) ?? []
        requestsOut = try c.decodeIfPresent([FriendRequest].self, forKey: .requestsOut) ?? []
    }
}

/// Odgovor na poslano prosnjo: ali prosnja caka (request) ali sta ze prijatelja (friend).
struct FriendRequestResponse: Decodable {
    let request: FriendRequest?
    let friend: FriendUser?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r: FriendRequest?? = try? c.decodeIfPresent(FriendRequest.self, forKey: .request)
        let f: FriendUser?? = try? c.decodeIfPresent(FriendUser.self, forKey: .friend)
        request = r ?? nil
        friend = f ?? nil
    }
    enum CodingKeys: String, CodingKey { case request, friend }
}

private struct UserSearchResponse: Decodable {
    let users: [UserSearchResult]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users = try c.decodeIfPresent([UserSearchResult].self, forKey: .users) ?? []
    }
    enum CodingKeys: String, CodingKey { case users }
}

private struct AcceptFriendResponse: Decodable {
    let friend: FriendUser
}

/// Dogodek, na katerega gre vsaj en prijatelj: isti stolpci kot GET /events (APIEvent)
/// plus ime/logo kluba in seznam prijateljev.
/// `interested` in `myPlan` sta nova (backend migracija 020, 23. 9. 2026) — star backend ju
/// se nima, zato privzeto prazen seznam / nil (pravilo 2).
struct FriendPlan: Decodable, Identifiable {
    let event: APIEvent
    let clubName: String
    let clubLogoUrl: String
    /// Prijatelji, ki GREJO (vstopnica). Ime `friends` je ostalo zaradi obratne zdruzljivosti.
    let friends: [FriendUser]
    /// Prijatelji, ki jih dogodek ZANIMA (brez vstopnice).
    let interested: [FriendUser]
    /// Moj lasten odnos do dogodka (na /me/plans je to skoraj vedno .going).
    let myPlan: EventPlan?

    var id: Int { event.id }

    enum CodingKeys: String, CodingKey {
        case friends, interested
        case clubName = "club_name"
        case clubLogoUrl = "club_logo_url"
        case myPlan = "my_plan"
    }

    init(from decoder: Decoder) throws {
        event = try APIEvent(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        clubLogoUrl = try c.decodeIfPresent(String.self, forKey: .clubLogoUrl) ?? ""
        friends = try c.decodeIfPresent([FriendUser].self, forKey: .friends) ?? []
        interested = try c.decodeIfPresent([FriendUser].self, forKey: .interested) ?? []
        let p: EventPlan?? = try? c.decodeIfPresent(EventPlan.self, forKey: .myPlan)
        myPlan = p ?? nil
    }
}

/// Obvestilo "X sent you a ticket" (GET /me/tickets/received, backend migracija 017).
/// `id` je id prenosa (ne vstopnice); `from` je nil, ce je posiljatelj izbrisal racun.
struct ReceivedTicket: Decodable, Identifiable {
    let id: Int
    let ticketId: Int
    let eventId: Int
    let eventTitle: String
    let clubName: String
    let from: FriendUser?

    enum CodingKeys: String, CodingKey {
        case id, from
        case ticketId = "ticket_id"
        case eventId = "event_id"
        case eventTitle = "event_title"
        case clubName = "club_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        ticketId = try c.decodeIfPresent(Int.self, forKey: .ticketId) ?? 0
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        eventTitle = try c.decodeIfPresent(String.self, forKey: .eventTitle) ?? ""
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        from = try? c.decodeIfPresent(FriendUser.self, forKey: .from)
    }
}

private struct ReceivedTicketsResponse: Decodable {
    let received: [ReceivedTicket]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        received = try c.decodeIfPresent([ReceivedTicket].self, forKey: .received) ?? []
    }
    enum CodingKeys: String, CodingKey { case received }
}

private struct FriendPlansResponse: Decodable {
    let events: [FriendPlan]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([FriendPlan].self, forKey: .events) ?? []
    }
    enum CodingKeys: String, CodingKey { case events }
}

extension APIClient {

    /// GET /users/search?q= — predpona uporabniskega imena (2-20 znakov: crke, stevke, podcrtaj).
    func searchUsers(token: String, query: String) async throws -> [UserSearchResult] {
        let data = try await send(path: "users/search", method: "GET", token: token,
                                  query: [URLQueryItem(name: "q", value: query)])
        return try decode(UserSearchResponse.self, from: data).users
    }

    func fetchMyFriends(token: String) async throws -> MyFriendsResponse {
        let data = try await send(path: "me/friends", method: "GET", token: token)
        return try decode(MyFriendsResponse.self, from: data)
    }

    /// Poslje prosnjo. Ce je nasprotna prosnja ze cakala, sta takoj prijatelja (friend != nil).
    func sendFriendRequest(token: String, userId: Int) async throws -> FriendRequestResponse {
        let data = try await send(path: "me/friends/requests", method: "POST", token: token, json: ["user_id": userId])
        return try decode(FriendRequestResponse.self, from: data)
    }

    func acceptFriendRequest(token: String, requestId: Int) async throws -> FriendUser {
        let data = try await send(path: "me/friends/requests/\(requestId)/accept", method: "POST", token: token)
        return try decode(AcceptFriendResponse.self, from: data).friend
    }

    func declineFriendRequest(token: String, requestId: Int) async throws {
        _ = try await send(path: "me/friends/requests/\(requestId)/decline", method: "POST", token: token)
    }

    /// Preklice lastno poslano prosnjo.
    func cancelFriendRequest(token: String, requestId: Int) async throws {
        _ = try await send(path: "me/friends/requests/\(requestId)", method: "DELETE", token: token)
    }

    func removeFriend(token: String, userId: Int) async throws {
        _ = try await send(path: "me/friends/\(userId)", method: "DELETE", token: token)
    }

    /// GET /me/friends/plans — prihajajoci dogodki, na katere gredo prijatelji (z vklopljenim deljenjem).
    func fetchFriendsPlans(token: String) async throws -> [FriendPlan] {
        let data = try await send(path: "me/friends/plans", method: "GET", token: token)
        return try decode(FriendPlansResponse.self, from: data).events
    }

    /// GET /me/tickets/received — neprebrana obvestila o prejetih vstopnicah.
    func fetchReceivedTickets(token: String) async throws -> [ReceivedTicket] {
        let data = try await send(path: "me/tickets/received", method: "GET", token: token)
        return try decode(ReceivedTicketsResponse.self, from: data).received
    }

    /// Obvestilo o prejeti vstopnici je prebrano (dotik v meniju). Idempotentno.
    func markReceivedTicketSeen(token: String, id: Int) async throws {
        _ = try await send(path: "me/tickets/received/\(id)/seen", method: "POST", token: token)
    }

    /// Prenos vstopnice prijatelju iz seznama (po id). Streznik dovoli samo prijatelju.
    func transferTicket(token: String, ticketId: Int, userId: Int) async throws -> TransferResponse {
        let data = try await send(path: "tickets/\(ticketId)/transfer", method: "POST", token: token,
                                  json: ["user_id": userId])
        return try decode(TransferResponse.self, from: data)
    }
}
