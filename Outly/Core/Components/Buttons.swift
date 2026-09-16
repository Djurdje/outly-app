import SwiftUI
import PhotosUI

//Gumbi

/// Glavni modri gumb iz Figme (#4C76FF, visina 40-48, radij 8-14). Eno mesto,
/// da se Login/Register/Forgot/Complete ne razidejo.
struct OutlyPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(.white) }
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.outlyBlue)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
    }
}

struct OutlyMenuRowButton: View {
    let icon: String
    let title: String
    var height: CGFloat = 60
    /// Rdeca znacka desno (npr. stevilo cakajocih vabil pri "My Clubs"); 0 = brez.
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text(LocalizedStringKey(title))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Color(red: 1, green: 0.30, blue: 0.30)))
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
struct OutlyInfoCardButton: View {
    let icon: String
    let title: String          // "Username" / "Phone number" (ZNOTRAJ kartice)
    let value: String          // "getoglava" / "+386..."
    let description: String    // sivi opis spodaj
    var actionTitle: String = "Edit"
    var onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text(LocalizedStringKey(title))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)

                Text(value)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                // Prazen actionTitle = samo prikaz, brez gumba (npr. e-naslov, ki ga ni mogoce urejati).
                if !actionTitle.isEmpty {
                    Button(action: onAction) {
                        Text(LocalizedStringKey(actionTitle))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.blackColor)
                    }
                }
            }

            Text(LocalizedStringKey(description))
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

struct AvatarUploadButton: View {
    @EnvironmentObject private var session: SessionStore

    // Parent ti poda trenutnega userja, mi ga posodabljamo po uploadu
    @Binding var user: Me?

    @State private var pickedItem: PhotosPickerItem?
    @State private var isUploading = false

    var size: CGFloat = 64

    var body: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            ZStack {
                if let urlString = user?.avatarUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.12)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.75))
                        .padding(10)
                }

                if isUploading {
                    Color.black.opacity(0.35)
                    ProgressView()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
        .disabled(isUploading)
        .onChange(of: pickedItem) { _, newItem in
            if let newItem {
                Task { await handlePicked(newItem) }
            }
        }
    }

    private func handlePicked(_ item: PhotosPickerItem) async {
        let token = session.token
        guard !token.isEmpty else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            let sig = try await APIClient.shared.fetchCloudinarySignature(token: token)
            let imageUrl = try await APIClient.shared.uploadImageToCloudinary(
                imageData: data,
                fileName: "avatar.jpg",
                signature: sig
            )

            let updated = try await APIClient.shared.updateMyAvatar(token: token, avatarUrl: imageUrl)

            // takoj posodobi UI
            await MainActor.run {
                user = updated
            }
        } catch {
            print("Avatar upload error:", error.localizedDescription)
        }
    }
}
