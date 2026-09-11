import SwiftUI

@MainActor
struct LoginView: View {
    @AppStorage("authStage") private var authStage: String = "login"
    @EnvironmentObject private var session: SessionStore
    @AppStorage("pendingEmail") private var pendingEmail: String = ""
    /// Enkratno obvestilo (npr. po ponastavitvi gesla). Pokaze se in pobrise.
    @AppStorage("loginNotice") private var loginNotice: String = ""

    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            loginContent
        }
        .preferredColorScheme(.dark)
    }

    private var loginContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer().frame(height: 30)

                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 350)
                    .clipped()
                    .padding(.top, 10)

                Button {
                    loginNotice = ""
                    authStage = "register"
                } label: {
                    Text("Create an account")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.outlyBlue)
                        .padding(.top, 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text("Enter your email to sign up for this app")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, -6)

                VStack(spacing: 12) {
                    OutlyTextField(placeholder: "email@domain.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    OutlySecureField(placeholder: "password", text: $password)
                }
                .padding(.top, 6)

                HStack {
                    Spacer()
                    NavigationLink {
                        ForgotPasswordView()
                    } label: {
                        Text("Forgot password?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, -6)

                if let n = session.sessionExpiredNotice {
                    Text(n)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                if !loginNotice.isEmpty {
                    Text(loginNotice)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                if let message = message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                Button {
                    Task { await login() }
                } label: {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().tint(.white) }
                        Text(isLoading ? "Continue..." : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.outlyBlue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isLoading)

                Spacer()

                // "Continue with Apple" odstranjen: gumb ni delal nic (TODO), Apple
                // nedelujoc gumb zavrne po smernici 2.1. Vrni ga, ko bo Sign in with Apple narejen.

                VStack(spacing: 4) {
                    Text("By clicking continue, you agree to our")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.35))

                    HStack(spacing: 6) {
                        Link("Terms of Service", destination: LegalLinks.terms)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("and")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.35))
                        Link("Privacy Policy", destination: LegalLinks.privacy)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private func login() async {
        message = nil
        loginNotice = ""

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard cleanEmail.contains("@") else {
            message = "Vpiši veljaven email."
            return
        }
        guard !password.isEmpty else {
            message = "Vpiši geslo."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Prijava pri Supabase (edina identiteta). Backend Outlyja zeton preveri
            // in ob prvem klicu (GET /me) racun poveze ali ustvari.
            let seja = try await SupabaseAuth.shared.signIn(email: cleanEmail, password: password)

            session.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
            guard session.isLoggedIn else {
                // Keychain je zavrnil zapis (redko; npr. naprava se ni odklenjena po zagonu).
                message = "Could not save your session on this device. Please try again."
                return
            }
            // GET /me naredi SessionLoadingView takoj po preklopu na "main".
            authStage = "main"

        } catch {
            let text = error.userMessage
            let nepotrjen = (error as? SupabaseAuthError)?.code == "email_not_confirmed"

            await MainActor.run {
                message = text
                // E-naslov se ni potrjen: na zaslon s kodo iz maila.
                if nepotrjen {
                    pendingEmail = cleanEmail
                    authStage = "verifyEmail"
                }
            }
        }
    }
}
