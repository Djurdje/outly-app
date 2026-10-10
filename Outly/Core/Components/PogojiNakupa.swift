import SwiftUI

/// Kratko besedilo s povezavama na Pogoje in Politiko zasebnosti tik ob gumbu za placilo (outly-backend#96).
/// URL-ja sta literal v nizu (markdown povezava z interpolacijo v `LocalizedStringKey` ni zanesljiva); morata se
/// ujemati z `LegalLinks.terms` / `LegalLinks.privacy`. Siv, droben tekst: poudarjena stvar na zaslonu ostane gumb; povezavi sta svetlejsi
/// (`.tint`), ne modri (modra je samo na glavnem gumbu). Markdown povezave v `Text` odpre sistem (Safari).
struct OutlyPogojiNakupa: View {
    var body: some View {
        Text("By continuing you agree to the [Terms of Service](https://outly.si/terms) and acknowledge the [Privacy Policy](https://outly.si/privacy-app).")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.45))
            .tint(Color.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }
}
