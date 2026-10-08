import XCTest
import Foundation
@testable import Outly

/// Guest lista (8. 10. 2026): modeli s privzetimi vrednostmi (star backend), nova polja vstopnic, oznaka v skenerju, telo zahtevka, napake.
@MainActor
final class GuestListTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let polnaLista = """
    {"id": 12,
     "event": {"id": 5, "title": "Friday", "start_at": "2030-01-01T22:00:00.000Z", "end_at": null, "poster_url": "https://x/p.jpg",
               "club_id": 3, "club_name": "Klub", "min_age": 18, "status": "published"},
     "spots": 5, "remaining": 3, "can_invite": true, "my_ticket_id": 991, "note": "Do 24h",
     "invited": [{"user_id": 7, "username": "ana", "avatar_url": null, "status": "valid"},
                 {"user_id": 9, "username": "bob", "avatar_url": "https://x/a.jpg", "status": "used"}]}
    """

    // MARK: - Modeli

    func testListaSeDekodiraPoPogodbi() throws {
        let g = try decode(GuestList.self, polnaLista)
        XCTAssertEqual(g.id, 12)
        XCTAssertEqual(g.event.title, "Friday")
        XCTAssertEqual(g.event.minAge, 18)
        XCTAssertEqual(g.event.clubName, "Klub")
        XCTAssertEqual(g.spots, 5)
        XCTAssertEqual(g.remaining, 3)
        XCTAssertTrue(g.canInvite)
        XCTAssertEqual(g.myTicketId, 991)
        XCTAssertEqual(g.note, "Do 24h")
        XCTAssertEqual(g.invited.map(\.userId), [7, 9])
        XCTAssertFalse(g.invited[0].jeVstopil)
        XCTAssertTrue(g.invited[1].jeVstopil)
        XCTAssertEqual(g.povabljeniIdji, [7, 9])
        XCTAssertTrue(g.lahkoVabi)
    }

    func testMinimalnaListaDobiPrivzeteVrednosti() throws {
        let g = try decode(GuestList.self, #"{"id": 1}"#)
        XCTAssertEqual(g.spots, 0)
        XCTAssertEqual(g.remaining, 0)
        XCTAssertFalse(g.canInvite, "manjkajoce polje = ne vabi")
        XCTAssertNil(g.myTicketId)
        XCTAssertEqual(g.note, "")
        XCTAssertTrue(g.invited.isEmpty)
        XCTAssertEqual(g.event.minAge, 0)
        XCTAssertFalse(g.lahkoVabi)
    }

    func testPolnaAliZaprtaListaNeVabi() throws {
        let polna = try decode(GuestList.self, #"{"id": 1, "spots": 2, "remaining": 0, "can_invite": true}"#)
        XCTAssertFalse(polna.lahkoVabi)
        XCTAssertNotNil(GuestListPrikaz.zakajNeVabi(polna))
        let zaprta = try decode(GuestList.self, #"{"id": 1, "spots": 2, "remaining": 2, "can_invite": false}"#)
        XCTAssertFalse(zaprta.lahkoVabi)
        XCTAssertNotNil(GuestListPrikaz.zakajNeVabi(zaprta))
        let odprta = try decode(GuestList.self, polnaLista)
        XCTAssertNil(GuestListPrikaz.zakajNeVabi(odprta))
    }

    func testOdgovorPovabilaVsebujeListoInDodane() throws {
        let r = try decode(GuestListInviteResult.self, #"{"guest_list": \#(polnaLista), "added": [7, 9]}"#)
        XCTAssertEqual(r.added, [7, 9])
        XCTAssertEqual(r.guestList.id, 12)
    }

    func testNepopolnPovabljenKrozPrivzete() throws {
        let i = try decode(GuestListInvited.self, #"{"user_id": 4}"#)
        XCTAssertEqual(i.username, "")
        XCTAssertNil(i.avatarUrl)
        XCTAssertEqual(i.status, "valid")
    }

    func testStarBackend404JeNiList() {
        XCTAssertTrue(APIClient.jeStarBackendBrezGuestList(APIError.requestFailed(404, "Cannot GET /me/guest-lists")))
        XCTAssertFalse(APIClient.jeStarBackendBrezGuestList(APIError.requestFailed(500, "")))
        XCTAssertFalse(APIClient.jeStarBackendBrezGuestList(APIError.requestFailed(401, "")))
    }

    func testTeloVabilaBrezStarostiNimaAgeConfirmed() {
        let brez = APIClient.teloVabila(userIds: [7, 9], ageConfirmed: false)
        XCTAssertEqual(Set(brez.keys), ["user_ids"])
        XCTAssertEqual(brez["user_ids"] as? [Int], [7, 9])
        let z = APIClient.teloVabila(userIds: [7], ageConfirmed: true)
        XCTAssertEqual(Set(z.keys), ["user_ids", "age_confirmed"])
        XCTAssertEqual(z["age_confirmed"] as? Bool, true)
    }

    func testGostiteljevaVstopnicaIzMojih() throws {
        let g = try decode(GuestList.self, polnaLista)
        let t1 = try decode(APITicket.self, #"{"id": 5}"#)
        let t2 = try decode(APITicket.self, #"{"id": 991, "is_guest_list": true}"#)
        XCTAssertEqual(GuestListPrikaz.gostiteljevaVstopnica(g, med: [t1, t2])?.id, 991)
        XCTAssertNil(GuestListPrikaz.gostiteljevaVstopnica(g, med: [t1]))
        let brez = try decode(GuestList.self, #"{"id": 1}"#)
        XCTAssertNil(GuestListPrikaz.gostiteljevaVstopnica(brez, med: [t1, t2]))
    }

    // MARK: - Vstopnice

    func testStaraVstopnicaNimaGuestListOznake() throws {
        let t = try decode(APITicket.self, #"{"id": 2, "serial": "X", "status": "valid", "qr": "q"}"#)
        XCTAssertFalse(t.isGuestList)
        XCTAssertNil(t.guestListHostUsername)
        XCTAssertNil(t.povabilGostitelj(jaz: "ana"))
    }

    func testVstopnicaGuestListeSeDekodira() throws {
        let t = try decode(APITicket.self, #"{"id": 2, "is_guest_list": true, "guest_list_host_username": "marko"}"#)
        XCTAssertTrue(t.isGuestList)
        XCTAssertEqual(t.guestListHostUsername, "marko")
    }

    func testInvitedByPrijateljuNeGostitelju() throws {
        let prijatelj = try decode(APITicket.self, #"{"id": 2, "is_guest_list": true, "guest_list_host_username": "marko"}"#)
        XCTAssertEqual(prijatelj.povabilGostitelj(jaz: "ana"), "marko")
        XCTAssertEqual(prijatelj.povabilGostitelj(jaz: nil), "marko")
        // gostitelj na svoji vstopnici: gostitelj je on sam (velikost crk ni pomembna)
        XCTAssertNil(prijatelj.povabilGostitelj(jaz: "Marko"))
        let brezGostitelja = try decode(APITicket.self, #"{"id": 3, "is_guest_list": true, "guest_list_host_username": null}"#)
        XCTAssertNil(brezGostitelja.povabilGostitelj(jaz: "ana"))
        let navadna = try decode(APITicket.self, #"{"id": 4, "guest_list_host_username": "marko"}"#)
        XCTAssertNil(navadna.povabilGostitelj(jaz: "ana"), "brez is_guest_list ni oznake")
    }

    func testOznakaGuestListeSePreziviShranjevanjeNaDisk() throws {
        let t = try decode(APITicket.self, #"{"id": 2, "status": "valid", "qr": "q", "is_guest_list": true, "guest_list_host_username": "marko"}"#)
        let nazaj = try JSONDecoder().decode(APITicket.self, from: JSONEncoder().encode(t))
        XCTAssertTrue(nazaj.isGuestList)
        XCTAssertEqual(nazaj.guestListHostUsername, "marko")
    }

    // MARK: - Skener

    func testSeznamBrezPoljaNimaGuestListe() throws {
        let t = try decode(ScanListTicket.self, #"{"serial": "s1", "status": "valid"}"#)
        XCTAssertFalse(t.isGuestList)
        XCTAssertNil(t.guestListHostUsername)
    }

    func testSeznamNosiGuestListoTudiPoShranjevanju() throws {
        let t = try decode(ScanListTicket.self, #"{"serial": "s1", "status": "valid", "is_guest_list": true, "guest_list_host_username": "marko"}"#)
        XCTAssertTrue(t.isGuestList)
        let nazaj = try JSONDecoder().decode(ScanListTicket.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(nazaj, t)
    }

    func testOznakaVSkenerju() {
        XCTAssertNil(SkenPrikaz.guestListOznaka(isGuestList: false, host: "marko"))
        let z = SkenPrikaz.guestListOznaka(isGuestList: true, host: "marko")
        XCTAssertTrue(z?.contains("@marko") == true)
        XCTAssertTrue(z?.contains(String(localized: "Guest list")) == true)
        let brez = SkenPrikaz.guestListOznaka(isGuestList: true, host: nil)
        XCTAssertEqual(brez, String(localized: "Guest list"))
        XCTAssertEqual(SkenPrikaz.guestListOznaka(isGuestList: true, host: ""), String(localized: "Guest list"))
    }

    func testOnlineSkenPokazeGuestListo() throws {
        let r = try decode(ScanResult.self, #"{"result":"ok","message":"Welcome","ticket":{"is_vip":false,"is_guest_list":true,"guest_list_host_username":"marko"}}"#)
        let p = SkenPrikaz.iz(r)
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertTrue(p.guestList?.contains("@marko") == true)
        XCTAssertNil(p.vip)
    }

    func testOnlineSkenBrezGuestListeNimaOznake() throws {
        let r = try decode(ScanResult.self, #"{"result":"already_used","message":"x","ticket":{"is_vip":true,"table_label":"T1"}}"#)
        XCTAssertNil(SkenPrikaz.iz(r).guestList)
        let star = try decode(ScanResult.self, #"{"result":"ok","message":"x"}"#)
        XCTAssertNil(SkenPrikaz.iz(star).guestList)
    }

    func testOznakaGuestListeJeTudiPriZavrnjeniVstopnici() throws {
        let r = try decode(ScanResult.self, #"{"result":"already_used","message":"x","ticket":{"is_guest_list":true,"guest_list_host_username":"marko"}}"#)
        let p = SkenPrikaz.iz(r)
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertNotNil(p.guestList)
    }

    func testSkenBrezPovezaveIzSeznama() {
        let vstopnica = ScanListTicket(serial: "s1", holderUsername: "ana", isGuestList: true, guestListHostUsername: "marko")
        let p = SkenPrikaz.iz(SkenSodba(razlog: .veljavna, serial: "s1", vstopnica: vstopnica), qr: "q")
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertTrue(p.guestList?.contains("@marko") == true)
        let navadna = SkenPrikaz.iz(SkenSodba(razlog: .veljavna, serial: "s2", vstopnica: ScanListTicket(serial: "s2")), qr: "q")
        XCTAssertNil(navadna.guestList)
    }

    // MARK: - Napake

    func testNapakeGuestListeImajoPrijaznaSporocila() {
        let ni = APIError.requestFailed(403, "You can only invite friends.")
        XCTAssertEqual(ni.userMessage, String(localized: "You can only invite friends on Outly."))
        let mesta = APIError.requestFailed(409, "Only 2 spots left.")
        XCTAssertEqual(mesta.userMessage, String(localized: "There are not enough free spots left on this guest list."))
        let ze = APIError.requestFailed(409, "ana is already on your guest list.")
        XCTAssertEqual(ze.userMessage, String(localized: "That friend is already on your guest list."))
        let zaprta = APIError.requestFailed(409, "This guest list is closed.")
        XCTAssertEqual(zaprta.userMessage, String(localized: "This guest list is closed."))
        let mlad = APIError.requestFailed(403, "ana is under 18.")
        XCTAssertEqual(mlad.userMessage, String(localized: "One of these friends is too young for this event."))
        let ze2 = APIError.requestFailed(409, "Already checked in.")
        XCTAssertEqual(ze2.userMessage, String(localized: "This friend has already checked in, so they can't be removed."))
        let prenos = APIError.requestFailed(409, "Guest list tickets can't be transferred.")
        XCTAssertEqual(prenos.userMessage, String(localized: "Guest list tickets can't be sent to someone else."))
    }

    func testStarostnaNapakaPriPovabiluImaZeSporocilo() {
        let n = APIError.requestFailed(400, #"{"error":"age_confirmation_required","min_age":18}"#)
        XCTAssertEqual(PrenosStarosti.izNapake(n), 18)
        XCTAssertEqual(n.userMessage, String(localized: "Confirm that your friend is old enough for this event."))
    }
}
