import SwiftUI

struct OutlyTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(LocalizedStringKey(placeholder), text: $text)
            .font(.system(size: 16, weight: .medium))
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.95))
            .foregroundColor(Color.black.opacity(0.85))
            .tint(.black)
            .environment(\.colorScheme, .light)
            .cornerRadius(12)
    }
}

struct OutlySecureField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(LocalizedStringKey(placeholder), text: $text)
            .font(.system(size: 16, weight: .medium))
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.95))
            .foregroundColor(Color.black.opacity(0.85))
            .tint(.black)
            .environment(\.colorScheme, .light)       
            .cornerRadius(12)
    }
}

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .background(Color.outlyCard)
        .cornerRadius(16)
    }
}
