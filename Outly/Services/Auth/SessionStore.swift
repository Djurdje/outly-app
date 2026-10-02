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
    /// Vsak zapis `me` (tudi neposredni iz CompleteAccountView, SelectGenresView, PersonalInfoView, PreferencesView) se shrani
    /// za hladen zagon brez povezave (K1): drugace bi na disku ostal neonboardan Me.
    @Published var me: Me? = nil {
        didSet { meSpremenjen(prej: oldValue) }
    }
    /// Napaka zadnjega nalaganja /me (razumljivo sporocilo), nil ce je slo v redu.
    @Published var meLoadError: String? = nil

    /// Nastavi se, ko streznik sejo dokoncno zavrne (osvezitev ni uspela).
    /// AuthGateView takrat pokaze prijavo; LoginView pokaze to sporocilo.
    @Published var sessionExpiredNotice: String? = nil

    private var refreshTask: Task<Bool, Never>?

    /// Zadnji shranjen Me (z `sub` zetona). Z diska ga preberemo ENKRAT ob zagonu in ga drzimo v pomnilniku.
    private var shranjenMe: MeShramba.Zapis?

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
        shranjenMe = MeShramba.preberiZapis()
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
        // M13: neposlane skene skenerja TEGA uporabnika poskusi poslati se z veljavnim zetonom (kratek rok), nato Supabase odjava.
        // ID zajamemo PRED clearLocalSession (ta pobrise `me`). Lokalni del odjave se zgodi takoj; brez povezave skeni ostanejo na
        // disku do naslednje prijave istega racuna.
        let uporabnikId = me?.id
        let imaSkene = SkenVrsta.deljena(SkenDisk()).steviloVseh > 0
        if !t.isEmpty {
            Task.detached {
                if imaSkene, let uporabnikId { await SkenOdjava.poslji(token: t, uporabnikId: uporabnikId) }
                try? await SupabaseAuth.shared.signOut(token: t)
            }
        }
        clearLocalSession()
    }

    /// Streznik je sejo zavrnil (npr. po ponastavitvi gesla na drugi napravi).
    func sessionRejected(message: String = String(localized: "Your session has expired. Please log in again.")) {
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
        // K1: shranjen Me (brez zetonov) in shramba skenerja gresta ob odjavi/zavrnjeni seji. Neposlani skeni ostanejo na disku;
        // logout() jih prej poskusi poslati (SkenOdjava.poslji).
        shranjenMe = nil
        MeShramba.pobrisi()
        SkenOdjava.pocisti()
        refreshTask?.cancel()
        refreshTask = nil
        // Idempotentni kljuci nakupov (samo v pomnilniku) so vezani na uporabnika: ob odjavi/zavrnjeni seji vsi stran.
        NakupniKljucShramba.deljena.pocistiVse()
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
            // Hladen zagon s shranjenim Me: kratek rok, ob izpadu itak nadaljujemo s shranjenim (K1).
            let kratek: TimeInterval? = (me == nil && shranjenMeZaZeton() != nil) ? 8 : nil
            let fetched = try await APIClient.shared.me(token: token, timeout: kratek)
            // Samo ob dejanski spremembi (29. 9. 2026): vsaka objava `me` znova izrise vse, kar
            // opazuje sejo (tudi MainTabView z vsemi zavihki) — Home in Profile klicata /me ob
            // vsakem prikazu, torej sredi animacije preklopa zavihka.
            if me != fetched { me = fetched }   // didSet shrani Me za hladen zagon brez povezave (K1)
            if meLoadError != nil { meLoadError = nil }
            return true
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 {
                sessionRejected()
                return false
            }
            return uporabiShranjenMe(ob: api)
        } catch {
            return uporabiShranjenMe(ob: error)
        }
    }

    /// K1: GET /me ni uspel zaradi izpada povezave ali streznika (ne zaradi 401/403): aplikacija nadaljuje z zadnjim shranjenim Me,
    /// da vratar ob hladnem zagonu brez povezave pride do skenerja. Brez shranjenega Me ostane napaka in »Try again«.
    private func uporabiShranjenMe(ob napaka: Error) -> Bool {
        if me != nil, napaka.jeIzpadPovezave { return true }   // ze imamo Me iz prejsnjega klica: ne prepisuj s shranjenim
        if let shranjen = MeShramba.nadomestniMe(ob: napaka, shranjen: shranjenMeZaZeton()) {
            me = shranjen
            meLoadError = nil
            return true
        }
        meLoadError = napaka.userMessage
        return false
    }

    /// Shranjen Me, ce pripada racunu trenutnega zetona (primerjava `sub`); Me drugega racuna se ne uporabi.
    private func shranjenMeZaZeton() -> Me? {
        guard let z = shranjenMe, let sub = MeShramba.sub(izZetona: token), z.sub == sub else { return nil }
        return z.me
    }

    private func meSpremenjen(prej: Me?) {
        // Nakupni kljuci, nastali, preden je bil `me` znan (Pay takoj po hladnem zagonu), postanejo kljuci tega uporabnika:
        // sicer bi ponovni Pay po prihodu `me` dobil nov kljuc in drugo narocilo (outly-backend #137, tocka 2).
        if prej == nil, let m = me { NakupniKljucShramba.deljena.pripisiNeznanega(uporabnik: m.id) }
        guard let m = me, m != prej, let sub = MeShramba.sub(izZetona: token) else { return }
        if let z = shranjenMe, z.sub == sub, z.me == m { return }   // enako ze shranjeno (npr. Me iz shrambe)
        shranjenMe = MeShramba.Zapis(sub: sub, me: m)
        MeShramba.shrani(m, sub: sub)
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
