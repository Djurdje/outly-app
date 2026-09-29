import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Brez tega je CoreLocation posiljal posodobitve neprestano (tudi ko uporabnik stoji),
        // vsaka objava `location` pa je znova izrisala domaci zaslon, zemljevid in koren
        // aplikacije (29. 9. 2026, "aplikacija steka"). Razdalje do klubov so v km — 100 m je dovolj.
        manager.distanceFilter = 100
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    private func startUpdating() {
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let nova = locations.last else { return }
        // Objavimo samo ob opaznem premiku (ali prvi lokaciji) — glej distanceFilter zgoraj.
        if let stara = location, nova.distance(from: stara) < 50 { return }
        location = nova
    }
}
