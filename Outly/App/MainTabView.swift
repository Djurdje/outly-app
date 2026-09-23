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
/// "Krozno razkritje" (Martin, 23. 9.): nad TabView lezi prekrivna plast (RazkritjeSloj/ZabrisSloj
/// iz RazkritjeZavihka.swift), ki ob preklopu Home<->Search/Profile rise krog (avatar) ali
/// zaobljen pravokotnik (polje Where to?), ki zraste/skrci cez cel zaslon; Search<->Profile je
/// en gib cez oba; karkoli z Map je navaden zabris. Sistemski TabView sam preklopi takoj (brez
/// svoje animacije), plast nad njim je tista, ki "pripoveduje" prehod.
struct MainTabView: View {
    // Izbran zavihek: domaci zaslon ("Where to?") preklopi na iskanje, avatar na profil.
    @State private var zavihek = 0
    @State private var posnetekDoma: UIImage?
    /// Okvirja avatarja in polja "Where to?" (HomeView jih izmeri in poda navzgor).
    @State private var okvirIzvorov = IzvoriRazkritja()
    /// Plasti kroznega/pravokotnega razkritja, trenutno na zaslonu (obicajno 0 ali 1, med
    /// Search<->Profile za hip 0 potem 1 — glej prehodSearchProfil).
    @State private var plasti: [PlastPodatki] = []
    /// Zabris (Map, ali Reduce Motion namesto oblik) — samostojen, ker nima oblike/izvora.
    @State private var zabrisi: [UUID: (slika: UIImage, trajanje: Double)] = [:]

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var jezik: Jezik
    @Environment(\.accessibilityReduceMotion) private var zmanjsanoGibanje

    /// Preklop zavihka: ce zapuscamo domaci zaslon, ga najprej posnamemo.
    private var izbira: Binding<Int> {
        Binding(get: { zavihek }, set: { nov in preklopi(na: nov) })
    }

    // MARK: - Odlocitev vrste prehoda

    /// Velikost okna v tockah — isti koordinatni sistem kot okvirIzvorov (global) in posnetki.
    private var velikostOkna: CGSize {
        UIApplication.shared.kljucnoOkno?.bounds.size ?? UIScreen.main.bounds.size
    }

    private var oknoBounds: CGRect {
        CGRect(origin: .zero, size: velikostOkna)
    }

    /// Privzeti izvor za Profil, ce avatar ni (vec) viden (odrsan) — krog pri levem zgornjem robu.
    private var privzetIzvorProfil: CGRect {
        CGRect(x: 16, y: 54, width: 36, height: 36)
    }

    /// Privzeti izvor za Search, ce polje ni (vec) vidno — pravokotnik na sredini vrha.
    private var privzetIzvorIskanje: CGRect {
        let sirina = min(velikostOkna.width - 32, 320)
        return CGRect(x: (velikostOkna.width - sirina) / 2, y: 92, width: sirina, height: 48)
    }

    /// Okvir je "veljaven" (uporaben za izvor), ce ga poznamo IN je njegovo sredisce znotraj
    /// vidnega okna — sicer (odrsan, ali se ne izmerjen) uporabimo privzeti izvor pri robu.
    private func veljavenIzvor(_ r: CGRect?) -> CGRect? {
        guard let r, r.width > 1, r.height > 1 else { return nil }
        let sredisce = CGPoint(x: r.midX, y: r.midY)
        return oknoBounds.contains(sredisce) ? r : nil
    }

    private var izvorProfil: CGRect { veljavenIzvor(okvirIzvorov.avatar) ?? privzetIzvorProfil }
    private var izvorIskanje: CGRect { veljavenIzvor(okvirIzvorov.whereTo) ?? privzetIzvorIskanje }

    /// Skala, pri kateri oblika (krog ali pravokotnik) s sredino v izvoru pokrije cel zaslon,
    /// vkljucno z najbolj oddaljenim vogalom (+5 % zaloge).
    private func skalaZaPokritje(izvor: CGRect, krog: Bool) -> CGFloat {
        let okno = oknoBounds
        let sredisce = CGPoint(x: izvor.midX, y: izvor.midY)
        if krog {
            let vogali = [
                CGPoint(x: okno.minX, y: okno.minY), CGPoint(x: okno.maxX, y: okno.minY),
                CGPoint(x: okno.minX, y: okno.maxY), CGPoint(x: okno.maxX, y: okno.maxY)
            ]
            let najdaljsi = vogali.map { hypot($0.x - sredisce.x, $0.y - sredisce.y) }.max() ?? 0
            let polmer = min(izvor.width, izvor.height) / 2
            guard polmer > 0 else { return 1 }
            return (najdaljsi * 1.05) / polmer
        } else {
            let maxDX = max(sredisce.x - okno.minX, okno.maxX - sredisce.x)
            let maxDY = max(sredisce.y - okno.minY, okno.maxY - sredisce.y)
            let skalaX = izvor.width > 0 ? (maxDX * 2 * 1.05) / izvor.width : 1
            let skalaY = izvor.height > 0 ? (maxDY * 2 * 1.05) / izvor.height : 1
            return max(skalaX, skalaY, 1)
        }
    }

    private func preklopi(na nov: Int) {
        guard nov != zavihek else { return }  // dvakratni dotik iste ikone: sistemsko ze vrne na koren, sicer nic
        let od = zavihek

        // Ozadje za Search/Profile (zamegljen posnetek Home) osvezimo vedno, ko zapuscamo Home —
        // enako kot prej (glej osveziOzadjeZavihka).
        if od == 0 && nov != 0 { osveziOzadjeZavihka() }

        if zmanjsanoGibanje {
            // Reduce Motion: brez oblik, samo zabris 0,2 s (velja za VSAK prehod, tudi Map).
            zabris(na: nov, trajanje: 0.2)
            return
        }

        switch (od, nov) {
        case (2, _), (_, 2):
            // Karkoli <-> Map: navaden zabris, Map nima izvora.
            zabris(na: nov, trajanje: 0.25)
        case (0, 1):
            rastIzHome(na: nov, krog: false)
        case (0, 3):
            rastIzHome(na: nov, krog: true)
        case (1, 0):
            skrciVHome(krog: false)
        case (3, 0):
            skrciVHome(krog: true)
        case (1, 3):
            prehodSearchProfil(naProfil: true)
        case (3, 1):
            prehodSearchProfil(naProfil: false)
        default:
            zavihek = nov
        }
    }

    // MARK: - Prehodi z obliko

    /// Home -> Search/Profile: oblika zraste iz avatarja/polja in pokrije zaslon; POD njo je ze
    /// ziv cilj (zavihek preklopimo TAKOJ, plast nad njim samo "odpre luknjo").
    private func rastIzHome(na nov: Int, krog: Bool) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else { zavihek = nov; return }
        let izvor = krog ? izvorProfil : izvorIskanje
        let koncna = skalaZaPokritje(izvor: izvor, krog: krog)
        zavihek = nov
        dodajPlast(PlastPodatki(slika: surov, izvor: izvor, krog: krog,
                                 zacetnaSkala: 1, koncnaSkala: koncna, obratno: false, trajanje: 0.45))
    }

    /// Search/Profile -> Home: oblika (ki kaze zamrznjen Search/Profile) se skrci nazaj v
    /// avatar/polje; POD njo je ze ziv Home (zavihek preklopimo TAKOJ na 0).
    private func skrciVHome(krog: Bool) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else { zavihek = 0; return }
        let izvor = krog ? izvorProfil : izvorIskanje
        let zacetna = skalaZaPokritje(izvor: izvor, krog: krog)
        zavihek = 0
        dodajPlast(PlastPodatki(slika: surov, izvor: izvor, krog: krog,
                                 zacetnaSkala: zacetna, koncnaSkala: 1, obratno: true, trajanje: 0.35))
    }

    /// Search <-> Profile: en gib (~0,4 s), vmes za hip viden Home — izvedeno zaporedno
    /// (skrcitev trenutnega v svojo obliko 0,2 s, nato rast ciljnega iz svoje oblike 0,25 s),
    /// kar navodilo izrecno dopusca kot sprejemljivo.
    private func prehodSearchProfil(naProfil: Bool) {
        guard let surovOd = UIApplication.shared.surovPosnetek(merilo: 1.0) else {
            zavihek = naProfil ? 3 : 1
            return
        }
        // "Od": ce gremo NA profil, smo bili na Searchu (pravokotnik); sicer smo bili na Profilu (krog).
        let odKrog = !naProfil
        let izvorOd = odKrog ? izvorProfil : izvorIskanje
        let zacetnaOd = skalaZaPokritje(izvor: izvorOd, krog: odKrog)

        zavihek = 0  // za hip Home, kot v skrciVHome
        dodajPlast(PlastPodatki(slika: surovOd, izvor: izvorOd, krog: odKrog,
                                 zacetnaSkala: zacetnaOd, koncnaSkala: 1, obratno: true, trajanje: 0.2)) {
            let ciljZavihek = naProfil ? 3 : 1
            guard let surovHome = UIApplication.shared.surovPosnetek(merilo: 1.0) else {
                zavihek = ciljZavihek
                return
            }
            let naKrog = naProfil
            let izvorNa = naKrog ? izvorProfil : izvorIskanje
            let koncnaNa = skalaZaPokritje(izvor: izvorNa, krog: naKrog)
            zavihek = ciljZavihek
            dodajPlast(PlastPodatki(slika: surovHome, izvor: izvorNa, krog: naKrog,
                                     zacetnaSkala: 1, koncnaSkala: koncnaNa, obratno: false, trajanje: 0.25))
        }
    }

    /// Doda plast, jo po trajanju odstrani in (ce podano) sprozi naslednji korak — uporablja
    /// Search<->Profile za zaporedje dveh plasti v enem gibu.
    private func dodajPlast(_ p: PlastPodatki, poKoncu: (() -> Void)? = nil) {
        plasti.append(p)
        let id = p.id
        DispatchQueue.main.asyncAfter(deadline: .now() + p.trajanje) {
            plasti.removeAll { $0.id == id }
            poKoncu?()
        }
    }

    /// Navaden zabris (Map, ali Reduce Motion): zavihek preklopimo takoj, plast nad njim pojema.
    private func zabris(na nov: Int, trajanje: Double) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else { zavihek = nov; return }
        zavihek = nov
        let id = UUID()
        zabrisi[id] = (surov, trajanje)
        DispatchQueue.main.asyncAfter(deadline: .now() + trajanje) { zabrisi.removeValue(forKey: id) }
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

            // Prekrivna plast kroznega/pravokotnega razkritja — nad TabView, dotiki gredo skozi.
            ForEach(plasti) { p in
                RazkritjeSloj(podatki: p, velikostOkna: velikostOkna)
            }
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
