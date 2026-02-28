import ComposableArchitecture

@Reducer
struct WorkoutsListFeature {
    @ObservableState
    struct State: Equatable {
        let programId: String
        let userSub: String
        var workouts: [WorkoutSummary] = []
        var workoutStatuses: [String: WorkoutProgressStatus] = [:]
        var isLoading = false
        var isRefreshing = false
        var isShowingCachedData = false
        var error: UserFacingError?
    }

    enum Action: Equatable {
        case onAppear
        case refresh
        case retry
        case cachedResponse([WorkoutSummary]?)
        case response(Result<[WorkoutSummary], APIError>)
        case statusesLoaded([String: WorkoutProgressStatus])
        case workoutTapped(String)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case openWorkout(workoutId: String)
    }

    private let workoutsClient: WorkoutsClientProtocol
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring

    init(
        workoutsClient: WorkoutsClientProtocol,
        progressStore: WorkoutProgressStore,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
    ) {
        self.workoutsClient = workoutsClient
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.workouts.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                state.error = nil
                return .concatenate(
                    loadCached(programId: state.programId, namespace: state.userSub),
                    loadWorkouts(programId: state.programId),
                )

            case .refresh:
                guard !state.isRefreshing else { return .none }
                state.isRefreshing = true
                state.error = nil
                return .concatenate(
                    loadCached(programId: state.programId, namespace: state.userSub),
                    loadWorkouts(programId: state.programId),
                )

            case .retry:
                state.isLoading = true
                state.error = nil
                return .concatenate(
                    loadCached(programId: state.programId, namespace: state.userSub),
                    loadWorkouts(programId: state.programId),
                )

            case let .cachedResponse(cached):
                guard let cached else { return .none }
                state.workouts = cached
                state.isShowingCachedData = true
                let userSub = state.userSub
                let programId = state.programId
                return .run { [progressStore] send in
                    let statuses = await progressStore.statuses(
                        userSub: userSub,
                        programId: programId,
                        workoutIds: cached.map(\.id),
                    )
                    await send(.statusesLoaded(statuses))
                }

            case let .response(result):
                state.isLoading = false
                state.isRefreshing = false
                switch result {
                case let .success(workouts):
                    state.workouts = workouts
                    state.error = nil
                    state.isShowingCachedData = false
                    let userSub = state.userSub
                    let programId = state.programId
                    let namespace = state.userSub
                    let key = cacheKey(programId: state.programId)
                    return .merge(
                        .run { [cacheStore] _ in
                            await cacheStore.set(key, value: workouts, namespace: namespace, ttl: 60 * 30)
                        },
                        .run { [progressStore] send in
                            let statuses = await progressStore.statuses(
                                userSub: userSub,
                                programId: programId,
                                workoutIds: workouts.map(\.id),
                            )
                            await send(.statusesLoaded(statuses))
                        },
                    )
                case let .failure(error):
                    if error == .offline || !networkMonitor.currentStatus, !state.workouts.isEmpty {
                        state.error = nil
                        state.isShowingCachedData = true
                        return .none
                    }
                    state.error = error.userFacing(context: .workoutsList)
                    return .none
                }

            case let .statusesLoaded(statuses):
                state.workoutStatuses = statuses
                return .none

            case let .workoutTapped(workoutID):
                return .send(.delegate(.openWorkout(workoutId: workoutID)))

            case .delegate:
                return .none
            }
        }
    }

    private func loadWorkouts(programId: String) -> Effect<Action> {
        .run { [workoutsClient] send in
            let result = await workoutsClient.listWorkouts(for: programId)
            await send(.response(result))
        }
    }

    private func loadCached(programId: String, namespace: String) -> Effect<Action> {
        .run { [cacheStore] send in
            let cached = await cacheStore.get(
                cacheKey(programId: programId),
                as: [WorkoutSummary].self,
                namespace: namespace,
            )
            await send(.cachedResponse(cached))
        }
    }

    private func cacheKey(programId: String) -> String {
        "workouts.list:\(programId)"
    }
}
