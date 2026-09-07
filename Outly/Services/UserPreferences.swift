import SwiftUI
import Foundation
import Combine

/// Lokalne nastavitve, ki NISO del racuna na strezniku.
/// Zanri in datum rojstva so od dokoncanja racuna naprej na strezniku (GET /me),
/// zato jih tu ni vec. Stara kljuca "selectedGenres"/"selectedAgeGroup" v UserDefaults
/// ostaneta neuporabljena in ju lahko kdaj pocistimo.
final class UserPreferences: ObservableObject {
    @AppStorage("maxDistanceKm") var maxDistanceKm: Double = 20
}
