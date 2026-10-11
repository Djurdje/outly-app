import XCTest
import Foundation
@testable import Outly

/// Podatki prodajalca (outly-backend#94 / #101): dekodiranje `seller` (star backend ga nima), surova polja kluba,
/// izbira DDV besedila po `vat_payer`, vrstice bloka in sporocilo ob 403 `owner_only`.
final class ProdajalecTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let polnProdajalec = #"""
    {"name": "Klub d.o.o.", "address": "Ulica 1, 1000 Ljubljana", "registration_number": "1234567",
     "tax_number": "SI12345678", "vat_payer": true, "phone": "+386 1 234 567", "email": "", "complete": true}
    """#

    func testProdajalecDekodiraVsaPolja() throws {
        let s = try decode(Seller.self, polnProdajalec)
        XCTAssertEqual(s.name, "Klub d.o.o.")
        XCTAssertEqual(s.address, "Ulica 1, 1000 Ljubljana")
        XCTAssertEqual(s.registrationNumber, "1234567")
        XCTAssertEqual(s.taxNumber, "SI12345678")
        XCTAssertEqual(s.vatPayer, true)
        XCTAssertEqual(s.phone, "+386 1 234 567")
        XCTAssertTrue(s.complete)
    }

    func testProdajalecBrezPoljInNapacenTipNePodreDekodiranja() throws {
        let prazen = try decode(Seller.self, "{}")
        XCTAssertEqual(prazen.name, "")
        XCTAssertNil(prazen.vatPayer)
        XCTAssertFalse(prazen.complete)
        let napacen = try decode(Seller.self, #"{"name": 5, "vat_payer": "da", "complete": "yes"}"#)
        XCTAssertEqual(napacen.name, "")
        XCTAssertNil(napacen.vatPayer)
        XCTAssertFalse(napacen.complete)
        XCTAssertNil(try decode(Seller.self, #"{"vat_payer": null}"#).vatPayer)
    }

    func testDogodekVipInKlubDekodirajoSeller() throws {
        let e = try decode(APIEvent.self, #"{"id": 1, "seller": \#(polnProdajalec)}"#)
        XCTAssertEqual(e.seller?.name, "Klub d.o.o.")
        XCTAssertNil(try decode(APIEvent.self, #"{"id": 1}"#).seller)              // star backend / seznam
        XCTAssertNil(try decode(APIEvent.self, #"{"id": 1, "seller": 3}"#).seller) // napacen tip ne podre seznama

        let v = try decode(EventVip.self, #"{"event_id": 1, "enabled": true, "seller": \#(polnProdajalec)}"#)
        XCTAssertEqual(v.seller?.taxNumber, "SI12345678")
        XCTAssertNil(try decode(EventVip.self, #"{"event_id": 1}"#).seller)

        let k = try decode(APIClub.self, #"{"id": 7, "seller": \#(polnProdajalec)}"#)
        XCTAssertEqual(k.seller?.vatPayer, true)
        XCTAssertNil(try decode(APIClub.self, #"{"id": 7}"#).seller)
    }

    func testPoslovniKlubDekodiraSurovaPoljaInStarBackendDaPrivzetke() throws {
        let k = try decode(APIClub.self, """
        {"id": 7, "legal_name": "Klub d.o.o.", "legal_address": "Ulica 1", "registration_number": "123",
         "tax_number": "SI1", "vat_payer": false, "seller_complete": true}
        """)
        XCTAssertEqual(k.legalName, "Klub d.o.o.")
        XCTAssertEqual(k.legalAddress, "Ulica 1")
        XCTAssertEqual(k.registrationNumber, "123")
        XCTAssertEqual(k.taxNumber, "SI1")
        XCTAssertEqual(k.vatPayer, false)
        XCTAssertTrue(k.sellerComplete)

        let star = try decode(APIClub.self, #"{"id": 7}"#)
        XCTAssertEqual(star.legalName, "")
        XCTAssertNil(star.vatPayer)
        XCTAssertFalse(star.sellerComplete)
    }

    func testDdvBesediloPoStatusuProdajalca() {
        let zavezanec = Seller.ddvBesedilo(Seller(vatPayer: true))
        let nezavezanec = Seller.ddvBesedilo(Seller(vatPayer: false))
        let nevpisano = Seller.ddvBesedilo(Seller(vatPayer: nil))
        XCTAssertNotEqual(zavezanec, nezavezanec)
        XCTAssertNotEqual(zavezanec, nevpisano)
        XCTAssertNotEqual(nezavezanec, nevpisano)
        // Brez prodajalca (star backend) ne trdimo, da cene vkljucujejo DDV.
        XCTAssertEqual(Seller.ddvBesedilo(nil), nevpisano)
    }

    func testVrsticeBloka() {
        let s = Seller(name: " Klub ", address: "Ulica 1", registrationNumber: "1234567", taxNumber: "", phone: "+386 1", email: "info@klub.si")
        XCTAssertEqual(s.imeProdajalca, "Klub")
        XCTAssertTrue(s.registracijaVrstica.contains("1234567"))
        XCTAssertFalse(s.registracijaVrstica.contains("·"))   // davcne ni -> ena sama postavka
        XCTAssertEqual(s.stikVrstica, "+386 1 · info@klub.si")
        XCTAssertEqual(Seller().registracijaVrstica, "")
        XCTAssertEqual(Seller().stikVrstica, "")
    }

    func testOwnerOnlyDobiSvojeSporocilo() {
        let napaka = APIError.requestFailed(403, #"{"error":"owner_only"}"#)
        XCTAssertEqual(napaka.userMessage, String(localized: "Only the club owner can change seller details."))
    }

    func testSamoLastnikUrejaPodatkeProdajalca() throws {
        func makeMe(role: String, clubRole: String?) throws -> Me {
            let cr = clubRole.map { "\"\($0)\"" } ?? "null"
            let json = #"{"id": 1, "email": "t@outly.si", "username": "tester", "role": "\#(role)", "club_id": 5, "club_role": \#(cr)}"#
            return try JSONDecoder().decode(Me.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try makeMe(role: "user", clubRole: "owner").isClubOwner)
        XCTAssertFalse(try makeMe(role: "user", clubRole: "manager").isClubOwner)
        XCTAssertFalse(try makeMe(role: "user", clubRole: "doorman").isClubOwner)
        XCTAssertFalse(try makeMe(role: "user", clubRole: nil).isClubOwner)
    }
}
