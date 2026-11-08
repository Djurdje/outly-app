import SwiftUI
import UIKit

// Izrez bannerja dogodka pred nalaganjem (outly-backend#400, Luka 8. 11. 2026).
// Dva bannerja: velik 4:5 (glava dogodka, »Big events coming up«) in majhen 3:4 (kartice).
// Izrez je lokalen; izhod je tocno 4:5 oz. 3:4, najvec 1080 px v sirino, manjse slike se ne povecujejo.

/// Vrsta bannerja dogodka.
nonisolated enum VrstaBannerja {
    case velik    // 4:5, `poster_url`
    case majhen   // 3:4, `poster_card_url`

    /// Razmerje sirina : visina kot celi stevili, da je izhod natancen (4:5 -> 1080 x 1350, 3:4 -> 1080 x 1440).
    var sirinaDel: Int { self == .velik ? 4 : 3 }
    var visinaDel: Int { self == .velik ? 5 : 4 }
    var razmerje: CGFloat { CGFloat(sirinaDel) / CGFloat(visinaDel) }
}

/// Premik in povecava izreza. Odmik je v enotah SIRINE okvira (ne v tockah), zato isto stanje velja za
/// glavni okvir in za manjse predoglede. Slika je osnovno `scaledToFill` v okvirju (zoom 1), nato povecana
/// okoli sredine in premaknjena; `omejen` poskrbi, da slika vedno prekrije cel okvir.
nonisolated struct IzrezStanje: Equatable {
    static let najvecZoom: CGFloat = 4

    var zoom: CGFloat = 1
    var odmik: CGSize = .zero

    /// Zoom v [1, najvecZoom], odmik tako, da v okvirju ni praznega roba.
    func omejen(slika: CGSize, razmerje: CGFloat) -> IzrezStanje {
        guard slika.width > 0, slika.height > 0, razmerje > 0 else { return IzrezStanje() }
        var s = self
        s.zoom = min(max(zoom, 1), Self.najvecZoom)
        let fh = 1 / razmerje
        let s0 = max(1 / slika.width, fh / slika.height)
        let prikazanaSirina = slika.width * s0 * s.zoom
        let prikazanaVisina = slika.height * s0 * s.zoom
        let mx = max(0, (prikazanaSirina - 1) / 2)
        let my = max(0, (prikazanaVisina - fh) / 2)
        s.odmik = CGSize(width: min(max(odmik.width, -mx), mx),
                         height: min(max(odmik.height, -my), my))
        return s
    }

    /// Pravokotnik v PIKSLIH slike, ki je viden v okvirju.
    func izrez(slika: CGSize, razmerje: CGFloat) -> CGRect {
        guard slika.width > 0, slika.height > 0, razmerje > 0 else { return CGRect(origin: .zero, size: slika) }
        let s = omejen(slika: slika, razmerje: razmerje)
        let fh = 1 / razmerje
        let k = max(1 / slika.width, fh / slika.height) * s.zoom   // enot okvirja na piksel slike
        let w = min(1 / k, slika.width)
        let h = min(fh / k, slika.height)
        let cx = slika.width / 2 - s.odmik.width / k
        let cy = slika.height / 2 - s.odmik.height / k
        let x = min(max(cx - w / 2, 0), slika.width - w)
        let y = min(max(cy - h / 2, 0), slika.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Izrez in kodiranje bannerja.
nonisolated enum BannerIzrez {
    static let najvecSirina = 1080
    static let kakovostJPEG: CGFloat = 0.9

    /// Izhodna velikost: sirina najvec 1080 in nikoli vecja od izreza (brez povecevanja), razmerje natancno.
    static func izhodnaVelikost(izrezSirina: CGFloat, vrsta: VrstaBannerja) -> (sirina: Int, visina: Int) {
        let sirina = min(najvecSirina, max(1, Int(izrezSirina.rounded(.down))))
        let k = max(1, sirina / vrsta.sirinaDel)
        return (k * vrsta.sirinaDel, k * vrsta.visinaDel)
    }

    /// JPEG izreza (brez EXIF; `SlikaZaNalaganje` ga ob nalaganju vseeno ponovno kodira).
    /// `slika` mora biti ze pravilno obrnjena (`SlikovniPredpomnilnik.pomanjsaj` uposteva EXIF).
    static func izrezi(_ slika: UIImage, vrsta: VrstaBannerja, stanje: IzrezStanje) -> Data? {
        guard let cg = slika.cgImage else { return nil }
        let velikost = CGSize(width: cg.width, height: cg.height)
        let izrez = stanje.izrez(slika: velikost, razmerje: vrsta.razmerje)
        let meja = CGRect(origin: .zero, size: velikost)
        let celi = izrez.integral.intersection(meja)
        guard !celi.isNull, celi.width >= 1, celi.height >= 1, let izrezan = cg.cropping(to: celi) else { return nil }

        let izhod = izhodnaVelikost(izrezSirina: celi.width, vrsta: vrsta)
        guard let ctx = CGContext(data: nil, width: izhod.sirina, height: izhod.visina, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // Prosojni deli (PNG) postanejo crni, kot povsod v aplikaciji (temna tema).
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: izhod.sirina, height: izhod.visina))
        ctx.interpolationQuality = .high
        ctx.draw(izrezan, in: CGRect(x: 0, y: 0, width: izhod.sirina, height: izhod.visina))
        guard let rezultat = ctx.makeImage() else { return nil }
        return UIImage(cgImage: rezultat, scale: 1, orientation: .up).jpegData(compressionQuality: kakovostJPEG)
    }
}

/// Izbrana slika, ki caka na izrez (za `fullScreenCover(item:)`).
struct BannerIzrezNalog: Identifiable {
    let id = UUID()
    let slika: UIImage
    let vrsta: VrstaBannerja
}

/// Zaslon izreza: fiksen okvir pravega razmerja, premik in povecava s prsti, predogled v pravem okviru.
/// »Use« vrne izrezan JPEG, »Cancel« ne naredi nicesar (nalaganje se ne zacne).
struct BannerIzrezView: View {
    let slika: UIImage
    let vrsta: VrstaBannerja
    var onUse: (Data) -> Void
    var onCancel: () -> Void

    @State private var stanje = IzrezStanje()
    @State private var osnovaZoom: CGFloat = 1
    @State private var osnovaOdmik: CGSize = .zero
    @State private var napaka = false

    /// Velikost v pikslih (slika iz `SlikovniPredpomnilnik.pomanjsaj` ima scale 1, a ne zanasamo se na to).
    private var pikslov: CGSize {
        if let cg = slika.cgImage { return CGSize(width: cg.width, height: cg.height) }
        return slika.size
    }

    private var naslov: LocalizedStringKey {
        vrsta == .velik ? "Crop main banner" : "Crop card banner"
    }

    var body: some View {
        VStack(spacing: 0) {
            zgornjaVrstica

            GeometryReader { geo in
                let f = velikostOkvira(v: geo.size)
                okvirIzreza(f)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            predogled
                .padding(.top, 12)

            Text("Drag to move, pinch to zoom.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
                .padding(.vertical, 16)
        }
        .background(Color.outlyBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .alert(Text("Could not crop this image."), isPresented: $napaka) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Vrstica

    private var zgornjaVrstica: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundColor(.white)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            Spacer()
            Text(naslov)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button {
                uporabi()
            } label: {
                Text("Use")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.outlyBlue)
                    .clipShape(Capsule())
            }
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
    }

    private func uporabi() {
        if let data = BannerIzrez.izrezi(slika, vrsta: vrsta, stanje: stanje) {
            onUse(data)
        } else {
            napaka = true
        }
    }

    // MARK: - Okvir

    /// Najvecji okvir pravega razmerja, ki gre v ponujeno obmocje.
    private func velikostOkvira(v: CGSize) -> CGSize {
        let najvecSirina = max(1, v.width - 32)
        let najvecVisina = max(1, v.height - 8)
        let sirina = max(1, min(najvecSirina, najvecVisina * vrsta.razmerje))
        return CGSize(width: sirina, height: sirina / vrsta.razmerje)
    }

    private func okvirIzreza(_ f: CGSize) -> some View {
        Color.clear
            .frame(width: f.width, height: f.height)
            .overlay { slikaVOkvirju(stanje, sirina: f.width) }
            .clipped()
            .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(premik(f).simultaneously(with: povecava))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Crop area"))
            .accessibilityValue("\(Int((stanje.zoom * 100).rounded()))%")
            .accessibilityHint(Text("Swipe up or down to zoom."))
            .accessibilityAdjustableAction { smer in
                let korak: CGFloat = 0.25
                osnovaZoom = stanje.zoom + (smer == .increment ? korak : -korak)
                popravi(zoom: osnovaZoom)
                osnovaOdmik = stanje.odmik
            }
    }

    /// Ista slika, zoom in odmik v okvirju dane sirine (glavni okvir in predogledi).
    private func slikaVOkvirju(_ s: IzrezStanje, sirina: CGFloat) -> some View {
        Color.clear.overlay(
            Image(uiImage: slika)
                .resizable()
                .scaledToFill()
                .scaleEffect(s.zoom)
                .offset(x: s.odmik.width * sirina, y: s.odmik.height * sirina)
        ).clipped()
    }

    // MARK: - Kretnje

    private func premik(_ f: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                var s = stanje
                s.odmik = CGSize(width: osnovaOdmik.width + v.translation.width / f.width,
                                 height: osnovaOdmik.height + v.translation.height / f.width)
                stanje = s.omejen(slika: pikslov, razmerje: vrsta.razmerje)
            }
            .onEnded { _ in osnovaOdmik = stanje.odmik }
    }

    private var povecava: some Gesture {
        MagnifyGesture()
            .onChanged { v in popravi(zoom: osnovaZoom * v.magnification) }
            .onEnded { _ in
                osnovaZoom = stanje.zoom
                osnovaOdmik = stanje.odmik
            }
    }

    private func popravi(zoom: CGFloat) {
        var s = stanje
        s.zoom = zoom
        stanje = s.omejen(slika: pikslov, razmerje: vrsta.razmerje)
    }

    // MARK: - Predogled

    /// Izrez v pravem okviru: velik kot glava dogodka (preliv + vrstica z vstopnicami), majhen kot `EventPosterCard`
    /// (zaobljena kartica s spodnjim pasom). Samo okrasen; slika je ista kot v okvirju izreza.
    @ViewBuilder
    private var predogled: some View {
        VStack(spacing: 6) {
            switch vrsta {
            case .velik: velikPredogled
            case .majhen: majhenPredogled
            }
            Text(vrsta == .velik ? LocalizedStringKey("Event page") : LocalizedStringKey("Card"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .accessibilityHidden(true)
    }

    private var velikPredogled: some View {
        let sirina: CGFloat = 120
        return slikaVOkvirju(stanje, sirina: sirina)
            .frame(width: sirina, height: sirina * 5 / 4)
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0),
                                       .init(color: .clear, location: 0.20),
                                       .init(color: .clear, location: 0.62),
                                       .init(color: .black.opacity(0.75), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(height: 14)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .clipped()
    }

    private var majhenPredogled: some View {
        let sirina: CGFloat = 120
        let oblika = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return slikaVOkvirju(stanje, sirina: sirina)
            .frame(width: sirina, height: sirina * 4 / 3)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.45))
                    .frame(height: 40)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color.white.opacity(0.7)).frame(width: 56, height: 5)
                            Capsule().fill(Color.white.opacity(0.4)).frame(width: 38, height: 4)
                        }
                        .padding(.leading, 8)
                    }
            }
            .clipShape(oblika)
            .overlay(oblika.stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}
