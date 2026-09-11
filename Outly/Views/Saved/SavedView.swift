import SwiftUI

/// Zavihek "Saved": dogodki, ki jih je uporabnik oznacil s srckom. Seznam pride s
/// streznika (FavoritesStore / GET /me/favorites), zato je isti na vseh napravah.
/// Odpovedani in pretekli dogodki so v loceni skupini spodaj, da uporabnik vidi,
/// zakaj jih ni vec na vrhu.
@MainActor
struct SavedView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var session: SessionStore

    @State private var clubsById: [Int: APIClub] = [:]

    private var upcoming: [APIEvent] {
        favorites.events.filter { ($0.startDate ?? .distantFuture) >= Date().addingTimeInterval(-6 * 3600) }
    }
    private var past: [APIEvent] {
        favorites.events.filter { ($0.startDate ?? .distantFuture) < Date().addingTimeInterval(-6 * 3600) }
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Saved")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.top, 6)

                        if favorites.isLoading && !favorites.loaded {
                            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
                        } else if let err = favorites.loadError, !favorites.loaded {
                            VStack(spacing: 10) {
                                Text(err).foregroundColor(.red).font(.subheadline).multilineTextAlignment(.center)
                                Button("Try again") { Task { await favorites.load(token: session.token) } }
                                    .foregroundColor(.outlyBlue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        } else if favorites.events.isEmpty {
                            prazno
                        } else {
                            if !upcoming.isEmpty {
                                Text("Coming up")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                ForEach(upcoming) { e in
                                    NavigationLink { EventDetailView(event: e) } label: {
                                        EventCardAPI(event: e, clubName: clubsById[e.clubId]?.name,
                                                     clubLogoUrl: clubsById[e.clubId]?.logoUrl, variant: .clubRow)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if !past.isEmpty {
                                Text("Already happened")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, upcoming.isEmpty ? 0 : 8)
                                ForEach(past) { e in
                                    NavigationLink { EventDetailView(event: e) } label: {
                                        EventCardAPI(event: e, clubName: clubsById[e.clubId]?.name,
                                                     clubLogoUrl: clubsById[e.clubId]?.logoUrl, variant: .clubRow)
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(0.6)
                                }
                            }
                        }

                        Spacer(minLength: 30)
                    }
                }
                .refreshable { await favorites.load(token: session.token) }
            }
            .task {
                if !favorites.loaded { await favorites.load(token: session.token) }
                if clubsById.isEmpty, let clubs = try? await APIClient.shared.fetchClubs() {
                    clubsById = Dictionary(uniqueKeysWithValues: clubs.map { ($0.id, $0) })
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var prazno: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 50)
            Text("Nothing saved yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Tap the heart on any event and it will wait for you here — on every device you log in to.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }
}
