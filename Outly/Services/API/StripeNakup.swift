import Foundation
import Combine

/// Stanje nakupa, ki gre prek Stripe Checkouta (list vstopnic `BuyTicketsView` in VIP list `VipTablesView` imata vsak svoj primerek).
///
/// Potek: nakup vrne `mode: "stripe"` -> `odpri` (preveri URL, nastavi `stran`; pogled z `.stripeSeja` odpre
/// ASWebAuthenticationSession) -> uporabnik placa (outly://placilo?stanje=uspeh) ali preklice/zapre -> `preveri` prebere
/// GET /me/orders in poisce narocilo po `order.id`: placano z vstopnicami -> uspesni zaslon; se pending -> `caka` ostane in pogled
/// pokaze `PlaciloSeVeriKartica` z gumbom »Check again«; narocila ni vec (opuscen/failed/cancelled) -> napaka in nov kljuc.
/// Po izrecnem preklicu na Stripu (`tiho`) ostane kupec na nakupnem listu brez napake in brez kartice, kljuc ostane. Pri zaprtju seje
/// ali napaki (ni gotovo, ali je placal) ostane pending narocilo na kartici »Checking your payment« z gumbom »Check again«.
///
/// IDEMPOTENTNI KLJUC (`NakupniKljucShramba`): ob stripe odgovoru se NE pozabi (ponovni pritisk Pay dokler je narocilo
/// pending vrne ISTO narocilo in isti `checkout_url`); pozabi se sele, ko je narocilo placano (`poUspehu`), ali ko narocila ni vec
/// (`poNapaki(.narociloNeaktivno)` ga zavrti, da je naslednji pritisk nov nakup).
@MainActor
final class StripeNakup: ObservableObject {

    /// Zahteva za odprtje Stripove strani; `.stripeSeja(stran:)` jo vzame in postavi na nil, ko seja konca.
    @Published var stran: StripeStran?
    /// Narocilo, ki caka potrditev placila (pending po vrnitvi s Stripa); nil = ni nicesar za preverjati.
    @Published private(set) var caka: PurchaseResponse?
    @Published private(set) var preverjanje = false
    /// Sporocilo za uporabnika po zadnjem preverjanju (napaka branja ali neuspelo placilo); nil = ni.
    @Published private(set) var napaka: String?

    private var uporabnik = NakupniKljucShramba.neznanUporabnik
    private var dogodekId = 0
    private var vrsta: VrstaNakupa = .vstopnice
    private let shramba: NakupniKljucShramba
    private let bralnik: Bralnik

    /// Prebere narocilo (GET /me/orders) in vrne izid; vstavljivo zaradi testov.
    typealias Bralnik = (_ token: String, _ narociloId: Int, _ poskusov: Int) async throws -> StripePlacilo.Izid

    convenience init() {
        self.init(shramba: NakupniKljucShramba.deljena)
    }

    /// `shramba` in `bralnik` sta vstavljiva zaradi testov.
    init(shramba: NakupniKljucShramba,
         bralnik: @escaping Bralnik = { token, narociloId, poskusov in
             try await StripePlacilo.preberi(token: token, narociloId: narociloId, poskusov: poskusov)
         }) {
        self.shramba = shramba
        self.bralnik = bralnik
    }

    /// Nov nakup se zacne: staro stanje stran.
    func ponastavi() {
        caka = nil
        napaka = nil
    }

    /// Odpre Stripovo stran za narocilo iz odgovora nakupa. Vrne false, ce URL ni https na stripe.com ali ga ni:
    /// takrat se NICESAR ne odpre, narocilo pa ostane na strezniku (kljuc ostane, ponovni pritisk dobi isto narocilo).
    func odpri(_ p: PurchaseResponse, uporabnik: Int, dogodekId: Int, vrsta: VrstaNakupa) -> Bool {
        self.uporabnik = uporabnik
        self.dogodekId = dogodekId
        self.vrsta = vrsta
        napaka = nil
        // Potekla seja (backend#203): povezave ne odpiramo; kljuc ostane, ponovni nakup z istim kljucem backend razresi
        // (placano -> 201, preklicano -> 409 order_not_active -> nov kljuc).
        if p.order.checkoutExpired {
            caka = nil
            napaka = StripePlacilo.sporociloPotekla
            return false
        }
        guard let url = StripePlacilo.varenUrl(p.checkoutUrl ?? p.order.checkoutUrl) else {
            caka = nil
            return false
        }
        caka = p
        stran = StripeStran(url: url)
        return true
    }

    /// Seje s Stripovo stranjo ni bilo mogoce zagnati: nakupni list z obstojecim sporocilom, brez kartice; narocilo ostane na strezniku,
    /// kljuc ostane (ponovni Pay dobi isto narocilo in isti checkout_url).
    func sejaNiZagnana() {
        caka = nil
        napaka = String(localized: "We couldn't open the payment page. Please try again.")
    }

    /// Prebere narocilo (po uspehu `StripePlacilo.samodejnihBranjPoUspehu` poskusov, na gumb »Check again« 1).
    /// Vrne odgovor za uspesni zaslon, ce je narocilo placano in ima vstopnice; sicer nil (stanje je v `caka` / `napaka`).
    ///
    /// `tiho` (samo po izrecnem preklicu `stanje=preklic`): placano -> uspesni zaslon (kupec je morda placal in sele nato zaprl);
    /// se pending -> `caka` se pobrise (nakupni list brez kartice »Checking your payment«, kljuc OSTANE, zato ponovni Pay odpre isto
    /// placilo); narocila ni vec -> kljuc se zavrti, a brez sporocila o napaki; napaka branja -> brez sporocila, `caka` ostane.
    func preveri(token: String, poskusov: Int, tiho: Bool = false) async -> PurchaseResponse? {
        guard let narocilo = caka, !preverjanje else { return nil }
        preverjanje = true
        napaka = nil
        defer { preverjanje = false }
        do {
            switch try await bralnik(token, narocilo.order.id, poskusov) {
            case .placano(let placano):
                shramba.poUspehu(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta)
                caka = nil
                return StripePlacilo.odgovorPoPlacilu(placano)
            case .caka:
                if tiho { caka = nil }
                return nil
            case .potekel:
                // Narocilo je bilo ravnokar prebrano (osvezeno); kartica »Checking your payment« izgine, kljuc OSTANE.
                caka = nil
                if !tiho { napaka = StripePlacilo.sporociloPotekla }
                return nil
            case .opuscen:
                shramba.poNapaki(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta, izid: .narociloNeaktivno)
                caka = nil
                if !tiho { napaka = String(localized: "The payment was not completed. You can try again.") }
                return nil
            }
        } catch {
            if !tiho { napaka = error.userMessage }
            return nil
        }
    }
}
