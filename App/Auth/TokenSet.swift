import Foundation

struct TokenSet: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let tokenType: String
    let scope: String?
    let expiresAt: Date?

    func isAccessTokenExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    func isAccessTokenNearExpiry(now: Date = Date(), leeway: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= leeway
    }
}
