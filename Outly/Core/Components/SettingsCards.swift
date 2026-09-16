import SwiftUI
import UIKit

// Skupni slog nastavitvenih zaslonov (Figma "Pass and sec" 95:1403, "notification" 113:955):
// crno ozadje, temne kartice z naslovom, vrstice z ikono levo in dejanjem/stikalom desno,
// siva opomba pod vrstico. Uporabljajo ga Password and security, Notifications, ...
// Isti radij in prosojnost kot OutlyMenuRowButton na profilu, da je vse iz enega kosa.

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
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 2)
            VStack(spacing: 8) { content }
        }
    }
}

/// Vrstica: ikona, naslov, desno modro dejanje ("Edit", "Turn on") — cela vrstica je gumb.
struct OutlySettingsRow: View {
    let icon: String
    let title: String
    var action: String? = nil
    var actionColor: Color = .outlyBlue
    var footnote: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24)
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    if let action {
                        Text(action)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(actionColor)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Vrstica s stikalom (Figma "notification").
struct OutlySettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
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
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                SecureField(placeholder, text: $text)
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
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 4)
            }
        }
    }
}
