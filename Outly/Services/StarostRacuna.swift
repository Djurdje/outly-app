import Foundation

/// Najnizja starost za uporabniski racun (Martin, 19. 10. 2026: racun od 18 let, prej 15; backend #301, `starost_racuna.js`).
/// Steje se kot na strezniku: po LJUBLJANSKEM koledarju (Europe/Ljubljana) in po polnih letih kot SQL AGE
/// (rojen 29. 2. dopolni leto v neprestopnem letu sele 1. 3.).
///
/// Meja velja samo ob NASTAVITVI ali SPREMEMBI datuma rojstva: obstojec racun 15-17 let z ze vpisanim datumom ostane
/// (backend isti datum sprejme, ker ni sprememba). Zato zasloni preverijo mejo samo, ce se datum razlikuje od shranjenega.
/// Cista logika brez stanja (testi: StarostRacunaTests; zaslon da `zdaj`, testi fiksen datum).
enum StarostRacuna {
    /// Mora ostati enako kot `NAJMANJ_LET_RACUN` v outly-backend `starost_racuna.js`.
    nonisolated static let najmanjLet = 18

    /// Koledar, po katerem steje streznik.
    static var ljubljanskiKoledar: Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Ljubljana") ?? .current
        return k
    }

    /// Datum brez ure (leto, mesec, dan).
    struct Dan: Equatable {
        let leto: Int
        let mesec: Int
        let dan: Int
    }

    /// Dan trenutka `datum` v koledarju `koledar` (privzeto ljubljanski).
    static func dan(_ datum: Date, koledar: Calendar = ljubljanskiKoledar) -> Dan {
        let c = koledar.dateComponents([.year, .month, .day], from: datum)
        return Dan(leto: c.year ?? 0, mesec: c.month ?? 1, dan: c.day ?? 1)
    }

    /// "YYYY-MM-DD" -> Dan (nil, ce oblika ni prava).
    static func dan(iz niz: String) -> Dan? {
        let deli = niz.split(separator: "-")
        guard deli.count == 3, let l = Int(deli[0]), let m = Int(deli[1]), let d = Int(deli[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return Dan(leto: l, mesec: m, dan: d)
    }

    /// Polna leta od rojstva do `danes` (kot `polnaLeta` na strezniku).
    static func polnaLeta(rojstvo: Dan, danes: Dan) -> Int {
        var leta = danes.leto - rojstvo.leto
        if danes.mesec < rojstvo.mesec || (danes.mesec == rojstvo.mesec && danes.dan < rojstvo.dan) { leta -= 1 }
        return leta
    }

    /// Ali ima oseba z rojstnim dnem `rojstvo` na dan `danes` vsaj `najmanjLet` let.
    static func jeDovoljStar(rojstvo: Dan, danes: Dan, najmanj: Int = najmanjLet) -> Bool {
        polnaLeta(rojstvo: rojstvo, danes: danes) >= najmanj
    }

    /// Najkasnejsi dovoljen rojstni dan na dan `danes`: danes - `najmanj` let po koledarju. 29. 2. v neprestopnem
    /// ciljnem letu postane 28. 2. (rojen 29. 2. je na 28. 2. se mlajsi, glej `polnaLeta`).
    static func najkasnejsiRojstniDan(danes: Dan, najmanj: Int = najmanjLet) -> Dan {
        let leto = danes.leto - najmanj
        if danes.mesec == 2 && danes.dan == 29 && !jePrestopno(leto) {
            return Dan(leto: leto, mesec: 2, dan: 28)
        }
        return Dan(leto: leto, mesec: danes.mesec, dan: danes.dan)
    }

    static func jePrestopno(_ leto: Int) -> Bool {
        (leto % 4 == 0 && leto % 100 != 0) || leto % 400 == 0
    }

    /// Zgornja meja izbirnika datuma rojstva (DatePicker v koledarju naprave): konec najkasnejsega dovoljenega dne.
    /// `obstojec`: ze shranjen datum rojstva (racun 15-17 let pred 19. 10. 2026) - meja ga mora vkljuciti, sicer bi ga
    /// izbirnik ob odprtju premaknil na drug dan.
    static func zgornjaMejaIzbirnika(zdaj: Date = Date(), obstojec: Date? = nil,
                                                 koledarNaprave: Calendar = .current) -> Date {
        let d = najkasnejsiRojstniDan(danes: dan(zdaj))
        let zacetek = koledarNaprave.date(from: DateComponents(year: d.leto, month: d.mesec, day: d.dan)) ?? zdaj
        let konec = koledarNaprave.date(byAdding: DateComponents(day: 1, second: -1), to: zacetek) ?? zacetek
        if let obstojec, obstojec > konec { return obstojec }
        return konec
    }

    /// Preverba ob shranjevanju: `izbran` je "YYYY-MM-DD" iz izbirnika, `shranjen` datum, ki je ze v racunu (ali nil).
    /// Isti datum kot shranjen je vedno v redu (ni sprememba, backend ga sprejme). Sicer vsaj `najmanjLet` let.
    static func smeShraniti(izbran: String, shranjen: String?, danes: Dan) -> Bool {
        if let shranjen, shranjen == izbran { return true }
        guard let r = dan(iz: izbran) else { return false }
        return jeDovoljStar(rojstvo: r, danes: danes)
    }
}
