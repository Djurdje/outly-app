import SwiftUI

@MainActor
struct EditBusinessPageView: View {
    let clubId: Int?
    @EnvironmentObject private var session: SessionStore
    // header data (loaded)
    @State private var clubName: String = ""
    @State private var clubLogoUrl: String?

    enum Route: Hashable {
        case clubInfo
        case passwordSecurity
    }

    var body: some View {
        // Potisnjen na ProfileView-ov NavigationStack; navigationDestination(for:) deluje
        // na starsevskem skladu, zato tu ni lastnega NavigationStacka.
        Group {
            VStack(alignment: .leading, spacing: 20) {

                header

                Divider()
                    .opacity(0.25)

                VStack(spacing: 12) {
                    NavigationLink(value: Route.clubInfo) {
                        OutlyMenuRowButton(icon: "person", title: "Club info")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: Route.passwordSecurity) {
                        OutlyMenuRowButton(icon: "lock", title: "Password and security")
                    }
                    .buttonStyle(.plain)

                    // "Switch to personal account" odstranjen: backend nima poti za
                    // spremembo vloge; gumb ni delal nic.
                }

                // "Withdraw" odstranjen: v aplikaciji ni denarnice (odlocitev: brez izdajanja
                // e-denarja po ZPlaSSIED). Izplacila klubom gredo neposredno prek Stripe Connect.

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .clubInfo:
                    ClubInfoView(clubId: clubId)
                    
                case .passwordSecurity:
                    PasswordSecurityView()
                }
            }
            .task {
                await loadHeaderClubInfo()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ClubLogoView(urlString: clubLogoUrl)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(clubName.isEmpty ? "Your club" : clubName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Edit your page")
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundColor(.blackColor)
            }

            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: - Load club name + logo using existing APIClub model

    private func loadHeaderClubInfo() async {
        guard !session.token.isEmpty else { return }
        do {
            let club = try await APIClient.shared.fetchMyBusinessClub(token: session.token)
            clubName = club.name
            clubLogoUrl = club.logoUrl
        } catch {
            // Glava ostane "Your club"; podrobno napako pokaze ClubInfoView.
        }
    }
}

// MARK: - Logo view

private struct ClubLogoView: View {
    let urlString: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().scaleEffect(0.9)

                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))

                    @unknown default:
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
