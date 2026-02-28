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
        var hasBootstrapped = false
        var sessionState: RootSessionState = .authenticating
        var diagnostics = DiagnosticsFeature.State()
        var catalog = CatalogFeature.State()
        var programDetails: ProgramDetailsFeature.State?
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
        case catalog(CatalogFeature.Action)
        case programDetails(ProgramDetailsFeature.Action)
        case programDetailsDismissed
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
        Scope(state: \.catalog, action: \.catalog) { [apiClient] in
            CatalogFeature(programsClient: apiClient as? ProgramsClientProtocol)
        }
        .ifLet(\.programDetails, action: \.programDetails) { [apiClient] in
            ProgramDetailsFeature(programsClient: apiClient as? ProgramsClientProtocol)
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.hasBootstrapped else { return .none }
                state.hasBootstrapped = true
                state.sessionState = .authenticating
                return .run { [sessionManager] send in
                    let resolved = await sessionManager.bootstrap()
                    await send(.sessionResolved(resolved))
                }

            case .retryBootstrapTapped:
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
                                            message: error.loginFailureMessage,
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

            case let .catalog(.delegate(.openProgram(programID))):
                state.programDetails = ProgramDetailsFeature.State(programId: programID)
                return .none

            case .catalog:
                return .none

            case .programDetails:
                return .none

            case .programDetailsDismissed:
                state.programDetails = nil
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

private extension APIError {
    var loginFailureMessage: String {
        switch self {
        case .timeout, .offline:
            "Не удалось связаться с сервером авторизации. Проверьте сеть и адрес Keycloak."
        case .invalidURL:
            "Некорректная конфигурация URL авторизации. Проверьте настройки окружения."
        case .unauthorized, .forbidden:
            "Клиент авторизации отклонён. Проверьте clientId, redirect URI и настройки в Keycloak."
        default:
            "Не удалось выполнить вход через Keycloak. Проверьте настройки клиента и HTTPS для auth-сервера."
        }
    }
}
