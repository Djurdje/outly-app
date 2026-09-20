import SwiftUI

/// Spustni meni obvestil pod zvoncem na domacem zaslonu (Martin, 20. 9. 2026): prej je
/// zvonec vodil na My Clubs, kar je bilo narobe. Meni lezi cez HomeView (overlay), zapre se
/// z dotikom zunaj. Vsebina: vabila v ekipo kluba (-> ClubInvitesView, kjer se sprejme),
/// prosnje za prijateljstvo (-> MyFriendsView) in prejete vstopnice (-> TicketsView; dotik
/// obvestilo oznaci kot prebrano, backend migracija 017). Sprejem se ne zgodi tu — dejanje s
/// posledicami ostane na zaslonu, ki ga ze ima. Potisnih obvestil (APNs) se ni.
/// Spodnjih gumbov My Clubs / My Friends ni vec (Martin, 21. 9. 2026) — oba sta v profilu.
/// Lezi znotraj NavigationStack domacega zaslona, zato NavigationLink dela.
struct NotificationsMenuView: View {
    @Binding var invites: [MyInvite]
    let friendRequests: [FriendRequest]
    let receivedTickets: [ReceivedTicket]
    let isLoading: Bool
    /// Zapre meni (pred navigacijo in ob dotiku zunaj).
    var onClose: () -> Void
    /// Po sprejemu vabila v ekipo (ime kluba) — HomeView osvezi profil.
    var onJoined: (String) -> Void
    /// Dotik obvestila o prejeti vstopnici (id prenosa) — HomeView ga oznaci kot prebrano.
    var onTicketSeen: (Int) -> Void

    private var jePrazno: Bool { invites.isEmpty && friendRequests.isEmpty && receivedTickets.isEmpty }

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
                    ForEach(receivedTickets) { t in
                        NavigationLink {
                            TicketsView()
                        } label: {
                            vrstica(slika: .oseba(t.from?.avatarUrl),
                                    naslov: t.from.map { String(localized: "\($0.username) sent you a ticket for \(t.eventTitle)") }
                                        ?? String(localized: "You received a ticket for \(t.eventTitle)"),
                                    podnaslov: String(localized: "It's in your Tickets"))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { onTicketSeen(t.id); onClose() })
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
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
}
