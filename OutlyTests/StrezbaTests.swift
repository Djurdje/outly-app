import XCTest
import Foundation
@testable import Outly

/// Vloga bartender + strezba VIP miz (9. 10. 2026, issue #176): novo polje Me s privzeto vrednostjo, oblike odgovorov,
/// vrstni red dogodkov v izbirniku in pravilo, kdo vidi Table service.
@MainActor
final class StrezbaTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testMeBrezPoljaImaNic() throws {
        let me = try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "u"}"#)
        XCTAssertEqual(me.pendingTableService, 0)
    }

    func testMePrezivi_encodeDecode() throws {
        let me = try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "u", "pending_table_service": 3, "club_role": "bartender"}"#)
        let nazaj = try JSONDecoder().decode(Me.self, from: JSONEncoder().encode(me))
        XCTAssertEqual(nazaj.pendingTableService, 3)
        XCTAssertEqual(nazaj, me)
        XCTAssertFalse(me.canManageClub)
        XCTAssertTrue(me.isBusiness)
    }

    func testStrezbaDekodiraPolja() throws {
        let r = try decode(TableServiceResponse.self, #"""
        {"items": [{"id": 5, "order_id": 9, "table_label": "V3", "table_seats": 6, "package_name": "Gold",
                    "package_description": "2 bottles", "scanned_at": "2026-10-10T20:14:00.000Z",
                    "delivered_at": null, "delivered_by_username": null}]}
        """#)
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].tableLabel, "V3")
        XCTAssertFalse(r.items[0].jeDostavljeno)
        XCTAssertNotNil(r.items[0].scannedDate)
    }

    func testStrezbaBrezPoljNePodreDekodiranja() throws {
        let t = try decode(TableServiceItem.self, #"{"id": 1}"#)
        XCTAssertEqual(t.tableLabel, "")
        XCTAssertEqual(t.tableSeats, 0)
        XCTAssertFalse(t.jeDostavljeno)
        let prazno = try decode(TableServiceResponse.self, "{}")
        XCTAssertTrue(prazno.items.isEmpty)
    }

    func testZvonecVrstica() throws {
        let r = try decode(MyTableServiceResponse.self, #"""
        {"items": [{"id": 2, "club_id": 7, "club_name": "Klub", "event_id": 11, "event_title": "Noc",
                    "table_label": "A1", "package_name": "Silver", "scanned_at": "2026-10-10T20:14:00Z"}]}
        """#)
        XCTAssertEqual(r.items[0].clubId, 7)
        XCTAssertEqual(r.items[0].eventId, 11)
    }

    func testKdoVidiStrezbo() {
        XCTAssertTrue(TableServiceView.smeVideti(role: "owner"))
        XCTAssertTrue(TableServiceView.smeVideti(role: "manager"))
        XCTAssertTrue(TableServiceView.smeVideti(role: "bartender"))
        XCTAssertFalse(TableServiceView.smeVideti(role: "doorman"))
    }

    func testVlogeBartender() throws {
        let clan = try decode(TeamMember.self, #"{"user_id": 1, "role": "bartender"}"#)
        XCTAssertEqual(clan.roleIcon, "wineglass")
        let vabilo = try decode(MyInvite.self, #"{"id": 1, "role": "bartender"}"#)
        XCTAssertEqual(vabilo.roleDescription, String(localized: "serving VIP tables"))
    }

    func testIzbirnikDogodkov_tekociPrviNatoPrihajajociIzpusceniOsnutki() throws {
        let zdaj = Date()
        func dogodek(_ id: Int, _ odUre: Double, status: String = "published") throws -> APIEvent {
            let cas = DateParsing.iso.string(from: zdaj.addingTimeInterval(odUre * 3600))
            return try decode(APIEvent.self, #"{"id": \#(id), "title": "E\#(id)", "start_at": "\#(cas)", "status": "\#(status)", "club_id": 1}"#)
        }
        let seznam = [try dogodek(1, 30), try dogodek(2, -3), try dogodek(3, 5), try dogodek(4, 2, status: "draft"), try dogodek(5, -40)]
        let urejeni = TableServiceView.urediDogodke(seznam, zdaj: zdaj).map { $0.id }
        XCTAssertEqual(urejeni, [2, 3, 1, 5])
    }
}
