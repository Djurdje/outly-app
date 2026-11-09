import SwiftUI

/// Znacka »Coming soon« (Martin, 9. 11. 2026, seja: dizajn 2 obvestilo + preliv, barva 2 pol-pol G/E, velikost S6):
/// zaobljen pravokotnik (radij 9, NE kapsula), ozadje #171717, rob 1 pt s prelivom od leve #ECD67F (polno) do desne
/// (alfa 0,06), ravna 3 pt leva crta #ECD67F znotraj oblike (kot CSS inset box-shadow), besedilo #F4E8AE
/// (kontrast na #171717 ~14,5 : 1). NE modra (modra je samo za glavni gumb). Kljuc je loc (en vrednost je izrecna),
/// ker naslov razdelka z istim angleskim besedilom v sl pomeni drugo.
struct ComingSoonZnacka: View {
    private static let ozadje = Color(red: 23/255, green: 23/255, blue: 23/255)
    private static let zlata = Color(red: 236/255, green: 214/255, blue: 127/255)
    private static let besedilo = Color(red: 244/255, green: 232/255, blue: 174/255)
    private static let oblika = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        Text("Coming soon (badge)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Self.besedilo)
            .padding(.top, 7)
            .padding(.bottom, 7)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .background(Self.ozadje)
            // Leva crta 3 pt po vsej visini, porezana z isto obliko (sledi zaobljenima levima kotoma).
            .overlay(alignment: .leading) {
                Self.zlata.frame(width: 3)
            }
            .clipShape(Self.oblika)
            .overlay(
                Self.oblika.strokeBorder(
                    LinearGradient(colors: [Self.zlata, Self.zlata.opacity(0.06)],
                                   startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1)
            )
    }
}

/// Slika iz https URL-ja (OutlyAsyncImage); brez URL-ja ali ob napaki nevtralen nadomestek.
private struct KmaluSlika: View {
    let url: URL?
    var simbol: String = "building.2"

    var body: some View {
        if let url {
            OutlyAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                case .failure:
                    nadomestek
                default:
                    SkeletonBlock()
                }
            }
        } else {
            nadomestek
        }
    }

    private var nadomestek: some View {
        ZStack {
            Color.outlyCard
            Image(systemName: simbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

/// Kartica kluba v vodoravni vrsti na Home: cover 16:10, spodaj preliv, logo + ime + mesto, znacka v kotu.
struct ComingSoonKartica: View {
    let klub: ComingSoonClub

    private let sirina: CGFloat = 280
    private var visina: CGFloat { sirina * 10 / 16 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            KmaluSlika(url: klub.coverURL)
                .frame(width: sirina, height: visina)
                .clipped()

            LinearGradient(colors: [.clear, Color.black.opacity(0.85)],
                           startPoint: .center, endPoint: .bottom)

            HStack(spacing: 10) {
                KmaluSlika(url: klub.logoURL)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(klub.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !klub.city.isEmpty {
                        Text(klub.city)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: sirina, height: visina)
        .overlay(alignment: .topTrailing) {
            ComingSoonZnacka().padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(klub.name), coming soon"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Vodoravna vrsta kartic; vsaka vodi na stran kluba (NavigationLink, brez lastnega NavigationStack).
struct ComingSoonVrsta: View {
    let klubi: [ComingSoonClub]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(klubi) { klub in
                    NavigationLink {
                        ComingSoonClubView(klub: klub)
                    } label: {
                        ComingSoonKartica(klub: klub)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Stevec zahtev za osvezitev razdelka (referenca v @State na HomeView; sprememba polja ne sprozi izrisa).
final class KmaluZahteva {
    var stevec = 0
}
