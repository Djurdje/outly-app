import SwiftUI

/// Skeni, ki so bili na telefonu zeleni (gost je sel noter), streznik pa jih ni potrdil — navadno ker je isto vstopnico
/// pred nami spustil drug telefon ali spletni skener brez povezave. Ne brisemo jih tiho: ostanejo, dokler jih vratar ne potrdi.
@MainActor
struct SkenKonfliktiView: View {
    @ObservedObject var seja: SkenSeja
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These guests were let in from this phone, but the server did not confirm the entry.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))

                        if seja.konflikti.isEmpty {
                            Text("No conflicts")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }

                        ForEach(seja.konflikti) { k in
                            kartica(k)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func kartica(_ k: SkenKonflikt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: k.imetnik ?? String(k.serial?.prefix(8) ?? "?"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(verbatim: SkenPrikaz.razlogKonflikta(k.result))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            Text("Scanned here at \(SkenPrikaz.cas(k.scannedAt))")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
            if let t = SkenCas.razcleni(k.streznikUsedAt) {
                Text("First used on the server at \(SkenPrikaz.cas(t))")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
            }
            Button("Dismiss") { seja.potrdiKonflikt(k) }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
