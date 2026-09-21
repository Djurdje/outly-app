import SwiftUI
import UIKit

// Skupni slog nastavitvenih zaslonov (Figma "Pass and sec" 95:1403, "notification" 113:955):
// crno ozadje, temne kartice z naslovom, vrstice s stikalom. Vrstice z dejanjem so od 21. 9.
// (Luka) SAMO dva gradnika: OutlyMenuRowButton (ikona + naslov) in OutlyInfoCardButton
// (naslov kartice, vrednost, Edit, opomba) v Buttons.swift — tretjega sloga ni vec.

/// Kartica z naslovom (npr. "Login", "Tickets") in vsebino (vrstice).
struct OutlySettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 2)
            VStack(spacing: 8) { content }
        }
    }
}

/// Vrstica s stikalom (Figma "notification").
struct OutlySettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
        .tint(.outlyBlue)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Temno vnosno polje za gesla (Figma "Pass change" 184:2333): oznaka nad vrednostjo,
/// opomba pod poljem. Bela polja (OutlySecureField) ostanejo za prijavo/registracijo.
struct OutlyDarkSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    var contentType: UITextContentType = .password

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(label))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                SecureField(LocalizedStringKey(placeholder), text: $text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .tint(.outlyBlue)
                    .textContentType(contentType)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))

            if let hint {
                Text(LocalizedStringKey(hint))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 4)
            }
        }
    }
}
