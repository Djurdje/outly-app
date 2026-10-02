import Foundation

/// Napotek ob PONOVNEM odprtju nakupnega lista po nejasnem izidu (timeout, izgubljena povezava, 409 `request_in_progress`):
/// narocilo je morda ze nastalo, zato uporabnik to izve ze ob odprtju, ne sele ob novem pritisku (outly-backend #130,
/// paritet s spletom outly_webpage #29 / `webapp/js/views/nakup.js`, `vip-kupec.js`).
///
/// Cisti tip brez UI-ja (testabilen). Bere SAMO `NakupniKljucShramba.odprtaVsebina`; pravil kljuca ne spreminja in kolicine
/// ne zaklepa (sprememba kolicine = nov kljuc, kot prej). `odprtaVsebina` je nil po uspehu, dokoncni napaki, rotaciji kljuca,
/// izteku in odjavi, zato napotka tedaj ni.
enum NakupniNapotek: Equatable {
    /// Narocilo je morda ze nastalo; ponovni pritisk z istim kljucem to preveri (ne bo drugega narocila).
    case moznoUspel
    /// VIP: lastne mize ni vec mogoce izbrati (v tlorisu je »Booked«), zato ponovitve z istim kljucem ni; narocilo je
    /// morda ze v Profil -> Tickets.
    case preveriProfil

    /// List vstopnic: napotek samo, ce je nerazresen poskus vstopnic (vsebina brez mize).
    static func zaVstopnice(odprtaVsebina vsebina: NakupniKljuc.Vsebina?) -> NakupniNapotek? {
        guard let v = vsebina, v.mizaId == nil else { return nil }
        return .moznoUspel
    }

    /// VIP list: napotek samo, ce je nerazresen poskus mize. Miza se je obdrzala (se prosta) -> `.moznoUspel`
    /// (ponovni pritisk preveri); ni je vec med prostimi (kupljena ali umaknjena) -> `.preveriProfil`.
    static func zaVip(odprtaVsebina vsebina: NakupniKljuc.Vsebina?, mizaProsta: Bool) -> NakupniNapotek? {
        guard let v = vsebina, v.mizaId != nil else { return nil }
        return mizaProsta ? .moznoUspel : .preveriProfil
    }

    /// Besedilo; ista angleska niza kot splet (`nakupBrezOdgovoraSporocilo`, `vip-kupec.js`), sl v `Localizable.xcstrings`.
    var besedilo: String {
        switch self {
        case .moznoUspel:
            return String(localized: "Your purchase may have gone through — tap the button again to check (you won't be charged twice).")
        case .preveriProfil:
            return String(localized: "No response from the server. Check Profile → Tickets before you try again.")
        }
    }
}
