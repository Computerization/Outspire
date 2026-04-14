import Foundation

/// Minimal user model inferred from the new server's /Home/Login response
struct V2User: Codable {
    let userId: Int?
    let userCode: String?
    let name: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case userCode = "UserCode"
        case name = "Name"
        case role = "Role"
    }
}
