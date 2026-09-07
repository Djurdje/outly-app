import Foundation

/// Uporabnik, kot ga vrne GET /me (in PATCH /me, PATCH /me/avatar).
/// Vsa polja razen id/email/username/role so neobvezna, ker so bila dodana
/// z migracijo 003 in so lahko NULL. Ena vrstica z NULL ne sme podreti dekodiranja.
struct Me: Decodable {
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

    enum CodingKeys: String, CodingKey {
        case id, email, username, role, phone, country, genres
        case avatarUrl = "avatar_url"
        case emailVerified = "email_verified"
        case phoneVerified = "phone_verified"
        case dateOfBirth = "date_of_birth"
        case onboardedAt = "onboarded_at"
        case createdAt = "created_at"
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
        // Postgres DATE pride kot "YYYY-MM-DD" ali kot ISO cas; obdrzimo prvih 10 znakov.
        if let raw = try c.decodeIfPresent(String.self, forKey: .dateOfBirth), raw.count >= 10 {
            dateOfBirth = String(raw.prefix(10))
        } else {
            dateOfBirth = nil
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
