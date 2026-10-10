import Foundation

// Prijava zlorabe in blokiranje (outly-backend #189, Apple App Review 1.2, 10. 10. 2026).
// POST   /reports                { target_type, target_id, reason, details? }  -> 201 / 200 { ok, id }
// GET    /me/blocks              -> { blocks: [{ user_id, username, avatar_url, blocked_at }] }
// POST   /me/blocks/:userId      -> 204 (idempotentno; prijateljstvo in prosnje med njima izginejo)
// DELETE /me/blocks/:userId      -> 204 (prijateljstvo se NE obnovi)
//
// Napake: 400 invalid_target | invalid_reason | invalid_details, 404 not_found (cilj ni javen),
// 429 (omejevalnik / too_many_reports), 409 blocks_limit.
// Star backend teh poti se nima: Express vrne 404 »Cannot POST /reports« — `prijavaSporocilo` to
// pokaze kot »Not available yet.«, brez sesutja.

/// Kaj prijavljamo. `media` aplikacija zaenkrat ne uporablja (slika kluba), a ga backend pozna.
enum ReportTargetType: String {
    case user, club, event, media
}

/// Razlogi prijave: rawValue je tocno to, kar pricakuje backend.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam, harassment, inappropriate, impersonation, illegal, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: return String(localized: "Spam or scam")
        case .harassment: return String(localized: "Harassment or hate")
        case .inappropriate: return String(localized: "Inappropriate or offensive content")
        case .impersonation: return String(localized: "Impersonation")
        case .illegal: return String(localized: "Illegal activity")
        case .other: return String(localized: "Something else")
        }
    }
}

/// Uporabnik, ki sem ga blokiral (GET /me/blocks). Vsa polja razen `user_id` z privzeto vrednostjo.
struct BlockedUser: Decodable, Identifiable {
    let userId: Int
    let username: String
    let avatarUrl: String?
    let blockedAt: String

    var id: Int { userId }

    /// Za FriendRow in drugi skupni UI.
    var user: FriendUser { FriendUser(id: userId, username: username, avatarUrl: avatarUrl) }

    enum CodingKeys: String, CodingKey {
        case username
        case userId = "user_id"
        case avatarUrl = "avatar_url"
        case blockedAt = "blocked_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(Int.self, forKey: .userId)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        blockedAt = try c.decodeIfPresent(String.self, forKey: .blockedAt) ?? ""
    }
}

private struct BlocksResponse: Decodable {
    let blocks: [BlockedUser]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decodeIfPresent([BlockedUser].self, forKey: .blocks) ?? []
    }
    enum CodingKeys: String, CodingKey { case blocks }
}

extension APIClient {

    /// Najvec znakov v `details` (backend steje kodne tocke).
    static let prijavaPodrobnostiNajvec = 1000

    /// POST /reports. Prazne podrobnosti se ne posljejo; predolge se skrajsajo na 1000 kodnih tock.
    func sendReport(token: String, targetType: ReportTargetType, targetId: Int, reason: ReportReason, details: String) async throws {
        var body: [String: Any] = [
            "target_type": targetType.rawValue,
            "target_id": targetId,
            "reason": reason.rawValue
        ]
        let d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty {
            body["details"] = String(String.UnicodeScalarView(d.unicodeScalars.prefix(APIClient.prijavaPodrobnostiNajvec)))
        }
        _ = try await send(path: "reports", method: "POST", token: token, json: body)
    }

    /// GET /me/blocks — samo uporabniki, ki sem jih blokiral JAZ; najnovejsi prvi.
    func fetchBlocks(token: String) async throws -> [BlockedUser] {
        let data = try await send(path: "me/blocks", method: "GET", token: token)
        return try decode(BlocksResponse.self, from: data).blocks
    }

    /// POST /me/blocks/:userId — idempotentno. Prijateljstvo (obe smeri) in cakajoce prosnje izginejo.
    func blockUser(token: String, userId: Int) async throws {
        _ = try await send(path: "me/blocks/\(userId)", method: "POST", token: token)
    }

    /// DELETE /me/blocks/:userId — idempotentno. Prijateljstvo se ne obnovi.
    func unblockUser(token: String, userId: Int) async throws {
        _ = try await send(path: "me/blocks/\(userId)", method: "DELETE", token: token)
    }
}

extension Error {
    /// Sporocilo za prijavo in blokiranje. 404 brez `not_found` v telesu = pot na backendu se ne obstaja
    /// (star backend); 404 `not_found` = cilj ni vec javen. Vse ostalo gre skozi `userMessage`.
    var prijavaSporocilo: String {
        if let api = self as? APIError, case .requestFailed(let code, let raw) = api {
            let t = raw.lowercased()
            if code == 404 {
                return t.contains("not_found")
                    ? String(localized: "This is no longer available.")
                    : String(localized: "Not available yet.")
            }
            if code == 429 { return String(localized: "Try again later.") }
            if code == 409 && t.contains("blocks_limit") {
                return String(localized: "You have reached the limit of blocked users.")
            }
        }
        return userMessage
    }
}
