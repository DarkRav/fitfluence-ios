@testable import FitfluenceApp
import XCTest

@MainActor
final class WorkoutsFeatureAndProgressStoreTests: XCTestCase {
    func testWorkoutsListViewModelSuccessLoadsItemsAndStatuses() async {
        let workouts = [
            WorkoutSummary(id: "w1", title: "День 1", dayOrder: 1, exerciseCount: 3, estimatedDurationMinutes: 35),
            WorkoutSummary(id: "w2", title: "День 2", dayOrder: 2, exerciseCount: 4, estimatedDurationMinutes: 42),
        ]

        let workoutsClient = MockWorkoutsClient(
            listResults: [.success(workouts)],
            detailsResults: [],
        )
        let progressStore = MockWorkoutProgressStore(
            statuses: ["w1": .inProgress, "w2": .completed],
        )

        let viewModel = WorkoutsListViewModel(
            programId: "p1",
            userSub: "u1",
            workoutsClient: workoutsClient,
            progressStore: progressStore,
            cacheStore: MemoryCacheStore(),
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.workouts, workouts)
        XCTAssertEqual(viewModel.workoutStatuses["w1"], .inProgress)
        XCTAssertEqual(viewModel.workoutStatuses["w2"], .completed)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testWorkoutsListViewModelOfflineWithoutCacheShowsError() async {
        let workoutsClient = MockWorkoutsClient(
            listResults: [.failure(.offline)],
            detailsResults: [],
        )

        let viewModel = WorkoutsListViewModel(
            programId: "p1",
            userSub: "u1",
            workoutsClient: workoutsClient,
            progressStore: MockWorkoutProgressStore(statuses: [:]),
            cacheStore: MemoryCacheStore(),
        )

        await viewModel.onAppear()

        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(viewModel.error?.kind, .offline)
        XCTAssertTrue(viewModel.workouts.isEmpty)
    }

    func testWorkoutsListViewModelOfflineWithCacheShowsCachedData() async {
        let workouts = [
            WorkoutSummary(id: "w1", title: "День 1", dayOrder: 1, exerciseCount: 3, estimatedDurationMinutes: 35),
        ]
        let cacheStore = MemoryCacheStore()
        await cacheStore.set("workouts.list:p1", value: workouts, namespace: "u1", ttl: 1800)

        let workoutsClient = MockWorkoutsClient(
            listResults: [.failure(.offline)],
            detailsResults: [],
        )

        let viewModel = WorkoutsListViewModel(
            programId: "p1",
            userSub: "u1",
            workoutsClient: workoutsClient,
            progressStore: MockWorkoutProgressStore(statuses: ["w1": .inProgress]),
            cacheStore: cacheStore,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.workouts.count, 1)
        XCTAssertEqual(viewModel.workouts.first?.id, "w1")
        XCTAssertTrue(viewModel.isShowingCachedData)
        XCTAssertNil(viewModel.error)
    }

    func testWorkoutPlayerViewModelToggleNumericAndUndo() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.toggleSetComplete(setIndex: 0)
        await viewModel.incrementReps(setIndex: 0)
        await viewModel.incrementWeight(setIndex: 0)

        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.isCompleted, true)
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.repsText, "1")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.weightText, "2.5")
        XCTAssertTrue(viewModel.restTimer.isVisible)

        await viewModel.undoLastChange()

        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.weightText, "")
        XCTAssertEqual(viewModel.toastMessage, "Последнее действие отменено")
    }

    func testWorkoutPlayerViewModelFinishProducesSummary() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.toggleSetComplete(setIndex: 0)
        await viewModel.finish()

        XCTAssertTrue(viewModel.isFinished)
        XCTAssertEqual(viewModel.completionSummary?.completedExercises, 1)
        XCTAssertEqual(viewModel.completionSummary?.totalExercises, 1)
        XCTAssertEqual(viewModel.completionSummary?.completedSets, 1)
        XCTAssertEqual(viewModel.completionSummary?.totalSets, 2)

        let snapshot = await progressStore.load(userSub: "u1", programId: "p1", workoutId: "w1")
        XCTAssertEqual(snapshot?.isFinished, true)
    }

    func testWorkoutPlayerViewModelCopyPreviousAndJump() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: WorkoutDetailsModel(
                id: "w2",
                title: "Тренировка B",
                dayOrder: 1,
                coachNote: nil,
                exercises: [
                    WorkoutExercise(
                        id: "ex-1",
                        name: "Присед",
                        sets: 2,
                        repsMin: 6,
                        repsMax: 8,
                        targetRpe: nil,
                        restSeconds: 90,
                        notes: nil,
                        orderIndex: 0,
                    ),
                    WorkoutExercise(
                        id: "ex-2",
                        name: "Жим",
                        sets: 2,
                        repsMin: 8,
                        repsMax: 10,
                        targetRpe: nil,
                        restSeconds: 90,
                        notes: nil,
                        orderIndex: 1,
                    ),
                ],
            ),
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.incrementReps(setIndex: 0)
        await viewModel.incrementReps(setIndex: 0)
        await viewModel.incrementWeight(setIndex: 0)
        await viewModel.copyPreviousSet(setIndex: 1)

        XCTAssertEqual(viewModel.currentExerciseState?.sets[1].repsText, "2")
        XCTAssertEqual(viewModel.currentExerciseState?.sets[1].weightText, "2.5")

        await viewModel.jumpToExercise("ex-2")
        XCTAssertEqual(viewModel.currentExercise?.id, "ex-2")
    }

    func testLocalProgressStoreSaveAndLoad() async throws {
        let suiteName = "fitfluence.tests.progress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalWorkoutProgressStore(defaults: defaults)
        let snapshot = WorkoutProgressSnapshot(
            userSub: "u1",
            programId: "p1",
            workoutId: "w1",
            currentExerciseIndex: 0,
            isFinished: false,
            lastUpdated: Date(),
            exercises: [
                "ex-1": StoredExerciseProgress(sets: [
                    StoredSetProgress(isCompleted: true, repsText: "10", weightText: "40", rpeText: "8"),
                ]),
            ],
        )

        await store.save(snapshot)
        let loaded = await store.load(userSub: "u1", programId: "p1", workoutId: "w1")
        let status = await store.status(userSub: "u1", programId: "p1", workoutId: "w1")

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(status, .inProgress)
    }

    func testLatestActiveSessionPrefersInProgressOverNewerNotStarted() async throws {
        let suiteName = "fitfluence.tests.progress.latest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalWorkoutProgressStore(defaults: defaults)
        let inProgress = WorkoutProgressSnapshot(
            userSub: "u1",
            programId: "p1",
            workoutId: "w1",
            currentExerciseIndex: 2,
            isFinished: false,
            lastUpdated: Date().addingTimeInterval(-60),
            exercises: [
                "ex-1": StoredExerciseProgress(sets: [
                    StoredSetProgress(isCompleted: true, repsText: "", weightText: "", rpeText: ""),
                ]),
            ],
        )
        let notStarted = WorkoutProgressSnapshot(
            userSub: "u1",
            programId: "p1",
            workoutId: "w2",
            currentExerciseIndex: 0,
            isFinished: false,
            lastUpdated: Date(),
            exercises: [
                "ex-2": StoredExerciseProgress(sets: [
                    StoredSetProgress(isCompleted: false, repsText: "", weightText: "", rpeText: ""),
                ]),
            ],
        )

        await store.save(inProgress)
        await store.save(notStarted)

        let latest = await store.latestActiveSession(userSub: "u1")
        XCTAssertEqual(latest?.workoutId, "w1")
        XCTAssertEqual(latest?.status, .inProgress)
    }

    private var sampleWorkoutDetails: WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: "w1",
            title: "Тренировка A",
            dayOrder: 1,
            coachNote: nil,
            exercises: [
                WorkoutExercise(
                    id: "ex-1",
                    name: "Присед",
                    sets: 2,
                    repsMin: 8,
                    repsMax: 10,
                    targetRpe: 8,
                    restSeconds: 90,
                    notes: nil,
                    orderIndex: 0,
                ),
            ],
        )
    }
}

private actor MockWorkoutsClient: WorkoutsClientProtocol {
    private var listResults: [Result<[WorkoutSummary], APIError>]
    private var detailsResults: [Result<WorkoutDetailsModel, APIError>]

    let progressStorageMode: WorkoutProgressStorageMode

    init(
        listResults: [Result<[WorkoutSummary], APIError>],
        detailsResults: [Result<WorkoutDetailsModel, APIError>],
        progressStorageMode: WorkoutProgressStorageMode = .localOnly,
    ) {
        self.listResults = listResults
        self.detailsResults = detailsResults
        self.progressStorageMode = progressStorageMode
    }

    func listWorkouts(for _: String) async -> Result<[WorkoutSummary], APIError> {
        guard !listResults.isEmpty else { return .failure(.unknown) }
        return listResults.removeFirst()
    }

    func getWorkoutDetails(programId _: String, workoutId _: String) async -> Result<WorkoutDetailsModel, APIError> {
        guard !detailsResults.isEmpty else { return .failure(.unknown) }
        return detailsResults.removeFirst()
    }
}

private actor MockWorkoutProgressStore: WorkoutProgressStore {
    private let statusesValue: [String: WorkoutProgressStatus]
    private var snapshotValue: WorkoutProgressSnapshot?

    init(statuses: [String: WorkoutProgressStatus], snapshot: WorkoutProgressSnapshot? = nil) {
        statusesValue = statuses
        snapshotValue = snapshot
    }

    func load(userSub _: String, programId _: String, workoutId _: String) async -> WorkoutProgressSnapshot? {
        snapshotValue
    }

    func save(_ snapshot: WorkoutProgressSnapshot) async {
        snapshotValue = snapshot
    }

    func status(userSub _: String, programId _: String, workoutId: String) async -> WorkoutProgressStatus {
        statusesValue[workoutId] ?? .notStarted
    }

    func statuses(
        userSub _: String,
        programId _: String,
        workoutIds: [String],
    ) async -> [String: WorkoutProgressStatus] {
        Dictionary(uniqueKeysWithValues: workoutIds.map { ($0, statusesValue[$0] ?? .notStarted) })
    }

    func latestActiveSession(userSub _: String) async -> ActiveWorkoutSession? {
        guard let snapshot = snapshotValue else { return nil }
        return ActiveWorkoutSession(
            userSub: snapshot.userSub,
            programId: snapshot.programId,
            workoutId: snapshot.workoutId,
            source: snapshot.source ?? .program,
            status: snapshot.status,
            currentExerciseIndex: snapshot.currentExerciseIndex,
            lastUpdated: snapshot.lastUpdated,
        )
    }
}
