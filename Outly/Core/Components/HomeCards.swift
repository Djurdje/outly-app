import SwiftUI

// Kartice domacega zaslona po Figmi ("homescreen", 20:2): hit tedna, velik dogodek,
// zanri. Slike so vedno v Color.clear.overlay(...).clipped() (past 12).

/// Plakat ali logo iz URL-ja, omejen na okvir starsa. Brez slike -> gradient z znakom.
struct OmejenaSlika: View {
    let urlString: String
    var fallbackSymbol: String = "music.note"

    var body: some View {
        if !urlString.isEmpty, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                default:
                    SkeletonBlock()
                }
            }
        } else {
            ZStack {
                LinearGradient(colors: [Color.outlyBlue.opacity(0.7), Color.purple.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

/// "Last week's biggest hits" / "Trending now": siroka kartica z modrim gradientom,
/// logom kluba, naslovom in plakatom desno (Figma 237:1070).
struct HitCard: View {
    let event: APIEvent
    let club: APIClub?
    let label: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    OmejenaSlika(urlString: club?.logoUrl ?? "", fallbackSymbol: "building.2")
                        .clipShape(Circle())
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(label.uppercased()))
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.75))
                    Text(event.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text([club?.name ?? "", event.displayDayTime].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    if !event.genres.isEmpty {
                        Text(event.genres.map { $0.uppercased() }.joined(separator: "  "))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    if event.soldCount > 0 {
                        Text("\(event.soldCount) going")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            OmejenaSlika(urlString: event.posterUrl)
                .frame(width: 130)
        }
        .frame(height: 150)
        .background(
            LinearGradient(colors: [Color(red: 0, green: 14/255, blue: 61/255),
                                    Color(red: 25/255, green: 53/255, blue: 142/255),
                                    Color(red: 46/255, green: 71/255, blue: 153/255)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// "Big Events Coming Up": velik plakat cez celo sirino z logom in imenom kluba
/// zgoraj ter datumom/ceno spodaj (Figma 408:802).
struct HeroEventCard: View {
    let event: APIEvent
    let club: APIClub?

    var body: some View {
        ZStack(alignment: .top) {
            OmejenaSlika(urlString: event.posterUrl)

            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading) {
                HStack(spacing: 12) {
                    OmejenaSlika(urlString: club?.logoUrl ?? "", fallbackSymbol: "building.2")
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(club?.name ?? "")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("BIG EVENT COMING UP")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                    if let badge = event.badgeText {
                        Text(badge)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(event.isSoldOut ? .white : .black)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(event.isSoldOut ? Color.red.opacity(0.9) : Color.white.opacity(0.92))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(event.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 10) {
                    Label(event.displayDayTime, systemImage: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(ticketBadgeText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.outlyBlue)
                        .clipShape(Capsule())
                }
            }
            .padding(16)
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// Besedilo modrega znacka spodaj desno; loceno od View-ja, ker je bila gnezdena
    /// ternarka niz (Text(String)) in se ni prevajala.
    private var ticketBadgeText: String {
        if event.isSoldOut { return String(localized: "Sold out") }
        if let price = event.displayPrice { return price }
        if event.ticketUrl?.isEmpty == false { return String(localized: "Tickets") }
        return String(localized: "Free")
    }
}

/// "Discover your genre": vrstica zanra (Figma 838:1645) — plakat dogodka tega zanra
/// zatemnjen, sicer barvni gradient; ime zanra na sredini.
struct GenreRow: View {
    let genre: String
    let posterUrl: String
    let count: Int

    private var odtenek: Color {
        // Deterministicna barva po imenu (hashValue je v Swiftu nakljucen ob vsakem zagonu).
        let vsota = genre.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let h = Double(vsota % 360) / 360.0
        return Color(hue: h, saturation: 0.55, brightness: 0.55)
    }

    var body: some View {
        ZStack {
            if !posterUrl.isEmpty {
                OmejenaSlika(urlString: posterUrl).opacity(0.55)
            } else {
                LinearGradient(colors: [odtenek, odtenek.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
            }
            Color.black.opacity(0.25)
            HStack {
                Text(genre.uppercased())
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(.white)
                Spacer()
                if count > 0 {
                    Group {
                        if count == 1 {
                            Text("1 event")
                        } else {
                            Text("\(count) events")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Iskalno polje "Where to?" (Figma 37:122), od 20. 9. dvodelno: levo lupa + "Where to?"
/// (odpre iskanje), desno ikona filtra (odpre Filtre). Isti okvir, isto ozadje in obroba,
/// med deloma samo tanko navpicno locilo — filter NI videti kot loceni gumb.
/// Barve kot vrstice nastavitev (bela 8 %, obroba 14 %, radij 14), ne vec polna siva #2F2E2E.
struct WhereToField: View {
    var onSearch: () -> Void = {}
    var onFilter: () -> Void = {}
    /// true = filtri so nastavljeni (modra pika ob ikoni).
    var filterActive: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSearch) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Where to?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
                .padding(.vertical, 12)

            Button(action: onFilter) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .overlay(alignment: .topTrailing) {
                        if filterActive {
                            Circle().fill(Color.outlyBlue).frame(width: 7, height: 7).offset(x: 4, y: -3)
                        }
                    }
                    .frame(width: 52, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Filters"))
        }
        .frame(height: 48)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
