import Foundation

/// Placilo prek Stripe Checkouta (backend 4. 10. 2026; DECISIONS: gostovana Stripe stran, kartica se NIKOLI ne vnasa v
/// aplikaciji). Klub s povezanim Stripom na nakupu vrne `mode: "stripe"`, narocilo `pending`, prazne vstopnice in
/// `checkout_url`; vstopnice nastanejo sele, ko Stripe potrdi placilo (webhook, nekaj sekund po placilu).
/// Klub brez Stripa vrne `mode: "test"` (takoj placano) in gre po stari poti nespremenjeno.
///
/// Ta datoteka je cisti del (brez UI-ja, testabilen): preverba URL-ja in razvrstitev narocila po ponovnem branju.
/// Stanje zaslona vodi `StripeNakup`, Safari ovoj je `StripeSafariView`.
enum StripePlacilo {

    /// URL, ki ga smemo odpreti kot Stripovo placilno stran: `https` in gostitelj `stripe.com` ali poddomena
    /// (`checkout.stripe.com`). Vse drugo (http, tuj gostitelj, `evilstripe.com`, `stripe.com.evil.com`, uporabnik@ v URL-ju,
    /// nestandardna vrata, prazen niz, nil) -> nil: aplikacija takrat NICESAR ne odpre.
    static func varenUrl(_ niz: String?) -> URL? {
        guard let niz = niz?.trimmingCharacters(in: .whitespacesAndNewlines), !niz.isEmpty,
              let url = URL(string: niz),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let gostitelj = url.host?.lowercased() else { return nil }
        guard gostitelj == "stripe.com" || gostitelj.hasSuffix(".stripe.com") else { return nil }
        return url
    }

    /// Izid ponovnega branja narocila (GET /me/orders) po zaprtju Stripove strani.
    enum Izid {
        /// Placano in vstopnice so ze nastale: pokazi uspesni zaslon.
        case placano(APIOrder)
        /// Se `pending` (ali placano, vstopnice pa se niso zapisane): webhook se ni prisel ali uporabnik ni placal.
        case caka
        /// Narocila ni vec med mojimi (backend opuscenih ne vraca) ali ima status failed/cancelled/refunded:
        /// placilo ni uspelo, naslednji pritisk je nov nakup (nov kljuc).
        case opuscen
    }

    /// Razvrsti narocilo `narociloId` iz seznama GET /me/orders.
    static func izid(narocila: [APIOrder], narociloId: Int) -> Izid {
        guard let n = narocila.first(where: { $0.id == narociloId }) else { return .opuscen }
        switch n.status {
        case "paid":
            return n.tickets.isEmpty ? .caka : .placano(n)
        case "pending":
            return .caka
        default:
            return .opuscen
        }
    }

    /// Nakup, sestavljen iz placanega narocila (za obstojeci uspesni zaslon z vstopnicami; brez oznake TEST, ker `mode != "test"`).
    static func odgovorPoPlacilu(_ narocilo: APIOrder) -> PurchaseResponse {
        PurchaseResponse(mode: "stripe", order: narocilo, tickets: narocilo.tickets, checkoutUrl: nil)
    }

    /// Najvec samodejnih branj takoj po zaprtju Stripove strani (webhook zakasni nekaj sekund) in premor med njimi.
    /// Potem se bere samo se na uporabnikov pritisk (»Check again«): brez neskoncne zanke.
    static let samodejnihBranj = 3
    static let premorMedBranjiNanosekund: UInt64 = 2_000_000_000

    /// Prebere GET /me/orders do `poskusov`-krat (premor med poskusi) in vrne izid za `narociloId`; ob `.caka` poskusi znova,
    /// dokler poskusov ne zmanjka. Ce vsi poskusi padejo na napaki, vrze zadnjo napako.
    static func preberi(token: String, narociloId: Int, poskusov: Int,
                        premorNanosekund: UInt64 = premorMedBranjiNanosekund) async throws -> Izid {
        var zadnjaNapaka: Error?
        for i in 0..<max(1, poskusov) {
            if i > 0 {
                try? await Task.sleep(nanoseconds: premorNanosekund)
                if Task.isCancelled { break }
            }
            do {
                let narocila = try await APIClient.shared.fetchMyOrders(token: token)
                zadnjaNapaka = nil
                let r = izid(narocila: narocila, narociloId: narociloId)
                if case .caka = r { continue }
                return r
            } catch {
                zadnjaNapaka = error
            }
        }
        if let zadnjaNapaka { throw zadnjaNapaka }
        return .caka
    }
}
