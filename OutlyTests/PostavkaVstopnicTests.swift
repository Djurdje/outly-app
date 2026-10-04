import XCTest
import Foundation
@testable import Outly

/// `PostavkaVstopnic.zdruzi`: VIP vstopnice istega narocila v eno razprto vrstico (Martin, 4. 10. 2026).
@MainActor
final class PostavkaVstopnicTests: XCTestCase {

    private func vstopnica(id: Int, narocilo: Int, vip: Bool) throws -> APITicket {
        let json = """
        {
            "id": \(id),
            "order_id": \(narocilo),
            "event_id": 20,
            "serial": "ABC\(id)",
            "status": "valid",
            "used_at": null,
            "created_at": "2026-01-01T00:00:00.000Z",
            "qr": "signed-payload",
            "public_ref": "OUT-\(narocilo)",
            "event_title": "Test dogodek",
            "start_at": "2030-01-01T22:00:00.000Z",
            "end_at": null,
            "poster_url": "",
            "min_age": 18,
            "club_id": 5,
            "club_name": "Klub",
            "address": "",
            "city": "",
            "logo_url": "",
            "transferable": true,
            "transferred": false,
            "holder_username": "",
            "buyer_username": "",
            "is_vip": \(vip ? "true" : "false"),
            "table_label": \(vip ? "\"5\"" : "null")
        }
        """
        return try JSONDecoder().decode(APITicket.self, from: Data(json.utf8))
    }

    private func opis(_ p: [PostavkaVstopnic]) -> [String] {
        p.map {
            switch $0 {
            case .ena(let t): return "ena \(t.id)"
            case .miza(let o, let v): return "miza \(o): " + v.map { String($0.id) }.joined(separator: ",")
            }
        }
    }

    func testVipIstegaNarocilaVEnoMizoNaMestuPrve() throws {
        let seznam = [
            try vstopnica(id: 1, narocilo: 100, vip: false),
            try vstopnica(id: 2, narocilo: 200, vip: true),
            try vstopnica(id: 3, narocilo: 200, vip: true),
            try vstopnica(id: 4, narocilo: 300, vip: false),
            try vstopnica(id: 5, narocilo: 200, vip: true),
        ]
        XCTAssertEqual(opis(PostavkaVstopnic.zdruzi(seznam)), ["ena 1", "miza 200: 2,3,5", "ena 4"])
    }

    func testNavadneVstopniceIstegaNarocilaOstanejoLocene() throws {
        let seznam = [
            try vstopnica(id: 1, narocilo: 100, vip: false),
            try vstopnica(id: 2, narocilo: 100, vip: false),
        ]
        XCTAssertEqual(opis(PostavkaVstopnic.zdruzi(seznam)), ["ena 1", "ena 2"])
    }

    func testEnaVipVstopnicaOstaneNavadnaVrstica() throws {
        let seznam = [try vstopnica(id: 7, narocilo: 700, vip: true)]
        XCTAssertEqual(opis(PostavkaVstopnic.zdruzi(seznam)), ["ena 7"])
    }

    func testDveMiziLoceni() throws {
        let seznam = [
            try vstopnica(id: 1, narocilo: 100, vip: true),
            try vstopnica(id: 2, narocilo: 200, vip: true),
            try vstopnica(id: 3, narocilo: 100, vip: true),
            try vstopnica(id: 4, narocilo: 200, vip: true),
        ]
        let p = PostavkaVstopnic.zdruzi(seznam)
        XCTAssertEqual(opis(p), ["miza 100: 1,3", "miza 200: 2,4"])
        XCTAssertEqual(Set(p.map(\.id)).count, p.count, "id-ji postavk morajo biti unikatni (ForEach)")
    }

    func testPrazenSeznam() {
        XCTAssertTrue(PostavkaVstopnic.zdruzi([]).isEmpty)
    }
}
