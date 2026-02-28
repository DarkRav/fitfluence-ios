import ComposableArchitecture
import Foundation

@Reducer
struct ProgramDetailsFeature {
    @ObservableState
    struct State: Equatable {
        struct SelectedWorkout: Equatable {
            let userSub: String
            let programId: String
            let workoutId: String
        }

        let programId: String
        let userSub: String
        var details: ProgramDetails?
        var isShowingCachedData = false
        var isWorkoutsPresented = false
        var selectedWorkout: SelectedWorkout?
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
        case workoutSelected(String)
        case workoutsListDismissed
        case selectedWorkoutDismissed
    }

    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring

    init(
        programsClient: ProgramsClientProtocol?,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
    ) {
        self.programsClient = programsClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
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
                    state.error = apiError.userFacing(context: .programDetails)
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
                    state.error = apiError.userFacing(context: .programDetails)
                }
                return .none

            case .openWorkoutsTapped:
                state.isWorkoutsPresented = true
                return .none

            case .workoutsListDismissed:
                state.isWorkoutsPresented = false
                return .none

            case let .workoutSelected(workoutID):
                state.selectedWorkout = State.SelectedWorkout(
                    userSub: state.userSub,
                    programId: state.programId,
                    workoutId: workoutID,
                )
                return .none

            case .selectedWorkoutDismissed:
                state.selectedWorkout = nil
                return .none
            }
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
