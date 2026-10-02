import XCTest
import Foundation
@testable import Outly

/// Pravila idempotentnega kljuca nakupa (outly-backend #112 / PR #123): kdaj ostane isti UUID, kdaj se zamenja.
@MainActor
final class NakupniKljucTests: XCTestCase {

    /// Deterministicni izvor kljucev: k1, k2, ...
    private func ustvarjalnik() -> () -> String {
        var n = 0
        return { n += 1; return "k\(n)" }
    }

    private func vstopnice(_ kolicina: Int, dogodek: Int = 7) -> NakupniKljuc.Vsebina {
        NakupniKljuc.Vsebina(dogodekId: dogodek, kolicina: kolicina)
    }

    private func miza(_ id: Int, paket: Int? = nil, dogodek: Int = 7) -> NakupniKljuc.Vsebina {
        NakupniKljuc.Vsebina(dogodekId: dogodek, mizaId: id, paketId: paket)
    }

    // MARK: - Isti kljuc

    func testIstiNakupPonovnoPosljeSIstimKljucem() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let prvi = k.zaNakup(vstopnice(2))
        XCTAssertEqual(k.zaNakup(vstopnice(2)), prvi)
        XCTAssertEqual(k.zaNakup(vstopnice(2)), prvi)
    }

    func testIstiKljucPoNavadniNapakiInNejasnemIzidu() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let prvi = k.zaNakup(vstopnice(1))
        for izid in [NakupniIzid.navadna, .vObdelavi, .nejasen] {
            k.poNapaki(izid)
            XCTAssertEqual(k.zaNakup(vstopnice(1)), prvi, "izid \(izid)")
        }
    }

    func testPoNeaktivnemNarocilu() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let a = k.zaNakup(vstopnice(2))
        k.poNapaki(.narociloNeaktivno)
        // Naslednji pritisk iste vsebine je nov nakup z NOVIM kljucem (stari je vezan na neaktivno narocilo)...
        let b = k.zaNakup(vstopnice(2))
        XCTAssertNotEqual(a, b)
        // ... in ob naslednji navadni napaki ostane isti (ni vrtenja kljucev).
        k.poNapaki(.navadna)
        XCTAssertEqual(k.zaNakup(vstopnice(2)), b)
    }

    func testPrviKljucJeUUIDPrivzetegaIzvora() {
        var k = NakupniKljuc()
        XCTAssertNotNil(UUID(uuidString: k.zaNakup(vstopnice(1))))
    }

    // MARK: - Nov kljuc

    func testSpremembaKolicineDaNovKljuc() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let a = k.zaNakup(vstopnice(1))
        let b = k.zaNakup(vstopnice(2))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(k.zaNakup(vstopnice(2)), b)
        // Nazaj na prejsnjo kolicino je spet nov nakup (stari kljuc se ne obuja).
        XCTAssertNotEqual(k.zaNakup(vstopnice(1)), a)
    }

    func testSpremembaMizePaketaInDogodkaDaNovKljuc() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let a = k.zaNakup(miza(3, paket: 10))
        let b = k.zaNakup(miza(4, paket: 10))     // druga miza
        let c = k.zaNakup(miza(4, paket: 11))     // drug paket
        let d = k.zaNakup(miza(4, paket: nil))    // brez paketa
        let e = k.zaNakup(miza(4, paket: nil, dogodek: 8))   // drug dogodek
        XCTAssertEqual(Set([a, b, c, d, e]).count, 5)
    }

    func testPoUspehuNaslednjiNakupJeNov() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let a = k.zaNakup(vstopnice(2))
        k.poUspehu()
        // Tudi ISTA vsebina po uspehu je nov nakup.
        XCTAssertNotEqual(k.zaNakup(vstopnice(2)), a)
    }

    func testPoZavrnjenemKljucuNovKljucZaIstoVsebino() {
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        let a = k.zaNakup(miza(3, paket: 10))
        k.poNapaki(.kljucZavrzen)
        let b = k.zaNakup(miza(3, paket: 10))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(k.zaNakup(miza(3, paket: 10)), b)
    }

    func testPrviPoUspehuInZavrnitviNeZapraviKljucevZaporedoma() {
        // Dva zaporedna »nova nakupa« ne smeta dobiti istega kljuca.
        var k = NakupniKljuc(ustvari: ustvarjalnik())
        var videni = Set<String>()
        for _ in 0..<5 {
            videni.insert(k.zaNakup(vstopnice(1)))
            k.poUspehu()
        }
        XCTAssertEqual(videni.count, 5)
    }

    // MARK: - Razvrstitev napak

    func testIzidKljucZavrzen() {
        XCTAssertEqual(APIError.requestFailed(422, #"{"error":"idempotency_key_reused","message":"This Idempotency-Key was already used for a different purchase."}"#).nakupniIzid, .kljucZavrzen)
        XCTAssertEqual(APIError.requestFailed(400, #"{"error":"invalid_idempotency_key","message":"Idempotency-Key must be a UUID."}"#).nakupniIzid, .kljucZavrzen)
    }

    func testIzidVObdelavi() {
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"request_in_progress","message":"Your previous attempt is still being processed."}"#).nakupniIzid, .vObdelavi)
    }

    func testIzidNarociloNeaktivno() {
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"order_not_active","message":"The order for this Idempotency-Key is no longer active."}"#).nakupniIzid, .narociloNeaktivno)
        // Drugi 409 se ne zamenjajo: razlocuje koda `error`.
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"request_in_progress","message":"x"}"#).nakupniIzid, .vObdelavi)
        XCTAssertEqual(APIError.requestFailed(409, "This table is already booked.").nakupniIzid, .navadna)
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"sold_out","message":"Not enough tickets left."}"#).nakupniIzid, .navadna)
        // Koda pri napacnem statusu se ne steje.
        XCTAssertEqual(APIError.requestFailed(500, "order_not_active").nakupniIzid, .navadna)
    }

    func testIzidNejasenZaTimeoutInIzgubljenoPovezavo() {
        XCTAssertEqual(URLError(.timedOut).nakupniIzid, .nejasen)
        XCTAssertEqual(URLError(.networkConnectionLost).nakupniIzid, .nejasen)
        XCTAssertEqual(APIError.requestFailed(-1, "No HTTP response").nakupniIzid, .nejasen)
    }

    func testIzidNavadnaZaOstalo() {
        // Zahtevek sploh ni bil poslan -> ni »morda je uspelo«.
        XCTAssertEqual(URLError(.notConnectedToInternet).nakupniIzid, .navadna)
        XCTAssertEqual(APIError.requestFailed(-1, "Could not refresh session").nakupniIzid, .navadna)
        // Navadni 409/422/503 brez kljucne kode.
        XCTAssertEqual(APIError.requestFailed(409, "This table is already booked.").nakupniIzid, .navadna)
        XCTAssertEqual(APIError.requestFailed(409, "Not enough tickets left.").nakupniIzid, .navadna)
        XCTAssertEqual(APIError.requestFailed(422, "Something else").nakupniIzid, .navadna)
        XCTAssertEqual(APIError.requestFailed(503, "Server busy.").nakupniIzid, .navadna)
        XCTAssertEqual(APIError.requestFailed(500, "Server error.").nakupniIzid, .navadna)
        XCTAssertEqual(APIError.decodingFailed.nakupniIzid, .navadna)
        // Koda kljuca pri napacnem statusu se ne steje.
        XCTAssertEqual(APIError.requestFailed(500, "request_in_progress").nakupniIzid, .navadna)
    }

    // MARK: - Osvezitev VIP tlorisa po napaki

    func testOsveziTlorisSamoPoNavadnem409() {
        // Miza prodana / cena spremenjena / prodaja zaprta: osvezi.
        XCTAssertTrue(APIError.requestFailed(409, "This table is already booked.").osveziTlorisPoNapaki)
        XCTAssertTrue(APIError.requestFailed(409, #"{"error":"table_unavailable","message":"The table price has changed."}"#).osveziTlorisPoNapaki)
        // Izjemi: izbira ostane.
        XCTAssertFalse(APIError.requestFailed(409, #"{"error":"request_in_progress","message":"x"}"#).osveziTlorisPoNapaki)
        XCTAssertFalse(APIError.requestFailed(409, #"{"error":"order_not_active","message":"x"}"#).osveziTlorisPoNapaki)
        // Ni 409 ali ni APIError.
        XCTAssertFalse(APIError.requestFailed(422, #"{"error":"idempotency_key_reused"}"#).osveziTlorisPoNapaki)
        XCTAssertFalse(APIError.requestFailed(503, "Server busy.").osveziTlorisPoNapaki)
        XCTAssertFalse(URLError(.timedOut).osveziTlorisPoNapaki)
    }

    // MARK: - Sporocila in premor

    func testSporocilaKljucnihIzidov() {
        let zavrzen = APIError.requestFailed(422, #"{"error":"idempotency_key_reused","message":"This Idempotency-Key was already used for a different purchase."}"#)
        // translate() bi »already used« sicer prevedel v »ticket was already used«.
        XCTAssertNotEqual(zavrzen.nakupUserMessage, zavrzen.userMessage)
        XCTAssertFalse(zavrzen.nakupUserMessage.isEmpty)

        let vObdelavi = APIError.requestFailed(409, #"{"error":"request_in_progress","message":"x"}"#)
        XCTAssertNotEqual(vObdelavi.nakupUserMessage, vObdelavi.userMessage)

        let neaktivno = APIError.requestFailed(409, #"{"error":"order_not_active","message":"The order for this Idempotency-Key is no longer active."}"#)
        XCTAssertNotEqual(neaktivno.nakupUserMessage, neaktivno.userMessage)
        XCTAssertEqual(neaktivno.nakupUserMessage, String(localized: "Your previous order is no longer active. Tap again to buy anew."))
        XCTAssertNotEqual(neaktivno.nakupUserMessage, vObdelavi.nakupUserMessage)

        let nejasen = URLError(.timedOut)
        XCTAssertNotEqual(nejasen.nakupUserMessage, nejasen.userMessage)

        // Navadni izidi ostanejo kot prej.
        XCTAssertEqual(APIError.requestFailed(409, "Already booked").nakupUserMessage, APIError.requestFailed(409, "Already booked").userMessage)
    }

    func testPremorPoNapaki() {
        XCTAssertEqual(APIError.requestFailed(503, "Server busy.").nakupPremorNanosekund, 5_000_000_000)
        XCTAssertEqual(APIError.requestFailed(409, #"{"error":"request_in_progress"}"#).nakupPremorNanosekund, 2_000_000_000)
        XCTAssertNil(APIError.requestFailed(409, "This table is already booked.").nakupPremorNanosekund)
        XCTAssertNil(APIError.requestFailed(409, #"{"error":"order_not_active"}"#).nakupPremorNanosekund)
        XCTAssertNil(URLError(.timedOut).nakupPremorNanosekund)
    }

    // MARK: - Shramba (list se zapre in odpre znova)

    /// Nadzorovana ura in deterministicni kljuci k1, k2, ...
    private final class Ura {
        var zdaj = Date(timeIntervalSince1970: 1_000_000)
        func naprej(_ s: TimeInterval) { zdaj = zdaj.addingTimeInterval(s) }
    }

    private func shramba(_ ura: Ura, veljavnost: TimeInterval = 600) -> NakupniKljucShramba {
        NakupniKljucShramba(veljavnost: veljavnost, ura: { ura.zdaj }, ustvari: ustvarjalnik())
    }

    func testShrambaPonovnoOdprtListIsteVsebineDobiIstiKljuc() {
        let ura = Ura()
        let s = shramba(ura)
        // Prvi list: Pay -> timeout (.nejasen) -> list zapre. »Nov dostop« = isti klic z isto vsebino.
        let prvi = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        ura.naprej(120)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(2)), prvi)
        // Tudi po drugi navadni napaki in vObdelavi.
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .vObdelavi)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(2)), prvi)
    }

    func testShrambaPazljivoPoVsebiniInDogodku() {
        let s = shramba(Ura())
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(1))
        // Drugacna kolicina v istem dogodku = nov nakup (pravilo NakupniKljuc).
        let b = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        XCTAssertNotEqual(a, b)
        // Drug dogodek ima svoj zapis in ne povozi kljuca prvega.
        let c = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2, dogodek: 8))
        XCTAssertNotEqual(c, b)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(2)), b)
        // Miza in paket znotraj dogodka.
        let m = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10)), m)
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 11)), m)
    }

    func testShrambaPoUspehuNovKljuc() {
        let s = shramba(Ura())
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poUspehu(uporabnik: 1, dogodekId: 7)
        XCTAssertEqual(s.steviloZapisov, 0)
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(2)), a)
    }

    func testShrambaPoZavrnjenemKljucuInNeaktivnemNarocilu() {
        let s = shramba(Ura())
        for izid in [NakupniIzid.kljucZavrzen, .narociloNeaktivno] {
            let a = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: izid)
            let b = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
            XCTAssertNotEqual(a, b, "izid \(izid)")
            // Novi kljuc potem ostane (ponovno odprtje ga ne zamenja).
            XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10)), b)
        }
    }

    func testShrambaPoIzteku() {
        let ura = Ura()
        let s = shramba(ura, veljavnost: 600)
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(1))
        ura.naprej(599)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)   // uporaba osvezi rok
        ura.naprej(599)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
        ura.naprej(600)                                                      // od zadnje uporabe poteklo 10 min
        XCTAssertEqual(s.steviloZapisov, 0)
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
    }

    func testShrambaNapakaOsveziRokInNeUstvariZapisa() {
        let ura = Ura()
        let s = shramba(ura, veljavnost: 600)
        // Napaka brez zapisa (npr. po odjavi) zapisa ne ustvari.
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertEqual(s.steviloZapisov, 0)
        // Nakup, ki je trajal do timeouta: rok se steje od napake.
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(1))
        ura.naprej(500)
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        ura.naprej(500)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
    }

    func testShrambaDrugUporabnikDobiNovKljuc() {
        let s = shramba(Ura())
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(1))
        let b = s.zaNakup(uporabnik: 2, vsebina: vstopnice(1))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
        XCTAssertEqual(s.zaNakup(uporabnik: 2, vsebina: vstopnice(1)), b)
        // Uspeh enega ne zadene drugega.
        s.poUspehu(uporabnik: 1, dogodekId: 7)
        XCTAssertEqual(s.zaNakup(uporabnik: 2, vsebina: vstopnice(1)), b)
    }

    func testShrambaOdjavaPocistiVse() {
        let s = shramba(Ura())
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(1))
        let b = s.zaNakup(uporabnik: 1, vsebina: miza(3, dogodek: 9))
        XCTAssertEqual(s.steviloZapisov, 2)
        s.pocistiVse()
        XCTAssertEqual(s.steviloZapisov, 0)
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: miza(3, dogodek: 9)), b)
    }

    func testShrambaPrivzetaVeljavnostJeEnDan() {
        // Backend kljuc hrani trajno; iztek je samo higiena pomnilnika (pozen Pay po timeoutu mora dati isti kljuc).
        XCTAssertEqual(NakupniKljucShramba.privzetaVeljavnost, 24 * 60 * 60)
        let ura = Ura()
        let s = NakupniKljucShramba(ura: { ura.zdaj }, ustvari: ustvarjalnik())
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(1))
        ura.naprej(60 * 60)   // list odprt eno uro po timeoutu
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
        ura.naprej(24 * 60 * 60)
        XCTAssertNotEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(1)), a)
        let privzeta = NakupniKljucShramba()
        XCTAssertNotNil(UUID(uuidString: privzeta.zaNakup(uporabnik: 1, vsebina: vstopnice(1))))
    }

    // MARK: - Odprta vsebina (predizpolnitev ob ponovnem odprtju lista)

    func testOdprtaVsebinaJeSamoPoNerazresenemPoskusu() {
        let s = shramba(Ura())
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))          // se ni poskusa
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .vObdelavi)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(3))
        // Branje zapisa ne spremeni.
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(3))
    }

    func testOdprtaVsebinaNeObstanePoDokoncniNapaki() {
        let s = shramba(Ura())
        let a = s.zaNakup(uporabnik: 1, vsebina: vstopnice(4))
        // 403, razprodano, 503 ...: backend kljuca ne zapomni, predizpolnitev bi samo presenetila.
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
        // Kljuc sam se NE spremeni (pravila kljuca ostanejo): ponovni pritisk iste vsebine ga uporabi znova.
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: vstopnice(4)), a)
        // Po novem nejasnem izidu je vsebina spet odprta.
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), vstopnice(4))
    }

    func testOdprtaVsebinaMedZahtevkomJeNejasna() {
        // zaNakup brez poNapaki/poUspehu (odgovor se ni prisel): obravnavano kot nejasno.
        let s = shramba(Ura())
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), miza(3, paket: 10))
        // Nov zaNakup po dokoncni napaki ponastavi izid na »se brez odgovora«.
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .navadna)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), miza(3, paket: 10))
    }

    func testOdprtaVsebinaPoMizi() {
        let s = shramba(Ura())
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(3, paket: 10))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), miza(3, paket: 10))
        // Uporabnikova nova izbira (druga miza) je zadnji poskus.
        _ = s.zaNakup(uporabnik: 1, vsebina: miza(4, paket: nil))
        XCTAssertEqual(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), miza(4, paket: nil))
    }

    func testOdprtaVsebinaPoUspehuInRotacijiKljucaJeNil() {
        let s = shramba(Ura())
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.poUspehu(uporabnik: 1, dogodekId: 7)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
        // 422/400 in 409 order_not_active: kljuc je rotiran, prejsnje vsebine ne vsiljujemo.
        for izid in [NakupniIzid.kljucZavrzen, .narociloNeaktivno] {
            _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
            s.poNapaki(uporabnik: 1, dogodekId: 7, izid: izid)
            XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7), "izid \(izid)")
        }
    }

    func testOdprtaVsebinaPoIzteku_OdjaviInZaDrugegaUporabnika() {
        let ura = Ura()
        let s = shramba(ura, veljavnost: 600)
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        XCTAssertNil(s.odprtaVsebina(uporabnik: 2, dogodekId: 7))          // drug uporabnik
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 8))          // drug dogodek
        ura.naprej(599)
        XCTAssertNotNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
        // Branje roka ne osvezi: 599 + 1 = 600 od zadnje uporabe -> poteklo.
        ura.naprej(1)
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
        _ = s.zaNakup(uporabnik: 1, vsebina: vstopnice(2))
        s.pocistiVse()
        XCTAssertNil(s.odprtaVsebina(uporabnik: 1, dogodekId: 7))
    }

    func testPredizpolnjenaVsebinaDaIstiKljucKotPrviPoskus() {
        // Celoten scenarij: kolicina 3, timeout, zapri; nov list prebere odprtoVsebino in pri Pay poslje isto vsebino.
        let s = shramba(Ura())
        let prvi = s.zaNakup(uporabnik: 1, vsebina: vstopnice(3))
        s.poNapaki(uporabnik: 1, dogodekId: 7, izid: .nejasen)
        let predizpolnjena = s.odprtaVsebina(uporabnik: 1, dogodekId: 7)
        XCTAssertEqual(predizpolnjena, vstopnice(3))
        XCTAssertEqual(s.zaNakup(uporabnik: 1, vsebina: predizpolnjena ?? vstopnice(1)), prvi)
    }
}
