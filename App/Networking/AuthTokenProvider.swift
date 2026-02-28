import Foundation

protocol AuthTokenProvider: Sendable {
    func accessToken() async -> String?
}

struct NoAuthTokenProvider: AuthTokenProvider {
    func accessToken() async -> String? {
        nil
    }
}
