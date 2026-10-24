import SwiftUI

/// Potrdilo po rezervaciji mize za placilo na VIP vratih (VipTablesView, `vip_payment == "door"`): miza, paket, znesek za placilo
/// z gotovino na vratih, ime rezervacije in »Cancel reservation« (DELETE …/reservations, do zacetka dogodka). Brez Stripa in
/// vstopnic. Rezervacija je potem tudi v Profile -> Tickets -> Table reservations. Brez lastnega NavigationStack.
@MainActor
struct VipRezervacijaUspeh: View {
    let rezervacija: TableReservation
    /// »Done« in po preklicu: klicatelj zapre list.
    let zapri: () -> Void

    @EnvironmentObject private var session: SessionStore

    @State private var potrdiPreklic = false
    @State private var preklicujem = false
    @State private var napaka: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.vipZlata.opacity(0.18)).frame(width: 84, height: 84)
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.vipZlata)
                }
                .padding(.top, 16)

                Text("Your table is reserved")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        VipZnacka()
                        Text(verbatim: povzetek)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    if !rezervacija.packageName.isEmpty {
                        Text(verbatim: rezervacija.packageName)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    if !rezervacija.guestName.isEmpty {
                        Text("Reserved for \(rezervacija.guestName)")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                // Kaj in koliko placa na vratih: najpomembnejsa vrstica zaslona.
                HStack(spacing: 12) {
                    Image(systemName: "banknote")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.vipZlata)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                    Text(verbatim: rezervacija.znesekNaVratih.map { String(localized: "Pay \($0) in cash at the VIP door") }
                         ?? String(localized: "No payment needed"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Nothing was charged in the app. Show your name at the VIP door. You can find this reservation in Profile > Tickets.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let napaka {
                    Text(napaka)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                if rezervacija.jeMogocPreklic() {
                    Button {
                        potrdiPreklic = true
                    } label: {
                        HStack(spacing: 8) {
                            if preklicujem { ProgressView().tint(.red) }
                            Text("Cancel reservation")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.red.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .disabled(preklicujem)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .confirmationDialog("Cancel this reservation?", isPresented: $potrdiPreklic, titleVisibility: .visible) {
            Button("Cancel reservation", role: .destructive) { Task { await preklici() } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The table becomes available to other guests again.")
        }
        .interactiveDismissDisabled(preklicujem)
    }

    /// "Table T4 · Up to 6 people"
    private var povzetek: String {
        var deli: [String] = []
        if !rezervacija.tableLabel.isEmpty { deli.append(VipOznaka.miza(rezervacija.tableLabel)) }
        if rezervacija.seats > 0 { deli.append(String(localized: "Up to \(rezervacija.seats) people")) }
        return deli.joined(separator: " · ")
    }

    private func preklici() async {
        napaka = nil
        preklicujem = true
        defer { preklicujem = false }
        do {
            try await APIClient.shared.cancelVipReservation(eventId: rezervacija.eventId, tableId: rezervacija.tableId, token: session.token)
            zapri()
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api {
                if code == 401 { session.logout(); return }
                // 404: rezervacije ni vec (ze preklicana) - za kupca enako kot uspeh.
                if code == 404 { zapri(); return }
            }
            napaka = api.userMessage
        } catch {
            napaka = error.userMessage
        }
    }
}
