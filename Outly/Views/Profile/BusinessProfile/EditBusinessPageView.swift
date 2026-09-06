import SwiftUI

struct EditBusinessPageView: View {
    let clubId: Int?
    // header data (loaded)
    @State private var clubName: String = ""
    @State private var clubLogoUrl: String?
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case clubInfo
        case passwordSecurity
        case switchToPersonal
        case withdraw
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 20) {

                header

                Divider()
                    .opacity(0.25)

                VStack(spacing: 12) {
                    menuRow(icon: "person", title: "Club info") {
                        path.append(Route.clubInfo)
                    }

                    menuRow(icon: "lock", title: "Password and security") {
                        path.append(Route.passwordSecurity)
                    }

                    menuRow(icon: "arrow.up.right", title: "Switch to personal account") {
                        path.append(Route.switchToPersonal)
                    }
                }
                
                Divider()
                    .background(Color.gray)
                    .padding(.horizontal, 15)

                VStack(spacing: 12) {
                    menuRow(icon: "dollarsign", title: "Withdraw") {
                        path.append(Route.withdraw)
                    }
                }

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
                    Text("Password and security")
                        .navigationTitle("Password and security")

                case .switchToPersonal:
                    Text("Switch to personal account")
                        .navigationTitle("Switch account")

                case .withdraw:
                    Text("Withdraw")
                        .navigationTitle("Withdraw")
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

    // MARK: - Clickable row wrapper

    private func menuRow(icon: String, title: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            OutlyMenuRowButton(icon: icon, title: title)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Load club name + logo using existing APIClub model

    private func loadHeaderClubInfo() async {
        guard let clubId else { return }

        do {
            guard let url = URL(string: "https://outly-backend-roy3.onrender.com/clubs") else { return }

            let (data, _) = try await URLSession.shared.data(from: url)

            let clubs = try JSONDecoder().decode([APIClub].self, from: data)

            if let club = clubs.first(where: { $0.id == clubId }) {
                await MainActor.run {
                    self.clubName = club.name
                    self.clubLogoUrl = club.logoUrl
                }
            }
        } catch {
            // optional: print(error)
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
