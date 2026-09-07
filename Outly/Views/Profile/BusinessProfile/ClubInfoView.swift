import SwiftUI
import PhotosUI

struct ClubInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }

    let clubId: Int? // trenutno ga ne rabimo, ker bomo brali /business/clubs/me

    // UI state
    @State private var isLoading = false
    @State private var errorMessage: String?

    // club fields
    @State private var clubName = ""
    @State private var clubPhone = ""
    @State private var clubWebsite = ""
    @State private var clubEmail = ""
    @State private var clubDescription = ""
    @State private var clubAddress = ""
    @State private var clubLogoUrl = ""
    @State private var clubBannerUrl = ""

    // edit sheet
    @State private var activeEdit: EditField?
    @State private var editText = ""

    // pickers (IMPORTANT: presented pickers work with your button components)
    @State private var showLogoPicker = false
    @State private var showBannerPicker = false
    @State private var pickedLogoItem: PhotosPickerItem?
    @State private var pickedBannerItem: PhotosPickerItem?

    // upload
    @State private var isUploadingLogo = false
    @State private var isUploadingBanner = false

    enum EditField: Identifiable {
        case name, phone, website, email, description, address
        var id: String { "\(self)" }

        var title: String {
            switch self {
            case .name: return "Club name"
            case .phone: return "Phone number"
            case .website: return "Website"
            case .email: return "Email"
            case .description: return "About club"
            case .address: return "Address"
            }
        }

        var multiline: Bool { self == .description }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {

                // ===== LOGO CARD =====
                VStack(spacing: 14) {
                    ZStack {
                        logoView

                        if isUploadingLogo {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 72, height: 72)
                            ProgressView()
                        }

                        // plus badge
                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.blackColor)
                                        .frame(width: 26, height: 26)

                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.blue)
                                }
                            }
                            Spacer()
                        }
                        .frame(width: 72, height: 72)
                        .offset(x: 18, y: -6)
                    }
                    .onTapGesture {
                        guard !isUploadingLogo, !authToken.isEmpty else { return }
                        showLogoPicker = true
                    }

                    Text("Add a profile photo so people can\nrecognise you")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
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

                // ===== INFO CARDS =====
                infoCard(icon: "person", title: "Club name", value: clubName, field: .name,
                         description: "This is the official name of your club shown to users and on all published events.")

                infoCard(icon: "phone", title: "Phone number", value: clubPhone, field: .phone,
                         description: "This includes your club’s phone number used for customer inquiries and support.")

                infoCard(icon: "globe", title: "Website", value: clubWebsite, field: .website,
                         description: "Your official website link.")

                infoCard(icon: "envelope", title: "Email", value: clubEmail, field: .email,
                         description: "Email used for customer support and contact.")

                infoCard(icon: "doc.text", title: "About club", value: clubDescription, field: .description,
                         description: "Short description shown on your club page.")

                infoCard(icon: "mappin.and.ellipse", title: "Location", value: clubAddress, field: .address,
                         description: "Your club address shown to users.")

                // ===== BANNER CARD (button opens picker) =====
                OutlyInfoCardButton(
                    icon: "photo.on.rectangle",
                    title: "Profile banner",
                    value: clubBannerUrl.isEmpty ? "Upload banner image" : "Banner uploaded",
                    description: "Recommended size: 393x220px",
                    actionTitle: isUploadingBanner ? "Uploading..." : "Upload",
                    onAction: {
                        guard !isUploadingBanner, !authToken.isEmpty else { return }
                        showBannerPicker = true
                    }
                )

                if let url = URL(string: clubBannerUrl), !clubBannerUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.06))
                        }
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if isLoading {
                    ProgressView().padding(.top, 8)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 6)
                }

                Spacer(minLength: 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Club info")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
            }
        }
        .task { await loadClub() }
        .sheet(item: $activeEdit) { field in editSheet(field) }

        // ✅ these are the key: presented PhotosPicker
        .photosPicker(isPresented: $showLogoPicker, selection: $pickedLogoItem, matching: .images)
        .photosPicker(isPresented: $showBannerPicker, selection: $pickedBannerItem, matching: .images)

        .onChange(of: pickedLogoItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadLogo(newItem) }
        }
        .onChange(of: pickedBannerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadBanner(newItem) }
        }
    }

    // MARK: - UI helpers

    private var logoView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .frame(width: 72, height: 72)

            if let url = URL(string: clubLogoUrl), !clubLogoUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "building.2.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white.opacity(0.85))
                            .padding(10)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: "building.2.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(10)
            }
        }
        .frame(width: 72, height: 72)
    }

    private func infoCard(icon: String, title: String, value: String, field: EditField, description: String) -> some View {
        OutlyInfoCardButton(
            icon: icon,
            title: title,
            value: value.isEmpty ? "Not set" : value,
            description: description,
            onAction: {
                editText = value
                activeEdit = field
            }
        )
    }

    // MARK: - Edit sheet

    private func editSheet(_ field: EditField) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                if field.multiline {
                    TextEditor(text: $editText)
                        .frame(height: 140)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundColor(.white)
                } else {
                    TextField(field.title, text: $editText)
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { activeEdit = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        applyEdit(field)
                        activeEdit = nil
                        Task { await saveClub() }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func applyEdit(_ field: EditField) {
        let v = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name: clubName = v
        case .phone: clubPhone = v
        case .website: clubWebsite = v
        case .email: clubEmail = v
        case .description: clubDescription = v
        case .address: clubAddress = v
        }
    }

    // MARK: - API

    private func loadClub() async {
        guard !authToken.isEmpty else {
            await MainActor.run { errorMessage = "Missing auth token." }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            guard let url = URL(string: "https://outly-backend-roy3.onrender.com/business/clubs/me") else { return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "ClubInfo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load club (check backend /business/clubs/me)."])
            }

            let club = try JSONDecoder().decode(APIClub.self, from: data)

            await MainActor.run {
                clubName = club.name
                clubPhone = club.contactPhone
                clubWebsite = club.website
                clubEmail = club.contactEmail
                clubDescription = club.description
                clubAddress = club.address
                clubLogoUrl = club.logoUrl
                clubBannerUrl = club.bannerUrl
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func saveClub() async {
        guard !authToken.isEmpty else { return }

        do {
            guard let url = URL(string: "https://outly-backend-roy3.onrender.com/business/clubs/me") else { return }

            let payload: [String: Any] = [
                "name": clubName,
                "contact_phone": clubPhone,
                "website": clubWebsite,
                "contact_email": clubEmail,
                "description": clubDescription,
                "address": clubAddress,
                "logo_url": clubLogoUrl,
                "banner_url": clubBannerUrl
            ]

            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "ClubInfo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to save club."])
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Upload (Cloudinary) — same pattern as PersonalInfoView

    private func uploadLogo(_ item: PhotosPickerItem) async {
        guard !authToken.isEmpty else { return }

        await MainActor.run {
            isUploadingLogo = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isUploadingLogo = false } }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "ClubInfo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to read selected image data."])
            }

            let sig = try await APIClient.shared.fetchCloudinarySignature(token: authToken)
            let imageUrl = try await APIClient.shared.uploadImageToCloudinary(
                imageData: data,
                fileName: "club_logo.jpg",
                signature: sig
            )

            await MainActor.run { clubLogoUrl = imageUrl }
            await saveClub()
        } catch {
            await MainActor.run { errorMessage = "Logo upload failed: \(error.localizedDescription)" }
        }
    }

    private func uploadBanner(_ item: PhotosPickerItem) async {
        guard !authToken.isEmpty else { return }

        await MainActor.run {
            isUploadingBanner = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isUploadingBanner = false } }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "ClubInfo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to read selected image data."])
            }

            let sig = try await APIClient.shared.fetchCloudinarySignature(token: authToken)
            let imageUrl = try await APIClient.shared.uploadImageToCloudinary(
                imageData: data,
                fileName: "club_banner.jpg",
                signature: sig
            )

            await MainActor.run { clubBannerUrl = imageUrl }
            await saveClub()
        } catch {
            await MainActor.run { errorMessage = "Banner upload failed: \(error.localizedDescription)" }
        }
    }
}
