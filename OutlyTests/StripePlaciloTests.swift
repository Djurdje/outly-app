import XCTest
import Foundation
@testable import Outly

/// Placilo prek Stripe Checkouta (backend 4. 10. 2026): dekodiranje `checkout_url` (star backend ga ne posilja), preverba URL-ja
/// (samo https na stripe.com / *.stripe.com), razvrstitev narocila po ponovnem branju in kljuc, ki ob stripe odgovoru ostane.
@MainActor
final class StripePlaciloTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func narocilo(id: Int = 41, status: String, vstopnic: Int, checkout: String? = nil) throws -> APIOrder {
        let tickets = (0..<vstopnic).map { #"{"id": \#(100 + $0), "serial": "S\#($0)", "status": "valid", "qr": "q\#($0)"}"# }
            .joined(separator: ",")
        let url = checkout.map { #", "checkout_url": "\#($0)""# } ?? ""
        return try decode(APIOrder.self, """
        {"id": \(id), "public_ref": "OUT-1", "status": "\(status)", "quantity": 2, "total_cents": 2000, "tickets": [\(tickets)]\(url)}
        """)
    }

    private func novaShramba() -> NakupniKljucShramba {
        var n = 0
        return NakupniKljucShramba(veljavnost: 600, ura: { Date(timeIntervalSince1970: 1_000_000) },
                                   ustvari: { n += 1; return "k\(n)" })
    }

    // MARK: - Dekodiranje

    func testStripeOdgovorNakupaDekodiraCheckoutUrl() throws {
        let r = try decode(PurchaseResponse.self, """
        {"mode": "stripe", "tickets": [], "checkout_url": "https://checkout.stripe.com/c/pay/cs_test_1",
         "order": {"id": 41, "status": "pending", "is_test": false, "checkout_url": "https://checkout.stripe.com/c/pay/cs_test_1"}}
        """)
        XCTAssertEqual(r.mode, "stripe")
        XCTAssertEqual(r.checkoutUrl, "https://checkout.stripe.com/c/pay/cs_test_1")
        XCTAssertEqual(r.order.checkoutUrl, "https://checkout.stripe.com/c/pay/cs_test_1")
        XCTAssertTrue(r.tickets.isEmpty)
        XCTAssertTrue(r.cakaPlacilo)
    }

    func testTestniOdgovorBrezCheckoutUrlSeVednoDelaInNiCakanja() throws {
        let r = try decode(PurchaseResponse.self, """
        {"mode": "test", "order": {"id": 5, "status": "paid", "is_test": true},
         "tickets": [{"id": 1, "serial": "S", "status": "valid", "qr": "q"}]}
        """)
        XCTAssertEqual(r.mode, "test")
        XCTAssertNil(r.checkoutUrl)
        XCTAssertNil(r.order.checkoutUrl)
        XCTAssertFalse(r.cakaPlacilo)
        XCTAssertEqual(r.tickets.count, 1)
    }

    func testNarociloBrezAliSNapacnimCheckoutUrlDekodiraKotNil() throws {
        XCTAssertNil(try decode(APIOrder.self, #"{"id": 1}"#).checkoutUrl)
        XCTAssertNil(try decode(APIOrder.self, #"{"id": 1, "checkout_url": null}"#).checkoutUrl)
        XCTAssertNil(try decode(APIOrder.self, #"{"id": 1, "checkout_url": 12}"#).checkoutUrl)
    }

    func testStripeOdgovorZPlacanimNarocilomInVstopnicamiNiCakanja() throws {
        // Ponovitev nakupa z istim kljucem po placilu: narocilo je placano in ima vstopnice -> uspesni zaslon.
        let r = try decode(PurchaseResponse.self, """
        {"mode": "stripe", "order": {"id": 41, "status": "paid"},
         "tickets": [{"id": 1, "serial": "S", "status": "valid", "qr": "q"}]}
        """)
        XCTAssertFalse(r.cakaPlacilo)
    }

    func testPendingBrezVstopnicNiUspehNeGledeNaNacin() throws {
        // Neznan nacin, a pending brez vstopnic: nikoli »You're in!« z 0 vstopnicami.
        let r = try decode(PurchaseResponse.self, #"{"mode": "live", "tickets": [], "order": {"id": 9, "status": "pending"}}"#)
        XCTAssertTrue(r.cakaPlacilo)
    }

    // MARK: - Preverba URL-ja

    func testVarenUrlSprejmeSamoHttpsStripe() {
        XCTAssertNotNil(StripePlacilo.varenUrl("https://checkout.stripe.com/c/pay/cs_test_1#frag"))
        XCTAssertNotNil(StripePlacilo.varenUrl("https://stripe.com/x"))
        XCTAssertNotNil(StripePlacilo.varenUrl("HTTPS://Checkout.Stripe.com/c/pay/cs"))
        XCTAssertNotNil(StripePlacilo.varenUrl("https://checkout.stripe.com:443/c/pay"))
    }

    func testVarenUrlZavrneVseDrugo() {
        XCTAssertNil(StripePlacilo.varenUrl(nil))
        XCTAssertNil(StripePlacilo.varenUrl(""))
        XCTAssertNil(StripePlacilo.varenUrl("   "))
        XCTAssertNil(StripePlacilo.varenUrl("http://checkout.stripe.com/c/pay"))
        XCTAssertNil(StripePlacilo.varenUrl("https://evil.com/checkout.stripe.com"))
        XCTAssertNil(StripePlacilo.varenUrl("https://evilstripe.com/x"))
        XCTAssertNil(StripePlacilo.varenUrl("https://stripe.com.evil.com/x"))
        XCTAssertNil(StripePlacilo.varenUrl("https://checkout.stripe.com@evil.com/x"))
        XCTAssertNil(StripePlacilo.varenUrl("https://user@checkout.stripe.com/x"))
        XCTAssertNil(StripePlacilo.varenUrl("https://checkout.stripe.com:8443/x"))
        XCTAssertNil(StripePlacilo.varenUrl("javascript:alert(1)"))
        XCTAssertNil(StripePlacilo.varenUrl("outly://checkout.stripe.com"))
        XCTAssertNil(StripePlacilo.varenUrl("checkout.stripe.com/c/pay"))
    }

    // MARK: - Izid ponovnega branja

    func testPlacanoZVstopnicamiJePlacano() throws {
        let n = [try narocilo(status: "paid", vstopnic: 2)]
        guard case .placano(let o) = StripePlacilo.izid(narocila: n, narociloId: 41) else { return XCTFail("pricakovano .placano") }
        XCTAssertEqual(o.tickets.count, 2)
        let p = StripePlacilo.odgovorPoPlacilu(o)
        XCTAssertEqual(p.tickets.count, 2)
        XCTAssertNotEqual(p.mode, "test")   // oznaka TEST samo pri mode == "test"
        XCTAssertFalse(p.cakaPlacilo)
    }

    func testPendingInPlacanoBrezVstopnicCakata() throws {
        let pending = [try narocilo(status: "pending", vstopnic: 0, checkout: "https://checkout.stripe.com/c/pay/cs")]
        guard case .caka = StripePlacilo.izid(narocila: pending, narociloId: 41) else { return XCTFail("pending -> caka") }
        let placanoBrez = [try narocilo(status: "paid", vstopnic: 0)]
        guard case .caka = StripePlacilo.izid(narocila: placanoBrez, narociloId: 41) else { return XCTFail("paid brez vstopnic -> caka") }
    }

    func testManjkajoceInNeuspeloNarociloJeOpuscen() throws {
        guard case .opuscen = StripePlacilo.izid(narocila: [], narociloId: 41) else { return XCTFail("manjka -> opuscen") }
        let drugo = [try narocilo(id: 7, status: "paid", vstopnic: 1)]
        guard case .opuscen = StripePlacilo.izid(narocila: drugo, narociloId: 41) else { return XCTFail("drug id -> opuscen") }
        for status in ["failed", "cancelled", "refunded"] {
            let n = [try narocilo(status: status, vstopnic: 0)]
            guard case .opuscen = StripePlacilo.izid(narocila: n, narociloId: 41) else { return XCTFail("\(status) -> opuscen") }
        }
    }

    // MARK: - Potekla seja in brezplacno narocilo (backend#203)

    func testCheckoutExpiredDekodiraInPrivzetoJeFalse() throws {
        XCTAssertFalse(try decode(APIOrder.self, #"{"id": 1}"#).checkoutExpired)
        XCTAssertFalse(try decode(APIOrder.self, #"{"id": 1, "checkout_expired": "da"}"#).checkoutExpired)
        let o = try decode(APIOrder.self, #"{"id": 1, "status": "pending", "checkout_url": null, "checkout_expired": true}"#)
        XCTAssertTrue(o.checkoutExpired)
        XCTAssertNil(o.checkoutUrl)
    }

    func testPendingPotekelJePotekelBrezCakanja() throws {
        let potekel = try decode(APIOrder.self, #"{"id": 41, "status": "pending", "checkout_url": null, "checkout_expired": true}"#)
        guard case .potekel = StripePlacilo.izid(narocila: [potekel], narociloId: 41) else { return XCTFail("pending + expired -> potekel") }
        let seUstvarja = try decode(APIOrder.self, #"{"id": 41, "status": "pending", "checkout_url": null, "checkout_expired": false}"#)
        guard case .caka = StripePlacilo.izid(narocila: [seUstvarja], narociloId: 41) else { return XCTFail("pending brez expired -> caka") }
    }

    func testOdpriPotekloNarociloNeOdpreStripaInPokazeSporocilo() throws {
        let p = try decode(PurchaseResponse.self, """
        {"mode": "stripe", "tickets": [], "checkout_url": null,
         "order": {"id": 41, "status": "pending", "checkout_url": null, "checkout_expired": true}}
        """)
        XCTAssertTrue(p.cakaPlacilo)
        let s = StripeNakup(shramba: novaShramba())
        XCTAssertFalse(s.odpri(p, uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        XCTAssertNil(s.stran)
        XCTAssertNil(s.caka)
        XCTAssertEqual(s.napaka, StripePlacilo.sporociloPotekla)
    }

    func testOdpriPotekloNarociloSIzvirnoPovezavoVseenoNeOdpre() throws {
        // Backend ob expired povezave ne vrne; ce bi jo (napaka), expired vseeno prevlada.
        let p = try decode(PurchaseResponse.self, """
        {"mode": "stripe", "tickets": [], "checkout_url": "https://checkout.stripe.com/c/pay/cs",
         "order": {"id": 41, "status": "pending", "checkout_expired": true}}
        """)
        let s = StripeNakup(shramba: novaShramba())
        XCTAssertFalse(s.odpri(p, uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        XCTAssertNil(s.stran)
    }

    func testPreveriPotekelaSejaPokazeSporociloKljucOstane() async throws {
        let shramba = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = shramba.zaNakup(uporabnik: 3, vsebina: vsebina)
        let s = try nakupZBralnikom(.potekel, shramba: shramba)
        let p = await s.preveri(token: "t", poskusov: 5)
        XCTAssertNil(p)
        XCTAssertNil(s.caka)   // brez kartice »Checking your payment«
        XCTAssertEqual(s.napaka, StripePlacilo.sporociloPotekla)
        XCTAssertEqual(shramba.zaNakup(uporabnik: 3, vsebina: vsebina), k1)   // ponovni pritisk: isti kljuc, backend razresi
    }

    func testBrezplacnoNarociloPriKlubuSStripomJeUspesenNakup() throws {
        let r = try decode(PurchaseResponse.self, """
        {"mode": "stripe", "checkout_url": null,
         "order": {"id": 9, "status": "paid", "total_cents": 0, "checkout_url": null, "checkout_expired": false},
         "tickets": [{"id": 1, "serial": "S", "status": "valid", "qr": "q"}]}
        """)
        XCTAssertFalse(r.cakaPlacilo)       // Stripa se ne odpira
        XCTAssertNotEqual(r.mode, "test")   // uspesni zaslon brez oznake TEST
        XCTAssertEqual(r.tickets.count, 1)
    }

    func testOrderNotActiveDaSporociloPotekleSeje() {
        let e = APIError.requestFailed(409, #"{"error":"order_not_active","message":"x"}"#)
        XCTAssertEqual(e.nakupniIzid, .narociloNeaktivno)
        XCTAssertEqual(e.nakupUserMessage, StripePlacilo.sporociloPotekla)
    }

    // MARK: - Odlozeno placilo in meja brezplacnih vstopnic (backend#203, krog 2)

    func testPaymentProcessingDekodiraInPrivzetoJeFalse() throws {
        XCTAssertFalse(try decode(APIOrder.self, #"{"id": 1}"#).paymentProcessing)
        XCTAssertFalse(try decode(APIOrder.self, #"{"id": 1, "payment_processing": "da"}"#).paymentProcessing)
        let o = try decode(APIOrder.self, #"{"id": 1, "status": "pending", "checkout_url": null, "checkout_expired": false, "payment_processing": true}"#)
        XCTAssertTrue(o.paymentProcessing)
        XCTAssertFalse(o.checkoutExpired)
    }

    func testPendingVObdelaviJeVObdelaviNiPotekelNiCaka() throws {
        let n = try decode(APIOrder.self, #"{"id": 41, "status": "pending", "checkout_url": null, "payment_processing": true}"#)
        guard case .vObdelavi = StripePlacilo.izid(narocila: [n], narociloId: 41) else { return XCTFail("pending + processing -> vObdelavi") }
        // processing prevlada, tudi ce bi bil istocasno expired (backend tega ne poslje)
        let obe = try decode(APIOrder.self, #"{"id": 41, "status": "pending", "checkout_expired": true, "payment_processing": true}"#)
        guard case .vObdelavi = StripePlacilo.izid(narocila: [obe], narociloId: 41) else { return XCTFail("processing prevlada") }
        // placano naročilo ostane placano
        let placano = try narocilo(status: "paid", vstopnic: 1)
        guard case .placano = StripePlacilo.izid(narocila: [placano], narociloId: 41) else { return XCTFail("paid -> placano") }
    }

    func testOdpriNarociloVObdelaviNeOdpreStripa() throws {
        let p = try decode(PurchaseResponse.self, """
        {"mode": "stripe", "tickets": [], "checkout_url": null,
         "order": {"id": 41, "status": "pending", "checkout_url": null, "payment_processing": true}}
        """)
        let s = StripeNakup(shramba: novaShramba())
        XCTAssertFalse(s.odpri(p, uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        XCTAssertNil(s.stran)
        XCTAssertNil(s.caka)
        XCTAssertEqual(s.napaka, StripePlacilo.sporociloVObdelavi)
    }

    func testPreveriVObdelaviPokazeSporociloBrezKarticeKljucOstane() async throws {
        let shramba = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = shramba.zaNakup(uporabnik: 3, vsebina: vsebina)
        for tiho in [false, true] {
            let s = try nakupZBralnikom(.vObdelavi, shramba: shramba)
            let p = await s.preveri(token: "t", poskusov: 5, tiho: tiho)
            XCTAssertNil(p)
            XCTAssertNil(s.caka)
            XCTAssertEqual(s.napaka, StripePlacilo.sporociloVObdelavi)
            XCTAssertEqual(shramba.zaNakup(uporabnik: 3, vsebina: vsebina), k1)
        }
    }

    func testFreeLimitDaSporociloInNiNavadnaNapakaTloris() {
        let e = APIError.requestFailed(409, #"{"error":"free_limit","message":"You can get at most 10 free tickets for this event (3 left for you)."}"#)
        XCTAssertTrue(e.jeBrezplacnaMeja)
        XCTAssertEqual(e.nakupUserMessage, String(localized: "You've reached the limit of free tickets for this event."))
        XCTAssertFalse(e.osveziTlorisPoNapaki)
        XCTAssertFalse(APIError.requestFailed(409, "Already booked").jeBrezplacnaMeja)
        XCTAssertFalse(APIError.requestFailed(400, "free_limit").jeBrezplacnaMeja)
    }

    // MARK: - StripeNakup (stanje + kljuc)

    private func stripeOdgovor(url: String?) throws -> PurchaseResponse {
        let u = url.map { #", "checkout_url": "\#($0)""# } ?? ""
        return try decode(PurchaseResponse.self, """
        {"mode": "stripe", "tickets": [], "order": {"id": 41, "status": "pending"}\(u)}
        """)
    }

    func testOdpriZVarnimUrlomOdpreStranInZapomniNarocilo() throws {
        let shramba = novaShramba()
        let s = StripeNakup(shramba: shramba)
        let p = try stripeOdgovor(url: "https://checkout.stripe.com/c/pay/cs")
        XCTAssertTrue(s.odpri(p, uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        XCTAssertEqual(s.stran?.url.host, "checkout.stripe.com")
        XCTAssertEqual(s.caka?.order.id, 41)
    }

    func testOdpriBrezAliSTujimUrlomNicesarNeOdpre() throws {
        let s = StripeNakup(shramba: novaShramba())
        XCTAssertFalse(s.odpri(try stripeOdgovor(url: nil), uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        XCTAssertNil(s.stran)
        XCTAssertNil(s.caka)
        XCTAssertFalse(s.odpri(try stripeOdgovor(url: "https://evil.com/pay"), uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        XCTAssertNil(s.stran)
        XCTAssertNil(s.caka)
    }

    func testKljucOstaneObStripeOdgovoru() throws {
        let shramba = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = shramba.zaNakup(uporabnik: 3, vsebina: vsebina)
        let s = StripeNakup(shramba: shramba)
        XCTAssertTrue(s.odpri(try stripeOdgovor(url: "https://checkout.stripe.com/c/pay/cs"),
                              uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        // Stripe odgovor kljuca ne pozabi: ponovni pritisk Pay dobi ISTI kljuc (backend vrne isto narocilo in isti checkout_url).
        XCTAssertEqual(shramba.zaNakup(uporabnik: 3, vsebina: vsebina), k1)
        XCTAssertNotNil(shramba.odprtaVsebina(uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
    }

    // MARK: - Klic nazaj outly://placilo (ASWebAuthenticationSession)

    private func klic(_ niz: String) -> StripePlacilo.PovratniKlic? {
        StripePlacilo.PovratniKlic.razcleni(URL(string: niz))
    }

    func testKlicNazajUspehInPreklicZNarocilom() {
        XCTAssertEqual(klic("outly://placilo?stanje=uspeh&narocilo=OUT-ABC123"), .uspeh(narocilo: "OUT-ABC123"))
        XCTAssertEqual(klic("outly://placilo?stanje=preklic&narocilo=OUT-ABC123"), .preklic(narocilo: "OUT-ABC123"))
        // Vrstni red parametrov ni pomemben, dodatni parametri se spregledajo.
        XCTAssertEqual(klic("outly://placilo?narocilo=77&app=ios&stanje=uspeh"), .uspeh(narocilo: "77"))
    }

    func testKlicNazajBrezAliPrazenNarociloJeNil() {
        XCTAssertEqual(klic("outly://placilo?stanje=uspeh"), .uspeh(narocilo: nil))
        XCTAssertEqual(klic("outly://placilo?stanje=preklic&narocilo="), .preklic(narocilo: nil))
        XCTAssertEqual(klic("outly://placilo?stanje=preklic&narocilo=%20"), .preklic(narocilo: nil))
    }

    func testKlicNazajNiObcutljivNaVelikeCrke() {
        XCTAssertEqual(klic("OUTLY://PLACILO?stanje=USPEH&narocilo=X1"), .uspeh(narocilo: "X1"))
        XCTAssertEqual(klic("outly://Placilo?stanje=Preklic"), .preklic(narocilo: nil))
    }

    func testKlicNazajDekodiraOdstotkovnoKodiranoNarocilo() {
        XCTAssertEqual(klic("outly://placilo?stanje=uspeh&narocilo=OUT%2D123"), .uspeh(narocilo: "OUT-123"))
    }

    func testKlicNazajZavrneNeveljavneUrlje() {
        XCTAssertNil(StripePlacilo.PovratniKlic.razcleni(nil))
        XCTAssertNil(klic("https://outly.si/placilo?stanje=uspeh&app=ios&narocilo=1"))   // ni nasa shema
        XCTAssertNil(klic("http://placilo?stanje=uspeh"))
        XCTAssertNil(klic("outly://drugo?stanje=uspeh"))                                  // drug gostitelj
        XCTAssertNil(klic("outly://placilo.evil.com?stanje=uspeh"))
        XCTAssertNil(klic("outly://evil.com/placilo?stanje=uspeh"))
        XCTAssertNil(klic("outly://placilo"))                                             // brez stanja
        XCTAssertNil(klic("outly://placilo?narocilo=1"))
        XCTAssertNil(klic("outly://placilo?stanje="))
        XCTAssertNil(klic("outly://placilo?stanje=neznano&narocilo=1"))
        XCTAssertNil(klic("outly://placilo?stanje=uspeh1"))
        XCTAssertNil(klic("evil://placilo?stanje=uspeh"))
    }

    func testIzidSejeIzKlica() {
        XCTAssertEqual(StripePlacilo.SejaIzid.izKlica(URL(string: "outly://placilo?stanje=uspeh&narocilo=1")), .uspeh)
        XCTAssertEqual(StripePlacilo.SejaIzid.izKlica(URL(string: "outly://placilo?stanje=preklic&narocilo=1")), .preklic)
        // Nerazumljiv URL ali brez URL-ja -> napaka (tiho enkratno preverjanje), nikoli »uspeh«.
        XCTAssertEqual(StripePlacilo.SejaIzid.izKlica(URL(string: "https://outly.si/placilo?stanje=uspeh")), .napaka)
        XCTAssertEqual(StripePlacilo.SejaIzid.izKlica(nil), .napaka)
    }

    func testSamoUspehPotrjujeVecBranjInSamoPreklicJeTiho() {
        XCTAssertEqual(StripePlacilo.SejaIzid.uspeh.poskusov, StripePlacilo.samodejnihBranjPoUspehu)
        XCTAssertGreaterThan(StripePlacilo.SejaIzid.uspeh.poskusov, 1)
        XCTAssertFalse(StripePlacilo.SejaIzid.uspeh.tiho)
        // Izrecni preklic: tiho enkratno preverjanje (brez kartice in napake).
        XCTAssertEqual(StripePlacilo.SejaIzid.preklic.poskusov, 1)
        XCTAssertTrue(StripePlacilo.SejaIzid.preklic.tiho)
        // Zaprtje seje in napaka: eno branje, a NE tiho (pending ostane na kartici »Checking your payment«).
        for izid in [StripePlacilo.SejaIzid.prekinil, .napaka, .nezagnana] {
            XCTAssertEqual(izid.poskusov, 1)
            XCTAssertFalse(izid.tiho)
        }
    }

    func testShemaVrnitveJeOutly() {
        XCTAssertEqual(StripePlacilo.shemaVrnitve, "outly")
    }

    // MARK: - StripeNakup.preveri po vrnitvi (vstavljen bralnik, brez omrezja)

    private func nakupZBralnikom(_ izid: StripePlacilo.Izid, shramba: NakupniKljucShramba) throws -> StripeNakup {
        let s = StripeNakup(shramba: shramba, bralnik: { _, _, _ in izid })
        XCTAssertTrue(s.odpri(try stripeOdgovor(url: "https://checkout.stripe.com/c/pay/cs"),
                              uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        return s
    }

    func testPreveriUspehPlacanoVrneUspesniZaslonInPozabiKljuc() async throws {
        let shramba = novaShramba()
        _ = shramba.zaNakup(uporabnik: 3, vsebina: NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2))
        let s = try nakupZBralnikom(.placano(try narocilo(status: "paid", vstopnic: 2)), shramba: shramba)
        let p = await s.preveri(token: "t", poskusov: 5)
        XCTAssertEqual(p?.order.id, 41)
        XCTAssertEqual(p?.tickets.count, 2)
        XCTAssertNil(s.caka)
        XCTAssertNil(s.napaka)
        XCTAssertNil(shramba.odprtaVsebina(uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
    }

    func testPreveriPoUspehuSePendingOstaneNaKarticiPlaciloSeVeri() async throws {
        let s = try nakupZBralnikom(.caka, shramba: novaShramba())
        let p = await s.preveri(token: "t", poskusov: 5)
        XCTAssertNil(p)
        XCTAssertNotNil(s.caka)   // kartica »Checking your payment« + »Check again«
        XCTAssertNil(s.napaka)
    }

    func testTihoPreveriPoPreklicuPendingVrneNaNakupniListBrezNapakeKljucOstane() async throws {
        let shramba = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = shramba.zaNakup(uporabnik: 3, vsebina: vsebina)
        let s = try nakupZBralnikom(.caka, shramba: shramba)
        let p = await s.preveri(token: "t", poskusov: 1, tiho: true)
        XCTAssertNil(p)
        XCTAssertNil(s.caka)      // brez kartice
        XCTAssertNil(s.napaka)    // brez napake
        XCTAssertEqual(shramba.zaNakup(uporabnik: 3, vsebina: vsebina), k1)   // ponovni Pay = isto placilo
    }

    func testPoZaprtjuSejeKupcaKiJePlacalPendingOstaneNaKarticiBrezNapake() async throws {
        // Zaprtje seje / napaka (tiho = false, 1 poskus): kupec je morda placal, preusmeritve pa ni bilo.
        for izid in [StripePlacilo.SejaIzid.prekinil, .napaka] {
            let s = try nakupZBralnikom(.caka, shramba: novaShramba())
            let p = await s.preveri(token: "t", poskusov: izid.poskusov, tiho: izid.tiho)
            XCTAssertNil(p)
            XCTAssertNotNil(s.caka)   // kartica »Checking your payment« + »Check again« ostane
            XCTAssertNil(s.napaka)    // brez napake
        }
    }

    func testPoZaprtjuSejeKupecKiJePlacalVidiVstopnico() async throws {
        let s = try nakupZBralnikom(.placano(try narocilo(status: "paid", vstopnic: 2)), shramba: novaShramba())
        let p = await s.preveri(token: "t", poskusov: StripePlacilo.SejaIzid.prekinil.poskusov, tiho: StripePlacilo.SejaIzid.prekinil.tiho)
        XCTAssertEqual(p?.tickets.count, 2)
        XCTAssertNil(s.caka)
    }

    func testSejaNiZagnanaPokazeSporociloBrezKarticeKljucOstane() throws {
        let shramba = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = shramba.zaNakup(uporabnik: 3, vsebina: vsebina)
        let s = StripeNakup(shramba: shramba)
        XCTAssertTrue(s.odpri(try stripeOdgovor(url: "https://checkout.stripe.com/c/pay/cs"),
                              uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        s.sejaNiZagnana()
        XCTAssertNil(s.caka)
        XCTAssertEqual(s.napaka, "We couldn't open the payment page. Please try again.")
        XCTAssertEqual(shramba.zaNakup(uporabnik: 3, vsebina: vsebina), k1)
    }

    func testTihoPreveriCeJeKupecPlacalInSeleNatoZaprlPokazeVstopnico() async throws {
        let s = try nakupZBralnikom(.placano(try narocilo(status: "paid", vstopnic: 1)), shramba: novaShramba())
        let p = await s.preveri(token: "t", poskusov: 1, tiho: true)
        XCTAssertEqual(p?.tickets.count, 1)
        XCTAssertNil(s.caka)
    }

    func testTihoPreveriOpuscenoNarociloZavrtiKljucBrezSporocila() async throws {
        let shramba = novaShramba()
        let vsebina = NakupniKljuc.Vsebina(dogodekId: 7, kolicina: 2)
        let k1 = shramba.zaNakup(uporabnik: 3, vsebina: vsebina)
        let s = try nakupZBralnikom(.opuscen, shramba: shramba)
        let p = await s.preveri(token: "t", poskusov: 1, tiho: true)
        XCTAssertNil(p)
        XCTAssertNil(s.caka)
        XCTAssertNil(s.napaka)
        XCTAssertNotEqual(shramba.zaNakup(uporabnik: 3, vsebina: vsebina), k1)
    }

    func testGlasnoPreveriOpuscenoNarociloPokazeNapako() async throws {
        let s = try nakupZBralnikom(.opuscen, shramba: novaShramba())
        _ = await s.preveri(token: "t", poskusov: 1)
        XCTAssertNil(s.caka)
        XCTAssertNotNil(s.napaka)
    }

    func testTihoPreveriNapakaBranjaBrezSporocilaInCakaOstane() async throws {
        struct Napaka: Error {}
        let s = StripeNakup(shramba: novaShramba(), bralnik: { _, _, _ in throw Napaka() })
        XCTAssertTrue(s.odpri(try stripeOdgovor(url: "https://checkout.stripe.com/c/pay/cs"),
                              uporabnik: 3, dogodekId: 7, vrsta: .vstopnice))
        let p = await s.preveri(token: "t", poskusov: 1, tiho: true)
        XCTAssertNil(p)
        XCTAssertNotNil(s.caka)
        XCTAssertNil(s.napaka)
    }
}
