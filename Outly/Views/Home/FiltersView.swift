import SwiftUI

/// Filtri domacega zaslona (desni del polja "Where to?"). Do 20. 9. zaslona za filtre ni
/// bilo; ta je v slogu nastavitvenih zaslonov (OutlySettingsCard, vrstice bela 8 %).
/// Vrstni red: City, Use my preferences, Music genres, Distance, Age range, Entry price.
/// "Use my preferences" ob vklopu prepise vrednosti s tistimi iz Profil -> Preferences ->
/// My preferences (UserPreferences); uporabnik jih lahko potem se rocno spremeni.
struct EventFilters: Equatable {
    /// Prazno = vsa mesta.
    var city: String = ""
    /// Prazno = vsi zanri.
    var genres: Set<String> = []
    var maxDistanceKm: Double = 100
    var ageMin: Int = 16
    var ageMax: Int = 60
    var priceMinCents: Int = 0
    var priceMaxCents: Int = 10_000

    static let privzeti = EventFilters()

    /// true = uporabnik je kaj spremenil (pika na ikoni filtra).
    var jeAktiven: Bool { self != EventFilters.privzeti }

    /// Dogodek ustreza zanrom, starosti in ceni. Mesto in razdalja se preverjata prek kluba.
    func ustreza(_ e: APIEvent) -> Bool {
        if !genres.isEmpty {
            let evGenres = Set(e.genres.map { $0.lowercased() })
            if evGenres.isDisjoint(with: Set(genres.map { $0.lowercased() })) { return false }
        }
        if e.minAge > ageMax { return false }
        if let c = e.ticketPriceCents, c < priceMinCents || c > priceMaxCents { return false }
        return true
    }

    /// Klub ustreza mestu, zanrom in razdalji (nil razdalja = ne vemo, pustimo).
    func ustreza(_ c: APIClub, razdaljaKm: Double?) -> Bool {
        if !city.isEmpty, c.city.caseInsensitiveCompare(city) != .orderedSame { return false }
        if !genres.isEmpty {
            let clubGenres = Set(c.genres.map { $0.lowercased() })
            if !clubGenres.isEmpty && clubGenres.isDisjoint(with: Set(genres.map { $0.lowercased() })) { return false }
        }
        if let d = razdaljaKm, d > maxDistanceKm { return false }
        return true
    }
}

@MainActor
struct FiltersView: View {
    @Binding var filters: EventFilters
    /// Mesta iz seznama klubov (HomeView), brez podvajanja.
    let cities: [String]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var prefs: UserPreferences
    @EnvironmentObject private var session: SessionStore

    @State private var osnutek: EventFilters
    @State private var useMyPreferences = false
    @State private var genres: [String] = []
    @State private var isLoadingGenres = true
    @State private var genresError: String?

    // Drsniki delajo z Double.
    @State private var distance: Double = 100
    @State private var ageMin: Double = 16
    @State private var ageMax: Double = 60
    @State private var priceMin: Double = 0
    @State private var priceMax: Double = 100

    init(filters: Binding<EventFilters>, cities: [String]) {
        self._filters = filters
        self.cities = cities
        self._osnutek = State(initialValue: filters.wrappedValue)
    }

    var body: some View {
        // Prikazan kot sheet, zato ima svoj NavigationStack (ni potisnjen pogled).
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Filters")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    OutlySettingsCard("City") {
                        Menu {
                            Button { osnutek.city = "" } label: {
                                if osnutek.city.isEmpty { Label("All cities", systemImage: "checkmark") } else { Text("All cities") }
                            }
                            ForEach(cities, id: \.self) { mesto in
                                Button { osnutek.city = mesto } label: {
                                    if osnutek.city == mesto { Label(mesto, systemImage: "checkmark") } else { Text(mesto) }
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 24)
                                Text(osnutek.city.isEmpty ? String(localized: "All cities") : osnutek.city)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                            .contentShape(Rectangle())
                        }
                    }

                    OutlyToggleDetailRow(icon: "person.crop.circle.badge.checkmark",
                                         title: "Use my preferences",
                                         subtitle: "Apply preferences from your profile",
                                         isOn: $useMyPreferences)

                    OutlySettingsCard("Music genres") {
                        if isLoadingGenres {
                            HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                                .frame(height: 56)
                        } else if genres.isEmpty {
                            OutlySettingsRow(icon: "exclamationmark.triangle", title: genresError ?? String(localized: "Could not load genres."),
                                             action: String(localized: "Try again"), onTap: { Task { await loadGenres() } })
                        } else {
                            OutlyGenreGrid(genres: genres, selected: $osnutek.genres)
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

                    OutlyPrimaryButton(title: "Show results") {
                        uporabi()
                    }
                    .padding(.top, 6)

                    Button {
                        osnutek = .privzeti
                        useMyPreferences = false
                        naloziDrsnike(iz: osnutek)
                    } label: {
                        Text("Reset filters")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { naloziDrsnike(iz: osnutek) }
        .task { await loadGenres() }
        .onChange(of: useMyPreferences) { _, vklop in
            if vklop { naloziMojeNastavitve() }
        }
        .onChange(of: ageMin) { _, nov in if nov > ageMax { ageMax = nov } }
        .onChange(of: ageMax) { _, nov in if nov < ageMin { ageMin = nov } }
        .onChange(of: priceMin) { _, nov in if nov > priceMax { priceMax = nov } }
        .onChange(of: priceMax) { _, nov in if nov < priceMin { priceMin = nov } }
    }

    private func naloziDrsnike(iz f: EventFilters) {
        distance = f.maxDistanceKm
        ageMin = Double(f.ageMin)
        ageMax = Double(f.ageMax)
        priceMin = Double(f.priceMinCents / 100)
        priceMax = Double(f.priceMaxCents / 100)
    }

    /// "Use my preferences": prepise zanre, razdaljo, starost in ceno z vrednostmi iz profila.
    private func naloziMojeNastavitve() {
        let lokalni = prefs.savedGenres
        let zanri = lokalni.isEmpty ? (session.me?.genres ?? []) : lokalni
        osnutek.genres = Set(zanri)
        osnutek.maxDistanceKm = prefs.maxDistanceKm
        osnutek.ageMin = prefs.ageMin
        osnutek.ageMax = prefs.ageMax
        osnutek.priceMinCents = prefs.priceMinCents
        osnutek.priceMaxCents = prefs.priceMaxCents
        naloziDrsnike(iz: osnutek)
    }

    private func uporabi() {
        osnutek.maxDistanceKm = distance
        osnutek.ageMin = Int(ageMin)
        osnutek.ageMax = Int(ageMax)
        osnutek.priceMinCents = Int(priceMin) * 100
        osnutek.priceMaxCents = Int(priceMax) * 100
        filters = osnutek
        dismiss()
    }

    private func loadGenres() async {
        isLoadingGenres = true
        genresError = nil
        defer { isLoadingGenres = false }
        do {
            genres = try await APIClient.shared.fetchGenres()
        } catch {
            genres = []
            genresError = error.userMessage
        }
    }
}
