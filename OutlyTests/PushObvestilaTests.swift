import XCTest
import Foundation
@testable import Outly

/// Potisna obvestila (APNs, outly-backend#184): kam vodi dotik (`outly.type` / `outly.id`) in kdaj se zeton znova poslje.
/// Cista logika (PushCilj, PushOdlocitev); sistemski del (dovoljenje, delegat) se preveri na napravi.
@MainActor
final class PushObvestilaTests: XCTestCase {

    private func userInfo(_ vrsta: String, _ id: Any) -> [AnyHashable: Any] {
        ["aps": ["sound": "default"], "outly": ["type": vrsta, "id": id]]
    }

    // MARK: - Cilj dotika

    func testVrsteObvestilVodijoNaPravaZaslona() {
        XCTAssertEqual(PushCilj(userInfo: userInfo("ticket_received", 5)), PushCilj.vstopnice(id: 5))
        XCTAssertEqual(PushCilj(userInfo: userInfo("guest_list_invite", 7)), PushCilj.vstopnice(id: 7))
        XCTAssertEqual(PushCilj(userInfo: userInfo("club_event", 123)), PushCilj.dogodek(id: 123))
        XCTAssertEqual(PushCilj(userInfo: userInfo("table_service", 9)), PushCilj.strezba(id: 9))
    }

    func testIdIzJsonStevilaInNiza() throws {
        let json = #"{"aps":{"sound":"default"},"outly":{"type":"club_event","id":42}}"#
        let slovar = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [AnyHashable: Any])
        XCTAssertEqual(PushCilj(userInfo: slovar), PushCilj.dogodek(id: 42))
        XCTAssertEqual(PushCilj(userInfo: userInfo("table_service", "9")), PushCilj.strezba(id: 9))
    }

    func testNeznanTipAliManjkajocIdNimaCilja() {
        XCTAssertNil(PushCilj(userInfo: userInfo("neznano", 1)))
        XCTAssertNil(PushCilj(userInfo: userInfo("club_event", 0)))
        XCTAssertNil(PushCilj(userInfo: userInfo("club_event", -3)))
        XCTAssertNil(PushCilj(userInfo: ["aps": ["sound": "default"]]))
        XCTAssertNil(PushCilj(userInfo: ["outly": ["type": "club_event"]]))
        XCTAssertNil(PushCilj(userInfo: ["outly": ["id": 3]]))
    }

    func testVsakCiljImaSvojId() {
        XCTAssertNotEqual(PushCilj.vstopnice(id: 1).id, PushCilj.dogodek(id: 1).id)
        XCTAssertNotEqual(PushCilj.dogodek(id: 1).id, PushCilj.dogodek(id: 2).id)
    }

    func testUsmerjevalnikCiljPrevzameSamoEnkrat() {
        let u = PushUsmerjevalnik.deljen
        u.pocisti()
        XCTAssertNil(u.prevzemi())
        u.postavi(.dogodek(id: 4))
        XCTAssertEqual(u.prevzemi(), PushCilj.dogodek(id: 4))
        XCTAssertNil(u.prevzemi(), "cilj se prevzame samo enkrat")
        u.postavi(.strezba(id: 2))
        u.pocisti()
        XCTAssertNil(u.prevzemi(), "pocisceni cilj (odjava) se ne prevzame")
    }

    // MARK: - Registracija zetona

    func testRegistracijaSamoKoJeTreba() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let zadnja = PushRegistracija(zeton: "ab", uporabnikId: 1, cas: t0)
        XCTAssertTrue(PushOdlocitev.jeTreba(zeton: "ab", uporabnikId: 1, zadnja: nil, zdaj: t0), "prvic")
        XCTAssertFalse(PushOdlocitev.jeTreba(zeton: "ab", uporabnikId: 1, zadnja: zadnja, zdaj: t0.addingTimeInterval(3600)), "isti zeton in uporabnik, 1 h")
        XCTAssertFalse(PushOdlocitev.jeTreba(zeton: "ab", uporabnikId: 1, zadnja: zadnja, zdaj: t0.addingTimeInterval(24 * 3600)), "natanko 24 h")
        XCTAssertTrue(PushOdlocitev.jeTreba(zeton: "ab", uporabnikId: 1, zadnja: zadnja, zdaj: t0.addingTimeInterval(24 * 3600 + 1)), "starejse od 24 h")
        XCTAssertTrue(PushOdlocitev.jeTreba(zeton: "cd", uporabnikId: 1, zadnja: zadnja, zdaj: t0.addingTimeInterval(10)), "spremenjen zeton")
        XCTAssertTrue(PushOdlocitev.jeTreba(zeton: "ab", uporabnikId: 2, zadnja: zadnja, zdaj: t0.addingTimeInterval(10)), "drug uporabnik")
        XCTAssertTrue(PushOdlocitev.jeTreba(zeton: "ab", uporabnikId: 1, zadnja: zadnja, zdaj: t0.addingTimeInterval(-10)), "ura premaknjena nazaj")
    }

    func testZetonJeHexZMalimiCrkami() {
        XCTAssertEqual(PushOdlocitev.hex(Data([0x00, 0xAB, 0x0F, 0xFF])), "00ab0fff")
    }

    func testStanjeRegistracijePreziviKodiranje() throws {
        let r = PushRegistracija(zeton: "00ab", uporabnikId: 3, cas: Date(timeIntervalSince1970: 1_000_000))
        let nazaj = try JSONDecoder().decode(PushRegistracija.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(nazaj, r)
    }
}
