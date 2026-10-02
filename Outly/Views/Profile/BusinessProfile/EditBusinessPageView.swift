import SwiftUI

/// "Edit your page" v lastnikovem profilu: glava kluba + Club info in Password and security.
/// Lezi v NavigationStacku ProfileView — brez lastnega (trdo pravilo 4).
///
/// Popravek 22. 9. 2026 (Martin, posnetek zaslona z buildom 64/66): dotik na "Club info" je
/// potisnil PRAZEN zaslon, glava tega pogleda pa se je hkrati vrnila na "Your club" — torej
/// se je cel sklad ponovno zgradil. Vzrok: ta pogled je mesal DVA nacina navigacije —
/// sam je bil potisnjen z `NavigationLink { destination }` (OwnerProfileView), znotraj sebe
/// pa je uporabljal `NavigationLink(value:)` + `.navigationDestination(for:)`. V iOS 17 to
/// v istem skladu obcasno potisne prazen zaslon in ponastavi stanje potisnjenega pogleda.
/// Zdaj sta oba gumba navadna `NavigationLink { destination }`, kot povsod drugje v aplikaciji,
/// glava pa se ohrani, ker jo hranimo v `@State` in nalozimo samo enkrat (`nalozeno`).
@MainActor
struct EditBusinessPageView: View {
    let clubId: Int?
    @EnvironmentObject private var session: SessionStore
    // header data (loaded)
    @State private var clubName: String = ""
    @State private var clubLogoUrl: String?
    /// Glavo naloz imo enkrat: ob vrnitvi s Club info se `.task` sicer pozene znova in
    /// ime za trenutek pade nazaj na "Your club".
    @State private var nalozeno = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            header

            Divider()
                .opacity(0.25)

            VStack(spacing: 12) {
                NavigationLink {
                    ClubInfoView(clubId: clubId)
                } label: {
                    OutlyMenuRowButton(icon: "person", title: "Club info")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PasswordSecurityView()
                } label: {
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
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !nalozeno else { return }
            await loadHeaderClubInfo()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ClubLogoView(urlString: clubLogoUrl)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(clubName.isEmpty ? String(localized: "Your club") : clubName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Edit your page")
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundColor(.outlyBlue)
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
            nalozeno = true
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

            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                OutlyAsyncImage(url: url) { phase in
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
                Image(systemName: "building.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
