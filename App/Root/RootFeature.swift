import ComposableArchitecture

@Reducer
struct RootFeature {
    private let sessionManager: SessionManaging
    private let authService: AuthServiceProtocol
    private let apiClient: APIClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let athleteClient: AthleteProfileClientProtocol?

    init(
        sessionManager: SessionManaging,
        authService: AuthServiceProtocol,
        apiClient: APIClientProtocol?,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
    ) {
        self.sessionManager = sessionManager
        self.authService = authService
        self.apiClient = apiClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        athleteClient = apiClient as? AthleteProfileClientProtocol
    }

    @ObservableState
    struct State: Equatable {
        struct SelectedProgram: Equatable {
            let programId: String
            let userSub: String
        }

        var hasBootstrapped = false
        var isOnline = true
        var sessionState: RootSessionState = .authenticating
        var selectedProgram: SelectedProgram?
        var onboarding: OnboardingFeature.State?
    }

    enum Action: Equatable {
        case onAppear
        case retryBootstrapTapped
        case loginTapped(LoginEntryMode)
        case logoutTapped
        case networkStatusChanged(Bool)
        case sessionResolved(RootSessionState)
        case onboarding(OnboardingFeature.Action)
        case openProgram(programId: String, userSub: String)
        case programDetailsDismissed
    }

    private enum CancelID {
        case networkMonitoring
    }

    var body: some ReducerOf<Self> {
        CombineReducers {
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
                    let namespace = cacheNamespace(for: state)
                    state.sessionState = .authenticating
                    state.selectedProgram = nil
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
                    return .none

                case let .openProgram(programID, userSub):
                    state.selectedProgram = State.SelectedProgram(
                        programId: programID,
                        userSub: userSub,
                    )
                    return .none

                case .programDetailsDismissed:
                    state.selectedProgram = nil
                    return .none

                case let .onboarding(.delegate(.sessionResolved(nextState))):
                    state.sessionState = nextState
                    if case let .needsOnboarding(context) = nextState {
                        state.onboarding = OnboardingFeature.State(context: context)
                    } else {
                        state.onboarding = nil
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
    }

    private func cacheNamespace(for state: State) -> String {
        if case let .authenticated(context) = state.sessionState {
            return context.me.subject ?? "anonymous"
        }
        return "anonymous"
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
