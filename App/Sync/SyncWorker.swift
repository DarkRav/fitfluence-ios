import Foundation

actor SyncWorker {
    private enum ExecutionOutcome {
        case success
        case retry(delay: TimeInterval, error: String)
        case delayed(error: String)
        case dead(error: String)
    }

    private let outboxStore: SyncOutboxStore
    private var isRunning = false

    init(outboxStore: SyncOutboxStore) {
        self.outboxStore = outboxStore
    }

    func process(
        namespace: String,
        athleteTrainingClient: AthleteTrainingClientProtocol?,
        isOnline: Bool,
    ) async {
        guard !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isOnline else { return }
        guard let athleteTrainingClient else { return }
        guard !isRunning else { return }

        isRunning = true
        defer { isRunning = false }

        await outboxStore.recoverInFlight(namespace: namespace)
        await outboxStore.markSyncAttempt(namespace: namespace, error: nil)

        while true {
            let allOperations = await outboxStore.allOperations(namespace: namespace)
            let now = Date()

            guard let operation = selectNextOperation(from: allOperations, now: now) else {
                break
            }

            await outboxStore.markInFlight(operationId: operation.id, namespace: namespace)

            let outcome = await execute(operation: operation, client: athleteTrainingClient)
            switch outcome {
            case .success:
                await outboxStore.markSent(operationId: operation.id, namespace: namespace)
                await outboxStore.markSyncAttempt(namespace: namespace, error: nil)

            case let .retry(delay, error):
                let nextRetryAt = Date().addingTimeInterval(delay)
                await outboxStore.markRetryableError(
                    operationId: operation.id,
                    namespace: namespace,
                    error: error,
                    nextRetryAt: nextRetryAt,
                    retryCount: operation.retryCount + 1,
                )
                await outboxStore.markSyncAttempt(namespace: namespace, error: error)

            case let .delayed(error):
                await outboxStore.markRetryableError(
                    operationId: operation.id,
                    namespace: namespace,
                    error: error,
                    nextRetryAt: nil,
                    retryCount: operation.retryCount + 1,
                )
                await outboxStore.markSyncAttempt(namespace: namespace, error: error)

            case let .dead(error):
                await outboxStore.markDead(operationId: operation.id, namespace: namespace, error: error)
                await outboxStore.markSyncAttempt(namespace: namespace, error: error)
            }
        }
    }

    nonisolated func backoffDelay(forRetryCount retryCount: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [2, 5, 15, 30, 60, 120, 300]
        guard retryCount > 0 else { return schedule[0] }
        let index = min(retryCount - 1, schedule.count - 1)
        return schedule[index]
    }

    private func execute(
        operation: SyncOperation,
        client: AthleteTrainingClientProtocol,
    ) async -> ExecutionOutcome {
        let result: Result<Void, APIError>

        switch operation.type {
        case .upsertSet:
            guard let exerciseExecutionId = operation.exerciseExecutionId,
                  let setNumber = operation.setNumber
            else {
                return .dead(error: "Invalid UPSERT_SET payload")
            }

            let response = await client.updateExerciseSet(
                exerciseExecutionId: exerciseExecutionId,
                setNumber: setNumber,
                weight: operation.payload.weight,
                reps: operation.payload.reps,
                rpe: operation.payload.rpe,
                isCompleted: operation.payload.isCompleted,
                isWarmup: operation.payload.isWarmup,
                restSecondsActual: operation.payload.restSecondsActual,
            )
            result = response.map { _ in () }

        case .startWorkout:
            guard let workoutInstanceId = operation.workoutInstanceId else {
                return .dead(error: "Invalid START_WORKOUT payload")
            }

            let response = await client.startWorkout(
                workoutInstanceId: workoutInstanceId,
                startedAt: SyncOperation.parseISO8601(operation.payload.startedAt),
            )
            result = response.map { _ in () }

        case .completeWorkout:
            guard let workoutInstanceId = operation.workoutInstanceId else {
                return .dead(error: "Invalid COMPLETE_WORKOUT payload")
            }

            let response = await client.completeWorkout(
                workoutInstanceId: workoutInstanceId,
                completedAt: SyncOperation.parseISO8601(operation.payload.completedAt),
            )
            result = response.map { _ in () }

        case .abandonWorkout:
            guard let workoutInstanceId = operation.workoutInstanceId else {
                return .dead(error: "Invalid ABANDON_WORKOUT payload")
            }

            let response = await client.abandonWorkout(
                workoutInstanceId: workoutInstanceId,
                abandonedAt: SyncOperation.parseISO8601(operation.payload.abandonedAt),
            )
            result = response.map { _ in () }
        }

        switch result {
        case .success:
            return .success
        case let .failure(error):
            return classify(error: error, operation: operation)
        }
    }

    private func classify(error: APIError, operation: SyncOperation) -> ExecutionOutcome {
        switch error {
        case .offline, .timeout, .transportError, .cancelled, .serverError:
            return .retry(
                delay: backoffDelay(forRetryCount: operation.retryCount + 1),
                error: describe(error: error),
            )

        case .unauthorized:
            return .dead(error: "Unauthorized after refresh. User was logged out")

        case .forbidden:
            return .dead(error: "Forbidden (403). Operation moved to DEAD")

        case let .httpError(statusCode, body):
            if operation.type == .startWorkout, statusCode == 409 {
                return .success
            }

            if statusCode == 403 || statusCode == 422 {
                return .dead(error: "HTTP \(statusCode). Validation/forbidden error")
            }

            if statusCode == 409 {
                return .delayed(error: "Conflict (409). Manual session reset may be required")
            }

            if (500 ... 599).contains(statusCode) {
                return .retry(
                    delay: backoffDelay(forRetryCount: operation.retryCount + 1),
                    error: "HTTP \(statusCode) \(body ?? "")",
                )
            }

            return .dead(error: "HTTP \(statusCode) \(body ?? "")")

        case .decodingError, .unknown:
            return .retry(
                delay: backoffDelay(forRetryCount: operation.retryCount + 1),
                error: describe(error: error),
            )

        case .invalidURL:
            return .dead(error: "Invalid URL in sync operation")
        }
    }

    private func selectNextOperation(from operations: [SyncOperation], now: Date) -> SyncOperation? {
        let unsent = operations.filter { $0.status.isUnsent }
        let ready = unsent
            .filter { operation in
                if operation.status == .error {
                    guard let nextRetryAt = operation.nextRetryAt else {
                        // Manual intervention required.
                        return false
                    }
                    return nextRetryAt <= now
                }
                return operation.status != .inFlight
            }
            .sorted(by: sortByCreatedAt)

        for candidate in ready {
            if dependenciesSatisfied(for: candidate, within: unsent) {
                return candidate
            }
        }

        return nil
    }

    private func dependenciesSatisfied(for candidate: SyncOperation, within unsent: [SyncOperation]) -> Bool {
        guard let workoutId = candidate.workoutInstanceId else {
            return true
        }

        switch candidate.type {
        case .upsertSet:
            let hasUnsentStart = unsent.contains(where: {
                $0.id != candidate.id &&
                    $0.workoutInstanceId == workoutId &&
                    $0.type == .startWorkout
            })
            return !hasUnsentStart

        case .completeWorkout:
            let hasUnsentSet = unsent.contains(where: {
                $0.id != candidate.id &&
                    $0.workoutInstanceId == workoutId &&
                    $0.type == .upsertSet
            })
            if hasUnsentSet {
                return false
            }

            let hasUnsentStart = unsent.contains(where: {
                $0.id != candidate.id &&
                    $0.workoutInstanceId == workoutId &&
                    $0.type == .startWorkout
            })
            return !hasUnsentStart

        case .startWorkout, .abandonWorkout:
            return true
        }
    }

    private func sortByCreatedAt(lhs: SyncOperation, rhs: SyncOperation) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func describe(error: APIError) -> String {
        switch error {
        case .offline:
            return "Offline"
        case .timeout:
            return "Timeout"
        case .cancelled:
            return "Cancelled"
        case .invalidURL:
            return "Invalid URL"
        case let .transportError(urlError):
            return "Transport error: \(urlError.code.rawValue)"
        case let .httpError(statusCode, snippet):
            return "HTTP \(statusCode) \(snippet ?? "")"
        case .decodingError:
            return "Decoding error"
        case .unauthorized:
            return "Unauthorized"
        case .forbidden:
            return "Forbidden"
        case let .serverError(statusCode, snippet):
            return "Server \(statusCode) \(snippet ?? "")"
        case .unknown:
            return "Unknown"
        }
    }
}
