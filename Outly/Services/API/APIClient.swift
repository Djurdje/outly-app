import Foundation

enum APIError: Error, LocalizedError {
    case requestFailed(Int, String)
    case decodingFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid URL.")
        case .requestFailed(let code, let msg):
            return String(localized: "Request failed (\(code)): \(msg)")
        case .decodingFailed:
            return String(localized: "Failed to decode response.")
        }
    }
}

/// Klient za Outly backend. Vsi klici gredo skozi send() (APIClient+Account.swift),
/// ki poskrbi za Authorization, napake in osvezitev poteklega zetona ob 401.
/// Racun (prijava, registracija, geslo) je pri Supabase: SupabaseAuth.swift.
/// Poti so razdeljene po datotekah: +Account, +Events, +Discover, +Business.
final class APIClient: Sendable {
    static let shared = APIClient()
    private init() {}

    // Interni (ne private), da ga vidijo razsiritve v drugih datotekah.
    let baseURL = URL(string: "https://outly-backend-roy3.onrender.com")!

    // MARK: - Klubi in dogodki (javno)

    func fetchClubs() async throws -> [APIClub] {
        let data = try await send(path: "clubs", method: "GET")
        return try decode([APIClub].self, from: data)
    }

    /// GET /clubs/:id. Z zetonom odgovor vsebuje tudi `is_following` (backend 019) —
    /// brez njega je gumb Follow ob odprtju vedno videti kot "Follow". Pot je javna,
    /// zato je zeton neobvezen.
    func fetchClub(id: Int, token: String? = nil) async throws -> APIClub {
        let data = try await send(path: "clubs/\(id)", method: "GET", token: token)
        return try decode(APIClub.self, from: data)
    }

    /// GET /events (SEZNAM). Privzeto `lite=true` (backend #114): odgovor brez `description`, ki je pri
    /// vecjem stevilu dogodkov vecina teze odgovora. Seznami opisa ne kazejo; EventDetailView ga ob
    /// odprtju dogodka dobi sam (loadPlan / loadOpis), zato `APIEvent.description` iz seznama ostane "".
    /// Star backend parametra ne pozna in vrne poln odgovor — dekodiranje je enako.
    func fetchEvents(clubId: Int? = nil, upcoming: Bool = true, lite: Bool = true) async throws -> [APIEvent] {
        var q = [URLQueryItem(name: "upcoming", value: upcoming ? "true" : "false")]
        if let clubId { q.append(URLQueryItem(name: "clubId", value: "\(clubId)")) }
        if lite { q.append(URLQueryItem(name: "lite", value: "true")) }
        let data = try await send(path: "events", method: "GET", query: q)
        return try decode([APIEvent].self, from: data)
    }

    // MARK: - Slike

    func fetchCloudinarySignature(token: String) async throws -> CloudinarySignature {
        let data = try await send(path: "uploads/cloudinary-signature", method: "POST", token: token)
        return try decode(CloudinarySignature.self, from: data)
    }

    func updateMyAvatar(token: String, avatarUrl: String) async throws -> Me {
        let data = try await send(path: "me/avatar", method: "PATCH", token: token, json: ["avatarUrl": avatarUrl])
        return try decode(Me.self, from: data)
    }
}

struct CloudinarySignature: Decodable {
    let cloudName: String
    let apiKey: String
    let timestamp: Int
    let folder: String
    let signature: String

    /// Backend ga sestavi sam in ga vkljuci v podpis (npr. "outly/u42/1757193600-3f9a1c2b").
    /// Ker je del podpisa, ga MORAMO poslati naprej Cloudinaryju nespremenjenega,
    /// sicer podpis ne velja. Hkrati preprecuje pisanje cez tuje slike.
    let publicId: String
}

struct CloudinaryUploadResponse: Decodable {
    let secureUrl: String

    enum CodingKeys: String, CodingKey {
        case secureUrl = "secure_url"
    }
}

// Nalaganje na Cloudinary gre na TUJ streznik (api.cloudinary.com), ne na nas backend,
// zato ne gre skozi send().
extension APIClient {
    /// Video kluba (migracija 015). Isti podpis kot za slike (podpisani so folder,
    /// public_id, timestamp — resource_type ni del podpisa), druga pot: /video/upload.
    func uploadVideoToCloudinary(
        videoData: Data,
        fileName: String,
        signature: CloudinarySignature
    ) async throws -> String {
        try await uploadToCloudinary(data: videoData, fileName: fileName, contentType: "video/mp4", resourceType: "video", signature: signature)
    }

    func uploadImageToCloudinary(
        imageData: Data,
        fileName: String,
        signature: CloudinarySignature
    ) async throws -> String {
        try await uploadToCloudinary(data: imageData, fileName: fileName, contentType: "image/jpeg", resourceType: "image", signature: signature)
    }

    private func uploadToCloudinary(
        data payload: Data,
        fileName: String,
        contentType: String,
        resourceType: String,
        signature: CloudinarySignature
    ) async throws -> String {

        let url = URL(string: "https://api.cloudinary.com/v1_1/\(signature.cloudName)/\(resourceType)/upload")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        func addFile(_ name: String, _ filename: String, _ data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        addField("api_key", signature.apiKey)
        addField("timestamp", String(signature.timestamp))
        addField("folder", signature.folder)
        addField("public_id", signature.publicId)
        addField("signature", signature.signature)

        addFile("file", fileName, payload)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Cloudinary error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            let decoded = try JSONDecoder().decode(CloudinaryUploadResponse.self, from: data)
            return decoded.secureUrl
        } catch {
            throw APIError.decodingFailed
        }
    }
}

