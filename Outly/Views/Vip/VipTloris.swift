import SwiftUI

/// Tloris kluba za VIP mize: temno platno z rahlo mrezo, orientacijski elementi (zamolklo polnilo + napis)
/// in mize kot gumbi (prosta / izbrana / prodana). Celica = sirina platna / `plan.width`; sirino prebere
/// en sam GeometryReader, nobena vrednost se ne hrani v @State (nic se ne preracuna ob drsenju).
struct VipTloris: View {
    let plan: VipPlan
    let mize: [VipTable]
    let izbranaId: Int?
    /// false = prodaja zaprta: mize se vidijo, izbrati se jih ne da.
    let prodajaOdprta: Bool
    let onSelect: (VipTable) -> Void

    var body: some View {
        GeometryReader { geo in
            let celica = geo.size.width / CGFloat(plan.width)
            ZStack(alignment: .topLeading) {
                Color(white: 0.08)
                mreza(celica: celica)
                ForEach(Array(plan.elements.enumerated()), id: \.offset) { _, el in
                    element(el, celica: celica)
                }
                ForEach(mize) { m in
                    miza(m, celica: celica)
                }
            }
            .frame(width: geo.size.width, height: celica * CGFloat(plan.height), alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .aspectRatio(CGFloat(plan.width) / CGFloat(plan.height), contentMode: .fit)
    }

    // MARK: - Mreza

    private func mreza(celica: CGFloat) -> some View {
        let sirina = celica * CGFloat(plan.width)
        let visina = celica * CGFloat(plan.height)
        return Path { p in
            for i in 0...plan.width {
                let x = CGFloat(i) * celica
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: visina))
            }
            for j in 0...plan.height {
                let y = CGFloat(j) * celica
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: sirina, y: y))
            }
        }
        .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
    }

    // MARK: - Elementi

    private func element(_ el: VipElement, celica: CGFloat) -> some View {
        let jeStena = el.type == "wall"
        let jeNapis = el.type == "label"
        let radij = min(8, celica * 0.4)
        return ZStack {
            if !jeNapis {
                RoundedRectangle(cornerRadius: radij, style: .continuous)
                    .fill(Color.white.opacity(jeStena ? 0.20 : 0.07))
                RoundedRectangle(cornerRadius: radij, style: .continuous)
                    .stroke(Color.white.opacity(jeStena ? 0 : 0.12), lineWidth: 1)
            }
            napis(el, celica: celica)
        }
        .frame(width: CGFloat(el.w) * celica, height: CGFloat(el.h) * celica)
        .offset(x: CGFloat(el.x) * celica, y: CGFloat(el.y) * celica)
        .allowsHitTesting(false)
        .accessibilityHidden(el.label.isEmpty && VipOznaka.privzetNaziv(tip: el.type) == nil)
    }

    @ViewBuilder
    private func napis(_ el: VipElement, celica: CGFloat) -> some View {
        if !el.label.isEmpty {
            urediNapis(Text(verbatim: el.label), celica: celica)
        } else if let kljuc = VipOznaka.privzetNaziv(tip: el.type) {
            urediNapis(Text(LocalizedStringKey(kljuc)), celica: celica)
        }
    }

    private func urediNapis(_ t: Text, celica: CGFloat) -> some View {
        t.font(.system(size: max(7, min(11, celica * 0.5)), weight: .medium))
            .foregroundColor(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .padding(2)
    }

    // MARK: - Mize

    private func oblika(_ m: VipTable, celica: CGFloat) -> AnyShape {
        if m.shape == "round" { return AnyShape(Ellipse()) }
        return AnyShape(RoundedRectangle(cornerRadius: min(8, celica * 0.35), style: .continuous))
    }

    private func opisStanja(_ m: VipTable) -> String {
        if m.id == izbranaId { return String(localized: "Selected") }
        return m.available ? String(localized: "Available") : String(localized: "Booked")
    }

    private func miza(_ m: VipTable, celica: CGFloat) -> some View {
        let izbrana = m.id == izbranaId
        let prosta = m.available
        let polnilo: Color = izbrana ? .outlyBlue : (prosta ? Color(white: 0.14) : Color.white.opacity(0.03))
        let obroba: Color = izbrana ? Color.white.opacity(0.9) : (prosta ? Color.white.opacity(0.65) : Color.white.opacity(0.12))
        let besedilo: Color = prosta || izbrana ? .white : Color.white.opacity(0.3)
        let oblikaMize = oblika(m, celica: celica)
        let sirinaMize = CGFloat(m.w) * celica
        let visinaMize = CGFloat(m.h) * celica
        let tarcaSirina = max(sirinaMize, 44)
        let tarcaVisina = max(visinaMize, 44)
        return Button {
            if prosta && prodajaOdprta { onSelect(m) }
        } label: {
            ZStack {
                oblikaMize.fill(polnilo)
                oblikaMize.stroke(obroba, lineWidth: izbrana ? 2 : 1.5)
                Text(verbatim: m.label)
                    .font(.system(size: max(8, min(13, celica * 0.6)), weight: .bold))
                    .foregroundColor(besedilo)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(2)
            }
            .frame(width: sirinaMize, height: visinaMize)
            // Tarca za dotik vsaj 44 x 44 pt, sredinsko okoli mize; izris ostane enak.
            .frame(width: tarcaSirina, height: tarcaVisina)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(m.x) * celica - (tarcaSirina - sirinaMize) / 2,
                y: CGFloat(m.y) * celica - (tarcaVisina - visinaMize) / 2)
        .accessibilityLabel(Text(verbatim: "\(VipOznaka.miza(m.label)), \(opisStanja(m))"))
    }
}
