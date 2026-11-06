import SwiftUI

/// Kratka stran kluba »Coming soon« (6. 11. 2026). Klub ni pravi klub v API-ju: brez nakupa, sledenja in dogodkov.
/// Potisnjen pogled — brez lastnega NavigationStack.
struct ComingSoonClubView: View {
    let klub: ComingSoonClub

    @Environment(\.openURL) private var openURL

    /// Naslov, ce ga ni, mesto.
    private var kje: String { klub.address.isEmpty ? klub.city : klub.address }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cover

                HStack(spacing: 14) {
                    logo
                    VStack(alignment: .leading, spacing: 4) {
                        Text(klub.name)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                        if !kje.isEmpty {
                            Text(kje)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 0)
                }

                ComingSoonZnacka()

                Text("\(klub.name) is coming to Outly soon. Events and tickets will be available here.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                povezave
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .outlyOzadje()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay(slika(klub.coverURL, simbol: "building.2"))
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
    }

    private var logo: some View {
        slika(klub.logoURL, simbol: "building.2")
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func slika(_ url: URL?, simbol: String) -> some View {
        if let url {
            OutlyAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                case .failure:
                    nadomestek(simbol)
                default:
                    SkeletonBlock()
                }
            }
        } else {
            nadomestek(simbol)
        }
    }

    private func nadomestek(_ simbol: String) -> some View {
        ZStack {
            Color.outlyCard
            Image(systemName: simbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // Website / Instagram: samo, ce polje ni prazno in je povezava https; odpreta zunanji brskalnik.
    @ViewBuilder
    private var povezave: some View {
        let splet = klub.websiteURL
        let insta = klub.instagramURL
        if splet != nil || insta != nil {
            HStack(spacing: 12) {
                if let splet {
                    povezava("Website", ikona: "globe", url: splet)
                }
                if let insta {
                    povezava("Instagram", ikona: "camera", url: insta)
                }
            }
        }
    }

    private func povezava(_ naslov: LocalizedStringKey, ikona: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: ikona)
                Text(naslov)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
