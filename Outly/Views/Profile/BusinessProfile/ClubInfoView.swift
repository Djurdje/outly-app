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
    /// Organizator brez lastnega prizorisca (backend 037): brez naslova in pina na zemljevidu.
    @State private var clubIsOrganizer = false
    @State private var clubLogoUrl = ""
    // Instagram, najnizja starost in zanri (outly-backend#20): PATCH /business/clubs/me jih sprejme,
    // posljemo pa jih samo, ko jih uporabnik uredi (`saveClub(changed:)`) — ce ima klub zanr, ki ga
    // strezniski seznam ne pozna, bi poslan celoten seznam zavrnil VSE shranjevanje.
    @State private var clubInstagram = ""
    @State private var clubMinAge = 18
    @State private var clubGenres: [String] = []
    @State private var allGenres: [String] = []
    @State private var genresFailed = false
    @State private var clubBarPrices: [BarPriceItem] = []
    @State private var showBarPricesEditor = false
    // Podatki prodajalca (backend#94): vidni in urejljivi samo lastniku; shranijo se posebej (`saveSeller`), ker jih manager
    // ne sme spremeniti (403 owner_only) in ker jih splosno shranjevanje (`saveClub`) nikoli ne posilja.
    @State private var clubLegalName = ""
    @State private var clubLegalAddress = ""
    @State private var clubRegistrationNumber = ""
    @State private var clubTaxNumber = ""
    @State private var clubVatPayer: Bool?
    @State private var clubSellerComplete = true

    // Slideshow (do 3 slike) in video (migracija 015)
    @State private var clubGalleryUrls: [String] = []
    @State private var clubVideoUrl = ""
    @State private var showGalleryPicker = false
    @State private var pickedGalleryItems: [PhotosPickerItem] = []
    @State private var isUploadingGallery = false
    @State private var showVideoPicker = false
    @State private var pickedVideoItem: PhotosPickerItem?
    @State private var isUploadingVideo = false

    // edit sheet
    @State private var activeEdit: EditField?
    @State private var editText = ""
    @State private var editMinAge = 18
    @State private var editGenres: Set<String> = []
    @State private var editError: String?

    // pickers (IMPORTANT: presented pickers work with your button components)
    @State private var showLogoPicker = false
    @State private var pickedLogoItem: PhotosPickerItem?

    // upload
    @State private var isUploadingLogo = false

    enum EditField: Identifiable {
        case name, phone, website, instagram, email, description, address, city, minAge, genres
        case legalName, legalAddress, registrationNumber, taxNumber
        var id: String { "\(self)" }

        var title: String {
            switch self {
            case .name: return String(localized: "Club name")
            case .phone: return String(localized: "Phone number")
            case .website: return String(localized: "Website")
            case .instagram: return String(localized: "Instagram")
            case .email: return String(localized: "Email")
            case .description: return String(localized: "About club")
            case .address: return String(localized: "Address")
            case .city: return String(localized: "City")
            case .minAge: return String(localized: "Minimum age")
            case .genres: return String(localized: "Music genres")
            case .legalName: return String(localized: "Company name")
            case .legalAddress: return String(localized: "Registered office")
            case .registrationNumber: return String(localized: "Registration number")
            case .taxNumber: return String(localized: "Tax number (VAT ID)")
            }
        }

        var multiline: Bool { self == .description }

        /// Kljuc v PATCH /business/clubs/me za podatke prodajalca; nil = navadno polje kluba.
        var kljucProdajalca: String? {
            switch self {
            case .legalName: return "legal_name"
            case .legalAddress: return "legal_address"
            case .registrationNumber: return "registration_number"
            case .taxNumber: return "tax_number"
            default: return nil
            }
        }

        /// Meje dolzin kot v bazi (CHECK): firma 200, sedez 300, maticna 20, davcna 20.
        var najvecZnakov: Int? {
            switch self {
            case .legalName: return 200
            case .legalAddress: return 300
            case .registrationNumber, .taxNumber: return 20
            default: return nil
            }
        }
    }

    /// Prvo nalaganje: podatkov se ni. Brez tega je zaslon ob odprtju poln "Not set"
    /// (Martin, posnetek 20. 9.) in je videti, kot da je klub prazen.
    private var prvicNalagam: Bool { isLoading && clubName.isEmpty && errorMessage == nil }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {

                if prvicNalagam {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Loading...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else {

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
                                        .foregroundColor(.white)
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

                infoCard(icon: "at", title: "Instagram", value: clubInstagram, field: .instagram,
                         description: "Your Instagram handle (@name) or a link. Shown in the contact section of your club page.")

                infoCard(icon: "envelope", title: "Email", value: clubEmail, field: .email,
                         description: "Email used for customer support and contact.")

                infoCard(icon: "doc.text", title: "About club", value: clubDescription, field: .description,
                         description: "Short description shown on your club page.")

                OutlyToggleDetailRow(icon: "megaphone",
                                     title: "I organize events without my own venue",
                                     subtitle: "No address or map pin. You choose the venue for each event.",
                                     isOn: Binding(get: { clubIsOrganizer },
                                                   set: { nov in Task { await saveOrganizer(nov) } }))

                if !clubIsOrganizer {
                    infoCard(icon: "mappin.and.ellipse", title: "Address", value: clubAddress, field: .address,
                             description: "Street and number. Together with the city this places your club on the map.")

                    infoCard(icon: "building.2", title: "City", value: clubCity, field: .city,
                             description: clubLat != nil
                                ? "On the map ✓"
                                : "Not on the map yet — set the address and city.")
                }

                OutlyInfoCardButton(
                    icon: "person.badge.shield.checkmark",
                    title: "Minimum age",
                    value: clubMinAge == 0 ? String(localized: "All ages") : "\(clubMinAge)+",
                    description: "Age limit of your club. Each event can set its own.",
                    onAction: {
                        editMinAge = clubMinAge
                        editError = nil
                        activeEdit = .minAge
                    }
                )

                OutlyInfoCardButton(
                    icon: "music.note",
                    title: "Music genres",
                    value: clubGenres.isEmpty ? String(localized: "Not set") : clubGenres.map { GenreNames.display($0) }.joined(separator: ", "),
                    description: "The music styles your club is known for.",
                    onAction: {
                        editGenres = Set(clubGenres)
                        editError = nil
                        activeEdit = .genres
                        if allGenres.isEmpty { Task { await loadGenres() } }
                    }
                )

                // Kartice "Profile banner" tu NI vec (Martin, 22. 9. 2026): stran kluba kaze
                // samo slideshow. Stolpec banner_url v bazi ostane, da klubi, ki imajo pasico
                // in se nimajo galerije, ne ostanejo brez slike (APIClub.slideshowUrls).

                // ===== SLIDESHOW (migracija 015) =====
                OutlyInfoCardButton(
                    icon: "photo.stack",
                    title: "Slideshow",
                    value: clubGalleryUrls.isEmpty ? String(localized: "No photos yet") : String(localized: "\(clubGalleryUrls.count) of 3 photos"),
                    description: "Up to 3 photos shown at the top of your club page (recommended 1200x800).",
                    actionTitle: isUploadingGallery ? "Uploading..." : "Choose photos",
                    onAction: {
                        guard !isUploadingGallery, !authToken.isEmpty else { return }
                        pickedGalleryItems = []
                        showGalleryPicker = true
                    }
                )

                if !clubGalleryUrls.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(clubGalleryUrls.enumerated()), id: \.offset) { i, u in
                            ZStack(alignment: .topTrailing) {
                                Color.clear
                                    .overlay(
                                        OutlyAsyncImage(url: URL(string: u)) { phase in
                                            switch phase {
                                            case .success(let image): image.resizable().scaledToFill()
                                            default: Rectangle().fill(Color.white.opacity(0.06))
                                            }
                                        }
                                    )
                                    .frame(height: 90)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Button {
                                    clubGalleryUrls.remove(at: i)
                                    Task { await saveGalleryAndVideo() }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white, Color.black.opacity(0.6))
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // ===== VIDEO (migracija 015) =====
                OutlyInfoCardButton(
                    icon: "play.rectangle",
                    title: "Club video",
                    value: clubVideoUrl.isEmpty ? String(localized: "No video yet") : String(localized: "Video uploaded"),
                    description: "Short intro video shown on your club page (up to 100 MB, plays muted in a loop).",
                    actionTitle: isUploadingVideo ? "Uploading..." : (clubVideoUrl.isEmpty ? "Upload" : "Replace"),
                    onAction: {
                        guard !isUploadingVideo, !authToken.isEmpty else { return }
                        showVideoPicker = true
                    }
                )

                if !clubVideoUrl.isEmpty {
                    Button {
                        clubVideoUrl = ""
                        Task { await saveGalleryAndVideo() }
                    } label: {
                        Text("Remove video")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                    }
                    .buttonStyle(.plain)
                }

                // ===== CENIK BARA (migracija 014) =====
                OutlyInfoCardButton(
                    icon: "wineglass",
                    title: "Bar prices",
                    value: clubBarPrices.isEmpty ? String(localized: "Not added yet") : String(localized: "\(clubBarPrices.count) items"),
                    description: "Guests see the list under \"Bar prices\" on every event of your club.",
                    onAction: { showBarPricesEditor = true }
                )

                // ===== PODATKI PRODAJALCA (backend#94) — samo lastnik =====
                if session.me?.isClubOwner == true {
                    prodajalecRazdelek
                }

                if isLoading {
                    ProgressView().padding(.top, 8)
                }

                } // konec else (prvicNalagam)

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
        .outlyOzadje()
        .navigationTitle("Club info")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // Pogled je potisnjen: sistemski gumb nazaj ze obstaja (prej sta bila dva).
        .task { await loadClub() }
        .sheet(item: $activeEdit) { field in editSheet(field) }
        // List namesto navigationDestination(isPresented:): ta v potisnjenem pogledu v iOS 17
        // vcasih potisne prazen zaslon (Luka, build 64: Club info "zasteka", podatki sele po Nazaj).
        .sheet(isPresented: $showBarPricesEditor) {
            NavigationStack {
                BarPricesEditorView(items: clubBarPrices) { clubBarPrices = $0 }
            }
            .preferredColorScheme(.dark)
        }

        // ✅ these are the key: presented PhotosPicker
        .photosPicker(isPresented: $showLogoPicker, selection: $pickedLogoItem, matching: .images)
        .photosPicker(isPresented: $showGalleryPicker, selection: $pickedGalleryItems, maxSelectionCount: 3, matching: .images)
        .photosPicker(isPresented: $showVideoPicker, selection: $pickedVideoItem, matching: .videos)
        .onChange(of: pickedGalleryItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await uploadGallery(items) }
        }
        .onChange(of: pickedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadVideo(newItem) }
        }

        .onChange(of: pickedLogoItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadLogo(newItem) }
        }
    }

    // MARK: - UI helpers

    private var logoView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .frame(width: 72, height: 72)

            if let url = URL(string: clubLogoUrl), !clubLogoUrl.isEmpty {
                OutlyAsyncImage(url: url) { phase in
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
            value: value.isEmpty ? String(localized: "Not set") : value,
            description: description,
            onAction: {
                editText = value
                editError = nil
                activeEdit = field
            }
        )
    }

    // MARK: - Podatki prodajalca (samo lastnik)

    private var prodajalecRazdelek: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Seller details")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("Shown to buyers before payment and on receipts (required by consumer law).")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if !clubSellerComplete {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                        Text("Some details are missing.")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(.top, 6)

            infoCard(icon: "building.columns", title: "Company name", value: clubLegalName, field: .legalName,
                     description: "Legal name of the company or sole proprietor that sells the tickets.")

            infoCard(icon: "mappin.and.ellipse", title: "Registered office", value: clubLegalAddress, field: .legalAddress,
                     description: "Street, postcode and city of the registered office.")

            infoCard(icon: "number", title: "Registration number", value: clubRegistrationNumber, field: .registrationNumber,
                     description: "Company registration number.")

            infoCard(icon: "doc.text", title: "Tax number (VAT ID)", value: clubTaxNumber, field: .taxNumber,
                     description: "Tax number or VAT ID, e.g. SI12345678.")

            vatStatusKartica
        }
    }

    /// Izbira DDV statusa: zavezanec / ni zavezanec / ni izbrano (nil). Shrani se takoj, vrednost pa se prevzame sele iz odgovora.
    private var vatStatusKartica: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VAT status")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "percent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text(vatStatusNapis(clubVatPayer))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Menu {
                    Button(vatStatusNapis(true)) { Task { await saveSeller(["vat_payer": true]) } }
                    Button(vatStatusNapis(false)) { Task { await saveSeller(["vat_payer": false]) } }
                    Button(vatStatusNapis(nil)) { Task { await saveSeller(["vat_payer": NSNull()]) } }
                } label: {
                    Text("Edit")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.outlyBlue)
                }
            }

            Text("Decides which VAT line buyers see under the total.")
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

    private func vatStatusNapis(_ vatPayer: Bool?) -> String {
        switch vatPayer {
        case true?: return String(localized: "VAT payer")
        case false?: return String(localized: "Not a VAT payer")
        default: return String(localized: "Not selected")
        }
    }

    // MARK: - Edit sheet

    private func editSheet(_ field: EditField) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch field {
                case .minAge:
                    Stepper(value: $editMinAge, in: 0...99) {
                        Text("Minimum age: \(editMinAge)")
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                case .genres:
                    if allGenres.isEmpty {
                        if genresFailed {
                            Text("Could not load genres.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 24)
                        } else {
                            ProgressView().tint(.white).padding(.top, 24)
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            OutlyGenreGrid(genres: allGenres, selected: $editGenres)
                        }
                    }
                default:
                    if field.multiline {
                        TextEditor(text: $editText)
                            .frame(height: 140)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundColor(.white)
                    } else {
                        TextField(field.title, text: $editText)
                            .keyboardType(field == .instagram || field == .website ? .URL : .default)
                            .textInputAutocapitalization(field == .instagram || field == .website ? TextInputAutocapitalization.never : nil)
                            .autocorrectionDisabled(field == .instagram || field == .website)
                            .padding()
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundColor(.white)
                    }
                }
                if let editError {
                    Text(editError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                        if field == .instagram, InstagramVnos.normaliziraj(editText) == nil {
                            editError = String(localized: "Enter an Instagram handle like @velvet.lj or a link starting with https://.")
                            return
                        }
                        // Spletna stran: samo http(s) povezava (kot splet in backend url_polja.js, #293 / I48); brez sheme dobi https://.
                        if field == .website, SpletnaStranVnos.normaliziraj(editText) == nil {
                            editError = String(localized: "Enter a website link starting with http:// or https://, e.g. https://klub.si.")
                            return
                        }
                        // Podatki prodajalca: dolzina kot v bazi; shrani se samo to polje, brez optimisticnega zapisa
                        // (manager dobi 403 owner_only, vrednost se prevzame sele iz odgovora).
                        if let kljuc = field.kljucProdajalca {
                            let v = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let najvec = field.najvecZnakov, v.count > najvec {
                                editError = String(localized: "That is too long (max \(najvec) characters).")
                                return
                            }
                            activeEdit = nil
                            Task { await saveSeller([kljuc: v]) }
                            return
                        }
                        applyEdit(field)
                        activeEdit = nil
                        Task { await saveClub(changed: field) }
                    }
                    .disabled(field == .genres && allGenres.isEmpty)
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
        case .website: clubWebsite = SpletnaStranVnos.normaliziraj(v) ?? clubWebsite
        case .email: clubEmail = v
        case .description: clubDescription = v
        case .address: clubAddress = v
        case .city: clubCity = v
        case .instagram: clubInstagram = InstagramVnos.normaliziraj(v) ?? clubInstagram
        case .minAge: clubMinAge = editMinAge
        case .genres: clubGenres = allGenres.filter { editGenres.contains($0) }
        case .legalName, .legalAddress, .registrationNumber, .taxNumber: break   // gre prek saveSeller
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
            applySeller(club)
        } catch let api as APIError {
            if case let .requestFailed(code, raw) = api, code == 404, raw.lowercased().contains("club") {
                errorMessage = String(localized: "Your club is not set up yet. Contact luka@outly.si to get it created.")
            } else {
                errorMessage = api.userMessage
            }
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Zaprti seznam zanrov (GET /genres) za urejanje; ob napaki ostane prazen in Save je onemogocen.
    private func loadGenres() async {
        guard allGenres.isEmpty else { return }
        genresFailed = false
        if let list = try? await APIClient.shared.fetchGenres() { allGenres = list } else { genresFailed = true }
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
        clubIsOrganizer = club.isOrganizer
        clubLogoUrl = club.logoUrl
        clubInstagram = club.instagram
        clubMinAge = club.minAge
        clubGenres = club.genres
        clubBarPrices = club.barPrices
        clubGalleryUrls = club.galleryUrls
        clubVideoUrl = club.videoUrl
    }

    /// Podatki prodajalca iz GET /business/clubs/me. Namenoma loceno od `apply`: odgovor drugih PATCH-ov teh polj morda ne vsebuje
    /// in bi jih pobrisal s zaslona.
    private func applySeller(_ club: APIClub) {
        clubLegalName = club.legalName
        clubLegalAddress = club.legalAddress
        clubRegistrationNumber = club.registrationNumber
        clubTaxNumber = club.taxNumber
        clubVatPayer = club.vatPayer
        clubSellerComplete = club.sellerComplete
    }

    /// Stikalo "I organize events without my own venue": optimisticen preklop, ob napaki nazaj.
    private func saveOrganizer(_ nov: Bool) async {
        guard !authToken.isEmpty, nov != clubIsOrganizer else { return }
        errorMessage = nil
        let prej = clubIsOrganizer
        clubIsOrganizer = nov
        do {
            let club = try await APIClient.shared.setMyClubOrganizer(token: authToken, isOrganizer: nov)
            apply(club)
        } catch {
            clubIsOrganizer = prej
            errorMessage = error.userMessage
        }
    }

    /// Slideshow in video se shranita posebej (samo ti dve polji), da ne prepiseta drugega.
    private func saveGalleryAndVideo() async {
        guard !authToken.isEmpty else { return }
        errorMessage = nil
        do {
            let club = try await APIClient.shared.updateMyBusinessClub(
                token: authToken,
                fields: ["gallery_urls": clubGalleryUrls, "video_url": clubVideoUrl]
            )
            apply(club)
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Podatki prodajalca (PATCH /business/clubs/me samo s podanimi polji; backend#94). Sme samo lastnik: manager dobi
    /// 403 `owner_only` -> sporocilo prek `userMessage`. Stanje se ne zapise optimisticno: po uspehu ga ponovno preberemo
    /// (GET /business/clubs/me ima surova polja in `seller_complete`).
    private func saveSeller(_ fields: [String: Any]) async {
        guard !authToken.isEmpty else { return }
        errorMessage = nil
        do {
            _ = try await APIClient.shared.updateMyBusinessClub(token: authToken, fields: fields)
            let club = try await APIClient.shared.fetchMyBusinessClub(token: authToken)
            applySeller(club)
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Izbrane slike ZAMENJAJO slideshow (najvec 3).
    private func uploadGallery(_ items: [PhotosPickerItem]) async {
        guard !authToken.isEmpty else { return }
        await MainActor.run { isUploadingGallery = true; errorMessage = nil }
        defer { Task { @MainActor in isUploadingGallery = false } }
        do {
            var urls: [String] = []
            for item in items.prefix(3) {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let sig = try await APIClient.shared.fetchCloudinarySignature(token: authToken)
                let url = try await APIClient.shared.uploadImageToCloudinary(imageData: data, fileName: "club_gallery.jpg", signature: sig)
                urls.append(url)
            }
            guard !urls.isEmpty else { return }
            await MainActor.run { clubGalleryUrls = urls }
            await saveGalleryAndVideo()
        } catch {
            await MainActor.run { errorMessage = String(localized: "Photo upload failed. \(error.userMessage)") }
        }
    }

    private func uploadVideo(_ item: PhotosPickerItem) async {
        guard !authToken.isEmpty else { return }
        await MainActor.run { isUploadingVideo = true; errorMessage = nil }
        defer { Task { @MainActor in isUploadingVideo = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "ClubInfo", code: 5, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to read the selected video.")])
            }
            // Cloudinary (brezplacni paket) sprejme videe do 100 MB.
            if data.count > 100 * 1024 * 1024 {
                throw NSError(domain: "ClubInfo", code: 6, userInfo: [NSLocalizedDescriptionKey: String(localized: "The video is larger than 100 MB. Please pick a shorter one.")])
            }
            let sig = try await APIClient.shared.fetchCloudinarySignature(token: authToken)
            let url = try await APIClient.shared.uploadVideoToCloudinary(videoData: data, fileName: "club_video.mp4", signature: sig)
            await MainActor.run { clubVideoUrl = url }
            await saveGalleryAndVideo()
        } catch {
            await MainActor.run { errorMessage = String(localized: "Video upload failed. \(error.userMessage)") }
        }
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
        ]
        // Samo polje, ki ga je uporabnik pravkar uredil (glej opombo pri clubInstagram).
        // Instagram: stolpec je NOT NULL, zato prazen niz, ne null.
        if field == .instagram { fields["instagram"] = clubInstagram }
        if field == .minAge { fields["min_age"] = clubMinAge }
        if field == .genres { fields["genres"] = clubGenres }
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
                throw NSError(domain: "ClubInfo", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to read selected image data.")])
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
            await MainActor.run { errorMessage = String(localized: "Logo upload failed. \(error.userMessage)") }
        }
    }
}

/// Vnos spletne strani kluba (outly-backend#293, url_polja.js, I48): backend sprejme samo absoluten http(s) URL z imenom gostitelja
/// (brez uporabnika/gesla, presledkov, kontrolnih znakov in `\`), vnos brez sheme dopolni z https:// (gostitelj mora imeti piko),
/// `-` in prazno brisata. Aplikacija isto preveri PRED shranjevanjem (kot splet: povezava samo http(s)), da lastnik ne dobi 400
/// in da se ob napaki ne shrani nic drugega. Najvec 200 znakov kot na spletu (backend dovoli 2048).
enum SpletnaStranVnos {
    static let najvecZnakov = 200

    /// "" (prazno ali "-" = odstrani), sicer http(s) povezava (brez sheme dobi https://); nil, ce vnos ni veljaven.
    static func normaliziraj(_ vnos: String) -> String? {
        let t = vnos.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "-" { return "" }
        guard t.count <= najvecZnakov else { return nil }
        // Presledki, kontrolni znaki in »\« (WHATWG in RFC razclenjevalnik se pri »https://dobra.si\@zla.si« razideta).
        if t.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) || $0 == "\\" }) {
            return nil
        }
        let maShemo = t.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil
        let gostiteljZVrati = t.range(of: "^[^/:?#]+:[0-9]+([/?#]|$)", options: .regularExpression) != nil
        var url = t
        var dodana = false
        if (!maShemo || gostiteljZVrati) && !t.hasPrefix("/") {
            url = "https://" + t
            dodana = true
        }
        guard url.range(of: "^https?://[^/?#]", options: [.regularExpression, .caseInsensitive]) != nil,
              let c = URLComponents(string: url),
              let shema = c.scheme?.lowercased(), shema == "http" || shema == "https",
              let gostitelj = c.host, !gostitelj.isEmpty,
              c.user == nil, c.password == nil else { return nil }
        if dodana && !gostitelj.contains(".") { return nil }
        return url
    }
}

/// Vnos Instagrama kluba. Backend (`PATCH /business/clubs/me`) ga shrani, kot ga dobi: brez trimanja,
/// brez preverbe oblike in brez omejitve dolzine; stolpec `clubs.instagram` je NOT NULL DEFAULT ''.
/// Spletna aplikacija razume "@ime", "ime" in povezavo https://..., zato aplikacija sama poenoti vnos
/// v "@ime" ali https povezavo in zavrne ostalo.
enum InstagramVnos {
    /// "" (prazno = odstrani), "@ime" ali "https://..." — nil, ce vnos ni veljaven.
    static func normaliziraj(_ vnos: String) -> String? {
        let t = vnos.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t.lowercased().hasPrefix("https://") {
            return t.count <= 200 && !t.contains(where: { $0.isWhitespace }) ? t : nil
        }
        let ime = t.hasPrefix("@") ? String(t.dropFirst()) : t
        let veljavno = !ime.isEmpty && ime.count <= 30
            && ime.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }
        return veljavno ? "@" + ime : nil
    }
}
