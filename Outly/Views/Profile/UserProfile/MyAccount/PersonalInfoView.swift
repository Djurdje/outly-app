import SwiftUI
import PhotosUI

/// Osebni podatki iz GET /me z urejanjem prek PATCH /me: uporabnisko ime, telefon,
/// datum rojstva, drzava, zvrsti. E-naslova ni mogoce spremeniti (backend te poti nima —
/// sprememba e-naslova bi zahtevala ponovno potrditev), zato je samo prikazan.
@MainActor
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

    // Urejanje
    @State private var activeEdit: EditField?
    @State private var editText = ""
    @State private var editDate = Date()
    @State private var editCountry = "SI"
    @State private var isSaving = false
    @State private var editError: String?

    enum EditField: Identifiable {
        case username, phone, birthDate, country
        var id: String { "\(self)" }
        var title: String {
            switch self {
            case .username: return String(localized: "Username")
            case .phone: return String(localized: "Phone number")
            case .birthDate: return String(localized: "Date of birth")
            case .country: return String(localized: "Country")
            }
        }
    }

    private var profileImageUrl: URL? {
        guard let s = user?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        // Ta pogled se POTISNE na obstojeci NavigationStack (ProfileView/MyAccountView);
        // gnezden NavigationStack bi skril gumb nazaj in zlomil navigacijo.
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Personal info")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    profilePhotoCard

                    OutlyInfoCardButton(
                        icon: "person",
                        title: "Username",
                        value: user?.username ?? "—",
                        description: "This is your display name shown on your profile and used when managing events or teams."
                    ) { open(.username) }

                    OutlyInfoCardButton(
                        icon: "phone",
                        title: "Phone number",
                        value: user.flatMap { $0.phone }.flatMap { $0.isEmpty ? nil : $0 } ?? "Not set",
                        description: "Optional. Used for account recovery and important notifications. Include the country code, e.g. +386."
                    ) { open(.phone) }

                    OutlyInfoCardButton(
                        icon: "envelope",
                        title: "Email",
                        value: user?.email ?? "—",
                        description: "Your email is used for login and important notifications. To change it, contact luka@outly.si.",
                        actionTitle: ""
                    ) {}

                    OutlyInfoCardButton(
                        icon: "calendar",
                        title: "Date of birth",
                        value: displayBirthDate,
                        description: "Used to hide events you are too young for. This is not an age verification — that happens at the door."
                    ) { open(.birthDate) }

                    OutlyInfoCardButton(
                        icon: "globe",
                        title: "Country",
                        value: user?.country.flatMap { Countries.name(for: $0) } ?? "Not set",
                        description: "Your home country."
                    ) { open(.country) }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 6)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarBackButtonHidden(false)
        }
        .preferredColorScheme(.dark)
        .task { await loadMe() }
        .onAppear { if let me = session.me { user = me } }
        .onChange(of: pickedItem) { _, newItem in
            if let newItem { Task { await handlePickedAvatar(newItem) } }
        }
        .sheet(item: $activeEdit) { field in editSheet(field) }
    }

    // MARK: - Prikaz

    private var displayBirthDate: String {
        guard let dob = user?.dateOfBirth, let d = Self.parse(dob) else { return "Not set" }
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: d)
    }

    // MARK: - Urejanje

    private func open(_ field: EditField) {
        editError = nil
        switch field {
        case .username: editText = user?.username ?? ""
        case .phone: editText = user?.phone ?? ""
        case .birthDate:
            editDate = user?.dateOfBirth.flatMap(Self.parse)
                ?? Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
        case .country: editCountry = user?.country ?? (Locale.current.region?.identifier ?? "SI")
        }
        activeEdit = field
    }

    private func editSheet(_ field: EditField) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch field {
                case .username:
                    OutlyTextField(placeholder: "username", text: $editText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("3–20 characters: letters, numbers, underscore.")
                        .font(.caption).foregroundColor(.gray)
                case .phone:
                    OutlyTextField(placeholder: "+386 41 123 456", text: $editText)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Text("Leave empty to remove the number.")
                        .font(.caption).foregroundColor(.gray)
                case .birthDate:
                    DatePicker("", selection: $editDate,
                               in: (Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast)...Date(),
                               displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                case .country:
                    Picker("Country", selection: $editCountry) {
                        ForEach(Countries.all, id: \.code) { c in
                            Text(c.name).tag(c.code)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                if let editError {
                    Text(editError).font(.caption).foregroundColor(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeEdit = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save(field) }
                    } label: {
                        Text(LocalizedStringKey(isSaving ? "Saving..." : "Save"))
                    }
                    .disabled(isSaving)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
    }

    private func save(_ field: EditField) async {
        editError = nil
        var update = APIClient.MeUpdate()
        switch field {
        case .username:
            let u = editText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard u.count >= 3 else { editError = String(localized: "Username must be at least 3 characters."); return }
            update.username = u
        case .phone:
            let digits = editText.filter { $0.isNumber }
            if digits.isEmpty {
                update.phone = .some(nil)
            } else {
                guard editText.trimmingCharacters(in: .whitespaces).hasPrefix("+") else {
                    editError = String(localized: "Start with the country code, e.g. +386.")
                    return
                }
                update.phone = .some("+" + digits)
            }
        case .birthDate:
            let years = Calendar.current.dateComponents([.year], from: editDate, to: Date()).year ?? 0
            guard years >= 15 else { editError = String(localized: "You must be at least 15 years old to use Outly."); return }
            update.dateOfBirth = Self.format(editDate)
        case .country:
            update.country = editCountry
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let me = try await APIClient.shared.updateMe(token: authToken, update)
            user = me
            session.me = me
            activeEdit = nil
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); authStage = "login"; return }
            editError = api.userMessage
        } catch {
            editError = error.userMessage
        }
    }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // Lokalni casovni pas, enako kot DatePicker in prikaz — sicer je zahodno od GMT dan prej.
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    // MARK: - Profile photo card
    private var profilePhotoCard: some View {
        VStack(spacing: 14) {
            ZStack {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    avatarView
                }
                .disabled(isUploadingAvatar || authToken.isEmpty)

                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.outlyBlue)
                                .frame(width: 26, height: 26)

                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
                .frame(width: 70, height: 70)
                .offset(x: 18, y: -6)
            }

            Text("Add a profile photo so friends can\nrecognise you")
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .semibold))

            if isLoading {
                ProgressView().tint(.white)
            }
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if await session.refreshMe(), let me = session.me {
            user = me
        } else if !session.isLoggedIn {
            authStage = "login"
        } else {
            errorMessage = session.meLoadError
        }
    }

    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard !authToken.isEmpty else { return }
        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let sig = try await APIClient.shared.fetchCloudinarySignature(token: authToken)
            let imageUrl = try await APIClient.shared.uploadImageToCloudinary(
                imageData: data, fileName: "avatar.jpg", signature: sig)
            // PATCH /me/avatar vrne samo del polj (brez onboarded_at, club_role ...).
            // Ce bi ta delni objekt shranili v sejo, bi AuthGate uporabnika vrgel v
            // "Complete your account" in poslovni obraz bi izginil. Zato polni GET /me.
            _ = try await APIClient.shared.updateMyAvatar(token: authToken, avatarUrl: imageUrl)
            await session.refreshMe()
            if let m = session.me { user = m }
        } catch {
            errorMessage = error.userMessage
        }
    }
}
