@testable import FitfluenceApp
import XCTest

final class ExercisePickerFeatureTests: XCTestCase {
    func testTrainingStoreSuggestionsProviderBuildsRecentAndTemplateSections() async throws {
        let suite = "fitfluence.tests.exercise-picker.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let now = calendar.startOfDay(for: Date())
        let recentDay = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let futureDay = calendar.date(byAdding: .day, value: 2, to: now) ?? now

        let template = WorkoutTemplateDraft(
            id: "template-1",
            userSub: "u1",
            name: "Upper",
            exercises: [
                TemplateExerciseDraft(id: "ex-shared", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
                TemplateExerciseDraft(id: "ex-template", name: "Тяга верхнего блока", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90),
            ],
            updatedAt: recentDay,
        )

        let recentWorkout = WorkoutDetailsModel.quickWorkout(
            title: "Recent",
            exercises: [
                WorkoutExercise(
                    id: "ex-recent",
                    name: "Присед",
                    sets: 4,
                    repsMin: 5,
                    repsMax: 8,
                    targetRpe: nil,
                    restSeconds: 150,
                    notes: nil,
                    orderIndex: 0,
                ),
                WorkoutExercise(
                    id: "ex-shared",
                    name: "Жим лёжа",
                    sets: 4,
                    repsMin: 5,
                    repsMax: 8,
                    targetRpe: nil,
                    restSeconds: 120,
                    notes: nil,
                    orderIndex: 1,
                ),
            ],
        )

        let futureWorkout = WorkoutDetailsModel.quickWorkout(
            title: "Future",
            exercises: [
                WorkoutExercise(
                    id: "ex-future",
                    name: "Планка",
                    sets: 3,
                    repsMin: 1,
                    repsMax: 1,
                    targetRpe: nil,
                    restSeconds: 60,
                    notes: nil,
                    orderIndex: 0,
                ),
            ],
        )

        await store.saveTemplate(template)
        await store.schedule(
            TrainingDayPlan(
                id: "plan-recent",
                userSub: "u1",
                day: recentDay,
                status: .completed,
                programId: nil,
                programTitle: nil,
                workoutId: "w-recent",
                title: "Recent",
                source: .freestyle,
                workoutDetails: recentWorkout,
            ),
        )
        await store.schedule(
            TrainingDayPlan(
                id: "plan-future",
                userSub: "u1",
                day: futureDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: "w-future",
                title: "Future",
                source: .freestyle,
                workoutDetails: futureWorkout,
            ),
        )

        let provider = TrainingStoreExercisePickerSuggestionsProvider(
            userSub: "u1",
            trainingStore: store,
            calendar: calendar,
        )

        let snapshot = await provider.loadSuggestions()

        XCTAssertEqual(snapshot.sections.map(\.kind), [.recent, .templates])
        XCTAssertEqual(snapshot.sections[0].items.map(\.id), ["ex-recent", "ex-shared"])
        XCTAssertEqual(snapshot.sections[1].items.map(\.id), ["ex-template"])
        XCTAssertEqual(snapshot.contractGaps, [])
    }

    func testTrainingStoreSuggestionsProviderPrefersBackendRecentExercisesFeed() async throws {
        let suite = "fitfluence.tests.exercise-picker.remote.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalTrainingStore(defaults: defaults)
        let template = WorkoutTemplateDraft(
            id: "template-1",
            userSub: "u1",
            name: "Upper",
            exercises: [
                TemplateExerciseDraft(id: "ex-template", name: "Тяга верхнего блока", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90),
            ],
            updatedAt: Date(),
        )
        await store.saveTemplate(template)

        let provider = TrainingStoreExercisePickerSuggestionsProvider(
            userSub: "u1",
            athleteTrainingClient: StubAthleteTrainingClient(
                recentExercisesResult: .success(
                    AthleteRecentExercisesResponse(
                        entries: [
                            AthleteRecentExerciseEntry(
                                exercise: AthleteExerciseBrief(
                                    id: "ex-remote-1",
                                    code: "back-squat",
                                    name: "Присед",
                                    description: "Со штангой",
                                    isBodyweight: false,
                                    equipment: nil,
                                    media: nil,
                                ),
                                lastUsedAt: "2026-03-18T10:00:00Z",
                                usageCount: 5,
                            ),
                            AthleteRecentExerciseEntry(
                                exercise: AthleteExerciseBrief(
                                    id: "ex-remote-2",
                                    code: "bench-press",
                                    name: "Жим лёжа",
                                    description: nil,
                                    isBodyweight: false,
                                    equipment: nil,
                                    media: nil,
                                ),
                                lastUsedAt: "2026-03-16T10:00:00Z",
                                usageCount: 3,
                            ),
                        ],
                    ),
                ),
            ),
            templateRepository: LocalWorkoutTemplateRepository(trainingStore: store),
            trainingStore: store,
        )

        let snapshot = await provider.loadSuggestions()

        XCTAssertEqual(snapshot.sections.map(\.kind), [.recent, .templates])
        XCTAssertEqual(snapshot.sections[0].items.map(\.id), ["ex-remote-1", "ex-remote-2"])
        XCTAssertEqual(snapshot.sections[1].items.map(\.id), ["ex-template"])
        XCTAssertEqual(snapshot.contractGaps, [])
    }

    @MainActor
    func testViewModelBuildsCatalogQueryFromSearchAndFilters() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
            ],
            metadata: ExerciseCatalogMetadata(
                muscles: [
                    ExerciseCatalogMuscle(
                        id: "muscle-chest",
                        code: "chest",
                        name: "Грудь",
                        muscleGroup: .chest,
                        description: nil,
                        media: nil,
                    ),
                ],
                equipment: [
                    ExerciseCatalogEquipment(
                        id: "equipment-barbell",
                        code: "barbell",
                        name: "Штанга",
                        category: .freeWeight,
                        description: nil,
                        media: nil,
                    ),
                ],
                muscleGroups: [.chest],
                equipmentCategories: [.freeWeight],
                movementPatterns: [.push],
                difficultyLevels: [.beginner],
            ),
        )

        let viewModel = ExercisePickerViewModel(
            repository: repository,
            suggestionsProvider: StubExercisePickerSuggestionsProvider(snapshot: .empty),
        )

        await viewModel.onAppear()
        viewModel.searchText = "жим"
        await viewModel.toggleMuscleGroup(.chest)
        await viewModel.toggleMuscleGroup(.shoulders)
        await viewModel.toggleEquipment(viewModel.catalogMetadata.equipment.first!)
        await viewModel.toggleMovementPattern(.push)
        await viewModel.toggleDifficulty(.beginner)

        let lastQuery = await repository.lastQuery
        XCTAssertEqual(lastQuery?.search, "жим")
        XCTAssertEqual(lastQuery?.muscleGroups, [.chest, .shoulders])
        XCTAssertEqual(lastQuery?.equipmentIds, ["equipment-barbell"])
        XCTAssertEqual(lastQuery?.movementPattern, .push)
        XCTAssertEqual(lastQuery?.difficultyLevel, .beginner)
    }

    @MainActor
    func testViewModelBuildsCatalogQueryWithMultipleEquipmentFilters() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
                .content(items: [makeCatalogItem(id: "ex-1", name: "Жим лёжа")]),
            ],
            metadata: ExerciseCatalogMetadata(
                muscles: [],
                equipment: [
                    makeEquipment(id: "equipment-barbell", name: "Штанга"),
                    makeEquipment(id: "equipment-dumbbell", name: "Гантели"),
                ],
                muscleGroups: [],
                equipmentCategories: [.freeWeight],
                movementPatterns: [],
                difficultyLevels: [],
            ),
        )
        let viewModel = ExercisePickerViewModel(repository: repository)

        await viewModel.onAppear()
        await viewModel.toggleEquipment(makeEquipment(id: "equipment-barbell", name: "Штанга"))
        await viewModel.toggleEquipment(makeEquipment(id: "equipment-dumbbell", name: "Гантели"))

        let lastQuery = await repository.lastQuery
        XCTAssertEqual(Set(lastQuery?.equipmentIds ?? []), Set(["equipment-barbell", "equipment-dumbbell"]))
    }

    @MainActor
    func testViewModelAppliesMultiSelectMovementAndDifficultyLocally() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(
                    items: [
                        makeCatalogItem(id: "ex-push", name: "Жим лёжа", movementPattern: .push, difficultyLevel: .beginner),
                        makeCatalogItem(id: "ex-pull", name: "Тяга блока", movementPattern: .pull, difficultyLevel: .intermediate),
                        makeCatalogItem(id: "ex-hinge", name: "Румынская тяга", movementPattern: .hinge, difficultyLevel: .advanced),
                    ]
                ),
                .content(
                    items: [
                        makeCatalogItem(id: "ex-push", name: "Жим лёжа", movementPattern: .push, difficultyLevel: .beginner),
                        makeCatalogItem(id: "ex-pull", name: "Тяга блока", movementPattern: .pull, difficultyLevel: .intermediate),
                        makeCatalogItem(id: "ex-hinge", name: "Румынская тяга", movementPattern: .hinge, difficultyLevel: .advanced),
                    ]
                ),
                .content(
                    items: [
                        makeCatalogItem(id: "ex-push", name: "Жим лёжа", movementPattern: .push, difficultyLevel: .beginner),
                        makeCatalogItem(id: "ex-pull", name: "Тяга блока", movementPattern: .pull, difficultyLevel: .intermediate),
                        makeCatalogItem(id: "ex-hinge", name: "Румынская тяга", movementPattern: .hinge, difficultyLevel: .advanced),
                    ]
                ),
            ],
        )
        let viewModel = ExercisePickerViewModel(repository: repository)

        await viewModel.onAppear()
        await viewModel.toggleMovementPattern(.push)
        await viewModel.toggleMovementPattern(.pull)
        await viewModel.toggleDifficulty(.beginner)
        await viewModel.toggleDifficulty(.intermediate)

        let resultIDs = viewModel.visibleSections.flatMap(\.items).map(\.id)
        let lastQuery = await repository.lastQuery

        XCTAssertEqual(Set(resultIDs), Set(["ex-push", "ex-pull"]))
        XCTAssertNil(lastQuery?.movementPattern)
        XCTAssertNil(lastQuery?.difficultyLevel)
    }

    @MainActor
    func testViewModelContextualEquipmentUsesAllSelectedMuscleGroups() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(
                    items: [
                        makeCatalogItem(
                            id: "ex-chest",
                            name: "Жим лёжа",
                            muscleGroups: [.chest],
                            equipment: [makeEquipment(id: "equipment-barbell", name: "Штанга")]
                        ),
                        makeCatalogItem(
                            id: "ex-shoulders",
                            name: "Жим гантелей сидя",
                            muscleGroups: [.shoulders],
                            equipment: [makeEquipment(id: "equipment-dumbbell", name: "Гантели")]
                        ),
                        makeCatalogItem(
                            id: "ex-legs",
                            name: "Жим ногами",
                            muscleGroups: [.legs],
                            equipment: [makeEquipment(id: "equipment-leg-press", name: "Тренажёр для жима ногами")]
                        ),
                    ]
                ),
            ],
        )
        let viewModel = ExercisePickerViewModel(repository: repository)

        let options = await viewModel.contextualFilterOptions(
            for: ExercisePickerViewModel.FilterState(muscleGroups: [.chest, .shoulders])
        )

        XCTAssertEqual(Set(options.equipment.map(\.id)), Set(["equipment-barbell", "equipment-dumbbell"]))
    }

    @MainActor
    func testViewModelContextualFiltersUseAllSelectedMuscleGroups() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(
                    items: [
                        makeCatalogItem(
                            id: "ex-arms",
                            name: "Сгибание рук с гантелями",
                            movementPattern: .pull,
                            difficultyLevel: .beginner,
                            muscleGroups: [.arms],
                            equipment: [makeEquipment(id: "equipment-dumbbell", name: "Гантели")]
                        ),
                        makeCatalogItem(
                            id: "ex-legs",
                            name: "Присед со штангой",
                            movementPattern: .squat,
                            difficultyLevel: .intermediate,
                            muscleGroups: [.legs],
                            equipment: [makeEquipment(id: "equipment-barbell", name: "Штанга")]
                        ),
                        makeCatalogItem(
                            id: "ex-back",
                            name: "Тяга верхнего блока",
                            movementPattern: .pull,
                            difficultyLevel: .advanced,
                            muscleGroups: [.back],
                            equipment: [makeEquipment(id: "equipment-cable", name: "Блочный тренажёр")]
                        ),
                    ]
                ),
            ],
        )
        let viewModel = ExercisePickerViewModel(repository: repository)
        let filters = ExercisePickerViewModel.FilterState(muscleGroups: [.arms, .legs])

        let options = await viewModel.contextualFilterOptions(for: filters)

        XCTAssertEqual(Set(options.equipment.map(\.id)), Set(["equipment-dumbbell", "equipment-barbell"]))
        XCTAssertEqual(Set(options.movementPatterns), Set([.pull, .squat]))
        XCTAssertEqual(Set(options.difficultyLevels), Set([.beginner, .intermediate]))
    }

    @MainActor
    func testViewModelShowsLocalMatchesWhenCatalogIsUnavailable() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .unavailable(message: "Нет сети"),
                .unavailable(message: "Нет сети"),
            ],
        )
        let snapshot = ExercisePickerSuggestionsSnapshot(
            sections: [
                ExercisePickerSection(
                    kind: .templates,
                    title: "Из шаблонов",
                    subtitle: nil,
                    items: [makeCatalogItem(id: "ex-squat", name: "Присед")],
                ),
            ],
            contractGaps: [],
        )

        let viewModel = ExercisePickerViewModel(
            repository: repository,
            suggestionsProvider: StubExercisePickerSuggestionsProvider(snapshot: snapshot),
        )

        await viewModel.onAppear()
        viewModel.searchText = "присед"
        await viewModel.refreshCatalog()

        XCTAssertEqual(viewModel.visibleSections.map(\.kind), [.localMatches])
        XCTAssertEqual(viewModel.visibleSections.first?.items.map(\.id), ["ex-squat"])
        XCTAssertEqual(viewModel.statusMessage, "Нет сети")
    }

    @MainActor
    func testViewModelAppliesPlanningContextToCatalogQuery() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(items: [makeCatalogItem(id: "ex-bench", name: "Жим лёжа", muscleGroups: [.chest])]),
            ],
        )
        let viewModel = ExercisePickerViewModel(
            repository: repository,
            suggestionsProvider: StubExercisePickerSuggestionsProvider(snapshot: .empty),
            context: ExercisePickerViewModel.Context(
                title: "Контекст тренировки",
                muscleGroups: [.chest, .shoulders],
                equipmentIDs: ["equipment-barbell", "equipment-bench"],
                equipmentNames: ["Штанга", "Скамья"],
            ),
        )

        await viewModel.onAppear()

        let lastQuery = await repository.lastQuery
        XCTAssertEqual(lastQuery?.muscleGroups, [.chest, .shoulders])
        XCTAssertEqual(lastQuery?.equipmentIds, ["equipment-barbell", "equipment-bench"])
        XCTAssertTrue(viewModel.isContextualBrowsing)
        XCTAssertEqual(viewModel.contextChips, ["Грудь", "Плечи", "Штанга", "Скамья"])
    }

    @MainActor
    func testViewModelLoadsNextCatalogPageWhenLastVisibleItemAppears() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(
                    items: [
                        makeCatalogItem(id: "ex-1", name: "Жим лёжа"),
                        makeCatalogItem(id: "ex-2", name: "Тяга блока"),
                    ],
                    metadata: PageMetadata(page: 0, size: 2, totalElements: 4, totalPages: 2)
                ),
                .content(
                    items: [
                        makeCatalogItem(id: "ex-3", name: "Присед"),
                        makeCatalogItem(id: "ex-4", name: "Выпады"),
                    ],
                    metadata: PageMetadata(page: 1, size: 2, totalElements: 4, totalPages: 2)
                ),
            ],
        )
        let viewModel = ExercisePickerViewModel(repository: repository)

        await viewModel.onAppear()
        await viewModel.loadNextCatalogPageIfNeeded(currentItemID: "ex-2")

        XCTAssertEqual(viewModel.visibleSections.first?.items.map(\.id), ["ex-1", "ex-2", "ex-3", "ex-4"])
        XCTAssertEqual(viewModel.catalogResultsBadgeCount, 4)

        let queries = await repository.queries
        XCTAssertEqual(queries.map(\.page), [0, 1])
    }

    @MainActor
    func testViewModelContinuesPaginationAcrossNonMatchingPagesForClientSideFilters() async {
        let repository = StubExerciseCatalogRepository(
            results: [
                .content(
                    items: [
                        makeCatalogItem(id: "ex-push", name: "Жим лёжа", movementPattern: .push),
                    ],
                    metadata: PageMetadata(page: 0, size: 1, totalElements: 3, totalPages: 3)
                ),
                .content(
                    items: [
                        makeCatalogItem(id: "ex-hinge", name: "Румынская тяга", movementPattern: .hinge),
                    ],
                    metadata: PageMetadata(page: 1, size: 1, totalElements: 3, totalPages: 3)
                ),
                .content(
                    items: [
                        makeCatalogItem(id: "ex-pull", name: "Тяга верхнего блока", movementPattern: .pull),
                    ],
                    metadata: PageMetadata(page: 2, size: 1, totalElements: 3, totalPages: 3)
                ),
            ],
        )
        let viewModel = ExercisePickerViewModel(repository: repository)

        await viewModel.onAppear()
        viewModel.filters = ExercisePickerViewModel.FilterState(
            movementPatterns: [.push, .pull]
        )

        await viewModel.loadNextCatalogPageIfNeeded(currentItemID: "ex-push")

        XCTAssertEqual(viewModel.visibleSections.first?.items.map(\.id), ["ex-push", "ex-pull"])
        XCTAssertEqual(viewModel.catalogResultsBadgeCount, 2)

        let queries = await repository.queries
        XCTAssertEqual(queries.map(\.page), [0, 1, 2])
    }
}

private actor StubExerciseCatalogRepository: ExerciseCatalogRepository {
    private var recordedQueries: [ExerciseCatalogQuery] = []
    private var queuedResults: [ExerciseCatalogResult]
    private let fallbackResult: ExerciseCatalogResult
    private let metadataResult: ExerciseCatalogMetadata

    init(results: [ExerciseCatalogResult], metadata: ExerciseCatalogMetadata = .empty) {
        queuedResults = results
        fallbackResult = results.last ?? .content(items: [])
        metadataResult = metadata
    }

    func search(query: ExerciseCatalogQuery) async -> ExerciseCatalogResult {
        recordedQueries.append(query)
        if !queuedResults.isEmpty {
            return queuedResults.removeFirst()
        }
        return fallbackResult
    }

    var lastQuery: ExerciseCatalogQuery? {
        recordedQueries.last
    }

    var queries: [ExerciseCatalogQuery] {
        recordedQueries
    }

    func metadata() async -> ExerciseCatalogMetadata {
        metadataResult
    }
}

private struct StubExercisePickerSuggestionsProvider: ExercisePickerSuggestionsProviding {
    let snapshot: ExercisePickerSuggestionsSnapshot

    func loadSuggestions() async -> ExercisePickerSuggestionsSnapshot {
        snapshot
    }
}

private struct StubAthleteTrainingClient: AthleteTrainingClientProtocol {
    let recentExercisesResult: Result<AthleteRecentExercisesResponse, APIError>

    func recentExercises(limit _: Int?) async -> Result<AthleteRecentExercisesResponse, APIError> {
        recentExercisesResult
    }
}

private func makeCatalogItem(
    id: String,
    name: String,
    movementPattern: ExerciseCatalogMovementPattern? = nil,
    difficultyLevel: ExerciseCatalogDifficultyLevel? = nil,
    muscleGroups: [ExerciseCatalogMuscleGroup] = [],
    equipment: [ExerciseCatalogEquipment] = [],
) -> ExerciseCatalogItem {
    ExerciseCatalogItem(
        id: id,
        code: nil,
        name: name,
        description: nil,
        movementPattern: movementPattern,
        difficultyLevel: difficultyLevel,
        isBodyweight: false,
        muscles: muscleGroups.enumerated().map { index, group in
            ExerciseCatalogMuscle(
                id: "muscle-\(index)-\(id)",
                code: "muscle-\(index)",
                name: group.rawValue,
                muscleGroup: group,
                description: nil,
                media: nil,
            )
        },
        equipment: equipment,
        media: [],
        source: .athleteCatalog,
        draftDefaults: nil,
    )
}

private func makeEquipment(id: String, name: String) -> ExerciseCatalogEquipment {
    ExerciseCatalogEquipment(
        id: id,
        code: id,
        name: name,
        category: .freeWeight,
        description: nil,
        media: nil,
    )
}

private extension ExerciseCatalogResult {
    static func content(items: [ExerciseCatalogItem], metadata: PageMetadata? = nil) -> ExerciseCatalogResult {
        ExerciseCatalogResult(
            items: items,
            metadata: metadata,
            state: .content,
            source: .athleteCatalog,
            note: nil,
            contractGaps: [],
        )
    }

    static func unavailable(message: String) -> ExerciseCatalogResult {
        ExerciseCatalogResult(
            items: [],
            metadata: nil,
            state: .unavailable(message: message),
            source: .athleteCatalog,
            note: nil,
            contractGaps: [],
        )
    }
}
