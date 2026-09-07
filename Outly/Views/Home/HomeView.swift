import SwiftUI
import CoreLocation

struct HomeView: View {
    @State private var clubs: [APIClub] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var me: Me?

    @State private var upcomingEvents: [APIEvent] = []
    @State private var popularEvents: [APIEvent] = []
    @State private var clubsById: [Int: APIClub] = [:]

    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }

    @EnvironmentObject private var prefs: UserPreferences
    @EnvironmentObject private var locationManager: LocationManager

    private var userMinAge: Int {
        switch prefs.selectedAgeGroup {
        case .under18: return 0
        case ._18plus: return 18
        case ._21plus: return 21
        case ._25plus: return 25
        case nil: return 0
        }
    }

    private func distanceKm(to club: APIClub) -> Double? {
        guard let userLoc = locationManager.location else { return nil }
        guard let lat = club.lat, let lng = club.lng else { return nil }

        let clubLoc = CLLocation(latitude: lat, longitude: lng)
        return userLoc.distance(from: clubLoc) / 1000.0
    }

    private var filteredClubs: [APIClub] {
        clubs.filter { club in
            if club.minAge > userMinAge { return false }

            if !prefs.selectedGenres.isEmpty {
                let selectedSet = Set(prefs.selectedGenres.map { $0.rawValue.lowercased() })
                let clubSet = Set(club.genres.map { $0.lowercased() })
                if selectedSet.isDisjoint(with: clubSet) { return false }
            }

            if let d = distanceKm(to: club) {
                if d > prefs.maxDistanceKm { return false }
            }

            return true
        }
    }

    private var suggestedClubs: [APIClub] { Array(filteredClubs.shuffled().prefix(6)) }

    private var nearbyClubs: [APIClub] {
        guard locationManager.location != nil else { return [] }

        return filteredClubs
            .filter { distanceKm(to: $0) != nil }
            .sorted {
                (distanceKm(to: $0) ?? .greatestFiniteMagnitude) <
                (distanceKm(to: $1) ?? .greatestFiniteMagnitude)
            }
            .prefix(10)
            .map { $0 }
    }

    private var bigComingUp: APIEvent? {
        upcomingEvents.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }.first
    }

    private var bigPopular: APIEvent? {
        popularEvents.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    ZStack {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)

                        HStack {
                            Button(action: {}) {
                                OutlyAvatarView(avatarUrlString: me?.avatarUrl, size: 40)
                            }
                            Spacer()
                        }
                    }

                    SearchBarPlaceholder()

                    if isLoading {
                        ProgressView().padding(.vertical, 20)
                    }

                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }

                    SectionHeader(title: "Suggestions")
                    HorizontalClubsScrollAPI(
                        clubs: suggestedClubs,
                        variant: .suggestion
                    )

                    SectionHeader(title: "Last week's biggest hits")
                    if let e = bigPopular {
                        NavigationLink {
                            EventDetailView(event: e)
                        } label: {
                            EventCardAPI(event: e, clubName: clubsById[e.clubId]?.name,clubLogoUrl: clubsById[e.clubId]?.logoUrl, variant: .homeRow)
                        }
                        .buttonStyle(.plain)
                    } else if !isLoading && errorText == nil {
                        Text("No popular events yet.")
                            .foregroundStyle(.secondary)
                    }

                    SectionHeader(title: "In your area")
                    HorizontalClubsScrollAPI(
                        clubs: nearbyClubs,
                        variant: .area
                    )

                    SectionHeader(title: "Big Events Coming Up")
                    if let e = bigComingUp {
                        NavigationLink {
                            EventDetailView(event: e)
                        } label: {
                            // če hočeš “velik card” stil kot screenshot, bomo to naredili kot BigEventHeroCard.
                            // za zdaj: deluje + real API
                            EventCardAPI(event: e, clubName: clubsById[e.clubId]?.name, variant: .hero)
                        }
                        .buttonStyle(.plain)
                    } else if !isLoading && errorText == nil {
                        Text("No upcoming events yet.")
                            .foregroundStyle(.secondary)
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
                .padding()
                .padding(.bottom, 20)
            }
            .navigationTitle("")
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

    private func loadAll() async {
        isLoading = true
        errorText = nil

        do {
            async let c = APIClient.shared.fetchClubs()
            async let up = APIClient.shared.fetchEvents(upcoming: true)
            async let pop = APIClient.shared.fetchEvents(upcoming: false)

            let (clubsRes, upRes, popRes) = try await (c, up, pop)

            await MainActor.run {
                self.clubs = clubsRes
                self.upcomingEvents = upRes
                self.popularEvents = popRes
                self.clubsById = Dictionary(uniqueKeysWithValues: clubsRes.map { ($0.id, $0) })
            }

            await loadMe()
        } catch {
            await MainActor.run {
                self.errorText = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func loadMe() async {
        guard !authToken.isEmpty else { return }
        do {
            let fetched = try await APIClient.shared.me(token: authToken)
            await MainActor.run { self.me = fetched }
        } catch {
            print("HomeView loadMe error:", error.localizedDescription)
        }
    }
}
