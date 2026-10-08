import XCTest
import Foundation
@testable import Outly

/// Razdelitev VIP vstopnic po nakupu mize (8. 10. 2026): meja N-1, posiljanje od druge vstopnice, zaporedje, delni neuspeh.
@MainActor
final class VipRazdelitevTests: XCTestCase {

    private func vstopnica(id: Int, status: String = "valid", transferred: Bool = false) throws -> APITicket {
        let json = """
        {"id": \(id), "order_id": 10, "event_id": 20, "serial": "S\(id)", "status": "\(status)", "qr": "q\(id)",
         "transferred": \(transferred), "is_vip": true, "table_label": "T1", "table_seats": 6}
        """
        return try JSONDecoder().decode(APITicket.self, from: Data(json.utf8))
    }

    private func miza(_ n: Int) throws -> [APITicket] {
        try (1...n).map { try vstopnica(id: 100 + $0) }
    }

    private func prijatelji(_ idji: [Int]) -> [FriendUser] {
        idji.map { FriendUser(id: $0, username: "u\($0)", avatarUrl: nil) }
    }

    /// Prevzame vstopnica-id, po katerih je bil klican `posli` (v vrstnem redu klicev).
    private final class Dnevnik {
        var klici: [(prijatelj: Int, vstopnica: Int)] = []
    }

    // MARK: - Meja

    func testMejaJeNMinusEna() throws {
        XCTAssertEqual(VipRazdelitev.najvecPrijateljev(vstopnic: 6), 5)
        XCTAssertEqual(VipRazdelitev.najvecPrijateljev(vstopnic: 2), 1)
        XCTAssertEqual(VipRazdelitev.najvecPrijateljev(vstopnic: 1), 0)
        XCTAssertEqual(VipRazdelitev.najvecPrijateljev(vstopnic: 0), 0)
        XCTAssertEqual(VipRazdelitev.meja(try miza(4)), 3)
    }

    func testMejaStejeSamoMojeVeljavneVstopnice() throws {
        let seznam = [try vstopnica(id: 1), try vstopnica(id: 2, transferred: true), try vstopnica(id: 3, status: "void"), try vstopnica(id: 4)]
        XCTAssertEqual(VipRazdelitev.moje(seznam).map(\.id), [1, 4])
        XCTAssertEqual(VipRazdelitev.meja(seznam), 1)
    }

    // MARK: - Izbira vstopnic

    func testPrvaVstopnicaOstaneKupcu() throws {
        XCTAssertEqual(VipRazdelitev.zaPosiljanje(try miza(4)).map(\.id), [102, 103, 104])
        XCTAssertTrue(VipRazdelitev.zaPosiljanje(try miza(1)).isEmpty)
        XCTAssertTrue(VipRazdelitev.zaPosiljanje([]).isEmpty)
    }

    func testPariOdDrugeVstopniceNaprejVVrstnemReduIzbire() throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([9, 7]), vstopnice: try miza(4))
        XCTAssertEqual(pari.map { [$0.prijatelj.id, $0.vstopnicaId] }, [[9, 102], [7, 103]])
    }

    func testPariNikoliNePresezejoStevilaProstihVstopnic() throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([1, 2, 3, 4]), vstopnice: try miza(3))
        XCTAssertEqual(pari.count, 2, "pri 3 vstopnicah najvec 2 prijatelja")
        XCTAssertFalse(pari.contains { $0.vstopnicaId == 101 })
    }

    func testPrijateljiIzIdjevObdrziVrstniRedInPreskociNeznaneInPodvojene() {
        let r = VipRazdelitev.prijateljiIzIdjev([3, 8, 1, 3], prijatelji([1, 2, 3]))
        XCTAssertEqual(r.map(\.id), [3, 1])
    }

    // MARK: - Zaporedno posiljanje

    func testPosiljaZaporednoVVrstnemRedu() async throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([1, 2, 3]), vstopnice: try miza(4))
        let d = Dnevnik()
        let izid = await VipRazdelitev.razdeli(pari) { par in
            d.klici.append((par.prijatelj.id, par.vstopnicaId))
        }
        XCTAssertEqual(d.klici.map { [$0.prijatelj, $0.vstopnica] }, [[1, 102], [2, 103], [3, 104]])
        XCTAssertTrue(izid.jePopoln)
        XCTAssertEqual(izid.poslani.count, 3)
        XCTAssertNil(izid.zahtevaStarost)
    }

    func testDelniNeuspehPokazeKomuJeSloInKomuNe() async throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([1, 2, 3]), vstopnice: try miza(4))
        let d = Dnevnik()
        let izid = await VipRazdelitev.razdeli(pari) { par in
            d.klici.append((par.prijatelj.id, par.vstopnicaId))
            if par.prijatelj.id == 2 { throw APIError.requestFailed(403, "Your friend is under 18.") }
        }
        XCTAssertEqual(d.klici.count, 3, "napaka enega para ne ustavi ostalih")
        XCTAssertEqual(izid.poslani.map { $0.prijatelj.id }, [1, 3])
        XCTAssertEqual(izid.neuspeli.map { $0.par.prijatelj.id }, [2])
        XCTAssertEqual(izid.neuspeli.first?.par.vstopnicaId, 103, "neuspela vstopnica ostane za ponovitev")
        XCTAssertFalse(izid.neuspeli.first?.sporocilo.isEmpty ?? true)
        XCTAssertFalse(izid.jePopoln)
    }

    func testStarostnaNapakaVrneMejoZaKljukico() async throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([1, 2]), vstopnice: try miza(3))
        let izid = await VipRazdelitev.razdeli(pari) { par in
            if par.prijatelj.id == 1 { throw APIError.requestFailed(400, #"{"error":"age_confirmation_required","min_age":21}"#) }
        }
        XCTAssertEqual(izid.zahtevaStarost, 21)
        XCTAssertEqual(izid.poslani.map { $0.prijatelj.id }, [2])
        XCTAssertEqual(izid.neuspeli.map { $0.par.prijatelj.id }, [1])
    }

    func testPonovitevPosljeSamoNeuspele() async throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([1, 2]), vstopnice: try miza(3))
        let prvi = await VipRazdelitev.razdeli(pari) { par in
            if par.prijatelj.id == 1 { throw APIError.requestFailed(409, "Something") }
        }
        let d = Dnevnik()
        let drugi = await VipRazdelitev.razdeli(prvi.neuspeli.map(\.par)) { par in d.klici.append((par.prijatelj.id, par.vstopnicaId)) }
        XCTAssertEqual(d.klici.map { [$0.prijatelj, $0.vstopnica] }, [[1, 102]], "ista vstopnica za istega prijatelja")
        XCTAssertTrue(drugi.jePopoln)
    }

    func testNapakaPovezaveUstaviOstaleInJihOznaciKotNeposlane() async throws {
        let pari = VipRazdelitev.pari(prijatelji: prijatelji([1, 2, 3]), vstopnice: try miza(4))
        let d = Dnevnik()
        let izid = await VipRazdelitev.razdeli(pari) { par in
            d.klici.append((par.prijatelj.id, par.vstopnicaId))
            if par.prijatelj.id == 2 { throw URLError(.notConnectedToInternet) }
        }
        XCTAssertEqual(d.klici.count, 2, "tretji prijatelj se ne poskusi")
        XCTAssertEqual(izid.poslani.map { $0.prijatelj.id }, [1])
        XCTAssertEqual(izid.neuspeli.map { $0.par.prijatelj.id }, [2, 3])
        XCTAssertEqual(izid.neuspeli[0].sporocilo, izid.neuspeli[1].sporocilo)
    }

    func testKateraNapakaPrekineVse() {
        XCTAssertTrue(VipRazdelitev.prekineVse(URLError(.timedOut)))
        XCTAssertTrue(VipRazdelitev.prekineVse(APIError.requestFailed(401, "")))
        XCTAssertTrue(VipRazdelitev.prekineVse(APIError.requestFailed(503, "")))
        XCTAssertTrue(VipRazdelitev.prekineVse(APIError.requestFailed(429, "")))
        XCTAssertFalse(VipRazdelitev.prekineVse(APIError.requestFailed(403, "Your friend is under 18.")))
        XCTAssertFalse(VipRazdelitev.prekineVse(APIError.requestFailed(404, "Ticket not found.")))
        XCTAssertFalse(VipRazdelitev.prekineVse(APIError.requestFailed(409, "x")))
    }

    func testBrezParovNicNeposlje() async {
        let izid = await VipRazdelitev.razdeli([]) { _ in XCTFail("ne sme klicati") }
        XCTAssertEqual(izid, VipRazdelitev.Izid())
    }
}
