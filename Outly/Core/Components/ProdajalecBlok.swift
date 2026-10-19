import SwiftUI

/// Podatki prodajalca tik nad gumbom za placilo (outly-backend#94; ZVPot-1 18/1-2, 130/1-1): kupec mora PRED nakupom
/// izvedeti, kdo je prodajalec (firma, sedez, maticna in davcna stevilka, kontakt). Siv, droben tekst brez nove barve:
/// poudarjena stvar na zaslonu ostane gumb.
/// - `kazeDdv`: vrstica o DDV (po `vat_payer`) v bloku; pri nakupu vstopnic je DDV vrstica ze pod skupnim zneskom, zato tam false.
/// - `kazePosrednika`: stavek »Outly is the intermediary.«; false tam, kjer ga zaslon ze ima (nakup vstopnic).
///   Pri `seller.isPlatform` (uradni profil Outly, backend I50) namesto njega vedno »Outly is the seller.«.
struct OutlyProdajalecBlok: View {
    let seller: Seller
    var kazeDdv: Bool = false
    var kazePosrednika: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Seller")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))
                .padding(.bottom, 2)

            if !seller.imeProdajalca.isEmpty {
                Text(verbatim: seller.imeProdajalca)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            vrstica(seller.address)
            vrstica(seller.registracijaVrstica)
            vrstica(seller.stikVrstica)
            if kazeDdv {
                vrstica(Seller.ddvBesedilo(seller))
            }
            if seller.isPlatform {
                // Uradni profil Outly (backend I50): prodajalec je platforma sama, posrednika ni (tudi tam, kjer bi sicer stal stavek o njem).
                Text("Outly is the seller.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else if kazePosrednika {
                Text("Outly is the intermediary.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func vrstica(_ besedilo: String) -> some View {
        let t = besedilo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            Text(verbatim: t)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
