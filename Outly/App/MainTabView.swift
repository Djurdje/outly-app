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
/// 40 % na 100 % velikosti, hkrati se pojavi (opacity 0->1) v ~0,3 s; brez blura na zivi vsebini (25. 9.)
/// (ease-out) — to nosi `VstopZavihka` v okolju (Core/Themes/Ozadje.swift), ki jo `.outlyOzadje()`
/// prebere in uporabi na SVOJI vsebini zaslona. Poleg tega domaci zaslon pod njo v ~0,3 s zbledi
/// v ze zamegljen posnetek (`ZabrisSloj` nad TabViewom, oster posnetek pojema) — to je "Home se
/// zamegli" del. Nazaj (Profile/Search -> Home) zavihek preklopimo TAKOJ, cez zivi Home pa se
/// skrci zamrznjen posnetek zaslona, ki ga zapuscamo (KrcenjeSloj), pod njim pa zbledi zamegljen
/// posnetek Home ("domaci zaslon se izostri").
///
/// 29. 9. 2026 ("ko hitro menjam zavihke, aplikacija steka / zmrzne s crnim zaslonom"): prej je
/// prehod nazaj na Home cakal na konec animacije (completion), sele nato preklopil zavihek. Dotik
/// med animacijo je bil prezrt, sistemska vrstica in SwiftUI sta se razhajala, koncni preklop pa je
/// uporabnika vrgel na Home, cetudi je ze izbral drug zavihek; vsebina Search/Profile je lahko
/// ostala na prosojnosti 0 (crn zaslon). Zdaj: zavihek se preklopi vedno takoj, vsak nov dotik
/// pocisti prejsnji prehod, dotik med tekocim prehodom pa preklopi brez animacije.
/// Search <-> Profile je NAVADEN preklop, brez animacije (Martin izrecno). Karkoli <-> Map in
/// Reduce Motion ostaneta navaden zabris (ZabrisSloj), kot prej.
struct MainTabView: View {
    // Izbran zavihek: domaci zaslon ("Where to?") preklopi na iskanje, avatar na profil.
    @State private var zavihek = 0
    @State private var posnetekDoma: UIImage?
    /// Okvirja avatarja in polja "Where to?" (HomeView ju zapise). Referenca brez opazovanja —
    /// glej IzvoriRazkritja: drsenje Home ne sme vsak frame znova izrisati tega pogleda.
    @State private var izvori = IzvoriRazkritja()
    /// Trenutno stanje rasti vsebine zavihka (glej VstopZavihka v Ozadje.swift) — v okolju,
    /// zato ga prebere `.outlyOzadje()` katerekoli globoke vsebine (tudi potisnjenih zaslonov).
    @State private var vstop = VstopZavihka.privzeto
    /// Prekrivne plasti cez cel zaslon (zabris, krcenje), v vrstnem redu risanja (zadnja je zgoraj).
    @State private var plasti: [PrekrivnaPlast] = []
    /// Stevec prehodov: zamaknjeni koraki prehoda (zacetek animacije, odstranitev plasti) se
    /// izvedejo samo, ce se je medtem ni zacel nov prehod.
    @State private var generacija = 0
    /// Do kdaj tece zadnji prehod — dotik pred tem preklopi takoj, brez animacije.
    @State private var prehodDo = Date.distantPast

    @EnvironmentObject private var jezik: Jezik
    @Environment(\.accessibilityReduceMotion) private var zmanjsanoGibanje

    /// Preklop zavihka: ce zapuscamo domaci zaslon, ga najprej posnamemo.
    private var izbira: Binding<Int> {
        Binding(get: { zavihek }, set: { nov in preklopi(na: nov) })
    }

    // MARK: - Sidra (avatar / Where to?)

    /// Velikost okna v tockah — isti koordinatni sistem kot izvori (global) in posnetki.
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

    private var izvorProfil: CGRect { veljavenIzvor(izvori.avatar) ?? privzetIzvorProfil }
    private var izvorIskanje: CGRect { veljavenIzvor(izvori.whereTo) ?? privzetIzvorIskanje }

    /// Sidro skaliranja (UnitPoint, 0...1) iz okenskega okvirja — sredisce izvora glede na
    /// dano velikost (okno ali izrez nad spodnjo vrstico).
    private func sidroIz(_ izvor: CGRect, v velikost: CGSize) -> UnitPoint {
        guard velikost.width > 0, velikost.height > 0 else { return .topLeading }
        return UnitPoint(x: min(max(izvor.midX / velikost.width, 0), 1),
                         y: min(max(izvor.midY / velikost.height, 0), 1))
    }

    // MARK: - Preklop

    private func preklopi(na nov: Int) {
        guard nov != zavihek else { return }  // dvakratni dotik iste ikone: sistemsko ze vrne na koren, sicer nic
        let od = zavihek
        // Dotik med tekocim prehodom (hitro preklapljanje): brez animacije in brez novega posnetka.
        let hiter = Date() < prehodDo
        pocistiPrehod()

        // Ozadje za Search/Profile (zamegljen posnetek Home) osvezimo, ko zapuscamo Home —
        // pri rasti ga odpriIzHome izpelje iz istega (enega) posnetka.
        let rastIzHome = !zmanjsanoGibanje && !hiter && od == 0 && (nov == 1 || nov == 3)
        if od == 0 && !rastIzHome { osveziOzadjeZavihka() }

        if hiter {
            zavihek = nov
            return
        }

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

    /// Prekine prejsnji prehod: odstrani plasti in vstop vrne na nevtralno BREZ animacije, da
    /// vsebina zavihka nikoli ne obstane pomanjsana ali prosojna (crn zaslon).
    private func pocistiPrehod() {
        generacija += 1
        prehodDo = .distantPast
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            plasti.removeAll()
            vstop = .privzeto
        }
    }

    /// Home -> Search/Profile: vsebina cilja zraste iz sidra (40 % -> 100 %,
    /// 0,3 s ease-out, brez blura); zavihek preklopimo TAKOJ (POD plastjo je ze ziv cilj), plast
    /// nad njim (oster posnetek Home) v istem casu pojema in odkriva ze zamegljen posnetekDoma
    /// pod seboj — to je "Home se zamegli".
    private func odpriIzHome(na nov: Int, izvor: CGRect) {
        let sidro = sidroIz(izvor, v: velikostOkna)
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else {
            zavihek = nov
            return
        }
        // EN zajem hierarhije; zamegljeno ozadje izpeljemo iz istega posnetka s pomanjsavo na cetrtino.
        let majhen = OzadnjaZameglitev.pomanjsaj(surov, naMerilo: 0.25)
        posnetekDoma = OzadnjaZameglitev.zamegli(majhen) ?? majhen
        // Prosojnost zive vsebine ostane 1 (29. 9. 2026): animirana prosojnost cez cel ziv zaslon je
        // najdrazji del (vsak frame loceno sestavljanje cele plasti). Pojavljanje nosi oster posnetek
        // Home, ki nad vsem pojema (ZabrisSloj) — videz ostane "kot Revolut", dela je manj.
        // (Poskusi #34-#38 z animacijo posnetka namesto zive vsebine so spremenili videz — vrnjeno.)
        vstop = VstopZavihka(skala: 0.4, prosojnost: 1, zameglitev: 0, sidro: sidro)
        zavihek = nov
        dodajPlast(PrekrivnaPlast(slika: surov, vrsta: .zabris, trajanje: 0.3))
        prehodDo = Date().addingTimeInterval(0.3)
        // Animacija se zacne EN frame po preklopu (v tem framu SwiftUI postavi ciljni zaslon).
        // Ce je uporabnik vmes ze preklopil drugam, je generacija drugacna in ne naredimo nic.
        let gen = generacija
        DispatchQueue.main.async {
            guard gen == generacija else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                vstop = VstopZavihka(skala: 1, prosojnost: 1, zameglitev: 0, sidro: sidro)
            }
        }
    }

    /// Search/Profile -> Home: zavihek preklopimo TAKOJ. Nad zivim Home se skrci zamrznjen posnetek
    /// zaslona, ki ga zapuscamo (brez spodnje vrstice, 100 % -> 40 %, 0,25 s), pod njim pa zbledi
    /// zamegljen posnetek Home (0,35 s) — "domaci zaslon se izostri".
    private func zapriVHome(odIzvora izvor: CGRect) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0),
              let izrez = izrezNadVrstico(surov) else {
            zavihek = 0
            return
        }
        let sidro = sidroIz(izvor, v: izrez.size)
        zavihek = 0
        if let ozadje = posnetekDoma {
            dodajPlast(PrekrivnaPlast(slika: ozadje, vrsta: .zabris, trajanje: 0.35))
        }
        dodajPlast(PrekrivnaPlast(slika: izrez, vrsta: .krcenje(sidro: sidro), trajanje: 0.25))
        prehodDo = Date().addingTimeInterval(0.3)
    }

    /// Posnetek brez spodnje vrstice zavihkov — ta ostane na mestu, krci se samo vsebina.
    private func izrezNadVrstico(_ slika: UIImage) -> UIImage? {
        let okno = UIApplication.shared.kljucnoOkno
        let visinaOkna = slika.size.height
        let vrh = okno?.spodnjaVrsticaVrh ?? (visinaOkna - (okno?.safeAreaInsets.bottom ?? 0) - 49)
        let visina = min(max(vrh, 1), visinaOkna)
        guard let cg = slika.cgImage else { return nil }
        let px = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: (visina * slika.scale).rounded(.down))
        guard let obrezan = cg.cropping(to: px) else { return nil }
        return UIImage(cgImage: obrezan, scale: slika.scale, orientation: .up)
    }

    /// Doda plast in jo po trajanju odstrani (po id-ju; ce jo je nov prehod ze pocistil, ni nic za odstraniti).
    private func dodajPlast(_ plast: PrekrivnaPlast) {
        plasti.append(plast)
        let id = plast.id
        DispatchQueue.main.asyncAfter(deadline: .now() + plast.trajanje + 0.05) {
            plasti.removeAll { $0.id == id }
        }
    }

    /// Navaden zabris (Map, ali Reduce Motion): zavihek preklopimo takoj, plast nad njim pojema.
    private func zabris(na nov: Int, trajanje: Double) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else { zavihek = nov; return }
        zavihek = nov
        dodajPlast(PrekrivnaPlast(slika: surov, vrsta: .zabris, trajanje: trajanje))
        prehodDo = Date().addingTimeInterval(trajanje)
    }

    /// Ozadje zavihka Search/Profile (zamegljen zamrznjen Home).
    private func osveziOzadjeZavihka() {
        // Sinhrono: posnetek je v cetrtini locljivosti, zameglitev traja nekaj milisekund.
        posnetekDoma = UIApplication.shared.posnetekZaslona()
    }

    var body: some View {
        ZStack {
            TabView(selection: izbira) {
                HomeView(odpriIskanje: { preklopi(na: 1) }, odpriProfil: { preklopi(na: 3) },
                         izvori: izvori)
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
            // Stanje rasti vsebine (glej VstopZavihka) — privzeto nevtralno, zato brez
            // ucinka na Home/Map, ki `.outlyOzadje()` ne kliceta.
            .environment(\.vstopZavihka, vstop)

            // Prekrivne plasti — nad TabView, dotiki gredo skozi.
            ForEach(plasti) { plast in
                switch plast.vrsta {
                case .zabris:
                    ZabrisSloj(slika: plast.slika, velikostOkna: velikostOkna, trajanje: plast.trajanje)
                case .krcenje(let sidro):
                    KrcenjeSloj(slika: plast.slika, velikost: plast.slika.size, sidro: sidro, trajanje: plast.trajanje)
                }
            }
        }
        // Priljubljeni s streznika ob prijavi (in ob menjavi seje). V lastnem pogledu, da
        // objave SessionStore/FavoritesStore (npr. /me ob vsakem prikazu Home) ne izrisejo
        // znova celega TabViewa.
        .background(NalaganjePriljubljenih())
        // Dotik na potisno obvestilo (APNs): prevzame cakajoci cilj in odpre ustrezen zaslon (glej PushPrehodView.swift).
        .background(PushPrehod())
        // Po preklopu jezika (koren dobi nov .id) se vrni na zavihek, kjer je bil preklop.
        .onAppear {
            if let z = jezik.zavihekPoPreklopu { zavihek = z; jezik.zavihekPoPreklopu = nil }
        }
    }
}

/// Ena prekrivna plast prehoda med zavihki.
private struct PrekrivnaPlast: Identifiable {
    enum Vrsta {
        /// Cez cel zaslon, pojema (ZabrisSloj).
        case zabris
        /// Izrez nad spodnjo vrstico, krci se proti sidru in pojema (KrcenjeSloj).
        case krcenje(sidro: UnitPoint)
    }

    let id = UUID()
    let slika: UIImage
    let vrsta: Vrsta
    let trajanje: Double
}

/// Nalaganje priljubljenih ob prijavi / menjavi seje — edini del MainTabView, ki je rabil sejo.
private struct NalaganjePriljubljenih: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .task(id: session.token) { await favorites.load(token: session.token) }
    }
}

private extension UIWindow {
    /// Zgornji rob sistemske spodnje vrstice zavihkov v okenskih koordinatah (nil, ce je ni).
    var spodnjaVrsticaVrh: CGFloat? {
        func najdi(_ v: UIView) -> UITabBar? {
            if let t = v as? UITabBar, !t.isHidden, t.alpha > 0.01 { return t }
            for p in v.subviews { if let t = najdi(p) { return t } }
            return nil
        }
        guard let vrstica = najdi(self) else { return nil }
        return vrstica.convert(vrstica.bounds, to: self).minY
    }
}
