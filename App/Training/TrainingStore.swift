import Foundation

enum WorkoutSource: String, Codable, Equatable, Sendable {
    case program
    case freestyle
    case template
}

enum TrainingDayStatus: String, Codable, Equatable, Sendable {
    case planned
    case inProgress
    case completed
    case missed
    case skipped

    var isMissedLike: Bool {
        self == .missed || self == .skipped
    }
}

enum TrainingDayPendingSyncState: String, Codable, Equatable, Sendable {
    case createCustomWorkout
}

struct CompletedWorkoutRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let userSub: String
    let programId: String
    let workoutId: String
    let workoutTitle: String
    let source: WorkoutSource
    let startedAt: Date
    let finishedAt: Date
    let durationSeconds: Int
    let completedSets: Int
    let totalSets: Int
    let volume: Double
    let workoutDetails: WorkoutDetailsModel?
    let notes: String?
    let overallRPE: Int?
}

struct TrainingDayPlan: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let userSub: String
    let day: Date
    let status: TrainingDayStatus
    let programId: String?
    let programTitle: String?
    let workoutId: String?
    let title: String
    let source: WorkoutSource
    let workoutDetails: WorkoutDetailsModel?
    let pendingSyncState: TrainingDayPendingSyncState?
    let pendingSyncOperationId: UUID?

    init(
        id: String,
        userSub: String,
        day: Date,
        status: TrainingDayStatus,
        programId: String?,
        programTitle: String?,
        workoutId: String?,
        title: String,
        source: WorkoutSource,
        workoutDetails: WorkoutDetailsModel?,
        pendingSyncState: TrainingDayPendingSyncState? = nil,
        pendingSyncOperationId: UUID? = nil,
    ) {
        self.id = id
        self.userSub = userSub
        self.day = day
        self.status = status
        self.programId = programId
        self.programTitle = programTitle
        self.workoutId = workoutId
        self.title = title
        self.source = source
        self.workoutDetails = workoutDetails
        self.pendingSyncState = pendingSyncState
        self.pendingSyncOperationId = pendingSyncOperationId
    }

    var isPendingCustomWorkoutCreation: Bool {
        pendingSyncState == .createCustomWorkout
    }
}

struct TemplateExerciseDraft: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var name: String
    var sets: Int
    var repsMin: Int?
    var repsMax: Int?
    var restSeconds: Int?
    var targetRpe: Int? = nil
    var notes: String? = nil
}

struct WorkoutTemplateDraft: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let userSub: String
    var name: String
    var exercises: [TemplateExerciseDraft]
    var updatedAt: Date
}

func scheduledDayString(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0
    return String(format: "%04d-%02d-%02d", year, month, day)
}

struct WorkoutCompositionExerciseDraft: Equatable, Sendable, Identifiable {
    let id: String
    var name: String
    var catalogTags: [String]
    var sets: Int
    var repsMin: Int?
    var repsMax: Int?
    var targetRpe: Int?
    var restSeconds: Int?
    var notes: String?

    init(
        id: String,
        name: String,
        catalogTags: [String] = [],
        sets: Int,
        repsMin: Int?,
        repsMax: Int?,
        targetRpe: Int?,
        restSeconds: Int?,
        notes: String?,
    ) {
        self.id = id
        self.name = name
        self.catalogTags = catalogTags
        self.sets = max(1, sets)

        let resolvedRepsMin = repsMin.map { max(1, $0) }
        let resolvedRepsMax = repsMax.map { max(1, $0) }
        if let resolvedRepsMin {
            self.repsMin = resolvedRepsMin
            self.repsMax = max(resolvedRepsMin, resolvedRepsMax ?? resolvedRepsMin)
        } else {
            self.repsMin = nil
            self.repsMax = resolvedRepsMax
        }

        self.targetRpe = targetRpe.map { min(10, max(1, $0)) }
        self.restSeconds = restSeconds.map { max(0, $0) }
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(catalogItem: ExerciseCatalogItem) {
        let defaults = catalogItem.draftDefaults ?? .standard
        self.init(
            id: catalogItem.id,
            name: catalogItem.name,
            catalogTags: catalogItem.composerTags,
            sets: defaults.sets,
            repsMin: defaults.repsMin,
            repsMax: defaults.repsMax,
            targetRpe: defaults.targetRpe,
            restSeconds: defaults.restSeconds,
            notes: defaults.notes,
        )
    }

    init(workoutExercise: WorkoutExercise) {
        self.init(
            id: workoutExercise.id,
            name: workoutExercise.name,
            sets: workoutExercise.sets,
            repsMin: workoutExercise.repsMin,
            repsMax: workoutExercise.repsMax,
            targetRpe: workoutExercise.targetRpe,
            restSeconds: workoutExercise.restSeconds,
            notes: workoutExercise.notes,
        )
    }

    init(templateExercise: TemplateExerciseDraft) {
        self.init(
            id: templateExercise.id,
            name: templateExercise.name,
            sets: templateExercise.sets,
            repsMin: templateExercise.repsMin,
            repsMax: templateExercise.repsMax,
            targetRpe: templateExercise.targetRpe,
            restSeconds: templateExercise.restSeconds,
            notes: templateExercise.notes,
        )
    }

    var summaryText: String {
        var parts = ["\(sets) подхода"]
        if let repsText {
            parts.append(repsText)
        }
        if let restSeconds {
            parts.append("отдых \(restSeconds) сек")
        }
        if let targetRpe {
            parts.append("RPE \(targetRpe)")
        }
        return parts.joined(separator: " • ")
    }

    var notesPreview: String? {
        notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var repsText: String? {
        switch (repsMin, repsMax) {
        case let (min?, max?):
            return min == max ? "\(min) повторов" : "\(min)-\(max) повторов"
        case let (min?, nil):
            return "\(min) повторов"
        case let (nil, max?):
            return "до \(max) повторов"
        case (nil, nil):
            return nil
        }
    }

    func asWorkoutExercise(orderIndex: Int) -> WorkoutExercise {
        WorkoutExercise(
            id: id,
            name: name,
            sets: max(1, sets),
            repsMin: repsMin,
            repsMax: repsMax,
            targetRpe: targetRpe,
            restSeconds: restSeconds,
            notes: notesPreview,
            orderIndex: orderIndex,
        )
    }

    func asTemplateExercise() -> TemplateExerciseDraft {
        TemplateExerciseDraft(
            id: id,
            name: name,
            sets: max(1, sets),
            repsMin: repsMin,
            repsMax: repsMax,
            restSeconds: restSeconds,
            targetRpe: targetRpe,
            notes: notesPreview,
        )
    }
}

struct WorkoutCompositionDraft: Equatable, Sendable {
    var title: String
    var exercises: [WorkoutCompositionExerciseDraft]

    init(
        title: String = "",
        exercises: [WorkoutCompositionExerciseDraft] = [],
    ) {
        self.title = title
        self.exercises = exercises
    }

    init(workout: WorkoutDetailsModel) {
        title = workout.title
        exercises = workout.exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .map(WorkoutCompositionExerciseDraft.init(workoutExercise:))
    }

    init(template: WorkoutTemplateDraft) {
        title = template.name
        exercises = template.exercises.map(WorkoutCompositionExerciseDraft.init(templateExercise:))
    }

    var normalizedTitle: String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    mutating func addExercise(_ exercise: ExerciseCatalogItem) -> Bool {
        let draft = WorkoutCompositionExerciseDraft(catalogItem: exercise)
        guard !exercises.contains(where: { $0.id == draft.id }) else { return false }
        exercises.append(draft)
        return true
    }

    mutating func removeExercise(id: String) {
        exercises.removeAll { $0.id == id }
    }

    mutating func updateExercise(id: String, mutate: (inout WorkoutCompositionExerciseDraft) -> Void) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        var updated = exercises[index]
        mutate(&updated)
        exercises[index] = WorkoutCompositionExerciseDraft(
            id: updated.id,
            name: updated.name,
            catalogTags: updated.catalogTags,
            sets: updated.sets,
            repsMin: updated.repsMin,
            repsMax: updated.repsMax,
            targetRpe: updated.targetRpe,
            restSeconds: updated.restSeconds,
            notes: updated.notes,
        )
    }

    mutating func reorderExercise(draggedId: String, targetId: String) -> Bool {
        guard draggedId != targetId,
              let from = exercises.firstIndex(where: { $0.id == draggedId }),
              let to = exercises.firstIndex(where: { $0.id == targetId })
        else { return false }

        let item = exercises.remove(at: from)
        exercises.insert(item, at: to)
        return true
    }

    func asWorkoutDetailsModel(
        workoutID: String,
        fallbackTitle: String,
        dayOrder: Int,
        coachNote: String?,
    ) -> WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: workoutID,
            title: normalizedTitle ?? fallbackTitle,
            dayOrder: dayOrder,
            coachNote: coachNote,
            exercises: exercises.enumerated().map { index, exercise in
                exercise.asWorkoutExercise(orderIndex: index)
            },
        )
    }

    func asTemplateDraft(
        id: String,
        userSub: String,
        fallbackTitle: String,
        updatedAt: Date = Date(),
    ) -> WorkoutTemplateDraft {
        WorkoutTemplateDraft(
            id: id,
            userSub: userSub,
            name: normalizedTitle ?? fallbackTitle,
            exercises: exercises.map { $0.asTemplateExercise() },
            updatedAt: updatedAt,
        )
    }
}

private extension ExerciseCatalogItem {
    var composerTags: [String] {
        var tags: [String] = []
        if let movementPattern {
            tags.append(movementPattern.displayLabel)
        }
        if let difficultyLevel {
            tags.append(difficultyLevel.displayLabel)
        }
        let muscleTags = muscles
            .compactMap(\.muscleGroup)
            .map(\.displayLabel)
            .uniqueStrings()
        tags.append(contentsOf: muscleTags.prefix(2))
        let equipmentTags = equipment
            .map(\.name)
            .uniqueStrings()
        tags.append(contentsOf: equipmentTags.prefix(2))
        if tags.isEmpty, isBodyweight == true {
            tags.append("Свой вес")
        }
        return Array(tags.prefix(4))
    }
}

private extension ExerciseCatalogMovementPattern {
    var displayLabel: String {
        switch self {
        case .push:
            "Жим"
        case .pull:
            "Тяга"
        case .squat:
            "Присед"
        case .hinge:
            "Наклон"
        case .other:
            "Другое"
        }
    }
}

private extension ExerciseCatalogDifficultyLevel {
    var displayLabel: String {
        switch self {
        case .beginner:
            "Базовый"
        case .intermediate:
            "Средний"
        case .advanced:
            "Продвинутый"
        }
    }
}

private extension ExerciseCatalogMuscleGroup {
    var displayLabel: String {
        switch self {
        case .chest:
            "Грудь"
        case .back:
            "Спина"
        case .shoulders:
            "Плечи"
        case .legs:
            "Ноги"
        case .arms:
            "Руки"
        case .abs:
            "Пресс"
        }
    }
}

private extension Array where Element == String {
    func uniqueStrings() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

struct WeeklyTrainingSummary: Equatable, Sendable {
    let weekStart: Date
    let planned: Int
    let completed: Int
    let missed: Int
    let streakDays: Int
}

protocol TrainingStore: Sendable {
    func storeHistoryRecord(_ record: CompletedWorkoutRecord) async
    func completeWorkout(_ record: CompletedWorkoutRecord, planId: String?) async
    func history(userSub: String, source: WorkoutSource?, limit: Int?) async -> [CompletedWorkoutRecord]
    func lastCompleted(userSub: String) async -> CompletedWorkoutRecord?
    func saveTemplate(_ template: WorkoutTemplateDraft) async
    func deleteTemplate(userSub: String, templateId: String) async
    func templates(userSub: String) async -> [WorkoutTemplateDraft]
    func schedule(_ plan: TrainingDayPlan) async
    func deletePlan(
        userSub: String,
        day: Date,
        planId: String?,
        workoutId: String?,
        title: String,
        source: WorkoutSource,
    ) async
    func movePlan(
        userSub: String,
        from day: Date,
        to targetDay: Date,
        planId: String?,
        workoutId: String?,
        title: String,
        source: WorkoutSource,
        status: TrainingDayStatus,
        programId: String?,
        programTitle: String?,
        workoutDetails: WorkoutDetailsModel?,
    ) async
    func deleteProgramPlans(
        userSub: String,
        programId: String,
        statuses: [TrainingDayStatus]
    ) async
    func plans(userSub: String, month: Date) async -> [TrainingDayPlan]
    func weeklySummary(userSub: String, weekStart: Date) async -> WeeklyTrainingSummary
    func storageSizeBytes(userSub: String) async -> Int
}

extension TrainingStore {
    func completeWorkout(_ record: CompletedWorkoutRecord, planId _: String?) async {
        await storeHistoryRecord(record)
    }

    func deletePlan(
        userSub _: String,
        day _: Date,
        planId _: String?,
        workoutId _: String?,
        title _: String,
        source _: WorkoutSource,
    ) async {}

    func movePlan(
        userSub _: String,
        from _: Date,
        to _: Date,
        planId _: String?,
        workoutId _: String?,
        title _: String,
        source _: WorkoutSource,
        status _: TrainingDayStatus,
        programId _: String?,
        programTitle _: String?,
        workoutDetails _: WorkoutDetailsModel?,
    ) async {}

    func deleteProgramPlans(
        userSub _: String,
        programId _: String,
        statuses _: [TrainingDayStatus]
    ) async {}
}

actor LocalTrainingStore: TrainingStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let historyPrefix = "fitfluence.training.history"
    private let templatesPrefix = "fitfluence.training.templates"
    private let planPrefix = "fitfluence.training.plan"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func storeHistoryRecord(_ record: CompletedWorkoutRecord) async {
        var items = await history(userSub: record.userSub, source: nil, limit: nil)
        items.removeAll { $0.id == record.id }
        items.append(record)
        items.sort { $0.finishedAt > $1.finishedAt }
        await saveArray(items, key: historyKey(userSub: record.userSub))
    }

    func completeWorkout(_ record: CompletedWorkoutRecord, planId: String?) async {
        await storeHistoryRecord(record)

        var items = loadArray([TrainingDayPlan].self, key: planKey(userSub: record.userSub)) ?? []
        let resolvedPlanId = resolveCompletedPlanID(
            for: record,
            preferredPlanId: planId,
            existingPlans: items,
        )
        let existingPlan = resolvedPlanId.flatMap { candidateId in
            items.first(where: { $0.userSub == record.userSub && $0.id == candidateId })
        }
        let normalizedTitle = record.workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Тренировка"
        let completedPlan = TrainingDayPlan(
            id: resolvedPlanId ?? record.id,
            userSub: record.userSub,
            day: existingPlan?.day ?? record.finishedAt,
            status: .completed,
            programId: existingPlan?.programId ?? normalized(record.programId),
            programTitle: existingPlan?.programTitle,
            workoutId: existingPlan?.workoutId ?? record.workoutId,
            title: existingPlan?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? normalizedTitle,
            source: existingPlan?.source ?? record.source,
            workoutDetails: existingPlan?.workoutDetails ?? record.workoutDetails,
        )

        items.removeAll { $0.userSub == record.userSub && $0.id == completedPlan.id }
        items.append(completedPlan)
        items.sort { $0.day > $1.day }
        await saveArray(items, key: planKey(userSub: record.userSub))
    }

    func history(userSub: String, source: WorkoutSource?, limit: Int?) async -> [CompletedWorkoutRecord] {
        var items = loadArray([CompletedWorkoutRecord].self, key: historyKey(userSub: userSub)) ?? []
        if let source {
            items = items.filter { $0.source == source }
        }
        items.sort { $0.finishedAt > $1.finishedAt }
        if let limit {
            return Array(items.prefix(limit))
        }
        return items
    }

    func lastCompleted(userSub: String) async -> CompletedWorkoutRecord? {
        await history(userSub: userSub, source: nil, limit: 1).first
    }

    func saveTemplate(_ template: WorkoutTemplateDraft) async {
        var items = await templates(userSub: template.userSub)
        items.removeAll { $0.id == template.id }
        items.append(template)
        items.sort { $0.updatedAt > $1.updatedAt }
        await saveArray(items, key: templatesKey(userSub: template.userSub))
    }

    func deleteTemplate(userSub: String, templateId: String) async {
        let items = await templates(userSub: userSub).filter { $0.id != templateId }
        await saveArray(items, key: templatesKey(userSub: userSub))
    }

    func templates(userSub: String) async -> [WorkoutTemplateDraft] {
        (loadArray([WorkoutTemplateDraft].self, key: templatesKey(userSub: userSub)) ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func schedule(_ plan: TrainingDayPlan) async {
        var items = loadArray([TrainingDayPlan].self, key: planKey(userSub: plan.userSub)) ?? []
        items.removeAll { $0.userSub == plan.userSub && $0.id == plan.id }
        items.append(plan)
        items.sort { $0.day > $1.day }
        await saveArray(items, key: planKey(userSub: plan.userSub))
    }

    func deletePlan(
        userSub: String,
        day: Date,
        planId: String?,
        workoutId: String?,
        title: String,
        source: WorkoutSource,
    ) async {
        let normalizedDay = startOfDay(day)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = (loadArray([TrainingDayPlan].self, key: planKey(userSub: userSub)) ?? []).filter { item in
            guard item.userSub == userSub else { return true }
            guard startOfDay(item.day) == normalizedDay else { return true }
            if let planId {
                return item.id != planId
            }
            if let workoutId {
                return item.workoutId != workoutId
            }
            return item.title != normalizedTitle || item.source != source
        }
        await saveArray(items, key: planKey(userSub: userSub))
    }

    func movePlan(
        userSub: String,
        from day: Date,
        to targetDay: Date,
        planId: String?,
        workoutId: String?,
        title: String,
        source: WorkoutSource,
        status: TrainingDayStatus,
        programId: String?,
        programTitle: String?,
        workoutDetails: WorkoutDetailsModel?,
    ) async {
        let normalizedFromDay = startOfDay(day)
        let normalizedTargetDay = startOfDay(targetDay)
        guard normalizedFromDay != normalizedTargetDay else { return }

        await deletePlan(
            userSub: userSub,
            day: normalizedFromDay,
            planId: planId,
            workoutId: workoutId,
            title: title,
            source: source,
        )

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TrainingDayPlan(
            id: planId ?? UUID().uuidString,
            userSub: userSub,
            day: targetDay,
            status: status,
            programId: programId,
            programTitle: programTitle,
            workoutId: workoutId,
            title: normalizedTitle.isEmpty ? "Тренировка" : normalizedTitle,
            source: source,
            workoutDetails: workoutDetails,
        )
        await schedule(plan)
    }

    func plans(userSub: String, month: Date) async -> [TrainingDayPlan] {
        let items = loadArray([TrainingDayPlan].self, key: planKey(userSub: userSub)) ?? []
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return items
        }
        return items
            .filter { monthInterval.contains($0.day) }
            .sorted { $0.day < $1.day }
    }

    func plan(userSub: String, planId: String) async -> TrainingDayPlan? {
        (loadArray([TrainingDayPlan].self, key: planKey(userSub: userSub)) ?? []).first { item in
            item.userSub == userSub && item.id == planId
        }
    }

    func deleteProgramPlans(
        userSub: String,
        programId: String,
        statuses: [TrainingDayStatus]
    ) async {
        let statusSet = Set(statuses)
        let items = (loadArray([TrainingDayPlan].self, key: planKey(userSub: userSub)) ?? []).filter { item in
            guard item.userSub == userSub else { return true }
            guard item.programId == programId else { return true }
            return !statusSet.contains(item.status)
        }
        await saveArray(items, key: planKey(userSub: userSub))
    }

    func weeklySummary(userSub: String, weekStart: Date) async -> WeeklyTrainingSummary {
        let start = startOfDay(weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let items = (loadArray([TrainingDayPlan].self, key: planKey(userSub: userSub)) ?? [])
            .filter { $0.day >= start && $0.day < end }

        let planned = items.count(where: { $0.status == .planned || $0.status == .inProgress })
        let completed = items.count(where: { $0.status == .completed })
        let missed = items.count(where: { $0.status.isMissedLike })

        return WeeklyTrainingSummary(
            weekStart: start,
            planned: planned,
            completed: completed,
            missed: missed,
            streakDays: streakDays(userSub: userSub),
        )
    }

    func storageSizeBytes(userSub: String) async -> Int {
        [historyKey(userSub: userSub), templatesKey(userSub: userSub), planKey(userSub: userSub)]
            .compactMap { defaults.data(forKey: $0) }
            .reduce(0) { $0 + $1.count }
    }

    private func streakDays(userSub: String) -> Int {
        let records = (loadArray([CompletedWorkoutRecord].self, key: historyKey(userSub: userSub)) ?? [])
            .sorted { $0.finishedAt > $1.finishedAt }
        guard !records.isEmpty else { return 0 }

        var streak = 0
        var cursor = startOfDay(Date())
        var index = 0

        while index < records.count {
            let day = startOfDay(records[index].finishedAt)
            if day == cursor {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                while index < records.count, startOfDay(records[index].finishedAt) == day {
                    index += 1
                }
            } else if day < cursor {
                break
            } else {
                index += 1
            }
        }

        return streak
    }

    private func resolveCompletedPlanID(
        for record: CompletedWorkoutRecord,
        preferredPlanId: String?,
        existingPlans: [TrainingDayPlan],
    ) -> String? {
        let userPlans = existingPlans.filter { $0.userSub == record.userSub }

        if let preferredPlanId = preferredPlanId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           userPlans.contains(where: { $0.id == preferredPlanId })
        {
            return preferredPlanId
        }

        let remoteCandidate = "remote-\(record.workoutId)"
        if userPlans.contains(where: { $0.id == remoteCandidate }) {
            return remoteCandidate
        }

        let sameDayCandidates = userPlans.filter { candidate in
            guard candidate.source == record.source else { return false }
            guard normalized(candidate.workoutId) == normalized(record.workoutId) else { return false }
            return startOfDay(candidate.day) == startOfDay(record.finishedAt)
        }
        if sameDayCandidates.count == 1 {
            return sameDayCandidates[0].id
        }

        return nil
    }

    private func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func loadArray<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveArray(_ value: some Encodable, key: String) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func historyKey(userSub: String) -> String {
        "\(historyPrefix).\(userSub)"
    }

    private func templatesKey(userSub: String) -> String {
        "\(templatesPrefix).\(userSub)"
    }

    private func planKey(userSub: String) -> String {
        "\(planPrefix).\(userSub)"
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

extension WorkoutDetailsModel {
    static func quickWorkout(title: String, exercises: [WorkoutExercise]) -> WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: "quick-\(UUID().uuidString)",
            title: title,
            dayOrder: 0,
            coachNote: "Быстрая тренировка",
            exercises: exercises,
        )
    }

    func asRepeatableCopy(prefix: String) -> WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: "\(prefix)-\(UUID().uuidString)",
            title: repeatableTitle,
            dayOrder: dayOrder,
            coachNote: coachNote,
            exercises: exercises,
        )
    }

    func asCreateCustomWorkoutRequest(scheduledDate: Date? = nil) -> AthleteCreateCustomWorkoutRequest {
        AthleteCreateCustomWorkoutRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Тренировка",
            scheduledDate: scheduledDate.map { scheduledDayString($0) },
            scheduledAt: scheduledDate.map { scheduledDateTimeString($0) },
            notes: coachNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            exercises: exercises
                .sorted(by: { $0.orderIndex < $1.orderIndex })
                .enumerated()
                .map { index, exercise in
                    AthleteCustomWorkoutExerciseDraftRequest(
                        exerciseId: exercise.id,
                        orderIndex: index,
                        sets: max(1, exercise.sets),
                        repsMin: exercise.repsMin,
                        repsMax: exercise.repsMax,
                        targetRpe: exercise.targetRpe,
                        restSeconds: exercise.restSeconds,
                        notes: exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        progressionPolicyId: nil,
                    )
                },
        )
    }

    func asUpdateCustomWorkoutRequest(scheduledDate: Date? = nil) -> AthleteUpdateCustomWorkoutRequest {
        AthleteUpdateCustomWorkoutRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            scheduledDate: scheduledDate.map { scheduledDayString($0) },
            scheduledAt: scheduledDate.map { scheduledDateTimeString($0) },
            notes: coachNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            exercises: exercises
                .sorted(by: { $0.orderIndex < $1.orderIndex })
                .enumerated()
                .map { index, exercise in
                    AthleteCustomWorkoutExerciseDraftRequest(
                        exerciseId: exercise.id,
                        orderIndex: index,
                        sets: max(1, exercise.sets),
                        repsMin: exercise.repsMin,
                        repsMax: exercise.repsMax,
                        targetRpe: exercise.targetRpe,
                        restSeconds: exercise.restSeconds,
                        notes: exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        progressionPolicyId: nil,
                    )
                },
        )
    }

    private var repeatableTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.hasPrefix("Быстрая тренировка") else {
            return trimmedTitle
        }

        let suffix = trimmedTitle.replacingOccurrences(of: "Быстрая тренировка", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard suffix.first == "•" else {
            return trimmedTitle
        }

        let candidate = suffix.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = candidate.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0 ... 23).contains(hour),
              (0 ... 59).contains(minute)
        else {
            return trimmedTitle
        }

        return "Быстрая тренировка"
    }
}

func scheduledDateTimeString(_ date: Date) -> String {
    scheduledDateTimeFormatter.string(from: date)
}

private let scheduledDateTimeFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

protocol WorkoutTemplateRepository: Sendable {
    func templates(userSub: String) async -> [WorkoutTemplateDraft]
    func saveTemplate(_ template: WorkoutTemplateDraft) async throws -> WorkoutTemplateDraft
    func deleteTemplate(userSub: String, templateId: String) async throws
}

struct LocalWorkoutTemplateRepository: WorkoutTemplateRepository {
    private let trainingStore: any TrainingStore

    init(trainingStore: any TrainingStore = LocalTrainingStore()) {
        self.trainingStore = trainingStore
    }

    func templates(userSub: String) async -> [WorkoutTemplateDraft] {
        await trainingStore.templates(userSub: userSub)
    }

    func saveTemplate(_ template: WorkoutTemplateDraft) async throws -> WorkoutTemplateDraft {
        await trainingStore.saveTemplate(template)
        return template
    }

    func deleteTemplate(userSub: String, templateId: String) async throws {
        await trainingStore.deleteTemplate(userSub: userSub, templateId: templateId)
    }
}

actor BackendWorkoutTemplateRepository: WorkoutTemplateRepository {
    private let apiClient: AthleteWorkoutTemplatesAPIClientProtocol?
    private let cacheStore: any TrainingStore
    private let remoteFailureCooldown: Duration = .seconds(60)
    private var remoteFetchStateByUserSub: [String: RemoteFetchState] = [:]

    init(
        apiClient: AthleteWorkoutTemplatesAPIClientProtocol?,
        cacheStore: any TrainingStore = LocalTrainingStore(),
    ) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
    }

    func templates(userSub: String) async -> [WorkoutTemplateDraft] {
        guard let apiClient else {
            return await cacheStore.templates(userSub: userSub)
        }

        if shouldUseCachedTemplates(for: userSub) {
            return await cacheStore.templates(userSub: userSub)
        }

        switch await apiClient.listAthleteWorkoutTemplates() {
        case let .success(payload):
            let drafts = payload.map { $0.asDraft(userSub: userSub) }
            remoteFetchStateByUserSub[userSub] = .healthy(fetchedAt: ContinuousClock.now)
            await syncCache(drafts, userSub: userSub)
            return drafts
        case .failure:
            remoteFetchStateByUserSub[userSub] = .failed(at: ContinuousClock.now)
            return await cacheStore.templates(userSub: userSub)
        }
    }

    func saveTemplate(_ template: WorkoutTemplateDraft) async throws -> WorkoutTemplateDraft {
        guard let apiClient else {
            await cacheStore.saveTemplate(template)
            return template
        }

        let cachedTemplates = await cacheStore.templates(userSub: template.userSub)
        let shouldUpdateRemote = cachedTemplates.contains { $0.id == template.id }

        let result: Result<AthleteWorkoutTemplatePayload, APIError> = if shouldUpdateRemote {
            await apiClient.updateAthleteWorkoutTemplate(
                templateId: template.id,
                request: template.asUpdateRequest,
            )
        } else {
            await apiClient.createAthleteWorkoutTemplate(request: template.asCreateRequest)
        }

        switch result {
        case let .success(payload):
            let saved = payload.asDraft(userSub: template.userSub)
            await cacheStore.saveTemplate(saved)
            return saved
        case let .failure(error):
            throw error
        }
    }

    func deleteTemplate(userSub: String, templateId: String) async throws {
        guard let apiClient else {
            await cacheStore.deleteTemplate(userSub: userSub, templateId: templateId)
            return
        }

        switch await apiClient.deleteAthleteWorkoutTemplate(templateId: templateId) {
        case .success:
            await cacheStore.deleteTemplate(userSub: userSub, templateId: templateId)
        case let .failure(error):
            throw error
        }
    }

    private func syncCache(_ templates: [WorkoutTemplateDraft], userSub: String) async {
        let existing = await cacheStore.templates(userSub: userSub)
        let existingIDs = Set(existing.map(\.id))
        let incomingIDs = Set(templates.map(\.id))

        for staleID in existingIDs.subtracting(incomingIDs) {
            await cacheStore.deleteTemplate(userSub: userSub, templateId: staleID)
        }
        for template in templates {
            await cacheStore.saveTemplate(template)
        }
    }

    private func shouldUseCachedTemplates(for userSub: String) -> Bool {
        guard case let .failed(at) = remoteFetchStateByUserSub[userSub] else {
            return false
        }
        return at.duration(to: ContinuousClock.now) < remoteFailureCooldown
    }
}

private enum RemoteFetchState: Sendable {
    case healthy(fetchedAt: ContinuousClock.Instant)
    case failed(at: ContinuousClock.Instant)
}

private extension WorkoutTemplateDraft {
    var asCreateRequest: CreateAthleteWorkoutTemplateRequestBody {
        CreateAthleteWorkoutTemplateRequestBody(
            title: name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Тренировка",
            notes: nil,
            exercises: exercises.map(\.asTemplateExerciseInput),
        )
    }

    var asUpdateRequest: UpdateAthleteWorkoutTemplateRequestBody {
        UpdateAthleteWorkoutTemplateRequestBody(
            title: name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Тренировка",
            notes: nil,
            exercises: exercises.map(\.asTemplateExerciseInput),
        )
    }
}

private extension TemplateExerciseDraft {
    var asTemplateExerciseInput: AthleteWorkoutTemplateExerciseInputRequest {
        AthleteWorkoutTemplateExerciseInputRequest(
            exerciseId: id,
            sets: max(1, sets),
            repsMin: repsMin,
            repsMax: repsMax,
            targetRpe: targetRpe,
            restSeconds: restSeconds,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            progressionPolicyId: nil,
        )
    }
}

private extension AthleteWorkoutTemplatePayload {
    func asDraft(userSub: String) -> WorkoutTemplateDraft {
        WorkoutTemplateDraft(
            id: id,
            userSub: userSub,
            name: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Тренировка",
            exercises: exercises.map(\.asDraft),
            updatedAt: updatedAt.flatMap(Self.iso8601.date(from:)) ?? Date(),
        )
    }

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension AthleteWorkoutTemplateExercisePayload {
    var asDraft: TemplateExerciseDraft {
        TemplateExerciseDraft(
            id: exercise.id,
            name: exercise.name,
            sets: sets,
            repsMin: repsMin,
            repsMax: repsMax,
            restSeconds: restSeconds,
            targetRpe: targetRpe,
            notes: notes,
        )
    }
}
