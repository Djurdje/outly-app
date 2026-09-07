import Foundation

/// Javni naslovi pravnih dokumentov. Eno mesto: LoginView, RegisterView, AboutView, DeleteAccount.
/// Dokumenta sta osnutka v mapi pravno/ in cakata odvetnikov pregled; dokler nista
/// objavljena na outly.si, ti naslovi vrnejo 404 — to je znano in ni napaka aplikacije.
enum LegalLinks {
    static let terms   = URL(string: "https://outly.si/terms")!
    static let privacy = URL(string: "https://outly.si/privacy")!
    /// Prijava za ustvarjalce/klube (obstaja na spletni strani).
    static let creatorForm = URL(string: "https://outly.si/Creator.html")!
}
