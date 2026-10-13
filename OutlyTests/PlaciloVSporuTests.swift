import XCTest
import Foundation
@testable import Outly

/// Placilo v sporu (outly-app#92, backend#232): vstopnica z odprtim ali izgubljenim sporom pri banki ima `status: valid` in
/// `payment_disputed: true`. Skener jo mora zavrniti z jasnim sporocilom, denarnica jo mora pokazati kot neveljavno.
/// Star backend polja nima: dekodiranje ne sme pasti, privzeto je false.
@MainActor
final class PlaciloVSporuTests: XCTestCase {

    private func decode<T: Decodable>(_ tip: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(tip, from: Data(json.utf8))
    }

    private func vstopnica(status: String = "valid", polje: String = "") throws -> APITicket {
        let json = """
        {"id": 1, "serial": "ABC123", "status": "\(status)", "qr": "signed", "event_title": "Noc",
         "start_at": "\(DateParsing.isoFrac.string(from: Date().addingTimeInterval(60 * 60 * 24 * 30)))"\(polje)}
        """
        return try decode(APITicket.self, json)
    }

    // MARK: - Modeli

    func testVstopnicaBrezPoljaNiVSporu() throws {
        let t = try vstopnica()
        XCTAssertFalse(t.paymentDisputed)
        XCTAssertFalse(t.jeVSporu)
        XCTAssertTrue(t.jeVeljavna)
        XCTAssertEqual(t.statusLabel, String(localized: "VALID"))
    }

    func testVstopnicaZNullPoljemNiVSporu() throws {
        XCTAssertFalse(try vstopnica(polje: #", "payment_disputed": null"#).paymentDisputed)
        XCTAssertFalse(try vstopnica(polje: #", "payment_disputed": "napacen tip""#).paymentDisputed)
    }

    func testVstopnicaZPoljemTrueJeNeveljavna() throws {
        let t = try vstopnica(polje: #", "payment_disputed": true"#)
        XCTAssertTrue(t.paymentDisputed)
        XCTAssertTrue(t.jeVSporu)
        XCTAssertEqual(t.status, "valid")   // status ostane valid: neveljavnost pove samo polje
        XCTAssertFalse(t.jeVeljavna)
        XCTAssertEqual(t.statusLabel, String(localized: "PAYMENT DISPUTED"))
    }

    func testSporPrevladaSamoPriValid() throws {
        let vrnjena = try vstopnica(status: "refunded", polje: #", "payment_disputed": true"#)
        XCTAssertFalse(vrnjena.jeVSporu)
        XCTAssertEqual(vrnjena.statusLabel, String(localized: "REFUNDED"))
        let preklicana = try vstopnica(status: "void", polje: #", "payment_disputed": true"#)
        XCTAssertFalse(preklicana.jeVSporu)
        XCTAssertEqual(preklicana.statusLabel, String(localized: "VOID"))
        let valid = try vstopnica(status: "valid", polje: #", "payment_disputed": true"#)
        XCTAssertTrue(valid.jeVSporu)
        XCTAssertEqual(valid.statusLabel, String(localized: "PAYMENT DISPUTED"))
    }

    func testSporNePrekrijeExpiredPriPreteklemDogodku() throws {
        let json = """
        {"id": 1, "serial": "ABC123", "status": "valid", "qr": "signed", "payment_disputed": true,
         "start_at": "\(DateParsing.isoFrac.string(from: Date().addingTimeInterval(-60 * 60 * 24 * 30)))"}
        """
        let t = try decode(APITicket.self, json)
        XCTAssertFalse(t.jeVSporu)
        XCTAssertEqual(t.statusLabel, String(localized: "EXPIRED"))
    }

    func testUporabljenaVstopnicaOstaneUporabljena() throws {
        let t = try vstopnica(status: "used", polje: #", "payment_disputed": true"#)
        XCTAssertFalse(t.jeVSporu)
        XCTAssertEqual(t.statusLabel, String(localized: "USED"))
    }

    func testVstopnicaPreziviShranjevanjeNaTelefon() throws {
        let t = try vstopnica(polje: #", "payment_disputed": true"#)
        let nazaj = try JSONDecoder().decode(APITicket.self, from: JSONEncoder().encode(t))
        XCTAssertTrue(nazaj.paymentDisputed)
    }

    func testSeznamZaSkenBrezPoljaInZPoljem() throws {
        let star = try decode(ScanListTicket.self, #"{"serial": "s1", "status": "unpaid"}"#)
        XCTAssertFalse(star.paymentDisputed)
        let nov = try decode(ScanListTicket.self, #"{"serial": "s1", "status": "unpaid", "payment_disputed": true}"#)
        XCTAssertTrue(nov.paymentDisputed)
        let nazaj = try JSONDecoder().decode(ScanListTicket.self, from: JSONEncoder().encode(nov))
        XCTAssertEqual(nazaj, nov)
        XCTAssertTrue(nazaj.paymentDisputed)
    }

    func testVstopnicaVOdgovoruSkena() throws {
        let brez = try decode(ScanResult.self, #"{"result":"ok","message":"x","ticket":{"is_vip":false}}"#)
        XCTAssertEqual(brez.ticket?.paymentDisputed, false)
        let r = try decode(ScanResult.self, #"{"result":"payment_disputed","message":"The payment for this ticket is disputed (chargeback).","ticket":{"is_vip":true,"payment_disputed":true}}"#)
        XCTAssertEqual(r.result, "payment_disputed")
        XCTAssertEqual(r.ticket?.paymentDisputed, true)
        XCTAssertNil(r.usedAt)
    }

    // MARK: - Prikaz v skenerju

    func testSpletniSkenPokazeRdeceBesediloZaVratarja() throws {
        let r = try decode(ScanResult.self, #"{"result":"payment_disputed","message":"The payment for this ticket is disputed (chargeback). Do not admit; send the guest to the club manager.","ticket":{"is_vip":false,"payment_disputed":true}}"#)
        let p = SkenPrikaz.iz(r)
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertFalse(p.uspesen)
        XCTAssertFalse(p.ponudiVstop)
        XCTAssertEqual(p.naslov, String(localized: "PAYMENT DISPUTED"))
        XCTAssertEqual(p.podnaslov, String(localized: "Ticket not valid. Send the guest to the club manager."))
        XCTAssertNotEqual(p.naslov, String(localized: "REFUSED"))
    }

    func testSpletniSkenPokazeVipInGuestListo() throws {
        let r = try decode(ScanResult.self, #"{"result":"payment_disputed","message":"x","ticket":{"is_vip":true,"table_label":"T1","is_guest_list":true,"guest_list_host_username":"marko"}}"#)
        let p = SkenPrikaz.iz(r)
        XCTAssertNotNil(p.vip)
        XCTAssertTrue(p.guestList?.contains("@marko") == true)
    }

    func testDokoncniOdgovorStreznikaZaLokalnoZelenSken() {
        let sodba = SkenSodba(razlog: .veljavna, serial: "s1")
        let p = SkenPrikaz.iz(streznik: "payment_disputed", usedAt: nil, sodba: sodba)
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, String(localized: "PAYMENT DISPUTED"))
        XCTAssertEqual(p.podnaslov, String(localized: "Ticket not valid. Send the guest to the club manager."))
        XCTAssertNotEqual(p.naslov, String(localized: "INVALID CODE"))
    }

    func testSkenBrezPovezavePokazeIstoBesedilo() {
        let v = ScanListTicket(serial: "s1", status: "unpaid", holderUsername: "ana", paymentDisputed: true)
        let p = SkenPrikaz.iz(SkenSodba(razlog: .placiloVSporu, serial: "s1", vstopnica: v), qr: "q")
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, String(localized: "PAYMENT DISPUTED"))
        XCTAssertEqual(p.podnaslov, String(localized: "Ticket not valid. Send the guest to the club manager."))
        XCTAssertFalse(p.ponudiVstop)
        XCTAssertNotEqual(p.naslov, String(localized: "NOT PAID"))
    }

    func testSodbaPlaciloVSporuJeRdecaInNiZaVstop() {
        let s = SkenSodba(razlog: .placiloVSporu, serial: "s1")
        XCTAssertEqual(s.barva, .rdece)
        XCTAssertFalse(s.spusti)
    }

    func testKonfliktPoSinhronizacijiImaLastnoBesedilo() {
        let b = SkenPrikaz.razlogKonflikta("payment_disputed")
        XCTAssertEqual(b, String(localized: "The payment is disputed: this guest was let in, but the ticket is not valid."))
        XCTAssertNotEqual(b, SkenPrikaz.razlogKonflikta("neznano-novo-stanje"))
    }

    func testRezultatSinhronizacijeJeDokoncen() throws {
        let r = try decode(ScanBatchResult.self, #"{"client_scan_id":"a","serial":"s1","result":"payment_disputed","used_at":null}"#)
        XCTAssertEqual(r.result, "payment_disputed")
        XCTAssertNil(r.usedAt)
        XCTAssertTrue(r.jeDokoncen)   // vnos gre iz vrste in postane konflikt, ne ponavlja se
    }
}
