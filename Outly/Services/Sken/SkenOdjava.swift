import Foundation

// M13: ob odjavi se shramba skenerja (seznami z imeni imetnikov, lokalni skeni, konflikti, kljuc) pobrise. Neposlani skeni ostanejo
// (vrsta je na disku po vnosih in jih sinhronizira samo uporabnik, ki jih je skeniral), zato jih PREJ poskusimo poslati s se
// veljavnim zetonom. Brez povezave ostanejo do naslednje prijave istega racuna.

@MainActor
enum SkenOdjava {
    /// Poskusi poslati vse neposlane skene (kratek rok), vsakega kluba s svojo glavo. Ne vrze.
    static func poslji(token: String, api: SkenApi = SkenApiZivi(), disk: SkenDisk = SkenDisk(), rok: Double = 5,
                       deviceId: String = SkenNaprava.id()) async {
        guard !token.isEmpty else { return }
        let vrsta = SkenVrsta.deljena(disk)
        for (klub, uporabnik) in vrsta.neposlaniKlubi() {
            var krogi = 0
            while krogi < 20 {   // najvec 20 paketov po 500
                krogi += 1
                let paket = vrsta.paket(klub: klub, uporabnik: uporabnik)
                if paket.isEmpty { break }
                let klubZaApi: Int? = klub > 0 ? klub : nil
                let odgovor = await SkenRok.zRokom(rok) { try await api.paket(token: token, klubId: klubZaApi, vnosi: paket, deviceId: deviceId) }
                guard case .success(let rezultati)? = odgovor, vrsta.uporabi(rezultati, poslani: paket) > 0 else { break }
            }
        }
    }

    /// Pobrise vse razen neposlanih vnosov (ti ostanejo brez imen imetnikov).
    static func pocisti(disk: SkenDisk = SkenDisk()) {
        SkenVrsta.deljena(disk).pocistiPoOdjavi()
        disk.pocistiVsePoOdjavi()
    }
}
