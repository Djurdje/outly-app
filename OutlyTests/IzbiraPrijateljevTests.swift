import XCTest
import Foundation
@testable import Outly

/// Skupna izbira vec prijateljev (VIP razdelitev po nakupu in guest lista, 8. 10. 2026): meja izbranih, izkljuceni, kljukica starosti.
@MainActor
final class IzbiraPrijateljevTests: XCTestCase {

    private func prijatelji(_ idji: [Int]) -> [FriendUser] {
        idji.map { FriendUser(id: $0, username: "u\($0)", avatarUrl: nil) }
    }

    func testPreklopiDodaInOdstrani() {
        var izbrani: [Int] = []
        izbrani = IzbiraPrijateljev.preklopi(izbrani, id: 5, meja: 3)
        izbrani = IzbiraPrijateljev.preklopi(izbrani, id: 7, meja: 3)
        XCTAssertEqual(izbrani, [5, 7], "vrstni red izbire se ohrani")
        izbrani = IzbiraPrijateljev.preklopi(izbrani, id: 5, meja: 3)
        XCTAssertEqual(izbrani, [7])
    }

    func testPreklopiNePresezeMeje() {
        let polna = [1, 2]
        XCTAssertEqual(IzbiraPrijateljev.preklopi(polna, id: 3, meja: 2), [1, 2])
        // ob polni meji se izbrani se vedno da odstraniti
        XCTAssertEqual(IzbiraPrijateljev.preklopi(polna, id: 1, meja: 2), [2])
    }

    func testMejaNicPomeniNobenegaIzbranega() {
        XCTAssertEqual(IzbiraPrijateljev.preklopi([], id: 1, meja: 0), [])
        XCTAssertEqual(IzbiraPrijateljev.preklopi([], id: 1, meja: -3), [])
    }

    func testRazpolozljiviIzkljuciOznacene() {
        let r = IzbiraPrijateljev.razpolozljivi(prijatelji([1, 2, 3, 4]), izkljuceni: [2, 4])
        XCTAssertEqual(r.map(\.id), [1, 3])
    }

    func testOcistiObdrziSamoObstojeceBrezPodvojenihInPoMeji() {
        let r = IzbiraPrijateljev.ocisti([3, 9, 3, 1, 2], razpolozljivi: prijatelji([1, 2, 3]), meja: 2)
        XCTAssertEqual(r, [3, 1])
        XCTAssertEqual(IzbiraPrijateljev.ocisti([1], razpolozljivi: [], meja: 5), [])
    }

    func testKljukicaStarostiSamoZMejoInIzbiro() {
        XCTAssertFalse(IzbiraPrijateljev.kazeStarost(izbranih: 2, starostnaMeja: 0))
        XCTAssertFalse(IzbiraPrijateljev.kazeStarost(izbranih: 0, starostnaMeja: 18))
        XCTAssertTrue(IzbiraPrijateljev.kazeStarost(izbranih: 1, starostnaMeja: 18))
    }

    func testPosiljanjeZahtevaIzbiroInPotrditevStarosti() {
        XCTAssertFalse(IzbiraPrijateljev.lahkoPosljes(izbranih: 0, starostnaMeja: 0, starostPotrjena: false))
        XCTAssertTrue(IzbiraPrijateljev.lahkoPosljes(izbranih: 1, starostnaMeja: 0, starostPotrjena: false))
        XCTAssertFalse(IzbiraPrijateljev.lahkoPosljes(izbranih: 1, starostnaMeja: 18, starostPotrjena: false))
        XCTAssertTrue(IzbiraPrijateljev.lahkoPosljes(izbranih: 1, starostnaMeja: 18, starostPotrjena: true))
        XCTAssertFalse(IzbiraPrijateljev.lahkoPosljes(izbranih: 0, starostnaMeja: 18, starostPotrjena: true))
    }
}
