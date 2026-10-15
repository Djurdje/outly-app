import SwiftUI

enum ClubCardVariant {
    case suggestion
    case area
}

struct ClubCard: View {
    let club: APIClub
    let variant: ClubCardVariant
    /// Razdalja do kluba v km (samo "In your area"); nil = ni znana.
    var distanceKm: Double? = nil
    /// true = logo zatemnjen in cez njega razdalja (po prvem dotiku).
    var showDistance: Bool = false

    init(club: APIClub, variant: ClubCardVariant, distanceKm: Double? = nil, showDistance: Bool = false) {
        self.club = club
        self.variant = variant
        self.distanceKm = distanceKm
        self.showDistance = showDistance
    }

    private var distanceText: String {
        guard let d = distanceKm else { return "" }
        return d < 1 ? "\(Int(d * 1000)) m" : String(format: "%.1f km", d)
    }

    var body: some View {
        switch variant {
        case .suggestion:
            suggestionBody
        case .area:
            areaBody
        }
    }

    // MARK: - SUGGESTIONS
    // Banner
    // Ime kluba CENTER
    // Brez lokacije
    private var suggestionBody: some View {
        ZStack {
            // Figma 37:151: 188x123, radij 14, slika zatemnjena, ime na sredini.
            bannerImage
                .frame(width: 188, height: 123)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.35)],
                startPoint: .bottom,
                endPoint: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(club.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
        }
        .frame(width: 188, height: 123)
        .overlay(alignment: .topLeading) {
            if club.isDemo { DemoZnacka(kompakten: true).padding(8) }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - IN YOUR AREA
    // Kvadratni logo
    // Ime kluba POD sliko
    // Brez lokacije
    private var areaBody: some View {
        VStack(spacing: 8) {
            // Figma 389:773: kvadrat 121, radij 10, ime pod sliko.
            clubLogo
                .frame(width: 121, height: 121)
                .overlay(
                    ZStack {
                        Color.black.opacity(showDistance ? 0.62 : 0)
                        if showDistance {
                            VStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                // Martin (14. 10. 2026): samo razdalja je modra s subtilnim sijem; ikona in »Tap to open« ostaneta beli.
                                Text(distanceText)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color.outlyBlue)
                                    .shadow(color: Color.outlyBlue.opacity(0.8), radius: 6)
                                    .shadow(color: Color.outlyBlue.opacity(0.4), radius: 12)
                                Text("Tap to open")
                                    .font(.system(size: 10, weight: .medium))
                                    .opacity(0.7)
                            }
                            .foregroundStyle(.white)
                            .transition(.opacity)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(showDistance ? 0.35 : 0.10), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if club.isDemo && !showDistance { DemoZnacka(kompakten: true).padding(6) }
                }
                .animation(.easeOut(duration: 0.15), value: showDistance)

            Text(club.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(width: 121)
    }

    // MARK: - Helpers

    /// Prva slika slideshowa (in sele ce je ni, stara pasica — glej APIClub.slideshowUrls).
    /// Od 22. 9. klub pasice ne nalaga vec, zato je to za nove klube prva slika slideshowa.
    @ViewBuilder
    private var bannerImage: some View {
        if
            let prva = club.slideshowUrls.first, !prva.isEmpty,
            let url = URL(string: prva)
        {
            OutlyAsyncImage(url: url) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                Rectangle().opacity(0.15)
            }
        } else {
            Rectangle()
                .opacity(0.15)
                .overlay(Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.5)))
        }
    }

    @ViewBuilder
    private var clubLogo: some View {
        if
            !club.logoUrl.isEmpty,
            let url = URL(string: club.logoUrl)
        {
            OutlyAsyncImage(url: url) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                RoundedRectangle(cornerRadius: 22)
                    .opacity(0.15)
            }
        } else {
            RoundedRectangle(cornerRadius: 22)
                .opacity(0.15)
                .overlay(
                    Text(initialLetter)
                        .font(.title.bold())
                )
        }
    }

    private var initialLetter: String {
        String(club.name.prefix(1)).uppercased()
    }
}
