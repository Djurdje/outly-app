import Foundation

// Potisna obvestila (APNs, backend outly-backend#183, aplikacija #184). Ta datoteka je CISTA logika (samo Foundation):
// kam vodi dotik na obvestilo in kdaj je treba zeton znova poslati na streznik. Brez izolacije na glavno nit
// (nonisolated), ker jo kliceta tudi metodi UNUserNotificationCenterDelegate, ki nista na glavni niti.
//
// Vsebina obvestila (pogodba z backendom, DECISIONS 10. 10. 2026):
//   { "aps": { "alert": { "title-loc-key", "loc-key", "loc-args" }, "sound": "default" }, "outly": { "type": "...", "id": 123 } }
//
//   outly.type          outly.id            cilj
//   ticket_received     id vstopnice        vstopnice (denarnica)
//   guest_list_invite   id vstopnice        vstopnice (denarnica)
//   club_event          id dogodka          EventDetailView
//   table_service       id strezbe          Table service
// Neznan `type` ali manjkajoc/neveljaven `id` -> nil (aplikacija se samo odpre).

/// Kam odpre dotik na potisno obvestilo.
nonisolated enum PushCilj: Equatable, Sendable {
    /// `ticket_received`, `guest_list_invite`: seznam vstopnic (TicketsView). `id` je id vstopnice; zaslon ga ne rabi.
    case vstopnice(id: Int)
    /// `club_event`: EventDetailView dogodka.
    case dogodek(id: Int)
    /// `table_service`: zaslon Table service (klub se najde prek GET /me/table-service).
    case strezba(id: Int)

    /// Iz `userInfo` obvestila. nil = neznana vrsta ali manjkajoc id.
    init?(userInfo: [AnyHashable: Any]) {
        guard let outly = userInfo["outly"] as? [String: Any],
              let vrsta = outly["type"] as? String,
              let id = PushCilj.celoStevilo(outly["id"]), id > 0 else { return nil }
        switch vrsta {
        case "ticket_received", "guest_list_invite": self = .vstopnice(id: id)
        case "club_event": self = .dogodek(id: id)
        case "table_service": self = .strezba(id: id)
        default: return nil
        }
    }

    /// `outly.id` je JSON stevilo (NSNumber); pogumno sprejmemo tudi stevilski niz.
    private static func celoStevilo(_ vrednost: Any?) -> Int? {
        if let n = vrednost as? Int { return n }
        if let s = vrednost as? String { return Int(s) }
        return nil
    }
}

extension PushCilj: Identifiable {
    /// Za `.sheet(item:)`: vsak nov dotik je nov cilj, tudi ce vodi na isti zaslon.
    nonisolated var id: String {
        switch self {
        case .vstopnice(let id): return "vstopnice-\(id)"
        case .dogodek(let id): return "dogodek-\(id)"
        case .strezba(let id): return "strezba-\(id)"
        }
    }
}

/// Zadnja uspesna registracija zetona na streznik (hrani se v UserDefaults).
nonisolated struct PushRegistracija: Codable, Equatable, Sendable {
    var zeton: String
    var uporabnikId: Int
    var cas: Date

    /// Registracija se ponovi najpozneje na 24 h (backend: omejevalnik 60/h/IP, `last_seen_at` se osvezi ob vsakem POST-u).
    static let najvecStarost: TimeInterval = 24 * 60 * 60
}

nonisolated enum PushOdlocitev {
    /// Ali je treba zeton poslati na streznik: prvic, spremenjen zeton, drug uporabnik kot zadnjic ali zadnja uspesna
    /// registracija starejsa od 24 h (tudi ce se je ura premaknila nazaj: negativna starost).
    static func jeTreba(zeton: String, uporabnikId: Int, zadnja: PushRegistracija?, zdaj: Date) -> Bool {
        guard let z = zadnja else { return true }
        if z.zeton != zeton || z.uporabnikId != uporabnikId { return true }
        let starost = zdaj.timeIntervalSince(z.cas)
        return starost < 0 || starost > PushRegistracija.najvecStarost
    }

    /// Zeton naprave kot heksadecimalni niz z malimi crkami (oblika, ki jo pricakuje POST /me/devices).
    static func hex(_ podatki: Data) -> String {
        podatki.map { String(format: "%02x", $0) }.joined()
    }
}
