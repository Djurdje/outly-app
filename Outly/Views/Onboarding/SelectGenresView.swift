import SwiftUI

/// Figma: "complete acc 2" (424:1433). Cipi v treh stolpcih, izbrani so modri.
/// Seznam pride iz GET /genres (21 zanrov); ob "Complete" gre PATCH /me { genres }.
/// Streznik nato nastavi onboarded_at in AuthGateView spusti uporabnika v aplikacijo.
/// Zanri so neobvezni: »Skip for later« poslje samo { complete_onboarding: true } (brez zanrov); »Complete« poslje zanre
/// in complete_onboarding: true. Pri urejanju (isEditing) se complete_onboarding ne posilja in »Skip for later« ni prikazan.
@MainActor
struct SelectGenresView: View {
    /// true = urejanje iz "Personal info": po shranjevanju se zaslon zapre.
    var isEditing: Bool = false

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var genres: [String] = []
    @State private var selected: Set<String> = []
    @State private var isLoadingList = true
    @State private var isSaving = false
    @State private var isSkipping = false
    @State private var message: String?

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Color.outlyBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 30)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Select your genre")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(.white)

                        if isLoadingList {
                            HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                                .padding(.vertical, 30)
                        } else if genres.isEmpty {
                            VStack(spacing: 10) {
                                Text(message ?? String(localized: "Could not load genres."))
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                                Button("Try again") { Task { await loadGenres() } }
                                    .foregroundColor(.outlyBlue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(genres, id: \.self) { g in
                                    GenreChip(title: GenreNames.display(g), isSelected: selected.contains(g)) {
                                        if selected.contains(g) { selected.remove(g) } else { selected.insert(g) }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }

                        if let message, !genres.isEmpty {
                            Text(message)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                        }

                        OutlyPrimaryButton(title: isSaving ? "Saving..." : (isEditing ? "Save" : "Complete"), isLoading: isSaving) {
                            Task { await save() }
                        }
                        .disabled(isSaving || isSkipping || selected.isEmpty || genres.isEmpty)
                        .opacity(selected.isEmpty ? 0.6 : 1)
                        .padding(.top, 30)

                        if !isEditing {
                            // Sekundarno dejanje: navadno besedilo, ne modro (modra samo na glavnem gumbu).
                            Button {
                                Task { await save(preskoci: true) }
                            } label: {
                                HStack(spacing: 8) {
                                    if isSkipping { ProgressView().tint(Color.outlyMuted) }
                                    Text("Skip for later")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.outlyMuted)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving || isSkipping)
                        }
                    }
                    .padding(22)
                    .background(Color.outlyCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 28)

                    Spacer(minLength: 60)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.outlyBackground, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await loadGenres() }
    }

    private func loadGenres() async {
        isLoadingList = true
        message = nil
        defer { isLoadingList = false }
        do {
            let list = try await APIClient.shared.fetchGenres()
            genres = list
            // Ce je uporabnik ze imel zanre (npr. ureja profil), jih oznacimo.
            if let mine = session.me?.genres { selected = Set(mine).intersection(list) }
        } catch {
            genres = []
            message = error.userMessage
        }
    }

    /// `preskoci`: »Skip for later« — brez zanrov in brez zahteve po vsaj enem; streznik z complete_onboarding nastavi onboarded_at.
    private func save(preskoci: Bool = false) async {
        message = nil
        if !preskoci {
            guard !selected.isEmpty else { message = String(localized: "Select at least one genre."); return }
        }
        if preskoci { isSkipping = true } else { isSaving = true }
        defer { isSaving = false; isSkipping = false }
        do {
            var update = APIClient.MeUpdate()
            if !preskoci {
                update.genres = genres.filter { selected.contains($0) }  // ohrani vrstni red streznika
            }
            if !isEditing { update.completeOnboarding = true }
            let me = try await APIClient.shared.updateMe(token: session.token, update)
            session.me = me
            if isEditing { dismiss(); return }
            if !me.isOnboarded {
                // Streznik zahteva datum rojstva + vsaj en zanr. Ce se vedno ni dokoncano,
                // manjka datum rojstva (uporabnik je prisel sem po drugi poti).
                message = String(localized: "Please fill in your date of birth on the previous step.")
            }
            // Ce je isOnboarded, AuthGateView sam preklopi na MainTabView.
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }
}

/// Cip zanra (moder = izbran). Deljen s Filtri in My preferences, zato ni private.
struct GenreChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(isSelected ? .white : .outlyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                // Neizbran: samo rob, brez ozadja (Martin, 22. 9. 2026). Izbran: moder.
                .background(
                    Capsule().fill(isSelected ? Color.outlyBlue : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.55), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Prikazna imena zanrov. Kljuci so tocno tisti iz backenda (ZANRI v index.js).
enum GenreNames {
    private static let map: [String: String] = [
        "electronic": "Electronic", "hiphop": "Hip hop", "pop": "Pop", "rnb": "R&B",
        "rock": "Rock", "metal": "Metal", "punk": "Punk", "afrobeat": "Afrobeat",
        "balkan": "Balkan", "latino": "Latino", "country": "Country", "hardcore": "Hardcore",
        "70s": "70s", "80s": "80s", "90s": "90s", "rap": "Rap", "2000s": "2000s",
        "house": "House", "garage": "Garage", "trap": "Trap", "techno": "Techno",
    ]
    static func display(_ key: String) -> String { map[key] ?? key.capitalized }
}
