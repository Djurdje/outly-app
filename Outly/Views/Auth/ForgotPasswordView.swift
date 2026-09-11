import SwiftUI

/// Figma: "Forgot pass" (15:738). Vnos e-naslova -> Supabase /recover (mail s
/// 6-mestno kodo in povezavo). Supabase vedno odgovori 200, zato uporabniku ne
/// povemo, ali racun obstaja.
@MainActor
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    /// Ko ResetPasswordView uspe, nastavi obvestilo; tu se umaknemo nazaj na prijavo.
    @AppStorage("loginNotice") private var loginNotice: String = ""

    @State private var email = ""
    @State private var message: String?
    @State private var isLoading = false
    @State private var goToReset = false

    var body: some View {
        ZStack {
            Color.outlyBackground.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer().frame(height: 40)

                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)

                Text("Forgot password")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.outlyBlue)
                    .padding(.top, 10)

                Text("Please enter your email address to receive\na verification code.")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                OutlyTextField(placeholder: "email@domain.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.top, 20)

                if let message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                OutlyPrimaryButton(title: isLoading ? "Sending..." : "Send", isLoading: isLoading) {
                    Task { await send() }
                }
                .disabled(isLoading)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.outlyBackground, for: .navigationBar)
        .navigationDestination(isPresented: $goToReset) {
            ResetPasswordView(email: cleanEmail)
        }
        .onChange(of: loginNotice) { _, new in
            if !new.isEmpty { dismiss() }
        }
        .preferredColorScheme(.dark)
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func send() async {
        message = nil
        let e = cleanEmail
        guard e.contains("@"), e.contains("."), e.count >= 5 else {
            message = "Enter a valid email address."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await SupabaseAuth.shared.requestPasswordReset(email: e)
            goToReset = true
        } catch {
            message = error.userMessage
        }
    }
}
