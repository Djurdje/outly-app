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
    /// "Invite more" je za 35 % manjsi od avatarjev (Martin, 21. 9. 2026): 64 -> 42.
    private let velikostPovabi: CGFloat = 42
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
    /// Cel element je pomanjsan na ~65 % (krog 42, plus 13, razmik 7); napis v modri Outly barvi.
    /// Pisava 11 pt, ne 9 (sorazmerno): Apple HIG spodnja meja berljivosti je 11 pt.
    private var povabi: some View {
        ShareLink(item: URL(string: "https://outly.si")!,
                  message: Text("Join me on Outly — see where we're going out.")) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: velikostPovabi, height: velikostPovabi)
                    .overlay(
                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundColor(.white.opacity(0.45))
                    )
                Text("Invite\nmore")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.outlyBlue)
                    .multilineTextAlignment(.leading)
            }
            .frame(height: velikost)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "View" iz razdelka (Martin, 21. 9. 2026, po sliki "Friends' plans tonight"): naslov s podnaslovom,
/// vrsta gumbov "All" + po en gumb na prijatelja (izbrani je moder), pod njo kartica na dogodek:
/// plakat kot zatemnjeno ozadje z modrim robom, "N FRIENDS GOING", prekrivajoci se avatarji,
/// klub, dogodek · cas, kraj · datum, sličica plakata, spodaj "Join them" (nakup) in "View event".
/// Ce je podana `oseba`, je njen gumb izbran ob prihodu. Potisnjen pogled, brez lastnega NavigationStacka.
struct FriendsPlansView: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]
    var oseba: FriendUser? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore
    /// nil = All, sicer id prijatelja.
    @State private var izbran: Int? = nil
    @State private var izbranNastavljen = false

    private let najvecAvatarjev = 4

    /// Prijatelji brez podvajanja, v vrstnem redu prvega dogodka (gumbi).
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

    private var prikazani: [FriendPlan] {
        guard let izbran else { return plans }
        return plans.filter { p in p.friends.contains { $0.id == izbran } }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text("Friends' plans")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("See where your friends are going.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                if !prijatelji.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            gumbFiltra(String(localized: "All"), id: nil)
                            ForEach(prijatelji) { f in gumbFiltra(f.username, id: f.id) }
                        }
                        .padding(.vertical, 2)
                    }
                }

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
                    VStack(spacing: 16) {
                        ForEach(prikazani) { p in kartica(p) }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            // Samo prvic: ce je uporabnik prisel z avatarja prijatelja, je ta gumb ze izbran.
            if !izbranNastavljen { izbran = oseba?.id; izbranNastavljen = true }
        }
    }

    // MARK: - Gumbi filtra

    private func gumbFiltra(_ naslov: String, id: Int?) -> some View {
        let aktiven = izbran == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { izbran = id }
        } label: {
            Text(naslov)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(aktiven ? .white : .white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(aktiven ? Color.outlyBlue : Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Color.white.opacity(aktiven ? 0 : 0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kartica dogodka

    private func kartica(_ p: FriendPlan) -> some View {
        let klub = clubsById[p.event.clubId]
        let imeKluba = p.clubName.isEmpty ? (klub?.name ?? "") : p.clubName
        let kraj = klub?.city ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(napisGredo(p.friends).uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    favorites.toggle(p.event.id, token: session.token)
                } label: {
                    Image(systemName: favorites.contains(p.event.id) ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(favorites.contains(p.event.id) ? .outlyBlue : .white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(favorites.contains(p.event.id) ? "Remove from liked events" : "Add to liked events"))
            }

            avatarji(p.friends)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(imeKluba.isEmpty ? p.event.title : imeKluba)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text([imeKluba.isEmpty ? "" : p.event.title, casDogodka(p.event)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                        Text([kraj, p.event.displayDayShort].filter { !$0.isEmpty }.joined(separator: " · "))
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                plakat(p.event.posterUrl)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.outlyBlue, lineWidth: 1.5))
            }

            HStack(spacing: 10) {
                NavigationLink {
                    BuyTicketsView(event: p.event, clubName: imeKluba.isEmpty ? String(localized: "Club") : imeKluba)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill").font(.system(size: 15, weight: .semibold))
                        Text("Join them").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.outlyBlue))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EventDetailView(event: p.event)
                } label: {
                    HStack(spacing: 6) {
                        Text("View event").font(.system(size: 16, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(ozadje(p.event.posterUrl))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.outlyBlue, lineWidth: 1.5))
    }

    /// Prekrivajoci se avatarji (najvec 4) + crn krog "+" za ostale.
    private func avatarji(_ prijatelji: [FriendUser]) -> some View {
        HStack(spacing: -12) {
            ForEach(prijatelji.prefix(najvecAvatarjev)) { f in
                OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 46)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
            }
            if prijatelji.count > najvecAvatarjev {
                Text("+\(prijatelji.count - najvecAvatarjev)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .padding(.leading, 18)
            }
        }
    }

    private func napisGredo(_ prijatelji: [FriendUser]) -> String {
        if prijatelji.count == 1, let f = prijatelji.first { return String(localized: "\(f.username) is going") }
        return String(localized: "\(prijatelji.count) friends going")
    }

    /// "22:00 - 06:00" ali samo "22:00", ce konca ni.
    private func casDogodka(_ e: APIEvent) -> String {
        let zacetek = e.displayTimeShort
        guard let konec = e.endDate else { return zacetek }
        return zacetek + " - " + DateParsing.shortTime.string(from: konec)
    }

    /// Plakat kot zatemnjeno ozadje kartice; brez plakata temna ploskev.
    private func ozadje(_ url: String) -> some View {
        ZStack {
            Color(red: 14/255, green: 16/255, blue: 24/255)
            plakat(url)
            LinearGradient(colors: [Color.black.opacity(0.45), Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
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
