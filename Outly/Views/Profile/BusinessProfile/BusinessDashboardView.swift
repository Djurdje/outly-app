import SwiftUI
import Charts

/// Nadzorna plosca kluba, prenovljena 25. 9. 2026 (Martin): graf prodaje po Figmi/skici,
/// "Check activity" (kliki na profil/dogodke, sledilci, aktivnost ekipe na vratih) in
/// "Event performance". "Recent sales" je odstranjen (razlog: Martin, 25. 9.) — dekodiranje
/// recent_orders v BusinessSales ostane, ker ga backend se posilja in ne skodi.
@MainActor
struct BusinessDashboardView: View {
    var clubId: Int? = nil
    let clubName: String?

    @EnvironmentObject private var session: SessionStore

    @State private var sales: BusinessSales?
    @State private var activity: BusinessActivity?
    @State private var isLoading = false
    @State private var isChartLoading = false
    @State private var errorText: String?
    @State private var range: SalesRange = .month

    /// Opozorilo, ko kupci ne morejo kupovati. Pri nepopolnih podatkih prodajalca (samo lastnik jih lahko izpolni, backend#94)
    /// kartica vodi v Club info, kjer je razdelek »Seller details«; sicer samo besedilo.
    @ViewBuilder
    private func prodajaNedosegljivaNapotek(_ razlog: RazlogNedosegljivosti) -> some View {
        if razlog == .prodajalecNepopoln, session.me?.isClubOwner == true {
            NavigationLink { ClubInfoView(clubId: clubId) } label: {
                NapotekKartica(besedilo: razlog.besedilo)
            }
            .buttonStyle(.plain)
        } else {
            NapotekKartica(besedilo: razlog.besedilo)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if let sales, sales.jeTestni {
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

                if let sales, sales.jeTestni {
                    Text("Test mode: purchases are simulated, no money moves. Numbers show how the real dashboard will look.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let sales, sales.nacinPlacila.prodajaNedosegljiva {
                    prodajaNedosegljivaNapotek(sales.razlogNedosegljivosti)
                }

                if isLoading && sales == nil {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 40)
                } else if let errorText {
                    VStack(spacing: 10) {
                        Text(errorText).foregroundColor(.red).font(.subheadline)
                        Button("Try again") { Task { await load() } }.foregroundColor(.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                } else if let sales {
                    // Vrstni red (Martin, 26. 9.): stirje okvirji na vrhu, gumbi obdobja nad grafom, graf.
                    povzetek(sales)
                    periodPills
                    graf(sales)

                    if let activity {
                        checkActivity(activity)
                    }

                    dogodki(sales)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
        .refreshable { await Task { await load() }.value }
        .onAppear { Task { await load() } }
    }

    // MARK: - 1) Graf prodaje (kartica, identicna skici Martina 25. 9. 2026)

    private var periodSumCents: Int {
        sales?.series.reduce(0) { $0 + $1.grossCents } ?? 0
    }

    private func graf(_ s: BusinessSales) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sales")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if isChartLoading {
                    // Preklop obdobja: majhen indikator namesto vsote, dokler nov graf ne pride.
                    ProgressView().tint(.outlyBlue).scaleEffect(0.7)
                } else {
                    Text(Denar.evri(periodSumCents))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.outlyBlue)
                }
            }
            .padding(.bottom, 14)

            ZStack {
                if s.series.isEmpty || periodSumCents == 0 {
                    Text("No sales in this period")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    salesChart(s.series)
                        .animation(.snappy, value: s.series.map(\.grossCents))
                }
            }
            .frame(height: 200)
        }
        .padding(.vertical, 8)
        // Brez modre kartice (Martin, 26. 9.: "barva ni povsod, ampak od modre crte dol"): graf lezi
        // na crnem ozadju kot na sliki, modra je samo krivulja in preliv pod njo.
    }

    private func salesChart(_ series: [BusinessSales.SeriesPoint]) -> some View {
        let maxEuros = Double(series.map(\.grossCents).max() ?? 0) / 100.0
        let yValues = yAxisValues(maxEuros: maxEuros)
        let domainTop = yValues.last ?? 1

        return Chart(series) { p in
            let y = Double(p.grossCents) / 100.0

            // Preliv SAMO pod krivuljo: mocnejsi tik pod crto, izgine proti dnu (Martin, 26. 9., slika).
            AreaMark(x: .value("Date", p.date), y: .value("Gross", y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Color.outlyBlue.opacity(0.55), location: 0),
                            .init(color: Color.outlyBlue.opacity(0.18), location: 0.45),
                            .init(color: Color.outlyBlue.opacity(0.0), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Sij okoli krivulje (Chart nima .shadow na LineMark): dve sirsi, prosojni kopiji iste poti.
            LineMark(x: .value("Date", p.date), y: .value("Gross", y))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.outlyBlue.opacity(0.14))
            LineMark(x: .value("Date", p.date), y: .value("Gross", y))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.outlyBlue.opacity(0.35))

            LineMark(x: .value("Date", p.date), y: .value("Gross", y))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.outlyBlue)
        }
        .chartYScale(domain: 0...max(domainTop, 1))
        .chartXAxis {
            AxisMarks(values: xAxisDates(series)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(xAxisLabel(d))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yValues) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v == 0 ? "0 €" : "\(Int(v)) €")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    /// Sest "lepih" vrednosti Y-osi (0, ~max/12, ~max/6, ~max/3, ~max/2, max), zaokrozenih
    /// na 10/50/100, kot na Martinovi skici (0 €, 300 €, 750 €, 1500 €, 3000 €, 7000 €).
    private func yAxisValues(maxEuros: Double) -> [Double] {
        guard maxEuros > 0 else { return [0] }
        let fractions: [Double] = [0, 1.0 / 12, 1.0 / 6, 1.0 / 3, 1.0 / 2, 1.0]
        var values = fractions.map { niceRoundUp(maxEuros * $0) }
        for i in 1..<values.count where values[i] <= values[i - 1] {
            values[i] = values[i - 1] + (values[i - 1] < 100 ? 10 : (values[i - 1] < 1000 ? 50 : 100))
        }
        return values
    }

    private func niceRoundUp(_ v: Double) -> Double {
        guard v > 0 else { return 0 }
        let step: Double = v < 100 ? 10 : (v < 1000 ? 50 : 100)
        return (v / step).rounded(.up) * step
    }

    /// Kateri datumi dobijo oznako na osi X, glede na izbrano obdobje.
    private func xAxisDates(_ series: [BusinessSales.SeriesPoint]) -> [Date] {
        switch range {
        case .year, .week:
            return series.map(\.date)
        case .month:
            return series.enumerated().compactMap { i, p in i % 5 == 0 ? p.date : nil }
        }
    }

    private func xAxisLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Jezik.shared.locale
        switch range {
        case .year:
            f.dateFormat = "MMM"
            return f.string(from: d).lowercased()
        case .month:
            f.dateFormat = "d. M."
            return f.string(from: d)
        case .week:
            f.dateFormat = "EEE"
            return f.string(from: d).lowercased()
        }
    }

    // MARK: - 2) Gumbi obdobja

    private var periodPills: some View {
        HStack(spacing: 10) {
            ForEach(SalesRange.allCases, id: \.self) { r in
                periodPill(r)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func periodPill(_ r: SalesRange) -> some View {
        let izbran = r == range
        return Button {
            guard r != range else { return }
            range = r
            Task { await loadSales() }
        } label: {
            Text(r.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(izbran ? Color.outlyBlue : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(izbran ? Color.clear : Color.outlyBlue.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Povzetek (Martin, 25. 9. 2026: vrni te stevilke — odstranjen je bil samo "Recent sales")

    private func povzetek(_ s: BusinessSales) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            summaryCard("Total revenue", Denar.evri(s.summary.grossCents), "gross, all events")
            summaryCard("Tickets sold", stevilka(s.summary.ticketsSold), "\(s.summary.orders) orders · \(s.summary.buyers) buyers")
            summaryCard("Outly fee", Denar.evri(s.summary.feeCents), "\(Int(s.feePercent)) % of gross")
            summaryCard("Your payout", Denar.evri(s.summary.netCents), "after fee and refunds", modra: true)
        }
    }

    /// Ista kartica kot "Check activity" (radij 16, bela podlaga ~5-6 %); "Your payout" je edina
    /// modra stevilka v tej mrezi (poudarek, kot je narocil Martin).
    private func summaryCard(_ naslov: LocalizedStringKey, _ vrednost: String, _ opis: LocalizedStringKey, modra: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(naslov)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
            Text(vrednost)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(modra ? .outlyBlue : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(opis)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(minHeight: 78, alignment: .topLeading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 3) Check activity

    private let leftColumnHeight: CGFloat = 224

    private func checkActivity(_ a: BusinessActivity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check activity")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    statCard("Clicks on profile", a.clicksProfile, a.clicksProfile7d)
                    statCard("Clicks on events", a.clicksEvents, a.clicksEvents7d)
                    statCard("Followers", a.followersCount, a.followersNew7d)
                }
                .frame(maxWidth: .infinity)

                staffCard(a.staff)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func statCard(_ naslov: LocalizedStringKey, _ vrednost: Int, _ delta7d: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(naslov)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
            Text(stevilka(vrednost))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("+\(stevilka(delta7d)) this week")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(height: (leftColumnHeight - 20) / 3)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func staffCard(_ staff: [BusinessActivity.StaffActivity]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Staff activity")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if staff.isEmpty {
                Spacer()
                Text("No staff yet")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(staff) { m in
                            NavigationLink {
                                StaffScansView(member: m)
                            } label: {
                                staffRow(m)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(height: leftColumnHeight, alignment: .top)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func staffRow(_ m: BusinessActivity.StaffActivity) -> some View {
        HStack(spacing: 8) {
            OutlyAvatarView(avatarUrlString: m.avatarUrl, size: 28)
            Text(m.username)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Text(stevilka(m.scans))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.outlyBlue)
        }
    }

    private func stevilka(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Jezik.shared.locale
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - 4) Event performance (drsljiv seznam, max ~4 vrstice vidne)

    private let eventListHeight: CGFloat = 340

    private func dogodki(_ s: BusinessSales) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Event performance")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Spacer()
                NavigationLink {
                    BusinessEventsView(clubId: clubId, clubName: clubName)
                } label: {
                    Text("View all")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if s.events.isEmpty {
                Text("No events yet. Add one under Events.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                ScrollView(showsIndicators: false) {
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
                .frame(height: eventListHeight)
            }
        }
    }

    private func vrsticaDogodka(_ e: BusinessSales.EventSales) -> some View {
        HStack(spacing: 12) {
            if !e.posterUrl.isEmpty, let url = URL(string: e.posterUrl) {
                OutlyAsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.outlyBlue.opacity(0.25))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "calendar").foregroundColor(.outlyBlue))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text(datum(e.startDate) + (e.status != "published" ? " · \(eventStatusLabel(e.status))" : ""))
                    .font(.caption).foregroundColor(.white.opacity(0.55))
                HStack(spacing: 8) {
                    if let cap = e.capacity {
                        Text("\(e.ticketsSold)/\(cap) sold")
                    } else {
                        Text("\(e.ticketsSold) sold")
                    }
                    Text("·")
                    Text("\(e.checkedIn) in")
                    if e.interestedCount > 0 {
                        Text("·")
                        Label("\(e.interestedCount) interested", systemImage: "hand.thumbsup")
                            .labelStyle(.titleAndIcon)
                    }
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

    /// Napis statusa dogodka za prikaz (vrednost "published"/"draft"/"cancelled" ostane za API).
    private func eventStatusLabel(_ status: String) -> String {
        switch status {
        case "cancelled": return String(localized: "cancelled")
        case "draft": return String(localized: "draft")
        default: return status
        }
    }

    private func datum(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Nalaganje

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sales = try await APIClient.shared.fetchBusinessSales(token: session.token, range: range.apiValue)
            errorText = nil
        } catch {
            errorText = error.userMessage
            return
        }
        // Ce streznik (se) nima /business/activity (star backend), zaslon vseeno pokaze
        // graf in dogodke — samo "Check activity" izgine namesto da podre cel zaslon.
        activity = try? await APIClient.shared.fetchBusinessActivity(token: session.token)
    }

    /// Ob preklopu obdobja osvezimo samo graf (aktivnost in dogodki ostanejo).
    private func loadSales() async {
        isChartLoading = true
        defer { isChartLoading = false }
        do {
            sales = try await APIClient.shared.fetchBusinessSales(token: session.token, range: range.apiValue)
        } catch {
            errorText = error.userMessage
        }
    }
}

/// Obdobje grafa prodaje (GET /business/sales?range=). Vrstni red je isti kot na Martinovi
/// skici: By year, By month, By week — privzeto By month (najbolj uporabno za lastnika).
enum SalesRange: String, CaseIterable {
    case year, month, week

    var apiValue: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .year: return "By year"
        case .month: return "By month"
        case .week: return "By week"
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
    /// VIP rezervacije (backend 025). nil = se ni naloženo ali star streznik brez poti -> razdelka ni.
    @State private var vip: BusinessEventVip?
    /// Rezervacija po telefonu: miza za list "Mark as reserved", miza za potrditev "Release", napaka zadnjega dejanja.
    @State private var rezervirajMizo: VipBusinessTable?
    @State private var sprostiMizo: VipBusinessTable?
    @State private var delujocaMiza: Int?
    @State private var vipNapaka: String?

    /// Rezervacijo po telefonu sme dodati/sprostiti samo lastnik in manager; vratar vidi, spreminjati ne more.
    private var smeUrejatiRezervacije: Bool { session.me?.canManageClub ?? false }

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

                vipRezervacije

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
                                    Text(verbatim: t.serialKratek.isEmpty ? t.publicRef : t.serialKratek)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text(t.publicRef)
                                        .font(.caption).foregroundColor(.white.opacity(0.5))
                                    if t.isVip {
                                        HStack(spacing: 6) {
                                            VipZnacka(kompakten: true)
                                            if let l = t.tableLabel, !l.isEmpty {
                                                Text(verbatim: VipOznaka.miza(l))
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.vipZlata)
                                            }
                                        }
                                    }
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

                Text("The QR on each ticket is signed by the server; scanning it twice is refused. Use Scan tickets in your profile for the camera scanner.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { Task { await load() } }
        .sheet(item: $rezervirajMizo) { m in
            VipHoldSheet(eventId: event.id, miza: m, onDone: { vip = $0 }, onNapaka: { Task { await naloziVip() } })
                .environmentObject(session)
        }
        // presenting: akcija dobi svojo kopijo mize - ne zanasa se na @State, ki ga SwiftUI ob zaprtju lahko pobrise prej.
        .confirmationDialog(
            "Release this reservation?",
            isPresented: Binding(get: { sprostiMizo != nil }, set: { if !$0 { sprostiMizo = nil } }),
            titleVisibility: .visible,
            presenting: sprostiMizo
        ) { m in
            Button("Release", role: .destructive) {
                Task { await sprosti(m) }
            }
            Button("Cancel", role: .cancel) { sprostiMizo = nil }
        } message: { m in
            Text(verbatim: "\(VipOznaka.miza(m.label)) · \(m.hold?.guestName ?? "")")
        }
    }

    private func stevilka(_ v: String, _ n: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            Text(n).font(.caption).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - VIP rezervacije (tloris in cene se urejajo na outly.si/app; rezervacijo po telefonu klub doda tu)

    @ViewBuilder
    private var vipRezervacije: some View {
        if let vip {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.vipZlata)
                    Text("VIP reservations")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                }
                if let vipNapaka {
                    Text(vipNapaka)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
                if !vip.rezervirane.isEmpty {
                    // Rezervacije so resnica tudi, ce je VIP medtem izklopljen ali tloris odstranjen.
                    VStack(spacing: 8) {
                        ForEach(vip.rezervirane) { m in
                            if m.booking != nil {
                                vrsticaRezervacije(m)
                            } else {
                                vrsticaTelefon(m)
                            }
                        }
                    }
                } else if !vip.isSetUp {
                    Text("Set up VIP tables at outly.si/app")
                        .font(.subheadline).foregroundColor(.white.opacity(0.6))
                } else {
                    Text("No reservations yet")
                        .font(.subheadline).foregroundColor(.white.opacity(0.6))
                }

                if smeUrejatiRezervacije && !vip.prosteMize.isEmpty {
                    Text("Available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 6)
                    VStack(spacing: 8) {
                        ForEach(vip.prosteMize) { m in
                            vrsticaProste(m)
                        }
                    }
                }
            }
        }
    }

    /// Prosta miza + "Mark as reserved" (lastnik, manager).
    private func vrsticaProste(_ m: VipBusinessTable) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: VipOznaka.miza(m.label))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                if m.seats > 0 {
                    Text("Up to \(m.seats) people")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 8)
            Button {
                vipNapaka = nil
                rezervirajMizo = m
            } label: {
                Text("Mark as reserved")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Miza, ki jo je klub rezerviral po telefonu: ime gosta, opomba, "Release" (lastnik, manager).
    @ViewBuilder
    private func vrsticaTelefon(_ m: VipBusinessTable) -> some View {
        if let h = m.hold {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.vipZlata)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: VipOznaka.miza(m.label))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("Reserved by phone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.vipZlata)
                    Text(verbatim: h.guestName)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                    if let opomba = h.prikazanaOpomba {
                        Text(verbatim: opomba)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 8)
                if smeUrejatiRezervacije {
                    Button {
                        vipNapaka = nil
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
                    .disabled(delujocaMiza != nil)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.vipZlata.opacity(0.35), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func vrsticaRezervacije(_ m: VipBusinessTable) -> some View {
        if let b = m.booking {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: VipOznaka.miza(m.label))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(verbatim: b.buyerUsername)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                    if !b.packageName.isEmpty {
                        Text(verbatim: b.packageName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.vipZlata)
                    }
                    if !b.packageDescription.isEmpty {
                        Text(verbatim: b.packageDescription)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(b.checkedIn)/\(b.guests)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(b.guests > 0 && b.checkedIn >= b.guests ? .green : .white)
                    Text("Checked in")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.vipZlata.opacity(0.35), lineWidth: 1)
            )
        }
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
        await naloziVip()
    }

    /// Tiho: starejsi streznik poti nima (404) in VIP je dodatek - seznam vstopnic ne sme zaradi tega odpovedati.
    private func naloziVip() async {
        do {
            vip = try await APIClient.shared.fetchBusinessEventVip(eventId: event.id, token: session.token)
        } catch {
            vip = nil
        }
    }

    private func sprosti(_ m: VipBusinessTable) async {
        sprostiMizo = nil
        delujocaMiza = m.id
        defer { delujocaMiza = nil }
        do {
            vip = try await APIClient.shared.releaseVipTableHold(eventId: event.id, tableId: m.id, token: session.token)
            vipNapaka = nil
        } catch {
            vipNapaka = error.userMessage
            await naloziVip()
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
