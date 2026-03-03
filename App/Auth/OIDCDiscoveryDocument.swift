import Foundation

struct OIDCDiscoveryDocument: Codable, Equatable, Sendable {
    let issuer: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let endSessionEndpoint: URL?
    let userinfoEndpoint: URL?
    let jwksURI: URL?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case endSessionEndpoint = "end_session_endpoint"
        case userinfoEndpoint = "userinfo_endpoint"
        case jwksURI = "jwks_uri"
    }
}

protocol OIDCDiscoveryServiceProtocol: Sendable {
    func discover() async throws -> OIDCDiscoveryDocument
}

struct OIDCDiscoveryService: OIDCDiscoveryServiceProtocol {
    let baseURL: URL
    let realm: String
    var session: URLSession = .shared

    func discover() async throws -> OIDCDiscoveryDocument {
        guard !realm.isEmpty else {
            throw APIError.invalidURL
        }

        let endpoint = baseURL
            .appendingPathComponent("realms")
            .appendingPathComponent(realm)
            .appendingPathComponent(".well-known")
            .appendingPathComponent("openid-configuration")

        do {
            let (data, response) = try await session.data(from: endpoint)
            guard let httpResponse = response as? HTTPURLResponse else {
                FFLog.error("OIDC discovery: non-HTTP response from \(endpoint.absoluteString)")
                throw APIError.unknown
            }

            if let apiError = APIError.from(statusCode: httpResponse.statusCode, data: data) {
                FFLog.error(
                    "OIDC discovery failed status=\(httpResponse.statusCode) url=\(endpoint.absoluteString)",
                )
                throw apiError
            }

            do {
                let decoded = try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: data)
                return normalized(document: decoded)
            } catch {
                FFLog.error("OIDC discovery decoding failed for \(endpoint.absoluteString)")
                throw APIError.decodingError
            }
        } catch let apiError as APIError {
            throw apiError
        } catch let urlError as URLError {
            FFLog.error(
                "OIDC discovery network error code=\(urlError.code.rawValue) url=\(endpoint.absoluteString)",
            )
            throw APIError.from(urlError: urlError)
        } catch {
            FFLog.error("OIDC discovery unknown error for \(endpoint.absoluteString)")
            throw APIError.unknown
        }
    }

    private func normalized(document: OIDCDiscoveryDocument) -> OIDCDiscoveryDocument {
        OIDCDiscoveryDocument(
            issuer: normalizeIfLoopback(document.issuer),
            authorizationEndpoint: normalizeIfLoopback(document.authorizationEndpoint),
            tokenEndpoint: normalizeIfLoopback(document.tokenEndpoint),
            endSessionEndpoint: document.endSessionEndpoint.map(normalizeIfLoopback),
            userinfoEndpoint: document.userinfoEndpoint.map(normalizeIfLoopback),
            jwksURI: document.jwksURI.map(normalizeIfLoopback),
        )
    }

    private func normalizeIfLoopback(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else {
            return url
        }
        let isLoopback = host == "localhost" || host == "127.0.0.1"

        // Keycloak can return stale absolute URLs in discovery after host/IP changes.
        // For endpoints bound to our configured realm we trust runtime baseURL host.
        let realmBasePath = "/realms/\(realm)"
        let belongsToRealm = url.path == realmBasePath || url.path.hasPrefix("\(realmBasePath)/")
        let shouldRewriteHost = isLoopback || (belongsToRealm && host != (baseURL.host ?? "").lowercased())
        guard shouldRewriteHost else {
            return url
        }
        guard let targetHost = baseURL.host, !targetHost.isEmpty else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme
        components?.host = targetHost
        if let port = baseURL.port {
            components?.port = port
        }
        return components?.url ?? url
    }
}
