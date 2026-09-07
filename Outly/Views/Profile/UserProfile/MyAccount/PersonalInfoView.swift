import SwiftUI
import PhotosUI

struct PersonalInfoView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("authStage") private var authStage: String = "main"
    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }

    @State private var user: Me?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Avatar picker/upload state
    @State private var pickedItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false

    // Placeholder phone (dokler ne dodaš v backend)
    @State private var phoneNumber: String = "+38640XXXXXX"

    // Uporabi avatar_url iz /me
    private var profileImageUrl: URL? {
        guard let s = user?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Personal info")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    // Profile photo card (tap avatar to upload)
                    profilePhotoCard

                    OutlyInfoCardButton(
                        icon: "person",
                        title: "Username",
                        value: user?.username ?? "—",
                        description: "This is your display name shown on your profile and used when managing events or teams."
                    ) {
                        // open edit username sheet
                    }

                    OutlyInfoCardButton(
                        icon: "phone",
                        title: "Phone number",
                        value: phoneNumber,
                        description: "Your contact number is used for account recovery and important notifications."
                    ) {
                        // open edit phone sheet
                    }

                    OutlyInfoCardButton(
                        icon: "envelope",
                        title: "Email",
                        value: user?.email ?? "—",
                        description: "Your email is used for login and important notifications."
                    ) {
                        // edit email
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 6)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarBackButtonHidden(false) // sistemski back
        }
        .preferredColorScheme(.dark)
        .task {
            await loadMe()
        }
        .onChange(of: pickedItem) { _, newItem in
            if let newItem {
                Task { await handlePickedAvatar(newItem) }
            }
        }
    }

    // MARK: - Profile photo card
    private var profilePhotoCard: some View {
        VStack(spacing: 14) {
            ZStack {
                // Klikabilen avatar (PhotosPicker)
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    avatarView
                }
                .disabled(isUploadingAvatar || authToken.isEmpty)

                // plus badge (kot na sliki)
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blackColor)
                                .frame(width: 26, height: 26)

                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                    Spacer()
                }
                .frame(width: 70, height: 70)
                .offset(x: 18, y: -6)
            }

            Text("Add a profile photo so friends can\nrecognnise you")
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .semibold))

            Text("ID: \(user?.id ?? 0)")
                .foregroundColor(.gray)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 70, height: 70)

            if let url = profileImageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white.opacity(0.85))
                            .padding(8)
                    }
                }
                .frame(width: 70, height: 70)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .foregroundColor(.white.opacity(0.85))
            }

            if isUploadingAvatar {
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 70, height: 70)

                ProgressView()
            }
        }
    }

    // MARK: - API
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
            // Če je 401, logout
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

    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard !authToken.isEmpty else { return }

        await MainActor.run {
            isUploadingAvatar = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in
                isUploadingAvatar = false
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            let sig = try await APIClient.shared.fetchCloudinarySignature(token: authToken)
            let imageUrl = try await APIClient.shared.uploadImageToCloudinary(
                imageData: data,
                fileName: "avatar.jpg",
                signature: sig
            )

            let updated = try await APIClient.shared.updateMyAvatar(token: authToken, avatarUrl: imageUrl)

            await MainActor.run {
                self.user = updated
            }
        } catch let apiErr as APIError {
            await MainActor.run {
                errorMessage = apiErr.localizedDescription
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}
