import Foundation
import Combine

/// Stanje nakupa, ki gre prek Stripe Checkouta (list vstopnic `BuyTicketsView` in VIP list `VipTablesView` imata vsak svoj primerek).
///
/// Potek: nakup vrne `mode: "stripe"` -> `odpri` (preveri URL, odpre Safari) -> uporabnik placa ali zapre -> `preveri` prebere
/// GET /me/orders in poisce narocilo po `order.id`: placano z vstopnicami -> uspesni zaslon; se pending -> `caka` ostane in pogled
/// pokaze `PlaciloSeVeriKartica` z gumbom »Check again«; narocila ni vec (opuscen/failed/cancelled) -> napaka in nov kljuc.
///
/// IDEMPOTENTNI KLJUC (`NakupniKljucShramba`): ob stripe odgovoru se NE pozabi (ponovni pritisk Pay dokler je narocilo
/// pending vrne ISTO narocilo in isti `checkout_url`); pozabi se sele, ko je narocilo placano (`poUspehu`), ali ko narocila ni vec
/// (`poNapaki(.narociloNeaktivno)` ga zavrti, da je naslednji pritisk nov nakup).
@MainActor
final class StripeNakup: ObservableObject {

    /// Odprta Stripova stran (`.fullScreenCover(item:)`); pogled jo ob koncu postavi na nil.
    @Published var stran: StripeStran?
    /// Narocilo, ki caka potrditev placila (pending po zaprtju Safarija); nil = ni nicesar za preverjati.
    @Published private(set) var caka: PurchaseResponse?
    @Published private(set) var preverjanje = false
    /// Sporocilo za uporabnika po zadnjem preverjanju (napaka branja ali neuspelo placilo); nil = ni.
    @Published private(set) var napaka: String?

    private var uporabnik = NakupniKljucShramba.neznanUporabnik
    private var dogodekId = 0
    private var vrsta: VrstaNakupa = .vstopnice
    private let shramba: NakupniKljucShramba

    convenience init() {
        self.init(shramba: NakupniKljucShramba.deljena)
    }

    /// `shramba` je vstavljiva zaradi testov.
    init(shramba: NakupniKljucShramba) {
        self.shramba = shramba
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
        guard let url = StripePlacilo.varenUrl(p.checkoutUrl ?? p.order.checkoutUrl) else {
            caka = nil
            return false
        }
        caka = p
        stran = StripeStran(url: url)
        return true
    }

    /// Prebere narocilo (po zaprtju Safarija `StripePlacilo.samodejnihBranj` poskusov, na gumb »Check again« 1).
    /// Vrne odgovor za uspesni zaslon, ce je narocilo placano in ima vstopnice; sicer nil (stanje je v `caka` / `napaka`).
    func preveri(token: String, poskusov: Int) async -> PurchaseResponse? {
        guard let narocilo = caka, !preverjanje else { return nil }
        preverjanje = true
        napaka = nil
        defer { preverjanje = false }
        do {
            switch try await StripePlacilo.preberi(token: token, narociloId: narocilo.order.id, poskusov: poskusov) {
            case .placano(let placano):
                shramba.poUspehu(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta)
                caka = nil
                return StripePlacilo.odgovorPoPlacilu(placano)
            case .caka:
                return nil
            case .opuscen:
                shramba.poNapaki(uporabnik: uporabnik, dogodekId: dogodekId, vrsta: vrsta, izid: .narociloNeaktivno)
                caka = nil
                napaka = String(localized: "The payment was not completed. You can try again.")
                return nil
            }
        } catch {
            napaka = error.userMessage
            return nil
        }
    }
}
