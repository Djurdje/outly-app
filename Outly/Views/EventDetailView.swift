import SwiftUI
import MapKit
import UIKit

struct EventDetailView: View {
    let event: APIEvent

    @State private var club: APIClub?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showBuy = false
    @State private var showBarPrices = false
    @EnvironmentObject private var session: SessionStore
    /// Srcek (Liked events na domacem zaslonu). Prej na zaslonu dogodka ni bilo srcka.
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.0569, longitude: 14.5058),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                // Pasica DOGODKA; na njej samo vrstica z vstopnicami (Luka 14. 9.).
                hero

                // Ime dogodka + srcek pod pasico
                titleBlock

                // Logo in ime kluba (vodi na stran kluba)
                clubRow

                // Kdaj (med klubom in naslovom)
                whenCard

                // Naslov, kontakt, zemljevid
                infoBlock

                // Cenik bara (migracija 014)
                barPricesButton

                aboutBlock

                Spacer(minLength: 40)
            }
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await loadClub() }
        .sheet(isPresented: $showBuy) {
            BuyTicketsView(event: event, clubName: club?.name ?? String(localized: "Club"))
                .environmentObject(session)
        }
        .sheet(isPresented: $showBarPrices) {
            BarPricesView(clubName: club?.name ?? String(localized: "Club"), items: club?.barPrices ?? [])
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
                    AsyncImage(url: url) { img in
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

    // MARK: - Naslov + srcek (pod sliko)
    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if session.isLoggedIn {
                Button {
                    favorites.toggle(event.id, token: session.token)
                } label: {
                    Image(systemName: favorites.contains(event.id) ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(favorites.contains(event.id) ? Color.outlyBlue : Color.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: favorites.contains(event.id) ? "Remove from liked events" : "Add to liked events"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: - Klub: logo, ime, 18+ -> stran kluba
    private var clubRow: some View {
        NavigationLink {
            ClubDetailView(clubId: event.clubId)
        } label: {
            HStack(spacing: 12) {
                if let club, !club.logoUrl.isEmpty, let url = URL(string: club.logoUrl) {
                    AsyncImage(url: url) { img in
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
                    Text(club?.name ?? String(localized: "Club"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("View club")
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
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    labeled(String(localized: "ADDRESS"), club?.addressFull ?? "-")
                    labeled(String(localized: "PHONE"), club?.contactPhone.isEmpty == false ? club!.contactPhone : "-")
                }

                Spacer(minLength: 0)

                if let club, let lat = club.lat, let lng = club.lng {
                    Map(coordinateRegion: $region, annotationItems: [Pin(lat: lat, lng: lng)]) { pin in
                        MapMarker(coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng))
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .onAppear {
                        region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .opacity(0.10)
                        .frame(width: 150, height: 150)
                        .overlay(Image(systemName: "map").font(.title2))
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
                let n = club?.barPrices.count ?? 0
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
        if !event.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ABOUT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))

                Text(event.description)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
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
private struct Pin: Identifiable {
    let id = UUID()
    let lat: Double
    let lng: Double
}

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
