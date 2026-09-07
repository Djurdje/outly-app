import SwiftUI

/// Placila. Odlocitev projekta: v aplikaciji NI denarnice (stanja, polnjenja, dvigov),
/// ker bi bilo to izdajanje e-denarja po ZPlaSSIED. Kartica se ne vnasa v nas vmesnik
/// (PCI DSS) — ob nakupu jo prevzame Stripov obrazec. Prejsnja "Balance" kartica in
/// vrstici, ki sta vodili na napacen zaslon, so odstranjene.
struct PaymentView: View {
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 18) {
                Text("Payment")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.outlyBlue)
                        Text("Secure checkout")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Text("Ticket purchases are coming soon. Payments will be processed by Stripe; Outly never sees or stores your card details, and the app does not hold a balance.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
