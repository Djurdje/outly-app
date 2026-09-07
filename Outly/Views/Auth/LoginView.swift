import SwiftUI

struct LoginView: View {
    @AppStorage("authStage") private var authStage: String = "login"
    @EnvironmentObject private var session: SessionStore
    @AppStorage("pendingEmail") private var pendingEmail: String = ""

    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
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
                    authStage = "register"
                } label: {
                    Text("Create an account")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.33, green: 0.47, blue: 0.98))
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
                    .background(Color(red: 0.33, green: 0.47, blue: 0.98))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isLoading)

                Spacer()

                Divider()
                    .background(Color.gray)
                    .padding(.horizontal, 15)

                Button {
                    // TODO: Sign in with Apple later
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo")
                        Text("Continue with Apple")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.95))
                    .foregroundColor(.black.opacity(0.85))
                    .cornerRadius(14)
                }

                VStack(spacing: 4) {
                    Text("By clicking continue, you agree to our")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.35))

                    HStack(spacing: 6) {
                        Text("Terms of Service")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("and")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.35))
                        Text("Privacy Policy")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    private func login() async {
        message = nil

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
            let token = try await APIClient.shared.login(email: cleanEmail, password: password)

            await MainActor.run {
                session.setToken(token)
                authStage = "main"
            }

            Task {
                do {
                    let me = try await APIClient.shared.me(token: token)
                    print("✅ Logged in as \(me.username) role=\(me.role)")
                } catch {
                    print("⚠️ /me failed: \(error.localizedDescription)")
                }
            }

        } catch {
            let text = error.localizedDescription

            await MainActor.run {
                message = text

                // ✅ če backend blokira login zaradi verifikacije
                if text.lowercased().contains("email not verified") {
                    pendingEmail = cleanEmail
                    authStage = "verifyEmail"
                }
            }
        }
    }
}
