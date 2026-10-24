import SwiftUI
import PhotosUI
import CoreLocation

/// Profil LASTNIKA kluba (Luka, 21. 9. 2026; Figma "settings"): racun z vlogo `business` ni
/// namenjen zuranju, ampak klubu. Zato namesto osebnega profila (Tickets, My friends, My Clubs)
/// vidi: logo in ime kluba, moder "Edit your page", nato Dashboard, Events, My team, Settings.
/// Zaposleni (manager, vratar) imajo se naprej OSEBNI profil in svoj klub pod My Clubs —
/// tako je Martin odlocil 20. 9., to tu ostane. Lastnik lahko v Settings preklopi na osebni
/// racun (in nazaj v My Account); izbira je shranjena na napravi (`profilObraz`).
/// Sveze odobren lastnik brez kluba dobi kratek obrazec (ClubSetupView), s katerim klub
/// nastane in je takoj na domacem zaslonu.
/// Lezi v NavigationStacku ProfileView — brez lastnega.
@MainActor
struct OwnerProfileView: View {
    let me: Me

    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"

    @State private var club: APIClub?
    @State private var brezKluba = false
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                if brezKluba {
                    ClubSetupView { nov in
                        club = nov
                        brezKluba = false
                    }
                } else {
                    glava
                    Divider().background(Color.gray)
                    meni
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 20)

                Button {
                    session.logout()
                    authStage = "login"
                } label: {
                    Text("Log out")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                }
                // Spodnji odmik zaradi plavajoce spodnje vrstice (trdo pravilo 6).
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .outlyOzadje()
        .navigationTitle("")
        .task { await load() }
        // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
        .refreshable { await Task { await load() }.value }
    }

    // MARK: - Glava: logo, ime, Edit your page

    private var glava: some View {
        // Iste mere kot osebni profil (ProfileView): slika 60, ime .title2, povezava navaden font.
        HStack(spacing: 25) {
            logo
            VStack(alignment: .leading, spacing: 6) {
                Text(club?.name ?? (isLoading ? String(localized: "Loading...") : String(localized: "Your club")))
                    .font(.title2)
                    .foregroundColor(.white)
                    .lineLimit(2)
                NavigationLink {
                    EditBusinessPageView(clubId: club?.id)
                } label: {
                    Text("Edit your page")
                        .foregroundColor(.outlyBlue)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var logo: some View {
        Group {
            if let s = club?.logoUrl, !s.isEmpty, let u = URL(string: s) {
                OutlyAsyncImage(url: u) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.outlyBlue.opacity(0.2))
                    .overlay(Image(systemName: "building.2").font(.system(size: 20)).foregroundColor(.outlyBlue))
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Meni (isti gradnik kot osebni profil)

    private var meni: some View {
        VStack(spacing: 12) {
            NavigationLink { BusinessDashboardView(clubId: club?.id, clubName: club?.name, clubLogoUrl: club?.logoUrl ?? "") } label: {
                OutlyMenuRowButton(icon: "chart.bar", title: "Dashboard")
            }
            NavigationLink { BusinessEventsView(clubId: club?.id, clubName: club?.name) } label: {
                OutlyMenuRowButton(icon: "calendar", title: "Events")
            }
            NavigationLink { RezervacijeDogodkiView(smeSprostiti: true) } label: {
                OutlyMenuRowButton(icon: "table.furniture", title: "Reservations")
            }
            NavigationLink { TeamView(clubName: club?.name) } label: {
                OutlyMenuRowButton(icon: "person.2", title: "My team")
            }
            NavigationLink { OwnerSettingsView(club: club) } label: {
                OutlyMenuRowButton(icon: "gearshape", title: "Settings")
            }
        }
    }

    // MARK: - Podatki

    private func load() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        do {
            club = try await APIClient.shared.fetchMyBusinessClub(token: session.token)
            brezKluba = false
        } catch let api as APIError {
            // 404 = lastnik se nima kluba (sveze odobren) -> obrazec. Drugo je napaka.
            if case let .requestFailed(code, _) = api, code == 404 || code == 403 {
                brezKluba = true
            } else {
                errorText = api.userMessage
            }
        } catch {
            errorText = error.userMessage
        }
    }
}

// MARK: - Settings lastnika (Figma "settings")

/// Club info, Password and security, Switch to personal account. "Withdraw" iz Figme NI tu:
/// Stripe racuna se ni (issue #16) in po DECISIONS se denarnica/$ ne gradi; izplacila bodo
/// prek Stripove strani, gumb pride takrat.
@MainActor
struct OwnerSettingsView: View {
    let club: APIClub?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("profilObraz") private var obraz: String = "club"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                VStack(spacing: 12) {
                    NavigationLink { ClubInfoView(clubId: club?.id) } label: {
                        OutlyMenuRowButton(icon: "person", title: "Club info")
                    }
                    NavigationLink { PasswordSecurityView() } label: {
                        OutlyMenuRowButton(icon: "lock", title: "Password and security")
                    }
                    Button {
                        // Nazaj na koren, potem preklop: ProfileView zamenja obraz.
                        dismiss()
                        obraz = "personal"
                    } label: {
                        OutlyMenuRowButton(icon: "arrow.left.arrow.right", title: "Switch to personal account")
                    }
                    .buttonStyle(.plain)
                }

                Text("Your personal account has tickets, friends and preferences. You can switch back any time in My Account.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Prvi klub (sveze odobren lastnik)

/// Najmanj, kar klub rabi, da je na domacem zaslonu in zemljevidu: ime, logo, naslov in mesto
/// (koordinate izracuna naprava, CLGeocoder), zanri, starostna meja. POST /clubs. Vse ostalo
/// (opis, pasica, galerija, cenik, kontakti) lastnik doda pozneje prek Edit your page / Club info.
@MainActor
struct ClubSetupView: View {
    /// Poklice se z ustvarjenim klubom.
    var onCreated: (APIClub) -> Void

    @EnvironmentObject private var session: SessionStore

    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    /// "I organize events without my own venue" (backend 037): brez naslova, mesto neobvezno.
    @State private var isOrganizer = false
    @State private var minAge = 18
    @State private var genres: [String] = []
    @State private var selectedGenres: Set<String> = []
    @State private var isLoadingGenres = false

    @State private var logoUrl = ""
    @State private var pickedLogo: PhotosPickerItem?
    @State private var isUploadingLogo = false

    @State private var isSaving = false
    @State private var errorText: String?

    private let starosti = [0, 16, 18, 21]

    private var lahkoShrani: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (isOrganizer || !city.trimmingCharacters(in: .whitespaces).isEmpty)
            && !isSaving && !isUploadingLogo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your club")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text("Just the basics to put your club on Outly. You can add photos, prices and more later.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Logo
            HStack(spacing: 16) {
                PhotosPicker(selection: $pickedLogo, matching: .images) {
                    ZStack {
                        if !logoUrl.isEmpty, let u = URL(string: logoUrl) {
                            OutlyAsyncImage(url: u) { img in
                                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                            } placeholder: {
                                Rectangle().fill(Color.white.opacity(0.1))
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white.opacity(0.08))
                                .overlay(Image(systemName: "camera").font(.system(size: 22)).foregroundColor(.white.opacity(0.7)))
                        }
                        if isUploadingLogo {
                            Color.black.opacity(0.4)
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(isUploadingLogo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Club logo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Square image works best. Optional.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }

            polje(isOrganizer ? "Organizer name" : "Club name", text: $name,
                  placeholder: isOrganizer ? "e.g. Night Events" : "e.g. Klub K4")

            // Promotor ali podjetje brez lastnega prizorisca: stran kot klub, a brez naslova in pina;
            // vsak dogodek pove, kje poteka.
            OutlyToggleDetailRow(icon: "megaphone",
                                 title: "I organize events without my own venue",
                                 subtitle: "No address or map pin. You choose the venue for each event.",
                                 isOn: $isOrganizer)

            if !isOrganizer {
                polje("Address", text: $address, placeholder: "Street and number")
            }
            polje(isOrganizer ? "City (optional)" : "City", text: $city, placeholder: "e.g. Ljubljana")

            VStack(alignment: .leading, spacing: 8) {
                Text("Minimum age")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    ForEach(starosti, id: \.self) { a in
                        Button { minAge = a } label: {
                            Text(a == 0 ? String(localized: "All ages") : "\(a)+")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Capsule().fill(minAge == a ? Color.outlyBlue : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Music genres")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if isLoadingGenres {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }.frame(height: 56)
                } else if genres.isEmpty {
                    Button { Task { await loadGenres() } } label: {
                        OutlyMenuRowButton(icon: "exclamationmark.triangle", title: "Could not load genres.",
                                           value: String(localized: "Try again"))
                    }
                    .buttonStyle(.plain)
                } else {
                    OutlyGenreGrid(genres: genres, selected: $selectedGenres)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }

            OutlyPrimaryButton(title: "Create club", isLoading: isSaving) { Task { await save() } }
                .disabled(!lahkoShrani)
                .opacity(lahkoShrani ? 1 : 0.5)
        }
        .task { await loadGenres() }
        .onChange(of: pickedLogo) { _, nov in
            if let nov { Task { await uploadLogo(nov) } }
        }
    }

    private func polje(_ naslov: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(naslov))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            TextField(LocalizedStringKey(placeholder), text: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .tint(.outlyBlue)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
        }
    }

    private func loadGenres() async {
        isLoadingGenres = true
        defer { isLoadingGenres = false }
        genres = (try? await APIClient.shared.fetchGenres()) ?? []
    }

    private func uploadLogo(_ item: PhotosPickerItem) async {
        guard session.isLoggedIn else { return }
        isUploadingLogo = true
        defer { isUploadingLogo = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let sig = try await APIClient.shared.fetchCloudinarySignature(token: session.token)
            logoUrl = try await APIClient.shared.uploadImageToCloudinary(imageData: data, fileName: "logo.jpg", signature: sig)
        } catch {
            errorText = error.userMessage
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        var lat: Double?
        var lng: Double?
        let naslov = [isOrganizer ? "" : address, city].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !isOrganizer, !naslov.isEmpty, let loc = try? await CLGeocoder().geocodeAddressString(naslov).first?.location {
            lat = loc.coordinate.latitude
            lng = loc.coordinate.longitude
        }
        var fields: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "logoUrl": logoUrl,
            "address": isOrganizer ? "" : address.trimmingCharacters(in: .whitespaces),
            "city": city.trimmingCharacters(in: .whitespaces),
            "minAge": minAge,
            "genres": Array(selectedGenres).sorted(),
        ]
        if let lat, let lng { fields["lat"] = lat; fields["lng"] = lng }
        if isOrganizer { fields["isOrganizer"] = true }
        do {
            let klub = try await APIClient.shared.createClub(token: session.token, fields: fields)
            _ = await session.refreshMe()
            onCreated(klub)
        } catch {
            errorText = error.userMessage
        }
    }
}
