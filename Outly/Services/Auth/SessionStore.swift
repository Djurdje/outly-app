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

    /// Trenutni uporabnik iz GET /me. nil = se ni nalozen (ali odjavljen).
    @Published var me: Me? = nil
    /// Napaka zadnjega nalaganja /me (razumljivo sporocilo), nil ce je slo v redu.
    @Published var meLoadError: String? = nil

    var isLoggedIn: Bool { !token.isEmpty }

    /// Racun se ni dokoncan (onboarded_at je prazen) -> pokazi "Complete your account".
    /// Velja za navadne uporabnike. Poslovni racun (klub) in admin nimata datuma
    /// rojstva in zanrov osebe, zato ju ne silimo skozi ta tok.
    var needsOnboarding: Bool {
        guard let me else { return false }
        return me.role == "user" && !me.isOnboarded
    }

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
        me = nil
        meLoadError = nil
    }

    /// Nalozi GET /me. Ob 401 (zeton potekel ali preklican) odjavi.
    /// Vrne true, ce je uporabnik nalozen.
    @discardableResult
    func refreshMe() async -> Bool {
        guard !token.isEmpty else { return false }
        do {
            let fetched = try await APIClient.shared.me(token: token)
            me = fetched
            meLoadError = nil
            return true
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 {
                logout()
                return false
            }
            meLoadError = api.userMessage
            return false
        } catch {
            meLoadError = error.userMessage
            return false
        }
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
