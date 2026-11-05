import SwiftUI
import MapKit
import CoreLocation

/// Zemljevid VSEH klubov (GET /clubs/map). Prej je risal en sam klub — najblizjega.
/// Dotik pina odpre ClubDetailView.
@MainActor
struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager

    @State private var clubs: [MapClub] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedClubId: Int?
    @State private var showClub = false
    @State private var hasCentered = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ClubsMKMapView(
                    clubs: clubs,
                    userLocation: locationManager.location,
                    hasCentered: $hasCentered,
                    onSelect: { id in
                        selectedClubId = id
                        showClub = true
                    }
                )
                .ignoresSafeArea(edges: .top)

                if isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 10)
                }

                if let errorText {
                    VStack(spacing: 6) {
                        Text(errorText).foregroundStyle(.red)
                        Button("Try again") { Task { await loadClubs(force: true) } }
                            .foregroundStyle(Color.outlyBlue)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 10)
                }

                if !isLoading, errorText == nil, clubs.isEmpty {
                    Text("No clubs on the map yet.")
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 10)
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showClub) {
                if let id = selectedClubId {
                    ClubDetailView(clubId: id)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            locationManager.requestPermission()
            await loadClubs(force: false)
        }
    }

    private func loadClubs(force: Bool) async {
        guard force || clubs.isEmpty else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            clubs = try await APIClient.shared.fetchMapClubs()
        } catch {
            errorText = error.userMessage
        }
    }
}

// MARK: - MKMapView

private final class ClubAnnotation: NSObject, MKAnnotation {
    let clubId: Int
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(club: MapClub) {
        clubId = club.clubId
        coordinate = CLLocationCoordinate2D(latitude: club.lat, longitude: club.lng)
        title = club.name
        subtitle = club.city.isEmpty ? nil : club.city
    }
}

private extension MapClub {
    var clubId: Int { id }
}

private struct ClubsMKMapView: UIViewRepresentable {
    let clubs: [MapClub]
    let userLocation: CLLocation?
    @Binding var hasCentered: Bool
    let onSelect: (Int) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false
        map.showsUserLocation = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "club")
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Pine osvezimo samo, ce se je seznam spremenil (sicer utripajo ob vsakem premiku).
        let current = Set(map.annotations.compactMap { ($0 as? ClubAnnotation)?.clubId })
        let wanted = Set(clubs.map(\.id))
        if current != wanted {
            map.removeAnnotations(map.annotations.filter { $0 is ClubAnnotation })
            map.addAnnotations(clubs.map(ClubAnnotation.init(club:)))
        }

        // Prvic centriramo: na uporabnika, sicer tako, da so vidni vsi klubi.
        // Potem uporabniku ne premikamo zemljevida vec (prej je skakal ob vsaki lokaciji).
        guard !hasCentered else { return }
        if let userLoc = userLocation {
            map.setRegion(MKCoordinateRegion(center: userLoc.coordinate,
                                             span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
                          animated: false)
            DispatchQueue.main.async { hasCentered = true }
        } else if !clubs.isEmpty {
            map.showAnnotations(map.annotations.filter { $0 is ClubAnnotation }, animated: false)
            DispatchQueue.main.async { hasCentered = true }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onSelect: (Int) -> Void
        init(onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is ClubAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "club", for: annotation) as! MKMarkerAnnotationView
            v.markerTintColor = UIColor(Color.outlyBlue)
            v.glyphImage = UIImage(systemName: "music.note")
            v.canShowCallout = true
            v.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return v
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let a = view.annotation as? ClubAnnotation else { return }
            onSelect(a.clubId)
        }
    }
}
