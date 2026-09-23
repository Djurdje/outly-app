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

/// Razdelek "Your friends plans" na domacem zaslonu (Martin, 23. 9. 2026, prenova iz kroznih
/// avatarjev v seznam vrstic po dogodku): najvec 3 vrstice, razvrscene po stevilu prijateljev
/// (going + interested) padajoce, nato po datumu. Desno gumb "Join them" (nakup) ali "I'm in"
/// (PUT interest) ali znacka "Going" — glej FriendsPlanRow. Moder sij samo na gumbu prve vrstice
/// (pravilo: en sij na zaslon). Na koncu "Invite more" brez sija. Brez nacrtov razdelek ostane
/// z namigom, ne izgine.
struct FriendsPlansSection: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]

    private let najvecVrstic = 3

    /// Brez koncanih in podvojenih dogodkov, razvrsceno po priljubljenosti med prijatelji.
    private var prikazani: [FriendPlan] {
        plans.brezPodvojenihInKoncanih.razvrsceniPoPriljubljenosti()
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

            if prikazani.isEmpty {
                Text("Add friends to see their plans here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(prikazani.prefix(najvecVrstic).enumerated()), id: \.element.id) { index, p in
                        FriendPlanRow(plan: p, clubsById: clubsById, prikaziSij: index == 0)
                    }
                }
                povabiVrstica
            }
        }
    }

    /// "Invite more": deli povezavo do Outlyja. Brez sija (sij je ze na prvi vrstici zgoraj).
    private var povabiVrstica: some View {
        ShareLink(item: URL(string: "https://outly.si")!,
                  message: Text("Join me on Outly — see where we're going out.")) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text("Invite more")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
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

    /// Po stevilu prijateljev (going + interested) padajoce, nato po datumu zacetka.
    func razvrsceniPoPriljubljenosti() -> [FriendPlan] {
        sorted { a, b in
            let na = a.friends.count + a.interested.count
            let nb = b.friends.count + b.interested.count
            if na != nb { return na > nb }
            let da = a.event.startDate ?? .distantFuture
            let db = b.event.startDate ?? .distantFuture
            return da < db
        }
    }
}

// MARK: - Ena vrstica dogodka (deli jo Home razdelek in "View")

/// Plakat 60x60, naslov, dan · klub, prekrivajoci avatarji + napis, desno gumb/znacka.
/// Dotik na vrstico (ne na gumb) -> EventDetailView. Skrit NavigationLink je .background
/// cele vrstice; gumb v ospredju dotik prestreze prej, zato ne sprozi tudi navigacije.
struct FriendPlanRow: View {
    let plan: FriendPlan
    let clubsById: [Int: APIClub]
    /// Sij samo na prvi vrstici zaslona (pravilo: en sij na zaslon).
    var prikaziSij: Bool = false

    @EnvironmentObject private var session: SessionStore
    @State private var mojNacrt: EventPlan?
    @State private var posiljam = false
    @State private var showBuy = false

    private var imeKluba: String {
        plan.clubName.isEmpty ? (clubsById[plan.event.clubId]?.name ?? "") : plan.clubName
    }

    /// Cena na Outlyju obstaja in dogodek se ni razprodan/koncan -> "Join them" vodi v nakup.
    private var mozenNakup: Bool {
        plan.event.ticketPriceCents != nil && !plan.event.isSoldOut && !plan.event.hasEnded
    }

    private var napisPrijateljev: String {
        FriendsPlanText.summary(going: plan.friends, interested: plan.interested)
    }

    var body: some View {
        // Skrit NavigationLink kot .background cele vrstice: dobi tocno njen okvir (background
        // se prilagodi velikosti nadrejenega), gumb v ospredju pa dotik prestreze prej kot on.
        rowContent
            .background(
                NavigationLink {
                    EventDetailView(event: plan.event)
                } label: { EmptyView() }
                .opacity(0)
            )
            .onAppear {
                if mojNacrt == nil { mojNacrt = plan.myPlan }
            }
            .sheet(isPresented: $showBuy) {
                BuyTicketsView(event: plan.event, clubName: imeKluba.isEmpty ? String(localized: "Club") : imeKluba)
                    .environmentObject(session)
            }
    }

    private var rowContent: some View {
            HStack(spacing: 12) {
                plakat
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text([plan.event.displayDayShort, imeKluba].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                    if !napisPrijateljev.isEmpty {
                        HStack(spacing: 6) {
                            avatarji
                            Text(napisPrijateljev)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                gumb
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Do 3 prekrivajoci se avatarji: najprej tisti, ki grejo, nato tisti, ki jih zanima.
    private var avatarji: some View {
        let vsi = (plan.friends + plan.interested.filter { fi in !plan.friends.contains { $0.id == fi.id } }).prefix(3)
        return HStack(spacing: -10) {
            ForEach(Array(vsi)) { f in
                OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 22)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            }
        }
    }

    @ViewBuilder
    private var gumb: some View {
        if mojNacrt == .going {
            goingZnacka
        } else if mozenNakup {
            Button {
                showBuy = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill").font(.system(size: 13, weight: .semibold))
                    Text("Join them").font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(Color.outlyBlue))
            }
            .buttonStyle(.plain)
            .outlySij(moc: 1.0, aktiven: prikaziSij)
        } else {
            imInGumb
        }
    }

    private var goingZnacka: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
            Text("Going").font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule().fill(Color.outlyBlue))
    }

    private var imInGumb: some View {
        let jeZanima = mojNacrt == .interested
        return Button {
            preklopiZanimanje()
        } label: {
            Text(jeZanima ? "Interested" : "I'm in")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(jeZanima ? .outlyBlue : .white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(jeZanima ? Color.white : Color.clear))
                .overlay(Capsule().stroke(Color.white.opacity(jeZanima ? 0 : 0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .outlySij(moc: 1.0, aktiven: prikaziSij)
    }

    /// PUT/DELETE interest, optimisticno; ob napaki vrne nazaj. Isti vzorec kot na EventDetailView.
    private func preklopiZanimanje() {
        guard !posiljam else { return }
        let token = session.token
        guard !token.isEmpty else { return }
        let prejsnje = mojNacrt
        let novo: EventPlan? = (mojNacrt == .interested) ? nil : .interested
        withAnimation(.snappy) { mojNacrt = novo }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        posiljam = true
        Task {
            do {
                if let novo {
                    try await APIClient.shared.setEventInterest(token: token, eventId: plan.event.id, plan: novo)
                } else {
                    try await APIClient.shared.clearEventInterest(token: token, eventId: plan.event.id)
                }
            } catch {
                await MainActor.run { withAnimation(.snappy) { mojNacrt = prejsnje } }
            }
            await MainActor.run { posiljam = false }
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

/// "View" iz razdelka (Martin, 23. 9. 2026, prenova): naslov, dva segmenta "Going"/"Interested"
/// (namesto gumbov po prijatelju), pod njimi iste vrstice kot na Home (FriendPlanRow).
/// Potisnjen pogled, brez lastnega NavigationStacka.
struct FriendsPlansView: View {
    let plans: [FriendPlan]
    let clubsById: [Int: APIClub]
    /// Ostal zaradi obratne zdruzljivosti klica iz avatarja prijatelja (ni vec uporabljen
    /// za filter po osebi, samo za morebitno prihodnjo rabo).
    var oseba: FriendUser? = nil

    private enum Zavihek: String, CaseIterable { case going, interested }
    @State private var izbran: Zavihek = .going

    private var vsi: [FriendPlan] { plans.brezPodvojenihInKoncanih }

    /// Going: dogodki, kjer gre vsaj en prijatelj (razvrsceni po stevilu, ki gredo).
    private var going: [FriendPlan] {
        vsi.filter { !$0.friends.isEmpty }.razvrsceniPoPriljubljenosti()
    }

    /// Interested: dogodki, kjer je vsaj en prijatelj zainteresiran (razvrsceni enako).
    private var interested: [FriendPlan] {
        vsi.filter { !$0.interested.isEmpty }.razvrsceniPoPriljubljenosti()
    }

    private var prikazani: [FriendPlan] {
        izbran == .going ? going : interested
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

                zavihki

                if prikazani.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2").font(.system(size: 36)).foregroundStyle(Color.outlyBlue)
                        Text(izbran == .going ? "No one going yet" : "No one interested yet")
                            .font(.headline).foregroundStyle(.white)
                        Text("When a friend gets a ticket, the event shows up here.").font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 10) {
                        ForEach(prikazani) { p in
                            FriendPlanRow(plan: p, clubsById: clubsById)
                        }
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

    /// Segment pil: izbrani moder poln, drugi prosojen z belo obrobo.
    private var zavihki: some View {
        HStack(spacing: 8) {
            zavihekGumb(String(localized: "Going"), tab: .going)
            zavihekGumb(String(localized: "Interested"), tab: .interested)
        }
    }

    private func zavihekGumb(_ naslov: String, tab: Zavihek) -> some View {
        let aktiven = izbran == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { izbran = tab }
        } label: {
            Text(naslov)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(aktiven ? .white : .white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(aktiven ? Color.outlyBlue : Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Color.white.opacity(aktiven ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
