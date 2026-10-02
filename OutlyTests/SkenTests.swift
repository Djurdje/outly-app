import XCTest
import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Outly

// Sken vstopnic brez povezave (backend issue #86): preverjanje kode v2, vrsta, odlocitev, SkenSeja z lazno API-jem,
// hladen zagon brez povezave (K1), odjava (M13). Koda se podpise v testu s CryptoKit kot streznik (Ed25519 nad "o2.<base64url(JSON)>").

private enum Pomoc {
    static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func telo(serial: String, event: Int, kid: String = "kid1") -> String {
        b64url(Data("{\"v\":2,\"t\":\"\(serial)\",\"e\":\(event),\"i\":1790000000,\"k\":\"\(kid)\"}".utf8))
    }

    /// Koda v2, kot jo izda streznik.
    static func koda(_ kljuc: Curve25519.Signing.PrivateKey, serial: String, event: Int, kid: String = "kid1") -> String {
        let sporocilo = "o2.\(telo(serial: serial, event: event, kid: kid))"
        let podpis = try! kljuc.signature(for: Data(sporocilo.utf8))
        return "\(sporocilo).\(b64url(podpis))"
    }

    /// Koda v1 (stara): telo {v:1,t,e,i} + "." + 32 sestnajstiskih znakov (HMAC, ki ga telefon ne more preveriti).
    static func kodaV1(serial: String, event: Int) -> String {
        let telo = b64url(Data("{\"v\":1,\"t\":\"\(serial)\",\"e\":\(event),\"i\":1790000000}".utf8))
        return "\(telo).0123456789abcdef0123456789abcdef"
    }

    static func serial() -> String { UUID().uuidString.lowercased() }

    static func zacasnaMapa() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("outly-sken-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func javni(_ k: Curve25519.Signing.PrivateKey) -> Data { k.publicKey.rawRepresentation }

    static func scanKey(_ k: Curve25519.Signing.PrivateKey, kid: String = "kid1") -> ScanKey {
        ScanKey(kid: kid, publicKey: b64url(javni(k)))
    }

    static func seznamPodatki(_ l: ScanList) -> Data { try! JSONEncoder().encode(l) }
}

// MARK: - Razclenjevanje in podpis

final class SkenKodaTests: XCTestCase {
    private let kljuc = Curve25519.Signing.PrivateKey()

    private func jeV1(_ qr: String) -> Bool { if case .v1 = SkenKoda.razcleni(qr) { return true } else { return false } }
    private func jeNeznano(_ qr: String) -> Bool { SkenKoda.razcleni(qr) == .neznano }

    func testVeljavnaKodaSeRazclenjiInPreveri() throws {
        let s = Pomoc.serial()
        let qr = Pomoc.koda(kljuc, serial: s.uppercased(), event: 42)   // serial v kodi z velikimi crkami -> normaliziran
        guard case let .v2(telo, sporocilo, podpis) = SkenKoda.razcleni(qr) else { return XCTFail("pricakovana koda v2") }
        XCTAssertEqual(telo.serial, s)
        XCTAssertEqual(telo.eventId, 42)
        XCTAssertEqual(telo.kid, "kid1")
        XCTAssertTrue(SkenPodpis.preveri(sporocilo: sporocilo, podpis: podpis, javniKljuc: Pomoc.javni(kljuc)))
    }

    func testSpremenjenPodpisJeZavrnjen() throws {
        let qr = Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 1)
        var deli = qr.split(separator: ".").map(String.init)
        var podpis = Data(base64URL: deli[2])!
        podpis[0] ^= 0x01
        deli[2] = Pomoc.b64url(podpis)
        guard case let .v2(_, sporocilo, p) = SkenKoda.razcleni(deli.joined(separator: ".")) else { return XCTFail() }
        XCTAssertFalse(SkenPodpis.preveri(sporocilo: sporocilo, podpis: p, javniKljuc: Pomoc.javni(kljuc)))
    }

    func testSpremenjenoTeloJeZavrnjeno() throws {
        let s = Pomoc.serial()
        let qr = Pomoc.koda(kljuc, serial: s, event: 1)
        let deli = qr.split(separator: ".").map(String.init)
        // Napadalec zamenja dogodek v telesu, podpis ostane.
        let ponarejeno = "o2.\(Pomoc.telo(serial: s, event: 2)).\(deli[2])"
        guard case let .v2(_, sporocilo, p) = SkenKoda.razcleni(ponarejeno) else { return XCTFail() }
        XCTAssertFalse(SkenPodpis.preveri(sporocilo: sporocilo, podpis: p, javniKljuc: Pomoc.javni(kljuc)))
    }

    func testTujKljucJeZavrnjen() throws {
        let qr = Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 1)
        guard case let .v2(_, sporocilo, p) = SkenKoda.razcleni(qr) else { return XCTFail() }
        let drug = Curve25519.Signing.PrivateKey()
        XCTAssertFalse(SkenPodpis.preveri(sporocilo: sporocilo, podpis: p, javniKljuc: Pomoc.javni(drug)))
        XCTAssertFalse(SkenPodpis.preveri(sporocilo: sporocilo, podpis: p, javniKljuc: Data(repeating: 0, count: 31)))
    }

    func testSmetiNisoKoda() {
        XCTAssertTrue(jeNeznano(""))
        XCTAssertTrue(jeNeznano("https://example.com/x"))
        XCTAssertTrue(jeNeznano("o2.@@@.@@@"))
        XCTAssertTrue(jeNeznano("o2.\(Pomoc.telo(serial: "ni-uuid", event: 1)).\(Pomoc.b64url(Data(count: 64)))"))
        XCTAssertTrue(jeNeznano("o2.\(Pomoc.telo(serial: Pomoc.serial(), event: 1)).\(Pomoc.b64url(Data(count: 10)))"))
        XCTAssertTrue(jeNeznano(String(repeating: "a", count: 2000)))
    }

    /// P4: koda v1 mora imeti telo {v:1, t: UUID, e}; vsak "a.b" ni v1 (pred popravkom je bil vsak par z dvema deloma »stara koda«).
    func testKodaV1MoraImetiPraviloTelo() {
        let s = Pomoc.serial()
        XCTAssertTrue(jeV1(Pomoc.kodaV1(serial: s, event: 42)))
        guard case let .v1(telo) = SkenKoda.razcleni(Pomoc.kodaV1(serial: s.uppercased(), event: 42)) else { return XCTFail() }
        XCTAssertEqual(telo.serial, s)
        XCTAssertEqual(telo.eventId, 42)
        XCTAssertNil(telo.kid)
        XCTAssertTrue(jeNeznano("abc.def"))
        XCTAssertTrue(jeNeznano("o2.abc"))
        XCTAssertTrue(jeNeznano("eyJ0IjoiYWJjIn0.0123456789abcdef0123456789abcdef"))   // telo {"t":"abc"}: ni UUID, ni v
        XCTAssertTrue(jeNeznano("e30.0123456789abcdef"))                               // telo {}
        let slabUuid = Pomoc.b64url(Data("{\"v\":1,\"t\":\"ni-uuid\",\"e\":42}".utf8))
        XCTAssertTrue(jeNeznano("\(slabUuid).0123456789abcdef0123456789abcdef"))
        let napacnaVerzija = Pomoc.b64url(Data("{\"v\":2,\"t\":\"\(s)\",\"e\":42}".utf8))
        XCTAssertTrue(jeNeznano("\(napacnaVerzija).0123456789abcdef0123456789abcdef"))
        let brezDogodka = Pomoc.b64url(Data("{\"v\":1,\"t\":\"\(s)\"}".utf8))
        XCTAssertTrue(jeNeznano("\(brezDogodka).0123456789abcdef0123456789abcdef"))
    }

    /// M15: dejanska koda, ki jo je izdal backend (QR_SECRET »outly-test-secret-0123456789-abcdefghij-XYZ«, backend `qrKodaV2`),
    /// in javni kljuc iz GET /business/scan-key. Ujame razhajanje formata (kodiranje, vrstni red polj, podpisano besedilo), ki ga
    /// testi s podpisom iz CryptoKit ne morejo: ti bi se z napako v obe smeri ujemali sami s seboj.
    func testKodaIzdanaNaBackenduSePreveri() {
        let qr = "o2.eyJ2IjoyLCJ0IjoiNWIwZjBhNGUtNmMxZC00ZjdhLTlhNTItM2MxZDJlN2I4YTkwIiwiZSI6NDI0MiwiaSI6MTc5MDc2OTYwMCwiayI6IklWQlZ3TXA4ekcwIn0.8qToG70-CDxRzP2DVfayB-T9DeYrFSQ_KjWSPmSTzygeckkVsAc4oLQtbtXRIxFZA_ZhSMdnn9rqLr4f6JgJAw"
        let kljuc = ScanKey(kid: "IVBVwMp8zG0", publicKey: "hlTuMAovT8cRxqiA11PnLeCuyCAzbtq6edCPyuTcDUk")
        XCTAssertNotNil(kljuc.surovi)
        guard case let .v2(telo, sporocilo, podpis) = SkenKoda.razcleni(qr) else { return XCTFail("backendova koda ni v2") }
        XCTAssertEqual(telo.serial, "5b0f0a4e-6c1d-4f7a-9a52-3c1d2e7b8a90")
        XCTAssertEqual(telo.eventId, 4242)
        XCTAssertEqual(telo.kid, "IVBVwMp8zG0")
        XCTAssertTrue(SkenPodpis.preveri(sporocilo: sporocilo, podpis: podpis, javniKljuc: kljuc.surovi ?? Data()))
        // ... in prek celotne odlocitve: pravi dogodek zelena, drug dogodek rdeca, ponarejen podpis rdeca
        let s1 = SkenOdlocitev.odloci(qr: qr, dogodekId: 4242, kljuc: kljuc, indeks: nil, lokalni: [:])
        XCTAssertEqual(s1.razlog, .veljavnaNiNaSeznamu)
        XCTAssertEqual(SkenOdlocitev.odloci(qr: qr, dogodekId: 1, kljuc: kljuc, indeks: nil, lokalni: [:]).razlog, .napacenDogodek)
        var zlomljen = Array(qr)
        zlomljen[zlomljen.count - 5] = zlomljen[zlomljen.count - 5] == "A" ? "B" : "A"
        XCTAssertEqual(SkenOdlocitev.odloci(qr: String(zlomljen), dogodekId: 4242, kljuc: kljuc, indeks: nil, lokalni: [:]).razlog, .neveljavna)
    }

    func testBase64URL() {
        XCTAssertEqual(Data(base64URL: "-_8"), Data([0xfb, 0xff]))
        XCTAssertNil(Data(base64URL: "a"))      // dolzina mod 4 == 1
        XCTAssertNil(Data(base64URL: "a+b="))   // ni base64url
        XCTAssertEqual(Data(base64URL: ""), Data())
    }
}

// MARK: - Odlocitev

final class SkenOdlocitevTests: XCTestCase {
    private let kljuc = Curve25519.Signing.PrivateKey()
    private let dogodek = 42

    private func odloci(_ qr: String, seznam: ScanList?, lokalni: [String: Date] = [:], kljucPodatek: ScanKey? = nil) -> SkenSodba {
        SkenOdlocitev.odloci(qr: qr, dogodekId: dogodek, kljuc: kljucPodatek ?? Pomoc.scanKey(kljuc),
                             indeks: seznam.map { SkenIndeks($0) }, lokalni: lokalni)
    }

    func testVeljavnaVstopnicaJeZelena() {
        let s = Pomoc.serial()
        let seznam = ScanList(eventId: dogodek, tickets: [ScanListTicket(serial: s, isVip: true, tableLabel: "T1", packageName: "Jameson", holderUsername: "ana")])
        let r = odloci(Pomoc.koda(kljuc, serial: s, event: dogodek), seznam: seznam)
        XCTAssertEqual(r.razlog, .veljavna)
        XCTAssertEqual(r.barva, .zeleno)
        XCTAssertTrue(r.spusti)
        XCTAssertEqual(r.vstopnica?.holderUsername, "ana")
        XCTAssertEqual(r.serial, s)
    }

    func testPodpisanaKodaBrezVnosaNaSeznamuJeZelenaZOpombo() {
        let r = odloci(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: dogodek), seznam: ScanList(eventId: dogodek))
        XCTAssertEqual(r.razlog, .veljavnaNiNaSeznamu)
        XCTAssertEqual(r.barva, .zeleno)
    }

    /// P4: kljuc je, seznama (se) ni: podpis in dogodek se vseeno preverita, sele nato zeleno z opombo.
    func testKljucBrezSeznamaPreveriPodpisInDogodek() {
        let s = Pomoc.serial()
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: dogodek), seznam: nil).razlog, .veljavnaNiNaSeznamu)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: 7), seznam: nil).razlog, .napacenDogodek)
        let tuj = Curve25519.Signing.PrivateKey()
        XCTAssertEqual(odloci(Pomoc.koda(tuj, serial: s, event: dogodek), seznam: nil).razlog, .neveljavna)
    }

    func testSpremenjenPodpisTeloAliKljucJeRdece() {
        let s = Pomoc.serial()
        let seznam = ScanList(eventId: dogodek, tickets: [ScanListTicket(serial: s)])
        let qr = Pomoc.koda(kljuc, serial: s, event: dogodek)
        let deli = qr.split(separator: ".").map(String.init)
        var podpis = Data(base64URL: deli[2])!
        podpis[10] ^= 0xff
        XCTAssertEqual(odloci("\(deli[0]).\(deli[1]).\(Pomoc.b64url(podpis))", seznam: seznam).razlog, .neveljavna)
        XCTAssertEqual(odloci("o2.\(Pomoc.telo(serial: s, event: 99)).\(deli[2])", seznam: seznam).razlog, .neveljavna)
        XCTAssertEqual(odloci(qr, seznam: seznam, kljucPodatek: Pomoc.scanKey(Curve25519.Signing.PrivateKey())).razlog, .neveljavna)
        XCTAssertEqual(odloci("nekaj tretjega", seznam: seznam).razlog, .neveljavna)
    }

    /// M10: koda z drugim `kid` od kljuca na telefonu ni ponaredek, ampak zastarel kljuc: rumeno, ne rdece.
    func testDrugKidJeRumenoNeRdece() {
        let s = Pomoc.serial()
        let novi = Curve25519.Signing.PrivateKey()
        let r = odloci(Pomoc.koda(novi, serial: s, event: dogodek, kid: "kid2"), seznam: ScanList(eventId: dogodek, tickets: [ScanListTicket(serial: s)]))
        XCTAssertEqual(r.razlog, .kljucNeujema)
        XCTAssertEqual(r.barva, .rumeno)
        XCTAssertFalse(r.spusti)
        // isti kid, drug podpis = ponaredek: rdece
        let ponaredek = odloci(Pomoc.koda(novi, serial: s, event: dogodek, kid: "kid1"), seznam: nil)
        XCTAssertEqual(ponaredek.razlog, .neveljavna)
    }

    func testNapacenDogodekJeRdece() {
        let s = Pomoc.serial()
        let r = odloci(Pomoc.koda(kljuc, serial: s, event: 7), seznam: ScanList(eventId: dogodek, tickets: [ScanListTicket(serial: s)]))
        XCTAssertEqual(r.razlog, .napacenDogodek)
        XCTAssertEqual(r.barva, .rdece)
    }

    func testPrenesenSerialJeRdece() {
        let s = Pomoc.serial()
        let r = odloci(Pomoc.koda(kljuc, serial: s, event: dogodek), seznam: ScanList(eventId: dogodek, transferredSerials: [s.uppercased()]))
        XCTAssertEqual(r.razlog, .prenesena)
        XCTAssertEqual(r.barva, .rdece)
    }

    func testStanjePoSeznamu() {
        let u = Pomoc.serial(), v = Pomoc.serial(), x = Pomoc.serial(), n = Pomoc.serial(), neznan = Pomoc.serial()
        let seznam = ScanList(eventId: dogodek, tickets: [
            ScanListTicket(serial: u, status: "used", usedAt: "2026-10-01T21:15:00.000Z"),
            ScanListTicket(serial: v, status: "refunded"),
            ScanListTicket(serial: x, status: "void"),
            ScanListTicket(serial: n, status: "unpaid"),
            ScanListTicket(serial: neznan, status: "nekaj-novega"),
        ])
        let ru = odloci(Pomoc.koda(kljuc, serial: u, event: dogodek), seznam: seznam)
        XCTAssertEqual(ru.razlog, .zeUporabljena)
        XCTAssertEqual(ru.kdaj, SkenCas.razcleni("2026-10-01T21:15:00.000Z"))
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: v, event: dogodek), seznam: seznam).razlog, .vrnjena)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: x, event: dogodek), seznam: seznam).razlog, .preklicana)
        // P3: neplacano narocilo je rdece (backend ga vrne s statusom unpaid)
        let rn = odloci(Pomoc.koda(kljuc, serial: n, event: dogodek), seznam: seznam)
        XCTAssertEqual(rn.razlog, .neplacana)
        XCTAssertEqual(rn.barva, .rdece)
        // neznan status ni nikoli zelen
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: neznan, event: dogodek), seznam: seznam).barva, .rdece)
    }

    func testDvojniLokalniSkenJeRdece() {
        let s = Pomoc.serial()
        let cas = Date(timeIntervalSince1970: 1_790_000_000)
        let seznam = ScanList(eventId: dogodek, tickets: [ScanListTicket(serial: s)])
        let r = odloci(Pomoc.koda(kljuc, serial: s, event: dogodek), seznam: seznam, lokalni: [s: cas])
        XCTAssertEqual(r.razlog, .zeUporabljenaLokalno)
        XCTAssertEqual(r.kdaj, cas)
        // tudi, ce vstopnice ni na seznamu
        let r2 = odloci(Pomoc.koda(kljuc, serial: s, event: dogodek), seznam: ScanList(eventId: dogodek), lokalni: [s: cas])
        XCTAssertEqual(r2.razlog, .zeUporabljenaLokalno)
    }

    func testStaraKodaInManjkajociPodatki() {
        let s = Pomoc.serial()
        let v1 = Pomoc.kodaV1(serial: s, event: dogodek)
        XCTAssertEqual(odloci(v1, seznam: ScanList(eventId: dogodek)).razlog, .staraKoda)
        XCTAssertEqual(odloci(v1, seznam: ScanList(eventId: dogodek)).barva, .rumeno)
        let brez = SkenOdlocitev.odloci(qr: Pomoc.koda(kljuc, serial: s, event: dogodek), dogodekId: dogodek, kljuc: nil, indeks: nil, lokalni: [:])
        XCTAssertEqual(brez.razlog, .manjkaPodatkov)
        XCTAssertEqual(brez.barva, .rumeno)
        // negativni podatki veljajo tudi za v1: ze skenirana na tej napravi, prenesena, drug dogodek
        XCTAssertEqual(odloci(v1, seznam: ScanList(eventId: dogodek), lokalni: [s: Date()]).razlog, .zeUporabljenaLokalno)
        XCTAssertEqual(odloci(v1, seznam: ScanList(eventId: dogodek, transferredSerials: [s])).razlog, .prenesena)
        XCTAssertEqual(odloci(Pomoc.kodaV1(serial: s, event: 9), seznam: nil).razlog, .napacenDogodek)
        // koda, ki ni v1 ali v2, je neveljavna (ne »stara koda«, ki bi ponudila »Let in«)
        XCTAssertEqual(odloci("abc.def", seznam: nil).razlog, .neveljavna)
        XCTAssertEqual(odloci("e30.0123456789abcdef", seznam: nil).razlog, .neveljavna)
    }
}

// MARK: - Modeli

final class SkenModeliTests: XCTestCase {
    func testScanListInKljucSeDekodirataBrezNovihPolj() throws {
        let json = """
        {"event_id": 5, "generated_at": "2026-10-01T20:00:00.000Z", "kid": "abc",
         "tickets": [{"serial": "S1", "status": "valid", "used_at": null, "is_vip": true, "table_label": "T2", "package_name": null, "holder_username": "ana"},
                     {"serial": "S2"}],
         "transferred_serials": ["OLD"], "nekaj_novega": 1}
        """
        let l = try JSONDecoder().decode(ScanList.self, from: Data(json.utf8))
        XCTAssertEqual(l.eventId, 5)
        XCTAssertEqual(l.tickets.count, 2)
        XCTAssertTrue(l.tickets[0].isVip)
        XCTAssertEqual(l.tickets[1].status, "unknown")   // manjkajoc status ni nikoli "valid"
        XCTAssertFalse(l.tickets[1].isVip)
        XCTAssertEqual(l.transferredSerials, ["OLD"])

        let k = try JSONDecoder().decode(ScanKey.self, from: Data(#"{"alg":"Ed25519","kid":"k","public_key":"\#(Pomoc.b64url(Data(count: 32)))","qr_format":"x"}"#.utf8))
        XCTAssertEqual(k.kid, "k")
        XCTAssertEqual(k.surovi?.count, 32)
        XCTAssertNil(ScanKey(alg: "RSA", kid: "k", publicKey: Pomoc.b64url(Data(count: 32))).surovi)
        XCTAssertNil(ScanKey(kid: "k", publicKey: "kratek").surovi)
    }

    /// M9: pokvarjen odgovor ne sme postati prazen seznam (to bi izbrisalo vso znanje o vstopnicah).
    func testPokvarjenSeznamVrzeNamestoPraznega() {
        XCTAssertThrowsError(try JSONDecoder().decode(ScanList.self, from: Data(#"{"event_id":1,"tickets":"nekaj","transferred_serials":[]}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ScanList.self, from: Data(#"{"event_id":1,"tickets":[{"status":"valid"}],"transferred_serials":[]}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ScanList.self, from: Data("{}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ScanList.self, from: Data(#"{"event_id":1,"tickets":[]}"#.utf8)))
    }

    func testRezultatiBatcha() throws {
        let json = #"[{"client_scan_id":"a","serial":"s","result":"ok","used_at":"2026-10-01T21:00:00.000Z"},{"client_scan_id":"b","serial":null,"result":"error","used_at":null},{"result":"invalid"}]"#
        let r = try JSONDecoder().decode([ScanBatchResult].self, from: Data(json.utf8))
        XCTAssertTrue(r[0].jeDokoncen)
        XCTAssertFalse(r[1].jeDokoncen)   // error ostane v vrsti
        XCTAssertFalse(r[2].jeDokoncen)   // brez client_scan_id ga ni mogoce povezati z vnosom
    }
}

// MARK: - Klasifikacija napak, cas prenosa (M11, M12)

final class SkenNapakeInCasTests: XCTestCase {
    /// M12: preklic ni izpad povezave; omrezne napake in 5xx so.
    func testPreklicNiIzpadPovezave() {
        XCTAssertFalse(URLError(.cancelled).jeIzpadPovezave)
        XCTAssertFalse(CancellationError().jeIzpadPovezave)
        XCTAssertTrue(URLError(.notConnectedToInternet).jeIzpadPovezave)
        XCTAssertTrue(URLError(.timedOut).jeIzpadPovezave)
        XCTAssertTrue(APIError.requestFailed(503, "").jeIzpadPovezave)
        XCTAssertTrue(APIError.requestFailed(-1, "Could not refresh session").jeIzpadPovezave)
        XCTAssertTrue(APIError.requestFailed(429, "").jeIzpadPovezave)
        for koda in [400, 401, 403, 404, 409] { XCTAssertFalse(APIError.requestFailed(koda, "").jeIzpadPovezave) }
        XCTAssertFalse(APIError.decodingFailed.jeIzpadPovezave)
        XCTAssertFalse(SkenSeja.jeOmrezna(URLError(.cancelled)))
        XCTAssertTrue(SkenSeja.jeOmrezna(URLError(.networkConnectionLost)))
    }

    func testSeznamJeStarPo10Minutah() {
        let zdaj = Date()
        XCTAssertFalse(SkenSeja.jeStar(nil, zdaj: zdaj))                                  // ni prenosa: »ni prenesen«, ne »star«
        XCTAssertFalse(SkenSeja.jeStar(zdaj.addingTimeInterval(-60), zdaj: zdaj))
        XCTAssertFalse(SkenSeja.jeStar(zdaj.addingTimeInterval(-9 * 60), zdaj: zdaj))
        XCTAssertTrue(SkenSeja.jeStar(zdaj.addingTimeInterval(-11 * 60), zdaj: zdaj))
    }

    func testCasPrenosaImaDatumCeNiDanes() {
        var koledar = Calendar(identifier: .gregorian)
        koledar.timeZone = TimeZone(identifier: "UTC")!
        let zdaj = Date(timeIntervalSince1970: 1_790_000_000)
        let danes = zdaj.addingTimeInterval(-3600)
        let vceraj = zdaj.addingTimeInterval(-26 * 3600)
        XCTAssertEqual(SkenPrikaz.casPrenosa(danes, zdaj: zdaj, koledar: koledar), SkenPrikaz.cas(danes))
        XCTAssertNotEqual(SkenPrikaz.casPrenosa(vceraj, zdaj: zdaj, koledar: koledar), SkenPrikaz.cas(vceraj))
        XCTAssertTrue(SkenPrikaz.casPrenosa(vceraj, zdaj: zdaj, koledar: koledar).count > SkenPrikaz.cas(vceraj).count)
    }
}

// MARK: - K1: hladen zagon brez povezave

final class MeShrambaTests: XCTestCase {
    private var mapa: URL!
    private var disk: SkenDisk!
    private let sub = "5b0f0a4e-6c1d-4f7a-9a52-3c1d2e7b8a90"

    override func setUp() async throws {
        mapa = Pomoc.zacasnaMapa()
        disk = SkenDisk(mapa: mapa.appendingPathComponent("Seja", isDirectory: true))
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: mapa) }

    private func vratar(id: Int = 7, onboardan: Bool = true) throws -> Me {
        let onb = onboardan ? #","onboarded_at":"2026-09-01T10:00:00.000Z""# : ""
        let json = """
        {"id":\(id),"email":"ana@primer.si","username":"ana","role":"user","club_id":3,"club_role":"doorman",
         "clubs":[{"club_id":3,"club_name":"Klub Tri","club_logo_url":"https://x/y.png","role":"doorman"}],
         "pending_invites":2,"genres":["techno"]\(onb)}
        """
        return try JSONDecoder().decode(Me.self, from: Data(json.utf8))
    }

    private func jwt(sub: String) -> String {
        let glava = Pomoc.b64url(Data(#"{"alg":"ES256","typ":"JWT"}"#.utf8))
        let telo = Pomoc.b64url(Data(#"{"sub":"\#(sub)","exp":1790000000}"#.utf8))
        return "\(glava).\(telo).podpis"
    }

    func testMeSePrebereNazajIzDiska() throws {
        let me = try vratar()
        XCTAssertNil(MeShramba.preberi(sub: sub, disk: disk))
        XCTAssertTrue(MeShramba.shrani(me, sub: sub, disk: disk))
        let nazaj = MeShramba.preberi(sub: sub, disk: disk)
        XCTAssertEqual(nazaj, me)
        XCTAssertEqual(nazaj?.clubs.first?.clubName, "Klub Tri")
        XCTAssertEqual(nazaj?.clubs.first?.role, "doorman")
        XCTAssertEqual(nazaj?.isOnboarded, true)
        XCTAssertEqual(MeShramba.preberiZapis(disk: disk)?.sub, sub)
        // brez zetonov: datoteka ima samo Me in sub
        let besedilo = String(data: disk.surovo(MeShramba.ime) ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(besedilo.lowercased().contains("token"))
        XCTAssertFalse(besedilo.contains("Bearer"))
        MeShramba.pobrisi(disk: disk)
        XCTAssertNil(MeShramba.preberi(sub: sub, disk: disk))
    }

    /// Pomembno 10: Me drugega racuna (drug `sub`) se ob branju zavrne.
    func testMeDrugegaRacunaSeZavrne() throws {
        MeShramba.shrani(try vratar(), sub: sub, disk: disk)
        XCTAssertNil(MeShramba.preberi(sub: "00000000-0000-0000-0000-000000000000", disk: disk))
        XCTAssertNil(MeShramba.preberi(sub: nil, disk: disk))
        XCTAssertNotNil(MeShramba.preberi(sub: sub.uppercased(), disk: disk))   // velikost crk ni pomembna
    }

    func testSubIzZetona() {
        XCTAssertEqual(MeShramba.sub(izZetona: jwt(sub: sub)), sub)
        XCTAssertEqual(MeShramba.sub(izZetona: jwt(sub: sub.uppercased())), sub)
        XCTAssertNil(MeShramba.sub(izZetona: ""))
        XCTAssertNil(MeShramba.sub(izZetona: "a.b"))
        XCTAssertNil(MeShramba.sub(izZetona: "a.@@@.c"))
        XCTAssertNil(MeShramba.sub(izZetona: "a.\(Pomoc.b64url(Data("{}".utf8))).c"))
    }

    /// Pomembno 3: neonboardan Me, shranjen pred koncanim onboardingom, se ob novem shranjevanju (didSet v SessionStore) nadomesti.
    func testShranjevanjePrepiseStarMe() throws {
        MeShramba.shrani(try vratar(onboardan: false), sub: sub, disk: disk)
        XCTAssertEqual(MeShramba.preberi(sub: sub, disk: disk)?.isOnboarded, false)
        MeShramba.shrani(try vratar(onboardan: true), sub: sub, disk: disk)
        XCTAssertEqual(MeShramba.preberi(sub: sub, disk: disk)?.isOnboarded, true)
    }

    /// Pred popravkom: GET /me brez povezave -> nikoli Me -> SessionLoadingView za vedno (vratar ne pride do skenerja).
    func testIzpadPovezaveUporabiShranjenMe() throws {
        let me = try vratar()
        MeShramba.shrani(me, sub: sub, disk: disk)
        let shranjen = MeShramba.preberi(sub: sub, disk: disk)
        XCTAssertEqual(MeShramba.nadomestniMe(ob: URLError(.notConnectedToInternet), shranjen: shranjen), me)
        XCTAssertEqual(MeShramba.nadomestniMe(ob: URLError(.timedOut), shranjen: shranjen), me)
        XCTAssertEqual(MeShramba.nadomestniMe(ob: APIError.requestFailed(503, ""), shranjen: shranjen), me)
        XCTAssertEqual(MeShramba.nadomestniMe(ob: APIError.requestFailed(-1, "Could not refresh session"), shranjen: shranjen), me)
    }

    /// 401/403 in pokvarjen odgovor NISO izpad: tam odloca SessionStore (odjava ali napaka), ne shranjen Me.
    func testZavrnitevInPreklicNistaIzpad() throws {
        let shranjen = try vratar()
        XCTAssertNil(MeShramba.nadomestniMe(ob: APIError.requestFailed(401, ""), shranjen: shranjen))
        XCTAssertNil(MeShramba.nadomestniMe(ob: APIError.requestFailed(403, ""), shranjen: shranjen))
        XCTAssertNil(MeShramba.nadomestniMe(ob: APIError.requestFailed(404, ""), shranjen: shranjen))
        XCTAssertNil(MeShramba.nadomestniMe(ob: APIError.decodingFailed, shranjen: shranjen))
        XCTAssertNil(MeShramba.nadomestniMe(ob: URLError(.cancelled), shranjen: shranjen))
        // brez shranjenega Me ni cesa uporabiti
        XCTAssertNil(MeShramba.nadomestniMe(ob: URLError(.notConnectedToInternet), shranjen: nil))
    }

    func testPokvarjenaDatotekaMeNiCrash() throws {
        try FileManager.default.createDirectory(at: disk.mapa, withIntermediateDirectories: true)
        try Data("{ ni json".utf8).write(to: disk.mapa.appendingPathComponent(MeShramba.ime))
        XCTAssertNil(MeShramba.preberi(sub: sub, disk: disk))
        // star zapis brez `sub` (samo Me) se prav tako zavrne, ne podre
        try JSONEncoder().encode(try vratar()).write(to: disk.mapa.appendingPathComponent(MeShramba.ime))
        XCTAssertNil(MeShramba.preberi(sub: sub, disk: disk))
    }
}

// MARK: - Vrsta

@MainActor
final class SkenVrstaTests: XCTestCase {
    private var mapa: URL!
    private var disk: SkenDisk!

    override func setUp() async throws {
        mapa = Pomoc.zacasnaMapa()
        disk = SkenDisk(mapa: mapa)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: mapa)
    }

    private func vnos(_ id: String = UUID().uuidString.lowercased(), klub: Int = 1, uporabnik: Int? = 7, dogodek: Int = 42,
                      cas: Date = Date()) -> SkenVnos {
        SkenVnos(clientScanId: id, qr: "o2.x.y", serial: Pomoc.serial(), eventId: dogodek, klubId: klub, uporabnikId: uporabnik,
                 scannedAt: cas, imetnik: "ana")
    }

    func testVrstaPrezivi_ponovniZagon() {
        let a = vnos(cas: Date(timeIntervalSince1970: 1_790_000_000)), b = vnos(cas: Date(timeIntervalSince1970: 1_790_000_100))
        let v1 = SkenVrsta(disk: disk)
        v1.dodaj(a)
        v1.dodaj(b)
        let v2 = SkenVrsta(disk: disk)   // simulira zaprtje in ponovni zagon aplikacije
        XCTAssertEqual(v2.vnosi, [a, b])
        XCTAssertTrue(v2.zapisUspel)
    }

    func testDodajJeIdempotentenPoClientScanId() {
        let v = SkenVrsta(disk: disk)
        let a = vnos("id-1")
        XCTAssertTrue(v.dodaj(a))
        XCTAssertFalse(v.dodaj(a))
        XCTAssertEqual(v.vnosi.count, 1)
    }

    /// M8: dodajanje skena zapise samo nov vnos; obstojecih datotek ne prepisuje (pred popravkom je vsak sken prepisal celo vrsto).
    func testDodajanjeSkenaNePrepisujeCeleVrste() throws {
        let v = SkenVrsta(disk: disk)
        v.dodaj(vnos("a"))
        let pot = mapa.appendingPathComponent("vrsta/a.json")
        try Data("marker".utf8).write(to: pot)
        v.dodaj(vnos("b"))
        XCTAssertEqual(try String(contentsOf: pot, encoding: .utf8), "marker")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mapa.appendingPathComponent("vrsta/b.json").path))
    }

    func testOkOdstraniTihoAlreadyUsedPostaneKonflikt() {
        let v = SkenVrsta(disk: disk)
        let a = vnos("a"), b = vnos("b"), c = vnos("c")
        [a, b, c].forEach { v.dodaj($0) }
        let odstranjeni = v.uporabi([
            ScanBatchResult(clientScanId: "a", serial: a.serial, result: "ok", usedAt: "2026-10-01T21:00:00.000Z"),
            ScanBatchResult(clientScanId: "b", serial: b.serial, result: "already_used", usedAt: "2026-10-01T20:59:00.000Z"),
            ScanBatchResult(clientScanId: "c", serial: c.serial, result: "error"),
        ], poslani: [a, b, c])
        XCTAssertEqual(odstranjeni, 2)
        XCTAssertEqual(v.vnosi.map { $0.clientScanId }, ["c"])      // error ostane v vrsti
        XCTAssertEqual(v.vnosi.first?.poskusi, 1)
        XCTAssertEqual(v.konflikti.count, 1)
        XCTAssertEqual(v.konflikti[0].clientScanId, "b")
        XCTAssertEqual(v.konflikti[0].result, "already_used")
        XCTAssertEqual(v.konflikti[0].streznikUsedAt, "2026-10-01T20:59:00.000Z")
        XCTAssertEqual(v.konflikti[0].imetnik, "ana")
        // konflikt in preostali vnos prezivita ponovni zagon
        let v2 = SkenVrsta(disk: disk)
        XCTAssertEqual(v2.vnosi.count, 1)
        XCTAssertEqual(v2.nepotrjeniKonflikti(klub: 1).count, 1)
    }

    func testPonovnaObdelavaIstegaOdgovoraJeNeskodljiva() {
        let v = SkenVrsta(disk: disk)
        let a = vnos("a"), b = vnos("b")
        v.dodaj(a); v.dodaj(b)
        let rez = [ScanBatchResult(clientScanId: "a", result: "already_used"), ScanBatchResult(clientScanId: "b", result: "ok")]
        v.uporabi(rez, poslani: [a, b])
        v.uporabi(rez, poslani: [a, b])   // ponovitev odgovora (npr. dvojen klic)
        XCTAssertTrue(v.vnosi.isEmpty)
        XCTAssertEqual(v.konflikti.count, 1)
    }

    func testVsiDokoncniRezultatiOdstranijoVnos() {
        let v = SkenVrsta(disk: disk)
        let imena = ["ok", "already_used", "transferred", "invalid", "wrong_club", "unknown", "unpaid", "refunded", "void"]
        let vnosi = imena.map { vnos($0) }
        vnosi.forEach { v.dodaj($0) }
        v.uporabi(imena.map { ScanBatchResult(clientScanId: $0, result: $0) }, poslani: vnosi)
        XCTAssertTrue(v.vnosi.isEmpty)
        XCTAssertEqual(v.konflikti.count, imena.count - 1)   // vse razen ok
    }

    func testVnosBrezRezultataOstane() {
        let v = SkenVrsta(disk: disk)
        let a = vnos("a")
        v.dodaj(a)
        v.uporabi([], poslani: [a])
        XCTAssertEqual(v.vnosi.count, 1)
        XCTAssertEqual(v.vnosi[0].poskusi, 1)
    }

    func testPaketJeOmejenNa500InFiltriranPoKlubuInUporabniku() {
        let v = SkenVrsta(disk: disk)
        for _ in 0..<520 { v.dodaj(vnos()) }
        v.dodaj(vnos(klub: 2))
        v.dodaj(vnos(uporabnik: 99))
        XCTAssertEqual(v.paket(klub: 1, uporabnik: 7).count, 500)
        XCTAssertEqual(v.stevilo(klub: 1, uporabnik: 7), 520)
        XCTAssertEqual(v.stevilo(klub: 2, uporabnik: 7), 1)
        XCTAssertEqual(v.stevilo(klub: 1, uporabnik: nil), 521)   // uporabnik neznan -> vsi tega kluba
        XCTAssertEqual(v.steviloVseh, 522)
    }

    func testZadrzaniVnosNeGreVPaket() {
        let v = SkenVrsta(disk: disk)
        v.dodaj(vnos("a"), zadrzi: true)
        v.dodaj(vnos("b"))
        XCTAssertEqual(v.paket(klub: 1, uporabnik: 7).map { $0.clientScanId }, ["b"])
        XCTAssertEqual(v.stevilo(klub: 1, uporabnik: 7), 2)   // a se vedno caka (steje se)
        v.sprosti("a")
        XCTAssertEqual(v.paket(klub: 1, uporabnik: 7).count, 2)
    }

    func testPotrditevKonfliktaPrezivi() {
        let v = SkenVrsta(disk: disk)
        let a = vnos("a")
        v.dodaj(a)
        v.uporabi([ScanBatchResult(clientScanId: "a", result: "already_used")], poslani: [a])
        v.potrdiKonflikt("a")
        XCTAssertEqual(v.nepotrjeniKonflikti(klub: 1).count, 0)
        XCTAssertEqual(SkenVrsta(disk: disk).konflikti.count, 1)   // ni izbrisan, samo potrjen
    }

    /// M14: potrjeni konflikti, starejsi od 30 dni, se obrezejo; nepotrjeni ostanejo, dokler jih vratar ne potrdi.
    func testPotrjeniKonfliktiStarejsiOd30DniSeObrezejo() {
        let v = SkenVrsta(disk: disk)
        let staro = Date().addingTimeInterval(-40 * 86400)
        let star = vnos("star", cas: staro), svez = vnos("svez"), nepotrjenStar = vnos("nepotrjen", cas: staro)
        [star, svez, nepotrjenStar].forEach { v.dodaj($0) }
        v.uporabi(["star", "svez", "nepotrjen"].map { ScanBatchResult(clientScanId: $0, result: "already_used") }, poslani: [star, svez, nepotrjenStar])
        XCTAssertEqual(v.konflikti.count, 3)
        v.potrdiKonflikt("star")
        v.potrdiKonflikt("svez")
        XCTAssertEqual(Set(v.konflikti.map { $0.clientScanId }), ["svez", "nepotrjen"])          // potrjen in star: ze obrezan
        XCTAssertEqual(Set(SkenVrsta(disk: disk).konflikti.map { $0.clientScanId }), ["svez", "nepotrjen"])
        // cez 31 dni (ob zagonu) se obreze se potrjeni svez, nepotrjen starec ostane
        let kasneje = SkenVrsta(disk: disk, zdaj: Date().addingTimeInterval(31 * 86400))
        XCTAssertEqual(Set(kasneje.konflikti.map { $0.clientScanId }), ["nepotrjen"])
    }

    /// Manjse 6: konflikt se zapise PRED brisanjem vnosa. Ce zapisa konflikta ni mogoce narediti, vnos ostane (ponovno posiljanje je
    /// idempotentno); prej je ubitje vmes (ali napaka zapisa) izgubilo konflikt, gost pa je ze bil spuscen.
    func testKonfliktSeZapisePredBrisanjemVnosa() throws {
        let v = SkenVrsta(disk: disk)
        let a = vnos("a"), b = vnos("b")
        v.dodaj(a); v.dodaj(b)
        // zapis konfliktov ne uspe (na poti je mapa)
        try FileManager.default.createDirectory(at: mapa.appendingPathComponent(SkenVrsta.datotekaKonfliktov), withIntermediateDirectories: true)
        let odstranjeni = v.uporabi([ScanBatchResult(clientScanId: "a", result: "already_used"), ScanBatchResult(clientScanId: "b", result: "ok")],
                                    poslani: [a, b])
        XCTAssertEqual(odstranjeni, 1)                          // samo ok
        XCTAssertEqual(v.vnosi.map { $0.clientScanId }, ["a"])  // vnos s konfliktom ostane
        XCTAssertTrue(v.konflikti.isEmpty)
        XCTAssertFalse(v.zapisUspel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mapa.appendingPathComponent("vrsta/a.json").path))
        // pot se sprosti: isti odgovor zdaj zapise konflikt in sele nato odstrani vnos
        try FileManager.default.removeItem(at: mapa.appendingPathComponent(SkenVrsta.datotekaKonfliktov))
        XCTAssertEqual(v.uporabi([ScanBatchResult(clientScanId: "a", result: "already_used")], poslani: [a]), 1)
        XCTAssertTrue(v.vnosi.isEmpty)
        XCTAssertEqual(SkenVrsta(disk: disk).konflikti.map { $0.clientScanId }, ["a"])
        XCTAssertTrue(v.zapisUspel)
    }

    /// Manjse 7: zapisUspel ostane false, dokler ni potrjen vsak neuspel zapis (prej ga je prepisal naslednji uspesen zapis).
    func testNeuspelZapisOstaneVidenDoPotrditve() throws {
        let v = SkenVrsta(disk: disk)
        v.dodaj(vnos("a"))
        try FileManager.default.createDirectory(at: mapa.appendingPathComponent("vrsta/b.json"), withIntermediateDirectories: true)
        v.dodaj(vnos("b"))                 // zapis ne uspe
        XCTAssertFalse(v.zapisUspel)
        v.dodaj(vnos("c"))                 // uspe, a ne sme skriti napake pri b
        XCTAssertFalse(v.zapisUspel)
        try FileManager.default.removeItem(at: mapa.appendingPathComponent("vrsta/b.json"))
        v.ponoviNeuspele()
        XCTAssertTrue(v.zapisUspel)
        XCTAssertEqual(Set(SkenVrsta(disk: disk).vnosi.map { $0.clientScanId }), ["a", "b", "c"])
    }

    /// P5: pokvarjena shramba vrste ne sme tiho pobrisati cakajocih skenov: ostane na strani (vrsta.pokvarjena-<cas>.json).
    func testPokvarjenaVrstaOstaneNaStrani() throws {
        let v1 = SkenVrsta(disk: disk)
        v1.dodaj(vnos("a"))
        let podmapa = mapa.appendingPathComponent("vrsta")
        for ime in try FileManager.default.contentsOfDirectory(atPath: podmapa.path) {
            try Data("{ pokvarjeno".utf8).write(to: podmapa.appendingPathComponent(ime))
        }
        let v2 = SkenVrsta(disk: disk)
        XCTAssertEqual(v2.vnosi.count, 0)
        XCTAssertEqual(v2.pokvarjenihDatotek, 1)
        let stran = disk.imena().filter { $0.hasPrefix("vrsta.pokvarjena-") && $0.hasSuffix(".json") }
        XCTAssertEqual(stran.count, 1)
        XCTAssertEqual(String(data: disk.surovo(stran[0]) ?? Data(), encoding: .utf8), "{ pokvarjeno")
    }

    /// P5: ena pokvarjena datoteka ne potegne s seboj ostalih (pred popravkom je celotna vrsta padla skupaj z eno napako).
    func testPokvarjenVnosNePotegneOstalih() throws {
        let v1 = SkenVrsta(disk: disk)
        ["a", "b", "c"].forEach { v1.dodaj(vnos($0)) }
        try Data("{ pokvarjeno".utf8).write(to: mapa.appendingPathComponent("vrsta/b.json"))
        let v2 = SkenVrsta(disk: disk)
        XCTAssertEqual(Set(v2.vnosi.map { $0.clientScanId }), ["a", "c"])
        XCTAssertEqual(v2.pokvarjenihDatotek, 1)
        XCTAssertEqual(disk.imena().filter { $0.hasPrefix("vrsta.pokvarjena-") }.count, 1)
    }

    func testPokvarjenElementKonfliktovNePotegneOstalih() throws {
        let v1 = SkenVrsta(disk: disk)
        let a = vnos("a")
        v1.dodaj(a)
        v1.uporabi([ScanBatchResult(clientScanId: "a", result: "already_used")], poslani: [a])
        let dobri = try JSONSerialization.jsonObject(with: JSONEncoder().encode(v1.konflikti)) as? [Any] ?? []
        let podatki = try JSONSerialization.data(withJSONObject: dobri + [["nekaj": 1]])
        try podatki.write(to: mapa.appendingPathComponent(SkenVrsta.datotekaKonfliktov))
        let v2 = SkenVrsta(disk: disk)
        XCTAssertEqual(v2.konflikti.map { $0.clientScanId }, ["a"])
        XCTAssertEqual(v2.pokvarjenihDatotek, 1)
        XCTAssertEqual(disk.imena().filter { $0.hasPrefix("konflikti.pokvarjena-") }.count, 1)
    }

    func testDeljenaVrstaJeEnaNaDisk() {
        let a = SkenVrsta.deljena(disk)
        a.dodaj(vnos("x"))
        let b = SkenVrsta.deljena(SkenDisk(mapa: mapa))
        XCTAssertTrue(a === b)                       // stara in nova seja delita kopijo: nobena ne prepise datoteke z zastarelim stanjem
        XCTAssertEqual(b.vnosi.count, 1)
        XCTAssertFalse(SkenVrsta.deljena(SkenDisk(mapa: Pomoc.zacasnaMapa())) === a)
    }

    func testPociscenjeShrambeDogodkov() {
        disk.zapisi(SkenLokalniSkeni(), SkenDisk.imeLokalnih(klub: 1, dogodek: 10))
        disk.zapisi(SkenLokalniSkeni(), SkenDisk.imeLokalnih(klub: 1, dogodek: 11))
        disk.zapisi(SkenLokalniSkeni(), SkenDisk.imeLokalnih(klub: 2, dogodek: 10))
        disk.pocisti(klub: 1, obdrzi: [10])
        let imena = Set(disk.imena())
        XCTAssertTrue(imena.contains(SkenDisk.imeLokalnih(klub: 1, dogodek: 10)))
        XCTAssertFalse(imena.contains(SkenDisk.imeLokalnih(klub: 1, dogodek: 11)))
        XCTAssertTrue(imena.contains(SkenDisk.imeLokalnih(klub: 2, dogodek: 10)))
    }
}

// MARK: - SkenSeja

private final class LazniApi: SkenApi, @unchecked Sendable {
    private let zapah = NSLock()
    var kljucOdgovor: Result<ScanKey, Error>
    var seznamOdgovor: Result<Data, Error>
    var paketOdgovor: ([SkenVnos]) -> Result<[ScanBatchResult], Error> = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") }) }
    var spletniOdgovor: Result<ScanResult, Error> = .success(ScanResult(result: "ok", message: "Welcome", usedAt: nil))
    var dogodkiOdgovor: Result<[SkenDogodek], Error> = .success([])
    /// Streznik odgovori sele po toliko sekundah (ali ga prekine rok).
    /// Zakasnitve IGNORIRAJO preklic (kot nestrukturiran Task za osvezitev zetona v send(), ki ga preklic ne doseze).
    var zakasnitevPaketa: Double = 0
    var zakasnitevSpletnega: Double = 0
    var zakasnitevSeznama: Double = 0
    private(set) var paketi: [[SkenVnos]] = []
    private(set) var deviceIdji: [String] = []
    private(set) var spletniKlici: [String] = []
    private(set) var klubIdji: [Int?] = []
    private(set) var kljucKlici = 0
    private(set) var seznamKlici = 0

    init(kljuc: ScanKey, seznam: ScanList) {
        kljucOdgovor = .success(kljuc)
        seznamOdgovor = .success(Pomoc.seznamPodatki(seznam))
    }

    /// Caka, ne da bi se odzval na preklic Taska (continuation + GCD, ne Task.sleep).
    static func neprekinljivoCakaj(_ sekunde: Double) async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + sekunde) { k.resume() }
        }
    }

    func nastaviSeznam(_ l: ScanList) { seznamOdgovor = .success(Pomoc.seznamPodatki(l)) }

    // Zapah samo v sinhronih pomoznih funkcijah (NSLock v async funkciji je v Swift 6 napaka).
    private func zabelezi(_ klub: Int?, kljuc: Bool = false, seznam: Bool = false, paket: [SkenVnos]? = nil, deviceId: String? = nil, spletni: String? = nil) {
        zapah.lock()
        defer { zapah.unlock() }
        klubIdji.append(klub)
        if kljuc { kljucKlici += 1 }
        if seznam { seznamKlici += 1 }
        if let paket { paketi.append(paket) }
        if let deviceId { deviceIdji.append(deviceId) }
        if let spletni { spletniKlici.append(spletni) }
    }

    func dogodki(token: String, klubId: Int?) async throws -> [SkenDogodek] { zabelezi(klubId); return try dogodkiOdgovor.get() }
    func kljuc(token: String, klubId: Int?) async throws -> ScanKey {
        zabelezi(klubId, kljuc: true)
        return try kljucOdgovor.get()
    }
    func seznam(token: String, klubId: Int?, dogodekId: Int) async throws -> Data {
        zabelezi(klubId, seznam: true)
        if zakasnitevSeznama > 0 { await Self.neprekinljivoCakaj(zakasnitevSeznama) }
        return try seznamOdgovor.get()
    }
    func paket(token: String, klubId: Int?, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        zabelezi(klubId, paket: vnosi, deviceId: deviceId)
        if zakasnitevPaketa > 0 { await Self.neprekinljivoCakaj(zakasnitevPaketa) }
        return try paketOdgovor(vnosi).get()
    }
    func spletniSken(token: String, klubId: Int?, qr: String, rok: Double) async throws -> ScanResult {
        zabelezi(klubId, spletni: qr)
        if zakasnitevSpletnega > 0 { await Self.neprekinljivoCakaj(zakasnitevSpletnega) }
        return try spletniOdgovor.get()
    }
}

@MainActor
final class SkenSejaTests: XCTestCase {
    private var mapa: URL!
    private let kljuc = Curve25519.Signing.PrivateKey()
    private let dogodek = SkenDogodek(id: 42, title: "Noc")

    override func setUp() async throws { mapa = Pomoc.zacasnaMapa() }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: mapa) }

    private func naredi(_ api: LazniApi, klub: Int = 1, deviceId: String = "naprava-1", rok: Double = 1.0, rokSpletni: Double = 1.0,
                        kljucOdmik: Double = 0) -> SkenSeja {
        // Nova vrsta z diska = nov zagon aplikacije (vsaka seja prebere vrsto in lokalne skene znova z diska).
        let disk = SkenDisk(mapa: mapa)
        let s = SkenSeja(klubId: klub, uporabnikId: 7, api: api, disk: disk, deviceId: deviceId, vrsta: SkenVrsta(disk: disk),
                         rokStreznika: rok, rokSpletni: rokSpletni, kljucOdmik: kljucOdmik)
        s.zeton = { "zeton" }
        return s
    }

    private func api(vstopnice: [ScanListTicket]) -> LazniApi {
        LazniApi(kljuc: Pomoc.scanKey(kljuc), seznam: ScanList(eventId: 42, generatedAt: "2026-10-01T20:00:00Z", kid: "kid1", tickets: vstopnice))
    }

    private func zdaj() -> Date { Date() }

    func testZelenoTakojInDvojniSkenJeRdece() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, isVip: true, tableLabel: "T1", packageName: "Jameson", holderUsername: "ana")])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }   // streznik ni dosegljiv
        let seja = naredi(a)
        await seja.odpri(dogodek)
        XCTAssertEqual(seja.priprava, .pripravljen)

        let qr = Pomoc.koda(kljuc, serial: s1, event: 42)
        let p1 = await seja.skeniraj(qr)
        XCTAssertEqual(p1.barva, .zeleno)
        XCTAssertNotNil(p1.vip)
        XCTAssertEqual(p1.podnaslov, "ana")
        XCTAssertEqual(seja.cakajoce, 1)    // v vrsti, streznika ni bilo treba cakati

        let p2 = await seja.skeniraj(qr)
        XCTAssertEqual(p2.barva, .rdece)    // dvojni sken na isti napravi
        XCTAssertEqual(seja.cakajoce, 1)    // drugi sken ne gre v vrsto
        XCTAssertEqual(seja.sprejeti, 1)
        XCTAssertEqual(seja.zavrnjeni, 1)
    }

    // MARK: K2: dvojen vstop, ko sta oba vratarja ONLINE

    /// Pred popravkom: online sken je bil zelen takoj, `already_used` je prisel sele pozneje kot »konflikt«, gost pa je ze sel noter.
    func testOnlineStreznikRecheAlreadyUsedJeRdeceInNiKonflikta() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, holderUsername: "ana")])
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "already_used", usedAt: "2026-10-01T20:59:00.000Z") }) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, String(localized: "ALREADY SCANNED"))
        XCTAssertEqual(seja.cakajoce, 0)          // gost ni bil spuscen: vnos ne ostane v vrsti
        XCTAssertEqual(seja.konflikti.count, 0)   // in ni konflikt
        XCTAssertEqual(seja.sprejeti, 0)
        XCTAssertEqual(seja.zavrnjeni, 1)
    }

    func testOnlineOkJeZelenoSTemIstimClientScanId() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, holderUsername: "ana")])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let qr = Pomoc.koda(kljuc, serial: s1, event: 42)
        let p = await seja.skeniraj(qr)
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertNil(p.opomba)
        XCTAssertEqual(seja.cakajoce, 0)          // streznik je potrdil: vnos je odstranjen
        XCTAssertEqual(a.paketi.count, 1)         // ENA zahteva, takoj ob skenu (ne ob naslednjem tiku)
        XCTAssertEqual(a.paketi[0].count, 1)
        XCTAssertEqual(a.paketi[0][0].qr, qr)
        XCTAssertEqual(seja.sprejeti, 1)
        XCTAssertFalse(seja.preverjaNaStrezniku)
    }

    func testOnlineVsiDokoncniOdgovoriStreznikaSoRdeci() async {
        let a = api(vstopnice: [])
        var odgovor = "ok"
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: odgovor, usedAt: nil) }) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let rdeci = ["already_used", "transferred", "refunded", "void", "unpaid", "invalid", "wrong_club", "unknown"]
        for r in rdeci {
            odgovor = r
            let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
            XCTAssertEqual(p.barva, .rdece, "rezultat \(r)")
        }
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertEqual(seja.konflikti.count, 0)
        XCTAssertEqual(seja.sprejeti, 0)
        XCTAssertEqual(seja.zavrnjeni, rdeci.count)
        XCTAssertEqual(a.paketi.count, rdeci.count)
    }

    /// Streznik gosta ni spustil -> koda ni »porabljena« lokalno: naslednji sken spet vpraša streznik (npr. po tem ko vratar uredi napako).
    func testStreznikovoRdeceNeZapreKodeLokalno() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        var odgovor = "unpaid"
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: odgovor) }) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let qr = Pomoc.koda(kljuc, serial: s1, event: 42)
        let prvi = await seja.skeniraj(qr)
        XCTAssertEqual(prvi.barva, .rdece)
        odgovor = "ok"
        let drugi = await seja.skeniraj(qr)
        XCTAssertEqual(drugi.barva, .zeleno)
        XCTAssertEqual(a.paketi.count, 2)
        XCTAssertNotEqual(a.paketi[0][0].clientScanId, a.paketi[1][0].clientScanId)
    }

    /// Rok ~2 s (tu 0,2 s): streznik ne odgovori -> velja lokalna sodba, vnos ostane v vrsti in se poslje pozneje (isti client_scan_id).
    func testOnlineRokPoteceVelaLokalnaSodbaInNeBlokira() async {
        let s1 = Pomoc.serial(), s2 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1), ScanListTicket(serial: s2)])
        a.zakasnitevPaketa = 10
        let seja = naredi(a, rok: 0.2)
        await seja.odpri(dogodek)
        let zacetek = Date()
        let p1 = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        let p2 = await seja.skeniraj(Pomoc.koda(kljuc, serial: s2, event: 42))
        let trajanje = Date().timeIntervalSince(zacetek)
        XCTAssertEqual(p1.barva, .zeleno)
        XCTAssertEqual(p2.barva, .zeleno)
        XCTAssertTrue(trajanje < 3, "dva skena sta cakala \(trajanje) s (rok 0,2 s, zakasnitev streznika 10 s)")
        XCTAssertEqual(seja.cakajoce, 2)
        XCTAssertEqual(seja.sprejeti, 2)
        XCTAssertFalse(seja.preverjaNaStrezniku)
        // streznik spet odgovarja: vrsta se poslje z ISTIMI client_scan_id (idempotentnost), nic ne ostane
        let vVrsti = Set(SkenVrsta(disk: SkenDisk(mapa: mapa)).vnosi.map { $0.clientScanId })
        XCTAssertEqual(vVrsti.count, 2)
        a.zakasnitevPaketa = 0
        await seja.pocakajPosiljanje()   // morebitno ozadnje posiljanje, ki ga je sprozil drugi sken
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertTrue(vVrsti.isSubset(of: Set(a.paketi.flatMap { $0 }.map { $0.clientScanId })))
        XCTAssertEqual(Set(a.paketi.flatMap { $0 }.map { $0.clientScanId }), vVrsti)   // nobenih tujih id-jev: isti client_scan_id
    }

    func testOnlineNapakaStreznikaVelaLokalnaSodba() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        a.paketOdgovor = { _ in .failure(APIError.requestFailed(503, "")) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(seja.cakajoce, 1)
        XCTAssertFalse(seja.povezava)
    }

    func testOnlineErrorRezultatVelaLokalnaSodbaVnosOstane() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, result: "error") }) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(seja.cakajoce, 1)
    }

    /// P3: brez povezave »ni na seznamu« ostane zeleno z opombo; z povezavo odloci streznik.
    func testNiNaSeznamuBrezPovezaveZelenoZOpombo() async {
        let a = api(vstopnice: [])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        seja.omrezjeSpremenjeno(gor: false)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertNotNil(p.opomba)
    }

    func testNiNaSeznamuZPovezavoOdlociStreznik() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let kupljena = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))   // streznik: ok
        XCTAssertEqual(kupljena.barva, .zeleno)
        XCTAssertNil(kupljena.opomba)                                                              // streznik je potrdil, opombe ni
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, result: "unknown") }) }
        let neznana = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(neznana.barva, .rdece)
    }

    func testPoslanoInDvojniSkenPoSinhronizacijiOstaneRdec() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let qr = Pomoc.koda(kljuc, serial: s1, event: 42)
        _ = await seja.skeniraj(qr)
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertEqual(a.paketi.flatMap { $0 }.count, 1)
        XCTAssertEqual(a.deviceIdji.first, "naprava-1")
        XCTAssertNotNil(UUID(uuidString: a.paketi[0][0].clientScanId))
        XCTAssertEqual(a.paketi[0][0].qr, qr)
        // seznam se se ni osvezil (vstopnica na njem je se `valid`), a lokalni zapis drzi
        let p = await seja.skeniraj(qr)
        XCTAssertEqual(p.barva, .rdece)
    }

    func testAlreadyUsedOdStreznikaPoSinhronizacijiPostaneKonflikt() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, holderUsername: "ana")])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        seja.omrezjeSpremenjeno(gor: false)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))   // brez povezave: zeleno, gost gre noter
        XCTAssertEqual(p.barva, .zeleno)
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "already_used", usedAt: "2026-10-01T20:59:00.000Z") }) }
        seja.omrezjeSpremenjeno(gor: true)
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertEqual(seja.konflikti.count, 1)
        XCTAssertEqual(seja.konflikti[0].result, "already_used")
        XCTAssertEqual(seja.konflikti[0].imetnik, "ana")
        seja.potrdiKonflikt(seja.konflikti[0])
        XCTAssertEqual(seja.konflikti.count, 0)
    }

    func testBrezPovezaveVrstaOstaneInSePosljeKoSeVrne() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        var padi = true
        a.paketOdgovor = { v in
            padi ? .failure(URLError(.notConnectedToInternet)) : .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") })
        }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 1)
        XCTAssertFalse(seja.povezava)
        padi = false
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertTrue(seja.povezava)
        // ponovni poskus poslje ISTI client_scan_id (idempotentnost na strezniku), ne nov
        XCTAssertGreaterThanOrEqual(a.paketi.count, 2)
        XCTAssertEqual(Set(a.paketi.flatMap { $0 }.map { $0.clientScanId }).count, 1)
    }

    /// M12: preklic klica (zaslon izgine) ni izpad povezave: indikator ostane »Online«, vnos ostane v vrsti.
    func testPreklicKlicaNiOffline() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        a.paketOdgovor = { _ in .failure(URLError(.cancelled)) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertTrue(seja.povezava)
        XCTAssertEqual(seja.cakajoce, 1)
    }

    func testOdprtjeBrezPovezaveSShranjenimSeznamom() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let prva = naredi(a)
        await prva.odpri(dogodek)                 // prenese in shrani
        XCTAssertNotNil(prva.zadnjiPrenos)

        let brez = api(vstopnice: [])
        brez.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let druga = naredi(brez)                    // nova seja = ponovni zagon aplikacije, brez povezave
        await druga.odpri(dogodek)
        XCTAssertEqual(druga.priprava, .pripravljen)
        XCTAssertFalse(druga.povezava)
        let p = await druga.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(druga.cakajoce, 1)

        // vrsta in lokalni skeni prezivijo zaprtje aplikacije
        let tretja = naredi(brez)
        await tretja.odpri(dogodek)
        XCTAssertEqual(tretja.cakajoce, 1)
        let ponovno = await tretja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(ponovno.barva, .rdece)
    }

    func testBrezPovezaveInBrezShrambeJeManjkaPodatkov() async {
        let a = api(vstopnice: [])
        a.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        a.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(a)
        await seja.odpri(dogodek)
        guard case .manjkaPodatkov = seja.priprava else { return XCTFail("pricakovan manjkaPodatkov, dobljeno \(seja.priprava)") }
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(p.barva, .rumeno)
        XCTAssertFalse(p.ponudiVstop)             // v2 brez kljuca ni mogoce spustiti na slepo (P4: »Let in« samo za v1)
        XCTAssertTrue(a.spletniKlici.isEmpty)      // brez povezave nobenega spletnega klica
    }

    /// P4: kljuc je globalen: prenesen za en dogodek, velja za vse (pred popravkom je bil kljuc na dogodek).
    func testKljucJeGlobalenInDelaZaDrugDogodekBrezSeznama() async {
        let a = api(vstopnice: [])
        let prva = naredi(a)
        await prva.odpri(dogodek)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mapa.appendingPathComponent(SkenDisk.imeKljuca).path))

        let brez = api(vstopnice: [])
        brez.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let druga = naredi(brez)
        await druga.odpri(SkenDogodek(id: 77, title: "Drug dogodek"))   // seznama za ta dogodek ni, kljuc pa je
        XCTAssertEqual(druga.priprava, .pripravljen)
        let dobra = await druga.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 77))
        XCTAssertEqual(dobra.barva, .zeleno)
        let napacenDogodek = await druga.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(napacenDogodek.barva, .rdece)
        let ponaredek = await druga.skeniraj(Pomoc.koda(Curve25519.Signing.PrivateKey(), serial: Pomoc.serial(), event: 77))
        XCTAssertEqual(ponaredek.barva, .rdece)
    }

    func testStaraKodaBrezPovezaveJeRumenaSPovezavoGreNaStreznik() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let v1 = Pomoc.kodaV1(serial: Pomoc.serial(), event: 42)

        // s povezavo: obstojec POST /scan
        let online = await seja.skeniraj(v1)
        XCTAssertEqual(online.barva, .zeleno)
        XCTAssertEqual(a.spletniKlici, [v1])
        XCTAssertEqual(seja.cakajoce, 0)
        // isto kodo brez povezave: ze skenirana na tej napravi
        seja.omrezjeSpremenjeno(gor: false)
        let ponovnoV1 = await seja.skeniraj(v1)
        XCTAssertEqual(ponovnoV1.barva, .rdece)

        // druga stara koda brez povezave: rumeno, vratar odloci
        let v1b = Pomoc.kodaV1(serial: Pomoc.serial(), event: 42)
        let rumena = await seja.skeniraj(v1b)
        XCTAssertEqual(rumena.barva, .rumeno)
        XCTAssertTrue(rumena.ponudiVstop)
        XCTAssertEqual(seja.cakajoce, 0)           // aplikacija ne spusti samodejno
        XCTAssertEqual(a.spletniKlici.count, 1)
        let spuscen = seja.spustiRocno(qr: v1b)
        XCTAssertEqual(spuscen.barva, .zeleno)
        XCTAssertEqual(seja.cakajoce, 1)
        let ponovnoV1b = await seja.skeniraj(v1b)
        XCTAssertEqual(ponovnoV1b.barva, .rdece)
    }

    /// P4: »Let in« samo za veljavno obliko v1 za TA dogodek; v2 (brez kljuca/z neujemajocim kljucem), smeti in drug dogodek se zavrnejo.
    func testSpustiRocnoSamoZaV1ZaTaDogodek() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        XCTAssertEqual(seja.spustiRocno(qr: Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42)).barva, .rdece)   // v2
        XCTAssertEqual(seja.spustiRocno(qr: "abc.def").barva, .rdece)
        XCTAssertEqual(seja.spustiRocno(qr: "e30.0123456789abcdef").barva, .rdece)
        XCTAssertEqual(seja.spustiRocno(qr: Pomoc.kodaV1(serial: Pomoc.serial(), event: 9)).barva, .rdece)        // drug dogodek
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertEqual(seja.spustiRocno(qr: Pomoc.kodaV1(serial: Pomoc.serial(), event: 42)).barva, .zeleno)
        XCTAssertEqual(seja.cakajoce, 1)
    }

    /// P6: spletni sken ima kratek rok; Wi-Fi brez interneta ne sme zadrzati vrat 30 s. Ob roku: rumeno z »Let in«.
    func testSpletniSkenImaKratekRokInPadeNaRumeno() async {
        let a = api(vstopnice: [])
        a.zakasnitevSpletnega = 10
        let seja = naredi(a, rokSpletni: 0.2)
        await seja.odpri(dogodek)
        let zacetek = Date()
        let p = await seja.skeniraj(Pomoc.kodaV1(serial: Pomoc.serial(), event: 42))
        XCTAssertTrue(Date().timeIntervalSince(zacetek) < 3)
        XCTAssertEqual(p.barva, .rumeno)
        XCTAssertTrue(p.ponudiVstop)
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertFalse(seja.preverjaNaStrezniku)
    }

    func testPrenesenaInNapacenDogodekSkoziSejo() async {
        let s1 = Pomoc.serial()
        let a = LazniApi(kljuc: Pomoc.scanKey(kljuc), seznam: ScanList(eventId: 42, kid: "kid1", tickets: [], transferredSerials: [s1]))
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let prenesena = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        let drugDogodek = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 5))
        XCTAssertEqual(prenesena.barva, .rdece)
        XCTAssertEqual(drugDogodek.barva, .rdece)
        XCTAssertEqual(seja.cakajoce, 0)
    }

    func testNeplacanaVstopnicaJeRdecaSkoziSejo() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, status: "unpaid")])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, String(localized: "NOT PAID"))
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertTrue(a.paketi.isEmpty)   // rdece se odloci lokalno, streznika ni treba vprasati
    }

    func testSpremenjenKidPonovnoPrenesePodpisniKljuc() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        // streznik zamenja skrivnost -> nov par in nov kid
        let novi = Curve25519.Signing.PrivateKey()
        a.kljucOdgovor = .success(Pomoc.scanKey(novi, kid: "kid2"))
        a.nastaviSeznam(ScanList(eventId: 42, kid: "kid2", tickets: [ScanListTicket(serial: s1)]))
        await seja.osveziSeznam()
        let noviSken = await seja.skeniraj(Pomoc.koda(novi, serial: s1, event: 42, kid: "kid2"))
        XCTAssertEqual(noviSken.barva, .zeleno)
        // koda s starim kljucem (drug kid) ni ponaredek, ampak zastarela: rumeno, ne rdece (M10)
        a.spletniOdgovor = .failure(URLError(.timedOut))
        let stariSken = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(stariSken.barva, .rumeno)
        XCTAssertEqual(a.spletniKlici.count, 1)   // z povezavo najprej poskusi streznik
    }

    /// M10: koda z novim `kid`, kljuca na telefonu pa ni mogoce osveziti: rumeno (ne rdece); ko se kljuc prenese, je koda zelena.
    func testNovKidBrezMoznostiPrenosaKljucaNeDaNapacnegaRdecega() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        a.kljucOdgovor = .failure(URLError(.timedOut))
        a.nastaviSeznam(ScanList(eventId: 42, kid: "kid2", tickets: [ScanListTicket(serial: s1)]))
        await seja.osveziSeznam()
        a.spletniOdgovor = .failure(URLError(.timedOut))   // tudi spletni sken ne uspe
        let novi = Curve25519.Signing.PrivateKey()
        let koda = Pomoc.koda(novi, serial: s1, event: 42, kid: "kid2")
        let p = await seja.skeniraj(koda)
        XCTAssertEqual(p.barva, .rumeno)           // ne rdece: koda je lahko pristna
        XCTAssertEqual(p.naslov, String(localized: "KEY OUTDATED"))
        XCTAssertFalse(p.ponudiVstop)
        // povezava se vrne, kljuc se prenese: ista koda je zelena
        a.kljucOdgovor = .success(Pomoc.scanKey(novi, kid: "kid2"))
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        seja.omrezjeSpremenjeno(gor: false)
        _ = await seja.osveziKljuc()
        let zdajKoda = await seja.skeniraj(koda)
        XCTAssertEqual(zdajKoda.barva, .zeleno)
    }

    /// Neuspel prenos kljuca se ne ponavlja vsako sekundo (vsak sken z zastarelim kljucem sprozi poskus): najmanj 20 s med poskusi.
    func testNeuspelPrenosKljucaSePonoviNajprejCez20s() async {
        let a = api(vstopnice: [])
        a.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(a, kljucOdmik: 20)
        await seja.odpri(dogodek)       // en poskus
        _ = await seja.osveziKljuc()
        _ = await seja.osveziKljuc()
        XCTAssertEqual(a.kljucKlici, 1)
    }

    func testDogodkiSeShranijoInPonujajoPravePrihajajoce() async {
        let a = api(vstopnice: [])
        let zdaj = Date()
        func iso(_ ure: Double) -> String { SkenCas.niz(zdaj.addingTimeInterval(ure * 3600)) }
        a.dogodkiOdgovor = .success([
            SkenDogodek(id: 1, title: "Jutri", startAt: iso(24)),
            SkenDogodek(id: 2, title: "Osnutek", startAt: iso(5), status: "draft"),
            SkenDogodek(id: 3, title: "Davno", startAt: iso(-72), endAt: iso(-66), status: "published", lifecycle: "ended"),
            SkenDogodek(id: 4, title: "Zdaj", startAt: iso(-2), status: "published", lifecycle: "live"),
        ])
        let prva = naredi(a)
        await prva.naloziDogodke()
        XCTAssertEqual(prva.ponujeniDogodki.map { $0.id }, [4, 1])

        let brez = api(vstopnice: [])
        brez.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        let druga = naredi(brez)
        await druga.naloziDogodke()   // brez povezave: shranjen seznam
        XCTAssertEqual(druga.ponujeniDogodki.map { $0.id }, [4, 1])
        XCTAssertNil(druga.dogodkiNapaka)
    }

    // MARK: Pregled tipov PR #45 (2. krog)

    /// Kriticno 1: delo, ki preklica ne upostevajo (send() ob 401 caka nestrukturiran refreshAccessToken, Supabase rok 30 s), ne smejo
    /// zadrzati vrat. Pred popravkom je withTaskGroup cakal na vse otroke: sken je trajal toliko kot pocasen streznik.
    func testPocasenKlicKiPreklicaNeUpostevaNeZadrziVrat() async {
        let s1 = Pomoc.serial(), s2 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1), ScanListTicket(serial: s2)])
        a.zakasnitevPaketa = 3
        let seja = naredi(a, rok: 0.2)
        await seja.odpri(dogodek)
        let zacetek = Date()
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        let trajanje = Date().timeIntervalSince(zacetek)
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertTrue(trajanje < 1.5, "sken je cakal \(trajanje) s (rok 0,2 s)")
        XCTAssertEqual(seja.cakajoce, 1)
    }

    func testPocasenSpletniSkenKiPreklicaNeUpostevaNeZadrziVrat() async {
        let a = api(vstopnice: [])
        a.zakasnitevSpletnega = 3
        let seja = naredi(a, rokSpletni: 0.2)
        await seja.odpri(dogodek)
        let zacetek = Date()
        let p = await seja.skeniraj(Pomoc.kodaV1(serial: Pomoc.serial(), event: 42))
        let trajanje = Date().timeIntervalSince(zacetek)
        XCTAssertEqual(p.barva, .rumeno)
        XCTAssertTrue(trajanje < 1.5, "spletni sken je cakal \(trajanje) s (rok 0,2 s)")
    }

    func testRokVrneNilBrezCakanjaNaOtroka() async {
        let zacetek = Date()
        let r = await SkenRok.zRokom(0.1) { () async throws -> Int in
            await LazniApi.neprekinljivoCakaj(2)
            return 1
        }
        XCTAssertNil(r)
        XCTAssertTrue(Date().timeIntervalSince(zacetek) < 1.0)
        // hitro delo vrne rezultat, napaka pride kot .failure
        let ok = await SkenRok.zRokom(2) { () async throws -> Int in 7 }
        if case .success(let v)? = ok { XCTAssertEqual(v, 7) } else { XCTFail("pricakovan uspeh") }
        let napaka = await SkenRok.zRokom(2) { () async throws -> Int in throw URLError(.timedOut) }
        if case .failure? = napaka {} else { XCTFail("pricakovana napaka") }
    }

    /// Kriticno 1 (odjava): SkenOdjava.poslji prav tako ne sme cakati na pocasen klic.
    func testOdjavaNeCakaNaPocasenKlic() async {
        let disk = SkenDisk(mapa: mapa)
        let vrsta = SkenVrsta.deljena(disk)
        vrsta.dodaj(SkenVnos(qr: "o2.x.y", serial: Pomoc.serial(), eventId: 42, klubId: 3, uporabnikId: 7))
        let a = api(vstopnice: [])
        a.zakasnitevPaketa = 3
        let zacetek = Date()
        await SkenOdjava.poslji(token: "zeton", uporabnikId: 7, api: a, disk: disk, rok: 0.2, deviceId: "naprava-1")
        XCTAssertTrue(Date().timeIntervalSince(zacetek) < 1.5)
        XCTAssertEqual(vrsta.vnosi.count, 1)   // vnos ostane
    }

    /// Pomembno 4: po izteku roka se naslednji skeni ne cakajo vsak po 2 s; uspesen periodicen klic povezavo povrne.
    func testPoRokuNaslednjiSkeniNeCakajoZnova() async {
        let s1 = Pomoc.serial(), s2 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1), ScanListTicket(serial: s2)])
        a.zakasnitevPaketa = 2
        let seja = naredi(a, rok: 0.3)
        await seja.odpri(dogodek)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))   // rok poteces
        XCTAssertFalse(seja.povezava)
        let zacetek = Date()
        let p2 = await seja.skeniraj(Pomoc.koda(kljuc, serial: s2, event: 42))
        XCTAssertEqual(p2.barva, .zeleno)
        XCTAssertTrue(Date().timeIntervalSince(zacetek) < 0.15, "drugi sken je cakal na streznik")
        // streznik spet odgovarja: periodicno posiljanje uspe in povezava je spet gor
        a.zakasnitevPaketa = 0
        await seja.pocakajPosiljanje()
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertTrue(seja.povezava)
    }

    /// Pomembno 2: backend requireClub z IZRECNIM klubom za nepoznavalca vrne 404 »Club not found.« (ne 403): M13 mora delovati na to.
    func testOdvzemDostopaSeSprozi404ClubNotFound() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.naloziDogodke()
        await seja.odpri(dogodek)
        a.seznamOdgovor = .failure(APIError.requestFailed(404, "Club not found."))
        await seja.osveziSeznam()
        XCTAssertTrue(seja.dostopOdvzet)
        let imena = Set(SkenDisk(mapa: mapa).imena())
        XCTAssertFalse(imena.contains(SkenDisk.imeSeznama(klub: 1, dogodek: 42)))
        // JSON oblika istega odgovora (scan-list, scan-batch)
        let b = api(vstopnice: [])
        let seja2 = naredi(b)
        await seja2.odpri(dogodek)
        b.seznamOdgovor = .failure(APIError.requestFailed(404, #"{"error":"not_found","message":"Club not found."}"#))
        await seja2.osveziSeznam()
        XCTAssertTrue(seja2.dostopOdvzet)
    }

    func testOstaleNapakeNisoOdvzemDostopa() {
        XCTAssertTrue(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(404, "Club not found.")))
        XCTAssertTrue(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(403, "Forbidden.")))
        XCTAssertFalse(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(403, "Email not verified.")))
        XCTAssertFalse(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(403, "Your role in the club does not allow this.")))
        XCTAssertFalse(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(404, #"{"error":"not_found","message":"Event not found."}"#)))
        XCTAssertFalse(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(401, "Invalid token.")))
        XCTAssertFalse(SkenSeja.jeOdvzemDostopaNapaka(APIError.requestFailed(503, "Auth service unavailable.")))
        XCTAssertFalse(SkenSeja.jeOdvzemDostopaNapaka(URLError(.notConnectedToInternet)))
    }

    /// Pomembno 2: ko streznik pove, da dostopa ni vec, hitra pot ne sme dati lokalnega zelenega; vrsta se ne poskusa vec poslati.
    func testHitraPot404NeDaZelenegaInOdvzameDostop() async {
        let s1 = Pomoc.serial(), s2 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1), ScanListTicket(serial: s2)])
        a.paketOdgovor = { _ in .failure(APIError.requestFailed(404, "Club not found.")) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertTrue(seja.dostopOdvzet)
        XCTAssertEqual(seja.cakajoce, 0)          // gost ni bil spuscen: vnos ne ostane
        // naslednji skeni so rdeci brez vprasanja streznika
        let stevilo = a.paketi.count
        let p2 = await seja.skeniraj(Pomoc.koda(kljuc, serial: s2, event: 42))
        XCTAssertEqual(p2.barva, .rdece)
        XCTAssertEqual(a.paketi.count, stevilo)
    }

    func testPoslanjeVrsteVNedogledSeKonca404() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(seja.cakajoce, 1)
        a.paketOdgovor = { _ in .failure(APIError.requestFailed(404, "Club not found.")) }
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertTrue(seja.dostopOdvzet)
        XCTAssertEqual(seja.cakajoce, 1)           // vnos ostane na disku
        let stevilo = a.paketi.count
        await seja.poslji()
        XCTAssertEqual(a.paketi.count, stevilo)    // in se ne posilja vec
    }

    /// Manjse 13: osvezitev za drug dogodek ne sme pobrisati oznake osvezitve, ki je ze tecla za zdajsnji dogodek (dvojen prenos).
    func testZakljucekOsvezitveDrugegaDogodkaNeOdklenePodvojenegaPrenosa() async throws {
        let a = api(vstopnice: [])
        a.zakasnitevSeznama = 0.4
        let seja = naredi(a)
        let ta = Task { await seja.odpri(SkenDogodek(id: 42, title: "A")) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let tb = Task { await seja.odpri(SkenDogodek(id: 43, title: "B")) }
        try await Task.sleep(nanoseconds: 350_000_000)     // A je koncal (0,4 s), B tece se do ~0,5 s
        await seja.osveziSeznam()                          // ne sme zagnati tretjega prenosa
        await ta.value
        await tb.value
        XCTAssertEqual(a.seznamKlici, 2)
    }

    /// Manjse 5: zeton ob odjavi velja samo za odjavljenega uporabnika: vnosov drugih racunov na isti napravi ne posilja.
    func testOdjavaPosljeSamoVnoseOdjavljenegaUporabnika() async {
        let disk = SkenDisk(mapa: mapa)
        let vrsta = SkenVrsta.deljena(disk)
        let moj = SkenVnos(qr: "o2.moj.y", serial: Pomoc.serial(), eventId: 42, klubId: 3, uporabnikId: 7)
        let tuj = SkenVnos(qr: "o2.tuj.y", serial: Pomoc.serial(), eventId: 42, klubId: 3, uporabnikId: 99)
        let tujKlub = SkenVnos(qr: "o2.tuj2.y", serial: Pomoc.serial(), eventId: 5, klubId: 8, uporabnikId: 99)
        [moj, tuj, tujKlub].forEach { vrsta.dodaj($0) }
        let a = api(vstopnice: [])
        await SkenOdjava.poslji(token: "zeton", uporabnikId: 7, api: a, disk: disk, rok: 2, deviceId: "naprava-1")
        XCTAssertEqual(a.paketi.flatMap { $0 }.map { $0.qr }, ["o2.moj.y"])
        XCTAssertEqual(a.klubIdji, [3])
        XCTAssertEqual(Set(vrsta.vnosi.map { $0.qr }), ["o2.tuj.y", "o2.tuj2.y"])
    }

    func testKonfliktiSoPoUporabniku() {
        let vrsta = SkenVrsta(disk: SkenDisk(mapa: mapa))
        let a = SkenVnos(clientScanId: "a", qr: "x", serial: Pomoc.serial(), eventId: 1, klubId: 1, uporabnikId: 7, imetnik: "ana")
        let b = SkenVnos(clientScanId: "b", qr: "y", serial: Pomoc.serial(), eventId: 1, klubId: 1, uporabnikId: 99, imetnik: "bojan")
        vrsta.dodaj(a); vrsta.dodaj(b)
        vrsta.uporabi([ScanBatchResult(clientScanId: "a", result: "already_used"), ScanBatchResult(clientScanId: "b", result: "already_used")], poslani: [a, b])
        XCTAssertEqual(vrsta.nepotrjeniKonflikti(klub: 1, uporabnik: 7).map { $0.imetnik }, ["ana"])
        XCTAssertEqual(vrsta.nepotrjeniKonflikti(klub: 1, uporabnik: 99).map { $0.imetnik }, ["bojan"])
        XCTAssertEqual(vrsta.nepotrjeniKonflikti(klub: 1).count, 2)
        // prezivi zagon (uporabnikId je v zapisu)
        XCTAssertEqual(SkenVrsta(disk: SkenDisk(mapa: mapa)).nepotrjeniKonflikti(klub: 1, uporabnik: 7).map { $0.imetnik }, ["ana"])
    }

    /// Manjse 8, 9: ob odjavi gre vse; tudi pokvarjene datoteke in predpomnilnik odgovorov (scan-list z imeni imetnikov).
    /// Lasten URLCache samo v pomnilniku (brez diska): test ne deli stanja z URLCache.shared (slike, drugi testi) in ne zavisi od
    /// asinhronega diskovnega brisanja (prej obcasno rdec: shranjen odgovor je po removeAllCachedResponses se obstajal).
    func testOdjavaBrisePokvarjeneDatotekeInPredpomnilnik() throws {
        let disk = SkenDisk(mapa: mapa)
        disk.shraniPokvarjeno("vrsta", Data("{ pokvarjeno".utf8))
        disk.shraniPokvarjeno("konflikti", Data("{ pokvarjeno".utf8))
        let predpomnilnik = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let url = URL(string: "https://outly.example/business/events/42/scan-list")!
        let zahteva = URLRequest(url: url)
        let odgovor = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
        predpomnilnik.storeCachedResponse(CachedURLResponse(response: odgovor, data: Data("{}".utf8)), for: zahteva)
        XCTAssertNotNil(predpomnilnik.cachedResponse(for: zahteva))
        XCTAssertTrue(disk.imena().contains { $0.contains(".pokvarjena-") })
        SkenOdjava.pocisti(disk: disk, predpomnilniki: [predpomnilnik])
        XCTAssertFalse(disk.imena().contains { $0.contains(".pokvarjena-") })
        XCTAssertNil(predpomnilnik.cachedResponse(for: zahteva))
    }

    /// Klici backenda ne smejo pisati odgovorov (imena imetnikov, vstopnice) na disk: API seja ima predpomnilnik samo v pomnilniku.
    func testApiSejaNimaDiskovnegaPredpomnilnika() {
        XCTAssertEqual(APIPredpomnilnik.predpomnilnik.diskCapacity, 0)
        XCTAssertTrue(APIPredpomnilnik.seja.configuration.urlCache === APIPredpomnilnik.predpomnilnik)
    }

    // MARK: M7: klub izrecno v vsakem klicu

    func testVsakKlicNosiIzrecenKlub() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a, klub: 5)
        await seja.naloziDogodke()
        await seja.odpri(dogodek)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        _ = await seja.skeniraj(Pomoc.kodaV1(serial: Pomoc.serial(), event: 42))
        await seja.poslji()
        XCTAssertTrue(a.klubIdji.count >= 5)   // dogodki, kljuc, seznam, paket, spletni sken
        XCTAssertEqual(Set(a.klubIdji.map { $0 ?? -1 }), [5])
        // klub 0 (ni znan): glava se ne poslje
        let b = api(vstopnice: [])
        let brezKluba = naredi(b, klub: 0)
        await brezKluba.odpri(dogodek)
        XCTAssertEqual(Set(b.klubIdji.map { $0 ?? -1 }), [-1])
    }

    // MARK: M8: nespremenjen seznam

    func testNespremenjenSeznamSeNeZapisujeZnova() async throws {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let datoteka = mapa.appendingPathComponent(SkenDisk.imeSeznama(klub: 1, dogodek: 42))
        XCTAssertTrue(FileManager.default.fileExists(atPath: datoteka.path))
        try Data("marker".utf8).write(to: datoteka)
        let prej = seja.zadnjiPrenos
        try await Task.sleep(nanoseconds: 20_000_000)
        await seja.osveziSeznam()   // isti odgovor
        XCTAssertEqual(try String(contentsOf: datoteka, encoding: .utf8), "marker")   // ni bil ponovno zapisan
        XCTAssertTrue((seja.zadnjiPrenos ?? .distantPast) > (prej ?? .distantFuture))     // cas prenosa se je osvezil
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))           // indeks je ostal
        XCTAssertEqual(p.barva, .zeleno)
        // spremenjen odgovor se zapise
        a.nastaviSeznam(ScanList(eventId: 42, kid: "kid1", tickets: [ScanListTicket(serial: s1), ScanListTicket(serial: Pomoc.serial())]))
        await seja.osveziSeznam()
        XCTAssertNotEqual(try String(contentsOf: datoteka, encoding: .utf8), "marker")
    }

    // MARK: M9: pokvarjen odgovor obdrzi stari seznam

    func testPokvarjenOdgovorSeznamaObdrziStariSeznam() async {
        let s1 = Pomoc.serial()
        let a = LazniApi(kljuc: Pomoc.scanKey(kljuc), seznam: ScanList(eventId: 42, kid: "kid1", tickets: [], transferredSerials: [s1]))
        let seja = naredi(a)
        await seja.odpri(dogodek)
        a.seznamOdgovor = .success(Data(#"{"event_id":42,"tickets":"pokvarjeno"}"#.utf8))
        await seja.osveziSeznam()
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .rdece)   // vstopnica je se vedno »prenesena«, praznega seznama ni
        // tudi na disku je ostal star seznam
        let druga = naredi(a)
        a.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        await druga.odpri(dogodek)
        let p2 = await druga.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p2.barva, .rdece)
    }

    // MARK: M11: starost seznama

    func testSvezSeznamNiStarInUspesnoOsvezevanjeBrisePogoj() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        XCTAssertFalse(seja.seznamStar)
        XCTAssertNotNil(seja.zadnjiPrenos)
    }

    // MARK: M13: 403 in odjava

    func testOdvzemDostopaPrejPosljeNeposlanoNatoPobriseSezname() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, holderUsername: "ana")])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.naloziDogodke()
        await seja.odpri(dogodek)
        seja.omrezjeSpremenjeno(gor: false)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(seja.cakajoce, 1)
        await seja.poslji()                // neuspel poskus (ozadnji poskus ob skenu se konca skupaj z njim)
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 1)
        // povezava je spet tu, a streznik pravi 403 (ni vec clan ekipe): najprej poslji, kar caka, nato pobrisi sezname
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") }) }
        a.seznamOdgovor = .failure(APIError.requestFailed(404, "Club not found."))   // pravi odgovor requireClub za izrecen klub
        await seja.osveziSeznam()
        XCTAssertTrue(seja.dostopOdvzet)
        XCTAssertEqual(seja.cakajoce, 0)   // neposlano je bilo poslano pred brisanjem
        let imena = Set(SkenDisk(mapa: mapa).imena())
        XCTAssertFalse(imena.contains(SkenDisk.imeSeznama(klub: 1, dogodek: 42)))
        XCTAssertFalse(imena.contains(SkenDisk.imeLokalnih(klub: 1, dogodek: 42)))
        XCTAssertFalse(imena.contains(SkenDisk.imeDogodkov(klub: 1)))
        // brez dostopa se skeniranje ne poskusa vec poslati
        let stevilo = a.paketi.count
        await seja.poslji()
        XCTAssertEqual(a.paketi.count, stevilo)
    }

    func testOdvzemDostopaBrezPovezaveObdrziNeposlaneSkene() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        a.seznamOdgovor = .failure(APIError.requestFailed(404, "Club not found."))
        await seja.osveziSeznam()
        XCTAssertTrue(seja.dostopOdvzet)
        XCTAssertFalse(Set(SkenDisk(mapa: mapa).imena()).contains(SkenDisk.imeSeznama(klub: 1, dogodek: 42)))
        XCTAssertEqual(SkenVrsta(disk: SkenDisk(mapa: mapa)).vnosi.count, 1)   // vnos je se na disku
    }

    func testOdjavaPosljeNeposlanoInPobrisePodatke() async {
        let disk = SkenDisk(mapa: mapa)
        let vrsta = SkenVrsta.deljena(disk)
        vrsta.dodaj(SkenVnos(qr: "o2.x.y", serial: Pomoc.serial(), eventId: 42, klubId: 3, uporabnikId: 7, imetnik: "ana"))
        disk.zapisi(SkenLokalniSkeni(), SkenDisk.imeLokalnih(klub: 3, dogodek: 42))
        disk.zapisiSurovo(Data("{}".utf8), SkenDisk.imeSeznama(klub: 3, dogodek: 42))
        let a = api(vstopnice: [])
        await SkenOdjava.poslji(token: "zeton", uporabnikId: 7, api: a, disk: disk, rok: 2, deviceId: "naprava-1")
        XCTAssertEqual(vrsta.vnosi.count, 0)
        XCTAssertEqual(a.klubIdji, [3])        // vsak klub s svojo glavo
        SkenOdjava.pocisti(disk: disk, predpomnilniki: [])
        XCTAssertEqual(disk.imena().filter { $0 != "vrsta" }, [])
    }

    func testOdjavaBrezPovezaveObdrziVnosBrezImenaInPobrisePreostalo() async {
        let disk = SkenDisk(mapa: mapa)
        let vrsta = SkenVrsta.deljena(disk)
        let v = SkenVnos(qr: "o2.x.y", serial: Pomoc.serial(), eventId: 42, klubId: 3, uporabnikId: 7, imetnik: "ana")
        vrsta.dodaj(v)
        disk.zapisi(ScanKey(kid: "k", publicKey: "p"), SkenDisk.imeKljuca)
        disk.zapisiSurovo(Data("[]".utf8), SkenVrsta.datotekaKonfliktov)
        let a = api(vstopnice: [])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        await SkenOdjava.poslji(token: "zeton", uporabnikId: 7, api: a, disk: disk, rok: 2, deviceId: "naprava-1")
        XCTAssertEqual(vrsta.vnosi.count, 1)
        SkenOdjava.pocisti(disk: disk, predpomnilniki: [])
        XCTAssertEqual(disk.imena().filter { $0 != "vrsta" }, [])      // kljuc, konflikti, seznami so pobrisani
        let nova = SkenVrsta(disk: disk)                               // vnos prezivi, imena imetnika ni vec
        XCTAssertEqual(nova.vnosi.map { $0.clientScanId }, [v.clientScanId])
        XCTAssertNil(nova.vnosi.first?.imetnik)
        // brez zetona se ne poskusa nic
        let b = api(vstopnice: [])
        await SkenOdjava.poslji(token: "", uporabnikId: 7, api: b, disk: disk, rok: 2, deviceId: "x")
        XCTAssertTrue(b.paketi.isEmpty)
    }

    func testDeviceIdJeStalenPoNamestitviInNakljucen() {
        let ime = "outly.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: ime)!
        defer { d.removePersistentDomain(forName: ime) }
        let prvi = SkenNaprava.id(d)
        XCTAssertNotNil(UUID(uuidString: prvi))
        XCTAssertEqual(SkenNaprava.id(d), prvi)
        let drug = UserDefaults(suiteName: ime + ".b")!
        defer { drug.removePersistentDomain(forName: ime + ".b") }
        XCTAssertNotEqual(SkenNaprava.id(drug), prvi)
    }
}
