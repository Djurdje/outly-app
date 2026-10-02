import XCTest
import Foundation
@testable import Outly

/// Napotek ob ponovnem odprtju nakupnega lista po nejasnem izidu (outly-backend #130). Shramba je lasten primerek z
/// vstavljeno uro (brez `deljena`, brez cakanja); napotek samo bere `odprtaVsebina`, pravil kljuca ne spreminja.
@MainActor
final class NakupniNapotekTests: XCTestCase {

    private func vstopnice(_ kolicina: Int) -> NakupniKljuc.Vsebina {
        NakupniKljuc.Vsebina(dogodekId: 7, kolicina: kolicina)
    }

    private func miza(_ id: Int, paket: Int? = nil) -> NakupniKljuc.Vsebina {
        NakupniKljuc.Vsebina(dogodekId: 7, mizaId: id, paketId: paket)
    }

    private func novaShramba() -> NakupniKljucShramba {
        var n = 0
        return NakupniKljucShramba(veljavnost: 600, ura: { Date(timeIntervalSince1970: 1_000_000) },
                                   ustvari: { n += 1; return "k\(n)" })
    }

    // MARK: - Vstopnice (napotek izpeljan iz trenutne izbire)

    func testVstopniceBrezNerazresenegaPoskusaNimajoNapotka() {
        XCTAssertNil(NakupniNapotek.zaVstopnice(odprta: nil, trenutna: vstopnice(2), gumbNaVoljo: true))
    }

    func testVstopniceIstaKolicinaInGumbNaVoljoDaMordaUspelo() {
        XCTAssertEqual(NakupniNapotek.zaVstopnice(odprta: vstopnice(3), trenutna: vstopnice(3), gumbNaVoljo: true),
                       .moznoUspel)
    }

    func testVstopniceSpremembaKolicineDaPreveriProfil() {
        // Druga kolicina = nov kljuc: »tap again, won't be charged twice« bi lagalo.
        XCTAssertEqual(NakupniNapotek.zaVstopnice(odprta: vstopnice(3), trenutna: vstopnice(4), gumbNaVoljo: true),
                       .preveriProfil)
    }

    func testVstopniceSamodejnoZmanjsanjeKolicineDaPreveriProfil() {
        // Zaloga je padla: predizpolnitev je kolicino 5 stisnila na 3 (maxQuantity), kljuc je zato nov.
        XCTAssertEqual(NakupniNapotek.zaVstopnice(odprta: vstopnice(5), trenutna: vstopnice(3), gumbNaVoljo: true),
                       .preveriProfil)
    }

    func testVstopniceRazprodanoDaPreveriProfil() {
        XCTAssertEqual(NakupniNapotek.zaVstopnice(odprta: vstopnice(2), trenutna: vstopnice(2), gumbNaVoljo: false),
                       .preveriProfil)
    }

    func testVstopniceNimajoNapotkaZaNerazresenoMizo() {
        XCTAssertNil(NakupniNapotek.zaVstopnice(odprta: miza(3), trenutna: vstopnice(1), gumbNaVoljo: true))
    }

    // MARK: - VIP

    func testVipBrezNerazresenegaPoskusaNimaNapotka() {
        XCTAssertNil(NakupniNapotek.zaVip(odprta: nil, trenutna: miza(3), gumbNaVoljo: true))
        XCTAssertNil(NakupniNapotek.zaVip(odprta: nil, trenutna: nil, gumbNaVoljo: false))
    }

    func testVipIstaMizaInPaketDaMordaUspelo() {
        XCTAssertEqual(NakupniNapotek.zaVip(odprta: miza(3, paket: 10), trenutna: miza(3, paket: 10), gumbNaVoljo: true),
                       .moznoUspel)
    }

    func testVipMizaBookedBrezIzbireDaPreveriProfil() {
        XCTAssertEqual(NakupniNapotek.zaVip(odprta: miza(3, paket: 10), trenutna: nil, gumbNaVoljo: true), .preveriProfil)
    }

    func testVipDrugaMizaAliDrugPaketDaPreveriProfil() {
        XCTAssertEqual(NakupniNapotek.zaVip(odprta: miza(3, paket: 10), trenutna: miza(4, paket: 10), gumbNaVoljo: true),
                       .preveriProfil)
        XCTAssertEqual(NakupniNapotek.zaVip(odprta: miza(3, paket: 10), trenutna: miza(3, paket: 11), gumbNaVoljo: true),
                       .preveriProfil)
        XCTAssertEqual(NakupniNapotek.zaVip(odprta: miza(3, paket: 10), trenutna: miza(3), gumbNaVoljo: true),
                       .preveriProfil)
    }

    func testVipProdajaZaprtaDaPreveriProfil() {
        XCTAssertEqual(NakupniNapotek.zaVip(odprta: miza(3), trenutna: miza(3), gumbNaVoljo: false), .preveriProfil)
    }

    func testVipNimaNapotkaZaNerazresenoVsebinoVstopnic() {
        XCTAssertNil(NakupniNapotek.zaVip(odprta: vstopnice(2), trenutna: miza(3), gumbNaVoljo: true))
    }

    // MARK: - Shramba: nejasen izid je lepljiv (isti kljuc)

    func testNejasenIzidPreziviNavadnoNapakoZIstimKljucem() {
        let s = novaShramba()
        let prvi = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        // Ponovitev z istim kljucem: 503 (.navadna). Prvo narocilo je lahko ze nastalo -> vsebina ostane odprta.
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(3)), prvi)
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(3))
        // Se ena ponovitev + navadna napaka: se vedno lepljivo; kljuc isti.
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(3)), prvi)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(3))   // zahtevek v teku
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(3))
    }

    func testVObdelaviPreziviNavadnoNapako() {
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .vObdelavi)
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), miza(3, paket: 10))
    }

    func testNavadnaNapakaBrezPrejsnjegaNejasnegaIzidaNeDaVsebine() {
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
    }

    func testNejasenIzidPoUspehuJeNil() {
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poUspehu(uporabnik: 1, dogodekId: 7)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
    }

    func testNejasenIzidPoRotacijiKljucaJeNil() {
        let s = novaShramba()
        for izid in [NakupniIzid.kljucZavrzen, .narociloNeaktivno] {
            _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: izid)
            XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), "izid \(izid)")
            // Po rotaciji naslednja navadna napaka ne obudi starega nejasnega izida.
            _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
            XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), "izid \(izid)")
        }
    }

    func testNejasenIzidNeSegaNaNovKljucZaradiDrugeVsebine() {
        let s = novaShramba()
        let prvi = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        // Druga kolicina = nov kljuc (pravilo NakupniKljuc ostane); njena navadna napaka ne podeduje nejasnega izida.
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(4)), prvi)
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
    }

    func testDrugUporabnikInDrugDogodekNistaDelezniNapotka() {
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 2, dogodekId: 7))
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 8))
        XCTAssertNotNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
    }

    // MARK: - Napotek ne spremeni kljuca

    func testBranjeNapotkaNeSpremeniKljucaInKolicineNeZaklene() {
        let s = novaShramba()
        let prvi = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        let odprta = s.odprtaVsebina(uporabnik: 1, dogodekId: 7)
        _ = NakupniNapotek.zaVstopnice(odprta: odprta, trenutna: vstopnice(3), gumbNaVoljo: true)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(3)), prvi)      // ista vsebina = isti kljuc
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(4)), prvi)   // druga kolicina = nov kljuc
    }

    // MARK: - Besedilo

    func testBesediliSta2RazlicniInNeprazni() {
        XCTAssertFalse(NakupniNapotek.moznoUspel.besedilo.isEmpty)
        XCTAssertFalse(NakupniNapotek.preveriProfil.besedilo.isEmpty)
        XCTAssertNotEqual(NakupniNapotek.moznoUspel.besedilo, NakupniNapotek.preveriProfil.besedilo)
    }
}
