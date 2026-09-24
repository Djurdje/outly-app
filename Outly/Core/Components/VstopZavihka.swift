import SwiftUI

/// "Kot Revolut" prehod med zavihki (Martin, 24. 9. 2026, zamenjava za "krozno razkritje" iz
/// PR #22 — Martin je videl posnetek Revoluta in hoce drugacno animacijo, brez maske/kroga):
/// ob preklopu Home -> Search/Profile vsebina cilja zraste iz sidra (sredisce avatarja ali polja
/// "Where to?") s 40 % na 100 %, hkrati se pojavi (opacity) in izostri (blur), medtem ko domaci
/// zaslon pod njo zbledi v ze zamegljen posnetek (glej ZabrisSloj spodaj in VstopZavihka v
/// Core/Themes/Ozadje.swift). Nazaj je obratno. Search<->Profile je navaden preklop (brez
/// animacije, Martin izrecno) in Map ostane navaden zabris — oboje ne rabi izvora/oblike, zato
/// so tu samo skupni tipi, ki jih poganja MainTabView (samo on ve, kateri zavihek zapuscamo in
/// katerega odpiramo).

/// Okvirja avatarja in polja "Where to?" v HomeView, v GLOBALNIH (okenskih) koordinatah —
/// isti koordinatni sistem kot posnetek zaslona (surovPosnetek), da se sidro ujema z vsebino.
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

/// Navaden zabris cez cel zaslon: zamrznjena slika pojema iz neprosojne v prosojno, pod njo je
/// ze ziv cilj (zavihek je ze preklopljen, ko se ta plast doda). Uporabljajo ga TRIJE prehodi:
/// - karkoli <-> Map (Martin: "pusti kot je"),
/// - Reduce Motion namesto rasti/krcenja (samo prosojnost, trdo pravilo),
/// - Home -> Search/Profile in Search/Profile -> Home kot spremljevalna plast ("Home se zamegli"
///   oz. "domaci zaslon se izostri") POLEG rasti/krcenja vsebine (VstopZavihka), ne namesto nje.
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
