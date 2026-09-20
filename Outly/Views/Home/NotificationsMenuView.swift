import SwiftUI

/// Spustni meni obvestil pod zvoncem na domacem zaslonu (Martin, 20. 9. 2026): prej je
/// zvonec vodil na My Clubs, kar je bilo narobe. Meni lezi cez HomeView (overlay), zapre se
/// z dotikom zunaj. Vsebina: vabila v ekipo kluba (-> ClubInvitesView, kjer se sprejme)
/// in prosnje za prijateljstvo (-> MyFriendsView). Sprejem se ne zgodi tu — dejanje s
/// posledicami ostane na zaslonu, ki ga ze ima. Potisnih obvestil (APNs) se ni.
/// Lezi znotraj NavigationStack domacega zaslona, zato NavigationLink dela.
struct NotificationsMenuView: View {
    @Binding var invites: [MyInvite]
    let friendRequests: [FriendRequest]
    let isLoading: Bool
    /// Zapre meni (pred navigacijo in ob dotiku zunaj).
    var onClose: () -> Void
    /// Po sprejemu vabila v ekipo (ime kluba) — HomeView osvezi profil.
    var onJoined: (String) -> Void

    private var jePrazno: Bool { invites.isEmpty && friendRequests.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if isLoading { ProgressView().tint(.white).scaleEffect(0.8) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if jePrazno && !isLoading {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.45))
                    Text("No new notifications")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 6) {
                    ForEach(invites) { v in
                        NavigationLink {
                            ClubInvitesView(invites: $invites, onJoined: onJoined)
                        } label: {
                            vrstica(slika: .klub(v.clubLogoUrl),
                                    naslov: String(localized: "\(v.clubName) invited you to work as \(v.roleLabel)"),
                                    podnaslov: String(localized: "Open to accept or reject"))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { onClose() })
                    }
                    ForEach(friendRequests) { r in
                        NavigationLink {
                            MyFriendsView()
                        } label: {
                            vrstica(slika: .oseba(r.user.avatarUrl),
                                    naslov: String(localized: "\(r.user.username) wants to be your friend"),
                                    podnaslov: String(localized: "Open My friends to accept"))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { onClose() })
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Divider().background(Color.white.opacity(0.12))

            HStack(spacing: 0) {
                NavigationLink { MyClubsView() } label: {
                    noga("My Clubs", ikona: "building.2")
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { onClose() })

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 22)

                NavigationLink { MyFriendsView() } label: {
                    noga("My Friends", ikona: "person.2")
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { onClose() })
            }
            .frame(height: 44)
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 18/255, green: 20/255, blue: 28/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
    }

    private enum Slika { case klub(String), oseba(String?) }

    private func vrstica(slika: Slika, naslov: String, podnaslov: String) -> some View {
        HStack(spacing: 10) {
            switch slika {
            case .klub(let url):
                Group {
                    if !url.isEmpty, let u = URL(string: url) {
                        AsyncImage(url: u) { img in
                            Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                        } placeholder: {
                            Rectangle().fill(Color.white.opacity(0.1))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 9).fill(Color.outlyBlue.opacity(0.2))
                            .overlay(Image(systemName: "building.2").font(.system(size: 14)).foregroundColor(.outlyBlue))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            case .oseba(let url):
                OutlyAvatarView(avatarUrlString: url, size: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(naslov)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(podnaslov)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
    }

    private func noga(_ naslov: String, ikona: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ikona).font(.system(size: 12, weight: .semibold))
            Text(LocalizedStringKey(naslov)).font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
