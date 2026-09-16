import XCTest
import Foundation
@testable import Outly

/// `APITicket`: statusLabel ter transferable/transferred (prenos vstopnice prijatelju, 008).
final class APITicketTests: XCTestCase {

    private func makeTicket(
        status: String = "valid",
        startAt: String,
        transferable: Bool? = nil,
        transferred: Bool? = nil,
        holderUsername: String? = nil,
        buyerUsername: String? = nil
    ) throws -> APITicket {
        func boolJSON(_ b: Bool?) -> String { b.map { $0 ? "true" : "false" } ?? "null" }
        func strJSON(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        let json = """
        {
            "id": 1,
            "order_id": 10,
            "event_id": 20,
            "serial": "ABC123",
            "status": "\(status)",
            "used_at": null,
            "created_at": "2026-01-01T00:00:00.000Z",
            "qr": "signed-payload",
            "public_ref": "OUT-1",
            "event_title": "Test dogodek",
            "start_at": "\(startAt)",
            "end_at": null,
            "poster_url": "",
            "min_age": 18,
            "club_id": 5,
            "club_name": "Klub",
            "address": "",
            "city": "",
            "logo_url": "",
            "transferable": \(boolJSON(transferable)),
            "transferred": \(boolJSON(transferred)),
            "holder_username": \(strJSON(holderUsername)),
            "buyer_username": \(strJSON(buyerUsername))
        }
        """
        return try JSONDecoder().decode(APITicket.self, from: Data(json.utf8))
    }

    /// Datum v prihodnosti/preteklosti, generiran z ISTIM formatterjem kot produkcijska koda
    /// (DateParsing.isoFrac), da testi ne postanejo "casovna bomba".
    private var farFutureISO: String {
        DateParsing.isoFrac.string(from: Date().addingTimeInterval(60 * 60 * 24 * 30))
    }
    private var farPastISO: String {
        DateParsing.isoFrac.string(from: Date().addingTimeInterval(-60 * 60 * 24 * 30))
    }

    // MARK: - statusLabel

    func testStatusLabelUsedTakesPriorityRegardlessOfDate() throws {
        let t = try makeTicket(status: "used", startAt: farFutureISO)
        XCTAssertTrue(t.isUsed)
        XCTAssertEqual(t.statusLabel, "USED")
    }

    func testStatusLabelValidUpcomingIsValid() throws {
        let t = try makeTicket(status: "valid", startAt: farFutureISO)
        XCTAssertFalse(t.isPast)
        XCTAssertEqual(t.statusLabel, "VALID")
    }

    /// Vstopnica velja se 8 ur po zacetku dogodka (glej isPast), zato "davno preteklo" -> EXPIRED.
    func testStatusLabelValidButLongPastIsExpired() throws {
        let t = try makeTicket(status: "valid", startAt: farPastISO)
        XCTAssertTrue(t.isPast)
        XCTAssertEqual(t.statusLabel, "EXPIRED")
    }

    func testStatusLabelVoidAndRefundedAreUppercasedAsIs() throws {
        let void = try makeTicket(status: "void", startAt: farFutureISO)
        XCTAssertEqual(void.statusLabel, "VOID")

        let refunded = try makeTicket(status: "refunded", startAt: farPastISO)
        XCTAssertEqual(refunded.statusLabel, "REFUNDED")
    }

    // MARK: - transferable / transferred (prenos vstopnice, 008)

    func testTransferFieldsDecodeFromBackend() throws {
        let t = try makeTicket(
            startAt: farFutureISO,
            transferable: true,
            transferred: false,
            holderUsername: "martin",
            buyerUsername: "martin"
        )
        XCTAssertTrue(t.transferable)
        XCTAssertFalse(t.transferred)
        XCTAssertEqual(t.holderUsername, "martin")
        XCTAssertEqual(t.buyerUsername, "martin")
    }

    func testTransferredTicketHasDifferentHolderThanBuyer() throws {
        let t = try makeTicket(
            startAt: farFutureISO,
            transferable: false,
            transferred: true,
            holderUsername: "prijatelj",
            buyerUsername: "martin"
        )
        XCTAssertFalse(t.transferable)
        XCTAssertTrue(t.transferred)
        XCTAssertNotEqual(t.holderUsername, t.buyerUsername)
    }

    /// Star backend brez migracije 008: transferable/transferred/holder/buyer manjkajo -> privzeto.
    func testDecodesWithDefaultsWhenTransferFieldsMissing() throws {
        let json = """
        {
            "id": 2,
            "serial": "X",
            "status": "valid",
            "created_at": "2026-01-01T00:00:00.000Z",
            "qr": "q"
        }
        """
        let t = try JSONDecoder().decode(APITicket.self, from: Data(json.utf8))
        XCTAssertFalse(t.transferable)
        XCTAssertFalse(t.transferred)
        XCTAssertEqual(t.holderUsername, "")
        XCTAssertEqual(t.buyerUsername, "")
        XCTAssertEqual(t.orderId, 0)
        XCTAssertEqual(t.eventId, 0)
    }
}
