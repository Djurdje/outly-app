import Foundation

/// Placilo prek Stripe Checkouta (backend 4. 10. 2026; DECISIONS: gostovana Stripe stran, kartica se NIKOLI ne vnasa v
/// aplikaciji). Klub s povezanim Stripom na nakupu vrne `mode: "stripe"`, narocilo `pending`, prazne vstopnice in
/// `checkout_url`; vstopnice nastanejo sele, ko Stripe potrdi placilo (webhook, nekaj sekund po placilu).
/// Klub brez Stripa vrne `mode: "test"` (takoj placano) in gre po stari poti nespremenjeno.
///
/// Placilna stran se odpre v `ASWebAuthenticationSession` (od 4. 10. 2026, TestFlight #162: v SFSafariViewController je kupec po
/// placilu obstal na spletni strani). Backend ob glavi `X-Outly-Client: ios` Stripu nastavi success/cancel URL na
/// `https://outly.si/placilo?stanje=uspeh|preklic&app=ios&narocilo=<REF>`; ta stran takoj preusmeri na
/// `outly://placilo?stanje=uspeh|preklic&narocilo=<REF>`, sejo pa ob tem URL-ju zapre sistem sam (registracija sheme v Info.plist
/// ni potrebna). Klic nazaj je samo SPROZILEC: placilo vedno potrdi streznik (GET /me/orders po `order.id`), nikoli URL.
///
/// Ta datoteka je cisti del (brez UI-ja, testabilen): preverba URL-ja, razclenitev klica nazaj in razvrstitev narocila po
/// ponovnem branju. Stanje zaslona vodi `StripeNakup`, sejo vodi `StripeSejaVodja` (Core/Components/StripeSeja.swift).
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

    /// Shema klica nazaj; `ASWebAuthenticationSession(callbackURLScheme:)` jo prestreze sam.
    static let shemaVrnitve = "outly"

    /// Klic nazaj `outly://placilo?stanje=uspeh|preklic&narocilo=<REF>` po razclenitvi.
    enum PovratniKlic: Equatable {
        case uspeh(narocilo: String?)
        case preklic(narocilo: String?)

        /// Razclenitev. nil = ni nas klic: druga shema, drug gostitelj (ne `placilo`) ali neznano/manjkajoce `stanje`.
        /// `narocilo` je samo informativen (prazen niz ali manjkajoc -> nil); aplikacija ga ne uporabi za odlocitev.
        static func razcleni(_ url: URL?) -> PovratniKlic? {
            guard let url,
                  url.scheme?.lowercased() == StripePlacilo.shemaVrnitve,
                  url.host?.lowercased() == "placilo",
                  let komponente = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            func parameter(_ ime: String) -> String? {
                let v = komponente.queryItems?.first(where: { $0.name == ime })?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (v?.isEmpty ?? true) ? nil : v
            }
            let narocilo = parameter("narocilo")
            switch parameter("stanje")?.lowercased() {
            case "uspeh": return .uspeh(narocilo: narocilo)
            case "preklic": return .preklic(narocilo: narocilo)
            default: return nil
            }
        }
    }

    /// Kako se je koncala seja s Stripovo stranjo.
    enum SejaIzid: Equatable {
        /// Klic nazaj `stanje=uspeh`: kupec je placal, webhook pride nekaj sekund kasneje.
        case uspeh
        /// Klic nazaj `stanje=preklic`.
        case preklic
        /// Kupec je sejo zaprl sam (`ASWebAuthenticationSessionError.canceledLogin`).
        case prekinil
        /// Seje ni bilo mogoce zagnati (`start()` vrne false): pokaze se »We couldn't open the payment page«, narocilo se ne bere.
        case nezagnana
        /// Seja je koncala z drugo napako ali z nerazumljivim URL-jem klica nazaj.
        case napaka

        /// Izid iz URL-ja klica nazaj (`nil` ali nerazumljiv URL -> `.napaka`).
        static func izKlica(_ url: URL?) -> SejaIzid {
            switch PovratniKlic.razcleni(url) {
            case .uspeh?: return .uspeh
            case .preklic?: return .preklic
            case nil: return .napaka
            }
        }

        /// Tiho (brez kartice in brez napake) je samo izrecni `preklic` s Stripove strani: kupec je sam pritisnil nazaj/Cancel na Stripu.
        /// Pri `prekinil` (zaprl je sejo sam) in `napaka` (preusmeritve ni bilo) je kupec morda placal, pa povratni klic ni prisel:
        /// narocilo se enkrat prebere, ce je se `pending`, ostane kartica »Checking your payment« z gumbom »Check again« (brez napake).
        var tiho: Bool { self == .preklic }

        /// Koliko samodejnih branj GET /me/orders sledi izidu.
        var poskusov: Int { self == .uspeh ? StripePlacilo.samodejnihBranjPoUspehu : 1 }
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

    /// Najvec samodejnih branj po klicu nazaj `stanje=uspeh` (webhook pride nekaj sekund po placilu): 5 branj, 2 s premora (~8 s),
    /// nato se bere samo se na uporabnikov pritisk (»Check again«): brez neskoncne zanke. Premor med branji je spodaj.
    static let samodejnihBranjPoUspehu = 5
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
