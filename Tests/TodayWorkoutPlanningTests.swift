@testable import FitfluenceApp
import XCTest

@MainActor
final class TodayWorkoutPlanningTests: XCTestCase {
    func testPlanningRequestRequiresMusclesAndDuration() {
        var request = TodayWorkoutPlanningRequest()

        XCTAssertFalse(request.canBuild)

        request.toggleMuscleGroup(.back)
        XCTAssertFalse(request.canBuild)

        request.setDurationForTest(45)
        XCTAssertTrue(request.canBuild)

        request.toggleEquipment(id: "eq-1")
        XCTAssertTrue(request.availableEquipmentIDs.contains("eq-1"))

        request.toggleMuscleGroup(.back)
        XCTAssertFalse(request.canBuild)
    }

    func testPlanningViewModelLoadsCatalogAndUpdatesSelections() async {
        let snapshot = TodayWorkoutPlanningCatalogSnapshot(
            equipmentOptions: [
                TodayWorkoutPlanningEquipmentOption(id: "eq-1", name: "Barbell", category: .freeWeight),
                TodayWorkoutPlanningEquipmentOption(id: "eq-2", name: "Bench", category: .machine),
            ],
            allEquipmentOptions: [
                TodayWorkoutPlanningEquipmentOption(id: "eq-1", name: "Barbell", category: .freeWeight),
                TodayWorkoutPlanningEquipmentOption(id: "eq-2", name: "Bench", category: .machine),
            ],
            note: "Catalog loaded",
            contractGaps: ["gap-1"],
            isCatalogAvailable: true,
        )
        let provider = StubTodayWorkoutPlanningProvider(snapshot: snapshot, seed: nil)
        let viewModel = TodayWorkoutPlanningViewModel(provider: provider)

        await viewModel.onAppear()
        viewModel.toggleMuscleGroup(.chest)
        viewModel.toggleEquipment(id: "eq-1")
        viewModel.setDuration(35)
        viewModel.setFocus(.hypertrophy)

        XCTAssertEqual(viewModel.catalogSnapshot.equipmentOptions.count, 2)
        XCTAssertEqual(viewModel.catalogSnapshot.note, "Catalog loaded")
        XCTAssertEqual(viewModel.request.targetMuscleGroups, [.chest])
        XCTAssertEqual(viewModel.request.availableEquipmentIDs, ["eq-1"])
        XCTAssertEqual(viewModel.request.desiredDurationMinutes, 35)
        XCTAssertEqual(viewModel.request.focus, .hypertrophy)
        XCTAssertTrue(viewModel.request.canBuild)
    }

    func testPlanningServiceBuildsStarterDraftUsingCatalogFilters() async {
        let repository = StubPlanningExerciseCatalogRepository(
            items: [
                makeCatalogItem(
                    id: "ex-bench",
                    name: "Bench Press",
                    equipment: [makeEquipment(id: "eq-barbell", name: "Barbell")],
                    muscleGroups: [.chest],
                ),
                makeCatalogItem(
                    id: "ex-row",
                    name: "Chest Supported Row",
                    equipment: [makeEquipment(id: "eq-bench", name: "Bench")],
                    muscleGroups: [.back],
                ),
                makeCatalogItem(
                    id: "ex-fly",
                    name: "Cable Fly",
                    equipment: [makeEquipment(id: "eq-cable", name: "Cable")],
                    muscleGroups: [.chest],
                ),
            ],
            metadata: ExerciseCatalogMetadata(
                muscles: [],
                equipment: [
                    makeEquipment(id: "eq-barbell", name: "Barbell"),
                    makeEquipment(id: "eq-bench", name: "Bench"),
                    makeEquipment(id: "eq-cable", name: "Cable"),
                ],
                muscleGroups: [],
                equipmentCategories: [.freeWeight, .machine],
                movementPatterns: [],
                difficultyLevels: [],
            ),
        )
        let service = TodayWorkoutPlanningService(repository: repository)
        let snapshot = await service.loadCatalogSnapshot(for: .init())

        var request = TodayWorkoutPlanningRequest()
        request.toggleMuscleGroup(.chest)
        request.setDurationForTest(45)
        request.focus = .strength
        request.toggleEquipment(id: "eq-barbell")

        let seed = await service.buildDraftSeed(for: request, snapshot: snapshot)
        let lastQuery = await repository.lastQuery

        XCTAssertEqual(lastQuery?.muscleGroups, [.chest])
        XCTAssertEqual(lastQuery?.equipmentIds, ["eq-barbell"])
        XCTAssertEqual(seed.exercises.map(\.id), ["ex-bench"])
        XCTAssertEqual(seed.exercises.first?.sets, 5)
        XCTAssertEqual(seed.exercises.first?.repsMin, 4)
        XCTAssertEqual(seed.exercises.first?.restSeconds, 150)
        XCTAssertEqual(seed.selectedEquipmentNames, ["Barbell"])
        XCTAssertTrue(seed.generationSummary.contains("Собрано"))
        XCTAssertFalse(seed.generationAppliedRules.isEmpty)
        XCTAssertTrue(seed.isCatalogBacked)
    }

    func testPlanningServiceLoadsEquipmentFromDerivedCatalogMetadata() async {
        let repository = StubPlanningExerciseCatalogRepository(
            items: [
                makeCatalogItem(
                    id: "ex-bench",
                    name: "Bench Press",
                    equipment: [
                        makeEquipment(id: "eq-barbell", name: "Barbell"),
                        makeEquipment(id: "eq-bench", name: "Bench"),
                    ],
                    muscleGroups: [.chest],
                ),
            ],
            metadata: .empty,
        )
        let service = TodayWorkoutPlanningService(repository: repository)

        let snapshot = await service.loadCatalogSnapshot(for: .init())

        XCTAssertEqual(snapshot.equipmentOptions.map(\.name), ["Barbell", "Bench"])
        XCTAssertEqual(snapshot.allEquipmentOptions.map(\.name), ["Barbell", "Bench"])
        XCTAssertNil(snapshot.note)
        XCTAssertTrue(snapshot.contractGaps.isEmpty)
        XCTAssertTrue(snapshot.isCatalogAvailable)
    }

    func testPlanningServiceReturnsDegradedDraftWhenEquipmentFilterEliminatesCatalog() async {
        let repository = StubPlanningExerciseCatalogRepository(
            items: [
                makeCatalogItem(
                    id: "ex-squat",
                    name: "Goblet Squat",
                    equipment: [makeEquipment(id: "eq-dumbbells", name: "Dumbbells")],
                    muscleGroups: [.legs],
                ),
            ],
            metadata: ExerciseCatalogMetadata(
                muscles: [],
                equipment: [makeEquipment(id: "eq-dumbbells", name: "Dumbbells")],
                muscleGroups: [],
                equipmentCategories: [.freeWeight],
                movementPatterns: [],
                difficultyLevels: [],
            ),
        )
        let service = TodayWorkoutPlanningService(repository: repository)
        let snapshot = await service.loadCatalogSnapshot(for: .init())

        var request = TodayWorkoutPlanningRequest()
        request.toggleMuscleGroup(.legs)
        request.toggleEquipment(id: "eq-barbell")
        request.setDurationForTest(25)

        let seed = await service.buildDraftSeed(for: request, snapshot: snapshot)

        XCTAssertTrue(seed.exercises.isEmpty)
        XCTAssertTrue(seed.isDegraded)
        XCTAssertTrue(seed.generationSummary.contains("оборудованию"))
        XCTAssertFalse(seed.generationWarnings.isEmpty)
    }

    func testPlanningServiceDerivesContextualEquipmentFromSelectedMuscles() async {
        let repository = StubPlanningExerciseCatalogRepository(
            items: [
                makeCatalogItem(
                    id: "ex-bench",
                    name: "Bench Press",
                    equipment: [
                        makeEquipment(id: "eq-barbell", name: "Barbell"),
                        makeEquipment(id: "eq-bench", name: "Bench"),
                    ],
                    muscleGroups: [.chest],
                ),
                makeCatalogItem(
                    id: "ex-leg-press",
                    name: "Leg Press",
                    equipment: [
                        makeEquipment(id: "eq-leg-press", name: "Leg Press Machine"),
                    ],
                    muscleGroups: [.legs],
                ),
            ],
            metadata: ExerciseCatalogMetadata(
                muscles: [],
                equipment: [
                    makeEquipment(id: "eq-barbell", name: "Barbell"),
                    makeEquipment(id: "eq-bench", name: "Bench"),
                    makeEquipment(id: "eq-leg-press", name: "Leg Press Machine"),
                ],
                muscleGroups: [],
                equipmentCategories: [.freeWeight, .machine],
                movementPatterns: [],
                difficultyLevels: [],
            ),
        )
        let service = TodayWorkoutPlanningService(repository: repository)
        let request = TodayWorkoutPlanningRequest(targetMuscleGroups: [.chest])

        let snapshot = await service.loadCatalogSnapshot(for: request)

        XCTAssertEqual(snapshot.equipmentOptions.map(\.name), ["Barbell", "Bench"])
        XCTAssertEqual(snapshot.allEquipmentOptions.map(\.name), ["Barbell", "Bench", "Leg Press Machine"])
    }

    func testPlanningDraftSeedBuildsLaunchableWorkoutHandoff() async {
        let seed = TodayWorkoutPlanningDraftSeed(
            request: TodayWorkoutPlanningRequest(
                targetMuscleGroups: [.back, .shoulders],
                availableEquipmentIDs: ["eq-1"],
                desiredDurationMinutes: 35,
                focus: .hypertrophy,
            ),
            equipmentOptions: [
                TodayWorkoutPlanningEquipmentOption(id: "eq-1", name: "Dumbbells", category: .freeWeight),
            ],
            exercises: [
                WorkoutCompositionExerciseDraft(
                    id: "ex-row",
                    name: "One Arm Row",
                    sets: 4,
                    repsMin: 8,
                    repsMax: 12,
                    targetRpe: 8,
                    restSeconds: 90,
                    notes: nil,
                ),
            ],
            explanation: TodayWorkoutDraftExplanation(
                summary: "Собрано 1 упражнение и около 4 рабочих подходов под 35 мин.",
                appliedRules: ["Сначала отфильтровали упражнения по выбранным мышцам и оборудованию."],
                warnings: [],
            ),
            matchedMuscleGroups: [.back],
            missingMuscleGroups: [.shoulders],
            coveredMovementPatterns: [.pull],
            targetExerciseCount: 4,
            targetWorkingSets: 4,
            note: nil,
            contractGaps: [],
            isCatalogBacked: true,
            isDegraded: false,
        )

        let workout = seed.draft.asWorkoutDetailsModel(
            workoutID: "planning-1",
            fallbackTitle: seed.suggestedTitle,
            dayOrder: 0,
            coachNote: seed.coachNote,
        )

        XCTAssertEqual(workout.title, seed.suggestedTitle)
        XCTAssertEqual(workout.coachNote, seed.coachNote)
        XCTAssertEqual(workout.exercises.first?.name, "One Arm Row")
        XCTAssertTrue(seed.summaryLine.contains("35 мин"))
        XCTAssertTrue(seed.summaryLine.contains("Dumbbells"))
    }
}

private actor StubPlanningExerciseCatalogRepository: ExerciseCatalogRepository {
    private let items: [ExerciseCatalogItem]
    private let catalogMetadata: ExerciseCatalogMetadata
    private var queries: [ExerciseCatalogQuery] = []

    init(items: [ExerciseCatalogItem], metadata: ExerciseCatalogMetadata = .empty) {
        self.items = items
        catalogMetadata = metadata
    }

    func search(query: ExerciseCatalogQuery) async -> ExerciseCatalogResult {
        queries.append(query)

        let filtered = items.filter { item in
            let matchesMuscle = query.muscleGroups.isEmpty || item.muscles.contains(where: { muscle in
                guard let group = muscle.muscleGroup else { return false }
                return query.muscleGroups.contains(group)
            })
            let matchesEquipment = query.equipmentIds.isEmpty || item.equipment.contains(where: { equipment in
                query.equipmentIds.contains(equipment.id)
            })
            return matchesMuscle && matchesEquipment
        }

        return ExerciseCatalogResult(
            items: filtered,
            metadata: nil,
            state: .content,
            source: .athleteCatalog,
            note: nil,
            contractGaps: [],
        )
    }

    var lastQuery: ExerciseCatalogQuery? {
        queries.last
    }

    func metadata() async -> ExerciseCatalogMetadata {
        if !catalogMetadata.equipment.isEmpty || !catalogMetadata.muscles.isEmpty {
            return catalogMetadata
        }
        return ExerciseCatalogMetadata.derived(from: items)
    }
}

private struct StubTodayWorkoutPlanningProvider: TodayWorkoutPlanningProviding {
    let snapshot: TodayWorkoutPlanningCatalogSnapshot
    let seed: TodayWorkoutPlanningDraftSeed?

    func loadCatalogSnapshot(
        for _: TodayWorkoutPlanningRequest
    ) async -> TodayWorkoutPlanningCatalogSnapshot {
        snapshot
    }

    func buildDraftSeed(
        for request: TodayWorkoutPlanningRequest,
        snapshot: TodayWorkoutPlanningCatalogSnapshot
    ) async -> TodayWorkoutPlanningDraftSeed {
        seed ?? TodayWorkoutPlanningDraftSeed(
            request: request,
            equipmentOptions: snapshot.equipmentOptions,
            exercises: [],
            explanation: TodayWorkoutDraftExplanation(
                summary: "Каталог не смог честно собрать стартовую тренировку под текущие параметры.",
                appliedRules: ["Сначала попытались отфильтровать каталог по выбранным мышцам и оборудованию."],
                warnings: ["Оставили builder в рабочем состоянии без фейкового наполнения."],
            ),
            matchedMuscleGroups: [],
            missingMuscleGroups: request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder }),
            coveredMovementPatterns: [],
            targetExerciseCount: request.suggestedExerciseCount,
            targetWorkingSets: request.suggestedExerciseCount * 3,
            note: snapshot.note,
            contractGaps: snapshot.contractGaps,
            isCatalogBacked: snapshot.isCatalogAvailable,
            isDegraded: true,
        )
    }
}

private func makeCatalogItem(
    id: String,
    name: String,
    equipment: [ExerciseCatalogEquipment],
    muscleGroups: [ExerciseCatalogMuscleGroup],
    movementPattern: ExerciseCatalogMovementPattern? = nil,
    difficultyLevel: ExerciseCatalogDifficultyLevel? = nil
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
                code: "muscle-\(index)-\(id)",
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

private extension TodayWorkoutPlanningRequest {
    mutating func setDurationForTest(_ minutes: Int) {
        desiredDurationMinutes = minutes
    }
}
