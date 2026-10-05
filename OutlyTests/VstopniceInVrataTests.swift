import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Outly

// Varnostni pregled 5. 10. 2026: vstopnice brez signala (VstopniceShramba), zadrzek iste kode po »Next« (SkenZadrzek),
// odpovedan dogodek na vratih (event_cancelled).

private func vstopnica(id: Int, status: String = "valid", qr: String = "o2.telo.podpis") -> APITicket {
    let json = """
    {"id":\(id),"order_id":7,"event_id":42,"serial":"11111111-2222-3333-4444-55555555555\(id % 10)","status":"\(status)",
     "qr":"\(qr)","created_at":"2026-10-01T20:00:00Z","public_ref":"OUT-\(id)","event_title":"Petek","start_at":"2026-10-10T22:00:00Z",
     "club_id":3,"club_name":"Klub","is_vip":true,"table_label":"T1","table_seats":4,"package_name":"Gold"}
    """
    return try! JSONDecoder().decode(APITicket.self, from: Data(json.utf8))
}

private func zacasnaMapa() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("outly-vstopnice-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

final class VstopniceShrambaTests: XCTestCase {
    private var mapa: URL!

    override func setUp() {
        super.setUp()
        mapa = zacasnaMapa()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: mapa)
        super.tearDown()
    }

    func testShraniInPreberiVrneIsteVstopniceSQrKodo() throws {
        let shramba = VstopniceShramba(mapa: mapa)
        let cas = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(shramba.shrani([vstopnica(id: 1, qr: "o2.a.b"), vstopnica(id: 2)], uporabnikId: 5, zdaj: cas))
        let p = try XCTUnwrap(shramba.preberi(uporabnikId: 5))
        XCTAssertEqual(p.vstopnice.map(\.id), [1, 2])
        XCTAssertEqual(p.vstopnice.first?.qr, "o2.a.b")
        XCTAssertEqual(p.vstopnice.first?.eventTitle, "Petek")
        XCTAssertEqual(p.vstopnice.first?.tableLabel, "T1")
        XCTAssertTrue(p.vstopnice.first?.isVip ?? false)
        XCTAssertEqual(p.shranjeno, cas)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shramba.datoteka.path))
        // Application Support (ali podana mapa), ne UserDefaults
        XCTAssertTrue(shramba.datoteka.path.hasPrefix(mapa.path))
    }

    func testPrivzetaMapaJeVApplicationSupport() {
        let pot = VstopniceShramba().datoteka.path
        XCTAssertTrue(pot.contains("Application Support") || pot.contains(".local/share"), pot)
    }

    func testPorabljenaVrnjenaInBrezKodeNeGrejoNaDisk() throws {
        let shramba = VstopniceShramba(mapa: mapa)
        shramba.shrani([vstopnica(id: 1), vstopnica(id: 2, status: "used"), vstopnica(id: 3, status: "refunded"),
                        vstopnica(id: 4, status: "void"), vstopnica(id: 5, qr: "")], uporabnikId: 5)
        XCTAssertEqual(shramba.preberi(uporabnikId: 5)?.vstopnice.map(\.id), [1])
    }

    func testOsvezitevUmaknePrenesenoInPorabljeno() throws {
        let shramba = VstopniceShramba(mapa: mapa)
        shramba.shrani([vstopnica(id: 1), vstopnica(id: 2), vstopnica(id: 3)], uporabnikId: 5)
        // Po osvezitvi: 2 je bila prenesena (ni je vec v /me/tickets), 3 je bila skenirana.
        shramba.shrani([vstopnica(id: 1), vstopnica(id: 3, status: "used")], uporabnikId: 5)
        XCTAssertEqual(shramba.preberi(uporabnikId: 5)?.vstopnice.map(\.id), [1])
    }

    func testOdstraniPoPrenosu() {
        let shramba = VstopniceShramba(mapa: mapa)
        shramba.shrani([vstopnica(id: 1), vstopnica(id: 2)], uporabnikId: 5)
        shramba.odstrani(vstopnicaId: 2)
        XCTAssertEqual(shramba.preberi(uporabnikId: 5)?.vstopnice.map(\.id), [1])
    }

    func testTujiUporabnikNeVidiPosnetka() {
        let shramba = VstopniceShramba(mapa: mapa)
        shramba.shrani([vstopnica(id: 1)], uporabnikId: 5)
        XCTAssertNil(shramba.preberi(uporabnikId: 6))
        XCTAssertNotNil(shramba.preberi(uporabnikId: nil))
    }

    func testPokvarjenaDatotekaNeSesujeInVrneNil() throws {
        let shramba = VstopniceShramba(mapa: mapa)
        try Data("{ pokvarjeno".utf8).write(to: shramba.datoteka)
        XCTAssertNil(shramba.preberi(uporabnikId: 5))
    }

    @MainActor
    func testOdjavaPobriseShranjeneVstopnice() {
        let shramba = VstopniceShramba(mapa: mapa)
        shramba.shrani([vstopnica(id: 1)], uporabnikId: 5)
        XCTAssertNotNil(shramba.preberi(uporabnikId: 5))
        let disk = SkenDisk(mapa: mapa.appendingPathComponent("Sken", isDirectory: true))
        SkenOdjava.pocisti(disk: disk, predpomnilniki: [], vstopnice: shramba)
        XCTAssertNil(shramba.preberi(uporabnikId: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shramba.datoteka.path))
    }

    func testShranjenSeznamSamoObZacasniNapaki() {
        XCTAssertTrue(VstopniceShramba.pokaziShranjeno(ob: URLError(.notConnectedToInternet)))
        XCTAssertTrue(VstopniceShramba.pokaziShranjeno(ob: URLError(.timedOut)))
        XCTAssertTrue(VstopniceShramba.pokaziShranjeno(ob: APIError.requestFailed(503, "")))
        XCTAssertFalse(VstopniceShramba.pokaziShranjeno(ob: APIError.requestFailed(401, "")))
        XCTAssertFalse(VstopniceShramba.pokaziShranjeno(ob: URLError(.cancelled)))
        XCTAssertFalse(VstopniceShramba.pokaziShranjeno(ob: CancellationError()))
    }
}

final class SkenZadrzekTests: XCTestCase {
    func testIstaKodaPoNextJeZadrzana3s() {
        var z = SkenZadrzek()
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertFalse(z.ignoriraj("koda", zdaj: t0))
        z.zadrzi("koda", zdaj: t0)
        XCTAssertTrue(z.ignoriraj("koda", zdaj: t0.addingTimeInterval(2.9)))
        XCTAssertFalse(z.ignoriraj("druga", zdaj: t0.addingTimeInterval(1)))     // drug gost gre takoj
        XCTAssertFalse(z.ignoriraj("koda", zdaj: t0.addingTimeInterval(3.0)))    // po 3 s spet bere
        z.zadrzi("koda", zdaj: t0)
        z.pocisti()
        XCTAssertFalse(z.ignoriraj("koda", zdaj: t0.addingTimeInterval(1)))
        z.zadrzi("", zdaj: t0)
        XCTAssertFalse(z.ignoriraj("", zdaj: t0))
    }
}

final class SkenOdpovedanDogodekTests: XCTestCase {
    func testSpletniSkenEventCancelled() throws {
        let r = try JSONDecoder().decode(ScanResult.self, from: Data(#"{"result":"event_cancelled","message":"This event was cancelled."}"#.utf8))
        let p = SkenPrikaz.iz(r)
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, String(localized: "EVENT CANCELLED"))
        XCTAssertEqual(p.podnaslov, String(localized: "This event was cancelled."))
        XCTAssertFalse(p.uspesen)
    }

    func testStreznikPoZelenemSkenuEventCancelled() {
        let p = SkenPrikaz.iz(streznik: "event_cancelled", usedAt: nil, sodba: SkenSodba(razlog: .veljavna, serial: "s"))
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, String(localized: "EVENT CANCELLED"))
        XCTAssertEqual(p.podnaslov, String(localized: "This event was cancelled."))
    }

    func testRazlogKonfliktaEventCancelled() {
        XCTAssertEqual(SkenPrikaz.razlogKonflikta("event_cancelled"), String(localized: "This event was cancelled."))
        XCTAssertNotEqual(SkenPrikaz.razlogKonflikta("event_cancelled"), SkenPrikaz.razlogKonflikta("nekaj_novega"))
    }
}
