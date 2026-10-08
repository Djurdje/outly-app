import Foundation

// Modeli za sken brez povezave (backend issue #86). Vsa polja so s privzeto vrednostjo ali opcijska
// (pravilo 2: star ali novejsi backend ne sme podreti dekodiranja). Vsi so Codable, ker jih hranimo na disku.

/// GET /business/scan-key
struct ScanKey: Codable, Equatable {
    var alg: String
    var kid: String
    /// base64url, 32 B surovo (Ed25519).
    var publicKey: String

    enum CodingKeys: String, CodingKey {
        case alg, kid
        case publicKey = "public_key"
    }

    init(alg: String = "Ed25519", kid: String, publicKey: String) {
        self.alg = alg
        self.kid = kid
        self.publicKey = publicKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alg = (try? c.decodeIfPresent(String.self, forKey: .alg)) ?? "Ed25519"
        kid = (try? c.decodeIfPresent(String.self, forKey: .kid)) ?? ""
        publicKey = (try? c.decodeIfPresent(String.self, forKey: .publicKey)) ?? ""
    }

    /// Surovi javni kljuc ali nil, ce ni uporaben (napacen alg, dolzina).
    var surovi: Data? {
        guard alg == "Ed25519", let d = Data(base64URL: publicKey), d.count == 32 else { return nil }
        return d
    }
}

/// Ena vstopnica v GET /business/events/:id/scan-list.
struct ScanListTicket: Codable, Equatable {
    var serial: String
    /// valid | used | refunded | void | unpaid (vstopnica neplacanega narocila; backend jih vrne od 2. 10. 2026)
    var status: String
    var usedAt: String?
    var isVip: Bool
    var tableLabel: String?
    var packageName: String?
    var holderUsername: String?
    /// Guest lista (backend 8. 10. 2026): star backend ali star seznam na disku polj nima -> false / nil.
    var isGuestList: Bool
    var guestListHostUsername: String?

    enum CodingKeys: String, CodingKey {
        case serial, status
        case usedAt = "used_at"
        case isVip = "is_vip"
        case tableLabel = "table_label"
        case packageName = "package_name"
        case holderUsername = "holder_username"
        case isGuestList = "is_guest_list"
        case guestListHostUsername = "guest_list_host_username"
    }

    init(serial: String, status: String = "valid", usedAt: String? = nil, isVip: Bool = false,
         tableLabel: String? = nil, packageName: String? = nil, holderUsername: String? = nil,
         isGuestList: Bool = false, guestListHostUsername: String? = nil) {
        self.serial = serial
        self.status = status
        self.usedAt = usedAt
        self.isVip = isVip
        self.tableLabel = tableLabel
        self.packageName = packageName
        self.holderUsername = holderUsername
        self.isGuestList = isGuestList
        self.guestListHostUsername = guestListHostUsername
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serial = try c.decode(String.self, forKey: .serial)
        // Manjkajoc status NIKOLI ne pomeni "valid": neznano stanje je rdece (odlocitev prepusti strezniku).
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "unknown"
        usedAt = (try? c.decodeIfPresent(String.self, forKey: .usedAt)) ?? nil
        isVip = (try? c.decodeIfPresent(Bool.self, forKey: .isVip)) ?? false
        tableLabel = (try? c.decodeIfPresent(String.self, forKey: .tableLabel)) ?? nil
        packageName = (try? c.decodeIfPresent(String.self, forKey: .packageName)) ?? nil
        holderUsername = (try? c.decodeIfPresent(String.self, forKey: .holderUsername)) ?? nil
        isGuestList = (try? c.decodeIfPresent(Bool.self, forKey: .isGuestList)) ?? false
        guestListHostUsername = (try? c.decodeIfPresent(String.self, forKey: .guestListHostUsername)) ?? nil
    }
}

/// GET /business/events/:id/scan-list
struct ScanList: Codable, Equatable {
    var eventId: Int
    var generatedAt: String
    var kid: String
    var tickets: [ScanListTicket]
    /// Stari serial-i prenesenih vstopnic: koda s takim serialom ne velja vec.
    var transferredSerials: [String]

    enum CodingKeys: String, CodingKey {
        case tickets, kid
        case eventId = "event_id"
        case generatedAt = "generated_at"
        case transferredSerials = "transferred_serials"
    }

    init(eventId: Int, generatedAt: String = "", kid: String = "", tickets: [ScanListTicket] = [], transferredSerials: [String] = []) {
        self.eventId = eventId
        self.generatedAt = generatedAt
        self.kid = kid
        self.tickets = tickets
        self.transferredSerials = transferredSerials
    }

    /// Strogo: pokvarjen ali okrnjen odgovor (manjkajoc `tickets`, napacen tip, vstopnica brez serial-a) vrze. Prejsnja razlicica je
    /// to tiho spremenila v PRAZEN seznam in izbrisala vse znanje o vstopnicah (pregled M9); klicatelj ob napaki obdrzi stari seznam.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = (try? c.decodeIfPresent(Int.self, forKey: .eventId)) ?? 0
        generatedAt = (try? c.decodeIfPresent(String.self, forKey: .generatedAt)) ?? ""
        kid = (try? c.decodeIfPresent(String.self, forKey: .kid)) ?? ""
        tickets = try c.decode([ScanListTicket].self, forKey: .tickets)
        transferredSerials = try c.decode([String].self, forKey: .transferredSerials)
    }
}

/// Rezultat enega skena v odgovoru POST /business/tickets/scan-batch.
struct ScanBatchResult: Decodable, Equatable {
    var clientScanId: String
    var serial: String?
    /// ok | already_used | transferred | invalid | wrong_club | unknown | unpaid | refunded | void (dokoncni) ali error (poskusi znova).
    var result: String
    var usedAt: String?

    enum CodingKeys: String, CodingKey {
        case serial, result
        case clientScanId = "client_scan_id"
        case usedAt = "used_at"
    }

    init(clientScanId: String, serial: String? = nil, result: String, usedAt: String? = nil) {
        self.clientScanId = clientScanId
        self.serial = serial
        self.result = result
        self.usedAt = usedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientScanId = (try? c.decodeIfPresent(String.self, forKey: .clientScanId)) ?? ""
        serial = (try? c.decodeIfPresent(String.self, forKey: .serial)) ?? nil
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? "error"
        usedAt = (try? c.decodeIfPresent(String.self, forKey: .usedAt)) ?? nil
    }

    /// Dokoncen rezultat = vnos gre iz vrste. Samo `error` (in manjkajoc rezultat) ostane za nov poskus.
    var jeDokoncen: Bool { result != "error" && !clientScanId.isEmpty }
}

/// Dogodek za izbiro v skenerju. Hranimo svojo kopijo (APIEvent ni Encodable), da se seznam odpre tudi brez povezave.
struct SkenDogodek: Codable, Equatable, Identifiable {
    var id: Int
    var title: String
    var startAt: String
    var endAt: String?
    var status: String
    var lifecycle: String

    enum CodingKeys: String, CodingKey { case id, title, startAt, endAt, status, lifecycle }

    init(id: Int, title: String, startAt: String = "", endAt: String? = nil, status: String = "published", lifecycle: String = "upcoming") {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.status = status
        self.lifecycle = lifecycle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        startAt = (try? c.decodeIfPresent(String.self, forKey: .startAt)) ?? ""
        endAt = (try? c.decodeIfPresent(String.self, forKey: .endAt)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "published"
        lifecycle = (try? c.decodeIfPresent(String.self, forKey: .lifecycle)) ?? "upcoming"
    }

    init(_ e: APIEvent) {
        self.init(id: e.id, title: e.title, startAt: e.startAt, endAt: e.endAt, status: e.status, lifecycle: e.lifecycle)
    }
}

/// Ure iz streznika (ISO 8601 z ali brez delcev sekunde).
enum SkenCas {
    nonisolated(unsafe) private static let brezDelcev: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let zDelci: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func razcleni(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return zDelci.date(from: s) ?? brezDelcev.date(from: s)
    }

    static func niz(_ d: Date) -> String { zDelci.string(from: d) }
}
