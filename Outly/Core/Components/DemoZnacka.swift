import SwiftUI

/// Znacka »Demo« (klub ali dogodek izmisljenega demo kluba, backend#243). Nevtralna siva kapsula z belim napisom
/// (modra je samo za glavni gumb, zlata za VIP); berljiva tudi na svetlem plakatu. `kompakten` = manjsa (kartice, vrstice).
/// Ena sama izvedba za vse kartice in zaslone: pogoj je `isDemo` iz API-ja (`APIClub`, `APIEvent`, `MapClub` ...).
struct DemoZnacka: View {
    var kompakten: Bool = false

    var body: some View {
        Text("Demo")
            .font(.system(size: kompakten ? 9 : 11, weight: .heavy))
            .tracking(0.4)
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, kompakten ? 7 : 9)
            .padding(.vertical, kompakten ? 3 : 4)
            .background(Color(white: 0.34))
            .clipShape(Capsule())
            .accessibilityLabel(Text("Demo"))
    }
}
