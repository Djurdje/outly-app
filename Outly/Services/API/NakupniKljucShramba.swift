import Foundation

/// Shramba idempotentnih kljucev nakupa, SAMO v pomnilniku (ne UserDefaults/Keychain/disk).
///
/// Zakaj: kljuc v `@State` lista se izgubi, ko uporabnik list zapre. Scenarij: Pay -> timeout (narocilo je na strezniku
/// ze nastalo) -> zapre in znova odpre list -> nov kljuc -> DRUGO narocilo (pri VIP mizi »already booked« za lastno mizo).
/// Zato kljuc ostane tu: ponovno odprt list ISTE vsebine v `veljavnost` (10 min od zadnje uporabe) dobi ISTI kljuc.
///
/// Zapis je vezan na (uporabnik, dogodek); znotraj zapisa velja pravilo `NakupniKljuc` (sprememba kolicine/mize/paketa = nov kljuc).
/// Zapis se zavrze po uspehu, po 422/400 (`.kljucZavrzen`) in 409 `order_not_active` (`NakupniKljuc.poNapaki` ponastavi kljuc),
/// ob odjavi (`pocistiVse`, klice SessionStore) in po izteku. Ura je vstavljiva zaradi testov.
@MainActor
final class NakupniKljucShramba {

    /// Skupna shramba aplikacije.
    static let deljena = NakupniKljucShramba()

    /// Kako dolgo od zadnje uporabe je kljuc se veljaven.
    nonisolated static let privzetaVeljavnost: TimeInterval = 10 * 60

    private struct Pot: Hashable {
        let uporabnik: Int
        let dogodekId: Int
    }

    private struct Zapis {
        var kljuc: NakupniKljuc
        var zadnjaUporaba: Date
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
        var zapis = zapisi[pot] ?? Zapis(kljuc: NakupniKljuc(ustvari: ustvari), zadnjaUporaba: zdaj)
        let kljuc = zapis.kljuc.zaNakup(vsebina)
        zapis.zadnjaUporaba = zdaj
        zapisi[pot] = zapis
        return kljuc
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
