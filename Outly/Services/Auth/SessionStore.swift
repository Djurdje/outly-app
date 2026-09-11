import Foundation
import SwiftUI
import Combine

/// Edino mesto v aplikaciji, ki hrani sejo: Supabasov dostopni zeton (1 h) in
/// osvezevalni zeton. Oba zivita IZKLJUCNO v Keychainu; v pomnilniku je le kopija,
/// da SwiftUI pogledi reagirajo na prijavo/odjavo.
///
/// Od 11. 9. 2026 je identiteta Supabase Auth (SupabaseAuth.swift): prijava,
/// osvezitev in odjava gredo na Supabase, backend Outlyja zeton samo preverja.
///
/// Pogledi NE smejo brati zetonov iz @AppStorage/UserDefaults.
/// Uporabi: @EnvironmentObject var session: SessionStore  ->  session.token
///
/// Osvezevanje: APIClient.send ob 401 poklice refreshAccessToken() in klic ponovi.
/// Pogledi se s tem ne ukvarjajo.
///
/// Stanje zaslona (@AppStorage("authStage")) je locena zadeva in ostane, kjer je.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var token: String = ""
    @Published private(set) var refreshToken: String = ""

    /// Trenutni uporabnik iz GET /me. nil = se ni nalozen (ali odjavljen).
    @Published var me: Me? = nil
    /// Napaka zadnjega nalaganja /me (razumljivo sporocilo), nil ce je slo v redu.
    @Published var meLoadError: String? = nil

    /// Nastavi se, ko streznik sejo dokoncno zavrne (osvezitev ni uspela).
    /// AuthGateView takrat pokaze prijavo; LoginView pokaze to sporocilo.
    @Published var sessionExpiredNotice: String? = nil

    private var refreshTask: Task<Bool, Never>?

    var isLoggedIn: Bool { !token.isEmpty }

    /// Velja za navadne uporabnike. Poslovni racun (klub) in admin nimata datuma
    /// rojstva in zanrov osebe, zato ju ne silimo skozi ta tok.
    var needsOnboarding: Bool {
        guard let me else { return false }
        return me.role == "user" && !me.isOnboarded
    }

    init() {
        migrateLegacyTokenIfNeeded()
        token = KeychainService.shared.read(.accessToken) ?? ""
        refreshToken = KeychainService.shared.read(.refreshToken) ?? ""
        // Zeton iz starejse razlicice (lastni HS256 zeton backenda) ni vec uporaben:
        // pobrisemo ga, uporabnik se prijavi znova (isti e-naslov in geslo).
        if !token.isEmpty && !SupabaseAuth.jeSupabaseZeton(token) {
            KeychainService.shared.delete(.accessToken)
            KeychainService.shared.delete(.refreshToken)
            token = ""
            refreshToken = ""
        }
        SessionRefresh.handler = { [weak self] in
            guard let self else { return nil }
            return await self.refreshAccessToken() ? self.token : nil
        }
        SessionRefresh.isLoggedIn = { [weak self] in self?.isLoggedIn ?? false }
    }

    // MARK: - Prijava / odjava

    /// Po uspesni prijali ali osvezitvi. Zapise oba zetona v Keychain in obvesti poglede.
    func setSession(token newToken: String, refreshToken newRefresh: String?) {
        let t = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { logout(); return }
        guard KeychainService.shared.save(t, for: .accessToken) else {
            // Keychain je odpovedal: zeton ne sme ostati nikjer drugje.
            token = ""
            return
        }
        token = t
        if let r = newRefresh?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            if KeychainService.shared.save(r, for: .refreshToken) { refreshToken = r }
        }
        sessionExpiredNotice = nil
    }

    /// Stari klic (samo dostopni zeton). Ostane za zdruzljivost; nova koda naj klice setSession.
    func setToken(_ newToken: String) { setSession(token: newToken, refreshToken: nil) }

    /// Odjava: Supabase preklice sejo (osvezevalni zeton), nato lokalno pobrisemo
    /// vse. Lokalni del se zgodi VEDNO, tudi brez omrezja.
    func logout() {
        let t = token
        if !t.isEmpty {
            Task.detached { try? await SupabaseAuth.shared.signOut(token: t) }
        }
        clearLocalSession()
    }

    /// Streznik je sejo zavrnil (npr. po ponastavitvi gesla na drugi napravi).
    func sessionRejected(message: String = "Your session has expired. Please log in again.") {
        clearLocalSession()
        sessionExpiredNotice = message
    }

    private func clearLocalSession() {
        KeychainService.shared.delete(.accessToken)
        KeychainService.shared.delete(.refreshToken)
        token = ""
        refreshToken = ""
        me = nil
        meLoadError = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Osvezevanje

    /// Zamenja potekli dostopni zeton z novim prek Supabase (grant_type=refresh_token).
    /// Vec socasnih klicev deli isto osvezitev (en sam klic na streznik).
    /// Vrne false, ce osvezitev ni mogoca — takrat je uporabnik odjavljen.
    func refreshAccessToken() async -> Bool {
        if let t = refreshTask { return await t.value }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            let r = self.refreshToken
            guard !r.isEmpty else {
                // Stara namestitev brez osvezevalnega zetona: dostopni je potekel, nic za osveziti.
                self.sessionRejected()
                return false
            }
            do {
                let seja = try await SupabaseAuth.shared.refresh(refreshToken: r)
                self.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
                return true
            } catch let e as SupabaseAuthError {
                // 400/401/403: zeton porabljen, preklican ali potekel -> odjava.
                // 5xx / omrezje: seje NE brisemo, naslednji klic poskusi znova.
                if e.status == 400 || e.status == 401 || e.status == 403 {
                    self.sessionRejected()
                }
                return false
            } catch {
                return false
            }
        }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    // MARK: - Uporabnik

    /// Nalozi GET /me. Ob 401 (tudi po neuspesni osvezitvi) odjavi.
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
                sessionRejected()
                return false
            }
            meLoadError = api.userMessage
            return false
        } catch {
            meLoadError = error.userMessage
            return false
        }
    }

    // MARK: - Selitev

    /// Enkratna selitev: starejse razlicice so zeton hranile v UserDefaults ("authToken").
    /// Prenesemo ga v Keychain in iz UserDefaults IZBRISEMO, da tam ne ostane cistopis.
    private func migrateLegacyTokenIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: "authToken") else { return }
        defer { defaults.removeObject(forKey: "authToken") }
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainService.shared.read(.accessToken) == nil {
            KeychainService.shared.save(trimmed, for: .accessToken)
        }
    }
}
