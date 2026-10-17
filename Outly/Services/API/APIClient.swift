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

    /// outly-backend#257 — pogodba (ista kot splet, outly_webpage#78 `parametriPodpisa`): VSAKO polje odgovora
    /// razen `nepodpisanaPolja` je podpisan parameter in gre Cloudinaryju nespremenjeno; ime camelCase -> snake_case
    /// (publicId -> public_id), seznam -> niz z vejicami, `null` se izpusti. Tako backend podpisu doda npr.
    /// `allowedFormats` brez nove razlicice aplikacije. Danasnji backend: folder, public_id, timestamp.
    /// Razvrsceno po imenu (vrstni red Cloudinaryju ni pomemben, je pa stabilen za teste).
    let podpisaniParametri: [(ime: String, vrednost: String)]

    /// Polja odgovora, ki NISO podpisani parametri (enako kot NEPODPISANA na spletu).
    nonisolated static let nepodpisanaPolja: Set<String> = [
        "signature", "apiKey", "api_key", "cloudName", "cloud_name", "resourceType", "resource_type",
    ]

    enum CodingKeys: String, CodingKey {
        case cloudName, apiKey, timestamp, folder, signature, publicId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cloudName = try c.decode(String.self, forKey: .cloudName)
        apiKey    = try c.decode(String.self, forKey: .apiKey)
        timestamp = try c.decode(Int.self, forKey: .timestamp)
        folder    = try c.decode(String.self, forKey: .folder)
        signature = try c.decode(String.self, forKey: .signature)
        publicId  = try c.decode(String.self, forKey: .publicId)

        let vsa = try decoder.container(keyedBy: PoljeOdgovora.self)
        var parametri: [(ime: String, vrednost: String)] = []
        for kljuc in vsa.allKeys where !Self.nepodpisanaPolja.contains(kljuc.stringValue) {
            if (try? vsa.decodeNil(forKey: kljuc)) == true { continue }
            // Neznana oblika (objekt) ne podre dekodiranja; Cloudinary bi tedaj vrnil "Invalid Signature".
            guard let vrednost = try? vsa.decode(PodpisanaVrednost.self, forKey: kljuc) else { continue }
            parametri.append((ime: Self.vSnake(kljuc.stringValue), vrednost: vrednost.niz))
        }
        podpisaniParametri = parametri.sorted { $0.ime < $1.ime }
    }

    /// "publicId" -> "public_id", "allowedFormats" -> "allowed_formats" (kot `vSnake` na spletu: vsaka A-Z -> "_" + mala).
    nonisolated static func vSnake(_ ime: String) -> String {
        var izhod = ""
        for znak in ime {
            if znak.isASCII && znak.isUppercase {
                izhod += "_" + znak.lowercased()
            } else {
                izhod.append(znak)
            }
        }
        return izhod
    }
}

/// Poljuben kljuc JSON odgovora (za branje vseh polj podpisa).
nonisolated struct PoljeOdgovora: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Vrednost podpisanega parametra kot niz, kot jo poslje splet (`String(v)`, seznam z vejicami).
nonisolated struct PodpisanaVrednost: Decodable, Sendable {
    let niz: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            niz = s
        } else if let i = try? c.decode(Int64.self) {
            niz = String(i)
        } else if let b = try? c.decode(Bool.self) {
            niz = b ? "true" : "false"
        } else if let d = try? c.decode(Double.self) {
            niz = String(d)
        } else if let seznam = try? c.decode([String].self) {
            niz = seznam.joined(separator: ",")
        } else if let stevila = try? c.decode([Int64].self) {
            niz = stevila.map { String($0) }.joined(separator: ",")
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Nepodprta vrednost podpisanega parametra")
        }
    }
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
    /// Video kluba (migracija 015) in posnetek dogodka. Isti podpis kot za slike (resource_type ni del podpisa),
    /// druga pot: /video/upload.
    func uploadVideoToCloudinary(
        videoData: Data,
        fileName: String,
        signature: CloudinarySignature
    ) async throws -> String {
        // Nikoli izvirnik: izvoz brez metapodatkov odstrani lokacijo (VideoZaNalaganje). Ce ne uspe, vrze napako.
        let video = try await VideoZaNalaganje.pripravi(videoData)
        return try await uploadToCloudinary(
            data: video.podatki,
            fileName: SlikaZaNalaganje.imeDatoteke(fileName, koncnica: video.koncnica),
            contentType: video.contentType,
            resourceType: "video",
            signature: signature
        )
    }

    func uploadImageToCloudinary(
        imageData: Data,
        fileName: String,
        signature: CloudinarySignature
    ) async throws -> String {
        // Nikoli izvirnik: ponovno kodiranje odstrani EXIF/GPS (SlikaZaNalaganje). Ce ne uspe, vrze napako.
        let slika = try await SlikaZaNalaganje.pripravi(imageData)
        return try await uploadToCloudinary(
            data: slika.podatki,
            fileName: SlikaZaNalaganje.imeDatoteke(fileName, koncnica: slika.koncnica),
            contentType: slika.contentType,
            resourceType: "image",
            signature: signature
        )
    }

    private func uploadToCloudinary(
        data payload: Data,
        fileName: String,
        contentType: String,
        resourceType: String,
        signature: CloudinarySignature
    ) async throws -> String {

        // cloudName pride s streznika: napacna vrednost (presledek ipd.) ne sme sesuti aplikacije.
        guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(signature.cloudName)/\(resourceType)/upload") else {
            throw APIError.invalidURL
        }
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

        // outly-backend#257: natanko podpisani parametri (iz odgovora backenda), ne trdo kodiran seznam.
        addField("api_key", signature.apiKey)
        for parameter in signature.podpisaniParametri {
            addField(parameter.ime, parameter.vrednost)
        }
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

