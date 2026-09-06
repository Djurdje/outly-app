//
//  OutlyApp.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI
import SwiftData

@main
struct OutlyApp: App {
    @StateObject private var prefs = UserPreferences()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(prefs)
                .environmentObject(locationManager)
                .environmentObject(session)
        }
    }
}
