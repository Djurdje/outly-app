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

    /// Objavljen dogodek z zacetkom in koncem (konec nil = brez `endAt`).
    static func dogodek(_ id: Int, title: String = "Noc", zacetek: Date, konec: Date? = nil, status: String = "published") -> SkenDogodek {
        SkenDogodek(id: id, title: title, startAt: SkenCas.niz(zacetek), endAt: konec.map { SkenCas.niz($0) }, status: status)
    }

    /// Sedanji cas na cele sekunde: ISO niz z milisekundami zaokrozuje, zato bi se tocne meje okna sicer premaknile za delec ms.
    static func sedajNaSekundo() -> Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }

    /// Dogodek, ki traja zdaj (zacel pred uro, konec cez 5 ur).
    static func aktivenDogodek(_ id: Int, title: String = "Noc") -> SkenDogodek {
        dogodek(id, title: title, zacetek: Date().addingTimeInterval(-3600), konec: Date().addingTimeInterval(5 * 3600))
    }
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

    /// Placilo v sporu (backend#232): seznam ga vrne kot `unpaid` + `payment_disputed`; brez polja ostane genericni »neplacana«.
    func testPlaciloVSporuJeLocenoOdNeplacanega() {
        let spor = Pomoc.serial(), navadna = Pomoc.serial(), veljavnaVSporu = Pomoc.serial(), uporabljenaVSporu = Pomoc.serial()
        let vrnjenaVSporu = Pomoc.serial(), preklicanaVSporu = Pomoc.serial()
        let seznam = ScanList(eventId: dogodek, tickets: [
            ScanListTicket(serial: spor, status: "unpaid", paymentDisputed: true),
            ScanListTicket(serial: navadna, status: "unpaid"),
            ScanListTicket(serial: veljavnaVSporu, status: "valid", paymentDisputed: true),
            ScanListTicket(serial: uporabljenaVSporu, status: "used", usedAt: "2026-10-01T21:15:00.000Z", paymentDisputed: true),
            ScanListTicket(serial: vrnjenaVSporu, status: "refunded", paymentDisputed: true),
            ScanListTicket(serial: preklicanaVSporu, status: "void", paymentDisputed: true),
        ])
        let r = odloci(Pomoc.koda(kljuc, serial: spor, event: dogodek), seznam: seznam)
        XCTAssertEqual(r.razlog, .placiloVSporu)
        XCTAssertEqual(r.barva, .rdece)
        XCTAssertFalse(r.spusti)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: navadna, event: dogodek), seznam: seznam).razlog, .neplacana)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: veljavnaVSporu, event: dogodek), seznam: seznam).razlog, .placiloVSporu)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: uporabljenaVSporu, event: dogodek), seznam: seznam).razlog, .zeUporabljena)
        // refunded / void ostaneta, kar sta, tudi ce ima vstopnica se oznako spora
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: vrnjenaVSporu, event: dogodek), seznam: seznam).razlog, .vrnjena)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: preklicanaVSporu, event: dogodek), seznam: seznam).razlog, .preklicana)
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

// MARK: - Casovno okno (8. 10. 2026: vratar ne izbira dogodka)

@MainActor
final class SkenOknoTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let ura: TimeInterval = 3600

    private func dogodek(_ zacetek: Date, konec: Date? = nil, status: String = "published") -> SkenDogodek {
        Pomoc.dogodek(1, zacetek: zacetek, konec: konec, status: status)
    }

    func testKonstanteSo12UrPredIn6UrPo() {
        XCTAssertEqual(SkenOkno.predZacetkom, 12 * ura)
        XCTAssertEqual(SkenOkno.poKoncu, 6 * ura)
        XCTAssertEqual(SkenOkno.privzetoTrajanje, 12 * ura)
    }

    /// Meje so vkljucene: tocno 12 h pred zacetkom je ze aktivno, ena sekunda prej se ne.
    func testMejaPredZacetkom() {
        let d = dogodek(t0, konec: t0.addingTimeInterval(4 * ura))
        XCTAssertFalse(SkenOkno.jeAktiven(d, zdaj: t0.addingTimeInterval(-12 * ura - 1)))
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: t0.addingTimeInterval(-12 * ura)))
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: t0.addingTimeInterval(-12 * ura + 1)))
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: t0))
    }

    /// Tocno 6 h po koncu je se aktivno, sekundo kasneje ne vec.
    func testMejaPoKoncu() {
        let konec = t0.addingTimeInterval(4 * ura)
        let d = dogodek(t0, konec: konec)
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: konec))
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: konec.addingTimeInterval(6 * ura - 1)))
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: konec.addingTimeInterval(6 * ura)))
        XCTAssertFalse(SkenOkno.jeAktiven(d, zdaj: konec.addingTimeInterval(6 * ura + 1)))
    }

    /// Brez `endAt` dogodek traja 12 h, torej je aktiven do zacetek + 18 h.
    func testBrezEndAtTrajaDvanajstUrInSeSestUr() {
        let d = dogodek(t0)
        XCTAssertEqual(SkenOkno.konec(d), t0.addingTimeInterval(12 * ura))
        XCTAssertTrue(SkenOkno.jeAktiven(d, zdaj: t0.addingTimeInterval(18 * ura)))
        XCTAssertFalse(SkenOkno.jeAktiven(d, zdaj: t0.addingTimeInterval(18 * ura + 1)))
    }

    /// `endAt` pred ali ob zacetku je napaka v podatkih: velja privzeto trajanje (dogodek ne sme biti aktiven samo 6 h).
    func testEndAtPredZacetkomVelaPrivzetoTrajanje() {
        XCTAssertEqual(SkenOkno.konec(dogodek(t0, konec: t0.addingTimeInterval(-ura))), t0.addingTimeInterval(12 * ura))
        XCTAssertEqual(SkenOkno.konec(dogodek(t0, konec: t0)), t0.addingTimeInterval(12 * ura))
        XCTAssertEqual(SkenOkno.konec(SkenDogodek(id: 1, title: "x", startAt: SkenCas.niz(t0), endAt: "ni datum")), t0.addingTimeInterval(12 * ura))
    }

    func testNeobjavljenInNeberljivDogodekNistaAktivna() {
        XCTAssertFalse(SkenOkno.jeAktiven(dogodek(t0, status: "draft"), zdaj: t0))
        XCTAssertFalse(SkenOkno.jeAktiven(dogodek(t0, status: "cancelled"), zdaj: t0))
        XCTAssertFalse(SkenOkno.jeAktiven(SkenDogodek(id: 1, title: "x", startAt: ""), zdaj: t0))
        XCTAssertFalse(SkenOkno.jeAktiven(SkenDogodek(id: 1, title: "x", startAt: "jutri zvecer"), zdaj: t0))
        XCTAssertNil(SkenOkno.odprtoOd(SkenDogodek(id: 1, title: "x", startAt: "")))
    }

    func testAktivniSoUrejeniPoZacetkuInIdju() {
        let seznam = [
            Pomoc.dogodek(3, zacetek: t0.addingTimeInterval(2 * ura)),
            Pomoc.dogodek(1, zacetek: t0.addingTimeInterval(-ura)),
            Pomoc.dogodek(2, zacetek: t0.addingTimeInterval(2 * ura)),   // enak zacetek kot 3 -> po id-ju
            Pomoc.dogodek(4, zacetek: t0.addingTimeInterval(40 * ura)),  // se zaprto
            Pomoc.dogodek(5, zacetek: t0, status: "draft"),
        ]
        XCTAssertEqual(SkenOkno.aktivni(seznam, zdaj: t0).map { $0.id }, [1, 2, 3])
    }

    func testNaslednjiJeNajzgodnejsiDogodekKiSeNiOdprt() {
        let seznam = [
            Pomoc.dogodek(1, zacetek: t0.addingTimeInterval(-ura)),                      // ze aktiven
            Pomoc.dogodek(2, zacetek: t0.addingTimeInterval(40 * ura)),
            Pomoc.dogodek(3, zacetek: t0.addingTimeInterval(30 * ura)),                  // odpre se cez 18 h
            Pomoc.dogodek(4, zacetek: t0.addingTimeInterval(13 * ura), status: "draft"), // neobjavljen
            Pomoc.dogodek(5, zacetek: t0.addingTimeInterval(-100 * ura), konec: t0.addingTimeInterval(-90 * ura)),   // mimo
        ]
        XCTAssertEqual(SkenOkno.naslednji(seznam, zdaj: t0)?.id, 3)
        XCTAssertEqual(SkenOkno.odprtoOd(seznam[2]), t0.addingTimeInterval(18 * ura))
        // tocno ob odprtju dogodek ni vec »naslednji« (je aktiven)
        XCTAssertEqual(SkenOkno.naslednji(seznam, zdaj: t0.addingTimeInterval(18 * ura))?.id, 2)
        XCTAssertNil(SkenOkno.naslednji([seznam[0], seznam[3], seznam[4]], zdaj: t0))
        XCTAssertNil(SkenOkno.naslednji([], zdaj: t0))
    }
}

// MARK: - Odlocitev z vec aktivnimi dogodki

@MainActor
final class SkenOdlocitevVecDogodkovTests: XCTestCase {
    private let kljuc = Curve25519.Signing.PrivateKey()
    private let a = 42, b = 43

    private func odloci(_ qr: String, aktivni: Set<Int>? = nil, indeksi: [Int: ScanList] = [:], lokalni: [Int: [String: Date]] = [:],
                        kljucPodatek: ScanKey?? = nil) -> SkenSodba {
        SkenOdlocitev.odloci(qr: qr, aktivni: aktivni ?? [a, b], kljuc: kljucPodatek ?? Pomoc.scanKey(kljuc),
                             indeksi: indeksi.mapValues { SkenIndeks($0) }, lokalni: lokalni)
    }

    func testKodaPoveDogodekInUporabiSeznamTistega() {
        let sa = Pomoc.serial(), sb = Pomoc.serial()
        let indeksi = [
            a: ScanList(eventId: a, tickets: [ScanListTicket(serial: sa, holderUsername: "ana")]),
            b: ScanList(eventId: b, tickets: [ScanListTicket(serial: sb, isVip: true, tableLabel: "T9", holderUsername: "bojan")]),
        ]
        let ra = odloci(Pomoc.koda(kljuc, serial: sa, event: a), indeksi: indeksi)
        XCTAssertEqual(ra.razlog, .veljavna)
        XCTAssertEqual(ra.dogodekId, a)
        XCTAssertEqual(ra.vstopnica?.holderUsername, "ana")
        let rb = odloci(Pomoc.koda(kljuc, serial: sb, event: b), indeksi: indeksi)
        XCTAssertEqual(rb.razlog, .veljavna)
        XCTAssertEqual(rb.dogodekId, b)
        XCTAssertEqual(rb.vstopnica?.tableLabel, "T9")
        // vstopnica dogodka B ni na seznamu dogodka A: koda nosi B, torej se isce samo na seznamu B
        let sc = Pomoc.serial()
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: sc, event: b), indeksi: indeksi).razlog, .veljavnaNiNaSeznamu)
    }

    func testStanjeInLokalniSkeniSoLocenaPoDogodkih() {
        let s = Pomoc.serial()
        let cas = Date(timeIntervalSince1970: 1_790_000_000)
        let indeksi = [
            a: ScanList(eventId: a, tickets: [ScanListTicket(serial: s, status: "used", usedAt: "2026-10-01T21:15:00.000Z")]),
            b: ScanList(eventId: b, tickets: []),
        ]
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: a), indeksi: indeksi).razlog, .zeUporabljena)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: b), indeksi: indeksi).razlog, .veljavnaNiNaSeznamu)
        let lokalni = [a: [s: cas]]
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: a), lokalni: lokalni).razlog, .zeUporabljenaLokalno)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: b), lokalni: lokalni).razlog, .veljavnaNiNaSeznamu)
    }

    /// Dogodek iz kode ni med aktivnimi (izven okna, neobjavljen ali neznan): rdece z novim razlogom, tudi ce je podpis veljaven.
    func testDogodekIzvenAktivnihJeNijeZaDanes() {
        let s = Pomoc.serial()
        let r = odloci(Pomoc.koda(kljuc, serial: s, event: 50))
        XCTAssertEqual(r.razlog, .nijeZaDanes)
        XCTAssertEqual(r.barva, .rdece)
        XCTAssertFalse(r.spusti)
        XCTAssertEqual(r.dogodekId, 50)
        XCTAssertEqual(r.serial, s)
        // ni aktivnih dogodkov
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: a), aktivni: []).razlog, .nijeZaDanes)
        // koda v1
        XCTAssertEqual(odloci(Pomoc.kodaV1(serial: s, event: 50)).razlog, .nijeZaDanes)
        // brez kljuca (telefon ga se nima) za dogodek izven okna ni rumeno: rdece je varno in dokoncno
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: 50), kljucPodatek: .some(nil)).razlog, .nijeZaDanes)
        // ponarejen podpis za dogodek izven okna je tudi rdec
        let tuj = Curve25519.Signing.PrivateKey()
        XCTAssertEqual(odloci(Pomoc.koda(tuj, serial: s, event: 50)).barva, .rdece)
    }

    func testKodaKiNiRazclenljivaOstaneNeveljavna() {
        for smeti in ["", "https://example.com/x", "abc.def", "o2.@@@.@@@", String(repeating: "a", count: 2000)] {
            let r = odloci(smeti)
            XCTAssertEqual(r.razlog, .neveljavna, smeti)
            XCTAssertNil(r.dogodekId)
        }
    }

    func testKodaV1ZaAktivenDogodekJeRumenaZDogodkom() {
        let s = Pomoc.serial()
        let r = odloci(Pomoc.kodaV1(serial: s, event: b))
        XCTAssertEqual(r.razlog, .staraKoda)
        XCTAssertEqual(r.barva, .rumeno)
        XCTAssertEqual(r.dogodekId, b)
        // negativni podatki tistega dogodka veljajo tudi za v1
        let rdece = odloci(Pomoc.kodaV1(serial: s, event: b), lokalni: [b: [s: Date()]])
        XCTAssertEqual(rdece.razlog, .zeUporabljenaLokalno)
    }

    /// Koda v1: event_id ni podpisan, zato lokalni skeni drugih aktivnih dogodkov veljajo kot negativen dokaz. Koda v2 (podpisana) ne.
    func testKodaV1JeRdecaCeJeLokalnoSkeniranaPodDrugimDogodkom() {
        let s = Pomoc.serial()
        let cas = Date(timeIntervalSince1970: 1_790_000_000)
        let lokalni = [a: [s: cas]]
        let v1 = odloci(Pomoc.kodaV1(serial: s, event: b), lokalni: lokalni)
        XCTAssertEqual(v1.razlog, .zeUporabljenaLokalno)
        XCTAssertEqual(v1.kdaj, cas)
        XCTAssertEqual(v1.barva, .rdece)
        // dogodek, ki ni aktiven, ne daje dokaza (lokalni skeni so samo za aktivne)
        XCTAssertEqual(odloci(Pomoc.kodaV1(serial: s, event: b), aktivni: [b], lokalni: lokalni).razlog, .staraKoda)
        // v2: podpis velja, dogodek je zanesljiv -> serial pod drugim dogodkom ne vpliva
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: s, event: b), lokalni: lokalni).razlog, .veljavnaNiNaSeznamu)
        XCTAssertEqual(SkenOdlocitev.lokalniSkenKjerkoli(serial: s, aktivni: [a, b], lokalni: lokalni, najprej: b), cas)
        XCTAssertNil(SkenOdlocitev.lokalniSkenKjerkoli(serial: Pomoc.serial(), aktivni: [a, b], lokalni: lokalni, najprej: b))
    }

    func testNijeZaDanesImaPravilenPrikaz() {
        let p = SkenPrikaz.iz(SkenSodba(razlog: .nijeZaDanes, serial: Pomoc.serial(), dogodekId: 50), qr: "x")
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, "NOT TODAY'S EVENT")
        XCTAssertEqual(p.podnaslov, "This ticket is not for today's event.")
        XCTAssertFalse(p.ponudiVstop)
        XCTAssertFalse(p.uspesen)
    }

    // Streznisko okno (backend #170): result "not_today" ima na vseh treh poteh isti prikaz kot lokalni razlog nijeZaDanes.

    /// Sken, ki je bil na telefonu zelen, streznik pa ga zavrne kot not_today (409).
    func testStreznikNotTodayJeNijeZaDanes() {
        let sodba = SkenSodba(razlog: .veljavna, serial: Pomoc.serial())
        let p = SkenPrikaz.iz(streznik: "not_today", usedAt: nil, sodba: sodba)
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, "NOT TODAY'S EVENT")
        XCTAssertEqual(p.podnaslov, "This ticket is not for today's event.")
        XCTAssertFalse(p.ponudiVstop)
        XCTAssertFalse(p.uspesen)
        XCTAssertEqual(p, SkenPrikaz.iz(SkenSodba(razlog: .nijeZaDanes, serial: sodba.serial), qr: ""))
        XCTAssertNotEqual(p.naslov, "INVALID CODE")
    }

    /// Konflikt iz scan-batch: razlog za vratarja.
    func testRazlogKonfliktaNotToday() {
        XCTAssertEqual(SkenPrikaz.razlogKonflikta("not_today"), "This ticket is not for today's event.")
        XCTAssertNotEqual(SkenPrikaz.razlogKonflikta("not_today"), SkenPrikaz.razlogKonflikta("nekaj_novega"))
    }

    /// Odgovor spletnega POST /business/tickets/scan (409): naslov po result, podnaslov je sporocilo streznika.
    func testSpletniSkenNotToday() {
        let r = ScanResult(result: "not_today", message: "This ticket is not for today's event.", usedAt: nil)
        let p = SkenPrikaz.iz(r)
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, "NOT TODAY'S EVENT")
        XCTAssertEqual(p.podnaslov, "This ticket is not for today's event.")
        XCTAssertFalse(p.uspesen)
        XCTAssertNotEqual(p.naslov, "REFUSED")
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

    /// scan-batch element z result "not_today" je dokoncen (ne ostane v vrsti) in postane konflikt (gost je bil spusceni).
    func testNotTodayVBatchuJeDokoncenKonflikt() throws {
        let el = try JSONDecoder().decode(ScanBatchResult.self, from: Data(#"{"client_scan_id":"n","serial":"s","result":"not_today","used_at":null}"#.utf8))
        XCTAssertTrue(el.jeDokoncen)
        let v = SkenVrsta(disk: disk)
        let n = vnos("n")
        v.dodaj(n)
        let odstranjeni = v.uporabi([el], poslani: [n])
        XCTAssertEqual(odstranjeni, 1)
        XCTAssertTrue(v.vnosi.isEmpty)
        XCTAssertEqual(v.konflikti.count, 1)
        XCTAssertEqual(v.konflikti[0].result, "not_today")
        XCTAssertEqual(SkenPrikaz.razlogKonflikta(v.konflikti[0].result), "This ticket is not for today's event.")
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

/// Vrata za lazni API: klic obstoji, dokler test ne pokliče `odpri()` (nic ne cakamo na pravi cas).
private final class Vrata: @unchecked Sendable {
    private let zapah = NSLock()
    private var odprta = false
    private var cakalci: [CheckedContinuation<Void, Never>] = []

    func pocakaj() async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            if !dodaj(k) { k.resume() }
        }
    }

    // Zapah samo v sinhronih pomoznih funkcijah (NSLock v async funkciji je v Swift 6 napaka).
    private func dodaj(_ k: CheckedContinuation<Void, Never>) -> Bool {
        zapah.lock()
        defer { zapah.unlock() }
        if odprta { return false }
        cakalci.append(k)
        return true
    }

    func odpri() {
        zapah.lock()
        odprta = true
        let vsi = cakalci
        cakalci = []
        zapah.unlock()
        vsi.forEach { $0.resume() }
    }
}

/// Ura, ki jo test premika sam.
private final class TestnaUra {
    var zdaj: Date
    init(_ zdaj: Date) { self.zdaj = zdaj }
}

private final class LazniApi: SkenApi, @unchecked Sendable {
    private let zapah = NSLock()
    var kljucOdgovor: Result<ScanKey, Error>
    var seznamOdgovor: Result<Data, Error>
    /// Odgovor scan-list po dogodku; brez vnosa velja `seznamOdgovor`.
    var seznamPoDogodku: [Int: Result<Data, Error>] = [:]
    var paketOdgovor: ([SkenVnos]) -> Result<[ScanBatchResult], Error> = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") }) }
    var spletniOdgovor: Result<ScanResult, Error> = .success(ScanResult(result: "ok", message: "Welcome", usedAt: nil))
    var dogodkiOdgovor: Result<[SkenDogodek], Error> = .success([])
    /// Streznik odgovori sele po toliko sekundah (ali ga prekine rok).
    /// Zakasnitve IGNORIRAJO preklic (kot nestrukturiran Task za osvezitev zetona v send(), ki ga preklic ne doseze).
    var zakasnitevPaketa: Double = 0
    var zakasnitevSpletnega: Double = 0
    var zakasnitevSeznama: Double = 0
    /// Klic ostane obvisel, dokler se vrata ne odprejo.
    var vrataSeznama: Vrata?
    var vrataPaketa: Vrata?
    private(set) var paketi: [[SkenVnos]] = []
    private(set) var deviceIdji: [String] = []
    private(set) var spletniKlici: [String] = []
    private(set) var klubIdji: [Int?] = []
    private(set) var kljucKlici = 0
    private(set) var seznamKlici = 0
    private(set) var seznamDogodki: [Int] = []
    private(set) var dogodkiKlici = 0
    /// Za vsak klic scan-list: ali je bil zahtevan mimo predpomnilnika.
    private(set) var svezeKlici: [Bool] = []
    private func zabeleziSveze(_ sveze: Bool) {
        zapah.lock()
        svezeKlici.append(sveze)
        zapah.unlock()
    }

    init(kljuc: ScanKey, seznam: ScanList) {
        kljucOdgovor = .success(kljuc)
        seznamOdgovor = .success(Pomoc.seznamPodatki(seznam))
        dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42)])
    }

    /// Caka, ne da bi se odzval na preklic Taska (continuation + GCD, ne Task.sleep).
    static func neprekinljivoCakaj(_ sekunde: Double) async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + sekunde) { k.resume() }
        }
    }

    func nastaviSeznam(_ l: ScanList) { seznamOdgovor = .success(Pomoc.seznamPodatki(l)) }

    // Zapah samo v sinhronih pomoznih funkcijah (NSLock v async funkciji je v Swift 6 napaka).
    private func zabelezi(_ klub: Int?, kljuc: Bool = false, seznam: Bool = false, dogodek: Int? = nil, dogodki: Bool = false, paket: [SkenVnos]? = nil, deviceId: String? = nil, spletni: String? = nil) {
        zapah.lock()
        defer { zapah.unlock() }
        klubIdji.append(klub)
        if kljuc { kljucKlici += 1 }
        if seznam { seznamKlici += 1 }
        if let dogodek { seznamDogodki.append(dogodek) }
        if dogodki { dogodkiKlici += 1 }
        if let paket { paketi.append(paket) }
        if let deviceId { deviceIdji.append(deviceId) }
        if let spletni { spletniKlici.append(spletni) }
    }

    func dogodki(token: String, klubId: Int?) async throws -> [SkenDogodek] {
        zabelezi(klubId, dogodki: true)
        return try dogodkiOdgovor.get()
    }
    func kljuc(token: String, klubId: Int?) async throws -> ScanKey {
        zabelezi(klubId, kljuc: true)
        return try kljucOdgovor.get()
    }
    func seznam(token: String, klubId: Int?, dogodekId: Int, sveze: Bool) async throws -> Data {
        zabelezi(klubId, seznam: true, dogodek: dogodekId)
        zabeleziSveze(sveze)
        let vrata = vrataSeznama
        if let vrata { await vrata.pocakaj() }
        if zakasnitevSeznama > 0 { await Self.neprekinljivoCakaj(zakasnitevSeznama) }
        return try (seznamPoDogodku[dogodekId] ?? seznamOdgovor).get()
    }
    func paket(token: String, klubId: Int?, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        zabelezi(klubId, paket: vnosi, deviceId: deviceId)
        let vrata = vrataPaketa
        if let vrata { await vrata.pocakaj() }
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
    private let dogodek = Pomoc.aktivenDogodek(42)

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

    /// Caka na POGOJ (ne na cas): gornja meja je samo varovalka pred obvisanjem testa.
    private func pocakaj(_ pogoj: () -> Bool, rok: Double = 30) async -> Bool {
        let konec = Date().addingTimeInterval(rok)
        while !pogoj() && Date() < konec { try? await Task.sleep(nanoseconds: 2_000_000) }
        return pogoj()
    }

    /// Neposlani vnosi, kot jih vidi nov zagon aplikacije (vsak vnos je datoteka na disku).
    private func vnosiNaDisku() -> [SkenVnos] { SkenVrsta(disk: SkenDisk(mapa: mapa)).vnosi }

    func testZelenoTakojInDvojniSkenJeRdece() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, isVip: true, tableLabel: "T1", packageName: "Jameson", holderUsername: "ana")])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }   // streznik ni dosegljiv
        let seja = naredi(a)
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(seja.cakajoce, 1)
    }

    /// P3: brez povezave »ni na seznamu« ostane zeleno z opombo; z povezavo odloci streznik.
    func testNiNaSeznamuBrezPovezaveZelenoZOpombo() async {
        let a = api(vstopnice: [])
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.naloziDogodke()
        seja.omrezjeSpremenjeno(gor: false)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertNotNil(p.opomba)
    }

    func testNiNaSeznamuZPovezavoOdlociStreznik() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertTrue(seja.povezava)
        XCTAssertEqual(seja.cakajoce, 1)
    }

    func testOdprtjeBrezPovezaveSShranjenimSeznamom() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let prva = naredi(a)
        await prva.naloziDogodke()                 // prenese in shrani
        XCTAssertNotNil(prva.zadnjiPrenos)

        let brez = api(vstopnice: [])
        brez.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        brez.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))   // aktivni dogodki iz shranjenega seznama in ure telefona
        let druga = naredi(brez)                    // nova seja = ponovni zagon aplikacije, brez povezave
        await druga.naloziDogodke()
        XCTAssertEqual(druga.priprava, .pripravljen)
        XCTAssertFalse(druga.povezava)
        let p = await druga.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(druga.cakajoce, 1)

        // vrsta in lokalni skeni prezivijo zaprtje aplikacije
        let tretja = naredi(brez)
        await tretja.naloziDogodke()
        XCTAssertEqual(tretja.cakajoce, 1)
        let ponovno = await tretja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(ponovno.barva, .rdece)
    }

    func testBrezPovezaveInBrezShrambeJeManjkaPodatkov() async {
        let a = api(vstopnice: [])
        a.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        a.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(a)
        await seja.naloziDogodke()
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
        await prva.naloziDogodke()
        XCTAssertTrue(FileManager.default.fileExists(atPath: mapa.appendingPathComponent(SkenDisk.imeKljuca).path))

        let brez = api(vstopnice: [])
        brez.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let druga = naredi(brez)
        brez.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(77, title: "Drug dogodek")])
        await druga.naloziDogodke()   // seznama za ta dogodek ni, kljuc pa je
        XCTAssertEqual(druga.priprava, .pripravljen)
        let dobra = await druga.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 77))
        XCTAssertEqual(dobra.barva, .zeleno)
        let napacenDogodek = await druga.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(napacenDogodek.barva, .rdece)
        XCTAssertEqual(napacenDogodek.naslov, "NOT TODAY'S EVENT")   // dogodek 42 ni med aktivnimi
        let ponaredek = await druga.skeniraj(Pomoc.koda(Curve25519.Signing.PrivateKey(), serial: Pomoc.serial(), event: 77))
        XCTAssertEqual(ponaredek.barva, .rdece)
    }

    func testStaraKodaBrezPovezaveJeRumenaSPovezavoGreNaStreznik() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
        // streznik zamenja skrivnost -> nov par in nov kid
        let novi = Curve25519.Signing.PrivateKey()
        a.kljucOdgovor = .success(Pomoc.scanKey(novi, kid: "kid2"))
        a.nastaviSeznam(ScanList(eventId: 42, kid: "kid2", tickets: [ScanListTicket(serial: s1)]))
        await seja.osveziSeznam(42)
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
        await seja.naloziDogodke()
        a.kljucOdgovor = .failure(URLError(.timedOut))
        a.nastaviSeznam(ScanList(eventId: 42, kid: "kid2", tickets: [ScanListTicket(serial: s1)]))
        await seja.osveziSeznam(42)
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
        await seja.naloziDogodke()       // en poskus
        _ = await seja.osveziKljuc()
        _ = await seja.osveziKljuc()
        XCTAssertEqual(a.kljucKlici, 1)
    }

    func testAktivniDogodkiIzSeznamaInShranjenSeznamBrezPovezave() async {
        let a = api(vstopnice: [])
        let zdaj = Date()
        func ob(_ ure: Double) -> Date { zdaj.addingTimeInterval(ure * 3600) }
        a.dogodkiOdgovor = .success([
            Pomoc.dogodek(1, title: "Jutri", zacetek: ob(24)),                              // okno se odpre cez 12 h
            Pomoc.dogodek(2, title: "Osnutek", zacetek: ob(5), status: "draft"),            // neobjavljen
            Pomoc.dogodek(3, title: "Davno", zacetek: ob(-72), konec: ob(-66)),             // okno zaprto 60 h nazaj
            Pomoc.dogodek(4, title: "Zdaj", zacetek: ob(-2)),
            Pomoc.dogodek(5, title: "Pozno zvecer", zacetek: ob(10)),                       // okno se je odprlo pred 2 h
            Pomoc.dogodek(6, title: "Pojutrisnjem", zacetek: ob(48)),
        ])
        let prva = naredi(a)
        await prva.naloziDogodke()
        XCTAssertEqual(prva.aktivni.map { $0.id }, [4, 5])
        XCTAssertEqual(prva.naslednji?.id, 1)   // naslednje odprtje: dogodek 1, cez 12 h
        XCTAssertEqual(prva.priprava, .pripravljen)

        let brez = api(vstopnice: [])
        brez.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        let druga = naredi(brez)
        await druga.naloziDogodke()   // brez povezave: shranjen seznam dogodkov in ura telefona
        XCTAssertEqual(druga.aktivni.map { $0.id }, [4, 5])
        XCTAssertEqual(druga.naslednji?.id, 1)
        XCTAssertNil(druga.dogodkiNapaka)
    }

    /// Brez shranjenega seznama in brez povezave ni aktivnih dogodkov: napaka je vidna, zaslon ne pokaze »ni dogodka« kot dejstva.
    func testBrezSeznamaDogodkovInBrezPovezaveJeNapaka() async {
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(a)
        await seja.naloziDogodke()
        XCTAssertTrue(seja.aktivni.isEmpty)
        XCTAssertNotNil(seja.dogodkiNapaka)
        XCTAssertTrue(seja.dogodkiNalozeni)
        XCTAssertEqual(seja.priprava, .brezDogodka)
    }

    // MARK: Brez izbire dogodka (8. 10. 2026)

    /// Skener je pripravljen takoj po nalaganju: brez izbire dogodka, dogodek pove koda.
    func testSkenerBrezIzbireDogodka() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, holderUsername: "ana")])
        let seja = naredi(a)
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        XCTAssertEqual(seja.priprava, .pripravljen)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(p.podnaslov, "ana")
    }

    /// Dva dogodka hkrati: vsak ima svoj seznam, svoje lokalne skene in svoj vnos v vrsti; koda pove, za katerega je.
    func testDvaAktivnaDogodkaKodaPoveZaKaterega() async {
        let sa = Pomoc.serial(), sb = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: sa, holderUsername: "ana")])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42, title: "Sobota"), Pomoc.aktivenDogodek(43, title: "After")])
        a.seznamPoDogodku[43] = .success(Pomoc.seznamPodatki(ScanList(eventId: 43, kid: "kid1", tickets: [
            ScanListTicket(serial: sb, isVip: true, tableLabel: "T9", holderUsername: "bojan")])))
        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        let seja = naredi(a)
        await seja.naloziDogodke()
        XCTAssertEqual(Set(seja.aktivni.map { $0.id }), [42, 43])
        XCTAssertEqual(Set(a.seznamDogodki), [42, 43])   // seznam VSAKEGA aktivnega dogodka

        let pa = await seja.skeniraj(Pomoc.koda(kljuc, serial: sa, event: 42))
        XCTAssertEqual(pa.barva, .zeleno)
        XCTAssertEqual(pa.podnaslov, "ana")
        let pb = await seja.skeniraj(Pomoc.koda(kljuc, serial: sb, event: 43))
        XCTAssertEqual(pb.barva, .zeleno)
        XCTAssertEqual(pb.podnaslov, "bojan")
        XCTAssertNotNil(pb.vip)
        // vstopnica enega dogodka ni na seznamu drugega, a koda nosi svoj dogodek -> zeleno z opombo, ne »napacen dogodek«
        let pc = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 43))
        XCTAssertEqual(pc.barva, .zeleno)
        XCTAssertNotNil(pc.opomba)
        // ponovni sken je rdec samo v svojem dogodku
        let ponovno = await seja.skeniraj(Pomoc.koda(kljuc, serial: sa, event: 42))
        XCTAssertEqual(ponovno.barva, .rdece)
        XCTAssertEqual(ponovno.naslov, "ALREADY SCANNED")
        XCTAssertEqual(seja.cakajoce, 3)
        XCTAssertEqual(Set(vnosiNaDisku().map { $0.eventId }), [42, 43])
        XCTAssertEqual(vnosiNaDisku().first { $0.serial == sb }?.eventId, 43)

        // lokalni skeni so na disku po dogodku
        let disk = SkenDisk(mapa: mapa)
        XCTAssertEqual(disk.preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: 1, dogodek: 42))?.casi.keys.sorted(), [sa])
        XCTAssertEqual(disk.preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: 1, dogodek: 43))?.casi.count, 2)
    }

    /// Koda za dogodek kluba, ki je izven okna, ali za neznan dogodek: rdece, nov razlog, brez omrezja.
    func testKodaZaDogodekIzvenOknaJeRdecaBrezOmrezja() async {
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([
            Pomoc.aktivenDogodek(42),
            Pomoc.dogodek(50, title: "Cez teden", zacetek: Date().addingTimeInterval(30 * 3600)),   // okno se odpre cez 18 h
            Pomoc.dogodek(51, title: "Prejsnji teden", zacetek: Date().addingTimeInterval(-200 * 3600)),
        ])
        let seja = naredi(a)
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        let omrezniKlici = a.klubIdji.count
        for (qr, ime) in [(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 50), "izven okna (prihodnji)"),
                          (Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 51), "izven okna (pretekli)"),
                          (Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 999), "neznan dogodek"),
                          (Pomoc.kodaV1(serial: Pomoc.serial(), event: 50), "v1 izven okna")] {
            let p = await seja.skeniraj(qr)
            XCTAssertEqual(p.barva, .rdece, ime)
            XCTAssertEqual(p.naslov, "NOT TODAY'S EVENT", ime)
            XCTAssertEqual(p.podnaslov, "This ticket is not for today's event.", ime)
        }
        XCTAssertEqual(seja.zavrnjeni, 4)
        XCTAssertEqual(seja.cakajoce, 0)
        XCTAssertEqual(a.klubIdji.count, omrezniKlici)   // nobenega klica na streznik
        // koda, ki je ni mogoce razclenit, ostane »neveljavna«
        let smeti = await seja.skeniraj("https://example.com")
        XCTAssertEqual(smeti.naslov, "INVALID CODE")
    }

    /// Brez aktivnega dogodka: skener je zaprt, seja pove, kdaj se odpre naslednji, vsaka koda je rdeca.
    func testBrezAktivnegaDogodkaJeNaslednjiInKodeSoRdece() async {
        let a = api(vstopnice: [])
        let odpre = Date().addingTimeInterval(30 * 3600)
        a.dogodkiOdgovor = .success([
            Pomoc.dogodek(7, title: "Pojutrisnjem", zacetek: Date().addingTimeInterval(60 * 3600)),
            Pomoc.dogodek(6, title: "Jutri", zacetek: odpre),
            Pomoc.dogodek(5, title: "Osnutek", zacetek: Date().addingTimeInterval(20 * 3600), status: "draft"),
        ])
        let seja = naredi(a)
        XCTAssertEqual(seja.priprava, .nalaga)
        await seja.naloziDogodke()
        XCTAssertTrue(seja.aktivni.isEmpty)
        XCTAssertEqual(seja.priprava, .brezDogodka)
        XCTAssertEqual(seja.naslednji?.id, 6)
        let od = SkenOkno.odprtoOd(seja.naslednji!)
        XCTAssertEqual(od?.timeIntervalSince1970 ?? 0, odpre.addingTimeInterval(-12 * 3600).timeIntervalSince1970, accuracy: 0.01)
        XCTAssertTrue(a.seznamDogodki.isEmpty)    // seznamov izven okna ne prenasamo
        XCTAssertEqual(a.kljucKlici, 0)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 6))
        XCTAssertEqual(p.naslov, "NOT TODAY'S EVENT")
    }

    /// Dogodek, ki med sejo vstopi v okno, se doda (stanje + prenos seznama); tisti, ki izstopi, se odstrani, podatki na disku ostanejo.
    func testDogodekVstopiInIzstopiIzOknaMedSejo() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let zdaj = Date()
        a.dogodkiOdgovor = .success([
            Pomoc.aktivenDogodek(42),
            Pomoc.dogodek(43, title: "Pozneje", zacetek: zdaj.addingTimeInterval(13 * 3600)),   // okno se odpre cez 1 h
        ])
        let seja = naredi(a)
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        XCTAssertEqual(seja.naslednji?.id, 43)
        XCTAssertEqual(a.seznamDogodki, [42])
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))

        // ura telefona se premakne za 90 min: 43 vstopi v okno
        seja.uskladiAktivne(zdaj: zdaj.addingTimeInterval(5400))
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42, 43])
        XCTAssertNil(seja.naslednji)
        XCTAssertNil(seja.zadnjiPrenos)   // za 43 seznam se ni prenesen
        await seja.osveziSeznam(43)
        XCTAssertEqual(a.seznamDogodki, [42, 43])
        XCTAssertNotNil(seja.zadnjiPrenos)

        // ... in cez 40 h oba izstopita (42: konec +12 h +6 h; 43: +13 h +12 h +6 h)
        seja.uskladiAktivne(zdaj: zdaj.addingTimeInterval(40 * 3600))
        XCTAssertTrue(seja.aktivni.isEmpty)
        XCTAssertEqual(seja.priprava, .brezDogodka)
        XCTAssertNil(seja.zadnjiPrenos)
        let imena = Set(SkenDisk(mapa: mapa).imena())
        XCTAssertTrue(imena.contains(SkenDisk.imeSeznama(klub: 1, dogodek: 42)))
        XCTAssertTrue(imena.contains(SkenDisk.imeLokalnih(klub: 1, dogodek: 42)))

        // ura se vrne: dogodek 42 je spet aktiven in lokalni skeni so z diska nazaj (ista koda je spet rdeca)
        seja.uskladiAktivne(zdaj: zdaj)
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        let ponovno = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(ponovno.barva, .rdece)
        XCTAssertEqual(ponovno.naslov, "ALREADY SCANNED")
    }

    /// Dogodek, ki je vstopil v okno med dvema tikoma, je ob skenu ze aktiven (sken sam preracuna mnozico). Ura je podtaknjena.
    func testSkenPreracunaMnozicoAktivnih() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([
            Pomoc.dogodek(42, zacetek: t0.addingTimeInterval(-3600), konec: t0.addingTimeInterval(5 * 3600)),
            Pomoc.dogodek(43, title: "Skoraj", zacetek: t0.addingTimeInterval(13 * 3600)),   // okno se odpre cez 1 h
        ])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        let prej = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 43))
        XCTAssertEqual(prej.naslov, "NOT TODAY'S EVENT")
        ura.zdaj = t0.addingTimeInterval(3600 - 1)
        let tikPrej = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 43))
        XCTAssertEqual(tikPrej.naslov, "NOT TODAY'S EVENT")   // sekundo pred odprtjem
        ura.zdaj = t0.addingTimeInterval(3600)                // tocno 12 h pred zacetkom
        let potem = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 43))
        XCTAssertEqual(potem.barva, .zeleno)   // seznama se ni, kljuc pa je: zeleno z opombo (streznik preveri)
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42, 43])
    }

    /// Tik (vsako sekundo): dogodek, ki vstopi v okno, sam dobi stanje, a prvi prenos seznama cez 0-30 s (razprsitev); brez izbire dogodka.
    func testTikSamDodaDogodekKiVstopiVOknoZRazprsitvijo() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([
            Pomoc.dogodek(42, zacetek: t0.addingTimeInterval(-3600), konec: t0.addingTimeInterval(5 * 3600)),
            Pomoc.dogodek(43, title: "Skoraj", zacetek: t0.addingTimeInterval(13 * 3600)),   // okno se odpre cez 1 h
        ])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        XCTAssertEqual(a.seznamDogodki, [42])          // ob odprtju skenerja gre prenos takoj

        ura.zdaj = t0.addingTimeInterval(3600)
        seja.tik()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42, 43])
        let naslednja = seja.naslednjaOsvezitevSeznama(dogodek: 43)
        XCTAssertNotNil(naslednja)
        XCTAssertTrue((naslednja ?? .distantPast) >= ura.zdaj && (naslednja ?? .distantFuture) <= ura.zdaj.addingTimeInterval(30))
        XCTAssertFalse(a.seznamDogodki.contains(43))   // tik ni takoj sprozil prenosa

        ura.zdaj = t0.addingTimeInterval(3600 + 31)
        seja.tik()
        let prenesen = await pocakaj { a.seznamDogodki.contains(43) }
        XCTAssertTrue(prenesen)                         // zdaj je prenos zapadel
    }

    /// Dogodek, ki ga ustvari odprtje skenerja ali odgovor strezniga (ne tik), prenese seznam takoj.
    func testStanjeIzSkenaAliOdgovoraImaPrenosTakoj() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.dogodek(42, zacetek: t0.addingTimeInterval(-3600)),
                                     Pomoc.dogodek(43, zacetek: t0.addingTimeInterval(13 * 3600))])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        ura.zdaj = t0.addingTimeInterval(3700)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 43))   // sken ustvari stanje
        XCTAssertEqual(seja.naslednjaOsvezitevSeznama(dogodek: 43), .distantPast)
    }

    /// Seznam z diska velja takoj ob hladnem zagonu brez povezave: koda, ki je na seznamu `used`, je rdeca.
    func testSeznamZDiskaVelaPriHladnemZagonu() async {
        let sUsed = Pomoc.serial(), sOk = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: sUsed, status: "used", usedAt: "2026-10-08T21:15:00.000Z"), ScanListTicket(serial: sOk)])
        await naredi(a).naloziDogodke()
        let brez = api(vstopnice: [])
        brez.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.kljucOdgovor = .failure(URLError(.notConnectedToInternet))
        brez.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(brez)
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        XCTAssertNotNil(seja.zadnjiPrenos)
        let rdece = await seja.skeniraj(Pomoc.koda(kljuc, serial: sUsed, event: 42))
        XCTAssertEqual(rdece.barva, .rdece)
        XCTAssertEqual(rdece.naslov, "ALREADY SCANNED")
        let zeleno = await seja.skeniraj(Pomoc.koda(kljuc, serial: sOk, event: 42))
        XCTAssertEqual(zeleno.barva, .zeleno)
    }

    /// `zadnjiPrenos` je prenos NAJSTAREJSEGA med aktivnimi; dokler kateri ni prenesen, ga ni.
    func testZadnjiPrenosJeNajstarejsiMedAktivnimi() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42), Pomoc.aktivenDogodek(43)])
        a.seznamPoDogodku[43] = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertNil(seja.zadnjiPrenos)             // 43 se ni bil prenesen
        a.seznamPoDogodku[43] = .success(Pomoc.seznamPodatki(ScanList(eventId: 43, kid: "kid1")))
        ura.zdaj = t0.addingTimeInterval(60)
        await seja.osveziSeznam(43)
        XCTAssertEqual(seja.zadnjiPrenos, t0)       // najstarejsi je prenos dogodka 42
    }

    /// Periodicna osvezitev seznama dogodkov: novi dogodek postane aktiven, preklican/neobjavljen preneha biti.
    func testOsvezitevSeznamaDogodkovSpremeniAktivne() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.naloziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42), Pomoc.aktivenDogodek(44, title: "Dodan")])
        await seja.osveziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42, 44])
        a.dogodkiOdgovor = .success([Pomoc.dogodek(44, title: "Dodan", zacetek: Date().addingTimeInterval(-3600), status: "draft")])
        await seja.osveziDogodke()
        XCTAssertTrue(seja.aktivni.isEmpty)
        // neuspela osvezitev ohrani stari seznam
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42)])
        await seja.osveziDogodke()
        a.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        await seja.osveziDogodke()
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        XCTAssertNil(seja.dogodkiNapaka)
    }

    /// Rocno spustitev kode v1 odloca dogodek iz kode: vnos nosi svoj dogodek, izven okna je zavrnjeno.
    func testSpustiRocnoZVecDogodki() async {
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42), Pomoc.aktivenDogodek(43)])
        let seja = naredi(a)
        await seja.naloziDogodke()
        let s43 = Pomoc.serial()
        let p = seja.spustiRocno(qr: Pomoc.kodaV1(serial: s43, event: 43))
        XCTAssertEqual(p.barva, .zeleno)
        XCTAssertEqual(vnosiNaDisku().map { $0.eventId }, [43])
        let ponovno = seja.spustiRocno(qr: Pomoc.kodaV1(serial: s43, event: 43))
        XCTAssertEqual(ponovno.naslov, "ALREADY SCANNED")
        let izven = seja.spustiRocno(qr: Pomoc.kodaV1(serial: Pomoc.serial(), event: 50))
        XCTAssertEqual(izven.barva, .rdece)
        XCTAssertEqual(izven.naslov, "NOT TODAY'S EVENT")
        XCTAssertEqual(vnosiNaDisku().count, 1)
        // po sinhronizaciji gre vnos na streznik s svojo kodo
        await seja.poslji()
        XCTAssertEqual(a.paketi.flatMap { $0 }.map { $0.eventId }, [43])
    }

    /// Koda v1 za aktiven dogodek: s povezavo gre na streznik, brez nje je rumeno z ponudbo »Let in« (dosedanji tok).
    func testKodaV1VOknuGreNaStreznikIzvenOknaNe() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.naloziDogodke()
        let vOknu = await seja.skeniraj(Pomoc.kodaV1(serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(a.spletniKlici.count, 1)
        XCTAssertEqual(vOknu.barva, .zeleno)   // streznik (laz) odgovori »ok«
        let izven = await seja.skeniraj(Pomoc.kodaV1(serial: Pomoc.serial(), event: 9))
        XCTAssertEqual(izven.naslov, "NOT TODAY'S EVENT")
        XCTAssertEqual(a.spletniKlici.count, 1)   // izven okna streznika ne vprasamo
    }

    // MARK: Pregled PR #68 (logika)

    /// Odmik ponovnega poskusa GET /business/events: eksponenten 30 s ... 300 s z jitterjem.
    func testOdmikDogodkovPoNapakahJeEksponentenZJitterjem() {
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(1, jitter: 1), 30)
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(2, jitter: 1), 60)
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(3, jitter: 1), 120)
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(4, jitter: 1), 240)
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(5, jitter: 1), 300)
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(40, jitter: 1.25), 300)   // zgornja meja velja tudi z jitterjem
        XCTAssertEqual(SkenSeja.odmikDogodkovPoNapakah(1, jitter: 0.75), 22.5)
        for n in 1...8 {
            let o = SkenSeja.odmikDogodkovPoNapakah(n)
            XCTAssertTrue(o > 0 && o <= 300)
        }
    }

    /// Ob zaporednih napakah se seznam dogodkov ne ponavlja na fiksnih 30 s; uspeh vrne redni razmik ~10 min.
    func testOsvezitevDogodkovOdlagaZBackoffomInSeVrne() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        func odmik() -> Double { seja.osvezitevDogodkovOb.timeIntervalSince(ura.zdaj) }
        XCTAssertTrue((22.5...37.5).contains(odmik()), "1. napaka: \(odmik())")
        await seja.osveziDogodke()
        XCTAssertTrue((45...75).contains(odmik()), "2. napaka: \(odmik())")
        await seja.osveziDogodke()
        XCTAssertTrue((90...150).contains(odmik()), "3. napaka: \(odmik())")
        for _ in 0..<6 { await seja.osveziDogodke() }
        XCTAssertTrue(odmik() <= 300, "najvec 300 s: \(odmik())")
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42)])
        await seja.osveziDogodke()
        XCTAssertTrue((540...660).contains(odmik()), "po uspehu: \(odmik())")
        a.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        await seja.osveziDogodke()
        XCTAssertTrue((22.5...37.5).contains(odmik()), "stevec napak se je ponastavil: \(odmik())")
    }

    /// Vrnitev povezave / aplikacije v ospredje: osvezitve (dogodki, seznami) z jitterjem 0-15 s, ne vse takoj.
    func testTakojOsveziRazprsiOsvezitve() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        for _ in 0..<20 {
            seja.takojOsvezi()
            let seznam = seja.naslednjaOsvezitevSeznama(dogodek: 42) ?? .distantPast
            XCTAssertTrue(seznam >= t0 && seznam <= t0.addingTimeInterval(15))
            XCTAssertTrue(seja.osvezitevDogodkovOb >= t0 && seja.osvezitevDogodkovOb <= t0.addingTimeInterval(15))
        }
    }

    /// Zavrnjena koda (dogodek ni aktiven) ob povezavi enkrat znova nalozi dogodke (najvec 1x/min); naslednji sken je pravilen.
    func testRdecaKodaZaradiStarihDogodkovPonovnoNaloziDogodke() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertEqual(a.dogodkiKlici, 1)
        // klub je med vecerom objavil dogodek 50 (ze v oknu), telefon ga se ne pozna
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42), Pomoc.aktivenDogodek(50, title: "Dodan")])
        let prva = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 50))
        XCTAssertEqual(prva.naslov, "NOT TODAY'S EVENT")
        let nalozeno = await pocakaj { a.dogodkiKlici == 2 && seja.aktivni.count == 2 }
        XCTAssertTrue(nalozeno)
        let druga = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 50))
        XCTAssertEqual(druga.barva, .zeleno)   // naslednji sken je pravilen
        // nov rdec sken v isti minuti ne sprozi novega nalaganja
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 999))
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 998))
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(a.dogodkiKlici, 2)
        // cez minuto spet
        ura.zdaj = t0.addingTimeInterval(61)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 997))
        let spet = await pocakaj { a.dogodkiKlici == 3 }
        XCTAssertTrue(spet)
        // brez povezave nalaganja ne poskusamo
        ura.zdaj = t0.addingTimeInterval(200)
        seja.omrezjeSpremenjeno(gor: false)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 996))
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(a.dogodkiKlici, 3)
    }

    /// Zavrnjena koda za ZNAN dogodek (izven okna) ne sprozi nalaganja, dokler je seznam dogodkov svez; ko je starejsi od 5 min, ga.
    func testRdecaKodaZaZnanDogodekNaloziSamoCeJeSeznamStar() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42), Pomoc.dogodek(60, title: "Cez teden", zacetek: t0.addingTimeInterval(100 * 3600))])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertEqual(a.dogodkiKlici, 1)
        ura.zdaj = t0.addingTimeInterval(120)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 60))
        XCTAssertEqual(p.naslov, "NOT TODAY'S EVENT")
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(a.dogodkiKlici, 1)            // znan dogodek, seznam star 2 min: brez klica
        ura.zdaj = t0.addingTimeInterval(301)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 60))
        let nalozeno = await pocakaj { a.dogodkiKlici == 2 }
        XCTAssertTrue(nalozeno)                       // seznam star > 5 min
    }

    /// Ce nalaganje dogodkov pada, rdeca koda ne klice streznika vsako minuto: velja backoff (30 s ... 300 s).
    func testRdecaKodaNeBombardiraPadlegaStreznika() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .failure(APIError.requestFailed(400, "Bad request."))   // ne izpad povezave: `povezava` ostane true
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()                  // 1. napaka
        await seja.osveziDogodke()                  // 2.
        await seja.osveziDogodke()                  // 3. -> odmik 90-150 s
        XCTAssertEqual(a.dogodkiKlici, 3)
        XCTAssertTrue(seja.osvezitevDogodkovOb.timeIntervalSince(t0) >= 90)
        XCTAssertTrue(seja.povezava)
        ura.zdaj = t0.addingTimeInterval(70)         // minuta med dvema nalaganjema je mimo, backoff se ni
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 777))   // neznan dogodek
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(a.dogodkiKlici, 3)
        ura.zdaj = seja.osvezitevDogodkovOb.addingTimeInterval(1)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 777))
        let naslednji = await pocakaj { a.dogodkiKlici == 4 }
        XCTAssertTrue(naslednji)
    }

    /// Ura telefona: svez seznam s `generated_at` > 5 min stran od ure telefona (v obe smeri) prizge opozorilo; okna ne popravljamo.
    func testNapacnaUraTelefonaJeOpozorilo() async {
        let nic = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertFalse(SkenSeja.jeUraNapacna(generatedAt: SkenCas.niz(nic.addingTimeInterval(-299)), zdaj: nic))
        XCTAssertFalse(SkenSeja.jeUraNapacna(generatedAt: SkenCas.niz(nic.addingTimeInterval(299)), zdaj: nic))
        XCTAssertTrue(SkenSeja.jeUraNapacna(generatedAt: SkenCas.niz(nic.addingTimeInterval(-301)), zdaj: nic))
        XCTAssertTrue(SkenSeja.jeUraNapacna(generatedAt: SkenCas.niz(nic.addingTimeInterval(301)), zdaj: nic))
        XCTAssertFalse(SkenSeja.jeUraNapacna(generatedAt: "", zdaj: nic))
        XCTAssertFalse(SkenSeja.jeUraNapacna(generatedAt: "ni datum", zdaj: nic))

        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        // streznik je na 1 h pred telefonom (telefon je prehiteval)
        a.nastaviSeznam(ScanList(eventId: 42, generatedAt: SkenCas.niz(t0.addingTimeInterval(-3600)), kid: "kid1"))
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertTrue(seja.uraNapacna)
        XCTAssertEqual(a.svezeKlici, [false])      // dokler ura ni sumljiva, gre prenos prek predpomnilnika (ETag/304)
        // ura je se napacna in odgovor nespremenjen: opozorilo ostane, prenos pa gre mimo predpomnilnika
        await seja.osveziSeznam(42)
        XCTAssertTrue(seja.uraNapacna)
        XCTAssertEqual(a.svezeKlici, [false, true])
        // uporabnik popravi uro (telefon zdaj kaze streznikov cas), vsebina seznama je ENAKA: svez odgovor ugasne opozorilo
        ura.zdaj = t0.addingTimeInterval(-3600)
        await seja.osveziSeznam(42)
        XCTAssertFalse(seja.uraNapacna)
        XCTAssertEqual(a.svezeKlici, [false, true, true])
        // opozorila ni vec: naslednji prenos je spet navaden (ETag/304)
        await seja.osveziSeznam(42)
        XCTAssertEqual(a.svezeKlici, [false, true, true, false])
        ura.zdaj = t0
        // spremenjen svez seznam z ujemajoco uro opozorila ne prizge
        a.nastaviSeznam(ScanList(eventId: 42, generatedAt: SkenCas.niz(t0), kid: "kid1", tickets: [ScanListTicket(serial: Pomoc.serial())]))
        await seja.osveziSeznam(42)
        XCTAssertFalse(seja.uraNapacna)
        // telefon zaostaja: streznikov cas je v prihodnosti
        a.nastaviSeznam(ScanList(eventId: 42, generatedAt: SkenCas.niz(t0.addingTimeInterval(1800)), kid: "kid1"))
        await seja.osveziSeznam(42)
        XCTAssertTrue(seja.uraNapacna)
        // okna ne popravljamo: aktivni dogodek ostane aktiven po telefonovi uri
        XCTAssertEqual(seja.aktivni.map { $0.id }, [42])
        // dogodek izstopi: opozorila ni (nima vec kaj opozarjati)
        seja.uskladiAktivne(zdaj: t0.addingTimeInterval(40 * 3600))
        XCTAssertFalse(seja.uraNapacna)
    }

    /// Zaslon brez dogodka pokaze, kdaj je bil seznam dogodkov osvezen: ob prenosu, ob hladnem zagonu pa iz datoteke na disku.
    func testCasOsvezitveSeznamaDogodkov() async {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let a = api(vstopnice: [])
        let seja = naredi(a)
        seja.ura = { t0 }
        XCTAssertNil(seja.dogodkiPosodobljeni)
        await seja.naloziDogodke()
        XCTAssertEqual(seja.dogodkiPosodobljeni, t0)

        let brez = api(vstopnice: [])
        brez.dogodkiOdgovor = .failure(URLError(.notConnectedToInternet))
        let druga = naredi(brez)
        await druga.naloziDogodke()
        XCTAssertNotNil(druga.dogodkiPosodobljeni)   // cas zapisa datoteke
        XCTAssertTrue(abs((druga.dogodkiPosodobljeni ?? .distantPast).timeIntervalSinceNow) < 120)
    }

    /// Koda v1: event_id ni podpisan, zato lokalni skeni VSEH aktivnih dogodkov veljajo kot dokaz »ze skenirano«.
    func testKodaV1JeRdecaCeJeBilaSkeniranaPodDrugimAktivnimDogodkom() async {
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42), Pomoc.aktivenDogodek(43)])
        let seja = naredi(a)
        await seja.naloziDogodke()
        let s = Pomoc.serial()
        XCTAssertEqual(seja.spustiRocno(qr: Pomoc.kodaV1(serial: s, event: 42)).barva, .zeleno)
        let p = await seja.skeniraj(Pomoc.kodaV1(serial: s, event: 43))
        XCTAssertEqual(p.barva, .rdece)
        XCTAssertEqual(p.naslov, "ALREADY SCANNED")
        XCTAssertTrue(a.spletniKlici.isEmpty)   // odlocitev je lokalna
        XCTAssertEqual(seja.spustiRocno(qr: Pomoc.kodaV1(serial: s, event: 43)).naslov, "ALREADY SCANNED")
        XCTAssertEqual(vnosiNaDisku().count, 1)
    }

    /// Dogodek izstopi iz okna, medtem ko sken caka na streznik: lokalni zapis (zeleno) ne izgine, zavrnitev ga pobrise z diska.
    func testDogodekIzstopiMedCakanjemNaStreznik() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        for streznikPraviOk in [true, false] {
            let s1 = Pomoc.serial()
            let a = api(vstopnice: [ScanListTicket(serial: s1)])
            a.dogodkiOdgovor = .success([Pomoc.dogodek(42, zacetek: t0.addingTimeInterval(-3600), konec: t0.addingTimeInterval(5 * 3600))])
            if !streznikPraviOk {
                a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "already_used") }) }
            }
            let vrata = Vrata()
            a.vrataPaketa = vrata
            let seja = naredi(a, rok: 30)
            seja.ura = { ura.zdaj }
            await seja.naloziDogodke()
            let sken = Task { await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42)) }
            let poslano = await pocakaj { a.paketi.count == 1 }
            XCTAssertTrue(poslano)
            seja.uskladiAktivne(zdaj: t0.addingTimeInterval(40 * 3600))   // dogodek izstopi iz okna
            XCTAssertTrue(seja.aktivni.isEmpty)
            vrata.odpri()
            let p = await sken.value
            let lokalni = SkenDisk(mapa: mapa).preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: 1, dogodek: 42))?.casi ?? [:]
            if streznikPraviOk {
                XCTAssertEqual(p.barva, .zeleno)
                XCTAssertNotNil(lokalni[s1], "lokalni zapis zelenega skena mora ostati")
            } else {
                XCTAssertEqual(p.barva, .rdece)
                XCTAssertNil(lokalni[s1], "strezniska zavrnitev pobrise lokalni zapis tudi za izstopil dogodek")
            }
            try? FileManager.default.removeItem(at: mapa)
            try? FileManager.default.createDirectory(at: mapa, withIntermediateDirectories: true)
        }
    }

    /// Vrsta na disku iz prejsnje razlicice (vnos za dogodek, ki ni vec / se ni aktiven) se po zagonu poslje.
    func testObstojecaVrstaNaDiskuSePosljeBrezAktivnegaDogodka() async {
        let serial = Pomoc.serial()
        let id = UUID().uuidString.lowercased()
        let json = #"{"clientScanId":"\#(id)","qr":"o2.x.y","serial":"\#(serial)","eventId":50,"klubId":1,"uporabnikId":7,"scannedAt":780000000}"#
        SkenDisk(mapa: mapa).podmapa(SkenVrsta.mapaVnosov).zapisiSurovo(Data(json.utf8), id + ".json")
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([])    // nobenega aktivnega dogodka
        let seja = naredi(a)
        XCTAssertEqual(seja.cakajoce, 1)
        await seja.naloziDogodke()
        XCTAssertTrue(seja.aktivni.isEmpty)
        await seja.poslji()
        await seja.pocakajPosiljanje()
        XCTAssertEqual(a.paketi.flatMap { $0 }.map { $0.clientScanId }, [id])
        XCTAssertEqual(a.paketi.flatMap { $0 }.first?.eventId, 50)
        XCTAssertEqual(seja.cakajoce, 0)
    }

    /// Dogodek izstopi in znova vstopi, medtem ko stari prenos seznama se visi: stari rezultat ne sme odkleniti oznake novega vstopa.
    func testZaostaliPrenosStaregaVstopaNeOdklenePrenosaNovega() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.dogodek(42, zacetek: t0.addingTimeInterval(-3600), konec: t0.addingTimeInterval(5 * 3600))])
        let seja = naredi(a)
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        XCTAssertEqual(a.seznamKlici, 1)

        let staraVrata = Vrata()
        a.vrataSeznama = staraVrata
        let stari = Task { await seja.osveziSeznam(42) }               // stari vstop: prenos visi
        let zacet = await pocakaj { a.seznamKlici == 2 }
        XCTAssertTrue(zacet)
        seja.uskladiAktivne(zdaj: t0.addingTimeInterval(40 * 3600))    // izstop
        seja.uskladiAktivne(zdaj: t0)                                  // nov vstop
        let novaVrata = Vrata()
        a.vrataSeznama = novaVrata
        let novi = Task { await seja.osveziSeznam(42) }                // nov vstop: prenos visi
        let zacet2 = await pocakaj { a.seznamKlici == 3 }
        XCTAssertTrue(zacet2)

        staraVrata.odpri()
        await stari.value                                              // stari prenos konca: njegov defer ne sme posegati v nov vstop
        let cetrti = Task { await seja.osveziSeznam(42) }              // nov prenos se vedno tece -> ne sme se zagnati se enkrat
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(a.seznamKlici, 3)
        novaVrata.odpri()                                              // sele zdaj, da test ob napaki ne obvisi
        await cetrti.value
        await novi.value
        XCTAssertNotNil(seja.zadnjiPrenos)
    }

    // MARK: Pregled tipov PR #45 (2. krog)

    /// Kriticno 1: delo, ki preklica ne upostevajo (send() ob 401 caka nestrukturiran refreshAccessToken, Supabase rok 30 s), ne smejo
    /// zadrzati vrat. Pred popravkom je withTaskGroup cakal na vse otroke: sken je trajal toliko kot pocasen streznik.
    func testPocasenKlicKiPreklicaNeUpostevaNeZadrziVrat() async {
        let s1 = Pomoc.serial(), s2 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1), ScanListTicket(serial: s2)])
        a.zakasnitevPaketa = 3
        let seja = naredi(a, rok: 0.2)
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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
        // Rok 1 s, streznik odgovori sele po 2 s: cakanje na streznik bi trajalo vsaj 1 s, zato je meja 0,9 s dalec od
        // obeh izidov (prej rok 0,3 s in meja 0,15 s: na obremenjenem CI runnerju je test padal brez napake v kodi).
        a.zakasnitevPaketa = 2
        let seja = naredi(a, rok: 1.0)
        await seja.naloziDogodke()
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))   // rok poteces
        XCTAssertFalse(seja.povezava)
        let zacetek = Date()
        let p2 = await seja.skeniraj(Pomoc.koda(kljuc, serial: s2, event: 42))
        XCTAssertEqual(p2.barva, .zeleno)
        XCTAssertTrue(Date().timeIntervalSince(zacetek) < 0.9, "drugi sken je cakal na streznik")
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
        a.seznamOdgovor = .failure(APIError.requestFailed(404, "Club not found."))
        await seja.osveziSeznam(42)
        XCTAssertTrue(seja.dostopOdvzet)
        let imena = Set(SkenDisk(mapa: mapa).imena())
        XCTAssertFalse(imena.contains(SkenDisk.imeSeznama(klub: 1, dogodek: 42)))
        // JSON oblika istega odgovora (scan-list, scan-batch)
        let b = api(vstopnice: [])
        let seja2 = naredi(b)
        await seja2.naloziDogodke()
        b.seznamOdgovor = .failure(APIError.requestFailed(404, #"{"error":"not_found","message":"Club not found."}"#))
        await seja2.osveziSeznam(42)
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
        await seja.naloziDogodke()
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
        await seja.naloziDogodke()
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

    /// Manjse 13: osvezitev enega dogodka ne sme odkleniti ali pobrisati oznake osvezitve drugega, ki ze tece (dvojen prenos).
    /// Prenosa visita na vratih, dokler jih test ne odpre: nic ne temelji na pravem casu.
    func testZakljucekOsvezitveDrugegaDogodkaNeOdklenePodvojenegaPrenosa() async {
        let a = api(vstopnice: [])
        a.dogodkiOdgovor = .success([Pomoc.aktivenDogodek(42, title: "A"), Pomoc.aktivenDogodek(43, title: "B")])
        let vrata = Vrata()
        a.vrataSeznama = vrata
        let seja = naredi(a)
        let nalaganje = Task { await seja.naloziDogodke() }    // prenos A visi na vratih
        let zacet = await pocakaj { a.seznamKlici == 1 }
        XCTAssertTrue(zacet)
        let drugi = Task { await seja.osveziSeznam(43) }       // B tece vzporedno
        let zacet2 = await pocakaj { a.seznamKlici == 2 }
        XCTAssertTrue(zacet2)
        let dvojnikA = Task { await seja.osveziSeznam(42) }    // A ze tece: ne sme zagnati drugega prenosa
        let dvojnikB = Task { await seja.osveziSeznam(43) }    // B ze tece: ne sme zagnati drugega prenosa
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)         // (negativni preizkus: poskusa bi morala koncati takoj)
        XCTAssertEqual(a.seznamKlici, 2)
        vrata.odpri()                                          // sele zdaj, da test ob napaki ne obvisi
        await dvojnikA.value
        await dvojnikB.value
        await nalaganje.value
        await drugi.value
        XCTAssertEqual(Set(a.seznamDogodki), [42, 43])
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

    /// Enkratno ciscenje starih API odgovorov na disku URLCache.shared: prvic pobrise, drugic ne (zastavica v UserDefaults).
    func testStareOdgovoreNaDiskuPocistiSamoEnkrat() {
        let ime = "outly-test-\(UUID().uuidString)"
        let privzetosti = UserDefaults(suiteName: ime)!
        defer { privzetosti.removePersistentDomain(forName: ime) }
        let predpomnilnik = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let url = URL(string: "https://outly.example/business/events/42/scan-list")!
        let zahteva = URLRequest(url: url)
        let odgovor = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
        func shrani() { predpomnilnik.storeCachedResponse(CachedURLResponse(response: odgovor, data: Data("{}".utf8)), for: zahteva) }
        shrani()
        XCTAssertTrue(APIPredpomnilnik.enkratnoPocistiStareOdgovore(privzetosti: privzetosti, predpomnilnik: predpomnilnik))
        XCTAssertNil(predpomnilnik.cachedResponse(for: zahteva))
        shrani()
        XCTAssertFalse(APIPredpomnilnik.enkratnoPocistiStareOdgovore(privzetosti: privzetosti, predpomnilnik: predpomnilnik))
        XCTAssertNotNil(predpomnilnik.cachedResponse(for: zahteva))   // drugic ne brise
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
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        _ = await seja.skeniraj(Pomoc.kodaV1(serial: Pomoc.serial(), event: 42))
        await seja.poslji()
        XCTAssertTrue(a.klubIdji.count >= 5)   // dogodki, kljuc, seznam, paket, spletni sken
        XCTAssertEqual(Set(a.klubIdji.map { $0 ?? -1 }), [5])
        // klub 0 (ni znan): glava se ne poslje
        let b = api(vstopnice: [])
        let brezKluba = naredi(b, klub: 0)
        await brezKluba.naloziDogodke()
        XCTAssertEqual(Set(b.klubIdji.map { $0 ?? -1 }), [-1])
    }

    // MARK: M8: nespremenjen seznam

    func testNespremenjenSeznamSeNeZapisujeZnova() async throws {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        let ura = TestnaUra(Date())
        seja.ura = { ura.zdaj }
        await seja.naloziDogodke()
        let datoteka = mapa.appendingPathComponent(SkenDisk.imeSeznama(klub: 1, dogodek: 42))
        XCTAssertTrue(FileManager.default.fileExists(atPath: datoteka.path))
        try Data("marker".utf8).write(to: datoteka)
        let prej = seja.zadnjiPrenos
        ura.zdaj = ura.zdaj.addingTimeInterval(30)
        await seja.osveziSeznam(42)   // isti odgovor
        XCTAssertEqual(try String(contentsOf: datoteka, encoding: .utf8), "marker")   // ni bil ponovno zapisan
        XCTAssertTrue((seja.zadnjiPrenos ?? .distantPast) > (prej ?? .distantFuture))     // cas prenosa se je osvezil
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))           // indeks je ostal
        XCTAssertEqual(p.barva, .zeleno)
        // spremenjen odgovor se zapise
        a.nastaviSeznam(ScanList(eventId: 42, kid: "kid1", tickets: [ScanListTicket(serial: s1), ScanListTicket(serial: Pomoc.serial())]))
        await seja.osveziSeznam(42)
        XCTAssertNotEqual(try String(contentsOf: datoteka, encoding: .utf8), "marker")
    }

    // MARK: M9: pokvarjen odgovor obdrzi stari seznam

    func testPokvarjenOdgovorSeznamaObdrziStariSeznam() async {
        let s1 = Pomoc.serial()
        let a = LazniApi(kljuc: Pomoc.scanKey(kljuc), seznam: ScanList(eventId: 42, kid: "kid1", tickets: [], transferredSerials: [s1]))
        let seja = naredi(a)
        await seja.naloziDogodke()
        a.seznamOdgovor = .success(Data(#"{"event_id":42,"tickets":"pokvarjeno"}"#.utf8))
        await seja.osveziSeznam(42)
        let p = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p.barva, .rdece)   // vstopnica je se vedno »prenesena«, praznega seznama ni
        // tudi na disku je ostal star seznam
        let druga = naredi(a)
        a.seznamOdgovor = .failure(URLError(.notConnectedToInternet))
        await druga.naloziDogodke()
        let p2 = await druga.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(p2.barva, .rdece)
    }

    // MARK: M11: starost seznama

    func testSvezSeznamNiStarInUspesnoOsvezevanjeBrisePogoj() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.naloziDogodke()
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
        seja.omrezjeSpremenjeno(gor: false)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        XCTAssertEqual(seja.cakajoce, 1)
        await seja.poslji()                // neuspel poskus (ozadnji poskus ob skenu se konca skupaj z njim)
        await seja.pocakajPosiljanje()
        XCTAssertEqual(seja.cakajoce, 1)
        // povezava je spet tu, a streznik pravi 403 (ni vec clan ekipe): najprej poslji, kar caka, nato pobrisi sezname
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") }) }
        a.seznamOdgovor = .failure(APIError.requestFailed(404, "Club not found."))   // pravi odgovor requireClub za izrecen klub
        await seja.osveziSeznam(42)
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
        await seja.naloziDogodke()
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
        a.seznamOdgovor = .failure(APIError.requestFailed(404, "Club not found."))
        await seja.osveziSeznam(42)
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

/// outly-app#108: ko scan-batch vrne delni paket (`error` za preostanek po SKEN_BATCH_ROK_MS, zasedena baza), telefon preostanka ne
/// poslje takoj znova, ampak z odmikom (5 s ... 60 s, raztros). Ura je podtaknjena; nic ne caka na pravi cas.
@MainActor
final class SkenOdmikPosiljanjaTests: XCTestCase {
    private var mapa: URL!

    override func setUp() async throws { mapa = Pomoc.zacasnaMapa() }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: mapa) }

    private func lazniApi() -> LazniApi {
        LazniApi(kljuc: Pomoc.scanKey(Curve25519.Signing.PrivateKey()), seznam: ScanList(eventId: 42, kid: "kid1", tickets: []))
    }

    /// Vrsta s `n` vnosi na disku (kot po vecerih brez povezave) in seja nad njo.
    private func seja(_ a: LazniApi, ura: TestnaUra, vnosov n: Int) -> (SkenSeja, SkenVrsta) {
        let disk = SkenDisk(mapa: mapa)
        let vrsta = SkenVrsta(disk: disk)
        for i in 0..<n {
            vrsta.dodaj(SkenVnos(qr: "o2.x.\(i)", serial: Pomoc.serial(), eventId: 42, klubId: 1, uporabnikId: 7,
                                 scannedAt: ura.zdaj.addingTimeInterval(Double(i))))
        }
        let s = SkenSeja(klubId: 1, uporabnikId: 7, api: a, disk: disk, deviceId: "naprava-1", vrsta: vrsta, rokStreznika: 1, rokSpletni: 1,
                         kljucOdmik: 0)
        s.zeton = { "zeton" }
        s.ura = { ura.zdaj }
        return (s, vrsta)
    }

    /// Caka na POGOJ (ne na cas): gornja meja je samo varovalka pred obvisanjem testa.
    private func pocakaj(_ pogoj: () -> Bool, rok: Double = 30) async -> Bool {
        let konec = Date().addingTimeInterval(rok)
        while !pogoj() && Date() < konec { try? await Task.sleep(nanoseconds: 2_000_000) }
        return pogoj()
    }

    private func odmik(_ s: SkenSeja, od t: Date) -> Double { s.posiljanjeOdlozenoDo.timeIntervalSince(t) }

    func testOdmikPosiljanjaJeEksponentenZRaztrosomInNajvec60s() {
        XCTAssertEqual(SkenSeja.odmikPosiljanja(1, raztros: 1), 5, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(2, raztros: 1), 10, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(3, raztros: 1), 20, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(4, raztros: 1), 40, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(5, raztros: 1), 50, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(100, raztros: 1.5), 60, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(1, raztros: 0.8), 4, accuracy: 1e-9)
        XCTAssertEqual(SkenSeja.odmikPosiljanja(0, raztros: 1), 5, accuracy: 1e-9)
        for _ in 0..<50 { XCTAssertTrue((3.99...6.01).contains(SkenSeja.odmikPosiljanja(1))) }
    }

    func testDelniPaketPrepozna() {
        let a = SkenVnos(clientScanId: "a", qr: "q", serial: nil, eventId: 42, klubId: 1, uporabnikId: 7)
        let b = SkenVnos(clientScanId: "b", qr: "q", serial: nil, eventId: 42, klubId: 1, uporabnikId: 7)
        let ok = ScanBatchResult(clientScanId: "a", result: "ok")
        XCTAssertFalse(SkenSeja.jeDelniPaket([ok, ScanBatchResult(clientScanId: "b", result: "already_used")], poslani: [a, b]))
        XCTAssertTrue(SkenSeja.jeDelniPaket([ok, ScanBatchResult(clientScanId: "b", result: "error")], poslani: [a, b]))
        XCTAssertTrue(SkenSeja.jeDelniPaket([ok], poslani: [a, b]))   // rezultat manjka
    }

    func testDelniPaketPreostanekZOdmikomNeTakoj() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = lazniApi()
        // Backend ob zasedeni bazi: prvi element obdelan, preostali `error`.
        a.paketOdgovor = { v in .success(v.enumerated().map { e in
            ScanBatchResult(clientScanId: e.element.clientScanId, serial: e.element.serial, result: e.offset == 0 ? "ok" : "error")
        }) }
        let (s, vrsta) = seja(a, ura: ura, vnosov: 3)
        XCTAssertEqual(s.cakajoce, 3)

        await s.poslji()
        XCTAssertEqual(a.paketi.count, 1)          // pred popravkom: takoj druga zahteva s preostankom
        XCTAssertEqual(s.cakajoce, 2)              // obdelani je sel iz vrste, `error` ostaneta
        let prvi = odmik(s, od: t0)
        XCTAssertTrue((3.99...6.01).contains(prvi), "prvi odmik ~5 s: \(prvi)")

        // Vratar odklene telefon / omrezje se vrne: odmik zasedene baze ostane.
        s.takojOsvezi()
        XCTAssertEqual(odmik(s, od: t0), prvi)
        s.omrezjeSpremenjeno(gor: false)
        s.omrezjeSpremenjeno(gor: true)
        XCTAssertEqual(odmik(s, od: t0), prvi)
        // Odhod z zaslona med odmikom ne poslje (vnosi so na disku).
        await s.posljiObOdhodu()
        XCTAssertEqual(a.paketi.count, 1)

        // Se en delni paket: odmik se podvoji.
        ura.zdaj = s.posiljanjeOdlozenoDo
        await s.poslji()
        XCTAssertEqual(a.paketi.count, 2)
        XCTAssertEqual(s.cakajoce, 1)
        let drugi = odmik(s, od: ura.zdaj)
        XCTAssertTrue((7.99...12.01).contains(drugi), "drugi odmik ~10 s: \(drugi)")

        // Po izteku odmika tik poslje preostanek; uspesen paket brez `error` odmik ponastavi.
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") }) }
        ura.zdaj = s.posiljanjeOdlozenoDo
        s.tik()
        let poslano = await pocakaj { a.paketi.count == 3 }
        XCTAssertTrue(poslano)
        await s.pocakajPosiljanje()
        XCTAssertEqual(s.cakajoce, 0)

        // Ponastavljeno: naslednji delni paket spet zacne pri ~5 s, ne pri ~20 s.
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, result: "error") }) }
        vrsta.dodaj(SkenVnos(qr: "o2.x.n", serial: Pomoc.serial(), eventId: 42, klubId: 1, uporabnikId: 7, scannedAt: ura.zdaj))
        await s.poslji()
        let tretji = odmik(s, od: ura.zdaj)
        XCTAssertTrue((3.99...6.01).contains(tretji), "po uspehu spet ~5 s: \(tretji)")
    }

    /// 503 (preobremenjen streznik) se obnasa kot `error`: vrnitev v ospredje odmika ne preskoci. Izpad omrezja (ni odgovora) ga preskoci.
    func testOdmikOb503OstaneOdmikOmrezjaSePreskoci() async {
        let t0 = Pomoc.sedajNaSekundo()
        let ura = TestnaUra(t0)
        let a = lazniApi()
        a.paketOdgovor = { _ in .failure(APIError.requestFailed(503, "Service temporarily unavailable. Please try again shortly.")) }
        let (s, _) = seja(a, ura: ura, vnosov: 1)
        await s.poslji()
        XCTAssertEqual(s.cakajoce, 1)
        let prvi = odmik(s, od: t0)
        XCTAssertTrue((3.99...6.01).contains(prvi))
        s.takojOsvezi()
        XCTAssertEqual(odmik(s, od: t0), prvi)
        // Po izteku odmika ga takojOsvezi spet sme ponastaviti.
        ura.zdaj = s.posiljanjeOdlozenoDo
        s.takojOsvezi()
        XCTAssertEqual(s.posiljanjeOdlozenoDo, .distantPast)

        a.paketOdgovor = { _ in .failure(URLError(.notConnectedToInternet)) }
        await s.poslji()
        XCTAssertGreaterThan(s.posiljanjeOdlozenoDo, ura.zdaj)
        s.takojOsvezi()                            // povezava je nazaj: skeni gredo takoj
        XCTAssertEqual(s.posiljanjeOdlozenoDo, .distantPast)
    }
}
