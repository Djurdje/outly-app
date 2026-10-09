//
//  Club.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import Foundation

struct APIClub: Identifiable, Decodable {
    let id: Int
    let name: String
    let logoUrl: String
    let bannerUrl: String
    let description: String

    let contactEmail: String
    let contactPhone: String
    let instagram: String
    let website: String

    let address: String
    let city: String
    let country: String

    let lat: Double?
    let lng: Double?

    let minAge: Int
    let genres: [String]
    let createdAt: String?

    /// Cenik bara (migracija 014). Prazen seznam = klub ga se ni vnesel.
    let barPrices: [BarPriceItem]
    /// Slideshow na strani kluba, do 3 slike (migracija 015). Prazno -> bannerUrl.
    let galleryUrls: [String]
    /// Predstavitveni video kluba (migracija 015). Prazen niz = brez videa.
    let videoUrl: String

    /// Stevilo sledilcev kluba (migracija 019). Star backend polja nima -> 0.
    let followersCount: Int
    /// Ali PRIJAVLJENI uporabnik sledi klubu. Pove samo GET /clubs/:id z zetonom;
    /// drugje ostane false in gumb Follow se popravi, ko se klub nalozi.
    let isFollowing: Bool

    /// Organizator dogodkov brez lastnega prizorisca (backend 037, 9. 10. 2026): ista stran kot klub,
    /// a brez naslova in pina na zemljevidu; vsak njegov dogodek nosi prizorisce. Star backend -> false.
    let isOrganizer: Bool
    /// Uradni profil podjetja Outly (nastavi samo admin): njegovi dogodki so na vrhu Home
    /// v razdelku "Organized by Outly". Star backend -> false.
    let isOfficial: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case logoUrl = "logo_url"
        case bannerUrl = "banner_url"
        case description

        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case instagram
        case website

        case address, city, country
        case lat, lng
        case minAge = "min_age"
        case genres
        case createdAt = "created_at"
        case barPrices = "bar_prices"
        case galleryUrls = "gallery_urls"
        case videoUrl = "video_url"
        case followersCount = "followers_count"
        case isFollowing = "is_following"
        case isOrganizer = "is_organizer"
        case isOfficial = "is_official"
    }

    /// Obrambno dekodiranje: shema ima NOT NULL DEFAULT '' na besedilih, a ce bi
    /// kdaj prisel NULL ali manjkajoc kljuc, ne sme pasti dekodiranje CELOTNEGA seznama.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(Int.self, forKey: .id)
        name         = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        logoUrl      = try c.decodeIfPresent(String.self, forKey: .logoUrl) ?? ""
        bannerUrl    = try c.decodeIfPresent(String.self, forKey: .bannerUrl) ?? ""
        description  = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        contactEmail = try c.decodeIfPresent(String.self, forKey: .contactEmail) ?? ""
        contactPhone = try c.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
        instagram    = try c.decodeIfPresent(String.self, forKey: .instagram) ?? ""
        website      = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
        address      = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        city         = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        country      = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        lat          = try c.decodeIfPresent(Double.self, forKey: .lat)
        lng          = try c.decodeIfPresent(Double.self, forKey: .lng)
        minAge       = try c.decodeIfPresent(Int.self, forKey: .minAge) ?? 18
        genres       = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        createdAt    = try c.decodeIfPresent(String.self, forKey: .createdAt)
        // Star backend brez stolpca ali pokvarjena postavka ne sme podreti kluba.
        barPrices    = (try? c.decodeIfPresent([BarPriceItem].self, forKey: .barPrices)) ?? []
        galleryUrls  = ((try? c.decodeIfPresent([String].self, forKey: .galleryUrls)) ?? []).filter { !$0.isEmpty }
        videoUrl     = (try? c.decodeIfPresent(String.self, forKey: .videoUrl)) ?? ""
        followersCount = (try? c.decodeIfPresent(Int.self, forKey: .followersCount)) ?? 0
        isFollowing    = (try? c.decodeIfPresent(Bool.self, forKey: .isFollowing)) ?? false
        isOrganizer    = (try? c.decodeIfPresent(Bool.self, forKey: .isOrganizer)) ?? false
        isOfficial     = (try? c.decodeIfPresent(Bool.self, forKey: .isOfficial)) ?? false
    }

    /// Slike za slideshow: galerija, sicer pasica (da stari klubi ostanejo enaki).
    var slideshowUrls: [String] {
        if !galleryUrls.isEmpty { return galleryUrls }
        return bannerUrl.isEmpty ? [] : [bannerUrl]
    }
}

/// Ena postavka cenika bara: ime, cena v centih, neobvezna kategorija (npr. "Beer").
struct BarPriceItem: Identifiable, Codable, Equatable {
    var name: String
    var priceCents: Int
    var category: String?

    /// Lokalen id za sezname v SwiftUI; backend postavk ne oznacuje.
    var id: String { "\(name)|\(priceCents)|\(category ?? "")" }

    enum CodingKeys: String, CodingKey {
        case name
        case priceCents = "price_cents"
        case category
    }

    init(name: String, priceCents: Int, category: String? = nil) {
        self.name = name
        self.priceCents = priceCents
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name       = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        priceCents = try c.decodeIfPresent(Int.self, forKey: .priceCents) ?? 0
        let cat    = try c.decodeIfPresent(String.self, forKey: .category)?.trimmingCharacters(in: .whitespaces)
        category   = (cat?.isEmpty ?? true) ? nil : cat
    }

    /// Slovar za PATCH /business/clubs/me (bar_prices).
    var json: [String: Any] {
        var d: [String: Any] = ["name": name, "price_cents": priceCents]
        if let category, !category.isEmpty { d["category"] = category }
        return d
    }
}
