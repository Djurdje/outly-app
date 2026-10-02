import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Predpomnilnik in seja za klice backenda prek `APIClient.send()`.
///
/// Zakaj ne `URLSession.shared`: ta pise odgovore GET (scan-list z uporabniskimi imeni imetnikov, /me, vstopnice) v `URLCache.shared`
/// na DISK, kjer ostanejo po odjavi. Brisanje diskovnega dela URLCache je na Applovih platformah asinhrono (shranjevanje in brisanje
/// tecesta v ozadju), zato `removeAllCachedResponses()` ob odjavi ne jamci, da je odgovor res izginil, in pozni zapis zakasnelega
/// klica ga lahko vrne. Tu je predpomnilnik SAMO v pomnilniku (`diskCapacity: 0`): na disk ne pride nic, ob koncu procesa izgine,
/// brisanje je sinhrono. ETag/304 znotraj seje se deluje (SkenSeja ne prenasa celega seznama znova, ce se ni spremenil).
/// Slike (OutlyAsyncImage) ostanejo na `URLCache.shared`.
nonisolated enum APIPredpomnilnik {
    /// 32 MB: URLCache ne hrani odgovorov, vecjih od 5 % zmogljivosti; seznam vstopnic velikega dogodka je lahko ~1 MB.
    nonisolated static let predpomnilnik = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 0, diskPath: nil)

    nonisolated static let seja: URLSession = {
        let konfiguracija = URLSessionConfiguration.default
        konfiguracija.urlCache = predpomnilnik
        konfiguracija.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: konfiguracija)
    }()

    /// Ob odjavi: pobrise predpomnilnik API-ja in `URLCache.shared`. Slednji je potreben samo za odgovore, ki jih je starejsa razlicica
    /// aplikacije (ko je API se sel prek URLSession.shared) ze zapisala na disk; novi odgovori tja ne pridejo vec.
    nonisolated static func pocisti(_ predpomnilniki: [URLCache] = [APIPredpomnilnik.predpomnilnik, URLCache.shared]) {
        for p in predpomnilniki { p.removeAllCachedResponses() }
    }
}
