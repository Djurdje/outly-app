import SwiftUI

/// "Interested events" (Martin, 25. 9. 2026: prej "Going events" — sedaj samo dogodki, kjer
/// sem rekel "I'm in"; dogodki z vstopnico (.going) so pod Tickets, tu se ne kazejo vec).
/// Zaslon "See all" iz razdelka na domacem zaslonu, isti vir (GET /me/plans). Potisnjen
/// pogled — brez lastnega NavigationStack (past 9). Pretekli dogodki so v loceni skupini
/// spodaj, da uporabnik vidi, zakaj jih ni vec na vrhu.
@MainActor
struct SavedView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var plans: [FriendPlan] = []
    @State private var clubsById: [Int: APIClub] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var loaded = false

    /// Samo interested (going ima svoj dom pod Tickets) — Martin, 25. 9. 2026.
    private var interested: [FriendPlan] { plans.filter { $0.myPlan == .interested } }

    private var upcoming: [FriendPlan] {
        interested.filter { ($0.event.startDate ?? .distantFuture) >= Date().addingTimeInterval(-6 * 3600) }
    }
    private var past: [FriendPlan] {
        interested.filter { ($0.event.startDate ?? .distantFuture) < Date().addingTimeInterval(-6 * 3600) }
    }

    var body: some View {
        Group {
            Screen {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Interested events")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 6)

                        if isLoading && !loaded {
                            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
                        } else if let err = loadError, !loaded {
                            VStack(spacing: 10) {
                                Text(err).foregroundColor(.red).font(.subheadline).multilineTextAlignment(.center)
                                Button("Try again") { Task { await load() } }
                                    .foregroundColor(.outlyBlue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        } else if interested.isEmpty {
                            prazno
                        } else {
                            if !upcoming.isEmpty {
                                Text("Coming up")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                ForEach(upcoming) { p in vrstica(p) }
                            }
                            if !past.isEmpty {
                                Text("Already happened")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, upcoming.isEmpty ? 0 : 8)
                                ForEach(past) { p in vrstica(p).opacity(0.6) }
                            }
                        }

                        Spacer(minLength: 30)
                    }
                }
                // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
                .refreshable { await Task { await load() }.value }
            }
            .task {
                if !loaded { await load() }
                if clubsById.isEmpty, let clubs = try? await APIClient.shared.fetchClubs() {
                    clubsById = Dictionary(uniqueKeysWithValues: clubs.map { ($0.id, $0) })
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func vrstica(_ p: FriendPlan) -> some View {
        NavigationLink { EventDetailView(event: p.event) } label: {
            EventCardAPI(event: p.event,
                         clubName: p.clubName.isEmpty ? clubsById[p.event.clubId]?.name : p.clubName,
                         clubLogoUrl: p.clubLogoUrl.isEmpty ? clubsById[p.event.clubId]?.logoUrl : p.clubLogoUrl,
                         variant: .clubRow,
                         planBadge: p.myPlan)
        }
        .buttonStyle(.plain)
    }

    /// Naloz moje nacrte; brez zetona (odjavljen) ostane prazen seznam, ne napaka.
    private func load() async {
        guard !session.token.isEmpty else { loaded = true; return }
        isLoading = true
        loadError = nil
        do {
            plans = try await APIClient.shared.fetchMyPlans(token: session.token)
            loaded = true
        } catch is CancellationError {
        } catch let url as URLError where url.code == .cancelled {
        } catch {
            loadError = error.userMessage
        }
        isLoading = false
    }

    private var prazno: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 50)
            Text("No interested events yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Tap \"I'm in\" on any event and it will show up here and on your home screen — on every device you log in to.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }
}
