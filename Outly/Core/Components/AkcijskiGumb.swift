import SwiftUI
import UIKit

/// Stanje skupnega akcijskega gumba "gumb -> krog -> kljukica" (Martin, 23. 9. 2026).
/// En vzorec za Buy in Send ticket, da se ne razideta.
enum StanjeAkcije: Equatable {
    case miruje
    case nalaga
    case uspeh
    case napaka
}

/// Gumb, ki se ob dejanju skrci v krog s crtico (ProgressView), ob uspehu vanj
/// nariseva belo kljukico (animiran `trim`, haptika .success, rahel poskok), ob
/// napaki se strese in za hip pordeci (haptika .error), nato se sam vrne v `.miruje`.
///
/// Po uspehu klicatelj izbere eno od dveh poti:
/// - `naslovUspeha` podan: krog se razsiri nazaj v poln moder gumb s kljukico + napisom
///   (npr. "Sent to Ana") - primerno, ko je dejanje s tem koncano.
/// - `naslovUspeha` nil: gumb ostane krog s kljukico, klicatelj nadaljuje sam (npr. nakup,
///   kjer se naslednji zaslon pojavi iz kroga).
///
/// Oblika v `.miruje` je enaka `OutlyPrimaryButton` (visina 48, radij 14, #4C76FF, bel napis
/// 16 semibold). Sij se prizge SAM samo med `.nalaga` (diha) - stalni sij v mirovanju je
/// stvar klicatelja (`.outlySij(...)` od zunaj), da ostane pravilo "en sij na zaslon".
/// Reduce Motion: brez krcenja/poskoka/tresenja - samo zabrisana zamenjava vsebine.
struct OutlyAkcijskiGumb: View {
    let naslov: String
    @Binding var stanje: StanjeAkcije
    var naslovUspeha: String? = nil
    /// false = gumb nikoli ne diha (npr. ce klicatelj sam v celoti nadzoruje sij).
    var sij: Bool = true
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var manjGibanja

    /// true = polna sirina (miruje, ali uspeh po razsiritvi); false = krog.
    @State private var razsirjen = true
    @State private var kljukicaDelez: CGFloat = 0
    @State private var poskok: CGFloat = 1
    @State private var tresenjeX: CGFloat = 0
    @State private var napakaBarva = false

    private let visina: CGFloat = 48
    private let premerKroga: CGFloat = 52

    var body: some View {
        Button {
            guard stanje == .miruje else { return }
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: razsirjen ? 14 : premerKroga / 2, style: .continuous)
                    .fill(napakaBarva ? Color.red : Color.outlyBlue)
                vsebina
            }
            .frame(maxWidth: razsirjen ? .infinity : premerKroga)
            .frame(height: razsirjen ? visina : premerKroga)
        }
        .buttonStyle(.plain)
        .disabled(stanje != .miruje)
        .accessibilityLabel(Text(LocalizedStringKey(naslov)))
        .offset(x: tresenjeX)
        .scaleEffect(poskok)
        .outlySij(moc: 0.6, aktiven: sij && stanje == .nalaga, diha: true)
        .animation(manjGibanja ? nil : .easeInOut(duration: 0.3), value: razsirjen)
        .onChange(of: stanje) { _, novo in obdelajStanje(novo) }
        .onAppear { razsirjen = (stanje == .miruje || stanje == .uspeh) }
    }

    @ViewBuilder
    private var vsebina: some View {
        switch stanje {
        case .miruje:
            Text(LocalizedStringKey(naslov))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .transition(prehod)

        case .nalaga:
            ProgressView()
                .tint(.white)
                .transition(prehod)

        case .uspeh:
            if razsirjen, let naslovUspeha {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                    Text(LocalizedStringKey(naslovUspeha))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .transition(prehod)
            } else {
                OutlyKljukicaOblika()
                    .trim(from: 0, to: kljukicaDelez)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                    .transition(prehod)
            }

        case .napaka:
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .transition(prehod)
        }
    }

    private var prehod: AnyTransition {
        manjGibanja ? .opacity : .opacity.combined(with: .scale(scale: 0.8))
    }

    // MARK: - Prehodi med stanji

    private func obdelajStanje(_ novo: StanjeAkcije) {
        switch novo {
        case .miruje:
            napakaBarva = false
            kljukicaDelez = 0
            withAnimation(manjGibanja ? nil : .easeInOut(duration: 0.3)) { razsirjen = true }

        case .nalaga:
            napakaBarva = false
            kljukicaDelez = 0
            withAnimation(manjGibanja ? nil : .easeInOut(duration: 0.3)) { razsirjen = false }

        case .uspeh:
            zazenajUspeh()

        case .napaka:
            zazenajNapako()
        }
    }

    private func zazenajUspeh() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        razsirjen = false
        withAnimation(manjGibanja ? nil : .easeOut(duration: 0.3)) { kljukicaDelez = 1 }

        if !manjGibanja {
            withAnimation(.easeOut(duration: 0.15)) { poskok = 1.08 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.15)) { poskok = 1 }
            }
        }

        guard naslovUspeha != nil else { return }
        // Kratek premor, da je kljukica vidna, preden se krog razsiri nazaj v gumb.
        let zamik = manjGibanja ? 0.1 : 0.55
        DispatchQueue.main.asyncAfter(deadline: .now() + zamik) {
            withAnimation(manjGibanja ? nil : .easeInOut(duration: 0.3)) { razsirjen = true }
        }
    }

    private func zazenajNapako() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        kljukicaDelez = 0
        napakaBarva = true

        guard !manjGibanja else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                napakaBarva = false
                stanje = .miruje
            }
            return
        }

        // Tresenje +-8pt, 3x (6 korakov), nato nazaj na 0 in v .miruje.
        let zamiki: [CGFloat] = [-8, 8, -8, 8, -8, 8, 0]
        for (i, z) in zamiki.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                withAnimation(.easeInOut(duration: 0.08)) { tresenjeX = z }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(zamiki.count) * 0.08) {
            napakaBarva = false
            razsirjen = true
            stanje = .miruje
        }
    }
}

/// Kljukica kot pot - trim(from:to:) jo animirano "nariše".
private struct OutlyKljukicaOblika: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.20, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.75))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.28))
        return p
    }
}

/// Zabrisana zamenjava vsebine (Reduce Motion: samo prosojnost, brez blura je manj mote).
extension AnyTransition {
    static var outlyZabris: AnyTransition {
        .modifier(
            active: OutlyZabrisModifier(radius: 8, prosojnost: 0),
            identity: OutlyZabrisModifier(radius: 0, prosojnost: 1)
        )
    }
}

private struct OutlyZabrisModifier: ViewModifier {
    let radius: CGFloat
    let prosojnost: Double
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(prosojnost)
    }
}
