import SwiftUI

/// Informativen napotek (nevtralna kartica, brez barvnega poudarka): npr. nejasen izid nakupa ob ponovnem odprtju lista.
/// Napaka je rdeca, glavni gumb modra; to je samo obvestilo.
struct NapotekKartica: View {
    let besedilo: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.white.opacity(0.6))
                .accessibilityHidden(true)
            Text(besedilo)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
