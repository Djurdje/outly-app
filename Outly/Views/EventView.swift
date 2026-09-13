import SwiftUI

struct EventView: View {
    @State private var comingSoon: [APIEvent] = []
    @State private var popular: [APIEvent] = []
    @State private var clubsById: [Int: APIClub] = [:]
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        // Ta pogled se POTISNE na obstojeci NavigationStack (ProfileView/MyAccountView);
        // gnezden NavigationStack bi skril gumb nazaj in zlomil navigacijo.
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    if isLoading {
                        ProgressView().padding(.vertical, 12)
                    }

                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)
                    }

                    section(title: "Popular", events: popular)
                    section(title: "Coming Soon", events: comingSoon)

                }
                .padding()
                .padding(.bottom, 90)
            }
            .navigationTitle("Events")
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private func section(title: String, events: [APIEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())

            if events.isEmpty && !isLoading && errorText == nil {
                Text("No events.")
                    .foregroundStyle(.secondary)
            }


            ForEach(events, id: \.id) { e in
                let clubName = clubsById[e.clubId]?.name

                NavigationLink {
                    EventDetailView(event: e)
                } label: {
                    EventCardAPI(event: e, clubName: clubName)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil

        do {
            async let up = APIClient.shared.fetchEvents(upcoming: true)
            async let pop = APIClient.shared.fetchEvents(upcoming: false)
            async let clubs = APIClient.shared.fetchClubs()

            let (u, p, c) = try await (up, pop, clubs)

            await MainActor.run {
                self.comingSoon = u
                // Pretekli od najnovejsega (backend vraca od najstarejsega).
                self.popular = p.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
                self.clubsById = Dictionary(uniqueKeysWithValues: c.map { ($0.id, $0) })
            }
        } catch {
            await MainActor.run {
                self.errorText = error.userMessage
            }
        }

        isLoading = false
    }
}
