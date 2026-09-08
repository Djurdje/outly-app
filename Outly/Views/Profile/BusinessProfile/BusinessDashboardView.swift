import SwiftUI
import Charts

/// Nadzorna plosca kluba s PRAVIMI podatki (GET /business/sales): prihodek, prodane
/// vstopnice, provizija, izplacilo, prodaja po dogodkih, zadnja narocila, vstop na vratih.
/// Prejsnja razlicica (v _staro/) je kazala izmisljene dolarje.
@MainActor
struct BusinessDashboardView: View {
    let clubName: String?

    @EnvironmentObject private var session: SessionStore

    @State private var sales: BusinessSales?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if let sales, sales.mode == "test" {
                        Text("TEST")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 6)

                if let clubName {
                    Text(clubName)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }

                if isLoading && sales == nil {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 30)
                } else if let errorText {
                    VStack(spacing: 10) {
                        Text(errorText).foregroundColor(.red).font(.subheadline)
                        Button("Try again") { Task { await load() } }.foregroundColor(.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                } else if let sales {
                    statistika(sales)
                    graf(sales)
                    dogodki(sales)
                    narocila(sales)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .refreshable { await load() }
        .onAppear { Task { await load() } }
    }

    // MARK: - Statistika

    private func statistika(_ s: BusinessSales) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                kartica("Total revenue", Denar.evri(s.summary.grossCents), "gross, all events")
                kartica("Tickets sold", "\(s.summary.ticketsSold)", "\(s.summary.orders) orders · \(s.summary.buyers) buyers")
                kartica("Outly fee", Denar.evri(s.summary.feeCents), "\(Int(s.feePercent)) % of gross")
                kartica("Your payout", Denar.evri(s.summary.netCents), "after fee and refunds")
            }
            HStack(spacing: 12) {
                kartica("Last 7 days", Denar.evri(s.summary.gross7dCents), "\(s.summary.tickets7d) tickets")
            }
            if s.mode == "test" {
                Text("Test mode: purchases are simulated, no money moves. Numbers show how the real dashboard will look.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kartica(_ naslov: String, _ vrednost: String, _ opis: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(naslov)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
            Text(vrednost)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(opis)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Graf (Swift Charts, zadnjih 14 dni)

    private func graf(_ s: BusinessSales) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sales, last 14 days")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Spacer()
                Text(Denar.evri(s.salesByDay.reduce(0) { $0 + $1.grossCents }))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.outlyBlue)
            }

            if s.salesByDay.isEmpty {
                Text("No daily data yet.")
                    .font(.subheadline).foregroundColor(.white.opacity(0.6))
            } else {
                Chart(s.salesByDay) { d in
                    BarMark(
                        x: .value("Day", d.date, unit: .day),
                        y: .value("Revenue", Double(d.grossCents) / 100.0)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Color.outlyBlue, Color.outlyBlue.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if let n = v.as(Double.self) {
                                Text(n >= 1000 ? String(format: "%.1fk €", n / 1000) : String(format: "%.0f €", n))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                }
                .frame(height: 170)
                .padding(14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Dogodki

    private func dogodki(_ s: BusinessSales) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event performance")
                .font(.title3.bold())
                .foregroundColor(.white)

            if s.events.isEmpty {
                Text("No events yet. Add one under Events.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(spacing: 10) {
                    ForEach(s.events) { e in
                        NavigationLink {
                            EventTicketsView(event: e)
                        } label: {
                            vrsticaDogodka(e)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func vrsticaDogodka(_ e: BusinessSales.EventSales) -> some View {
        HStack(spacing: 12) {
            if !e.posterUrl.isEmpty, let url = URL(string: e.posterUrl) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Rectangle().opacity(0.12) }
                    .frame(width: 54, height: 54)
                    .clipped()
                    .cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.outlyBlue.opacity(0.25))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "calendar").foregroundColor(.outlyBlue))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text(datum(e.startDate) + (e.status != "published" ? " · \(e.status)" : ""))
                    .font(.caption).foregroundColor(.white.opacity(0.55))
                HStack(spacing: 8) {
                    Text("\(e.ticketsSold)\(e.capacity.map { "/\($0)" } ?? "") sold")
                    Text("·")
                    Text("\(e.checkedIn) in")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Denar.evri(e.grossCents))
                    .font(.headline).foregroundColor(.outlyBlue)
                if let cap = e.capacity, cap > 0 {
                    ProgressView(value: Double(min(e.soldCount, cap)), total: Double(cap))
                        .tint(.outlyBlue)
                        .frame(width: 70)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Narocila

    private func narocila(_ s: BusinessSales) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sales")
                .font(.title3.bold())
                .foregroundColor(.white)

            if s.recentOrders.isEmpty {
                Text("No sales yet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    ForEach(s.recentOrders) { o in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(o.eventTitle)
                                    .font(.subheadline.weight(.semibold)).foregroundColor(.white).lineLimit(1)
                                Text("\(o.buyerUsername.isEmpty ? o.buyerEmail : o.buyerUsername) · \(o.quantity) × \(Denar.evri(o.unitPriceCents, koda: o.currency))")
                                    .font(.caption).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Denar.evri(o.totalCents, koda: o.currency))
                                    .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                                Text(cas(o.createdDate) + (o.status == "paid" ? "" : " · \(o.status)"))
                                    .font(.caption).foregroundColor(.white.opacity(0.45))
                            }
                        }
                        .padding(.vertical, 10)
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func datum(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func cas(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sales = try await APIClient.shared.fetchBusinessSales(token: session.token)
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }
}

/// Vrata: seznam vstopnic dogodka in "Check in" (POST /business/tickets/scan).
/// Kamera za branje QR pride pozneje; tu je isti klic, sprozen z gumbom, da se tok
/// vstopa vidi od konca do konca.
@MainActor
struct EventTicketsView: View {
    let event: BusinessSales.EventSales

    @EnvironmentObject private var session: SessionStore

    @State private var tickets: [APITicket] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var zadnjiRezultat: ScanResult?
    @State private var delujoc: Int?

    private var used: Int { tickets.filter { $0.isUsed }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                HStack(spacing: 14) {
                    stevilka("\(tickets.count)", "sold")
                    stevilka("\(used)", "checked in")
                    stevilka("\(tickets.count - used)", "expected")
                }

                if let r = zadnjiRezultat {
                    HStack(spacing: 10) {
                        Image(systemName: r.result == "ok" ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundColor(r.result == "ok" ? .green : .red)
                        Text(r.message)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background((r.result == "ok" ? Color.green : Color.red).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text("Door check-in")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                if isLoading && tickets.isEmpty {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                } else if let errorText {
                    Text(errorText).foregroundColor(.red).font(.subheadline)
                } else if tickets.isEmpty {
                    Text("No tickets sold for this event yet.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.6))
                } else {
                    VStack(spacing: 8) {
                        ForEach(tickets) { t in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.serial.prefix(8).uppercased())
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text(t.publicRef)
                                        .font(.caption).foregroundColor(.white.opacity(0.5))
                                }
                                Spacer()
                                if t.isUsed {
                                    Text("IN")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.green.opacity(0.15))
                                        .clipShape(Capsule())
                                } else {
                                    Button {
                                        Task { await checkIn(t) }
                                    } label: {
                                        if delujoc == t.id {
                                            ProgressView().tint(.white)
                                        } else {
                                            Text("Check in")
                                                .font(.caption.weight(.bold))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.outlyBlue)
                                    .clipShape(Capsule())
                                    .disabled(delujoc != nil)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                Text("The QR on each ticket is signed by the server; scanning it twice is refused. A camera scanner will replace this list.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { Task { await load() } }
    }

    private func stevilka(_ v: String, _ n: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            Text(n).font(.caption).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tickets = try await APIClient.shared.fetchEventTickets(token: session.token, eventId: event.id)
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }

    private func checkIn(_ t: APITicket) async {
        delujoc = t.id
        defer { delujoc = nil }
        do {
            zadnjiRezultat = try await APIClient.shared.scanTicket(token: session.token, qr: t.qr)
            await load()
        } catch {
            errorText = error.userMessage
        }
    }
}
