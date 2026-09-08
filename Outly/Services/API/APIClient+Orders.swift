import Foundation

// Vstopnice: nakup, moje vstopnice, prodaja kluba, skener. Backend index.js:
// POST /events/:id/orders, GET /me/orders, GET /me/tickets, GET /business/sales,
// GET /business/events/:id/tickets, POST /business/tickets/scan.
//
// NACIN: dokler Stripe Connect ni vkljucen, backend dela v TESTNEM nacinu —
// narocilo je takoj "placano", denar se ne premakne, odgovor nosi mode:"test".
// Aplikacija to pokaze (oznaka TEST), da nihce ne misli, da je placal.

// MARK: - Modeli

struct APITicket: Decodable, Identifiable {
    let id: Int
    let orderId: Int
    let eventId: Int
    let serial: String
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

    enum CodingKeys: String, CodingKey {
        case id, serial, status, qr, address, city
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
        serial = try c.decodeIfPresent(String.self, forKey: .serial) ?? ""
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
    }

    var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    var isUsed: Bool { status == "used" }
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

    enum CodingKeys: String, CodingKey {
        case id, quantity, currency, status, tickets
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
    }

    var createdDate: Date? { DateParsing.parseBackendDate(createdAt) }
}

/// Odgovor POST /events/:id/orders.
struct PurchaseResponse: Decodable {
    /// "test" ali "live"
    let mode: String
    let order: APIOrder
    let tickets: [APITicket]
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

        enum CodingKeys: String, CodingKey {
            case id, title, status, capacity
            case startAt = "start_at"
            case posterUrl = "poster_url"
            case ticketPriceCents = "ticket_price_cents"
            case soldCount = "sold_count"
            case grossCents = "gross_cents"
            case ticketsSold = "tickets_sold"
            case checkedIn = "checked_in"
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
        }

        var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    }

    let mode: String
    let feePercent: Double
    let summary: Summary
    let events: [EventSales]
    let recentOrders: [APIOrder]

    enum CodingKeys: String, CodingKey {
        case mode, summary, events
        case feePercent = "fee_percent"
        case recentOrders = "recent_orders"
    }
}

/// Odgovor POST /business/tickets/scan (200 in 4xx imata isto obliko).
struct ScanResult: Decodable {
    /// ok | already_used | invalid | unknown | wrong_club | unpaid | void | refunded
    let result: String
    let message: String
    let usedAt: String?

    enum CodingKeys: String, CodingKey {
        case result, message
        case usedAt = "used_at"
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

// MARK: - Klici

extension APIClient {

    /// POST /events/:id/orders — nakup vstopnic. V testnem nacinu takoj "placano".
    func buyTickets(token: String, eventId: Int, quantity: Int) async throws -> PurchaseResponse {
        let data = try await send(path: "events/\(eventId)/orders", method: "POST", token: token,
                                  json: ["quantity": quantity])
        return try decode(PurchaseResponse.self, from: data)
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

    /// GET /business/sales — prodaja lastnega kluba.
    func fetchBusinessSales(token: String) async throws -> BusinessSales {
        let data = try await send(path: "business/sales", method: "GET", token: token)
        return try decode(BusinessSales.self, from: data)
    }

    /// GET /business/events/:id/tickets — vstopnice enega dogodka (za vrata).
    func fetchEventTickets(token: String, eventId: Int) async throws -> [APITicket] {
        let data = try await send(path: "business/events/\(eventId)/tickets", method: "GET", token: token)
        return try decode([APITicket].self, from: data)
    }

    /// POST /business/tickets/scan — skener. 409/400/404 nosijo isto JSON obliko kot 200,
    /// zato jih tu prevedemo v ScanResult namesto v napako.
    func scanTicket(token: String, qr: String) async throws -> ScanResult {
        do {
            let data = try await send(path: "business/tickets/scan", method: "POST", token: token, json: ["qr": qr])
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
