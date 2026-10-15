import Foundation

/// Javni naslovi pravnih dokumentov. Eno mesto: LoginView, RegisterView, AboutView, DeleteAccount.
/// Objavljena 11. 9. 2026 na outly.si (terms.html, privacy-app.html — slovenska
/// politika za aplikacijo; /privacy je angleska politika spletne strani).
enum LegalLinks {
    static let terms   = URL(string: "https://outly.si/terms")!
    static let privacy = URL(string: "https://outly.si/privacy-app")!
    /// Razlicica Pogojev uporabe, ki jo aplikacija zapise ob registraciji (`terms_version` v Supabase user_metadata) in ob nakupu z
    /// racunom (polje telesa `terms_version`; outly-backend#215, ZVPot-1 21/1-2, ZEPT 7/1). Mora ostati ENAKA kot `TERMS_VERSION`
    /// v outly_webpage `webapp/js/pogoji.js` in v `terms.html`; ob novih pogojih se dvigne na obeh mestih hkrati.
    nonisolated static let termsVersion = "1.1.2"
    /// Prijava za ustvarjalce/klube (obstaja na spletni strani).
    static let creatorForm = URL(string: "https://outly.si/Creator.html")!
}
