import Foundation

// Moja vabila v ekipo kluba (migracija 013). Figma "My clubs inv" / "My clubs con".
// GET /me/invites -> { invites: [MyInvite] }
// POST /me/invites/:id/accept -> { club: {id, name, logo_url}, role, invites: [] }
// POST /me/invites/:id/decline -> { invites: [MyInvite] }

/// Cakajoce vabilo, kot ga vidi povabljeni uporabnik.
struct MyInvite: Decodable, Identifiable {
    let id: Int
    let clubId: Int
    let clubName: String
    let clubLogoUrl: String
    let clubCity: String
    /// "manager" | "doorman" | "bartender"
    let role: String
    let createdAt: String
    let invitedByUsername: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case clubId = "club_id"
        case clubName = "club_name"
        case clubLogoUrl = "club_logo_url"
        case clubCity = "club_city"
        case createdAt = "created_at"
        case invitedByUsername = "invited_by_username"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? String(localized: "A club")
        clubLogoUrl = try c.decodeIfPresent(String.self, forKey: .clubLogoUrl) ?? ""
        clubCity = try c.decodeIfPresent(String.self, forKey: .clubCity) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "doorman"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        invitedByUsername = try c.decodeIfPresent(String.self, forKey: .invitedByUsername)
    }

    var roleLabel: String {
        switch role {
        case "manager": return String(localized: "Manager")
        case "bartender": return String(localized: "Bartender")
        default: return String(localized: "Door staff")
        }
    }

    /// Kaj vloga prinese (besedilo na kartici vabila, Figma 370:1050).
    var roleDescription: String {
        switch role {
        case "manager": return String(localized: "event management, sales and ticket scanning")
        case "bartender": return String(localized: "serving VIP tables")
        default: return String(localized: "ticket scanning at the door")
        }
    }
}

struct MyInvitesResponse: Decodable {
    let invites: [MyInvite]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invites = try c.decodeIfPresent([MyInvite].self, forKey: .invites) ?? []
    }
    enum CodingKeys: String, CodingKey { case invites }
}

/// Odgovor na sprejem vabila: klub in vloga, ki ju je uporabnik dobil.
struct AcceptInviteResponse: Decodable {
    struct Club: Decodable {
        let id: Int
        let name: String
        let logoUrl: String?
        enum CodingKeys: String, CodingKey { case id, name; case logoUrl = "logo_url" }
    }
    let club: Club
    let role: String
}

extension APIClient {

    func fetchMyInvites(token: String) async throws -> [MyInvite] {
        let data = try await send(path: "me/invites", method: "GET", token: token)
        return try decode(MyInvitesResponse.self, from: data).invites
    }

    /// Sprejme vabilo: uporabnik postane clan (409 is_owner / already_member, 404 ce ni vec cakajoce).
    func acceptInvite(token: String, inviteId: Int) async throws -> AcceptInviteResponse {
        let data = try await send(path: "me/invites/\(inviteId)/accept", method: "POST", token: token)
        return try decode(AcceptInviteResponse.self, from: data)
    }

    /// Zavrne vabilo. Vrne preostala cakajoca vabila.
    func declineInvite(token: String, inviteId: Int) async throws -> [MyInvite] {
        let data = try await send(path: "me/invites/\(inviteId)/decline", method: "POST", token: token)
        return try decode(MyInvitesResponse.self, from: data).invites
    }
}
