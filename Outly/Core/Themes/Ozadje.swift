import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Ozadje zaslonov (Luka, 21. 9. 2026, "kot Revolut"): zavihka Search in Profile ne odpreta
/// svojega crnega zaslona, ampak lezita nad zamegljenim, zamrznjenim posnetkom domacega zaslona.
/// MainTabView posnetek naredi ob preklopu zavihka in ga da v okolje (`posnetekDoma`).
/// Vsak zaslon, ki je prej imel `.background(Color.black.ignoresSafeArea())`, uporabi `.outlyOzadje()`:
/// s posnetkom v okolju narise posnetek, sicer crno. Ozadje rise VSAK zaslon sam (tudi potisnjeni),
/// ker NavigationStack pod seboj ne pusti videti nicesar — prvi poskus z ZStackom pod
/// NavigationStackom (build 64) je ostal crn.
private struct PosnetekDomaKey: EnvironmentKey {
    static let defaultValue: UIImage? = nil
}

extension EnvironmentValues {
    /// Ze zamegljen posnetek domacega zaslona; nil = navadno crno ozadje.
    var posnetekDoma: UIImage? {
        get { self[PosnetekDomaKey.self] }
        set { self[PosnetekDomaKey.self] = newValue }
    }
}

private struct OutlyOzadjeModifier: ViewModifier {
    @Environment(\.posnetekDoma) private var posnetek

    func body(content: Content) -> some View {
        content.background(HomeSnapshotBackground(slika: posnetek))
    }
}

extension View {
    /// Crno ozadje zaslona oziroma zamegljen domaci zaslon, ce ga okolje ima (glej PosnetekDomaKey).
    func outlyOzadje() -> some View { modifier(OutlyOzadjeModifier()) }
}

/// Zamegljen (ze ob zajemu), zatemnjen posnetek domacega zaslona; brez posnetka crno.
struct HomeSnapshotBackground: View {
    let slika: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let slika {
                Image(uiImage: slika)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(0.6))
            }
        }
        .ignoresSafeArea()
    }
}

/// Samostojna zameglitev (cisto racunanje na CIImage/CGImage, brez UIKit hierarhije).
enum OzadnjaZameglitev {
    /// CIContext je drag za ustvarit (prevede si cevovod senčilnikov) — prej je nastal ob VSAKEM
    /// posnetku in je bil glavni del zamika. Zdaj nastane enkrat na zagon aplikacije.
    private static let ciKontekst = CIContext(options: [.useSoftwareRenderer: false])

    /// Zamegli ze zajet posnetek (CIGaussianBlur); radij v pikslih se prilagodi merilu SLIKE,
    /// zato deluje na posnetku katerekoli locljivosti.
    static func zamegli(_ slika: UIImage) -> UIImage? {
        guard let cg = slika.cgImage else { return nil }
        let vhod = CIImage(cgImage: cg)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = vhod.clampedToExtent()
        // Radij v PIKSLIH: pri merilu 0.25 je 22 pt enako 22 * 0.25 piksla, pri merilu 1.0 pa 22 pt.
        filter.radius = Float(22 * slika.scale)
        guard let izhod = filter.outputImage?.cropped(to: vhod.extent) else { return nil }
        guard let rezultat = ciKontekst.createCGImage(izhod, from: vhod.extent) else { return nil }
        return UIImage(cgImage: rezultat, scale: slika.scale, orientation: slika.imageOrientation)
    }
}

extension UIApplication {
    /// Kljucno okno (edino mesto, kjer to iscemo — uporabljata ga tako surovPosnetek kot
    /// prekrivna plast krozhnega razkritja v MainTabView za velikost zaslona).
    var kljucnoOkno: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// Oster zajem trenutnega zaslona v danem merilu (pikslov na tocko), BREZ zameglitve.
    /// Klice se na glavni niti (drawHierarchy je UIKit, samo glavna nit) — zato je sinhrona.
    /// Za ozadje zavihka (zamegljeno, cetrtina locljivosti) uporabi `posnetekZaslona()`.
    /// Za prekrivno plast "krozhnega razkritja" (Martin, 23. 9.) uporabi merilo 1.0 — plast
    /// je vidna oster med rastjo/krcitvijo, cetrtinska locljivost bi bila tam vidno zrnata.
    func surovPosnetek(merilo: CGFloat = Self.meriloPosnetka) -> UIImage? {
        guard let okno = kljucnoOkno else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = merilo
        format.opaque = true  // brez alfa kanala je risanje hitrejse (ozadje je itak crno)
        return UIGraphicsImageRenderer(bounds: okno.bounds, format: format).image { _ in
            okno.drawHierarchy(in: okno.bounds, afterScreenUpdates: false)
        }
    }

    /// Zamegli ze zajet posnetek (CIGaussianBlur) — ovoj okrog OzadnjaZameglitev.
    func zamegljenPosnetek(iz slika: UIImage) -> UIImage? {
        OzadnjaZameglitev.zamegli(slika)
    }

    /// Posnetek trenutnega zaslona, ze zamegljen (CIGaussianBlur) — klice se PRED preklopom
    /// zavihka, da kaze domaci zaslon tam, kjer je uporabnik ostal. Ostaja kot ovoj za FiltersView
    /// (posnetekZaFiltre v HomeView), ki ga rabi sinhrono, preden se zaslon Filtri odpre.
    func posnetekZaslona() -> UIImage? {
        // Posnetek se zajame v CETRTINI locljivosti (Martin, 22. 9.: "filter ozadje dolgo nalaga").
        // Zajem in zameglitev sta bila prej na polni locljivosti in sta se zgodila SINHRONO,
        // preden se je zaslon Filtri sploh odprl — od dotika do zaslona je bila vidna luknja.
        // Slika se tako ali tako zamegli z radijem 22 pt, torej vse pod 22 pt izgine; pri cetrtini
        // je najmanjsa ohranjena podrobnost 4 pt, kar je globoko pod mejo. Pikslov je 16x manj.
        guard let surov = surovPosnetek(merilo: Self.meriloPosnetka) else { return nil }
        return zamegljenPosnetek(iz: surov) ?? surov
    }

    /// Koliko pikslov na tocko ima posnetek za ozadje zavihka. 0.25 = cetrtina locljivosti.
    fileprivate static let meriloPosnetka: CGFloat = 0.25
}
