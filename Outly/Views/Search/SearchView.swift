import SwiftUI

/// Iskanje prek GET /search: klubi IN dogodki, na strezniku, ne po prvih 100 klubih na napravi.
@MainActor
struct SearchView: View {
    @State private var query = ""
    @State private var results: SearchResults?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var openEvent: APIEvent?
    @State private var showEvent = false
    @State private var openingEventId: Int?

    // Prazno stanje (Martin: "search bar je cist prazen"): zanri in klubi, se preden kaj vtipkas.
    @State private var genres: [String] = []
    @State private var clubs: [APIClub] = []
    @State private var events: [APIEvent] = []
    @State private var browseLoaded = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search clubs or events", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                if isLoading {
                    ProgressView().padding(.top, 8)
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red).padding(.top, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let r = results {
                            if r.isEmpty && !isLoading {
                                Text("No results for \"\(trimmed)\".")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                            }

                            if !r.clubs.isEmpty {
                                SectionHeader(title: "Clubs")
                                ForEach(r.clubs) { club in
                                    NavigationLink {
                                        ClubDetailView(clubId: club.id)
                                    } label: {
                                        row(icon: "building.2", title: club.name,
                                            subtitle: club.city, imageUrl: club.logoUrl)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().background(Color.gray.opacity(0.3))
                                }
                            }

                            if !r.events.isEmpty {
                                SectionHeader(title: "Events")
                                ForEach(r.events) { e in
                                    Button {
                                        Task { await open(eventId: e.id) }
                                    } label: {
                                        row(icon: "calendar", title: e.title,
                                            subtitle: eventSubtitle(e), imageUrl: e.posterUrl,
                                            busy: openingEventId == e.id)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().background(Color.gray.opacity(0.3))
                                }
                            }
                        } else if trimmed.count == 1 {
                            Text("Type at least 2 characters.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                        } else {
                            browse
                        }
                    }
                    .padding(.bottom, 40)   // odmik za spodnjo vrstico (past 8)
                }
                .scrollDismissesKeyboard(.immediately)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Search")
            .navigationDestination(isPresented: $showEvent) {
                if let e = openEvent {
                    EventDetailView(event: e)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: query) { _, _ in scheduleSearch() }
        .task { await loadBrowse() }
    }

    // MARK: - Prazno stanje: zanri (vodoravni trak) + klubi

    private var clubsById: [Int: APIClub] {
        Dictionary(clubs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func events(for genre: String) -> [APIEvent] {
        let g = genre.lowercased()
        return events.filter { e in e.genres.contains { $0.lowercased() == g } }
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !genres.isEmpty {
                SectionHeader(title: "Browse by genre")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.self) { g in
                            NavigationLink {
                                GenreEventsView(genre: g, events: events(for: g), clubsById: clubsById)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(g.capitalized)
                                        .font(.system(size: 14, weight: .semibold))
                                    let n = events(for: g).count
                                    if n > 0 {
                                        Text("\(n)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white.opacity(0.55))
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Color.white.opacity(0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !clubs.isEmpty {
                SectionHeader(title: "Clubs")
                    .padding(.top, 4)
                ForEach(clubs) { club in
                    NavigationLink {
                        ClubDetailView(clubId: club.id)
                    } label: {
                        row(icon: "building.2", title: club.name,
                            subtitle: clubSubtitle(club), imageUrl: club.logoUrl)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.gray.opacity(0.3))
                }
            }

            if browseLoaded && genres.isEmpty && clubs.isEmpty {
                Text("Search for a club or an event.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    private func clubSubtitle(_ c: APIClub) -> String {
        let n = events.filter { $0.clubId == c.id }.count
        var parts: [String] = []
        if !c.city.isEmpty { parts.append(c.city) }
        if n > 0 { parts.append(n == 1 ? "1 upcoming event" : "\(n) upcoming events") }
        return parts.joined(separator: " · ")
    }

    private func loadBrowse() async {
        guard !browseLoaded else { return }
        async let g = APIClient.shared.fetchGenres()
        async let c = APIClient.shared.fetchClubs()
        async let e = APIClient.shared.fetchEvents()
        genres = (try? await g) ?? []
        clubs = (try? await c) ?? []
        events = (try? await e) ?? []
        browseLoaded = true
    }

    private func eventSubtitle(_ e: SearchResults.Event) -> String {
        var parts: [String] = []
        if !e.clubName.isEmpty { parts.append(e.clubName) }
        if let d = e.startDate {
            let f = DateFormatter()
            f.dateFormat = "d. MMM, HH:mm"
            parts.append(f.string(from: d))
        }
        return parts.joined(separator: " · ")
    }

    private func row(icon: String, title: String, subtitle: String, imageUrl: String, busy: Bool = false) -> some View {
        HStack(spacing: 12) {
            if let url = URL(string: imageUrl), !imageUrl.isEmpty {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundColor(.white).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundColor(.gray).lineLimit(1)
                }
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                Image(systemName: "chevron.right").foregroundColor(.gray.opacity(0.7))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// Iskanje sprozimo 350 ms po zadnjem znaku, da ne streljamo klica na vsako tipko.
    private func scheduleSearch() {
        searchTask?.cancel()
        errorText = nil
        let q = trimmed
        guard q.count >= 2 else {
            results = nil
            isLoading = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let r = try await APIClient.shared.search(q)
                if Task.isCancelled { return }
                results = r
            } catch {
                if Task.isCancelled { return }
                errorText = error.userMessage
            }
        }
    }

    private func open(eventId: Int) async {
        openingEventId = eventId
        defer { openingEventId = nil }
        do {
            openEvent = try await APIClient.shared.fetchEvent(id: eventId)
            showEvent = true
        } catch {
            errorText = error.userMessage
        }
    }
}
