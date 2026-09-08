import SwiftUI
import CoreLocation

/// Domaci zaslon: Tonight / This weekend / Trending (po prodanih vstopnicah) /
/// Near you (z razdaljo) / Picked for you (po zanrih). Vsi seznami so iz zivih
/// podatkov (GET /clubs, GET /events). Priporocila se premesajo ENKRAT ob nalaganju —
/// prej so se ob vsakem izrisu, zato so kartice pod prstom skakale.
@MainActor
struct HomeView: View {
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

    private var bigComingUp: APIEvent? { sortedUpcoming.first }

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

                    SearchBarPlaceholder()

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
                        if !tonight.isEmpty {
                            sekcija("Tonight", podnaslov: "Doors open soon") {
                                HorizontalEventsScroll(events: tonight, clubsById: clubsById)
                            }
                        } else if !thisWeek.isEmpty {
                            sekcija("This week", podnaslov: "Next seven days") {
                                HorizontalEventsScroll(events: thisWeek, clubsById: clubsById)
                            }
                        }

                        if !weekend.isEmpty {
                            sekcija("This weekend", podnaslov: "Friday to Sunday") {
                                HorizontalEventsScroll(events: weekend, clubsById: clubsById)
                            }
                        }

                        if !trending.isEmpty {
                            sekcija("Trending now", podnaslov: "Selling fastest on Outly") {
                                HorizontalEventsScroll(events: trending, clubsById: clubsById)
                            }
                        }

                        if !nearbyClubs.isEmpty {
                            sekcija("Near you", podnaslov: "Closest clubs first") {
                                HorizontalClubsScrollAPI(clubs: nearbyClubs, variant: .area, distances: nearbyDistances)
                            }
                        }

                        if !suggestedClubs.isEmpty {
                            sekcija("Picked for you", podnaslov: userGenres.isEmpty ? "Popular clubs" : "Based on your genres") {
                                HorizontalClubsScrollAPI(clubs: suggestedClubs, variant: .suggestion)
                            }
                        }

                        if let e = bigComingUp {
                            sekcija("Big event coming up", podnaslov: nil) {
                                NavigationLink {
                                    EventDetailView(event: e)
                                } label: {
                                    EventCardAPI(event: e, clubName: clubsById[e.clubId]?.name, variant: .hero)
                                }
                                .buttonStyle(.plain)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(todayLine)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            OutlyAvatarView(avatarUrlString: me?.avatarUrl, size: 40)
        }
        .padding(.top, 6)
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

            withAnimation(.easeOut(duration: 0.25)) {
                self.clubs = clubsRes
                self.upcomingEvents = upRes
                self.popularEvents = popRes
                self.clubsById = Dictionary(uniqueKeysWithValues: clubsRes.map { ($0.id, $0) })
                if suggestedOrder.isEmpty { suggestedOrder = clubsRes.map(\.id).shuffled() }
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
