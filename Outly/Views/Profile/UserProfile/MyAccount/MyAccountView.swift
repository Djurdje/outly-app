import SwiftUI

struct MyAccountView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("authStage") private var authStage: String = "main"
    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }
    @State private var user: Me?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var userAvatarURL: URL? {
        guard let s = user?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        // Ta pogled se POTISNE na obstojeci NavigationStack (ProfileView/MyAccountView);
        // gnezden NavigationStack bi skril gumb nazaj in zlomil navigacijo.
        Group {
            VStack(spacing: 30) {
                // ===== HEADER =====
                VStack(spacing: 10) {

                    if let url = userAvatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.blackColor)
                            }
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 90, height: 90)
                            .foregroundColor(.blackColor)
                    }

                    if let user = user {
                        Text(user.username)
                            .font(.title2)
                    } else if isLoading {
                        Text("Loading...")
                            .font(.title2)
                            .foregroundColor(.gray)
                    } else {
                        Text("Unknown user")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Divider()
                    .background(Color.gray)
                    .padding(.horizontal, 15)

                // ===== MENU =====
                VStack(spacing: 12) {

                    NavigationLink(destination: PersonalInfoView()) {
                        OutlyMenuRowButton(icon: "person", title: "Personal info")
                    }

                    NavigationLink(destination: PasswordSecurityView()) {
                        OutlyMenuRowButton(icon: "lock", title: "Password and security")
                    }

                    NavigationLink(destination: ReguestForCreatorView()) {
                        OutlyMenuRowButton(icon: "chart.line.uptrend.xyaxis", title: "Request for creator")
                    }

                    Divider()
                        .background(Color.gray)
                        .padding(.horizontal, 15)
                        .padding(.top, 8)

                    NavigationLink(destination: NotificationsView()) {
                        OutlyMenuRowButton(icon: "bell", title: "Notifications")
                    }

                    Divider()
                        .background(Color.gray)
                        .padding(.horizontal, 15)
                        .padding(.top, 8)

                    Button {
                        session.logout()
                        authStage = "login"
                    } label: {
                        OutlyMenuRowButton(icon: "arrow.left", title: "Log out")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: DeleteAccountView()) {
                        OutlyMenuRowButton(icon: "trash", title: "Delete account")
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("")
        }
        .preferredColorScheme(.dark)
        .task {
            await loadMe()
        }
        .onAppear {
            // ko se vrneš iz PersonalInfoView po uploadu, osveži avatar
            Task { await loadMe() }
        }
    }

    // ✅ /me fetch – brez User, brez mapped
    private func loadMe() async {
        guard !authToken.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let me = try await APIClient.shared.me(token: authToken)

            await MainActor.run {
                self.user = me
                self.isLoading = false
            }

        } catch let apiErr as APIError {
            if case let .requestFailed(code, _) = apiErr, code == 401 {
                await MainActor.run {
                    session.logout()
                    authStage = "login"
                }
                return
            }

            await MainActor.run {
                errorMessage = apiErr.localizedDescription
                isLoading = false
            }

        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// ===== Placeholder views =====

