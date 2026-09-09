import SwiftUI
import CoreLocation

/// Domaci zaslon po Figmi ("homescreen", 20:2): avatar levo, logo na sredini,
/// "Where to?", Suggestions, Tonight/This week, Last week's biggest hits, In your area,
/// Big events coming up, This weekend, Discover your genre. Vsi seznami so iz zivih
/// podatkov (GET /clubs, GET /events, GET /genres). Priporocila se premesajo ENKRAT
/// ob nalaganju — prej so se ob vsakem izrisu, zato so kartice pod prstom skakale.
@MainActor
struct HomeView: View {
    /// Preklop zavihka (MainTabView): "Where to?" -> iskanje, avatar -> profil.
    var odpriIskanje: () -> Void = {}
    var odpriProfil: () -> Void = {}
    @State private var genres: [String] = []

    @State private var clubs: [APIClub] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var me: Me?

    @State private var upcomingEvents: [APIEvent] = []
    @State private var popularEvents: [APIEvent] = []
    @State private var clubsById: [Int: APIClub] = [:]
    @State private var suggestedOrder: [Int] = []

    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }

    @EnvironmentObject private var prefs: UserPreferences
    @EnvironmentObject private var locationManager: LocationManager

    private var userAge: Int? { session.me?.age }
    private var userGenres: [String] { session.me?.genres ?? [] }

    // MARK: - Izpeljani seznami

    private func distanceKm(to club: APIClub) -> Double? {
        guard let userLoc = locationManager.location, let lat = club.lat, let lng = club.lng else { return nil }
        return userLoc.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1000.0
    }

    private var filteredClubs: [APIClub] {
        clubs.filter { club in
            if let age = userAge, club.minAge > age { return false }
            if !userGenres.isEmpty {
                let selected = Set(userGenres.map { $0.lowercased() })
                let clubSet = Set(club.genres.map { $0.lowercased() })
                if !clubSet.isEmpty && selected.isDisjoint(with: clubSet) { return false }
            }
            if let d = distanceKm(to: club), d > prefs.maxDistanceKm { return false }
            return true
        }
    }

    private var suggestedClubs: [APIClub] {
        let ids = suggestedOrder.isEmpty ? filteredClubs.map(\.id) : suggestedOrder
        let dovoljeni = Set(filteredClubs.map(\.id))
        return ids.compactMap { clubsById[$0] }.filter { dovoljeni.contains($0.id) }.prefix(8).map { $0 }
    }

    private var nearbyClubs: [APIClub] {
        guard locationManager.location != nil else { return [] }
        return clubs.filter { distanceKm(to: $0) != nil }
            .sorted { (distanceKm(to: $0) ?? 1e9) < (distanceKm(to: $1) ?? 1e9) }
            .prefix(10).map { $0 }
    }

    private var nearbyDistances: [Int: Double] {
        var d: [Int: Double] = [:]
        for c in nearbyClubs { if let km = distanceKm(to: c) { d[c.id] = km } }
        return d
    }

    private var sortedUpcoming: [APIEvent] {
        upcomingEvents.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var tonight: [APIEvent] { sortedUpcoming.filter { $0.isToday } }

    private var thisWeek: [APIEvent] {
        sortedUpcoming.filter { ($0.startDate ?? .distantFuture).timeIntervalSinceNow < 7 * 24 * 3600 }
    }

    private var weekend: [APIEvent] { sortedUpcoming.filter { $0.isThisWeekend } }

    private var trending: [APIEvent] {
        upcomingEvents.filter { $0.soldCount > 0 || $0.isSoldOut }
            .sorted { ($0.soldCount, $0.startDate ?? .distantFuture) > ($1.soldCount, $1.startDate ?? .distantFuture) }
            .prefix(8).map { $0 }
    }

    /// Najvecji prihajajoci dogodek: po zmogljivosti, nato po prodanih, nato najblizji.
    private var bigComingUp: APIEvent? {
        // Kljuc razbit na korake, da tipni preverjevalnik ne obupa (tuple + vec ??).
        func kljuc(_ e: APIEvent) -> (Int, Int, Double) {
            let zmogljivost: Int = e.capacity ?? 0
            let cez: Double = e.startDate?.timeIntervalSinceNow ?? 0
            return (zmogljivost, e.soldCount, -cez)
        }
        return sortedUpcoming.max { kljuc($0) < kljuc($1) }
    }

    /// Hit tedna: pretekli dogodek z najvec prodanimi; ce ga ni, najbolje prodajan prihajajoci.
    private var hitTedna: (event: APIEvent, label: String)? {
        if let p = popularEvents.filter({ $0.soldCount > 0 }).max(by: { $0.soldCount < $1.soldCount }) {
            return (p, "Last week's biggest hit")
        }
        if let t = trending.first { return (t, "Trending right now") }
        return nil
    }

    /// "In your area": po razdalji, ce imamo lokacijo; sicer vsi klubi (da razdelek ni prazen).
    private var areaClubs: [APIClub] {
        nearbyClubs.isEmpty ? Array(clubs.prefix(10)) : nearbyClubs
    }

    /// Zanri z dogodki: najprej uporabnikovi, potem ostali; plakat = prvi dogodek zanra.
    private var genreRows: [(genre: String, poster: String, count: Int)] {
        let vsi = genres.isEmpty ? Array(Set(upcomingEvents.flatMap { $0.genres.map { $0.lowercased() } })).sorted() : genres
        let moji = Set(userGenres.map { $0.lowercased() })
        let urejeni = vsi.sorted { a, b in
            let ma = moji.contains(a.lowercased()), mb = moji.contains(b.lowercased())
            return ma != mb ? ma : a < b
        }
        return urejeni.map { g in
            let evs = sortedUpcoming.filter { $0.genres.contains { $0.caseInsensitiveCompare(g) == .orderedSame } }
            return (g, evs.first?.posterUrl ?? "", evs.count)
        }
    }

    private func eventsForGenre(_ g: String) -> [APIEvent] {
        sortedUpcoming.filter { $0.genres.contains { $0.caseInsensitiveCompare(g) == .orderedSame } }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let pozdrav = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        if let name = me?.username, !name.isEmpty { return "\(pozdrav), \(name)" }
        return pozdrav
    }

    private var todayLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {

                    header

                    Button(action: odpriIskanje) { WhereToField() }
                        .buttonStyle(.plain)

                    if let errorText {
                        VStack(spacing: 8) {
                            Text(errorText).foregroundStyle(.red).font(.subheadline)
                            Button("Try again") { Task { await loadAll() } }.foregroundStyle(Color.outlyBlue)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if isLoading && upcomingEvents.isEmpty && clubs.isEmpty {
                        skeleton
                    } else {
                        // 1. Suggestions (Figma 37:139) — siroke pasice klubov po zanrih
                        if !suggestedClubs.isEmpty {
                            sekcija("Suggestions", podnaslov: userGenres.isEmpty ? "Popular clubs" : "Based on your genres") {
                                HorizontalClubsScrollAPI(clubs: suggestedClubs, variant: .suggestion)
                            }
                        }

                        // 2. Tonight / This week — plakati (to je razlog, da nekdo odpre aplikacijo)
                        if !tonight.isEmpty {
                            sekcija("Tonight", podnaslov: "Doors open soon") {
                                HorizontalEventsScroll(events: tonight, clubsById: clubsById)
                            }
                        } else if !thisWeek.isEmpty {
                            sekcija("This week", podnaslov: "Next seven days") {
                                HorizontalEventsScroll(events: thisWeek, clubsById: clubsById)
                            }
                        }

                        // 3. Last week's biggest hits (Figma 50:100)
                        if let hit = hitTedna {
                            sekcija("Last week's biggest hits", podnaslov: nil) {
                                NavigationLink { EventDetailView(event: hit.event) } label: {
                                    HitCard(event: hit.event, club: clubsById[hit.event.clubId], label: hit.label)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // 4. In your area (Figma 50:86) — kvadratni logotipi
                        if !areaClubs.isEmpty {
                            sekcija("In your area", podnaslov: nearbyClubs.isEmpty ? "Clubs on Outly" : "Closest clubs first") {
                                HorizontalClubsScrollAPI(clubs: areaClubs, variant: .area, distances: nearbyDistances)
                            }
                        }

                        // 5. Big events coming up (Figma 51:111) — velik plakat
                        if let e = bigComingUp {
                            sekcija("Big events coming up", podnaslov: nil) {
                                NavigationLink { EventDetailView(event: e) } label: {
                                    HeroEventCard(event: e, club: clubsById[e.clubId])
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // 6. This weekend / Trending — plakati
                        if !weekend.isEmpty {
                            sekcija("This weekend", podnaslov: "Friday to Sunday") {
                                HorizontalEventsScroll(events: weekend, clubsById: clubsById)
                            }
                        } else if !trending.isEmpty {
                            sekcija("Trending now", podnaslov: "Selling fastest on Outly") {
                                HorizontalEventsScroll(events: trending, clubsById: clubsById)
                            }
                        }

                        // 7. Discover your genre (Figma 838:1638) — vrstice zanrov
                        if !genreRows.isEmpty {
                            sekcija("Discover your genre", podnaslov: nil) {
                                VStack(spacing: 10) {
                                    ForEach(genreRows, id: \.genre) { g in
                                        NavigationLink {
                                            GenreEventsView(genre: g.genre, events: eventsForGenre(g.genre), clubsById: clubsById)
                                        } label: {
                                            GenreRow(genre: g.genre, posterUrl: g.poster, count: g.count)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if upcomingEvents.isEmpty && clubs.isEmpty && !isLoading && errorText == nil {
                            VStack(spacing: 10) {
                                Image(systemName: "moon.stars").font(.system(size: 36)).foregroundStyle(Color.outlyBlue)
                                Text("Nothing on yet").font(.headline).foregroundStyle(.white)
                                Text("Clubs and events will show up here.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }

                        NavigationLink {
                            EventView()
                        } label: {
                            Text("See all events")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding()
                .padding(.bottom, 40)
            }
            .navigationTitle("")
            .refreshable { await loadAll() }
        }
        .preferredColorScheme(.dark)
        .task {
            locationManager.requestPermission()
            await loadAll()
        }
        .onAppear {
            Task { await loadMe() }
        }
    }

    // MARK: - Deli

    /// Figma 239:804: avatar levo, logo Outly na sredini. Pozdrav je pod logom, majhen.
    private var header: some View {
        VStack(spacing: 2) {
            ZStack {
                // Sredstvo "logo" je 800x800 z napisom na sredini (~31 % visine),
                // zato ga narisemo vecjega in odrezemo na visino vrstice.
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .frame(height: 44)
                    .clipped()

                HStack {
                    Button(action: odpriProfil) {
                        OutlyAvatarView(avatarUrlString: me?.avatarUrl, size: 36)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            Text(greeting)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    private func sekcija<Content: View>(_ naslov: String, podnaslov: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: naslov)
                if let podnaslov {
                    Text(podnaslov)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            content()
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock().frame(width: 120, height: 18).clipShape(Capsule())
                SkeletonRow()
            }
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock().frame(width: 160, height: 18).clipShape(Capsule())
                SkeletonRow(width: 110, height: 110, count: 3)
            }
        }
    }

    // MARK: - Nalaganje

    private func loadAll() async {
        isLoading = true
        errorText = nil
        do {
            async let c = APIClient.shared.fetchClubs()
            async let up = APIClient.shared.fetchEvents(upcoming: true)
            async let pop = APIClient.shared.fetchEvents(upcoming: false)
            let (clubsRes, upRes, popRes) = try await (c, up, pop)
            // Zanri niso kriticni: ce padejo, vzamemo zanre iz dogodkov.
            let genresRes = (try? await APIClient.shared.fetchGenres()) ?? []

            withAnimation(.easeOut(duration: 0.25)) {
                self.clubs = clubsRes
                self.upcomingEvents = upRes
                self.popularEvents = popRes
                self.clubsById = Dictionary(uniqueKeysWithValues: clubsRes.map { ($0.id, $0) })
                if suggestedOrder.isEmpty { suggestedOrder = clubsRes.map(\.id).shuffled() }
                if !genresRes.isEmpty { self.genres = genresRes }
            }
            await loadMe()
        } catch {
            self.errorText = error.userMessage
        }
        isLoading = false
    }

    private func loadMe() async {
        guard !authToken.isEmpty else { return }
        _ = await session.refreshMe()
        self.me = session.me
    }
}
