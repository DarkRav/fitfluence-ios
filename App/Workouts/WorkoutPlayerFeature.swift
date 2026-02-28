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
        let programId: String
        let workoutId: String
        var workout: WorkoutDetailsModel?
        var currentExerciseIndex = 0
        var perExerciseState: [String: ExerciseProgress] = [:]
        var isLoading = false
        var error: UserFacingError?
        var completionSummary: CompletionSummary?
        var progressStorageMode: WorkoutProgressStorageMode = .localOnly
    }

    enum Action: Equatable {
        case onAppear
        case retry
        case detailsResponse(Result<WorkoutDetailsModel, APIError>)
        case nextExerciseTapped
        case prevExerciseTapped
        case toggleSetComplete(exerciseId: String, setIndex: Int)
        case updateSetReps(exerciseId: String, setIndex: Int, value: String)
        case updateSetWeight(exerciseId: String, setIndex: Int, value: String)
        case updateSetRPE(exerciseId: String, setIndex: Int, value: String)
        case finishWorkoutTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case workoutCompleted(CompletionSummary)
    }

    private let workoutsClient: WorkoutsClientProtocol

    init(workoutsClient: WorkoutsClientProtocol) {
        self.workoutsClient = workoutsClient
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.workout == nil, !state.isLoading else { return .none }
                state.isLoading = true
                state.error = nil
                state.progressStorageMode = workoutsClient.progressStorageMode
                return loadWorkout(programId: state.programId, workoutId: state.workoutId)

            case .retry:
                state.isLoading = true
                state.error = nil
                return loadWorkout(programId: state.programId, workoutId: state.workoutId)

            case let .detailsResponse(result):
                state.isLoading = false
                switch result {
                case let .success(workout):
                    state.workout = workout
                    state.currentExerciseIndex = 0
                    state.perExerciseState = makeExerciseProgress(for: workout)
                    state.error = nil
                case let .failure(error):
                    state.error = error.workoutPlayerUserFacingError
                }
                return .none

            case .nextExerciseTapped:
                guard let workout = state.workout else { return .none }
                state.currentExerciseIndex = min(state.currentExerciseIndex + 1, max(0, workout.exercises.count - 1))
                return .none

            case .prevExerciseTapped:
                state.currentExerciseIndex = max(0, state.currentExerciseIndex - 1)
                return .none

            case let .toggleSetComplete(exerciseID, setIndex):
                guard var progress = state.perExerciseState[exerciseID], progress.sets.indices.contains(setIndex) else {
                    return .none
                }
                progress.sets[setIndex].isCompleted.toggle()
                state.perExerciseState[exerciseID] = progress
                return .none

            case let .updateSetReps(exerciseID, setIndex, value):
                return updateSetState(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    update: { $0.repsText = value },
                )

            case let .updateSetWeight(exerciseID, setIndex, value):
                return updateSetState(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    update: { $0.weightText = value },
                )

            case let .updateSetRPE(exerciseID, setIndex, value):
                return updateSetState(
                    state: &state,
                    exerciseID: exerciseID,
                    setIndex: setIndex,
                    update: { $0.rpeText = value },
                )

            case .finishWorkoutTapped:
                guard let workout = state.workout else { return .none }
                let summary = makeSummary(workout: workout, perExercise: state.perExerciseState)
                state.completionSummary = summary
                return .send(.delegate(.workoutCompleted(summary)))

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
    ) -> Effect<Action> {
        guard var progress = state.perExerciseState[exerciseID], progress.sets.indices.contains(setIndex) else {
            return .none
        }
        update(&progress.sets[setIndex])
        state.perExerciseState[exerciseID] = progress
        return .none
    }

    private func loadWorkout(programId: String, workoutId: String) -> Effect<Action> {
        .run { [workoutsClient] send in
            let result = await workoutsClient.getWorkoutDetails(programId: programId, workoutId: workoutId)
            await send(.detailsResponse(result))
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
}

private extension APIError {
    var workoutPlayerUserFacingError: UserFacingError {
        switch self {
        case .offline:
            UserFacingError(
                title: "Нет подключения к интернету",
                message: "Проверьте соединение и откройте тренировку снова.",
            )
        case .serverError, .transportError, .timeout:
            UserFacingError(
                title: "Сервис временно недоступен",
                message: "Не удалось загрузить детали тренировки.",
            )
        case .decodingError:
            UserFacingError(
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера",
            )
        default:
            UserFacingError(
                title: "Ошибка загрузки",
                message: "Тренировку пока не удалось открыть.",
            )
        }
    }
}
