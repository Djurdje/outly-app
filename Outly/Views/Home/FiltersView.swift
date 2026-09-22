import SwiftUI

/// Filtri domacega zaslona (desni del polja "Where to?"). Do 20. 9. zaslona za filtre ni
/// bilo; ta je v slogu nastavitvenih zaslonov (OutlySettingsCard, vrstice bela 8 %).
/// Vrstni red: City, Use my preferences, Music genres, Distance, Age range, Entry price.
/// "Use my preferences" ob vklopu prepise vrednosti s tistimi iz Profil -> Preferences ->
/// My preferences (UserPreferences); uporabnik jih lahko potem se rocno spremeni. Ob IZKLOPU
/// se zanri, razdalja, starost in cena vrnejo na privzete (mesto ostane) — prej so
/// prenesene vrednosti ostale aktivne (Martin, 20. 9.).
/// Distance, Age range in Entry price so od 20. 9. drsniki od-do s histogramom dejanske
/// porazdelitve prihajajocih dogodkov (OutlyRangeHistogramSlider).
struct EventFilters: Equatable {
    /// Prazno = vsa mesta.
    var city: String = ""
    /// Prazno = vsi zanri.
    var genres: Set<String> = []
    var minDistanceKm: Double = 0
    var maxDistanceKm: Double = 100
    var ageMin: Int = 16
    var ageMax: Int = 60
    var priceMinCents: Int = 0
    var priceMaxCents: Int = 10_000
    /// true = vrednosti so prisle iz "Use my preferences" (stikalo ostane vklopljeno,
    /// ko uporabnik znova odpre Filtre).
    var izMojihNastavitev: Bool = false

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
        if let d = razdaljaKm, d < minDistanceKm || d > maxDistanceKm { return false }
        return true
    }
}

@MainActor
struct FiltersView: View {
    @Binding var filters: EventFilters
    /// Mesta iz seznama klubov (HomeView), brez podvajanja.
    let cities: [String]
    /// Prihajajoci dogodki in klubi (HomeView) za histograme; razdalja do kluba (nil = ne vemo).
    var events: [APIEvent] = []
    var clubsById: [Int: APIClub] = [:]
    var distanceKm: (APIClub) -> Double? = { _ in nil }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var prefs: UserPreferences
    @EnvironmentObject private var session: SessionStore

    @State private var osnutek: EventFilters
    @State private var useMyPreferences = false
    @State private var genres: [String] = []
    @State private var isLoadingGenres = true
    @State private var genresError: String?

    // Drsniki delajo z Double.
    @State private var distanceMin: Double = 0
    @State private var distanceMax: Double = 100
    @State private var ageMin: Double = 16
    @State private var ageMax: Double = 60
    @State private var priceMin: Double = 0
    @State private var priceMax: Double = 100

    private static let razponRazdalje: ClosedRange<Double> = 0...100
    private static let razponStarosti: ClosedRange<Double> = 16...60
    private static let razponCene: ClosedRange<Double> = 0...100

    init(filters: Binding<EventFilters>, cities: [String],
         events: [APIEvent] = [], clubsById: [Int: APIClub] = [:],
         distanceKm: @escaping (APIClub) -> Double? = { _ in nil }) {
        self._filters = filters
        self.cities = cities
        self.events = events
        self.clubsById = clubsById
        self.distanceKm = distanceKm
        self._osnutek = State(initialValue: filters.wrappedValue)
        self._useMyPreferences = State(initialValue: filters.wrappedValue.izMojihNastavitev)
    }

    var body: some View {
        // Prikazan kot fullScreenCover (od 22. 9.), zato ima svoj NavigationStack (ni potisnjen pogled).
        // Ozadje je zamegljen zamrznjen domaci zaslon — posnetek pride iz okolja (posnetekDoma),
        // narise ga .outlyOzadje() spodaj, enako kot pri Search in Profile.
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
                            Button { Task { await loadGenres() } } label: {
                                OutlyMenuRowButton(icon: "exclamationmark.triangle", title: genresError ?? String(localized: "Could not load genres."),
                                                   value: String(localized: "Try again"))
                            }
                            .buttonStyle(.plain)
                        } else {
                            OutlyGenreGrid(genres: genres, selected: $osnutek.genres)
                        }
                    }

                    OutlySettingsCard("Distance") {
                        OutlyRangeHistogramSlider(counts: histogramRazdalje, range: Self.razponRazdalje,
                                                  lower: $distanceMin, upper: $distanceMax,
                                                  label: { PrefBesedila.km($0) })
                            .padding(.horizontal, 4)
                    }

                    OutlySettingsCard("Age range") {
                        OutlyRangeHistogramSlider(counts: histogramStarosti, range: Self.razponStarosti,
                                                  lower: $ageMin, upper: $ageMax,
                                                  label: { PrefBesedila.leta($0) })
                            .padding(.horizontal, 4)
                    }

                    OutlySettingsCard("Entry price") {
                        OutlyRangeHistogramSlider(counts: histogramCene, range: Self.razponCene,
                                                  lower: $priceMin, upper: $priceMax,
                                                  label: { PrefBesedila.evriKratko($0) })
                            .padding(.horizontal, 4)
                    }

                    spodnjaGumba
                        .padding(.top, 6)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .outlyOzadje()
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
            if vklop { naloziMojeNastavitve() } else { odstraniMojeNastavitve() }
        }
    }

    // MARK: - Spodnja gumba: Reset (obroba) + Apply filters (modra)
    private var spodnjaGumba: some View {
        HStack(spacing: 12) {
            Button {
                osnutek = .privzeti
                useMyPreferences = false
                naloziDrsnike(iz: osnutek)
            } label: {
                Text("Reset")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 128, height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                uporabi()
            } label: {
                Text("Apply filters")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.outlyBlue))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Histogrami (dejanska porazdelitev prihajajocih dogodkov)

    private enum Dimenzija { case razdalja, starost, cena }

    /// Filtri, kot so trenutno nastavljeni na zaslonu (osnutek + drsniki), brez dimenzije `brez`,
    /// da histogram te dimenzije kaze vse, kar ostali filtri se pustijo.
    private func trenutniFiltri(brez d: Dimenzija) -> EventFilters {
        var f = osnutek
        f.minDistanceKm = d == .razdalja ? 0 : distanceMin
        f.maxDistanceKm = d == .razdalja ? .infinity : distanceMax
        f.ageMin = d == .starost ? Int(Self.razponStarosti.lowerBound) : Int(ageMin)
        f.ageMax = d == .starost ? Int.max : Int(ageMax)
        f.priceMinCents = d == .cena ? 0 : Int(priceMin) * 100
        f.priceMaxCents = d == .cena ? Int.max : Int(priceMax) * 100
        return f
    }

    /// Dogodki, ki jih ostali filtri (mesto, zanri, druga dva drsnika) se pustijo; z razdaljo do kluba.
    private func kandidati(brez d: Dimenzija) -> [(event: APIEvent, razdalja: Double?)] {
        let f = trenutniFiltri(brez: d)
        return events.compactMap { e -> (event: APIEvent, razdalja: Double?)? in
            guard f.ustreza(e) else { return nil }
            let club = clubsById[e.clubId]
            let razdalja = club.flatMap { distanceKm($0) }
            if let club, !f.ustreza(club, razdaljaKm: razdalja) { return nil }
            return (e, razdalja)
        }
    }

    /// Koliko dogodkov je na posameznih razdaljah od uporabnika (brez lokacije = brez stolpcev).
    private var histogramRazdalje: [Int] {
        let vrednosti = kandidati(brez: .razdalja).compactMap { $0.razdalja }
        return Histogram.prestej(vrednosti, range: Self.razponRazdalje, bins: 25)
    }

    /// Porazdelitev po starostni omejitvi dogodka (min_age; brez omejitve steje kot spodnja meja).
    private var histogramStarosti: [Int] {
        let vrednosti = kandidati(brez: .starost).map { max(Double($0.event.minAge), Self.razponStarosti.lowerBound) }
        return Histogram.prestej(vrednosti, range: Self.razponStarosti, bins: 22)
    }

    /// Porazdelitev po ceni vstopnice (dogodki brez cene na Outlyju se ne stejejo).
    private var histogramCene: [Int] {
        let vrednosti = kandidati(brez: .cena).compactMap { $0.event.ticketPriceCents.map { Double($0) / 100 } }
        return Histogram.prestej(vrednosti, range: Self.razponCene, bins: 25)
    }

    // MARK: - Drsniki <-> filtri

    private func naloziDrsnike(iz f: EventFilters) {
        distanceMin = min(max(f.minDistanceKm, Self.razponRazdalje.lowerBound), Self.razponRazdalje.upperBound)
        distanceMax = min(max(f.maxDistanceKm, Self.razponRazdalje.lowerBound), Self.razponRazdalje.upperBound)
        ageMin = min(max(Double(f.ageMin), Self.razponStarosti.lowerBound), Self.razponStarosti.upperBound)
        ageMax = min(max(Double(f.ageMax), Self.razponStarosti.lowerBound), Self.razponStarosti.upperBound)
        priceMin = min(max(Double(f.priceMinCents / 100), Self.razponCene.lowerBound), Self.razponCene.upperBound)
        priceMax = min(max(Double(f.priceMaxCents / 100), Self.razponCene.lowerBound), Self.razponCene.upperBound)
    }

    /// "Use my preferences" VKLOP: prepise zanre, razdaljo, starost in ceno z vrednostmi iz profila.
    private func naloziMojeNastavitve() {
        let lokalni = prefs.savedGenres
        let zanri = lokalni.isEmpty ? (session.me?.genres ?? []) : lokalni
        osnutek.genres = Set(zanri)
        osnutek.minDistanceKm = 0
        osnutek.maxDistanceKm = prefs.maxDistanceKm
        osnutek.ageMin = prefs.ageMin
        osnutek.ageMax = prefs.ageMax
        osnutek.priceMinCents = prefs.priceMinCents
        osnutek.priceMaxCents = prefs.priceMaxCents
        osnutek.izMojihNastavitev = true
        naloziDrsnike(iz: osnutek)
    }

    /// "Use my preferences" IZKLOP: kar je stikalo nastavilo, se vrne na privzeto (mesto ostane).
    private func odstraniMojeNastavitve() {
        let privzeti = EventFilters.privzeti
        osnutek.genres = privzeti.genres
        osnutek.minDistanceKm = privzeti.minDistanceKm
        osnutek.maxDistanceKm = privzeti.maxDistanceKm
        osnutek.ageMin = privzeti.ageMin
        osnutek.ageMax = privzeti.ageMax
        osnutek.priceMinCents = privzeti.priceMinCents
        osnutek.priceMaxCents = privzeti.priceMaxCents
        osnutek.izMojihNastavitev = false
        naloziDrsnike(iz: osnutek)
    }

    private func uporabi() {
        osnutek.minDistanceKm = distanceMin
        osnutek.maxDistanceKm = distanceMax
        osnutek.ageMin = Int(ageMin)
        osnutek.ageMax = Int(ageMax)
        osnutek.priceMinCents = Int(priceMin) * 100
        osnutek.priceMaxCents = Int(priceMax) * 100
        osnutek.izMojihNastavitev = useMyPreferences
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
