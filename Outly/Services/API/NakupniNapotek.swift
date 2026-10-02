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

    /// List vstopnic: napotek samo, ce je nerazresen poskus vstopnic (`odprta` brez mize). Izpeljan iz TRENUTNE izbire:
    /// `.moznoUspel` (»tap the button again ... won't be charged twice«) samo, ce je trenutna vsebina enaka nerazresenemu
    /// poskusu (isti kljuc) IN je gumb Pay na voljo; sicer `.preveriProfil` (druga kolicina = nov kljuc, ali gumba ni).
    static func zaVstopnice(odprta: NakupniKljuc.Vsebina?, trenutna: NakupniKljuc.Vsebina,
                            gumbNaVoljo: Bool) -> NakupniNapotek? {
        guard let o = odprta, o.mizaId == nil else { return nil }
        return izberi(istaVsebina: o == trenutna, gumbNaVoljo: gumbNaVoljo)
    }

    /// VIP list: napotek samo, ce je nerazresen poskus mize (`odprta` z mizo). `trenutna` = trenutna izbira mize in paketa
    /// (nil = nobena miza ni izbrana, npr. lastna miza je ze »Booked«). `.moznoUspel` samo ob isti mizi in istem paketu
    /// IN ko je gumb Reserve na voljo (prodaja odprta); sicer `.preveriProfil`.
    static func zaVip(odprta: NakupniKljuc.Vsebina?, trenutna: NakupniKljuc.Vsebina?,
                      gumbNaVoljo: Bool) -> NakupniNapotek? {
        guard let o = odprta, o.mizaId != nil else { return nil }
        return izberi(istaVsebina: trenutna == o, gumbNaVoljo: gumbNaVoljo)
    }

    private static func izberi(istaVsebina: Bool, gumbNaVoljo: Bool) -> NakupniNapotek {
        (istaVsebina && gumbNaVoljo) ? .moznoUspel : .preveriProfil
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
