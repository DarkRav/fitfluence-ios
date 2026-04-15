@testable import FitfluenceApp
import XCTest

final class TrainingStoreTests: XCTestCase {
    func testStoreHistoryRecordUpdatesLastCompletedWithoutChangingWeeklySummary() async throws {
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
            workoutDetails: nil,
            notes: nil,
            overallRPE: 8,
        )

        await store.storeHistoryRecord(record)

        let last = await store.lastCompleted(userSub: "u1")
        XCTAssertEqual(last?.id, "r1")

        let weekStart = Calendar.current.date(from: Calendar.current.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: now,
        )) ?? now
        let summary = await store.weeklySummary(userSub: "u1", weekStart: weekStart)
        XCTAssertEqual(summary.completed, 0)
    }

    func testStoreHistoryRecordDoesNotCreatePlanEntry() async throws {
        let suite = "fitfluence.tests.training.history-only.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalTrainingStore(defaults: defaults)
        let finishedAt = Date()
        let record = CompletedWorkoutRecord(
            id: "history-only",
            userSub: "u1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "History Only",
            source: .program,
            startedAt: finishedAt.addingTimeInterval(-1800),
            finishedAt: finishedAt,
            durationSeconds: 1800,
            completedSets: 8,
            totalSets: 10,
            volume: 840,
            workoutDetails: nil,
            notes: nil,
            overallRPE: nil,
        )

        await store.storeHistoryRecord(record)

        let plans = await store.plans(userSub: "u1", month: finishedAt)
        XCTAssertTrue(plans.isEmpty)
    }

    func testCompleteWorkoutUpdatesLastCompletedAndWeeklySummary() async throws {
        let suite = "fitfluence.tests.training.complete-summary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalTrainingStore(defaults: defaults)
        let now = Date()
        await store.schedule(
            TrainingDayPlan(
                id: "plan-complete-summary",
                userSub: "u1",
                day: now,
                status: .planned,
                programId: "p1",
                programTitle: "Program",
                workoutId: "w1",
                title: "Тренировка A",
                source: .program,
                workoutDetails: nil
            )
        )

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
            workoutDetails: nil,
            notes: nil,
            overallRPE: 8,
        )

        await store.completeWorkout(record, planId: "plan-complete-summary")

        let last = await store.lastCompleted(userSub: "u1")
        XCTAssertEqual(last?.id, "r1")

        let weekStart = Calendar.current.date(from: Calendar.current.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: now,
        )) ?? now
        let summary = await store.weeklySummary(userSub: "u1", weekStart: weekStart)
        XCTAssertEqual(summary.completed, 1)
    }

    func testCompleteWorkoutUpdatesExistingPlanWithoutDuplicate() async throws {
        let suite = "fitfluence.tests.training.complete-existing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let plannedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 18, minute: 15)))
        let finishedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 20, minute: 42)))

        await store.schedule(
            TrainingDayPlan(
                id: "plan-1",
                userSub: "u1",
                day: plannedDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: "manual-1",
                title: "Быстрая тренировка",
                source: .freestyle,
                workoutDetails: makeRepeatWorkout(id: "manual-1", title: "Быстрая тренировка"),
            )
        )

        await store.completeWorkout(
            CompletedWorkoutRecord(
                id: "record-1",
                userSub: "u1",
                programId: "freestyle",
                workoutId: "manual-1",
                workoutTitle: "Быстрая тренировка",
                source: .freestyle,
                startedAt: finishedAt.addingTimeInterval(-1800),
                finishedAt: finishedAt,
                durationSeconds: 1800,
                completedSets: 6,
                totalSets: 6,
                volume: 1200,
                workoutDetails: makeRepeatWorkout(id: "manual-1", title: "Быстрая тренировка"),
                notes: nil,
                overallRPE: 8,
            ),
            planId: "plan-1",
        )

        let plans = await store.plans(userSub: "u1", month: finishedAt)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.id, "plan-1")
        XCTAssertEqual(plans.first?.status, .completed)
        XCTAssertEqual(plans.first?.day, plannedDay)
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
    func testPlanViewModelMutationStillBroadcastsPlanRefreshNotification() async throws {
        let suite = "fitfluence.tests.training.plan.notifications.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let trainingStore = LocalTrainingStore(defaults: defaults)
        let targetDay = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 18)) ?? Date()
        await trainingStore.schedule(
            TrainingDayPlan(
                id: "broadcast-plan",
                userSub: "u1",
                day: targetDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: "workout-1",
                title: "Plan to delete",
                source: .freestyle,
                workoutDetails: makeRepeatWorkout(id: "workout-1", title: "Plan to delete"),
            ),
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: trainingStore,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: .current,
        )
        await viewModel.onAppear()
        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)

        let notificationExpectation = expectation(description: "plan refresh notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .fitfluenceTrainingPlanDidChange,
            object: nil,
            queue: nil,
        ) { notification in
            guard let day = notification.object as? Date else { return }
            if Calendar.current.isDate(day, inSameDayAs: targetDay) {
                notificationExpectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await viewModel.deletePlan(item)

        await fulfillment(of: [notificationExpectation], timeout: 1.0)
    }

    func testPlanEntryPreservesCanonicalStatusWhileNormalizingDisplayStatus() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 4 * 60 * 60) ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 13, hour: 12)) ?? Date()
        let futureDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 18)) ?? now
        let pastDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: 18)) ?? now

        let futureMissed = TrainingDayPlan(
            id: "future-missed",
            userSub: "u1",
            day: futureDay,
            status: .missed,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-future",
            title: "Будущая",
            source: .freestyle,
            workoutDetails: nil,
        ).asPlanEntry(calendar: calendar, now: now)

        let pastMissed = TrainingDayPlan(
            id: "past-missed",
            userSub: "u1",
            day: pastDay,
            status: .missed,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-past",
            title: "Прошлая",
            source: .freestyle,
            workoutDetails: nil,
        ).asPlanEntry(calendar: calendar, now: now)

        XCTAssertEqual(futureMissed.canonicalStatus, .missed)
        XCTAssertEqual(futureMissed.displayStatus, .planned)
        XCTAssertEqual(pastMissed.canonicalStatus, .missed)
        XCTAssertEqual(pastMissed.displayStatus, .missed)
    }

    func testPlanEntryOwnershipMappingCoversRemotePendingAndLocalCases() {
        let baseDay = Date()
        let operationId = UUID()

        let remoteProgram = TrainingDayPlan(
            id: "remote-program-1",
            userSub: "u1",
            day: baseDay,
            status: .planned,
            programId: "program-1",
            programTitle: "Program",
            workoutId: "workout-program",
            title: "Program",
            source: .program,
            workoutDetails: nil,
        ).asPlanEntry()
        let localProgram = TrainingDayPlan(
            id: "local-program-1",
            userSub: "u1",
            day: baseDay,
            status: .planned,
            programId: "program-1",
            programTitle: "Program",
            workoutId: "workout-program-template",
            title: "Program Local",
            source: .program,
            workoutDetails: nil,
        ).asPlanEntry()
        let remoteCustom = TrainingDayPlan(
            id: "remote-custom-1",
            userSub: "u1",
            day: baseDay,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "11111111-1111-1111-1111-111111111111",
            title: "Remote Custom",
            source: .freestyle,
            workoutDetails: nil,
        ).asPlanEntry()
        let pendingCustom = TrainingDayPlan(
            id: "pending-custom-1",
            userSub: "u1",
            day: baseDay,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "local-custom",
            title: "Pending Custom",
            source: .template,
            workoutDetails: nil,
            pendingSyncState: .createCustomWorkout,
            pendingSyncOperationId: operationId,
        ).asPlanEntry()
        let localFreestyle = TrainingDayPlan(
            id: "local-freestyle-1",
            userSub: "u1",
            day: baseDay,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "local-freestyle",
            title: "Local Freestyle",
            source: .freestyle,
            workoutDetails: nil,
        ).asPlanEntry()
        let localTemplate = TrainingDayPlan(
            id: "local-template-1",
            userSub: "u1",
            day: baseDay,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "template-1",
            title: "Local Template",
            source: .template,
            workoutDetails: nil,
        ).asPlanEntry()

        XCTAssertEqual(remoteProgram.ownership, .remoteProgram)
        XCTAssertEqual(localProgram.ownership, .localProgramOverlay)
        XCTAssertEqual(remoteCustom.ownership, .remoteCustom)
        XCTAssertEqual(pendingCustom.ownership, .pendingCustom)
        XCTAssertEqual(localFreestyle.ownership, .localFreestyle)
        XCTAssertEqual(localTemplate.ownership, .localTemplate)
    }

    func testPlanEntryDetailsStateMappingDistinguishesHydratedPlaceholderAndMissing() {
        let hydrated = TrainingDayPlan(
            id: "details-hydrated",
            userSub: "u1",
            day: Date(),
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-hydrated",
            title: "Hydrated",
            source: .freestyle,
            workoutDetails: makeRepeatWorkout(id: "workout-hydrated", title: "Hydrated"),
        ).asPlanEntry()
        let placeholder = TrainingDayPlan(
            id: "details-placeholder",
            userSub: "u1",
            day: Date(),
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-placeholder",
            title: "Placeholder",
            source: .freestyle,
            workoutDetails: WorkoutDetailsModel(
                id: "workout-placeholder",
                title: "Placeholder",
                dayOrder: 0,
                coachNote: nil,
                exercises: []
            ),
        ).asPlanEntry()
        let missing = TrainingDayPlan(
            id: "details-missing",
            userSub: "u1",
            day: Date(),
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-missing",
            title: "Missing",
            source: .freestyle,
            workoutDetails: nil,
        ).asPlanEntry()

        XCTAssertEqual(hydrated.detailsState, .hydrated)
        XCTAssertEqual(placeholder.detailsState, .placeholder)
        XCTAssertEqual(missing.detailsState, .missing)
    }

    func testPlanEntrySyncStateMappingTracksPendingCreateCustomWorkout() {
        let operationId = UUID()
        let pending = TrainingDayPlan(
            id: "pending-sync",
            userSub: "u1",
            day: Date(),
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-pending",
            title: "Pending",
            source: .freestyle,
            workoutDetails: nil,
            pendingSyncState: .createCustomWorkout,
            pendingSyncOperationId: operationId,
        ).asPlanEntry()
        let synced = TrainingDayPlan(
            id: "synced",
            userSub: "u1",
            day: Date(),
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: "workout-synced",
            title: "Synced",
            source: .freestyle,
            workoutDetails: nil,
        ).asPlanEntry()

        XCTAssertEqual(pending.syncState, .pendingCreateCustomWorkout(operationId: operationId))
        XCTAssertTrue(pending.syncState.isPendingCreateCustomWorkout)
        XCTAssertEqual(pending.syncState.pendingOperationId, operationId)
        XCTAssertEqual(synced.syncState, .none)
        XCTAssertFalse(synced.syncState.isPendingCreateCustomWorkout)
        XCTAssertNil(synced.syncState.pendingOperationId)
    }

    func testPlanReadModelRepositoryAssemblesPreviousCurrentAndNextMonthsWithoutChangingSelection() async throws {
        let suite = "fitfluence.tests.training.plan.read-model.month-assembly.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))
        let selectedMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let previousDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 8)))
        let currentDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: 18)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 7)))
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        await store.schedule(
            TrainingDayPlan(
                id: "prev-plan",
                userSub: "u1",
                day: previousDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: "prev-workout",
                title: "Предыдущий месяц",
                source: .freestyle,
                workoutDetails: nil,
            )
        )
        await store.schedule(
            TrainingDayPlan(
                id: "current-plan",
                userSub: "u1",
                day: currentDay,
                status: .planned,
                programId: "program-1",
                programTitle: "Текущий блок",
                workoutId: "current-workout",
                title: "Текущий месяц",
                source: .program,
                workoutDetails: makeRepeatWorkout(id: "current-workout", title: "Текущий месяц"),
            )
        )
        await store.schedule(
            TrainingDayPlan(
                id: "next-plan",
                userSub: "u1",
                day: nextDay,
                status: .completed,
                programId: nil,
                programTitle: nil,
                workoutId: "next-workout",
                title: "Следующий месяц",
                source: .template,
                workoutDetails: nil,
            )
        )

        let repository = PlanReadModelRepository(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )

        let assembly = await repository.loadMonthAssembly(
            selectedMonth: selectedMonth,
            suppressedPlanSignatures: [],
        )

        XCTAssertEqual(assembly.monthPlans.map(\.id), ["current-plan"])
        XCTAssertEqual(assembly.contextPlans.map(\.id), ["prev-plan", "current-plan", "next-plan"])
        XCTAssertEqual(assembly.monthPlans.first?.ownership, .localProgramOverlay)
        XCTAssertEqual(assembly.monthPlans.first?.detailsState, .hydrated)
    }

    func testPlanReadModelRepositoryKeepsRemoteStatusAndSourceMappingUnchanged() async throws {
        let suite = "fitfluence.tests.training.plan.read-model.remote-mapping.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))
        let selectedMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.unknown),
            calendarResult: .success(
                AthleteCalendarResponse(
                    workouts: [
                        AthleteWorkoutInstance(
                            id: "remote-program-completed",
                            enrollmentId: nil,
                            workoutTemplateId: "template-1",
                            title: "Program Complete",
                            status: .completed,
                            source: .program,
                            scheduledDate: "2026-04-10",
                            scheduledAt: nil,
                            startedAt: nil,
                            completedAt: nil,
                            durationSeconds: nil,
                            notes: nil,
                            programId: "program-1"
                        ),
                        AthleteWorkoutInstance(
                            id: "remote-custom-abandoned",
                            enrollmentId: nil,
                            workoutTemplateId: nil,
                            title: "Custom Skipped",
                            status: .abandoned,
                            source: .custom,
                            scheduledDate: "2026-04-11",
                            scheduledAt: nil,
                            startedAt: nil,
                            completedAt: nil,
                            durationSeconds: nil,
                            notes: nil,
                            programId: nil
                        ),
                        AthleteWorkoutInstance(
                            id: "remote-custom-planned",
                            enrollmentId: nil,
                            workoutTemplateId: nil,
                            title: "Custom Planned",
                            status: nil,
                            source: .custom,
                            scheduledDate: "2026-04-12",
                            scheduledAt: nil,
                            startedAt: nil,
                            completedAt: nil,
                            durationSeconds: nil,
                            notes: nil,
                            programId: nil
                        ),
                    ]
                )
            )
        )
        let repository = PlanReadModelRepository(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        let assembly = await repository.loadMonthAssembly(
            selectedMonth: selectedMonth,
            suppressedPlanSignatures: [],
        )

        let completedProgram = try XCTUnwrap(assembly.monthPlans.first(where: { $0.id == "remote-remote-program-completed" }))
        let skippedManual = try XCTUnwrap(assembly.monthPlans.first(where: { $0.id == "remote-remote-custom-abandoned" }))
        let plannedManual = try XCTUnwrap(assembly.monthPlans.first(where: { $0.id == "remote-remote-custom-planned" }))

        XCTAssertEqual(completedProgram.canonicalStatus, .completed)
        XCTAssertEqual(completedProgram.source, .program)
        XCTAssertEqual(completedProgram.ownership, .remoteProgram)

        XCTAssertEqual(skippedManual.canonicalStatus, .skipped)
        XCTAssertEqual(skippedManual.source, .freestyle)
        XCTAssertEqual(skippedManual.ownership, .remoteCustom)

        XCTAssertEqual(plannedManual.canonicalStatus, .planned)
        XCTAssertEqual(plannedManual.source, .freestyle)
        XCTAssertEqual(plannedManual.ownership, .remoteCustom)
    }

    @MainActor
    func testPlanViewModelDayItemKeepsCanonicalStatusSeparateFromDisplayStatus() async throws {
        let suite = "fitfluence.tests.training.plan.day-item-status.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 4 * 60 * 60) ?? .current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        await store.schedule(
            TrainingDayPlan(
                id: "future-missed-plan",
                userSub: "u1",
                day: targetDay,
                status: .missed,
                programId: nil,
                programTitle: nil,
                workoutId: "future-missed-workout",
                title: "Future Missed",
                source: .freestyle,
                workoutDetails: nil,
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )

        await viewModel.onAppear()
        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)

        XCTAssertEqual(item.canonicalStatus, .missed)
        XCTAssertEqual(item.displayStatus, .planned)
        XCTAssertEqual(item.status, .planned)
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
    func testPlanViewModelDeletesRemoteManualWorkoutViaServer() async throws {
        let suite = "fitfluence.tests.training.plan.delete-remote-custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let remoteWorkoutID = "11111111-1111-1111-1111-111111111114"
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.unknown),
            deleteResult: .success(())
        )

        await store.schedule(
            TrainingDayPlan(
                id: "remote-\(remoteWorkoutID)",
                userSub: "u1",
                day: today,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: remoteWorkoutID,
                title: "Ручная тренировка",
                source: .freestyle,
                workoutDetails: makeRepeatWorkout(id: remoteWorkoutID, title: "Ручная тренировка"),
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        await viewModel.onAppear()
        let item = try XCTUnwrap(viewModel.dayItems(for: today).first)
        XCTAssertTrue(viewModel.canDeletePlannedWorkout(item))

        await viewModel.deletePlan(item)

        let deletedWorkoutID = await client.deletedWorkoutID()
        XCTAssertEqual(deletedWorkoutID, remoteWorkoutID)
        XCTAssertTrue(viewModel.dayItems(for: today).isEmpty)
        XCTAssertNil(viewModel.deleteErrorMessage)
    }

    @MainActor
    func testUpdatePlannedManualWorkoutSendsExercisesViaCustomWorkoutUpdate() async throws {
        let suite = "fitfluence.tests.training.plan.update-remote-custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let remoteWorkoutID = "11111111-1111-1111-1111-111111111115"
        let updatedWorkout = WorkoutDetailsModel.quickWorkout(
            title: "Обновлённая ручная",
            exercises: [
                WorkoutExercise(
                    id: "exercise-a",
                    name: "Присед",
                    sets: 4,
                    repsMin: 6,
                    repsMax: 8,
                    targetRpe: 8,
                    restSeconds: 120,
                    notes: "Тяжело",
                    orderIndex: 0
                ),
                WorkoutExercise(
                    id: "exercise-b",
                    name: "Жим",
                    sets: 3,
                    repsMin: 8,
                    repsMax: 10,
                    targetRpe: 7,
                    restSeconds: 90,
                    notes: nil,
                    orderIndex: 1
                ),
            ]
        )
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.unknown),
            updateResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: remoteWorkoutID,
                    title: updatedWorkout.title,
                    source: .custom,
                    exercises: [
                        makeExerciseExecutionResponse(id: "execution-a", exerciseId: "exercise-a", name: "Присед", orderIndex: 0, plannedSets: 4),
                        makeExerciseExecutionResponse(id: "execution-b", exerciseId: "exercise-b", name: "Жим", orderIndex: 1, plannedSets: 3),
                    ]
                )
            )
        )

        await store.schedule(
            TrainingDayPlan(
                id: "remote-\(remoteWorkoutID)",
                userSub: "u1",
                day: today,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: remoteWorkoutID,
                title: "Старая ручная",
                source: .freestyle,
                workoutDetails: WorkoutDetailsModel.quickWorkout(
                    title: "Старая ручная",
                    exercises: [
                        WorkoutExercise(
                            id: "exercise-old",
                            name: "Становая",
                            sets: 2,
                            repsMin: 5,
                            repsMax: 5,
                            targetRpe: nil,
                            restSeconds: nil,
                            notes: nil,
                            orderIndex: 0
                        ),
                    ]
                ),
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        await viewModel.onAppear()
        let item = try XCTUnwrap(viewModel.dayItems(for: today).first)

        await viewModel.updatePlannedManualWorkout(item, with: updatedWorkout)

        let updateRequest = await client.updatedWorkoutRequest()
        XCTAssertEqual(updateRequest?.title, "Обновлённая ручная")
        XCTAssertEqual(updateRequest?.exercises?.count, 2)
        XCTAssertEqual(updateRequest?.exercises?.first?.exerciseId, "exercise-a")
        XCTAssertEqual(updateRequest?.exercises?.first?.sets, 4)
        let syncActiveWorkoutCallCount = await client.syncActiveWorkoutCallCount()
        XCTAssertEqual(syncActiveWorkoutCallCount, 0)
        XCTAssertNil(viewModel.plannedWorkoutUpdateErrorMessage)

        let refreshedItem = try XCTUnwrap(viewModel.dayItems(for: today).first)
        XCTAssertEqual(refreshedItem.workoutDetails?.exercises.count, 2)
        XCTAssertEqual(refreshedItem.title, "Обновлённая ручная")
    }

    @MainActor
    func testPlanReloadPreservesHydratedManualWorkoutDetailsAgainstCalendarSummary() async throws {
        let suite = "fitfluence.tests.training.plan.reload-preserves-details.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let remoteWorkoutID = "22222222-2222-2222-2222-222222222222"
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        await store.schedule(
            TrainingDayPlan(
                id: "remote-\(remoteWorkoutID)",
                userSub: "u1",
                day: targetDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: remoteWorkoutID,
                title: "Ручная A",
                source: .freestyle,
                workoutDetails: WorkoutDetailsModel.quickWorkout(
                    title: "Ручная A",
                    exercises: [
                        WorkoutExercise(
                            id: "exercise-a",
                            name: "Присед",
                            sets: 4,
                            repsMin: 6,
                            repsMax: 8,
                            targetRpe: nil,
                            restSeconds: nil,
                            notes: nil,
                            orderIndex: 0
                        ),
                        WorkoutExercise(
                            id: "exercise-b",
                            name: "Жим",
                            sets: 3,
                            repsMin: 8,
                            repsMax: 10,
                            targetRpe: nil,
                            restSeconds: nil,
                            notes: nil,
                            orderIndex: 1
                        ),
                    ]
                ),
            )
        )

        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.unknown),
            calendarResult: .success(
                AthleteCalendarResponse(
                    workouts: [
                        AthleteWorkoutInstance(
                            id: remoteWorkoutID,
                            enrollmentId: nil,
                            workoutTemplateId: nil,
                            title: "Ручная A",
                            status: .planned,
                            source: .custom,
                            scheduledDate: scheduledDayString(targetDay, calendar: calendar),
                            scheduledAt: scheduledDateTimeString(targetDay),
                            startedAt: nil,
                            completedAt: nil,
                            durationSeconds: nil,
                            notes: nil,
                            programId: nil
                        ),
                    ]
                )
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        await viewModel.onAppear()

        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(item.workoutDetails?.exercises.count, 2)
        XCTAssertEqual(item.workoutDetails?.exercises.first?.name, "Присед")
    }

    @MainActor
    func testResolveWorkoutDetailsFetchesRemoteWhenStoredPlanContainsLegacySummaryPlaceholder() async throws {
        let suite = "fitfluence.tests.training.plan.resolve-legacy-placeholder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let remoteWorkoutID = "33333333-3333-3333-3333-333333333333"
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        await store.schedule(
            TrainingDayPlan(
                id: "remote-\(remoteWorkoutID)",
                userSub: "u1",
                day: targetDay,
                status: .planned,
                programId: nil,
                programTitle: nil,
                workoutId: remoteWorkoutID,
                title: "Пустой placeholder",
                source: .freestyle,
                workoutDetails: WorkoutDetailsModel(
                    id: remoteWorkoutID,
                    title: "Пустой placeholder",
                    dayOrder: 0,
                    coachNote: nil,
                    exercises: []
                ),
            )
        )

        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.unknown),
            getDetailsResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: remoteWorkoutID,
                    title: "Пустой placeholder",
                    source: .custom,
                    scheduledDate: scheduledDayString(targetDay, calendar: calendar),
                    scheduledAt: scheduledDateTimeString(targetDay),
                    exercises: [
                        makeExerciseExecutionResponse(
                            id: "execution-rich",
                            exerciseId: "exercise-rich",
                            name: "Тяга верхнего блока",
                            orderIndex: 0,
                            plannedSets: 3
                        ),
                    ]
                )
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        await viewModel.onAppear()
        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)

        let resolved = await viewModel.resolveWorkoutDetails(for: item)
        let fetchedWorkoutID = await client.fetchedWorkoutID()

        XCTAssertEqual(fetchedWorkoutID, remoteWorkoutID)
        XCTAssertEqual(resolved?.exercises.count, 1)
        XCTAssertEqual(resolved?.exercises.first?.name, "Тяга верхнего блока")
    }

    @MainActor
    func testReplanMissedMovesOriginalPlanInsteadOfCreatingDuplicate() async throws {
        let suite = "fitfluence.tests.training.plan.replan-move.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let missedDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let targetDay = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        await store.schedule(
            TrainingDayPlan(
                id: "missed-plan-1",
                userSub: "u1",
                day: missedDay,
                status: .missed,
                programId: nil,
                programTitle: nil,
                workoutId: "missed-workout-1",
                title: "Пропущенная тренировка",
                source: .freestyle,
                workoutDetails: WorkoutDetailsModel.quickWorkout(
                    title: "Пропущенная тренировка",
                    exercises: []
                ),
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )

        await viewModel.onAppear()
        let missedItem = try XCTUnwrap(viewModel.dayItems(for: missedDay).first)

        await viewModel.replanMissed(missedItem, on: targetDay)

        XCTAssertTrue(viewModel.dayItems(for: missedDay).isEmpty)
        let replannedItems = viewModel.dayItems(for: targetDay)
        XCTAssertEqual(replannedItems.count, 1)
        XCTAssertEqual(replannedItems.first?.planId, "missed-plan-1")
        XCTAssertEqual(replannedItems.first?.status, .planned)
    }

    @MainActor
    func testMergedPlansPreferLocalRescheduledRemotePlanOverOldRemoteDay() async throws {
        let suite = "fitfluence.tests.training.plan.remote-overlay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let missedDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let targetDay = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let remoteWorkoutID = "44444444-4444-4444-4444-444444444444"
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        await store.schedule(
            TrainingDayPlan(
                id: "remote-\(remoteWorkoutID)",
                userSub: "u1",
                day: targetDay,
                status: .planned,
                programId: "program-1",
                programTitle: "Сила",
                workoutId: remoteWorkoutID,
                title: "День A",
                source: .program,
                workoutDetails: nil,
            )
        )

        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.unknown),
            calendarResult: .success(
                AthleteCalendarResponse(
                    workouts: [
                        AthleteWorkoutInstance(
                            id: remoteWorkoutID,
                            enrollmentId: nil,
                            workoutTemplateId: "template-1",
                            title: "День A",
                            status: .missed,
                            source: .program,
                            scheduledDate: scheduledDayString(missedDay, calendar: calendar),
                            scheduledAt: nil,
                            startedAt: nil,
                            completedAt: nil,
                            durationSeconds: nil,
                            notes: nil,
                            programId: "program-1"
                        ),
                    ]
                )
            )
        )

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        await viewModel.onAppear()

        XCTAssertTrue(viewModel.dayItems(for: missedDay).isEmpty)
        let futureItems = viewModel.dayItems(for: targetDay)
        XCTAssertEqual(futureItems.count, 1)
        XCTAssertEqual(futureItems.first?.planId, "remote-\(remoteWorkoutID)")
        XCTAssertEqual(futureItems.first?.status, .planned)
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

    @MainActor
    func testScheduleRepeatedWorkoutCreatesRemoteMirrorAfterServerCreate() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-remote.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let remoteWorkoutID = "11111111-1111-1111-1111-111111111111"
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: remoteWorkoutID,
                    title: "Повтор тренировки",
                    source: .custom,
                )
            )
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )
        let workout = makeRepeatWorkout(id: "quick-repeat-local", title: "Повтор тренировки")

        let didSchedule = await viewModel.scheduleRepeatedWorkout(workout, source: .freestyle, on: targetDay)

        XCTAssertTrue(didSchedule)
        let request = await client.lastCreateRequest
        assertScheduledRequest(request, matches: targetDay, calendar: calendar)
        let idempotencyKey = await client.lastCreateIdempotencyKey
        XCTAssertTrue(idempotencyKey?.hasPrefix("custom-workout-create:pending-custom-") == true)

        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(item.planId, "remote-\(remoteWorkoutID)")
        XCTAssertEqual(item.workoutId, remoteWorkoutID)
        XCTAssertEqual(item.source, .freestyle)
        XCTAssertEqual(item.title, "Повтор тренировки")
        XCTAssertEqual(item.workoutDetails?.exercises.count, 1)
    }

    @MainActor
    func testScheduleRepeatedWorkoutAcceptsDateOnlyServerCreateResponse() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-remote-date-only.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let targetDay = try XCTUnwrap(
            calendar.date(
                bySettingHour: 20,
                minute: 42,
                second: 0,
                of: tomorrow
            )
        )
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let remoteWorkoutID = "11111111-1111-1111-1111-111111111112"
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: remoteWorkoutID,
                    title: "Повтор тренировки",
                    source: .custom,
                    scheduledDate: scheduledDayString(targetDay, calendar: calendar)
                )
            )
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )
        let workout = makeRepeatWorkout(id: "quick-repeat-date-only", title: "Повтор тренировки")

        let didSchedule = await viewModel.scheduleRepeatedWorkout(workout, source: .freestyle, on: targetDay)

        XCTAssertTrue(didSchedule)
        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(item.planId, "remote-\(remoteWorkoutID)")
        XCTAssertEqual(item.workoutId, remoteWorkoutID)
    }

    @MainActor
    func testScheduleRepeatedWorkoutAcceptsCreateResponseWithoutCustomSource() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-remote-source.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let remoteWorkoutID = "11111111-1111-1111-1111-111111111113"
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: remoteWorkoutID,
                    title: "Повтор тренировки",
                    source: .program,
                    scheduledDate: scheduledDayString(targetDay, calendar: calendar)
                )
            )
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )
        let workout = makeRepeatWorkout(id: "quick-repeat-source", title: "Повтор тренировки")

        let didSchedule = await viewModel.scheduleRepeatedWorkout(workout, source: .freestyle, on: targetDay)

        XCTAssertTrue(didSchedule)
        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(item.planId, "remote-\(remoteWorkoutID)")
        XCTAssertEqual(item.source, .freestyle)
    }

    func testRepeatableCopyDropsLegacyQuickWorkoutTimeFromTitle() {
        let workout = makeRepeatWorkout(id: "quick-legacy", title: "Быстрая тренировка • 17:57")

        let copy = workout.asRepeatableCopy(prefix: "quick-repeat")

        XCTAssertEqual(copy.title, "Быстрая тренировка")
        XCTAssertTrue(copy.id.hasPrefix("quick-repeat-"))
    }

    @MainActor
    func testScheduleRepeatedWorkoutQueuesPendingTemplatePlanWhenOffline() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-local-pending.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let client = MockRepeatWorkoutAthleteTrainingClient(createResult: .success(makeWorkoutDetailsResponse(
            workoutID: "should-not-be-used",
            title: "Шаблонный повтор",
            source: .custom,
        )))
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )
        let workout = makeRepeatWorkout(id: "template-repeat-local", title: "Шаблонный повтор")

        let didSchedule = await viewModel.scheduleRepeatedWorkout(workout, source: .template, on: targetDay)

        XCTAssertTrue(didSchedule)
        let request = await client.lastCreateRequest
        XCTAssertNil(request)

        let item = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertTrue(item.planId.hasPrefix("pending-custom-"))
        XCTAssertEqual(item.workoutId, "template-repeat-local")
        XCTAssertEqual(item.source, .template)
        XCTAssertEqual(item.title, "Шаблонный повтор")
        XCTAssertEqual(item.workoutDetails, workout)
        XCTAssertTrue(item.isPendingRemoteCreation)
    }

    @MainActor
    func testRepeatCompletedManualWorkoutCreatesFreshRemoteInstance() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-completed-remote.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let completedDay = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: completedDay) ?? completedDay
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let oldWorkoutID = "11111111-1111-1111-1111-111111111111"
        let newWorkoutID = "22222222-2222-2222-2222-222222222222"
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: newWorkoutID,
                    title: "Повтор manual",
                    source: .custom,
                )
            )
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )
        let completedWorkout = makeRepeatWorkout(id: oldWorkoutID, title: "Повтор manual")
        await store.schedule(
            TrainingDayPlan(
                id: "completed-manual",
                userSub: "u1",
                day: completedDay,
                status: .completed,
                programId: nil,
                programTitle: nil,
                workoutId: oldWorkoutID,
                title: "Повтор manual",
                source: .freestyle,
                workoutDetails: completedWorkout,
            )
        )
        await viewModel.onAppear()

        let completedItem = try XCTUnwrap(viewModel.dayItems(for: completedDay).first)

        await viewModel.repeatCompleted(completedItem, on: targetDay)

        let request = await client.lastCreateRequest
        assertScheduledRequest(request, matches: targetDay, calendar: calendar)
        let idempotencyKey = await client.lastCreateIdempotencyKey
        XCTAssertTrue(idempotencyKey?.hasPrefix("custom-workout-create:pending-custom-") == true)

        let repeatedItem = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(repeatedItem.source, .freestyle)
        XCTAssertEqual(repeatedItem.status, .planned)
        XCTAssertEqual(repeatedItem.workoutId, newWorkoutID)
        XCTAssertNotEqual(repeatedItem.workoutId, oldWorkoutID)
        XCTAssertEqual(repeatedItem.planId, "remote-\(newWorkoutID)")
    }

    @MainActor
    func testRepeatCompletedManualWorkoutQueuesPendingFreshCopyWhenOffline() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-completed-local.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let completedDay = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 2, to: completedDay) ?? completedDay
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let oldWorkoutID = "33333333-3333-3333-3333-333333333333"
        let client = MockRepeatWorkoutAthleteTrainingClient(createResult: .failure(.unknown))
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar,
        )
        let completedWorkout = makeRepeatWorkout(id: oldWorkoutID, title: "Локальный повтор")
        await store.schedule(
            TrainingDayPlan(
                id: "completed-local-manual",
                userSub: "u1",
                day: completedDay,
                status: .completed,
                programId: nil,
                programTitle: nil,
                workoutId: oldWorkoutID,
                title: "Локальный повтор",
                source: .freestyle,
                workoutDetails: completedWorkout,
            )
        )
        await viewModel.onAppear()

        let completedItem = try XCTUnwrap(viewModel.dayItems(for: completedDay).first)

        await viewModel.repeatCompleted(completedItem, on: targetDay)

        let request = await client.lastCreateRequest
        XCTAssertNil(request)

        let repeatedItem = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(repeatedItem.source, .freestyle)
        XCTAssertEqual(repeatedItem.status, .planned)
        XCTAssertNotEqual(repeatedItem.workoutId, oldWorkoutID)
        XCTAssertTrue(repeatedItem.planId.hasPrefix("pending-custom-"))
        XCTAssertEqual(repeatedItem.workoutDetails?.title, "Локальный повтор")
        XCTAssertNotEqual(repeatedItem.workoutDetails?.id, oldWorkoutID)
        XCTAssertTrue(repeatedItem.isPendingRemoteCreation)
    }

    @MainActor
    func testScheduleRepeatLastWorkoutFetchesMissingManualDetailsBeforeCreate() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-last-fetch-details.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let completedDay = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: completedDay) ?? completedDay
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let completedWorkoutID = "44444444-4444-4444-4444-444444444444"
        let newWorkoutID = "55555555-5555-5555-5555-555555555555"
        let fetchedDetails = makeRepeatWorkout(id: completedWorkoutID, title: "Последняя manual")
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: newWorkoutID,
                    title: "Последняя manual",
                    source: .custom,
                )
            ),
            getDetailsResult: .success(
                makeWorkoutDetailsResponse(
                    workoutID: completedWorkoutID,
                    title: "Последняя manual",
                    source: .custom,
                    workoutTemplateID: nil,
                )
            )
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )

        await store.storeHistoryRecord(
            CompletedWorkoutRecord(
                id: "history-last-manual",
                userSub: "u1",
                programId: "",
                workoutId: completedWorkoutID,
                workoutTitle: fetchedDetails.title,
                source: .freestyle,
                startedAt: completedDay.addingTimeInterval(1800),
                finishedAt: completedDay.addingTimeInterval(3600),
                durationSeconds: 1800,
                completedSets: 4,
                totalSets: 4,
                volume: 640,
                workoutDetails: nil,
                notes: nil,
                overallRPE: nil,
            )
        )
        await viewModel.onAppear()

        await viewModel.scheduleRepeatLastWorkout(on: targetDay)

        let fetchedWorkoutID = await client.lastFetchedWorkoutID
        XCTAssertEqual(fetchedWorkoutID, completedWorkoutID)
        let createRequest = await client.lastCreateRequest
        XCTAssertEqual(createRequest?.title, "Последняя manual")

        let repeatedItem = try XCTUnwrap(viewModel.dayItems(for: targetDay).first)
        XCTAssertEqual(repeatedItem.planId, "remote-\(newWorkoutID)")
        XCTAssertEqual(repeatedItem.workoutId, newWorkoutID)
    }

    @MainActor
    func testScheduleRepeatedWorkoutDoesNotQueuePendingAfterAmbiguousServerFailure() async throws {
        let suite = "fitfluence.tests.training.plan.repeat-server-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let client = MockRepeatWorkoutAthleteTrainingClient(
            createResult: .failure(.serverError(statusCode: 500, bodySnippet: nil))
        )
        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: client,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: true),
            calendar: calendar,
        )
        let workout = makeRepeatWorkout(id: "quick-repeat-local", title: "Повтор тренировки")

        let didSchedule = await viewModel.scheduleRepeatedWorkout(workout, source: .freestyle, on: targetDay)

        XCTAssertFalse(didSchedule)
        let request = await client.lastCreateRequest
        XCTAssertNotNil(request)
        XCTAssertTrue(viewModel.dayItems(for: targetDay).isEmpty)
        XCTAssertEqual(
            viewModel.repeatSchedulingErrorMessage,
            "Не удалось создать тренировку на сервере. Проверьте план и повторите попытку."
        )
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

    func testCompleteWorkoutPreservesCompletedTimeInPlan() async throws {
        let suite = "fitfluence.tests.training.plan.completed-time.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 4 * 60 * 60))

        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)
        let finishedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 20, minute: 42)))

        await store.completeWorkout(
            CompletedWorkoutRecord(
                id: "completed-time-1",
                userSub: "u1",
                programId: "",
                workoutId: "manual-1",
                workoutTitle: "Быстрая тренировка",
                source: .freestyle,
                startedAt: finishedAt.addingTimeInterval(-3600),
                finishedAt: finishedAt,
                durationSeconds: 3600,
                completedSets: 6,
                totalSets: 6,
                volume: 136,
                workoutDetails: nil,
                notes: nil,
                overallRPE: nil,
            ),
            planId: nil
        )

        let plans = await store.plans(userSub: "u1", month: finishedAt)
        let plan = try XCTUnwrap(plans.first(where: { $0.id == "completed-time-1" }))
        let components = calendar.dateComponents([.hour, .minute], from: plan.day)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 42)
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

        let createCallCount = await apiClient.createCallCount
        let updateCallCount = await apiClient.updateCallCount
        XCTAssertEqual(saved.id, "server-template-1")
        XCTAssertEqual(createCallCount, 1)
        XCTAssertEqual(updateCallCount, 0)
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

        let createCallCount = await apiClient.createCallCount
        let updateCallCount = await apiClient.updateCallCount
        let lastUpdatedTemplateId = await apiClient.lastUpdatedTemplateId
        XCTAssertEqual(saved.name, "Upper A+")
        XCTAssertEqual(createCallCount, 0)
        XCTAssertEqual(updateCallCount, 1)
        XCTAssertEqual(lastUpdatedTemplateId, cachedTemplate.id)
    }

    @MainActor
    func testPlanViewModelPrefersRichCompletedRecordForManualWorkout() async throws {
        let suite = "fitfluence.tests.training.plan.completed-rich-record.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let store = LocalTrainingStore(defaults: defaults, calendar: calendar)

        let workoutDetails = WorkoutDetailsModel(
            id: "manual-1",
            title: "Быстрая тренировка",
            dayOrder: 0,
            coachNote: nil,
            exercises: [
                WorkoutExercise(
                    id: "ex-1",
                    name: "Жим лёжа",
                    sets: 3,
                    repsMin: 8,
                    repsMax: 10,
                    targetRpe: nil,
                    restSeconds: 90,
                    notes: nil,
                    orderIndex: 0
                ),
            ]
        )

        let plan = TrainingDayPlan(
            id: "plan-completed",
            userSub: "u1",
            day: day,
            status: .completed,
            programId: "freestyle",
            programTitle: nil,
            workoutId: "manual-1",
            title: "Быстрая тренировка",
            source: .freestyle,
            workoutDetails: nil
        )
        await store.schedule(plan)

        let remoteLikeRecord = CompletedWorkoutRecord(
            id: "remote-summary",
            userSub: "u1",
            programId: "freestyle",
            workoutId: "instance-1",
            workoutTitle: "Быстрая тренировка",
            source: .freestyle,
            startedAt: day.addingTimeInterval(3600),
            finishedAt: day.addingTimeInterval(5400),
            durationSeconds: 1800,
            completedSets: 0,
            totalSets: 0,
            volume: 0,
            workoutDetails: nil,
            notes: nil,
            overallRPE: nil
        )
        let localRichRecord = CompletedWorkoutRecord(
            id: "local-finish",
            userSub: "u1",
            programId: "freestyle",
            workoutId: "manual-1",
            workoutTitle: "Быстрая тренировка",
            source: .freestyle,
            startedAt: day.addingTimeInterval(3600),
            finishedAt: day.addingTimeInterval(5400),
            durationSeconds: 1800,
            completedSets: 6,
            totalSets: 6,
            volume: 1200,
            workoutDetails: workoutDetails,
            notes: nil,
            overallRPE: 8
        )

        await store.storeHistoryRecord(remoteLikeRecord)
        await store.storeHistoryRecord(localRichRecord)

        let viewModel = PlanScheduleViewModel(
            userSub: "u1",
            trainingStore: store,
            athleteTrainingClient: nil,
            cacheStore: MemoryCacheStore(),
            networkMonitor: StaticNetworkMonitor(currentStatus: false),
            calendar: calendar
        )

        await viewModel.onAppear()
        let item = try XCTUnwrap(viewModel.dayItems(for: day).first(where: { $0.planId == "plan-completed" }))
        let resolved = await viewModel.completedRecord(for: item)

        XCTAssertEqual(resolved?.id, "local-finish")
        XCTAssertEqual(resolved?.workoutDetails?.id, "manual-1")
        XCTAssertEqual(resolved?.completedSets, 6)
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

    private func assertScheduledRequest(
        _ request: AthleteCreateCustomWorkoutRequest?,
        matches expectedDate: Date,
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request else {
            XCTFail("request is nil", file: file, line: line)
            return
        }

        guard let scheduledDate = request.scheduledDate else {
            XCTFail("scheduledDate is nil", file: file, line: line)
            return
        }
        XCTAssertEqual(scheduledDate, scheduledDayString(expectedDate, calendar: calendar), file: file, line: line)

        guard let scheduledAt = request.scheduledAt else {
            XCTFail("scheduledAt is nil", file: file, line: line)
            return
        }
        guard let parsedDate = SyncOperation.parseISO8601(scheduledAt) else {
            XCTFail("scheduledAt is not ISO-8601: \(scheduledAt)", file: file, line: line)
            return
        }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsedDate)
        let expected = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: expectedDate)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func makeRepeatWorkout(id: String, title: String) -> WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: id,
            title: title,
            dayOrder: 0,
            coachNote: "Повтор",
            exercises: [
                WorkoutExercise(
                    id: "ex-1",
                    name: "Жим лёжа",
                    sets: 4,
                    repsMin: 6,
                    repsMax: 8,
                    targetRpe: 8,
                    restSeconds: 120,
                    notes: "Тяжёлый сет",
                    orderIndex: 0,
                ),
            ],
        )
    }

    private func makeWorkoutDetailsResponse(
        workoutID: String,
        title: String,
        source: AthleteWorkoutSource,
        workoutTemplateID: String? = nil,
        status: AthleteWorkoutInstanceStatus? = .planned,
        scheduledDate: String? = nil,
        scheduledAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil,
        exercises: [AthleteExerciseExecution]? = nil,
    ) -> AthleteWorkoutDetailsResponse {
        AthleteWorkoutDetailsResponse(
            workout: AthleteWorkoutInstance(
                id: workoutID,
                enrollmentId: nil,
                workoutTemplateId: workoutTemplateID,
                title: title,
                status: status,
                source: source,
                scheduledDate: scheduledDate,
                scheduledAt: scheduledAt,
                startedAt: startedAt,
                completedAt: completedAt,
                durationSeconds: nil,
                notes: "Повтор",
                programId: nil,
            ),
            exercises: exercises ?? [
                AthleteExerciseExecution(
                    id: "execution-1",
                    workoutInstanceId: workoutID,
                    exerciseTemplateId: nil,
                    workoutPlanId: nil,
                    exerciseId: "ex-1",
                    orderIndex: 0,
                    notes: nil,
                    plannedSets: 4,
                    plannedRepsMin: 6,
                    plannedRepsMax: 8,
                    plannedTargetRpe: 8,
                    plannedRestSeconds: 120,
                    plannedNotes: "Тяжёлый сет",
                    progressionPolicyId: nil,
                    exercise: AthleteExerciseBrief(
                        id: "ex-1",
                        code: nil,
                        name: "Жим лёжа",
                        description: nil,
                        isBodyweight: false,
                        equipment: nil,
                        media: nil,
                    ),
                    sets: nil,
                ),
            ],
        )
    }

    private func makeExerciseExecutionResponse(
        id: String,
        exerciseId: String,
        name: String,
        orderIndex: Int,
        plannedSets: Int,
    ) -> AthleteExerciseExecution {
        AthleteExerciseExecution(
            id: id,
            workoutInstanceId: "workout-instance",
            exerciseTemplateId: nil,
            workoutPlanId: nil,
            exerciseId: exerciseId,
            orderIndex: orderIndex,
            notes: nil,
            plannedSets: plannedSets,
            plannedRepsMin: nil,
            plannedRepsMax: nil,
            plannedTargetRpe: nil,
            plannedRestSeconds: nil,
            plannedNotes: nil,
            progressionPolicyId: nil,
            exercise: AthleteExerciseBrief(
                id: exerciseId,
                code: nil,
                name: name,
                description: nil,
                isBodyweight: false,
                equipment: nil,
                media: nil,
            ),
            sets: nil,
        )
    }
}

private actor MockRepeatWorkoutAthleteTrainingClient: AthleteTrainingClientProtocol {
    private(set) var lastCreateRequest: AthleteCreateCustomWorkoutRequest?
    private(set) var lastCreateIdempotencyKey: String?
    private(set) var lastFetchedWorkoutID: String?
    private(set) var lastDeletedWorkoutID: String?
    private(set) var lastUpdatedWorkoutID: String?
    private(set) var lastUpdateRequest: AthleteUpdateCustomWorkoutRequest?
    private var recordedSyncActiveWorkoutCallCount = 0
    private let createResult: Result<AthleteWorkoutDetailsResponse, APIError>
    private let getDetailsResult: Result<AthleteWorkoutDetailsResponse, APIError>
    private let deleteResult: Result<Void, APIError>
    private let updateResult: Result<AthleteWorkoutDetailsResponse, APIError>
    private let calendarResult: Result<AthleteCalendarResponse, APIError>

    init(
        createResult: Result<AthleteWorkoutDetailsResponse, APIError>,
        getDetailsResult: Result<AthleteWorkoutDetailsResponse, APIError> = .failure(.unknown),
        deleteResult: Result<Void, APIError> = .failure(.unknown),
        updateResult: Result<AthleteWorkoutDetailsResponse, APIError> = .failure(.unknown),
        calendarResult: Result<AthleteCalendarResponse, APIError> = .failure(.unknown),
    ) {
        self.createResult = createResult
        self.getDetailsResult = getDetailsResult
        self.deleteResult = deleteResult
        self.updateResult = updateResult
        self.calendarResult = calendarResult
    }

    func calendar(month _: String) async -> Result<AthleteCalendarResponse, APIError> {
        calendarResult
    }

    func createCustomWorkout(
        request: AthleteCreateCustomWorkoutRequest,
        idempotencyKey: String?,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        lastCreateRequest = request
        lastCreateIdempotencyKey = idempotencyKey
        return createResult
    }

    func getWorkoutDetails(workoutInstanceId: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        lastFetchedWorkoutID = workoutInstanceId
        return getDetailsResult
    }

    func updateCustomWorkout(
        workoutInstanceId: String,
        request: AthleteUpdateCustomWorkoutRequest,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        lastUpdatedWorkoutID = workoutInstanceId
        lastUpdateRequest = request
        return updateResult
    }

    func syncActiveWorkout(
        workoutInstanceId _: String,
        request _: ActiveWorkoutSyncRequest,
    ) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        recordedSyncActiveWorkoutCallCount += 1
        return .failure(.unknown)
    }

    func deleteCustomWorkout(workoutInstanceId: String) async -> Result<Void, APIError> {
        lastDeletedWorkoutID = workoutInstanceId
        return deleteResult
    }

    func deletedWorkoutID() -> String? {
        lastDeletedWorkoutID
    }

    func fetchedWorkoutID() -> String? {
        lastFetchedWorkoutID
    }

    func updatedWorkoutRequest() -> AthleteUpdateCustomWorkoutRequest? {
        lastUpdateRequest
    }

    func syncActiveWorkoutCallCount() -> Int {
        recordedSyncActiveWorkoutCallCount
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
