@testable import FitfluenceApp
import XCTest

final class TrainingStoreTests: XCTestCase {
    func testAppendHistoryUpdatesLastCompletedAndSummary() async throws {
        let suite = "fitfluence.tests.training.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalTrainingStore(defaults: defaults)
        let now = Date()
        let record = CompletedWorkoutRecord(
            id: "r1",
            userSub: "u1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Тренировка A",
            source: .program,
            startedAt: now.addingTimeInterval(-1800),
            finishedAt: now,
            durationSeconds: 1800,
            completedSets: 10,
            totalSets: 12,
            volume: 1240,
            notes: nil,
            overallRPE: 8,
        )

        await store.appendHistory(record)

        let last = await store.lastCompleted(userSub: "u1")
        XCTAssertEqual(last?.id, "r1")

        let weekStart = Calendar.current.date(from: Calendar.current.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: now,
        )) ?? now
        let summary = await store.weeklySummary(userSub: "u1", weekStart: weekStart)
        XCTAssertEqual(summary.completed, 1)
    }

    func testTemplatePersistenceAndNamespace() async throws {
        let suite = "fitfluence.tests.training.templates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalTrainingStore(defaults: defaults)

        let templateU1 = WorkoutTemplateDraft(
            id: "t1",
            userSub: "u1",
            name: "Upper A",
            exercises: [
                TemplateExerciseDraft(id: "ex1", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
            ],
            updatedAt: Date(),
        )
        let templateU2 = WorkoutTemplateDraft(
            id: "t2",
            userSub: "u2",
            name: "Lower A",
            exercises: [
                TemplateExerciseDraft(id: "ex2", name: "Присед", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
            ],
            updatedAt: Date(),
        )

        await store.saveTemplate(templateU1)
        await store.saveTemplate(templateU2)

        let templatesU1 = await store.templates(userSub: "u1")
        let templatesU2 = await store.templates(userSub: "u2")

        XCTAssertEqual(templatesU1.count, 1)
        XCTAssertEqual(templatesU1.first?.name, "Upper A")
        XCTAssertEqual(templatesU2.count, 1)
        XCTAssertEqual(templatesU2.first?.name, "Lower A")

        await store.deleteTemplate(userSub: "u1", templateId: "t1")
        let afterDeleteU1 = await store.templates(userSub: "u1")
        let afterDeleteU2 = await store.templates(userSub: "u2")

        XCTAssertTrue(afterDeleteU1.isEmpty)
        XCTAssertEqual(afterDeleteU2.count, 1)
    }

    func testProgressInsightEnginePrioritizesMissedWorkouts() {
        let context = ProgressInsightContext(
            workouts7d: 4,
            missedCount: 2,
            recentPRExerciseId: "ex1",
            recentPRExerciseName: "Squat",
            recentPRDate: Date(),
            lastWorkoutDate: Date(),
        )

        let insight = ProgressInsightEngine.resolve(context: context, now: Date(), calendar: .current)

        XCTAssertEqual(insight.action, .openPlan)
        XCTAssertEqual(insight.ctaTitle, "Open Plan")
    }

    func testProgressInsightEngineShowsRecentPRAction() {
        let calendar = Calendar.current
        let recentDate = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        let context = ProgressInsightContext(
            workouts7d: 1,
            missedCount: 0,
            recentPRExerciseId: "ex-bench",
            recentPRExerciseName: "Bench Press",
            recentPRDate: recentDate,
            lastWorkoutDate: Date(),
        )

        let insight = ProgressInsightEngine.resolve(context: context, now: Date(), calendar: calendar)

        XCTAssertEqual(insight.action, .openExercise(exerciseId: "ex-bench"))
        XCTAssertEqual(insight.ctaTitle, "Open Exercise")
    }

    func testProgressInsightEngineDetectsLongPause() {
        let calendar = Calendar.current
        let oldDate = calendar.date(byAdding: .day, value: -8, to: Date()) ?? Date()
        let context = ProgressInsightContext(
            workouts7d: 0,
            missedCount: 0,
            recentPRExerciseId: nil,
            recentPRExerciseName: nil,
            recentPRDate: nil,
            lastWorkoutDate: oldDate,
        )

        let insight = ProgressInsightEngine.resolve(context: context, now: Date(), calendar: calendar)

        XCTAssertEqual(insight.action, .startNextWorkout)
        XCTAssertEqual(insight.ctaTitle, "Start next workout")
    }
}
