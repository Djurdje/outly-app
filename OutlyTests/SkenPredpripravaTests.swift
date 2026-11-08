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
        var pociscenih: [Int] = []
        var ociscenj = 0
        /// Odgovor priprave po klubu (privzeto true = okno porabljeno).
        var izid: [Int: Bool] = [:]
    }

    /// Sibka referenca na pripravo za closure, ki jo mora poklicati med njenim lastnim tekom (Swift 6: brez `var` zajetja).
    private final class Drzalo {
        weak var priprava: SkenPredpriprava?
        let skener = NSObject()
    }

    private func naredi(_ d: Dnevnik, ura: TestnaUraPriprave, med: (@MainActor (Int) -> Void)? = nil) -> SkenPredpriprava {
        let p = SkenPredpriprava(pripravi: { klub, uporabnik, _ in
            d.klubi.append(klub)
            d.uporabniki.append(uporabnik)
            med?(klub)
            return d.izid[klub] ?? true
        }, pocisti: { klub in d.pociscenih.append(klub) }, ociStare: { d.ociscenj += 1 })
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
        let drzalo = Drzalo()
        let p = naredi(d, ura: TestnaUraPriprave(), med: { klub in if klub == 1 { drzalo.priprava?.preklici() } })
        drzalo.priprava = p
        await p.sprozi(me: try me(clubs: [(1, "owner"), (2, "owner")]), zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [1])    // klub 2 po odjavi ni na vrsti
        XCTAssertEqual(d.pociscenih, [1])   // klub, ki ga je priprava ze zacela, se pobrise (ne glede na zeton)
    }

    // MARK: Skener odprt

    func testZaKlubZOdprtimSkenerjemPripravaMiruje() async throws {
        let d = Dnevnik()
        let p = naredi(d, ura: TestnaUraPriprave())
        let m = try me(clubs: [(1, "owner"), (2, "doorman")])
        let skener = NSObject()
        p.skenerOdprt(1, seja: skener)
        await p.sprozi(me: m, zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [2])
        p.skenerZaprt(seja: skener)
        await p.sprozi(me: m, zeton: { "z" })?.value   // klub 1 okna ni porabil
        XCTAssertEqual(d.klubi, [2, 1])
    }

    func testSkenerOdprtMedPripravoPreskociNaslednjiKlub() async throws {
        let d = Dnevnik()
        let drzalo = Drzalo()
        let p = naredi(d, ura: TestnaUraPriprave(), med: { klub in if klub == 1 { drzalo.priprava?.skenerOdprt(2, seja: drzalo.skener) } })
        drzalo.priprava = p
        await p.sprozi(me: try me(clubs: [(1, "owner"), (2, "owner")]), zeton: { "z" })?.value
        XCTAssertEqual(d.klubi, [1])
    }

    func testRegistracijaOdprtegaSkenerjaJePoSeji() {
        let p = naredi(Dnevnik(), ura: TestnaUraPriprave())
        let a = NSObject(), b = NSObject()
        p.skenerZaprt(seja: a)                      // brez odprtja: nic
        p.skenerOdprt(1, seja: a); p.skenerOdprt(1, seja: a)   // dvakrat isti = ena registracija
        p.skenerOdprt(1, seja: b)
        p.skenerZaprt(seja: a)
        XCTAssertTrue(p.jeSkenerOdprt(1))           // b je se odprt
        p.skenerZaprt(seja: b)
        XCTAssertFalse(p.jeSkenerOdprt(1))
    }

    // MARK: Prekinjen ali brezomrezen poskus ne porabi okna

    func testBrezOmrezjaNePorabiOkna() async throws {
        let d = Dnevnik()
        d.izid[1] = false
        let p = naredi(d, ura: TestnaUraPriprave())
        let m = try me(clubs: [(1, "owner")])
        await p.sprozi(me: m, zeton: { "z" })?.value
        d.izid[1] = true
        await p.sprozi(me: m, zeton: { "z" })?.value   // takoj spet: prvi poskus okna ni porabil
        XCTAssertEqual(d.klubi, [1, 1])
        XCTAssertNil(p.sprozi(me: m, zeton: { "z" }))   // uspeh okno porabi
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
