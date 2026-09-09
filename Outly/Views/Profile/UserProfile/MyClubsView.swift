import SwiftUI

/// "My clubs" za navadnega uporabnika: klubi, v katerih je ze imel vstopnico
/// (iz GET /me/tickets, brez podvajanja), in spodaj vsi klubi (GET /clubs).
/// Vsaka vrstica vodi na ClubDetailView. Prazno stanje vabi k prijavi kluba.
@MainActor
struct MyClubsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var visited: [APIClub] = []
    @State private var all: [APIClub] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("My clubs")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if isLoading && all.isEmpty {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
                    } else if let errorText, all.isEmpty {
                        VStack(spacing: 10) {
                            Text(errorText).foregroundColor(.red).font(.subheadline)
                            Button("Try again") { Task { await load() } }.foregroundColor(.outlyBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    } else {
                        if visited.isEmpty {
                            prazno
                        } else {
                            Text("Clubs you've been to")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                            ForEach(visited) { c in
                                NavigationLink { ClubDetailView(clubId: c.id) } label: { vrstica(c) }
                                    .buttonStyle(.plain)
                            }
                        }

                        if !all.isEmpty {
                            Text("All clubs")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, visited.isEmpty ? 0 : 8)
                            ForEach(all) { c in
                                NavigationLink { ClubDetailView(clubId: c.id) } label: { vrstica(c) }
                                    .buttonStyle(.plain)
                            }
                        }

                        NavigationLink { ReguestForCreatorView() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "building.2")
                                    .foregroundColor(.outlyBlue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Own or run a club?")
                                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                    Text("Request creator access and list your events on Outly.")
                                        .font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.gray)
                            }
                            .padding(14)
                            .background(Color.outlyBlue.opacity(0.12))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await load() } }
    }

    private var prazno: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.outlyBlue)
            Text("No clubs yet")
                .font(.title3).fontWeight(.semibold).foregroundColor(.white)
            Text("Clubs you buy tickets for\nwill show up here.")
                .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    private func vrstica(_ c: APIClub) -> some View {
        HStack(spacing: 12) {
            if !c.logoUrl.isEmpty, let url = URL(string: c.logoUrl) {
                Color.clear
                    .overlay(
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().opacity(0.12)
                        }
                    )
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.outlyBlue.opacity(0.25))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "building.2").foregroundColor(.outlyBlue))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(c.name)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text(c.city.isEmpty ? c.address : c.city)
                    .font(.subheadline).foregroundColor(.gray).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray)
        }
        .padding(14)
        .background(Color.gray.opacity(0.14))
        .cornerRadius(16)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let clubs = try await APIClient.shared.fetchClubs()
            all = clubs

            if session.isLoggedIn {
                // Klubi iz vstopnic: prvi pojav vsakega clubId, v vrstnem redu vstopnic.
                let tickets = try await APIClient.shared.fetchMyTickets(token: session.token)
                var seen = Set<Int>()
                var ids: [Int] = []
                for t in tickets where !seen.contains(t.clubId) {
                    seen.insert(t.clubId)
                    ids.append(t.clubId)
                }
                let byId = Dictionary(clubs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                visited = ids.compactMap { byId[$0] }
            }
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }
}

struct Screen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .background(Color.black.ignoresSafeArea())
    }
}
