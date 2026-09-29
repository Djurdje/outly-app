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

    init() {
        // Predpomnilnik slik (AsyncImage gre skozi URLSession.shared -> URLCache.shared). Privzeti
        // je premajhen (~0,5 MB v pomnilniku) za plakate, zato se je vsaka slika ob vsakem preklopu
        // zavihka znova prenesla in dekodirala (29. 9. 2026, "aplikacija steka").
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

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
