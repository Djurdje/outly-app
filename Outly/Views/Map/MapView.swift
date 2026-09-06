import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager

    @State private var clubs: [APIClub] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                CleanMKMapView(
                    userLocation: locationManager.location,
                    selectedClub: selectedClub
                )
                .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 10)
                }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 10)
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task {
            locationManager.requestPermission()
            await loadClubs()
        }
    }

    // samo klubi z veljavnimi koordinatami
    private var clubsWithCoordinates: [APIClub] {
        clubs.filter { $0.lat != nil && $0.lng != nil }
    }

    // izberi EN klub: najbližjega userju, sicer prvega
    private var selectedClub: APIClub? {
        guard !clubsWithCoordinates.isEmpty else { return nil }

        guard let userLoc = locationManager.location else {
            return clubsWithCoordinates.first
        }

        return clubsWithCoordinates.min { a, b in
            let da = distance(from: userLoc.coordinate, to: clubCoordinate(a)!)
            let db = distance(from: userLoc.coordinate, to: clubCoordinate(b)!)
            return da < db
        }
    }

    private func clubCoordinate(_ club: APIClub) -> CLLocationCoordinate2D? {
        guard let lat = club.lat, let lng = club.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func loadClubs() async {
        guard clubs.isEmpty else { return }
        isLoading = true
        errorText = nil
        do {
            clubs = try await APIClient.shared.fetchClubs()
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}

//
// MARK: - MKMapView wrapper (NO auto Ljubljana, black pin)
//
private struct CleanMKMapView: UIViewRepresentable {
    let userLocation: CLLocation?
    let selectedClub: APIClub?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)

        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false

        map.showsUserLocation = true

        map.isRotateEnabled = true
        map.isPitchEnabled = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
            
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // odstrani stare pin-e (razen user)
        let toRemove = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(toRemove)

        // dodaj EN club pin (črn)
        if let club = selectedClub,
           let lat = club.lat,
           let lng = club.lng {

            let ann = MKPointAnnotation()
            ann.title = club.name
            ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            map.addAnnotation(ann)
        }

        // CENTER LOGIKA (to je KLJUČNO)
        if let userLoc = userLocation {
            let region = MKCoordinateRegion(
                center: userLoc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
            map.setRegion(region, animated: true)

        } else if let club = selectedClub,
                  let lat = club.lat,
                  let lng = club.lng {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
            )
            map.setRegion(region, animated: true)
        }
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: ()) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {}

}
