import Foundation

// Ekipa kluba (migracija 009): lastnik + managerji + vratarji.
// Backend: GET/POST /business/team, DELETE /business/team/:userId, DELETE /business/team/me.
// Lastnik sme vse; manager sme dodajati in odstranjevati samo vratarje.

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
        case "owner": return "Owner"
        case "manager": return "Manager"
        default: return "Door staff"
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

/// Odgovor GET/POST/DELETE /business/team.
struct TeamResponse: Decodable {
    /// Vloga prijavljenega: "owner" | "manager" | "admin".
    let myRole: String
    let members: [TeamMember]

    enum CodingKeys: String, CodingKey {
        case members
        case myRole = "my_role"
    }
}

extension APIClient {

    func fetchTeam(token: String) async throws -> TeamResponse {
        let data = try await send(path: "business/team", method: "GET", token: token)
        return try decode(TeamResponse.self, from: data)
    }

    /// role: "manager" ali "doorman". Uporabnik mora ze imeti Outly racun (sicer 404 no_account).
    func addTeamMember(token: String, email: String, role: String) async throws -> TeamResponse {
        let data = try await send(path: "business/team", method: "POST", token: token,
                                  json: ["email": email, "role": role])
        return try decode(TeamResponse.self, from: data)
    }

    func removeTeamMember(token: String, userId: Int) async throws -> TeamResponse {
        let data = try await send(path: "business/team/\(userId)", method: "DELETE", token: token)
        return try decode(TeamResponse.self, from: data)
    }

    /// Clan (tudi vratar) sam zapusti ekipo. 204 brez telesa.
    func leaveTeam(token: String) async throws {
        _ = try await send(path: "business/team/me", method: "DELETE", token: token)
    }
}
