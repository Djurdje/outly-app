import SwiftUI
import MapKit
import UIKit

struct EventDetailView: View {
    let event: APIEvent

    @State private var club: APIClub?
    /// Klub gostitelj (`event.venueClubId`): njegov naslov, zemljevid in telefon so naslov dogodka.
    @State private var venueClub: APIClub?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showBuy = false
    @State private var showBarPrices = false
    @State private var showVip = false
    @EnvironmentObject private var session: SessionStore

    // "I'm in" (backend migracija 020, 23. 9. 2026): moj nacrt + prijatelji, ki grejo/jih zanima.
    // Nalozi se loceno od dogodka (GET /events/:id z zetonom), da fetchEvent(id:) v
    // APIClient+Discover ostane nespremenjen (ga uporabljajo tudi neprijavljeni zasloni).
    @State private var myPlan: EventPlan?
    @State private var friendsGoing: [FriendUser] = []
    @State private var friendsInterested: [FriendUser] = []
    @State private var planSubmitting = false

    // Opis (GET /events?lite=true ga v seznamih ne vrne): ce `event.description` ni prazen, ga uporabimo;
    // sicer ga nalozimo ob odprtju (loadPlan za prijavljene, loadOpis za goste).
    @State private var nalozenOpis = ""
    private var opis: String { event.description.isEmpty ? nalozenOpis : event.description }

    /// Dogodek kluba, v katerem sem lastnik ali clan ekipe (Me.clubs / Me.clubId).
    private var jeMojDogodek: Bool {
        guard let me = session.me else { return false }
        return me.clubId == event.clubId || me.clubs.contains { $0.clubId == event.clubId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                // Pasica DOGODKA; na njej samo vrstica z vstopnicami (Luka 14. 9.).
                hero

                // Ime dogodka + srcek pod pasico
                titleBlock

                // Prijatelji, ki grejo/jih zanima (samo, ce jih je) — pod naslovom, nad opisom.
                friendsRow

                // Logo in ime kluba (vodi na stran kluba)
                clubRow

                // Kdaj (med klubom in naslovom)
                whenCard

                // Naslov, kontakt, zemljevid
                infoBlock

                // Cenik bara (migracija 014)
                barPricesButton

                aboutBlock

                // Kdo prodaja (backend#94): ena vrstica, samo za dogodke, prodajane v aplikaciji
                soldByVrstica

                // VIP mize: rezervacija po telefonu kluba (Martin, 28. 9. 2026)
                vipBlock

                Spacer(minLength: 40)
            }
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // Report v meniju »…« (outly-backend #189, Apple 1.2); ne za dogodek kluba, v katerem sam delam.
        .prijavaMeni(targetType: .event, targetId: event.id, targetName: event.title, skrij: jeMojDogodek)
        .task { await loadClub() }
        .task { await loadVenueClub() }
        .task { await loadPlan() }
        .task { await loadOpis() }
        // Stevec ogledov za nadzorno plosco kluba (Martin, 25. 9. 2026): enkrat na prikaz, brez zetona.
        .task { await APIClient.shared.postView(eventId: event.id) }
        .sheet(isPresented: $showBuy) {
            BuyTicketsView(event: event, clubName: club?.name ?? String(localized: "Club"), seller: prodajalec)
                .environmentObject(session)
        }
        .sheet(isPresented: $showVip) {
            // VIP mize v aplikaciji (backend 025): tloris + nakup. Brez njih ostane prejsnji list (telefon kluba).
            if event.vipEnabled {
                VipTablesView(event: event, clubName: club?.name ?? String(localized: "Club"), seller: prodajalec)
                    .environmentObject(session)
            } else {
                VipTablesSheet(clubName: club?.name ?? String(localized: "Club"))
            }
        }
        .sheet(isPresented: $showBarPrices) {
            BarPricesView(clubName: barClub?.name ?? String(localized: "Club"), items: barClub?.barPrices ?? [])
        }
    }

    // MARK: - Hero: pasica dogodka (plakat); na njej samo vrstica z vstopnicami, sredinsko,
    // malo dvignjena od dna. Naslov in kdaj sta pod sliko (Lukov popravek 14. 9. zvecer).
    private var headerImageUrl: String {
        if !event.posterUrl.isEmpty { return event.posterUrl }
        // Brez plakata vzamemo prvo sliko kluba (slideshow, sicer stara pasica).
        return club?.slideshowUrls.first ?? ""
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                // Koncan dogodek s posnetkom (backend 019): video stopi NA MESTO plakata,
                // da uporabnik vidi, kako je bilo. Prenese se sele ob dotiku (OutlyRecapVideo).
                if let recap = event.recapVideoURL {
                    OutlyRecapVideo(url: recap, posterUrl: headerImageUrl, playSize: 64)
                } else if !headerImageUrl.isEmpty, let url = URL(string: headerImageUrl) {
                    OutlyAsyncImage(url: url) { img in
                        Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                    } placeholder: {
                        Rectangle().opacity(0.12)
                    }
                } else {
                    Color(white: 0.14)
                }

                // Temnenje proti dnu, da sta kartici in naslov berljivi na vsakem plakatu.
                // Rahlo temnenje proti dnu, da se vrstica z vstopnicami loci od plakata.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.30), location: 0),
                        .init(color: .clear, location: 0.20),
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(0.75), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Brez tega preliv prestreze dotik in posnetka ni mogoce zagnati.
                .allowsHitTesting(false)
            }
            // Obrezuje se samo slika/video (scaledToFill gre cez rob), NE gumb za vstopnice:
            // gumb je 18 pt od dna, njegov moder sij pa sega dlje — z obrezovanjem cele pasice
            // bi bil sij spodaj odrezan v ravno crto.
            .frame(height: heroHeight)
            .clipped()

            ticketBar
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .frame(height: heroHeight)
    }

    /// Plakat cez priblizno polovico zaslona (na iPhonu 14 Pro ~470 pt).
    private var heroHeight: CGFloat {
        max(400, min(540, UIScreen.main.bounds.height * 0.55))
    }

    // MARK: - Naslov + pil "I'm in" (pod sliko)
    // Srcek je odstranjen (Martin, 24. 9. 2026): "I'm in" ga je nadomestil, FavoritesStore
    // ostaja v repu (backend pot ostane), samo ta zaslon ga vec ne uporablja.
    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if session.isLoggedIn {
                imInPill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    /// Pil s tremi stanji: nic -> "I'm in" (bel rob, prosojno), interested ->
    /// "Interested" (bel poln pil, moder napis), going -> "Going" (moder poln pil, bela kljukica,
    /// ni pritisljiv — to stanje pride samo iz vstopnice, ne od tod). Martin, 23. 9. 2026.
    @ViewBuilder
    private var imInPill: some View {
        switch myPlan {
        case .going:
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                Text("Going").font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(Color.outlyBlue))

        case .interested:
            Button { preklopiZanimanje() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hand.thumbsup.fill").font(.system(size: 12, weight: .bold))
                    Text("Interested").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.outlyBlue)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)

        case nil:
            Button { preklopiZanimanje() } label: {
                Text("I'm in")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    /// Vrstica prijateljev pod naslovom: prekrivajoci avatarji + "Ana, Luka going · 2 interested".
    /// Skrita, ce dogodka ne gre/ne zanima noben prijatelj (nalozi se v loadPlan()).
    @ViewBuilder
    private var friendsRow: some View {
        let napis = FriendsPlanText.summary(going: friendsGoing, interested: friendsInterested)
        if !napis.isEmpty {
            let vsi = Array((friendsGoing + friendsInterested.filter { fi in !friendsGoing.contains { $0.id == fi.id } }).prefix(4))
            HStack(spacing: 8) {
                HStack(spacing: -10) {
                    ForEach(vsi) { f in
                        OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 28)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    }
                }
                Text(napis)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Klub: logo, ime, 18+ -> stran kluba
    // Organizator (is_organizer): "Organizer: <ime>" -> njegova stran (dogovor 9. 10. 2026).
    private var clubRowTitle: String {
        guard let club else { return String(localized: "Club") }
        if club.isOrganizer { return String(localized: "Organizer: \(club.name)") }
        return club.name
    }

    private var clubRow: some View {
        NavigationLink {
            ClubDetailView(clubId: event.clubId)
        } label: {
            HStack(spacing: 12) {
                if let club, !club.logoUrl.isEmpty, let url = URL(string: club.logoUrl) {
                    OutlyAsyncImage(url: url) { img in
                        Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                    } placeholder: { Circle().opacity(0.12) }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle().fill(Color.white.opacity(0.10))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "building.2").foregroundStyle(.white.opacity(0.7)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(clubRowTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(LocalizedStringKey(club?.isOrganizer == true ? "View organizer" : "View club"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                if event.minAge > 0 {
                    Text("\(event.minAge)+")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kdaj: datum in ura, jasno in na enem mestu
    private var whenCard: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(monthShort.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.6))
                Text(dayNumber)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(dayLong)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(timeRange)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            if let badge = relativeBadge {
                let isTonight: Bool = { if case .tonight = badge { return true }; return false }()
                Text(relativeBadgeText(badge))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isTonight ? Color.black : Color.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(isTonight ? Color.white : Color.white.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var monthShort: String {
        guard let d = event.startDate else { return "" }
        let f = DateFormatter(); f.locale = Jezik.shared.locale; f.dateFormat = "MMM"
        return f.string(from: d)
    }
    private var dayNumber: String {
        guard let d = event.startDate else { return "–" }
        return String(Calendar.current.component(.day, from: d))
    }
    private var dayLong: String {
        guard let d = event.startDate else { return event.startAt }
        let f = DateFormatter(); f.locale = Jezik.shared.locale; f.dateFormat = "EEEE, d MMMM"
        return f.string(from: d)
    }
    private var timeRange: String {
        guard let d = event.startDate else { return "" }
        let t = DateParsing.shortTime.string(from: d)
        if let e = event.endDate {
            return "\(t) – \(DateParsing.shortTime.string(from: e))"
        }
        return String(localized: "Starts at \(t)")
    }

    /// Znacka "Tonight"/"Ended"/... ob strani datuma. Loceno od besedila (relativeBadgeText),
    /// da primerjava za belo/modro stanje ne razpade, ko je besedilo prevedeno (prej rel == "TONIGHT").
    private enum RelativeBadge { case ended, tonight, tomorrow, inDays(Int) }

    private var relativeBadge: RelativeBadge? {
        guard let d = event.startDate else { return nil }
        let cal = Calendar.current
        if event.isPast { return .ended }
        if cal.isDateInToday(d) { return .tonight }
        if cal.isDateInTomorrow(d) { return .tomorrow }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        if days > 0 && days <= 14 { return .inDays(days) }
        return nil
    }

    private func relativeBadgeText(_ badge: RelativeBadge) -> String {
        switch badge {
        case .ended: return String(localized: "ENDED")
        case .tonight: return String(localized: "TONIGHT")
        case .tomorrow: return String(localized: "TOMORROW")
        case .inDays(let days): return String(localized: "IN \(days) DAYS")
        }
    }

    // MARK: - Vrstica z vstopnicami: temna kartica, cena levo, bel gumb desno (Martin: modra tu ne pase)
    private enum TicketState { case buy, free, external, door, fewLeft(Int), soldOut, ended }

    private var ticketState: TicketState {
        if event.isPast { return .ended }
        if event.isSoldOut { return .soldOut }
        if let cents = event.ticketPriceCents {
            if event.isFewLeft, let n = event.ticketsLeft { return .fewLeft(n) }
            return cents == 0 ? .free : .buy
        }
        if let u = event.ticketUrl, !u.isEmpty { return .external }
        return .door
    }

    private var ticketBar: some View {
        let state = ticketState
        let price = event.displayPrice ?? String(localized: "Tickets")

        let (top, sub): (String, String) = {
            switch state {
            case .buy:          return (price, String(localized: "per ticket"))
            case .free:         return (String(localized: "FREE"), String(localized: "free entry"))
            case .fewLeft(let n): return (price, n == 1 ? String(localized: "last ticket") : String(localized: "only \(n) left"))
            case .external:     return (String(localized: "Tickets"), String(localized: "sold by the club"))
            case .door:         return (String(localized: "Tickets"), String(localized: "at the door"))
            case .soldOut:      return (price, String(localized: "sold out"))
            case .ended:        return (String(localized: "Ended"), String(localized: "event is over"))
            }
        }()

        let active: Bool = {
            if case .buy = state { return true }
            if case .free = state { return true }
            if case .fewLeft = state { return true }
            if case .external = state { return true }
            return false
        }()

        // Videz od 20. 9. (Martin): en kompakten, sredinski, zaobljen moder okvir (#4C76FF,
        // samo ozadje 65 % prosojno, da plakat rahlo sije skozi), brez belega gumba "Get tickets",
        // z belo obrobo. Cena: znak in cela stevilka velika, decimalke manjse in dvignjene
        // (superscript), pod ceno majhen "per ticket". Ves tekst 100 % neprosojen.
        // Neaktivna stanja temna, obroba bledejsa. Malenkost vecji od prve razlicice (20. 9. zvecer).
        // Polozaj na pasici in dotik (nakup / tuja povezava) sta nespremenjena.
        return HStack {
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                if let deli = razdeljenaCena(top) {
                    HStack(alignment: .top, spacing: 1) {
                        Text(deli.glavni)
                            .font(.system(size: 36, weight: .bold))
                        Text(deli.decimalke)
                            .font(.system(size: 15, weight: .bold))
                            .padding(.top, 6)
                    }
                    .foregroundStyle(.white)
                } else {
                    Text(top)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(sub)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    // Bolj izrazit od 22. 9. (Martin): polnejsa modra in moder sij okoli gumba
                    // (dve senci brez zamika — ozka svetla + siroka mehka), da nakup izstopi s plakata.
                    .fill(active ? Color.outlyBlue.opacity(0.85) : Color.black.opacity(0.55))
                    .shadow(color: active ? Color.outlyBlue.opacity(0.70) : .black.opacity(0.35),
                            radius: active ? 12 : 14, y: active ? 0 : 6)
                    .shadow(color: active ? Color.outlyBlue.opacity(0.45) : .clear, radius: 28)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(active ? 0.9 : 0.16), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture {
                guard active else { return }
                // Cena na Outlyju -> nakup v aplikaciji (BuyTicketsView, testni nacin do Stripa).
                // Brez cene, a s tujo povezavo -> tuja prodaja v brskalniku.
                if event.ticketPriceCents != nil {
                    showBuy = true
                } else if let urlStr = event.ticketUrl,
                          !urlStr.isEmpty,
                          let url = URL(string: urlStr) {
                    UIApplication.shared.open(url)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "€26.00" -> ("€26", ".00"); nil, ce napis ni cena z decimalkami (npr. "Tickets", "FREE").
    /// displayPrice vedno uporabi piko (String(format: "%.2f")), zato je pika zanesljivo locilo.
    private func razdeljenaCena(_ napis: String) -> (glavni: String, decimalke: String)? {
        guard napis == event.displayPrice, let pika = napis.lastIndex(of: ".") else { return nil }
        let glavni = String(napis[..<pika])
        let decimalke = String(napis[pika...])
        guard !glavni.isEmpty, decimalke.count > 1 else { return nil }
        return (glavni, decimalke)
    }

    // MARK: - Info block (address/phone/map style)
    // Kje je dogodek (dogovor 9. 10. 2026): klub gostitelj (vrstica "at <klub>" -> njegova stran, njegov
    // naslov/telefon/zemljevid), prosto vpisano prizorisce (venue_*) ali naslov kluba, ki dogodek objavlja.
    // Organizator brez prizorisca nima naslova -> blok se ne pokaze.

    /// Podatki za blok "kje". nil = ni kaj pokazati (organizator brez prizorisca).
    private struct Prizorisce {
        var ime: String = ""
        var gostiteljId: Int? = nil
        var naslov: String = "-"
        var telefon: String? = nil
        var lat: Double? = nil
        var lng: Double? = nil
    }

    private var prizorisce: Prizorisce? {
        if let vid = event.venueClubId {
            var p = Prizorisce()
            p.gostiteljId = vid
            p.ime = event.imePrizorisca.isEmpty ? (venueClub?.name ?? "") : event.imePrizorisca
            p.naslov = venueClub?.addressFull ?? "-"
            p.telefon = venueClub?.contactPhone
            p.lat = venueClub?.lat
            p.lng = venueClub?.lng
            return p
        }
        if event.imaPrizorisce {
            var p = Prizorisce()
            p.ime = event.imePrizorisca
            let naslov = event.naslovPrizorisca
            p.naslov = naslov.isEmpty ? "-" : naslov
            p.lat = event.venueLat
            p.lng = event.venueLng
            return p
        }
        if club?.isOrganizer == true { return nil }
        var p = Prizorisce()
        p.naslov = club?.addressFull ?? "-"
        p.telefon = club?.contactPhone
        p.lat = club?.lat
        p.lng = club?.lng
        return p
    }

    /// Klub, katerega cenik bara velja za dogodek: gostitelj, sicer klub, ki dogodek objavlja.
    private var barClub: APIClub? { venueClub ?? club }

    @ViewBuilder
    private var infoBlock: some View {
        let p = prizorisce
        if p != nil || isLoading || errorText != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let p {
                    prizoriscePovezava(p)

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            labeled(String(localized: "ADDRESS"), p.naslov)
                            if let tel = p.telefon {
                                labeled(String(localized: "PHONE"), tel.isEmpty ? "-" : tel)
                            }
                        }

                        Spacer(minLength: 0)

                        if let lat = p.lat, let lng = p.lng {
                            // Staticen; klik -> Apple Maps / Google Maps z navodili za pot
                            StaticnaKarta(lat: lat, lng: lng)
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .opacity(0.10)
                                .frame(width: 150, height: 150)
                                .overlay(Image(systemName: "map").font(.title2))
                        }
                    }
                }

                if isLoading {
                    ProgressView().padding(.top, 6)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }

    /// Vrstica "at <ime prizorisca>"; pri klubu gostitelju vodi na njegovo stran (ClubDetailView).
    @ViewBuilder
    private func prizoriscePovezava(_ p: Prizorisce) -> some View {
        if !p.ime.isEmpty {
            if let id = p.gostiteljId {
                NavigationLink {
                    ClubDetailView(clubId: id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                        Text("at \(p.ime)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                    Text("at \(p.ime)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Cenik bara (gumb odpre seznam; Martin 14. 9.)
    private var barPricesButton: some View {
        Button {
            showBarPrices = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wineglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("Bar prices")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                let n = barClub?.barPrices.count ?? 0
                Group {
                    if n == 0 {
                        Text("Not added yet")
                    } else {
                        Text("\(n) items")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - About (opis; plakat je zdaj pasica na vrhu, zato tu ni vec kartice s sliko)
    @ViewBuilder
    private var aboutBlock: some View {
        if !opis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ABOUT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))

                Text(opis)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Prodajalec (backend#94)

    /// Prodajalec je VEDNO klub `event.clubId` (pri gostovanem dogodku organizator, ne prizorisce): najprej `seller` iz
    /// GET /events/:id, sicer iz GET /clubs/:id (`club` je klub dogodka). Star backend ga nima -> nil.
    private var prodajalec: Seller? { event.seller ?? club?.seller }

    /// Dogodek se prodaja v aplikaciji: ima ceno na Outlyju in ni tuja prodaja (`availability == "external"`).
    private var prodanVAplikaciji: Bool { event.ticketPriceCents != nil && event.availability != "external" }

    @ViewBuilder
    private var soldByVrstica: some View {
        if prodanVAplikaciji, let ime = prodajalec?.imeProdajalca, !ime.isEmpty {
            Text("Sold by \(ime)")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - VIP & Tables (Martin, 28. 9. 2026): zamegljen in zatemnjen plakat dogodka kot
    // ozadje, cez napis. Kartica je gumb: odpre list s tlorisom miz (rezervacije v aplikaciji
    // pridejo pozneje - razpored miz poslje organizator). Pod kartico sredinsko "FOR MORE
    // QUESTIONS CALL:" in telefon kluba (tel:). Koncan dogodek kartice nima.
    private var vipPhone: String {
        (club?.contactPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var vipTelURL: URL? {
        let stevke = vipPhone.filter { $0.isNumber || $0 == "+" }
        return stevke.isEmpty ? nil : URL(string: "tel:\(stevke)")
    }

    @ViewBuilder
    private var vipBlock: some View {
        if !event.hasEnded, club != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("VIP & TABLES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))

                Button {
                    showVip = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Reserve a VIP table")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        if event.vipEnabled, let od = event.vipFromCents {
                            Text("from \(Denar.evri(od, koda: event.currency ?? "EUR"))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.vipZlata)
                        }
                        Text("Bottle service and private tables for your group.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            Text("See tables")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(vipOzadje)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                if let tel = vipTelURL {
                    VStack(spacing: 6) {
                        Text("FOR MORE QUESTIONS CALL:")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                        Link(destination: tel) {
                            Text(vipPhone)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.outlyBlue)
                        }
                        .accessibilityLabel(Text("Call \(vipPhone)"))
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    /// Zamegljen in zatemnjen plakat dogodka (ali slika kluba) za kartico VIP.
    private var vipOzadje: some View {
        ZStack {
            if !headerImageUrl.isEmpty, let url = URL(string: headerImageUrl) {
                OutlyAsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill().blur(radius: 14, opaque: true)).clipped()
                } placeholder: {
                    Color(white: 0.14)
                }
            } else {
                Color(white: 0.14)
            }
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    /// Naloz "I'm in": moj nacrt + prijatelji. Samo za prijavljene, tiho ob napaki
    /// (zasebno stanje, ne sme podreti ostalega zaslona).
    private func loadPlan() async {
        guard session.isLoggedIn, !session.token.isEmpty else { return }
        do {
            let info = try await APIClient.shared.fetchEventPlan(id: event.id, token: session.token)
            await MainActor.run {
                myPlan = info.myPlan
                friendsGoing = info.friendsGoing
                friendsInterested = info.friendsInterested
                if event.description.isEmpty { nalozenOpis = info.description }
            }
        } catch {
            // Tiho: "I'm in" gumb ostane v zacetnem stanju, ostali zaslon dela naprej.
            // Opis pa ne sme izginiti: isti nadomestni klic kot za goste.
            await naloziPolniOpis()
        }
    }

    /// Opis za dogodek iz LAHKEGA seznama (GET /events?lite=true je brez `description`).
    /// Prijavljeni ga dobijo z loadPlan (isti klic GET /events/:id), zato tu samo gost ali manjkajoc zeton;
    /// dogodek, ki opis ze ima (iskanje, GET /events/:id), ne naredi nic. Tiho ob napaki: brez opisa se
    /// blok "ABOUT" preprosto ne pokaze.
    private func loadOpis() async {
        guard !(session.isLoggedIn && !session.token.isEmpty) else { return }
        await naloziPolniOpis()
    }

    /// GET /events/:id (javno) samo zaradi opisa; ne naredi nic, ce ga dogodek ze ima.
    private func naloziPolniOpis() async {
        guard event.description.isEmpty else { return }
        guard let poln = try? await APIClient.shared.fetchEvent(id: event.id) else { return }
        await MainActor.run { nalozenOpis = poln.description }
    }

    /// Preklopi "I'm in" <-> "Interested" (PUT/DELETE), optimisticno z vrnitvijo ob napaki.
    /// "Going" ni dosegljivo od tu — pride samo z nakupom vstopnice (streznik nastavi plan).
    private func preklopiZanimanje() {
        guard !planSubmitting, myPlan != .going else { return }
        let token = session.token
        guard !token.isEmpty else { return }
        let prejsnje = myPlan
        let novo: EventPlan? = (myPlan == .interested) ? nil : .interested
        withAnimation(.snappy) { myPlan = novo }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        planSubmitting = true
        Task {
            do {
                if let novo {
                    try await APIClient.shared.setEventInterest(token: token, eventId: event.id, plan: novo)
                } else {
                    try await APIClient.shared.clearEventInterest(token: token, eventId: event.id)
                }
            } catch {
                await MainActor.run { withAnimation(.snappy) { myPlan = prejsnje } }
            }
            await MainActor.run { planSubmitting = false }
        }
    }

    /// Klub gostitelj (samo za dogodke z `venue_club_id`); tiho ob napaki: vrstica "at <ime>"
    /// ostane (ime pride z dogodkom), manjka le naslov in zemljevid.
    private func loadVenueClub() async {
        guard let vid = event.venueClubId else { return }
        if let c = try? await APIClient.shared.fetchClub(id: vid) {
            await MainActor.run { venueClub = c }
        }
    }

    private func loadClub() async {
        isLoading = true
        errorText = nil
        do {
            let c = try await APIClient.shared.fetchClub(id: event.clubId)
            await MainActor.run {
                self.club = c
            }
        } catch {
            await MainActor.run {
                self.errorText = error.userMessage
            }
        }
        isLoading = false
    }
}

// MARK: - Helpers
private extension APIClub {
    var addressFull: String {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let co = country.trimmingCharacters(in: .whitespacesAndNewlines)

        if !a.isEmpty && !c.isEmpty { return "\(a) \(c) \(co)".trimmingCharacters(in: .whitespaces) }
        if !a.isEmpty { return "\(a) \(co)".trimmingCharacters(in: .whitespaces) }
        if !c.isEmpty { return "\(c) \(co)".trimmingCharacters(in: .whitespaces) }
        return co.isEmpty ? "-" : co
    }
}

// MARK: - List "VIP tables" (Martin, 28. 9. 2026): rezervacij miz v aplikaciji se ni. Razpored
// miz bo poslal organizator; do takrat list pove, da pride, in napoti na telefon pod kartico.
private struct VipTablesSheet: View {
    let clubName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 5).padding(.top, 8)
            Image(systemName: "table.furniture")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 12)
            Text("VIP tables")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text("\(clubName) has not published a table layout for this event yet.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Call the club to reserve a table.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07).ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
