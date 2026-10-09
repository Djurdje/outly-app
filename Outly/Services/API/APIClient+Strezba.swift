import Foundation

// Strezba VIP miz (vloga bartender, backend issue #176, dogovor 9. 10. 2026).
// Vratar skenira VIP QR; ob prvem uspesnem skenu nastane strezba (miza + paket + cas). Natakar, manager in lastnik jo vidijo
// in oznacijo »Delivered«. Natakar NIKOLI ne dobi osebnih podatkov kupca (invarianta I27) — teh polj tudi ni v modelih.
// Poti (vse prek APIClient.send, klub izrecen -> glava X-Outly-Club):
//   GET /business/events/:id/table-service  -> { items: [TableServiceItem] }  (owner, manager, bartender; vratar 403)
//   PUT /business/table-service/:id         { delivered: Bool } -> posodobljen element
//   GET /me/table-service                   -> { items: [MyTableServiceItem] }  (zvonec; star backend: 404 = prazno)
// GET /me ima novo polje pending_table_service (Me.pendingTableService, privzeto 0).
// Vsa polja imajo privzete vrednosti (pravilo 2).

/// Ena strezba na seznamu dogodka.
struct TableServiceItem: Decodable, Identifiable, Equatable {
    let id: Int
    let orderId: Int
    /// Oznaka mize (npr. "V3").
    let tableLabel: String
    let tableSeats: Int
    let packageName: String
    let packageDescription: String
    /// ISO cas skena VIP vstopnice.
    let scannedAt: String
    /// nil = se ni dostavljeno.
    let deliveredAt: String?
    let deliveredByUsername: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case tableLabel = "table_label"
        case tableSeats = "table_seats"
        case packageName = "package_name"
        case packageDescription = "package_description"
        case scannedAt = "scanned_at"
        case deliveredAt = "delivered_at"
        case deliveredByUsername = "delivered_by_username"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        orderId = try c.decodeIfPresent(Int.self, forKey: .orderId) ?? 0
        tableLabel = try c.decodeIfPresent(String.self, forKey: .tableLabel) ?? ""
        tableSeats = try c.decodeIfPresent(Int.self, forKey: .tableSeats) ?? 0
        packageName = try c.decodeIfPresent(String.self, forKey: .packageName) ?? ""
        packageDescription = try c.decodeIfPresent(String.self, forKey: .packageDescription) ?? ""
        scannedAt = try c.decodeIfPresent(String.self, forKey: .scannedAt) ?? ""
        deliveredAt = (try? c.decodeIfPresent(String.self, forKey: .deliveredAt)) ?? nil
        deliveredByUsername = (try? c.decodeIfPresent(String.self, forKey: .deliveredByUsername)) ?? nil
    }

    var jeDostavljeno: Bool { deliveredAt != nil }
    var scannedDate: Date? { DateParsing.parseBackendDate(scannedAt) }
    var deliveredDate: Date? { deliveredAt.flatMap { DateParsing.parseBackendDate($0) } }
}

struct TableServiceResponse: Decodable {
    let items: [TableServiceItem]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([TableServiceItem].self, forKey: .items)) ?? []
    }
}

/// Vrstica za zvonec: nedostavljena strezba v klubu, kjer sem owner / manager / bartender.
struct MyTableServiceItem: Decodable, Identifiable, Equatable {
    let id: Int
    let clubId: Int
    let clubName: String
    let eventId: Int
    let eventTitle: String
    let tableLabel: String
    let packageName: String
    let scannedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case clubId = "club_id"
        case clubName = "club_name"
        case eventId = "event_id"
        case eventTitle = "event_title"
        case tableLabel = "table_label"
        case packageName = "package_name"
        case scannedAt = "scanned_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        eventTitle = try c.decodeIfPresent(String.self, forKey: .eventTitle) ?? ""
        tableLabel = try c.decodeIfPresent(String.self, forKey: .tableLabel) ?? ""
        packageName = try c.decodeIfPresent(String.self, forKey: .packageName) ?? ""
        scannedAt = try c.decodeIfPresent(String.self, forKey: .scannedAt) ?? ""
    }
}

struct MyTableServiceResponse: Decodable {
    let items: [MyTableServiceItem]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([MyTableServiceItem].self, forKey: .items)) ?? []
    }
}

extension APIClient {

    /// GET /business/events/:id/table-service — nedostavljene najprej, nato dostavljene. Klub je izrecen (glava X-Outly-Club).
    func fetchTableService(token: String, eventId: Int, clubId: Int?) async throws -> [TableServiceItem] {
        let data = try await send(path: "business/events/\(eventId)/table-service", method: "GET", token: token, clubId: clubId)
        return try decode(TableServiceResponse.self, from: data).items
    }

    /// PUT /business/table-service/:id — Delivered / Undo. Vrne posodobljen element.
    func setTableServiceDelivered(token: String, id: Int, delivered: Bool, clubId: Int?) async throws -> TableServiceItem {
        let data = try await send(path: "business/table-service/\(id)", method: "PUT", token: token,
                                  json: ["delivered": delivered], clubId: clubId)
        return try decode(TableServiceItem.self, from: data)
    }

    /// GET /me/table-service — za zvonec. Star backend poti nima (404): to je »brez vrstic«, ne napaka.
    func fetchMyTableService(token: String) async throws -> [MyTableServiceItem] {
        do {
            let data = try await send(path: "me/table-service", method: "GET", token: token)
            return try decode(MyTableServiceResponse.self, from: data).items
        } catch let api as APIError {
            if case .requestFailed(404, _) = api { return [] }
            throw api
        }
    }
}
