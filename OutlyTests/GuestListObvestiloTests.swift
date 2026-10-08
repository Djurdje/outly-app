import XCTest
import Foundation
@testable import Outly

/// Obvestilo v zvoncu ob vabilu na guest listo (8. 10. 2026): novo polje Me s privzeto vrednostjo (star backend),
/// oblika GET /me/guest-list-invites/received, obrambno dekodiranje in sestavljen podnaslov vrstice.
@MainActor
final class GuestListObvestiloTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Me.pendingGuestListInvites

    func testMeBrezPoljaImaNic() throws {
        let me = try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "u"}"#)
        XCTAssertEqual(me.pendingGuestListInvites, 0)
    }

    func testMeDekodiraStevecVabil() throws {
        let me = try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "u", "pending_guest_list_invites": 2}"#)
        XCTAssertEqual(me.pendingGuestListInvites, 2)
    }

    func testMeSNeveljavnimPoljemNePodreDekodiranja() throws {
        let me = try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "u", "pending_guest_list_invites": null}"#)
        XCTAssertEqual(me.pendingGuestListInvites, 0)
    }

    /// Shranjen Me (MeShramba) mora ohraniti stevec: encode -> decode.
    func testStevecPrezivi_encodeDecode() throws {
        let me = try decode(Me.self, #"{"id": 1, "email": "a@b.si", "username": "u", "pending_guest_list_invites": 4}"#)
        let nazaj = try JSONDecoder().decode(Me.self, from: JSONEncoder().encode(me))
        XCTAssertEqual(nazaj.pendingGuestListInvites, 4)
        XCTAssertEqual(nazaj, me)
    }

    // MARK: - GET /me/guest-list-invites/received

    private let odgovor = """
    {"invites": [
      {"id": 31, "guest_list_id": 12, "ticket_id": 995, "host_username": "martin", "host_avatar_url": "https://x/a.jpg",
       "created_at": "2030-01-01T10:00:00.000Z",
       "event": {"id": 5, "title": "Friday", "start_at": "2030-01-05T22:00:00.000Z", "poster_url": "https://x/p.jpg", "club_name": "Klub"}},
      {"id": 30, "guest_list_id": 11, "ticket_id": 990, "host_username": "ana", "host_avatar_url": null,
       "created_at": "2030-01-01T09:00:00.000Z", "event": {"id": 4, "title": "Sat", "start_at": "", "poster_url": "", "club_name": ""}}
    ]}
    """

    func testOdgovorSeDekodiraPoPogodbi() throws {
        let r = try decode(GuestListInvitesReceivedResponse.self, odgovor)
        XCTAssertEqual(r.invites.map(\.id), [31, 30])
        let v = r.invites[0]
        XCTAssertEqual(v.guestListId, 12)
        XCTAssertEqual(v.ticketId, 995)
        XCTAssertEqual(v.hostUsername, "martin")
        XCTAssertEqual(v.hostAvatarUrl, "https://x/a.jpg")
        XCTAssertEqual(v.event.id, 5)
        XCTAssertEqual(v.event.title, "Friday")
        XCTAssertEqual(v.event.clubName, "Klub")
        XCTAssertEqual(v.event.posterUrl, "https://x/p.jpg")
        XCTAssertNil(r.invites[1].hostAvatarUrl)
    }

    func testPrazenOdgovorInManjkajocePoljeDaPrazenSeznam() throws {
        XCTAssertEqual(try decode(GuestListInvitesReceivedResponse.self, #"{"invites": []}"#).invites.count, 0)
        XCTAssertEqual(try decode(GuestListInvitesReceivedResponse.self, "{}").invites.count, 0)
    }

    func testObvestiloSamoZIdjemPrevzamePrivzeteVrednosti() throws {
        let v = try decode(GuestListInviteNotification.self, #"{"id": 7}"#)
        XCTAssertEqual(v.id, 7)
        XCTAssertEqual(v.ticketId, 0)
        XCTAssertEqual(v.hostUsername, "")
        XCTAssertNil(v.hostAvatarUrl)
        XCTAssertEqual(v.event.title, "")
        XCTAssertEqual(v.podnaslov, "")
    }

    func testPodnaslovPrazniDeliOdpadejo() throws {
        let r = try decode(GuestListInvitesReceivedResponse.self, odgovor)
        // Prvo obvestilo ima datum: "Friday · Klub · <datum>"; drugo nima ne kluba ne datuma.
        XCTAssertTrue(r.invites[0].podnaslov.hasPrefix("Friday · Klub · "))
        XCTAssertFalse(r.invites[0].displayDayTime.isEmpty)
        XCTAssertEqual(r.invites[1].podnaslov, "Sat")
    }

    // MARK: - 404 starega backenda

    func testStarBackend404JeBrezVrstic() {
        XCTAssertTrue(APIClient.jeStarBackendBrezGuestList(.requestFailed(404, "")))
        XCTAssertFalse(APIClient.jeStarBackendBrezGuestList(.requestFailed(500, "")))
        XCTAssertFalse(APIClient.jeStarBackendBrezGuestList(.requestFailed(503, "")))
    }
}
