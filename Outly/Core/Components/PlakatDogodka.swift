import SwiftUI

/// Banner dogodka v okvirju, ki ga doloci klicatelj (8. 11. 2026, Luka, outly-backend#400: slika vedno zapolni cel
/// okvir, brez zamegljenega roba; nadomesti odlocitev 23. 10. 2026 »cel plakat + zamegljen rob«).
///
/// - Slika je FILL (`scaledToFill`, sredina), obrezana na okvir. Prazen rob ne obstaja.
/// - Velik banner (4:5): glava dogodka in »Big events coming up« podata `posterUrl`; majhne prikaze klicatelji
///   napolnijo s `posterSmallUrl` (majhen banner 3:4, sicer velik).
/// - Pravilo slik: okvir vedno doloci `Color.clear.overlay(...).clipped()`, slika sama okvirja ne siri.
///
/// Velikost okvirja doloci klicatelj (`.frame`, `.aspectRatio`, ...); gradnik zapolni ponujeni prostor.
struct PlakatDogodka: View {
    let urlString: String
    /// Ikona na modrem ozadju, ko dogodek nima plakata.
    var fallbackSymbol: String = "music.note"
    /// true = tih (nepremicen) nadomestek med nalaganjem, za majhne sliccice v seznamih.
    var mirenPlaceholder: Bool = false

    var body: some View {
        if !urlString.isEmpty, let url = URL(string: urlString) {
            PlakatDogodkaSlika(url: url, mirenPlaceholder: mirenPlaceholder)
        } else {
            ZStack {
                // Brez plakata: samo modra v temno (pravilo: brez vijolicnih prelivov), kot EventPosterCard.
                LinearGradient(colors: [Color.outlyBlue.opacity(0.55), Color.outlyBackground],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

/// Samo slika z znanim URL-jem (klicatelji z lastnim nadomestkom za dogodek brez plakata).
struct PlakatDogodkaSlika: View {
    let url: URL
    var mirenPlaceholder: Bool = false

    var body: some View {
        OutlyAsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            default:
                if mirenPlaceholder {
                    Rectangle().fill(Color.white.opacity(0.08))
                } else {
                    SkeletonBlock()
                }
            }
        }
    }
}
