import SwiftUI

/// Ozadje zaslonov (Martin/Luka, 21. 9. 2026, "kot Revolut"): zavihka Search in Profile ne
/// odpreta svojega crnega zaslona, ampak lezita nad zamegljenim, zamrznjenim posnetkom
/// domacega zaslona (MainTabView ga posname ob preklopu zavihka). Zato vsak zaslon, ki je
/// prej imel `.background(Color.black.ignoresSafeArea())`, uporabi `.outlyOzadje()`:
/// v zavihku s posnetkom je prosojen (posnetek se vidi), sicer crn kot prej.
/// Potisnjeni pogledi podedujejo okolje, zato velja tudi zanje (Revolut: cel sklad).
private struct ProsojnoOzadjeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// true = zaslon lezi nad posnetkom domacega zaslona in ne sme risati crnega ozadja.
    var prosojnoOzadje: Bool {
        get { self[ProsojnoOzadjeKey.self] }
        set { self[ProsojnoOzadjeKey.self] = newValue }
    }
}

private struct OutlyOzadjeModifier: ViewModifier {
    @Environment(\.prosojnoOzadje) private var prosojno

    func body(content: Content) -> some View {
        content.background((prosojno ? Color.clear : Color.black).ignoresSafeArea())
    }
}

extension View {
    /// Crno ozadje zaslona, ki se umakne posnetku domacega zaslona (glej ProsojnoOzadjeKey).
    func outlyOzadje() -> some View { modifier(OutlyOzadjeModifier()) }
}

/// Zamegljen, zatemnjen posnetek domacega zaslona kot ozadje zavihka (Search, Profile).
/// Brez posnetka (prvi prikaz pred prvim preklopom) je crn.
struct HomeSnapshotBackground: View {
    let slika: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let slika {
                Image(uiImage: slika)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28, opaque: true)
                    .overlay(Color.black.opacity(0.62))
            }
        }
        .ignoresSafeArea()
    }
}

extension UIApplication {
    /// Posnetek trenutnega zaslona (kar uporabnik vidi zdaj) — klice se PRED preklopom zavihka,
    /// da posnetek kaze domaci zaslon tam, kjer je uporabnik ostal.
    func posnetekZaslona() -> UIImage? {
        let okno = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let okno else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // polovicna locljivost zadostuje, saj se slika zamegli
        return UIGraphicsImageRenderer(bounds: okno.bounds, format: format).image { _ in
            okno.drawHierarchy(in: okno.bounds, afterScreenUpdates: false)
        }
    }
}
