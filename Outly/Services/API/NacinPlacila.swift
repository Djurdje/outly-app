import Foundation

/// Nacin placila prodajalca (backend `payment_mode`, outly-backend#203 / #149): polje je odvisno od KLUBA, ne od uporabnika.
/// Pride v dogodkih (seznam, podrobnosti), v odgovoru VIP tlorisa (`GET /events/:id/vip`) in v `GET /business/sales`.
///
///  – `test`: klub brez dokoncanega Stripa (zivi backend ga ne vrne; prikazuje se kot navaden nakup, brez napisa);
///  – `stripe`: pravo placilo prek Stripe Checkouta;
///  – `unavailable`: nakup bi bil zavrnjen (409 »club does not accept online payments yet« / 503) -> gumb onemogocen s pojasnilom;
///  – `neznan`: star backend polja ne poslje (nil) -> nakup ni blokiran. Neznana vrednost v prihodnosti se obravnava kot `stripe`.
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

    /// Nakup bi bil zavrnjen: gumb onemogocen, pokazi pojasnilo namesto klica, ki konca z 409.
    var prodajaNedosegljiva: Bool { self == .nedosegljivo }
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
                ? String(localized: "Buyers can't purchase yet: complete your seller details in Club info.")
                : String(localized: "Buyers can't purchase yet: the club owner needs to complete the seller details in Club info.")
        case .placilaNenastavljena: return String(localized: "Payments aren't set up yet. Contact Outly.")
        case .stripeNiPripravljen: return String(localized: "Buyers can't purchase yet — connect Stripe at outly.si/app.")
        }
    }
}
