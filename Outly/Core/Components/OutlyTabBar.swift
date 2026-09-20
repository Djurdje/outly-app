import SwiftUI

/// Lastna spodnja vrstica (Home, Search, Map, Profile) — nadomesca sistemski TabView,
/// ker prehodi med zasloni (MainTabView) potrebujejo Home pod ostalimi zasloni.
/// Videz kot prej: SF ikone, aktivni zavihek moder (#4C76FF), ostali beli 45 %.
struct OutlyTabBar: View {
    @Binding var selected: Int

    struct Zavihek {
        let tag: Int
        let title: LocalizedStringKey
        let icon: String
    }

    static let zavihki: [Zavihek] = [
        Zavihek(tag: 0, title: "Home", icon: "house.fill"),
        Zavihek(tag: 1, title: "Search", icon: "magnifyingglass"),
        Zavihek(tag: 2, title: "Map", icon: "map.fill"),
        Zavihek(tag: 3, title: "Profile", icon: "person.fill")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.zavihki, id: \.tag) { z in
                Button {
                    selected = z.tag
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: z.icon)
                            .font(.system(size: 22, weight: .medium))
                            .frame(height: 26)
                        Text(z.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selected == z.tag ? Color.outlyBlue : Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(z.title))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
        }
    }
}
