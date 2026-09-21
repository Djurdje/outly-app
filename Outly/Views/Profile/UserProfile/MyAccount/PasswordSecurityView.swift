import SwiftUI

/// Geslo in varnost — po Figmi "Pass and sec" (95:1403): naslov, kartica "Login" z vrstico
/// "Change password → Edit" in opombo (OutlyInfoCardButton, isti slog kot Personal info). Dvostopenjske potrditve in Google/Apple prijave
/// backend nima, zato teh vrstic ni (Apple zavrne gumbe, ki ne delajo nic).
/// Dodana kartica "Sessions" (odjava z vseh naprav) — ni v Figmi, a je varnostno potrebna.
@MainActor
struct PasswordSecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"

    @State private var showChange = false
    @State private var isLoggingOutAll = false
    @State private var showLogoutAllConfirm = false
    @State private var success: String?

    var body: some View {
        // Potisnjen na obstojeci NavigationStack; brez lastnega NavigationStacka.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                Text("Password and security")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                if let success {
                    Text(success)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }

                // Isti gradnik kot Personal info (Luka, 21. 9.: samo dva sloga vrstic v aplikaciji).
                OutlyInfoCardButton(icon: "lock", title: "Login",
                                    value: String(localized: "Change password"),
                                    description: "You can change your password at any time.",
                                    actionTitle: "Edit") { showChange = true }

                OutlyInfoCardButton(icon: "iphone.and.arrow.forward", title: "Sessions",
                                    value: String(localized: "Sign out of all devices"),
                                    description: "Signed in somewhere you don't recognise? Sign out everywhere, including this device.",
                                    actionTitle: isLoggingOutAll ? "Signing out…" : "Sign out",
                                    actionColor: Color(red: 1, green: 0.35, blue: 0.35)) { showLogoutAllConfirm = true }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // List namesto navigationDestination(isPresented:) — isti razlog kot v ClubInfoView.
        .sheet(isPresented: $showChange) {
            NavigationStack {
                PasswordChangeView { success = String(localized: "Password changed. Other devices were signed out.") }
            }
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("Sign out of all devices?", isPresented: $showLogoutAllConfirm, titleVisibility: .visible) {
            Button("Sign out everywhere", role: .destructive) { Task { await logoutEverywhere() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out on this device too.")
        }
    }

    private func logoutEverywhere() async {
        isLoggingOutAll = true
        defer { isLoggingOutAll = false }
        do {
            try await SupabaseAuth.shared.signOut(token: session.token, scope: "global")
        } catch {
            // Tudi ce Supabase ne odgovori, se lokalno odjavimo.
        }
        session.logout()
        authStage = "login"
    }
}

/// Sprememba gesla — po Figmi "Pass change" (184:2333): naslov "Password change", "Done"
/// desno zgoraj, tri temna polja z oznako in opombo. Trenutno geslo se preveri s ponovno
/// prijavo pri Supabase, nato se z novo sejo nastavi novo geslo (druge naprave Supabase odjavi).
@MainActor
struct PasswordChangeView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let onChanged: () -> Void

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var isSaving = false

    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 8 && !confirm.isEmpty && !isSaving
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                OutlyDarkSecureField(
                    label: "Password",
                    placeholder: "Enter the current password",
                    text: $current,
                    hint: "Enter the current password for security reasons",
                    contentType: .password
                )
                OutlyDarkSecureField(
                    label: "New password",
                    placeholder: "Enter new password",
                    text: $newPassword,
                    hint: "At least 8 characters",
                    contentType: .newPassword
                )
                OutlyDarkSecureField(
                    label: "Confirm password",
                    placeholder: "Repeat new password",
                    text: $confirm,
                    hint: "Double check that you entered the password correctly",
                    contentType: .newPassword
                )

                if let message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

                Text("After changing your password, all other devices are signed out. This one stays signed in.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .outlyOzadje()
        .navigationTitle("Password change")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Button("Done") { Task { await change() } }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(canSubmit ? .white : .white.opacity(0.35))
                        .disabled(!canSubmit)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func change() async {
        message = nil
        guard newPassword == confirm else { message = String(localized: "New passwords do not match."); return }
        guard newPassword != current else { message = String(localized: "New password must be different from the current one."); return }
        guard let email = session.me?.email, !email.isEmpty else {
            message = String(localized: "Your profile is still loading. Please try again.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let seja = try await SupabaseAuth.shared.signIn(email: email, password: current)
            try await SupabaseAuth.shared.updatePassword(token: seja.accessToken, newPassword: newPassword)
            session.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
            onChanged()
            dismiss()
        } catch let sb as SupabaseAuthError {
            if sb.code == "invalid_credentials" || sb.message.lowercased().contains("invalid login credentials") {
                message = String(localized: "Current password is wrong.")
                return
            }
            message = sb.userMessage
        } catch {
            message = error.userMessage
        }
    }
}
