import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @EnvironmentObject var prefs: UserPreferences
    @EnvironmentObject var locationManager: LocationManager

    @State private var selectedGenres = Set<MusicGenre>()
    @State private var selectedAge: AgeGroup? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                Text("Setup")
                    .font(.title.bold())

                GroupBox(label: Text("Location")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enable location to show clubs near you.")
                            .foregroundStyle(.secondary)

                        Button {
                            locationManager.requestPermission()
                        } label: {
                            Text(locationButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                GroupBox(label: Text("Age group")) {
                    VStack(alignment: .leading) {
                        ForEach(AgeGroup.allCases) { group in
                            HStack {
                                Text(group.rawValue)
                                Spacer()
                                Image(systemName: selectedAge == group ? "checkmark.circle.fill" : "circle")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedAge = group }
                            .padding(.vertical, 6)
                        }
                    }
                }

                GroupBox(label: Text("Genres")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(MusicGenre.allCases) { genre in
                            let isSelected = selectedGenres.contains(genre)

                            Text(genre.title)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    if isSelected { selectedGenres.remove(genre) }
                                    else { selectedGenres.insert(genre) }
                                }
                        }
                    }
                }

                GroupBox(label: Text("Max distance (km)")) {
                    VStack(alignment: .leading) {
                        Text("\(Int(prefs.maxDistanceKm)) km")
                        Slider(value: $prefs.maxDistanceKm, in: 1...100, step: 1)
                    }
                }

                Button {
                    prefs.selectedGenres = Array(selectedGenres)
                    prefs.selectedAgeGroup = selectedAge
                    prefs.onboardingCompleted = true
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAge == nil || selectedGenres.isEmpty)

            }
            .padding()
        }
    }

    private var locationButtonTitle: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Location enabled"
        case .denied, .restricted:
            return "Location denied (Settings)"
        default:
            return "Enable location"
        }
    }
}
