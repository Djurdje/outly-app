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
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await loadClub() }
        .sheet(isPresented: $showBuy) {
            BuyTicketsView(event: event, clubName: club?.name ?? "Club")
                .environmentObject(session)
        }
        .sheet(isPresented: $showBarPrices) {
            BarPricesView(clubName: club?.name ?? "Club", items: club?.barPrices ?? [])
        }
    }

    // MARK: - Hero: pasica dogodka (plakat); na njej samo vrstica z vstopnicami, sredinsko,
    // malo dvignjena od dna. Naslov in kdaj sta pod sliko (Lukov popravek 14. 9. zvecer).
    private var headerImageUrl: String {
        if !event.posterUrl.isEmpty { return event.posterUrl }
        return club?.bannerUrl ?? ""
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if !headerImageUrl.isEmpty, let url = URL(string: headerImageUrl) {
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
            }

            ticketBar
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .frame(height: heroHeight)
        .clipped()
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
                .accessibilityLabel(favorites.contains(event.id) ? "Remove from liked events" : "Add to liked events")
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
                    Text(club?.name ?? "Club")
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

            if let rel = relativeLabel {
                Text(rel)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(rel == "TONIGHT" ? Color.black : Color.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(rel == "TONIGHT" ? Color.white : Color.white.opacity(0.10))
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
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "MMM"
        return f.string(from: d)
    }
    private var dayNumber: String {
        guard let d = event.startDate else { return "–" }
        return String(Calendar.current.component(.day, from: d))
    }
    private var dayLong: String {
        guard let d = event.startDate else { return event.startAt }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE, d MMMM"
        return f.string(from: d)
    }
    private var timeRange: String {
        guard let d = event.startDate else { return "" }
        let t = DateParsing.shortTime.string(from: d)
        if let e = event.endDate {
            return "\(t) – \(DateParsing.shortTime.string(from: e))"
        }
        return "Starts at \(t)"
    }
    private var relativeLabel: String? {
        guard let d = event.startDate else { return nil }
        let cal = Calendar.current
        if event.isPast { return "ENDED" }
        if cal.isDateInToday(d) { return "TONIGHT" }
        if cal.isDateInTomorrow(d) { return "TOMORROW" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        if days > 0 && days <= 14 { return "IN \(days) DAYS" }
        return nil
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
        let price = event.displayPrice ?? "Tickets"

        let (top, sub, button): (String, String, String?) = {
            switch state {
            case .buy:          return (price, "per ticket", "Get tickets")
            case .free:         return ("FREE", "free entry", "Get tickets")
            case .fewLeft(let n): return (price, n == 1 ? "last ticket" : "only \(n) left", "Get tickets")
            case .external:     return ("Tickets", "sold by the club", "Open")
            case .door:         return ("Tickets", "at the door", nil)
            case .soldOut:      return (price, "sold out", nil)
            case .ended:        return ("Ended", "event is over", nil)
            }
        }()

        let active: Bool = {
            if case .buy = state { return true }
            if case .free = state { return true }
            if case .fewLeft = state { return true }
            if case .external = state { return true }
            return false
        }()

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(top)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(sub)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(active ? 0.8 : 0.55))
            }

            Spacer(minLength: 8)

            if let button {
                HStack(spacing: 6) {
                    Text(button)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(active ? Color.outlyBlue : Color.white.opacity(0.6))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(active ? Color.white : Color.white.opacity(0.10))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        // Modra kot v Figmi, malo prosojna (Luka 14. 9.), ker lezi na plakatu. Neaktivna stanja temna.
        .background(active ? Color.outlyBlue.opacity(0.82) : Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(active ? 0 : 0.14), lineWidth: 1)
        )
        .shadow(color: active ? Color.outlyBlue.opacity(0.35) : .black.opacity(0.35), radius: 16, y: 6)
        .contentShape(Rectangle())
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
    }


    // MARK: - Info block (address/phone/map style)
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    labeled("ADDRESS", club?.addressFull ?? "-")
                    labeled("PHONE", club?.contactPhone.isEmpty == false ? club!.contactPhone : "-")
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
                Text(n == 0 ? "Not added yet" : "\(n) items")
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
