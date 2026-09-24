import SwiftUI
import CoreLocation
import UIKit

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
    /// Okvirja avatarja in polja "Where to?" v okenskih koordinatah — MainTabView jih rabi za
    /// izvor "kroznega razkritja" (Martin, 23. 9.). Privzeto .constant, da klicu ni treba skrbeti
    /// za to v predogledih/testih.
    var okvirIzvorov: Binding<IzvoriRazkritja> = .constant(IzvoriRazkritja())
    @State private var genres: [String] = []

    @State private var clubs: [APIClub] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var me: Me?

    @State private var upcomingEvents: [APIEvent] = []
    @State private var popularEvents: [APIEvent] = []
    @State private var clubsById: [Int: APIClub] = [:]
    @State private var suggestedOrder: [Int] = []
    /// "In your area": klub, ki je po prvem dotiku zatemnjen in kaze razdaljo (drugi dotik odpre klub).
    @State private var areaSelected: Int?
    /// Filtri (desni del "Where to?"); privzeti = brez omejitev.
    @State private var filters: EventFilters = .privzeti
    @State private var showFilters = false
    /// Zamegljen posnetek domacega zaslona za zaslon Filtri (isto kot Search/Profile,
    /// Martin 22. 9.). Nastane ob dotiku na ikono filtra, torej kaze tocno to, kar je bilo.
    @State private var posnetekZaFiltre: UIImage?
    /// Spustni meni obvestil pod zvoncem (od 20. 9.; prej je zvonec vodil na My Clubs).
    @State private var showNotifications = false
    @State private var invites: [MyInvite] = []
    @State private var friendRequests: [FriendRequest] = []
    @State private var receivedTickets: [ReceivedTicket] = []
    /// Obvestila "klub, ki mu sledis, je objavil dogodek" (backend migracija 019).
    @State private var clubEvents: [ClubEventNotification] = []
    @State private var notificationsLoading = false
    /// "Your friends' plans" (od 20. 9.): dogodki, na katere gredo prijatelji (GET /me/friends/plans).
    @State private var friendPlans: [FriendPlan] = []
    /// "Going events" (Martin, 24. 9. 2026, namesto "Liked events" — srcek je odstranjen, nadomestil
    /// ga je "I'm in"): moji lastni nacrti (GET /me/plans), going in interested.
    @State private var myPlans: [FriendPlan] = []
    /// Odmik drsenja (0 = vrh) za ozadje, ki se odziva na drsenje.
    @State private var scrollOffset: CGFloat = 0

    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }

    @EnvironmentObject private var prefs: UserPreferences
    @EnvironmentObject private var locationManager: LocationManager

    /// "Going events": prihajajoci moji nacrti, going najprej, nato interested, znotraj tega
    /// po datumu (Martin, 24. 9. 2026 — nadomestilo za "Liked events" po odstranitvi srckov).
    private var goingUpcoming: [FriendPlan] {
        myPlans
            .filter { ($0.event.startDate ?? .distantFuture) >= Date().addingTimeInterval(-6 * 3600) }
            .sorted { a, b in
                if (a.myPlan == .going) != (b.myPlan == .going) { return a.myPlan == .going }
                return (a.event.startDate ?? .distantFuture) < (b.event.startDate ?? .distantFuture)
            }
    }

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
            return filters.ustreza(club, razdaljaKm: distanceKm(to: club))
        }
    }

    /// Mesta klubov za zaslon Filtri (brez podvajanja, po abecedi).
    private var cities: [String] {
        Array(Set(clubs.map(\.city).filter { !$0.isEmpty })).sorted()
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

    /// Prihajajoci dogodki po casu, skozi Filtre (zanri, starost, cena; mesto/razdalja prek kluba).
    private var sortedUpcoming: [APIEvent] {
        upcomingEvents
            .filter { e in
                guard filters.ustreza(e) else { return false }
                if let club = clubsById[e.clubId] {
                    return filters.ustreza(club, razdaljaKm: distanceKm(to: club))
                }
                return true
            }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
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
        // Samo pretekli dogodki zadnjih 7 dni — sicer bi bil "hit tedna" lahko star mesece.
        let teden = Date().addingTimeInterval(-7 * 24 * 3600)
        if let p = popularEvents.filter({ $0.soldCount > 0 && ($0.startDate ?? .distantPast) >= teden })
            .max(by: { $0.soldCount < $1.soldCount }) {
            return (p, String(localized: "Last week's biggest hit"))
        }
        if let t = trending.first { return (t, String(localized: "Trending right now")) }
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
        let pozdrav = h < 12 ? String(localized: "Good morning") : (h < 18 ? String(localized: "Good afternoon") : String(localized: "Good evening"))
        if let name = me?.username, !name.isEmpty { return "\(pozdrav), \(name)" }
        return pozdrav
    }

    private var todayLine: String {
        let f = DateFormatter()
        f.locale = Jezik.shared.locale
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {

                    header

                    WhereToField(onSearch: odpriIskanje,
                                 onFilter: {
                                     posnetekZaFiltre = UIApplication.shared.posnetekZaslona()
                                     showFilters = true
                                 },
                                 filterActive: filters.jeAktiven)
                        // Okvir polja "Where to?" v okenskih koordinatah — izvor pravokotnika za
                        // rast/krcitev Searcha (isti okvir, isti radij kot polje samo).
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: WhereToOkvirKey.self, value: g.frame(in: .global))
                            }
                        )

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

                        // 2b. Going events (Martin, 24. 9.): moji nacrti ("I'm in") na domaci zaslon,
                        // namesto prejsnjih srckov. Razdelek je viden samo, ko je kaj v njem.
                        if !goingUpcoming.isEmpty {
                            goingSection
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
                                HorizontalClubsScrollAPI(clubs: areaClubs, variant: .area, distances: nearbyDistances, selected: $areaSelected)
                            }
                        }

                        // 4b. Your friends' plans (Martin, 20. 9.): krogi prijateljev + Invite more + View.
                        // Samo prijavljeni; brez nacrtov ostane kot namig, da dodas prijatelje.
                        if session.isLoggedIn {
                            FriendsPlansSection(plans: friendPlans, clubsById: clubsById)
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
                            genreSection
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
                .contentShape(Rectangle())
                .onTapGesture { if areaSelected != nil { withAnimation(.easeOut(duration: 0.15)) { areaSelected = nil } } }
                // Odmik drsenja za ozadje (iOS 17: PreferenceKey; onScrollGeometryChange je sele iOS 18).
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: HomeScrollOffsetKey.self,
                                               value: -g.frame(in: .named("homeScroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { scrollOffset = $0 }
            // Okvirja avatarja/polja gresta navzgor v MainTabView (izvora "kroznega razkritja").
            // Posodabljata se tudi med drsenjem, zato MainTabView v trenutku dotika ve, ali sta
            // (se) vidna — ce nista, uporabi privzeti izvor pri robu (glej preklopi(na:)).
            .onPreferenceChange(AvatarOkvirKey.self) { if let r = $0 { okvirIzvorov.wrappedValue.avatar = r } }
            .onPreferenceChange(WhereToOkvirKey.self) { if let r = $0 { okvirIzvorov.wrappedValue.whereTo = r } }
            .background(homeBackground)
            .overlay {
                if showNotifications { notificationsOverlay }
            }
            .navigationTitle("")
            // fullScreenCover, ne sheet: filtri lezijo cez cel zaslon nad zamegljenim
            // zamrznjenim domacim zaslonom, tako kot Search in Profile. Kot list bi bili
            // kartica s sistemskim ozadjem in posnetek bi bil odrezan.
            .fullScreenCover(isPresented: $showFilters) {
                FiltersView(filters: $filters, cities: cities,
                            events: upcomingEvents, clubsById: clubsById,
                            distanceKm: { distanceKm(to: $0) })
                    .environment(\.posnetekDoma, posnetekZaFiltre)
            }
            // Osvezitev tece v samostojni nalogi: SwiftUI prekine nalogo .refreshable, ce se
            // stanje pogleda spremeni pred koncem klicev (isLoading, me, lokacija), in
            // URLSession bi vrgel "cancelled" -> "Connection problem". Task {} tega ne deduje.
            .refreshable { await Task { await loadAll() }.value }
        }
        .preferredColorScheme(.dark)
        .task {
            locationManager.requestPermission()
            await loadAll()
        }
        // Ob vrnitvi na zavihek osvezimo samo profil (avatar, pozdrav), ne vsega.
        // Prvi prikaz: .task ze klice loadMe() znotraj loadAll(), zato tu preskocimo.
        .onAppear {
            // Ob vrnitvi na zavihek (npr. z zaslona dogodka po "I'm in") osvezimo profil in nacrte
            // (Martin, 24. 9.: Going events in Friends plans morajo sledit takoj, ne sele po pull-to-refresh).
            if !clubs.isEmpty { Task { await loadMe(); await osveziNacrte() } }
        }
    }

    // MARK: - Going events (loceno zaradi tipnega preverjevalnika, kot genreSection)
    private var goingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Going events")
                Spacer()
                NavigationLink { SavedView() } label: {
                    Text("See all")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(goingUpcoming) { p in
                        NavigationLink { EventDetailView(event: p.event) } label: {
                            ZStack(alignment: .topTrailing) {
                                EventPosterCard(event: p.event, clubName: p.clubName.isEmpty ? clubsById[p.event.clubId]?.name : p.clubName)
                                if let plan = p.myPlan { goingZnacka(plan) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Majhna znacka na kartici "Going events": moder poln pil (going) ali bela obroba (interested).
    private func goingZnacka(_ plan: EventPlan) -> some View {
        Text(plan == .going ? "Going" : "Interested")
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.3)
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(plan == .going ? Color.outlyBlue : Color.black.opacity(0.55))
            .overlay(Capsule().stroke(Color.white.opacity(plan == .going ? 0 : 0.6), lineWidth: 1))
            .clipShape(Capsule())
            .padding(10)
    }

    // MARK: - Discover your genre (vidne 3 vrstice, ostale z drsenjem) — loceno,
    // da tipni preverjevalnik v body ne obupa (Actions #17: "unable to type-check").
    private var genreListHeight: CGFloat {
        let n = genreRows.count
        if n >= 3 { return 72 * 3 + 10 * 2 + 24 }
        return CGFloat(n) * 82
    }

    private var genreFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var genreSection: some View {
        sekcija("Discover your genre", podnaslov: nil) {
            ScrollView(.vertical, showsIndicators: false) {
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
            .frame(height: genreListHeight)
            .mask { genreFadeMask }
        }
    }

    // MARK: - Deli

    /// Delez drsenja 0…1 (1400 pt drsenja = poln premik sijev).
    private var scrollT: CGFloat { min(max(scrollOffset / 1400, 0), 1) }

    /// Ozadje domacega zaslona (od 20. 9.): temno mornariski preliv z dvema mehkima
    /// modrima sijema, ki se ob drsenju pocasi premikata in spreminjata moc — zgornji
    /// pojenja in gre desno-gor, spodnji se krepi in leze navzgor. Brez ostrih robov,
    /// brez oblik. Samo tu — ostali zasloni ostanejo crni.
    private var homeBackground: some View {
        let t = scrollT
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 13/255, green: 18/255, blue: 38/255), location: 0),
                    .init(color: Color(red: 10/255, green: 12/255, blue: 20/255), location: 0.46),
                    .init(color: Color(red: 8/255, green: 9/255, blue: 15/255), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Sij A (zgoraj levo): 55 % -> pojenja.
            RadialGradient(colors: [Color.outlyBlue.opacity(0.55), .clear],
                           center: .center, startRadius: 0, endRadius: 310)
                .frame(width: 620, height: 620)
                .blur(radius: 40)
                .offset(x: -100 + 120 * t, y: -260 - 160 * t)
                .opacity(0.95 - 0.55 * t)
            // Sij B (spodaj desno): 30 % -> se krepi in leze navzgor.
            RadialGradient(colors: [Color.outlyBlue.opacity(0.30), .clear],
                           center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 520, height: 520)
                .blur(radius: 60)
                .offset(x: 140 - 90 * t, y: 260 - 240 * t)
                .opacity(0.35 + 0.6 * t)
        }
        .animation(.linear(duration: 0.9), value: t)
        .ignoresSafeArea()
    }

    /// Stevilo obvestil za zvonec: cakajoca vabila v ekipo kluba (Me.pendingInvites), prosnje
    /// za prijateljstvo (Me.pendingFriendRequests) in neprebrane prejete vstopnice
    /// (Me.pendingReceivedTickets); drugih obvestil (APNs) se ni.
    /// 0 = samo zvonec, 1 = "1", 2+ = "1+".
    private var notificationCount: Int {
        (me?.pendingInvites ?? 0) + (me?.pendingFriendRequests ?? 0)
            + (me?.pendingReceivedTickets ?? 0) + (me?.pendingClubEvents ?? 0)
    }

    /// Meni obvestil cez domaci zaslon: zatemnjeno ozadje (dotik zapre) + kartica pod zvoncem.
    private var notificationsOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { zapriObvestila() }
            NotificationsMenuView(invites: $invites, friendRequests: friendRequests, receivedTickets: receivedTickets,
                                  clubEvents: clubEvents,
                                  isLoading: notificationsLoading,
                                  onClose: { zapriObvestila() },
                                  onJoined: { _ in Task { await loadMe() } },
                                  onTicketSeen: { id in Task { await oznaciPrejetoVstopnico(id) } },
                                  onClubEventSeen: { id in Task { await oznaciObvestiloKluba(id) } })
                .padding(.top, 50)
                .padding(.trailing, 16)
                .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private func zapriObvestila() {
        withAnimation(.easeOut(duration: 0.18)) { showNotifications = false }
    }

    private func loadNotifications() async {
        guard !authToken.isEmpty else { return }
        notificationsLoading = true
        defer { notificationsLoading = false }
        async let v = APIClient.shared.fetchMyInvites(token: authToken)
        async let f = APIClient.shared.fetchMyFriends(token: authToken)
        async let p = APIClient.shared.fetchReceivedTickets(token: authToken)
        async let k = APIClient.shared.fetchClubEventNotifications(token: authToken)
        if let vabila = try? await v { invites = vabila }
        if let prijatelji = try? await f { friendRequests = prijatelji.requestsIn }
        // Star backend brez poti -> napaka -> seznam ostane prazen (brez obvestila, ne pade).
        if let prejete = try? await p { receivedTickets = prejete }
        if let klubski = try? await k { clubEvents = klubski }
        await loadMe()
    }

    /// Dotik obvestila "klub je objavil dogodek": lokalno takoj izgine, streznik ga oznaci
    /// kot prebrano, nato se osvezi stevec na zvoncu.
    private func oznaciObvestiloKluba(_ id: Int) async {
        clubEvents.removeAll { $0.id == id }
        guard !authToken.isEmpty else { return }
        try? await APIClient.shared.markClubEventSeen(token: authToken, id: id)
        await loadMe()
    }

    /// Dotik obvestila "X sent you a ticket": lokalno takoj izgine, streznik ga oznaci kot prebrano,
    /// nato se osvezi stevec na zvoncu. Napaka se ne kaze — ob naslednjem nalaganju se vrne.
    private func oznaciPrejetoVstopnico(_ id: Int) async {
        receivedTickets.removeAll { $0.id == id }
        guard !authToken.isEmpty else { return }
        try? await APIClient.shared.markReceivedTicketSeen(token: authToken, id: id)
        await loadMe()
    }

    /// Figma 239:804: avatar levo, logo Outly na sredini, zvonec desno (od 20. 9.).
    /// Pozdrav je pod logom, majhen. Oba gumba sta 36 pt, zato logo ostane v sredini.
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
                    // Okvir avatarja v okenskih koordinatah — izvor kroga za rast/krcitev Profila.
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: AvatarOkvirKey.self, value: g.frame(in: .global))
                        }
                    )
                    Spacer()
                    Button {
                        if showNotifications {
                            zapriObvestila()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showNotifications = true }
                            Task { await loadNotifications() }
                        }
                    } label: {
                        bellButton
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Notifications"))
                }
            }
            Text(greeting)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    /// Zvonec v krogu 36 pt (kot avatar) z modro znacko: "1" ali "1+".
    private var bellButton: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 36, height: 36)
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
            if notificationCount > 0 {
                Text(notificationCount >= 2 ? "1+" : "1")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Color.outlyBlue))
                    .overlay(Capsule().stroke(Color(red: 13/255, green: 18/255, blue: 38/255), lineWidth: 2))
                    .offset(x: 3, y: -3)
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
    }

    private func sekcija<Content: View>(_ naslov: String, podnaslov: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Podnaslovi umaknjeni (Martin, 10. 9.): parameter ostane, da klici ne padejo.
            SectionHeader(title: naslov)
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
            // Nacrti prijateljev in moji lastni ("Going events"): napaka (npr. star backend
            // brez poti) ni kriticna -> prazen razdelek. Tiho, ker to ni kljucni podatek zaslona.
            if !authToken.isEmpty {
                friendPlans = (try? await APIClient.shared.fetchFriendsPlans(token: authToken)) ?? []
                myPlans = (try? await APIClient.shared.fetchMyPlans(token: authToken)) ?? []
            }
        } catch is CancellationError {
            // Prekinitev naloge (SwiftUI) ni napaka za uporabnika.
        } catch let url as URLError where url.code == .cancelled {
            // Isto: URLSession sporoci prekinitev kot URLError.cancelled (-999).
        } catch {
            self.errorText = error.userMessage
        }
        isLoading = false
    }

    /// Nacrti prijateljev in moji nacrti (Going events); napaka ni kriticna -> seznam ostane.
    private func osveziNacrte() async {
        guard !authToken.isEmpty else { return }
        if let f = try? await APIClient.shared.fetchFriendsPlans(token: authToken) { friendPlans = f }
        if let m = try? await APIClient.shared.fetchMyPlans(token: authToken) { myPlans = m }
    }

    private func loadMe() async {
        guard !authToken.isEmpty else { return }
        _ = await session.refreshMe()
        self.me = session.me
    }
}

/// Odmik drsenja domacega zaslona (za ozadje, ki se odziva na drsenje).
private struct HomeScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
