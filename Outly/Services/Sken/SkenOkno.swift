import Foundation

// Casovno okno skenerja (8. 10. 2026): vratar NE izbira dogodka. Aktiven je vsak objavljen dogodek kluba, katerega okno traja
// od 12 h pred zacetkom do 6 h po koncu. Konec je `endAt`, brez njega zacetek + 12 h. Koda QR nosi event_id, zato je dovolj,
// da telefon pozna mnozico aktivnih dogodkov; vse se racuna iz seznama dogodkov in ure telefona (deluje tudi brez povezave).
// Cista funkcija brez stanja: konstante so SAMO tu (splet ima isti dogovor v webapp/js).

enum SkenOkno {
    /// Skeniranje se odpre toliko pred zacetkom dogodka.
    static let predZacetkom: TimeInterval = 12 * 3600
    /// Skeniranje ostane odprto toliko po koncu dogodka.
    static let poKoncu: TimeInterval = 6 * 3600
    /// Dogodek brez `endAt` (ali z `endAt` pred zacetkom) traja toliko.
    static let privzetoTrajanje: TimeInterval = 12 * 3600

    static func zacetek(_ d: SkenDogodek) -> Date? { SkenCas.razcleni(d.startAt) }

    /// Konec dogodka; nil, ce zacetka ni mogoce prebrati. `endAt`, ki ni po zacetku, je napaka v podatkih -> privzeto trajanje.
    static func konec(_ d: SkenDogodek) -> Date? {
        guard let zacetek = zacetek(d) else { return nil }
        if let k = SkenCas.razcleni(d.endAt), k > zacetek { return k }
        return zacetek.addingTimeInterval(privzetoTrajanje)
    }

    /// Od kdaj je skeniranje dogodka odprto (zacetek - 12 h).
    static func odprtoOd(_ d: SkenDogodek) -> Date? { zacetek(d)?.addingTimeInterval(-predZacetkom) }

    /// Do kdaj je skeniranje dogodka odprto (konec + 6 h).
    static func odprtoDo(_ d: SkenDogodek) -> Date? { konec(d)?.addingTimeInterval(poKoncu) }

    /// Okno objavljenega dogodka z ze razclenjenimi urami (seja ga ima vnaprej, da tik vsako sekundo ne razclenjuje nizov).
    struct Okno: Equatable {
        let dogodek: SkenDogodek
        let zacetek: Date
        let odprtoOd: Date
        let odprtoDo: Date

        /// Aktiven = `zdaj` v zaprtem intervalu [zacetek - 12 h, konec + 6 h].
        func jeAktiven(zdaj: Date) -> Bool { zdaj >= odprtoOd && zdaj <= odprtoDo }
    }

    /// nil, ce dogodek ni objavljen ali mu zacetka ni mogoce prebrati (taksen dogodek ne more biti aktiven).
    static func okno(_ d: SkenDogodek) -> Okno? {
        guard d.status == "published", let zacetek = zacetek(d), let konec = konec(d) else { return nil }
        return Okno(dogodek: d, zacetek: zacetek, odprtoOd: zacetek.addingTimeInterval(-predZacetkom),
                    odprtoDo: konec.addingTimeInterval(poKoncu))
    }

    static func okna(_ dogodki: [SkenDogodek]) -> [Okno] { dogodki.compactMap { okno($0) } }

    /// Aktivni dogodki, po zacetku (pri enakem zacetku po id).
    static func aktivniIz(okna: [Okno], zdaj: Date) -> [SkenDogodek] {
        okna
            .filter { $0.jeAktiven(zdaj: zdaj) }
            .sorted { a, b in a.zacetek != b.zacetek ? a.zacetek < b.zacetek : a.dogodek.id < b.dogodek.id }
            .map { $0.dogodek }
    }

    /// Dogodek, katerega okno se se ni odprlo, ki se odpre najprej; nil, ce takega ni.
    static func naslednjiIz(okna: [Okno], zdaj: Date) -> SkenDogodek? {
        okna
            .filter { $0.odprtoOd > zdaj }
            .min { a, b in a.odprtoOd != b.odprtoOd ? a.odprtoOd < b.odprtoOd : a.dogodek.id < b.dogodek.id }?
            .dogodek
    }

    static func jeAktiven(_ d: SkenDogodek, zdaj: Date) -> Bool { okno(d)?.jeAktiven(zdaj: zdaj) ?? false }

    static func aktivni(_ dogodki: [SkenDogodek], zdaj: Date) -> [SkenDogodek] { aktivniIz(okna: okna(dogodki), zdaj: zdaj) }

    static func naslednji(_ dogodki: [SkenDogodek], zdaj: Date) -> SkenDogodek? { naslednjiIz(okna: okna(dogodki), zdaj: zdaj) }
}
