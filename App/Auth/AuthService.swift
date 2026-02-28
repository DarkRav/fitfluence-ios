import AppAuth
import Foundation
import UIKit

enum LoginEntryMode: String, Sendable {
    case login
    case createAccount
}

protocol AuthServiceProtocol: Sendable {
    @MainActor
    func login(
        presentingViewController: UIViewController,
        mode: LoginEntryMode
    ) async -> Result<TokenSet, APIError>

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

    init(
        environment: AppEnvironment,
        discoveryService: OIDCDiscoveryServiceProtocol,
        tokenStore: TokenStore = KeychainTokenStore()
    ) {
        self.environment = environment
        self.discoveryService = discoveryService
        self.tokenStore = tokenStore
    }

    @MainActor
    func login(
        presentingViewController: UIViewController,
        mode: LoginEntryMode
    ) async -> Result<TokenSet, APIError> {
        do {
            let discovery = try await discoveryService.discover()

            guard
                let redirectURL = environment.keycloakRedirectURI,
                !environment.keycloakClientId.isEmpty
            else {
                return .failure(.invalidURL)
            }

            let configuration = OIDServiceConfiguration(
                authorizationEndpoint: discovery.authorizationEndpoint,
                tokenEndpoint: discovery.tokenEndpoint,
                issuer: discovery.issuer,
                registrationEndpoint: nil,
                endSessionEndpoint: discovery.endSessionEndpoint
            )

            let scopes = environment.keycloakScopes
                .split(separator: " ")
                .map(String.init)

            let authRequest = OIDAuthorizationRequest(
                configuration: configuration,
                clientId: environment.keycloakClientId,
                clientSecret: nil,
                scopes: scopes,
                redirectURL: redirectURL,
                responseType: OIDResponseTypeCode,
                additionalParameters: registrationParameters(for: mode)
            )

            let authState = try await present(request: authRequest, from: presentingViewController)

            guard let tokenResponse = authState.lastTokenResponse else {
                return .failure(.unknown)
            }

            let tokenSet = tokenSet(from: tokenResponse)
            try tokenStore.save(tokenSet)
            return .success(tokenSet)
        } catch let apiError as APIError {
            return .failure(apiError)
        } catch {
            return .failure(.unknown)
        }
    }

    func refreshIfNeeded() async -> Bool {
        guard let tokenSet = currentTokenSetSync() else { return false }
        guard tokenSet.isAccessTokenNearExpiry() else { return true }
        return await refresh()
    }

    func refresh() async -> Bool {
        await refreshCoordinator.run {
            do {
                guard let tokenSet = try tokenStore.load(), let refreshToken = tokenSet.refreshToken else {
                    return false
                }

                let discovery = try await discoveryService.discover()
                let configuration = OIDServiceConfiguration(
                    authorizationEndpoint: discovery.authorizationEndpoint,
                    tokenEndpoint: discovery.tokenEndpoint,
                    issuer: discovery.issuer,
                    registrationEndpoint: nil,
                    endSessionEndpoint: discovery.endSessionEndpoint
                )

                let tokenRequest = OIDTokenRequest(
                    configuration: configuration,
                    grantType: OIDGrantTypeRefreshToken,
                    authorizationCode: nil,
                    redirectURL: nil,
                    clientID: environment.keycloakClientId,
                    clientSecret: nil,
                    scope: environment.keycloakScopes,
                    refreshToken: refreshToken,
                    codeVerifier: nil,
                    additionalParameters: nil
                )

                let response = try await perform(tokenRequest: tokenRequest)
                let nextTokenSet = tokenSet(from: response, fallbackRefreshToken: refreshToken)
                try tokenStore.save(nextTokenSet)
                return true
            } catch {
                try? tokenStore.clear()
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

    private func tokenSet(from response: OIDTokenResponse, fallbackRefreshToken: String? = nil) -> TokenSet {
        TokenSet(
            accessToken: response.accessToken ?? "",
            refreshToken: response.refreshToken ?? fallbackRefreshToken,
            idToken: response.idToken,
            tokenType: response.tokenType ?? "Bearer",
            scope: response.scope,
            expiresAt: response.accessTokenExpirationDate
        )
    }

    @MainActor
    private func present(request: OIDAuthorizationRequest, from presentingViewController: UIViewController) async throws -> OIDAuthState {
        try await withCheckedThrowingContinuation { continuation in
            OIDAuthState.authState(byPresenting: request, presenting: presentingViewController) { authState, error in
                if let error = error as NSError? {
                    if error.domain == OIDOAuthAuthorizationErrorDomain, error.code == OIDErrorCodeOAuth.accessDenied.rawValue {
                        continuation.resume(throwing: APIError.cancelled)
                    } else {
                        continuation.resume(throwing: APIError.unknown)
                    }
                    return
                }

                guard let authState else {
                    continuation.resume(throwing: APIError.unknown)
                    return
                }
                continuation.resume(returning: authState)
            }
        }
    }

    private func perform(tokenRequest: OIDTokenRequest) async throws -> OIDTokenResponse {
        try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(tokenRequest) { response, error in
                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain, let code = URLError.Code(rawValue: error.code) {
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
