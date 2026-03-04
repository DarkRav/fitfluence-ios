import Foundation

struct ActiveEnrollmentProgressResponse: Codable, Equatable, Sendable {
    let programId: String?
    let programTitle: String?
    let programVersionId: String?
    let nextWorkoutId: String?
    let nextWorkoutTitle: String?
    let completedSessions: Int?
    let totalSessions: Int?
    let lastCompletedAt: String?
}

enum AthleteWorkoutSource: String, Codable, Equatable, Sendable {
    case program = "PROGRAM"
    case custom = "CUSTOM"
}

struct AthleteWorkoutInstance: Codable, Equatable, Sendable {
    let id: String
    let enrollmentId: String?
    let workoutTemplateId: String?
    let title: String?
    let source: AthleteWorkoutSource
    let scheduledDate: String?
    let startedAt: String?
    let completedAt: String?
    let durationSeconds: Int?
    let notes: String?
}

struct AthleteExerciseBrief: Codable, Equatable, Sendable {
    let id: String
    let code: String?
    let name: String
}

struct AthleteSetExecution: Codable, Equatable, Sendable {
    let id: String
    let setNumber: Int
    let weight: Double?
    let reps: Int?
    let rpe: Int?
    let isCompleted: Bool
    let restSecondsActual: Int?
}

struct AthleteExerciseExecution: Codable, Equatable, Sendable {
    let id: String
    let workoutInstanceId: String
    let exerciseTemplateId: String?
    let workoutPlanId: String?
    let exerciseId: String
    let orderIndex: Int
    let notes: String?
    let plannedSets: Int?
    let plannedRepsMin: Int?
    let plannedRepsMax: Int?
    let plannedTargetRpe: Int?
    let plannedRestSeconds: Int?
    let plannedNotes: String?
    let progressionPolicyId: String?
    let exercise: AthleteExerciseBrief?
    let sets: [AthleteSetExecution]?
}

struct AthleteWorkoutDetailsResponse: Codable, Equatable, Sendable {
    let workout: AthleteWorkoutInstance
    let exercises: [AthleteExerciseExecution]
}

private struct StartWorkoutRequestBody: Codable, Sendable {
    let startedAt: String?
}

protocol AthleteTrainingClientProtocol: Sendable {
    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError>
    func getWorkoutDetails(workoutInstanceId: String) async -> Result<AthleteWorkoutDetailsResponse, APIError>
    func startWorkout(workoutInstanceId: String, startedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError>
}

extension AthleteWorkoutDetailsResponse {
    func asWorkoutDetailsModel() -> WorkoutDetailsModel {
        let mappedExercises = exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .enumerated()
            .map { index, execution in
                WorkoutExercise(
                    id: execution.exerciseId,
                    name: execution.exercise?.name.trimmedNilIfEmpty ?? "Упражнение \(index + 1)",
                    sets: max(1, execution.plannedSets ?? execution.sets?.count ?? 1),
                    repsMin: execution.plannedRepsMin,
                    repsMax: execution.plannedRepsMax,
                    targetRpe: execution.plannedTargetRpe,
                    restSeconds: execution.plannedRestSeconds,
                    notes: execution.plannedNotes?.trimmedNilIfEmpty ?? execution.notes?.trimmedNilIfEmpty,
                    orderIndex: execution.orderIndex,
                )
            }

        let title = workout.title?.trimmedNilIfEmpty ?? "Тренировка"

        return WorkoutDetailsModel(
            id: workout.id,
            title: title,
            dayOrder: 0,
            coachNote: workout.notes?.trimmedNilIfEmpty,
            exercises: mappedExercises,
        )
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension APIClient: AthleteTrainingClientProtocol {
    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/enrollments/active", requiresAuthorization: true)
        return await decode(request, as: ActiveEnrollmentProgressResponse.self)
    }

    func getWorkoutDetails(workoutInstanceId: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/workouts/\(workoutInstanceId)", requiresAuthorization: true)
        return await decode(request, as: AthleteWorkoutDetailsResponse.self)
    }

    func startWorkout(workoutInstanceId: String, startedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        do {
            var body: Data?
            if let startedAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let payload = StartWorkoutRequestBody(startedAt: formatter.string(from: startedAt))
                body = try JSONEncoder().encode(payload)
            }

            let request = APIRequest(
                path: "/v1/athlete/workouts/\(workoutInstanceId)/start",
                method: .post,
                body: body,
                requiresAuthorization: true,
            )
            return await decode(request, as: AthleteWorkoutInstance.self)
        } catch {
            return .failure(.unknown)
        }
    }
}
