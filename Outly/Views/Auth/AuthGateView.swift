import SwiftUI

struct AuthGateView: View {
    @AppStorage("authStage") private var authStage: String = "register"
    @EnvironmentObject var prefs: UserPreferences

    var body: some View {
        switch authStage {
        case "register":
            RegisterView()

        case "verifyEmail":
            VerifyEmailView()

        case "login":
            LoginView()

        case "main":
            if prefs.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingView()
            }

        default:
            RegisterView()
        }
    }
}
