import Foundation
import UIKit

/// Priprava fotografije pred nalaganjem na Cloudinary (pregled 17. 10. 2026).
/// Fotografije iz galerije nosijo EXIF, pogosto tudi GPS (kje je bila slika posneta). Izvirnik
/// se zato NIKOLI ne nalozi: slika se dekodira, pomanjsa na najvec `najvecPikslov` in ponovno
/// kodira. Novo kodirana slika nima EXIF/GPS (CGImage metapodatkov ne nosi). Ce dekodiranje
/// ne uspe, se vrze `SlikaNapaka.neBerljiva` in nalaganja ni.
/// Klice jo `APIClient.uploadImageToCloudinary`, zato velja za VSA mesta, ki nalagajo slike.
enum SlikaZaNalaganje {
    /// Najdaljsa stranica v pikslih (vec kot dovolj za plakat; prikaz je do 1200 px).
    nonisolated static let najvecPikslov: CGFloat = 2048
    nonisolated static let kakovostJPEG: CGFloat = 0.85

    nonisolated struct Pripravljena: Sendable {
        let podatki: Data
        let contentType: String
        /// Koncnica brez pike ("jpg" ali "png").
        let koncnica: String
    }

    /// Dekodiranje in kodiranje tece v ozadju (ne na glavni niti).
    static func pripravi(_ podatki: Data) async throws -> Pripravljena {
        let meja = najvecPikslov
        let kakovost = kakovostJPEG
        let rezultat = await Task.detached(priority: .userInitiated) { () -> Pripravljena? in
            SlikaZaNalaganje.ponovnoKodiraj(podatki, najvec: meja, kakovost: kakovost)
        }.value
        guard let rezultat else { throw SlikaNapaka.neBerljiva }
        return rezultat
    }

    /// Slike s prosojnostjo (npr. PNG logotip) ostanejo PNG, da ozadje ne postane crno;
    /// vse ostalo JPEG. Oboje iz CGImage, torej brez EXIF/GPS.
    nonisolated static func ponovnoKodiraj(_ podatki: Data, najvec: CGFloat, kakovost: CGFloat) -> Pripravljena? {
        guard let slika = SlikovniPredpomnilnik.pomanjsaj(podatki, najvec: najvec),
              let cg = slika.cgImage else { return nil }
        if imaProsojnost(cg.alphaInfo) {
            guard let png = slika.pngData() else { return nil }
            return Pripravljena(podatki: png, contentType: "image/png", koncnica: "png")
        }
        guard let jpeg = slika.jpegData(compressionQuality: kakovost) else { return nil }
        return Pripravljena(podatki: jpeg, contentType: "image/jpeg", koncnica: "jpg")
    }

    nonisolated static func imaProsojnost(_ info: CGImageAlphaInfo) -> Bool {
        switch info {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    /// "logo.jpg" + "png" -> "logo.png". Cloudinary ime shrani pod public_id, koncnica je informativna.
    nonisolated static func imeDatoteke(_ ime: String, koncnica: String) -> String {
        let osnova = (ime as NSString).deletingPathExtension
        return (osnova.isEmpty ? "slika" : osnova) + "." + koncnica
    }
}

/// Izbrane slike ni bilo mogoce dekodirati -> ne nalagamo nicesar (izvirnik bi lahko nosil GPS).
enum SlikaNapaka: Error {
    case neBerljiva
}
