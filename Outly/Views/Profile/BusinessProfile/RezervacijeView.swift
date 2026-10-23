import SwiftUI

// Sekcija »Reservations« za vodstvo kluba (owner, manager; 23. 10. 2026): kdo je rezerviral katero VIP mizo na izbranem dogodku.
// Zaslon 1: dogodki kluba (GET /business/events, prihajajoci najprej) s stevilom zasedenih miz (`vip_reservations`).
// Zaslon 2: rezervacije dogodka (GET /business/events/:id/vip): vsaka miza z `booking` (placano v aplikaciji) ali `hold`
// (rezervacija v aplikaciji za placilo na vratih ali vpis po telefonu). Rezervacijo (hold) lahko lastnik/manager sprosti;
// placanih (booking) ne. Vloge uveljavlja streznik; aplikacija samo skrije gumbe.

// MARK: - Zaslon 1: dogodki

@MainActor
struct RezervacijeDogodkiView: View {
    /// Vloga v IZBRANEM klubu (vstopna tocka): lastnik ali manager. Samo ta sme sprostiti rezervacijo; streznik vseeno uveljavi vlogo.
    let smeSprostiti: Bool

    @EnvironmentObject private var session: SessionStore

    @State private var dogodki: [APIEvent] = []
    @State private var nalaga = false
    @State private var napaka: String?
    @State private var nalozeno = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reservations")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                Text("Choose an event to see who reserved which VIP table.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                if nalaga && dogodki.isEmpty {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .padding(.vertical, 30)
                } else if let napaka, dogodki.isEmpty {
                    VStack(spacing: 10) {
                        Text(napaka).foregroundColor(.red).font(.subheadline)
                        Button("Try again") { Task { await nalozi() } }
                            .foregroundColor(.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if dogodki.isEmpty && nalozeno {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.outlyBlue)
                        Text("No events yet")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dogodki) { e in
                            NavigationLink {
                                RezervacijeDogodkaView(event: e, smeSprostiti: smeSprostiti)
                            } label: {
                                vrstica(e)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)   // odmik za spodnjo vrstico (trdo pravilo 6)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await nalozi() }
        .refreshable { await Task { await nalozi() }.value }
    }

    /// Vrstica dogodka: isti slog kot »Event performance« v Dashboardu (plakat, naslov, datum), desno stevilo rezerviranih miz.
    private func vrstica(_ e: APIEvent) -> some View {
        HStack(spacing: 12) {
            if !e.posterUrl.isEmpty, let url = URL(string: e.posterUrl) {
                PlakatDogodkaSlika(url: url, mirenPlaceholder: true)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "calendar").foregroundColor(.white.opacity(0.6)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: e.title)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text(verbatim: podnaslov(e))
                    .font(.caption).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                if e.vipReservations > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "table.furniture")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(e.vipReservations) reserved")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.vipZlata)
                } else {
                    Text("No reservations")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func podnaslov(_ e: APIEvent) -> String {
        var deli: [String] = []
        if let d = e.startDate { deli.append(d.formatted(date: .abbreviated, time: .shortened)) }
        switch e.status {
        case "cancelled": deli.append(String(localized: "Cancelled"))
        case "draft": deli.append(String(localized: "Draft"))
        default: break
        }
        return deli.joined(separator: " · ")
    }

    private func nalozi() async {
        guard !session.token.isEmpty else { return }
        nalaga = true
        defer { nalaga = false; nalozeno = true }
        do {
            let seznam = try await APIClient.shared.fetchMyBusinessEvents(token: session.token)
            dogodki = RezervacijeDogodkiView.uredi(seznam)
            napaka = nil
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            napaka = api.userMessage
        } catch {
            napaka = error.userMessage
        }
    }

    /// Prihajajoci najprej (najblizji na vrhu), nato pretekli (najnovejsi na vrhu); isto kot BusinessEventsView.
    static func uredi(_ seznam: [APIEvent], zdaj: Date = Date()) -> [APIEvent] {
        let prihajajoci = seznam.filter { ($0.startDate ?? .distantPast) >= zdaj }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let pretekli = seznam.filter { ($0.startDate ?? .distantPast) < zdaj }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        return prihajajoci + pretekli
    }
}

// MARK: - Zaslon 2: rezervacije dogodka

@MainActor
struct RezervacijeDogodkaView: View {
    let event: APIEvent
    /// Lastnik/manager v izbranem klubu (ne globalni `session.me`, ki pri vec klubih ne pove vloge v tem klubu).
    let smeSprostiti: Bool

    @EnvironmentObject private var session: SessionStore

    @State private var vip: BusinessEventVip?
    @State private var nalaga = false
    @State private var napaka: String?
    /// Miza, za katero se caka potrditev »Release«; miza, ki se ravno sprosca; napaka zadnjega dejanja.
    @State private var sprostiMizo: VipBusinessTable?
    @State private var delujocaMiza: Int?
    @State private var dejanjeNapaka: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                glava
                    .padding(.top, 6)

                if let dejanjeNapaka {
                    Text(dejanjeNapaka)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }

                if nalaga && vip == nil {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .padding(.vertical, 30)
                } else if let napaka, vip == nil {
                    VStack(spacing: 10) {
                        Text(napaka).foregroundColor(.red).font(.subheadline)
                        Button("Try again") { Task { await nalozi() } }
                            .foregroundColor(.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if let vip {
                    if vip.rezervirane.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "table.furniture")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            Text("No reservations yet")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(vip.rezervirane) { m in
                                kartica(m)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)   // odmik za spodnjo vrstico (trdo pravilo 6)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await nalozi() }
        .refreshable { await Task { await nalozi() }.value }
        .confirmationDialog("Release this reservation?",
                            isPresented: Binding(get: { sprostiMizo != nil }, set: { if !$0 { sprostiMizo = nil } }),
                            titleVisibility: .visible) {
            Button("Release", role: .destructive) {
                if let m = sprostiMizo { Task { await sprosti(m) } }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The table becomes available to other guests again.")
        }
    }

    private var glava: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: event.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
            if let d = event.startDate {
                Text(verbatim: d.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            if let vip, vip.enabled {
                Text(LocalizedStringKey(vip.payment == VipPlacilo.vrata
                                        ? "Tables are reserved in the app and paid in cash at the VIP door."
                                        : "Tables are bought and paid in the app."))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Kartica rezervacije

    private func kartica(_ m: VipBusinessTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: VipOznaka.miza(m.label))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                if m.seats > 0 {
                    Text("Up to \(m.seats) people")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer(minLength: 4)
                znacka(m)
            }

            if let b = m.booking {
                vrsticaKdo(Text(verbatim: "@" + b.buyerUsername), dodatno: nil)
                paket(ime: b.packageName, opis: b.packageDescription)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if let c = b.totalCents, c > 0 {
                            Text(verbatim: Denar.evri(c, koda: vip?.currency ?? "EUR"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        cas(b.createdAt)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: "\(b.checkedIn)/\(b.guests)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(b.guests > 0 && b.checkedIn >= b.guests ? .green : .white)
                        Text("Checked in")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            } else if let h = m.hold {
                vrsticaKdo(Text(verbatim: h.guestName), dodatno: h.prikazanoUporabniskoIme)
                paket(ime: h.packageName, opis: h.packageDescription)
                if let opomba = h.prikazanaOpomba {
                    Text(verbatim: opomba)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let c = h.priceCents, c > 0 {
                            Text(verbatim: Denar.evri(c, koda: vip?.currency ?? "EUR"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        cas(h.createdAt)
                    }
                    Spacer(minLength: 8)
                    if smeSprostiti {
                        Button {
                            dejanjeNapaka = nil
                            sprostiMizo = m
                        } label: {
                            if delujocaMiza == m.id {
                                ProgressView().tint(.white)
                            } else {
                                Text("Release")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .disabled(delujocaMiza != nil)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.vipZlata.opacity(0.35), lineWidth: 1)
        )
    }

    /// Nacin: »Paid in app« (nakup), »Pay at the door« (rezervacija v aplikaciji), »Phone« (vpis kluba).
    @ViewBuilder
    private func znacka(_ m: VipBusinessTable) -> some View {
        if m.booking != nil {
            capsula(ikona: "checkmark.circle.fill", besedilo: Text("Paid in app"), barva: .green)
        } else if let h = m.hold {
            if h.jeIzAplikacije {
                capsula(ikona: "banknote", besedilo: Text("Pay at the door"), barva: .vipZlata)
            } else {
                capsula(ikona: "phone.fill", besedilo: Text("Phone"), barva: .white.opacity(0.75))
            }
        }
    }

    private func capsula(ikona: String, besedilo: Text, barva: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ikona)
                .font(.system(size: 10, weight: .bold))
            besedilo
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(barva)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(barva.opacity(0.14))
        .clipShape(Capsule())
    }

    private func vrsticaKdo(_ glavno: Text, dodatno: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            glavno
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            if let dodatno {
                Text(verbatim: dodatno)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func paket(ime: String, opis: String) -> some View {
        if !ime.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ime)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.vipZlata)
                if !opis.isEmpty {
                    Text(verbatim: opis)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        }
    }

    @ViewBuilder
    private func cas(_ iso: String) -> some View {
        if let d = DateParsing.parseBackendDate(iso) {
            Text(verbatim: d.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: Klici

    private func nalozi() async {
        nalaga = true
        defer { nalaga = false }
        do {
            vip = try await APIClient.shared.fetchBusinessEventVip(eventId: event.id, token: session.token)
            napaka = nil
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            if vip == nil { napaka = api.userMessage }
        } catch {
            // Preklic (nova osvezitev) ni napaka; ob drugih napakah ostane prej nalozeno.
            if vip == nil, !(error is CancellationError) { napaka = error.userMessage }
        }
    }

    private func sprosti(_ m: VipBusinessTable) async {
        sprostiMizo = nil
        delujocaMiza = m.id
        defer { delujocaMiza = nil }
        do {
            vip = try await APIClient.shared.releaseVipTableHold(eventId: event.id, tableId: m.id, token: session.token)
            dejanjeNapaka = nil
        } catch {
            dejanjeNapaka = error.userMessage
            await nalozi()
        }
    }
}
