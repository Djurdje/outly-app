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
    /// Zadnji posnetek vsebine Search (1) / Profile (3), narejen ob odhodu z zavihka na Home.
    /// Home -> Search/Profile ga uporabi TAKOJ (29. 9. 2026, Martinov posnetek zaslona: pred rastjo
    /// je bilo ~200 ms zamrznjenega Home — cakanje na postavitev cilja in njegov zajem). Ob vsakem
    /// drugem odhodu z zavihka se zavrze, da ne bi rasel star zaslon.
    /// Poleg posnetka hranimo zamegljen Home, ki je bil takrat ozadje zavihka: posnetek ga vsebuje, zato mora
    /// biti tudi ozadje pod rastjo (in zivo ozadje po njej) isto — sicer raste viden pravokotnik z drugacnim
    /// ozadjem namesto vsebine (Martin, 29. 9. po #35: "ni vec tako kot prej, Revolut fora").
    @State private var posnetkiZavihkov: [Int: (slika: UIImage, ozadje: UIImage?)] = [:]

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
        // Posnetek zavihka velja samo, ce ga je ravnokar naredil zapriVHome (glej posnetkiZavihkov).
        if od == 1 || od == 3 { posnetkiZavihkov[od] = nil }
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
            zapriVHome(od: 1, odIzvora: izvorIskanje)
        case (3, 0):
            zapriVHome(od: 3, odIzvora: izvorProfil)
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

    /// Home -> Search/Profile (29. 9. 2026: prej je rasla ZIVA vsebina cilja — vsak frame se je
    /// na novo izrisal cel zaslon s poljem za iskanje, seznamom in slikami; na telefonu je to bilo
    /// "kot 15 fps"). Zdaj animiramo samo SLIKE, kot pri poti nazaj:
    /// 1. ob dotiku: oster posnetek Home cez cel zaslon kot mirujoc pokrov, zavihek preklopimo;
    /// 2. ~2 frama kasneje (cilj je postavljen pod pokrovom): posnamemo samo vsebino ciljnega
    ///    zavihka (brez spodnje vrstice) in zamenjamo pokrov s tremi plastmi:
    ///    zamegljen Home (mirujoce ozadje, isto kot ozadje cilja) -> oster Home, ki pojema ->
    ///    posnetek cilja, ki raste iz sidra (40 % -> 100 %, opacity 0 -> 1, 0,3 s ease-out);
    /// 3. po koncu plasti odstranimo — pod njimi je ze ziv, enak zaslon.
    private func odpriIzHome(na nov: Int, izvor: CGRect) {
        guard let surov = UIApplication.shared.surovPosnetek(merilo: 1.0) else {
            zavihek = nov
            return
        }
        // Hitra pot: posnetek cilja ze imamo (zadnji odhod s tega zavihka) — rast se zacne takoj.
        // Ozadje ostane TISTO, ki je v posnetku (glej posnetkiZavihkov), zato tu ne zameglimo znova.
        if let shranjen = posnetkiZavihkov[nov], let ozadje = shranjen.ozadje {
            let cilj = shranjen.slika
            posnetekDoma = ozadje
            zavihek = nov
            let sidro = sidroIz(izvor, v: cilj.size)
            dodajPlast(PrekrivnaPlast(slika: ozadje, vrsta: .ozadje(velikost: cilj.size), trajanje: 0.3))
            dodajPlast(PrekrivnaPlast(slika: surov, vrsta: .zabris, trajanje: 0.3))
            dodajPlast(PrekrivnaPlast(slika: cilj, vrsta: .rast(sidro: sidro), trajanje: 0.3))
            prehodDo = Date().addingTimeInterval(0.3)
            return
        }

        // EN zajem hierarhije; zamegljeno ozadje izpeljemo iz istega posnetka s pomanjsavo na cetrtino.
        let majhen = OzadnjaZameglitev.pomanjsaj(surov, naMerilo: 0.25)
        let zamegljen = OzadnjaZameglitev.zamegli(majhen) ?? majhen
        posnetekDoma = zamegljen

        // Prvic (posnetka se ni): pokrov, pocakamo, da se cilj postavi, in ga posnamemo.
        zavihek = nov
        dodajPlast(PrekrivnaPlast(slika: surov, vrsta: .mirujoca, trajanje: 1.0))
        prehodDo = Date().addingTimeInterval(0.4)

        let gen = generacija
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            guard gen == generacija else { return }
            let cilj = UIApplication.shared.kljucnoOkno?.posnetekIzbranegaZavihka()
            // Pokrov (mirujoc Home) zamenjamo z animacijo v ISTEM izrisu — brez utripa.
            plasti.removeAll()
            guard let cilj else {
                // Posnetka ni (npr. drugacna hierarhija): samo zbledi Home, kot navaden zabris.
                dodajPlast(PrekrivnaPlast(slika: surov, vrsta: .zabris, trajanje: 0.25))
                return
            }
            let sidro = sidroIz(izvor, v: cilj.size)
            dodajPlast(PrekrivnaPlast(slika: zamegljen, vrsta: .ozadje(velikost: cilj.size), trajanje: 0.3))
            dodajPlast(PrekrivnaPlast(slika: surov, vrsta: .zabris, trajanje: 0.3))
            dodajPlast(PrekrivnaPlast(slika: cilj, vrsta: .rast(sidro: sidro), trajanje: 0.3))
            prehodDo = Date().addingTimeInterval(0.3)
        }
    }

    /// Search/Profile -> Home: zavihek preklopimo TAKOJ. Nad zivim Home se skrci zamrznjen posnetek
    /// zaslona, ki ga zapuscamo (brez spodnje vrstice, 100 % -> 40 %, 0,25 s), pod njim pa zbledi
    /// zamegljen posnetek Home (0,35 s) — "domaci zaslon se izostri".
    private func zapriVHome(od: Int, odIzvora izvor: CGRect) {
        // Posnetek samo vsebine zavihka (brez vrstice, merilo 2, brez prisilnega izrisa — zaslon je
        // ze narisan); isti posnetek hranimo za naslednji Home -> ta zavihek.
        let zavihka = UIApplication.shared.kljucnoOkno?.posnetekIzbranegaZavihka(poOsvezitvi: false)
        guard let izrez = zavihka
                ?? UIApplication.shared.surovPosnetek(merilo: 1.0).flatMap({ izrezNadVrstico($0) }) else {
            zavihek = 0
            return
        }
        if let zavihka { posnetkiZavihkov[od] = (zavihka, posnetekDoma) }
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
                case .rast(let sidro):
                    KrcenjeSloj(slika: plast.slika, velikost: plast.slika.size, sidro: sidro, trajanje: plast.trajanje,
                                raste: true)
                case .mirujoca:
                    Image(uiImage: plast.slika)
                        .resizable()
                        .frame(width: velikostOkna.width, height: velikostOkna.height)
                        .ignoresSafeArea(.all)
                        .allowsHitTesting(false)
                case .ozadje(let velikost):
                    HomeSnapshotBackground(slika: plast.slika)
                        .frame(width: velikost.width, height: velikost.height)
                        .clipped()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .ignoresSafeArea(.all)
                        .allowsHitTesting(false)
                }
            }
        }
        // Priljubljeni s streznika ob prijavi (in ob menjavi seje). V lastnem pogledu, da
        // objave SessionStore/FavoritesStore (npr. /me ob vsakem prikazu Home) ne izrisejo
        // znova celega TabViewa.
        .background(NalaganjePriljubljenih())
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
        /// Posnetek ciljnega zavihka (nad spodnjo vrstico), raste iz sidra in se pojavi.
        case rast(sidro: UnitPoint)
        /// Mirujoca slika cez cel zaslon (pokrov, dokler se cilj ne postavi).
        case mirujoca
        /// Mirujoce zamegljeno ozadje (kot ozadje Search/Profile), velikost izreza nad vrstico.
        case ozadje(velikost: CGSize)
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
    /// Posnetek vsebine izbranega zavihka BREZ spodnje vrstice in brez prekrivnih plasti (te so
    /// SwiftUI sestra TabViewa, ne del pogleda zavihka). Merilo 2 — dovolj ostro za 0,3 s animacije.
    func posnetekIzbranegaZavihka(poOsvezitvi: Bool = true) -> UIImage? {
        func najdi(_ vc: UIViewController?) -> UITabBarController? {
            guard let vc else { return nil }
            if let t = vc as? UITabBarController { return t }
            for otrok in vc.children { if let t = najdi(otrok) { return t } }
            return najdi(vc.presentedViewController)
        }
        guard let pogled = najdi(rootViewController)?.selectedViewController?.view,
              pogled.bounds.width > 1, pogled.bounds.height > 1 else { return nil }
        let okvir = pogled.convert(pogled.bounds, to: self)
        let visina = min(spodnjaVrsticaVrh ?? okvir.maxY, okvir.maxY) - okvir.minY
        guard okvir.minY < 1, visina > 1 else { return nil }  // pricakujemo zavihek od vrha okna
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(traitCollection.displayScale, 2)
        format.opaque = true
        let meje = CGRect(x: 0, y: 0, width: pogled.bounds.width, height: visina)
        return UIGraphicsImageRenderer(bounds: meje, format: format).image { _ in
            pogled.drawHierarchy(in: pogled.bounds, afterScreenUpdates: poOsvezitvi)
        }
    }

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
