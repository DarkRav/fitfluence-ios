import ComposableArchitecture

@Reducer
struct RootFeature {
    private let sessionManager: SessionManaging
    private let authService: AuthServiceProtocol
    private let apiClient: APIClientProtocol?
    private let athleteClient: AthleteProfileClientProtocol?
    private let influencerClient: InfluencerProfileClientProtocol?

    init(
        sessionManager: SessionManaging,
        authService: AuthServiceProtocol,
        apiClient: APIClientProtocol?,
    ) {
        self.sessionManager = sessionManager
        self.authService = authService
        self.apiClient = apiClient
        athleteClient = apiClient as? AthleteProfileClientProtocol
        influencerClient = apiClient as? InfluencerProfileClientProtocol
    }

    @ObservableState
    struct State: Equatable {
        var sessionState: RootSessionState = .authenticating
        var diagnostics = DiagnosticsFeature.State()
        var selectedMainTab: MainTab = .catalog
        var onboarding: OnboardingFeature.State?
    }

    enum MainTab: Hashable {
        case catalog
        case workouts
        case profile
        #if DEBUG
        case diagnostics
        #endif
    }

    enum Action: Equatable {
        case onAppear
        case retryBootstrapTapped
        case loginTapped(LoginEntryMode)
        case logoutTapped
        case sessionResolved(RootSessionState)
        case diagnostics(DiagnosticsFeature.Action)
        case onboarding(OnboardingFeature.Action)
        case tabSelected(MainTab)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.diagnostics, action: \.diagnostics) {
            DiagnosticsFeature(apiClient: apiClient)
        }
        .ifLet(\.onboarding, action: \.onboarding) { [athleteClient, influencerClient, sessionManager] in
            OnboardingFeature(
                athleteClient: athleteClient,
                influencerClient: influencerClient,
                sessionManager: sessionManager,
            )
        }

        Reduce { state, action in
            switch action {
            case .onAppear, .retryBootstrapTapped:
                state.sessionState = .authenticating
                return .run { [sessionManager] send in
                    let resolved = await sessionManager.bootstrap()
                    await send(.sessionResolved(resolved))
                }

            case let .loginTapped(mode):
                state.sessionState = .authenticating
                return .run { [authService, sessionManager] send in
                    let result = await authService.login(mode: mode)

                    switch result {
                    case .success:
                        let nextState = await sessionManager.postLoginBootstrap()
                        await send(.sessionResolved(nextState))
                    case let .failure(error):
                        if error == .cancelled {
                            await send(.sessionResolved(.unauthenticated))
                        } else {
                            await send(
                                .sessionResolved(
                                    .error(
                                        UserFacingError(
                                            title: "Ошибка входа",
                                            message: "Не удалось выполнить вход через Keycloak.",
                                        ),
                                    ),
                                ),
                            )
                        }
                    }
                }

            case .logoutTapped:
                state.sessionState = .authenticating
                return .run { [sessionManager] send in
                    let nextState = await sessionManager.logout()
                    await send(.sessionResolved(nextState))
                }

            case let .sessionResolved(nextState):
                state.sessionState = nextState
                if case let .needsOnboarding(context) = nextState {
                    state.onboarding = OnboardingFeature.State(context: context)
                } else {
                    state.onboarding = nil
                }
                return .none

            case let .tabSelected(tab):
                state.selectedMainTab = tab
                return .none

            case .diagnostics:
                return .none

            case let .onboarding(.delegate(.sessionResolved(nextState))):
                state.sessionState = nextState
                if case let .needsOnboarding(context) = nextState {
                    state.onboarding = OnboardingFeature.State(context: context)
                } else {
                    state.onboarding = nil
                    if case let .authenticated(userContext) = nextState {
                        state.selectedMainTab = userContext.me.hasInfluencerProfile ? .profile : .catalog
                    }
                }
                return .none

            case .onboarding:
                return .none
            }
        }
    }
}
