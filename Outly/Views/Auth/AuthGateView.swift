import SwiftUI

struct AuthGateView: View {
    @AppStorage("authStage") private var authStage: String = "register"
    @EnvironmentObject var session: SessionStore

    var body: some View {
        switch authStage {
        case "register":
            RegisterView()

        case "verifyEmail":
            VerifyEmailView()

        case "login":
            LoginView()

        case "main":
            if !session.isLoggedIn {
                // "main" brez zetona v Keychainu (npr. po ponovni namestitvi, ko UserDefaults
                // ostanejo iz varnostne kopije) -> nazaj na prijavo.
                LoginView()
            } else if session.me == nil {
                // Zeton je, uporabnika se nismo nalozili. GET /me pove, ali je racun dokoncan.
                SessionLoadingView()
            } else if session.needsOnboarding {
                // onboarded_at je prazen -> dokoncanje racuna (telefon, datum rojstva, drzava, zanri).
                CompleteAccountView()
            } else {
                MainTabView()
            }

        default:
            RegisterView()
        }
    }
}

/// Kratek zaslon med nalaganjem GET /me. Ob napaki omrezja ponudi ponovni poskus
/// in odjavo; ob 401 SessionStore sam odjavi in gate pokaze prijavo.
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
