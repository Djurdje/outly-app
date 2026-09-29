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
    /// Pomanjsa ze zajet posnetek (npr. z merila 1.0 na 0.25) — risanje UIImage v manjsi renderer je
    /// poceni (GPU), za razliko od drugega klica drawHierarchy, ki znova prehodi vso hierarhijo.
    /// Zato ob preklopu zavihka zajamemo zaslon ENKRAT (ostro) in zamegljeno ozadje izpeljemo iz tega.
    static func pomanjsaj(_ slika: UIImage, naMerilo merilo: CGFloat) -> UIImage {
        let velikost = slika.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = merilo
        format.opaque = true
        return UIGraphicsImageRenderer(size: velikost, format: format).image { _ in
            slika.draw(in: CGRect(origin: .zero, size: velikost))
        }
    }

    /// Lasten CIContext za izlocanje vsebine (klice se tudi z ozadne niti).
    nonisolated(unsafe) private static let ciKontekstVsebine = CIContext(options: [.useSoftwareRenderer: false])

    /// Iz posnetka zavihka (vsebina + zamegljen Home kot ozadje) naredi sliko SAMO vsebine s prosojnim
    /// ozadjem (29. 9. 2026, Martin: "ni vec una animacija k je bla prej"). Prvotni prehod je povecal
    /// samo vsebino, ozadje je stalo; posnetek z ozadjem je rasel kot kartica. Ozadje poznamo tocno
    /// (isto kot HomeSnapshotBackground: crno + slika scaledToFill cez celo okno + 60 % crne), zato ga
    /// narisemo, odstejemo od posnetka in obdrzimo le piksle, ki se opazno razlikujejo (+ 2 pt roba).
    /// Temni deli vsebine, enaki ozadju, postanejo prosojni — za 0,3 s animacije to ni vidno.
    nonisolated static func izlociVsebino(_ posnetek: UIImage, ozadje: UIImage, visinaOkna: CGFloat) -> UIImage? {
        guard let cgS = posnetek.cgImage else { return nil }
        let velikost = posnetek.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = posnetek.scale
        format.opaque = true
        let pricakovano = UIGraphicsImageRenderer(size: velikost, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: velikost))
            let bw = ozadje.size.width, bh = ozadje.size.height
            if bw > 0, bh > 0 {
                let m = max(velikost.width / bw, visinaOkna / bh)
                let w = bw * m, h = bh * m
                ozadje.draw(in: CGRect(x: (velikost.width - w) / 2, y: (visinaOkna - h) / 2, width: w, height: h))
            }
            UIColor.black.withAlphaComponent(0.6).setFill()
            ctx.fill(CGRect(origin: .zero, size: velikost), blendMode: .normal)
        }
        guard let cgB = pricakovano.cgImage else { return nil }
        let vir = CIImage(cgImage: cgS)
        let razlika = CIFilter.differenceBlendMode()
        razlika.inputImage = vir
        razlika.backgroundImage = CIImage(cgImage: cgB)
        // Vsota razlik treh kanalov v vse tri -> sivina; nad pragom = vsebina.
        let sivo = CIFilter.colorMatrix()
        sivo.inputImage = razlika.outputImage
        let vsota = CIVector(x: 1, y: 1, z: 1, w: 0)
        sivo.rVector = vsota
        sivo.gVector = vsota
        sivo.bVector = vsota
        sivo.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let prag = CIFilter.colorThreshold()
        prag.inputImage = sivo.outputImage
        prag.threshold = 0.12
        let razsiri = CIFilter.morphologyMaximum()
        razsiri.inputImage = prag.outputImage
        razsiri.radius = Float(2 * posnetek.scale)
        let omehcaj = CIFilter.gaussianBlur()
        omehcaj.inputImage = razsiri.outputImage?.clampedToExtent()
        omehcaj.radius = Float(1.5 * posnetek.scale)
        guard let maska = omehcaj.outputImage?.cropped(to: vir.extent) else { return nil }
        let zdruzi = CIFilter.blendWithMask()
        zdruzi.inputImage = vir
        zdruzi.backgroundImage = CIImage.clear.cropped(to: vir.extent)
        zdruzi.maskImage = maska
        guard let izhod = zdruzi.outputImage,
              let cg = ciKontekstVsebine.createCGImage(izhod, from: vir.extent) else { return nil }
        return UIImage(cgImage: cg, scale: posnetek.scale, orientation: .up)
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
