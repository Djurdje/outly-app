import Foundation

// Vstopnice: nakup, moje vstopnice, prodaja kluba, skener. Backend index.js:
// POST /events/:id/orders, GET /me/orders, GET /me/tickets, GET /business/sales,
// GET /business/events/:id/tickets, POST /business/tickets/scan.
//
// NACIN: dokler Stripe Connect ni vkljucen, backend dela v TESTNEM nacinu —
// narocilo je takoj "placano", denar se ne premakne, odgovor nosi mode:"test".
// Aplikacija to pokaze (oznaka TEST), da nihce ne misli, da je placal.

// MARK: - Modeli

struct APITicket: Codable, Identifiable {
    let id: Int
    let orderId: Int
    let eventId: Int
    /// Serial vstopnice. Backend ga PRENESENI vstopnici (transferred, pri kupcu v /me/orders) ne vrne (null ali brez kljuca):
    /// nov serial pripada prejemniku. Nikoli ga ne kazi brez preverbe — glej `serialKratek`, `jePoslanaDalje`.
    let serial: String?
    /// "valid" | "used" | "void" | "refunded"
    let status: String
    let usedAt: String?
    let createdAt: String
    /// Podpisana vsebina kode QR (base64url.podpis). Prikaze se kot QR.
    let qr: String

    // Samo pri GET /me/tickets (spojeno z dogodkom in klubom); sicer prazno.
    let publicRef: String
    let eventTitle: String
    let startAt: String
    let endAt: String?
    let posterUrl: String
    let minAge: Int
    let clubId: Int
    let clubName: String
    let address: String
    let city: String
    let logoUrl: String

    // Prenos prijatelju (008). transferred = vstopnico sem prejel (ne kupil);
    // transferable = veljavna in dogodek se ni zacel; holderUsername = trenutni imetnik.
    // Kupcu se NIKOLI ne kaze e-naslov prejemnika (osebni podatek): backend polja `holder_email` ne bo vec vracal,
    // star backend ga se poslje — model ga zato ne dekodira, kaze se samo holderUsername.
    let transferable: Bool
    let transferred: Bool
    let holderUsername: String
    let buyerUsername: String

    // VIP miza (backend 025): vstopnica, ki pripada rezervirani mizi. Star backend -> false / nil.
    let isVip: Bool
    let tableLabel: String?
    let tableSeats: Int?
    let packageName: String?
    let packageDescription: String?

    // Guest lista (backend 8. 10. 2026): vstopnica gostitelja ali povabljenega prijatelja (narocilo z `guest_list_id`).
    // Star backend polj nima -> false / nil. Taka vstopnica se ne prenasa (POST /tickets/:id/transfer -> 409).
    let isGuestList: Bool
    /// Uporabnisko ime gostitelja liste; pri gostiteljevi vstopnici je to on sam (glej `povabilGostitelj`).
    let guestListHostUsername: String?

    /// Kupec je pri banki sprozil spor (chargeback) in je odprt ali izgubljen (backend 13. 10. 2026, outly-backend#232): `status` ostane
    /// `valid`, a vstopnica NE velja (skener jo zavrne). Star backend polja nima -> false.
    let paymentDisputed: Bool

    // Encodable (sintetiziran iz CodingKeys) samo za shranjen seznam na telefonu (VstopniceShramba), ne za klice na streznik.
    enum CodingKeys: String, CodingKey {
        case id, serial, status, qr, address, city, transferable, transferred
        case isVip = "is_vip"
        case tableLabel = "table_label"
        case tableSeats = "table_seats"
        case packageName = "package_name"
        case packageDescription = "package_description"
        case isGuestList = "is_guest_list"
        case guestListHostUsername = "guest_list_host_username"
        case paymentDisputed = "payment_disputed"
        case holderUsername = "holder_username"
        case buyerUsername = "buyer_username"
        case orderId = "order_id"
        case eventId = "event_id"
        case usedAt = "used_at"
        case createdAt = "created_at"
        case publicRef = "public_ref"
        case eventTitle = "event_title"
        case startAt = "start_at"
        case endAt = "end_at"
        case posterUrl = "poster_url"
        case minAge = "min_age"
        case clubId = "club_id"
        case clubName = "club_name"
        case logoUrl = "logo_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        orderId = try c.decodeIfPresent(Int.self, forKey: .orderId) ?? 0
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        serial = (try? c.decodeIfPresent(String.self, forKey: .serial)) ?? nil   // null / manjka / napacen tip -> nil
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "valid"
        usedAt = try c.decodeIfPresent(String.self, forKey: .usedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        qr = try c.decodeIfPresent(String.self, forKey: .qr) ?? ""
        publicRef = try c.decodeIfPresent(String.self, forKey: .publicRef) ?? ""
        eventTitle = try c.decodeIfPresent(String.self, forKey: .eventTitle) ?? ""
        startAt = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
        endAt = try c.decodeIfPresent(String.self, forKey: .endAt)
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl) ?? ""
        minAge = try c.decodeIfPresent(Int.self, forKey: .minAge) ?? 18
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl) ?? ""
        transferable = try c.decodeIfPresent(Bool.self, forKey: .transferable) ?? false
        transferred = try c.decodeIfPresent(Bool.self, forKey: .transferred) ?? false
        holderUsername = try c.decodeIfPresent(String.self, forKey: .holderUsername) ?? ""
        buyerUsername = try c.decodeIfPresent(String.self, forKey: .buyerUsername) ?? ""
        isVip = (try? c.decodeIfPresent(Bool.self, forKey: .isVip)) ?? false
        tableLabel = (try? c.decodeIfPresent(String.self, forKey: .tableLabel)) ?? nil
        tableSeats = (try? c.decodeIfPresent(Int.self, forKey: .tableSeats)) ?? nil
        packageName = (try? c.decodeIfPresent(String.self, forKey: .packageName)) ?? nil
        packageDescription = (try? c.decodeIfPresent(String.self, forKey: .packageDescription)) ?? nil
        isGuestList = (try? c.decodeIfPresent(Bool.self, forKey: .isGuestList)) ?? false
        guestListHostUsername = (try? c.decodeIfPresent(String.self, forKey: .guestListHostUsername)) ?? nil
        paymentDisputed = (try? c.decodeIfPresent(Bool.self, forKey: .paymentDisputed)) ?? false
    }

    var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    var isUsed: Bool { status == "used" }
    /// Placilo je v sporu, vstopnica je sicer `valid` in dogodek ni mimo: kartica jo kaze kot neveljavno (rdece), QR je zatemnjen.
    /// Spor prevlada SAMO pri `valid`: used / refunded / void ostanejo, kar so, pri preteklem dogodku ostane EXPIRED.
    var jeVSporu: Bool { paymentDisputed && status == "valid" && !isPast }

    /// "Invited by @host" samo pri vstopnici guest liste, ki pripada PRIJATELJU: gostitelj na svoji vstopnici vidi samo oznako
    /// »Guest list« (backend mu vrne njegovo ime kot gostitelja). `jaz` = moje uporabnisko ime.
    func povabilGostitelj(jaz: String?) -> String? {
        guard isGuestList, let host = guestListHostUsername, !host.isEmpty else { return nil }
        if let jaz, host.caseInsensitiveCompare(jaz) == .orderedSame { return nil }
        return host
    }

    /// Samo za vstopnice NAROCILA (GET /me/orders, POST …/orders = kupcev pogled): kupec je vstopnico poslal prijatelju,
    /// zato nima ne QR ne seriala (backend ju zadrzi za prejemnika). V GET /me/tickets (TicketsView) `transferred`
    /// pomeni "vstopnico sem PREJEL" — tam ta lastnost ni v uporabi, prejemnik svoj serial in QR vidi.
    var jePoslanaDalje: Bool { transferred && (qr.isEmpty || serial == nil) }
    /// Prvih 8 znakov seriala z velikimi crkami; prazen niz, ce serial ni na voljo.
    var serialKratek: String { String((serial ?? "").prefix(8)).uppercased() }
    /// Cel serial z velikimi crkami; prazen niz, ce ga ni.
    var serialVelik: String { (serial ?? "").uppercased() }
    /// Napis namesto QR za poslano vstopnico: "Transferred to @ana" (ali "Transferred", ce username ni znan).
    var poslanaNapis: String {
        holderUsername.isEmpty
            ? String(localized: "Transferred")
            : String(localized: "Transferred to @\(holderUsername)")
    }
    /// Napis na kartici: VALID samo za veljavno vstopnico prihodnjega dogodka;
    /// sicer USED / REFUNDED / VOID / EXPIRED (prej je bilo vse razen used "VALID").
    var statusLabel: String {
        if isUsed { return String(localized: "USED") }
        if jeVSporu { return String(localized: "PAYMENT DISPUTED") }
        switch status {
        case "valid": return isPast ? String(localized: "EXPIRED") : String(localized: "VALID")
        case "refunded": return String(localized: "REFUNDED")
        case "void": return String(localized: "VOID")
        default: return status.uppercased()   // neznano stanje iz prihodnjega backenda: surovo, a ne podre zaslona
        }
    }
    /// Veljavna vstopnica prihodnjega dogodka. Za barvo napisa: `statusLabel` je preveden, zato ga ne smemo primerjati z angleskim nizom.
    var jeVeljavna: Bool { !isUsed && status == "valid" && !isPast && !paymentDisputed }   // vstopnica v sporu ni veljavna (rdeca, ne modra)
    var isPast: Bool { (startDate ?? .distantFuture) < Date().addingTimeInterval(-8 * 3600) }
}

struct APIOrder: Decodable, Identifiable {
    let id: Int
    let publicRef: String
    let eventId: Int
    let clubId: Int
    let quantity: Int
    let unitPriceCents: Int
    let totalCents: Int
    let currency: String
    let applicationFeeCents: Int
    /// pending | paid | failed | cancelled | refunded | partially_refunded
    let status: String
    let buyerEmail: String
    let createdAt: String
    let paidAt: String?
    let isTest: Bool
    let eventTitle: String
    let startAt: String
    let posterUrl: String
    let clubName: String
    let buyerUsername: String
    let tickets: [APITicket]
    /// Stripe Checkout (backend 4. 10. 2026): samo pri `pending` narocilu klubov s povezanim Stripom (GET /me/orders).
    /// Star backend ga ne posilja -> nil. Pred odpiranjem OBVEZNO prek `StripePlacilo.varenUrl`.
    let checkoutUrl: String?
    /// Stripova seja (30 min) je potekla, narocilo je se `pending` (backend#203): `checkoutUrl` je takrat nil in povezave NE odpiramo.
    /// Backend narocilo takoj preveri pri Stripu, zato je po osvezitvi `paid` ali `cancelled`. Star backend polja nima -> false.
    let checkoutExpired: Bool
    /// Kupec je placal, banka (SEPA ipd.) pa denarja se ni potrdila (backend#203, krog 2): narocilo je `pending`, `checkoutUrl` nil,
    /// `checkoutExpired` false, `tickets` prazni. Povezave NE odpiramo, kupca ne pustimo placati znova. Star backend -> false.
    let paymentProcessing: Bool

    // VIP miza (backend 025): narocilo mize (quantity = 1, vstopnic = table_seats). Star backend -> false / nil.
    let isVip: Bool
    let tableId: Int?
    let tableLabel: String?
    let tableSeats: Int?
    let packageName: String?
    let packageDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, quantity, currency, status, tickets
        case isVip = "is_vip"
        case tableId = "table_id"
        case tableLabel = "table_label"
        case tableSeats = "table_seats"
        case packageName = "package_name"
        case packageDescription = "package_description"
        case publicRef = "public_ref"
        case eventId = "event_id"
        case clubId = "club_id"
        case unitPriceCents = "unit_price_cents"
        case totalCents = "total_cents"
        case applicationFeeCents = "application_fee_cents"
        case buyerEmail = "buyer_email"
        case createdAt = "created_at"
        case paidAt = "paid_at"
        case isTest = "is_test"
        case eventTitle = "event_title"
        case startAt = "start_at"
        case posterUrl = "poster_url"
        case clubName = "club_name"
        case buyerUsername = "buyer_username"
        case checkoutUrl = "checkout_url"
        case checkoutExpired = "checkout_expired"
        case paymentProcessing = "payment_processing"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        publicRef = try c.decodeIfPresent(String.self, forKey: .publicRef) ?? ""
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 0
        unitPriceCents = try c.decodeIfPresent(Int.self, forKey: .unitPriceCents) ?? 0
        totalCents = try c.decodeIfPresent(Int.self, forKey: .totalCents) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        applicationFeeCents = try c.decodeIfPresent(Int.self, forKey: .applicationFeeCents) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        buyerEmail = try c.decodeIfPresent(String.self, forKey: .buyerEmail) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        paidAt = try c.decodeIfPresent(String.self, forKey: .paidAt)
        isTest = try c.decodeIfPresent(Bool.self, forKey: .isTest) ?? false
        eventTitle = try c.decodeIfPresent(String.self, forKey: .eventTitle) ?? ""
        startAt = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl) ?? ""
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        buyerUsername = try c.decodeIfPresent(String.self, forKey: .buyerUsername) ?? ""
        tickets = try c.decodeIfPresent([APITicket].self, forKey: .tickets) ?? []
        checkoutUrl = (try? c.decodeIfPresent(String.self, forKey: .checkoutUrl)) ?? nil   // null / manjka / napacen tip -> nil
        checkoutExpired = (try? c.decodeIfPresent(Bool.self, forKey: .checkoutExpired)) ?? false
        paymentProcessing = (try? c.decodeIfPresent(Bool.self, forKey: .paymentProcessing)) ?? false
        isVip = (try? c.decodeIfPresent(Bool.self, forKey: .isVip)) ?? false
        tableId = (try? c.decodeIfPresent(Int.self, forKey: .tableId)) ?? nil
        tableLabel = (try? c.decodeIfPresent(String.self, forKey: .tableLabel)) ?? nil
        tableSeats = (try? c.decodeIfPresent(Int.self, forKey: .tableSeats)) ?? nil
        packageName = (try? c.decodeIfPresent(String.self, forKey: .packageName)) ?? nil
        packageDescription = (try? c.decodeIfPresent(String.self, forKey: .packageDescription)) ?? nil
    }

    var createdDate: Date? { DateParsing.parseBackendDate(createdAt) }
}

/// Odgovor POST /events/:id/orders in POST /events/:id/tables/:tableId/orders.
struct PurchaseResponse: Decodable {
    /// "test" (klub brez Stripa: takoj placano, vstopnice polne) ali "stripe" (klub s Stripe Connect: narocilo `pending`,
    /// `tickets` prazen, `checkoutUrl` = gostovana Stripe stran; vstopnice nastanejo sele po webhooku).
    let mode: String
    let order: APIOrder
    let tickets: [APITicket]
    /// Stripe Checkout URL (samo `mode == "stripe"`). Star backend ga ne pošilja -> nil. Pred odpiranjem OBVEZNO
    /// prek `StripePlacilo.varenUrl`.
    let checkoutUrl: String?

    enum CodingKeys: String, CodingKey {
        case mode, order, tickets
        case checkoutUrl = "checkout_url"
    }

    init(mode: String, order: APIOrder, tickets: [APITicket], checkoutUrl: String? = nil) {
        self.mode = mode
        self.order = order
        self.tickets = tickets
        self.checkoutUrl = checkoutUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(String.self, forKey: .mode)
        order = try c.decode(APIOrder.self, forKey: .order)
        tickets = try c.decodeIfPresent([APITicket].self, forKey: .tickets) ?? []
        checkoutUrl = (try? c.decodeIfPresent(String.self, forKey: .checkoutUrl)) ?? order.checkoutUrl
    }

    /// Narocilo caka placilo pri Stripu (vstopnic se ni): zaslona »You're in!« z 0 vstopnicami NE kazemo. `mode == "stripe"` ali
    /// vsak drug nacin (ne "test") s `pending` narocilom; samo dokler je `tickets` prazen, zato ponovitev nakupa po placilu
    /// (isti kljuc, narocilo ze placano z vstopnicami) gre naravnost na uspesni zaslon.
    var cakaPlacilo: Bool {
        guard mode != "test", tickets.isEmpty else { return false }
        return mode == "stripe" || order.status == "pending"
    }
}

/// GET /business/sales
struct BusinessSales: Decodable {
    struct Summary: Decodable {
        let grossCents: Int
        let feeCents: Int
        let netCents: Int
        let ticketsSold: Int
        let orders: Int
        let buyers: Int
        let gross7dCents: Int
        let tickets7d: Int

        enum CodingKeys: String, CodingKey {
            case orders, buyers
            case grossCents = "gross_cents"
            case feeCents = "fee_cents"
            case netCents = "net_cents"
            case ticketsSold = "tickets_sold"
            case gross7dCents = "gross_7d_cents"
            case tickets7d = "tickets_7d"
        }
    }

    struct EventSales: Decodable, Identifiable {
        let id: Int
        let title: String
        let startAt: String
        let posterUrl: String
        let status: String
        let ticketPriceCents: Int?
        let capacity: Int?
        let soldCount: Int
        let grossCents: Int
        let ticketsSold: Int
        let checkedIn: Int
        /// Koliko oseb je oznacilo "interested" (backend, 25. 9. 2026); star streznik ga se ne vrne -> 0.
        let interestedCount: Int

        enum CodingKeys: String, CodingKey {
            case id, title, status, capacity
            case startAt = "start_at"
            case posterUrl = "poster_url"
            case ticketPriceCents = "ticket_price_cents"
            case soldCount = "sold_count"
            case grossCents = "gross_cents"
            case ticketsSold = "tickets_sold"
            case checkedIn = "checked_in"
            case interestedCount = "interested_count"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            startAt = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
            posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl) ?? ""
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "published"
            ticketPriceCents = try c.decodeIfPresent(Int.self, forKey: .ticketPriceCents)
            capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
            soldCount = try c.decodeIfPresent(Int.self, forKey: .soldCount) ?? 0
            grossCents = try c.decodeIfPresent(Int.self, forKey: .grossCents) ?? 0
            ticketsSold = try c.decodeIfPresent(Int.self, forKey: .ticketsSold) ?? 0
            checkedIn = try c.decodeIfPresent(Int.self, forKey: .checkedIn) ?? 0
            interestedCount = try c.decodeIfPresent(Int.self, forKey: .interestedCount) ?? 0
        }

        var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    }

    struct DaySales: Decodable, Identifiable {
        let day: String
        let grossCents: Int
        let tickets: Int
        var id: String { day }

        enum CodingKeys: String, CodingKey {
            case day, tickets
            case grossCents = "gross_cents"
        }

        var date: Date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: day) ?? Date()
        }
    }

    /// En kos grafa prodaje (GET /business/sales?range=), dodano 25. 9. 2026 za prenovljeno
    /// nadzorno plosco. bucket je "YYYY-MM-DD" (week/month) ali "YYYY-MM" (year); loci ju stevilo znakov.
    struct SeriesPoint: Decodable, Identifiable {
        let bucket: String
        let grossCents: Int
        let tickets: Int
        var id: String { bucket }

        enum CodingKeys: String, CodingKey {
            case bucket, tickets
            case grossCents = "gross_cents"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
            grossCents = try c.decodeIfPresent(Int.self, forKey: .grossCents) ?? 0
            tickets = try c.decodeIfPresent(Int.self, forKey: .tickets) ?? 0
        }

        /// Mesecni kos ima obliko "YYYY-MM" (7 znakov), dnevni "YYYY-MM-DD" (10 znakov).
        var isMonthly: Bool { bucket.count == 7 }

        var date: Date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = isMonthly ? "yyyy-MM" : "yyyy-MM-dd"
            return f.date(from: bucket) ?? Date()
        }
    }

    let mode: String
    let feePercent: Double
    let summary: Summary
    let events: [EventSales]
    let recentOrders: [APIOrder]
    /// Zadnjih 14 dni; starejsi streznik ga ne vraca -> prazno.
    let salesByDay: [DaySales]
    /// Graf glede na izbrano obdobje (week/month/year); starejsi streznik ga se ne vraca -> prazno,
    /// zaslon takrat pade nazaj na salesByDay.
    let series: [SeriesPoint]
    /// Nacin placila TEGA kluba (backend#203): "test" | "stripe" | "unavailable"; nil = star backend -> napis temelji na `mode`.
    /// `mode` je globalen in se ne spremeni.
    let paymentMode: String?
    /// Zakaj je `paymentMode == "unavailable"` (backend#221): "seller_incomplete" | "stripe_not_ready" | "payments_not_configured" | "demo_club" (backend#243);
    /// nil = star backend, null ali polje manjka -> obstojece besedilo (glej `RazlogNedosegljivosti`).
    let paymentUnavailableReason: String?

    enum CodingKeys: String, CodingKey {
        case mode, summary, events, series
        case paymentMode = "payment_mode"
        case paymentUnavailableReason = "payment_unavailable_reason"
        case feePercent = "fee_percent"
        case recentOrders = "recent_orders"
        case salesByDay = "sales_by_day"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "test"
        feePercent = try c.decodeIfPresent(Double.self, forKey: .feePercent) ?? 10
        summary = try c.decode(Summary.self, forKey: .summary)
        events = try c.decodeIfPresent([EventSales].self, forKey: .events) ?? []
        recentOrders = try c.decodeIfPresent([APIOrder].self, forKey: .recentOrders) ?? []
        salesByDay = try c.decodeIfPresent([DaySales].self, forKey: .salesByDay) ?? []
        series = try c.decodeIfPresent([SeriesPoint].self, forKey: .series) ?? []
        paymentMode = (try? c.decodeIfPresent(String.self, forKey: .paymentMode)) ?? nil
        paymentUnavailableReason = (try? c.decodeIfPresent(String.self, forKey: .paymentUnavailableReason)) ?? nil
    }

    /// Dashboard kaze TEST samo, ko je placilo TEGA kluba testno (`payment_mode`); star backend: globalni `mode`.
    var jeTestni: Bool { NacinPlacila.dashboardTestni(paymentMode: paymentMode, mode: mode) }

    /// Nacin placila tega kluba; nil iz starega backenda -> `.neznan` (opozorila ni).
    var nacinPlacila: NacinPlacila { NacinPlacila(paymentMode) }

    /// Razlog, zakaj kupci ne morejo kupovati (samo ko je `nacinPlacila == .nedosegljivo`; sicer ni pomemben).
    var razlogNedosegljivosti: RazlogNedosegljivosti { RazlogNedosegljivosti(paymentUnavailableReason) }
}

/// Odgovor POST /business/tickets/scan (200 in 4xx imata isto obliko).
struct ScanResult: Decodable {
    /// ok | already_used | invalid | unknown | wrong_club | unpaid | void | refunded | event_cancelled | not_today | payment_disputed
    /// (zadnji: HTTP 409, vstopnica s sporom pri banki; backend#232).
    let result: String
    let message: String
    let usedAt: String?
    /// Podatki vstopnice (backend 025, tudi pri already_used); nil pri starem strezniku ali neveljavni kodi.
    /// Skener iz njih pokaze VIP / mizo / paket.
    let ticket: ScanTicketInfo?

    enum CodingKeys: String, CodingKey {
        case result, message, ticket
        case usedAt = "used_at"
    }

    init(result: String, message: String, usedAt: String?, ticket: ScanTicketInfo? = nil) {
        self.result = result
        self.message = message
        self.usedAt = usedAt
        self.ticket = ticket
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result = try c.decode(String.self, forKey: .result)
        message = try c.decode(String.self, forKey: .message)
        usedAt = try c.decodeIfPresent(String.self, forKey: .usedAt)
        // Napaka v neobveznem delu ne sme zavreci rezultata skena (vstop gosta je pomembnejsi).
        ticket = (try? c.decodeIfPresent(ScanTicketInfo.self, forKey: .ticket)) ?? nil
    }
}

/// Del vstopnice v odgovoru skena: samo tisto, kar skener prikaze vratarju.
struct ScanTicketInfo: Decodable {
    let isVip: Bool
    let tableLabel: String?
    let tableSeats: Int?
    let packageName: String?
    /// Guest lista (backend 8. 10. 2026): skener pokaze oznako »Guest list · @gostitelj«. Star backend -> false / nil.
    let isGuestList: Bool
    let guestListHostUsername: String?
    /// Placilo v sporu (backend#232). Star backend -> false.
    let paymentDisputed: Bool

    enum CodingKeys: String, CodingKey {
        case isVip = "is_vip"
        case tableLabel = "table_label"
        case tableSeats = "table_seats"
        case packageName = "package_name"
        case isGuestList = "is_guest_list"
        case guestListHostUsername = "guest_list_host_username"
        case paymentDisputed = "payment_disputed"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isGuestList = (try? c.decodeIfPresent(Bool.self, forKey: .isGuestList)) ?? false
        guestListHostUsername = (try? c.decodeIfPresent(String.self, forKey: .guestListHostUsername)) ?? nil
        paymentDisputed = (try? c.decodeIfPresent(Bool.self, forKey: .paymentDisputed)) ?? false
        isVip = (try? c.decodeIfPresent(Bool.self, forKey: .isVip)) ?? false
        tableLabel = (try? c.decodeIfPresent(String.self, forKey: .tableLabel)) ?? nil
        tableSeats = (try? c.decodeIfPresent(Int.self, forKey: .tableSeats)) ?? nil
        packageName = (try? c.decodeIfPresent(String.self, forKey: .packageName)) ?? nil
    }
}

// MARK: - Denar
// Zneski so v centih kot celo stevilo (odlocitev projekta). Prikaz: "12,50 €".
enum Denar {
    static func evri(_ centi: Int, koda: String = "EUR") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = koda
        f.locale = Locale(identifier: "sl_SI")
        return f.string(from: NSNumber(value: Double(centi) / 100.0)) ?? "\(centi / 100),\(String(format: "%02d", centi % 100)) €"
    }
}

struct TransferResponse: Decodable {
    let result: String
    let message: String
}

// MARK: - Klici

extension APIClient {

    /// Glave nakupnih klicev (POST /events/:id/orders in …/tables/:tableId/orders). `X-Outly-Client: ios` pove backendu, da
    /// nakup prihaja iz iOS aplikacije: pri Stripe Checkoutu nastavi success/cancel URL na outly.si/placilo?app=ios, ta stran pa
    /// kupca vrne v aplikacijo (outly://placilo, glej StripePlacilo.PovratniKlic). Star backend glavo spregleda.
    static let nakupneGlave: [String: String] = ["X-Outly-Client": "ios"]

    /// POST /events/:id/orders — nakup vstopnic. V testnem nacinu takoj "placano".
    /// `idempotencyKey` (NakupniKljuc): ponovitev istega nakupa z istim kljucem vrne isto narocilo (201 z istim telesom).
    /// `locale`: jezik Stripe Checkouta (`"sl"` | `"en"`), privzeto jezik APLIKACIJE; star backend polje spregleda.
    func buyTickets(token: String, eventId: Int, quantity: Int, idempotencyKey: String? = nil,
                    locale: String = Jezik.shared.stripeLocale) async throws -> PurchaseResponse {
        let data = try await send(path: "events/\(eventId)/orders", method: "POST", token: token,
                                  json: APIClient.telesoNakupaVstopnic(quantity: quantity, locale: locale),
                                  idempotencyKey: idempotencyKey,
                                  dodatneGlave: APIClient.nakupneGlave)
        return try decode(PurchaseResponse.self, from: data)
    }

    /// Telo POST /events/:id/orders: `quantity` + `locale` (jezik Stripe Checkouta, glej `Jezik.stripeLocale`) + `terms_version`
    /// (razlicica pogojev, ki jo je kupec videl ob gumbu za placilo; backend jo shrani na narocilo, #215; star backend polje spregleda
    /// in ga ne steje v vsebino za idempotenco).
    static func telesoNakupaVstopnic(quantity: Int, locale: String, termsVersion: String = LegalLinks.termsVersion) -> [String: Any] {
        ["quantity": quantity, "locale": locale, "terms_version": termsVersion]
    }

    /// POST /tickets/:id/transfer — posljem vstopnico prijatelju po e-naslovu.
    /// Po uspehu vstopnica ni vec moja; nov QR dobi prejemnik.
    /// `allowGuest` (samo ko `Me.canTransferToGuest`): prijatelj brez Outly racuna dobi vstopnico po e-posti.
    /// `ageConfirmed`: potrditev starosti (kljukica pri dogodku z mejo); streznik jo zahteva za goste (`age_confirmation_required`),
    /// pri prejemniku z racunom brez datuma rojstva jo sprejme namesto njega. Star streznik polje spregleda.
    func transferTicket(token: String, ticketId: Int, email: String,
                        allowGuest: Bool = false, ageConfirmed: Bool = false) async throws -> TransferResponse {
        let data = try await send(path: "tickets/\(ticketId)/transfer", method: "POST", token: token,
                                  json: APIClient.prenosTelo(email: email, allowGuest: allowGuest, ageConfirmed: ageConfirmed))
        return try decode(TransferResponse.self, from: data)
    }

    /// Telo POST /tickets/:id/transfer po e-naslovu: vedno `age_confirmed`, `allow_guest: true` samo pri `allowGuest`.
    static func prenosTelo(email: String, allowGuest: Bool, ageConfirmed: Bool) -> [String: Any] {
        var telo: [String: Any] = ["email": email, "age_confirmed": ageConfirmed]
        if allowGuest { telo["allow_guest"] = true }
        return telo
    }

    /// GET /me/tickets — moje vstopnice, prihajajoce najprej.
    func fetchMyTickets(token: String) async throws -> [APITicket] {
        let data = try await send(path: "me/tickets", method: "GET", token: token)
        return try decode([APITicket].self, from: data)
    }

    /// GET /me/orders — moja narocila z vstopnicami.
    func fetchMyOrders(token: String) async throws -> [APIOrder] {
        let data = try await send(path: "me/orders", method: "GET", token: token)
        return try decode([APIOrder].self, from: data)
    }

    /// GET /business/sales — prodaja lastnega kluba. `range` doloca graf (week/month/year, 25. 9. 2026);
    /// starejsi streznik ga ignorira in vrne isti odgovor kot prej (series prazen -> pade nazaj na salesByDay).
    func fetchBusinessSales(token: String, range: String = "month") async throws -> BusinessSales {
        let data = try await send(path: "business/sales", method: "GET", token: token,
                                  query: [URLQueryItem(name: "range", value: range)])
        return try decode(BusinessSales.self, from: data)
    }

    /// GET /business/events/:id/tickets — vstopnice enega dogodka (za vrata).
    func fetchEventTickets(token: String, eventId: Int) async throws -> [APITicket] {
        let data = try await send(path: "business/events/\(eventId)/tickets", method: "GET", token: token)
        return try decode([APITicket].self, from: data)
    }

    /// POST /business/tickets/scan — skener. 409/400/404 nosijo isto JSON obliko kot 200,
    /// zato jih tu prevedemo v ScanResult namesto v napako.
    /// `clubId` (izrecen klub) in `timeout` (kratek rok na vratih) sta neobvezna; brez njiju velja kot doslej.
    func scanTicket(token: String, qr: String, clubId: Int? = nil, timeout: TimeInterval? = nil) async throws -> ScanResult {
        do {
            let data = try await send(path: "business/tickets/scan", method: "POST", token: token, json: ["qr": qr],
                                      clubId: clubId, timeout: timeout)
            return try decode(ScanResult.self, from: data)
        } catch let api as APIError {
            if case let .requestFailed(code, raw) = api, [400, 403, 404, 409].contains(code),
               let d = raw.data(using: .utf8), let r = try? JSONDecoder().decode(ScanResult.self, from: d) {
                return r
            }
            throw api
        }
    }
}
