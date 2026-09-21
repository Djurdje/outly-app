import Foundation

// Ekipa kluba (migracija 009): lastnik + managerji + vratarji.
// Backend: GET/POST /business/team, DELETE /business/team/:userId, DELETE /business/team/me,
// DELETE /business/team/invites/:id. Lastnik sme vse; manager sme vabiti in odstranjevati samo vratarje.
// Od migracije 013 POST /business/team ustvari VABILO (TeamInvite); clan nastane,
// ko uporabnik vabilo sprejme v aplikaciji (My clubs -> zvonec).

/// Ena vrstica ekipe. Lastnik pride kot prva vrstica z role "owner".
struct TeamMember: Decodable, Identifiable {
    let userId: Int
    let username: String
    let email: String
    let avatarUrl: String?
    /// "owner" | "manager" | "doorman"
    let role: String
    let createdAt: String
    let invitedByUserId: Int?

    var id: Int { userId }

    enum CodingKeys: String, CodingKey {
        case username, email, role
        case userId = "user_id"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case invitedByUserId = "invited_by_user_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(Int.self, forKey: .userId)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "doorman"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        invitedByUserId = try c.decodeIfPresent(Int.self, forKey: .invitedByUserId)
    }

    var roleLabel: String {
        switch role {
        case "owner": return String(localized: "Owner")
        case "manager": return String(localized: "Manager")
        default: return String(localized: "Door staff")
        }
    }

    var roleIcon: String {
        switch role {
        case "owner": return "key.fill"
        case "manager": return "person.text.rectangle"
        default: return "qrcode.viewfinder"
        }
    }
}

/// Cakajoce vabilo kluba (GET /business/team -> invites[]).
struct TeamInvite: Decodable, Identifiable {
    let id: Int
    let userId: Int
    let username: String
    let email: String
    let avatarUrl: String?
    let role: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, username, email, role
        case userId = "user_id"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        userId = try c.decodeIfPresent(Int.self, forKey: .userId) ?? 0
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "doorman"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    var roleLabel: String { role == "manager" ? String(localized: "Manager") : String(localized: "Door staff") }
}

/// Odgovor GET/POST/DELETE /business/team.
struct TeamResponse: Decodable {
    /// Vloga prijavljenega: "owner" | "manager" | "admin".
    let myRole: String
    let members: [TeamMember]
    /// Cakajoca vabila (prazno pri starem backendu brez migracije 013).
    let invites: [TeamInvite]

    enum CodingKeys: String, CodingKey {
        case members, invites
        case myRole = "my_role"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        myRole = try c.decodeIfPresent(String.self, forKey: .myRole) ?? ""
        members = try c.decodeIfPresent([TeamMember].self, forKey: .members) ?? []
        invites = try c.decodeIfPresent([TeamInvite].self, forKey: .invites) ?? []
    }
}

extension APIClient {

    func fetchTeam(token: String) async throws -> TeamResponse {
        let data = try await send(path: "business/team", method: "GET", token: token)
        return try decode(TeamResponse.self, from: data)
    }

    /// Poslje VABILO (role: "manager" ali "doorman"). Uporabnik mora ze imeti Outly racun
    /// (sicer 404 no_account); 409 already_invited, ce vabilo ze caka.
    func addTeamMember(token: String, email: String, role: String) async throws -> TeamResponse {
        let data = try await send(path: "business/team", method: "POST", token: token,
                                  json: ["email": email, "role": role])
        return try decode(TeamResponse.self, from: data)
    }

    func removeTeamMember(token: String, userId: Int) async throws -> TeamResponse {
        let data = try await send(path: "business/team/\(userId)", method: "DELETE", token: token)
        return try decode(TeamResponse.self, from: data)
    }

    /// Preklice cakajoce vabilo (lastnik vsa, manager samo vratarjeva).
    func cancelTeamInvite(token: String, inviteId: Int) async throws -> TeamResponse {
        let data = try await send(path: "business/team/invites/\(inviteId)", method: "DELETE", token: token)
        return try decode(TeamResponse.self, from: data)
    }

    /// Clan (tudi vratar) sam zapusti ekipo. 204 brez telesa.
    func leaveTeam(token: String) async throws {
        _ = try await send(path: "business/team/me", method: "DELETE", token: token)
    }
}

/// Klub, ki ga uporabnik trenutno ureja (My Clubs -> View). Vsak klic APIClient.send doda glavo
/// X-Outly-Club s to vrednostjo (backend 018: oseba je lahko v vec ekipah). nil = brez glave ->
/// streznik vzame prvo clanstvo (in lastnikov klub), kot pred 018.
/// MyClubsView (seznam) ga pobrise, MyClubDetailView ga nastavi; globlji zasloni ga podedujejo.
enum IzbraniKlub {
    nonisolated(unsafe) static var id: Int?
}
