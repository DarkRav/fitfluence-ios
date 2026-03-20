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

    func testWorkoutSetInputFormattingNormalizesWeightInput() {
        XCTAssertEqual(WorkoutSetInputFormatting.normalizedWeightText(from: "42,5"), "42.5")
        XCTAssertEqual(WorkoutSetInputFormatting.normalizedWeightText(from: "100.00"), "100")
        XCTAssertEqual(WorkoutSetInputFormatting.normalizedWeightText(from: "17.25"), "17.25")
        XCTAssertNil(WorkoutSetInputFormatting.normalizedWeightText(from: "-5"))
    }

    func testWorkoutSetInputFormattingNormalizesRepsInput() {
        XCTAssertEqual(WorkoutSetInputFormatting.normalizedRepsText(from: "12"), "12")
        XCTAssertEqual(WorkoutSetInputFormatting.normalizedRepsText(from: "08"), "8")
        XCTAssertNil(WorkoutSetInputFormatting.normalizedRepsText(from: "8.5"))
        XCTAssertNil(WorkoutSetInputFormatting.normalizedRepsText(from: "abc"))
    }

    func testWorkoutPlayerViewModelDirectEditingPersistsWeightRepsAndRPE() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.updateWeight(setIndex: 0, input: "42,5")
        await viewModel.updateReps(setIndex: 0, input: "10")
        await viewModel.updateRPE(setIndex: 0, rpe: 9)

        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.weightText, "42.5")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.repsText, "10")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.rpeText, "9")

        let snapshot = await progressStore.load(userSub: "u1", programId: "p1", workoutId: "w1")
        XCTAssertEqual(snapshot?.exercises["ex-1"]?.sets.first?.weightText, "42.5")
        XCTAssertEqual(snapshot?.exercises["ex-1"]?.sets.first?.repsText, "10")
        XCTAssertEqual(snapshot?.exercises["ex-1"]?.sets.first?.rpeText, "9")
    }

    func testWorkoutPlayerViewModelRestoresDirectEditsAfterResume() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)

        let firstViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await firstViewModel.onAppear()
        await firstViewModel.updateWeight(setIndex: 0, input: "60")
        await firstViewModel.updateReps(setIndex: 0, input: "6")
        await firstViewModel.updateRPE(setIndex: 0, rpe: 8)

        let secondViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await secondViewModel.onAppear()

        XCTAssertEqual(secondViewModel.currentExerciseState?.sets.first?.weightText, "60")
        XCTAssertEqual(secondViewModel.currentExerciseState?.sets.first?.repsText, "6")
        XCTAssertEqual(secondViewModel.currentExerciseState?.sets.first?.rpeText, "8")
    }

    func testWorkoutPlayerViewModelPersistsSetStructureEditsAcrossResume() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)

        let firstViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await firstViewModel.onAppear()
        await firstViewModel.addSet(duplicateLast: false)
        await firstViewModel.toggleWarmup(setIndex: 2)
        await firstViewModel.removeSet(setIndex: 1)

        let snapshot = await progressStore.load(userSub: "u1", programId: "p1", workoutId: "w1")
        XCTAssertEqual(snapshot?.workoutDetails?.exercises.first?.sets, 2)
        XCTAssertEqual(snapshot?.exercises["ex-1"]?.sets.count, 2)
        XCTAssertEqual(snapshot?.exercises["ex-1"]?.sets.last?.isWarmup, true)
        XCTAssertEqual(snapshot?.hasLocalOnlyStructuralChanges, true)

        let secondViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await secondViewModel.onAppear()

        XCTAssertEqual(secondViewModel.currentExerciseState?.sets.count, 2)
        XCTAssertEqual(secondViewModel.currentExerciseState?.sets.last?.isWarmup, true)
        XCTAssertTrue(secondViewModel.showsLocalStructureNotice)
        XCTAssertEqual(secondViewModel.syncStatus, .savedLocally)
    }

    func testWorkoutPlayerViewModelWarmupToggleStaysServerSyncable() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)

        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.toggleWarmup(setIndex: 0)

        let snapshot = await progressStore.load(userSub: "u1", programId: "p1", workoutId: "w1")
        XCTAssertEqual(snapshot?.exercises["ex-1"]?.sets.first?.isWarmup, true)
        XCTAssertEqual(snapshot?.hasLocalOnlyStructuralChanges, false)
        XCTAssertFalse(viewModel.showsLocalStructureNotice)
    }

    func testWorkoutPlayerViewModelAddsExerciseDuringWorkoutAndRestoresIt() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)

        let firstViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await firstViewModel.onAppear()
        await firstViewModel.applyPickedExercise(
            sampleCatalogItem(
                id: "ex-extra",
                name: "Тяга блока",
                defaults: ExerciseCatalogDraftDefaults(
                    sets: 3,
                    repsMin: 10,
                    repsMax: 12,
                    restSeconds: 75,
                    targetRpe: 8,
                    notes: "Пауза в сведении",
                ),
            ),
            flow: .addAfterCurrent,
        )

        XCTAssertEqual(firstViewModel.progressItems.map(\.id), ["ex-1", "ex-extra"])
        XCTAssertEqual(firstViewModel.currentExercise?.id, "ex-extra")
        XCTAssertEqual(firstViewModel.currentExerciseState?.sets.count, 3)
        XCTAssertEqual(firstViewModel.currentExerciseState?.sets.first?.repsText, "10")
        XCTAssertEqual(firstViewModel.currentExerciseState?.sets.first?.rpeText, "8")

        let secondViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await secondViewModel.onAppear()

        XCTAssertEqual(secondViewModel.progressItems.map(\.id), ["ex-1", "ex-extra"])
        XCTAssertEqual(secondViewModel.currentExercise?.id, "ex-extra")
        XCTAssertEqual(secondViewModel.currentExerciseState?.sets.count, 3)
    }

    func testWorkoutHomeViewModelUsesHomeSummaryAsRemoteSourceOfTruth() async {
        let client = MockWorkoutHomeAthleteTrainingClient(
            homeSummaryResult: .success(
                AthleteHomeSummaryResponse(
                    generatedAt: "2026-03-19T09:20:00Z",
                    primaryAction: AthleteHomePrimaryAction(
                        type: .startTodaysWorkout,
                        title: "Начать тренировку на сегодня",
                        workout: AthleteHomeWorkoutSummary(
                            workoutInstanceId: "workout-1",
                            workoutTemplateId: nil,
                            enrollmentId: "enrollment-1",
                            programId: "program-1",
                            title: "Ноги A",
                            source: .program,
                            status: .planned,
                            scheduledDate: "2026-03-19",
                            startedAt: nil,
                            completedAt: nil,
                        ),
                        enrollmentId: "enrollment-1",
                        programId: "program-1",
                    ),
                    recentActivity: AthleteHomeRecentActivity(
                        lastCompletedWorkout: AthleteHomeRecentWorkoutSummary(
                            workoutInstanceId: "workout-0",
                            programId: "program-1",
                            title: "Верх A",
                            source: .program,
                            completedAt: "2026-03-18T09:20:00Z",
                            durationSeconds: 3000,
                        ),
                        recentWorkouts: [
                            AthleteHomeRecentWorkoutSummary(
                                workoutInstanceId: "workout-0",
                                programId: "program-1",
                                title: "Верх A",
                                source: .program,
                                completedAt: "2026-03-18T09:20:00Z",
                                durationSeconds: 3000,
                            ),
                        ],
                    ),
                    progressOverview: AthleteHomeProgressOverview(
                        streakDays: 4,
                        workouts7d: 3,
                        totalWorkouts: 12,
                        totalMinutes7d: 145,
                        lastWorkoutAt: "2026-03-18T09:20:00Z",
                    ),
                    activeWorkout: nil,
                    todayWorkout: AthleteHomeWorkoutSummary(
                        workoutInstanceId: "workout-1",
                        workoutTemplateId: nil,
                        enrollmentId: "enrollment-1",
                        programId: "program-1",
                        title: "Ноги A",
                        source: .program,
                        status: .planned,
                        scheduledDate: "2026-03-19",
                        startedAt: nil,
                        completedAt: nil,
                    ),
                    activeProgram: AthleteHomeProgramSummary(
                        enrollmentId: "enrollment-1",
                        programId: "program-1",
                        title: "Upper Lower",
                        completedWorkouts: 5,
                        totalWorkouts: 12,
                        summaryLine: "Сегодня: Ноги A",
                        completionPercent: 41.7,
                        lastCompletedAt: "2026-03-18T09:20:00Z",
                        resumeWorkout: nil,
                        todayWorkout: nil,
                        nextWorkout: AthleteHomeWorkoutSummary(
                            workoutInstanceId: "workout-1",
                            workoutTemplateId: nil,
                            enrollmentId: "enrollment-1",
                            programId: "program-1",
                            title: "Ноги A",
                            source: .program,
                            status: .planned,
                            scheduledDate: "2026-03-19",
                            startedAt: nil,
                            completedAt: nil,
                        ),
                    ),
                ),
            ),
            syncStatusResult: .success(
                AthleteSyncStatusResponse(
                    status: .synced,
                    hasPendingLocalChanges: false,
                    isDelayed: false,
                    pendingOperations: 0,
                    lastSyncedAt: "2026-03-19T09:20:00Z",
                ),
            ),
        )

        let viewModel = WorkoutHomeViewModel(
            userSub: "u1",
            trainingStore: LocalTrainingStore(),
            progressStore: MockWorkoutProgressStore(statuses: [:]),
            resumeStore: LocalWorkoutResumeStore(),
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            athleteTrainingClient: client,
            syncCoordinator: .shared,
        )

        await viewModel.reload()

        XCTAssertEqual(viewModel.todayWorkout?.title, "Ноги A")
        XCTAssertEqual(viewModel.programProgress?.title, "Upper Lower")
        XCTAssertEqual(viewModel.programProgress?.detailsLine, "Сегодня: Ноги A")
        XCTAssertEqual(viewModel.recentWorkouts.first?.workoutTitle, "Верх A")
        XCTAssertEqual(viewModel.startWorkoutTarget?.workoutId, "workout-1")
        XCTAssertEqual(viewModel.primaryActionKind, .startToday)
    }

    func testHomeViewModelUsesHomeSummaryAsPrimaryRemoteSourceOfTruth() async {
        let programId = "11111111-1111-1111-1111-111111111111"
        let client = MockWorkoutHomeAthleteTrainingClient(
            homeSummaryResult: .success(
                AthleteHomeSummaryResponse(
                    generatedAt: "2026-03-19T09:20:00Z",
                    primaryAction: AthleteHomePrimaryAction(
                        type: .continueActiveWorkout,
                        title: "Продолжить тренировку",
                        workout: AthleteHomeWorkoutSummary(
                            workoutInstanceId: "workout-remote",
                            workoutTemplateId: nil,
                            enrollmentId: "enrollment-1",
                            programId: programId,
                            title: "Ноги A",
                            source: .program,
                            status: .inProgress,
                            scheduledDate: "2026-03-19",
                            startedAt: "2026-03-19T09:00:00Z",
                            completedAt: nil,
                        ),
                        enrollmentId: "enrollment-1",
                        programId: "program-1",
                    ),
                    recentActivity: AthleteHomeRecentActivity(lastCompletedWorkout: nil, recentWorkouts: []),
                    progressOverview: AthleteHomeProgressOverview(
                        streakDays: 3,
                        workouts7d: 2,
                        totalWorkouts: 10,
                        totalMinutes7d: 90,
                        lastWorkoutAt: "2026-03-18T09:20:00Z",
                    ),
                    activeWorkout: AthleteHomeWorkoutSummary(
                        workoutInstanceId: "workout-remote",
                        workoutTemplateId: nil,
                        enrollmentId: "enrollment-1",
                        programId: programId,
                        title: "Ноги A",
                        source: .program,
                        status: .inProgress,
                        scheduledDate: "2026-03-19",
                        startedAt: "2026-03-19T09:00:00Z",
                        completedAt: nil,
                    ),
                    todayWorkout: AthleteHomeWorkoutSummary(
                        workoutInstanceId: "workout-remote",
                        workoutTemplateId: nil,
                        enrollmentId: "enrollment-1",
                        programId: programId,
                        title: "Ноги A",
                        source: .program,
                        status: .inProgress,
                        scheduledDate: "2026-03-19",
                        startedAt: "2026-03-19T09:00:00Z",
                        completedAt: nil,
                    ),
                    activeProgram: AthleteHomeProgramSummary(
                        enrollmentId: "enrollment-1",
                        programId: programId,
                        title: "Upper Lower",
                        completedWorkouts: 2,
                        totalWorkouts: 8,
                        summaryLine: "В процессе: Ноги A",
                        completionPercent: 25,
                        lastCompletedAt: "2026-03-18T09:20:00Z",
                        resumeWorkout: nil,
                        todayWorkout: nil,
                        nextWorkout: nil,
                    ),
                ),
            ),
            syncStatusResult: .success(
                AthleteSyncStatusResponse(
                    status: .synced,
                    hasPendingLocalChanges: false,
                    isDelayed: false,
                    pendingOperations: 0,
                    lastSyncedAt: "2026-03-19T09:20:00Z",
                ),
            ),
        )

        let viewModel = HomeViewModel(
            userSub: "u1",
            sessionManager: WorkoutSessionManager(progressStore: MockWorkoutProgressStore(statuses: [:])),
            isOnline: true,
            trainingStore: LocalTrainingStore(),
            cacheStore: MemoryCacheStore(),
            progressStore: MockWorkoutProgressStore(statuses: [:]),
            programsClient: nil,
            athleteTrainingClient: client,
            calendar: .current,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.activeSession?.workoutId, "workout-remote")
        XCTAssertEqual(viewModel.plannedWorkoutToday?.workoutId, "workout-remote")
        XCTAssertEqual(viewModel.primaryTitle, "Продолжить тренировку")
        XCTAssertEqual(viewModel.primaryAction, .continueSession(programId: programId, workoutId: "workout-remote"))
    }

    func testHomeViewModelFallsBackToTodayWorkoutFromActiveEnrollment() async {
        let programId = "22222222-2222-2222-2222-222222222222"
        let client = MockWorkoutHomeAthleteTrainingClient(
            progressResult: .success(
                ActiveEnrollmentProgressResponse(
                    enrollmentId: "enrollment-1",
                    status: "ACTIVE",
                    programId: programId,
                    programTitle: "Upper Lower",
                    programVersionId: "version-1",
                    currentWorkoutId: nil,
                    currentWorkoutTitle: nil,
                    currentWorkoutStatus: nil,
                    todayWorkoutId: "workout-today",
                    todayWorkoutTitle: "Ноги A",
                    todayWorkoutStatus: .planned,
                    nextWorkoutId: nil,
                    nextWorkoutTitle: nil,
                    nextWorkoutStatus: nil,
                    completedSessions: 2,
                    totalSessions: 8,
                    completionPercent: 25,
                    lastCompletedAt: nil,
                    updatedAt: nil,
                ),
            ),
            homeSummaryResult: .failure(.offline),
            syncStatusResult: .success(
                AthleteSyncStatusResponse(
                    status: .synced,
                    hasPendingLocalChanges: false,
                    isDelayed: false,
                    pendingOperations: 0,
                    lastSyncedAt: "2026-03-19T09:20:00Z",
                ),
            ),
        )

        let viewModel = HomeViewModel(
            userSub: "u1",
            sessionManager: WorkoutSessionManager(progressStore: MockWorkoutProgressStore(statuses: [:])),
            isOnline: true,
            trainingStore: LocalTrainingStore(),
            cacheStore: MemoryCacheStore(),
            progressStore: MockWorkoutProgressStore(statuses: [:]),
            programsClient: nil,
            athleteTrainingClient: client,
            calendar: .current,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.plannedWorkoutToday?.title, "Ноги A")
        XCTAssertEqual(viewModel.plannedWorkoutToday?.workoutId, "workout-today")
        XCTAssertEqual(viewModel.primaryTitle, "Начать сегодняшнюю")
        XCTAssertEqual(viewModel.primaryAction, .startNext(programId: programId, workoutId: "workout-today"))
    }

    func testWorkoutHomeViewModelPrefersRemoteResumeOverLocalStaleSession() async {
        let localSnapshot = WorkoutProgressSnapshot(
            userSub: "u1",
            programId: "program-local",
            workoutId: "workout-local",
            currentExerciseIndex: 0,
            startedAt: Date().addingTimeInterval(-1200),
            source: .program,
            workoutDetails: nil,
            hasLocalOnlyStructuralChanges: false,
            isFinished: false,
            lastUpdated: Date().addingTimeInterval(-900),
            exercises: [:],
        )
        let client = MockWorkoutHomeAthleteTrainingClient(
            homeSummaryResult: .success(
                AthleteHomeSummaryResponse(
                    generatedAt: "2026-03-19T09:20:00Z",
                    primaryAction: AthleteHomePrimaryAction(
                        type: .continueActiveWorkout,
                        title: "Продолжить тренировку",
                        workout: AthleteHomeWorkoutSummary(
                            workoutInstanceId: "workout-remote",
                            workoutTemplateId: nil,
                            enrollmentId: "enrollment-1",
                            programId: "program-remote",
                            title: "Жим B",
                            source: .program,
                            status: .inProgress,
                            scheduledDate: "2026-03-19",
                            startedAt: "2026-03-19T08:50:00Z",
                            completedAt: nil,
                        ),
                        enrollmentId: "enrollment-1",
                        programId: "program-remote",
                    ),
                    recentActivity: AthleteHomeRecentActivity(lastCompletedWorkout: nil, recentWorkouts: []),
                    progressOverview: AthleteHomeProgressOverview(
                        streakDays: 0,
                        workouts7d: 0,
                        totalWorkouts: 0,
                        totalMinutes7d: 0,
                        lastWorkoutAt: nil,
                    ),
                    activeWorkout: AthleteHomeWorkoutSummary(
                        workoutInstanceId: "workout-remote",
                        workoutTemplateId: nil,
                        enrollmentId: "enrollment-1",
                        programId: "program-remote",
                        title: "Жим B",
                        source: .program,
                        status: .inProgress,
                        scheduledDate: "2026-03-19",
                        startedAt: "2026-03-19T08:50:00Z",
                        completedAt: nil,
                    ),
                    todayWorkout: nil,
                    activeProgram: nil,
                ),
            ),
            syncStatusResult: .success(
                AthleteSyncStatusResponse(
                    status: .synced,
                    hasPendingLocalChanges: false,
                    isDelayed: false,
                    pendingOperations: 0,
                    lastSyncedAt: "2026-03-19T09:20:00Z",
                ),
            ),
        )

        let viewModel = WorkoutHomeViewModel(
            userSub: "u1",
            trainingStore: LocalTrainingStore(),
            progressStore: MockWorkoutProgressStore(statuses: [:], snapshot: localSnapshot),
            resumeStore: LocalWorkoutResumeStore(),
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            athleteTrainingClient: client,
            syncCoordinator: .shared,
        )

        await viewModel.reload()

        XCTAssertEqual(viewModel.resumeWorkout?.workoutName, "Жим B")
        if case let .remote(target)? = viewModel.resumeWorkout?.source {
            XCTAssertEqual(target.programId, "program-remote")
            XCTAssertEqual(target.workoutId, "workout-remote")
        } else {
            XCTFail("Expected remote resume source")
        }
    }

    func testWorkoutHomeViewModelTreatsRemoteTodayWorkoutWithoutStatusAsPlanned() async {
        let client = MockWorkoutHomeAthleteTrainingClient(
            homeSummaryResult: .success(
                AthleteHomeSummaryResponse(
                    generatedAt: "2026-03-19T09:20:00Z",
                    primaryAction: AthleteHomePrimaryAction(
                        type: .startTodaysWorkout,
                        title: "Начать тренировку на сегодня",
                        workout: AthleteHomeWorkoutSummary(
                            workoutInstanceId: "workout-remote",
                            workoutTemplateId: nil,
                            enrollmentId: "enrollment-1",
                            programId: "program-remote",
                            title: "Жим B",
                            source: .program,
                            status: nil,
                            scheduledDate: "2026-03-19",
                            startedAt: nil,
                            completedAt: nil,
                        ),
                        enrollmentId: "enrollment-1",
                        programId: "program-remote",
                    ),
                    recentActivity: AthleteHomeRecentActivity(lastCompletedWorkout: nil, recentWorkouts: []),
                    progressOverview: AthleteHomeProgressOverview(
                        streakDays: 0,
                        workouts7d: 0,
                        totalWorkouts: 0,
                        totalMinutes7d: 0,
                        lastWorkoutAt: nil,
                    ),
                    activeWorkout: nil,
                    todayWorkout: AthleteHomeWorkoutSummary(
                        workoutInstanceId: "workout-remote",
                        workoutTemplateId: nil,
                        enrollmentId: "enrollment-1",
                        programId: "program-remote",
                        title: "Жим B",
                        source: .program,
                        status: nil,
                        scheduledDate: "2026-03-19",
                        startedAt: nil,
                        completedAt: nil,
                    ),
                    activeProgram: nil,
                ),
            ),
            syncStatusResult: .success(
                AthleteSyncStatusResponse(
                    status: .synced,
                    hasPendingLocalChanges: false,
                    isDelayed: false,
                    pendingOperations: 0,
                    lastSyncedAt: "2026-03-19T09:20:00Z",
                ),
            ),
        )

        let viewModel = WorkoutHomeViewModel(
            userSub: "u1",
            trainingStore: LocalTrainingStore(),
            progressStore: MockWorkoutProgressStore(statuses: [:]),
            resumeStore: LocalWorkoutResumeStore(),
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            athleteTrainingClient: client,
            syncCoordinator: .shared,
        )

        await viewModel.reload()

        XCTAssertEqual(viewModel.todayWorkout?.status, .planned)
        XCTAssertEqual(viewModel.primaryActionKind, .startToday)
    }

    func testWorkoutPlayerViewModelNavigatesBetweenExercises() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: multiExerciseWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-1")
        XCTAssertFalse(viewModel.canMoveToPreviousExercise)
        XCTAssertTrue(viewModel.canMoveToNextExercise)
        XCTAssertEqual(viewModel.nextExerciseTitle, "Жим лёжа")
        XCTAssertEqual(viewModel.progressLabel, "Упражнение 1 из 2")

        await viewModel.nextExercise()

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-2")
        XCTAssertTrue(viewModel.canMoveToPreviousExercise)
        XCTAssertFalse(viewModel.canMoveToNextExercise)
        XCTAssertEqual(viewModel.previousExerciseTitle, "Присед")
        XCTAssertEqual(viewModel.progressLabel, "Упражнение 2 из 2")

        await viewModel.prevExercise()

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-1")
    }

    func testRestTimerControlsSupportAdjustResetAndSkip() {
        let timer = RestTimerModel()

        timer.start(seconds: 90)
        timer.pauseOrResume()

        XCTAssertTrue(timer.isVisible)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 90)

        timer.add(seconds: 30)
        XCTAssertEqual(timer.remainingSeconds, 120)

        timer.reset()
        timer.pauseOrResume()

        XCTAssertTrue(timer.isVisible)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 90)

        timer.skip()
        XCTAssertFalse(timer.isVisible)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)
    }

    func testWorkoutPlayerViewModelCompletingExerciseAdvancesFlowAndRestContext() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let restTimer = RestTimerModel()
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: multiExerciseWorkoutDetails,
            sessionManager: sessionManager,
            restTimer: restTimer,
        )

        await viewModel.onAppear()
        await viewModel.toggleSetComplete(setIndex: 0)

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-1")
        XCTAssertEqual(viewModel.autoAdvanceUndoState?.includesExerciseMove, false)
        XCTAssertEqual(viewModel.restStatusTitle, "Идёт отдых")

        await viewModel.toggleSetComplete(setIndex: 1)

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-2")
        XCTAssertEqual(viewModel.autoAdvanceUndoState?.includesExerciseMove, true)
        XCTAssertEqual(restTimer.exerciseName, "Жим лёжа")
        XCTAssertTrue(restTimer.isVisible)
        XCTAssertEqual(viewModel.nextStepSummary, "Дальше подход 1 в упражнении Жим лёжа.")
    }

    func testWorkoutPlayerViewModelPreservesCurrentExerciseAcrossResume() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)

        let firstViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: multiExerciseWorkoutDetails,
            sessionManager: sessionManager,
        )

        await firstViewModel.onAppear()
        await firstViewModel.nextExercise()

        let secondViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: multiExerciseWorkoutDetails,
            sessionManager: sessionManager,
        )

        await secondViewModel.onAppear()

        XCTAssertEqual(secondViewModel.currentExercise?.id, "ex-2")
        XCTAssertEqual(secondViewModel.progressLabel, "Упражнение 2 из 2")
        XCTAssertEqual(secondViewModel.previousExerciseTitle, "Присед")
    }

    func testWorkoutPlayerViewModelReplacesExerciseDuringWorkout() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.updateWeight(setIndex: 0, input: "80")

        await viewModel.applyPickedExercise(
            sampleCatalogItem(
                id: "ex-alt",
                name: "Жим ногами",
                defaults: ExerciseCatalogDraftDefaults(
                    sets: 4,
                    repsMin: 12,
                    repsMax: 15,
                    restSeconds: 90,
                    targetRpe: 7,
                    notes: nil,
                ),
            ),
            flow: .replaceCurrent,
        )

        XCTAssertEqual(viewModel.currentExercise?.id, "ex-alt")
        XCTAssertEqual(viewModel.currentExercise?.name, "Жим ногами")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.count, 4)
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.weightText, "")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.repsText, "12")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.rpeText, "7")
        XCTAssertEqual(viewModel.progressItems.map(\.id), ["ex-alt"])
    }

    func testWorkoutPlayerViewModelFinishUsesEditedWorkoutStructure() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        await viewModel.addSet(duplicateLast: false)
        await viewModel.applyPickedExercise(
            sampleCatalogItem(
                id: "ex-accessory",
                name: "Сгибание ног",
                defaults: ExerciseCatalogDraftDefaults(
                    sets: 2,
                    repsMin: 12,
                    repsMax: 15,
                    restSeconds: 60,
                    targetRpe: nil,
                    notes: nil,
                ),
            ),
            flow: .addAfterCurrent,
        )

        await viewModel.finish()

        XCTAssertEqual(viewModel.completionSummary?.totalExercises, 2)
        XCTAssertEqual(viewModel.completionSummary?.totalSets, 5)
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

    func testWorkoutPlayerViewModelMarksBodyweightExercise() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let workout = WorkoutDetailsModel(
            id: "w-bodyweight",
            title: "Bodyweight",
            dayOrder: 1,
            coachNote: nil,
            exercises: [
                WorkoutExercise(
                    id: "ex-bw",
                    name: "Подтягивания",
                    sets: 3,
                    repsMin: 6,
                    repsMax: 8,
                    targetRpe: nil,
                    restSeconds: 90,
                    notes: nil,
                    orderIndex: 0,
                    isBodyweight: true,
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

        XCTAssertTrue(viewModel.currentExerciseIsBodyweight)
    }

    func testWorkoutPlayerViewModelHidesSkipForSingleExerciseWorkout() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let singleExerciseWorkout = WorkoutDetailsModel(
            id: "w-single",
            title: "Одиночное упражнение",
            dayOrder: 1,
            coachNote: nil,
            exercises: [
                WorkoutExercise(
                    id: "ex-1",
                    name: "Планка",
                    sets: 3,
                    repsMin: nil,
                    repsMax: nil,
                    targetRpe: nil,
                    restSeconds: 60,
                    notes: nil,
                    orderIndex: 0,
                ),
            ],
        )

        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: singleExerciseWorkout,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        XCTAssertFalse(viewModel.canSkipCurrentExercise)
    }

    func testWorkoutPlayerQuickCopyAvailableOnlyForIncompleteSetsAfterFirst() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        XCTAssertFalse(viewModel.canCopyPreviousSet(setIndex: 0))
        XCTAssertFalse(viewModel.canUseQuickCopyAction)

        await viewModel.toggleSetComplete(setIndex: 0)

        XCTAssertTrue(viewModel.canCopyPreviousSet(setIndex: 1))
        XCTAssertTrue(viewModel.canUseQuickCopyAction)
        XCTAssertEqual(viewModel.quickActionSetTitle, "Из подхода 1")

        await viewModel.toggleSetComplete(setIndex: 1)

        XCTAssertFalse(viewModel.canCopyPreviousSet(setIndex: 1))
        XCTAssertFalse(viewModel.canUseQuickCopyAction)
    }

    func testWorkoutPlayerViewModelPreservesInjectedRestTimerAcrossReentry() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let restTimer = RestTimerModel()

        let firstViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
            restTimer: restTimer,
        )

        await firstViewModel.onAppear()
        await firstViewModel.toggleSetComplete(setIndex: 0)

        XCTAssertTrue(restTimer.isVisible)
        XCTAssertEqual(restTimer.workoutId, "w1")
        XCTAssertEqual(restTimer.exerciseName, "Присед")

        let secondViewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
            restTimer: restTimer,
        )

        await secondViewModel.onAppear()

        XCTAssertTrue(secondViewModel.restTimer.isVisible)
        XCTAssertEqual(secondViewModel.restTimer.workoutId, "w1")
        XCTAssertEqual(secondViewModel.restTimer.exerciseName, "Присед")
    }

    func testWorkoutPlayerViewModelFinishClearsRestTimerForCurrentWorkout() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let restTimer = RestTimerModel()
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
            restTimer: restTimer,
        )

        await viewModel.onAppear()
        await viewModel.toggleSetComplete(setIndex: 0)
        XCTAssertTrue(restTimer.isVisible)

        await viewModel.finish()

        XCTAssertFalse(restTimer.isVisible)
        XCTAssertNil(restTimer.workoutId)
        XCTAssertNil(restTimer.exerciseName)
        XCTAssertNil(restTimer.completionMessage)
    }

    func testWorkoutPlayerPrimaryActionShowsFinishConfirmationOnLastExercise() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        XCTAssertTrue(viewModel.isLastExercise)
        XCTAssertFalse(viewModel.isFinishConfirmationPresented)

        await viewModel.primaryBottomAction()

        XCTAssertTrue(viewModel.isFinishConfirmationPresented)
        XCTAssertFalse(viewModel.isFinished)
    }

    func testWorkoutPlayerConfirmFinishIsIdempotent() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()
        viewModel.isFinishConfirmationPresented = true

        await viewModel.confirmFinish()
        let firstSummary = viewModel.completionSummary

        await viewModel.confirmFinish()

        XCTAssertTrue(viewModel.isFinished)
        XCTAssertEqual(viewModel.completionSummary, firstSummary)
        XCTAssertFalse(viewModel.isFinishConfirmationPresented)
        XCTAssertFalse(viewModel.isSubmittingFinish)
    }

    func testWorkoutCompositionDraftBuildsLaunchableWorkoutForPlayer() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let draft = WorkoutCompositionDraft(
            title: "Builder Flow",
            exercises: [
                WorkoutCompositionExerciseDraft(
                    id: "ex-builder",
                    name: "Тяга гантели",
                    sets: 3,
                    repsMin: 10,
                    repsMax: 12,
                    targetRpe: 8,
                    restSeconds: 75,
                    notes: "Контроль лопатки",
                ),
            ],
        )

        let builtWorkout = draft.asWorkoutDetailsModel(
            workoutID: "quick-builder",
            fallbackTitle: "Fallback",
            dayOrder: 0,
            coachNote: "Быстрая тренировка",
        )
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "custom",
            workout: builtWorkout,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.currentExercise?.name, "Тяга гантели")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.count, 3)
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.repsText, "10")
        XCTAssertEqual(viewModel.currentExerciseState?.sets.first?.rpeText, "8")
    }

    func testWorkoutPlayerFinishPostsCompletionNotification() async {
        let progressStore = MockWorkoutProgressStore(statuses: [:])
        let sessionManager = WorkoutSessionManager(progressStore: progressStore)
        let viewModel = WorkoutPlayerViewModel(
            userSub: "u1",
            programId: "p1",
            workout: sampleWorkoutDetails,
            sessionManager: sessionManager,
        )

        await viewModel.onAppear()

        let stream = NotificationCenter.default.notifications(named: .fitfluenceWorkoutDidComplete)
        let notificationTask = Task { await stream.first(where: { _ in true }) }

        await viewModel.finish()

        let notification = await notificationTask.value
        XCTAssertEqual(notification?.userInfo?["programId"] as? String, "p1")
        XCTAssertEqual(notification?.userInfo?["workoutId"] as? String, "w1")
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

    func testAthleteShellTabsMakeTodayDefaultEntryPoint() {
        XCTAssertEqual(AthleteShellTab.defaultTab, .today)
        XCTAssertEqual(AthleteShellTab.allCases, [.today, .programs, .plan, .progress, .profile])
        XCTAssertEqual(
            AthleteShellTab.allCases.map(\.title),
            ["Сегодня", "Программы", "План", "Прогресс", "Профиль"],
        )
    }

    func testWorkoutHomePrimaryActionPrefersResumeThenTodayThenGenericStart() {
        let viewModel = WorkoutHomeViewModel(userSub: "u1")
        let remoteTarget = WorkoutHomeViewModel.RemoteWorkoutTarget(
            programId: "program-1",
            workoutId: "workout-1",
            title: "День 1",
        )

        viewModel.startWorkoutTarget = remoteTarget
        viewModel.todayWorkout = WorkoutHomeViewModel.TodayWorkout(
            title: "День 1",
            subtitle: "Сегодня • Сила 8 недель",
            detailText: "Запланирована • программа",
            status: .planned,
            source: .program,
            launchTarget: .remote(remoteTarget),
        )

        XCTAssertEqual(viewModel.primaryActionKind, .startToday)

        viewModel.resumeWorkout = WorkoutHomeViewModel.ResumeWorkout(
            source: .local(
                ActiveWorkoutSession(
                    userSub: "u1",
                    programId: "program-1",
                    workoutId: "workout-1",
                    source: .program,
                    status: .inProgress,
                    currentExerciseIndex: 1,
                    lastUpdated: Date(),
                ),
            ),
            workoutName: "День 1",
            completedExercisesCount: 1,
            totalExercisesCount: 5,
            startedAt: Date(),
        )

        XCTAssertEqual(viewModel.primaryActionKind, .resume)

        viewModel.resumeWorkout = nil
        XCTAssertEqual(viewModel.primaryActionKind, .startToday)

        viewModel.todayWorkout = nil
        XCTAssertEqual(viewModel.primaryActionKind, .startWorkout)
    }

    func testTodayWorkoutWithoutLaunchTargetFallsBackToPlanCTA() {
        let todayWorkout = WorkoutHomeViewModel.TodayWorkout(
            title: "День 2",
            subtitle: "Сегодня • По программе",
            detailText: "Запланирована • программа",
            status: .planned,
            source: .program,
            launchTarget: nil,
        )

        XCTAssertEqual(todayWorkout.buttonTitle, "Открыть план")
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
            todayWorkoutId: "workout-current",
            todayWorkoutTitle: "День 3",
            todayWorkoutStatus: .inProgress,
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

    func testActiveEnrollmentResolutionUsesTodayWorkoutAsPreferredLaunchWhenNextMissing() {
        let progress = ActiveEnrollmentProgressResponse(
            enrollmentId: "enr-2",
            status: "ACTIVE",
            programId: "program-2",
            programTitle: "Программа на сегодня",
            programVersionId: "version-2",
            currentWorkoutId: nil,
            currentWorkoutTitle: nil,
            currentWorkoutStatus: nil,
            todayWorkoutId: "workout-today",
            todayWorkoutTitle: "День 2",
            todayWorkoutStatus: .planned,
            nextWorkoutId: nil,
            nextWorkoutTitle: nil,
            nextWorkoutStatus: nil,
            completedSessions: 1,
            totalSessions: 4,
            completionPercent: 25,
            lastCompletedAt: nil,
            updatedAt: nil,
        )

        let resolved = WorkoutDomainRules.resolveActiveEnrollment(progress)

        XCTAssertEqual(resolved?.todayWorkout?.workoutId, "workout-today")
        XCTAssertEqual(resolved?.preferredLaunchWorkout?.workoutId, "workout-today")
        XCTAssertNil(resolved?.nextWorkoutToStart)
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
            todayWorkoutId: nil,
            todayWorkoutTitle: nil,
            todayWorkoutStatus: nil,
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

    private var multiExerciseWorkoutDetails: WorkoutDetailsModel {
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
                WorkoutExercise(
                    id: "ex-2",
                    name: "Жим лёжа",
                    sets: 2,
                    repsMin: 6,
                    repsMax: 8,
                    targetRpe: 8,
                    restSeconds: 120,
                    notes: nil,
                    orderIndex: 1,
                ),
            ],
        )
    }

    private func sampleCatalogItem(
        id: String,
        name: String,
        defaults: ExerciseCatalogDraftDefaults,
    ) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: id,
            code: nil,
            name: name,
            description: "Тестовое упражнение",
            movementPattern: nil,
            difficultyLevel: nil,
            isBodyweight: false,
            muscles: [],
            equipment: [],
            media: [],
            source: .athleteCatalog,
            draftDefaults: defaults,
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

private actor MockWorkoutHomeAthleteTrainingClient: AthleteTrainingClientProtocol {
    let progressResult: Result<ActiveEnrollmentProgressResponse, APIError>
    let homeSummaryResult: Result<AthleteHomeSummaryResponse, APIError>
    let syncStatusResult: Result<AthleteSyncStatusResponse, APIError>

    init(
        progressResult: Result<ActiveEnrollmentProgressResponse, APIError> = .failure(.unknown),
        homeSummaryResult: Result<AthleteHomeSummaryResponse, APIError>,
        syncStatusResult: Result<AthleteSyncStatusResponse, APIError>,
    ) {
        self.progressResult = progressResult
        self.homeSummaryResult = homeSummaryResult
        self.syncStatusResult = syncStatusResult
    }

    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError> {
        progressResult
    }

    func homeSummary() async -> Result<AthleteHomeSummaryResponse, APIError> {
        homeSummaryResult
    }

    func syncStatus() async -> Result<AthleteSyncStatusResponse, APIError> {
        syncStatusResult
    }

    func getWorkoutDetails(workoutInstanceId _: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func createCustomWorkout(request _: AthleteCreateCustomWorkoutRequest) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func updateCustomWorkout(
        workoutInstanceId _: String,
        request _: AthleteUpdateCustomWorkoutRequest,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func startWorkout(workoutInstanceId _: String, startedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        .failure(.unknown)
    }
}
