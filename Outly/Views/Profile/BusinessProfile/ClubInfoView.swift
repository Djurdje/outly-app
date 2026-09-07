import SwiftUI
import PhotosUI
import CoreLocation

/// Podatki kluba (GET/PATCH /business/clubs/me). Vsi klici gredo prek APIClient.send,
/// napake prek userMessage. Ob spremembi naslova ali mesta se koordinate izracunajo
/// na napravi (CLGeocoder) in posljejo strezniku — brez njih klub NI na zemljevidu.
@MainActor
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
    @State private var clubCity = ""
    @State private var clubLat: Double?
    @State private var clubLng: Double?
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
        case name, phone, website, email, description, address, city
        var id: String { "\(self)" }

        var title: String {
            switch self {
            case .name: return "Club name"
            case .phone: return "Phone number"
            case .website: return "Website"
            case .email: return "Email"
            case .description: return "About club"
            case .address: return "Address"
            case .city: return "City"
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

                infoCard(icon: "mappin.and.ellipse", title: "Address", value: clubAddress, field: .address,
                         description: "Street and number. Together with the city this places your club on the map.")

                infoCard(icon: "building.2", title: "City", value: clubCity, field: .city,
                         description: clubLat != nil
                            ? "On the map ✓"
                            : "Not on the map yet — set the address and city.")

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
                        Task { await saveClub(changed: field) }
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
        case .city: clubCity = v
        }
    }

    // MARK: - API

    private func loadClub() async {
        guard !authToken.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let club = try await APIClient.shared.fetchMyBusinessClub(token: authToken)
            apply(club)
        } catch let api as APIError {
            if case let .requestFailed(code, raw) = api, code == 404, raw.lowercased().contains("club") {
                errorMessage = "Your club is not set up yet. Contact luka@outly.si to get it created."
            } else {
                errorMessage = api.userMessage
            }
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func apply(_ club: APIClub) {
        clubName = club.name
        clubPhone = club.contactPhone
        clubWebsite = club.website
        clubEmail = club.contactEmail
        clubDescription = club.description
        clubAddress = club.address
        clubCity = club.city
        clubLat = club.lat
        clubLng = club.lng
        clubLogoUrl = club.logoUrl
        clubBannerUrl = club.bannerUrl
    }

    /// Shrani spremenjeno polje. Pri naslovu/mestu najprej poisce koordinate.
    private func saveClub(changed field: EditField? = nil) async {
        guard !authToken.isEmpty else { return }
        errorMessage = nil

        if field == .address || field == .city {
            await geocodeIfPossible()
        }

        var fields: [String: Any] = [
            "name": clubName,
            "contact_phone": clubPhone,
            "website": clubWebsite,
            "contact_email": clubEmail,
            "description": clubDescription,
            "address": clubAddress,
            "city": clubCity,
            "logo_url": clubLogoUrl,
            "banner_url": clubBannerUrl,
        ]
        // Koordinati gresta v paru (omejitev v bazi: obe ali nobena).
        if let lat = clubLat, let lng = clubLng {
            fields["lat"] = lat
            fields["lng"] = lng
        }

        do {
            let club = try await APIClient.shared.updateMyBusinessClub(token: authToken, fields: fields)
            apply(club)
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Naslov + mesto -> koordinate. Ce geokodiranje ne uspe, stare koordinate ostanejo.
    private func geocodeIfPossible() async {
        let query = [clubAddress, clubCity].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !query.isEmpty else { return }
        do {
            let marks = try await CLGeocoder().geocodeAddressString(query)
            if let loc = marks.first?.location {
                clubLat = loc.coordinate.latitude
                clubLng = loc.coordinate.longitude
            }
        } catch {
            // Ni usodno: klub se shrani brez novih koordinat, uporabnik vidi "Not on the map yet".
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
            await MainActor.run { errorMessage = "Logo upload failed. \(error.userMessage)" }
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
            await MainActor.run { errorMessage = "Banner upload failed. \(error.userMessage)" }
        }
    }
}
