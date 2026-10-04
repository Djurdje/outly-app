import XCTest
import Foundation
@testable import Outly

/// Glava `X-Outly-Client: ios` na nakupnih klicih (backend po njej Stripu nastavi success/cancel URL na outly.si/placilo?app=ios)
/// in da dodatne glave ne pokvarijo obstojecih (Authorization, Idempotency-Key, X-Outly-Club, Content-Type).
@MainActor
final class NakupneGlaveTests: XCTestCase {

    private func zahtevek(path: String, method: String = "POST", token: String? = "tok", json: [String: Any]? = ["quantity": 2],
                          idempotencyKey: String? = "k-1", clubId: Int? = nil,
                          dodatneGlave: [String: String] = [:]) throws -> URLRequest {
        try APIClient.shared.sestaviZahtevek(path: path, method: method, token: token, json: json, query: [], clubId: clubId,
                                             timeout: nil, idempotencyKey: idempotencyKey, dodatneGlave: dodatneGlave)
    }

    func testNakupneGlaveNosijoSamoOdjemalcaIos() {
        XCTAssertEqual(APIClient.nakupneGlave, ["X-Outly-Client": "ios"])
    }

    func testNakupVstopnicInMizeDobiGlavoOdjemalca() throws {
        // Natanko tiste glave, ki jih buyTickets (events/:id/orders) in buyTable (events/:id/tables/:tableId/orders) posljeta.
        let vstopnice = try zahtevek(path: "events/12/orders", dodatneGlave: APIClient.nakupneGlave)
        let miza = try zahtevek(path: "events/12/tables/5/orders", json: ["package_id": 3], dodatneGlave: APIClient.nakupneGlave)
        for r in [vstopnice, miza] {
            XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertEqual(r.value(forHTTPHeaderField: "X-Outly-Client"), "ios")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Idempotency-Key"), "k-1")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNotNil(r.httpBody)
        }
        XCTAssertEqual(vstopnice.url?.path, "/events/12/orders")
        XCTAssertEqual(miza.url?.path, "/events/12/tables/5/orders")
    }

    func testBrezDodatnihGlavOstalihKlicevNiGlaveOdjemalca() throws {
        let r = try zahtevek(path: "me/orders", method: "GET", json: nil, idempotencyKey: nil)
        XCTAssertNil(r.value(forHTTPHeaderField: "X-Outly-Client"))
        XCTAssertNil(r.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testDodatneGlaveNePovozijoObstojecih() throws {
        let r = try zahtevek(path: "events/12/orders", clubId: 9, dodatneGlave: [
            "Authorization": "Bearer ukraden", "Idempotency-Key": "tuj", "X-Outly-Club": "666", "Content-Type": "text/plain",
            "X-Outly-Client": "ios",
        ])
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Idempotency-Key"), "k-1")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Outly-Club"), "9")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Outly-Client"), "ios")
    }
}
