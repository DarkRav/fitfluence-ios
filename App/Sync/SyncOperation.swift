import Foundation

enum SyncOperationType: String, Codable, Equatable, Sendable {
    case upsertSet = "UPSERT_SET"
    case createCustomWorkout = "CREATE_CUSTOM_WORKOUT"
    case startWorkout = "START_WORKOUT"
    case completeWorkout = "COMPLETE_WORKOUT"
    case abandonWorkout = "ABANDON_WORKOUT"
}

enum SyncOperationStatus: String, Codable, Equatable, Sendable {
    case pending = "PENDING"
    case inFlight = "IN_FLIGHT"
    case sent = "SENT"
    case error = "ERROR"
    case dead = "DEAD"

    var isUnsent: Bool {
        switch self {
        case .pending, .inFlight, .error:
            return true
        case .sent, .dead:
            return false
        }
    }
}

struct SyncCustomWorkoutCreationPayload: Codable, Equatable, Sendable {
    let planId: String
    let idempotencyKey: String
    let source: WorkoutSource
    let title: String
    let scheduledDate: String?
    let scheduledAt: String?
    let notes: String?
    let exercises: [AthleteCustomWorkoutExerciseDraftRequest]
}

struct SyncOperationPayload: Codable, Equatable, Sendable {
    var weight: Double?
    var reps: Int?
    var rpe: Int?
    var isCompleted: Bool?
    var isWarmup: Bool?
    var restSecondsActual: Int?

    var startedAt: String?
    var completedAt: String?
    var abandonedAt: String?
    var customWorkoutCreation: SyncCustomWorkoutCreationPayload?

    static func upsertSet(
        weight: Double?,
        reps: Int?,
        rpe: Int?,
        isCompleted: Bool?,
        isWarmup: Bool?,
        restSecondsActual: Int?,
    ) -> SyncOperationPayload {
        SyncOperationPayload(
            weight: weight,
            reps: reps,
            rpe: rpe,
            isCompleted: isCompleted,
            isWarmup: isWarmup,
            restSecondsActual: restSecondsActual,
            startedAt: nil,
            completedAt: nil,
            abandonedAt: nil,
            customWorkoutCreation: nil,
        )
    }

    static func startWorkout(startedAt: String?) -> SyncOperationPayload {
        SyncOperationPayload(
            weight: nil,
            reps: nil,
            rpe: nil,
            isCompleted: nil,
            isWarmup: nil,
            restSecondsActual: nil,
            startedAt: startedAt,
            completedAt: nil,
            abandonedAt: nil,
            customWorkoutCreation: nil,
        )
    }

    static func completeWorkout(completedAt: String?) -> SyncOperationPayload {
        SyncOperationPayload(
            weight: nil,
            reps: nil,
            rpe: nil,
            isCompleted: nil,
            isWarmup: nil,
            restSecondsActual: nil,
            startedAt: nil,
            completedAt: completedAt,
            abandonedAt: nil,
            customWorkoutCreation: nil,
        )
    }

    static func abandonWorkout(abandonedAt: String?) -> SyncOperationPayload {
        SyncOperationPayload(
            weight: nil,
            reps: nil,
            rpe: nil,
            isCompleted: nil,
            isWarmup: nil,
            restSecondsActual: nil,
            startedAt: nil,
            completedAt: nil,
            abandonedAt: abandonedAt,
            customWorkoutCreation: nil,
        )
    }

    static func createCustomWorkout(_ payload: SyncCustomWorkoutCreationPayload) -> SyncOperationPayload {
        SyncOperationPayload(
            weight: nil,
            reps: nil,
            rpe: nil,
            isCompleted: nil,
            isWarmup: nil,
            restSecondsActual: nil,
            startedAt: nil,
            completedAt: nil,
            abandonedAt: nil,
            customWorkoutCreation: payload,
        )
    }
}

struct SyncOperation: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let type: SyncOperationType
    let createdAt: Date
    var updatedAt: Date
    var retryCount: Int
    var nextRetryAt: Date?
    var status: SyncOperationStatus
    let dedupeKey: String
    var payload: SyncOperationPayload

    let workoutInstanceId: String?
    let exerciseExecutionId: String?
    let setNumber: Int?

    var lastError: String?

    init(
        id: UUID = UUID(),
        type: SyncOperationType,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        retryCount: Int = 0,
        nextRetryAt: Date? = nil,
        status: SyncOperationStatus = .pending,
        dedupeKey: String,
        payload: SyncOperationPayload,
        workoutInstanceId: String?,
        exerciseExecutionId: String?,
        setNumber: Int?,
        lastError: String? = nil,
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.status = status
        self.dedupeKey = dedupeKey
        self.payload = payload
        self.workoutInstanceId = workoutInstanceId
        self.exerciseExecutionId = exerciseExecutionId
        self.setNumber = setNumber
        self.lastError = lastError
    }

    static func upsertSet(
        workoutInstanceId: String?,
        exerciseExecutionId: String,
        setNumber: Int,
        weight: Double?,
        reps: Int?,
        rpe: Int?,
        isCompleted: Bool?,
        isWarmup: Bool?,
        restSecondsActual: Int?,
    ) -> SyncOperation {
        SyncOperation(
            type: .upsertSet,
            dedupeKey: "\(exerciseExecutionId):\(setNumber)",
            payload: .upsertSet(
                weight: weight,
                reps: reps,
                rpe: rpe,
                isCompleted: isCompleted,
                isWarmup: isWarmup,
                restSecondsActual: restSecondsActual,
            ),
            workoutInstanceId: workoutInstanceId,
            exerciseExecutionId: exerciseExecutionId,
            setNumber: setNumber,
        )
    }

    static func startWorkout(workoutInstanceId: String, startedAt: Date?) -> SyncOperation {
        SyncOperation(
            type: .startWorkout,
            dedupeKey: "\(workoutInstanceId):\(SyncOperationType.startWorkout.rawValue)",
            payload: .startWorkout(startedAt: Self.iso8601String(startedAt)),
            workoutInstanceId: workoutInstanceId,
            exerciseExecutionId: nil,
            setNumber: nil,
        )
    }

    static func customWorkoutCreationIdempotencyKey(planId: String) -> String {
        "custom-workout-create:\(planId)"
    }

    static func createCustomWorkout(
        planId: String,
        source: WorkoutSource,
        workout: WorkoutDetailsModel,
        scheduledDay: Date,
    ) -> SyncOperation {
        let request = workout.asCreateCustomWorkoutRequest(scheduledDate: scheduledDay)
        return SyncOperation(
            type: .createCustomWorkout,
            dedupeKey: "\(planId):\(SyncOperationType.createCustomWorkout.rawValue)",
            payload: .createCustomWorkout(
                SyncCustomWorkoutCreationPayload(
                    planId: planId,
                    idempotencyKey: customWorkoutCreationIdempotencyKey(planId: planId),
                    source: source,
                    title: request.title,
                    scheduledDate: request.scheduledDate,
                    scheduledAt: request.scheduledAt,
                    notes: request.notes,
                    exercises: request.exercises ?? [],
                )
            ),
            workoutInstanceId: nil,
            exerciseExecutionId: nil,
            setNumber: nil,
        )
    }

    static func completeWorkout(workoutInstanceId: String, completedAt: Date?) -> SyncOperation {
        SyncOperation(
            type: .completeWorkout,
            dedupeKey: "\(workoutInstanceId):\(SyncOperationType.completeWorkout.rawValue)",
            payload: .completeWorkout(completedAt: Self.iso8601String(completedAt)),
            workoutInstanceId: workoutInstanceId,
            exerciseExecutionId: nil,
            setNumber: nil,
        )
    }

    static func abandonWorkout(workoutInstanceId: String, abandonedAt: Date?) -> SyncOperation {
        SyncOperation(
            type: .abandonWorkout,
            dedupeKey: "\(workoutInstanceId):\(SyncOperationType.abandonWorkout.rawValue)",
            payload: .abandonWorkout(abandonedAt: Self.iso8601String(abandonedAt)),
            workoutInstanceId: workoutInstanceId,
            exerciseExecutionId: nil,
            setNumber: nil,
        )
    }

    func withUpdatedPayload(_ payload: SyncOperationPayload, at updatedAt: Date = Date()) -> SyncOperation {
        var copy = self
        copy.payload = payload
        copy.updatedAt = updatedAt
        copy.retryCount = 0
        copy.nextRetryAt = nil
        copy.status = .pending
        copy.lastError = nil
        return copy
    }

    mutating func markInFlight(at date: Date) {
        status = .inFlight
        updatedAt = date
        lastError = nil
    }

    mutating func markSent(at date: Date) {
        status = .sent
        updatedAt = date
        nextRetryAt = nil
        lastError = nil
    }

    mutating func markError(error: String, nextRetryAt: Date?, at date: Date) {
        status = .error
        updatedAt = date
        self.nextRetryAt = nextRetryAt
        lastError = error
    }

    mutating func markDead(error: String, at date: Date) {
        status = .dead
        updatedAt = date
        nextRetryAt = nil
        lastError = error
    }

    mutating func resetRetry(at date: Date) {
        retryCount = 0
        nextRetryAt = nil
        status = .pending
        updatedAt = date
        lastError = nil
    }

    private static func iso8601String(_ date: Date?) -> String? {
        guard let date else { return nil }
        return iso8601WithFractions.string(from: date)
    }

    static func parseISO8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = iso8601WithFractions.date(from: value) {
            return date
        }
        return iso8601.date(from: value)
    }

    private static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct SyncLogEntry: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operationId: UUID?
    let operationType: SyncOperationType?
    let operationStatus: SyncOperationStatus?
    let message: String
    let error: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        operationId: UUID? = nil,
        operationType: SyncOperationType? = nil,
        operationStatus: SyncOperationStatus? = nil,
        message: String,
        error: String? = nil,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operationId = operationId
        self.operationType = operationType
        self.operationStatus = operationStatus
        self.message = message
        self.error = error
    }
}

struct SyncDiagnosticsSnapshot: Equatable, Sendable {
    let pendingCount: Int
    let lastSyncAttemptAt: Date?
    let lastSyncError: String?
    let logs: [SyncLogEntry]
    let hasDelayedRetries: Bool
}
