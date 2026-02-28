import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var userSub: String
        var activeSession: ActiveWorkoutSession?
        var workoutTitle: String?
        var programTitle: String?
        var isLoading = false

        var primaryTitle: String {
            if let session = activeSession {
                return session.status == .inProgress ? "Продолжить тренировку" : "Сегодняшняя тренировка"
            }
            return "Перейти в каталог"
        }

        var subtitle: String {
            guard let session = activeSession else {
                return "Выберите программу и начните первую тренировку."
            }

            if let workoutTitle, !workoutTitle.isEmpty {
                if session.status == .inProgress, let currentExerciseIndex = session.currentExerciseIndex {
                    return "\(workoutTitle) · упражнение \(currentExerciseIndex + 1)"
                }
                return workoutTitle
            }

            return session.status == .inProgress
                ? "Продолжите с места, где остановились."
                : "Готова к старту."
        }
    }

    enum Action: Equatable {
        case onAppear
        case sessionLoaded(ActiveWorkoutSession?)
        case titlesLoaded(programTitle: String?, workoutTitle: String?)
        case primaryTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case openCatalog
        case openWorkout(programId: String, workoutId: String)
    }

    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore

    init(
        progressStore: WorkoutProgressStore,
        cacheStore: CacheStore = CompositeCacheStore(),
    ) {
        self.progressStore = progressStore
        self.cacheStore = cacheStore
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.userSub.isEmpty else { return .none }
                state.isLoading = true
                let userSub = state.userSub
                return .run { [progressStore] send in
                    let session = await progressStore.latestActiveSession(userSub: userSub)
                    await send(.sessionLoaded(session))
                }

            case let .sessionLoaded(session):
                state.activeSession = session
                state.isLoading = false
                guard let session else {
                    state.programTitle = nil
                    state.workoutTitle = nil
                    return .none
                }

                let userSub = state.userSub
                let programId = session.programId
                let workoutId = session.workoutId
                return .run { [cacheStore] send in
                    let program = await cacheStore.get(
                        "program.details:\(programId)",
                        as: ProgramDetails.self,
                        namespace: userSub,
                    )
                    let workout = await cacheStore.get(
                        "workout.details:\(programId):\(workoutId)",
                        as: WorkoutDetailsModel.self,
                        namespace: userSub,
                    )
                    let workouts = await cacheStore.get(
                        "workouts.list:\(programId)",
                        as: [WorkoutSummary].self,
                        namespace: userSub,
                    )
                    await send(
                        .titlesLoaded(
                            programTitle: program?.title,
                            workoutTitle: workout?.title ?? workouts?.first(where: { $0.id == workoutId })?.title,
                        ),
                    )
                }

            case let .titlesLoaded(programTitle, workoutTitle):
                state.programTitle = programTitle
                state.workoutTitle = workoutTitle
                return .none

            case .primaryTapped:
                guard let session = state.activeSession else {
                    return .send(.delegate(.openCatalog))
                }
                return .send(
                    .delegate(
                        .openWorkout(programId: session.programId, workoutId: session.workoutId),
                    ),
                )

            case .delegate:
                return .none
            }
        }
    }
}
