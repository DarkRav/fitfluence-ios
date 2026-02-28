import ComposableArchitecture
import Foundation

@Reducer
struct ProgramDetailsFeature {
    @ObservableState
    struct State: Equatable {
        let programId: String
        let userSub: String
        var details: ProgramDetails?
        var isShowingCachedData = false
        var workoutsList: WorkoutsListFeature.State?
        var workoutPlayer: WorkoutPlayerFeature.State?
        var workoutCompletion: WorkoutCompletionFeature.State?
        var isLoading = false
        var isStartingProgram = false
        var error: UserFacingError?
        var successMessage: String?
    }

    enum Action: Equatable {
        case onAppear
        case retry
        case cachedDetailsResponse(ProgramDetails?)
        case detailsResponse(Result<ProgramDetails, APIError>)
        case startProgramTapped
        case startProgramResponse(Result<ProgramEnrollment, APIError>)
        case openWorkoutsTapped
        case workoutsList(WorkoutsListFeature.Action)
        case workoutsListDismissed
        case workoutPlayer(WorkoutPlayerFeature.Action)
        case workoutPlayerDismissed
        case workoutCompletion(WorkoutCompletionFeature.Action)
        case workoutCompletionDismissed
    }

    private let programsClient: ProgramsClientProtocol?
    private let workoutsClient: WorkoutsClientProtocol
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring

    init(
        programsClient: ProgramsClientProtocol?,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
    ) {
        self.programsClient = programsClient
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        if let programsClient {
            workoutsClient = WorkoutsClient(programsClient: programsClient)
        } else {
            workoutsClient = UnavailableWorkoutsClient()
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.details == nil else { return .none }
                state.isLoading = true
                state.error = nil
                return .concatenate(
                    loadCachedDetails(programId: state.programId, namespace: state.userSub),
                    loadDetails(programId: state.programId),
                )

            case .retry:
                state.isLoading = true
                state.error = nil
                return .concatenate(
                    loadCachedDetails(programId: state.programId, namespace: state.userSub),
                    loadDetails(programId: state.programId),
                )

            case let .cachedDetailsResponse(cached):
                guard let cached else { return .none }
                state.details = cached
                state.isShowingCachedData = true
                return .none

            case let .detailsResponse(result):
                state.isLoading = false
                switch result {
                case let .success(details):
                    state.details = details
                    state.isShowingCachedData = false
                    state.error = nil
                    let namespace = state.userSub
                    let key = cacheKey(programId: details.id)
                    return .run { [cacheStore] _ in
                        await cacheStore.set(key, value: details, namespace: namespace, ttl: 60 * 30)
                    }
                case let .failure(apiError):
                    if apiError == .offline || !networkMonitor.currentStatus {
                        if state.details != nil {
                            state.error = nil
                            state.isShowingCachedData = true
                            return .none
                        }
                    }
                    state.error = apiError.userFacingError
                }
                return .none

            case .startProgramTapped:
                guard
                    let versionID = state.details?.currentPublishedVersion?.id,
                    !state.isStartingProgram
                else {
                    return .none
                }

                state.isStartingProgram = true
                state.error = nil
                return .run { [programsClient] send in
                    let result: Result<ProgramEnrollment, APIError> = if let programsClient {
                        await programsClient.startProgram(programVersionId: versionID)
                    } else {
                        .failure(.invalidURL)
                    }
                    await send(.startProgramResponse(result))
                }

            case let .startProgramResponse(result):
                state.isStartingProgram = false
                switch result {
                case .success:
                    state.successMessage = "Программа успешно начата."
                case let .failure(apiError):
                    state.error = apiError.userFacingError
                }
                return .none

            case .openWorkoutsTapped:
                state.workoutsList = WorkoutsListFeature.State(
                    programId: state.programId,
                    userSub: state.userSub,
                )
                return .none

            case .workoutsListDismissed:
                state.workoutsList = nil
                return .none

            case let .workoutsList(.delegate(.openWorkout(workoutID))):
                state.workoutPlayer = WorkoutPlayerFeature.State(
                    userSub: state.userSub,
                    programId: state.programId,
                    workoutId: workoutID,
                    progressStorageMode: workoutsClient.progressStorageMode,
                )
                return .none

            case .workoutPlayerDismissed:
                state.workoutPlayer = nil
                return .none

            case let .workoutPlayer(.delegate(.workoutCompleted(summary))):
                state.workoutCompletion = WorkoutCompletionFeature.State(summary: summary)
                return .none

            case .workoutCompletionDismissed:
                state.workoutCompletion = nil
                return .none

            case .workoutCompletion(.delegate(.close)):
                state.workoutCompletion = nil
                state.workoutPlayer = nil
                return .none

            case .workoutsList:
                return .none

            case .workoutPlayer:
                return .none

            case .workoutCompletion:
                return .none
            }
        }
        .ifLet(\.workoutsList, action: \.workoutsList) { [workoutsClient, progressStore, cacheStore, networkMonitor] in
            WorkoutsListFeature(
                workoutsClient: workoutsClient,
                progressStore: progressStore,
                cacheStore: cacheStore,
                networkMonitor: networkMonitor,
            )
        }
        .ifLet(\.workoutPlayer, action: \.workoutPlayer) { [
            workoutsClient,
            progressStore,
            cacheStore,
            networkMonitor,
        ] in
            WorkoutPlayerFeature(
                workoutsClient: workoutsClient,
                progressStore: progressStore,
                cacheStore: cacheStore,
                networkMonitor: networkMonitor,
            )
        }
        .ifLet(\.workoutCompletion, action: \.workoutCompletion) {
            WorkoutCompletionFeature()
        }
    }

    private func loadDetails(programId: String) -> Effect<Action> {
        .run { [programsClient] send in
            let result: Result<ProgramDetails, APIError> = if let programsClient {
                await programsClient.getProgramDetails(programId: programId)
            } else {
                .failure(.invalidURL)
            }
            await send(.detailsResponse(result))
        }
    }

    private func loadCachedDetails(programId: String, namespace: String) -> Effect<Action> {
        .run { [cacheStore] send in
            let cached = await cacheStore.get(
                cacheKey(programId: programId),
                as: ProgramDetails.self,
                namespace: namespace,
            )
            await send(.cachedDetailsResponse(cached))
        }
    }

    private func cacheKey(programId: String) -> String {
        "program.details:\(programId)"
    }
}

private extension APIError {
    var userFacingError: UserFacingError {
        switch self {
        case .offline:
            UserFacingError(
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
        case .unauthorized:
            UserFacingError(
                title: "Сессия истекла. Войдите снова.",
                message: "Для продолжения нужно повторно авторизоваться.",
            )
        case .forbidden:
            UserFacingError(
                title: "Доступ запрещён",
                message: "Недостаточно прав для просмотра программы.",
            )
        case .serverError:
            UserFacingError(
                title: "Сервис временно недоступен",
                message: "Попробуйте открыть программу чуть позже.",
            )
        case .decodingError:
            UserFacingError(
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера",
            )
        default:
            UserFacingError(
                title: "Не удалось загрузить программу",
                message: "Попробуйте ещё раз через несколько секунд.",
            )
        }
    }
}
