import SwiftUI
import AuthenticationServices

/// Vodi prijavo z Googlom brez Google SDK: `ASWebAuthenticationSession` odpre Supabasov `/authorize?provider=google` (PKCE),
/// Supabase po Googlu preusmeri na `si.outly.app://auth-callback?code=...`, kodo zamenjamo za sejo (`/token?grant_type=pkce`).
///
/// - Sistem prestreze shemo `si.outly.app` sam; registracija URL sheme v Info.plist NI potrebna (kot pri Stripu, StripeSeja.swift).
/// - `presentationContextProvider` je v ASWebAuthenticationSession SIBKA referenca: vodja mora ziveti (`@State` v DruzabniGumbi).
/// - Seja je v MOCNI referenci, dokler tece; `prefersEphemeralWebBrowserSession` je izklopljen, da uporabnik, ki je ze prijavljen
///   v Google v Safariju, izbere racun z enim dotikom (sistem pokaze vprasanje »Outly wants to use google.com to sign in«).
@MainActor
final class GoogleSejaVodja: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var seja: ASWebAuthenticationSession?

    /// Vrne sejo ali nil, ce je uporabnik prijavo preklical (zaprl okno ali na Googlu pritisnil Cancel).
    func prijava() async throws -> SupabaseSession? {
        let verifier = DruzabnaPrijavaLogika.nakljucenNiz()
        guard let url = DruzabnaPrijavaLogika.authorizeURL(
            baseURL: SupabaseAuth.shared.baseURL, provider: "google",
            challenge: DruzabnaPrijavaLogika.pkceChallenge(verifier)) else { throw APIError.invalidURL }

        let povratni: URL? = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL?, Error>) in
            let obdelava: @Sendable (URL?, Error?) -> Void = { klic, napaka in
                if let napaka {
                    if let e = napaka as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                        cont.resume(returning: nil)
                    } else {
                        cont.resume(throwing: napaka)
                    }
                } else {
                    cont.resume(returning: klic)
                }
            }
            let nova = ASWebAuthenticationSession(url: url, callbackURLScheme: DruzabnaPrijavaLogika.shemaVrnitve,
                                                  completionHandler: obdelava)
            nova.prefersEphemeralWebBrowserSession = false
            nova.presentationContextProvider = self
            seja = nova
            if !nova.start() {
                // `start()` false: obdelava se NE pokliče, zato nadaljujemo sami (natanko enkrat).
                seja = nil
                cont.resume(throwing: SupabaseAuthError(status: 0, code: "", message: "ASWebAuthenticationSession did not start"))
            }
        }
        seja = nil
        guard let povratni else { return nil }

        switch DruzabnaPrijavaLogika.razclenPovratek(povratni) {
        case .koda(let koda):
            return try await SupabaseAuth.shared.exchangeCode(authCode: koda, codeVerifier: verifier)
        case .napaka(let e, let opis):
            // Cancel na Googlovem zaslonu soglasja pride kot error=access_denied: ni napaka, uporabnik si je premislil.
            if e == "access_denied" { return nil }
            throw SupabaseAuthError(status: 400, code: e, message: opis ?? "")
        case .neveljaven:
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

/// »or« + Continue with Apple + Continue with Google (prijava in registracija). Besedilo o pogojih je pod gumbi v LoginView/RegisterView
/// (»By clicking continue, you agree to our Terms of Service and Privacy Policy«). Po uspehu seja pride v SessionStore, AuthGateView
/// zamenja zaslon; zapis privolitve (`terms_version`) uredi SessionStore.zagotoviPrivolitev po GET /me.
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
            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                Text("or")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
            }

            SignInWithAppleButton(.continue, onRequest: { zahteva in
                let n = DruzabnaPrijavaLogika.nakljucenNiz()
                nonceApple = n
                zahteva.requestedScopes = [.email, .fullName]
                zahteva.nonce = DruzabnaPrijavaLogika.sha256Hex(n)
            }, onCompletion: { izid in
                Task { await apple(izid) }
            })
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isLoading)

            Button {
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
        switch izid {
        case .failure(let napaka):
            // Uporabnik je list zaprl: brez napake.
            if let a = napaka as? ASAuthorizationError, a.code == .canceled { return }
            message = String(localized: "Something went wrong. Please try again.")
        case .success(let avtorizacija):
            guard let cred = avtorizacija.credential as? ASAuthorizationAppleIDCredential,
                  let podatki = cred.identityToken,
                  let idToken = String(data: podatki, encoding: .utf8),
                  !nonceApple.isEmpty else {
                message = String(localized: "Something went wrong. Please try again.")
                return
            }
            isLoading = true
            defer { isLoading = false }
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
        isLoading = true
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
