import SwiftUI

enum ClubCardVariant {
    case suggestion
    case area
}

struct ClubCard: View {
    let club: APIClub
    let variant: ClubCardVariant
    /// Razdalja do kluba v km (samo "Near you"); nil = ne prikazi.
    var distanceKm: Double? = nil

    init(club: APIClub, variant: ClubCardVariant, distanceKm: Double? = nil) {
        self.club = club
        self.variant = variant
        self.distanceKm = distanceKm
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))

            Text(club.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)

            if let d = distanceKm {
                Text(d < 1 ? "\(Int(d * 1000)) m" : String(format: "%.1f km", d))
                    .font(.caption)
                    .foregroundStyle(Color.outlyBlue)
            }
        }
        .frame(width: 121)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var bannerImage: some View {
        if
            !club.bannerUrl.isEmpty,
            let url = URL(string: club.bannerUrl)
        {
            AsyncImage(url: url) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                Rectangle().opacity(0.15)
            }
        } else {
            Rectangle()
                .opacity(0.15)
                .overlay(Text("🎧").font(.largeTitle))
        }
    }

    @ViewBuilder
    private var clubLogo: some View {
        if
            !club.logoUrl.isEmpty,
            let url = URL(string: club.logoUrl)
        {
            AsyncImage(url: url) { img in
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
