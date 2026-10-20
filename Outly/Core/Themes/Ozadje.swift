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

/// "Kot Revolut" krcenje/rast vsebine (Martin, 24. 9. 2026, zamenjava za krozno razkritje iz PR #22):
/// ob preklopu Home<->Search/Profile MainTabView to vrednost animira, `.outlyOzadje()` pa jo
/// prebere in z njo skalira/zbledi/zamegli SVOJO vsebino (ne ozadja pod njo) — tako vsebina
/// "zraste" iz sidra (sredisce avatarja/polja Where to?) namesto da bi navaden TabView samo
/// zamenjal zaslon. Privzeta vrednost je "nevtralna" (skala 1, brez prosojnosti/zameglitve),
/// zato je za Home/Map brez ucinka, ce jo MainTabView ne spremeni.
struct VstopZavihka: Equatable {
    var skala: CGFloat = 1
    var prosojnost: Double = 1
    var zameglitev: CGFloat = 0
    /// Sidro skaliranja v LASTNIH koordinatah vsebine (0...1) — sredisce avatarja/polja Where to?,
    /// preracunano iz okenskih koordinat glede na velikost okna (MainTabView).
    var sidro: UnitPoint = .topLeading

    static let privzeto = VstopZavihka()
}

private struct VstopZavihkaKey: EnvironmentKey {
    static let defaultValue = VstopZavihka.privzeto
}

extension EnvironmentValues {
    /// Trenutno stanje "rasti/krcenja" vsebine zavihka (glej VstopZavihka).
    var vstopZavihka: VstopZavihka {
        get { self[VstopZavihkaKey.self] }
        set { self[VstopZavihkaKey.self] = newValue }
    }
}

private struct OutlyOzadjeModifier: ViewModifier {
    @Environment(\.posnetekDoma) private var posnetek
    @Environment(\.vstopZavihka) private var vstop
    @Environment(\.accessibilityReduceMotion) private var zmanjsanoGibanje

    func body(content: Content) -> some View {
        Group {
            if zmanjsanoGibanje {
                // Trdo pravilo (Martin, 24. 9.): pri Reduce Motion samo prosojnost, brez skale/zameglitve.
                content.opacity(vstop.prosojnost)
            } else {
                // Brez .blur na ZIVI vsebini (Martin, 25. 9.: "tranzicije stekajo"): animiran Gaussov
                // blur cez cel zaslon s slikami vsak frame znova rise in zamegli celo plast, skupaj s
                // skaliranjem pade pod 60 fps. Zameglitev ostane samo na posnetkih (ozadje, plast).
                content
                    .scaleEffect(vstop.skala, anchor: vstop.sidro)
                    .opacity(vstop.prosojnost)
            }
        }
        .background(HomeSnapshotBackground(slika: posnetek))
    }
}

extension View {
    /// Crno ozadje zaslona oziroma zamegljen domaci zaslon, ce ga okolje ima (glej PosnetekDomaKey),
    /// in "rast/krcenje" vsebine iz sidra, ce ga okolje ima (glej VstopZavihka).
    func outlyOzadje() -> some View { modifier(OutlyOzadjeModifier()) }
}

/// Zamegljen (ze ob zajemu), zatemnjen posnetek domacega zaslona; brez posnetka crno.
struct HomeSnapshotBackground: View {
    let slika: UIImage?

    var body: some View {
        ZStack {
            Color.black
            // Samo veljavna slika (merilo >= 1, velikost > 0): sicer SwiftUI ob razresevanju za nove
            // lastnosti zaslona zrusi aplikacijo v CoreUI ('scale must be > 0', build 303).
            if let slika, slika.jeVarnaZaPrikaz {
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
    /// Pomanjsa ze zajet posnetek (npr. z merila 1.0 na 0.25) — risanje UIImage v manjsi renderer je
    /// poceni (GPU), za razliko od drugega klica drawHierarchy, ki znova prehodi vso hierarhijo.
    /// Zato ob preklopu zavihka zajamemo zaslon ENKRAT (ostro) in zamegljeno ozadje izpeljemo iz tega.
    /// Vrne nil pri prazni sliki ali merilu <= 0 (renderer z nicelno velikostjo/merilom ne sme nastati).
    /// Rezultat ima merilo `merilo` (npr. 0.25) — NI za neposreden prikaz, pred `Image(uiImage:)` gre skozi `zaPrikaz`.
    static func pomanjsaj(_ slika: UIImage, naMerilo merilo: CGFloat) -> UIImage? {
        let velikost = slika.size
        guard merilo > 0, slika.scale > 0, velikost.width > 0, velikost.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = merilo
        format.opaque = true
        return UIGraphicsImageRenderer(size: velikost, format: format).image { _ in
            slika.draw(in: CGRect(origin: .zero, size: velikost))
        }
    }

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

    /// Slika, ki jo `Image(uiImage:)` varno prikaze (zrusitev build 303, Home -> dogodek -> Search):
    /// posnetek za ozadje ima merilo 0.25 (cetrtina locljivosti). SwiftUI ob razresevanju slike za
    /// lastnosti zaslona poklice `-[UIImage imageAsset]`, ta sliko registrira v CoreUI, ki merilo hrani
    /// kot celo stevilo (1x/2x/3x): 0.25 -> 0 -> NSInternalInconsistencyException 'scale must be > 0'.
    /// Zato isti piksli dobijo merilo 1 (manjsa velikost v tockah); ozadje je `.resizable().scaledToFill()`,
    /// zato je videz enak. Nil, ce slika nima pikslov ali velikosti — takrat se posnetek ne prikaze.
    static func zaPrikaz(_ slika: UIImage) -> UIImage? {
        guard let cg = slika.cgImage, cg.width > 0, cg.height > 0, slika.scale > 0 else { return nil }
        if slika.scale >= 1 { return slika }
        return UIImage(cgImage: cg, scale: 1, orientation: slika.imageOrientation)
    }
}

extension UIImage {
    /// Sme v `Image(uiImage:)`: ima piksle, velikost > 0 in merilo >= 1 (glej OzadnjaZameglitev.zaPrikaz).
    var jeVarnaZaPrikaz: Bool {
        guard let cg = cgImage else { return false }
        return scale >= 1 && cg.width > 0 && cg.height > 0 && size.width > 0 && size.height > 0
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
    func surovPosnetek(merilo: CGFloat = UIApplication.meriloPosnetka) -> UIImage? {
        guard let okno = kljucnoOkno, merilo > 0,
              okno.bounds.width > 0, okno.bounds.height > 0 else { return nil }
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
        // Merilo 0.25 ne sme v Image(uiImage:) — zaPrikaz istim pikslom da merilo 1.
        return OzadnjaZameglitev.zaPrikaz(zamegljenPosnetek(iz: surov) ?? surov)
    }

    /// Koliko pikslov na tocko ima posnetek za ozadje zavihka. 0.25 = cetrtina locljivosti.
    fileprivate static let meriloPosnetka: CGFloat = 0.25
}
