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

    var body: some Scene {
        WindowGroup {
            AuthGateView()
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
