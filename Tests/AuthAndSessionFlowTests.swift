import ComposableArchitecture
@testable import FitfluenceApp
import XCTest

final class AuthAndSessionFlowTests: XCTestCase {
    func testBootstrapWithExistingTokenAndRequiredAthleteProfileGoesToNeedsOnboarding() async {
        let auth = MockAuthService(tokenSet: sampleTokenSet)
        let meClient = MockMeClient(results: [.success(sampleMe(requiresAthlete: true, requiresInfluencer: false))])
        let manager = SessionManager(authService: auth, meClient: meClient)

        let state = await manager.bootstrap()

        guard case let .needsOnboarding(context) = state else {
            return XCTFail("Expected needsOnboarding")
        }
        XCTAssertTrue(context.requiredProfiles.requiresAthleteProfile)
        XCTAssertFalse(context.requiredProfiles.requiresInfluencerProfile)
    }

    func testOnboardingInitialStateIsAthleteOnly() {
        let context = OnboardingContext(
            me: sampleMe(requiresAthlete: true, requiresInfluencer: true),
            requiredProfiles: RequiredProfiles(requiresAthleteProfile: true, requiresInfluencerProfile: true),
        )

        let state = OnboardingFeature.State(context: context)
        XCTAssertEqual(state.athleteDisplayName, "")
    }

    @MainActor
    func testAthleteSubmitSuccessThenSessionBecomesAuthenticated() async {
        let athleteClient = MockAthleteProfileClient(result: .success(CreateAthleteProfileResponse(id: "ath-1")))
        let manager = MockSessionManager(nextState: .authenticated(UserContext(me: sampleMe(
            requiresAthlete: false,
            requiresInfluencer: false,
        ))))

        let store = TestStore(initialState: OnboardingFeature.State(context: OnboardingContext(
            me: sampleMe(requiresAthlete: true, requiresInfluencer: false),
            requiredProfiles: RequiredProfiles(requiresAthleteProfile: true, requiresInfluencerProfile: false),
        ))) {
            OnboardingFeature(
                athleteClient: athleteClient,
                sessionManager: manager,
            )
        }

        await store.send(.athleteDisplayNameChanged("Alex")) { $0.athleteDisplayName = "Alex" }

        await store.send(.createAthleteTapped("Alex")) {
            $0.isSubmitting = true
            $0.errorMessage = nil
        }

        await store.receive(.athleteResponse(.success(CreateAthleteProfileResponse(id: "ath-1")))) {
            $0.isSubmitting = false
            $0.successMessage = "Профиль создан."
        }

        let nextState = RootSessionState.authenticated(UserContext(me: sampleMe(
            requiresAthlete: false,
            requiresInfluencer: false,
        )))

        await store.receive(.postSubmitStateResolved(nextState)) {
            $0.successMessage = nil
        }

        await store.receive(.delegate(.sessionResolved(nextState)))
    }

    func test401RefreshAndRetrySuccess() async {
        let auth = MockAuthService(tokenSet: sampleTokenSet)
        auth.refreshResult = true

        let client = SequencedHTTPClient(
            outcomes: [
                .failure(.unauthorized),
                .success(HTTPResponse(
                    data: Data("{\"sub\":\"u1\",\"requiresAthleteProfile\":false,\"requiresInfluencerProfile\":false}"
                        .utf8),
                    statusCode: 200,
                    requestID: UUID(),
                    durationMs: 1,
                )),
            ],
        )

        let apiClient = APIClient(httpClient: client, authService: auth)
        let result = await apiClient.me()

        switch result {
        case let .success(me):
            XCTAssertEqual(me.subject, "u1")
            XCTAssertEqual(client.calls, 2)
            XCTAssertEqual(auth.refreshCalls, 1)
        case let .failure(error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testLogoutClearsTokensAndReturnsUnauthenticated() async {
        let auth = MockAuthService(tokenSet: sampleTokenSet)
        let manager = SessionManager(authService: auth, meClient: MockMeClient(results: []))

        let state = await manager.logout()
        let storedToken = await auth.currentTokenSet()

        XCTAssertEqual(state, .unauthenticated)
        XCTAssertNil(storedToken)
    }

    func testBootstrapWithRevokedAppleCredentialReturnsUnauthenticated() async {
        let auth = MockAuthService(tokenSet: sampleTokenSet)
        auth.validateExternalCredentialResult = false
        let manager = SessionManager(authService: auth, meClient: MockMeClient(results: []))

        let state = await manager.bootstrap()

        XCTAssertEqual(state, .unauthenticated)
        XCTAssertEqual(auth.logoutCalls, 0)
    }

    @MainActor
    func testRootFeatureDoesNotAutomaticallyAttemptInteractiveLoginAfterUnauthenticatedBootstrap() async {
        let auth = MockAuthService(tokenSet: sampleTokenSet)
        let manager = MockSessionManager(nextState: .unauthenticated)

        let store = TestStore(initialState: RootFeature.State()) {
            RootFeature(
                sessionManager: manager,
                authService: auth,
                apiClient: nil,
            )
        }

        await store.send(.sessionResolved(.unauthenticated)) {
            $0.sessionState = .unauthenticated
        }
    }

    @MainActor
    func testLogoutDisablesAutomaticLogin() async {
        let auth = MockAuthService(tokenSet: sampleTokenSet)
        let manager = MockSessionManager(nextState: .unauthenticated)

        let store = TestStore(initialState: RootFeature.State(
            hasBootstrapped: true,
            hasAttemptedAutomaticLogin: true,
            automaticLoginEnabled: true,
            isOnline: true,
            sessionState: .authenticated(UserContext(me: sampleMe(
                requiresAthlete: false,
                requiresInfluencer: false,
            ))),
            selectedProgram: nil,
            onboarding: nil,
        )) {
            RootFeature(
                sessionManager: manager,
                authService: auth,
                apiClient: nil,
            )
        }

        await store.send(.logoutTapped) {
            $0.automaticLoginEnabled = false
            $0.sessionState = .authenticating
            $0.selectedProgram = nil
        }

        await store.receive(.sessionResolved(.unauthenticated)) {
            $0.sessionState = .unauthenticated
        }
    }

    @MainActor
    func testAuthServiceAppleLoginSavesBackendTokenPair() async {
        let tokenStore = InMemoryTokenStore()
        let backendAuthClient = MockBackendAuthClient()
        let appleCredentialUserStore = InMemoryAppleCredentialUserStore()
        backendAuthClient.appleLoginResult = .success(
            BackendAppleAuthResponse(
                accessToken: "backend-access",
                accessTokenExpiresAt: Date().addingTimeInterval(1800),
                refreshToken: "backend-refresh",
                refreshTokenExpiresAt: Date().addingTimeInterval(86_400),
            ),
        )

        let service = AuthService(
            tokenStore: tokenStore,
            appleCredentialUserStore: appleCredentialUserStore,
            backendAuthClient: backendAuthClient,
            appleSignInAuthorizer: MockAppleSignInAuthorizer(
                result: .success(
                    AppleAuthorizationPayload(
                        identityToken: "apple-identity-token",
                        authorizationCode: "apple-auth-code",
                        userIdentifier: "apple-user",
                    ),
                ),
            ),
        )

        let result = await service.login(mode: .apple)
        guard case let .success(tokenSet) = result else {
            return XCTFail("Expected successful login")
        }

        XCTAssertEqual(tokenSet.accessToken, "backend-access")
        XCTAssertEqual(tokenSet.refreshToken, "backend-refresh")
        let storedTokenSet = await service.currentTokenSet()
        XCTAssertEqual(storedTokenSet, tokenSet)
        XCTAssertEqual(try? appleCredentialUserStore.loadUserIdentifier(), "apple-user")
    }

    func testAuthServiceRefreshUsesBackendRefreshEndpoint() async {
        let tokenStore = InMemoryTokenStore(initialTokenSet: TokenSet(
            accessToken: "expired-access",
            refreshToken: "refresh-token",
            idToken: nil,
            tokenType: "Bearer",
            scope: nil,
            expiresAt: Date().addingTimeInterval(-5),
        ))
        let backendAuthClient = MockBackendAuthClient()
        backendAuthClient.refreshResult = .success(
            BackendTokenRefreshResponse(
                accessToken: "rotated-access",
                accessTokenExpiresAt: Date().addingTimeInterval(1800),
                refreshToken: "rotated-refresh",
                refreshTokenExpiresAt: Date().addingTimeInterval(86_400),
            ),
        )

        let service = AuthService(
            tokenStore: tokenStore,
            backendAuthClient: backendAuthClient,
            appleSignInAuthorizer: MockAppleSignInAuthorizer(result: .failure(.cancelled)),
        )

        let refreshed = await service.refresh()
        XCTAssertTrue(refreshed)
        XCTAssertEqual(backendAuthClient.lastRefreshToken, "refresh-token")
        let refreshedTokenSet = await service.currentTokenSet()
        XCTAssertEqual(refreshedTokenSet?.accessToken, "rotated-access")
        XCTAssertEqual(refreshedTokenSet?.refreshToken, "rotated-refresh")
    }

    func testAuthServiceLogoutClearsStoredAppleCredentialUserIdentifier() async {
        let tokenStore = InMemoryTokenStore(initialTokenSet: sampleTokenSet)
        let appleCredentialUserStore = InMemoryAppleCredentialUserStore(initialUserIdentifier: "apple-user")
        let service = AuthService(
            tokenStore: tokenStore,
            appleCredentialUserStore: appleCredentialUserStore,
            backendAuthClient: MockBackendAuthClient(),
            appleSignInAuthorizer: MockAppleSignInAuthorizer(result: .failure(.cancelled)),
        )

        await service.logout()

        let storedUserIdentifier = try? appleCredentialUserStore.loadUserIdentifier()
        let storedTokenSet = await service.currentTokenSet()
        XCTAssertNil(storedUserIdentifier)
        XCTAssertNil(storedTokenSet)
    }

    func testAuthServiceValidateExternalCredentialClearsSessionWhenRevoked() async {
        let tokenStore = InMemoryTokenStore(initialTokenSet: sampleTokenSet)
        let appleCredentialUserStore = InMemoryAppleCredentialUserStore(initialUserIdentifier: "apple-user")
        let service = AuthService(
            tokenStore: tokenStore,
            appleCredentialUserStore: appleCredentialUserStore,
            backendAuthClient: MockBackendAuthClient(),
            appleSignInAuthorizer: MockAppleSignInAuthorizer(result: .failure(.cancelled)),
            appleCredentialStateChecker: MockAppleCredentialStateChecker(state: .revoked),
        )

        let isValid = await service.validateExternalCredentialIfNeeded()
        let storedTokenSet = await service.currentTokenSet()
        let storedUserIdentifier = try? appleCredentialUserStore.loadUserIdentifier()

        XCTAssertFalse(isValid)
        XCTAssertNil(storedTokenSet)
        XCTAssertNil(storedUserIdentifier)
    }

    private var sampleTokenSet: TokenSet {
        TokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: "id",
            tokenType: "Bearer",
            scope: "openid",
            expiresAt: Date().addingTimeInterval(3600),
        )
    }

    private func sampleMe(requiresAthlete: Bool, requiresInfluencer: Bool) -> MeResponse {
        MeResponse(
            subject: "u1",
            email: "demo@fitfluence.local",
            requiresAthleteProfile: requiresAthlete,
            requiresInfluencerProfile: requiresInfluencer,
            athleteProfile: requiresAthlete ? nil : .init(id: "athlete-1"),
            influencerProfile: requiresInfluencer ? nil : .init(id: "influencer-1"),
        )
    }
}

private final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    var tokenSet: TokenSet?
    var refreshResult = false
    var refreshCalls = 0
    var validateExternalCredentialResult = true
    var logoutCalls = 0

    init(tokenSet: TokenSet?) {
        self.tokenSet = tokenSet
    }

    @MainActor
    func login(mode _: LoginEntryMode) async -> Result<TokenSet, APIError> {
        if let tokenSet {
            return .success(tokenSet)
        }
        return .failure(.unauthorized)
    }

    func refreshIfNeeded() async -> Bool {
        tokenSet != nil
    }

    func refresh() async -> Bool {
        refreshCalls += 1
        return refreshResult
    }

    func logout() async {
        logoutCalls += 1
        tokenSet = nil
    }

    func currentTokenSet() async -> TokenSet? {
        tokenSet
    }

    func validateExternalCredentialIfNeeded() async -> Bool {
        validateExternalCredentialResult
    }
}

private final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var tokenSet: TokenSet?

    init(initialTokenSet: TokenSet? = nil) {
        tokenSet = initialTokenSet
    }

    func load() throws -> TokenSet? {
        tokenSet
    }

    func save(_ tokenSet: TokenSet) throws {
        self.tokenSet = tokenSet
    }

    func clear() throws {
        tokenSet = nil
    }
}

private final class InMemoryAppleCredentialUserStore: AppleCredentialUserStore, @unchecked Sendable {
    private var userIdentifier: String?

    init(initialUserIdentifier: String? = nil) {
        userIdentifier = initialUserIdentifier
    }

    func loadUserIdentifier() throws -> String? {
        userIdentifier
    }

    func saveUserIdentifier(_ userIdentifier: String) throws {
        self.userIdentifier = userIdentifier
    }

    func clearUserIdentifier() throws {
        userIdentifier = nil
    }
}

private struct MockAppleSignInAuthorizer: AppleSignInAuthorizing {
    let result: Result<AppleAuthorizationPayload, APIError>

    @MainActor
    func authorize() async throws -> AppleAuthorizationPayload {
        switch result {
        case let .success(payload):
            return payload
        case let .failure(error):
            throw error
        }
    }
}

private struct MockAppleCredentialStateChecker: AppleCredentialStateChecking {
    let state: AppleCredentialState

    @MainActor
    func credentialState(forUserID _: String) async -> AppleCredentialState {
        state
    }
}

private final class MockBackendAuthClient: BackendAuthClientProtocol, @unchecked Sendable {
    var appleLoginResult: Result<BackendAppleAuthResponse, APIError> = .failure(.unauthorized)
    var refreshResult: Result<BackendTokenRefreshResponse, APIError> = .failure(.unauthorized)
    var lastRefreshToken: String?

    func loginWithApple(_ payload: AppleAuthorizationPayload) async -> Result<BackendAppleAuthResponse, APIError> {
        _ = payload
        return appleLoginResult
    }

    func refresh(refreshToken: String) async -> Result<BackendTokenRefreshResponse, APIError> {
        lastRefreshToken = refreshToken
        return refreshResult
    }

    func logout(refreshToken _: String) async {}
}

private final class MockMeClient: MeClientProtocol, @unchecked Sendable {
    private var results: [Result<MeResponse, APIError>]

    init(results: [Result<MeResponse, APIError>]) {
        self.results = results
    }

    func me() async -> Result<MeResponse, APIError> {
        if results.isEmpty {
            return .failure(.unknown)
        }
        return results.removeFirst()
    }
}

private final class MockAthleteProfileClient: AthleteProfileClientProtocol, @unchecked Sendable {
    let result: Result<CreateAthleteProfileResponse, APIError>

    init(result: Result<CreateAthleteProfileResponse, APIError>) {
        self.result = result
    }

    func createProfile(_: CreateAthleteProfileRequest) async -> Result<CreateAthleteProfileResponse, APIError> {
        result
    }
}

private final class MockSessionManager: SessionManaging, @unchecked Sendable {
    let nextState: RootSessionState
    var postLoginState: RootSessionState

    init(nextState: RootSessionState) {
        self.nextState = nextState
        postLoginState = nextState
    }

    func bootstrap() async -> RootSessionState {
        nextState
    }

    func postLoginBootstrap() async -> RootSessionState {
        postLoginState
    }

    func logout() async -> RootSessionState {
        .unauthenticated
    }
}

private final class SequencedHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    enum Outcome {
        case success(HTTPResponse)
        case failure(APIError)
    }

    var outcomes: [Outcome]
    var calls = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func send(_: APIRequest) async throws -> HTTPResponse {
        calls += 1
        guard !outcomes.isEmpty else {
            throw APIError.unknown
        }

        let next = outcomes.removeFirst()
        switch next {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }
}
