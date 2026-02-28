import ComposableArchitecture
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

        let store = TestStore(initialState: CatalogFeature.State()) {
            CatalogFeature(
                programsClient: mockClient,
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
            $0.currentPage = 0
        }

        await store.receive(.cachedPageResponse(nil, append: false))

        await store.receive(.programsResponse(.success(samplePage(title: "Сила и тонус")), append: false)) {
            $0.isLoading = false
            $0.isRefreshing = false
            $0.programs = [
                CatalogFeature.ProgramCard(
                    id: "program-1",
                    title: "Сила и тонус",
                    description: "Описание программы",
                    influencerName: "Тренер",
                    goals: ["Сила"],
                    coverURL: "/uploads/media/image.png",
                    isPublished: true,
                ),
            ]
            $0.currentPage = 0
            $0.totalPages = 1
            $0.error = nil
        }
    }

    func testCatalogOnAppearErrorShowsErrorState() async {
        let mockClient = MockProgramsClient(
            listResults: [.failure(.offline)],
            detailsResults: [],
            startResults: [],
        )

        let store = TestStore(initialState: CatalogFeature.State()) {
            CatalogFeature(
                programsClient: mockClient,
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
            $0.currentPage = 0
        }

        await store.receive(.cachedPageResponse(nil, append: false))

        await store.receive(.programsResponse(.failure(.offline), append: false)) {
            $0.isLoading = false
            $0.isRefreshing = false
            $0.error = UserFacingError(
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
            $0.programs = []
        }
    }

    func testCatalogSearchDebounceAvoidsExtraRequests() async {
        let mockClient = MockProgramsClient(
            listResults: [
                .success(samplePage(title: "Первая")),
            ],
            detailsResults: [],
            startResults: [],
        )

        let store = TestStore(initialState: CatalogFeature.State()) {
            CatalogFeature(
                programsClient: mockClient,
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.searchQueryChanged("пе")) {
            $0.query = "пе"
            $0.error = nil
        }
        await store.send(.searchQueryChanged("пер")) {
            $0.query = "пер"
            $0.error = nil
        }

        try? await Task.sleep(for: .milliseconds(500))

        await store.receive(.searchSubmit) {
            $0.isLoading = true
            $0.error = nil
            $0.currentPage = 0
        }
        await store.receive(.cachedPageResponse(nil, append: false))
        await store.receive(.programsResponse(.success(samplePage(title: "Первая")), append: false)) {
            $0.isLoading = false
            $0.isRefreshing = false
            $0.programs = [
                CatalogFeature.ProgramCard(
                    id: "program-1",
                    title: "Первая",
                    description: "Описание программы",
                    influencerName: "Тренер",
                    goals: ["Сила"],
                    coverURL: "/uploads/media/image.png",
                    isPublished: true,
                ),
            ]
            $0.currentPage = 0
            $0.totalPages = 1
            $0.error = nil
        }

        let callCount = await mockClient.listCallCount()
        let lastQuery = await mockClient.lastQuery()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(lastQuery, "пер")
    }

    func testProgramDetailsSuccess() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.success(sampleDetails)],
            startResults: [],
        )

        let store = TestStore(initialState: ProgramDetailsFeature.State(programId: "program-1", userSub: "u1")) {
            ProgramDetailsFeature(
                programsClient: mockClient,
                progressStore: LocalWorkoutProgressStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
        }

        await store.receive(.cachedDetailsResponse(nil))

        await store.receive(.detailsResponse(.success(sampleDetails))) { [self] in
            $0.isLoading = false
            $0.details = self.sampleDetails
            $0.error = nil
        }
    }

    func testProgramDetailsError() async {
        let mockClient = MockProgramsClient(
            listResults: [],
            detailsResults: [.failure(.serverError(statusCode: 503, bodySnippet: nil))],
            startResults: [],
        )

        let store = TestStore(initialState: ProgramDetailsFeature.State(programId: "program-1", userSub: "u1")) {
            ProgramDetailsFeature(
                programsClient: mockClient,
                progressStore: LocalWorkoutProgressStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                cacheStore: MemoryCacheStore(),
                networkMonitor: StaticNetworkMonitor(currentStatus: true),
            )
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.error = nil
        }

        await store.receive(.cachedDetailsResponse(nil))

        await store.receive(.detailsResponse(.failure(.serverError(statusCode: 503, bodySnippet: nil)))) {
            $0.isLoading = false
            $0.error = UserFacingError(
                title: "Сервис временно недоступен",
                message: "Попробуйте открыть программу чуть позже.",
            )
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
    private var detailsResults: [Result<ProgramDetails, APIError>]
    private var startResults: [Result<ProgramEnrollment, APIError>]
    private(set) var receivedQueries: [String] = []

    init(
        listResults: [Result<PagedProgramResponse, APIError>],
        detailsResults: [Result<ProgramDetails, APIError>],
        startResults: [Result<ProgramEnrollment, APIError>],
    ) {
        self.listResults = listResults
        self.detailsResults = detailsResults
        self.startResults = startResults
    }

    func listPublishedPrograms(
        query: String,
        page _: Int,
        size _: Int,
    ) async -> Result<PagedProgramResponse, APIError> {
        receivedQueries.append(query)
        guard !listResults.isEmpty else {
            return .failure(.unknown)
        }
        return listResults.removeFirst()
    }

    func getProgramDetails(programId _: String) async -> Result<ProgramDetails, APIError> {
        guard !detailsResults.isEmpty else {
            return .failure(.unknown)
        }
        return detailsResults.removeFirst()
    }

    func startProgram(programVersionId _: String) async -> Result<ProgramEnrollment, APIError> {
        guard !startResults.isEmpty else {
            return .failure(.unknown)
        }
        return startResults.removeFirst()
    }

    func listCallCount() -> Int {
        receivedQueries.count
    }

    func lastQuery() -> String? {
        receivedQueries.last
    }
}
