import SwiftUI

/// Figma: "Create New Password" (15:985). Figma nima polja za kodo, Supabase pa
/// jo posilja v mailu — zato je tu polje za kodo. Dolzina kode je nastavljiva v
/// Supabase (Email OTP length, 6–10 stevk), zato sprejmemo 6 do 10 stevk in ne
/// odrezemo na 6 (Martin, 13. 9.: koda iz maila je bila daljsa in je ni bilo mogoce vpisati).
/// Koda (type "recovery")
/// vrne sejo, z njo nastavimo novo geslo (PUT /user) in sejo odjavimo, da se
/// uporabnik prijavi z novim geslom.
@MainActor
struct ResetPasswordView: View {
    let email: String

    @AppStorage("authStage") private var authStage: String = "login"
    @AppStorage("loginNotice") private var loginNotice: String = ""

    @State private var code = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var isLoading = false
    @State private var resent = false

    var body: some View {
        ZStack {
            Color.outlyBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    Spacer().frame(height: 30)

                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 140)

                    Text("We sent a code to \(email).")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)

                    Text("Your new password must be different from the\npreviously used password.")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 10)

                    OutlyTextField(placeholder: "code from the email", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: code) { _, newVal in
                            let digits = newVal.filter { $0.isNumber }
                            let cut = String(digits.prefix(10))
                            if cut != newVal { code = cut }
                        }

                    OutlySecureField(placeholder: "new password...", text: $password)
                        .textContentType(.newPassword)
                    OutlySecureField(placeholder: "confirm password...", text: $confirm)
                        .textContentType(.newPassword)

                    if let message {
                        Text(message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    OutlyPrimaryButton(title: isLoading ? "Saving..." : "Save", isLoading: isLoading) {
                        Task { await save() }
                    }
                    .disabled(isLoading || !canSubmit)
                    .opacity(canSubmit ? 1 : 0.6)

                    Button {
                        Task { await resend() }
                    } label: {
                        Text(resent ? "Code sent again" : "Resend code")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || resent)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.outlyBackground, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var canSubmit: Bool {
        (6...10).contains(code.count) && password.count >= 8 && !confirm.isEmpty
    }

    private func save() async {
        message = nil
        guard (6...10).contains(code.count) else { message = "Enter the code from the email."; return }
        guard password.count >= 8 else { message = "Password must be at least 8 characters."; return }
        guard password == confirm else { message = "Passwords do not match."; return }

        isLoading = true
        defer { isLoading = false }
        do {
            let seja = try await SupabaseAuth.shared.verify(email: email, code: code, type: "recovery")
            try await SupabaseAuth.shared.updatePassword(token: seja.accessToken, newPassword: password)
            // Sprememba gesla pri Supabase odjavi druge seje; to zacasno sejo zapremo
            // sami, da se uporabnik prijavi z novim geslom (kot prej).
            try? await SupabaseAuth.shared.signOut(token: seja.accessToken, scope: "global")
            // Nazaj na prijavo z obvestilom. Ponastavitev NE prijavi samodejno,
            // kar je prav: uporabnik se prijavi z novim geslom.
            // ForgotPasswordView opazuje loginNotice in se sam umakne na prijavo
            // (skupaj s tem zaslonom). Tukaj NE klicemo dismiss(), da ni dvojnega pop-a.
            loginNotice = "Password updated. Log in with your new password."
            authStage = "login"
        } catch {
            message = error.userMessage
        }
    }

    private func resend() async {
        message = nil
        isLoading = true
        do {
            try await SupabaseAuth.shared.requestPasswordReset(email: email)
        } catch {
            message = error.userMessage
            isLoading = false
            return
        }
        isLoading = false
        resent = true
        // Streznik nove kode ne poslje pogosteje kot enkrat na minuto. Cakanje tece
        // loceno, da gumb Save medtem NI zaklenjen (prej je bil 60 s "Saving...").
        Task {
            try? await Task.sleep(for: .seconds(60))
            resent = false
        }
    }
}
