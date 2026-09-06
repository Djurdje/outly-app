import Foundation

struct Me: Decodable {
    let id: Int
    let email: String
    let username: String
    let role: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email, username, role
        case avatarUrl = "avatar_url"
    }
}
