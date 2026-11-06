import SwiftUI

/// Znacka »Coming soon«: nevtralna (temna prosojna), NE modra (modra je samo za glavni gumb).
/// Kljuc je loc (en vrednost je izrecna), ker naslov razdelka z istim angleskim besedilom v sl pomeni drugo.
struct ComingSoonZnacka: View {
    var body: some View {
        Text("Coming soon (badge)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
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
