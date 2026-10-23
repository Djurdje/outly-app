import SwiftUI
import ImageIO
import UIKit

/// Nadomestek za `AsyncImage` (29. 9. 2026, "aplikacija steka"). Isti klici kot AsyncImage
/// (`{ phase in ... }` ali `{ img in ... } placeholder: { ... }`), a:
/// - dekodirane slike hrani v pomnilniku (NSCache) — AsyncImage tega nima, zato je vsako kartico
///   ob vsakem pojavu (drsenje, vrnitev na zavihek) znova prebral in dekodiral;
/// - sliko pomanjsa na najvec `SlikovniPredpomnilnik.najvecPikslov` in jo dekodira v OZADJU —
///   AsyncImage je plakat v polni locljivosti (npr. 2000 x 3000 = 24 MB) dekodiral sele ob
///   prvem izrisu, na glavni niti, kar je zatikalo drsenje;
/// - slika iz predpomnilnika je vidna ze v prvem framu (brez utripa skeletona).
struct OutlyAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content
    @State private var faza: AsyncImagePhase

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        if let url, let slika = SlikovniPredpomnilnik.iz(url) {
            _faza = State(initialValue: .success(Image(uiImage: slika)))
        } else {
            _faza = State(initialValue: .empty)
        }
    }

    init<I: View, P: View>(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url) { faza in
            if case .success(let slika) = faza {
                content(slika)
            } else {
                placeholder()
            }
        }
    }

    var body: some View {
        content(faza)
            .task(id: url) { await nalozi() }
    }

    private func nalozi() async {
        guard let url else { faza = .empty; return }
        if let slika = SlikovniPredpomnilnik.iz(url) {
            faza = .success(Image(uiImage: slika))
            return
        }
        do {
            let slika = try await SlikovniPredpomnilnik.nalozi(url)
            guard !Task.isCancelled else { return }
            faza = .success(Image(uiImage: slika))
        } catch {
            guard !Task.isCancelled else { return }
            faza = .failure(error)
        }
    }
}

/// Pomnilnik dekodiranih (ze pomanjsanih) slik, skupen vsem OutlyAsyncImage.
enum SlikovniPredpomnilnik {
    /// Najdaljsa stranica v pikslih. Plakat cez celo sirino zaslona (393 pt x 3) je ~1180 px.
    nonisolated static let najvecPikslov: CGFloat = 1200

    private static let predpomnilnik: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 120 * 1024 * 1024  // bajti dekodiranih slik
        return c
    }()

    /// Drobne sliccice (najvec ~48 px) za zamegljeno ozadje plakata (PlakatDogodka). Nastanejo ob prenosu,
    /// skupaj s polno sliko, zato ne zahtevajo dodatnega klica na omrezje (in ne Cloudinary transformacije).
    private static let drobne: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 400
        return c
    }()

    /// Najdaljsa stranica zamegljenega ozadja v pikslih. Razteg ~10x z mehkim vzorcenjem da gladko zameglitev.
    nonisolated static let najvecPikslovOzadja: CGFloat = 48

    static func iz(_ url: URL) -> UIImage? {
        predpomnilnik.object(forKey: url as NSURL)
    }

    /// Drobna razlicica za zamegljeno ozadje. Ce je (zaradi izpisa iz pomnilnika) ni, jo naredi iz
    /// ze dekodirane slike; nil samo, ce slika se ni nalozena.
    static func ozadje(_ url: URL) -> UIImage? {
        if let m = drobne.object(forKey: url as NSURL) { return m }
        guard let polna = predpomnilnik.object(forKey: url as NSURL) else { return nil }
        let m = zmanjsaj(polna, najvec: najvecPikslovOzadja)
        drobne.setObject(m, forKey: url as NSURL)
        return m
    }

    /// Pomanjsa ze dekodirano sliko (UIGraphicsImageRenderer); za drobne razlicice je to nekaj mikrosekund.
    nonisolated static func zmanjsaj(_ slika: UIImage, najvec: CGFloat) -> UIImage {
        let velikost = slika.size
        let daljsa = max(velikost.width, velikost.height)
        guard daljsa > najvec, daljsa > 0 else { return slika }
        let faktor = najvec / daljsa
        let nova = CGSize(width: max(1, (velikost.width * faktor).rounded()),
                          height: max(1, (velikost.height * faktor).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: nova, format: format).image { _ in
            slika.draw(in: CGRect(origin: .zero, size: nova))
        }
    }

    /// Prenos (skozi URLCache.shared, disk), pomanjsava in dekodiranje v ozadju, nato v pomnilnik.
    static func nalozi(_ url: URL) async throws -> UIImage {
        let (podatki, _) = try await URLSession.shared.data(from: url)
        let meja = najvecPikslov
        let ozadjeMeja = najvecPikslovOzadja
        let (slika, drobna) = await Task.detached(priority: .userInitiated) {
            (SlikovniPredpomnilnik.pomanjsaj(podatki, najvec: meja),
             SlikovniPredpomnilnik.pomanjsaj(podatki, najvec: ozadjeMeja))
        }.value
        guard let slika else { throw URLError(.cannotDecodeContentData) }
        let cena = Int(slika.size.width * slika.scale * slika.size.height * slika.scale * 4)
        predpomnilnik.setObject(slika, forKey: url as NSURL, cost: cena)
        if let drobna { drobne.setObject(drobna, forKey: url as NSURL) }
        return slika
    }

    /// ImageIO: pomanjsa in takoj dekodira (kCGImageSourceShouldCacheImmediately), brez
    /// polne locljivosti v pomnilniku. Uposteva EXIF orientacijo.
    nonisolated static func pomanjsaj(_ podatki: Data, najvec: CGFloat) -> UIImage? {
        let moznostiVira = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let vir = CGImageSourceCreateWithData(podatki as CFData, moznostiVira) else { return nil }
        let moznosti = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: najvec
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(vir, 0, moznosti) else { return nil }
        return UIImage(cgImage: cg)
    }
}
