//
//  MainTabView.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI

struct MainTabView: View {
    // Izbran zavihek: domaci zaslon ("Where to?") preklopi na iskanje, avatar na profil.
    @State private var zavihek = 0
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        TabView(selection: $zavihek) {
            HomeView(odpriIskanje: { zavihek = 1 }, odpriProfil: { zavihek = 3 })
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(1)

            // Zavihek "Saved" umaknjen (Martin, 13. 9.): priljubljeni dogodki so
            // razdelek "Liked events" na domacem zaslonu (SavedView = "See all").
            // Vrstni red kot v Figmi: Home, Search, Map, Profile.
            MapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(.blackColor)
        // Priljubljeni s streznika ob prijavi (in ob menjavi seje).
        .task(id: session.token) { await favorites.load(token: session.token) }
    }
}
