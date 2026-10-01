import Foundation

// VIP mize (backend migracija 025, 1. 10. 2026). Poti:
// GET /events/:id/vip (javno), POST /events/:id/tables/:tableId/orders (zeton),
// GET /business/events/:id/vip (vse vloge v klubu; glava X-Outly-Club doda send()).
// Urejevalnika tlorisa na iOS ni (samo splet, outly.si/app), zato PUT poti tu ni.
//
// Vsa polja so s privzeto vrednostjo ali opcijska: star backend (brez 025) ne sme podreti dekodiranja.

// MARK: - Tloris

/// Orientacijski element tlorisa (bar, oder, DJ, plesisce, vhod, WC, napis, stena).
/// Koordinate so v celicah mreze; izris: celica = sirina platna / `VipPlan.width`.
struct VipElement: Decodable {
    /// bar | stage | dj | dancefloor | entrance | wc | label | wall (neznan tip se izrise kot navaden element)
    let type: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
    /// Prazen = privzeti prevedeni naziv tipa (glej `VipOznaka.privzetNaziv`).
    let label: String

    enum CodingKeys: String, CodingKey { case type, x, y, w, h, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        x = try c.decodeIfPresent(Int.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Int.self, forKey: .y) ?? 0
        w = try c.decodeIfPresent(Int.self, forKey: .w) ?? 1
        h = try c.decodeIfPresent(Int.self, forKey: .h) ?? 1
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

struct VipPlan: Decodable {
    /// Mreza celic (8..40); os y gre navzdol.
    let width: Int
    let height: Int
    let elements: [VipElement]

    enum CodingKeys: String, CodingKey { case width, height, elements }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sirina = try c.decodeIfPresent(Int.self, forKey: .width) ?? 24
        let visina = try c.decodeIfPresent(Int.self, forKey: .height) ?? 16
        width = max(1, sirina)
        height = max(1, visina)
        elements = try c.decodeIfPresent([VipElement].self, forKey: .elements) ?? []
    }
}

// MARK: - Mize in paketi

/// Miza na tlorisu (kupec). `available == false` = prodana.
struct VipTable: Decodable, Identifiable {
    let id: Int
    let label: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
    /// round | rect
    let shape: String
    let seats: Int
    /// Efektivna cena za ta dogodek (v centih).
    let priceCents: Int
    let available: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, x, y, w, h, shape, seats, available
        case priceCents = "price_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        x = try c.decodeIfPresent(Int.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Int.self, forKey: .y) ?? 0
        w = try c.decodeIfPresent(Int.self, forKey: .w) ?? 1
        h = try c.decodeIfPresent(Int.self, forKey: .h) ?? 1
        shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? "rect"
        seats = try c.decodeIfPresent(Int.self, forKey: .seats) ?? 0
        priceCents = try c.decodeIfPresent(Int.self, forKey: .priceCents) ?? 0
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

/// Bottle paket, vstet v ceno mize.
struct VipPackage: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String

    enum CodingKeys: String, CodingKey { case id, name, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

// MARK: - GET /events/:id/vip

struct EventVip: Decodable {
    let eventId: Int
    let enabled: Bool
    /// false = dogodek se je zacel/koncal ali je prodaja zaprta (mize se vidijo, kupiti se ne da).
    let onSale: Bool
    let currency: String
    let plan: VipPlan?
    let tables: [VipTable]
    let packages: [VipPackage]

    enum CodingKeys: String, CodingKey {
        case enabled, currency, plan, tables, packages
        case eventId = "event_id"
        case onSale = "on_sale"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        onSale = try c.decodeIfPresent(Bool.self, forKey: .onSale) ?? false
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        plan = try c.decodeIfPresent(VipPlan.self, forKey: .plan)
        tables = try c.decodeIfPresent([VipTable].self, forKey: .tables) ?? []
        packages = try c.decodeIfPresent([VipPackage].self, forKey: .packages) ?? []
    }

    /// Tloris je uporaben, ce je vklopljen, ima mrezo in vsaj eno mizo.
    var isUsable: Bool { enabled && plan != nil && !tables.isEmpty }
}

// MARK: - GET /business/events/:id/vip

/// Rezervacija mize (samo poslovni pogled). Kupec je ime uporabnika, ne e-naslov.
struct VipBooking: Decodable {
    let orderId: Int
    let publicRef: String
    let buyerUsername: String
    let packageName: String
    let packageDescription: String
    /// Stevilo VIP vstopnic (= sedezi mize).
    let guests: Int
    let checkedIn: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case guests
        case orderId = "order_id"
        case publicRef = "public_ref"
        case buyerUsername = "buyer_username"
        case packageName = "package_name"
        case packageDescription = "package_description"
        case checkedIn = "checked_in"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderId = try c.decodeIfPresent(Int.self, forKey: .orderId) ?? 0
        publicRef = try c.decodeIfPresent(String.self, forKey: .publicRef) ?? ""
        buyerUsername = try c.decodeIfPresent(String.self, forKey: .buyerUsername) ?? ""
        packageName = try c.decodeIfPresent(String.self, forKey: .packageName) ?? ""
        packageDescription = try c.decodeIfPresent(String.self, forKey: .packageDescription) ?? ""
        guests = try c.decodeIfPresent(Int.self, forKey: .guests) ?? 0
        checkedIn = try c.decodeIfPresent(Int.self, forKey: .checkedIn) ?? 0
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

struct VipBusinessTable: Decodable, Identifiable {
    let id: Int
    let label: String
    let seats: Int
    let priceCents: Int
    let defaultPriceCents: Int
    let disabled: Bool
    /// Arhivirana miza (backend jo vrne samo, ce ima rezervacijo na tem dogodku).
    let archived: Bool
    /// nil = miza na tem dogodku ni rezervirana.
    let booking: VipBooking?

    enum CodingKeys: String, CodingKey {
        case id, label, seats, disabled, archived, booking
        case priceCents = "price_cents"
        case defaultPriceCents = "default_price_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        seats = try c.decodeIfPresent(Int.self, forKey: .seats) ?? 0
        priceCents = try c.decodeIfPresent(Int.self, forKey: .priceCents) ?? 0
        defaultPriceCents = try c.decodeIfPresent(Int.self, forKey: .defaultPriceCents) ?? 0
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        booking = try c.decodeIfPresent(VipBooking.self, forKey: .booking)
    }
}

struct BusinessEventVip: Decodable {
    let eventId: Int
    let enabled: Bool
    let currency: String
    let plan: VipPlan?
    let tables: [VipBusinessTable]
    let packages: [VipPackage]

    enum CodingKeys: String, CodingKey {
        case enabled, currency, plan, tables, packages
        case eventId = "event_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        plan = try c.decodeIfPresent(VipPlan.self, forKey: .plan)
        tables = try c.decodeIfPresent([VipBusinessTable].self, forKey: .tables) ?? []
        packages = try c.decodeIfPresent([VipPackage].self, forKey: .packages) ?? []
    }

    /// Rezervirane mize, urejene po oznaki (T2 pred T10).
    var bookings: [VipBusinessTable] {
        tables
            .filter { $0.booking != nil }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Klub ima VIP pri tem dogodku vklopljen in ima tloris z mizami.
    /// (Rezervacije se kazejo ne glede na to - glej `bookings`.)
    var isSetUp: Bool { enabled && plan != nil && !tables.isEmpty }
}

// MARK: - Klici

extension APIClient {

    /// GET /events/:id/vip — tloris, mize in paketi dogodka. Javno; zeton je neobvezen.
    func fetchEventVip(eventId: Int, token: String? = nil) async throws -> EventVip {
        let data = try await send(path: "events/\(eventId)/vip", method: "GET", token: token)
        return try decode(EventVip.self, from: data)
    }

    /// POST /events/:id/tables/:tableId/orders — nakup mize. `packageId` je obvezen, ce ima klub pakete.
    /// Odgovor je isti kot pri nakupu vstopnic (narocilo + N VIP vstopnic). 409 = miza je ze prodana.
    /// `expectedPriceCents` = cena, ki jo je kupec videl; ob drugacni ceni backend vrne 409 "The table price has changed.".
    func buyTable(eventId: Int, tableId: Int, packageId: Int?, expectedPriceCents: Int? = nil, token: String) async throws -> PurchaseResponse {
        var body: [String: Any] = [:]
        if let packageId { body["package_id"] = packageId }
        if let expectedPriceCents { body["expected_price_cents"] = expectedPriceCents }
        let data = try await send(path: "events/\(eventId)/tables/\(tableId)/orders", method: "POST",
                                  token: token, json: body)
        return try decode(PurchaseResponse.self, from: data)
    }

    /// GET /business/events/:id/vip — mize in rezervacije dogodka (owner, manager, doorman).
    func fetchBusinessEventVip(eventId: Int, token: String) async throws -> BusinessEventVip {
        let data = try await send(path: "business/events/\(eventId)/vip", method: "GET", token: token)
        return try decode(BusinessEventVip.self, from: data)
    }
}

// MARK: - Besedila

/// Skupni napisi za VIP (tloris, vstopnica, skener, poslovni pogled).
enum VipOznaka {
    /// "Table T1"
    static func miza(_ oznaka: String) -> String {
        "\(String(localized: "Table")) \(oznaka)"
    }

    /// "VIP · Table T1 · Jameson 0,7 l" (prazni deli se izpustijo).
    static func vrstica(tableLabel: String?, packageName: String?) -> String {
        var deli = ["VIP"]
        if let l = tableLabel, !l.isEmpty { deli.append(miza(l)) }
        if let p = packageName, !p.isEmpty { deli.append(p) }
        return deli.joined(separator: " · ")
    }

    /// Kljuc prevoda za privzeti naziv tipa elementa; nil = tip brez privzetega napisa (label, wall, neznan).
    static func privzetNaziv(tip: String) -> String? {
        switch tip {
        case "bar": return "Bar"
        case "stage": return "Stage"
        case "dj": return "DJ"
        case "dancefloor": return "Dance floor"
        case "entrance": return "Entrance"
        case "wc": return "WC"
        default: return nil
        }
    }
}
