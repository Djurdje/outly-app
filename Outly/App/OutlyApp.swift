//
//  OutlyApp.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI

@main
struct OutlyApp: App {
    @StateObject private var prefs = UserPreferences()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var session = SessionStore()
    @StateObject private var favorites = FavoritesStore()
    // Jezik (en | sl): singleton, ker Bundle.main dobi podrazred ze v init.
    @ObservedObject private var jezik = Jezik.shared

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                // Ob menjavi jezika se celotno drevo zgradi znova (vsi Text, navigationTitle).
                .id(jezik.koda)
                .environment(\.locale, jezik.locale)
                .environmentObject(jezik)
                .environmentObject(prefs)
                .environmentObject(locationManager)
                .environmentObject(session)
                .environmentObject(favorites)
                // Ob odjavi pobrisi priljubljene prejsnjega racuna (tudi lokalni cache).
                .onChange(of: session.token) { _, novi in
                    if novi.isEmpty { favorites.clear() }
                }
        }
    }
}
