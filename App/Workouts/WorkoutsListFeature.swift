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
        var error: UserFacingError?
    }

    enum Action: Equatable {
        case onAppear
        case refresh
        case retry
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

    init(workoutsClient: WorkoutsClientProtocol, progressStore: WorkoutProgressStore) {
        self.workoutsClient = workoutsClient
        self.progressStore = progressStore
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.workouts.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                state.error = nil
                return loadWorkouts(programId: state.programId)

            case .refresh:
                guard !state.isRefreshing else { return .none }
                state.isRefreshing = true
                state.error = nil
                return loadWorkouts(programId: state.programId)

            case .retry:
                state.isLoading = true
                state.error = nil
                return loadWorkouts(programId: state.programId)

            case let .response(result):
                state.isLoading = false
                state.isRefreshing = false
                switch result {
                case let .success(workouts):
                    state.workouts = workouts
                    state.error = nil
                    let userSub = state.userSub
                    let programId = state.programId
                    return .run { [progressStore] send in
                        let statuses = await progressStore.statuses(
                            userSub: userSub,
                            programId: programId,
                            workoutIds: workouts.map(\.id),
                        )
                        await send(.statusesLoaded(statuses))
                    }
                case let .failure(error):
                    state.error = error.workoutsUserFacingError
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
}

private extension APIError {
    var workoutsUserFacingError: UserFacingError {
        switch self {
        case .offline:
            UserFacingError(
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
        case .serverError, .transportError, .timeout:
            UserFacingError(
                title: "Сервис временно недоступен",
                message: "Попробуйте обновить список тренировок чуть позже.",
            )
        case .decodingError:
            UserFacingError(
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера",
            )
        default:
            UserFacingError(
                title: "Не удалось загрузить тренировки",
                message: "Повторите попытку.",
            )
        }
    }
}
