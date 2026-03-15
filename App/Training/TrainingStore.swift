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
}

struct TemplateExerciseDraft: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var name: String
    var sets: Int
    var repsMin: Int?
    var repsMax: Int?
    var restSeconds: Int?
}

struct WorkoutTemplateDraft: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let userSub: String
    var name: String
    var exercises: [TemplateExerciseDraft]
    var updatedAt: Date
}

struct WeeklyTrainingSummary: Equatable, Sendable {
    let weekStart: Date
    let planned: Int
    let completed: Int
    let missed: Int
    let streakDays: Int
}

protocol TrainingStore: Sendable {
    func appendHistory(_ record: CompletedWorkoutRecord) async
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
    func plans(userSub: String, month: Date) async -> [TrainingDayPlan]
    func weeklySummary(userSub: String, weekStart: Date) async -> WeeklyTrainingSummary
    func storageSizeBytes(userSub: String) async -> Int
}

extension TrainingStore {
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

    func appendHistory(_ record: CompletedWorkoutRecord) async {
        var items = await history(userSub: record.userSub, source: nil, limit: nil)
        items.removeAll { $0.id == record.id }
        items.append(record)
        items.sort { $0.finishedAt > $1.finishedAt }
        await saveArray(items, key: historyKey(userSub: record.userSub))

        let plan = TrainingDayPlan(
            id: record.id,
            userSub: record.userSub,
            day: startOfDay(record.finishedAt),
            status: .completed,
            programId: record.programId,
            programTitle: nil,
            workoutId: record.workoutId,
            title: record.workoutTitle,
            source: record.source,
            workoutDetails: nil,
        )
        await schedule(plan)
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
            day: normalizedTargetDay,
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
}
