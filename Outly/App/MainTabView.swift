//
//  MainTabView.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI

/// Koren aplikacije po prijavi: Home 0, Search 1, Map 2, Profile 3.
///
/// Od 20. 9. brez sistemskega TabView: Home je vedno spodaj, Search/Map/Profile so
/// plasti nad njim. Ob izbiri zavihka se Home zamegli, potemni in rahlo pomanjsa,
/// izbrani zaslon pa pride kot plast (odmik 36 pt, prosojnost). Vrnitev na Home
/// isti prehod v obratni smeri. Vsi stirje zasloni ostanejo zivi (vsak ima svoj
/// NavigationStack in stanje), tako kot prej v TabView.
struct MainTabView: View {
    // Izbran zavihek: domaci zaslon ("Where to?") preklopi na iskanje, avatar na profil.
    @State private var zavihek = 0

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var jezik: Jezik

    /// Krivulja kot na outly.si (cubic-bezier(.2,.9,.2,1)).
    private let prehod = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.45)

    private var jeNaHome: Bool { zavihek == 0 }

    var body: some View {
        ZStack {
            HomeView(odpriIskanje: { izberi(1) }, odpriProfil: { izberi(3) })
                .scaleEffect(jeNaHome ? 1 : 0.96)
                .blur(radius: jeNaHome ? 0 : 18)
                .brightness(jeNaHome ? 0 : -0.45)
                .allowsHitTesting(jeNaHome)
                .accessibilityHidden(!jeNaHome)

            // Scrim nad zamegljenim Home (crna 35 %).
            Color.black.opacity(jeNaHome ? 0 : 0.35)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            plast(1) { SearchView() }
            plast(2) { MapView() }
            plast(3) { ProfileView() }
        }
        .animation(prehod, value: zavihek)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OutlyTabBar(selected: Binding(get: { zavihek }, set: { izberi($0) }))
        }
        .background(Color.outlyBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // Priljubljeni s streznika ob prijavi (in ob menjavi seje).
        .task(id: session.token) { await favorites.load(token: session.token) }
        // Po preklopu jezika (koren dobi nov .id) se vrni na zavihek, kjer je bil preklop.
        .onAppear {
            if let z = jezik.zavihekPoPreklopu { zavihek = z; jezik.zavihekPoPreklopu = nil }
        }
    }

    private func izberi(_ nov: Int) {
        guard nov != zavihek else { return }
        withAnimation(prehod) { zavihek = nov }
    }

    /// Zaslon kot plast nad Home: viden in odziven samo, ko je izbran.
    private func plast<V: View>(_ tag: Int, @ViewBuilder _ vsebina: () -> V) -> some View {
        let izbran = zavihek == tag
        return vsebina()
            .opacity(izbran ? 1 : 0)
            .offset(y: izbran ? 0 : 36)
            .scaleEffect(izbran ? 1 : 0.985)
            .allowsHitTesting(izbran)
            .accessibilityHidden(!izbran)
    }
}
