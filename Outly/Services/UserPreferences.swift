import SwiftUI
import Foundation
import Combine

/// Lokalne nastavitve, ki NISO del racuna na strezniku.
/// Zanri in datum rojstva so od dokoncanja racuna naprej na strezniku (GET /me),
/// zato jih tu ni vec. Stara kljuca "selectedGenres"/"selectedAgeGroup" v UserDefaults
/// ostaneta neuporabljena in ju lahko kdaj pocistimo.
///
/// "My preferences" (Profil -> Preferences -> My preferences): privzeti zanri, razdalja,
/// starostni razpon in razpon cene vstopnice. Uporabi jih stikalo "Use my preferences"
/// na zaslonu Filtri. Shranjeno na napravi (@AppStorage), backend tega (se) ne pozna;
/// zanri se ob prazni lokalni vrednosti vzamejo iz racuna (Me.genres).
final class UserPreferences: ObservableObject {
    @AppStorage("maxDistanceKm") var maxDistanceKm: Double = 20

    /// Zanri, loceni z vejico (AppStorage ne zna [String]). Prazno = uporabi Me.genres.
    @AppStorage("pref.genres") var savedGenresRaw: String = ""
    @AppStorage("pref.ageMin") var ageMin: Int = 18
    @AppStorage("pref.ageMax") var ageMax: Int = 30
    /// Cena vstopnice v centih (pravilo 9: zneski v centih).
    @AppStorage("pref.priceMinCents") var priceMinCents: Int = 0
    @AppStorage("pref.priceMaxCents") var priceMaxCents: Int = 3000

    var savedGenres: [String] {
        get { savedGenresRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty } }
        set { savedGenresRaw = newValue.joined(separator: ",") }
    }
}
