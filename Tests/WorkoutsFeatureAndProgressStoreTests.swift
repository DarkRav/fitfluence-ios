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
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.repsText, "9")
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

        XCTAssertEqual(viewModel.currentExerciseState?.sets[1].repsText, "8")
        XCTAssertEqual(viewModel.currentExerciseState?.sets[1].weightText, "2.5")

        await viewModel.jumpToExercise("ex-2")
        XCTAssertEqual(viewModel.currentExercise?.id, "ex-2")
    }

    func testWorkoutPlayerViewModelAppliesSmartDefaultsFromPlan() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.repsText, "8")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.weightText, "")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.rpeText, "8")
    }

    func testWorkoutPlayerViewModelAutoAdvanceAndUndoSnackbar() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let workout = WorkoutDetailsModel(
            id: "w-auto",
            title: "Auto",
            dayOrder: 1,
            coachNote: nil,
            exercises: [
                WorkoutExercise(
                    id: "ex-1",
                    name: "Squat",
                    sets: 1,
                    repsMin: 5,
                    repsMax: 5,
                    targetRpe: nil,
                    restSeconds: 90,
                    notes: nil,
                    orderIndex: 0,
                ),
                WorkoutExercise(
                    id: "ex-2",
                    name: "Bench",
                    sets: 1,
                    repsMin: 5,
                    repsMax: 5,
                    targetRpe: nil,
                    restSeconds: 90,
                    notes: nil,
                    orderIndex: 1,
                ),
            ],
        )

        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: workout,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        XCTAssertEqual(viewModel.currentExercise?.id, "ex-1")

        await viewModel.toggleSetComplete(setIndex: 0)

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-2")
        XCTAssertNotNil(viewModel.autoAdvanceUndoState)

        await viewModel.undoAutoAdvance()
        XCTAssertEqual(viewModel.currentExercise?.id, "ex-1")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.isCompleted, false)
    }

    func testWorkoutInstanceRouteStateMapping() {
        XCTAssertEqual(resolveWorkoutInstanceRouteState(.planned), .requiresStart)
        XCTAssertEqual(resolveWorkoutInstanceRouteState(.inProgress), .resume)
        XCTAssertEqual(resolveWorkoutInstanceRouteState(.completed), .completed)
        XCTAssertEqual(resolveWorkoutInstanceRouteState(.abandoned), .abandoned)
        XCTAssertEqual(resolveWorkoutInstanceRouteState(nil), .resume)
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

    func testWorkoutLifecycleTransitionsInvariant() {
        XCTAssertTrue(WorkoutDomainRules.canTransition(from: .draft, to: .inProgress))
        XCTAssertTrue(WorkoutDomainRules.canTransition(from: .draft, to: .completed))
        XCTAssertTrue(WorkoutDomainRules.canTransition(from: .inProgress, to: .completed))
        XCTAssertTrue(WorkoutDomainRules.canTransition(from: .inProgress, to: .cancelled))
        XCTAssertTrue(WorkoutDomainRules.canTransition(from: .draft, to: .draft))

        XCTAssertFalse(WorkoutDomainRules.canTransition(from: .completed, to: .inProgress))
        XCTAssertFalse(WorkoutDomainRules.canTransition(from: .cancelled, to: .inProgress))
    }

    func testWorkoutProgressStatusResolutionInvariant() {
        let empty = WorkoutDomainRules.progressStatus(isFinished: false, exercises: [:])
        XCTAssertEqual(empty, .notStarted)

        let inProgress = WorkoutDomainRules.progressStatus(
            isFinished: false,
            exercises: [
                "e1": StoredExerciseProgress(sets: [
                    StoredSetProgress(isCompleted: false, repsText: "8", weightText: "", rpeText: ""),
                ]),
            ],
        )
        XCTAssertEqual(inProgress, .inProgress)

        let completed = WorkoutDomainRules.progressStatus(
            isFinished: true,
            exercises: [:],
        )
        XCTAssertEqual(completed, .completed)
    }

    func testActiveEnrollmentResolutionPrefersCurrentInProgressInvariant() {
        let progress = ActiveEnrollmentProgressResponse(
            enrollmentId: "enr-1",
            status: "ACTIVE",
            programId: "program-1",
            programTitle: "Сила 8 недель",
            programVersionId: "version-1",
            currentWorkoutId: "workout-current",
            currentWorkoutTitle: "День 3",
            currentWorkoutStatus: .inProgress,
            nextWorkoutId: "workout-next",
            nextWorkoutTitle: "День 4",
            nextWorkoutStatus: .planned,
            completedSessions: 2,
            totalSessions: 8,
            completionPercent: 25,
            lastCompletedAt: nil,
            updatedAt: nil,
        )

        let resolved = WorkoutDomainRules.resolveActiveEnrollment(progress)
        XCTAssertEqual(resolved?.programId, "program-1")
        XCTAssertEqual(resolved?.programTitle, "Сила 8 недель")
        XCTAssertEqual(resolved?.resumeWorkout?.workoutId, "workout-current")
        XCTAssertEqual(resolved?.resumeWorkout?.title, "День 3")
        XCTAssertEqual(resolved?.nextWorkoutToStart?.workoutId, "workout-next")
        XCTAssertEqual(resolved?.preferredLaunchWorkout?.workoutId, "workout-current")
        XCTAssertEqual(resolved?.completedSessions, 2)
        XCTAssertEqual(resolved?.totalSessions, 8)
    }

    func testActiveEnrollmentResolutionBuildsStartTargetWithoutResumeInvariant() {
        let progress = ActiveEnrollmentProgressResponse(
            enrollmentId: "enr-2",
            status: "ACTIVE",
            programId: "program-2",
            programTitle: nil,
            programVersionId: nil,
            currentWorkoutId: nil,
            currentWorkoutTitle: nil,
            currentWorkoutStatus: nil,
            nextWorkoutId: "workout-next",
            nextWorkoutTitle: nil,
            nextWorkoutStatus: .planned,
            completedSessions: 5,
            totalSessions: 0,
            completionPercent: nil,
            lastCompletedAt: nil,
            updatedAt: nil,
        )

        let resolved = WorkoutDomainRules.resolveActiveEnrollment(progress)
        XCTAssertEqual(resolved?.programId, "program-2")
        XCTAssertEqual(resolved?.programTitle, "Активная программа")
        XCTAssertNil(resolved?.resumeWorkout)
        XCTAssertEqual(resolved?.nextWorkoutToStart?.workoutId, "workout-next")
        XCTAssertEqual(resolved?.nextWorkoutToStart?.title, "Следующая тренировка")
        XCTAssertEqual(resolved?.completedSessions, 5)
        XCTAssertEqual(resolved?.totalSessions, 5)
        XCTAssertEqual(resolved?.totalSessionsForProgress, 5)
    }

    func testResolveNextWorkoutInvariant() {
        let workouts = [
            WorkoutSummary(id: "w1", title: "День 1", dayOrder: 1, exerciseCount: 4, estimatedDurationMinutes: 35),
            WorkoutSummary(id: "w2", title: "День 2", dayOrder: 2, exerciseCount: 5, estimatedDurationMinutes: 40),
            WorkoutSummary(id: "w3", title: "День 3", dayOrder: 3, exerciseCount: 6, estimatedDurationMinutes: 45),
        ]
        let statuses: [String: WorkoutProgressStatus] = [
            "w1": .completed,
            "w2": .notStarted,
            "w3": .completed,
        ]

        let firstPick = WorkoutDomainRules.resolveNextWorkout(
            workouts: workouts,
            statuses: statuses,
            activeSessionWorkoutId: nil,
        )
        XCTAssertEqual(firstPick?.id, "w2")

        let resumedPick = WorkoutDomainRules.resolveNextWorkout(
            workouts: workouts,
            statuses: statuses,
            activeSessionWorkoutId: "w3",
        )
        XCTAssertEqual(resumedPick?.id, "w3")
    }

    func testUserFacingUILiteralsAreRussianOnly() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = projectRoot.appendingPathComponent("App")
        let files = try swiftFiles(at: appRoot)
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let literals = extractUILiterals(from: source)
            for literal in literals {
                let normalized = sanitizeUILiteral(literal)
                guard !normalized.isEmpty else { continue }
                if normalized.range(of: "[A-Za-z]", options: .regularExpression) != nil {
                    violations.append("\(fileURL.path): \"\(literal)\"")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Найдены пользовательские строки с латиницей:\n\(violations.joined(separator: "\n"))",
        )
    }

    private func swiftFiles(at root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )

        var result: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            if file.pathExtension == "swift" {
                result.append(file)
            }
        }
        return result
    }

    private func extractUILiterals(from source: String) -> [String] {
        let patterns = [
            #"Text\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#,
            #"Button\(\s*"((?:[^"\\]|\\.)*)"\s*(?:,|\))"#,
            #"FFButton\(\s*title:\s*"((?:[^"\\]|\\.)*)""#,
            #"navigationTitle\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#,
            #"alert\(\s*"((?:[^"\\]|\\.)*)"\s*,"#,
            #"accessibility(?:Label|Hint)\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#,
            #"FFTextField\(\s*label:\s*"((?:[^"\\]|\\.)*)""#,
            #"FFTextField\(\s*label:\s*"(?:[^"\\]|\\.)*"\s*,\s*placeholder:\s*"((?:[^"\\]|\\.)*)""#,
            #"FF(?:EmptyState|ErrorState|LoadingState)\(\s*title:\s*"((?:[^"\\]|\\.)*)""#,
            #"FF(?:EmptyState|ErrorState)\(\s*title:\s*"(?:[^"\\]|\\.)*"\s*,\s*message:\s*"((?:[^"\\]|\\.)*)""#,
        ]

        return patterns.flatMap { pattern in
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators],
            ) else {
                return [String]()
            }
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            return matches.compactMap { match in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: source)
                else {
                    return nil
                }
                return String(source[range])
            }
        }
    }

    private func sanitizeUILiteral(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: #"\\\([^"]*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?:https?|mailto):\S+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"/v\d+/[^\s`]+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\n|\\t|\\r"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
