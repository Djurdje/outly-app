import SwiftUI

extension Color {
    /// Zlata za VIP vstopnice (poudarek, ne ploskev cez vso kartico).
    static let vipZlata = Color(red: 0.83, green: 0.69, blue: 0.22)
}

/// Znacka "VIP" s krono. `kompakten` = manjsa (vrstice seznamov).
struct VipZnacka: View {
    var kompakten: Bool = false

    var body: some View {
        HStack(spacing: kompakten ? 3 : 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: kompakten ? 9 : 11, weight: .bold))
            Text(verbatim: "VIP")
                .font(.system(size: kompakten ? 10 : 11, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundColor(.black)
        .padding(.horizontal, kompakten ? 7 : 9)
        .padding(.vertical, kompakten ? 3 : 4)
        .background(Color.vipZlata)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "VIP"))
    }
}
