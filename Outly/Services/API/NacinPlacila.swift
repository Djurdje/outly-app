import Foundation

/// Nacin placila prodajalca (backend `payment_mode`, outly-backend#203 / #149): polje je odvisno od KLUBA, ne od uporabnika.
/// Pride v dogodkih (seznam, podrobnosti), v odgovoru VIP tlorisa (`GET /events/:id/vip`) in v `GET /business/sales`.
///
///  – `test`: nic se ne zaracuna (testni sistem ali klub brez dokoncanega Stripa) -> vrstica »Test mode — nothing is charged«;
///  – `stripe`: pravo placilo prek Stripe Checkouta -> BREZ napisa o testnem nacinu;
///  – `unavailable`: nakup bi bil zavrnjen (409 »club does not accept online payments yet« / 503) -> gumb onemogocen s pojasnilom;
///  – `neznan`: star backend polja ne poslje (nil) -> DANASNJE vedenje (vrstica se kaze kot doslej, nakup ni blokiran),
///    da stara kombinacija ne pokvari nicesar. Neznana vrednost v prihodnosti se obravnava kot `stripe` (napisa o brezplacnem
///    nakupu NIKOLI ne kazemo, ce ni gotovo, da je res).
enum NacinPlacila: Equatable {
    case test
    case stripe
    case nedosegljivo
    case neznan

    init(_ niz: String?) {
        switch niz {
        case nil: self = .neznan
        case "test"?: self = .test
        case "unavailable"?: self = .nedosegljivo
        default: self = .stripe
        }
    }

    /// Ali naj nakupni list pokaze vrstico »Test mode — nothing is charged«. Cena 0 = placila ni, zato napisa ni
    /// (kjer je nacin znan); star backend (`neznan`) ohrani danasnje vedenje.
    func kazeTestniNapis(brezplacno: Bool) -> Bool {
        switch self {
        case .neznan: return true
        case .test: return !brezplacno
        case .stripe, .nedosegljivo: return false
        }
    }

    /// Nakup bi bil zavrnjen: gumb onemogocen, pokazi pojasnilo namesto klica, ki konca z 409.
    var prodajaNedosegljiva: Bool { self == .nedosegljivo }

    /// Napis v dashboardu lastnika: `payment_mode` kluba, sicer (star backend) globalni `mode == "test"` kot doslej.
    static func dashboardTestni(paymentMode: String?, mode: String) -> Bool {
        guard let paymentMode else { return mode == "test" }
        return paymentMode == "test"
    }
}

/// Razlog, zakaj je `payment_mode == "unavailable"` (backend#221, `payment_unavailable_reason` v `GET /business/sales`).
/// Samo za besedilo opozorila v dashboardu lastnika; nil, `stripe_not_ready` in neznana vrednost (prihodnji razlog) dajo
/// obstojece besedilo (»connect Stripe«), da se vedenje ne spremeni.
enum RazlogNedosegljivosti: Equatable {
    /// "seller_incomplete": zivi Stripe, klub ima Stripe, podatki prodajalca nepopolni.
    case prodajalecNepopoln
    /// "payments_not_configured": na streznik manjka nastavitev placil (lastnik ne more nicesar storiti).
    case placilaNenastavljena
    /// "stripe_not_ready", nil ali neznano: klub nima dokoncanega Stripa (obstojece besedilo).
    case stripeNiPripravljen

    init(_ niz: String?) {
        switch niz {
        case "seller_incomplete"?: self = .prodajalecNepopoln
        case "payments_not_configured"?: self = .placilaNenastavljena
        default: self = .stripeNiPripravljen
        }
    }

    /// Besedilo opozorila v dashboardu (angleski kljuci so isti kot na spletu). Podatke prodajalca sme izpolniti samo lastnik
    /// kluba (backend#94), zato manager pri `.prodajalecNepopoln` dobi besedilo, ki lastnika omeni (kot splet).
    func besedilo(jeLastnik: Bool) -> String {
        switch self {
        case .prodajalecNepopoln:
            return jeLastnik
                ? String(localized: "Buyers can't purchase yet: complete your seller details in Settings.")
                : String(localized: "Buyers can't purchase yet: the club owner needs to complete the seller details in Settings.")
        case .placilaNenastavljena: return String(localized: "Payments aren't set up yet. Contact Outly.")
        case .stripeNiPripravljen: return String(localized: "Buyers can't purchase yet — connect Stripe at outly.si/app.")
        }
    }
}
