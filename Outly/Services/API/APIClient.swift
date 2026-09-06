import Foundation

enum APIError: Error, LocalizedError {
    case requestFailed(Int, String)
    case decodingFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .requestFailed(let code, let msg):
            return "Request failed (\(code)): \(msg)"
        case .decodingFailed:
            return "Failed to decode response."
        }
    }
}

extension APIClient {

    struct VerifyEmailBody: Encodable {
        let email: String
        let code: String
    }

    func verifyEmail(email: String, code: String) async throws {
        let url = baseURL.appendingPathComponent("auth/verify-email")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(VerifyEmailBody(email: email, code: code))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }
    }

    struct ResendBody: Encodable {
        let email: String
    }

    func resendVerification(email: String) async throws {
        let url = baseURL.appendingPathComponent("auth/resend-verification")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ResendBody(email: email))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private let baseURL = URL(string: "https://outly-backend-roy3.onrender.com")!

    // MARK: - Login

    struct LoginBody: Encodable {
        let email: String
        let password: String
    }

    struct LoginResponse: Decodable {
        let token: String
    }

    func login(email: String, password: String) async throws -> String {
        let url = baseURL.appendingPathComponent("auth/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(LoginBody(email: email, password: password))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(LoginResponse.self, from: data).token
        } catch {
            throw APIError.decodingFailed
        }
    }

    // MARK: - Me

    func me(token: String) async throws -> Me {
        let url = baseURL.appendingPathComponent("me")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(Me.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    // MARK: - Clubs (public)

    func fetchClubs() async throws -> [APIClub] {
        let url = baseURL.appendingPathComponent("clubs")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode([APIClub].self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    // MARK: - Events (public)

    func fetchEvents(clubId: Int? = nil, upcoming: Bool = true) async throws -> [APIEvent] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "upcoming", value: upcoming ? "true" : "false")
        ]
        if let clubId {
            comps.queryItems?.append(URLQueryItem(name: "clubId", value: "\(clubId)"))
        }

        guard let url = comps.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode([APIEvent].self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }
    
    // MARK: - Single Club (public)
    func fetchClub(id: Int) async throws -> APIClub {
        let url = baseURL.appendingPathComponent("clubs/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(APIClub.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

}

struct CloudinarySignature: Decodable {
    let cloudName: String
    let apiKey: String
    let timestamp: Int
    let folder: String
    let signature: String
}

extension APIClient {
    func fetchCloudinarySignature(token: String) async throws -> CloudinarySignature {
        let url = baseURL.appendingPathComponent("uploads/cloudinary-signature")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(CloudinarySignature.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }
}


struct CloudinaryUploadResponse: Decodable {
    let secureUrl: String

    enum CodingKeys: String, CodingKey {
        case secureUrl = "secure_url"
    }
}

extension APIClient {
    func uploadImageToCloudinary(
        imageData: Data,
        fileName: String,
        signature: CloudinarySignature
    ) async throws -> String {

        let url = URL(string: "https://api.cloudinary.com/v1_1/\(signature.cloudName)/image/upload")!
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
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        addField("api_key", signature.apiKey)
        addField("timestamp", String(signature.timestamp))
        addField("folder", signature.folder)
        addField("signature", signature.signature)

        addFile("file", fileName, imageData)

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

extension APIClient {
    func updateMyAvatar(token: String, avatarUrl: String) async throws -> Me {
        let url = baseURL.appendingPathComponent("me/avatar")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["avatarUrl": avatarUrl]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.requestFailed(-1, "No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(Me.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }
}



