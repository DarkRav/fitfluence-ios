import Foundation

struct StoredAuthTokenProvider: AuthTokenProvider {
    let tokenStore: TokenStore

    func accessToken() async -> String? {
        (try? tokenStore.load())?.accessToken
    }
}
