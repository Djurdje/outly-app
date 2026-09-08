import Foundation

// Prosnja za poslovni racun ("Request for creator"). Backend: POST /creator-applications
// (prijavljenemu uporabniku se prosnja veze na racun, e-naslov vzame iz zetona) in
// GET /creator-applications/me (stanje). Admin jo odobri v panelu /admin -> uporabnik
// dobi vlogo business in prazen klub z imenom iz prosnje.

/// Ena vrstica iz GET /creator-applications/me.
struct CreatorApplication: Decodable, Identifiable {
    let id: Int
    let businessName: String
    /// "new" | "approved" | "rejected"
    let status: String
    let decidedAt: String?
    let decisionNote: String
    let clubId: Int?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case businessName = "business_name"
        case decidedAt = "decided_at"
        case decisionNote = "decision_note"
        case clubId = "club_id"
        case createdAt = "created_at"
    }

    // Obrambno dekodiranje: NULL ali manjkajoce polje v eni vrstici ne sme podreti seznama.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "new"
        decidedAt = try c.decodeIfPresent(String.self, forKey: .decidedAt)
        decisionNote = try c.decodeIfPresent(String.self, forKey: .decisionNote) ?? ""
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// Polja obrazca. Ista kot Creator.html na spletni strani.
struct CreatorApplicationForm {
    var businessName = ""
    var businessType = ""
    var businessAddress = ""
    var city = ""
    var licenceId = ""
    var contactName = ""
    var contactRole = ""
    var phone = ""
    var message = ""

    var json: [String: Any] {
        [
            "businessName": businessName.trimmingCharacters(in: .whitespacesAndNewlines),
            "businessType": businessType.trimmingCharacters(in: .whitespacesAndNewlines),
            "businessAddress": businessAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "licenceId": licenceId.trimmingCharacters(in: .whitespacesAndNewlines),
            "contactName": contactName.trimmingCharacters(in: .whitespacesAndNewlines),
            "contactRole": contactRole.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }
}

extension APIClient {

    /// POST /creator-applications. Z zetonom, da se prosnja veze na racun (e-naslov
    /// vzame streznik iz zetona; poslanega ignorira).
    func submitCreatorApplication(token: String, form: CreatorApplicationForm) async throws {
        _ = try await send(path: "creator-applications", method: "POST", token: token, json: form.json)
    }

    /// GET /creator-applications/me — prosnje prijavljenega uporabnika, najnovejsa prva.
    func fetchMyCreatorApplications(token: String) async throws -> [CreatorApplication] {
        let data = try await send(path: "creator-applications/me", method: "GET", token: token)
        return try decode([CreatorApplication].self, from: data)
    }
}
