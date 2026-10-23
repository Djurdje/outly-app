import Foundation

struct APIEvent: Identifiable, Decodable {
    let id: Int
    let clubId: Int

    let title: String
    let description: String
    let posterUrl: String

    let startAt: String
    let endAt: String?

    let minAge: Int
    let genres: [String]

    /// DB publish status (npr. "published")
    let status: String

    /// Computed by API: "coming_soon" | "popular"
    let timeStatus: String?

    let createdAt: String?
    
    let ticketPriceCents: Int?
    let currency: String?
    let ticketUrl: String?

    /// Zaloga (migracija 002; javno od septembra 2026). capacity nil = brez omejitve.
    let capacity: Int?
    let soldCount: Int
    /// Streznik: "available" | "few_left" | "sold_out" | "external"
    let availability: String?

    /// Stanje dogodka (backend migracija 019): "upcoming" | "live" | "ended".
    /// Star backend polja nima -> privzeto "upcoming" (pravilo 2: nova polja s privzetkom).
    /// Za "ali je ze mimo" uporabljaj `hasEnded`, ne tega niza.
    let lifecycle: String
    /// Posnetek "kako je bilo" na koncanem dogodku (019). Prazen niz = brez videa.
    let recapVideoUrl: String
    /// Samo v GET /business/events: ali sme klub na ta dogodek naloziti posnetek
    /// (koncan IN med tremi najbolj popularnimi). Pravilo uveljavi streznik.
    let recapAllowed: Bool

    /// VIP mize (backend 025): dogodek ima vklopljen VIP IN klub ima vsaj eno aktivno mizo.
    /// Star backend polj nima -> false / nil (pravilo 2).
    let vipEnabled: Bool
    /// Najnizja efektivna cena vklopljene mize v centih; nil = ni VIP.
    let vipFromCents: Int?

    /// Ime kluba/organizatorja, ki dogodek objavlja (`club_id`); seznami ga vracajo z join-om.
    /// Star backend ali pot brez imena -> "".
    let clubName: String

    /// Prizorisce dogodka (backend 037, 9. 10. 2026). Dogodek organizatorja nosi ali klub gostitelja
    /// (`venueClubId`, ime in logo prideta z join-om) ali prosto vpisano lokacijo (`venueName` ...).
    /// Navaden klub prizorisca ne rabi (velja njegov naslov). Star backend polj nima -> privzetki.
    let venueClubId: Int?
    let venueClubName: String?
    let venueClubLogoUrl: String?
    let venueName: String
    let venueAddress: String
    let venueCity: String
    let venueLat: Double?
    let venueLng: Double?
    /// Samo v seznamu dogodkov kluba: dogodek organizatorja, ki ga klub GOSTI (club_id je organizatorjev).
    let hosted: Bool

    /// Nacin placila prodajalca (backend#203): "test" | "stripe" | "unavailable"; nil = star backend (glej `NacinPlacila`).
    /// Ni v favoritih/nacrtih (tam ni nakupa) -> nil.
    let paymentMode: String?

    /// Prodajalec dogodka (klub `club_id`) je demo klub (backend#243, 13. 10. 2026): znacka »Demo«, brez nakupa
    /// (409 `demo_club`; admin sme). Star backend polja ne poslje -> false. Ne zanasaj se samo na `payment_mode`:
    /// `unavailable` je lahko tudi `seller_incomplete` / `stripe_not_ready`.
    let isDemo: Bool

    /// Prodajalec (klub `club_id`) za vrstico »Sold by« in blok pred placilom (backend#94). Pride samo pri GET /events/:id;
    /// seznami in star backend ga nimajo -> nil (zaslon vzame prodajalca iz kluba, glej `Seller`).
    let seller: Seller?

    /// Pavza prodaje (backend 055, I53, 21. 10. 2026): admin ali klub je prodajo zacasno ustavil (cena ostane).
    /// Star backend polja nima -> false.
    let salesPaused: Bool
    /// Nakup je ta trenutek odprt po stanju, pavzi, zacetku in oknu prodaje (backend 055/#327). Ne pove cene ne zaloge
    /// (to sta `ticketPriceCents` in `availability`). Star backend polja nima -> true (vedenje kot doslej).
    let onSale: Bool
    /// Okno prodaje (#327): ISO cas ali nil (brez omejitve). Javni odgovor ju (23. 10. 2026) se ne vraca -> nil;
    /// ce ju backend doda, vrstica z vstopnicami pokaze »prodaja se odpre …« / »prodaja zaprta« namesto splosnega besedila.
    let salesOpenAt: String?
    let salesCloseAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubId = "club_id"
        case title, description
        case posterUrl = "poster_url"
        case startAt = "start_at"
        case endAt = "end_at"
        case minAge = "min_age"
        case genres
        case status
        case timeStatus = "time_status"
        case createdAt = "created_at"
        case ticketPriceCents = "ticket_price_cents"
        case currency
        case ticketUrl = "ticket_url"
        case capacity
        case soldCount = "sold_count"
        case availability
        case lifecycle
        case recapVideoUrl = "recap_video_url"
        case recapAllowed = "recap_allowed"
        case vipEnabled = "vip_enabled"
        case vipFromCents = "vip_from_cents"
        case clubName = "club_name"
        case venueClubId = "venue_club_id"
        case venueClubName = "venue_club_name"
        case venueClubLogoUrl = "venue_club_logo_url"
        case venueName = "venue_name"
        case venueAddress = "venue_address"
        case venueCity = "venue_city"
        case venueLat = "venue_lat"
        case venueLng = "venue_lng"
        case hosted
        case paymentMode = "payment_mode"
        case isDemo = "is_demo"
        case seller
        case salesPaused = "sales_paused"
        case onSale = "on_sale"
        case salesOpenAt = "sales_open_at"
        case salesCloseAt = "sales_close_at"
    }

    /// Obrambno dekodiranje (glej APIClub): NULL ali manjkajoc kljuc v eni vrstici
    /// ne sme podreti celotnega seznama dogodkov.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(Int.self, forKey: .id)
        clubId           = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        title            = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description      = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        posterUrl        = try c.decodeIfPresent(String.self, forKey: .posterUrl) ?? ""
        startAt          = try c.decodeIfPresent(String.self, forKey: .startAt) ?? ""
        endAt            = try c.decodeIfPresent(String.self, forKey: .endAt)
        minAge           = try c.decodeIfPresent(Int.self, forKey: .minAge) ?? 18
        genres           = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        status           = try c.decodeIfPresent(String.self, forKey: .status) ?? "published"
        timeStatus       = try c.decodeIfPresent(String.self, forKey: .timeStatus)
        createdAt        = try c.decodeIfPresent(String.self, forKey: .createdAt)
        ticketPriceCents = try c.decodeIfPresent(Int.self, forKey: .ticketPriceCents)
        currency         = try c.decodeIfPresent(String.self, forKey: .currency)
        ticketUrl        = try c.decodeIfPresent(String.self, forKey: .ticketUrl)
        capacity         = try c.decodeIfPresent(Int.self, forKey: .capacity)
        soldCount        = try c.decodeIfPresent(Int.self, forKey: .soldCount) ?? 0
        availability     = try c.decodeIfPresent(String.self, forKey: .availability)
        // Star backend teh polj nima (pravilo 2: novo polje vedno s privzeto vrednostjo).
        lifecycle        = (try? c.decodeIfPresent(String.self, forKey: .lifecycle)) ?? "upcoming"
        recapVideoUrl    = (try? c.decodeIfPresent(String.self, forKey: .recapVideoUrl)) ?? ""
        recapAllowed     = (try? c.decodeIfPresent(Bool.self, forKey: .recapAllowed)) ?? false
        vipEnabled       = (try? c.decodeIfPresent(Bool.self, forKey: .vipEnabled)) ?? false
        vipFromCents     = (try? c.decodeIfPresent(Int.self, forKey: .vipFromCents)) ?? nil
        clubName         = (try? c.decodeIfPresent(String.self, forKey: .clubName)) ?? ""
        venueClubId      = (try? c.decodeIfPresent(Int.self, forKey: .venueClubId)) ?? nil
        venueClubName    = (try? c.decodeIfPresent(String.self, forKey: .venueClubName)) ?? nil
        venueClubLogoUrl = (try? c.decodeIfPresent(String.self, forKey: .venueClubLogoUrl)) ?? nil
        venueName        = (try? c.decodeIfPresent(String.self, forKey: .venueName)) ?? ""
        venueAddress     = (try? c.decodeIfPresent(String.self, forKey: .venueAddress)) ?? ""
        venueCity        = (try? c.decodeIfPresent(String.self, forKey: .venueCity)) ?? ""
        venueLat         = (try? c.decodeIfPresent(Double.self, forKey: .venueLat)) ?? nil
        venueLng         = (try? c.decodeIfPresent(Double.self, forKey: .venueLng)) ?? nil
        hosted           = (try? c.decodeIfPresent(Bool.self, forKey: .hosted)) ?? false
        paymentMode      = (try? c.decodeIfPresent(String.self, forKey: .paymentMode)) ?? nil
        isDemo           = (try? c.decodeIfPresent(Bool.self, forKey: .isDemo)) ?? false
        seller           = (try? c.decodeIfPresent(Seller.self, forKey: .seller)) ?? nil
        salesPaused      = (try? c.decodeIfPresent(Bool.self, forKey: .salesPaused)) ?? false
        onSale           = (try? c.decodeIfPresent(Bool.self, forKey: .onSale)) ?? true
        salesOpenAt      = (try? c.decodeIfPresent(String.self, forKey: .salesOpenAt)) ?? nil
        salesCloseAt     = (try? c.decodeIfPresent(String.self, forKey: .salesCloseAt)) ?? nil
    }
}

extension APIEvent {
    /// Nacin placila za nakupni list (vstopnice); nil iz starega backenda -> `.neznan`.
    var nacinPlacila: NacinPlacila { NacinPlacila(paymentMode) }
}

// MARK: - Stanje prodaje (pavza in okno prodaje, backend 055 / #327)
extension APIEvent {
    /// Zakaj nakup ni odprt, ceprav ima dogodek ceno na Outlyju. nil = prodaja odprta (ali star backend brez `on_sale`).
    enum ZaprtaProdaja: Equatable {
        /// `sales_paused`: prodaja je zacasno ustavljena.
        case ustavljena
        /// Okno prodaje se ni odprto (cas odprtja, ce ga backend poslje).
        case odpreSe(Date)
        /// Okno prodaje je zaprto.
        case zaprta
        /// `on_sale == false` brez znanega razloga (javni odgovor okna ne vraca).
        case niOdprta
    }

    var openSalesDate: Date? { salesOpenAt.flatMap { DateParsing.parseBackendDate($0) } }
    var closeSalesDate: Date? { salesCloseAt.flatMap { DateParsing.parseBackendDate($0) } }

    /// Razlog, da prodaja ni odprta; odloca streznik (`on_sale`), aplikacija samo izbere besedilo.
    var zaprtaProdaja: ZaprtaProdaja? {
        if salesPaused { return .ustavljena }
        guard !onSale else { return nil }
        let zdaj = Date()
        if let odpre = openSalesDate, odpre > zdaj { return .odpreSe(odpre) }
        if let zapre = closeSalesDate, zapre < zdaj { return .zaprta }
        return .niOdprta
    }
}

// MARK: - Date helpers (UI)
extension APIEvent {
    var startDate: Date? { DateParsing.parseBackendDate(startAt) }
    var endDate: Date? { endAt.flatMap { DateParsing.parseBackendDate($0) } }

    var displayDateShort: String {
        guard let d = startDate else { return startAt }
        return DateParsing.shortDate.string(from: d)  // npr. 21/6
    }

    var displayTimeShort: String {
        guard let d = startDate else { return "" }
        return DateParsing.shortTime.string(from: d)  // npr. 23:00
    }
}

enum DateParsing {
    // Nastavljeno enkrat: spreminjanje formatOptions ob vsakem klicu je bilo
    // tekmovanje med socasnimi klici (HomeView nalaga tri sezname hkrati).
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d/M"
        return f
    }()

    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Ze razclenjeni nizi (29. 9. 2026, "aplikacija steka"): `startDate` je racunana lastnost in
    /// domaci zaslon z njo razvrsca vse dogodke veckrat na izris (Tonight, This week, Weekend, vsak
    /// zanr posebej) — to je bilo na tisoce ISO razclenitev na izris. Niz datuma je nespremenljiv,
    /// zato rezultat hranimo. Omejeno na 5000 vnosov (potem pocistimo), da ne raste v neskoncnost.
    private static let zaklep = NSLock()
    nonisolated(unsafe) private static var predpomnilnik: [String: Date?] = [:]

    static func parseBackendDate(_ s: String) -> Date? {
        zaklep.lock()
        if let d = predpomnilnik[s] { zaklep.unlock(); return d }
        zaklep.unlock()
        let d = razcleni(s)
        zaklep.lock()
        if predpomnilnik.count > 5000 { predpomnilnik.removeAll(keepingCapacity: true) }
        predpomnilnik[s] = d
        zaklep.unlock()
        return d
    }

    /// DateFormatter za dani vzorec v trenutnem jeziku aplikacije — enkrat na (jezik, vzorec),
    /// ne ob vsakem izrisu kartice (ustvarjanje DateFormatterja je drago).
    nonisolated(unsafe) private static var oblikovalniki: [String: DateFormatter] = [:]

    static func oblikovalnik(_ vzorec: String) -> DateFormatter {
        let locale = Jezik.shared.locale
        let kljuc = locale.identifier + "|" + vzorec
        zaklep.lock()
        defer { zaklep.unlock() }
        if let f = oblikovalniki[kljuc] { return f }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = vzorec
        oblikovalniki[kljuc] = f
        return f
    }

    private static func razcleni(_ s: String) -> Date? {
        // pg vrne ISO niz, obicajno z milisekundami ("2026-10-10T21:00:00.000Z")
        if let d = isoFrac.date(from: s) { return d }
        if let d = iso.date(from: s) { return d }
        // fallback: "YYYY-MM-DD HH:MM:SS" brez casovnega pasu
        return plain.date(from: s)
    }
}

extension APIEvent {
    /// Dogodek je KONCAN (backend 019). Backend odloci po `COALESCE(end_at, start_at + 8 h)`;
    /// ce polja ni (star backend), isto izracunamo tu, da se meja ne razide.
    var hasEnded: Bool {
        if lifecycle == "ended" { return true }
        if lifecycle == "live" || lifecycle == "upcoming" { return false }
        let konec = endDate ?? startDate?.addingTimeInterval(8 * 3600)
        guard let konec else { return false }
        return konec <= Date()
    }

    /// Posnetek "kako je bilo" — samo na koncanem dogodku in samo, ce ga je klub nalozil.
    var recapVideoURL: URL? {
        guard hasEnded, !recapVideoUrl.isEmpty else { return nil }
        return URL(string: recapVideoUrl)
    }

    var isPast: Bool {
        // najprej uporabi timeStatus, če ga backend pošlje
        if let ts = timeStatus {
            return ts == "popular"
        }
        // fallback: primerjaj datume, če timeStatus ni
        if let d = startDate {
            return d <= Date()
        }
        return false
    }

    var displayPrice: String? { napisCene(cenaCents: nil) }

    /// Cena ene vstopnice: `cenaCents` (sveza cena po 409) nadomesti `ticketPriceCents`; dogodek brez cene ostane brez cene.
    func veljavnaCenaCents(cenaCents: Int?) -> Int? {
        ticketPriceCents == nil ? nil : (cenaCents ?? ticketPriceCents)
    }

    /// Napis cene za dogodek, ki ima ceno na Outlyju. `cenaCents` (npr. sveza cena po 409 »The ticket price has changed.«)
    /// nadomesti `ticketPriceCents`; dogodek brez cene (zunanja prodaja, vrata) tudi z njo ostane brez cene.
    func napisCene(cenaCents: Int?) -> String? {
        guard let cents = veljavnaCenaCents(cenaCents: cenaCents) else { return nil }
        let amount = Double(cents) / 100.0

        let code = (currency ?? "EUR").uppercased()
        let symbol: String
        switch code {
        case "EUR": symbol = "€"
        case "USD": symbol = "$"
        case "GBP": symbol = "£"
        default: symbol = code + " "
        }

        return "\(symbol)\(String(format: "%.2f", amount))"
    }
}

// MARK: - Zaloga in cas (oznake na karticah)
extension APIEvent {
    var isSoldOut: Bool { availability == "sold_out" }

    /// Napis cene na karticah. Brez cene NI "Free": NULL cena pomeni, da vstopnic
    /// ni na Outlyju (zunanja prodaja ali na vratih) — "Free" je samo pri ceni 0.
    var priceLabel: String {
        if isSoldOut { return "—" }
        if let p = displayPrice { return p }
        if let u = ticketUrl, !u.isEmpty { return String(localized: "Tickets") }
        return String(localized: "At the door")
    }
    var isFewLeft: Bool { availability == "few_left" }
    var ticketsLeft: Int? { capacity.map { max(0, $0 - soldCount) } }

    /// Kratka oznaka za kartico ali nil, ce ni nic posebnega.
    var badgeText: String? {
        if isPast { return nil }
        if isSoldOut { return String(localized: "SOLD OUT") }
        if isFewLeft, let n = ticketsLeft { return n == 1 ? String(localized: "LAST ONE") : String(localized: "\(n) LEFT") }
        if ticketPriceCents == nil, let u = ticketUrl, !u.isEmpty { return nil }
        if ticketPriceCents == 0 { return String(localized: "FREE") }
        return nil
    }

    var isToday: Bool {
        guard let d = startDate else { return false }
        return Calendar.current.isDateInToday(d) || (d > Date() && d.timeIntervalSinceNow < 6 * 3600)
    }

    /// Petek ali sobota (ali nedelja) tega tedna, ki se ni minil.
    var isThisWeekend: Bool {
        guard let d = startDate, d > Date() else { return false }
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: d) // 1 = nedelja, 6 = petek, 7 = sobota
        guard wd == 6 || wd == 7 || wd == 1 else { return false }
        return d.timeIntervalSinceNow < 8 * 24 * 3600
    }

    /// "Fri 11 Sep · 22:00"
    var displayDayTime: String {
        guard let d = startDate else { return "" }
        return DateParsing.oblikovalnik("EEE d MMM · HH:mm").string(from: d)
    }

    /// "Sat 26 Sep" (brez ure) — kartice nacrtov prijateljev.
    var displayDayShort: String {
        guard let d = startDate else { return "" }
        return DateParsing.oblikovalnik("EEE d MMM").string(from: d)
    }
}

// MARK: - Prizorisce ("kje je dogodek", dogovor 9. 10. 2026)
extension APIEvent {
    /// Dogodek ima prizorisce, ki ni klubov lastni naslov: klub gostitelj ali prosto vpisana lokacija.
    var imaPrizorisce: Bool { venueClubId != nil || !venueName.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Ime prizorisca: klub gostitelj, sicer `venue_name`; "" = velja naslov kluba, ki dogodek objavlja.
    var imePrizorisca: String {
        let klub = (venueClubName ?? "").trimmingCharacters(in: .whitespaces)
        if venueClubId != nil, !klub.isEmpty { return klub }
        return venueName.trimmingCharacters(in: .whitespaces)
    }

    /// Prosto vpisan naslov prizorisca ("Ulica 1, Ljubljana"); "" ce ga ni ali je prizorisce klub gostitelj.
    var naslovPrizorisca: String {
        guard venueClubId == nil else { return "" }
        return [venueAddress, venueCity]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Kratek opis, kje je dogodek: "Ime prizorisca · Mesto". `gostitelj` je klub z `venueClubId`
    /// (njegovo mesto), `organizator` klub, ki dogodek objavlja (velja, ko prizorisca ni).
    /// Mesto se prikaze vedno, ce ga poznamo.
    func kjeJe(gostitelj: APIClub?, organizator: APIClub?) -> String {
        var ime = imePrizorisca
        var mesto = ""
        if venueClubId != nil {
            if ime.isEmpty { ime = gostitelj?.name ?? "" }
            mesto = gostitelj?.city ?? ""
        } else if imaPrizorisce {
            mesto = venueCity
        } else {
            ime = organizator?.name ?? ""
            mesto = organizator?.city ?? ""
        }
        return [ime, mesto]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }
}
