@testable import FitfluenceApp
import XCTest

@MainActor
final class CatalogAndProgramDetailsFeatureTests: XCTestCase {
    func testRootPlanDependenciesBuildPlanViewModelFromInjectedTrainingStore() async throws {
        let suite = "RootPlanDependenciesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let trainingStore = LocalTrainingStore(defaults: defaults)
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 18)) ?? Date()
        await trainingStore.schedule(
            TrainingDayPlan(
                id: "root-plan-entry",
                userSub: "u1",
                day: day,
                status: .planned,
                programId: "program-1",
                programTitle: "Program",
                workoutId: "workout-1",
                title: "Injected Plan",
                source: .program,
                workoutDetails: nil,
            ),
        )

        let dependencies = RootPlanDependencies(
            apiClient: nil,
            trainingStore: trainingStore,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: .current,
        )
        let viewModel = dependencies.makePlanViewModel(userSub: "u1")

        await viewModel.onAppear()

        XCTAssertEqual(
            viewModel.dayItems(for: day).map(\.planId),
            ["root-plan-entry"],
        )
    }

    func testProgramDetailsOpenPlanRequestsFocusedDayBeforeOpeningPlan() {
        let expectedDay = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21)) ?? Date()
        var didOpenPlan = false

        requestPlanFocusAndOpen(day: expectedDay) {
            didOpenPlan = true
        }

        XCTAssertTrue(didOpenPlan)
        XCTAssertEqual(PlanNavigationCoordinator.shared.consumePendingDay(), expectedDay)
    }

    func testRepeatFlowOpenPlanRequestsFocusedDayBeforeOpeningPlan() {
        let expectedDay = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 24)) ?? Date()
        var openedCount = 0

        requestPlanFocusAndOpen(day: expectedDay) {
            openedCount += 1
        }

        XCTAssertEqual(openedCount, 1)
        XCTAssertEqual(PlanNavigationCoordinator.shared.consumePendingDay(), expectedDay)
        XCTAssertNil(PlanNavigationCoordinator.shared.consumePendingDay())
    }

    func testCatalogOnAppearSuccessShowsPrograms() async {
        let mockClient = MockProgramsClient(
            listResults: [.success(samplePage(title: "Сила и тонус"))],
            detailsResults: [],
            startResults: [],
        )

        let viewModel = CatalogViewModel(
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.programs.count, 1)
        XCTAssertEqual(viewModel.programs.first?.title, "Сила и тонус")
        XCTAssertEqual(viewModel.currentPage, 0)
        XCTAssertEqual(viewModel.totalPages, 1)
    }

    func testCatalogOnAppearErrorShowsErrorState() async {
        let mockClient = MockProgramsClient(
            listResults: [.failure(.offline)],
            detailsResults: [],
            startResults: [],
        )

        let viewModel = CatalogViewModel(
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.error?.kind, .offline)
        XCTAssertTrue(viewModel.programs.isEmpty)
    }

    func testCatalogSearchDebounceAvoidsExtraRequests() async {
        let mockClient = MockProgramsClient(
            listResults: [
                .success(samplePage(title: "Первая")),
            ],
            detailsResults: [],
            startResults: [],
        )

        let viewModel = CatalogViewModel(
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        viewModel.searchQueryChanged("пе")
        viewModel.searchQueryChanged("пер")

        try? await Task.sleep(for: .milliseconds(500))

        let callCount = await mockClient.listCallCount()
        let lastQuery = await mockClient.lastQuery()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(lastQuery, "пер")
        XCTAssertEqual(viewModel.programs.first?.title, "Первая")
    }

    func testFollowStateMachineOptimisticUpdateAndRollback() {
        let creator = InfluencerPublicCard(
            id: UUID(uuidString: "A617BC31-4A7D-4AA7-99D4-3DFBD2D9B2EE")!,
            displayName: "Creator",
            bio: "Bio",
            avatar: nil,
            socialLinks: nil,
            followersCount: 41,
            programsCount: 6,
            isFollowedByMe: false,
        )

        let followed = FollowStateMachine.apply(.follow, to: creator)
        XCTAssertTrue(followed.isFollowedByMe)
        XCTAssertEqual(followed.followersCount, 42)

        let rolledBack = FollowStateMachine.apply(.unfollow, to: followed)
        XCTAssertFalse(rolledBack.isFollowedByMe)
        XCTAssertEqual(rolledBack.followersCount, 41)
    }

    func testCreatorsDiscoveryFollowRollbackOnFailure() async {
        let creator = InfluencerPublicCard(
            id: UUID(uuidString: "F3D2CCAA-D8A0-4AE6-A8A6-B9204E320B18")!,
            displayName: "Coach",
            bio: "Strength coach",
            avatar: nil,
            socialLinks: nil,
            followersCount: 10,
            programsCount: 3,
            isFollowedByMe: false,
        )

        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [],
            startResults: [],
            influencersSearchResults: [
                .success(
                    PagedInfluencerPublicCardResponse(
                        content: [creator],
                        metadata: PageMetadata(page: 0, size: 20, totalElements: 1, totalPages: 1),
                    ),
                ),
            ],
            followResults: [.failure(.serverError(statusCode: 503, bodySnippet: nil))],
        )

        let viewModel = CreatorsDiscoveryViewModel(
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()
        XCTAssertEqual(viewModel.creators.first?.isFollowedByMe, false)
        XCTAssertEqual(viewModel.creators.first?.followersCount, 10)

        _ = await viewModel.toggleFollow(influencerId: creator.id)

        XCTAssertEqual(viewModel.creators.first?.isFollowedByMe, false)
        XCTAssertEqual(viewModel.creators.first?.followersCount, 10)
        XCTAssertEqual(viewModel.error?.kind, .server)
    }

    func testProgramDetailsViewModelSuccess() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetails)],
            startResults: [],
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.details?.id, "program-1")
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testProgramDetailsViewModelError() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.failure(.serverError(statusCode: 503, bodySnippet: nil))],
            startResults: [],
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.error?.kind, .server)
        XCTAssertEqual(viewModel.error?.title, "Сервис временно недоступен")
        XCTAssertEqual(viewModel.error?.message, "Попробуйте ещё раз чуть позже.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testProgramDetailsNonParticipantCannotOpenOrLaunchProgramWorkout() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetails)],
            startResults: [],
        )
        let trainingClient = MockProgramDetailsAthleteTrainingClient(
            progressResult: .failure(.unknown),
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            athleteTrainingClient: trainingClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertFalse(viewModel.canAccessProgramWorkouts)
        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Начать")

        viewModel.openWorkouts()
        viewModel.workoutPicked("workout-1")

        XCTAssertFalse(viewModel.isWorkoutsPresented)
        XCTAssertNil(viewModel.selectedWorkout)
    }

    func testProgramDetailsParticipantCanOpenAndLaunchProgramWorkout() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetails)],
            startResults: [],
        )
        let trainingClient = MockProgramDetailsAthleteTrainingClient(
            progressResult: .success(
                ActiveEnrollmentProgressResponse(
                    enrollmentId: "enr-1",
                    status: "ACTIVE",
                    programId: "program-1",
                    programTitle: "Программа",
                    programVersionId: "ver-1",
                    currentWorkoutId: nil,
                    currentWorkoutTitle: nil,
                    currentWorkoutStatus: nil,
                    todayWorkoutId: nil,
                    todayWorkoutTitle: nil,
                    todayWorkoutStatus: nil,
                    nextWorkoutId: "workout-2",
                    nextWorkoutTitle: "День 2",
                    nextWorkoutStatus: .planned,
                    completedSessions: 1,
                    totalSessions: 4,
                    completionPercent: 25,
                    lastCompletedAt: nil,
                    updatedAt: nil,
                ),
            ),
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            athleteTrainingClient: trainingClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertTrue(viewModel.canAccessProgramWorkouts)
        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Начать")

        viewModel.openWorkouts()
        viewModel.workoutPicked("workout-2")

        XCTAssertTrue(viewModel.isWorkoutsPresented)
        XCTAssertEqual(viewModel.selectedWorkout?.workoutId, "workout-2")
    }

    func testProgramDetailsParticipantWithResumableWorkoutShowsContinueProgramCTA() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetails)],
            startResults: [],
        )
        let trainingClient = MockProgramDetailsAthleteTrainingClient(
            progressResult: .success(
                ActiveEnrollmentProgressResponse(
                    enrollmentId: "enr-1",
                    status: "ACTIVE",
                    programId: "program-1",
                    programTitle: "Программа",
                    programVersionId: "ver-1",
                    currentWorkoutId: "workout-1",
                    currentWorkoutTitle: "День 1",
                    currentWorkoutStatus: .inProgress,
                    todayWorkoutId: "workout-1",
                    todayWorkoutTitle: "День 1",
                    todayWorkoutStatus: .inProgress,
                    nextWorkoutId: "workout-2",
                    nextWorkoutTitle: "День 2",
                    nextWorkoutStatus: .planned,
                    completedSessions: 0,
                    totalSessions: 4,
                    completionPercent: 0,
                    lastCompletedAt: nil,
                    updatedAt: nil,
                ),
            ),
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            athleteTrainingClient: trainingClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertTrue(viewModel.canAccessProgramWorkouts)
        XCTAssertTrue(viewModel.hasResumableWorkout)
        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Продолжить")
        XCTAssertEqual(viewModel.primaryProgramActionHint, "День 1")
    }

    func testProgramDetailsEnrollmentSuccessOpensConfirmationAndFallbackLaunch() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetailsWithWorkouts)],
            startResults: [
                .success(
                    ProgramEnrollment(
                        id: "enr-1",
                        athleteId: "athlete-1",
                        programId: "program-1",
                        programTitle: "Программа",
                        programVersionId: "ver-1",
                        status: .active,
                        startedAt: "2026-03-15T09:00:00Z",
                        createdAt: nil,
                        updatedAt: nil,
                    ),
                ),
            ],
        )
        let trainingClient = MockProgramDetailsAthleteTrainingClient(
            progressResult: .success(
                ActiveEnrollmentProgressResponse(
                    enrollmentId: "enr-1",
                    status: "ACTIVE",
                    programId: "program-1",
                    programTitle: "Программа",
                    programVersionId: "ver-1",
                    currentWorkoutId: nil,
                    currentWorkoutTitle: nil,
                    currentWorkoutStatus: nil,
                    todayWorkoutId: nil,
                    todayWorkoutTitle: nil,
                    todayWorkoutStatus: nil,
                    nextWorkoutId: nil,
                    nextWorkoutTitle: nil,
                    nextWorkoutStatus: nil,
                    completedSessions: 0,
                    totalSessions: 3,
                    completionPercent: 0,
                    lastCompletedAt: nil,
                    updatedAt: nil,
                ),
            ),
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            athleteTrainingClient: trainingClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()
        await viewModel.handlePrimaryProgramAction()

        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Распланировать")
        XCTAssertFalse(viewModel.canAccessProgramWorkouts)
        XCTAssertEqual(viewModel.enrollmentConfirmation?.firstWorkoutTitle, "День 1")
        XCTAssertFalse(viewModel.enrollmentConfirmation?.canStartFirstWorkout ?? true)
        XCTAssertNil(viewModel.enrollmentConfirmation?.firstWorkoutInstanceId)

        await viewModel.handleEnrollmentPrimaryAction()

        XCTAssertNotNil(viewModel.enrollmentConfirmation)
        XCTAssertNil(viewModel.selectedWorkout)
    }

    func testProgramDetailsParticipantWithTodayWorkoutUsesGenericLaunchCTA() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetails)],
            startResults: [],
        )
        let trainingClient = MockProgramDetailsAthleteTrainingClient(
            progressResult: .success(
                ActiveEnrollmentProgressResponse(
                    enrollmentId: "enr-1",
                    status: "ACTIVE",
                    programId: "program-1",
                    programTitle: "Программа",
                    programVersionId: "ver-1",
                    currentWorkoutId: nil,
                    currentWorkoutTitle: nil,
                    currentWorkoutStatus: nil,
                    todayWorkoutId: "workout-today",
                    todayWorkoutTitle: "День сегодня",
                    todayWorkoutStatus: .planned,
                    nextWorkoutId: nil,
                    nextWorkoutTitle: nil,
                    nextWorkoutStatus: nil,
                    completedSessions: 1,
                    totalSessions: 4,
                    completionPercent: 25,
                    lastCompletedAt: nil,
                    updatedAt: nil,
                ),
            ),
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            athleteTrainingClient: trainingClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
        )

        await viewModel.onAppear()

        XCTAssertTrue(viewModel.canAccessProgramWorkouts)
        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Начать сегодня")
        XCTAssertEqual(viewModel.primaryProgramActionHint, "День сегодня")
    }

    func testProgramDetailsScheduleProgramWorkoutsCreatesLocalPlan() async {
        let suiteName = "ProgramDetailsScheduleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let trainingStore = LocalTrainingStore(defaults: defaults)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetailsWithWorkouts)],
            startResults: [],
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            trainingStore: trainingStore,
        )

        await viewModel.onAppear()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        let nextMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        let startDate = stride(from: 0, through: 6, by: 1)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: nextMonthStart) }
            .first(where: { calendar.component(.weekday, from: $0) == 2 }) ?? nextMonthStart
        let firstDay = await viewModel.scheduleProgramWorkouts(
            startDate: startDate,
            weekdays: [.monday, .wednesday, .friday],
        )

        XCTAssertEqual(firstDay, startDate)

        let monthPlans = await trainingStore.plans(userSub: "u1", month: startDate)
        let scheduled = monthPlans
            .filter { $0.programId == "program-1" }
            .sorted { $0.day < $1.day }

        XCTAssertEqual(scheduled.count, 3)
        XCTAssertEqual(scheduled.map(\.title), ["День 1", "День 2", "День 3"])
        XCTAssertEqual(scheduled.map(\.source), [.program, .program, .program])
        XCTAssertEqual(scheduled.map(\.workoutId), ["w1", "w2", "w3"])
        XCTAssertEqual(scheduled.map(\.programTitle), ["Программа", "Программа", "Программа"])
        XCTAssertTrue(scheduled.allSatisfy { $0.workoutDetails != nil })
    }

    func testProgramDetailsScheduleReferencesUseSharedPlanDisplayInterpretation() async {
        let suiteName = "ProgramDetailsScheduleReferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let trainingStore = LocalTrainingStore(defaults: defaults)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let today = Calendar.current.startOfDay(for: Date())
        let plannedDay = Calendar.current.date(byAdding: .hour, value: 10, to: today) ?? today

        await trainingStore.schedule(
            TrainingDayPlan(
                id: "local-plan-reference",
                userSub: "u1",
                day: plannedDay,
                status: .missed,
                programId: "program-1",
                programTitle: "Программа",
                workoutId: "w1",
                title: "День 1",
                source: .program,
                workoutDetails: WorkoutDetailsModel(
                    id: "w1",
                    title: "День 1",
                    dayOrder: 1,
                    coachNote: nil,
                    exercises: [],
                ),
            ),
        )

        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetailsWithWorkouts)],
            startResults: [],
        )

        let viewModel = ProgramDetailsViewModel(
            programId: "program-1",
            userSub: "u1",
            programsClient: mockClient,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            trainingStore: trainingStore,
        )

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.scheduleReference(for: "w1")?.status, .planned)
        XCTAssertEqual(viewModel.templatePlanAnchors["w1"]?.status, .planned)
        XCTAssertEqual(viewModel.scheduleReference(for: "w1")?.day, plannedDay)
    }

    func testWorkoutsClientFallsBackToEquipmentForBodyweightProgramExercises() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [
                .success(
                    ProgramDetails(
                        id: "program-1",
                        title: "Core",
                        description: nil,
                        status: .published,
                        isFeatured: nil,
                        influencer: nil,
                        cover: nil,
                        media: nil,
                        goals: nil,
                        currentPublishedVersion: nil,
                        createdAt: nil,
                        updatedAt: nil,
                        versions: nil,
                        workouts: [
                            WorkoutTemplate(
                                id: "workout-1",
                                dayOrder: 1,
                                title: "Abs",
                                coachNote: nil,
                                exercises: [
                                    ExerciseTemplate(
                                        id: "template-1",
                                        exercise: ExerciseSummary(
                                            id: "exercise-1",
                                            code: "crunch",
                                            name: "Скручивания",
                                            description: nil,
                                            isBodyweight: nil,
                                            equipment: [
                                                ExerciseCatalogEquipment(
                                                    id: "equipment-1",
                                                    code: "bodyweight",
                                                    name: "Bodyweight",
                                                    category: .bodyweight,
                                                    description: nil,
                                                    media: nil,
                                                ),
                                            ],
                                            media: nil,
                                        ),
                                        sets: 3,
                                        repsMin: 15,
                                        repsMax: 20,
                                        targetRpe: nil,
                                        restSeconds: 60,
                                        notes: nil,
                                        orderIndex: 0,
                                    ),
                                ],
                                media: nil,
                            ),
                        ],
                    ),
                ),
            ],
            startResults: [],
        )
        let client = WorkoutsClient(programsClient: mockClient)

        let result = await client.getWorkoutDetails(programId: "program-1", workoutId: "workout-1")

        switch result {
        case let .success(details):
            XCTAssertEqual(details.exercises.first?.isBodyweight, true)
        case let .failure(error):
            XCTFail("Expected success, got \(error)")
        }
    }

    private func samplePage(title: String) -> PagedProgramResponse {
        PagedProgramResponse(
            content: [
                ProgramListItem(
                    id: "program-1",
                    title: title,
                    description: "Описание программы",
                    status: .published,
                    isFeatured: true,
                    influencer: InfluencerBrief(id: "inf-1", displayName: "Тренер", avatar: nil, bio: nil),
                    cover: ContentMedia(
                        id: "m1",
                        type: .image,
                        url: "/uploads/media/image.png",
                        mimeType: "image/png",
                        tags: nil,
                        createdAt: nil,
                        ownerType: nil,
                        ownerId: nil,
                        ownerDisplayName: nil,
                    ),
                    media: nil,
                    goals: ["Сила"],
                    currentPublishedVersion: ProgramVersionSummary(
                        id: "ver-1",
                        versionNumber: 1,
                        status: .published,
                        publishedAt: nil,
                        level: nil,
                        frequencyPerWeek: 3,
                        requirements: nil,
                    ),
                    level: "BEGINNER",
                    daysPerWeek: 3,
                    estimatedDurationMinutes: 45,
                    equipment: ["Гантели", "Скамья"],
                    createdAt: nil,
                    updatedAt: nil,
                ),
            ],
            metadata: PageMetadata(page: 0, size: 20, totalElements: 1, totalPages: 1),
        )
    }

    private var sampleDetails: ProgramDetails {
        ProgramDetails(
            id: "program-1",
            title: "Программа",
            description: "Описание",
            status: .published,
            isFeatured: false,
            influencer: nil,
            cover: nil,
            media: nil,
            goals: [],
            currentPublishedVersion: ProgramVersionSummary(
                id: "ver-1",
                versionNumber: 1,
                status: .published,
                publishedAt: nil,
                level: nil,
                frequencyPerWeek: nil,
                requirements: nil,
            ),
            createdAt: nil,
            updatedAt: nil,
            versions: nil,
            workouts: nil,
        )
    }

    private var sampleDetailsWithWorkouts: ProgramDetails {
        ProgramDetails(
            id: "program-1",
            title: "Программа",
            description: "Описание",
            status: .published,
            isFeatured: false,
            influencer: nil,
            cover: nil,
            media: nil,
            goals: [],
            currentPublishedVersion: ProgramVersionSummary(
                id: "ver-1",
                versionNumber: 1,
                status: .published,
                publishedAt: nil,
                level: nil,
                frequencyPerWeek: 3,
                requirements: nil,
            ),
            createdAt: nil,
            updatedAt: nil,
            versions: nil,
            workouts: [
                makeWorkoutTemplate(id: "w1", dayOrder: 1, title: "День 1"),
                makeWorkoutTemplate(id: "w2", dayOrder: 2, title: "День 2"),
                makeWorkoutTemplate(id: "w3", dayOrder: 3, title: "День 3"),
            ],
        )
    }

    private func makeWorkoutTemplate(id: String, dayOrder: Int, title: String) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            dayOrder: dayOrder,
            title: title,
            coachNote: nil,
            exercises: [
                ExerciseTemplate(
                    id: "ex-\(id)",
                    exercise: ExerciseSummary(
                        id: "exercise-\(id)",
                        code: nil,
                        name: "Присед",
                        description: nil,
                        isBodyweight: false,
                        equipment: nil,
                        media: nil,
                    ),
                    sets: 4,
                    repsMin: 5,
                    repsMax: 8,
                    targetRpe: nil,
                    restSeconds: 120,
                    notes: nil,
                    orderIndex: 0,
                ),
            ],
            media: nil,
        )
    }
}

private actor MockProgramsClient: ProgramsClientProtocol {
    private var listResults: [Result<PagedProgramResponse, APIError>]
    private var featuredResults: [Result<PagedProgramResponse, APIError>]
    private var detailsResults: [Result<ProgramDetails, APIError>]
    private var startResults: [Result<ProgramEnrollment, APIError>]
    private var influencersSearchResults: [Result<PagedInfluencerPublicCardResponse, APIError>]
    private var followingResults: [Result<PagedInfluencerPublicCardResponse, APIError>]
    private var followResults: [Result<Void, APIError>]
    private var unfollowResults: [Result<Void, APIError>]
    private var creatorProgramsResults: [Result<PagedProgramResponse, APIError>]
    private(set) var receivedQueries: [String] = []

    init(
        listResults: [Result<PagedProgramResponse, APIError>],
        detailsResults: [Result<ProgramDetails, APIError>],
        startResults: [Result<ProgramEnrollment, APIError>],
        influencersSearchResults: [Result<PagedInfluencerPublicCardResponse, APIError>] = [],
        followingResults: [Result<PagedInfluencerPublicCardResponse, APIError>] = [],
        followResults: [Result<Void, APIError>] = [],
        unfollowResults: [Result<Void, APIError>] = [],
        creatorProgramsResults: [Result<PagedProgramResponse, APIError>] = [],
    ) {
        self.listResults = listResults
        featuredResults = listResults
        self.detailsResults = detailsResults
        self.startResults = startResults
        self.influencersSearchResults = influencersSearchResults
        self.followingResults = followingResults
        self.followResults = followResults
        self.unfollowResults = unfollowResults
        self.creatorProgramsResults = creatorProgramsResults
    }

    func listPublishedPrograms(
        query: String,
        page _: Int,
        size _: Int,
    ) async -> Result<PagedProgramResponse, APIError> {
        receivedQueries.append(query)
        guard !listResults.isEmpty else { return .failure(.unknown) }
        return listResults.removeFirst()
    }

    func listFeaturedPrograms(page _: Int, size _: Int) async -> Result<PagedProgramResponse, APIError> {
        guard !featuredResults.isEmpty else { return .failure(.unknown) }
        return featuredResults.removeFirst()
    }

    func getProgramDetails(programId _: String) async -> Result<ProgramDetails, APIError> {
        guard !detailsResults.isEmpty else { return .failure(.unknown) }
        return detailsResults.removeFirst()
    }

    func startProgram(programVersionId _: String) async -> Result<ProgramEnrollment, APIError> {
        guard !startResults.isEmpty else { return .failure(.unknown) }
        return startResults.removeFirst()
    }

    func influencersSearch(request _: InfluencersSearchRequest) async -> Result<PagedInfluencerPublicCardResponse, APIError> {
        guard !influencersSearchResults.isEmpty else { return .failure(.unknown) }
        return influencersSearchResults.removeFirst()
    }

    func getFollowingCreators(page _: Int, size _: Int, search _: String?) async -> Result<PagedInfluencerPublicCardResponse, APIError> {
        guard !followingResults.isEmpty else { return .failure(.unknown) }
        return followingResults.removeFirst()
    }

    func followCreator(influencerId _: UUID) async -> Result<Void, APIError> {
        guard !followResults.isEmpty else { return .failure(.unknown) }
        return followResults.removeFirst()
    }

    func unfollowCreator(influencerId _: UUID) async -> Result<Void, APIError> {
        guard !unfollowResults.isEmpty else { return .failure(.unknown) }
        return unfollowResults.removeFirst()
    }

    func getCreatorPrograms(influencerId _: UUID, page _: Int, size _: Int) async -> Result<PagedProgramResponse, APIError> {
        guard !creatorProgramsResults.isEmpty else { return .failure(.unknown) }
        return creatorProgramsResults.removeFirst()
    }

    func listCallCount() async -> Int {
        receivedQueries.count
    }

    func lastQuery() async -> String? {
        receivedQueries.last
    }
}

private actor MockProgramDetailsAthleteTrainingClient: AthleteTrainingClientProtocol {
    private let progressResult: Result<ActiveEnrollmentProgressResponse, APIError>

    init(progressResult: Result<ActiveEnrollmentProgressResponse, APIError>) {
        self.progressResult = progressResult
    }

    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError> {
        progressResult
    }

    func programStatus(programId: String) async -> Result<AthleteProgramStatusResponse, APIError> {
        switch progressResult {
        case let .success(progress):
            let enrollment = progress.enrollmentId.map {
                AthleteProgramEnrollmentSummary(
                    id: $0,
                    athleteId: "athlete-1",
                    programId: progress.programId,
                    programTitle: progress.programTitle,
                    programVersionId: progress.programVersionId ?? "ver-1",
                    status: progress.status ?? "ACTIVE",
                    startedAt: "2026-03-15T09:00:00Z",
                    createdAt: nil,
                    updatedAt: nil,
                )
            }

            let currentWorkout = progress.currentWorkoutId.map {
                AthleteProgramWorkoutTarget(
                    workoutInstanceId: $0,
                    workoutTemplateId: nil,
                    title: progress.currentWorkoutTitle,
                    scheduledDate: progress.currentWorkoutStatus == .inProgress ? "2026-03-18" : nil,
                    status: progress.currentWorkoutStatus,
                )
            }
            let todayWorkout = progress.todayWorkoutId.map {
                AthleteProgramWorkoutTarget(
                    workoutInstanceId: $0,
                    workoutTemplateId: nil,
                    title: progress.todayWorkoutTitle,
                    scheduledDate: "2026-03-19",
                    status: progress.todayWorkoutStatus,
                )
            }
            let nextWorkout = progress.nextWorkoutId.map {
                AthleteProgramWorkoutTarget(
                    workoutInstanceId: $0,
                    workoutTemplateId: nil,
                    title: progress.nextWorkoutTitle,
                    scheduledDate: "2026-03-21",
                    status: progress.nextWorkoutStatus,
                )
            }

            return .success(
                AthleteProgramStatusResponse(
                    programId: progress.programId ?? programId,
                    programTitle: progress.programTitle ?? "Программа",
                    enrollment: enrollment,
                    currentWorkout: currentWorkout,
                    todayWorkout: todayWorkout,
                    nextWorkout: nextWorkout,
                    resumeWorkout: currentWorkout?.status == .inProgress ? currentWorkout : nil,
                    launchWorkout: currentWorkout?.status == .inProgress ? currentWorkout : (todayWorkout ?? nextWorkout),
                    completedSessions: progress.completedSessions,
                    totalSessions: progress.totalSessions,
                    completionPercent: progress.completionPercent,
                    lastCompletedAt: progress.lastCompletedAt,
                    updatedAt: progress.updatedAt,
                ),
            )
        case let .failure(error):
            return .failure(error)
        }
    }

    func getWorkoutDetails(workoutInstanceId _: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func createCustomWorkout(
        request _: AthleteCreateCustomWorkoutRequest,
        idempotencyKey _: String?,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func updateCustomWorkout(
        workoutInstanceId _: String,
        request _: AthleteUpdateCustomWorkoutRequest,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        .failure(.unknown)
    }

    func startWorkout(workoutInstanceId: String, startedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        .success(
            AthleteWorkoutInstance(
                id: workoutInstanceId,
                enrollmentId: "enr-1",
                workoutTemplateId: nil,
                title: "Тренировка",
                status: .inProgress,
                source: .program,
                scheduledDate: nil,
                startedAt: nil,
                completedAt: nil,
                durationSeconds: nil,
                notes: nil,
                programId: "program-1",
            ),
        )
    }
}
