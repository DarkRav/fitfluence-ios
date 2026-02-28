import ComposableArchitecture
import Foundation

@Reducer
struct WorkoutPlayerFeature {
    struct SetProgress: Equatable, Sendable {
        var isCompleted = false
        var repsText = ""
        var weightText = ""
        var rpeText = ""
    }

    struct ExerciseProgress: Equatable, Sendable {
        var sets: [SetProgress]
    }

    struct CompletionSummary: Equatable, Sendable {
        let completedExercises: Int
        let totalExercises: Int
        let completedSets: Int
    }

    @ObservableState
    struct State: Equatable {
        let userSub: String
        let programId: String
        let workoutId: String
        var workout: WorkoutDetailsModel?
        var isShowingCachedData = false
        var currentExerciseIndex = 0
        var perExerciseState: [String: ExerciseProgress] = [:]
        var isLoading = false
        var error: UserFacingError?
        var hasChanges = false
        var isExitConfirmationPresented = false
        var isResumePromptPresented = false
        var hasPromptedResume = false
        var completionSummary: CompletionSummary?
        var progressStorageMode: WorkoutProgressStorageMode = .localOnly
    }

    enum Action: Equatable {
        case onAppear
        case retry
        case cachedDetailsResponse(WorkoutDetailsModel?)
        case detailsResponse(Result<WorkoutDetailsModel, APIError>)
        case loadedProgress(WorkoutProgressSnapshot?)
        case nextExerciseTapped
        case prevExerciseTapped
        case toggleSetComplete(exerciseId: String, setIndex: Int)
        case updateSetReps(exerciseId: String, setIndex: Int, value: String)
        case updateSetWeight(exerciseId: String, setIndex: Int, value: String)
        case updateSetRPE(exerciseId: String, setIndex: Int, value: String)
        case incrementSetReps(exerciseId: String, setIndex: Int)
        case decrementSetReps(exerciseId: String, setIndex: Int)
        case incrementSetWeight(exerciseId: String, setIndex: Int)
        case decrementSetWeight(exerciseId: String, setIndex: Int)
        case exitTapped
        case exitConfirmed
        case exitConfirmationDismissed
        case resumePromptContinueTapped
        case resumePromptStartOverTapped
        case finishWorkoutTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case workoutCompleted(CompletionSummary)
        case closeRequested
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
                guard state.workout == nil, !state.isLoading else { return .none }
                state.isLoading = true
                state.error = nil
                state.progressStorageMode = workoutsClient.progressStorageMode
                return .concatenate(
                    loadCachedWorkout(programId: state.programId, workoutId: state.workoutId, namespace: state.userSub),
                    loadWorkout(programId: state.programId, workoutId: state.workoutId),
                )

            case .retry:
                state.isLoading = true
                state.error = nil
                return .concatenate(
                    loadCachedWorkout(programId: state.programId, workoutId: state.workoutId, namespace: state.userSub),
                    loadWorkout(programId: state.programId, workoutId: state.workoutId),
                )

            case let .cachedDetailsResponse(cached):
                guard let cached else { return .none }
                state.workout = cached
                state.currentExerciseIndex = 0
                state.perExerciseState = makeExerciseProgress(for: cached)
                state.isShowingCachedData = true
                let userSub = state.userSub
                let programId = state.programId
                let workoutId = state.workoutId
                return .run { [progressStore] send in
                    let snapshot = await progressStore.load(
                        userSub: userSub,
                        programId: programId,
                        workoutId: workoutId,
                    )
                    await send(.loadedProgress(snapshot))
                }

            case let .detailsResponse(result):
                state.isLoading = false
                switch result {
                case let .success(workout):
                    state.workout = workout
                    state.currentExerciseIndex = 0
                    state.perExerciseState = makeExerciseProgress(for: workout)
                    state.isShowingCachedData = false
                    state.error = nil
                    let userSub = state.userSub
                    let programId = state.programId
                    let workoutId = state.workoutId
                    let namespace = state.userSub
                    let key = cacheKey(programId: state.programId, workoutId: workout.id)
                    return .merge(
                        .run { [cacheStore] _ in
                            await cacheStore.set(key, value: workout, namespace: namespace, ttl: 60 * 30)
                        },
                        .run { [progressStore] send in
                            let snapshot = await progressStore.load(
                                userSub: userSub,
                                programId: programId,
                                workoutId: workoutId,
                            )
                            await send(.loadedProgress(snapshot))
                        },
                    )
                case let .failure(error):
                    if error == .offline || !networkMonitor.currentStatus, state.workout != nil {
                        state.error = nil
                        state.isShowingCachedData = true
                        return .none
                    }
                    state.error = error.userFacing(context: .workoutPlayer)
                    return .none
                }

            case let .loadedProgress(snapshot):
                guard let snapshot else { return .none }
                state.perExerciseState = mergeStoredProgress(
                    stored: snapshot,
                    fallback: state.perExerciseState,
                )
                if let index = snapshot.currentExerciseIndex {
                    let maxIndex = max(0, (state.workout?.exercises.count ?? 1) - 1)
                    state.currentExerciseIndex = min(max(0, index), maxIndex)
                }
                state.hasChanges = snapshot.status != .notStarted
                if !state.hasPromptedResume, snapshot.status == .inProgress {
                    state.isResumePromptPresented = true
                }
                return .none

            case .nextExerciseTapped:
                guard let workout = state.workout else { return .none }
                state.currentExerciseIndex = min(state.currentExerciseIndex + 1, max(0, workout.exercises.count - 1))
                state.hasChanges = true
                return persistProgress(state: state)

            case .prevExerciseTapped:
                state.currentExerciseIndex = max(0, state.currentExerciseIndex - 1)
                state.hasChanges = true
                return persistProgress(state: state)

            case let .toggleSetComplete(exerciseID, setIndex):
                guard var progress = state.perExerciseState[exerciseID], progress.sets.indices.contains(setIndex) else {
                    return .none
                }
                progress.sets[setIndex].isCompleted.toggle()
                state.perExerciseState[exerciseID] = progress
                if progress.sets[setIndex].isCompleted {
                    applyCarryOverValues(state: &state, exerciseID: exerciseID, setIndex: setIndex)
                }
                state.hasChanges = true
                return persistProgress(state: state)

            case let .updateSetReps(exerciseID, setIndex, value):
                updateSetState(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    update: { $0.repsText = value },
                )
                state.hasChanges = true
                return persistProgress(state: state)

            case let .updateSetWeight(exerciseID, setIndex, value):
                updateSetState(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    update: { $0.weightText = value },
                )
                state.hasChanges = true
                return persistProgress(state: state)

            case let .updateSetRPE(exerciseID, setIndex, value):
                updateSetState(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    update: { $0.rpeText = value },
                )
                state.hasChanges = true
                return persistProgress(state: state)

            case let .incrementSetReps(exerciseID, setIndex):
                return updateNumericValue(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    keyPath: \.repsText,
                    delta: 1,
                    formatter: { String(Int($0)) },
                )

            case let .decrementSetReps(exerciseID, setIndex):
                return updateNumericValue(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    keyPath: \.repsText,
                    delta: -1,
                    formatter: { String(Int($0)) },
                )

            case let .incrementSetWeight(exerciseID, setIndex):
                return updateNumericValue(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    keyPath: \.weightText,
                    delta: 2.5,
                    formatter: formatWeight,
                )

            case let .decrementSetWeight(exerciseID, setIndex):
                return updateNumericValue(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    keyPath: \.weightText,
                    delta: -2.5,
                    formatter: formatWeight,
                )

            case .exitTapped:
                if state.hasChanges {
                    state.isExitConfirmationPresented = true
                    return .none
                }
                return .send(.delegate(.closeRequested))

            case .exitConfirmationDismissed:
                state.isExitConfirmationPresented = false
                return .none

            case .resumePromptContinueTapped:
                state.isResumePromptPresented = false
                state.hasPromptedResume = true
                return .none

            case .resumePromptStartOverTapped:
                state.isResumePromptPresented = false
                state.hasPromptedResume = true
                guard let workout = state.workout else { return .none }
                state.currentExerciseIndex = 0
                state.perExerciseState = makeExerciseProgress(for: workout)
                state.hasChanges = false
                return persistProgress(state: state)

            case .exitConfirmed:
                state.isExitConfirmationPresented = false
                return .merge(
                    persistProgress(state: state),
                    .send(.delegate(.closeRequested)),
                )

            case .finishWorkoutTapped:
                guard let workout = state.workout else { return .none }
                let summary = makeSummary(workout: workout, perExercise: state.perExerciseState)
                state.completionSummary = summary
                return .merge(
                    persistProgress(state: state, isFinished: true),
                    .send(.delegate(.workoutCompleted(summary))),
                )

            case .delegate:
                return .none
            }
        }
    }

    private func updateSetState(
        state: inout State,
        exerciseID: String,
        setIndex: Int,
        update: (inout SetProgress) -> Void,
    ) {
        guard var progress = state.perExerciseState[exerciseID], progress.sets.indices.contains(setIndex) else {
            return
        }
        update(&progress.sets[setIndex])
        state.perExerciseState[exerciseID] = progress
    }

    private func updateNumericValue(
        state: inout State,
        exerciseID: String,
        setIndex: Int,
        keyPath: WritableKeyPath<SetProgress, String>,
        delta: Double,
        formatter: (Double) -> String,
    ) -> Effect<Action> {
        guard var progress = state.perExerciseState[exerciseID], progress.sets.indices.contains(setIndex) else {
            return .none
        }
        let currentRaw = progress.sets[setIndex][keyPath: keyPath]
        let current = parseDouble(currentRaw) ?? 0
        let nextValue = max(0, current + delta)
        progress.sets[setIndex][keyPath: keyPath] = formatter(nextValue)
        state.perExerciseState[exerciseID] = progress
        state.hasChanges = true
        return persistProgress(state: state)
    }

    private func loadWorkout(programId: String, workoutId: String) -> Effect<Action> {
        .run { [workoutsClient] send in
            let result = await workoutsClient.getWorkoutDetails(programId: programId, workoutId: workoutId)
            await send(.detailsResponse(result))
        }
    }

    private func loadCachedWorkout(programId: String, workoutId: String, namespace: String) -> Effect<Action> {
        .run { [cacheStore] send in
            let key = cacheKey(programId: programId, workoutId: workoutId)
            let cached = await cacheStore.get(key, as: WorkoutDetailsModel.self, namespace: namespace)
            await send(.cachedDetailsResponse(cached))
        }
    }

    private func makeExerciseProgress(for workout: WorkoutDetailsModel) -> [String: ExerciseProgress] {
        var result: [String: ExerciseProgress] = [:]
        for exercise in workout.exercises {
            let sets = Array(repeating: SetProgress(), count: max(1, exercise.sets))
            result[exercise.id] = ExerciseProgress(sets: sets)
        }
        return result
    }

    private func mergeStoredProgress(
        stored: WorkoutProgressSnapshot,
        fallback: [String: ExerciseProgress],
    ) -> [String: ExerciseProgress] {
        var merged = fallback
        for (exerciseID, storedExercise) in stored.exercises {
            guard var current = merged[exerciseID] else { continue }
            for index in current.sets.indices {
                guard storedExercise.sets.indices.contains(index) else { continue }
                let source = storedExercise.sets[index]
                current.sets[index].isCompleted = source.isCompleted
                current.sets[index].repsText = source.repsText
                current.sets[index].weightText = source.weightText
                current.sets[index].rpeText = source.rpeText
            }
            merged[exerciseID] = current
        }
        return merged
    }

    private func persistProgress(state: State, isFinished: Bool = false) -> Effect<Action> {
        let snapshot = WorkoutProgressSnapshot(
            userSub: state.userSub,
            programId: state.programId,
            workoutId: state.workoutId,
            currentExerciseIndex: state.currentExerciseIndex,
            isFinished: isFinished,
            lastUpdated: Date(),
            exercises: state.perExerciseState.mapValues { value in
                StoredExerciseProgress(
                    sets: value.sets.map { set in
                        StoredSetProgress(
                            isCompleted: set.isCompleted,
                            repsText: set.repsText,
                            weightText: set.weightText,
                            rpeText: set.rpeText,
                        )
                    },
                )
            },
        )

        return .run { [progressStore] _ in
            await progressStore.save(snapshot)
        }
    }

    private func applyCarryOverValues(state: inout State, exerciseID: String, setIndex: Int) {
        guard var progress = state.perExerciseState[exerciseID], progress.sets.indices.contains(setIndex) else {
            return
        }
        let nextIndex = setIndex + 1
        guard progress.sets.indices.contains(nextIndex) else { return }
        let source = progress.sets[setIndex]
        if progress.sets[nextIndex].repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            progress.sets[nextIndex].repsText = source.repsText
        }
        if progress.sets[nextIndex].weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            progress.sets[nextIndex].weightText = source.weightText
        }
        if progress.sets[nextIndex].rpeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            progress.sets[nextIndex].rpeText = source.rpeText
        }
        state.perExerciseState[exerciseID] = progress
    }

    private func parseDouble(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatWeight(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func makeSummary(
        workout: WorkoutDetailsModel,
        perExercise: [String: ExerciseProgress],
    ) -> CompletionSummary {
        let completedExercises = workout.exercises.count(where: { exercise in
            guard let progress = perExercise[exercise.id] else { return false }
            return !progress.sets.isEmpty && progress.sets.allSatisfy(\.isCompleted)
        })

        let completedSets = perExercise.values
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .count

        return CompletionSummary(
            completedExercises: completedExercises,
            totalExercises: workout.exercises.count,
            completedSets: completedSets,
        )
    }

    private func cacheKey(programId: String, workoutId: String) -> String {
        "workout.details:\(programId):\(workoutId)"
    }
}
