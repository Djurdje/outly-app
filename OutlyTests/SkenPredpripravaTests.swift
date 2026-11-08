import XCTest
import Foundation
@testable import Outly

// Priprava skenerja v ozadju (outly-backend#406): izbira klubov, omejitev 1x na 10 min, preklic ob odjavi.
// Testni target nima privzete MainActor izolacije, zato je razred @MainActor (SkenPredpriprava je @MainActor).

@MainActor
final class SkenPredpripravaTests: XCTestCase {

    private func me(clubs: [(Int, String)], clubId: Int? = nil, clubRole: String? = nil, id: Int = 7) throws -> Me {
        let seznam = clubs.map { #"{"club_id":\#($0.0),"club_name":"K\#($0.0)","club_logo_url":"","role":"\#($0.1)"}"# }.joined(separator: ",")
        let k = clubId.map { #","club_id":\#($0)"# } ?? ""
        let r = clubRole.map { #","club_role":"\#($0)""# } ?? ""
        let json = #"{"id":\#(id),"email":"a@b.si","username":"ana","role":"user"\#(k)\#(r),"clubs":[\#(seznam)]}"#
        return try JSONDecoder().decode(Me.self, from: Data(json.utf8))
    }

    /// Priprava, ki si zapomni, katere klube je dobila (brez omrezja in diska).
    private final class Dnevnik {
        var klubi: [Int] = []
        var uporabniki: [Int?] = []
    }

    private func naredi(_ d: Dnevnik, ura: TestnaUraPriprave, med: (@MainActor (Int) -> Void)? = nil) -> SkenPredpriprava {
        let p = SkenPredpriprava(pripravi: { klub, uporabnik, _ in
            d.klubi.append(klub)
            d.uporabniki.append(uporabnik)
            med?(klub)
        })
        p.ura = { ura.zdaj }
        return p
    }

    // MARK: Izbira klubov

    func testKlubiZaSkenSamoVlogeKiSmejoSkenirati() throws {
        let m = try me(clubs: [(1, "owner"), (2, "manager"), (3, "doorman"), (4, "bartender")])
        XCTAssertEqual(SkenPredpriprava.klubiZaSken(m), [1, 2, 3])
    }

    func testKlubiZaSkenBrezKlubovJePrazno() throws {
        XCTAssertEqual(SkenPredpriprava.klubiZaSken(try me(clubs: [])), [])
        XCTAssertEqual(SkenPredpriprava.klubiZaSken(try me(clubs: [(4, "bartender")], clubId: 4, clubRole: "bartender")), [])
    }

    func testKlubiZaSkenStarBackendBrezSeznamaKlubov() throws {
        XCTAssertEqual(SkenPredpriprava.klubiZaSken(try me(clubs: [], clubId: 9, clubRole: "doorman")), [9])
        XCTAssertEqual(SkenPredpriprava.klubiZaSken(try me(clubs: [], clubRole: "owner")), [0])
    }

    func testKlubiZaSkenBrezPodvojitev() throws {
        let m = try me(clubs: [(1, "owner"), (1, "doorman"), (2, "doorman")])
        XCTAssertEqual(SkenPredpriprava.klubiZaSken(m), [1, 2])
    }

    func testZaPripravoOmejitev10Minut() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let zadnje: [Int: Date] = [1: t.addingTimeInterval(-9 * 60), 2: t.addingTimeInterval(-10 * 60), 3: t.addingTimeInterval(-3600)]
        XCTAssertEqual(SkenPredpriprava.zaPripravo(klubi: [1, 2, 3, 4], zadnje: zadnje, zdaj: t), [2, 3, 4])
    }

    // MARK: Sprozilec

    func testSprozilNicZaObicajnegaUporabnikaInBrezZetona() async throws {
        let d = Dnevnik()
        let p = naredi(d, ura: TestnaUraPriprave())
        XCTAssertNil(p.sprozi(me: nil, zeton: { "z" }))
        XCTAssertNil(p.sprozi(me: try me(clubs: []), zeton: { "z" }))
        XCTAssertNil(p.sprozi(me: try me(clubs: [(1, "owner")]), zeton: { "" }))   // odjavljen
        XCTAssertEqual(d.klubi, [])
    }

    func testPripraviVsakKlubPoVrstiZUporabnikomId() async throws {
        let d = Dnevnik()
        let p = naredi(d, ura: TestnaUraPriprave())
        await p.sprozi(me: try me(clubs: [(1, "owner"), (2, "doorman"), (3, "bartender")], id: 42), zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [1, 2])
        XCTAssertEqual(d.uporabniki, [42, 42])
    }

    func testDrugiSprozilTakojNicTretjiPo10MinPonovi() async throws {
        let d = Dnevnik()
        let ura = TestnaUraPriprave()
        let p = naredi(d, ura: ura)
        let m = try me(clubs: [(1, "owner")])
        await p.sprozi(me: m, zeton: { "z" })?.value
        XCTAssertNil(p.sprozi(me: m, zeton: { "z" }))          // refreshMe + scenePhase takoj zatem
        ura.zdaj = ura.zdaj.addingTimeInterval(9 * 60)
        XCTAssertNil(p.sprozi(me: m, zeton: { "z" }))
        ura.zdaj = ura.zdaj.addingTimeInterval(61)
        await p.sprozi(me: m, zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [1, 1])
    }

    func testNovKlubSePripraviTakojStariPocaka() async throws {
        let d = Dnevnik()
        let ura = TestnaUraPriprave()
        let p = naredi(d, ura: ura)
        await p.sprozi(me: try me(clubs: [(1, "owner")]), zeton: { "z" })?.value
        ura.zdaj = ura.zdaj.addingTimeInterval(60)
        await p.sprozi(me: try me(clubs: [(1, "owner"), (2, "doorman")]), zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [1, 2])
    }

    func testSprozilMedTekocoPripravoNicNeZaganja() async throws {
        let d = Dnevnik()
        let p = naredi(d, ura: TestnaUraPriprave())
        let m = try me(clubs: [(1, "owner")])
        let prva = p.sprozi(me: m, zeton: { "z" })
        XCTAssertNotNil(prva)
        XCTAssertNil(p.sprozi(me: try me(clubs: [(1, "owner"), (2, "owner")]), zeton: { "z" }))   // prva se ni koncala
        await prva?.value
        XCTAssertEqual(d.klubi, [1])
    }

    // MARK: Odjava

    func testPreklicMedPripravoNeZacneNaslednjegaKluba() async throws {
        let d = Dnevnik()
        var p: SkenPredpriprava!
        p = naredi(d, ura: TestnaUraPriprave(), med: { klub in if klub == 1 { p.preklici() } })
        await p.sprozi(me: try me(clubs: [(1, "owner"), (2, "owner")]), zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [1])    // klub 2 po odjavi ni na vrsti
    }

    func testPoPreklicuPrijavaSpetPripraviBrezCakanja10Min() async throws {
        let d = Dnevnik()
        let p = naredi(d, ura: TestnaUraPriprave())
        let m = try me(clubs: [(1, "owner")])
        await p.sprozi(me: m, zeton: { "z" })?.value
        p.preklici()
        await p.sprozi(me: m, zeton: { "z2" })?.value
        XCTAssertEqual(d.klubi, [1, 1])
    }
}

final class TestnaUraPriprave {
    var zdaj = Date(timeIntervalSince1970: 1_800_000_000)
}
