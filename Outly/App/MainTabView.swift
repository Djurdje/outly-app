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
///
/// Prehod Home <-> Search/Profile (Martin, 24. 9., po posnetku Revoluta po slicicah — ZAMENJAVA
/// za "krozno razkritje" iz PR #22, ki ga je Martin videl in ni hotel): BREZ maske/kroga. Namesto
/// tega vsebina cilja (cela, ne izrezana) zraste iz sidra v sredini avatarja/polja "Where to?" s
/// 40 % na 100 % velikosti, hkrati se pojavi (opacity 0->1) in izostri (blur ~10->0) v ~0,3 s
/// (ease-out) — to nosi `VstopZavihka` v okolju (Core/Themes/Ozadje.swift), ki jo `.outlyOzadje()`
/// prebere in uporabi na SVOJI vsebini zaslona. Poleg tega domaci zaslon pod njo v ~0,3 s zbledi
/// v ze zamegljen posnetek (`ZabrisSloj` nad TabViewom, oster posnetek pojema) — to je "Home se
/// zamegli" del. Nazaj (Profile/Search -> Home) je obratno in v koncu preklopimo zavihek.
/// Search <-> Profile je NAVADEN preklop, brez animacije (Martin izrecno). Karkoli <-> Map in
/// Reduce Motion ostaneta navaden zabris (ZabrisSloj), kot prej.
struct MainTabView: View {
    // Izbran zavihek: domaci zaslon ("Where to?") preklopi na iskanje, avatar na profil.
    @State private var zavihek = 0
    @State private var posnetekDoma: UIImage?
    /// Okvirja avatarja in polja "Where to?" (HomeView jih izmeri in poda navzgor).
    @State private var okvirIzvorov = IzvoriRazkritja()
    /// Trenutno stanje rasti/krcenja vsebine zavihka (glej VstopZavihka v Ozadje.swift) — v okolju,
    /// zato ga prebere `.outlyOzadje()` katerekoli globoke vsebine (tudi potisnjenih zaslonov).
    @State private var vstop = VstopZavihka.privzeto
    /// Zabrisi cez cel zaslon, trenutno na zaslonu (Map, Reduce Motion, in spremljevalna plast
    /// pri rasti/krcenju "Home se zamegli"/"Home se izostri") — obicajno 0 ali 1 naenkrat.
    @State private var zabrisi: [UUID: (slika: UIImage, trajanje: Double)] = [:]

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var jezik: Jezik
    @Environment(\.accessibilityReduceMotion) private var zmanjsanoGibanje

    /// Preklop zavihka: ce zapuscamo domaci zaslon, ga najprej posnamemo.
    private var izbira: Binding<Int> {
        Binding(get: { zavihek }, set: { nov in preklopi(na: nov) })
    }

    // MARK: - Sidra (avatar / Where to?)

    /// Velikost okna v tockah — isti koordinatni sistem kot okvirIzvorov (global) in posnetki.
    private var velikostOkna: CGSize {
        UIApplication.shared.kljucnoOkno?.bounds.size ?? UIScreen.main.bounds.size
    }

    private var oknoBounds: CGRect {
        CGRect(origin: .zero, size: velikostOkna)
    }

    /// Privzeti izvor za Profil, ce avatar ni (vec) viden (odrsan) — levi zgornji rob, kot prej.
    private var privzetIzvorProfil: CGRect {
        CGRect(x: 16, y: 54, width: 36, height: 36)
    }

    /// Privzeti izvor za Search, ce polje ni (vec) vidno — sredina vrha, kot prej.
    private var privzetIzvorIskanje: CGRect {
        let sirina = min(velikostOkna.width - 32, 320)
        return CGRect(x: (velikostOkna.width - sirina) / 2, y: 92, width: sirina, height: 48)
    }

    /// Okvir je "veljaven" (uporaben za sidro), ce ga poznamo IN je njegovo sredisce znotraj
    /// vidnega okna — sicer (odrsan, ali se ne izmerjen) uporabimo privzet izvor pri robu.
    private func veljavenIzvor(_ r: CGRect?) -> CGRect? {
        guard let r, r.width > 1, r.height > 1 else { return nil }
        let sredisce = CGPoint(x: r.midX, y: r.midY)
        return oknoBounds.contains(sredisce) ? r : nil
    }

    private var izvorProfil: CGRect { veljavenIzvor(okvirIzvorov.avatar) ?? privzetIzvorProfil }
    private var izvorIskanje: CGRect { veljavenIzvor(okvirIzvorov.whereTo) ?? privzetIzvorIskanje }

    /// Sidro skaliranja (UnitPoint, 0...1) iz okenskega okvirja — sredisce izvora glede na
    /// velikost okna. `scaleEffect(anchor:)` na vsebini priblizno enake velikosti kot okno
    /// (zaslon minus varni rob/spodnja vrstica) to prime dovolj natancno.
    private func sidroIz(_ izvor: CGRect) -> UnitPoint {
        let okno = velikostOkna
        guard okno.width > 0, okno.height > 0 else { return .topLeading }
        return UnitPoint(x: izvor.midX / okno.width, y: izvor.midY / okno.height)
    }

    // MARK: - Preklop

    private func preklopi(na nov: Int) {
        guard nov != zavihek else { return }  // dvakratni dotik iste ikone: sistemsko ze vrne na koren, sicer nic
        let od = zavihek

        // Ozadje za Search/Profile (zamegljen posnetek Home) osvezimo vedno, ko zapuscamo Home —
        // isti posnetek uporabi tudi zapriVHome kot spremljevalno plast ob vrnitvi.
        if od == 0 && nov != 0 { osveziOzadjeZavihka() }

        if zmanjsanoGibanje {
            // Trdo pravilo (Martin, 24. 9.): pri Reduce Motion samo navaden zabris, brez rasti/krcenja.
            zabris(na: nov, trajanje: 0.2)
            return
        }

        switch (od, nov) {
        case (2, _), (_, 2):
            // Karkoli <-> Map: navaden zabris, pusti kot je (Martin izrecno).
            zabris(na: nov, trajanje: 0.25)
        case (0, 1):
            odpriIzHome(na: nov, izvor: izvorIskanje)
        case (0, 3):
            odpriIzHome(na: nov, izvor: izvorProfil)
        case (1, 0):
            zapriVHome(odIzvora: izvorIskanje)
        case (3, 0):
            zapriVHome(odIzvora: izvorProfil)
        default:
            // Search <-> Profile: navaden preklop, brez animacije (Martin izrecno).
            zavihek = nov
        }
    }

    /// Home -> Search/Profile: vsebina cilja zraste iz sidra (40 % -> 100 %, opacity 0->1,
    /// blur 10->0, 0,3 s ease-out); zavihek preklopimo TAKOJ (POD plastjo je ze ziv cilj), plast
    /// nad njim (oster posnetek Home) v istem casu pojema in odkriva ze zamegljen posnetekDoma
    /// pod seboj — to je "Home se zamegli".
    private func odpriIzHome(na nov: Int, izvor: CGRect) {
        let sidro = sidroIz(izvor)
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else {
            zavihek = nov
            return
        }
        vstop = VstopZavihka(skala: 0.4, prosojnost: 0, zameglitev: 10, sidro: sidro)
        zavihek = nov
        dodajZabris(slika: surov, trajanje: 0.3)
        withAnimation(.easeOut(duration: 0.3)) {
            vstop = VstopZavihka(skala: 1, prosojnost: 1, zameglitev: 0, sidro: sidro)
        }
    }

    /// Search/Profile -> Home: najprej ziva vsebina zaslona, ki ga zapuscamo, skrci proti sidru
    /// (100 % -> 40 %), zbledi in zamegli (0,25 s); SELE PO KONCU (withAnimation(_:completion:),
    /// iOS 17) preklopimo zavihek na Home in nad njim za 0,2 s zbledi plast z zamegljenim
    /// posnetkom Home (posnetekDoma) — "domaci zaslon se izostri". Na koncu vstop ponastavimo
    /// BREZ animacije, da je ob naslednjem odprtju stanje cisto.
    private func zapriVHome(odIzvora izvor: CGRect) {
        let sidro = sidroIz(izvor)
        withAnimation(.easeIn(duration: 0.25)) {
            vstop = VstopZavihka(skala: 0.4, prosojnost: 0, zameglitev: 10, sidro: sidro)
        } completion: {
            zavihek = 0
            if let ozadje = posnetekDoma {
                dodajZabris(slika: ozadje, trajanje: 0.2)
            }
            vstop = .privzeto
        }
    }

    /// Doda zabris (slika pojema iz neprosojne v prosojno) in ga po trajanju odstrani.
    private func dodajZabris(slika: UIImage, trajanje: Double) {
        let id = UUID()
        zabrisi[id] = (slika, trajanje)
        DispatchQueue.main.asyncAfter(deadline: .now() + trajanje) { zabrisi.removeValue(forKey: id) }
    }

    /// Navaden zabris (Map, ali Reduce Motion): zavihek preklopimo takoj, plast nad njim pojema.
    private func zabris(na nov: Int, trajanje: Double) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else { zavihek = nov; return }
        zavihek = nov
        dodajZabris(slika: surov, trajanje: trajanje)
    }

    /// Ozadje zavihka Search/Profile (zamegljen zamrznjen Home).
    private func osveziOzadjeZavihka() {
        // Sinhrono, kot doslej: posnetek je v cetrtini locljivosti (~100 x 210 pikslov), zameglitev
        // traja nekaj milisekund. Ozadna nit bi tu prinesla samo tveganje (Sendable, vrstni red
        // nastavitve ozadja med animacijo), ne pa opazne hitrosti.
        posnetekDoma = UIApplication.shared.posnetekZaslona()
    }

    var body: some View {
        ZStack {
            TabView(selection: izbira) {
                HomeView(odpriIskanje: { preklopi(na: 1) }, odpriProfil: { preklopi(na: 3) },
                         okvirIzvorov: $okvirIzvorov)
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
            // Stanje rasti/krcenja vsebine (glej VstopZavihka) — privzeto nevtralno, zato brez
            // ucinka na Home/Map, ki `.outlyOzadje()` ne kliceta.
            .environment(\.vstopZavihka, vstop)

            // Prekrivne plasti zabrisa — nad TabView, dotiki gredo skozi.
            ForEach(Array(zabrisi.keys), id: \.self) { id in
                if let z = zabrisi[id] {
                    ZabrisSloj(slika: z.slika, velikostOkna: velikostOkna, trajanje: z.trajanje)
                }
            }
        }
        // Priljubljeni s streznika ob prijavi (in ob menjavi seje).
        .task(id: session.token) { await favorites.load(token: session.token) }
        // Po preklopu jezika (koren dobi nov .id) se vrni na zavihek, kjer je bil preklop.
        .onAppear {
            if let z = jezik.zavihekPoPreklopu { zavihek = z; jezik.zavihekPoPreklopu = nil }
        }
    }
}
