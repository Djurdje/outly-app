//
//  AuthModels.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 8. 1. 26.
//

import Foundation

struct LoginResponse: Decodable {
    let token: String
}

struct MeResponse: Decodable {
    let id: Int
    let email: String
    let username: String?
    let created_at: String
}
