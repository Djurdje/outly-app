import XCTest
import Foundation
@testable import Outly

/// Odlocitve 19. 10. 2026: racun od 18 let (po ljubljanskem koledarju, meja samo ob spremembi datuma), pogoji 1.1.4,
/// seznam vstopnic za vrata (#277 N1), potrditev cene vstopnice (#277 N2), spletna stran kluba (#293, I48), prodajalec platforma (I50).
/// Vse cisto: fiksni datumi in koledarji, brez omrezja, deljenega stanja in cakanja.
@MainActor
final class Racun18InVrataTests: XCTestCase {

    private func dan(_ s: String) -> StarostRacuna.Dan { StarostRacuna.dan(iz: s)! }

    private var utc: Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "UTC")!
        return k
    }

    private func trenutek(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: - Starost racuna (18)

    func testMejaJe18() {
        XCTAssertEqual(StarostRacuna.najmanjLet, 18)
    }

    func testPolnaLetaKotNaStrezniku() {
        XCTAssertTrue(StarostRacuna.jeDovoljStar(rojstvo: dan("2008-10-19"), danes: dan("2026-10-19")))   // 18. rojstni dan
        XCTAssertFalse(StarostRacuna.jeDovoljStar(rojstvo: dan("2008-10-20"), danes: dan("2026-10-19")))  // dan pred
        XCTAssertFalse(StarostRacuna.jeDovoljStar(rojstvo: dan("2010-01-01"), danes: dan("2026-10-19")))  // 16 let
        XCTAssertEqual(StarostRacuna.polnaLeta(rojstvo: dan("2008-11-01"), danes: dan("2026-10-19")), 17)
    }

    func testRojenNa29FebruarDopolniLetoPrvegaMarca() {
        XCTAssertFalse(StarostRacuna.jeDovoljStar(rojstvo: dan("2008-02-29"), danes: dan("2026-02-28")))
        XCTAssertTrue(StarostRacuna.jeDovoljStar(rojstvo: dan("2008-02-29"), danes: dan("2026-03-01")))
    }

    func testNajkasnejsiRojstniDanJeDanesMinus18Let() {
        XCTAssertEqual(StarostRacuna.najkasnejsiRojstniDan(danes: dan("2026-10-19")), dan("2008-10-19"))
        // 29. 2. v prestopnem letu -> 28. 2. v neprestopnem ciljnem letu.
        XCTAssertEqual(StarostRacuna.najkasnejsiRojstniDan(danes: dan("2028-02-29")), dan("2010-02-28"))
        XCTAssertEqual(StarostRacuna.najkasnejsiRojstniDan(danes: dan("2024-02-29")), dan("2006-02-28"))
        XCTAssertEqual(StarostRacuna.najkasnejsiRojstniDan(danes: dan("2026-02-28")), dan("2008-02-28"))
    }

    func testDanesSeStejePoLjubljanskemKoledarju() {
        // 23:30 UTC 18. 10. je v Ljubljani ze 19. 10. (01:30, poletni cas).
        XCTAssertEqual(StarostRacuna.dan(trenutek("2026-10-18T23:30:00Z")), dan("2026-10-19"))
        XCTAssertEqual(StarostRacuna.dan(trenutek("2026-10-19T10:00:00Z")), dan("2026-10-19"))
    }

    func testZgornjaMejaIzbirnikaJeKonecNajkasnejsegaDne() {
        let meja = StarostRacuna.zgornjaMejaIzbirnika(zdaj: trenutek("2026-10-19T10:00:00Z"), koledarNaprave: utc)
        XCTAssertEqual(meja, trenutek("2008-10-19T23:59:59Z"))
        // Po ljubljanskem koledarju je ze 19. 10., ceprav je v UTC se 18. 10.
        let opolnoci = StarostRacuna.zgornjaMejaIzbirnika(zdaj: trenutek("2026-10-18T23:30:00Z"), koledarNaprave: utc)
        XCTAssertEqual(opolnoci, trenutek("2008-10-19T23:59:59Z"))
    }

    func testZgornjaMejaVkljuciObstojecDatumMladoletnega() {
        let obstojec = trenutek("2010-05-05T00:00:00Z")
        let meja = StarostRacuna.zgornjaMejaIzbirnika(zdaj: trenutek("2026-10-19T10:00:00Z"), obstojec: obstojec, koledarNaprave: utc)
        XCTAssertEqual(meja, obstojec)
        // Starejsi obstojec datum mejo pusti pri danes - 18 let.
        let star = StarostRacuna.zgornjaMejaIzbirnika(zdaj: trenutek("2026-10-19T10:00:00Z"),
                                                      obstojec: trenutek("1990-01-01T00:00:00Z"), koledarNaprave: utc)
        XCTAssertEqual(star, trenutek("2008-10-19T23:59:59Z"))
    }

    func testBudisticniInHebrejskiKoledarNapraveNePodreMeje() {
        // Leta so gregorijanska: z budisticnim koledarjem bi bila meja leta 1465 (pred spodnjo) in min...max bi sesul aplikacijo.
        let zdaj = trenutek("2026-10-19T10:00:00Z")
        for id in [Calendar.Identifier.buddhist, .hebrew, .japanese, .islamicUmmAlQura] {
            var k = Calendar(identifier: id)
            k.timeZone = TimeZone(identifier: "UTC")!
            XCTAssertEqual(StarostRacuna.zgornjaMejaIzbirnika(zdaj: zdaj, koledarNaprave: k), trenutek("2008-10-19T23:59:59Z"), "\(id)")
            let obseg = StarostRacuna.obsegIzbirnika(zdaj: zdaj, koledarNaprave: k)
            XCTAssertLessThan(obseg.lowerBound, obseg.upperBound, "\(id)")
            XCTAssertEqual(obseg.upperBound, trenutek("2008-10-19T23:59:59Z"), "\(id)")
        }
    }

    func testObsegIzbirnikaJe120LetNazaj() {
        let obseg = StarostRacuna.obsegIzbirnika(zdaj: trenutek("2026-10-19T10:00:00Z"), koledarNaprave: utc)
        XCTAssertEqual(obseg.lowerBound, trenutek("1906-10-19T10:00:00Z"))
    }

    func testIstiDatumObstojecegaRacunaSeSmeShranitiSpremembaPodMejoNe() {
        let danes = dan("2026-10-19")
        XCTAssertTrue(StarostRacuna.smeShraniti(izbran: "2010-05-05", shranjen: "2010-05-05", danes: danes))  // 16 let, nespremenjen
        XCTAssertFalse(StarostRacuna.smeShraniti(izbran: "2010-05-06", shranjen: "2010-05-05", danes: danes)) // sprememba, 16 let
        XCTAssertFalse(StarostRacuna.smeShraniti(izbran: "2010-05-05", shranjen: nil, danes: danes))          // nov vnos, 16 let
        XCTAssertTrue(StarostRacuna.smeShraniti(izbran: "2000-01-01", shranjen: "2010-05-05", danes: danes))  // sprememba, 26 let
        XCTAssertFalse(StarostRacuna.smeShraniti(izbran: "ni-datum", shranjen: nil, danes: danes))
    }

    func testDatumIzNiza() {
        XCTAssertEqual(StarostRacuna.dan(iz: "2008-02-29"), StarostRacuna.Dan(leto: 2008, mesec: 2, dan: 29))
        XCTAssertNil(StarostRacuna.dan(iz: "2008-13-01"))
        XCTAssertNil(StarostRacuna.dan(iz: "2008/01/01"))
        XCTAssertNil(StarostRacuna.dan(iz: ""))
    }

    // MARK: - Sporocila napak

    func testNovoInStaroSporociloStarostiRacuna() {
        XCTAssertEqual(APIError.requestFailed(400, "You must be at least 18 years old.").userMessage,
                       String(localized: "You must be at least 18 years old to use Outly."))
        XCTAssertEqual(APIError.requestFailed(400, "You must be at least 15 years old.").userMessage,
                       String(localized: "You must be at least 15 years old to use Outly."))
        // Meja nakupa ostane svoja (ne sme postati sporocilo o racunu).
        XCTAssertEqual(APIError.requestFailed(403, "You must be at least 18 to buy tickets for this event.").userMessage,
                       String(localized: "You must be at least \(18) to buy tickets for this event."))
    }

    func testSpremenjenaCenaVstopniceNiCenaMize() {
        let vstopnica = APIError.requestFailed(409, "The ticket price has changed.")
        XCTAssertEqual(vstopnica.userMessage, String(localized: "The ticket price has changed. Check the new price and try again."))
        XCTAssertTrue(vstopnica.jeSpremenjenaCenaVstopnice)
        XCTAssertEqual(vstopnica.nakupniIzid, .navadna)   // narocila ni, kljuc ostane za ponovni poskus

        let miza = APIError.requestFailed(409, "The table price has changed.")
        XCTAssertEqual(miza.userMessage, String(localized: "The table price has changed. Check the new price and try again."))
        XCTAssertFalse(miza.jeSpremenjenaCenaVstopnice)
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"table_unavailable","message":"The table price has changed."}"#).userMessage,
                       String(localized: "The table price has changed. Check the new price and try again."))
        XCTAssertFalse(APIError.requestFailed(400, "The ticket price has changed.").jeSpremenjenaCenaVstopnice)
    }

    func testNapacnaPovezavaPoPolju() {
        func napaka(_ polje: String) -> String {
            APIError.requestFailed(400, #"{"error":"invalid_url","field":"\#(polje)","message":"\#(polje) must be a web link starting with http:// or https://."}"#).userMessage
        }
        XCTAssertEqual(napaka("website"), String(localized: "Enter a website link starting with http:// or https://, e.g. https://klub.si."))
        XCTAssertEqual(napaka("instagram"), String(localized: "Enter an Instagram handle like @velvet.lj or a link starting with https://."))
        XCTAssertEqual(napaka("ticket_url"), String(localized: "Enter a ticket link starting with http:// or https://."))
        XCTAssertEqual(napaka("logo_url"), String(localized: "The image link is not valid. Upload the image again."))
        XCTAssertEqual(napaka("kaj_drugega"), String(localized: "Enter a link starting with http:// or https://."))
        XCTAssertEqual(APIError.requestFailed(400, "invalid_url").userMessage, String(localized: "Enter a link starting with http:// or https://."))
        XCTAssertEqual(APIError.poljeNapake(#"{"error":"invalid_url","field":"website"}"#), "website")
        XCTAssertNil(APIError.poljeNapake("Bad request"))
    }

    func testSeznamVstopnicZasedenInNapacnoIskanje() {
        let zaseden = APIError.requestFailed(503, #"{"error":"search_timeout","message":"The ticket list is busy. Try again in a few seconds."}"#)
        XCTAssertEqual(zaseden.userMessage, String(localized: "The ticket list is busy. Try again in a few seconds."))
        XCTAssertEqual(APIError.requestFailed(400, #"{"error":"invalid_q"}"#).userMessage,
                       String(localized: "Search text is too long or contains characters that aren't allowed."))
    }

    // MARK: - Seznam vstopnic za vrata (#277 N1)

    private func vrednosti(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testPoizvedbaPrveStraniImaSamoLimit200() {
        XCTAssertEqual(vrednosti(APIClient.poizvedbaVstopnicDogodka()), ["limit": "200"])
        XCTAssertEqual(APIClient.stranVstopnicVrata, 200)
    }

    func testPoizvedbaNaprejInIskanje() {
        XCTAssertEqual(vrednosti(APIClient.poizvedbaVstopnicDogodka(offset: 200, q: "  ana  ")),
                       ["limit": "200", "offset": "200", "q": "ana"])
        // Prazno / samo presledki = brez filtra; limit znotraj 0...1000.
        XCTAssertEqual(vrednosti(APIClient.poizvedbaVstopnicDogodka(limit: 5000, q: "   ")), ["limit": "1000"])
        XCTAssertEqual(vrednosti(APIClient.poizvedbaVstopnicDogodka(limit: -3)), ["limit": "0"])
    }

    func testIskanjeBrezKontrolnihZnakovInNajvec64EnotUtf16() {
        XCTAssertEqual(APIClient.ocistiIskanjeVstopnic("a\u{0}b\nc"), "abc")
        XCTAssertEqual(APIClient.ocistiIskanjeVstopnic(String(repeating: "x", count: 80)).count, 64)
        let emoji = APIClient.ocistiIskanjeVstopnic(String(repeating: "😀", count: 40))
        XCTAssertLessThanOrEqual(emoji.utf16.count, 64)
        XCTAssertEqual(emoji.count, 32)   // celi znaki, ne pol emojija
    }

    func testPlusVPoizvedbiOstaneDobesedenZnak() throws {
        let r = try APIClient.shared.sestaviZahtevek(path: "business/events/7/tickets", method: "GET", token: "tok", json: nil,
                                                     query: APIClient.poizvedbaVstopnicDogodka(q: "ana+klub@gmail.com"),
                                                     clubId: nil, timeout: nil, idempotencyKey: nil)
        let poizvedba = try XCTUnwrap(r.url?.query)
        XCTAssertTrue(poizvedba.contains("q=ana%2Bklub@gmail.com"), poizvedba)
        XCTAssertFalse(poizvedba.contains("+"))
    }

    func testOvojnicaSeznamaVstopnic() throws {
        let json = #"""
        {"tickets": [{"id": 1, "status": "used"}, {"id": 2, "status": "valid"}],
         "counts": {"all": 1500, "sold": 1450, "checked_in": 300, "expected": 1150, "refunded": 40, "void": 10},
         "total": 1500, "limit": 200, "offset": 0, "has_more": true, "next_offset": 200}
        """#
        let s = try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(json.utf8))
        XCTAssertEqual(s.tickets.map(\.id), [1, 2])
        XCTAssertEqual(s.counts, SeznamVstopnicDogodka.Stevci(all: 1500, sold: 1450, checkedIn: 300, expected: 1150, refunded: 40, void: 10))
        XCTAssertEqual(s.total, 1500)
        XCTAssertTrue(s.hasMore)
        XCTAssertEqual(s.nextOffset, 200)
        XCTAssertTrue(s.ovojnica)
    }

    func testZadnjaStranInHasMoreBrezOdmikaNeZacikla() throws {
        let zadnja = try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(
            #"{"tickets": [], "counts": {"all": 0}, "total": 0, "has_more": false, "next_offset": null}"#.utf8))
        XCTAssertFalse(zadnja.hasMore)
        XCTAssertNil(zadnja.nextOffset)
        let brezOdmika = try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(
            #"{"tickets": [{"id": 3}], "has_more": true}"#.utf8))
        XCTAssertFalse(brezOdmika.hasMore)
        XCTAssertNil(brezOdmika.nextOffset)
        XCTAssertEqual(brezOdmika.counts.all, 1)   // brez `counts`: iz vrstic
    }

    func testStarBackendGoloPoljeStevciIzVrstic() throws {
        let json = #"[{"id": 1, "status": "used"}, {"id": 2, "status": "valid"}, {"id": 3, "status": "refunded"}, {"id": 4, "status": "void"}]"#
        let s = try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(json.utf8))
        XCTAssertFalse(s.ovojnica)
        XCTAssertFalse(s.hasMore)
        XCTAssertEqual(s.counts, SeznamVstopnicDogodka.Stevci(all: 4, sold: 2, checkedIn: 1, expected: 1, refunded: 1, void: 1))
    }

    // MARK: - Load more in iskanje (VrataSeznam)

    private func stran(_ json: String) throws -> SeznamVstopnicDogodka {
        try JSONDecoder().decode(SeznamVstopnicDogodka.self, from: Data(json.utf8))
    }

    func testLoadMoreSeNovimIskanjemInStarimOdmikomNeZgodi() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}, {"id": 2}], "counts": {"all": 400}, "total": 400, "has_more": true, "next_offset": 200}"#),
                   iskanje: "")
        XCTAssertEqual(s.odmikNaprej(iskanje: ""), 200)
        XCTAssertEqual(s.odmikNaprej(iskanje: "  "), 200)          // ocisceno je isto iskanje
        // Uporabnik tipka (premor pred novim nalaganjem): gumba ni, stran za drugo iskanje se ne pripne.
        XCTAssertNil(s.odmikNaprej(iskanje: "ana"))
        XCTAssertFalse(s.pripni(try stran(#"{"tickets": [{"id": 9}], "has_more": false}"#), iskanje: "ana", odmik: 200))
        XCTAssertEqual(s.vrstice.map(\.id), [1, 2])
        // Isto iskanje: pripne brez podvojenih, odmik naprej.
        XCTAssertTrue(s.pripni(try stran(#"{"tickets": [{"id": 2}, {"id": 3}], "counts": {"all": 400}, "total": 400, "has_more": true, "next_offset": 400}"#),
                               iskanje: "", odmik: 200))
        XCTAssertEqual(s.vrstice.map(\.id), [1, 2, 3])
        XCTAssertEqual(s.odmikNaprej(iskanje: ""), 400)
        // Dvojni dotik (stara stran za ze premaknjen odmik) se ne pripne.
        XCTAssertFalse(s.pripni(try stran(#"{"tickets": [{"id": 5}]}"#), iskanje: "", odmik: 200))
    }

    func testOdmikKiSeNePremakneUstaviLoadMore() throws {
        var s = VrataSeznam()
        s.zamenjaj(try stran(#"{"tickets": [{"id": 1}], "has_more": true, "next_offset": 200}"#), iskanje: "x")
        XCTAssertTrue(s.pripni(try stran(#"{"tickets": [{"id": 2}], "has_more": true, "next_offset": 200}"#), iskanje: "x", odmik: 200))
        XCTAssertNil(s.odmikNaprej(iskanje: "x"))
    }

    func testOsvezitevPoVpisuNeKrajsaNa1000() {
        XCTAssertEqual(VrataSeznam.kosiOsvezitve(nalozenih: 0).map { [$0.offset, $0.limit] }, [[0, 200]])
        XCTAssertEqual(VrataSeznam.kosiOsvezitve(nalozenih: 600).map { [$0.offset, $0.limit] }, [[0, 600]])
        XCTAssertEqual(VrataSeznam.kosiOsvezitve(nalozenih: 2300).map { [$0.offset, $0.limit] },
                       [[0, 1000], [1000, 1000], [2000, 300]])
    }

    func testZdruzeniKosiBrezPodvojenih() throws {
        var s = VrataSeznam()
        s.zamenjajKose([try stran(#"{"tickets": [{"id": 1}, {"id": 2}], "has_more": true, "next_offset": 2}"#),
                        try stran(#"{"tickets": [{"id": 2}, {"id": 3}], "counts": {"all": 3, "sold": 3}, "total": 3, "has_more": false}"#)],
                       iskanje: "")
        XCTAssertEqual(s.vrstice.map(\.id), [1, 2, 3])
        XCTAssertEqual(s.stevci?.sold, 3)
        XCTAssertNil(s.odmikNaprej(iskanje: ""))
    }

    // MARK: - Odprti tokovi prijave (PrijavaNadzor)

    func testNadzorTokovPoIdNePoStevcu() {
        let n = PrijavaNadzor()   // lasten primerek, ne deljeni
        let a = UUID(), b = UUID()
        XCTAssertFalse(n.jeKajOdprto)
        n.odpri(a)
        n.odpri(a)                // ponovljen onAppear istega lista
        n.odpri(b)                // list v listu
        n.zapri(a)
        XCTAssertTrue(n.jeKajOdprto)
        n.zapri(b)
        XCTAssertFalse(n.jeKajOdprto)   // en par se ni stel dvakrat
        n.zapri(b)                // onDisappear in onDismiss oba: brez napake
        XCTAssertFalse(n.jeKajOdprto)
    }

    // MARK: - Potrditev cene (#277 N2)

    func testTeloNakupaNosiPricakovanoCenoEneVstopnice() {
        let telo = APIClient.telesoNakupaVstopnic(quantity: 3, locale: "sl", expectedPriceCents: 1500)
        XCTAssertEqual(telo["expected_price_cents"] as? Int, 1500)
        XCTAssertEqual(telo["quantity"] as? Int, 3)
        // 0 (brezplacno) je veljavna vrednost in NI isto kot brez polja.
        XCTAssertEqual(APIClient.telesoNakupaVstopnic(quantity: 1, locale: "en", expectedPriceCents: 0)["expected_price_cents"] as? Int, 0)
        XCTAssertNil(APIClient.telesoNakupaVstopnic(quantity: 1, locale: "en")["expected_price_cents"])
    }

    // MARK: - Promo koda (samo statistika)

    func testTeloNakupaPromoKodaSamoCeNeprazna() {
        XCTAssertEqual(APIClient.telesoNakupaVstopnic(quantity: 1, locale: "en", promoCode: "  max12 ")["promo_code"] as? String, "max12")
        XCTAssertNil(APIClient.telesoNakupaVstopnic(quantity: 1, locale: "en", promoCode: "   ")["promo_code"])
        XCTAssertNil(APIClient.telesoNakupaVstopnic(quantity: 1, locale: "en", promoCode: nil)["promo_code"])
    }

    func testPromoKodaNeveljavnaKljucOstane() {
        let napaka = APIError.requestFailed(400, #"{"error":"promo_code_invalid","message":"This promo code is not valid for this event."}"#)
        XCTAssertTrue(napaka.jePromoKodaNeveljavna)
        XCTAssertEqual(napaka.nakupniIzid, .navadna)
        XCTAssertEqual(napaka.nakupUserMessage, String(localized: "This promo code is not valid for this event."))
    }

    // MARK: - Pogoji 1.1.4

    func testRazlicicaPogojev() {
        XCTAssertEqual(LegalLinks.termsVersion, "1.1.4")
    }

    // MARK: - Spletna stran kluba (#293, I48)

    func testSpletnaStranSamoHttpInHttps() {
        XCTAssertEqual(SpletnaStranVnos.normaliziraj("https://klub.si"), "https://klub.si")
        XCTAssertEqual(SpletnaStranVnos.normaliziraj("http://klub.si/pot?x=1"), "http://klub.si/pot?x=1")
        XCTAssertEqual(SpletnaStranVnos.normaliziraj("  www.klub.si "), "https://www.klub.si")
        XCTAssertEqual(SpletnaStranVnos.normaliziraj("klub.si:8080/a"), "https://klub.si:8080/a")
        XCTAssertEqual(SpletnaStranVnos.normaliziraj(""), "")
        XCTAssertEqual(SpletnaStranVnos.normaliziraj("-"), "")
        for slab in ["javascript:alert(1)", "data:text/html,x", "ftp://klub.si", "https:klub.si", "klub",
                     "https://dobra.si\\@zla.si", "https://ime:geslo@klub.si", "https://klub .si", "/pot",
                     "https://" + String(repeating: "a", count: 2048) + ".si"] {
            XCTAssertNil(SpletnaStranVnos.normaliziraj(slab), slab)
        }
        // Meja je 2048 kot na strezniku (ne 200 kot na spletu).
        let dolga = "https://klub.si/" + String(repeating: "a", count: 300)
        XCTAssertEqual(SpletnaStranVnos.normaliziraj(dolga), dolga)
    }

    func testNespremenjenaStaraSpletnaStranSeNePreverja() {
        // Star neveljaven zapis (vpisan pred #293) ne sme blokirati shranjevanja; backend ga ob enakem vnosu tudi ne preverja.
        XCTAssertEqual(SpletnaStranVnos.normaliziraj(" klub ", stara: "klub"), "klub")
        XCTAssertNil(SpletnaStranVnos.normaliziraj("klub2", stara: "klub"))
        XCTAssertEqual(SpletnaStranVnos.normaliziraj("www.novi.si", stara: "klub"), "https://www.novi.si")
    }

    // MARK: - Prodajalec platforma (I50)

    func testProdajalecPlatformaSPoljemInBrez() throws {
        let platforma = try JSONDecoder().decode(Seller.self, from: Data(#"{"name": "NEXT DIMENSIONS d.o.o.", "is_platform": true}"#.utf8))
        XCTAssertTrue(platforma.isPlatform)
        let klub = try JSONDecoder().decode(Seller.self, from: Data(#"{"name": "Klub d.o.o."}"#.utf8))
        XCTAssertFalse(klub.isPlatform)
        let napacen = try JSONDecoder().decode(Seller.self, from: Data(#"{"name": "Klub", "is_platform": "da"}"#.utf8))
        XCTAssertFalse(napacen.isPlatform)
        let dogodek = try JSONDecoder().decode(APIEvent.self, from: Data(#"{"id": 1, "seller": {"name": "Outly", "is_platform": true}}"#.utf8))
        XCTAssertEqual(dogodek.seller?.isPlatform, true)
    }
}
