import ComposableArchitecture

@Reducer
struct RootFeature {
    private let sessionManager: SessionManaging
    private let authService: AuthServiceProtocol
    private let apiClient: APIClientProtocol?
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let athleteClient: AthleteProfileClientProtocol?

    init(
        sessionManager: SessionManaging,
        authService: AuthServiceProtocol,
        apiClient: APIClientProtocol?,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
    ) {
        self.sessionManager = sessionManager
        self.authService = authService
        self.apiClient = apiClient
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        athleteClient = apiClient as? AthleteProfileClientProtocol
    }

    @ObservableState
    struct State: Equatable {
        var hasBootstrapped = false
        var isOnline = true
        var sessionState: RootSessionState = .authenticating
        var home = HomeFeature.State(userSub: "anonymous")
        var catalog = CatalogFeature.State()
        var programDetails: ProgramDetailsFeature.State?
        var selectedMainTab: MainTab = .home
        var onboarding: OnboardingFeature.State?
    }

    enum MainTab: Hashable {
        case home
        case catalog
        case profile
    }

    enum Action: Equatable {
        case onAppear
        case retryBootstrapTapped
        case loginTapped(LoginEntryMode)
        case logoutTapped
        case networkStatusChanged(Bool)
        case sessionResolved(RootSessionState)
        case home(HomeFeature.Action)
        case onboarding(OnboardingFeature.Action)
        case catalog(CatalogFeature.Action)
        case programDetails(ProgramDetailsFeature.Action)
        case programDetailsDismissed
        case tabSelected(MainTab)
    }

    private enum CancelID {
        case networkMonitoring
    }

    var body: some ReducerOf<Self> {
        CombineReducers {
            Scope(state: \.home, action: \.home) { [progressStore, cacheStore] in
                HomeFeature(
                    progressStore: progressStore,
                    cacheStore: cacheStore,
                )
            }

            Scope(state: \.catalog, action: \.catalog) { [apiClient, cacheStore, networkMonitor] in
                CatalogFeature(
                    programsClient: apiClient as? ProgramsClientProtocol,
                    cacheStore: cacheStore,
                    networkMonitor: networkMonitor,
                )
            }

            Reduce { state, action in
                switch action {
            case .onAppear:
                guard !state.hasBootstrapped else { return .none }
                state.hasBootstrapped = true
                state.sessionState = .authenticating
                return .merge(
                    .run { [sessionManager] send in
                        let resolved = await sessionManager.bootstrap()
                        await send(.sessionResolved(resolved))
                    },
                    .run { [networkMonitor] send in
                        for await status in networkMonitor.statusUpdates() {
                            await send(.networkStatusChanged(status))
                        }
                    }
                    .cancellable(id: CancelID.networkMonitoring, cancelInFlight: true),
                )

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
                let namespace: String = if case let .authenticated(context) = state.sessionState {
                    context.me.subject ?? state.catalog.cacheNamespace
                } else {
                    state.catalog.cacheNamespace
                }
                state.sessionState = .authenticating
                state.programDetails = nil
                return .run { [sessionManager, cacheStore] send in
                    await cacheStore.clearAll(namespace: namespace)
                    let nextState = await sessionManager.logout()
                    await send(.sessionResolved(nextState))
                }

            case let .networkStatusChanged(status):
                state.isOnline = status
                return .none

            case let .sessionResolved(nextState):
                state.sessionState = nextState
                if case let .needsOnboarding(context) = nextState {
                    state.onboarding = OnboardingFeature.State(context: context)
                } else {
                    state.onboarding = nil
                }
                if case let .authenticated(context) = nextState {
                    let userSub = context.me.subject ?? "anonymous"
                    state.catalog.cacheNamespace = userSub
                    state.home.userSub = userSub
                    state.selectedMainTab = .home
                } else if case .unauthenticated = nextState {
                    state.catalog.cacheNamespace = "anonymous"
                    state.home.userSub = "anonymous"
                    state.selectedMainTab = .home
                }
                return .none

            case let .tabSelected(tab):
                state.selectedMainTab = tab
                return .none

            case .home(.onAppear):
                return .none

            case let .home(.delegate(.openCatalog)):
                state.selectedMainTab = .catalog
                return .none

            case let .home(.delegate(.openWorkout(programID, workoutID))):
                state.selectedMainTab = .catalog
                let userSub: String = if case let .authenticated(context) = state.sessionState {
                    context.me.subject ?? "anonymous"
                } else {
                    "anonymous"
                }
                state.programDetails = ProgramDetailsFeature.State(
                    programId: programID,
                    userSub: userSub,
                    workoutPlayer: WorkoutPlayerFeature.State(
                        userSub: userSub,
                        programId: programID,
                        workoutId: workoutID,
                    ),
                )
                return .none

            case let .catalog(.delegate(.openProgram(programID))):
                let userSub: String = if case let .authenticated(context) = state.sessionState {
                    context.me.subject ?? "anonymous"
                } else {
                    "anonymous"
                }
                state.programDetails = ProgramDetailsFeature.State(
                    programId: programID,
                    userSub: userSub,
                )
                return .none

            case .catalog:
                return .none

            case .home:
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
                    if case .authenticated = nextState {
                        state.selectedMainTab = .home
                    }
                }
                return .none

            case .onboarding:
                return .none
            }
            }
        }
        .ifLet(\.onboarding, action: \.onboarding) { [athleteClient, sessionManager] in
            OnboardingFeature(
                athleteClient: athleteClient,
                sessionManager: sessionManager,
            )
        }
        .ifLet(\.programDetails, action: \.programDetails) { [apiClient, progressStore, cacheStore, networkMonitor] in
            ProgramDetailsFeature(
                programsClient: apiClient as? ProgramsClientProtocol,
                progressStore: progressStore,
                cacheStore: cacheStore,
                networkMonitor: networkMonitor,
            )
        }
    }
}

private extension APIError {
    var loginFailureMessage: String {
        switch self {
        case .timeout, .offline:
            return "Не удалось связаться с сервером авторизации. Проверьте сеть и адрес Keycloak."
        case .invalidURL:
            return "Некорректная конфигурация URL авторизации. Проверьте настройки окружения."
        case .unauthorized, .forbidden:
            return "Клиент авторизации отклонён. Проверьте clientId, redirect URI и настройки в Keycloak."
        case let .httpError(statusCode, bodySnippet):
            if statusCode == 400, bodySnippet?.contains("invalid_scope") == true {
                return "Сервер авторизации отклонил scopes. Проверьте KEYCLOAK_SCOPES в Dev.xcconfig."
            }
            return "Сервер авторизации вернул ошибку \(statusCode). Проверьте настройки клиента в Keycloak."
        default:
            return "Не удалось выполнить вход через Keycloak. Проверьте настройки клиента и HTTPS для auth-сервера."
        }
    }
}
