@testable import FitfluenceApp
import XCTest

@MainActor
final class CatalogAndProgramDetailsFeatureTests: XCTestCase {
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
        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Начать программу")

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
        XCTAssertEqual(viewModel.primaryProgramActionTitle, "Продолжить программу")

        viewModel.openWorkouts()
        viewModel.workoutPicked("workout-2")

        XCTAssertTrue(viewModel.isWorkoutsPresented)
        XCTAssertEqual(viewModel.selectedWorkout?.workoutId, "workout-2")
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

    func getWorkoutDetails(workoutInstanceId _: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
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
