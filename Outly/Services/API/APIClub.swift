//
//  Club.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import Foundation

struct APIClub: Identifiable, Decodable {
    let id: Int
    let ownerUserId: Int
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

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
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
    }

    /// Obrambno dekodiranje: shema ima NOT NULL DEFAULT '' na besedilih, a ce bi
    /// kdaj prisel NULL ali manjkajoc kljuc, ne sme pasti dekodiranje CELOTNEGA seznama.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(Int.self, forKey: .id)
        ownerUserId  = try c.decodeIfPresent(Int.self, forKey: .ownerUserId) ?? 0
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
    }
}
