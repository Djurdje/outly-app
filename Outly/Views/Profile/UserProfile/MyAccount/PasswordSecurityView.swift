import SwiftUI

/// Geslo in varnost. Prej so bile tu tri vrstice brez delovanja (sprememba gesla,
/// dvostopenjska potrditev, povezava z Applom). Dvostopenjske potrditve in Apple
/// prijave backend nima, zato vrstic ni — Apple zavrne gumbe, ki ne delajo nic.
@MainActor
struct PasswordSecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var success: String?
    @State private var isSaving = false
    @State private var isLoggingOutAll = false

    var body: some View {
        // Ta pogled se POTISNE na obstojeci NavigationStack (ProfileView/MyAccountView);
        // gnezden NavigationStack bi skril gumb nazaj in zlomil navigacijo.
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {

                    Text("Password and security")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Change password")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        OutlySecureField(placeholder: "current password", text: $current)
                            .textContentType(.password)
                        OutlySecureField(placeholder: "new password (min. 8 characters)", text: $newPassword)
                            .textContentType(.newPassword)
                        OutlySecureField(placeholder: "confirm new password", text: $confirm)
                            .textContentType(.newPassword)

                        Text("After changing your password, all other devices are signed out. This one stays signed in.")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.55))

                        if let message {
                            Text(message).font(.system(size: 14, weight: .medium)).foregroundColor(.red)
                        }
                        if let success {
                            Text(success).font(.system(size: 14, weight: .medium)).foregroundColor(.green)
                        }

                        OutlyPrimaryButton(title: isSaving ? "Saving..." : "Change password", isLoading: isSaving) {
                            Task { await change() }
                        }
                        .disabled(isSaving || !canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sessions")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("Signed in somewhere you don't recognise? Sign out everywhere, including this device.")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.55))
                        Button {
                            Task { await logoutEverywhere() }
                        } label: {
                            HStack(spacing: 10) {
                                if isLoggingOutAll { ProgressView().tint(.white) }
                                Text("Sign out of all devices")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                        .disabled(isLoggingOutAll)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }

    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 8 && !confirm.isEmpty
    }

    private func change() async {
        message = nil
        success = nil
        guard newPassword == confirm else { message = "New passwords do not match."; return }
        guard newPassword != current else { message = "New password must be different from the current one."; return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await APIClient.shared.changePassword(token: session.token, current: current, new: newPassword)
            current = ""; newPassword = ""; confirm = ""
            success = "Password changed. Other devices were signed out."
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 {
                // Tu 401 pomeni napacno trenutno geslo, ne potekle seje (send() bi sejo ze osvezil).
                message = "Current password is wrong."
                return
            }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }

    private func logoutEverywhere() async {
        isLoggingOutAll = true
        defer { isLoggingOutAll = false }
        do {
            _ = try await APIClient.shared.send(path: "auth/logout-all", method: "POST", token: session.token)
        } catch {
            // Tudi ce streznik ne odgovori, se lokalno odjavimo.
        }
        session.logout()
        authStage = "login"
    }
}
