import SwiftUI

/// Vodoravna vrsta klubov. Vsaka kartica vodi na klub (prej ni vodila nikamor —
/// "Suggestions" na domacem zaslonu ni bilo mogoce odpreti).
struct HorizontalClubsScrollAPI: View {
    let clubs: [APIClub]
    let variant: ClubCardVariant
    /// Razdalja v km po id kluba (samo za "Near you").
    var distances: [Int: Double] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(clubs) { club in
                    NavigationLink {
                        ClubDetailView(clubId: club.id)
                    } label: {
                        ClubCard(club: club, variant: variant, distanceKm: distances[club.id])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
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
