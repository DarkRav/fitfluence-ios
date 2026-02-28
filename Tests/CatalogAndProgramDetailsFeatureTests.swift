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
        guard !listResults.isEmpty else { return .failure(.unknown) }
        return listResults.removeFirst()
    }

    func getProgramDetails(programId _: String) async -> Result<ProgramDetails, APIError> {
        guard !detailsResults.isEmpty else { return .failure(.unknown) }
        return detailsResults.removeFirst()
    }

    func startProgram(programVersionId _: String) async -> Result<ProgramEnrollment, APIError> {
        guard !startResults.isEmpty else { return .failure(.unknown) }
        return startResults.removeFirst()
    }

    func listCallCount() async -> Int {
        receivedQueries.count
    }

    func lastQuery() async -> String? {
        receivedQueries.last
    }
}
