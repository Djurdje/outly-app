import SwiftUI
import MapKit
import AVKit

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

                // Vrstni red po Lukovih navodilih (14. 9. 2026):
                // 1) Slideshow (do 3 slike) + ime kluba cez sliko
                header

                // 2) Logo, mesto, zanri, min age — takoj pod slideshowom
                infoBlock

                if isLoading {
                    ProgressView().padding(.horizontal, 16)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).padding(.horizontal, 16)
                }

                // 3) Popular
                eventsSection(title: String(localized: "Popular"), events: popular)

                // 4) Predstavitveni video (na mestu, kjer je bil prej opis)
                videoBlock

                // 5) Coming Soon
                eventsSection(title: String(localized: "Coming Soon"), events: comingSoon)

                // 6) Mapa + naslov
                mapBlock

                // 7) Kontakti
                contactBlock

                // 8) Opis kluba cisto na koncu
                descriptionBlock

                // da se ne odreže pod tab bar
                Spacer(minLength: 0)
            }
            .padding(.bottom, 90)
        }
        .navigationTitle("")
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: - 1) Header: slideshow do treh slik, ime kluba cez sliko
    // Slike so povsod ovite v Color.clear.overlay(...).clipped() (past 12).
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            ClubSlideshow(urls: club?.slideshowUrls ?? [])

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Text(club?.name ?? String(localized: "Club"))
                .font(.system(size: 40, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .allowsHitTesting(false)
        }
        .frame(height: 260)
        .clipped()
    }

    // MARK: - 4) Predstavitveni video kluba (iste sirine kot vsebina, visina kot prejsnji opis)
    @ViewBuilder
    private var videoBlock: some View {
        if let v = club?.videoUrl, !v.isEmpty, let url = URL(string: v) {
            ClubVideoPlayer(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .padding(.horizontal, 16)
        } else if club != nil {
            // Okvir je na mestu tudi brez videa, da klub vidi, kam sodi (Luka: "okvir za video").
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Club video coming soon")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                )
                .frame(height: 230)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - 8) Opis kluba (pod mapo in kontakti)
    @ViewBuilder
    private var descriptionBlock: some View {
        if let d = club?.description.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Loceno besedilo od "About" v profilu (drug kljuc, da prevod ne trci s Settings > About).
                Text("About the club")
                    .font(.headline)
                Text(d)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - 2) Info block (logo + mesto/država/žanri/min age)
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

            ContactRow(label: String(localized: "Email"), value: club?.contactEmail)
            ContactRow(label: String(localized: "Phone"), value: club?.contactPhone)
            ContactRow(label: String(localized: "Instagram"), value: club?.instagram)
            ContactRow(label: String(localized: "Website"), value: club?.website)
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
            // Pretekli dogodki pridejo od najstarejsega -> obrnemo, da so najnovejsi prvi.
            popular = try await pop.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            comingSoon = try await up
        } catch {
            errorText = error.userMessage
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

// MARK: - Slideshow (do 3 slike, samodejno menjavanje, pike spodaj)
private struct ClubSlideshow: View {
    let urls: [String]
    @State private var index = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                Rectangle().opacity(0.12)
            } else if urls.count == 1 {
                slika(urls[0])
            } else {
                TabView(selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                        slika(u).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                // Samodejno menjavanje na 4 s. .task se ob izginotju pogleda preklice sam;
                // stabilnejse kot Timer.publish v stored property (ta se ob vsakem izrisu starsa ponastavi).
                .task(id: urls.count) {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if Task.isCancelled { break }
                        withAnimation(.easeInOut(duration: 0.6)) {
                            index = (index + 1) % max(urls.count, 1)
                        }
                    }
                }
            }
        }
    }

    private func slika(_ u: String) -> some View {
        Group {
            if let url = URL(string: u) {
                AsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().opacity(0.15)
                }
            } else {
                Rectangle().opacity(0.12)
            }
        }
    }
}

// MARK: - Video: tiho, v zanki, brez kontrol; dotik vklopi/izklopi zvok
private struct ClubVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var muted = true
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // brez sistemskih kontrol; predvaja se samo
                    .onDisappear {
                        player.pause()
                        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
                        endObserver = nil
                    }
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
            }

            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.5)))
                .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            muted.toggle()
            player?.isMuted = muted
        }
        .onAppear {
            if player == nil {
                let p = AVPlayer(url: url)
                p.isMuted = true
                p.actionAtItemEnd = .none
                player = p
            }
            if endObserver == nil, let p = player {
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak p] _ in
                    p?.seek(to: .zero)
                    p?.play()
                }
            }
            player?.play()
        }
    }
}
