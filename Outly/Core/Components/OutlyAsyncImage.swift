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

    static func iz(_ url: URL) -> UIImage? {
        predpomnilnik.object(forKey: url as NSURL)
    }

    /// Prenos (skozi URLCache.shared, disk), pomanjsava in dekodiranje v ozadju, nato v pomnilnik.
    static func nalozi(_ url: URL) async throws -> UIImage {
        let (podatki, _) = try await URLSession.shared.data(from: url)
        let meja = najvecPikslov
        let slika = await Task.detached(priority: .userInitiated) {
            SlikovniPredpomnilnik.pomanjsaj(podatki, najvec: meja)
        }.value
        guard let slika else { throw URLError(.cannotDecodeContentData) }
        let cena = Int(slika.size.width * slika.scale * slika.size.height * slika.scale * 4)
        predpomnilnik.setObject(slika, forKey: url as NSURL, cost: cena)
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
