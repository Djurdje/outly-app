import SwiftUI

/// Glavni zaslon Profila (Martin, 20. 9.): zgornji del je osebni profil — uporabnikova
/// slika, uporabnisko ime, "My Account" — tudi ce je uporabnik zaposlen v klubu (vratar,
/// manager). Zaposlitev je pod "My Clubs" (MyClubsView -> MyClubDetailView).
/// Izjema (Luka, 21. 9.): LASTNIK kluba (vloga `business`) vidi klubski profil
/// (OwnerProfileView: logo, ime, Edit your page, Dashboard, Events, My team, Settings),
/// dokler v Settings ne preklopi na osebni racun (`profilObraz`, shranjeno na napravi).
@MainActor
struct ProfileView: View {
    @AppStorage("authStage") private var authStage: String = "main"
    /// "club" = lastnik vidi klubski profil; "personal" = osebni. Velja samo za vlogo business.
    @AppStorage("profilObraz") private var obraz: String = "club"
    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }
    @State private var user: Me?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var userAvatarURL: URL? {
        guard let s = user?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Pred prvim GET /me vzamemo profil iz seje, da lastnik ne vidi najprej osebnega obraza.
    private var trenutni: Me? { user ?? session.me }
    private var jeLastnik: Bool { trenutni?.role == "business" && obraz == "club" }

    var body: some View {
        NavigationStack {
            if jeLastnik, let trenutni {
                OwnerProfileView(me: trenutni)
            } else {
                osebni
            }
        }
        // Samo onAppear (prej se .task -> vsak prikaz 2x GET /me).
        .onAppear {
            Task { await loadProfile() }
        }
        .preferredColorScheme(.dark)
    }

    private var osebni: some View {
            // Scrollable (Martin, 20. 9.): "Log out" se je pri daljsem poslovnem meniju
            // skril pod plavajoco spodnjo vrstico. Meni je zdaj za vse enak in krajsi,
            // a ScrollView ostane, da je gumb dosegljiv tudi na manjsih zaslonih.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {

                    // ===== HEADER: vedno osebni profil, nikoli klub =====
                    HStack(spacing: 25) {
                        if let url = userAvatarURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.blackColor)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.blackColor)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            if let user = user {
                                Text(user.username)
                                    .font(.title2)
                            } else if isLoading {
                                Text("Loading...")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            } else {
                                Text("Unknown user")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }

                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            NavigationLink(destination: MyAccountView()) {
                                Text("My Account")
                                    .foregroundColor(.blackColor)
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)

                    Divider()
                        .background(Color.gray)

                    // ===== MENU: isti za vsakogar; klubske funkcije so pod My Clubs =====
                    VStack(spacing: 12) {
                        NavigationLink(destination: MyClubsView()) {
                            OutlyMenuRowButton(icon: "building.2", title: "My Clubs", badge: user?.pendingInvites ?? 0)
                        }

                        // Prijatelji (Martin, 20. 9.): iskanje, prosnje, seznam. Znacka = prejete prosnje.
                        NavigationLink(destination: MyFriendsView()) {
                            OutlyMenuRowButton(icon: "person.2", title: "My Friends", badge: user?.pendingFriendRequests ?? 0)
                        }

                        NavigationLink(destination: TicketsView()) {
                            OutlyMenuRowButton(icon: "ticket", title: "Tickets")
                        }

                        NavigationLink(destination: PaymentView()) {
                            OutlyMenuRowButton(icon: "creditcard", title: "Payment")
                        }

                        NavigationLink(destination: HelpCenterView()) {
                            OutlyMenuRowButton(icon: "questionmark.circle", title: "Support")
                        }

                        NavigationLink(destination: AboutView()) {
                            OutlyMenuRowButton(icon: "info.circle", title: "About")
                        }
                    }

                    Spacer(minLength: 20)

                    Button {
                        session.logout()
                        authStage = "login"
                    } label: {
                        Text("Log out")
                            .foregroundColor(.red)
                    }
                    // Spodnji odmik zaradi plavajoce spodnje vrstice (trdo pravilo 6).
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("")
    }

    func loadProfile() async {
        guard !authToken.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let me = try await APIClient.shared.me(token: authToken)

            await MainActor.run {
                self.user = me
                self.isLoading = false
            }

        } catch let apiErr as APIError {
            if case let .requestFailed(code, _) = apiErr, code == 401 {
                await MainActor.run {
                    session.logout()
                    authStage = "login"
                }
                return
            }

            await MainActor.run {
                errorMessage = apiErr.userMessage
                isLoading = false
            }

        } catch {
            await MainActor.run {
                errorMessage = error.userMessage
                isLoading = false
            }
        }
    }
}
