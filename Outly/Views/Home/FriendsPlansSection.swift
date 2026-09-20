import SwiftUI

/// Razdelek "Your friends' plans" na domacem zaslonu (Martin, 20. 9. 2026, po sliki
/// "Your crew is going"): pod "In your area". Krogi z modrim robom = prijatelji, ki imajo
/// vstopnico za prihajajoci dogodek (GET /me/friends/plans; samo prijatelji z vklopljenim
/// deljenjem), na koncu crtkan krog "+" z "Invite more" (deli povezavo do Outlyja),
/// desno "View" -> seznam dogodkov prijateljev (FriendsPlansView).
/// Brez nacrtov razdelek ostane (namig, da dodas prijatelje) — ne izgine.
struct FriendsPlansSection: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]

    private let velikost: CGFloat = 64
    private let najvecAvatarjev = 6

    /// Prijatelji brez podvajanja, v vrstnem redu prvega dogodka.
    private var prijatelji: [FriendUser] {
        var videni = Set<Int>()
        var seznam: [FriendUser] = []
        for p in plans {
            for f in p.friends where !videni.contains(f.id) {
                videni.insert(f.id)
                seznam.append(f)
            }
        }
        return seznam
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Your friends' plans")
                Spacer()
                NavigationLink {
                    FriendsPlansView(plans: plans, clubsById: clubsById)
                } label: {
                    Text("View")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.outlyBlue)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(prijatelji.prefix(najvecAvatarjev)) { f in
                        NavigationLink {
                            FriendsPlansView(plans: plans, clubsById: clubsById, oseba: f)
                        } label: {
                            avatar(f)
                        }
                        .buttonStyle(.plain)
                    }

                    if prijatelji.count > najvecAvatarjev {
                        NavigationLink {
                            FriendsPlansView(plans: plans, clubsById: clubsById)
                        } label: {
                            Text("+\(prijatelji.count - najvecAvatarjev)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: velikost, height: velikost)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                                .overlay(Circle().stroke(Color.outlyBlue, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }

                    if prijatelji.isEmpty {
                        Text("Add friends to see where they're going")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: 170, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    povabi
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Krog z modrim robom (kot na sliki), slika prek OutlyAvatarView.
    private func avatar(_ f: FriendUser) -> some View {
        OutlyAvatarView(avatarUrlString: f.avatarUrl, size: velikost - 6)
            .padding(3)
            .overlay(Circle().stroke(Color.outlyBlue, lineWidth: 2))
            .accessibilityLabel(Text(f.username))
    }

    /// Crtkan krog "+" in "Invite more": deli povezavo do Outlyja (sistemski list za deljenje).
    private var povabi: some View {
        ShareLink(item: URL(string: "https://outly.si")!,
                  message: Text("Join me on Outly — see where we're going out.")) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: velikost, height: velikost)
                    .overlay(
                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundColor(.white.opacity(0.45))
                    )
                Text("Invite\nmore")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "View" iz razdelka: prihajajoci dogodki, na katere gredo prijatelji. Ce je podana
/// `oseba`, samo dogodki tega prijatelja. Potisnjen pogled, brez lastnega NavigationStacka.
struct FriendsPlansView: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]
    var oseba: FriendUser? = nil

    private var prikazani: [FriendPlan] {
        guard let oseba else { return plans }
        return plans.filter { p in p.friends.contains { $0.id == oseba.id } }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: oseba.map { String(localized: "\($0.username)'s plans") } ?? "Your friends' plans", size: 28)
                    .padding(.top, 6)

                if prikazani.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2").font(.system(size: 36)).foregroundStyle(Color.outlyBlue)
                        Text("No plans yet").font(.headline).foregroundStyle(.white)
                        Text("When a friend gets a ticket, the event shows up here.").font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 12) {
                        ForEach(prikazani) { p in
                            NavigationLink {
                                EventDetailView(event: p.event)
                            } label: {
                                vrstica(p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    /// Plakat, naslov, klub · cas, spodaj majhni avatarji prijateljev, ki gredo.
    private func vrstica(_ p: FriendPlan) -> some View {
        HStack(spacing: 12) {
            plakat(p.event.posterUrl)
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(p.event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text([p.clubName.isEmpty ? (clubsById[p.event.clubId]?.name ?? "") : p.clubName, p.event.displayDayTime]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                HStack(spacing: -6) {
                    ForEach(p.friends.prefix(5)) { f in
                        OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 22)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    }
                    if p.friends.count > 5 {
                        Text("+\(p.friends.count - 5)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.outlyBlue))
                    }
                    Text(p.friends.count == 1 ? String(localized: "\(p.friends[0].username) is going") : String(localized: "\(p.friends.count) friends going"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.leading, 12)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func plakat(_ url: String) -> some View {
        if !url.isEmpty, let u = URL(string: url) {
            AsyncImage(url: u) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.1))
            }
        } else {
            Rectangle().fill(Color.outlyBlue.opacity(0.25))
                .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.7)))
        }
    }
}
