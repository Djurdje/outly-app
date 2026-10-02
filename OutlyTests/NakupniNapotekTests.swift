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

    // MARK: - Vstopnice

    func testVstopniceBrezPrejsnjegaPoskusaNimajoNapotka() {
        XCTAssertNil(NakupniNapotek.zaVstopnice(odprtaVsebina: nil))
    }

    func testVstopnicePoNejasnemIzidu() {
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        for izid in [NakupniIzid.nejasen, .vObdelavi] {
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: izid)
            XCTAssertEqual(NakupniNapotek.zaVstopnice(odprtaVsebina: s.odprtaVsebina(uporabnik: 1, dogodekId: 7)),
                           .moznoUspel, "izid \(izid)")
        }
    }

    func testVstopniceBrezNapotkaPoDokoncniNapakiInUspehu() {
        let s = novaShramba()
        for izid in [NakupniIzid.navadna, .kljucZavrzen, .narociloNeaktivno] {
            _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: izid)
            XCTAssertNil(NakupniNapotek.zaVstopnice(odprtaVsebina: s.odprtaVsebina(uporabnik: 1, dogodekId: 7)),
                         "izid \(izid)")
        }
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poUspehu(uporabnik: 1, dogodekId: 7)
        XCTAssertNil(NakupniNapotek.zaVstopnice(odprtaVsebina: s.odprtaVsebina(uporabnik: 1, dogodekId: 7)))
    }

    func testVstopniceNimajoNapotkaZaNerazresenoMizo() {
        XCTAssertNil(NakupniNapotek.zaVstopnice(odprtaVsebina: miza(3)))
    }

    // MARK: - VIP

    func testVipBrezPrejsnjegaPoskusaNimaNapotka() {
        XCTAssertNil(NakupniNapotek.zaVip(odprtaVsebina: nil, mizaProsta: true))
        XCTAssertNil(NakupniNapotek.zaVip(odprtaVsebina: nil, mizaProsta: false))
    }

    func testVipMizaSeProstaDaNapotekDaJeMordaUspelo() {
        XCTAssertEqual(NakupniNapotek.zaVip(odprtaVsebina: miza(3, paket: 10), mizaProsta: true), .moznoUspel)
    }

    func testVipMizaBookedDaNapotekProfilTickets() {
        XCTAssertEqual(NakupniNapotek.zaVip(odprtaVsebina: miza(3, paket: 10), mizaProsta: false), .preveriProfil)
    }

    func testVipNimaNapotkaZaNerazresenoVsebinoVstopnic() {
        XCTAssertNil(NakupniNapotek.zaVip(odprtaVsebina: vstopnice(2), mizaProsta: true))
    }

    func testVipPoNejasnemIzidu() {
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        let prej = s.odprtaVsebina(uporabnik: 1, dogodekId: 7)
        XCTAssertEqual(NakupniNapotek.zaVip(odprtaVsebina: prej, mizaProsta: true), .moznoUspel)
        XCTAssertEqual(NakupniNapotek.zaVip(odprtaVsebina: prej, mizaProsta: false), .preveriProfil)
    }

    // MARK: - Napotek ne spremeni kljuca

    func testBranjeNapotkaNeSpremeniKljucaInKolicineNeZaklene() {
        let s = novaShramba()
        let prvi = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        _ = NakupniNapotek.zaVstopnice(odprtaVsebina: s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
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
