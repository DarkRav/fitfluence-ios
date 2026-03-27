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

    @MainActor
    func testPlanViewModelSeesTemplateSavedByAnotherStoreInstance() async throws {
        let suite = "fitfluence.tests.training.templates.plan.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let writerStore = LocalTrainingStore(defaults: defaults)
        let readerStore = LocalTrainingStore(defaults: defaults)
        let template = WorkoutTemplateDraft(
            id: "t-plan",
            userSub: "u1",
            name: "Plan Visible Template",
            exercises: [
                TemplateExerciseDraft(id: "ex1", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
            ],
            updatedAt: Date(),
        )

        await writerStore.saveTemplate(template)

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: readerStore,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: .current,
        )

        let templates = await viewModel.templates()

        XCTAssertTrue(templates.contains(where: { $0.id == "t-plan" && $0.name == "Plan Visible Template" }))
    }

    @MainActor
    func testPlanViewModelDeleteTemplatePlanDoesNotRestoreFromLegacyMonthCache() async throws {
        let suite = "fitfluence.tests.training.plan.delete-template-cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let cacheStore = MemoryCacheStore()

        let localTemplatePlan = TrainingDayPlan(
            id: "local-template-plan",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "template-upper-lower",
            title: "Верх / Низ",
            source: .template,
            workoutDetails: nil,
        )
        let remoteProgramPlan = TrainingDayPlan(
            id: "remote-workout-1",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: "program-1",
            programTitle: "Сила 8 недель",
            workoutId: "workout-1",
            title: "День 1",
            source: .program,
            workoutDetails: nil,
        )

        await store.schedule(localTemplatePlan)
        await cacheStore.set(
            "athlete.plan.month.\(monthKey(for: today, calendar: calendar))",
            value: [remoteProgramPlan, localTemplatePlan],
            namespace: "u1",
            ttl: 60 * 10,
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: nil,
            cacheStore: cacheStore,
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )

        await viewModel.onAppear()
        let item = try XCTUnwrap(
            viewModel.dayItems(for: today).first(where: { $0.planId == "local-template-plan" })
        )

        await viewModel.deletePlan(item)

        let remainingItems = viewModel.dayItems(for: today)
        XCTAssertFalse(remainingItems.contains(where: { $0.planId == "local-template-plan" }))
        XCTAssertTrue(remainingItems.contains(where: { $0.planId == "remote-workout-1" }))
    }

    @MainActor
    func testPlanViewModelShowsRealProgramTitleForLocalProgramPlan() async throws {
        let suite = "fitfluence.tests.training.plan.program-title.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        let localProgramPlan = TrainingDayPlan(
            id: "local-program-plan",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: "program-1",
            programTitle: "Сила 8 недель",
            workoutId: "workout-1",
            title: "День 1",
            source: .program,
            workoutDetails: nil,
        )

        await store.schedule(localProgramPlan)

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )

        await viewModel.onAppear()

        let item = try XCTUnwrap(viewModel.dayItems(for: today).first)
        XCTAssertEqual(item.programTitle, "Сила 8 недель")
        XCTAssertEqual(item.sourceTitle, "Программа: Сила 8 недель")
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
        XCTAssertEqual(insight.ctaTitle, "Открыть план")
    }

    func testDeleteAndMovePlannedWorkout() async throws {
        let suite = "fitfluence.tests.training.plan.move.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let plan = TrainingDayPlan(
            id: "plan-1",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: "program-1",
            programTitle: "Сила 8 недель",
            workoutId: "workout-1",
            title: "День A",
            source: .program,
            workoutDetails: nil,
        )

        await store.schedule(plan)
        var plansToday = await store.plans(userSub: "u1", month: today)
        XCTAssertEqual(plansToday.count, 1)

        await store.movePlan(
            userSub: "u1",
            from: today,
            to: tomorrow,
            planId: "plan-1",
            workoutId: "workout-1",
            title: "День A",
            source: .program,
            status: .planned,
            programId: "program-1",
            programTitle: "Сила 8 недель",
            workoutDetails: nil,
        )

        plansToday = await store.plans(userSub: "u1", month: today)
        let plansTomorrow = await store.plans(userSub: "u1", month: tomorrow)
        XCTAssertFalse(plansToday.contains(where: { calendar.isDate($0.day, inSameDayAs: today) }))
        XCTAssertTrue(plansTomorrow.contains(where: { calendar.isDate($0.day, inSameDayAs: tomorrow) }))

        await store.deletePlan(
            userSub: "u1",
            day: tomorrow,
            planId: "plan-1",
            workoutId: "workout-1",
            title: "День A",
            source: .program,
        )
        let afterDelete = await store.plans(userSub: "u1", month: tomorrow)
        XCTAssertFalse(afterDelete.contains(where: { $0.workoutId == "workout-1" }))
    }

    func testMovePlanPreservesScheduledTime() async throws {
        let suite = "fitfluence.tests.training.plan.move-time.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))

        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 18, minute: 30)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 7, minute: 45)))

        let plan = TrainingDayPlan(
            id: "plan-time-1",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-time-1",
            title: "Вечерняя тренировка",
            source: .freestyle,
            workoutDetails: nil
        )

        await store.schedule(plan)
        await store.movePlan(
            userSub: "u1",
            from: today,
            to: tomorrow,
            planId: plan.id,
            workoutId: plan.workoutId,
            title: plan.title,
            source: plan.source,
            status: plan.status,
            programId: plan.programId,
            programTitle: plan.programTitle,
            workoutDetails: nil
        )

        let movedPlans = await store.plans(userSub: "u1", month: tomorrow)
        let moved = try XCTUnwrap(movedPlans.first(where: { $0.id == "plan-time-1" }))
        let components = calendar.dateComponents([.hour, .minute], from: moved.day)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 45)
    }

    func testScheduleAllowsMultiplePlansOnSameDayForSameWorkoutId() async throws {
        let suite = "fitfluence.tests.training.plan.multi.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let today = calendar.startOfDay(for: Date())

        let first = TrainingDayPlan(
            id: "plan-1",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "repeat-target",
            title: "Повтор 1",
            source: .freestyle,
            workoutDetails: nil,
        )
        let second = TrainingDayPlan(
            id: "plan-2",
            userSub: "u1",
            day: today,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "repeat-target",
            title: "Повтор 2",
            source: .freestyle,
            workoutDetails: nil,
        )

        await store.schedule(first)
        await store.schedule(second)

        let plans = await store.plans(userSub: "u1", month: today)
            .filter { calendar.isDate($0.day, inSameDayAs: today) }
        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue(plans.contains(where: { $0.id == "plan-1" }))
        XCTAssertTrue(plans.contains(where: { $0.id == "plan-2" }))
    }

    func testScheduledDayStringUsesLocalCalendarDayWithoutUtcShift() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))
        let localDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 0, minute: 30))
        )

        XCTAssertEqual(scheduledDayString(localDate, calendar: calendar), "2026-03-20")
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
        XCTAssertEqual(insight.ctaTitle, "Открыть упражнение")
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
        XCTAssertEqual(insight.ctaTitle, "Начать следующую тренировку")
    }

    func testWorkoutCompositionDraftSupportsAddRemoveReorderAndPrescriptionUpdates() {
        var draft = WorkoutCompositionDraft()
        let squat = makeCatalogItem(
            id: "ex-squat",
            name: "Присед",
            defaults: ExerciseCatalogDraftDefaults(
                sets: 4,
                repsMin: 5,
                repsMax: 8,
                restSeconds: 150,
                targetRpe: 8,
                notes: "Контроль глубины",
            ),
        )
        let bench = makeCatalogItem(
            id: "ex-bench",
            name: "Жим лёжа",
            defaults: ExerciseCatalogDraftDefaults(
                sets: 3,
                repsMin: 6,
                repsMax: 10,
                restSeconds: 120,
                targetRpe: 7,
                notes: nil,
            ),
        )

        XCTAssertTrue(draft.addExercise(squat))
        XCTAssertFalse(draft.addExercise(squat))
        XCTAssertTrue(draft.addExercise(bench))

        draft.updateExercise(id: "ex-bench") {
            $0.sets = 5
            $0.repsMin = 4
            $0.repsMax = 6
            $0.targetRpe = 9
            $0.notes = "Пауза 1 секунда"
        }

        XCTAssertTrue(draft.reorderExercise(draggedId: "ex-bench", targetId: "ex-squat"))
        XCTAssertEqual(draft.exercises.map(\.id), ["ex-bench", "ex-squat"])
        XCTAssertEqual(draft.exercises.first?.sets, 5)
        XCTAssertEqual(draft.exercises.first?.targetRpe, 9)
        XCTAssertEqual(draft.exercises.first?.notes, "Пауза 1 секунда")

        draft.removeExercise(id: "ex-squat")
        XCTAssertEqual(draft.exercises.map(\.id), ["ex-bench"])
    }

    func testWorkoutCompositionDraftHydratesFromExistingWorkoutAndBuildsWorkoutDetails() {
        let workout = WorkoutDetailsModel(
            id: "quick-1",
            title: "Push Day",
            dayOrder: 2,
            coachNote: "Быстрая тренировка",
            exercises: [
                WorkoutExercise(
                    id: "ex-press",
                    name: "Жим над головой",
                    sets: 4,
                    repsMin: 6,
                    repsMax: 8,
                    targetRpe: 8,
                    restSeconds: 120,
                    notes: "Без прогиба",
                    orderIndex: 0,
                ),
            ],
        )

        var draft = WorkoutCompositionDraft(workout: workout)
        XCTAssertEqual(draft.title, "Push Day")
        XCTAssertEqual(draft.exercises.first?.targetRpe, 8)
        XCTAssertEqual(draft.exercises.first?.notes, "Без прогиба")

        draft.updateExercise(id: "ex-press") {
            $0.sets = 5
            $0.restSeconds = 150
        }

        let rebuilt = draft.asWorkoutDetailsModel(
            workoutID: workout.id,
            fallbackTitle: "Fallback",
            dayOrder: workout.dayOrder,
            coachNote: workout.coachNote,
        )

        XCTAssertEqual(rebuilt.id, "quick-1")
        XCTAssertEqual(rebuilt.title, "Push Day")
        XCTAssertEqual(rebuilt.exercises.first?.sets, 5)
        XCTAssertEqual(rebuilt.exercises.first?.restSeconds, 150)
        XCTAssertEqual(rebuilt.exercises.first?.targetRpe, 8)
        XCTAssertEqual(rebuilt.exercises.first?.notes, "Без прогиба")
    }

    func testWorkoutCompositionDraftPreservesCatalogTagsForComposerUI() {
        var draft = WorkoutCompositionDraft()
        let item = ExerciseCatalogItem(
            id: "ex-bench",
            code: "bench-press",
            name: "Жим лёжа",
            description: nil,
            movementPattern: .push,
            difficultyLevel: .intermediate,
            isBodyweight: false,
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
            media: [],
            source: .athleteCatalog,
            draftDefaults: .standard,
        )

        XCTAssertTrue(draft.addExercise(item))
        XCTAssertEqual(draft.exercises.first?.catalogTags, ["Жим", "Средний", "Грудь", "Штанга"])

        draft.updateExercise(id: "ex-bench") {
            $0.sets = 4
            $0.notes = "Контроль паузы"
        }

        XCTAssertEqual(draft.exercises.first?.catalogTags, ["Жим", "Средний", "Грудь", "Штанга"])
    }

    func testWorkoutCompositionDraftBuildsTemplateDraftPreservingPrescription() {
        let draft = WorkoutCompositionDraft(
            title: "Upper A",
            exercises: [
                WorkoutCompositionExerciseDraft(
                    id: "ex-row",
                    name: "Тяга в наклоне",
                    sets: 4,
                    repsMin: 8,
                    repsMax: 10,
                    targetRpe: 8,
                    restSeconds: 90,
                    notes: "Локти назад",
                ),
            ],
        )

        let template = draft.asTemplateDraft(
            id: "template-upper-a",
            userSub: "u1",
            fallbackTitle: "Fallback",
        )

        XCTAssertEqual(template.name, "Upper A")
        XCTAssertEqual(template.exercises.first?.targetRpe, 8)
        XCTAssertEqual(template.exercises.first?.notes, "Локти назад")
        XCTAssertEqual(template.exercises.first?.repsMin, 8)
        XCTAssertEqual(template.exercises.first?.repsMax, 10)
    }

    func testBackendWorkoutTemplateRepositoryUsesCacheDuringRemoteFailureCooldown() async throws {
        let suite = "fitfluence.tests.training.backend-template-fallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let cacheStore = LocalTrainingStore(defaults: defaults)
        let cachedTemplate = WorkoutTemplateDraft(
            id: "cached-template",
            userSub: "u1",
            name: "Cached Upper",
            exercises: [
                TemplateExerciseDraft(id: "ex-1", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
            ],
            updatedAt: Date(),
        )
        await cacheStore.saveTemplate(cachedTemplate)

        let apiClient = StubAthleteWorkoutTemplatesAPIClient(
            listResults: [
                .failure(.serverError(statusCode: 500, bodySnippet: "boom")),
            ],
        )
        let repository = BackendWorkoutTemplateRepository(
            apiClient: apiClient,
            cacheStore: cacheStore,
        )

        let first = await repository.templates(userSub: "u1")
        let second = await repository.templates(userSub: "u1")

        XCTAssertEqual(first.map(\.id), ["cached-template"])
        XCTAssertEqual(second.map(\.id), ["cached-template"])
        let calls = await apiClient.listCallCount
        XCTAssertEqual(calls, 1)
    }

    func testBackendWorkoutTemplateRepositoryCreatesTemplateWhenIdIsNotInCache() async throws {
        let suite = "fitfluence.tests.training.backend-template-create.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let cacheStore = LocalTrainingStore(defaults: defaults)
        let createdPayload = AthleteWorkoutTemplatePayload(
            id: "server-template-1",
            athleteId: "athlete-1",
            title: "Upper A",
            notes: nil,
            exercises: [],
            createdAt: nil,
            updatedAt: nil,
        )
        let apiClient = StubAthleteWorkoutTemplatesAPIClient(
            listResults: [],
            createResult: .success(createdPayload),
        )
        let repository = BackendWorkoutTemplateRepository(
            apiClient: apiClient,
            cacheStore: cacheStore,
        )

        let template = WorkoutTemplateDraft(
            id: UUID().uuidString,
            userSub: "u1",
            name: "Upper A",
            exercises: [],
            updatedAt: Date(),
        )

        let saved = try await repository.saveTemplate(template)

        XCTAssertEqual(saved.id, "server-template-1")
        XCTAssertEqual(await apiClient.createCallCount, 1)
        XCTAssertEqual(await apiClient.updateCallCount, 0)
    }

    func testBackendWorkoutTemplateRepositoryUpdatesTemplateWhenIdExistsInCache() async throws {
        let suite = "fitfluence.tests.training.backend-template-update.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let cacheStore = LocalTrainingStore(defaults: defaults)
        let cachedTemplate = WorkoutTemplateDraft(
            id: "4A78021B-C9C2-47B2-A80A-5E657A298545",
            userSub: "u1",
            name: "Upper A",
            exercises: [],
            updatedAt: Date(),
        )
        await cacheStore.saveTemplate(cachedTemplate)

        let updatedPayload = AthleteWorkoutTemplatePayload(
            id: cachedTemplate.id,
            athleteId: "athlete-1",
            title: "Upper A+",
            notes: nil,
            exercises: [],
            createdAt: nil,
            updatedAt: nil,
        )
        let apiClient = StubAthleteWorkoutTemplatesAPIClient(
            listResults: [],
            updateResult: .success(updatedPayload),
        )
        let repository = BackendWorkoutTemplateRepository(
            apiClient: apiClient,
            cacheStore: cacheStore,
        )

        let saved = try await repository.saveTemplate(
            WorkoutTemplateDraft(
                id: cachedTemplate.id,
                userSub: "u1",
                name: "Upper A+",
                exercises: [],
                updatedAt: Date(),
            )
        )

        XCTAssertEqual(saved.name, "Upper A+")
        XCTAssertEqual(await apiClient.createCallCount, 0)
        XCTAssertEqual(await apiClient.updateCallCount, 1)
        XCTAssertEqual(await apiClient.lastUpdatedTemplateId, cachedTemplate.id)
    }

    private func monthKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func makeCatalogItem(
        id: String,
        name: String,
        defaults: ExerciseCatalogDraftDefaults,
    ) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: id,
            code: nil,
            name: name,
            description: nil,
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

private actor StubAthleteWorkoutTemplatesAPIClient: AthleteWorkoutTemplatesAPIClientProtocol {
    private var queuedListResults: [Result<[AthleteWorkoutTemplatePayload], APIError>]
    private(set) var listCallCount = 0
    private let createResult: Result<AthleteWorkoutTemplatePayload, APIError>
    private let updateResult: Result<AthleteWorkoutTemplatePayload, APIError>
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var lastUpdatedTemplateId: String?

    init(
        listResults: [Result<[AthleteWorkoutTemplatePayload], APIError>],
        createResult: Result<AthleteWorkoutTemplatePayload, APIError> = .failure(.unknown),
        updateResult: Result<AthleteWorkoutTemplatePayload, APIError> = .failure(.unknown),
    ) {
        queuedListResults = listResults
        self.createResult = createResult
        self.updateResult = updateResult
    }

    func listAthleteWorkoutTemplates() async -> Result<[AthleteWorkoutTemplatePayload], APIError> {
        listCallCount += 1
        if !queuedListResults.isEmpty {
            return queuedListResults.removeFirst()
        }
        return .success([])
    }

    func createAthleteWorkoutTemplate(
        request _: CreateAthleteWorkoutTemplateRequestBody,
    ) async -> Result<AthleteWorkoutTemplatePayload, APIError> {
        createCallCount += 1
        return createResult
    }

    func updateAthleteWorkoutTemplate(
        templateId: String,
        request _: UpdateAthleteWorkoutTemplateRequestBody,
    ) async -> Result<AthleteWorkoutTemplatePayload, APIError> {
        updateCallCount += 1
        lastUpdatedTemplateId = templateId
        return updateResult
    }

    func deleteAthleteWorkoutTemplate(templateId _: String) async -> Result<Void, APIError> {
        .failure(.unknown)
    }
}
