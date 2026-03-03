@testable import FitfluenceApp
import XCTest

final class OIDCAndTokenStoreTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.error = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testOIDCDiscoveryParsesDocument() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
              "issuer": "http://localhost:9990/realms/master",
              "authorization_endpoint": "http://localhost:9990/realms/master/protocol/openid-connect/auth",
              "token_endpoint": "http://localhost:9990/realms/master/protocol/openid-connect/token",
              "end_session_endpoint": "http://localhost:9990/realms/master/protocol/openid-connect/logout"
            }
            """
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data(json.utf8))
        }

        let service = try OIDCDiscoveryService(
            baseURL: XCTUnwrap(URL(string: "http://localhost:9990")),
            realm: "master",
            session: testSession,
        )
        let document = try await service.discover()

        XCTAssertEqual(document.issuer.absoluteString, "http://localhost:9990/realms/master")
        XCTAssertEqual(
            document.authorizationEndpoint.absoluteString,
            "http://localhost:9990/realms/master/protocol/openid-connect/auth",
        )
        XCTAssertEqual(
            document.tokenEndpoint.absoluteString,
            "http://localhost:9990/realms/master/protocol/openid-connect/token",
        )
    }

    func testOIDCDiscoveryRewritesLoopbackEndpointsToConfiguredHost() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
              "issuer": "http://localhost:9990/realms/fitfluence",
              "authorization_endpoint": "http://localhost:9990/realms/fitfluence/protocol/openid-connect/auth",
              "token_endpoint": "http://localhost:9990/realms/fitfluence/protocol/openid-connect/token",
              "end_session_endpoint": "http://localhost:9990/realms/fitfluence/protocol/openid-connect/logout"
            }
            """
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data(json.utf8))
        }

        let service = try OIDCDiscoveryService(
            baseURL: XCTUnwrap(URL(string: "http://192.168.88.137:9990")),
            realm: "fitfluence",
            session: testSession,
        )
        let document = try await service.discover()

        XCTAssertEqual(document.issuer.absoluteString, "http://192.168.88.137:9990/realms/fitfluence")
        XCTAssertEqual(
            document.authorizationEndpoint.absoluteString,
            "http://192.168.88.137:9990/realms/fitfluence/protocol/openid-connect/auth",
        )
        XCTAssertEqual(
            document.tokenEndpoint.absoluteString,
            "http://192.168.88.137:9990/realms/fitfluence/protocol/openid-connect/token",
        )
    }

    func testOIDCDiscoveryRewritesStaleIPEndpointsToConfiguredHost() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
              "issuer": "http://192.168.88.81:9990/realms/fitfluence",
              "authorization_endpoint": "http://192.168.88.81:9990/realms/fitfluence/protocol/openid-connect/auth",
              "token_endpoint": "http://192.168.88.81:9990/realms/fitfluence/protocol/openid-connect/token",
              "end_session_endpoint": "http://192.168.88.81:9990/realms/fitfluence/protocol/openid-connect/logout"
            }
            """
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data(json.utf8))
        }

        let service = try OIDCDiscoveryService(
            baseURL: XCTUnwrap(URL(string: "http://192.168.88.137:9990")),
            realm: "fitfluence",
            session: testSession,
        )
        let document = try await service.discover()

        XCTAssertEqual(document.issuer.absoluteString, "http://192.168.88.137:9990/realms/fitfluence")
        XCTAssertEqual(
            document.authorizationEndpoint.absoluteString,
            "http://192.168.88.137:9990/realms/fitfluence/protocol/openid-connect/auth",
        )
        XCTAssertEqual(
            document.tokenEndpoint.absoluteString,
            "http://192.168.88.137:9990/realms/fitfluence/protocol/openid-connect/token",
        )
    }

    func testTokenSetExpiryChecks() {
        let now = Date()
        let expired = TokenSet(
            accessToken: "a",
            refreshToken: "r",
            idToken: nil,
            tokenType: "Bearer",
            scope: "openid",
            expiresAt: now.addingTimeInterval(-10),
        )

        XCTAssertTrue(expired.isAccessTokenExpired(now: now))
        XCTAssertTrue(expired.isAccessTokenNearExpiry(now: now, leeway: 30))
    }

    func testKeychainTokenStoreSaveLoadClear() throws {
        let store = KeychainTokenStore(service: "com.fitfluence.tests.auth", account: UUID().uuidString)
        let tokenSet = TokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: "id",
            tokenType: "Bearer",
            scope: "openid profile",
            expiresAt: Date().addingTimeInterval(3600),
        )

        do {
            try store.clear()
            try store.save(tokenSet)

            let loaded = try store.load()
            XCTAssertEqual(loaded, tokenSet)

            try store.clear()
            XCTAssertNil(try store.load())
        } catch let TokenStoreError.keychain(status) where status == -34018 {
            throw XCTSkip("Keychain недоступен в текущем окружении тестов (status: -34018).")
        }
    }

    private var testSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
