import Foundation

// Aktivnost kluba (nova nadzorna plosca, Martin 25. 9. 2026):
// POST /views                      brez zetona -> 204 (klik na profil/dogodek, steje se enkrat na prikaz)
// GET  /business/activity          zeton -> klik na profil/dogodke, sledilci, aktivnost ekipe na vratih
// GET  /business/team/:userId/scans  zeton -> po dogodkih, koliko je posamezen clan ekipe pregledal vstopnic
//
// Vsa polja imajo privzetke, ker gre backend v produkcijo vzporedno s to datoteko
// (STATE.md: naloga za backend-dev, ce poti se ni).

/// GET /business/activity.
struct BusinessActivity: Decodable {
    /// Ena vrstica ekipe s stevilom pregledanih vstopnic (loceno od TeamMember v APIClient+Team.swift,
    /// ki nima teh stevilk).
    struct StaffActivity: Decodable, Identifiable {
        let id: Int
        let username: String
        let avatarUrl: String?
        /// "owner" | "manager" | "doorman"
        let role: String
        let scans: Int
        let scans7d: Int

        enum CodingKeys: String, CodingKey {
            case id, username, role, scans
            case avatarUrl = "avatar_url"
            case scans7d = "scans_7d"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
            username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
            avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
            role = try c.decodeIfPresent(String.self, forKey: .role) ?? "doorman"
            scans = try c.decodeIfPresent(Int.self, forKey: .scans) ?? 0
            scans7d = try c.decodeIfPresent(Int.self, forKey: .scans7d) ?? 0
        }

        var roleLabel: String {
            switch role {
            case "owner": return String(localized: "Owner")
            case "manager": return String(localized: "Manager")
            default: return String(localized: "Door staff")
            }
        }
    }

    let clicksProfile: Int
    let clicksProfile7d: Int
    let clicksEvents: Int
    let clicksEvents7d: Int
    let followersCount: Int
    let followersNew7d: Int
    let staff: [StaffActivity]

    enum CodingKeys: String, CodingKey {
        case staff
        case clicksProfile = "clicks_profile"
        case clicksProfile7d = "clicks_profile_7d"
        case clicksEvents = "clicks_events"
        case clicksEvents7d = "clicks_events_7d"
        case followersCount = "followers_count"
        case followersNew7d = "followers_new_7d"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clicksProfile = try c.decodeIfPresent(Int.self, forKey: .clicksProfile) ?? 0
        clicksProfile7d = try c.decodeIfPresent(Int.self, forKey: .clicksProfile7d) ?? 0
        clicksEvents = try c.decodeIfPresent(Int.self, forKey: .clicksEvents) ?? 0
        clicksEvents7d = try c.decodeIfPresent(Int.self, forKey: .clicksEvents7d) ?? 0
        followersCount = try c.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followersNew7d = try c.decodeIfPresent(Int.self, forKey: .followersNew7d) ?? 0
        staff = try c.decodeIfPresent([StaffActivity].self, forKey: .staff) ?? []
    }
}

/// GET /business/team/:userId/scans — po dogodkih, za en clan ekipe.
struct StaffScans: Decodable {
    struct EventScans: Decodable, Identifiable {
        let id: Int
        let title: String
        let startAt: String
        let posterUrl: String
        let scans: Int

        enum CodingKeys: String, CodingKey {
            case id, title, scans
            case startAt = "start_at"
            case posterUrl = "poster_url"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            startAt = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
            posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl) ?? ""
            scans = try c.decodeIfPresent(Int.self, forKey: .scans) ?? 0
        }

        var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    }

    let events: [EventScans]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([EventScans].self, forKey: .events) ?? []
    }

    enum CodingKeys: String, CodingKey { case events }
}

extension APIClient {

    /// GET /business/activity — kartice "Check activity" na nadzorni plosci.
    func fetchBusinessActivity(token: String) async throws -> BusinessActivity {
        let data = try await send(path: "business/activity", method: "GET", token: token)
        return try decode(BusinessActivity.self, from: data)
    }

    /// GET /business/team/:userId/scans — dogodki in stevilo skenov enega clana ekipe.
    func fetchStaffScans(token: String, userId: Int) async throws -> StaffScans {
        let data = try await send(path: "business/team/\(userId)/scans", method: "GET", token: token)
        return try decode(StaffScans.self, from: data)
    }

    /// POST /views — steje ogled profila kluba ali dogodka. Brez zetona, odgovor 204.
    /// Poslje se enkrat na prikaz (ClubDetailView / EventDetailView .task); napake namerno
    /// pogoltnemo (past: stevec ogledov ne sme podreti zaslona, ce backend pot se nima).
    func postView(clubId: Int? = nil, eventId: Int? = nil) async {
        var json: [String: Any] = [:]
        if let clubId { json["club_id"] = clubId }
        if let eventId { json["event_id"] = eventId }
        guard !json.isEmpty else { return }
        _ = try? await send(path: "views", method: "POST", json: json)
    }
}
