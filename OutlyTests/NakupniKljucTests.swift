import XCTest
import Foundation
@testable import Outly

/// Pravila idempotentnega kljuca nakupa (outly-backend #112 / PR #123): kdaj ostane isti UUID, kdaj se zamenja.
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
}
