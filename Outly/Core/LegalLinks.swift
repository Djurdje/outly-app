import Foundation

/// Javni naslovi pravnih dokumentov. Eno mesto: LoginView, RegisterView, AboutView, DeleteAccount.
/// Objavljena 11. 9. 2026 na outly.si (terms.html, privacy-app.html — slovenska
/// politika za aplikacijo; /privacy je angleska politika spletne strani).
enum LegalLinks {
    static let terms   = URL(string: "https://outly.si/terms")!
    static let privacy = URL(string: "https://outly.si/privacy-app")!
    /// Prijava za ustvarjalce/klube (obstaja na spletni strani).
    static let creatorForm = URL(string: "https://outly.si/Creator.html")!
}
