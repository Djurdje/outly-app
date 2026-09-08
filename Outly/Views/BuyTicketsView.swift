import SwiftUI
import UIKit

/// Nakup vstopnic (sheet iz EventDetailView). Kolicina -> potrditev -> vstopnice s QR.
/// Kartica se NE vnasa v aplikaciji (PCI DSS): ko pride Stripe, tu vstopi Stripov
/// obrazec. Do takrat backend dela v TESTNEM nacinu — denar se ne premakne, kar
/// zaslon jasno pove.
@MainActor
struct BuyTicketsView: View {
    let event: APIEvent
    let clubName: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var quantity = 1
    @State private var isBuying = false
    @State private var errorMessage: String?
    @State private var purchase: PurchaseResponse?

    private var unitCents: Int { event.ticketPriceCents ?? 0 }
    private var totalCents: Int { unitCents * quantity }

    var body: some View {
        NavigationStack {
            Group {
                if let purchase {
                    uspeh(purchase)
                } else {
                    obrazec
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(purchase == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Obrazec

    private var obrazec: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Tickets")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(clubName) · \(event.displayDateShort) \(event.displayTimeShort)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                    if event.minAge > 0 {
                        Text("\(event.minAge)+ · ID checked at the door")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                HStack {
                    Text("Quantity")
                        .foregroundColor(.white)
                    Spacer()
                    Stepper(value: $quantity, in: 1...10) {
                        Text("\(quantity)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(minWidth: 28)
                    }
                    .fixedSize()
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 10) {
                    vrstica("\(quantity) × \(Denar.evri(unitCents, koda: event.currency ?? "EUR"))", Denar.evri(totalCents, koda: event.currency ?? "EUR"))
                    Divider().background(Color.white.opacity(0.15))
                    HStack {
                        Text("Total").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        Spacer()
                        Text(Denar.evri(totalCents, koda: event.currency ?? "EUR"))
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                testniTrak

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OutlyPrimaryButton(title: event.isSoldOut ? "Sold out" : "Confirm purchase", isLoading: isBuying) {
                    Task { await kupi() }
                }
                .disabled(isBuying || event.isSoldOut)
                .opacity(event.isSoldOut ? 0.5 : 1)

                Text("Tickets for a dated event cannot be returned after purchase (ZVPot-1, 135/12). The seller is the club; Outly is the intermediary.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    private var testniTrak: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask")
                .foregroundColor(.orange)
            Text("TEST MODE — no money is charged. Card payments (Stripe) are not connected yet; this simulates the full flow.")
                .font(.system(size: 12))
                .foregroundColor(.orange.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func vrstica(_ levo: String, _ desno: String) -> some View {
        HStack {
            Text(levo).foregroundColor(.white.opacity(0.75))
            Spacer()
            Text(desno).foregroundColor(.white)
        }
        .font(.system(size: 15))
    }

    // MARK: - Uspeh

    private func uspeh(_ p: PurchaseResponse) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.outlyBlue)
                    .padding(.top, 20)

                Text("You're in!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Order \(p.order.publicRef) · \(p.tickets.count) ticket\(p.tickets.count == 1 ? "" : "s") · \(Denar.evri(p.order.totalCents, koda: p.order.currency))")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))

                if p.mode == "test" {
                    Text("TEST PURCHASE — nothing was charged.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }

                ForEach(Array(p.tickets.enumerated()), id: \.element.id) { i, t in
                    VStack(spacing: 10) {
                        Text("Ticket \(i + 1) of \(p.tickets.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        QRCodeView(content: t.qr, size: 200)
                        Text(t.serial.prefix(8).uppercased())
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Text("Your tickets are saved under Profile → Tickets. Show the QR code at the door.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                OutlyPrimaryButton(title: "Done") { dismiss() }
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    private func kupi() async {
        errorMessage = nil
        isBuying = true
        defer { isBuying = false }
        do {
            let p = try await APIClient.shared.buyTickets(token: session.token, eventId: event.id, quantity: quantity)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { purchase = p }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.userMessage
        }
    }
}
