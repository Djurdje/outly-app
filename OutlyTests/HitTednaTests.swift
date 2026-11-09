import XCTest
import Foundation
@testable import Outly

/// »Last week's biggest hits« kaze samo dogodek, ki se je ze zacel v zadnjih 7 dneh (9. 11. 2026:
/// razdelek je pokazal prihajajoci QUICKIE).
@MainActor
final class HitTednaTests: XCTestCase {

    private let zdaj = Date(timeIntervalSince1970: 1_800_000_000)
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func dogodek(id: Int, zacetekPredDnevi dnevi: Double, prodanih: Int) throws -> APIEvent {
        let zacetek = iso.string(from: zdaj.addingTimeInterval(-dnevi * 24 * 3600))
        let json = """
        {"id": \(id), "club_id": 1, "title": "T\(id)", "description": "", "poster_url": "",
         "start_at": "\(zacetek)", "end_at": null, "min_age": 18, "genres": [], "status": "published",
         "time_status": "popular", "ticket_price_cents": null, "currency": null, "ticket_url": null,
         "capacity": null, "sold_count": \(prodanih), "availability": null}
        """
        return try JSONDecoder().decode(APIEvent.self, from: Data(json.utf8))
    }

    func testPrihajajociDogodekNikoliNiHit() throws {
        let prihodnji = try dogodek(id: 1, zacetekPredDnevi: -18, prodanih: 500)
        XCTAssertNil(HitTedna.izberi(iz: [prihodnji], zdaj: zdaj))
    }

    func testPretekliDogodekZadnjegaTednaZNajvecProdanimiZmaga() throws {
        let a = try dogodek(id: 1, zacetekPredDnevi: 2, prodanih: 10)
        let b = try dogodek(id: 2, zacetekPredDnevi: 5, prodanih: 40)
        let c = try dogodek(id: 3, zacetekPredDnevi: -3, prodanih: 900)
        XCTAssertEqual(HitTedna.izberi(iz: [a, b, c], zdaj: zdaj)?.id, 2)
    }

    func testStarejsiOdTedenInBrezProdajeNista() throws {
        let star = try dogodek(id: 1, zacetekPredDnevi: 8, prodanih: 100)
        let brez = try dogodek(id: 2, zacetekPredDnevi: 1, prodanih: 0)
        XCTAssertNil(HitTedna.izberi(iz: [star, brez], zdaj: zdaj))
    }
}
