import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// M13: ob odjavi se shramba skenerja (seznami z imeni imetnikov, lokalni skeni, konflikti, kljuc) pobrise. Neposlani skeni ostanejo
// (vrsta je na disku po vnosih in jih sinhronizira samo uporabnik, ki jih je skeniral), zato jih PREJ poskusimo poslati s se
// veljavnim zetonom. Brez povezave ostanejo do naslednje prijave istega racuna.

@MainActor
enum SkenOdjava {
    /// Poskusi poslati neposlane skene TEGA uporabnika (zeton velja samo zanj; vnose drugih racunov pusti), vsakega kluba s svojo glavo.
    /// Ne vrze in ne caka dlje od `rok` na posamezen paket.
    static func poslji(token: String, uporabnikId: Int, api: SkenApi = SkenApiZivi(), disk: SkenDisk = SkenDisk(), rok: Double = 5,
                       deviceId: String = SkenNaprava.id()) async {
        guard !token.isEmpty else { return }
        let vrsta = SkenVrsta.deljena(disk)
        for klub in vrsta.neposlaniKlubi(uporabnik: uporabnikId) {
            var krogi = 0
            while krogi < 20 {   // najvec 20 paketov po 500
                krogi += 1
                let paket = vrsta.paket(klub: klub, uporabnik: uporabnikId)
                if paket.isEmpty { break }
                let klubZaApi: Int? = klub > 0 ? klub : nil
                let odgovor = await SkenRok.zRokom(rok) { try await api.paket(token: token, klubId: klubZaApi, vnosi: paket, deviceId: deviceId) }
                guard case .success(let rezultati)? = odgovor, vrsta.uporabi(rezultati, poslani: paket) > 0 else { break }
                // Delni paket (`error` = zasedena baza, outly-app#108): preostanka ne posiljamo takoj znova; ostane na disku do naslednje prijave.
                if SkenSeja.jeDelniPaket(rezultati, poslani: paket) { break }
            }
        }
    }

    /// Pobrise vse razen neposlanih vnosov (ti ostanejo brez imen imetnikov) in predpomnilnik odgovorov.
    /// Tudi shranjene vstopnice uporabnika (QR kode za vrata brez signala) - klice se ob odjavi, zavrnjeni seji in brisanju racuna.
    static func pocisti(disk: SkenDisk = SkenDisk(), predpomnilniki: [URLCache] = [APIPredpomnilnik.predpomnilnik, URLCache.shared],
                        vstopnice: VstopniceShramba = VstopniceShramba()) {
        SkenVrsta.deljena(disk).pocistiPoOdjavi()
        disk.pocistiVsePoOdjavi()
        pocistiPredpomnilnik(predpomnilniki)
        vstopnice.pobrisi()
    }

    /// Odgovori GET (tudi scan-list z imeni imetnikov) ne smejo ostati po odjavi. API ima lasten predpomnilnik samo v pomnilniku
    /// (APIPredpomnilnik); `URLCache.shared` pobrisemo se za odgovore, ki jih je starejsa razlicica zapisala na disk.
    /// `predpomnilniki` je parameter, da test dela z lastnim URLCache in ne z deljenim stanjem aplikacije.
    nonisolated static func pocistiPredpomnilnik(_ predpomnilniki: [URLCache] = [APIPredpomnilnik.predpomnilnik, URLCache.shared]) {
        APIPredpomnilnik.pocisti(predpomnilniki)
    }
}
