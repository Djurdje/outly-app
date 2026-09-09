import SwiftUI

/// Dogodki enega zanra (iz "Discover your genre" na domacem zaslonu). Potisnjen pogled,
/// brez lastnega NavigationStacka (past 9). Seznam pride ze nalozen iz HomeView.
struct GenreEventsView: View {
    let genre: String
    let events: [APIEvent]
    let clubsById: [Int: APIClub]

    private let stolpca = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: genre.capitalized, size: 28)
                    .padding(.top, 6)

                if events.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(Color.outlyBlue)
                        Text("No \(genre.lowercased()) events yet").font(.headline).foregroundStyle(.white)
                        Text("Check back soon.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: stolpca, spacing: 18) {
                        ForEach(events) { e in
                            NavigationLink {
                                EventDetailView(event: e)
                            } label: {
                                EventPosterCard(event: e, clubName: clubsById[e.clubId]?.name, width: 165)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
