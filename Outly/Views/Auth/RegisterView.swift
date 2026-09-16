import SwiftUI

struct RegisterView: View {
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var message: String?
    /// Barva sporocila: true = uspeh (zeleno). Message je zdaj lokaliziran, zato barve
    /// ne moremo vec ugotoviti iz besed v besedilu (kot prej).
    @State private var messageIsSuccess = false

    @AppStorage("authStage") private var authStage: String = "register"
    @AppStorage("pendingEmail") private var pendingEmail: String = ""   // ✅ DODANO

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

                Text("Create an account")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.outlyBlue)
                    .padding(.top, 6)

                VStack(spacing: 12) {
                    OutlyTextField(placeholder: "username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    OutlyTextField(placeholder: "email@domain.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    OutlySecureField(placeholder: "password", text: $password)
                    OutlySecureField(placeholder: "confirm password", text: $confirmPassword)
                }
                .padding(.top, 10)

                if let message = message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(messageIsSuccess ? .green : .red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.horizontal, 18)
                }

                HStack(spacing: 14) {
                    Button {
                        Task { await register() }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoading { ProgressView().tint(.white) }
                            Text(LocalizedStringKey(isLoading ? "Signing up..." : "Sign up"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.outlyBlue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(isLoading)

                    Button {
                        authStage = "login"
                    } label: {
                        Text("Sign in")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(Color.black.opacity(0.65))
                            .cornerRadius(14)
                    }
                    .disabled(isLoading)
                }
                .padding(.top, 8)

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
                .padding(.top, 14)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    func register() async {
        message = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedUsername.count >= 3 else {
            message = String(localized: "Username must be at least 3 characters.")
            return
        }
        guard trimmedUsername.count <= 20 else {
            message = String(localized: "Username can have at most 20 characters.")
            return
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard trimmedUsername.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            message = String(localized: "Username can contain only letters, numbers and underscore.")
            return
        }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") else {
            message = String(localized: "Enter a valid email address.")
            return
        }
        guard password.count >= 8 else {
            message = String(localized: "Password must be at least 8 characters.")
            return
        }
        guard password == confirmPassword else {
            message = String(localized: "Passwords do not match.")
            return
        }

        messageIsSuccess = false
        isLoading = true
        defer { isLoading = false }

        // Registracija pri Supabase (edina identiteta). Username gre v user_metadata;
        // backend ga prevzame, ko ob prvi prijavi ustvari lokalni racun.
        do {
            let ustvarjen = try await SupabaseAuth.shared.signUp(
                email: cleanEmail, password: password, username: trimmedUsername
            )
            await MainActor.run {
                if ustvarjen {
                    pendingEmail = cleanEmail
                    messageIsSuccess = true
                    message = String(localized: "Account created. Check your email for the code.")
                    authStage = "verifyEmail"
                } else {
                    message = String(localized: "That email is already registered. Sign in instead.")
                }
            }
        } catch {
            await MainActor.run {
                message = error.userMessage
            }
        }
    }
}
