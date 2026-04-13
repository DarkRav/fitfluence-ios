import Foundation
import XCTest
@testable import FitfluenceApp

final class SyncEngineTests: XCTestCase {
    func testOutboxDedupeKeepsSingleUpsertAndResetsRetryState() async throws {
        let store = SyncOutboxStore(baseURL: temporaryDirectory())
        let namespace = "athlete-1"

        let first = await store.enqueue(
            .upsertSet(
                workoutInstanceId: "w1",
                exerciseExecutionId: "exec-1",
                setNumber: 1,
                weight: 60,
                reps: 8,
                rpe: 8,
                isCompleted: true,
                isWarmup: false,
                restSecondsActual: nil,
            ),
            namespace: namespace,
        )
        guard let firstOperation = first.operation else {
            return XCTFail("Expected operation to be enqueued")
        }

        await store.markRetryableError(
            operationId: firstOperation.id,
            namespace: namespace,
            error: "Offline",
            nextRetryAt: Date().addingTimeInterval(120),
            retryCount: 3,
        )

        _ = await store.enqueue(
            .upsertSet(
                workoutInstanceId: "w1",
                exerciseExecutionId: "exec-1",
                setNumber: 1,
                weight: 62.5,
                reps: 10,
                rpe: 9,
                isCompleted: true,
                isWarmup: false,
                restSecondsActual: nil,
            ),
            namespace: namespace,
        )

        let operations = await store.allOperations(namespace: namespace)
        let unsent = operations.filter { $0.status.isUnsent }
        XCTAssertEqual(unsent.count, 1)

        let operation = try XCTUnwrap(unsent.first)
        XCTAssertEqual(operation.payload.weight, 62.5)
        XCTAssertEqual(operation.payload.reps, 10)
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertEqual(operation.status, .pending)
        XCTAssertNil(operation.nextRetryAt)
    }

    func testOutboxConflictRulesAbandonDiscardsCompleteForWorkout() async {
        let store = SyncOutboxStore(baseURL: temporaryDirectory())
        let namespace = "athlete-2"

        _ = await store.enqueue(
            .completeWorkout(workoutInstanceId: "w2", completedAt: Date()),
            namespace: namespace,
        )
        _ = await store.enqueue(
            .abandonWorkout(workoutInstanceId: "w2", abandonedAt: Date()),
            namespace: namespace,
        )

        let operations = await store.allOperations(namespace: namespace)
        let complete = operations.first(where: { $0.type == .completeWorkout })
        let abandon = operations.first(where: { $0.type == .abandonWorkout })

        XCTAssertEqual(complete?.status, .dead)
        XCTAssertEqual(abandon?.status, .pending)
    }

    func testBackoffSchedule() {
        let worker = SyncWorker(outboxStore: SyncOutboxStore(baseURL: temporaryDirectory()))

        XCTAssertEqual(worker.backoffDelay(forRetryCount: 1), 2, accuracy: 0.001)
        XCTAssertEqual(worker.backoffDelay(forRetryCount: 2), 5, accuracy: 0.001)
        XCTAssertEqual(worker.backoffDelay(forRetryCount: 3), 15, accuracy: 0.001)
        XCTAssertEqual(worker.backoffDelay(forRetryCount: 4), 30, accuracy: 0.001)
        XCTAssertEqual(worker.backoffDelay(forRetryCount: 5), 60, accuracy: 0.001)
        XCTAssertEqual(worker.backoffDelay(forRetryCount: 12), 300, accuracy: 0.001)
    }

    func testOrderingDependenciesStartBeforeSetsAndCompleteAfterSets() async throws {
        let store = SyncOutboxStore(baseURL: temporaryDirectory())
        let worker = SyncWorker(outboxStore: store)
        let client = MockAthleteTrainingClient()
        let namespace = "athlete-3"

        _ = await store.enqueue(.startWorkout(workoutInstanceId: "w3", startedAt: Date()), namespace: namespace)
        _ = await store.enqueue(
            .upsertSet(
                workoutInstanceId: "w3",
                exerciseExecutionId: "exec-3",
                setNumber: 1,
                weight: 100,
                reps: 5,
                rpe: 8,
                isCompleted: true,
                isWarmup: false,
                restSecondsActual: nil,
            ),
            namespace: namespace,
        )
        _ = await store.enqueue(.completeWorkout(workoutInstanceId: "w3", completedAt: Date()), namespace: namespace)

        await worker.process(namespace: namespace, athleteTrainingClient: client, isOnline: true)

        let calls = await client.calls
        XCTAssertEqual(calls, [
            "START_WORKOUT:w3",
            "UPSERT_SET:exec-3:1",
            "COMPLETE_WORKOUT:w3",
        ])
    }

    func testStateTransitionsPendingToSentErrorAndDead() async throws {
        do {
            let namespace = "athlete-sent"
            let store = SyncOutboxStore(baseURL: temporaryDirectory())
            let localWorker = SyncWorker(outboxStore: store)
            let client = MockAthleteTrainingClient()

            _ = await store.enqueue(.startWorkout(workoutInstanceId: "w-sent", startedAt: Date()), namespace: namespace)
            await localWorker.process(namespace: namespace, athleteTrainingClient: client, isOnline: true)

            let op = await store.allOperations(namespace: namespace).first
            XCTAssertEqual(op?.status, .sent)
        }

        do {
            let namespace = "athlete-error"
            let store = SyncOutboxStore(baseURL: temporaryDirectory())
            let localWorker = SyncWorker(outboxStore: store)
            let client = MockAthleteTrainingClient()
            await client.setSetResult(.failure(.offline))

            _ = await store.enqueue(
                .upsertSet(
                    workoutInstanceId: "w-error",
                    exerciseExecutionId: "exec-error",
                    setNumber: 1,
                    weight: 50,
                    reps: 8,
                    rpe: 7,
                    isCompleted: false,
                    isWarmup: false,
                    restSecondsActual: nil,
                ),
                namespace: namespace,
            )

            await localWorker.process(namespace: namespace, athleteTrainingClient: client, isOnline: true)

            let op = await store.allOperations(namespace: namespace).first
            XCTAssertEqual(op?.status, .error)
            XCTAssertEqual(op?.retryCount, 1)
            XCTAssertNotNil(op?.nextRetryAt)
        }

        do {
            let namespace = "athlete-dead"
            let store = SyncOutboxStore(baseURL: temporaryDirectory())
            let localWorker = SyncWorker(outboxStore: store)
            let client = MockAthleteTrainingClient()
            await client.setCompleteResult(.failure(.httpError(statusCode: 422, bodySnippet: "validation")))

            _ = await store.enqueue(.completeWorkout(workoutInstanceId: "w-dead", completedAt: Date()), namespace: namespace)
            await localWorker.process(namespace: namespace, athleteTrainingClient: client, isOnline: true)

            let op = await store.allOperations(namespace: namespace).first
            XCTAssertEqual(op?.status, .dead)
        }
    }

    func testStartWorkoutTerminalConflictMovesOperationToDead() async {
        let namespace = "athlete-start-conflict"
        let store = SyncOutboxStore(baseURL: temporaryDirectory())
        let localWorker = SyncWorker(outboxStore: store)
        let client = MockAthleteTrainingClient()
        await client.setStartResult(
            .failure(
                .httpError(
                    statusCode: 409,
                    bodySnippet: #"{"message":"RESOURCE_CONFLICT: Workout уже прервана"}"#,
                ),
            ),
        )

        _ = await store.enqueue(.startWorkout(workoutInstanceId: "w-conflict", startedAt: Date()), namespace: namespace)
        await localWorker.process(namespace: namespace, athleteTrainingClient: client, isOnline: true)

        let op = await store.allOperations(namespace: namespace).first
        XCTAssertEqual(op?.status, .dead)
    }

    func testCreateCustomWorkoutOperationMaterializesPendingPlan() async throws {
        let namespace = "athlete-pending-create"
        let outboxStore = SyncOutboxStore(baseURL: temporaryDirectory())
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "fitfluence.tests.sync.pending-create.\(UUID().uuidString)"))
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: Date())
        let trainingStore = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let reconciler = PendingCustomWorkoutReconciler(
            trainingStore: trainingStore,
            cacheStore: MemoryCacheStore(),
        )
        let worker = SyncWorker(
            outboxStore: outboxStore,
            pendingCustomWorkoutReconciler: reconciler,
        )
        let client = MockAthleteTrainingClient()
        let localWorkout = makeWorkout(id: "quick-repeat-local", title: "Повтор")
        let remoteWorkoutID = "77777777-7777-7777-7777-777777777777"

        await client.setCreateResult(.success(makeWorkoutDetailsResponse(
            workoutID: remoteWorkoutID,
            title: "Повтор",
            source: .custom,
            scheduledDate: scheduledDateTimeString(targetDay),
        )))
        await trainingStore.schedule(
            TrainingDayPlan(
                id: "pending-custom-plan",
                userSub: namespace,
                day: targetDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: localWorkout.id,
                title: localWorkout.title,
                source: .freestyle,
                workoutDetails: localWorkout,
                pendingSyncState: .createCustomWorkout,
            )
        )
        _ = await outboxStore.enqueue(
            .createCustomWorkout(
                planId: "pending-custom-plan",
                source: .freestyle,
                workout: localWorkout,
                scheduledDay: targetDay,
            ),
            namespace: namespace,
        )

        await worker.process(namespace: namespace, athleteTrainingClient: client, isOnline: true)

        let plans = await trainingStore.plans(userSub: namespace, month: targetDay)
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.id, "remote-\(remoteWorkoutID)")
        XCTAssertEqual(plan.workoutId, remoteWorkoutID)
        XCTAssertFalse(plan.isPendingCustomWorkoutCreation)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fitfluence-sync-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeWorkout(id: String, title: String) -> WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: id,
            title: title,
            dayOrder: 0,
            coachNote: "Повтор",
            exercises: [
                WorkoutExercise(
                    id: "ex-1",
                    name: "Жим лёжа",
                    sets: 4,
                    repsMin: 6,
                    repsMax: 8,
                    targetRpe: 8,
                    restSeconds: 120,
                    notes: "Тяжёлый сет",
                    orderIndex: 0,
                ),
            ],
        )
    }

    private func makeWorkoutDetailsResponse(
        workoutID: String,
        title: String,
        source: AthleteWorkoutSource,
        scheduledDate: String?,
    ) -> AthleteWorkoutDetailsResponse {
        AthleteWorkoutDetailsResponse(
            workout: AthleteWorkoutInstance(
                id: workoutID,
                enrollmentId: nil,
                workoutTemplateId: nil,
                title: title,
                status: .planned,
                source: source,
                scheduledDate: scheduledDate,
                startedAt: nil,
                completedAt: nil,
                durationSeconds: nil,
                notes: "Повтор",
                programId: nil,
            ),
            exercises: [
                AthleteExerciseExecution(
                    id: "execution-1",
                    workoutInstanceId: workoutID,
                    exerciseTemplateId: nil,
                    workoutPlanId: nil,
                    exerciseId: "ex-1",
                    orderIndex: 0,
                    notes: nil,
                    plannedSets: 4,
                    plannedRepsMin: 6,
                    plannedRepsMax: 8,
                    plannedTargetRpe: 8,
                    plannedRestSeconds: 120,
                    plannedNotes: "Тяжёлый сет",
                    progressionPolicyId: nil,
                    exercise: AthleteExerciseBrief(
                        id: "ex-1",
                        code: nil,
                        name: "Жим лёжа",
                        description: nil,
                        isBodyweight: false,
                        equipment: nil,
                        media: nil,
                    ),
                    sets: nil,
                ),
            ],
        )
    }
}

private actor MockAthleteTrainingClient: AthleteTrainingClientProtocol {
    var calls: [String] = []
    var createResult: Result<AthleteWorkoutDetailsResponse, APIError> = .failure(.unknown)

    var startResult: Result<AthleteWorkoutInstance, APIError> = .success(
        AthleteWorkoutInstance(
            id: "w",
            enrollmentId: nil,
            workoutTemplateId: nil,
            title: "Workout",
            status: .inProgress,
            source: .program,
            scheduledDate: nil,
            startedAt: nil,
            completedAt: nil,
            durationSeconds: nil,
            notes: nil,
            programId: nil,
        ),
    )

    var completeResult: Result<AthleteWorkoutInstance, APIError> = .success(
        AthleteWorkoutInstance(
            id: "w",
            enrollmentId: nil,
            workoutTemplateId: nil,
            title: "Workout",
            status: .completed,
            source: .program,
            scheduledDate: nil,
            startedAt: nil,
            completedAt: nil,
            durationSeconds: nil,
            notes: nil,
            programId: nil,
        ),
    )

    var abandonResult: Result<AthleteWorkoutInstance, APIError> = .success(
        AthleteWorkoutInstance(
            id: "w",
            enrollmentId: nil,
            workoutTemplateId: nil,
            title: "Workout",
            status: .abandoned,
            source: .program,
            scheduledDate: nil,
            startedAt: nil,
            completedAt: nil,
            durationSeconds: nil,
            notes: nil,
            programId: nil,
        ),
    )

    var setResult: Result<AthleteSetExecution, APIError> = .success(
        AthleteSetExecution(
            id: "set",
            setNumber: 1,
            weight: 50,
            reps: 8,
            rpe: 8,
            isCompleted: true,
            isWarmup: false,
            restSecondsActual: nil,
        ),
    )

    func setCompleteResult(_ result: Result<AthleteWorkoutInstance, APIError>) {
        completeResult = result
    }

    func setStartResult(_ result: Result<AthleteWorkoutInstance, APIError>) {
        startResult = result
    }

    func setSetResult(_ result: Result<AthleteSetExecution, APIError>) {
        setResult = result
    }

    func setCreateResult(_ result: Result<AthleteWorkoutDetailsResponse, APIError>) {
        createResult = result
    }

    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError> {
        .failure(.unknown)
    }

    func getWorkoutDetails(workoutInstanceId _: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func createCustomWorkout(
        request _: AthleteCreateCustomWorkoutRequest,
        idempotencyKey _: String?,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        calls.append("CREATE_CUSTOM_WORKOUT")
        return createResult
    }

    func updateCustomWorkout(
        workoutInstanceId _: String,
        request _: AthleteUpdateCustomWorkoutRequest,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func startWorkout(workoutInstanceId: String, startedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        calls.append("START_WORKOUT:\(workoutInstanceId)")
        return startResult
    }

    func completeWorkout(workoutInstanceId: String, completedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        calls.append("COMPLETE_WORKOUT:\(workoutInstanceId)")
        return completeResult
    }

    func abandonWorkout(workoutInstanceId: String, abandonedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        calls.append("ABANDON_WORKOUT:\(workoutInstanceId)")
        return abandonResult
    }

    func updateExerciseSet(
        exerciseExecutionId: String,
        setNumber: Int,
        weight _: Double?,
        reps _: Int?,
        rpe _: Int?,
        isCompleted _: Bool?,
        isWarmup _: Bool?,
        restSecondsActual _: Int?,
    ) async -> Result<AthleteSetExecution, APIError> {
        calls.append("UPSERT_SET:\(exerciseExecutionId):\(setNumber)")
        return setResult
    }
}
