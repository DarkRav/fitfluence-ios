import Foundation

enum LoginEntryMode: String, Sendable {
    case login
    case createAccount
    case apple
}

protocol AuthServiceProtocol: Sendable {
    @MainActor
    func login(mode: LoginEntryMode) async -> Result<TokenSet, APIError>

    func refreshIfNeeded() async -> Bool
    func refresh() async -> Bool
    func logout() async
    func currentTokenSet() async -> TokenSet?
    func validateExternalCredentialIfNeeded() async -> Bool
}

protocol BackendAuthClientProtocol: Sendable {
    func loginWithApple(_ payload: AppleAuthorizationPayload) async -> Result<BackendAppleAuthResponse, APIError>
    func refresh(refreshToken: String) async -> Result<BackendTokenRefreshResponse, APIError>
    func logout(refreshToken: String) async
}

struct BackendAppleAuthResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}

struct BackendTokenRefreshResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}

final class BackendAuthClient: BackendAuthClientProtocol {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL) {
        self.session = session
        self.baseURL = baseURL
    }

    func loginWithApple(_ payload: AppleAuthorizationPayload) async -> Result<BackendAppleAuthResponse, APIError> {
        await send(
            path: "v1/auth/apple/native",
            body: [
                "identityToken": payload.identityToken,
                "authorizationCode": payload.authorizationCode,
            ],
            responseType: BackendAppleAuthResponse.self,
        )
    }

    func refresh(refreshToken: String) async -> Result<BackendTokenRefreshResponse, APIError> {
        await send(
            path: "v1/auth/refresh",
            body: ["refreshToken": refreshToken],
            responseType: BackendTokenRefreshResponse.self,
        )
    }

    func logout(refreshToken: String) async {
        _ = await send(
            path: "v1/auth/logout",
            body: ["refreshToken": refreshToken],
            responseType: EmptyResponse.self,
            expectedStatusCodes: [204],
        )
    }

    private func send<Response: Decodable>(
        path: String,
        body: [String: String],
        responseType: Response.Type,
        expectedStatusCodes: Set<Int> = [200],
    ) async -> Result<Response, APIError> {
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(sanitizedPath)
        guard url.host?.isEmpty == false else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknown)
            }

            if !expectedStatusCodes.contains(httpResponse.statusCode) {
                if let apiError = APIError.from(statusCode: httpResponse.statusCode, data: data) {
                    return .failure(apiError)
                }
                return .failure(.unknown)
            }

            if responseType == EmptyResponse.self {
                return .success(EmptyResponse() as! Response)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try .success(decoder.decode(Response.self, from: data))
        } catch let apiError as APIError {
            return .failure(apiError)
        } catch let urlError as URLError {
            return .failure(APIError.from(urlError: urlError))
        } catch {
            return .failure(.unknown)
        }
    }
}

private struct EmptyResponse: Codable, Equatable, Sendable {}

actor RefreshCoordinator {
    private var activeRefreshTask: Task<Bool, Never>?

    func run(operation: @escaping @Sendable () async -> Bool) async -> Bool {
        if let activeRefreshTask {
            return await activeRefreshTask.value
        }

        let task = Task { await operation() }
        activeRefreshTask = task
        let result = await task.value
        activeRefreshTask = nil
        return result
    }
}

final class AuthService: AuthServiceProtocol, @unchecked Sendable {
    private let tokenStore: TokenStore
    private let appleCredentialUserStore: AppleCredentialUserStore
    private let backendAuthClient: BackendAuthClientProtocol
    private let appleSignInAuthorizer: AppleSignInAuthorizing
    private let appleCredentialStateChecker: AppleCredentialStateChecking
    private let refreshCoordinator = RefreshCoordinator()

    init(
        tokenStore: TokenStore = KeychainTokenStore(),
        appleCredentialUserStore: AppleCredentialUserStore = KeychainAppleCredentialUserStore(),
        backendAuthClient: BackendAuthClientProtocol,
        appleSignInAuthorizer: AppleSignInAuthorizing = AppleSignInAuthorizer(),
        appleCredentialStateChecker: AppleCredentialStateChecking = AppleCredentialStateChecker(),
    ) {
        self.tokenStore = tokenStore
        self.appleCredentialUserStore = appleCredentialUserStore
        self.backendAuthClient = backendAuthClient
        self.appleSignInAuthorizer = appleSignInAuthorizer
        self.appleCredentialStateChecker = appleCredentialStateChecker
    }

    @MainActor
    func login(mode: LoginEntryMode) async -> Result<TokenSet, APIError> {
        guard mode == .apple else {
            return .failure(.unauthorized)
        }

        do {
            let authorization = try await appleSignInAuthorizer.authorize()
            let result = await backendAuthClient.loginWithApple(authorization)

            switch result {
            case let .success(response):
                let tokenSet = TokenSet(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    idToken: nil,
                    tokenType: "Bearer",
                    scope: nil,
                    expiresAt: response.accessTokenExpiresAt,
                )
                try tokenStore.save(tokenSet)
                try? appleCredentialUserStore.saveUserIdentifier(authorization.userIdentifier)
                return .success(tokenSet)

            case let .failure(error):
                return .failure(error)
            }
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
        await refreshCoordinator.run { [self] in
            guard let refreshToken = try? tokenStore.load()?.refreshToken else {
                return false
            }

            let result = await backendAuthClient.refresh(refreshToken: refreshToken)
            switch result {
            case let .success(response):
                let tokenSet = TokenSet(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    idToken: nil,
                    tokenType: "Bearer",
                    scope: nil,
                    expiresAt: response.accessTokenExpiresAt,
                )
                do {
                    try tokenStore.save(tokenSet)
                    return true
                } catch {
                    return false
                }

            case .failure:
                try? tokenStore.clear()
                return false
            }
        }
    }

    func logout() async {
        if let refreshToken = try? tokenStore.load()?.refreshToken {
            await backendAuthClient.logout(refreshToken: refreshToken)
        }
        clearLocalSession()
    }

    func currentTokenSet() async -> TokenSet? {
        currentTokenSetSync()
    }

    func validateExternalCredentialIfNeeded() async -> Bool {
        guard currentTokenSetSync() != nil else { return true }
        let storedUserIdentifier = try? appleCredentialUserStore.loadUserIdentifier()
        guard let userIdentifier = storedUserIdentifier ?? nil, !userIdentifier.isEmpty else {
            return true
        }

        let credentialState = await appleCredentialStateChecker.credentialState(forUserID: userIdentifier)
        switch credentialState {
        case .authorized, .unknown:
            return true
        case .revoked, .notFound, .transferred:
            clearLocalSession()
            return false
        }
    }

    private func currentTokenSetSync() -> TokenSet? {
        try? tokenStore.load()
    }

    private func clearLocalSession() {
        try? tokenStore.clear()
        try? appleCredentialUserStore.clearUserIdentifier()
    }
}
