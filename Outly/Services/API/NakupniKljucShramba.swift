import Foundation

/// Shramba idempotentnih kljucev nakupa, SAMO v pomnilniku (ne UserDefaults/Keychain/disk).
///
/// Zakaj: kljuc v `@State` lista se izgubi, ko uporabnik list zapre. Scenarij: Pay -> timeout (narocilo je na strezniku
/// ze nastalo) -> zapre in znova odpre list -> nov kljuc -> DRUGO narocilo (pri VIP mizi »already booked« za lastno mizo).
/// Zato kljuc ostane tu: ponovno odprt list ISTE vsebine v `veljavnost` od zadnje uporabe dobi ISTI kljuc. List ob odprtju
/// prebere se `odprtaVsebina` (kolicina, miza, paket zadnjega nerazresenega poskusa) in z njo predizpolni izbiro, sicer bi
/// ponastavljena izbira (kolicina 1) dala drugo vsebino in s tem nov kljuc.
/// Backend kljuc hrani trajno, zato iztek ni potreben za pravilnost; 24 h je samo higiena pomnilnika (aplikacija dolgo zivi v ozadju).
///
/// Zapis je vezan na (uporabnik, dogodek, vrsta nakupa); znotraj zapisa velja pravilo `NakupniKljuc` (sprememba kolicine/mize/paketa
/// = nov kljuc). Vrsta (`VrstaNakupa`: vstopnice | VIP miza) je del poti, ker sta to dva loceni nakupa istega dogodka: brez nje je
/// Pay na listu vstopnic povozil nerazresen izid VIP mize (uspeh ga je celo zbrisal) in obratno (outly-backend #137).
/// Zapis se zavrze po uspehu, po 422/400 (`.kljucZavrzen`) in 409 `order_not_active` (`NakupniKljuc.poNapaki` ponastavi kljuc),
/// ob odjavi (`pocistiVse`, klice SessionStore) in po izteku (vsak zapis ima LASTEN rok). Ura je vstavljiva zaradi testov.
///
/// Pomnilnik procesa je edino mesto, zato zapisov iz stare oblike (en zapis na dogodek) ni kaj selititi: nova razlicica aplikacije
/// zacne s praznim zapisom. Kljuc ob ubitem procesu izgine (backend ga hrani, aplikacija ne) - znana, nespremenjena meja.
///
/// Uporabnik se ob Pay lahko se ni znan (`session.me == nil` takoj po hladnem zagonu): pogledi tedaj podajo `neznanUporabnik`.
/// Ko se `me` nalozi, `pripisiNeznanega` prenese te zapise na pravega uporabnika in si zapomni preslikavo, da klic, ki je
/// uporabnika prebral ze pred prihodom `me` (zahtevek v teku), pristane na istem zapisu, ne na osirotelem.
@MainActor
final class NakupniKljucShramba {

    /// Skupna shramba aplikacije.
    static let deljena = NakupniKljucShramba()

    /// Kako dolgo od zadnje uporabe je kljuc se veljaven (higiena pomnilnika, ne pravilnost: backend kljuc hrani trajno).
    nonisolated static let privzetaVeljavnost: TimeInterval = 24 * 60 * 60

    /// Uporabnik, dokler `session.me` ni nalozen (pogledi: `session.me?.id ?? NakupniKljucShramba.neznanUporabnik`).
    /// Prave id-je streznik dodeljuje od 1 naprej, zato trka ni.
    nonisolated static let neznanUporabnik = -1

    private struct Pot: Hashable {
        let uporabnik: Int
        let dogodekId: Int
        let vrsta: VrstaNakupa
    }

    private struct Zapis {
        var kljuc: NakupniKljuc
        var zadnjaUporaba: Date
        /// Izid zadnjega poskusa; nil = odgovor se ni prisel (zaNakup brez poNapaki/poUspehu), obravnavamo kot nejasen.
        var izid: NakupniIzid?
        /// Lepljiv »nejasen izid«: nastavi ga `.nejasen` / `.vObdelavi`, ohrani ga poznejsa `.navadna` (npr. 503 pri ponovitvi
        /// z ISTIM kljucem; prvo narocilo je lahko ze nastalo). Zbrise ga rotacija kljuca (`.kljucZavrzen`,
        /// `.narociloNeaktivno`, nov kljuc zaradi druge vsebine) ali uspeh (zapis stran).
        var nerazresen: Bool = false
    }

    private var zapisi: [Pot: Zapis] = [:]
    /// Pravi uporabnik, na katerega so bili pripisani zapisi `neznanUporabnik` (nil = se ni bilo pripisa). Zbrise ga `pocistiVse`.
    private var pripisaniUporabnik: Int?
    private let veljavnost: TimeInterval
    private let ura: () -> Date
    private let ustvari: () -> String

    /// `ura` in `ustvari` sta vstavljiva v testih (iztek brez cakanja, deterministicni kljuci).
    init(veljavnost: TimeInterval = NakupniKljucShramba.privzetaVeljavnost,
         ura: @escaping () -> Date = { Date() },
         ustvari: @escaping () -> String = { UUID().uuidString }) {
        self.veljavnost = veljavnost
        self.ura = ura
        self.ustvari = ustvari
    }

    /// Stevilo zivih zapisov (po izteku se ne steje); za teste.
    var steviloZapisov: Int {
        zavrziPotekle(ura())
        return zapisi.count
    }

    /// Klici tik pred posiljanjem. Isti kljuc kot pri prejsnjem poskusu iste vsebine istega uporabnika, ce ta ni potekel;
    /// sicer nov. Osvezi cas zadnje uporabe.
    func zaNakup(uporabnik: Int, vsebina: NakupniKljuc.Vsebina) -> String {
        let zdaj = ura()
        zavrziPotekle(zdaj)
        let pot = potZapisa(uporabnik: uporabnik, dogodekId: vsebina.dogodekId, vrsta: vsebina.vrsta)
        var zapis = zapisi[pot] ?? Zapis(kljuc: NakupniKljuc(ustvari: ustvari), zadnjaUporaba: zdaj, izid: nil)
        let prejsnjiKljuc = zapis.kljuc.vrednost
        let kljuc = zapis.kljuc.zaNakup(vsebina)
        if kljuc != prejsnjiKljuc { zapis.nerazresen = false }   // druga vsebina = nov kljuc = nov nakup
        zapis.zadnjaUporaba = zdaj
        zapis.izid = nil
        zapisi[pot] = zapis
        return kljuc
    }

    /// Vsebina zadnjega poskusa tega uporabnika, dogodka in VRSTE nakupa, SAMO ce je izid nejasen, tj. narocilo je morda nastalo:
    /// `.nejasen` (timeout, izgubljena povezava), `.vObdelavi` (409 request_in_progress) ali odgovor se ni prisel
    /// (zaNakup brez poNapaki/poUspehu; obravnavano kot nejasno). Po dokoncni napaki (`.navadna`: 403, razprodano, 503 ...)
    /// backend kljuca ne zapomni, zato predizpolnitev ni potrebna in bi samo presenetila; po uspehu, po rotaciji kljuca
    /// (`.kljucZavrzen`, `.narociloNeaktivno`), po izteku in po odjavi je nil. Nejasen izid je LEPLJIV: `.navadna` po njem
    /// (npr. 503 pri ponovitvi z istim kljucem) vsebine ne skrije, dokler je kljuc isti. Rok zadnje uporabe se ne osvezi.
    /// Kljuc sam se zaradi tega NE spremeni (pravila `NakupniKljuc` ostanejo).
    func odprtaVsebina(uporabnik: Int, dogodekId: Int, vrsta: VrstaNakupa) -> NakupniKljuc.Vsebina? {
        zavrziPotekle(ura())
        guard let zapis = zapisi[potZapisa(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta)] else { return nil }
        switch zapis.izid {
        case nil, .nejasen?, .vObdelavi?: return zapis.kljuc.vsebina
        case .navadna?: return zapis.nerazresen ? zapis.kljuc.vsebina : nil
        case .kljucZavrzen?, .narociloNeaktivno?: return nil
        }
    }

    /// Nakup je uspel: zapis TE vrste stran, naslednji nakup je nov nakup. Zapis druge vrste istega dogodka ostane
    /// (nerazresen VIP ne sme izginiti zaradi uspele vstopnice in obratno).
    func poUspehu(uporabnik: Int, dogodekId: Int, vrsta: VrstaNakupa) {
        zapisi[potZapisa(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta)] = nil
    }

    /// Nakup je padel: kljuc ostane (ponovni poskus je varen), razen ce ga je backend zavrnil ali je narocilo neaktivno
    /// (to dolocata `NakupniKljuc.poNapaki` in `NakupniIzid`). Zapisa ne ustvari; osvezi cas zadnje uporabe
    /// (nakup je lahko trajal do timeouta).
    func poNapaki(uporabnik: Int, dogodekId: Int, vrsta: VrstaNakupa, izid: NakupniIzid) {
        let pot = potZapisa(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta)
        let zdaj = ura()
        zavrziPotekle(zdaj)
        guard var zapis = zapisi[pot] else { return }
        zapis.kljuc.poNapaki(izid)
        switch izid {
        case .nejasen, .vObdelavi: zapis.nerazresen = true
        case .kljucZavrzen, .narociloNeaktivno: zapis.nerazresen = false
        case .navadna: break   // ohrani prejsnji nejasen izid (isti kljuc)
        }
        zapis.zadnjaUporaba = zdaj
        zapis.izid = izid
        zapisi[pot] = zapis
    }

    /// `session.me` se je prvic nalozil: zapisi, nastali, ko uporabnik se ni bil znan, postanejo zapisi pravega uporabnika
    /// (isti kljuc, isti izid, isti rok). Ce pot pri pravem uporabniku ze obstaja, obdrzi novejsi zapis. Klice SessionStore.
    /// Pozneje klici z `neznanUporabnik` (zahtevek, ki je uporabnika prebral pred prihodom `me`) pristanejo na pravem uporabniku.
    func pripisiNeznanega(uporabnik: Int) {
        guard uporabnik != NakupniKljucShramba.neznanUporabnik else { return }
        pripisaniUporabnik = uporabnik
        zavrziPotekle(ura())
        let neznani = zapisi.filter { $0.key.uporabnik == NakupniKljucShramba.neznanUporabnik }
        for (stara, zapis) in neznani {
            zapisi[stara] = nil
            let nova = Pot(uporabnik: uporabnik, dogodekId: stara.dogodekId, vrsta: stara.vrsta)
            if let obstojec = zapisi[nova], obstojec.zadnjaUporaba >= zapis.zadnjaUporaba { continue }
            zapisi[nova] = zapis
        }
    }

    /// Odjava / zavrnjena seja: vsi kljuci stran (tudi preslikava neznanega uporabnika).
    func pocistiVse() {
        zapisi.removeAll()
        pripisaniUporabnik = nil
    }

    /// Pot zapisa; `neznanUporabnik` po pripisu pomeni pravega uporabnika (glej `pripisiNeznanega`).
    private func potZapisa(uporabnik: Int, dogodekId: Int, vrsta: VrstaNakupa) -> Pot {
        let u = (uporabnik == NakupniKljucShramba.neznanUporabnik) ? (pripisaniUporabnik ?? uporabnik) : uporabnik
        return Pot(uporabnik: u, dogodekId: dogodekId, vrsta: vrsta)
    }

    private func zavrziPotekle(_ zdaj: Date) {
        zapisi = zapisi.filter { zdaj.timeIntervalSince($0.value.zadnjaUporaba) < veljavnost }
    }
}
