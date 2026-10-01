import XCTest
import Foundation
import CryptoKit
@testable import Outly

// Sken vstopnic brez povezave (backend issue #86): preverjanje kode v2, vrsta, odlocitev, SkenSeja z lazno API-jem.
// Koda se podpise v testu s CryptoKit kot streznik (Ed25519 nad "o2.<base64url(JSON)>").

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
}

// MARK: - Razclenjevanje in podpis

final class SkenKodaTests: XCTestCase {
    private let kljuc = Curve25519.Signing.PrivateKey()

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

    func testKodaV1InSmetiNisoV2() {
        XCTAssertEqual(SkenKoda.razcleni("eyJ0IjoiYWJjIn0.0123456789abcdef0123456789abcdef"), .v1)
        XCTAssertEqual(SkenKoda.razcleni(""), .neznano)
        XCTAssertEqual(SkenKoda.razcleni("https://example.com/x"), .neznano)
        XCTAssertEqual(SkenKoda.razcleni("o2.abc"), .v1)   // dva dela: oblika v1 (preveri streznik)
        XCTAssertEqual(SkenKoda.razcleni("o2.@@@.@@@"), .neznano)
        XCTAssertEqual(SkenKoda.razcleni("o2.\(Pomoc.telo(serial: "ni-uuid", event: 1)).\(Pomoc.b64url(Data(count: 64)))"), .neznano)
        XCTAssertEqual(SkenKoda.razcleni("o2.\(Pomoc.telo(serial: Pomoc.serial(), event: 1)).\(Pomoc.b64url(Data(count: 10)))"), .neznano)
        XCTAssertEqual(SkenKoda.razcleni(String(repeating: "a", count: 2000)), .neznano)
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

    private func odloci(_ qr: String, seznam: ScanList?, lokalni: [String: Date] = [:], kljucPodatek: Data? = nil) -> SkenSodba {
        SkenOdlocitev.odloci(qr: qr, dogodekId: dogodek, kljuc: kljucPodatek ?? Pomoc.javni(kljuc),
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

    func testSpremenjenPodpisTeloAliKljucJeRdece() {
        let s = Pomoc.serial()
        let seznam = ScanList(eventId: dogodek, tickets: [ScanListTicket(serial: s)])
        let qr = Pomoc.koda(kljuc, serial: s, event: dogodek)
        let deli = qr.split(separator: ".").map(String.init)
        var podpis = Data(base64URL: deli[2])!
        podpis[10] ^= 0xff
        XCTAssertEqual(odloci("\(deli[0]).\(deli[1]).\(Pomoc.b64url(podpis))", seznam: seznam).razlog, .neveljavna)
        XCTAssertEqual(odloci("o2.\(Pomoc.telo(serial: s, event: 99)).\(deli[2])", seznam: seznam).razlog, .neveljavna)
        XCTAssertEqual(odloci(qr, seznam: seznam, kljucPodatek: Pomoc.javni(Curve25519.Signing.PrivateKey())).razlog, .neveljavna)
        XCTAssertEqual(odloci("nekaj tretjega", seznam: seznam).razlog, .neveljavna)
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
        let u = Pomoc.serial(), v = Pomoc.serial(), x = Pomoc.serial()
        let seznam = ScanList(eventId: dogodek, tickets: [
            ScanListTicket(serial: u, status: "used", usedAt: "2026-10-01T21:15:00.000Z"),
            ScanListTicket(serial: v, status: "refunded"),
            ScanListTicket(serial: x, status: "void"),
        ])
        let ru = odloci(Pomoc.koda(kljuc, serial: u, event: dogodek), seznam: seznam)
        XCTAssertEqual(ru.razlog, .zeUporabljena)
        XCTAssertEqual(ru.kdaj, SkenCas.razcleni("2026-10-01T21:15:00.000Z"))
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: v, event: dogodek), seznam: seznam).razlog, .vrnjena)
        XCTAssertEqual(odloci(Pomoc.koda(kljuc, serial: x, event: dogodek), seznam: seznam).razlog, .preklicana)
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
        XCTAssertEqual(odloci("e30.0123456789abcdef", seznam: ScanList(eventId: dogodek)).razlog, .staraKoda)
        XCTAssertEqual(odloci("e30.0123456789abcdef", seznam: ScanList(eventId: dogodek)).barva, .rumeno)
        let brez = SkenOdlocitev.odloci(qr: Pomoc.koda(kljuc, serial: s, event: dogodek), dogodekId: dogodek, kljuc: nil, indeks: nil, lokalni: [:])
        XCTAssertEqual(brez.razlog, .manjkaPodatkov)
        XCTAssertEqual(brez.barva, .rumeno)
        // koda v1, ki je bila ze spuscena na tej napravi, je rdeca
        let cas = Date()
        XCTAssertEqual(odloci("e30.0123456789abcdef", seznam: ScanList(eventId: dogodek), lokalni: ["e30.0123456789abcdef": cas]).razlog, .zeUporabljenaLokalno)
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
        XCTAssertEqual(l.tickets[1].status, "valid")   // privzeto
        XCTAssertFalse(l.tickets[1].isVip)
        XCTAssertEqual(l.transferredSerials, ["OLD"])
        let prazno = try JSONDecoder().decode(ScanList.self, from: Data("{}".utf8))
        XCTAssertEqual(prazno.tickets.count, 0)

        let k = try JSONDecoder().decode(ScanKey.self, from: Data(#"{"alg":"Ed25519","kid":"k","public_key":"\#(Pomoc.b64url(Data(count: 32)))","qr_format":"x"}"#.utf8))
        XCTAssertEqual(k.kid, "k")
        XCTAssertEqual(k.surovi?.count, 32)
        XCTAssertNil(ScanKey(alg: "RSA", kid: "k", publicKey: Pomoc.b64url(Data(count: 32))).surovi)
        XCTAssertNil(ScanKey(kid: "k", publicKey: "kratek").surovi)
    }

    func testRezultatiBatcha() throws {
        let json = #"[{"client_scan_id":"a","serial":"s","result":"ok","used_at":"2026-10-01T21:00:00.000Z"},{"client_scan_id":"b","serial":null,"result":"error","used_at":null},{"result":"invalid"}]"#
        let r = try JSONDecoder().decode([ScanBatchResult].self, from: Data(json.utf8))
        XCTAssertTrue(r[0].jeDokoncen)
        XCTAssertFalse(r[1].jeDokoncen)   // error ostane v vrsti
        XCTAssertFalse(r[2].jeDokoncen)   // brez client_scan_id ga ni mogoce povezati z vnosom
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

    private func vnos(_ id: String = UUID().uuidString.lowercased(), klub: Int = 1, uporabnik: Int? = 7, dogodek: Int = 42) -> SkenVnos {
        SkenVnos(clientScanId: id, qr: "o2.x.y", serial: Pomoc.serial(), eventId: dogodek, klubId: klub, uporabnikId: uporabnik, imetnik: "ana")
    }

    func testVrstaPrezivi_ponovniZagon() {
        let a = vnos(), b = vnos()
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

private final class LazniApi: SkenApi {
    var kljucOdgovor: Result<ScanKey, Error>
    var seznamOdgovor: Result<ScanList, Error>
    var paketOdgovor: ([SkenVnos]) -> Result<[ScanBatchResult], Error> = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "ok") }) }
    var spletniOdgovor: Result<ScanResult, Error> = .success(ScanResult(result: "ok", message: "Welcome", usedAt: nil))
    var dogodkiOdgovor: Result<[SkenDogodek], Error> = .success([])
    private(set) var paketi: [[SkenVnos]] = []
    private(set) var deviceIdji: [String] = []
    private(set) var spletniKlici: [String] = []

    init(kljuc: ScanKey, seznam: ScanList) {
        kljucOdgovor = .success(kljuc)
        seznamOdgovor = .success(seznam)
    }

    func dogodki(token: String) async throws -> [SkenDogodek] { try dogodkiOdgovor.get() }
    func kljuc(token: String) async throws -> ScanKey { try kljucOdgovor.get() }
    func seznam(token: String, dogodekId: Int) async throws -> ScanList { try seznamOdgovor.get() }
    func paket(token: String, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        paketi.append(vnosi)
        deviceIdji.append(deviceId)
        return try paketOdgovor(vnosi).get()
    }
    func spletniSken(token: String, qr: String) async throws -> ScanResult {
        spletniKlici.append(qr)
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

    private func naredi(_ api: LazniApi, deviceId: String = "naprava-1") -> SkenSeja {
        // Nova vrsta z diska = nov zagon aplikacije (vsaka seja prebere vrsto in lokalne skene znova z diska).
        let disk = SkenDisk(mapa: mapa)
        let s = SkenSeja(klubId: 1, uporabnikId: 7, api: api, disk: disk, deviceId: deviceId, vrsta: SkenVrsta(disk: disk))
        s.zeton = { "zeton" }
        return s
    }

    private func api(vstopnice: [ScanListTicket]) -> LazniApi {
        LazniApi(kljuc: Pomoc.scanKey(kljuc), seznam: ScanList(eventId: 42, generatedAt: "2026-10-01T20:00:00Z", kid: "kid1", tickets: vstopnice))
    }

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

    func testAlreadyUsedOdStreznikaPostaneKonflikt() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1, holderUsername: "ana")])
        a.paketOdgovor = { v in .success(v.map { ScanBatchResult(clientScanId: $0.clientScanId, serial: $0.serial, result: "already_used", usedAt: "2026-10-01T20:59:00.000Z") }) }
        let seja = naredi(a)
        await seja.odpri(dogodek)
        _ = await seja.skeniraj(Pomoc.koda(kljuc, serial: s1, event: 42))
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
        XCTAssertTrue(a.spletniKlici.isEmpty)   // brez povezave nobenega spletnega klica
    }

    func testStaraKodaBrezPovezaveJeRumenaSPovezavoGreNaStreznik() async {
        let a = api(vstopnice: [])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        let v1 = "eyJ0IjoiYWJjIn0.0123456789abcdef0123456789abcdef"

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
        let v1b = "eyJ0IjoieHl6In0.fedcba9876543210fedcba9876543210"
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

    func testSpremenjenKidPonovnoPrenesePodpisniKljuc() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        // streznik zamenja skrivnost -> nov par in nov kid
        let novi = Curve25519.Signing.PrivateKey()
        a.kljucOdgovor = .success(Pomoc.scanKey(novi, kid: "kid2"))
        a.seznamOdgovor = .success(ScanList(eventId: 42, kid: "kid2", tickets: [ScanListTicket(serial: s1)]))
        await seja.osveziSeznam()
        let noviSken = await seja.skeniraj(Pomoc.koda(novi, serial: s1, event: 42, kid: "kid2"))
        XCTAssertEqual(noviSken.barva, .zeleno)
        // star kljuc ni vec veljaven
        let stariSken = await seja.skeniraj(Pomoc.koda(kljuc, serial: Pomoc.serial(), event: 42))
        XCTAssertEqual(stariSken.barva, .rdece)
    }

    func testNovKidBrezMoznostiPrenosaKljucaNeDaNapacnegaRdecega() async {
        let s1 = Pomoc.serial()
        let a = api(vstopnice: [ScanListTicket(serial: s1)])
        let seja = naredi(a)
        await seja.odpri(dogodek)
        a.kljucOdgovor = .failure(URLError(.timedOut))
        a.seznamOdgovor = .success(ScanList(eventId: 42, kid: "kid2", tickets: [ScanListTicket(serial: s1)]))
        await seja.osveziSeznam()
        a.spletniOdgovor = .failure(URLError(.timedOut))   // tudi spletni sken ne uspe
        let novi = Curve25519.Signing.PrivateKey()
        let p = await seja.skeniraj(Pomoc.koda(novi, serial: s1, event: 42, kid: "kid2"))
        XCTAssertEqual(p.barva, .rumeno)   // kljuca ni: odlocitev prepusti vratarju / strezniku
        XCTAssertEqual(a.spletniKlici.count, 1)   // a najprej poskusi streznik
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
