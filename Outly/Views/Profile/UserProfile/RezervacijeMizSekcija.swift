import SwiftUI

/// Razdelek »Table reservations« v Profile -> Tickets: moje rezervacije VIP miz za placilo z gotovino na VIP vratih
/// (GET /me/table-reservations; backend 23. 10. 2026). Vsaka kartica ima dogodek, datum, mizo, paket, »Pay X at the door« in
/// »Cancel« (DELETE do zacetka dogodka). Prazen seznam, star backend (404) ali napaka branja = razdelka ni (vstopnice delujejo brez njega).
/// Brez lastnega NavigationStack; vstavljen v ScrollView zaslona Tickets.
@MainActor
struct RezervacijeMizSekcija: View {
    @EnvironmentObject private var session: SessionStore

    @State private var rezervacije: [TableReservation] = []
    /// Rezervacija, za katero se caka potrditev preklica.
    @State private var zaPreklic: TableReservation?
    @State private var preklicujemId: Int?
    @State private var napaka: String?

    var body: some View {
        Group {
            if !rezervacije.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Table reservations")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    ForEach(rezervacije) { r in
                        kartica(r)
                    }
                    if let napaka {
                        Text(napaka)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .task { await nalozi() }
        .confirmationDialog("Cancel this reservation?",
                            isPresented: Binding(get: { zaPreklic != nil }, set: { if !$0 { zaPreklic = nil } }),
                            titleVisibility: .visible) {
            Button("Cancel reservation", role: .destructive) {
                if let r = zaPreklic { Task { await preklici(r) } }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The table becomes available to other guests again.")
        }
    }

    private func kartica(_ r: TableReservation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "table.furniture")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.vipZlata)
                .frame(width: 70, height: 70)
                .background(Color.vipZlata.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: r.eventTitle)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text(verbatim: [r.clubName, datum(r)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 6) {
                    VipZnacka(kompakten: true)
                    Text(verbatim: miza(r))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.vipZlata)
                        .lineLimit(1)
                }
                Text(verbatim: r.znesekNaVratih.map { String(localized: "Pay \($0) at the door") } ?? String(localized: "No payment needed"))
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if r.jeMogocPreklic() {
                Button {
                    napaka = nil
                    zaPreklic = r
                } label: {
                    if preklicujemId == r.id {
                        ProgressView().tint(.white)
                    } else {
                        Text("Cancel")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .disabled(preklicujemId != nil)
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.14))
        .cornerRadius(16)
    }

    /// "Table T4 · Jameson 0,7 l"
    private func miza(_ r: TableReservation) -> String {
        var deli: [String] = []
        if !r.tableLabel.isEmpty { deli.append(VipOznaka.miza(r.tableLabel)) }
        if !r.packageName.isEmpty { deli.append(r.packageName) }
        return deli.joined(separator: " · ")
    }

    private func datum(_ r: TableReservation) -> String {
        guard let d = r.startDate else { return "" }
        return "\(DateParsing.shortDate.string(from: d)) \(DateParsing.shortTime.string(from: d))"
    }

    /// Tiho: razdelek je dodatek, napaka branja (brez signala, 5xx) ostane pri tem, kar je ze prikazano.
    private func nalozi() async {
        guard session.isLoggedIn else { return }
        if let sveze = try? await APIClient.shared.fetchMyTableReservations(token: session.token) {
            rezervacije = sveze
        }
    }

    private func preklici(_ r: TableReservation) async {
        napaka = nil
        preklicujemId = r.id
        defer { preklicujemId = nil }
        do {
            try await APIClient.shared.cancelVipReservation(eventId: r.eventId, tableId: r.tableId, token: session.token)
            rezervacije.removeAll { $0.id == r.id }
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api {
                if code == 401 { session.logout(); return }
                // 404: rezervacije ni vec (ze preklicana ali pospravljena): seznam se osvezi.
                if code == 404 { await nalozi(); return }
            }
            napaka = api.userMessage
            await nalozi()
        } catch {
            napaka = error.userMessage
        }
    }
}
