import SwiftUI

/// Figma: "my acc delete" (558:1943). Applova zahteva 5.1.1(v): brisanje racuna v aplikaciji.
/// Backend (DELETE /me) zahteva geslo; ce ima uporabnik narocila, jih anonimizira
/// (racunovodske listine ostanejo, osebni podatki ne).
@MainActor
struct DeleteAccountView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var message: String?
    @State private var isLoading = false
    @State private var showConfirm = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Delete account")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("This action is permanent. It will remove your account, liked events and personal data. Tickets you have already bought stay valid, but they will no longer be linked to you and cannot be recovered in the app.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Enter your password to confirm.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                OutlySecureField(placeholder: "password", text: $password)
                    .textContentType(.password)

                if let message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showConfirm = true
                } label: {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().tint(.white) }
                        Text(LocalizedStringKey(isLoading ? "Deleting..." : "Delete Account"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isLoading || password.isEmpty)
                .opacity(password.isEmpty ? 0.6 : 1)

                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)

                Spacer()
            }
            .padding(24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .alert("Are you sure you want to delete your account?", isPresented: $showConfirm) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We're sorry to see you go! This is permanent: your account and personal data will be removed, and tickets you bought will no longer be linked to you.")
        }
    }

    private func deleteAccount() async {
        message = nil
        guard !password.isEmpty else { message = String(localized: "Enter your password to continue."); return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIClient.shared.deleteAccount(token: session.token, password: password)
            // Racun ne obstaja vec: zeton izbrisi in vrni na prijavo.
            session.logout()
            authStage = "login"
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 {
                // 401 tu pomeni napacno geslo (streznik vrne "Invalid credentials"), NE potekle seje.
                message = String(localized: "Wrong password.")
                return
            }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }
}
