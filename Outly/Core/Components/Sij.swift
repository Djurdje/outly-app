import SwiftUI

/// Moder sij okoli gumba (Martin, 23. 9. 2026: sij za marketinski poudarek). Isti sij kot na gumbu
/// za vstopnice na zaslonu dogodka (PR #21): dve senci brez zamika — ozka svetla + siroka mehka.
/// Pravilo: EN sij na zaslon, samo na gumbu, ki prinaša nakup ali rast (Buy, Join them, Follow,
/// Invite more, Log in / Create account). Nikoli na neaktivnem gumbu (`aktiven: false` = brez sija).
/// `moc` 1.0 = polni sij (Buy), 0.5 = sibkejsi (Invite more, prijava).
/// `diha`: sij pocasi utripa (npr. med nalaganjem); pri Reduce Motion ne utripa.
struct OutlySijModifier: ViewModifier {
    var moc: Double = 1.0
    var aktiven: Bool = true
    var diha: Bool = false
    @Environment(\.accessibilityReduceMotion) private var manjGibanja
    @State private var faza = false

    func body(content: Content) -> some View {
        let k = aktiven ? moc * (diha && faza ? 1.35 : 1.0) : 0
        content
            .shadow(color: Color.outlyBlue.opacity(0.70 * k), radius: 12)
            .shadow(color: Color.outlyBlue.opacity(0.45 * k), radius: 28)
            .onChange(of: diha, initial: true) { _, nov in
                guard nov, !manjGibanja else { faza = false; return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { faza = true }
            }
    }
}

extension View {
    /// Moder sij za en poudarjen gumb na zaslonu. Glej OutlySijModifier.
    func outlySij(moc: Double = 1.0, aktiven: Bool = true, diha: Bool = false) -> some View {
        modifier(OutlySijModifier(moc: moc, aktiven: aktiven, diha: diha))
    }
}
