import SwiftUI
import MapKit

/// Staticen zemljevid s pinom kluba (Martin, 4. 10. 2026): ne drsi in ne povecuje, da nihce
/// po nesreci ne "izgubi" pina. Klik ponudi Apple Maps ali Google Maps z navodili za pot do kluba.
/// Velikost in obliko (frame, clipShape, overlay) doloci klicatelj.
struct StaticnaKarta: View {
    let lat: Double
    let lng: Double

    @Environment(\.openURL) private var openURL
    @State private var izbira = false

    private var koordinata: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        Button {
            izbira = true
        } label: {
            // interactionModes [] = brez drsenja/povecave; allowsHitTesting(false), da dotik
            // dobi gumb in da drsenje cez zemljevid premika stran.
            Map(initialPosition: .region(MKCoordinateRegion(
                center: koordinata,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))),
                interactionModes: []) {
                Marker("", coordinate: koordinata)
            }
            .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Get directions"))
        .confirmationDialog(Text("Get directions"), isPresented: $izbira, titleVisibility: .visible) {
            Button {
                odpriAppleMaps()
            } label: {
                Text(verbatim: "Apple Maps")
            }
            Button {
                odpriGoogleMaps()
            } label: {
                Text(verbatim: "Google Maps")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var cilj: String { "\(lat),\(lng)" }

    private func odpriAppleMaps() {
        if let url = URL(string: "https://maps.apple.com/?daddr=\(cilj)") {
            openURL(url)
        }
    }

    /// Najprej aplikacija Google Maps (shema comgooglemaps://, za openURL je
    /// LSApplicationQueriesSchemes ni treba); ce je ni, Google Maps v brskalniku.
    private func odpriGoogleMaps() {
        guard let aplikacija = URL(string: "comgooglemaps://?daddr=\(cilj)"),
              let splet = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(cilj)")
        else { return }
        openURL(aplikacija) { odprto in
            if !odprto { openURL(splet) }
        }
    }
}
