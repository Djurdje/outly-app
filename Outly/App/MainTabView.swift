//
//  MainTabView.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI

/// Sistemski TabView (Martin, 20. 9.: vrstica ostane sistemska). "Kot Revolut" (Luka, 21. 9.):
/// ob preklopu z domacega zaslona na Search ali Profile se domaci zaslon posname in zamegli;
/// posnetek gre v okolje (`posnetekDoma`) in vsak zaslon v teh dveh zavihkih ga narise kot svoje
/// ozadje (`.outlyOzadje()`, glej Ozadje.swift). Map ostane pravi zemljevid.
/// Posnetek nastane PRED preklopom (lastni Binding), zato kaze tocno tisto, kar je bilo na zaslonu.
struct MainTabView: View {
    // Izbran zavihek: domaci zaslon ("Where to?") preklopi na iskanje, avatar na profil.
    @State private var zavihek = 0
    @State private var posnetekDoma: UIImage?
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var jezik: Jezik

    /// Preklop zavihka: ce zapuscamo domaci zaslon, ga najprej posnamemo.
    private var izbira: Binding<Int> {
        Binding(get: { zavihek }, set: { nov in preklopi(na: nov) })
    }

    private func preklopi(na nov: Int) {
        if zavihek == 0 && nov != 0 { posnetekDoma = UIApplication.shared.posnetekZaslona() }
        zavihek = nov
    }

    var body: some View {
        TabView(selection: izbira) {
            HomeView(odpriIskanje: { preklopi(na: 1) }, odpriProfil: { preklopi(na: 3) })
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            SearchView()
                .environment(\.posnetekDoma, posnetekDoma)
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
                .environment(\.posnetekDoma, posnetekDoma)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(.blackColor)
        // Priljubljeni s streznika ob prijavi (in ob menjavi seje).
        .task(id: session.token) { await favorites.load(token: session.token) }
        // Po preklopu jezika (koren dobi nov .id) se vrni na zavihek, kjer je bil preklop.
        .onAppear {
            if let z = jezik.zavihekPoPreklopu { zavihek = z; jezik.zavihekPoPreklopu = nil }
        }
    }
}
