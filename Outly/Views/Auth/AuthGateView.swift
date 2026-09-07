import SwiftUI

struct AuthGateView: View {
    @AppStorage("authStage") private var authStage: String = "register"
    @EnvironmentObject var prefs: UserPreferences
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
            // Zaslon "main" brez zetona v Keychainu (npr. po ponovni namestitvi,
            // ko UserDefaults ostanejo iz varnostne kopije) -> nazaj na prijavo.
            if !session.isLoggedIn {
                LoginView()
            } else if prefs.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingView()
            }

        default:
            RegisterView()
        }
    }
}
