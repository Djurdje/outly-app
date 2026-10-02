import Foundation

/// Idempotentni kljuc nakupa (outly-backend #112 / PR #123): glava `Idempotency-Key` na
/// POST /events/:id/orders in POST /events/:id/tables/:tableId/orders.
///
/// Pravila (dogovor z backendom):
/// – isti kljuc pri ponovnem poskusu ISTEGA nakupa (timeout, izgubljena povezava, 503, 409 `request_in_progress`,
///   ponovni pritisk po napaki): backend vrne isto narocilo namesto drugega;
/// – nov kljuc ob vsakem novem nakupu: spremenjena vsebina (dogodek, kolicina, miza, paket), po uspehu in ko backend
///   kljuc zavrne (422 `idempotency_key_reused`). Cena ni del identitete (isto kot na strezniku).
///
/// Cisti tip brez UI-ja, da so pravila testabilna (OutlyTests/NakupniKljucTests). Pogled ga hrani v `@State`.
/// Stari backend glavo ignorira, zato je uporaba varna tudi pred objavo backenda.
struct NakupniKljuc {

    /// Kaj kljuc »podpisuje«; ob drugacni vsebini je to ze nov nakup.
    struct Vsebina: Equatable {
        var dogodekId: Int
        var kolicina: Int = 1
        var mizaId: Int? = nil
        var paketId: Int? = nil
    }

    private(set) var vrednost: String
    private var vsebina: Vsebina?
    private let ustvari: () -> String

    /// `ustvari`: izvor novih kljucev (UUID); v testih nadomestljiv z deterministicnim.
    init(ustvari: @escaping () -> String = { UUID().uuidString }) {
        self.ustvari = ustvari
        self.vrednost = ustvari()
        self.vsebina = nil
    }

    /// Klici tik pred posiljanjem. Vrne kljuc za ta nakup: isti kot pri prejsnjem poskusu iste vsebine,
    /// nov, ce se je vsebina medtem spremenila.
    mutating func zaNakup(_ nova: Vsebina) -> String {
        if let prejsnja = vsebina, prejsnja != nova { vrednost = ustvari() }
        vsebina = nova
        return vrednost
    }

    /// Nakup je uspel: naslednji nakup je nov nakup.
    mutating func poUspehu() {
        vrednost = ustvari()
        vsebina = nil
    }

    /// Nakup je padel. Kljuc ostane (ponovni poskus je varen), razen ce ga je backend zavrnil.
    mutating func poNapaki(_ izid: NakupniIzid) {
        guard izid == .kljucZavrzen else { return }
        vrednost = ustvari()
        vsebina = nil
    }
}

/// Izid napacnega nakupa z vidika kljuca.
enum NakupniIzid: Equatable {
    /// Navadna napaka (409 razprodano, 403, 503 ...): kljuc ostane, uporabnik lahko poskusi znova.
    case navadna
    /// 409 `request_in_progress`: prejsnji poskus se obdeluje; isti kljuc, pocakaj (Retry-After, privzeto 2 s).
    case vObdelavi
    /// 422 `idempotency_key_reused` (ali 400 `invalid_idempotency_key`, ki ne bi smel nastati): nov kljuc.
    case kljucZavrzen
    /// Timeout / izgubljena povezava: nakup je morda uspel; isti kljuc, ponovni pritisk to preveri.
    case nejasen
}

extension Error {
    /// Razvrstitev napake nakupa po pravilih kljuca (glej `NakupniKljuc`).
    var nakupniIzid: NakupniIzid {
        if let url = self as? URLError {
            return (url.code == .timedOut || url.code == .networkConnectionLost) ? .nejasen : .navadna
        }
        guard let api = self as? APIError, case .requestFailed(let code, let raw) = api else { return .navadna }
        let t = raw.lowercased()
        switch code {
        case 422 where t.contains("idempotency_key_reused"): return .kljucZavrzen
        case 400 where t.contains("invalid_idempotency_key"): return .kljucZavrzen
        case 409 where t.contains("request_in_progress"): return .vObdelavi
        // -1 = odgovor ni prispel; »Could not refresh session« pa pomeni, da nakup sploh ni bil poslan.
        case -1 where !t.contains("refresh"): return .nejasen
        default: return .navadna
        }
    }

    /// Kako dolgo naj bo gumb za nakup onemogocen po napaki (nil = ne): 503 naval 5 s, 409 `request_in_progress` 2 s.
    /// Nakupa se ne ponavlja samodejno; uporabnik pritisne znova (z istim kljucem je to varno).
    var nakupPremorNanosekund: UInt64? {
        if jeNakup503 { return NavalNakupa.premorNanosekund }
        if nakupniIzid == .vObdelavi { return NavalNakupa.premorVObdelaviNanosekund }
        return nil
    }
}

extension NavalNakupa {
    /// `Retry-After` iz glave `send()` ne vrne; backend ob `request_in_progress` privzeto pove 2 s.
    static let premorVObdelaviNanosekund: UInt64 = 2_000_000_000
}
