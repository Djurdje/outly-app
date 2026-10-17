import Foundation

/// Cista logika zanrov v obrazcu dogodka (locena od pogleda zaradi testov; outly-app #97).
///
/// Zanri se izbirajo samo iz zaprtega seznama (GET /genres). Ce se ta seznam ni nalozil (ni povezave, 503),
/// uporabnik zanrov ne vidi in jih ne more spremeniti. Zato jih v zahtevku NE posljemo: strezniku `genres` ni
/// treba dobiti, PATCH brez `genres` zanrov ne spremeni, POST brez `genres` pa dogodek podeduje zanre kluba
/// (outly-backend `_testi/test_zanri_validacija.js`). Prazen seznam `[]` bi zanre dogodka izbrisal.
enum ZanriDogodka {
    /// Vrednost za polje `genres` v POST/PATCH /events. `nil` = polja sploh ne posljemo.
    /// - Parameter vsi: zaprti seznam zanrov s streznika (prazen = se ni nalozen).
    /// - Parameter izbrani: izbira uporabnika (pri urejanju prednapolnjena z zanri dogodka).
    static func zaPosiljanje(vsi: [String], izbrani: Set<String>) -> [String]? {
        guard !vsi.isEmpty else { return nil }
        return vsi.filter { izbrani.contains($0) }
    }
}
