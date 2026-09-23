import SwiftUI

/// "Krozno razkritje" ob preklopu zavihkov (Martin, 23. 9. 2026): namesto navadnega preklopa
/// TabView Profile "zraste" iz kroga avatarja, Search pa iz pravokotnika polja "Where to?" —
/// in obratno ob vrnitvi na Home. Ta datoteka nosi skupne tipe (izvorne okvirje, oblike plasti
/// in samo risano plast); zaporedje prehodov (kdaj kateri layer) je v MainTabView, ker samo ta
/// ve, kateri zavihek zapuscamo in katerega odpiramo.

/// Okvirja avatarja in polja "Where to?" v HomeView, v GLOBALNIH (okenskih) koordinatah —
/// isti koordinatni sistem kot posnetek zaslona (surovPosnetek), da se oblika ujema s sliko.
/// HomeView ju izmeri z GeometryReader/PreferenceKey in poda navzgor v MainTabView.
struct IzvoriRazkritja: Equatable {
    var avatar: CGRect?
    var whereTo: CGRect?
}

/// PreferenceKey za okvir avatarja (glava HomeView).
struct AvatarOkvirKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let n = nextValue() { value = n }
    }
}

/// PreferenceKey za okvir polja "Where to?" (HomeView).
struct WhereToOkvirKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let n = nextValue() { value = n }
    }
}

/// En sloj razkritja: kaksna oblika (krog/pravokotnik), kje (izvor), od kje do kje se skalira,
/// in ali je maska "obratna" (vidna je SAMO oblika — uporabi se pri krcitvi, ko oblika kaze
/// cilj, ki izginja) ali "navadna" (vse RAZEN oblike — uporabi se pri rasti, ko luknja siri
/// pogled na ziv zaslon pod zamrznjeno sliko).
struct PlastPodatki: Identifiable {
    let id = UUID()
    /// Zamrznjena slika, ki jo ta plast kaze (oster posnetek, surovPosnetek merilo 1.0).
    let slika: UIImage
    /// Izvorni okvir oblike, v okenskih koordinatah.
    let izvor: CGRect
    /// true = krog (avatar), false = zaobljen pravokotnik (polje Where to?).
    let krog: Bool
    let zacetnaSkala: CGFloat
    let koncnaSkala: CGFloat
    /// true = vidna je samo oblika (krcitev), false = vidno je vse razen oblike (rast).
    let obratno: Bool
    let trajanje: Double
}

/// Sama risana plast enega PlastPodatki — glej PlastPodatki za razlago obratno/krog.
/// `allowsHitTesting(false)`: plast je samo vizualna, dotiki gredo skozi njo na spodnji TabView.
struct RazkritjeSloj: View {
    let podatki: PlastPodatki
    let velikostOkna: CGSize

    @State private var skala: CGFloat

    init(podatki: PlastPodatki, velikostOkna: CGSize) {
        self.podatki = podatki
        self.velikostOkna = velikostOkna
        _skala = State(initialValue: podatki.zacetnaSkala)
    }

    /// Radij oblike: krog = polovica visine izvora (kvadraten okvir avatarja), pravokotnik = 14
    /// (isti radij kot polje Where to?, HomeCards.swift).
    private var radij: CGFloat { podatki.krog ? podatki.izvor.height / 2 : 14 }

    /// Oblika, POLNJENA (crna — barva ni pomembna, za masko/destinationOut steje samo alfa),
    /// da je zanesljivo neprosojna ne glede na privzet foregroundStyle.
    private var oblika: some View {
        RoundedRectangle(cornerRadius: radij, style: .continuous)
            .fill(Color.black)
            .frame(width: max(podatki.izvor.width, 1), height: max(podatki.izvor.height, 1))
            .scaleEffect(skala)
            .position(x: podatki.izvor.midX, y: podatki.izvor.midY)
    }

    var body: some View {
        Group {
            if podatki.obratno {
                // Krcitev: vidna je SAMO oblika (kaze kar izginja), zunaj nje je plast
                // popolnoma prosojna, zato je takoj viden ziv zaslon pod njo (Home).
                Image(uiImage: podatki.slika)
                    .resizable()
                    .scaledToFill()
                    .frame(width: velikostOkna.width, height: velikostOkna.height)
                    .mask(oblika)
            } else {
                // Rast: vidno je VSE RAZEN oblike (luknja) — destinationOut na SAMI sliki izreze
                // prosojno luknjo v zamrznjeni sliki, skozi katero se sirsa vidi ziv cilj pod
                // plastjo. (Prej: locen crn pravokotnik z izrezano luknjo NAD sliko — narobe,
                // to bi sliko skrilo povsod RAZEN v luknji.)
                ZStack {
                    Image(uiImage: podatki.slika)
                        .resizable()
                        .scaledToFill()
                        .frame(width: velikostOkna.width, height: velikostOkna.height)
                    oblika.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        }
        .ignoresSafeArea(.all)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: podatki.trajanje)) {
                skala = podatki.koncnaSkala
            }
        }
    }
}

/// Navaden zabris cez cel zaslon (Map, ali Reduce Motion namesto oblik): zamrznjena slika
/// pojema iz neprosojne v prosojno, pod njo je ze ziv cilj (zavihek je ze preklopljen).
struct ZabrisSloj: View {
    let slika: UIImage
    let velikostOkna: CGSize
    @State private var neprosojnost: Double = 1

    let trajanje: Double

    var body: some View {
        Image(uiImage: slika)
            .resizable()
            .scaledToFill()
            .frame(width: velikostOkna.width, height: velikostOkna.height)
            .opacity(neprosojnost)
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: trajanje)) { neprosojnost = 0 }
            }
    }
}
