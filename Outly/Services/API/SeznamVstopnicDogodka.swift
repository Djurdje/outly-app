import Foundation

/// GET /business/events/:id/tickets z ovojnico (#277 N1, outly-backend ARCHITECTURE »Seznam vstopnic dogodka za vrata«).
/// Ovojnica se vklopi, ko je poslan vsaj eden od `limit`, `offset`, `q`; brez njih backend vrne golo polje (najvec 1000 vrstic) —
/// to dekodiramo tudi (star backend), takrat so stevci izracunani iz vrstic in `hasMore` je false.
struct SeznamVstopnicDogodka: Decodable {
    /// Stevci VSEH vstopnic dogodka (vkljucno VIP in guest lista), neodvisno od `q` / `limit` / `offset`.
    struct Stevci: Decodable, Equatable {
        var all: Int = 0
        /// `valid` + `used`.
        var sold: Int = 0
        /// `used`.
        var checkedIn: Int = 0
        /// `valid`.
        var expected: Int = 0
        var refunded: Int = 0
        var void: Int = 0

        enum CodingKeys: String, CodingKey {
            case all, sold, expected, refunded, void
            case checkedIn = "checked_in"
        }

        init(all: Int = 0, sold: Int = 0, checkedIn: Int = 0, expected: Int = 0, refunded: Int = 0, void: Int = 0) {
            self.all = all
            self.sold = sold
            self.checkedIn = checkedIn
            self.expected = expected
            self.refunded = refunded
            self.void = void
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            all       = (try? c.decodeIfPresent(Int.self, forKey: .all)) ?? 0
            sold      = (try? c.decodeIfPresent(Int.self, forKey: .sold)) ?? 0
            checkedIn = (try? c.decodeIfPresent(Int.self, forKey: .checkedIn)) ?? 0
            expected  = (try? c.decodeIfPresent(Int.self, forKey: .expected)) ?? 0
            refunded  = (try? c.decodeIfPresent(Int.self, forKey: .refunded)) ?? 0
            void      = (try? c.decodeIfPresent(Int.self, forKey: .void)) ?? 0
        }

        /// Star backend (golo polje): isti pomen kot na strezniku, izracunan iz vrstic.
        static func izVrstic(_ vrstice: [APITicket]) -> Stevci {
            let used = vrstice.filter { $0.status == "used" }.count
            let valid = vrstice.filter { $0.status == "valid" }.count
            return Stevci(all: vrstice.count, sold: used + valid, checkedIn: used, expected: valid,
                          refunded: vrstice.filter { $0.status == "refunded" }.count,
                          void: vrstice.filter { $0.status == "void" }.count)
        }
    }

    var tickets: [APITicket]
    var counts: Stevci
    /// Zadetki `q` (brez `q` = `counts.all`).
    var total: Int
    var hasMore: Bool
    /// Naslednji `offset` ali nil.
    var nextOffset: Int?
    /// false = star backend je vrnil golo polje (brez ovojnice).
    var ovojnica: Bool

    enum CodingKeys: String, CodingKey {
        case tickets, counts, total
        case hasMore = "has_more"
        case nextOffset = "next_offset"
    }

    init(tickets: [APITicket], counts: Stevci, total: Int, hasMore: Bool, nextOffset: Int?, ovojnica: Bool = true) {
        self.tickets = tickets
        self.counts = counts
        self.total = total
        self.hasMore = hasMore
        self.nextOffset = nextOffset
        self.ovojnica = ovojnica
    }

    init(from decoder: Decoder) throws {
        if let polje = try? decoder.singleValueContainer().decode([APITicket].self) {
            self.init(tickets: polje, counts: .izVrstic(polje), total: polje.count, hasMore: false, nextOffset: nil, ovojnica: false)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let vrstice = try c.decodeIfPresent([APITicket].self, forKey: .tickets) ?? []
        let stevci = (try? c.decodeIfPresent(Stevci.self, forKey: .counts)) ?? Stevci.izVrstic(vrstice)
        let naslednji = (try? c.decodeIfPresent(Int.self, forKey: .nextOffset)) ?? nil
        // `has_more` brez `next_offset` bi nalaganje naprej zaciklalo: brez naslednjega odmika ni »Load more«.
        let vec = ((try? c.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? false) && naslednji != nil
        self.init(tickets: vrstice, counts: stevci,
                  total: (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? vrstice.count,
                  hasMore: vec, nextOffset: vec ? naslednji : nil, ovojnica: true)
    }
}

extension APIClient {
    /// Velikost strani seznama vstopnic za vrata (pogodba #277 N1: `?limit=200`).
    nonisolated static let stranVstopnicVrata = 200
    /// Najvec, kar backend sprejme v `limit` (osvezitev po vpisu obdrzi ze nalozene strani).
    nonisolated static let najvecVstopnicVrata = 1000
    /// Backend `q`: obrezan, 1-64 znakov (JS dolzina = UTF-16 enote), brez kontrolnih znakov (sicer 400 `invalid_q`).
    nonisolated static let najvecIskanjeVstopnic = 64

    /// Poizvedba za GET /business/events/:id/tickets: vedno `limit` (vklopi ovojnico s stevci), `offset` samo > 0, `q` samo neprazen.
    /// `q` je ociscen (obrezan, brez kontrolnih znakov, najvec 64 UTF-16 enot), da streznik ne vrne 400 `invalid_q`.
    static func poizvedbaVstopnicDogodka(limit: Int = APIClient.stranVstopnicVrata, offset: Int = 0, q: String = "") -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(min(max(limit, 0), najvecVstopnicVrata)))]
        if offset > 0 { items.append(URLQueryItem(name: "offset", value: String(offset))) }
        let iskanje = ocistiIskanjeVstopnic(q)
        if !iskanje.isEmpty { items.append(URLQueryItem(name: "q", value: iskanje)) }
        return items
    }

    /// Obrezan niz brez kontrolnih znakov, skrajsan na najvec 64 UTF-16 enot (cel znak, ne pol emojija).
    static func ocistiIskanjeVstopnic(_ q: String) -> String {
        let brez = String(String.UnicodeScalarView(q.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        var t = brez.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.utf16.count > najvecIskanjeVstopnic { t.removeLast() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// GET /business/events/:id/tickets?limit=&offset=&q= — ena stran seznama za vrata (owner, manager, doorman).
    /// 503 `search_timeout` (seznam je zaseden) gre kot napaka: zaslon pove »poskusi znova« (`userMessage`).
    func fetchEventTicketsStran(token: String, eventId: Int, offset: Int = 0, q: String = "",
                                limit: Int = APIClient.stranVstopnicVrata) async throws -> SeznamVstopnicDogodka {
        let data = try await send(path: "business/events/\(eventId)/tickets", method: "GET", token: token,
                                  query: APIClient.poizvedbaVstopnicDogodka(limit: limit, offset: offset, q: q))
        return try decode(SeznamVstopnicDogodka.self, from: data)
    }
}

/// Stanje seznama vstopnic na vratih (EventTicketsView), cista logika za strani in iskanje (testi: Racun18InVrataTests).
/// Vrstice in `naslednjiOdmik` veljajo za iskanje `q`, za katero so bile nalozene: ko uporabnik tipka (premor pred novim
/// nalaganjem), »Load more« ne sme vzeti NOVEGA `q` s STARIM odmikom.
struct VrataSeznam {
    private(set) var vrstice: [APITicket] = []
    /// Stevci vseh vstopnic dogodka (`counts`); nil = se ni nalozeno.
    private(set) var stevci: SeznamVstopnicDogodka.Stevci?
    /// Zadetki iskanja (`total`).
    private(set) var zadetkov = 0
    private(set) var naslednjiOdmik: Int?
    /// Ocisceno iskanje, za katero veljajo vrstice in odmik; nil = nic nalozeno.
    private(set) var q: String?

    static func kljuc(_ iskanje: String) -> String { APIClient.ocistiIskanjeVstopnic(iskanje) }

    /// Odmik za »Load more«, samo ce seznam velja za trenutno iskanje (sicer nil: gumba ni, klic se ne poslje).
    func odmikNaprej(iskanje: String) -> Int? {
        q == Self.kljuc(iskanje) ? naslednjiOdmik : nil
    }

    /// Prva stran za iskanje (zamenja vse).
    mutating func zamenjaj(_ stran: SeznamVstopnicDogodka, iskanje: String) {
        zamenjajKose([stran], iskanje: iskanje)
    }

    /// Osvezitev po vpisu v vec kosih (`kosiOsvezitve`): vrstice zdruzene brez podvojenih, stevci in odmik iz zadnjega kosa.
    mutating func zamenjajKose(_ strani: [SeznamVstopnicDogodka], iskanje: String) {
        guard let zadnja = strani.last else { return }
        var znani = Set<Int>()
        vrstice = strani.flatMap(\.tickets).filter { znani.insert($0.id).inserted }
        stevci = zadnja.counts
        zadetkov = zadnja.total
        naslednjiOdmik = zadnja.nextOffset
        q = Self.kljuc(iskanje)
    }

    /// Pripne naslednjo stran. false (nic se ne spremeni), ce je vmes drugo iskanje ali stran ni za trenutni odmik (dvojni dotik).
    @discardableResult
    mutating func pripni(_ stran: SeznamVstopnicDogodka, iskanje: String, odmik: Int) -> Bool {
        guard q == Self.kljuc(iskanje), naslednjiOdmik == odmik else { return false }
        let znani = Set(vrstice.map(\.id))
        vrstice.append(contentsOf: stran.tickets.filter { !znani.contains($0.id) })
        stevci = stran.counts
        zadetkov = stran.total
        // Odmik se mora premakniti naprej, sicer bi gumb vedno nalozil isto stran.
        if let n = stran.nextOffset, n > odmik { naslednjiOdmik = n } else { naslednjiOdmik = nil }
        return true
    }

    /// Kosi za osvezitev po »Check in«: vse ze nalozene vrstice (najmanj ena stran), v kosih po najvec 1000 (meja `limit`),
    /// da vratar pri vec kot 1000 nalozenih ne izgubi mesta na seznamu.
    static func kosiOsvezitve(nalozenih: Int) -> [(offset: Int, limit: Int)] {
        let skupaj = max(APIClient.stranVstopnicVrata, nalozenih)
        var kosi: [(offset: Int, limit: Int)] = []
        var odmik = 0
        while odmik < skupaj {
            let l = min(APIClient.najvecVstopnicVrata, skupaj - odmik)
            kosi.append((offset: odmik, limit: l))
            odmik += l
        }
        return kosi
    }
}
