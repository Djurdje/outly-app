import XCTest
import Foundation
@testable import Outly

/// Vrnitev na placilo VIP mize po zaprtju lista (outly-app#59): razvrstitev mojega narocila na mizi, ki je zaradi `pending` narocila
/// »Booked«, in pravilo, kdaj se zasedena miza sploh sme obdrzati kot izbrana. Testni razred je `@MainActor`, ker uporablja
/// `NakupniKljucShramba` (`@MainActor`); testni target nima privzete izolacije. Shramba je lasten primerek (brez `deljena`).
@MainActor
final class VipNadaljevanjeTests: XCTestCase {

    private func narocilo(id: Int = 41, event: Int = 7, miza: Int? = 3, status: String, vstopnic: Int = 0,
                          dodatno: String = "") throws -> APIOrder {
        let tickets = (0..<vstopnic).map { #"{"id": \#(100 + $0), "serial": "S\#($0)", "status": "valid", "qr": "q\#($0)"}"# }
            .joined(separator: ",")
        let mizaJSON = miza.map { #""table_id": \#($0), "is_vip": true,"# } ?? ""
        let json = """
        {"id": \(id), "public_ref": "OUT-1", "event_id": \(event), \(mizaJSON) "status": "\(status)", "quantity": 1,
         "total_cents": 30000, "tickets": [\(tickets)]\(dodatno)}
        """
        return try JSONDecoder().decode(APIOrder.self, from: Data(json.utf8))
    }

    private func razvrsti(_ n: [APIOrder], event: Int = 7, miza: Int = 3) -> VipNadaljevanje {
        VipNadaljevanje.razvrsti(narocila: n, dogodekId: event, mizaId: miza).stanje
    }

    // MARK: - razvrsti

    func testPendingSVeljavnoSejoNadaljujeZIstimKljucem() throws {
        let n = try narocilo(status: "pending", dodatno: #", "checkout_url": "https://checkout.stripe.com/c/pay/cs_1""#)
        XCTAssertEqual(razvrsti([n]), .nadaljuj)
    }

    func testPotekliPendingNeOdpiraPovezave() throws {
        let n = try narocilo(status: "pending", dodatno: #", "checkout_expired": true"#)
        XCTAssertEqual(razvrsti([n]), .poteklo)
    }

    func testPlaciloVObdelaviNePonujaNovegaPlacila() throws {
        let n = try narocilo(status: "pending", dodatno: #", "payment_processing": true"#)
        XCTAssertEqual(razvrsti([n]), .vObdelavi)
    }

    func testPlacanoZVstopnicamiPokazeUspeh() throws {
        let n = try narocilo(status: "paid", vstopnic: 4)
        let izid = VipNadaljevanje.razvrsti(narocila: [n], dogodekId: 7, mizaId: 3)
        XCTAssertEqual(izid.stanje, .placano)
        XCTAssertEqual(izid.narocilo?.id, 41)
        XCTAssertEqual(izid.narocilo?.tickets.count, 4)
    }

    func testDelnoVrnjenoJeSeVednoMojeAktivnoNarocilo() throws {
        XCTAssertEqual(razvrsti([try narocilo(status: "partially_refunded", vstopnic: 2)]), .placano)
    }

    func testPlacanoBrezVstopnicNiUspehaInNiPlacila() throws {
        // Prehodno stanje (vstopnice se niso zapisane): nic ne spremenimo, ostane napotek »Check Profile -> Tickets«.
        XCTAssertEqual(razvrsti([try narocilo(status: "paid", vstopnic: 0)]), .nejasno)
    }

    func testPreklicanoVrnjenoInNeuspeloNiAktivnoNarocilo() throws {
        for status in ["cancelled", "failed", "refunded"] {
            XCTAssertEqual(razvrsti([try narocilo(status: status)]), .ni, status)
        }
    }

    func testBrezNarocilIzbiraTujeMizeNiMogoca() throws {
        XCTAssertEqual(razvrsti([]), .ni)
    }

    func testNarocilaDrugeMizeInDrugegaDogodkaSeNeStejejo() throws {
        let drugaMiza = try narocilo(id: 1, miza: 9, status: "pending", dodatno: #", "checkout_url": "https://checkout.stripe.com/x""#)
        let drugDogodek = try narocilo(id: 2, event: 8, miza: 3, status: "pending", dodatno: #", "checkout_url": "https://checkout.stripe.com/y""#)
        let vstopnice = try narocilo(id: 3, miza: nil, status: "paid", vstopnic: 2)
        XCTAssertEqual(razvrsti([drugaMiza, drugDogodek, vstopnice]), .ni)
    }

    func testMedVecNarocilIzbereTistoNaZasediMizi() throws {
        let staro = try narocilo(id: 1, status: "cancelled")
        let zivo = try narocilo(id: 2, status: "pending", dodatno: #", "checkout_url": "https://checkout.stripe.com/c/pay/cs_2""#)
        let izid = VipNadaljevanje.razvrsti(narocila: [staro, zivo], dogodekId: 7, mizaId: 3)
        XCTAssertEqual(izid.stanje, .nadaljuj)
    }

    // MARK: - odgovor

    func testOdgovorZaUspehOhraniOznakoTestaSamoPriTestnemNarocilu() throws {
        let pravo = try narocilo(status: "paid", vstopnic: 2, dodatno: #", "is_test": false"#)
        let testno = try narocilo(status: "paid", vstopnic: 2, dodatno: #", "is_test": true"#)
        XCTAssertEqual(VipNadaljevanje.odgovor(pravo).mode, "stripe")
        XCTAssertEqual(VipNadaljevanje.odgovor(testno).mode, "test")
        XCTAssertFalse(VipNadaljevanje.odgovor(pravo).cakaPlacilo)
        XCTAssertEqual(VipNadaljevanje.odgovor(pravo).tickets.count, 2)
    }

    // MARK: - jeMojaMiza

    private func novaShramba() -> NakupniKljucShramba {
        var n = 0
        return NakupniKljucShramba(veljavnost: 600, ura: { Date(timeIntervalSince1970: 1_000_000) },
                                   ustvari: { n += 1; return "k\(n)" })
    }

    func testZasedenaMizaJeMojaSamoZaMizoNerazresenegaPoskusa() {
        let s = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, mizaId: 3, paketId: 5)
        _ = s.zaNakup(uporabnik: 1, vsebina: vsebina)
        let odprta = s.odprtaVsebina(uporabnik: 1, dogodekId: 7, vrsta: .vipMiza)
        XCTAssertTrue(VipNadaljevanje.jeMojaMiza(odprta: odprta, dogodekId: 7, mizaId: 3))
        XCTAssertFalse(VipNadaljevanje.jeMojaMiza(odprta: odprta, dogodekId: 7, mizaId: 4), "tuja miza nikoli")
        XCTAssertFalse(VipNadaljevanje.jeMojaMiza(odprta: odprta, dogodekId: 8, mizaId: 3), "drug dogodek nikoli")
    }

    func testBrezNerazresenegaPoskusaNobenaZasedenaMizaNiMoja() {
        XCTAssertFalse(VipNadaljevanje.jeMojaMiza(odprta: nil, dogodekId: 7, mizaId: 3))
        // Vsebina vstopnic (brez mize) ni VIP poskus.
        let vstopnice = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        XCTAssertFalse(VipNadaljevanje.jeMojaMiza(odprta: vstopnice, dogodekId: 7, mizaId: 3))
    }

    func testPoZavrnjenemNarocilu_KljucSeZavrzeInMizaNiVecMoja() {
        // Pot `.ni`: poNapaki(.narociloNeaktivno) rotira kljuc, odprtaVsebina je nil, zasedena miza ni vec izbirna.
        let s = novaShramba()
        _ = s.zaNakup(uporabnik: 1, vsebina: NakupniKljuc.Vsebina(dogodekId: 7, mizaId: 3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, vrsta: .vipMiza, izid: .narociloNeaktivno)
        let odprta = s.odprtaVsebina(uporabnik: 1, dogodekId: 7, vrsta: .vipMiza)
        XCTAssertNil(odprta)
        XCTAssertFalse(VipNadaljevanje.jeMojaMiza(odprta: odprta, dogodekId: 7, mizaId: 3))
    }

    func testIstiKljucSeNeUporabiZaDrugoMizo() {
        // Kljuc je vezan na (dogodek, miza, paket): druga miza dobi nov kljuc, tudi ce je prva se nerazresena.
        let s = novaShramba()
        let a = s.zaNakup(uporabnik: 1, vsebina: NakupniKljuc.Vsebina(dogodekId: 7, mizaId: 3))
        let b = s.zaNakup(uporabnik: 1, vsebina: NakupniKljuc.Vsebina(dogodekId: 7, mizaId: 4))
        XCTAssertNotEqual(a, b)
        let drugDogodek = s.zaNakup(uporabnik: 1, vsebina: NakupniKljuc.Vsebina(dogodekId: 8, mizaId: 4))
        XCTAssertNotEqual(b, drugDogodek)
    }
}
