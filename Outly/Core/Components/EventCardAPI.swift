import SwiftUI
import UIKit

enum EventCardVariant {
    case clubRow
    case homeRow
    case hero
}

struct EventCardAPI: View {
    /// Priljubljeni dogodki — na strezniku (FavoritesStore, migracija 012).
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var session: SessionStore

    private var isFavorite: Bool { favorites.contains(event.id) }
    private func toggleFavorite() {
        favorites.toggle(event.id, token: session.token)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    let event: APIEvent
    let clubName: String?
    let clubLogoUrl: String?
    let variant: EventCardVariant

    init(
        event: APIEvent,
        clubName: String? = nil,
        clubLogoUrl: String? = nil,
        variant: EventCardVariant = .clubRow
    ) {
        self.event = event
        self.clubName = clubName
        self.clubLogoUrl = clubLogoUrl
        self.variant = variant
    }

    var body: some View {
        Group {
            switch variant {
            case .clubRow:
                clubRowBody
            case .homeRow:
                homeRowBody
            case .hero:
                heroBody
            }
        }
    }

    // MARK: - CLUB ROW
    // Levo plakat (Figma "Coming Soon"), sredina: naslov, zanri, cena; desno datum + srce.
    private var clubRowBody: some View {
        HStack(spacing: 12) {
            eventPosterSmall
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                if !event.genres.isEmpty {
                    Text(event.genres.map { $0.capitalized }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(event.priceLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                    Text("·").foregroundStyle(Color.white.opacity(0.4))
                    Text(event.displayDateShort)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }

            Spacer(minLength: 8)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isFavorite ? Color.red : Color.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - HOME ROW
    // desno: banner (visok kot gumb)
    // levo: logo kluba + info
    private var homeRowBody: some View {
        HStack(spacing: 12) {
            eventPosterSmall
                .frame(width: 60, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let clubName, !clubName.isEmpty {
                    Text(clubName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    if !event.displayTimeShort.isEmpty {
                        Label(event.displayTimeShort, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if event.minAge > 0 {
                        Label("\(event.minAge)+", systemImage: "person.crop.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // desni "banner" (visok kot gumb)
            VStack {
                Text(event.displayPrice ?? String(localized: "BUY"))
                    .font(.subheadline.bold())
                    .foregroundStyle(event.isPast ? Color.white.opacity(0.7) : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(event.isPast ? Color.blackColor.opacity(0.35) : Color.white)
                    .clipShape(Capsule())

            }
        }
        .padding(5)
        .frame(minHeight: 92)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var eventPosterSmall: some View {
        if
            !event.posterUrl.isEmpty,
            let url = URL(string: event.posterUrl)
        {
            AsyncImage(url: url) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14)
                    .opacity(0.12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .opacity(0.12)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4)))
        }
    }

    private func initialLetter(from name: String?) -> String {
        guard let name, let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "O"
        }
        return String(first).uppercased()
    }

    // MARK: - HERO
    // Zahteva: dosti višji, NI gumba za ceno
    // info NI levo spodaj, ampak zgoraj
    private var heroBody: some View {
        ZStack(alignment: .topLeading) {
            heroPoster
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            // gradient za berljivost zgoraj
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.black.opacity(0.15), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 6) {
                if let clubName, !clubName.isEmpty {
                    Text(clubName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }

                Text(event.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if !event.displayDateShort.isEmpty { Text(event.displayDateShort) }
                    if !event.displayTimeShort.isEmpty { Text(event.displayTimeShort) }
                    if event.minAge > 0 { Text("\(event.minAge)+") }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

                if !event.genres.isEmpty {
                    Text(event.genres.map { $0.capitalized }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var heroPoster: some View {
        if !event.posterUrl.isEmpty, let url = URL(string: event.posterUrl) {
            AsyncImage(url: url) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                Rectangle().opacity(0.12)
            }
        } else {
            RoundedRectangle(cornerRadius: 24)
                .opacity(0.12)
                .overlay(Image(systemName: "ticket").font(.largeTitle).foregroundStyle(.white.opacity(0.4)))
        }
    }
}
