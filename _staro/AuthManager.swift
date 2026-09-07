import SwiftUI
import Combine
import Foundation

@MainActor
final class AuthManager: ObservableObject {

    @AppStorage("authStage") var authStage: String = "login"

    @Published var me: MeResponse? = nil
    @Published var isBootstrapping: Bool = false

    private let baseURL = URL(string: "https://outly-backend-roy3.onrender.com")!

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        guard let token = KeychainService.shared.readToken() else {
            authStage = "login"
            return
        }

        do {
            let me = try await fetchMe(token: token)
            self.me = me
            authStage = "main"
        } catch {
            _ = KeychainService.shared.deleteToken()
            me = nil
            authStage = "login"
        }
    }

    func handleLoginSuccess(token: String) {
        _ = KeychainService.shared.saveToken(token)
        authStage = "main"
    }

    func logout() {
        _ = KeychainService.shared.deleteToken()
        me = nil
        authStage = "login"
    }

    private func fetchMe(token: String) async throws -> MeResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("me"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        return try JSONDecoder().decode(MeResponse.self, from: data)
    }
}
