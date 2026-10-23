import Foundation

// VIP mize (backend migracija 025, 1. 10. 2026). Poti:
// GET /events/:id/vip (javno), POST /events/:id/tables/:tableId/orders (zeton),
// GET /business/events/:id/vip (vse vloge v klubu; glava X-Outly-Club doda send()).
// Urejevalnik tlorisa na iOS je od 9. 10. 2026 za organizatorje (VipUrejevalnikView, APIClient+VipLayout.swift); ta datoteka ima samo branje in nakup.
//
// Vsa polja so s privzeto vrednostjo ali opcijska: star backend (brez 025) ne sme podreti dekodiranja.
//
// Placilo mize na vratih (backend 23. 10. 2026): dogodek ima `vip_payment` "app" (privzeto, kot doslej) | "door".
// Pri "door" kupec mizo v aplikaciji samo REZERVIRA (POST /events/:id/tables/:tableId/reservations, brez Stripa in vstopnic) in placa z
// gotovino na VIP vratih. GET /me/table-reservations, DELETE /events/:id/tables/:tableId/reservations. Klub: PUT /business/events/:id/vip
// sprejme neobvezno `payment`; `hold` ima novo `source` ("phone" | "app"), `username`, `package_name`, `price_cents`.

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
    /// Nacin placila prodajalca (backend#203): "test" | "stripe" | "unavailable"; nil = star backend (glej `NacinPlacila`).
    let paymentMode: String?
    /// Prodajalec mize = klub dogodka (backend#94); star backend ga nima -> nil.
    let seller: Seller?
    /// Prodajalec je demo klub (backend#243; `GET /events/:id/vip` ima tudi `is_demo`): brez rezervacije mize (409 `demo_club`),
    /// admin sme. Star backend -> false.
    let isDemo: Bool
    /// Najmanjsa starost za mizo Z IZBRANIM PAKETOM pijace (backend `starostZaPaket`: vsaj 18, pri strozji meji dogodka ta).
    /// Star backend polja nima -> 18.
    let packageMinAge: Int
    /// Kako se placa miza (backend 23. 10. 2026): "app" (privzeto, tudi star backend) | "door" (rezervacija, gotovina na VIP vratih).
    let vipPayment: String

    enum CodingKeys: String, CodingKey {
        case enabled, currency, plan, tables, packages, seller
        case vipPayment = "vip_payment"
        case packageMinAge = "package_min_age"
        case eventId = "event_id"
        case onSale = "on_sale"
        case paymentMode = "payment_mode"
        case isDemo = "is_demo"
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
        paymentMode = (try? c.decodeIfPresent(String.self, forKey: .paymentMode)) ?? nil
        seller = (try? c.decodeIfPresent(Seller.self, forKey: .seller)) ?? nil
        isDemo = (try? c.decodeIfPresent(Bool.self, forKey: .isDemo)) ?? false
        let paketStarost = (try? c.decodeIfPresent(Int.self, forKey: .packageMinAge)) ?? nil
        packageMinAge = paketStarost.flatMap { $0 > 0 ? $0 : nil } ?? Self.privzetaStarostPaketa
        vipPayment = VipPlacilo.normaliziraj((try? c.decodeIfPresent(String.self, forKey: .vipPayment)) ?? nil)
    }

    /// Miza se rezervira v aplikaciji, placilo je z gotovino na VIP vratih.
    var placiloNaVratih: Bool { vipPayment == VipPlacilo.vrata }

    static let privzetaStarostPaketa = 18

    /// Starost, ki jo kaze kartica mize: pri mizi s paketom pijace `max(min_age dogodka, package_min_age)`, sicer `min_age` dogodka.
    /// 0 = brez omejitve (oznaka se ne kaze).
    func prikazanaStarost(minAgeDogodka: Int) -> Int {
        packages.isEmpty ? minAgeDogodka : max(minAgeDogodka, packageMinAge)
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

/// Zasedena miza brez placila v aplikaciji: rezervacija po telefonu (klub jo je vpisal) ali rezervacija v aplikaciji
/// (gost placa z gotovino na VIP vratih; backend 23. 10. 2026). Backend 4. 10. 2026 (telefon).
struct VipHold: Decodable, Equatable {
    let guestName: String
    /// Neobvezna opomba (npr. "6 guests, arriving 23:00"); nil ali prazno = brez.
    let note: String?
    let createdAt: String
    /// "phone" (klub vpisal po telefonu) | "app" (gost rezerviral v aplikaciji, placa na vratih). Star backend -> "phone".
    let source: String
    /// Uporabnisko ime gosta; samo pri "app".
    let username: String?
    /// Paket pijace ob rezervaciji (prazno = brez / telefon).
    let packageName: String
    let packageDescription: String
    /// Cena mize ob rezervaciji v centih; nil pri telefonu ali starem backendu.
    let priceCents: Int?

    enum CodingKeys: String, CodingKey {
        case note, source, username
        case guestName = "guest_name"
        case createdAt = "created_at"
        case packageName = "package_name"
        case packageDescription = "package_description"
        case priceCents = "price_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guestName = try c.decodeIfPresent(String.self, forKey: .guestName) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        let vir = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
        source = vir == "app" ? "app" : "phone"
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? nil
        packageName = (try? c.decodeIfPresent(String.self, forKey: .packageName)) ?? ""
        packageDescription = (try? c.decodeIfPresent(String.self, forKey: .packageDescription)) ?? ""
        priceCents = (try? c.decodeIfPresent(Int.self, forKey: .priceCents)) ?? nil
    }

    /// Gost je mizo rezerviral v aplikaciji in placa na vratih.
    var jeIzAplikacije: Bool { source == "app" }

    /// Opomba za prikaz; nil, ce je prazna.
    var prikazanaOpomba: String? {
        guard let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
        return n
    }

    /// Uporabnisko ime za prikaz (»@ime«); nil, ce ga ni.
    var prikazanoUporabniskoIme: String? {
        guard let u = username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return nil }
        return "@" + u
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
    /// Rezervacija po telefonu. nil = ni je (ali star backend, ki polja ne pozna).
    let hold: VipHold?

    enum CodingKeys: String, CodingKey {
        case id, label, seats, disabled, archived, booking, hold
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
        hold = try c.decodeIfPresent(VipHold.self, forKey: .hold)
    }

    /// Miza, ki jo je se mogoce oznaciti kot rezervirano po telefonu: ni arhivirana, prodana ali ze rezervirana.
    /// Izklop za spletno prodajo (disabled) ne velja: klub lahko mizo proda samo po telefonu (backend to dovoli).
    var jeProsta: Bool { !archived && booking == nil && hold == nil }
}

struct BusinessEventVip: Decodable {
    let eventId: Int
    let enabled: Bool
    let currency: String
    let plan: VipPlan?
    let tables: [VipBusinessTable]
    let packages: [VipPackage]
    /// Kako se placa miza na tem dogodku: "app" (privzeto, tudi star backend) | "door".
    let payment: String

    enum CodingKeys: String, CodingKey {
        case enabled, currency, plan, tables, packages, payment
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
        payment = VipPlacilo.normaliziraj((try? c.decodeIfPresent(String.self, forKey: .payment)) ?? nil)
    }

    /// Rezervirane mize, urejene po oznaki (T2 pred T10).
    var bookings: [VipBusinessTable] {
        tables
            .filter { $0.booking != nil }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Mize, ki jih je klub rezerviral po telefonu, urejene po oznaki.
    var holds: [VipBusinessTable] {
        tables
            .filter { $0.hold != nil }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Mize z rezervacijo (nakup ali telefon), urejene po oznaki (T2 pred T10).
    var rezervirane: [VipBusinessTable] {
        tables
            .filter { $0.booking != nil || $0.hold != nil }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Prosto mize, ki jih klub lahko rezervira po telefonu, urejene po oznaki.
    var prosteMize: [VipBusinessTable] {
        tables
            .filter { $0.jeProsta }
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
    /// `idempotencyKey` (NakupniKljuc): ponovitev istega nakupa z istim kljucem vrne isto narocilo namesto 409 "miza ze zasedena".
    /// `locale`: jezik Stripe Checkouta (`"sl"` | `"en"`), privzeto jezik APLIKACIJE; star backend polje spregleda.
    /// Ponovitev (»Continue to payment«, isti kljuc) poslje isto telo kot prvi poskus, plus `locale`.
    func buyTable(eventId: Int, tableId: Int, packageId: Int?, expectedPriceCents: Int? = nil, idempotencyKey: String? = nil, token: String,
                  locale: String = Jezik.shared.stripeLocale) async throws -> PurchaseResponse {
        let body = APIClient.telesoNakupaMize(packageId: packageId, expectedPriceCents: expectedPriceCents, locale: locale)
        let data = try await send(path: "events/\(eventId)/tables/\(tableId)/orders", method: "POST",
                                  token: token, json: body, idempotencyKey: idempotencyKey,
                                  dodatneGlave: APIClient.nakupneGlave)
        return try decode(PurchaseResponse.self, from: data)
    }

    /// Telo POST /events/:id/tables/:tableId/orders: neobvezna `package_id` in `expected_price_cents` + `locale` + `terms_version`
    /// (glej `telesoNakupaVstopnic`).
    static func telesoNakupaMize(packageId: Int?, expectedPriceCents: Int?, locale: String,
                                 termsVersion: String = LegalLinks.termsVersion) -> [String: Any] {
        var body: [String: Any] = ["locale": locale, "terms_version": termsVersion]
        if let packageId { body["package_id"] = packageId }
        if let expectedPriceCents { body["expected_price_cents"] = expectedPriceCents }
        return body
    }

    /// GET /business/events/:id/vip — mize in rezervacije dogodka (owner, manager, doorman).
    func fetchBusinessEventVip(eventId: Int, token: String) async throws -> BusinessEventVip {
        let data = try await send(path: "business/events/\(eventId)/vip", method: "GET", token: token)
        return try decode(BusinessEventVip.self, from: data)
    }

    /// POST /business/events/:id/tables/:tableId/hold — klub mizo oznaci kot rezervirano po telefonu (owner, manager).
    /// Odgovor je celoten pogled kot pri `fetchBusinessEventVip`. 409 "This table is already booked." = miza je prodana ali rezervirana.
    /// Glavo kluba (X-Outly-Club) doda `send()`.
    func holdVipTable(eventId: Int, tableId: Int, guestName: String, note: String?, token: String) async throws -> BusinessEventVip {
        var body: [String: Any] = ["guest_name": guestName]
        if let note, !note.isEmpty { body["note"] = note }
        let data = try await send(path: "business/events/\(eventId)/tables/\(tableId)/hold", method: "POST", token: token, json: body)
        return try decode(BusinessEventVip.self, from: data)
    }

    /// DELETE /business/events/:id/tables/:tableId/hold — sprosti rezervacijo po telefonu (owner, manager). 404 = rezervacije ni.
    func releaseVipTableHold(eventId: Int, tableId: Int, token: String) async throws -> BusinessEventVip {
        let data = try await send(path: "business/events/\(eventId)/tables/\(tableId)/hold", method: "DELETE", token: token)
        return try decode(BusinessEventVip.self, from: data)
    }

    /// PUT /business/events/:id/vip — vklop VIP miz in nacin placila (owner, manager). `tables` NI v telesu: izjeme po mizah
    /// (cene, izklop) ostanejo, kot so (backend: mize, ki jih ni na seznamu, se ne spremenijo). `payment` nil = brez spremembe.
    /// Odgovor je celoten pogled kot pri `fetchBusinessEventVip`. Glavo kluba (X-Outly-Club) doda `send()`.
    func setBusinessEventVip(eventId: Int, enabled: Bool, payment: String?, token: String, clubId: Int? = nil) async throws -> BusinessEventVip {
        let body = APIClient.telesoNastavitveVip(enabled: enabled, payment: payment)
        let data = try await send(path: "business/events/\(eventId)/vip", method: "PUT", token: token, json: body, clubId: clubId)
        return try decode(BusinessEventVip.self, from: data)
    }

    /// Telo PUT /business/events/:id/vip: `enabled` je obvezen, `payment` ("app" | "door") samo, ce se spreminja.
    static func telesoNastavitveVip(enabled: Bool, payment: String?) -> [String: Any] {
        var body: [String: Any] = ["enabled": enabled]
        if let payment { body["payment"] = payment }
        return body
    }

    // MARK: Rezervacija mize v aplikaciji (vip_payment = "door")

    /// POST /events/:id/tables/:tableId/reservations — kupec rezervira mizo in placa z gotovino na VIP vratih (brez Stripa, brez vstopnic).
    /// Gost brez racuna ne more. 409: `reservation_limit` (ena rezervacija na dogodek), `vip_pay_in_app`, `demo_club`, miza zasedena, cena spremenjena.
    func reserveVipTable(eventId: Int, tableId: Int, packageId: Int?, guestName: String?, expectedPriceCents: Int?, token: String) async throws -> TableReservation {
        let body = APIClient.telesoRezervacijeMize(packageId: packageId, guestName: guestName, expectedPriceCents: expectedPriceCents)
        let data = try await send(path: "events/\(eventId)/tables/\(tableId)/reservations", method: "POST", token: token, json: body,
                                  dodatneGlave: APIClient.nakupneGlave)
        return try decode(TableReservationOdgovor.self, from: data).reservation
    }

    /// Telo POST …/reservations: `package_id` (JSON null, ce paketa ni), `guest_name` (samo, ce je vpisan), `expected_price_cents`.
    static func telesoRezervacijeMize(packageId: Int?, guestName: String?, expectedPriceCents: Int?) -> [String: Any] {
        var body: [String: Any] = [:]
        if let packageId { body["package_id"] = packageId } else { body["package_id"] = NSNull() }
        if let ime = guestName?.trimmingCharacters(in: .whitespacesAndNewlines), !ime.isEmpty {
            body["guest_name"] = String(ime.prefix(TableReservation.najvecImena))
        }
        if let expectedPriceCents { body["expected_price_cents"] = expectedPriceCents }
        return body
    }

    /// DELETE /events/:id/tables/:tableId/reservations — kupec preklice SVOJO rezervacijo do zacetka dogodka.
    /// 404 = ni (vec) rezervacije, 409 `event_started` = dogodek se je ze zacel.
    func cancelVipReservation(eventId: Int, tableId: Int, token: String) async throws {
        _ = try await send(path: "events/\(eventId)/tables/\(tableId)/reservations", method: "DELETE", token: token)
    }

    /// GET /me/table-reservations — moje rezervacije miz (prihajajoci dogodki + koncani pred manj kot 24 h). Star backend poti nima (404):
    /// to je »ni rezervacij«, ne napaka.
    func fetchMyTableReservations(token: String) async throws -> [TableReservation] {
        do {
            let data = try await send(path: "me/table-reservations", method: "GET", token: token)
            return try decode(TableReservationsOdgovor.self, from: data).items
        } catch let api as APIError {
            if case .requestFailed(404, _) = api { return [] }
            throw api
        }
    }
}

// MARK: - Placilo mize in rezervacija kupca

extension Error {
    /// Ali naj VIP zaslon po zavrnjeni rezervaciji osvezi tloris (izbira mize izgine): 409 miza zasedena, cena spremenjena, nacin
    /// placila spremenjen (`vip_pay_in_app`). Izjemi: `reservation_limit` (miza je prosta, kupec ima ze drugo) in `demo_club`.
    var osveziTlorisPoRezervaciji: Bool {
        guard let api = self as? APIError, case .requestFailed(let status, let raw) = api, status == 409 else { return false }
        let t = raw.lowercased()
        return !(t.contains("reservation_limit") || t.contains("demo_club"))
    }
}

/// Vrednosti `vip_payment` / `payment`.
enum VipPlacilo {
    static let aplikacija = "app"
    static let vrata = "door"

    /// Neznana ali manjkajoca vrednost (star backend, nova vrednost) -> "app" (vedenje kot doslej).
    static func normaliziraj(_ vrednost: String?) -> String { vrednost == vrata ? vrata : aplikacija }
}

private struct TableReservationOdgovor: Decodable {
    let reservation: TableReservation
}

private struct TableReservationsOdgovor: Decodable {
    let items: [TableReservation]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([TableReservation].self, forKey: .items)) ?? []
    }
}

/// Rezervacija mize v aplikaciji (kupcev pogled; placilo z gotovino na VIP vratih). `price_cents` je cena, ki jo kupec placa na vratih.
struct TableReservation: Decodable, Identifiable, Equatable {
    /// Ime za rezervacijo: najvec toliko znakov (backend: 1-60 po trim).
    static let najvecImena = 60

    let id: Int
    let eventId: Int
    let eventTitle: String
    let eventStartAt: String
    let clubId: Int
    let clubName: String
    let tableId: Int
    let tableLabel: String
    let seats: Int
    let packageId: Int?
    let packageName: String
    let packageDescription: String
    let priceCents: Int
    let currency: String
    let guestName: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, seats, currency
        case eventId = "event_id"
        case eventTitle = "event_title"
        case eventStartAt = "event_start_at"
        case clubId = "club_id"
        case clubName = "club_name"
        case tableId = "table_id"
        case tableLabel = "table_label"
        case packageId = "package_id"
        case packageName = "package_name"
        case packageDescription = "package_description"
        case priceCents = "price_cents"
        case guestName = "guest_name"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        eventTitle = (try? c.decodeIfPresent(String.self, forKey: .eventTitle)) ?? ""
        eventStartAt = (try? c.decodeIfPresent(String.self, forKey: .eventStartAt)) ?? ""
        clubId = (try? c.decodeIfPresent(Int.self, forKey: .clubId)) ?? 0
        clubName = (try? c.decodeIfPresent(String.self, forKey: .clubName)) ?? ""
        tableId = try c.decodeIfPresent(Int.self, forKey: .tableId) ?? 0
        tableLabel = (try? c.decodeIfPresent(String.self, forKey: .tableLabel)) ?? ""
        seats = (try? c.decodeIfPresent(Int.self, forKey: .seats)) ?? 0
        packageId = (try? c.decodeIfPresent(Int.self, forKey: .packageId)) ?? nil
        packageName = (try? c.decodeIfPresent(String.self, forKey: .packageName)) ?? ""
        packageDescription = (try? c.decodeIfPresent(String.self, forKey: .packageDescription)) ?? ""
        priceCents = (try? c.decodeIfPresent(Int.self, forKey: .priceCents)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "EUR"
        guestName = (try? c.decodeIfPresent(String.self, forKey: .guestName)) ?? ""
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }

    var startDate: Date? { DateParsing.parseBackendDate(eventStartAt) }

    /// Rezervacijo je se mogoce preklicati (do zacetka dogodka). Neberljiv datum -> ne ponudimo preklica (streznik odloci).
    func jeMogocPreklic(zdaj: Date = Date()) -> Bool {
        guard let d = startDate else { return false }
        return d > zdaj
    }

    /// Znesek za placilo na vratih; prazno, ce je cena 0.
    var znesekNaVratih: String? {
        priceCents > 0 ? Denar.evri(priceCents, koda: currency) : nil
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
