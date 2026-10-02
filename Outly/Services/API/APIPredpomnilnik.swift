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
enum APIPredpomnilnik {
    /// 64 MB: URLCache ne hrani odgovorov, vecjih od ~5 % zmogljivosti (tu ~3,2 MB). Scan-list ima ~180 B na vstopnico, torej je do
    /// ~17000 vstopnic se predpomnjen; brez predpomnilnika ni 304 in bi vsak telefon vsake 2 min prenesel ves seznam.
    nonisolated static let predpomnilnik = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 0, diskPath: nil)

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

    /// Zastavica: stari API odgovori na disku `URLCache.shared` so ze pobrisani (enkrat na namestitev).
    nonisolated static let zastavicaPocisceno = "api.predpomnilnik.disk.pociscen.v1"

    /// Enkratno ob prvem zagonu te razlicice: starejse razlicice so odgovore API-ja (scan-list z imeni imetnikov, /me, vstopnice)
    /// pisale na disk `URLCache.shared`, kjer bi ostali do odjave. Pobrise ves `URLCache.shared` (tudi slike; enkrat je to sprejemljivo).
    /// Vrne true, ce je cez; naslednji klici ne storijo nic.
    @discardableResult
    nonisolated static func enkratnoPocistiStareOdgovore(privzetosti: UserDefaults = .standard, predpomnilnik: URLCache = URLCache.shared) -> Bool {
        guard !privzetosti.bool(forKey: zastavicaPocisceno) else { return false }
        predpomnilnik.removeAllCachedResponses()
        privzetosti.set(true, forKey: zastavicaPocisceno)
        return true
    }
}
