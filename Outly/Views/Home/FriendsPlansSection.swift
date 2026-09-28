import SwiftUI
import UIKit

/// Skupno besedilo "Ana, Luka + 2 going · 3 interested" — uporabljata ga tako ta razdelek
/// (Home in "View") kot vrstica prijateljev na EventDetailView (Martin, 23. 9. 2026).
enum FriendsPlanText {
    /// Prazen niz, ce ni ne enih ne drugih (klicatelj vrstico takrat skrije).
    static func summary(going: [FriendUser], interested: [FriendUser]) -> String {
        var deli: [String] = []
        if !going.isEmpty {
            switch going.count {
            case 1:
                deli.append(String(localized: "\(going[0].username) going"))
            case 2:
                deli.append(String(localized: "\(going[0].username), \(going[1].username) going"))
            default:
                let ostali = going.count - 2
                deli.append(String(localized: "\(going[0].username), \(going[1].username) + \(ostali) going"))
            }
        }
        if !interested.isEmpty {
            deli.append(String(localized: "\(interested.count) interested"))
        }
        return deli.joined(separator: " · ")
    }
}

/// Razdelek "Friends plans" na domacem zaslonu (Martin, 24. 9. 2026: nazaj na krozne avatarje
/// izpred PR #22, na Martinovo zahtevo po ogledu builda; vrstice po dogodku ostanejo samo na
/// zaslonu "View"). Krogi prijateljev: moder rob = grejo (vstopnica), bel rob 50 % = jih zanima
/// ("I'm in", sistem iz PR #22 ostane); grejo najprej, brez podvajanja osebe. Na koncu crtkan
/// krog "+" "Invite more" (ShareLink outly.si), desno "View" -> FriendsPlansView. Vsi elementi
/// so za 15 % manjsi kot v izvirniku izpred PR #22 (Martin: avatar 64->54, Invite more 42->36,
/// pisave/razmiki ×0,85, zaokrozeno na cele tocke). Brez nacrtov razdelek ostane z namigom.
struct FriendsPlansSection: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]

    // Avatarji +5 % (Martin, 25. 9. 2026): 54 -> 57. Invite more (36) ostane.
    private let velikost: CGFloat = 57
    private let velikostPovabi: CGFloat = 36
    private let najvecAvatarjev = 6

    /// Prijatelji, ki GREJO (vstopnica), brez podvajanja, v vrstnem redu prvega dogodka.
    /// Samo dogodki, ki se niso koncali.
    private var friendsGoing: [FriendUser] {
        var videni = Set<Int>()
        var seznam: [FriendUser] = []
        for p in plans where !p.event.hasEnded {
            for f in p.friends where !videni.contains(f.id) {
                videni.insert(f.id)
                seznam.append(f)
            }
        }
        return seznam
    }

    /// Prijatelji, ki jih ZANIMA (brez vstopnice), brez tistih, ki ze grejo (ni podvajanja osebe).
    private var friendsInterestedOnly: [FriendUser] {
        var videni = Set(friendsGoing.map(\.id))
        var seznam: [FriendUser] = []
        for p in plans where !p.event.hasEnded {
            for f in p.interested where !videni.contains(f.id) {
                videni.insert(f.id)
                seznam.append(f)
            }
        }
        return seznam
    }

    /// Grejo najprej, nato tisti, ki jih samo zanima.
    private var prijatelji: [(user: FriendUser, gre: Bool)] {
        friendsGoing.map { ($0, true) } + friendsInterestedOnly.map { ($0, false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Friends plans")
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
                HStack(spacing: 12) {
                    ForEach(Array(prijatelji.prefix(najvecAvatarjev)), id: \.user.id) { par in
                        NavigationLink {
                            FriendsPlansView(plans: plans, clubsById: clubsById)
                        } label: {
                            avatar(par.user, gre: par.gre)
                        }
                        .buttonStyle(.plain)
                    }

                    if prijatelji.count > najvecAvatarjev {
                        NavigationLink {
                            FriendsPlansView(plans: plans, clubsById: clubsById)
                        } label: {
                            Text("+\(prijatelji.count - najvecAvatarjev)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: velikost, height: velikost)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                                .overlay(Circle().stroke(Color.outlyBlue, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }

                    if prijatelji.isEmpty {
                        Text("Add friends to see where they're going")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: 145, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    povabi
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Krog z modrim (gre) ali belim 50 % (zanima) robom, slika prek OutlyAvatarView.
    private func avatar(_ f: FriendUser, gre: Bool) -> some View {
        OutlyAvatarView(avatarUrlString: f.avatarUrl, size: velikost - 5)
            .padding(3)
            .overlay(Circle().stroke(gre ? Color.outlyBlue : Color.white.opacity(0.5), lineWidth: 2))
            .accessibilityLabel(Text(f.username))
    }

    /// Crtkan krog "+" in "Invite more": deli povezavo do Outlyja (sistemski list za deljenje).
    private var povabi: some View {
        ShareLink(item: URL(string: "https://outly.si")!,
                  message: Text("Join me on Outly — see where we're going out.")) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
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

// MARK: - Razvrscanje / ciscenje seznama nacrtov (skupno za Section in View)

extension Array where Element == FriendPlan {
    /// Brez koncanih dogodkov in brez podvojenega id-ja (varovalo, ce bi streznik kdaj
    /// vrnil dva zapisa za isti dogodek — podvojen id v ForEach sicer zmede dotik).
    var brezPodvojenihInKoncanih: [FriendPlan] {
        var videni = Set<Int>()
        return filter { p in
            guard !p.event.hasEnded, !videni.contains(p.event.id) else { return false }
            videni.insert(p.event.id)
            return true
        }
    }

    // Prejsnja razvrsceniPoPriljubljenosti (razvrscanje za locena zavihka Going/Interested iz
    // PR #22) je odstranjena skupaj z zavihki spodaj — noben klicatelj je vec ne rabi
    // (Martin, 25. 9. 2026: "View" nazaj na izgled izpred PR #22).
}

// MARK: - "View" (FriendsPlansView)
// Martin, 28. 9. 2026: namesto gumbov po prijatelju trije filtri po stanju — All, Going
// (vsaj en prijatelj ima vstopnico) in Interested (vsaj enega prijatelja zanima). Kartica z
// zatemnjenim plakatom, prekrivajocimi avatarji in gumboma "Join them" / "View event" ostane.
// Potisnjen pogled, brez lastnega NavigationStacka (past 9).
struct FriendsPlansView: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]

    private enum Filter: CaseIterable {
        case all, going, interested

        var naslov: String {
            switch self {
            case .all: return String(localized: "friends_plans_filter_all", defaultValue: "All")
            case .going: return String(localized: "friends_plans_filter_going", defaultValue: "Going")
            case .interested: return String(localized: "friends_plans_filter_interested", defaultValue: "Interested")
            }
        }
    }

    @State private var filter: Filter = .all

    /// Brez podvojenih dogodkov in brez preteklih (varovalo, ce bi streznik kdaj vrnil vec
    /// kot en zapis na dogodek).
    private var vsi: [FriendPlan] { plans.brezPodvojenihInKoncanih }

    private var prikazani: [FriendPlan] {
        switch filter {
        case .all: return vsi
        case .going: return vsi.filter { !$0.friends.isEmpty }
        case .interested: return vsi.filter { !$0.interested.isEmpty }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text("Friends plans")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("See where your friends are going.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.self) { f in gumbFiltra(f) }
                }
                .padding(.vertical, 2)

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
                        ForEach(prikazani) { p in FriendsPlanCard(plan: p, clubsById: clubsById) }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: - Gumbi filtra

    private func gumbFiltra(_ f: Filter) -> some View {
        let aktiven = filter == f
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filter = f }
        } label: {
            Text(f.naslov)
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
}

// MARK: - Kartica dogodka na zaslonu "View"

/// Zatemnjen plakat kot ozadje, "N FRIENDS GOING · M INTERESTED" zgoraj, prekrivajoci avatarji
/// (going najprej z modrim robom, interested z belim robom 50 %), klub/dogodek/cas/kraj, plakat
/// z modrim robom, spodaj "Join them" (odpre nakup KOT LIST — BuyTicketsView ima lasten
/// NavigationStack, potisniti ga NE smemo, past: skrije gumb nazaj) in "View event" (potisne
/// EventDetailView, ki lastnega NavigationStacka nima). "Join them" je skrit, ce dogodek nima
/// cene na Outlyju ali je razprodan/koncan.
private struct FriendsPlanCard: View {
    let plan: FriendPlan
    let clubsById: [Int: APIClub]

    @EnvironmentObject private var session: SessionStore
    @State private var showBuy = false

    private let najvecAvatarjev = 4

    private var klub: APIClub? { clubsById[plan.event.clubId] }
    private var imeKluba: String { plan.clubName.isEmpty ? (klub?.name ?? "") : plan.clubName }
    private var kraj: String { klub?.city ?? "" }

    /// Cena na Outlyju obstaja in dogodek se ni razprodan/koncan -> "Join them" ima kaj prodati.
    private var mozenNakup: Bool {
        plan.event.ticketPriceCents != nil && !plan.event.isSoldOut && !plan.event.hasEnded
    }

    /// Going in interested skupaj, brez podvajanja osebe, going najprej.
    private var vsiPrijatelji: [(user: FriendUser, gre: Bool)] {
        let goingIds = Set(plan.friends.map(\.id))
        let samoInteresirani = plan.interested.filter { !goingIds.contains($0.id) }
        return plan.friends.map { ($0, true) } + samoInteresirani.map { ($0, false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(napisGlave.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white)

            avatarji

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(imeKluba.isEmpty ? plan.event.title : imeKluba)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text([imeKluba.isEmpty ? "" : plan.event.title, casDogodka].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                        Text([kraj, plan.event.displayDayShort].filter { !$0.isEmpty }.joined(separator: " · "))
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                plakat
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.outlyBlue, lineWidth: 1.5))
            }

            HStack(spacing: 10) {
                if mozenNakup {
                    Button {
                        showBuy = true
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
                }

                NavigationLink {
                    EventDetailView(event: plan.event)
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
        .background(ozadje)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.outlyBlue, lineWidth: 1.5))
        // Sheet, ne push: BuyTicketsView ima lasten NavigationStack, potisnjen bi skril gumb
        // nazaj (past iz razlicice tega zaslona pred PR #22).
        .sheet(isPresented: $showBuy) {
            BuyTicketsView(event: plan.event, clubName: imeKluba.isEmpty ? String(localized: "Club") : imeKluba)
                .environmentObject(session)
        }
    }

    /// Prekrivajoci se avatarji (najvec 4) + krog "+" za ostale; going najprej z modrim robom,
    /// interested z belim robom 50 % (kot krogi razdelka na Home).
    private var avatarji: some View {
        let vsi = vsiPrijatelji
        return HStack(spacing: -12) {
            ForEach(Array(vsi.prefix(najvecAvatarjev)), id: \.user.id) { par in
                OutlyAvatarView(avatarUrlString: par.user.avatarUrl, size: 46)
                    .overlay(Circle().stroke(par.gre ? Color.outlyBlue : Color.white.opacity(0.5), lineWidth: 2))
            }
            if vsi.count > najvecAvatarjev {
                Text("+\(vsi.count - najvecAvatarjev)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .padding(.leading, 18)
            }
        }
    }

    private var napisGlave: String {
        var deli: [String] = []
        if !plan.friends.isEmpty {
            deli.append(plan.friends.count == 1 ? String(localized: "1 friend going") : String(localized: "\(plan.friends.count) friends going"))
        }
        if !plan.interested.isEmpty {
            deli.append(plan.interested.count == 1 ? String(localized: "1 interested") : String(localized: "\(plan.interested.count) interested"))
        }
        return deli.joined(separator: " · ")
    }

    /// "22:00 - 06:00" ali samo "22:00", ce konca ni.
    private var casDogodka: String {
        let zacetek = plan.event.displayTimeShort
        guard let konec = plan.event.endDate else { return zacetek }
        return zacetek + " - " + DateParsing.shortTime.string(from: konec)
    }

    /// Plakat kot zatemnjeno ozadje kartice; brez plakata temna ploskev.
    private var ozadje: some View {
        ZStack {
            Color(red: 14/255, green: 16/255, blue: 24/255)
            plakat
            LinearGradient(colors: [Color.black.opacity(0.45), Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private var plakat: some View {
        if !plan.event.posterUrl.isEmpty, let u = URL(string: plan.event.posterUrl) {
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
