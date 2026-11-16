import SwiftUI
import UIKit

/// Okvir prijave in registracije: vsebina se NE pomika, ker se prilagodi razpolozeni visini.
/// Najprej se skrci logotip (in zgornji odmik), ob odprti tipkovnici se skrijeta se druzabni gumbi in jezik.
/// Drsenje ostane samo kot rezerva, ce vsebina ne gre na zaslon niti brez logotipa (npr. skrajno velika pisava).
///
/// Namenoma NI `ViewThatFits`: ta ob preklopu med razlicicami zamenja poglede, polje v fokusu izgubi fokus in tipkovnica se zapre.
/// Tu je struktura vedno ista (logotip, glavni del, noga), spreminjajo se samo mere.
struct AuthOkvir<Glavna: View, Noga: View>: View {
    @State private var tipkovnica = false

    /// Glavni del (polja, gumbi). Argument: ali je tipkovnica odprta. Mora biti ENA vrednost pogleda (npr. en VStack).
    /// Pogledov ob tipkovnici NE odstranjuj z `if` (izgubi se njihov @State, npr. nonce prijave z Applom): uporabi `.skrijBrezUnicenja(tipkovnica)`.
    private let glavna: (Bool) -> Glavna
    /// Noga (jezik). Mora biti ENA vrednost pogleda, ki ostane v drevesu; ob tipkovnici jo skrij z `.skrijBrezUnicenja(tipkovnica)`
    /// (ne `EmptyView`/`if` brez `else`: razpored potrebuje tri poglede).
    private let noga: (Bool) -> Noga

    init(@ViewBuilder glavna: @escaping (Bool) -> Glavna, @ViewBuilder noga: @escaping (Bool) -> Noga) {
        self.glavna = glavna
        self.noga = noga
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                AuthRaspored(visina: geo.size.height, logoNajvec: min(350, stabilnaVisinaZaslona() * 0.28)) {   // stabilno ob tipkovnici
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .clipped()
                        .padding(.horizontal, 24)
                    glavna(tipkovnica)
                        .padding(.horizontal, 24)
                    noga(tipkovnica)
                        .padding(.horizontal, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Samo tipkovnica te aplikacije (ne tuja, npr. v sistemskem oknu prijave z Applom/Googlom).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            if (n.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool) != false { tipkovnica = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { n in
            if (n.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool) != false { tipkovnica = false }
        }
    }
}

extension View {
    /// Skrije pogled, a ga OSTANE v drevesu, da ne izgubi @State. Visina 0 s poravnavo `.top` (preliv samo navzdol, ne cez sosede nad njim),
    /// `.clipped()` (izris in dotik samo v obmocju 0), `.disabled` (okolje isEnabled, tudi za UIKit gumbe), nevidno in brez VoiceOverja.
    /// Pri vidnem stanju (skrij == false) clip ne odreze ni, ker pogledi nimajo sencenja prek roba.
    func skrijBrezUnicenja(_ skrij: Bool) -> some View {
        self
            .disabled(skrij)
            .frame(height: skrij ? 0 : nil, alignment: .top)
            .clipped()
            .opacity(skrij ? 0 : 1)
            .allowsHitTesting(!skrij)
            .accessibilityHidden(skrij)
    }
}

/// Navpicni razpored treh pogledov: logotip, glavni del, noga.
/// Visina = max(razpolozena visina, potrebna visina): ce vsebina gre na zaslon, se ScrollView nima kaj pomikati.
struct AuthRaspored: Layout {
    /// Razpolozena visina (GeometryReader, brez tipkovnice).
    var visina: CGFloat
    /// Najvecja visina logotipa.
    var logoNajvec: CGFloat

    private let razmik: CGFloat = 18
    private let zgoraNajvec: CGFloat = 58
    private let zgoraNajmanj: CGFloat = 16
    private let spodaj: CGFloat = 16
    /// Manjsega logotipa od tega ne kazemo (raje nic).
    private let logoNajmanj: CGFloat = 48

    private struct Mere {
        var zgoraj: CGFloat
        var logo: CGFloat
        var logoRazmik: CGFloat
        var glavna: CGFloat
        var noga: CGFloat
        var skupaj: CGFloat
        var prosto: CGFloat
    }

    private func mere(_ subviews: Subviews, sirina: CGFloat) -> Mere? {
        guard subviews.count == 3 else { return nil }
        let ponudba = ProposedViewSize(width: sirina, height: nil)
        let glavna = max(0, subviews[1].sizeThatFits(ponudba).height)
        let noga = max(0, subviews[2].sizeThatFits(ponudba).height)
        let nogaMesto: CGFloat = noga > 0 ? (2 * razmik + noga + razmik) : 0
        let osnova = glavna + nogaMesto + spodaj
        let prostor = max(0, visina) - osnova          // za zgornji odmik, logotip in razmik za njim

        var logo = min(max(0, logoNajvec), max(0, prostor - zgoraNajvec - razmik))
        if logo < logoNajmanj { logo = 0 }
        let logoRazmik: CGFloat = logo > 0 ? razmik : 0
        let zgoraj: CGFloat = logo > 0 ? zgoraNajvec : max(zgoraNajmanj, min(zgoraNajvec, prostor))

        let potrebno = zgoraj + logo + logoRazmik + osnova
        let skupaj = max(max(0, visina), potrebno)
        return Mere(zgoraj: zgoraj, logo: logo, logoRazmik: logoRazmik, glavna: glavna, noga: noga,
                    skupaj: skupaj, prosto: skupaj - potrebno)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sirina = proposal.width ?? 390
        guard let m = mere(subviews, sirina: sirina) else {
            // Varovalo (ni 3 podpogledov): pogledi enega pod drugim.
            let ponudba = ProposedViewSize(width: sirina, height: nil)
            return CGSize(width: sirina, height: subviews.reduce(0) { $0 + max(0, $1.sizeThatFits(ponudba).height) })
        }
        return CGSize(width: sirina, height: m.skupaj)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let m = mere(subviews, sirina: bounds.width) else {
            // Varovalo (ni 3 podpogledov): pogledi enega pod drugim, brez praznega zaslona.
            var yv = bounds.minY
            for v in subviews {
                let h = max(0, v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height)
                v.place(at: CGPoint(x: bounds.minX, y: yv), anchor: .topLeading,
                        proposal: ProposedViewSize(width: bounds.width, height: h))
                yv += h
            }
            return
        }
        var y = bounds.minY + m.zgoraj

        subviews[0].place(at: CGPoint(x: bounds.midX, y: y), anchor: .top,
                          proposal: ProposedViewSize(width: bounds.width, height: m.logo))
        y += m.logo + m.logoRazmik

        subviews[1].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: m.glavna))
        y += m.glavna

        if m.noga > 0 {
            // Noga je na sredini preostalega prostora (kot prej s Spacer()).
            y += razmik + m.prosto / 2 + razmik
            subviews[2].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: m.noga))
        } else {
            subviews[2].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: 0))
        }
    }
}
