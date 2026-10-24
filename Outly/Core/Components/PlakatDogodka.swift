import SwiftUI

/// Plakat dogodka v okvirju, ki ga doloci klicatelj (23. 10. 2026, Martin: plakat naj bo povsod tak,
/// kot ga je organizator nalozil, okvirji kartic pa ostanejo enaki).
///
/// - Plakat je CEL (aspect fit, nic odrezanega), razmerje stranic ostane tako, kot je bilo naloženo.
/// - Prazen prostor ob straneh/zgoraj/spodaj zapolni zamegljena in zatemnjena kopija istega plakata.
/// - Zamegljeno ozadje je drobna sliccica (~48 px, nastane ob prenosu v `SlikovniPredpomnilnik`),
///   raztegnjena na okvir z mehkim vzorcenjem: brez `.blur` na sliki polne locljivosti
///   (pravilo 3, outly-app #33) in brez dodatnih omrezij klicev.
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
                ZStack {
                    zamegljenoOzadje
                    // Cel plakat: fit znotraj okvirja, nic odrezanega.
                    Color.clear.overlay(img.resizable().scaledToFit()).clipped()
                }
            default:
                if mirenPlaceholder {
                    Rectangle().fill(Color.white.opacity(0.08))
                } else {
                    SkeletonBlock()
                }
            }
        }
    }

    @ViewBuilder
    private var zamegljenoOzadje: some View {
        ZStack {
            if let drobna = SlikovniPredpomnilnik.ozadje(url) {
                Color.clear.overlay(
                    Image(uiImage: drobna)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                ).clipped()
            } else {
                Color(white: 0.08)
            }
            Color.black.opacity(0.38)
        }
    }
}
