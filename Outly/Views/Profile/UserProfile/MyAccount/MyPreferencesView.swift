import SwiftUI

/// Preferences -> My preferences: privzeti zanri, razdalja, starostni razpon in razpon
/// cene vstopnice. Shranjeno sproti na napravi (UserPreferences / @AppStorage), brez
/// gumba Shrani. Uporabi jih "Use my preferences" na zaslonu Filtri.
/// Slog kot NotificationsView: naslov 22 bold, kartice OutlySettingsCard, vrstice bela 8 %.
@MainActor
struct MyPreferencesView: View {
    @EnvironmentObject private var prefs: UserPreferences
    @EnvironmentObject private var session: SessionStore

    @State private var genres: [String] = []
    @State private var selected: Set<String> = []
    @State private var isLoadingGenres = true
    @State private var genresError: String?

    // Drsniki delajo z Double; AppStorage hrani Int/Double.
    @State private var distance: Double = 20
    @State private var ageMin: Double = 18
    @State private var ageMax: Double = 30
    @State private var priceMin: Double = 0
    @State private var priceMax: Double = 30

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("My preferences")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                OutlySettingsCard("Music genres") {
                    if isLoadingGenres {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                            .frame(height: 56)
                    } else if genres.isEmpty {
                        OutlySettingsRow(icon: "exclamationmark.triangle", title: genresError ?? String(localized: "Could not load genres."),
                                         action: String(localized: "Try again"), onTap: { Task { await loadGenres() } })
                    } else {
                        OutlyGenreGrid(genres: genres, selected: $selected)
                    }
                }

                OutlySettingsCard("Distance") {
                    OutlySliderRow(title: "Max distance", valueText: PrefBesedila.km(distance), value: $distance, range: 1...100)
                }

                OutlySettingsCard("Age range") {
                    OutlySliderRow(title: "From", valueText: PrefBesedila.leta(ageMin), value: $ageMin, range: 16...60)
                    OutlySliderRow(title: "To", valueText: PrefBesedila.leta(ageMax), value: $ageMax, range: 16...60)
                }

                OutlySettingsCard("Entry price") {
                    OutlySliderRow(title: "From", valueText: PrefBesedila.cena(Int(priceMin) * 100), value: $priceMin, range: 0...100)
                    OutlySliderRow(title: "To", valueText: PrefBesedila.cena(Int(priceMax) * 100), value: $priceMax, range: 0...100)
                }

                Text("Saved on this device. Turn on “Use my preferences” in Filters to apply them.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear(perform: naloziIzShrambe)
        .task { await loadGenres() }
        // Sprotno shranjevanje (min/max se ne smeta prekrizati).
        .onChange(of: selected) { _, nov in prefs.savedGenres = genres.filter { nov.contains($0) } }
        .onChange(of: distance) { _, nov in prefs.maxDistanceKm = nov }
        .onChange(of: ageMin) { _, nov in
            if nov > ageMax { ageMax = nov }
            prefs.ageMin = Int(nov)
        }
        .onChange(of: ageMax) { _, nov in
            if nov < ageMin { ageMin = nov }
            prefs.ageMax = Int(nov)
        }
        .onChange(of: priceMin) { _, nov in
            if nov > priceMax { priceMax = nov }
            prefs.priceMinCents = Int(nov) * 100
        }
        .onChange(of: priceMax) { _, nov in
            if nov < priceMin { priceMin = nov }
            prefs.priceMaxCents = Int(nov) * 100
        }
    }

    private func naloziIzShrambe() {
        distance = prefs.maxDistanceKm
        ageMin = Double(prefs.ageMin)
        ageMax = Double(prefs.ageMax)
        priceMin = Double(prefs.priceMinCents / 100)
        priceMax = Double(prefs.priceMaxCents / 100)
    }

    private func loadGenres() async {
        isLoadingGenres = true
        genresError = nil
        defer { isLoadingGenres = false }
        do {
            let list = try await APIClient.shared.fetchGenres()
            genres = list
            // Lokalno shranjeni zanri; ce jih ni, zanri z racuna (Me.genres).
            let lokalni = prefs.savedGenres
            let izhodisce = lokalni.isEmpty ? (session.me?.genres ?? []) : lokalni
            selected = Set(izhodisce).intersection(list)
        } catch {
            genres = []
            genresError = error.userMessage
        }
    }
}
