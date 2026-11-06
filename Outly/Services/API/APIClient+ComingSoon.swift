import Foundation

// »Coming soon«: klubi, s katerimi je podpisana pogodba, a jih se ni v bazi (6. 11. 2026).
// GET /coming-soon je javna pot (brez prijave). To NISO pravi klubi: nimajo `id`, sledenja ne dogodkov.
// Star backend poti nima (404) -> klicatelj sekcijo tiho skrije.

/// Klub »Coming soon«. `id` = `slug` (stabilen, a-z 0-9 -). Vsa polja so nizi; prazen niz = ni podatka.
struct ComingSoonClub: Decodable, Identifiable, Hashable {
    let slug: String
    let name: String
    let city: String
    let address: String
    let logoUrl: String
    let coverUrl: String
    let website: String
    /// Uporabnisko ime brez @ in brez URL-ja.
    let instagram: String

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, city, address, website, instagram
        case logoUrl = "logo_url"
        case coverUrl = "cover_url"
    }

    init(slug: String = "", name: String = "", city: String = "", address: String = "",
         logoUrl: String = "", coverUrl: String = "", website: String = "", instagram: String = "") {
        self.slug = slug
        self.name = name
        self.city = city
        self.address = address
        self.logoUrl = logoUrl
        self.coverUrl = coverUrl
        self.website = website
        self.instagram = instagram
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug      = (try? c.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        name      = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        city      = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? ""
        address   = (try? c.decodeIfPresent(String.self, forKey: .address)) ?? ""
        logoUrl   = (try? c.decodeIfPresent(String.self, forKey: .logoUrl)) ?? ""
        coverUrl  = (try? c.decodeIfPresent(String.self, forKey: .coverUrl)) ?? ""
        website   = (try? c.decodeIfPresent(String.self, forKey: .website)) ?? ""
        instagram = (try? c.decodeIfPresent(String.self, forKey: .instagram)) ?? ""
    }

    /// Samo `https` (pogodba); sicer nil -> element se skrije / nadomestek.
    static func httpsURL(_ niz: String) -> URL? {
        let t = niz.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let url = URL(string: t), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var logoURL: URL? { Self.httpsURL(logoUrl) }
    var coverURL: URL? { Self.httpsURL(coverUrl) }
    var websiteURL: URL? { Self.httpsURL(website) }

    /// https://www.instagram.com/<uporabnisko ime>/ ; nil, ce polje ni prazno-varno uporabnisko ime.
    var instagramURL: URL? {
        var u = instagram.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.hasPrefix("@") { u.removeFirst() }
        guard !u.isEmpty, u.range(of: "^[A-Za-z0-9._]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.instagram.com/\(u)/")
    }
}

extension APIClient {
    private struct ComingSoonOdgovor: Decodable {
        let clubs: [ComingSoonClub]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clubs = (try? c.decodeIfPresent([ComingSoonClub].self, forKey: .clubs)) ?? []
        }
        enum CodingKeys: String, CodingKey { case clubs }
    }

    /// GET /coming-soon — javno, brez zetona. Vrstni red = vrstni red prikaza; brez slug-a in podvojeni se odstranijo.
    func fetchComingSoon() async throws -> [ComingSoonClub] {
        let data = try await send(path: "coming-soon", method: "GET")
        let vsi = try decode(ComingSoonOdgovor.self, from: data).clubs
        var videni = Set<String>()
        return vsi.filter { !$0.slug.isEmpty && !$0.name.isEmpty && videni.insert($0.slug).inserted }
    }
}
