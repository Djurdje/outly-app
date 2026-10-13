import Foundation

/// Geslo in e-naslov racuna, ki caka na potrditev e-naslova. SAMO v pomnilniku procesa.
///
/// Zakaj: Supabasov mail vsebuje kodo IN povezavo. Ce uporabnik klikne povezavo, je racun potrjen,
/// koda pa je s tem porabljena (otp_expired) in nov mail se za potrjen racun ne poslje. Aplikacija
/// zato ob vrnitvi tiho poskusi prijavo z geslom, ki ga je uporabnik pravkar vpisal.
///
/// Pravila (varnost): geslo se NIKOLI ne zapise v UserDefaults/@AppStorage, Keychain, datoteko, dnevnik
/// ali Sentry. Po ponovnem zagonu aplikacije ga ni (uporabnik se prijavi sam). Pocisti se ob uspesni
/// prijavi, ob »Change email« in ob odhodu na prijavo.
@MainActor
final class CakajocaPotrditev {
    static let shared = CakajocaPotrditev()
    private init() {}

    private var email: String?
    private var geslo: String?

    func shrani(email: String, geslo: String) {
        self.email = email
        self.geslo = geslo
    }

    /// Geslo, ce je shranjeno za TA e-naslov (sicer nil).
    func geslo(za email: String) -> String? {
        guard let shranjen = self.email, shranjen == email else { return nil }
        return geslo
    }

    func pocisti() {
        email = nil
        geslo = nil
    }
}
