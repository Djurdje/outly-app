import SwiftUI

struct RegisterView: View {
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var message: String?

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
                    .foregroundColor(Color(red: 0.33, green: 0.47, blue: 0.98))
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
                        .foregroundColor(
                            message.lowercased().contains("created") || message.lowercased().contains("check your email")
                            ? .green : .red
                        )
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
                            Text(isLoading ? "Signing up..." : "Sign up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.33, green: 0.47, blue: 0.98))
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
            message = "Username naj bo vsaj 3 znake."
            return
        }
        guard trimmedUsername.count <= 20 else {
            message = "Username naj bo največ 20 znakov."
            return
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard trimmedUsername.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            message = "Username lahko vsebuje le črke, številke in _"
            return
        }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") else {
            message = "Vpiši veljaven email."
            return
        }
        guard password.count >= 8 else {
            message = "Geslo naj bo dolgo vsaj 8 znakov."
            return
        }
        guard password == confirmPassword else {
            message = "Gesli se ne ujemata."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let urlString = "https://outly-backend-roy3.onrender.com/auth/register"
        guard let url = URL(string: urlString) else {
            message = "Napačen URL."
            return
        }

        let payload: [String: Any] = [
            "username": trimmedUsername,
            "email": cleanEmail,
            "password": password
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                message = "Ni veljavnega odziva."
                return
            }

            if http.statusCode == 201 {
                await MainActor.run {
                    pendingEmail = cleanEmail
                    message = "Account created. Check your email for the code."
                    authStage = "verifyEmail"
                }
            } else {
                let text = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    message = "Napaka (\(http.statusCode)): \(text)"
                }
            }

        } catch {
            await MainActor.run {
                message = "Napaka: \(error.localizedDescription)"
            }
        }
    }
}
