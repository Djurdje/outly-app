import SwiftUI
import MapKit

struct ClubDetailView: View {
    let clubId: Int

    @EnvironmentObject private var session: SessionStore

    @State private var club: APIClub?
    @State private var popular: [APIEvent] = []
    @State private var comingSoon: [APIEvent] = []
    @State private var isLoading = false
    @State private var errorText: String?

    // Sledenje klubu (backend migracija 019). Lajkanja kluba ni — srcek je samo na dogodkih.
    @State private var sledim = false
    @State private var sledilci = 0
    @State private var sledenjeTece = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Vrstni red po Lukovih navodilih (14. 9. 2026), dopolnjen 22. 9.:
                // 1) Slideshow (do 3 slike) + ime kluba, stevilo sledilcev in gumb Follow cez sliko.
                //    Pasice (banner_url) tu NI: stran kluba kaze samo slideshow (DECISIONS 22. 9.).
                header

                // 2) Logo, mesto, zanri, min age — takoj pod slideshowom
                infoBlock

                if isLoading {
                    ProgressView().padding(.horizontal, 16)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).padding(.horizontal, 16)
                }

                // 3) Popular: najvec TRIJE koncani dogodki (streznik jih omeji). Navadne kartice —
                //    posnetek dogodka se predvaja SAMO na zaslonu koncanega dogodka (Martin, 22. 9.),
                //    tu bi trije predvajalniki zasedli cel zaslon in zasencili prihajajoce dogodke.
                eventsSection(title: String(localized: "Popular"), events: popular)

                // 4) Predstavitveni video (na mestu, kjer je bil prej opis)
                videoBlock

                // 5) Coming Soon
                eventsSection(title: String(localized: "Coming Soon"), events: comingSoon)

                // 6) Mapa + naslov
                mapBlock

                // 7) Kontakti
                contactBlock

                // 8) Opis kluba cisto na koncu
                descriptionBlock

                // da se ne odreže pod tab bar
                Spacer(minLength: 0)
            }
            .padding(.bottom, 90)
        }
        .navigationTitle("")
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
        // Stevec ogledov za nadzorno plosco kluba (Martin, 25. 9. 2026): enkrat na prikaz, brez zetona.
        .task { await APIClient.shared.postView(clubId: clubId) }
    }

    // MARK: - 1) Header: slideshow do treh slik in ime kluba
    // Slike so povsod ovite v Color.clear.overlay(...).clipped() (past 12).
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            ClubSlideshow(urls: club?.slideshowUrls ?? [])

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Samo ime kluba. Stevilo sledilcev je od 22. 9. (Martin) v vrstici z logom,
            // poravnano na desno — cez sliko je bilo tesno ob imenu in slabo berljivo.
            Text(club?.name ?? String(localized: "Club"))
                .font(.system(size: 40, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .allowsHitTesting(false)
        }
        .frame(height: 260)
        .clipped()
    }

    /// "1.2k followers" — desno v vrstici z logom. `fixedSize` prepreci, da bi se besedilo
    /// prelomilo, ko ima klub dolgo ime mesta ali veliko zanrov.
    private var followersLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(Self.kratkoStevilo(sledilci))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("followers")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    @ViewBuilder
    private var followButton: some View {
        if session.isLoggedIn {
            Button {
                Task { await preklopiSledenje() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sledim ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text(sledim ? String(localized: "Following") : String(localized: "Follow"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(sledim ? Color.white.opacity(0.9) : Color.white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    Capsule().fill(sledim ? Color.white.opacity(0.08) : Color.outlyBlue)
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(sledim ? 0.35 : 0), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sledenjeTece)
            .opacity(sledenjeTece ? 0.6 : 1)
            .accessibilityLabel(Text(sledim ? String(localized: "Following") : String(localized: "Follow")))
            // Sij samo dokler se ne sledi - potem, ko uporabnik ze sledi, gumb ni vec CTA.
            .outlySij(moc: 1.0, aktiven: !sledim)
        }
    }

    /// 0–999 kot je, potem 1.2k. Da se dolgo stevilo ne zaleti v ime kluba.
    private static func kratkoStevilo(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        let tisoc = Double(n) / 1000
        return String(format: n < 10_000 ? "%.1fk" : "%.0fk", tisoc)
    }

    // MARK: - 4) Predstavitveni video kluba (iste sirine kot vsebina, visina kot prejsnji opis)
    @ViewBuilder
    private var videoBlock: some View {
        if let v = club?.videoUrl, !v.isEmpty, let url = URL(string: v) {
            OutlyLoopingVideo(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .padding(.horizontal, 16)
        } else if club != nil {
            // Okvir je na mestu tudi brez videa, da klub vidi, kam sodi (Luka: "okvir za video").
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Club video coming soon")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                )
                .frame(height: 230)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - 8) Opis kluba (pod mapo in kontakti)
    @ViewBuilder
    private var descriptionBlock: some View {
        if let d = club?.description.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Loceno besedilo od "About" v profilu (drug kljuc, da prevod ne trci s Settings > About).
                Text("About the club")
                    .font(.headline)
                Text(d)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - 2) Info block (logo + mesto/država/žanri/min age)
    private var infoBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            if let logo = club?.logoUrl, !logo.isEmpty, let url = URL(string: logo) {
                OutlyAsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Circle().opacity(0.12)
                }
                .frame(width: 62, height: 62)
                .clipShape(Circle())
            } else {
                Circle().opacity(0.12)
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: "building.2").foregroundStyle(.white.opacity(0.6)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(cityCountryText)
                    .foregroundStyle(.secondary)

                if let genres = club?.genres, !genres.isEmpty {
                    Text(genres.map { $0.capitalized }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let minAge = club?.minAge {
                    Text("Min age: \(minAge)+")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            // Desno v vrstici z logom: stevilo sledilcev, pod njim gumb Follow (Martin, 22. 9.;
            // gumb je bil prej na slideshowu).
            VStack(alignment: .trailing, spacing: 10) {
                followersLabel
                followButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var cityCountryText: String {
        let city = (club?.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let country = (club?.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !city.isEmpty && !country.isEmpty { return "\(city), \(country)" }
        if !city.isEmpty { return city }
        if !country.isEmpty { return country }
        return ""
    }

    // MARK: - 5) Map block (brez "Location" naslova)
    @ViewBuilder
    private var mapBlock: some View {
        if let lat = club?.lat, let lng = club?.lng {
            // Staticen; klik -> Apple Maps / Google Maps z navodili za pot
            StaticnaKarta(lat: lat, lng: lng)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
                .padding(.top, 6)

            // naslov/adresa pod mapo (brez "Location" headerja)
            if let address = club?.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }


    // MARK: - 6) Contact block
    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contact")
                .font(.headline)

            ContactRow(label: String(localized: "Email"), value: club?.contactEmail)
            ContactRow(label: String(localized: "Phone"), value: club?.contactPhone)
            ContactRow(label: String(localized: "Instagram"), value: club?.instagram)
            ContactRow(label: String(localized: "Website"), value: club?.website)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Events section
    @ViewBuilder
    private func eventsSection(title: String, events: [APIEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())

            if events.isEmpty && !isLoading && errorText == nil {
                Text("No events.")
                    .foregroundStyle(.secondary)
            }

            ForEach(events, id: \.id) { e in
                NavigationLink {
                    EventDetailView(event: e)
                } label: {
                    EventCardAPI(event: e, clubName: club?.name, variant: .clubRow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Load
    private func load() async {
        isLoading = true
        errorText = nil
        do {
            // Zeton posljemo, da odgovor vsebuje is_following (stanje gumba Follow).
            async let c = APIClient.shared.fetchClub(id: clubId, token: session.token.isEmpty ? nil : session.token)
            // "Popular" = najvec 3 koncani dogodki kluba po prodanih vstopnicah (backend 019).
            // Prej je bil to ?upcoming=false z oknom 7 dni — posnetek dogodka bi izginil cez teden.
            async let pop = APIClient.shared.fetchPopularEvents(clubId: clubId)
            async let up = APIClient.shared.fetchEvents(clubId: clubId, upcoming: true)

            let klub = try await c
            club = klub
            sledim = klub.isFollowing
            sledilci = klub.followersCount
            popular = try await pop
            comingSoon = try await up
        } catch {
            errorText = error.userMessage
        }
        isLoading = false
    }

    /// Optimisticen preklop: gumb se spremeni takoj, ob napaki se vrne nazaj.
    private func preklopiSledenje() async {
        guard session.isLoggedIn, !sledenjeTece else { return }
        let novo = !sledim
        sledim = novo
        sledilci = max(0, sledilci + (novo ? 1 : -1))
        sledenjeTece = true
        defer { sledenjeTece = false }
        do {
            let stanje = try await APIClient.shared.setFollowClub(token: session.token, clubId: clubId, follow: novo)
            sledim = stanje.following
            sledilci = stanje.followersCount
        } catch {
            sledim = !novo
            sledilci = max(0, sledilci + (novo ? -1 : 1))
            errorText = error.userMessage
        }
    }
}

private struct ContactRow: View {
    let label: String
    let value: String?

    var body: some View {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            Text("\(label):")
                .foregroundStyle(.secondary)
            Spacer()
            Text(v.isEmpty ? "-" : v)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Slideshow (do 3 slike, samodejno menjavanje, pike spodaj). Od 28. 9. 2026 (Martin)
// se majhna gumba levo/desno za rocno premikanje; rocni premik ponovno zazene 4-s stevec.
private struct ClubSlideshow: View {
    let urls: [String]
    @State private var index = 0
    @State private var rocniPremik = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                Rectangle().opacity(0.12)
            } else if urls.count == 1 {
                slika(urls[0])
            } else {
                TabView(selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                        slika(u).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .overlay {
                    HStack {
                        puscica("chevron.left", smer: -1)
                        Spacer()
                        puscica("chevron.right", smer: 1)
                    }
                    .padding(.horizontal, 10)
                }
                // Samodejno menjavanje na 4 s. .task se ob izginotju pogleda preklice sam;
                // stabilnejse kot Timer.publish v stored property (ta se ob vsakem izrisu starsa ponastavi).
                .task(id: "\(urls.count)-\(rocniPremik)") {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if Task.isCancelled { break }
                        withAnimation(.easeInOut(duration: 0.6)) {
                            index = (index + 1) % max(urls.count, 1)
                        }
                    }
                }
            }
        }
    }

    /// Majhen okrogel gumb (28 pt) s tanko belo obrobo; kroži (za zadnjo sliko pride prva).
    private func puscica(_ ikona: String, smer: Int) -> some View {
        Button {
            let n = max(urls.count, 1)
            withAnimation(.easeInOut(duration: 0.35)) { index = (index + smer + n) % n }
            rocniPremik += 1
        } label: {
            Image(systemName: ikona)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(smer < 0 ? LocalizedStringKey("Previous photo") : LocalizedStringKey("Next photo")))
    }

    private func slika(_ u: String) -> some View {
        Group {
            if let url = URL(string: u) {
                OutlyAsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().opacity(0.15)
                }
            } else {
                Rectangle().opacity(0.12)
            }
        }
    }
}
