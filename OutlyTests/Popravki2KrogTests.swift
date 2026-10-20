import XCTest
import Foundation
@testable import Outly

/// 2. krog pregleda #114: vrata ne cakajo na osvezitev seznama po rocnem vpisu, »Try again« ob napaki dela prav tudi po
/// spremembi iskanja, cena po 409 velja tudi na zaslonu dogodka. Vse cisto: brez omrezja, deljenega stanja in cakanja.
@MainActor
final class Popravki2KrogTests: XCTestCase {

    private func stran(_ json: String) throws -> SeznamVstopnicDogodka {
        try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(json.utf8))
    }

    // MARK: - Rocni vpis ne blokira vrat

    func testVpisJeVidenTakojPredOsvezitvijo() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "counts": {"all": 2, "expected": 2}, "total": 2}"#),
                   iskanje: "")
        let t1 = s.vrstice[0], t2 = s.vrstice[1]
        XCTAssertFalse(s.jeVpisana(t1))
        s.oznaciVpisano(t1.id)                  // odgovor strezniga je prisel, osvezitev seznama se ni
        XCTAssertTrue(s.jeVpisana(t1))
        XCTAssertFalse(s.jeVpisana(t2))         // druga vstopnica ostane vpisljiva
    }

    func testOsvezitevPrevzameStreznikovoStanje() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciVpisano(1)
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "used"}], "counts": {"all": 1, "checked_in": 1}, "total": 1}"#)], iskanje: "")
        XCTAssertTrue(s.vpisani.isEmpty)
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))   // zdaj po streznikovem statusu
        XCTAssertEqual(s.stevci?.checkedIn, 1)
    }

    func testZastarelaOsvezitevKiVrneValidObdrziOptimisticniIN() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "total": 2}"#), iskanje: "")
        s.oznaciVpisano(1)
        s.oznaciVpisano(2)
        // Odgovor izpred vpisa vstopnice 2: 1 je ze `used`, 2 se `valid`.
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "used"}, {"id": 2, "status": "valid"}], "total": 2}"#)], iskanje: "")
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))
        XCTAssertTrue(s.jeVpisana(s.vrstice[1]))      // vpis 2 se ne izgubi
        XCTAssertEqual(s.vpisani, [2])                // streznik je potrdil samo 1
        // Streznik potrdi se 2: lokalna oznaka ni vec potrebna.
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "used"}, {"id": 2, "status": "used"}], "total": 2}"#)], iskanje: "")
        XCTAssertTrue(s.vpisani.isEmpty)
        XCTAssertTrue(s.vrstice.allSatisfy { s.jeVpisana($0) })
    }

    func testVrnjenaVstopnicaNiIN() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciVpisano(1)
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "refunded"}], "total": 1}"#)], iskanje: "")
        XCTAssertFalse(s.jeVpisana(s.vrstice[0]))
    }

    // MARK: - Napaka vpisa je na vrstici

    func testNapakaVpisaJeSamoNaTejVrstici() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "total": 2}"#), iskanje: "")
        s.oznaciNapakoVpisa(1)
        XCTAssertTrue(s.imaNapakoVpisa(s.vrstice[0]))
        XCTAssertFalse(s.imaNapakoVpisa(s.vrstice[1]))
        XCTAssertFalse(s.jeVpisana(s.vrstice[0]))       // vpis ni uspel: vrstica NI »IN«
    }

    func testUspesenPonovniVpisPobrisenapako() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciNapakoVpisa(1)
        s.oznaciVpisano(1)
        XCTAssertFalse(s.imaNapakoVpisa(s.vrstice[0]))
        XCTAssertTrue(s.napakeVpisa.isEmpty)
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))
    }

    func testNovPoskusPobrisenapakoInNovaNapakaJoVrne() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciNapakoVpisa(1)
        s.pobrisiNapakoVpisa(1)                         // zacetek ponovnega poskusa: vrtavka
        XCTAssertFalse(s.imaNapakoVpisa(s.vrstice[0]))
        s.oznaciNapakoVpisa(1)                          // spet padel
        XCTAssertTrue(s.imaNapakoVpisa(s.vrstice[0]))
    }

    func testOsvezitevKiVrneValidObdrziNapako() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciNapakoVpisa(1)
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#)], iskanje: "")
        XCTAssertTrue(s.imaNapakoVpisa(s.vrstice[0]))   // vstopnica je se `valid`: vratar mora vedeti, da ni vpisana
    }

    func testStreznikKiVrneUsedPobrisenapako() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 1}"#), iskanje: "")
        s.oznaciNapakoVpisa(1)
        // Vpis je kljub napaki (npr. izgubljen odgovor) prisel skozi.
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "used"}], "total": 1}"#)], iskanje: "")
        XCTAssertFalse(s.imaNapakoVpisa(s.vrstice[0]))
        XCTAssertTrue(s.napakeVpisa.isEmpty)
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))
    }

    // MARK: - Zavrnitev in negotov izid vpisa na vrstici

    func testTimeoutInPrekinjenaPovezavaStaNepotrjena() {
        XCTAssertEqual(VrataSeznam.napakaIzIzjeme(URLError(.timedOut)), .nepotrjeno)
        XCTAssertEqual(VrataSeznam.napakaIzIzjeme(URLError(.networkConnectionLost)), .nepotrjeno)
        XCTAssertEqual(VrataSeznam.napakaIzIzjeme(URLError(.notConnectedToInternet)), .neuspelo)   // klic ni sel ven
        XCTAssertEqual(VrataSeznam.napakaIzIzjeme(URLError(.cannotConnectToHost)), .neuspelo)
        XCTAssertEqual(VrataSeznam.napakaIzIzjeme(APIError.requestFailed(500, "")), .neuspelo)
    }

    func testZavrnitevStreznikaGreNaVrsticoZSporocilom() throws {
        for r in ["invalid", "unknown", "wrong_club", "unpaid", "not_today", "void", "refunded", "event_cancelled", "payment_disputed"] {
            XCTAssertEqual(VrataSeznam.zavrnitev(ScanResult(result: r, message: "Sporocilo \(r)", usedAt: nil)), .zavrnjeno("Sporocilo \(r)"), r)
        }
        XCTAssertNil(VrataSeznam.zavrnitev(ScanResult(result: "ok", message: "OK", usedAt: nil)))
        XCTAssertNil(VrataSeznam.zavrnitev(ScanResult(result: "already_used", message: "Used", usedAt: nil)))   // vstopnica je »IN«
        XCTAssertEqual(VrataSeznam.zavrnitev(ScanResult(result: "void", message: "", usedAt: nil)), .zavrnjeno("void"))

        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "total": 2}"#), iskanje: "")
        s.oznaciNapakoVpisa(1, .zavrnjeno("Wrong club"))
        XCTAssertEqual(s.napakaVrstice(s.vrstice[0]), .zavrnjeno("Wrong club"))
        XCTAssertTrue(s.napakaVrstice(s.vrstice[0])?.jeZavrnitev == true)
        XCTAssertNil(s.napakaVrstice(s.vrstice[1]))
        // Osvezitev, ki jo vrne kot valid, zavrnitev obdrzi; uspesen vpis ali `used` jo pobrise.
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "total": 2}"#)], iskanje: "")
        XCTAssertEqual(s.napakaVrstice(s.vrstice[0]), .zavrnjeno("Wrong club"))
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "used"}, {"id": 2, "status": "valid"}], "total": 2}"#)], iskanje: "")
        XCTAssertNil(s.napakaVrstice(s.vrstice[0]))
        s.oznaciNapakoVpisa(2, .nepotrjeno)
        s.oznaciVpisano(2)
        XCTAssertNil(s.napakaVrstice(s.vrstice[1]))
    }

    /// KRITICNO: timeout ne pomeni, da je prvi POST prisel do streznika. `already_used` po timeoutu NI potrditev nasega vpisa
    /// (vmes je lahko vstopnico vpisal drug vratar ali kamera s kopijo kode): ni uspeh (`ok`), temveč opozorilo.
    func testAlreadyUsedPoTimeoutuNiUspehTemvecOpozorilo() {
        let r = ScanResult(result: "already_used", message: "Already used", usedAt: "2026-10-20T21:07:30.000Z")
        XCTAssertTrue(VrataSeznam.jeOpozoriloPoNepotrjenem(r, prejsnja: .nepotrjeno))
        XCTAssertNotEqual(r.result, "ok")
        XCTAssertTrue(VrataSeznam.vpisaniRezultat(r.result))      // vrstica je »IN«: streznik pravi used
        XCTAssertNil(VrataSeznam.zavrnitev(r))                    // ni rdeca zavrnitev na vrstici
        // Brez predhodnega negotovega izida ostane obstojec rdec »already used«.
        XCTAssertFalse(VrataSeznam.jeOpozoriloPoNepotrjenem(r, prejsnja: nil))
        XCTAssertFalse(VrataSeznam.jeOpozoriloPoNepotrjenem(r, prejsnja: .neuspelo))
        XCTAssertFalse(VrataSeznam.jeOpozoriloPoNepotrjenem(r, prejsnja: .zavrnjeno("x")))
        // Drug rezultat po timeoutu ni opozorilo (ok je ok, zavrnitev je zavrnitev).
        for drug in ["ok", "invalid", "wrong_club", "void"] {
            XCTAssertFalse(VrataSeznam.jeOpozoriloPoNepotrjenem(ScanResult(result: drug, message: "", usedAt: nil), prejsnja: .nepotrjeno), drug)
        }
    }

    func testUraVpisaVLokalnemPasu() throws {
        let ljubljana = try XCTUnwrap(TimeZone(identifier: "Europe/Ljubljana"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(VrataSeznam.uraVpisa("2026-10-20T21:07:30.123Z", casovniPas: ljubljana), "23:07")     // poletni cas do 25. 10.
        XCTAssertEqual(VrataSeznam.uraVpisa("2026-10-20T21:07:30Z", casovniPas: utc), "21:07")
        XCTAssertEqual(VrataSeznam.uraVpisa("2026-12-01T21:07:30Z", casovniPas: ljubljana), "22:07")         // zimski cas
        XCTAssertNil(VrataSeznam.uraVpisa(nil, casovniPas: utc))
        XCTAssertNil(VrataSeznam.uraVpisa("ni datum", casovniPas: utc))
    }

    func testZavrnitevZastaraKoOsvezitevPokazeDrugStatus() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "total": 2}"#), iskanje: "")
        s.oznaciNapakoVpisa(1, .zavrnjeno("Not valid today"))
        s.oznaciNapakoVpisa(2, .neuspelo)
        // Isti status: zavrnitev ostane.
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "valid"}, {"id": 2, "status": "valid"}], "total": 2}"#)], iskanje: "")
        XCTAssertEqual(s.napakaVrstice(s.vrstice[0]), .zavrnjeno("Not valid today"))
        // Drug status (vracilo): zavrnitev zastara in se pobrise; izpad povezave (.neuspelo) ostane, dokler vratar ne ponovi.
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1, "status": "refunded"}, {"id": 2, "status": "valid"}], "total": 2}"#)], iskanje: "")
        XCTAssertNil(s.napakaVrstice(s.vrstice[0]))
        XCTAssertEqual(s.napakaVrstice(s.vrstice[1]), .neuspelo)
        XCTAssertEqual(Set(s.napakeVpisa.keys), [2])
    }

    // MARK: - Preklic ni napaka (VIP razdelek, nalaganje)

    func testPreklicNiNapaka() {
        XCTAssertTrue(VrataSeznam.jePreklic(CancellationError()))
        XCTAssertTrue(VrataSeznam.jePreklic(URLError(.cancelled)))
        XCTAssertFalse(VrataSeznam.jePreklic(URLError(.notConnectedToInternet)))
        XCTAssertFalse(VrataSeznam.jePreklic(URLError(.timedOut)))
        XCTAssertFalse(VrataSeznam.jePreklic(APIError.requestFailed(404, "")))
    }

    func testVipPreklicObdrziRazdelekPravaNapakaGaSkrije() {
        XCTAssertEqual(VrataSeznam.vipPoNapaki(URLError(.cancelled), prejsnji: 7), 7)
        XCTAssertEqual(VrataSeznam.vipPoNapaki(CancellationError(), prejsnji: 7), 7)
        XCTAssertNil(VrataSeznam.vipPoNapaki(APIError.requestFailed(404, "not found"), prejsnji: 7))   // star streznik brez poti
        XCTAssertNil(VrataSeznam.vipPoNapaki(URLError(.timedOut), prejsnji: 7))
        XCTAssertNil(VrataSeznam.vipPoNapaki(URLError(.cancelled), prejsnji: Int?.none))
    }

    func testStevecNalaganjRazveljaviStarejsa() {
        var n = VrataNalaganje()
        let a = n.zacni()
        XCTAssertTrue(n.jeZadnje(a))
        let b = n.zacni()
        XCTAssertFalse(n.jeZadnje(a))     // A ne sme prepisati stanja ne sprostiti isLoading
        XCTAssertTrue(n.jeZadnje(b))
    }

    func testLoadMoreNePobriseLokalnihVpisov() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1, "status": "valid"}], "total": 2, "has_more": true, "next_offset": 1}"#), iskanje: "")
        s.oznaciVpisano(1)
        XCTAssertTrue(s.pripni(try stran(#"{"tickets": [{"id": 2, "status": "valid"}], "total": 2}"#), iskanje: "", odmik: 1))
        XCTAssertTrue(s.jeVpisana(s.vrstice[0]))
        XCTAssertFalse(s.jeVpisana(s.vrstice[1]))
    }

    func testKateriRezultatPomeniVpisano() {
        XCTAssertTrue(VrataSeznam.vpisaniRezultat("ok"))
        XCTAssertTrue(VrataSeznam.vpisaniRezultat("already_used"))
        for r in ["invalid", "unknown", "wrong_club", "unpaid", "void", "refunded", "event_cancelled", "not_today", "payment_disputed"] {
            XCTAssertFalse(VrataSeznam.vpisaniRezultat(r), r)
        }
    }

    // MARK: - »Try again« (VrataPonovitev)

    func testPonovitevOsvezitveObdrziMestoNaSeznamu() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "total": 400, "has_more": true, "next_offset": 200}"#), iskanje: "ana")
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: "ana"), .osvezitev)
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: " ana "), .osvezitev)     // ocisceno je isto iskanje
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: "ana"), .naslednjaStran)
        XCTAssertEqual(s.ponovitev(.prvaStran, iskanje: "ana"), .prvaStran)
    }

    func testSpremembaIskanjaMedNapakoNeNaredeMrtvegaGumba() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "total": 400, "has_more": true, "next_offset": 200}"#), iskanje: "ana")
        // Uporabnik tipka dalje: seznam velja za »ana«, »Try again« za »anja« ne sme klicati »Load more« ali osvezitve starega iskanja.
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: "anja"), .prvaStran)
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: "anja"), .prvaStran)
    }

    func testPonovitevBrezNalozenegaSeznama() {
        let s = VrataSeznam()
        XCTAssertEqual(s.ponovitev(.osvezitev, iskanje: ""), .prvaStran)
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: ""), .prvaStran)
    }

    func testZadnjaStranNimaVecNaslednje() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "total": 1, "has_more": false}"#), iskanje: "")
        XCTAssertEqual(s.ponovitev(.naslednjaStran, iskanje: ""), .prvaStran)
    }

    // MARK: - Cena po 409 na zaslonu dogodka

    private func dogodek(priceCents: Int?, currency: String? = "EUR") throws -> APIEvent {
        let cena = priceCents.map { "\($0)" } ?? "null"
        let valuta = currency.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "id": 1, "club_id": 1, "title": "T", "description": "", "poster_url": "",
            "start_at": "2026-01-01T00:00:00.000Z", "end_at": null, "min_age": 18, "genres": [],
            "status": "published", "time_status": "coming_soon",
            "ticket_price_cents": \(cena), "currency": \(valuta), "ticket_url": null,
            "capacity": null, "sold_count": 0, "availability": null
        }
        """
        return try JSONDecoder().decode(APIEvent.self, from: Data(json.utf8))
    }

    func testSvezaCenaPo409NadomestiCenoDogodka() throws {
        let e = try dogodek(priceCents: 1600)
        XCTAssertEqual(e.displayPrice, "€16.00")
        XCTAssertEqual(e.napisCene(cenaCents: nil), "€16.00")
        XCTAssertEqual(e.napisCene(cenaCents: 1800), "€18.00")
        XCTAssertEqual(e.veljavnaCenaCents(cenaCents: 1800), 1800)
        XCTAssertEqual(e.veljavnaCenaCents(cenaCents: nil), 1600)
    }

    func testSvezaCenaNullaJeFree() throws {
        let e = try dogodek(priceCents: 1600)
        XCTAssertEqual(e.veljavnaCenaCents(cenaCents: 0), 0)      // cena padla na 0: zaslon kaze FREE (ticketState)
        XCTAssertEqual(e.napisCene(cenaCents: 0), "€0.00")
    }

    func testDogodekBrezCeneOstaneBrezCeneTudiPo409() throws {
        let e = try dogodek(priceCents: nil)
        XCTAssertNil(e.displayPrice)
        XCTAssertNil(e.napisCene(cenaCents: 1800))
        XCTAssertNil(e.veljavnaCenaCents(cenaCents: 1800))
    }
}
