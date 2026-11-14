import SwiftUI

/// Vstop v aplikacijo. Od 14. 11. 2026 (Martin) je prijava OBVEZNA: brez seje aplikacija pokaze samo prijavo/registracijo
/// (razveljavi brskanje brez racuna iz #114, 19. 10. 2026; splet outly.si/app ostane odprt).
///
/// Zaslon po stanju seje (od zgoraj):
/// - brez seje: RegisterView | VerifyEmailView | LoginView po `authStage` (registracija, prekinjena pred vnosom kode, se ob zagonu
///   vrne na zaslon s kodo; potekla seja -> LoginView z obvestilom `sessionExpiredNotice`);
/// - seja, `me` se ni nalozen: SessionLoadingView (GET /me);
/// - `me` nalozen, racun nedokoncan (`onboarded_at` prazen): CompleteAccountView;
/// - sicer MainTabView. Odjava zamenja zaslon s prijavo, zavihki in podatki prejsnjega racuna se unicijo.
@MainActor
struct AuthGateView: View {
    @AppStorage("authStage") private var authStage: String = "register"
    @EnvironmentObject var session: SessionStore

    var body: some View {
        Group {
            if !session.isLoggedIn {
                // "main" brez zetona v Keychainu (po odjavi ali ponovni namestitvi, ko UserDefaults ostanejo iz varnostne kopije)
                // ali neznano stanje -> prijava.
                switch authStage {
                case "register": RegisterView()
                case "verifyEmail": VerifyEmailView()
                default: LoginView()
                }
            } else if session.me == nil {
                // Zeton je, uporabnika se nismo nalozili. GET /me pove, ali je racun dokoncan.
                SessionLoadingView()
            } else if session.needsOnboarding {
                // onboarded_at je prazen -> dokoncanje racuna (telefon, datum rojstva, drzava, zanri).
                CompleteAccountView()
            } else {
                MainTabView()
            }
        }
        .onChange(of: session.isLoggedIn) { prej, zdaj in
            // Odjava ali zavrnjena seja: prijava (ne zaslon s kodo ali registracija prejsnjega poskusa).
            if prej && !zdaj { authStage = "login" }
        }
        .onChange(of: session.sessionExpiredNotice) { _, obvestilo in
            // Streznik je sejo zavrnil: prijava (LoginView pokaze obvestilo).
            if obvestilo != nil { authStage = "login" }
        }
    }
}

/// Kratek zaslon med nalaganjem GET /me. Ob napaki omrezja ponudi ponovni poskus
/// in odjavo; ob 401 SessionStore sam odjavi in gate pokaze prijavo.
@MainActor
struct SessionLoadingView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)

                if let err = session.meLoadError {
                    Text(err)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    OutlyPrimaryButton(title: "Try again") {
                        Task { await session.refreshMe() }
                    }
                    .padding(.horizontal, 40)
                    Button("Log out") {
                        session.logout()
                        authStage = "login"
                    }
                    .foregroundColor(.white.opacity(0.6))
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await session.refreshMe() }
    }
}
