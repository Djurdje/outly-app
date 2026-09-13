import SwiftUI

/// Pokoncna kartica dogodka s plakatom (vrste Tonight / This weekend / Trending).
/// Oznaka zaloge (SOLD OUT, 3 LEFT, FREE) pride iz streznika (availability).
struct EventPosterCard: View {
    let event: APIEvent
    let clubName: String?
    var width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                poster
                    .frame(width: width, height: width * 4 / 3)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .frame(width: width, height: width * 4 / 3)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(event.priceLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                    }
                }
                .padding(10)
                .frame(width: width, height: width * 4 / 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text([clubName ?? "", event.displayDayTime].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
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
            ZStack {
                LinearGradient(colors: [Color.outlyBlue.opacity(0.7), Color.purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    SkeletonBlock().frame(width: width * 0.8, height: 12).clipShape(Capsule())
                    SkeletonBlock().frame(width: width * 0.5, height: 10).clipShape(Capsule())
                }
            }
        }
    }
}
