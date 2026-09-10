import SwiftUI

/// Vodoravna vrsta klubov. Vsaka kartica vodi na klub (prej ni vodila nikamor —
/// "Suggestions" na domacem zaslonu ni bilo mogoce odpreti).
struct HorizontalClubsScrollAPI: View {
    let clubs: [APIClub]
    let variant: ClubCardVariant
    /// Razdalja v km po id kluba (samo "In your area").
    var distances: [Int: Double] = [:]
    /// "In your area" (Martin, 10. 9.): prvi dotik logo zatemni in pokaze razdaljo,
    /// drugi dotik odpre klub, dotik drugam (HomeView) izbiro pocisti. nil = obnasanje kot prej.
    var selected: Binding<Int?>? = nil

    @State private var openClubId: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(clubs) { club in
                    if let selected, variant == .area {
                        Button {
                            if selected.wrappedValue == club.id || distances[club.id] == nil {
                                openClubId = club.id
                            } else {
                                withAnimation(.easeOut(duration: 0.15)) { selected.wrappedValue = club.id }
                            }
                        } label: {
                            ClubCard(club: club, variant: variant,
                                     distanceKm: distances[club.id],
                                     showDistance: selected.wrappedValue == club.id)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ClubDetailView(clubId: club.id)
                        } label: {
                            ClubCard(club: club, variant: variant, distanceKm: distances[club.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .navigationDestination(item: $openClubId) { id in
            ClubDetailView(clubId: id)
        }
    }
}

/// Vodoravna vrsta dogodkov s plakati (Tonight, This weekend, Trending).
struct HorizontalEventsScroll: View {
    let events: [APIEvent]
    let clubsById: [Int: APIClub]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(events) { e in
                    NavigationLink {
                        EventDetailView(event: e)
                    } label: {
                        EventPosterCard(event: e, clubName: clubsById[e.clubId]?.name)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
