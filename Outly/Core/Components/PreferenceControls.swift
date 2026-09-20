import SwiftUI

// Skupni kontrolniki za "My preferences" (Profil) in "Filters" (Home), da sta oba zaslona
// iz enega kosa: isti cipi zanrov kot pri dokoncanju racuna, drsniki v vrsticah nastavitev
// (bela 8 %, radij 16, kot OutlySettingsRow), modra samo za izbrano/aktivno.

/// Mreza cipov zanrov v treh stolpcih (kot SelectGenresView), izbrani so modri.
struct OutlyGenreGrid: View {
    let genres: [String]
    @Binding var selected: Set<String>

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(genres, id: \.self) { g in
                GenreChip(title: GenreNames.display(g), isSelected: selected.contains(g)) {
                    if selected.contains(g) { selected.remove(g) } else { selected.insert(g) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Vrstica z drsnikom: naslov levo, vrednost desno, drsnik spodaj.
struct OutlySliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text(verbatim: valueText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: $value, in: range, step: step)
                .tint(.outlyBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Vrstica s stikalom, ikono in opisom pod naslovom ("Use my preferences").
struct OutlyToggleDetailRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .tint(.outlyBlue)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Pomocniki za besedila vrednosti (razdalja, starost, cena v centih).
enum PrefBesedila {
    static func km(_ v: Double) -> String { "\(Int(v)) km" }
    static func leta(_ v: Double) -> String { "\(Int(v))" }
    static func cena(_ centi: Int) -> String { centi == 0 ? String(localized: "Free") : Denar.evri(centi) }
}
