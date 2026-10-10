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

    /// Organizator brez lastnega prizorisca (backend 037): brez naslova, zemljevida in pina;
    /// namesto "Club" pisemo "Organizer".
    private var jeOrganizator: Bool { club?.isOrganizer == true }

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
        // Report v meniju »…« (outly-backend #189, Apple 1.2); ne za klub, v katerem sam delam.
        .prijavaMeni(targetType: .club, targetId: clubId, targetName: club?.name ?? "", skrij: jeMojKlub)
        .task { await load() }
        // Stevec ogledov za nadzorno plosco kluba (Martin, 25. 9. 2026): enkrat na prikaz, brez zetona.
        .task { await APIClient.shared.postView(clubId: clubId) }
    }

    /// Ali sem lastnik ali clan ekipe tega kluba (Me.clubs / Me.clubId).
    private var jeMojKlub: Bool {
        guard let me = session.me else { return false }
        return me.clubId == clubId || me.clubs.contains { $0.clubId == clubId }
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
                        Text(LocalizedStringKey(jeOrganizator ? "Organizer video coming soon" : "Club video coming soon"))
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
                Text(LocalizedStringKey(jeOrganizator ? "About the organizer" : "About the club"))
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
                    ClubGenresLine(genres: genres)
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

        // Organizator: oznaka "Organizer", mesto samo ce ga je vnesel (naslova in drzave nima).
        if jeOrganizator {
            let oznaka = String(localized: "Organizer")
            return city.isEmpty ? oznaka : "\(oznaka) \u{00B7} \(city)"
        }

        if !city.isEmpty && !country.isEmpty { return "\(city), \(country)" }
        if !city.isEmpty { return city }
        if !country.isEmpty { return country }
        return ""
    }

    // MARK: - 5) Map block (brez "Location" naslova)
    @ViewBuilder
    private var mapBlock: some View {
        if !jeOrganizator, let lat = club?.lat, let lng = club?.lng {
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
    // Kartica z vrsticami ikona + vrednost; vsaka vrstica odpre mailto:/tel:/https:. Prazne vrednosti
    // se skrijejo, brez kontaktov razdelka ni.
    @ViewBuilder
    private var contactBlock: some View {
        let vrstice = ClubContact.vrstice(
            email: club?.contactEmail,
            phone: club?.contactPhone,
            instagram: club?.instagram,
            website: club?.website
        )
        if !vrstice.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Contact")
                    .font(.headline)

                VStack(spacing: 0) {
                    ForEach(Array(vrstice.enumerated()), id: \.offset) { i, v in
                        if i > 0 {
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)
                        }
                        ContactLinkRow(vrstica: v)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
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
                    // Gostovan dogodek (hosted): klub je samo prizorisce, kartica kaze organizatorja.
                    EventCardAPI(event: e, clubName: e.hosted ? e.clubName : club?.name, variant: .clubRow)
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
            // Prvi Follow = smiseln trenutek za dovoljenje za potisna obvestila (klub objavi dogodek). Samo ce se ni odlocil.
            if stanje.following { PushObvestila.deljen.predlagajDovoljenje() }
        } catch {
            sledim = !novo
            sledilci = max(0, sledilci + (novo ? -1 : 1))
            errorText = error.userMessage
        }
    }
}

/// Zanri kluba: najvec 4, ostali za "Show more" (Martin, 9. 10. 2026). Besedilo in gumb sta
/// en Text, zato se "Show more" nadaljuje v isti vrstici; dotik razsiri/skrci seznam.
private struct ClubGenresLine: View {
    let genres: [String]
    @State private var razsirjeno = false

    private static let najvec = 4

    private var imaVec: Bool { genres.count > Self.najvec }

    private func zdruzi(_ g: [String]) -> String {
        g.map { $0.capitalized }.joined(separator: " • ")
    }

    var body: some View {
        if imaVec {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { razsirjeno.toggle() }
            } label: {
                (
                    Text(zdruzi(razsirjeno ? genres : Array(genres.prefix(Self.najvec))))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    + Text(razsirjeno ? " " : ", ")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.55))
                    + Text(LocalizedStringKey(razsirjeno ? "Show less" : "Show more"))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.55))
                )
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(zdruzi(genres))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Ena vrstica kontakta: ikona, vrednost in (ce je veljaven) naslov za odpiranje.
private struct ContactEntry {
    let ikona: String
    let vrednost: String
    let url: URL?
}

/// Pretvorba vnesenih kontaktov v varne povezave. Dovoljene so SAMO sheme http, https, mailto in tel;
/// vse drugo (javascript:, file:, ...) vrstico pusti brez povezave.
private enum ClubContact {
    static let dovoljeneSheme: Set<String> = ["http", "https", "mailto", "tel"]

    static func vrstice(email: String?, phone: String?, instagram: String?, website: String?) -> [ContactEntry] {
        var out: [ContactEntry] = []
        if let v = cisto(email) { out.append(ContactEntry(ikona: "envelope", vrednost: v, url: mailto(v))) }
        if let v = cisto(phone) { out.append(ContactEntry(ikona: "phone", vrednost: v, url: tel(v))) }
        if let v = cisto(instagram) { out.append(ContactEntry(ikona: "camera", vrednost: v, url: instagramURL(v))) }
        if let v = cisto(website) { out.append(ContactEntry(ikona: "globe", vrednost: v, url: splet(v))) }
        return out
    }

    /// Obrezana vrednost; prazno in "-" pomenita, da kontakta ni.
    static func cisto(_ s: String?) -> String? {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t == "-") ? nil : t
    }

    static func varen(_ url: URL?) -> URL? {
        guard let url, let sheme = url.scheme?.lowercased(), dovoljeneSheme.contains(sheme) else { return nil }
        return url
    }

    static func mailto(_ email: String) -> URL? {
        guard email.contains("@"), email.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return varen(URL(string: "mailto:" + email))
    }

    static func tel(_ phone: String) -> URL? {
        let stevilka = phone.filter { "+0123456789".contains($0) }
        guard !stevilka.isEmpty else { return nil }
        return varen(URL(string: "tel:" + stevilka))
    }

    static func instagramURL(_ vnos: String) -> URL? {
        let l = vnos.lowercased()
        if l.hasPrefix("http://") || l.hasPrefix("https://") { return spletURL(vnos) }
        if l.hasPrefix("instagram.com/") || l.hasPrefix("www.instagram.com/") { return spletURL("https://" + vnos) }
        var handle = vnos
        if handle.hasPrefix("@") { handle.removeFirst() }
        handle = handle.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let dovoljeno = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        guard !handle.isEmpty, handle.unicodeScalars.allSatisfy({ dovoljeno.contains($0) }) else { return nil }
        return varen(URL(string: "https://instagram.com/" + handle))
    }

    static func splet(_ vnos: String) -> URL? {
        let l = vnos.lowercased()
        if l.hasPrefix("http://") || l.hasPrefix("https://") { return spletURL(vnos) }
        if vnos.contains("://") { return nil }   // druge sheme (javascript, file, ftp ...) ne
        return spletURL("https://" + vnos)
    }

    private static func spletURL(_ s: String) -> URL? {
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return varen(url)
    }
}

private struct ContactLinkRow: View {
    let vrstica: ContactEntry
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = vrstica.url {
            Button {
                openURL(url)
            } label: {
                vsebina(klikljivo: true)
            }
            .buttonStyle(.plain)
        } else {
            vsebina(klikljivo: false)
        }
    }

    private func vsebina(klikljivo: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: vrstica.ikona)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 24)
            Text(vrstica.vrednost)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if klikljivo {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
