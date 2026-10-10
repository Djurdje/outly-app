//
//  OutlyApp.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI

@main
struct OutlyApp: App {
    // Potisna obvestila (APNs): zeton naprave in dotik na obvestilo (OutlyAppDelegate).
    @UIApplicationDelegateAdaptor(OutlyAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
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
        // Odgovori API-ja so pred tem sli na ta disk (imena imetnikov vstopnic): enkrat jih pobrisemo, odslej API ne pise vec na disk.
        APIPredpomnilnik.enkratnoPocistiStareOdgovore()
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
                .environmentObject(PushUsmerjevalnik.deljen)
                // Ob odjavi pobrisi priljubljene prejsnjega racuna (tudi lokalni cache).
                .onChange(of: session.token) { _, novi in
                    if novi.isEmpty { favorites.clear() } else { PushObvestila.deljen.osvezi() }
                }
                // Potisna obvestila: zeton se poslje, ko je znan uporabnik (GET /me), ne ze ob zetonu seje.
                .onChange(of: session.me?.id) { _, _ in PushObvestila.deljen.uskladi() }
                // Zagon in vrnitev v ospredje: ce je dovoljenje ze odobreno, naj iOS (znova) vrne zeton (brez vprasanja).
                .onChange(of: scenePhase) { _, faza in
                    if faza == .active { PushObvestila.deljen.osvezi() }
                }
                .task { PushObvestila.deljen.osvezi() }
        }
    }
}
