import Foundation
import SwiftUI
import Combine

/// Edino mesto v aplikaciji, ki hrani prijavni zeton.
/// Zeton zivi IZKLJUCNO v Keychainu (KeychainService); v pomnilniku je le kopija,
/// da SwiftUI pogledi lahko reagirajo na prijavo/odjavo.
///
/// Pogledi NE smejo brati "authToken" iz @AppStorage/UserDefaults.
/// Uporabi: @EnvironmentObject var session: SessionStore  ->  session.token
///
/// Stanje zaslona (@AppStorage("authStage")) je locena zadeva in ostane, kjer je.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var token: String = ""

    var isLoggedIn: Bool { !token.isEmpty }

    init() {
        migrateLegacyTokenIfNeeded()
        token = KeychainService.shared.readToken() ?? ""
    }

    /// Po uspesni prijavi. Zapise v Keychain in obvesti poglede.
    func setToken(_ newToken: String) {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logout()
            return
        }
        if KeychainService.shared.saveToken(trimmed) {
            token = trimmed
        } else {
            // Keychain je odpovedal: zeton ne sme ostati nikjer drugje.
            token = ""
        }
    }

    /// Odjava: izbrise zeton iz Keychaina in pomnilnika.
    func logout() {
        _ = KeychainService.shared.deleteToken()
        token = ""
    }

    /// Enkratna selitev: starejse razlicice so zeton hranile v UserDefaults ("authToken").
    /// Prenesemo ga v Keychain in iz UserDefaults IZBRISEMO, da tam ne ostane cistopis.
    private func migrateLegacyTokenIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: "authToken") else { return }
        defer { defaults.removeObject(forKey: "authToken") }
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainService.shared.readToken() == nil {
            _ = KeychainService.shared.saveToken(trimmed)
        }
    }
}
