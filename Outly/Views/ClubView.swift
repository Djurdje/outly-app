import SwiftUI
import MapKit

struct ClubDetailView: View {
    let clubId: Int

    @State private var club: APIClub?
    @State private var popular: [APIEvent] = []
    @State private var comingSoon: [APIEvent] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.0569, longitude: 14.5058),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 1) Banner + ime (kot zdaj)
                header

                // Optional: error/loading status (ne spremeni dizajna)
                if isLoading {
                    ProgressView().padding(.horizontal, 16)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).padding(.horizontal, 16)
                }

                // 2) Popular events
                eventsSection(title: "Popular", events: popular)

                // 3) Info block (logo, mesto, država, žanri, min age)
                infoBlock

                // 4) Coming Soon
                eventsSection(title: "Coming Soon", events: comingSoon)

                // 5) Mapa brez naslova "Location"
                mapBlock

                // 6) Kontakti čisto na koncu
                contactBlock

                // da se ne odreže pod tab bar
                Spacer(minLength: 0)
            }
            .padding(.bottom, 90)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: - 1) Header
    // Slike so povsod ovite v Color.clear.overlay(...).clipped(): AsyncImage s
    // scaledToFill brez okvirja prevzame naravno velikost slike (1600 px) in
    // razsiri celoten zaslon v desno — vsebina je bila odrezana, dotiki na
    // domaci strani pa so zgresili kartice. Color.clear vzame le prostor starsa.
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            if let banner = club?.bannerUrl, !banner.isEmpty, let url = URL(string: banner) {
                AsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().opacity(0.15)
                }
            } else {
                Rectangle().opacity(0.12)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(club?.name ?? "Club")
                .font(.system(size: 40, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(height: 260)
        .clipped()
    }

    // MARK: - 3) Info block (logo + mesto/država/žanri/min age)
    private var infoBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            if let logo = club?.logoUrl, !logo.isEmpty, let url = URL(string: logo) {
                AsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Circle().opacity(0.12)
                }
                .frame(width: 62, height: 62)
                .clipShape(Circle())
            } else {
                Circle().opacity(0.12)
                    .frame(width: 62, height: 62)
                    .overlay(Text("🎉"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(cityCountryText)
                    .foregroundStyle(.secondary)

                if let genres = club?.genres, !genres.isEmpty {
                    Text(genres.map { $0.capitalized }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let minAge = club?.minAge {
                    Text("Min age: \(minAge)+")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var cityCountryText: String {
        let city = (club?.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let country = (club?.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !city.isEmpty && !country.isEmpty { return "\(city), \(country)" }
        if !city.isEmpty { return city }
        if !country.isEmpty { return country }
        return ""
    }

    // MARK: - 5) Map block (brez "Location" naslova)
    @ViewBuilder
    private var mapBlock: some View {
        if let lat = club?.lat, let lng = club?.lng {
            Map(coordinateRegion: $region, annotationItems: [SimplePin(lat: lat, lng: lng)]) { pin in
                MapMarker(coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng))
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .onAppear {
                region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }

            // naslov/adresa pod mapo (brez "Location" headerja)
            if let address = club?.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }
    

    // MARK: - 6) Contact block
    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contact")
                .font(.headline)

            ContactRow(label: "Email", value: club?.contactEmail)
            ContactRow(label: "Phone", value: club?.contactPhone)
            ContactRow(label: "Instagram", value: club?.instagram)
            ContactRow(label: "Website", value: club?.website)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Events section
    @ViewBuilder
    private func eventsSection(title: String, events: [APIEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())

            if events.isEmpty && !isLoading && errorText == nil {
                Text("No events.")
                    .foregroundStyle(.secondary)
            }

            ForEach(events, id: \.id) { e in
                NavigationLink {
                    EventDetailView(event: e)
                } label: {
                    EventCardAPI(event: e, clubName: club?.name, variant: .clubRow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Load
    private func load() async {
        isLoading = true
        errorText = nil
        do {
            async let c = APIClient.shared.fetchClub(id: clubId)
            async let pop = APIClient.shared.fetchEvents(clubId: clubId, upcoming: false) // past -> popular
            async let up = APIClient.shared.fetchEvents(clubId: clubId, upcoming: true)  // future -> coming soon

            club = try await c
            popular = try await pop
            comingSoon = try await up
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

private struct SimplePin: Identifiable {
    let id = UUID()
    let lat: Double
    let lng: Double
}

private struct ContactRow: View {
    let label: String
    let value: String?

    var body: some View {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            Text("\(label):")
                .foregroundStyle(.secondary)
            Spacer()
            Text(v.isEmpty ? "-" : v)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}
