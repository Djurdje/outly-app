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
}
