import AppAuth
import AuthenticationServices
import Foundation
import UIKit

enum LoginEntryMode: String, Sendable {
    case login
    case createAccount
}

protocol AuthServiceProtocol: Sendable {
    @MainActor
    func login(mode: LoginEntryMode) async -> Result<TokenSet, APIError>

    func refreshIfNeeded() async -> Bool
    func refresh() async -> Bool
    func logout() async
    func currentTokenSet() async -> TokenSet?
}

final class AuthService: NSObject, AuthServiceProtocol, @unchecked Sendable {
    private let environment: AppEnvironment
    private let discoveryService: OIDCDiscoveryServiceProtocol
    private let tokenStore: TokenStore
    private let refreshCoordinator = RefreshCoordinator()
    @MainActor
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    init(
        environment: AppEnvironment,
        discoveryService: OIDCDiscoveryServiceProtocol,
        tokenStore: TokenStore = KeychainTokenStore(),
    ) {
        self.environment = environment
        self.discoveryService = discoveryService
        self.tokenStore = tokenStore
    }

    @MainActor
    func login(mode: LoginEntryMode) async -> Result<TokenSet, APIError> {
        let configuredScopes = environment.keycloakScopes
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        let primaryScopes = configuredScopes.isEmpty ? ["openid"] : configuredScopes
        let scopeVariants: [[String]] = primaryScopes == ["openid"] ? [primaryScopes] : [primaryScopes, ["openid"]]

        for scopes in scopeVariants {
            do {
                return try await .success(performLogin(mode: mode, scopes: scopes))
            } catch let apiError as APIError {
                let isInvalidScope = if case let .httpError(statusCode, bodySnippet) = apiError {
                    statusCode == 400 && bodySnippet?.contains("invalid_scope") == true
                } else {
                    false
                }

                if isInvalidScope, scopes != ["openid"] {
                    FFLog.info("OIDC login invalid_scope for configured scopes, retry with openid only")
                    continue
                }

                FFLog.error("OIDC login failed with APIError: \(String(describing: apiError))")
                return .failure(apiError)
            } catch {
                FFLog.error("OIDC login failed with unexpected error: \(error.localizedDescription)")
                return .failure(.unknown)
            }
        }

        return .failure(.unknown)
    }

    func refreshIfNeeded() async -> Bool {
        guard let tokenSet = currentTokenSetSync() else { return false }
        guard tokenSet.isAccessTokenNearExpiry() else { return true }
        return await refresh()
    }

    func refresh() async -> Bool {
        await refreshCoordinator.run { [self] in
            do {
                guard let refreshToken = try self.tokenStore.load()?.refreshToken else {
                    return false
                }

                let discovery = try await self.discoveryService.discover()
                let configuration = OIDServiceConfiguration(
                    authorizationEndpoint: discovery.authorizationEndpoint,
                    tokenEndpoint: discovery.tokenEndpoint,
                    issuer: discovery.issuer,
                    registrationEndpoint: nil,
                    endSessionEndpoint: discovery.endSessionEndpoint,
                )

                let tokenRequest = OIDTokenRequest(
                    configuration: configuration,
                    grantType: OIDGrantTypeRefreshToken,
                    authorizationCode: nil,
                    redirectURL: nil,
                    clientID: self.environment.keycloakClientId,
                    clientSecret: nil,
                    scope: nil,
                    refreshToken: refreshToken,
                    codeVerifier: nil,
                    additionalParameters: nil,
                )

                let response = try await self.perform(tokenRequest: tokenRequest)
                let nextTokenSet = self.tokenSet(from: response, fallbackRefreshToken: refreshToken)
                try self.tokenStore.save(nextTokenSet)
                return true
            } catch {
                try? self.tokenStore.clear()
                return false
            }
        }
    }

    func logout() async {
        try? tokenStore.clear()
    }

    func currentTokenSet() async -> TokenSet? {
        currentTokenSetSync()
    }

    private func currentTokenSetSync() -> TokenSet? {
        try? tokenStore.load()
    }

    private func registrationParameters(for mode: LoginEntryMode) -> [String: String]? {
        guard mode == .createAccount else { return nil }
        guard environment.keycloakRegistrationHintMode == "kc_action" else { return nil }
        return ["kc_action": "register"]
    }

    @MainActor
    private func performLogin(mode: LoginEntryMode, scopes: [String]) async throws -> TokenSet {
        let discovery = try await discoveryService.discover()

        guard
            let redirectURL = environment.keycloakRedirectURI,
            !environment.keycloakClientId.isEmpty
        else {
            throw APIError.invalidURL
        }

        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: discovery.authorizationEndpoint,
            tokenEndpoint: discovery.tokenEndpoint,
            issuer: discovery.issuer,
            registrationEndpoint: nil,
            endSessionEndpoint: discovery.endSessionEndpoint,
        )

        let authRequest = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: environment.keycloakClientId,
            clientSecret: nil,
            scopes: scopes,
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: registrationParameters(for: mode),
        )

        guard let presentingViewController = UIApplication.topViewController() else {
            throw APIError.unknown
        }
        let authState = try await present(request: authRequest, from: presentingViewController)

        guard let tokenResponse = authState.lastTokenResponse else {
            throw APIError.unknown
        }

        let tokenSet = tokenSet(from: tokenResponse)
        guard !tokenSet.accessToken.isEmpty else {
            FFLog.error("OIDC login completed without access token")
            throw APIError.unauthorized
        }
        try tokenStore.save(tokenSet)
        return tokenSet
    }

    private func tokenSet(from response: OIDTokenResponse, fallbackRefreshToken: String? = nil) -> TokenSet {
        TokenSet(
            accessToken: response.accessToken ?? "",
            refreshToken: response.refreshToken ?? fallbackRefreshToken,
            idToken: response.idToken,
            tokenType: response.tokenType ?? "Bearer",
            scope: response.scope,
            expiresAt: response.accessTokenExpirationDate,
        )
    }

    @MainActor
    private func present(
        request: OIDAuthorizationRequest,
        from presentingViewController: UIViewController,
    ) async throws -> OIDAuthState {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let resumeOnce: (Result<OIDAuthState, APIError>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                switch result {
                case let .success(state):
                    continuation.resume(returning: state)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            let flow = OIDAuthState.authState(byPresenting: request, presenting: presentingViewController) {
                [weak self] authState, error in
                Task { @MainActor in
                    self?.currentAuthorizationFlow = nil
                }

                if let error = error as NSError? {
                    FFLog
                        .error(
                            "OIDC auth callback error domain=\(error.domain) code=\(error.code) message=\(error.localizedDescription)",
                        )
                    if error.domain == OIDOAuthAuthorizationErrorDomain,
                       error.code == OIDErrorCodeOAuth.accessDenied.rawValue
                    {
                        resumeOnce(.failure(.cancelled))
                        return
                    }

                    if error.domain == OIDOAuthAuthorizationErrorDomain,
                       error.code == OIDErrorCodeOAuth.invalidScope.rawValue
                    {
                        resumeOnce(.failure(.httpError(statusCode: 400, bodySnippet: "invalid_scope")))
                        return
                    }

                    if error.domain == OIDGeneralErrorDomain, error.code == -3 {
                        resumeOnce(.failure(.cancelled))
                        return
                    }

                    if error.domain == ASWebAuthenticationSessionErrorDomain,
                       error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    {
                        resumeOnce(.failure(.cancelled))
                        return
                    }

                    if error.domain == NSURLErrorDomain {
                        let code = URLError.Code(rawValue: error.code)
                        resumeOnce(.failure(APIError.from(urlError: URLError(code))))
                        return
                    }

                    resumeOnce(.failure(.unknown))
                    return
                }

                guard let authState else {
                    resumeOnce(.failure(.unknown))
                    return
                }

                resumeOnce(.success(authState))
            }

            Task { @MainActor in
                currentAuthorizationFlow = flow
            }

            _ = flow
        }
    }

    private func perform(tokenRequest: OIDTokenRequest) async throws -> OIDTokenResponse {
        try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(tokenRequest) { response, error in
                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain {
                        let code = URLError.Code(rawValue: error.code)
                        continuation.resume(throwing: APIError.from(urlError: URLError(code)))
                    } else {
                        continuation.resume(throwing: APIError.unknown)
                    }
                    return
                }

                guard let response else {
                    continuation.resume(throwing: APIError.unknown)
                    return
                }

                continuation.resume(returning: response)
            }
        }
    }
}

private extension UIApplication {
    static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController,
    ) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = base as? UITabBarController, let selected = tabBarController.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

actor RefreshCoordinator {
    private var runningTask: Task<Bool, Never>?

    func run(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
        if let runningTask {
            return await runningTask.value
        }

        let task = Task { await operation() }
        runningTask = task
        let value = await task.value
        runningTask = nil
        return value
    }
}
