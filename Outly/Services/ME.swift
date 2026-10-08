import Foundation

/// Uporabnik, kot ga vrne GET /me (in PATCH /me, PATCH /me/avatar).
/// Vsa polja razen id/email/username/role so neobvezna, ker so bila dodana
/// z migracijo 003 in so lahko NULL. Ena vrstica z NULL ne sme podreti dekodiranja.
struct Me: Codable, Equatable {
    let id: Int
    let email: String
    let username: String
    let role: String
    let avatarUrl: String?

    let emailVerified: Bool?
    let phone: String?
    let phoneVerified: Bool?
    /// "YYYY-MM-DD" ali nil.
    let dateOfBirth: String?
    /// Dvocrkovna ISO koda ("SI") ali nil.
    let country: String?
    let genres: [String]
    /// nil = racun se ni dokoncan -> aplikacija pelje v "Complete your account".
    let onboardedAt: String?
    let createdAt: String?

    /// Klub, v katerem uporabnik dela (lastnik ali clan ekipe, migracija 009). nil = nobenega.
    let clubId: Int?
    /// "owner" | "manager" | "doorman" | nil. Poslovni obraz se odloca po tem, ne po role.
    let clubRole: String?
    /// Stevilo cakajocih vabil v ekipo kluba (migracija 013) — znacka na zvoncu v My clubs.
    let pendingInvites: Int
    /// Stevilo cakajocih prosenj za prijateljstvo (migracija 016) — obvestila, My friends.
    let pendingFriendRequests: Int
    /// Stevilo neprebranih prejetih vstopnic (migracija 017) — obvestilo "X sent you a ticket".
    let pendingReceivedTickets: Int
    /// Stevilo neprebranih obvestil "klub, ki mu sledis, je objavil dogodek" (migracija 019).
    let pendingClubEvents: Int
    /// Stevilo neprebranih obvestil »X te je dodal na guest listo« (backend, 8. 10. 2026). Star backend polja ne poslje -> 0.
    let pendingGuestListInvites: Int
    /// Ali prijatelji vidijo, na katere dogodke grem ("Your friends' plans"). Privzeto true.
    let sharePlansWithFriends: Bool
    /// Vsa clanstva (lastnistvo + ekipe; backend migracija 018, vec klubov na osebo). Star backend: [].
    let clubs: [MeClub]
    /// Prenos vstopnice prijatelju BREZ racuna po e-naslovu (backend, 5. 10. 2026). Streznik ga prizge samo za izbrane
    /// (do objave pogojev: admin; potem vsi). Star backend polja ne poslje -> false (stara oblika prenosa).
    let canTransferToGuest: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, username, role, phone, country, genres
        case avatarUrl = "avatar_url"
        case emailVerified = "email_verified"
        case phoneVerified = "phone_verified"
        case dateOfBirth = "date_of_birth"
        case onboardedAt = "onboarded_at"
        case createdAt = "created_at"
        case clubId = "club_id"
        case clubRole = "club_role"
        case pendingInvites = "pending_invites"
        case pendingFriendRequests = "pending_friend_requests"
        case pendingReceivedTickets = "pending_received_tickets"
        case pendingClubEvents = "pending_club_events"
        case pendingGuestListInvites = "pending_guest_list_invites"
        case sharePlansWithFriends = "share_plans_with_friends"
        case clubs
        case canTransferToGuest = "can_transfer_to_guest"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        username = try c.decode(String.self, forKey: .username)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "user"
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        phoneVerified = try c.decodeIfPresent(Bool.self, forKey: .phoneVerified)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        onboardedAt = try c.decodeIfPresent(String.self, forKey: .onboardedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId)
        clubRole = try c.decodeIfPresent(String.self, forKey: .clubRole)
        pendingInvites = try c.decodeIfPresent(Int.self, forKey: .pendingInvites) ?? 0
        pendingFriendRequests = try c.decodeIfPresent(Int.self, forKey: .pendingFriendRequests) ?? 0
        pendingReceivedTickets = try c.decodeIfPresent(Int.self, forKey: .pendingReceivedTickets) ?? 0
        pendingClubEvents = try c.decodeIfPresent(Int.self, forKey: .pendingClubEvents) ?? 0
        pendingGuestListInvites = (try? c.decodeIfPresent(Int.self, forKey: .pendingGuestListInvites)) ?? 0
        sharePlansWithFriends = try c.decodeIfPresent(Bool.self, forKey: .sharePlansWithFriends) ?? true
        clubs = (try? c.decodeIfPresent([MeClub].self, forKey: .clubs)) ?? []
        canTransferToGuest = (try? c.decodeIfPresent(Bool.self, forKey: .canTransferToGuest)) ?? false
        // Postgres DATE pride kot "YYYY-MM-DD" ali kot ISO cas; obdrzimo prvih 10 znakov.
        if let raw = try c.decodeIfPresent(String.self, forKey: .dateOfBirth), raw.count >= 10 {
            dateOfBirth = String(raw.prefix(10))
        } else {
            dateOfBirth = nil
        }
    }

    /// Za shranjevanje zadnjega Me na disk (MeShramba): isti kljuci kot v odgovoru streznika, da ga init(from:) prebere nazaj.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(email, forKey: .email)
        try c.encode(username, forKey: .username)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encodeIfPresent(emailVerified, forKey: .emailVerified)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(phoneVerified, forKey: .phoneVerified)
        try c.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encode(genres, forKey: .genres)
        try c.encodeIfPresent(onboardedAt, forKey: .onboardedAt)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(clubId, forKey: .clubId)
        try c.encodeIfPresent(clubRole, forKey: .clubRole)
        try c.encode(pendingInvites, forKey: .pendingInvites)
        try c.encode(pendingFriendRequests, forKey: .pendingFriendRequests)
        try c.encode(pendingReceivedTickets, forKey: .pendingReceivedTickets)
        try c.encode(pendingClubEvents, forKey: .pendingClubEvents)
        try c.encode(pendingGuestListInvites, forKey: .pendingGuestListInvites)
        try c.encode(sharePlansWithFriends, forKey: .sharePlansWithFriends)
        try c.encode(clubs, forKey: .clubs)
        try c.encode(canTransferToGuest, forKey: .canTransferToGuest)
    }

    /// Poslovni obraz v profilu: lastnik (role business, tudi brez kluba) ali clan ekipe.
    var isBusiness: Bool { role == "business" || clubRole != nil }

    /// Sme urejati klub in dogodke, videti prodajo: lastnik in manager (in admin brez kluba).
    var canManageClub: Bool { clubRole == "owner" || clubRole == "manager" || (clubRole == nil && isBusiness) }

    /// Sme urejati ekipo (lastnik vse, manager samo vratarje).
    var canSeeTeam: Bool { clubRole == "owner" || clubRole == "manager" }

    /// Napis vloge za profil: "Owner", "Manager", "Door staff".
    var clubRoleLabel: String? {
        switch clubRole {
        case "owner": return String(localized: "Owner")
        case "manager": return String(localized: "Manager")
        case "doorman": return String(localized: "Door staff")
        default: return nil
        }
    }

    /// Racun je dokoncan, ko streznik nastavi onboarded_at.
    var isOnboarded: Bool { onboardedAt != nil }

    /// Starost v letih iz datuma rojstva; nil, ce datuma ni.
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // Lokalni casovni pas, enako kot DatePicker in prikaz — sicer je zahodno od GMT dan prej.
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: d, to: Date()).year
    }
}

/// Eno clanstvo iz GET /me `clubs` (migracija 018): klub in moja vloga v njem.
struct MeClub: Codable, Identifiable, Equatable {
    let clubId: Int
    let clubName: String
    let clubLogoUrl: String
    /// "owner" | "manager" | "doorman"
    let role: String

    var id: Int { clubId }

    enum CodingKeys: String, CodingKey {
        case role
        case clubId = "club_id"
        case clubName = "club_name"
        case clubLogoUrl = "club_logo_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubId = try c.decode(Int.self, forKey: .clubId)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        clubLogoUrl = try c.decodeIfPresent(String.self, forKey: .clubLogoUrl) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "doorman"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clubId, forKey: .clubId)
        try c.encode(clubName, forKey: .clubName)
        try c.encode(clubLogoUrl, forKey: .clubLogoUrl)
        try c.encode(role, forKey: .role)
    }
}
