import Foundation

enum WorkoutProgressStorageMode: String, Equatable, Sendable {
    case localOnly
    case serverBacked
}

struct WorkoutSummary: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let dayOrder: Int
    let exerciseCount: Int
    let estimatedDurationMinutes: Int?
}

struct WorkoutDetailsModel: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let dayOrder: Int
    let coachNote: String?
    let exercises: [WorkoutExercise]
}

struct WorkoutExercise: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let sets: Int
    let repsMin: Int?
    let repsMax: Int?
    let targetRpe: Int?
    let restSeconds: Int?
    let notes: String?
    let orderIndex: Int
}

protocol WorkoutsClientProtocol: Sendable {
    func listWorkouts(for programId: String) async -> Result<[WorkoutSummary], APIError>
    func getWorkoutDetails(programId: String, workoutId: String) async -> Result<WorkoutDetailsModel, APIError>
    var progressStorageMode: WorkoutProgressStorageMode { get }
}

struct WorkoutsClient: WorkoutsClientProtocol {
    let programsClient: ProgramsClientProtocol
    let progressStorageMode: WorkoutProgressStorageMode

    init(
        programsClient: ProgramsClientProtocol,
        progressStorageMode: WorkoutProgressStorageMode = .localOnly,
    ) {
        self.programsClient = programsClient
        self.progressStorageMode = progressStorageMode
    }

    func listWorkouts(for programId: String) async -> Result<[WorkoutSummary], APIError> {
        let detailsResult = await programsClient.getProgramDetails(programId: programId)

        switch detailsResult {
        case let .success(details):
            let workouts = (details.workouts ?? [])
                .sorted(by: { $0.dayOrder < $1.dayOrder })
                .map { template in
                    let exercises = template.exercises ?? []
                    return WorkoutSummary(
                        id: template.id,
                        title: template.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? template.title! : "Тренировка \(template.dayOrder)",
                        dayOrder: template.dayOrder,
                        exerciseCount: exercises.count,
                        estimatedDurationMinutes: estimateDurationMinutes(exercises: exercises),
                    )
                }
            return .success(workouts)

        case let .failure(error):
            return .failure(error)
        }
    }

    func getWorkoutDetails(programId: String, workoutId: String) async -> Result<WorkoutDetailsModel, APIError> {
        let detailsResult = await programsClient.getProgramDetails(programId: programId)

        switch detailsResult {
        case let .success(details):
            guard let template = details.workouts?.first(where: { $0.id == workoutId }) else {
                return .failure(.httpError(statusCode: 404, bodySnippet: nil))
            }

            let mappedExercises = (template.exercises ?? [])
                .enumerated()
                .map { index, exercise in
                    WorkoutExercise(
                        id: exercise.id,
                        name: exercise.exercise.name,
                        sets: exercise.sets,
                        repsMin: exercise.repsMin,
                        repsMax: exercise.repsMax,
                        targetRpe: exercise.targetRpe,
                        restSeconds: exercise.restSeconds,
                        notes: exercise.notes,
                        orderIndex: exercise.orderIndex ?? index,
                    )
                }
                .sorted(by: { $0.orderIndex < $1.orderIndex })

            let title = template.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? template.title! : "Тренировка \(template.dayOrder)"

            return .success(
                WorkoutDetailsModel(
                    id: template.id,
                    title: title,
                    dayOrder: template.dayOrder,
                    coachNote: template.coachNote,
                    exercises: mappedExercises,
                ),
            )

        case let .failure(error):
            return .failure(error)
        }
    }

    private func estimateDurationMinutes(exercises: [ExerciseTemplate]) -> Int? {
        guard !exercises.isEmpty else { return 0 }
        let totalSets = exercises.reduce(0) { $0 + max(1, $1.sets) }
        let restSeconds = exercises.reduce(0) { partial, item in
            partial + (item.restSeconds ?? 45) * max(0, item.sets - 1)
        }
        let estimatedSeconds = totalSets * 90 + restSeconds
        return max(10, estimatedSeconds / 60)
    }
}

struct UnavailableWorkoutsClient: WorkoutsClientProtocol {
    let progressStorageMode: WorkoutProgressStorageMode = .localOnly

    func listWorkouts(for _: String) async -> Result<[WorkoutSummary], APIError> {
        .failure(.invalidURL)
    }

    func getWorkoutDetails(programId _: String, workoutId _: String) async -> Result<WorkoutDetailsModel, APIError> {
        .failure(.invalidURL)
    }
}
