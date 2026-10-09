import Foundation

// Razpored VIP miz za urejanje (organizator, backend migracija 039, 9. 10. 2026; issue outly-backend#175).
// Poti: GET|PUT /business/events/:id/vip-layout (razpored enega dogodka) in GET|PUT /business/vip (tloris kluba).
// Obe vrneta isto obliko mize, zato ju urejevalnik (`VipUrejevalnikView`) bere in pise prek enega vira (`VipVir`).
// Kupcev pogled (`EventVip`, GET /events/:id/vip) se ne spreminja.
//
// Vsa polja so s privzeto vrednostjo ali opcijska: star backend (brez 039) ne sme podreti dekodiranja.
// Stari backend na poti dogodka vrne 404 -> razdelek v obrazcu se skrije.

/// Kam urejevalnik bere in shranjuje razpored.
enum VipVir {
    /// Tloris in mize kluba (GET|PUT /business/vip). Paketi steklenic gredo nespremenjeni nazaj (PUT jih zahteva).
    case klub(clubId: Int)
    /// Razpored enega dogodka (GET|PUT /business/events/:id/vip-layout).
    case dogodek(eventId: Int, clubId: Int)

    var clubId: Int {
        switch self {
        case .klub(let id): return id
        case .dogodek(_, let id): return id
        }
    }

    var pot: String {
        switch self {
        case .klub: return "business/vip"
        case .dogodek(let eventId, _): return "business/events/\(eventId)/vip-layout"
        }
    }
}

/// Miza v razporedu (poslovni pogled, brez stanja rezervacije).
struct VipLayoutTable: Decodable {
    let id: Int
    let label: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
    /// round | rect
    let shape: String
    let seats: Int
    let priceCents: Int

    enum CodingKeys: String, CodingKey {
        case id, label, x, y, w, h, shape, seats
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
        shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? "round"
        seats = try c.decodeIfPresent(Int.self, forKey: .seats) ?? 1
        priceCents = try c.decodeIfPresent(Int.self, forKey: .priceCents) ?? 0
    }
}

/// Odgovor GET|PUT /business/events/:id/vip-layout (in GET|PUT /business/vip, kjer je `source` vedno "club").
struct VipLayout: Decodable {
    /// club | event
    let source: String
    let plan: VipPlan?
    let tables: [VipLayoutTable]
    /// Samo pri poti kluba; pri dogodku prazno (paketi so vedno organizatorjevi/klubski).
    let packages: [VipPackage]
    /// Od kod je kopija razporeda dogodka (informativno).
    let fromClubId: Int?
    let fromClubName: String
    let venueClubId: Int?
    let venueClubName: String
    /// Gostitelj ima tloris, ki ga je mogoce kopirati.
    let venueHasLayout: Bool

    enum CodingKeys: String, CodingKey {
        case source, plan, tables, packages
        case floorPlan = "floor_plan"
        case fromClubId = "from_club_id"
        case fromClubName = "from_club_name"
        case venueClubId = "venue_club_id"
        case venueClubName = "venue_club_name"
        case venueHasLayout = "venue_has_layout"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "club"
        let tloris = try? c.decodeIfPresent(VipPlan.self, forKey: .floorPlan)
        let tlorisKluba = try? c.decodeIfPresent(VipPlan.self, forKey: .plan)
        plan = tloris ?? tlorisKluba
        tables = try c.decodeIfPresent([VipLayoutTable].self, forKey: .tables) ?? []
        packages = try c.decodeIfPresent([VipPackage].self, forKey: .packages) ?? []
        fromClubId = try c.decodeIfPresent(Int.self, forKey: .fromClubId)
        fromClubName = try c.decodeIfPresent(String.self, forKey: .fromClubName) ?? ""
        venueClubId = try c.decodeIfPresent(Int.self, forKey: .venueClubId)
        venueClubName = try c.decodeIfPresent(String.self, forKey: .venueClubName) ?? ""
        venueHasLayout = try c.decodeIfPresent(Bool.self, forKey: .venueHasLayout) ?? false
    }

    init(source: String, plan: VipPlan?, tables: [VipLayoutTable], packages: [VipPackage],
         fromClubId: Int?, fromClubName: String, venueClubId: Int?, venueClubName: String, venueHasLayout: Bool) {
        self.source = source
        self.plan = plan
        self.tables = tables
        self.packages = packages
        self.fromClubId = fromClubId
        self.fromClubName = fromClubName
        self.venueClubId = venueClubId
        self.venueClubName = venueClubName
        self.venueHasLayout = venueHasLayout
    }

    /// Razpored tega dogodka (ne klubski tloris).
    var jeDogodkov: Bool { source == "event" }

    /// Razpored dogodka je kopija tlorisa gostitelja (ob prvem kopiranju; urejanje to ne spremeni).
    var jeKopijaGostitelja: Bool { jeDogodkov && fromClubId != nil }

    /// Ista oblika brez tlorisa in miz: izhodisce za »Own layout« (prazen tloris).
    func prazen() -> VipLayout {
        VipLayout(source: source, plan: nil, tables: [], packages: packages,
                  fromClubId: nil, fromClubName: "", venueClubId: venueClubId,
                  venueClubName: venueClubName, venueHasLayout: venueHasLayout)
    }
}

// MARK: - Klici

extension APIClient {

    /// GET razpored (dogodka ali kluba). Glavo kluba (X-Outly-Club) nastavi `clubId` iz vira. 404 = star backend ali tuj dogodek.
    func fetchVipLayout(vir: VipVir, token: String) async throws -> VipLayout {
        let data = try await send(path: vir.pot, method: "GET", token: token, clubId: vir.clubId)
        return try decode(VipLayout.self, from: data)
    }

    /// PUT lasten razpored. Dogodek: `{source:"event", floor_plan, tables}`; klub: `{plan, tables, packages}` (paketi nespremenjeni).
    /// `plan` je `{width, height, elements:[...]}`, `tables` seznam `{id?, label, x, y, w, h, shape, seats, price_cents}`
    /// (mize z `id` se posodobijo, manjkajoce se arhivirajo, nove brez `id`). Odgovor = isti kot GET.
    func saveVipLayout(vir: VipVir, plan: [String: Any], tables: [[String: Any]],
                       packages: [VipPackage], token: String) async throws -> VipLayout {
        var body: [String: Any] = ["tables": tables]
        switch vir {
        case .dogodek:
            body["source"] = "event"
            body["floor_plan"] = plan
        case .klub:
            body["plan"] = plan
            body["packages"] = packages.map { ["id": $0.id, "name": $0.name, "description": $0.description] as [String: Any] }
        }
        let data = try await send(path: vir.pot, method: "PUT", token: token, json: body, clubId: vir.clubId)
        return try decode(VipLayout.self, from: data)
    }

    /// PUT `{source:"event", copy_from_venue:true}` — kopija tlorisa in miz kluba gostitelja v razpored dogodka.
    /// 400 = dogodek nima gostitelja ali gostitelj nima tlorisa.
    func copyVipLayoutFromVenue(eventId: Int, clubId: Int, token: String) async throws -> VipLayout {
        let body: [String: Any] = ["source": "event", "copy_from_venue": true]
        let data = try await send(path: "business/events/\(eventId)/vip-layout", method: "PUT", token: token, json: body, clubId: clubId)
        return try decode(VipLayout.self, from: data)
    }

    /// PUT `{source:"club"}` — dogodek spet uporablja klubski tloris (organizator ga ponavadi nima = brez VIP).
    /// Mize dogodka se arhivirajo; narocila ostanejo veljavna.
    func resetVipLayoutToClub(eventId: Int, clubId: Int, token: String) async throws -> VipLayout {
        let body: [String: Any] = ["source": "club"]
        let data = try await send(path: "business/events/\(eventId)/vip-layout", method: "PUT", token: token, json: body, clubId: clubId)
        return try decode(VipLayout.self, from: data)
    }
}
