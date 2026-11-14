import SwiftUI
import AuthenticationServices

/// Nadaljevanje, ki se lahko izvede NAJVEC ENKRAT (zaklep): ASWebAuthenticationSession ob `start() == false` in obdelava napake
/// bi sicer obe poklicali `resume` (fatalna napaka). Natanko en izid.
final class EnkratnoNadaljevanje<T>: @unchecked Sendable {
    private let zaklep = NSLock()
    private var nadaljevanje: CheckedContinuation<T, Error>?

    init(_ nadaljevanje: CheckedContinuation<T, Error>) { self.nadaljevanje = nadaljevanje }

    func resume(_ izid: Result<T, Error>) {
        zaklep.lock()
        let c = nadaljevanje
        nadaljevanje = nil
        zaklep.unlock()
        c?.resume(with: izid)
    }
}

/// Zamenjava Googlove avtorizacijske kode za `id_token` (oauth2.googleapis.com/token). iOS client nima secreta; PKCE `code_verifier`
/// je dokaz. Klic ni na nas backend, zato ne gre skozi APIClient (kot SupabaseAuth). Brez Google SDK.
enum GoogleOAuth {
    static func idToken(code: String, codeVerifier: String) async throws -> String {
        guard let url = URL(string: DruzabnaPrijavaLogika.googleZetonNaslov) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(DruzabnaPrijavaLogika.googleTeloIzmenjave(code: code, codeVerifier: codeVerifier).utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.requestFailed(-1, "No HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseAuthError(status: http.statusCode, code: "google_token", message: "")
        }
        guard let t = DruzabnaPrijavaLogika.googleIdToken(izOdgovora: data) else { throw APIError.decodingFailed }
        return t
    }
}

/// Vodi prijavo z Googlom brez Google SDK in brez Supabasovega `/authorize` (ta vedno doda obseg `profile`: ime in slika bi se shranila).
/// `ASWebAuthenticationSession` odpre Googlov `/o/oauth2/v2/auth` z iOS clientom (`scope=openid email`, PKCE, `nonce`, `state`),
/// koda se zamenja pri Googlu za `id_token`, ta gre Supabasu (`/token?grant_type=id_token`, provider google).
///
/// - Sistem prestreze shemo (obrnjen client ID) sam; registracija URL sheme v Info.plist NI potrebna (kot pri Stripu, StripeSeja.swift).
/// - `presentationContextProvider` je v ASWebAuthenticationSession SIBKA referenca: vodja mora ziveti (`@State` pri klicatelju).
/// - `prefersEphemeralWebBrowserSession` je izklopljen (izbira racuna z enim dotikom); sistem pokaze vprasanje, ki omenja
///   `accounts.google.com`.
@MainActor
final class GoogleSejaVodja: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var seja: ASWebAuthenticationSession?

    /// Vrne sejo ali nil, ce je uporabnik prijavo preklical (zaprl okno ali na Googlu pritisnil Cancel).
    func prijava() async throws -> SupabaseSession? {
        // Brez client ID gumba sploh ni; varovalo za ponovno prijavo pred izbrisom racuna.
        guard DruzabnaPrijavaLogika.googleKonfiguriran else {
            throw SupabaseAuthError(status: 400, code: "provider_disabled", message: "")
        }
        let verifier = DruzabnaPrijavaLogika.nakljucenNiz()
        let nonce = DruzabnaPrijavaLogika.nakljucenNiz()
        let state = DruzabnaPrijavaLogika.nakljucenNiz(dolzina: 32)
        guard let url = DruzabnaPrijavaLogika.googleAvtorizacijaURL(
            challenge: DruzabnaPrijavaLogika.pkceChallenge(verifier),
            nonceHash: DruzabnaPrijavaLogika.sha256Hex(nonce), state: state) else { throw APIError.invalidURL }

        let povratni: URL? = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL?, Error>) in
            let enkrat = EnkratnoNadaljevanje(cont)
            let obdelava: @Sendable (URL?, Error?) -> Void = { klic, napaka in
                if let napaka {
                    if let e = napaka as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                        enkrat.resume(.success(nil))
                    } else {
                        enkrat.resume(.failure(napaka))
                    }
                } else {
                    enkrat.resume(.success(klic))
                }
            }
            let nova = ASWebAuthenticationSession(url: url, callbackURLScheme: DruzabnaPrijavaLogika.googleShema(),
                                                  completionHandler: obdelava)
            nova.prefersEphemeralWebBrowserSession = false
            nova.presentationContextProvider = self
            seja = nova
            if !nova.start() {
                seja = nil
                enkrat.resume(.failure(SupabaseAuthError(status: 0, code: "", message: "ASWebAuthenticationSession did not start")))
            }
        }
        seja = nil
        guard let povratni else { return nil }

        switch DruzabnaPrijavaLogika.razclenPovratek(povratni, state: state) {
        case .koda(let koda):
            let idToken = try await GoogleOAuth.idToken(code: koda, codeVerifier: verifier)
            return try await SupabaseAuth.shared.signInWithIdToken(provider: "google", idToken: idToken, nonce: nonce)
        case .napaka(let e, let opis):
            // Cancel na Googlovem zaslonu soglasja pride kot error=access_denied: ni napaka, uporabnik si je premislil.
            if e == "access_denied" { return nil }
            throw SupabaseAuthError(status: 400, code: e, message: opis ?? "")
        case .napacenState, .neveljaven:
            throw SupabaseAuthError(status: 400, code: "bad_oauth_callback", message: "")
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let okno = UIApplication.shared.kljucnoOkno { return okno }
        let scena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let scena { return ASPresentationAnchor(windowScene: scena) }
        return ASPresentationAnchor()
    }
}

/// `identityToken` iz Applovega odgovora kot niz (nil, ce ga ni).
func applovIdToken(_ avtorizacija: ASAuthorization) -> String? {
    guard let cred = avtorizacija.credential as? ASAuthorizationAppleIDCredential,
          let podatki = cred.identityToken else { return nil }
    return String(data: podatki, encoding: .utf8)
}

/// Prijava z Applom v kodi (brez SwiftUI gumba): za ponovno potrditev pred izbrisom racuna (»Confirm with Apple«).
/// Prijavni zaslon uporablja `SignInWithAppleButton` (DruzabniGumbi). Samo obseg `email` (ime Appla ne shranjujemo).
@MainActor
final class AppleVodja: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var enkrat: EnkratnoNadaljevanje<ASAuthorization?>?
    private var kontroler: ASAuthorizationController?

    /// Vrne sejo ali nil ob preklicu.
    func prijava() async throws -> SupabaseSession? {
        let nonce = DruzabnaPrijavaLogika.nakljucenNiz()
        let zahteva = ASAuthorizationAppleIDProvider().createRequest()
        zahteva.requestedScopes = [.email]
        zahteva.nonce = DruzabnaPrijavaLogika.sha256Hex(nonce)

        let avtorizacija: ASAuthorization? = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ASAuthorization?, Error>) in
            enkrat = EnkratnoNadaljevanje(cont)
            let k = ASAuthorizationController(authorizationRequests: [zahteva])
            k.delegate = self
            k.presentationContextProvider = self
            kontroler = k
            k.performRequests()
        }
        kontroler = nil
        enkrat = nil
        guard let avtorizacija else { return nil }
        guard let idToken = applovIdToken(avtorizacija) else { throw APIError.decodingFailed }
        return try await SupabaseAuth.shared.signInWithIdToken(provider: "apple", idToken: idToken, nonce: nonce)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        enkrat?.resume(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let a = error as? ASAuthorizationError, a.code == .canceled {
            enkrat?.resume(.success(nil))
        } else {
            enkrat?.resume(.failure(error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let okno = UIApplication.shared.kljucnoOkno { return okno }
        let scena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let scena { return ASPresentationAnchor(windowScene: scena) }
        return ASPresentationAnchor()
    }
}

/// Stavek o pogojih + Continue with Apple + Continue with Google (prijava in registracija). Stavek je NAD gumbi (pogodba backend
/// ARCHITECTURE »Prijava z Googlom in Applom«, tocka 5). Gumb Google je viden samo, ko je vpisan iOS client ID.
/// Po uspehu seja pride v SessionStore, AuthGateView zamenja zaslon; zapis privolitve (`terms_version`) uredi
/// SessionStore.zagotoviPrivolitev po GET /me.
@MainActor
struct DruzabniGumbi: View {
    @EnvironmentObject private var session: SessionStore
    /// Surov nonce trenutne Applove zahteve (Applu gre njegov SHA-256, Supabasu surov).
    @State private var nonceApple = ""
    @State private var vodja = GoogleSejaVodja()
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 12) {
            // Markdown povezave v prevedenem nizu (stavka ne sestavljamo iz delov: besedni red je v sl drugacen).
            Text("By continuing, you confirm you are 18 or older, agree to the [Terms of Use](\(LegalLinks.terms.absoluteString)) and acknowledge the [Privacy Policy](\(LegalLinks.privacy.absoluteString)).")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.6))
                .tint(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                Text("or")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
            }

            SignInWithAppleButton(.continue, onRequest: { zahteva in
                // Sinhrono PRED zacetkom zahteve: drugi dotik je onemogocen (isLoading), apple() ga ponastavi v vseh izidih.
                isLoading = true
                let n = DruzabnaPrijavaLogika.nakljucenNiz()
                nonceApple = n
                zahteva.requestedScopes = [.email]
                zahteva.nonce = DruzabnaPrijavaLogika.sha256Hex(n)
            }, onCompletion: { izid in
                Task { await apple(izid) }
            })
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isLoading)

            if DruzabnaPrijavaLogika.googleKonfiguriran {
                Button {
                    guard !isLoading else { return }
                    isLoading = true   // sinhrono, preden se zacne Task: dvojni dotik ne odpre dveh sej
                    Task { await google() }
                } label: {
                    HStack(spacing: 10) {
                        Image("google_g")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .foregroundColor(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            if let message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
        }
    }

    private func apple(_ izid: Result<ASAuthorization, Error>) async {
        message = nil
        defer { isLoading = false }
        switch izid {
        case .failure(let napaka):
            // Uporabnik je list zaprl: brez napake.
            if let a = napaka as? ASAuthorizationError, a.code == .canceled { return }
            message = String(localized: "Something went wrong. Please try again.")
        case .success(let avtorizacija):
            guard let idToken = applovIdToken(avtorizacija), !nonceApple.isEmpty else {
                message = String(localized: "Something went wrong. Please try again.")
                return
            }
            do {
                let seja = try await SupabaseAuth.shared.signInWithIdToken(provider: "apple", idToken: idToken, nonce: nonceApple)
                koncaj(seja)
            } catch {
                message = error.userMessage
            }
        }
    }

    private func google() async {
        message = nil
        defer { isLoading = false }
        do {
            if let seja = try await vodja.prijava() { koncaj(seja) }
        } catch {
            message = error.userMessage
        }
    }

    /// Enako kot LoginView po uspesni prijavi: seja v Keychain; GET /me (SessionLoadingView) ustvari racun na backendu.
    private func koncaj(_ seja: SupabaseSession) {
        session.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
        CakajocaPotrditev.shared.pocisti()
        if !session.isLoggedIn {
            message = String(localized: "Could not save your session on this device. Please try again.")
        }
    }
}
