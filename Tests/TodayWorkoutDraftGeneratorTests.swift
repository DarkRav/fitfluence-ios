@testable import FitfluenceApp
import XCTest

final class TodayWorkoutDraftGeneratorTests: XCTestCase {
    func testGeneratorFiltersByMuscleAndEquipmentAndAvoidsDuplicates() {
        let generator = TodayWorkoutDraftGenerator()
        let request = TodayWorkoutPlanningRequest(
            targetMuscleGroups: [.chest],
            availableEquipmentIDs: ["eq-barbell"],
            desiredDurationMinutes: 35,
            focus: nil,
        )

        let result = generator.generate(
            request: request,
            catalogItems: [
                generatorCatalogItem(
                    id: "ex-bench",
                    name: "Bench Press",
                    equipment: [generatorEquipment(id: "eq-barbell", name: "Barbell")],
                    muscleGroups: [.chest],
                    movementPattern: .push
                ),
                generatorCatalogItem(
                    id: "ex-bench",
                    name: "Bench Press Copy",
                    equipment: [generatorEquipment(id: "eq-barbell", name: "Barbell")],
                    muscleGroups: [.chest],
                    movementPattern: .push
                ),
                generatorCatalogItem(
                    id: "ex-fly",
                    name: "Cable Fly",
                    equipment: [generatorEquipment(id: "eq-cable", name: "Cable")],
                    muscleGroups: [.chest],
                    movementPattern: .push
                ),
                generatorCatalogItem(
                    id: "ex-row",
                    name: "Seated Row",
                    equipment: [generatorEquipment(id: "eq-barbell", name: "Barbell")],
                    muscleGroups: [.back],
                    movementPattern: .pull
                ),
            ],
        )

        XCTAssertEqual(result.exercises.map(\.id), ["ex-bench"])
        XCTAssertEqual(result.matchedMuscleGroups, [.chest])
        XCTAssertTrue(result.coveredMovementPatterns.contains(.push))
        XCTAssertFalse(result.isDegraded)
    }

    func testGeneratorBalancesMovementPatternsWhenMetadataExists() {
        let generator = TodayWorkoutDraftGenerator()
        let request = TodayWorkoutPlanningRequest(
            targetMuscleGroups: [.back, .legs],
            availableEquipmentIDs: [],
            desiredDurationMinutes: 60,
            focus: nil,
        )

        let result = generator.generate(
            request: request,
            catalogItems: [
                generatorCatalogItem(
                    id: "ex-row",
                    name: "Chest Supported Row",
                    equipment: [generatorEquipment(id: "eq-bench", name: "Bench")],
                    muscleGroups: [.back],
                    movementPattern: .pull
                ),
                generatorCatalogItem(
                    id: "ex-squat",
                    name: "Front Squat",
                    equipment: [generatorEquipment(id: "eq-barbell", name: "Barbell")],
                    muscleGroups: [.legs],
                    movementPattern: .squat
                ),
                generatorCatalogItem(
                    id: "ex-hinge",
                    name: "Romanian Deadlift",
                    equipment: [generatorEquipment(id: "eq-barbell", name: "Barbell")],
                    muscleGroups: [.legs, .back],
                    movementPattern: .hinge
                ),
                generatorCatalogItem(
                    id: "ex-curl",
                    name: "Leg Curl",
                    equipment: [generatorEquipment(id: "eq-machine", name: "Machine")],
                    muscleGroups: [.legs],
                    movementPattern: .other
                ),
                generatorCatalogItem(
                    id: "ex-pulldown",
                    name: "Lat Pulldown",
                    equipment: [generatorEquipment(id: "eq-cable", name: "Cable")],
                    muscleGroups: [.back],
                    movementPattern: .pull
                ),
            ],
        )

        XCTAssertEqual(Array(result.exercises.prefix(3)).map(\.id), ["ex-row", "ex-squat", "ex-hinge"])
        XCTAssertEqual(result.coveredMovementPatterns, [.pull, .squat, .hinge, .other])
        XCTAssertTrue(result.explanation.warnings.isEmpty)
    }

    func testGeneratorShapesVolumeByDuration() {
        let generator = TodayWorkoutDraftGenerator()
        let shortRequest = TodayWorkoutPlanningRequest(
            targetMuscleGroups: [.chest],
            availableEquipmentIDs: [],
            desiredDurationMinutes: 25,
            focus: .hypertrophy,
        )
        let longRequest = TodayWorkoutPlanningRequest(
            targetMuscleGroups: [.chest],
            availableEquipmentIDs: [],
            desiredDurationMinutes: 75,
            focus: .hypertrophy,
        )
        let items = [
            generatorCatalogItem(
                id: "ex-1",
                name: "Incline Press",
                equipment: [generatorEquipment(id: "eq-dumbbells", name: "Dumbbells")],
                muscleGroups: [.chest, .shoulders],
                movementPattern: .push
            ),
            generatorCatalogItem(
                id: "ex-2",
                name: "Bench Press",
                equipment: [generatorEquipment(id: "eq-barbell", name: "Barbell")],
                muscleGroups: [.chest],
                movementPattern: .push
            ),
            generatorCatalogItem(
                id: "ex-3",
                name: "Chest Fly",
                equipment: [generatorEquipment(id: "eq-cable", name: "Cable")],
                muscleGroups: [.chest],
                movementPattern: .other
            ),
            generatorCatalogItem(
                id: "ex-4",
                name: "Push Up",
                equipment: [],
                muscleGroups: [.chest, .arms],
                movementPattern: .push,
                isBodyweight: true
            ),
        ]

        let shortResult = generator.generate(request: shortRequest, catalogItems: items)
        let longResult = generator.generate(request: longRequest, catalogItems: items)

        XCTAssertLessThan(shortResult.exercises.reduce(0) { $0 + $1.sets }, longResult.exercises.reduce(0) { $0 + $1.sets })
        XCTAssertLessThan(shortResult.targetWorkingSets, longResult.targetWorkingSets)
    }

    func testGeneratorReturnsDegradedStateWhenNoCandidatesAfterFiltering() {
        let generator = TodayWorkoutDraftGenerator()
        let request = TodayWorkoutPlanningRequest(
            targetMuscleGroups: [.legs],
            availableEquipmentIDs: ["eq-barbell"],
            desiredDurationMinutes: 35,
            focus: nil,
        )

        let result = generator.generate(
            request: request,
            catalogItems: [
                generatorCatalogItem(
                    id: "ex-squat",
                    name: "Goblet Squat",
                    equipment: [generatorEquipment(id: "eq-dumbbells", name: "Dumbbells")],
                    muscleGroups: [.legs],
                    movementPattern: .squat
                ),
            ],
        )

        XCTAssertTrue(result.exercises.isEmpty)
        XCTAssertTrue(result.isDegraded)
        XCTAssertTrue(result.explanation.summary.contains("оборудованию"))
        XCTAssertFalse(result.explanation.warnings.isEmpty)
    }
}

private func generatorCatalogItem(
    id: String,
    name: String,
    equipment: [ExerciseCatalogEquipment],
    muscleGroups: [ExerciseCatalogMuscleGroup],
    movementPattern: ExerciseCatalogMovementPattern?,
    difficultyLevel: ExerciseCatalogDifficultyLevel? = nil,
    isBodyweight: Bool = false
) -> ExerciseCatalogItem {
    ExerciseCatalogItem(
        id: id,
        code: nil,
        name: name,
        description: nil,
        movementPattern: movementPattern,
        difficultyLevel: difficultyLevel,
        isBodyweight: isBodyweight,
        muscles: muscleGroups.enumerated().map { index, group in
            ExerciseCatalogMuscle(
                id: "\(id)-muscle-\(index)",
                code: "\(id)-muscle-\(index)",
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

private func generatorEquipment(
    id: String,
    name: String
) -> ExerciseCatalogEquipment {
    ExerciseCatalogEquipment(
        id: id,
        code: id,
        name: name,
        category: .freeWeight,
        description: nil,
        media: nil,
    )
}
