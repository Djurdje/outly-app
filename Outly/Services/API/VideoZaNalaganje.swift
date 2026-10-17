import Foundation
import AVFoundation

/// Priprava videa pred nalaganjem na Cloudinary (outly-app #106, 17. 10. 2026) — isti vzorec kot `SlikaZaNalaganje`.
/// MOV/MP4 iz galerije praviloma nosi lokacijo snemanja (`com.apple.quicktime.location.ISO6709`, `udta/©xyz`).
/// Izvirnik se zato NIKOLI ne nalozi: video se izvozi z `AVAssetExportSession` brez metapodatkov vsebnika
/// (`metadata = []`) in s filtrom `AVMetadataItemFilter.forSharing()` (odstrani lokacijo in podatke, ki identificirajo
/// uporabnika). Najprej passthrough (brez ponovnega kodiranja, hitro); izvozena datoteka se nato PREBERE in preveri,
/// da lokacije res ni vec. Ce passthrough ne uspe ali lokacija ostane, sledi ponovno kodiranje; ce tudi to ne uspe,
/// se vrze `VideoNapaka` in nalaganja ni (politika zasebnosti trdi, da lokacija ostane na napravi).
/// Zacasne datoteke se pobrisejo takoj po izvozu (tudi ob napaki). Vse tece izven glavne niti.
/// Klice ga `APIClient.uploadVideoToCloudinary`, zato velja za VSA mesta, ki nalagajo videe.
enum VideoZaNalaganje {
    /// Cloudinary (brezplacni paket) sprejme videe do 100 MB.
    nonisolated static let najvecBajtov = 100 * 1024 * 1024

    nonisolated struct Pripravljen: Sendable {
        let podatki: Data
        let contentType: String
        /// Koncnica brez pike ("mp4" ali "mov").
        let koncnica: String
    }

    /// Izvoz tece v ozadju (ne na glavni niti).
    static func pripravi(_ podatki: Data) async throws -> Pripravljen {
        try await Task.detached(priority: .userInitiated) { () async throws -> Pripravljen in
            try await VideoZaNalaganje.izvoziBrezMetapodatkov(podatki)
        }.value
    }

    nonisolated static func izvoziBrezMetapodatkov(_ podatki: Data) async throws -> Pripravljen {
        let fm = FileManager.default
        let mapa = fm.temporaryDirectory.appendingPathComponent("outly-video-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: mapa, withIntermediateDirectories: true)
        } catch {
            throw VideoNapaka.neBerljiv
        }
        // Mapa z vhodom in izhodi se pobrise v vsakem primeru (uspeh, napaka, preklic).
        defer { try? fm.removeItem(at: mapa) }

        let vhod = mapa.appendingPathComponent("vhod.\(vhodnaKoncnica(podatki))")
        do {
            try podatki.write(to: vhod)
        } catch {
            throw VideoNapaka.neBerljiv
        }
        // Casovne metapodatkovne/podatkovne sledi (GPMF `gpmd` GoPro/dron, `mebx`, sledi lokacije) lahko nosijo GPS
        // in jih passthrough prepise. Ce jih vir ima, izvazamo kompozicijo SAMO iz video in avdio sledi.
        let asset: AVAsset
        do {
            asset = try await samoVideoInZvok(AVURLAsset(url: vhod))
        } catch {
            throw VideoNapaka.lokacijeNiMogoceOdstraniti
        }

        let preseti = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        for (indeks, preset) in preseti.enumerated() {
            try Task.checkCancellation()
            guard let izvoz = try? await izvozi(asset, preset: preset, mapa: mapa, indeks: indeks) else { continue }
            // Preveri izvozeno datoteko: ce lokacije ni mogoce prebrati ali je se tam -> naslednji preset.
            guard await brezLokacije(izvoz.url) else { continue }
            // Velikost iz datoteke PRED branjem v pomnilnik.
            if let velikost = try? izvoz.url.resourceValues(forKeys: [.fileSizeKey]).fileSize, velikost > najvecBajtov {
                throw VideoNapaka.prevelik
            }
            let rezultat: Data
            do {
                rezultat = try Data(contentsOf: izvoz.url)
            } catch {
                continue
            }
            if rezultat.count > najvecBajtov { throw VideoNapaka.prevelik }
            return izvoz.tip == .mp4
                ? Pripravljen(podatki: rezultat, contentType: "video/mp4", koncnica: "mp4")
                : Pripravljen(podatki: rezultat, contentType: "video/quicktime", koncnica: "mov")
        }
        throw VideoNapaka.lokacijeNiMogoceOdstraniti
    }

    /// Vir brez sledi, ki niso video/avdio: ce ima vir samo video in avdio, ga vrne nespremenjenega, sicer
    /// `AVMutableComposition` iz video in avdio sledi (orientacija: `preferredTransform` video sledi se ohrani).
    nonisolated static func samoVideoInZvok(_ asset: AVURLAsset) async throws -> AVAsset {
        let sledi = try await asset.load(.tracks)
        guard sledi.contains(where: { !jeVideoAliZvok($0.mediaType) }) else { return asset }
        let sestava = AVMutableComposition()
        var steviloVideo = 0
        for sled in sledi where jeVideoAliZvok(sled.mediaType) {
            guard let nova = sestava.addMutableTrack(withMediaType: sled.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoNapaka.lokacijeNiMogoceOdstraniti
            }
            let obseg = try await sled.load(.timeRange)
            try nova.insertTimeRange(obseg, of: sled, at: obseg.start)
            if sled.mediaType == .video {
                nova.preferredTransform = try await sled.load(.preferredTransform)
                steviloVideo += 1
            }
        }
        guard steviloVideo > 0 else { throw VideoNapaka.neBerljiv }
        return sestava
    }

    nonisolated static func jeVideoAliZvok(_ tip: AVMediaType) -> Bool {
        tip == .video || tip == .audio
    }

    /// Izvoz v `mapa` z izbranim presetom; izhod brez metapodatkov vsebnika in s filtrom za deljenje.
    nonisolated private static func izvozi(
        _ asset: AVAsset,
        preset: String,
        mapa: URL,
        indeks: Int
    ) async throws -> (url: URL, tip: AVFileType) {
        guard let seja = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoNapaka.lokacijeNiMogoceOdstraniti
        }
        let tip: AVFileType = seja.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let izhod = mapa.appendingPathComponent("izhod\(indeks).\(tip == .mp4 ? "mp4" : "mov")")
        seja.metadata = []
        seja.metadataItemFilter = AVMetadataItemFilter.forSharing()
        seja.shouldOptimizeForNetworkUse = true
        if #available(iOS 18.0, *) {
            try await seja.export(to: izhod, as: tip)
        } else {
            seja.outputURL = izhod
            seja.outputFileType = tip
            await seja.export()
            guard seja.status == .completed else {
                throw seja.error ?? VideoNapaka.lokacijeNiMogoceOdstraniti
            }
        }
        return (izhod, tip)
    }

    /// true samo, ce se izvozena datoteka da prebrati, ima samo video/avdio sledi (nobene casovne metapodatkovne
    /// ali podatkovne sledi, npr. GPMF) IN nima nobenega metapodatka o lokaciji (ne vsebnik ne sledi).
    /// Ce branje ne uspe, velja kot "ima lokacijo".
    nonisolated static func brezLokacije(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            var vsi = try await asset.load(.metadata)
            for sled in try await asset.load(.tracks) {
                if !jeVideoAliZvok(sled.mediaType) { return false }
                vsi += try await sled.load(.metadata)
            }
            return !vsi.contains(where: { jeLokacija($0) })
        } catch {
            return false
        }
    }

    nonisolated static func jeLokacija(_ item: AVMetadataItem) -> Bool {
        if item.commonKey == .commonKeyLocation { return true }
        if let id = item.identifier {
            if id == .quickTimeMetadataLocationISO6709 || id == .quickTimeUserDataLocationISO6709
                || id == .commonIdentifierLocation {
                return true
            }
            if jeLokacijskiKljuc(id.rawValue) { return true }
        }
        if let kljuc = item.key as? String, jeLokacijskiKljuc(kljuc) { return true }
        return false
    }

    /// "mdta/com.apple.quicktime.location.ISO6709", "udta/©xyz" (QuickTime/3GPP lokacija) ipd.
    nonisolated static func jeLokacijskiKljuc(_ kljuc: String) -> Bool {
        let k = kljuc.lowercased()
        return k.contains("location") || k.contains("iso6709") || k.hasSuffix("xyz")
    }

    /// AVURLAsset prepozna vsebnik po koncnici: "qt  " v ftyp (ali brez ftyp) = QuickTime, sicer MP4.
    nonisolated static func vhodnaKoncnica(_ podatki: Data) -> String {
        guard podatki.count >= 12 else { return "mov" }
        let glava = [UInt8](podatki.prefix(12))
        let ftyp = String(bytes: glava[4..<8], encoding: .ascii)
        guard ftyp == "ftyp" else { return "mov" }
        let znamka = String(bytes: glava[8..<12], encoding: .ascii)
        return znamka == "qt  " ? "mov" : "mp4"
    }
}

/// Videa ni bilo mogoce pripraviti brez lokacije -> ne nalagamo nicesar (izvirnik bi lahko nosil GPS).
nonisolated enum VideoNapaka: Error {
    case neBerljiv
    case lokacijeNiMogoceOdstraniti
    case prevelik
}
