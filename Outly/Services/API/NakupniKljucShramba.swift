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
/// Zapis je vezan na (uporabnik, dogodek); znotraj zapisa velja pravilo `NakupniKljuc` (sprememba kolicine/mize/paketa = nov kljuc).
/// Zapis se zavrze po uspehu, po 422/400 (`.kljucZavrzen`) in 409 `order_not_active` (`NakupniKljuc.poNapaki` ponastavi kljuc),
/// ob odjavi (`pocistiVse`, klice SessionStore) in po izteku. Ura je vstavljiva zaradi testov.
@MainActor
final class NakupniKljucShramba {

    /// Skupna shramba aplikacije.
    static let deljena = NakupniKljucShramba()

    /// Kako dolgo od zadnje uporabe je kljuc se veljaven (higiena pomnilnika, ne pravilnost: backend kljuc hrani trajno).
    nonisolated static let privzetaVeljavnost: TimeInterval = 24 * 60 * 60

    private struct Pot: Hashable {
        let uporabnik: Int
        let dogodekId: Int
    }

    private struct Zapis {
        var kljuc: NakupniKljuc
        var zadnjaUporaba: Date
        /// Izid zadnjega poskusa; nil = odgovor se ni prisel (zaNakup brez poNapaki/poUspehu), obravnavamo kot nejasen.
        var izid: NakupniIzid?
    }

    private var zapisi: [Pot: Zapis] = [:]
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
        let pot = Pot(uporabnik: uporabnik, dogodekId: vsebina.dogodekId)
        var zapis = zapisi[pot] ?? Zapis(kljuc: NakupniKljuc(ustvari: ustvari), zadnjaUporaba: zdaj, izid: nil)
        let kljuc = zapis.kljuc.zaNakup(vsebina)
        zapis.zadnjaUporaba = zdaj
        zapis.izid = nil
        zapisi[pot] = zapis
        return kljuc
    }

    /// Vsebina zadnjega poskusa tega uporabnika in dogodka, SAMO ce je izid nejasen, tj. narocilo je morda nastalo:
    /// `.nejasen` (timeout, izgubljena povezava), `.vObdelavi` (409 request_in_progress) ali odgovor se ni prisel
    /// (zaNakup brez poNapaki/poUspehu; obravnavano kot nejasno). Po dokoncni napaki (`.navadna`: 403, razprodano, 503 ...)
    /// backend kljuca ne zapomni, zato predizpolnitev ni potrebna in bi samo presenetila; po uspehu, po rotaciji kljuca
    /// (`.kljucZavrzen`, `.narociloNeaktivno`), po izteku in po odjavi je nil. Rok zadnje uporabe se ne osvezi.
    /// Kljuc sam se zaradi tega NE spremeni (pravila `NakupniKljuc` ostanejo).
    func odprtaVsebina(uporabnik: Int, dogodekId: Int) -> NakupniKljuc.Vsebina? {
        zavrziPotekle(ura())
        guard let zapis = zapisi[Pot(uporabnik: uporabnik, dogodekId: dogodekId)] else { return nil }
        switch zapis.izid {
        case nil, .nejasen?, .vObdelavi?: return zapis.kljuc.vsebina
        case .navadna?, .kljucZavrzen?, .narociloNeaktivno?: return nil
        }
    }

    /// Nakup je uspel: zapis stran, naslednji nakup je nov nakup.
    func poUspehu(uporabnik: Int, dogodekId: Int) {
        zapisi[Pot(uporabnik: uporabnik, dogodekId: dogodekId)] = nil
    }

    /// Nakup je padel: kljuc ostane (ponovni poskus je varen), razen ce ga je backend zavrnil ali je narocilo neaktivno
    /// (to dolocata `NakupniKljuc.poNapaki` in `NakupniIzid`). Zapisa ne ustvari; osvezi cas zadnje uporabe
    /// (nakup je lahko trajal do timeouta).
    func poNapaki(uporabnik: Int, dogodekId: Int, izid: NakupniIzid) {
        let pot = Pot(uporabnik: uporabnik, dogodekId: dogodekId)
        let zdaj = ura()
        zavrziPotekle(zdaj)
        guard var zapis = zapisi[pot] else { return }
        zapis.kljuc.poNapaki(izid)
        zapis.zadnjaUporaba = zdaj
        zapis.izid = izid
        zapisi[pot] = zapis
    }

    /// Odjava / zavrnjena seja: vsi kljuci stran.
    func pocistiVse() {
        zapisi.removeAll()
    }

    private func zavrziPotekle(_ zdaj: Date) {
        zapisi = zapisi.filter { zdaj.timeIntervalSince($0.value.zadnjaUporaba) < veljavnost }
    }
}
