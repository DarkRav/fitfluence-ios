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

        await store.send(.createAthleteTapped) {
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
        tokenSet = nil
    }

    func currentTokenSet() async -> TokenSet? {
        tokenSet
    }
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

    init(nextState: RootSessionState) {
        self.nextState = nextState
    }

    func bootstrap() async -> RootSessionState {
        nextState
    }

    func postLoginBootstrap() async -> RootSessionState {
        nextState
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
