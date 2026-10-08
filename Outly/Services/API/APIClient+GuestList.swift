import Foundation

// Guest lista (backend 8. 10. 2026). Admin nastavi listo (dogodek + gostitelj + stevilo mest), gostitelj povabi PRIJATELJE;
// vsak dobi svojo vstopnico (QR) v Tickets, gostitelj tudi svojo. Poti:
// GET    /me/guest-lists                       -> { guest_lists: [GuestList] }  (star backend: 404 -> razdelek skrit)
// POST   /me/guest-lists/:id/invites           { user_ids: [Int], age_confirmed? } -> 201 { guest_list, added: [Int] }
// DELETE /me/guest-lists/:id/invites/:userId   -> 200 { guest_list }
// GET    /me/guest-list-invites/received       -> { invites: [GuestListInviteNotification] }  (neprebrana obvestila zvonca; 404 = brez vrstic)
// POST   /me/guest-list-invites/received/:id/seen -> { ok: true }  (idempotentno)
// GET /me ima novo polje pending_guest_list_invites (Me.pendingGuestListInvites, privzeto 0).
// Napake: 403 »You can only invite friends.«, 409 »Only N spots left.« / »<ime> is already on your guest list.« /
// »This guest list is closed.«, 400 { error: "age_confirmation_required", min_age }, 403 »<ime> is under N.«,
// 409 »Already checked in.« (odstranitev). Vsa polja imajo privzete vrednosti (pravilo 2).

// MARK: - Modeli

/// Dogodek, vezan na guest listo (podmnozica polj dogodka).
struct GuestListEvent: Decodable, Equatable {
    let id: Int
    let title: String
    let startAt: String
    let endAt: String?
    let posterUrl: String
    let clubId: Int
    let clubName: String
    let minAge: Int
    /// "published" | "cancelled"
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case startAt = "start_at"
        case endAt = "end_at"
        case posterUrl = "poster_url"
        case clubId = "club_id"
        case clubName = "club_name"
        case minAge = "min_age"
    }

    init(id: Int = 0, title: String = "", startAt: String = "", endAt: String? = nil, posterUrl: String = "",
         clubId: Int = 0, clubName: String = "", minAge: Int = 0, status: String = "published") {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.posterUrl = posterUrl
        self.clubId = clubId
        self.clubName = clubName
        self.minAge = minAge
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startAt = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
        endAt = (try? c.decodeIfPresent(String.self, forKey: .endAt)) ?? nil
        posterUrl = (try? c.decodeIfPresent(String.self, forKey: .posterUrl)) ?? ""
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        // Manjkajoca meja = brez kljukice starosti; streznik jo vseeno uveljavi (400 age_confirmation_required).
        minAge = try c.decodeIfPresent(Int.self, forKey: .minAge) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "published"
    }

    var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    var jeOdpovedan: Bool { status == "cancelled" }
}

/// Povabljen prijatelj na listi.
struct GuestListInvited: Decodable, Identifiable, Equatable {
    let userId: Int
    let username: String
    let avatarUrl: String?
    /// "valid" | "used"
    let status: String

    var id: Int { userId }
    /// Prijatelj je ze na vratih (vstopnica `used`): odstranitev ni mogoca (409 »Already checked in.«).
    var jeVstopil: Bool { status == "used" }

    enum CodingKeys: String, CodingKey {
        case username, status
        case userId = "user_id"
        case avatarUrl = "avatar_url"
    }

    init(userId: Int, username: String = "", avatarUrl: String? = nil, status: String = "valid") {
        self.userId = userId
        self.username = username
        self.avatarUrl = avatarUrl
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(Int.self, forKey: .userId)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarUrl = (try? c.decodeIfPresent(String.self, forKey: .avatarUrl)) ?? nil
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "valid"
    }
}

/// Moja guest lista (jaz sem gostitelj).
struct GuestList: Decodable, Identifiable, Equatable {
    let id: Int
    let event: GuestListEvent
    /// Koliko prijateljev lahko povabi (brez gostitelja).
    let spots: Int
    /// spots - aktivni povabljeni.
    let remaining: Int
    /// false: preklicana, dogodek koncan ali odpovedan.
    let canInvite: Bool
    /// Gostiteljeva vstopnica (je tudi v GET /me/tickets).
    let myTicketId: Int?
    /// Opomba admina (lahko prazna).
    let note: String
    let invited: [GuestListInvited]

    enum CodingKeys: String, CodingKey {
        case id, event, spots, remaining, note, invited
        case canInvite = "can_invite"
        case myTicketId = "my_ticket_id"
    }

    init(id: Int, event: GuestListEvent = GuestListEvent(), spots: Int = 0, remaining: Int = 0, canInvite: Bool = false,
         myTicketId: Int? = nil, note: String = "", invited: [GuestListInvited] = []) {
        self.id = id
        self.event = event
        self.spots = spots
        self.remaining = remaining
        self.canInvite = canInvite
        self.myTicketId = myTicketId
        self.note = note
        self.invited = invited
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        event = (try? c.decodeIfPresent(GuestListEvent.self, forKey: .event)) ?? GuestListEvent()
        spots = try c.decodeIfPresent(Int.self, forKey: .spots) ?? 0
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
        // Manjkajoce polje = ne vabi (varneje): streznik tako ali tako zavrne 409 »This guest list is closed.«
        canInvite = try c.decodeIfPresent(Bool.self, forKey: .canInvite) ?? false
        myTicketId = (try? c.decodeIfPresent(Int.self, forKey: .myTicketId)) ?? nil
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        invited = try c.decodeIfPresent([GuestListInvited].self, forKey: .invited) ?? []
    }

    /// Mojih ze povabljenih prijateljev (za izkljucitev iz izbire).
    var povabljeniIdji: Set<Int> { Set(invited.map(\.userId)) }
    /// Povabilo je mogoce: lista je odprta in so mesta prosta.
    var lahkoVabi: Bool { canInvite && remaining > 0 }
}

/// Obvestilo v zvoncu: »@gostitelj te je dodal na svojo guest listo« (GET /me/guest-list-invites/received).
/// `id` je id clanstva (guest_list_members.id), `ticketId` moja vstopnica (je v GET /me/tickets).
struct GuestListInviteNotification: Decodable, Identifiable, Equatable {
    let id: Int
    let guestListId: Int
    let ticketId: Int
    let hostUsername: String
    let hostAvatarUrl: String?
    let createdAt: String
    let event: GuestListEvent

    enum CodingKeys: String, CodingKey {
        case id, event
        case guestListId = "guest_list_id"
        case ticketId = "ticket_id"
        case hostUsername = "host_username"
        case hostAvatarUrl = "host_avatar_url"
        case createdAt = "created_at"
    }

    init(id: Int, guestListId: Int = 0, ticketId: Int = 0, hostUsername: String = "", hostAvatarUrl: String? = nil,
         createdAt: String = "", event: GuestListEvent = GuestListEvent()) {
        self.id = id
        self.guestListId = guestListId
        self.ticketId = ticketId
        self.hostUsername = hostUsername
        self.hostAvatarUrl = hostAvatarUrl
        self.createdAt = createdAt
        self.event = event
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guestListId = (try? c.decodeIfPresent(Int.self, forKey: .guestListId)) ?? 0
        ticketId = (try? c.decodeIfPresent(Int.self, forKey: .ticketId)) ?? 0
        hostUsername = (try? c.decodeIfPresent(String.self, forKey: .hostUsername)) ?? ""
        hostAvatarUrl = (try? c.decodeIfPresent(String.self, forKey: .hostAvatarUrl)) ?? nil
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        event = (try? c.decodeIfPresent(GuestListEvent.self, forKey: .event)) ?? GuestListEvent()
    }

    /// "Sat 26 Sep · 22:00" ali prazen niz, ce datuma ne moremo razbrati (isti zapis kot ClubEventNotification).
    var displayDayTime: String {
        guard let d = event.startDate else { return "" }
        let f = DateFormatter()
        f.locale = Jezik.shared.locale
        f.dateFormat = "EEE d MMM · HH:mm"
        return f.string(from: d)
    }

    /// Podnaslov vrstice v zvoncu: »naslov dogodka · klub · datum«; prazni deli odpadejo.
    var podnaslov: String {
        [event.title, event.clubName, displayDayTime].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct GuestListInvitesReceivedResponse: Decodable {
    let invites: [GuestListInviteNotification]

    enum CodingKeys: String, CodingKey { case invites }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invites = try c.decodeIfPresent([GuestListInviteNotification].self, forKey: .invites) ?? []
    }
}

/// Odgovor POST /me/guest-lists/:id/invites.
struct GuestListInviteResult: Decodable {
    let guestList: GuestList
    let added: [Int]

    enum CodingKeys: String, CodingKey {
        case added
        case guestList = "guest_list"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guestList = try c.decode(GuestList.self, forKey: .guestList)
        added = try c.decodeIfPresent([Int].self, forKey: .added) ?? []
    }
}

private struct GuestListsResponse: Decodable {
    let guestLists: [GuestList]

    enum CodingKeys: String, CodingKey { case guestLists = "guest_lists" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guestLists = try c.decodeIfPresent([GuestList].self, forKey: .guestLists) ?? []
    }
}

private struct GuestListResponse: Decodable {
    let guestList: GuestList

    enum CodingKeys: String, CodingKey { case guestList = "guest_list" }
}

// MARK: - Klici

extension APIClient {

    /// GET /me/guest-lists — moje liste (jaz sem gostitelj). Star backend poti se nima (404): to je »ni list«, ne napaka,
    /// zato razdelek v Tickets ostane skrit. Vse drugo (omrezje, 5xx) se vrze naprej.
    func fetchMyGuestLists(token: String) async throws -> [GuestList] {
        do {
            let data = try await send(path: "me/guest-lists", method: "GET", token: token)
            return try decode(GuestListsResponse.self, from: data).guestLists
        } catch let api as APIError {
            if APIClient.jeStarBackendBrezGuestList(api) { return [] }
            throw api
        }
    }

    /// 404 pri GET /me/guest-lists = backend poti se nima.
    static func jeStarBackendBrezGuestList(_ napaka: APIError) -> Bool {
        if case .requestFailed(404, _) = napaka { return true }
        return false
    }

    /// POST /me/guest-lists/:id/invites — povabi prijatelje (vse ali nic). `ageConfirmed` samo pri dogodku z mejo.
    func inviteToGuestList(token: String, listId: Int, userIds: [Int], ageConfirmed: Bool = false) async throws -> GuestListInviteResult {
        let data = try await send(path: "me/guest-lists/\(listId)/invites", method: "POST", token: token,
                                  json: APIClient.teloVabila(userIds: userIds, ageConfirmed: ageConfirmed))
        return try decode(GuestListInviteResult.self, from: data)
    }

    /// Telo POST /me/guest-lists/:id/invites: `age_confirmed` samo, ko je kljukica oznacena.
    static func teloVabila(userIds: [Int], ageConfirmed: Bool) -> [String: Any] {
        var telo: [String: Any] = ["user_ids": userIds]
        if ageConfirmed { telo["age_confirmed"] = true }
        return telo
    }

    /// DELETE /me/guest-lists/:id/invites/:userId — odstrani povabljenega (njegova vstopnica postane neveljavna, mesto se sprosti).
    func removeGuestListInvite(token: String, listId: Int, userId: Int) async throws -> GuestList {
        let data = try await send(path: "me/guest-lists/\(listId)/invites/\(userId)", method: "DELETE", token: token)
        return try decode(GuestListResponse.self, from: data).guestList
    }

    /// GET /me/guest-list-invites/received — neprebrana obvestila »X te je dodal na guest listo«. Star backend poti se nima
    /// (404): to je »brez vrstic«, ne napaka. Vse drugo (omrezje, 5xx) se vrze naprej.
    func fetchReceivedGuestListInvites(token: String) async throws -> [GuestListInviteNotification] {
        do {
            let data = try await send(path: "me/guest-list-invites/received", method: "GET", token: token)
            return try decode(GuestListInvitesReceivedResponse.self, from: data).invites
        } catch let api as APIError {
            if APIClient.jeStarBackendBrezGuestList(api) { return [] }
            throw api
        }
    }

    /// Obvestilo o vabilu na guest listo je prebrano (dotik v zvoncu). Idempotentno.
    func markGuestListInviteSeen(token: String, id: Int) async throws {
        _ = try await send(path: "me/guest-list-invites/received/\(id)/seen", method: "POST", token: token)
    }
}
