import ComposableArchitecture
@testable import FitfluenceApp
import XCTest

@MainActor
final class WorkoutsFeatureAndProgressStoreTests: XCTestCase {
    func testWorkoutsListSuccessLoadsItemsAndStatuses() async {
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

        let store = TestStore(
            initialState: WorkoutsListFeature.State(programId: "p1", userSub: "u1"),
        ) {
            WorkoutsListFeature(
                workoutsClient: workoutsClient,
                progressStore: progressStore,
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
        }

        await store.receive(.cachedResponse(nil))

        await store.receive(.response(.success(workouts))) {
            $0.isLoading = false
            $0.isRefreshing = false
            $0.workouts = workouts
            $0.error = nil
            $0.isShowingCachedData = false
        }

        await store.receive(.statusesLoaded(["w1": .inProgress, "w2": .completed])) {
            $0.workoutStatuses = ["w1": .inProgress, "w2": .completed]
        }
    }

    func testWorkoutsListErrorShowsError() async {
        let workoutsClient = MockWorkoutsClient(
            listResults: [.failure(.offline)],
            detailsResults: [],
        )

        let store = TestStore(
            initialState: WorkoutsListFeature.State(programId: "p1", userSub: "u1"),
        ) {
            WorkoutsListFeature(
                workoutsClient: workoutsClient,
                progressStore: MockWorkoutProgressStore(statuses: [:]),
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
        }

        await store.receive(.cachedResponse(nil))

        await store.receive(.response(.failure(.offline))) {
            $0.isLoading = false
            $0.isRefreshing = false
            $0.error = UserFacingError(
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
        }
    }

    func testWorkoutPlayerLoadsDetailsAndSupportsSetToggle() async {
        let workoutsClient = MockWorkoutsClient(
            listResults: [],
            detailsResults: [.success(sampleWorkoutDetails)],
        )

        let store = TestStore(
            initialState: WorkoutPlayerFeature.State(
                userSub: "u1",
                programId: "p1",
                workoutId: "w1",
            ),
        ) {
            WorkoutPlayerFeature(
                workoutsClient: workoutsClient,
                progressStore: MockWorkoutProgressStore(statuses: [:]),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
            $0.progressStorageMode = .localOnly
        }

        await store.receive(.cachedDetailsResponse(nil))

        await store.receive(.detailsResponse(.success(sampleWorkoutDetails))) { [self] in
            $0.isLoading = false
            $0.workout = self.sampleWorkoutDetails
            $0.currentExerciseIndex = 0
            $0.perExerciseState = [
                "ex-1": WorkoutPlayerFeature.ExerciseProgress(
                    sets: [
                        WorkoutPlayerFeature.SetProgress(),
                        WorkoutPlayerFeature.SetProgress(),
                    ],
                ),
            ]
            $0.isShowingCachedData = false
            $0.error = nil
        }

        await store.receive(.loadedProgress(nil))

        await store.send(.toggleSetComplete(exerciseId: "ex-1", setIndex: 0)) {
            $0.perExerciseState["ex-1"]?.sets[0].isCompleted = true
        }
    }

    func testWorkoutPlayerFinishSendsCompletionDelegate() async {
        let workoutsClient = MockWorkoutsClient(
            listResults: [],
            detailsResults: [],
        )

        var state = WorkoutPlayerFeature.State(
            userSub: "u1",
            programId: "p1",
            workoutId: "w1",
        )
        state.workout = sampleWorkoutDetails
        state.perExerciseState = [
            "ex-1": WorkoutPlayerFeature.ExerciseProgress(
                sets: [
                    WorkoutPlayerFeature.SetProgress(isCompleted: true),
                    WorkoutPlayerFeature.SetProgress(isCompleted: true),
                ],
            ),
        ]

        let store = TestStore(initialState: state) {
            WorkoutPlayerFeature(
                workoutsClient: workoutsClient,
                progressStore: MockWorkoutProgressStore(statuses: [:]),
            )
        }

        await store.send(.finishWorkoutTapped) {
            $0.completionSummary = WorkoutPlayerFeature.CompletionSummary(
                completedExercises: 1,
                totalExercises: 1,
                completedSets: 2,
            )
        }

        await store.receive(
            .delegate(
                .workoutCompleted(
                    WorkoutPlayerFeature.CompletionSummary(
                        completedExercises: 1,
                        totalExercises: 1,
                        completedSets: 2,
                    ),
                ),
            ),
        )
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

    init(statuses: [String: WorkoutProgressStatus]) {
        statusesValue = statuses
    }

    func load(userSub _: String, programId _: String, workoutId _: String) async -> WorkoutProgressSnapshot? {
        nil
    }

    func save(_: WorkoutProgressSnapshot) async {}

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
}
