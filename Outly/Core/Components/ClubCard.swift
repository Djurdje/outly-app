import SwiftUI

enum ClubCardVariant {
    case suggestion
    case area
}

struct ClubCard: View {
    let club: APIClub
    let variant: ClubCardVariant

    init(club: APIClub, variant: ClubCardVariant) {
        self.club = club
        self.variant = variant
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
            bannerImage
                .frame(width: 220, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            LinearGradient(
                colors: [.black.opacity(0.65), .black.opacity(0.15)],
                startPoint: .bottom,
                endPoint: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(club.name)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - IN YOUR AREA
    // Kvadratni logo
    // Ime kluba POD sliko
    // Brez lokacije
    private var areaBody: some View {
        VStack(spacing: 8) {
            clubLogo
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            Text(club.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 110)
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
