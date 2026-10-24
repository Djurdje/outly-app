import SwiftUI

enum EventCardVariant {
    case clubRow
    case homeRow
    case hero
}

struct EventCardAPI: View {
    let event: APIEvent
    let clubName: String?
    let clubLogoUrl: String?
    let variant: EventCardVariant
    /// Znacka "Going"/"Interested" namesto srcka (Martin, 24. 9. 2026: srcek je odstranjen,
    /// nadomestil ga je "I'm in"). nil = brez znacke (privzeto, obratna zdruzljivost klicev).
    let planBadge: EventPlan?

    init(
        event: APIEvent,
        clubName: String? = nil,
        clubLogoUrl: String? = nil,
        variant: EventCardVariant = .clubRow,
        planBadge: EventPlan? = nil
    ) {
        self.event = event
        self.clubName = clubName
        self.clubLogoUrl = clubLogoUrl
        self.variant = variant
        self.planBadge = planBadge
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
    // Levo plakat (Figma "Coming Soon"), sredina: naslov, zanri, datum; desno cena (modra z rahlim
    // sijem) in znacka. Kartica je cez vso sirino (Martin, 29. 9. 2026: vse kartice enako dolge kot
    // okvir videa na strani kluba, ne vsaka po dolzini naslova).
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

                Text(event.displayDateShort)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))

                // Gostovan dogodek organizatorja (backend 037): ime organizatorja pod datumom.
                if event.hosted, let clubName, !clubName.isEmpty {
                    Text(clubName)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(event.priceLabel)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.outlyBlue)
                    .lineLimit(1)
                    .fixedSize()
                    // Rahel sij, blizu gumbov (Sij.swift), a sibkejsi - to je napis, ne gumb.
                    .shadow(color: Color.outlyBlue.opacity(0.55), radius: 4)
                    .shadow(color: Color.outlyBlue.opacity(0.30), radius: 10)

                if event.hosted {
                    Text("Hosted")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                }

                if let planBadge {
                    znacka(planBadge)
                }

                if event.isDemo {
                    DemoZnacka()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Majhna znacka "Going" (moder poln pil) ali "Interested" (bela obroba) — glej CLAUDE.md
    /// (modra samo na glavnem gumbu ostaja, tu gre za status, ne gumb za dejanje).
    private func znacka(_ plan: EventPlan) -> some View {
        Text(plan == .going ? "Going" : "Interested")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(plan == .going ? .white : Color.white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule().fill(plan == .going ? Color.outlyBlue : Color.clear)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(plan == .going ? 0 : 0.5), lineWidth: 1)
            )
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

                if event.isDemo {
                    DemoZnacka(kompakten: true)
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
            PlakatDogodkaSlika(url: url, mirenPlaceholder: true)
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
        .overlay(alignment: .topTrailing) {
            if event.isDemo { DemoZnacka().padding(14) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var heroPoster: some View {
        if !event.posterUrl.isEmpty, let url = URL(string: event.posterUrl) {
            PlakatDogodkaSlika(url: url, mirenPlaceholder: true)
        } else {
            RoundedRectangle(cornerRadius: 24)
                .opacity(0.12)
                .overlay(Image(systemName: "ticket").font(.largeTitle).foregroundStyle(.white.opacity(0.4)))
        }
    }
}
