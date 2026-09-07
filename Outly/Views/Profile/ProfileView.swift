import SwiftUI

struct BusinessClub: Decodable {
    let id: Int
    let owner_user_id: Int
    let name: String
    let logo_url: String?
}

struct ProfileView: View {
    @AppStorage("authStage") private var authStage: String = "main"
    @EnvironmentObject private var session: SessionStore
    private var authToken: String { session.token }
    @State private var user: Me?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var businessClub: BusinessClub?

    private var userAvatarURL: URL? {
        guard let s = user?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {

                // ===== HEADER =====
                HStack(spacing: 25) {

                    // Business: pokaži club logo (kot prej)
                    if user?.role == "business",
                       let logo = businessClub?.logo_url,
                       let url = URL(string: logo) {

                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Image(systemName: "building.2.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.blackColor)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    } else {
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
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let user = user {

                            if user.role == "business" {
                                Text(businessClub?.name ?? "Your club")
                                    .font(.title2)
                            } else {
                                Text(user.username)
                                    .font(.title2)
                            }

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

                        if user?.role == "business" {
                            NavigationLink(destination: EditBusinessPageView(clubId: businessClub?.id)) {
                                Text("Edit your page")
                                    .foregroundColor(.blackColor)
                            }
                        } else {
                            NavigationLink(destination: MyAccountView()) {
                                Text("My Account")
                                    .foregroundColor(.blackColor)
                            }
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Divider()
                    .background(Color.gray)
                    .padding(.horizontal, 15)

                // ===== MENU =====
                VStack(spacing: 12) {

                    if user?.role == "business" {

                        NavigationLink(destination: BusinessDashboardView()) {
                            OutlyMenuRowButton(icon: "chart.bar", title: "Dashboard")
                        }

                        NavigationLink(destination: BusinessEventsView()) {
                            OutlyMenuRowButton(icon: "calendar", title: "Events")
                        }

                        NavigationLink(destination: BusinessTeamView()) {
                            OutlyMenuRowButton(icon: "person.2", title: "Team")
                        }

                        NavigationLink(destination: BusinessSettingsView()) {
                            OutlyMenuRowButton(icon: "gearshape", title: "Settings")
                        }

                    } else {

                        NavigationLink(destination: MyClubsView()) {
                            OutlyMenuRowButton(icon: "building.2", title: "My Clubs")
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
                }

                Spacer()

                Button {
                    session.logout()
                    authStage = "login"
                } label: {
                    Text("Log out")
                        .foregroundColor(.red)
                }

            }
            .padding()
            .navigationTitle("")
        }
        .task {
            await loadProfile()
            await loadBusinessClubIfNeeded()
        }
        .onAppear {
            Task {
                await loadProfile()
                await loadBusinessClubIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
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
                errorMessage = apiErr.localizedDescription
                isLoading = false
            }

        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadBusinessClubIfNeeded() async {
        guard let user = user, user.role == "business" else { return }

        do {
            let urlString = "https://outly-backend-roy3.onrender.com/clubs"
            guard let url = URL(string: urlString) else { return }

            let (data, _) = try await URLSession.shared.data(from: url)
            let clubs = try JSONDecoder().decode([BusinessClub].self, from: data)

            await MainActor.run {
                self.businessClub = clubs.first(where: { $0.owner_user_id == user.id })
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
