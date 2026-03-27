@testable import FitfluenceApp
import XCTest

final class ExerciseCatalogTests: XCTestCase {
    func testBodyweightResolverUsesExplicitBackendValue() {
        XCTAssertTrue(
            ExerciseBodyweightResolver.resolve(
                isBodyweight: true,
                equipmentCategories: [],
            ),
        )
        XCTAssertFalse(
            ExerciseBodyweightResolver.resolve(
                isBodyweight: false,
                equipmentCategories: [.bodyweight],
            ),
        )
    }

    func testBodyweightResolverFallsBackToEquipmentCategoryWhenBackendValueMissing() {
        XCTAssertTrue(
            ExerciseBodyweightResolver.resolve(
                isBodyweight: nil,
                equipmentCategories: [.bodyweight],
            ),
        )
        XCTAssertFalse(
            ExerciseBodyweightResolver.resolve(
                isBodyweight: nil,
                equipmentCategories: [.freeWeight, .machine],
            ),
        )
    }

    func testAPIExerciseMapsToDomainItem() {
        let exercise = APIExercise(
            id: "exercise-1",
            code: "barbell-squat",
            name: "Barbell Squat",
            description: "Primary squat pattern",
            movementPattern: .squat,
            difficultyLevel: .intermediate,
            isBodyweight: false,
            createdByInfluencerId: nil,
            muscles: [
                APIExerciseMuscle(
                    id: "muscle-1",
                    code: "quads",
                    name: "Quadriceps",
                    muscleGroup: .legs,
                    description: "Front thigh",
                    media: nil,
                ),
            ],
            media: [
                ContentMedia(
                    id: "media-1",
                    type: .video,
                    url: "/media/squat.mp4",
                    mimeType: "video/mp4",
                    tags: ["demo"],
                    createdAt: nil,
                    ownerType: nil,
                    ownerId: nil,
                    ownerDisplayName: nil,
                ),
            ],
            equipment: [
                APIExerciseEquipment(
                    id: "equipment-1",
                    code: "barbell",
                    name: "Barbell",
                    category: .freeWeight,
                    description: "Olympic barbell",
                    media: nil,
                ),
            ],
        )

        let mapped = exercise.asCatalogItem

        XCTAssertEqual(mapped.id, "exercise-1")
        XCTAssertEqual(mapped.code, "barbell-squat")
        XCTAssertEqual(mapped.name, "Barbell Squat")
        XCTAssertEqual(mapped.description, "Primary squat pattern")
        XCTAssertEqual(mapped.movementPattern, .squat)
        XCTAssertEqual(mapped.difficultyLevel, .intermediate)
        XCTAssertEqual(mapped.isBodyweight, false)
        XCTAssertEqual(mapped.muscles.first?.name, "Quadriceps")
        XCTAssertEqual(mapped.muscles.first?.muscleGroup, .legs)
        XCTAssertEqual(mapped.equipment.first?.name, "Barbell")
        XCTAssertEqual(mapped.equipment.first?.category, .freeWeight)
        XCTAssertEqual(mapped.media.count, 1)
        XCTAssertEqual(mapped.source, .athleteCatalog)
        XCTAssertNil(mapped.draftDefaults)
    }

    func testCatalogMetadataMapsToDomain() {
        let metadata = APIAthleteExerciseCatalogMetadataResponse(
            muscles: [
                APIExerciseMuscle(
                    id: "muscle-1",
                    code: "chest",
                    name: "Chest",
                    muscleGroup: .chest,
                    description: "Pectorals",
                    media: nil,
                ),
            ],
            equipment: [
                APIExerciseEquipment(
                    id: "equipment-1",
                    code: "barbell",
                    name: "Barbell",
                    category: .freeWeight,
                    description: nil,
                    media: nil,
                ),
            ],
            muscleGroups: [.chest, .back],
            equipmentCategories: [.freeWeight, .machine],
            movementPatterns: [.push, .pull],
            difficultyLevels: [.beginner, .advanced],
        )

        let mapped = metadata.asDomain

        XCTAssertEqual(mapped.muscles.map(\.name), ["Chest"])
        XCTAssertEqual(mapped.equipment.map(\.name), ["Barbell"])
        XCTAssertEqual(mapped.muscleGroups, [.chest, .back])
        XCTAssertEqual(mapped.equipmentCategories, [.freeWeight, .machine])
        XCTAssertEqual(mapped.movementPatterns, [.push, .pull])
        XCTAssertEqual(mapped.difficultyLevels, [.beginner, .advanced])
    }

    func testCatalogItemResolvesBodyweightFromEquipmentCategory() {
        let item = ExerciseCatalogItem(
            id: "exercise-1",
            code: "push-up",
            name: "Push-Up",
            description: nil,
            movementPattern: .push,
            difficultyLevel: .beginner,
            isBodyweight: nil,
            muscles: [],
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
            media: [],
            source: .athleteCatalog,
            draftDefaults: nil,
        )

        XCTAssertTrue(item.resolvedIsBodyweight)
    }

    func testRepositoryUsesBackendCatalogWhenAthleteSearchSucceeds() async throws {
        let store = try makeStore()
        let repository = BackendExerciseCatalogRepository(
            apiClient: MockExerciseCatalogAPIClient(
                searchResult: .success(
                    APIPagedExerciseResponse(
                        content: [
                            APIExercise(
                                id: "exercise-1",
                                code: "bench-press",
                                name: "Bench Press",
                                description: nil,
                                movementPattern: .push,
                                difficultyLevel: .beginner,
                                isBodyweight: false,
                                createdByInfluencerId: nil,
                                muscles: nil,
                                media: nil,
                                equipment: nil,
                            ),
                        ],
                        metadata: PageMetadata(page: 0, size: 20, totalElements: 1, totalPages: 1),
                    ),
                ),
            ),
            userSub: "u1",
            trainingStore: store,
        )

        await store.saveTemplate(
            WorkoutTemplateDraft(
                id: "template-1",
                userSub: "u1",
                name: "Saved Upper",
                exercises: [
                    TemplateExerciseDraft(id: "legacy-bp", name: "Legacy Bench", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
                ],
                updatedAt: Date(),
            ),
        )

        let result = await repository.search(query: ExerciseCatalogQuery())

        XCTAssertEqual(result.source, .athleteCatalog)
        XCTAssertEqual(result.state, .content)
        XCTAssertEqual(result.items.map(\.name), ["Bench Press"])
        XCTAssertNil(result.note)
    }

    func testRepositoryLoadsAthleteCatalogMetadata() async {
        let repository = BackendExerciseCatalogRepository(
            apiClient: MockExerciseCatalogAPIClient(
                searchResult: .failure(.unknown),
                metadataResult: .success(
                    APIAthleteExerciseCatalogMetadataResponse(
                        muscles: [
                            APIExerciseMuscle(
                                id: "muscle-1",
                                code: "back",
                                name: "Back",
                                muscleGroup: .back,
                                description: nil,
                                media: nil,
                            ),
                        ],
                        equipment: [
                            APIExerciseEquipment(
                                id: "equipment-1",
                                code: "band",
                                name: "Band",
                                category: .band,
                                description: nil,
                                media: nil,
                            ),
                        ],
                        muscleGroups: [.back],
                        equipmentCategories: [.band],
                        movementPatterns: [.pull],
                        difficultyLevels: [.intermediate],
                    ),
                ),
            ),
            userSub: "u1",
            trainingStore: try! makeStore(),
        )

        let metadata = await repository.metadata()

        XCTAssertEqual(metadata.muscles.map(\.name), ["Back"])
        XCTAssertEqual(metadata.equipment.map(\.name), ["Band"])
        XCTAssertEqual(metadata.movementPatterns, [.pull])
    }

    func testRepositoryDerivesMetadataFromSearchWhenMetadataEndpointFails() async throws {
        let repository = BackendExerciseCatalogRepository(
            apiClient: MockExerciseCatalogAPIClient(
                searchResult: .success(
                    APIPagedExerciseResponse(
                        content: [
                            APIExercise(
                                id: "exercise-1",
                                code: "bench-press",
                                name: "Bench Press",
                                description: nil,
                                movementPattern: .push,
                                difficultyLevel: .beginner,
                                isBodyweight: false,
                                createdByInfluencerId: nil,
                                muscles: [
                                    APIExerciseMuscle(
                                        id: "muscle-1",
                                        code: "chest",
                                        name: "Chest",
                                        muscleGroup: .chest,
                                        description: nil,
                                        media: nil,
                                    ),
                                ],
                                media: nil,
                                equipment: [
                                    APIExerciseEquipment(
                                        id: "equipment-1",
                                        code: "barbell",
                                        name: "Barbell",
                                        category: .freeWeight,
                                        description: nil,
                                        media: nil,
                                    ),
                                ],
                            ),
                        ],
                        metadata: PageMetadata(page: 0, size: 100, totalElements: 1, totalPages: 1),
                    ),
                ),
                metadataResult: .failure(.serverError(statusCode: 500, bodySnippet: nil)),
            ),
            userSub: "u1",
            trainingStore: try makeStore(),
        )

        let metadata = await repository.metadata()

        XCTAssertEqual(metadata.equipment.map(\.name), ["Barbell"])
        XCTAssertEqual(metadata.muscleGroups, [.chest])
        XCTAssertEqual(metadata.movementPatterns, [.push])
    }

    func testRepositoryFallsBackToSavedTemplatesWhenBackendUnavailable() async throws {
        let store = try makeStore()
        await store.saveTemplate(
            WorkoutTemplateDraft(
                id: "template-1",
                userSub: "u1",
                name: "Saved Lower",
                exercises: [
                    TemplateExerciseDraft(id: "exercise-1", name: "Goblet Squat", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90),
                ],
                updatedAt: Date(),
            ),
        )

        let repository = BackendExerciseCatalogRepository(
            apiClient: MockExerciseCatalogAPIClient(searchResult: .failure(.forbidden)),
            userSub: "u1",
            trainingStore: store,
        )

        let result = await repository.search(query: ExerciseCatalogQuery())

        XCTAssertEqual(result.source, .savedTemplates)
        XCTAssertEqual(result.state, .content)
        XCTAssertEqual(result.items.map(\.name), ["Goblet Squat"])
        XCTAssertEqual(result.items.first?.draftDefaults?.sets, 3)
        XCTAssertTrue(result.note?.contains("сохранённых шаблонов") == true)
    }

    func testRepositoryKeepsOfficialEmptyCatalogResponseWithoutTemplateFallback() async throws {
        let store = try makeStore()
        await store.saveTemplate(
            WorkoutTemplateDraft(
                id: "template-1",
                userSub: "u1",
                name: "Saved Lower",
                exercises: [
                    TemplateExerciseDraft(id: "exercise-1", name: "Goblet Squat", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90),
                ],
                updatedAt: Date(),
            ),
        )

        let repository = BackendExerciseCatalogRepository(
            apiClient: MockExerciseCatalogAPIClient(
                searchResult: .success(
                    APIPagedExerciseResponse(
                        content: [],
                        metadata: PageMetadata(page: 0, size: 20, totalElements: 0, totalPages: 0),
                    ),
                ),
            ),
            userSub: "u1",
            trainingStore: store,
        )

        let result = await repository.search(query: ExerciseCatalogQuery(search: "squat"))

        XCTAssertEqual(result.source, .athleteCatalog)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.state, .empty(message: "По вашему запросу упражнения не найдены."))
        XCTAssertNil(result.note)
    }

    func testRepositoryReturnsUnavailableWithoutBackendOrSavedTemplateFallback() async throws {
        let repository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: "u1",
            trainingStore: try makeStore(),
        )

        let result = await repository.search(query: ExerciseCatalogQuery(search: "squat"))

        XCTAssertEqual(result.source, .savedTemplates)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(
            result.state,
            .unavailable(message: "Каталог упражнений пока недоступен. Можно редактировать уже добавленные упражнения и сохранять свои шаблоны."),
        )
    }

    private func makeStore() throws -> LocalTrainingStore {
        let suite = "fitfluence.tests.exercise-catalog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return LocalTrainingStore(defaults: defaults)
    }
}

private struct MockExerciseCatalogAPIClient: ExerciseCatalogAPIClientProtocol {
    let searchResult: Result<APIPagedExerciseResponse, APIError>
    let metadataResult: Result<APIAthleteExerciseCatalogMetadataResponse, APIError>

    init(
        searchResult: Result<APIPagedExerciseResponse, APIError>,
        metadataResult: Result<APIAthleteExerciseCatalogMetadataResponse, APIError> = .failure(.unknown),
    ) {
        self.searchResult = searchResult
        self.metadataResult = metadataResult
    }

    func searchAthleteExercises(request _: APIExercisesSearchRequest?) async -> Result<APIPagedExerciseResponse, APIError> {
        searchResult
    }

    func athleteExerciseCatalogMetadata() async -> Result<APIAthleteExerciseCatalogMetadataResponse, APIError> {
        metadataResult
    }
}
