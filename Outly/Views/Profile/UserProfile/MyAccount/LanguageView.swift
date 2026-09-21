import SwiftUI

/// Jezik aplikacije: Moj racun -> Language. Seznam je pripravljen na vec jezikov
/// (dodas v Jezik.seznam, ta zaslon in vrstica v MyAccountView se same posodobita).
/// Preklop je takojsen, brez ponovnega zagona (glej Jezik.swift); ker koren aplikacije
/// dobi nov .id, se ta pogled po izbiri zapre - jezik.zavihekPoPreklopu postavi
/// MainTabView nazaj na zavihek Profil.
struct LanguageView: View {
    @EnvironmentObject private var jezik: Jezik

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                Text("Language")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                OutlySettingsCard("Language") {
                    ForEach(Jezik.seznam, id: \.koda) { vnos in
                        JezikVrstica(
                            ime: vnos.ime,
                            izbran: jezik.koda == vnos.koda,
                            onTap: { jezik.nastavi(vnos.koda, zavihek: 3) }
                        )
                    }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationTitle("Language")
        .preferredColorScheme(.dark)
    }
}

/// Vrstica jezika: ime (vedno v svojem jeziku, se NE prevaja) + kljukica, ce je izbran.
private struct JezikVrstica: View {
    let ime: String
    let izbran: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24)
                Text(verbatim: ime)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                if izbran {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.outlyBlue)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
