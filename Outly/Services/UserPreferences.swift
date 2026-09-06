import SwiftUI
import Foundation
import Combine

enum AgeGroup: String, CaseIterable, Identifiable, Codable {
    case under18 = "Under 18"
    case _18plus = "18+"
    case _21plus = "21+"
    case _25plus = "25+"
    var id: String { rawValue }
}

enum MusicGenre: String, CaseIterable, Identifiable, Codable {
    case balkan, techno, house, hiphop, rnb, pop, rock, edm, afro, exyu
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

final class UserPreferences: ObservableObject {
    @AppStorage("onboardingCompleted") var onboardingCompleted: Bool = false
    @AppStorage("selectedGenres") private var selectedGenresRaw: String = ""
    @AppStorage("selectedAgeGroup") private var selectedAgeGroupRaw: String = ""
    @AppStorage("maxDistanceKm") var maxDistanceKm: Double = 20

    var selectedGenres: [MusicGenre] {
        get { selectedGenresRaw.split(separator: ",").compactMap { MusicGenre(rawValue: String($0)) } }
        set { selectedGenresRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    var selectedAgeGroup: AgeGroup? {
        get { AgeGroup(rawValue: selectedAgeGroupRaw) }
        set { selectedAgeGroupRaw = newValue?.rawValue ?? "" }
    }
}
