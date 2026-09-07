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
    static let iso = ISO8601DateFormatter()
    static let isoFrac = ISO8601DateFormatter()

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

    static func parseBackendDate(_ s: String) -> Date? {
        // pg pogosto vrne ISO string; včasih z fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }

        // fallback: "YYYY-MM-DD HH:MM:SS" brez timezone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: s) { return d }

        return nil
    }
}

extension APIEvent {
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

    var displayPrice: String? {
        guard let cents = ticketPriceCents else { return nil }
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
