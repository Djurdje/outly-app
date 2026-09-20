import SwiftUI

/// Pokoncna kartica dogodka s plakatom (vrste Tonight / This week / Liked / Trending).
/// Oznaka zaloge (SOLD OUT, 3 LEFT, FREE) pride iz streznika (availability).
///
/// Od 20. 9.: podatki niso vec pod plakatom, ampak v spodnjem prekrivnem pasu ZNOTRAJ
/// plakata (levo temno zamegljeno: naslov + klub · cas; desno modro: cena; med njima
/// tanko locilo). Kartica je zato nizja (samo plakat) in na zaslon gre vec dogodkov.
/// Plakat sam se ne spreminja.
struct EventPosterCard: View {
    let event: APIEvent
    let clubName: String?
    var width: CGFloat = 150

    private var height: CGFloat { width * 4 / 3 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    private var subtitle: String {
        [clubName ?? "", event.displayDayTime].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            poster
                .frame(width: width, height: height)

            // Rahla zatemnitev proti dnu, da je pas berljiv tudi na svetlih plakatih.
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                .frame(width: width, height: height)
                .allowsHitTesting(false)

            if let badge = event.badgeText {
                Text(badge)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(event.isSoldOut ? .white : .black)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(event.isSoldOut ? Color.red.opacity(0.9) : Color.white.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(10)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                infoBar
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// Dvodelni spodnji pas: levo naslov + klub · cas na zamegljeni podlagi, desno cena na modri.
    private var infoBar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 44)

            Text(event.priceLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 9)
                .frame(minWidth: 44)
                .frame(height: 44)
                .background(Color.outlyBlue)
        }
        .frame(width: width, height: 44)
    }

    @ViewBuilder
    private var poster: some View {
        if !event.posterUrl.isEmpty, let url = URL(string: event.posterUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                        .transition(.opacity)
                default:
                    SkeletonBlock()
                }
            }
        } else {
            // Brez plakata: samo modra v temno (pravilo: brez vijolicnih prelivov).
            ZStack {
                LinearGradient(colors: [Color.outlyBlue.opacity(0.55), Color.outlyBackground], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

/// Utripajoc blok za nalaganje (skeleton) namesto vrtavke.
struct SkeletonBlock: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay(
                LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase * 260)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

/// Vrsta skeleton kartic, dokler podatki ne pridejo.
struct SkeletonRow: View {
    var width: CGFloat = 150
    var height: CGFloat = 200
    var count: Int = 3

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonBlock()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}
