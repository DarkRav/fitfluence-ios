import Observation
import SwiftUI

enum ProgressSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case exercises
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Обзор"
        case .exercises:
            "Упражнения"
        case .history:
            "История"
        }
    }
}

enum ProgressPeriod: String, CaseIterable, Equatable, Sendable {
    case days7
    case days30
    case days90
    case all

    var title: String {
        switch self {
        case .days7:
            "7 дн"
        case .days30:
            "30 дн"
        case .days90:
            "90 дн"
        case .all:
            "Всё время"
        }
    }

    var days: Int? {
        switch self {
        case .days7:
            7
        case .days30:
            30
        case .days90:
            90
        case .all:
            nil
        }
    }
}

enum ProgressHistorySourceFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case program
    case custom

    var title: String {
        switch self {
        case .all:
            "Все"
        case .program:
            "Программа"
        case .custom:
            "Свои"
        }
    }
}

enum ProgressInsightAction: Equatable, Sendable {
    case openPlan
    case startNextWorkout
    case openExercise(exerciseId: String)
}

struct ProgressInsight: Equatable, Sendable {
    let title: String
    let ctaTitle: String
    let action: ProgressInsightAction
}

struct ProgressAdherenceSnapshot: Equatable, Sendable {
    let planned: Int
    let completed: Int
    let missed: Int

    static let empty = ProgressAdherenceSnapshot(planned: 0, completed: 0, missed: 0)

    var completionRatePercent: Int {
        guard planned > 0 else { return completed > 0 ? 100 : 0 }
        return Int((Double(completed) / Double(max(planned, 1))) * 100.0)
    }
}

struct ProgressOverviewSnapshot: Equatable, Sendable {
    let streakDays: Int
    let workouts7d: Int
    let totalWorkouts: Int
    let totalMinutes7d: Int
    let totalVolume7d: Double
    let adherence: ProgressAdherenceSnapshot

    static let empty = ProgressOverviewSnapshot(
        streakDays: 0,
        workouts7d: 0,
        totalWorkouts: 0,
        totalMinutes7d: 0,
        totalVolume7d: 0,
        adherence: .empty,
    )
}

struct WeeklyHighlightSnapshot: Equatable, Sendable, Identifiable {
    let id: String
    let exerciseName: String
    let improvementText: String
    let contextText: String
}

struct ProgressNextActionSnapshot: Equatable, Sendable {
    let hasNextWorkout: Bool
    let nextWorkoutId: String?
    let nextWorkoutTitle: String?

    static let startWorkout = ProgressNextActionSnapshot(
        hasNextWorkout: false,
        nextWorkoutId: nil,
        nextWorkoutTitle: nil,
    )

    var primaryTitle: String {
        hasNextWorkout ? "Начать следующую тренировку" : "Начать тренировку"
    }
}

struct ExerciseProgressListItem: Equatable, Sendable, Identifiable, Hashable {
    let id: String
    let exerciseId: String?
    let name: String
    let prText: String
    let lastPerformedText: String
    let trendLabel: String?
    let lastPerformedAt: Date?
    let recentPRAt: Date?
}

private struct ExerciseHistoryMeta: Equatable, Sendable {
    let lastPerformedAt: Date?
    let trendLabel: String?
}

struct ProgressHistoryGroup: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let records: [CompletedWorkoutRecord]
}

struct ProgressInsightContext: Equatable, Sendable {
    let workouts7d: Int
    let missedCount: Int
    let recentPRExerciseId: String?
    let recentPRExerciseName: String?
    let recentPRDate: Date?
    let lastWorkoutDate: Date?
}

enum ProgressInsightEngine {
    static func resolve(
        context: ProgressInsightContext,
        now: Date = Date(),
        calendar: Calendar = .current,
    ) -> ProgressInsight {
        if context.missedCount >= 2 {
            return ProgressInsight(
                title: "Пропущено \(context.missedCount) тренировок по плану на этой неделе — выбери одну на сегодня",
                ctaTitle: "Открыть план",
                action: .openPlan,
            )
        }

        if let exerciseId = context.recentPRExerciseId,
           let exerciseName = context.recentPRExerciseName,
           let recentPRDate = context.recentPRDate,
           let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: recentPRDate), to: calendar.startOfDay(for: now)).day,
           days <= 14
        {
            return ProgressInsight(
                title: "В упражнении \(exerciseName) новый личный рекорд за последние 14 дней",
                ctaTitle: "Открыть упражнение",
                action: .openExercise(exerciseId: exerciseId),
            )
        }

        if context.workouts7d >= 3 {
            return ProgressInsight(
                title: "Ты выполнил \(context.workouts7d) тренировки за 7 дней — держишь темп",
                ctaTitle: "Начать следующую тренировку",
                action: .startNextWorkout,
            )
        }

        if let lastWorkoutDate = context.lastWorkoutDate,
           let pauseDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWorkoutDate), to: calendar.startOfDay(for: now)).day,
           pauseDays >= 5
        {
            return ProgressInsight(
                title: "Долгая пауза: не было тренировок \(pauseDays) дней",
                ctaTitle: "Начать следующую тренировку",
                action: .startNextWorkout,
            )
        }

        return ProgressInsight(
            title: "Стабильный прогресс строится на рутине — открой план и зафиксируй следующую сессию",
            ctaTitle: "Открыть план",
            action: .openPlan,
        )
    }
}

@Observable
@MainActor
final class TrainingInsightsViewModel {
    private enum CacheKeys {
        static let statsSummary = "progress.stats.summary"
        static let personalRecords = "progress.prs.all"
        static let activeEnrollmentProgress = "progress.active-enrollment"

        static func calendar(month: String) -> String {
            "progress.calendar.\(month)"
        }

        static func exerciseHistory(exerciseId: String) -> String {
            "progress.exercise.history.\(exerciseId)"
        }
    }

    private let userSub: String
    private let trainingStore: TrainingStore
    private let cacheStore: CacheStore
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let networkMonitor: NetworkMonitoring
    private let calendar: Calendar

    private let cacheTTL: TimeInterval = 60 * 60 * 24

    private(set) var didInitialLoad = false
    var isLoading = false
    var isOffline = false
    var isShowingCachedData = false
    var errorMessage: String?

    var selectedSection: ProgressSection = .overview
    var selectedPeriod: ProgressPeriod = .days30
    var selectedHistoryFilter: ProgressHistorySourceFilter = .all
    var searchQuery = ""

    var overview: ProgressOverviewSnapshot = .empty
    var insight: ProgressInsight?
    var weeklyHighlight: WeeklyHighlightSnapshot?
    var nextAction: ProgressNextActionSnapshot = .startWorkout

    var historyGroups: [ProgressHistoryGroup] = []

    private(set) var allExerciseItems: [ExerciseProgressListItem] = []
    private var localHistory: [CompletedWorkoutRecord] = []
    private var localPlansByMonth: [String: [TrainingDayPlan]] = [:]
    private var statsSummary: AthleteStatsSummaryResponse?
    private var personalRecords: [AthletePersonalRecord] = []
    private var calendarByMonth: [String: AthleteCalendarResponse] = [:]
    private var activeEnrollmentProgress: ActiveEnrollmentProgressResponse?
    private var exerciseHistoryMetaById: [String: ExerciseHistoryMeta] = [:]
    private var loadedExerciseMetaIds: Set<String> = []

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.cacheStore = cacheStore
        self.athleteTrainingClient = athleteTrainingClient
        self.networkMonitor = networkMonitor
        self.calendar = calendar
    }

    var exerciseItems: [ExerciseProgressListItem] {
        let normalized = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return allExerciseItems }

        return allExerciseItems.filter { item in
            item.name.lowercased().contains(normalized)
        }
    }

    func onAppear() async {
        if didInitialLoad {
            await preloadVisibleExerciseMetadata(limit: 20)
            return
        }
        didInitialLoad = true
        await reload()
    }

    func updateNetworkStatus(_ online: Bool) {
        isOffline = !online
    }

    func reload() async {
        guard !userSub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        isOffline = !networkMonitor.currentStatus
        isShowingCachedData = false

        localHistory = await trainingStore.history(userSub: userSub, source: nil, limit: 720)

        let monthKeys = requiredMonthKeys(for: selectedPeriod)
        localPlansByMonth = await loadLocalPlans(monthKeys: monthKeys)

        if let cachedSummary = await cacheStore.get(CacheKeys.statsSummary, as: AthleteStatsSummaryResponse.self, namespace: userSub) {
            statsSummary = cachedSummary
            isShowingCachedData = true
        }

        if let cachedPRs = await cacheStore.get(CacheKeys.personalRecords, as: [AthletePersonalRecord].self, namespace: userSub) {
            personalRecords = cachedPRs
            isShowingCachedData = true
        }

        if let cachedActiveEnrollment = await cacheStore.get(
            CacheKeys.activeEnrollmentProgress,
            as: ActiveEnrollmentProgressResponse.self,
            namespace: userSub,
        ) {
            activeEnrollmentProgress = cachedActiveEnrollment
            isShowingCachedData = true
        }

        for month in monthKeys {
            if let cachedCalendar = await cacheStore.get(CacheKeys.calendar(month: month), as: AthleteCalendarResponse.self, namespace: userSub) {
                calendarByMonth[month] = cachedCalendar
                isShowingCachedData = true
            }
        }

        rebuildDerivedState()
        await preloadVisibleExerciseMetadata(limit: 20)

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            if statsSummary == nil, personalRecords.isEmpty, localHistory.isEmpty {
                errorMessage = "Нет сети и кэшированных данных. Подключитесь к интернету и обновите экран."
            }
            return
        }

        await fetchRemoteStatsAndPRs(client: athleteTrainingClient)
        await fetchRemoteCalendars(client: athleteTrainingClient, monthKeys: monthKeys)
        await fetchRemoteNextAction(client: athleteTrainingClient)

        rebuildDerivedState()
        await preloadVisibleExerciseMetadata(limit: 20)

        if statsSummary == nil, personalRecords.isEmpty, localHistory.isEmpty {
            errorMessage = "Не удалось загрузить прогресс. Попробуйте позже."
        }
    }

    func selectPeriod(_ period: ProgressPeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period

        let monthKeys = requiredMonthKeys(for: period)
        localPlansByMonth = await loadLocalPlans(monthKeys: monthKeys)

        for month in monthKeys where calendarByMonth[month] == nil {
            if let cachedCalendar = await cacheStore.get(CacheKeys.calendar(month: month), as: AthleteCalendarResponse.self, namespace: userSub) {
                calendarByMonth[month] = cachedCalendar
                isShowingCachedData = true
            }
        }

        if networkMonitor.currentStatus, let athleteTrainingClient {
            await fetchRemoteCalendars(client: athleteTrainingClient, monthKeys: monthKeys)
        }

        rebuildDerivedState()
    }

    func selectHistoryFilter(_ filter: ProgressHistorySourceFilter) {
        selectedHistoryFilter = filter
        rebuildHistoryGroups()
    }

    func updateSearchQuery(_ query: String) async {
        searchQuery = query
        await preloadVisibleExerciseMetadata(limit: 20)
    }

    func exerciseItem(withExerciseId exerciseId: String) -> ExerciseProgressListItem? {
        allExerciseItems.first(where: { $0.exerciseId == exerciseId })
    }

    func makeExerciseDetailsViewModel(for item: ExerciseProgressListItem) -> ExerciseProgressDetailsViewModel {
        ExerciseProgressDetailsViewModel(
            userSub: userSub,
            item: item,
            initialPRs: personalRecords.filter { $0.exerciseId == item.exerciseId },
            athleteTrainingClient: athleteTrainingClient,
            cacheStore: cacheStore,
            networkMonitor: networkMonitor,
        )
    }

    func summaryForRecord(_ record: CompletedWorkoutRecord) async -> WorkoutSummaryState {
        var comparison: WorkoutSummaryState.ComparisonDelta?
        var hasPR = false
        var personalRecordHighlights: [String] = []

        if let athleteTrainingClient,
           record.workoutId.isUUID,
           networkMonitor.currentStatus
        {
            let result = await athleteTrainingClient.workoutComparison(workoutInstanceId: record.workoutId)
            if case let .success(response) = result,
               let previousWorkoutId = response.previousWorkoutInstanceId?.trimmedNilIfEmpty
            {
                comparison = WorkoutSummaryState.ComparisonDelta(
                    previousWorkoutInstanceId: previousWorkoutId,
                    repsDelta: response.repsDelta,
                    volumeDelta: response.volumeDelta,
                    durationDeltaSeconds: response.durationDeltaSeconds,
                )
                personalRecordHighlights = makePersonalRecordHighlights(response.personalRecords ?? [])
                hasPR = response.hasNewPersonalRecord == true || !personalRecordHighlights.isEmpty
            }
        }

        return WorkoutSummaryState(
            id: "history-\(record.id)",
            workoutTitle: record.workoutTitle,
            durationSeconds: max(0, record.durationSeconds),
            totalSets: max(0, record.completedSets),
            totalReps: 0,
            volume: max(0, record.volume),
            comparison: comparison,
            nextWorkout: nil,
            hasNewPersonalRecord: hasPR,
            personalRecordHighlights: personalRecordHighlights,
        )
    }

    private func makePersonalRecordHighlights(_ records: [AthletePersonalRecord]) -> [String] {
        records.prefix(3).map { record in
            let exerciseName = record.exerciseName?.trimmedNilIfEmpty ?? "Упражнение"
            return "\(exerciseName): \(record.displayValue) — личный рекорд"
        }
    }

    private func fetchRemoteStatsAndPRs(client: AthleteTrainingClientProtocol) async {
        async let summaryResult = client.statsSummary()
        async let prsResult = client.personalRecords(exerciseId: nil)

        let resolvedSummary = await summaryResult
        switch resolvedSummary {
        case let .success(summary):
            statsSummary = summary
            await cacheStore.set(CacheKeys.statsSummary, value: summary, namespace: userSub, ttl: cacheTTL)
            isShowingCachedData = false
        case .failure:
            break
        }

        let resolvedPRs = await prsResult
        switch resolvedPRs {
        case let .success(prs):
            personalRecords = prs.records
            await cacheStore.set(CacheKeys.personalRecords, value: prs.records, namespace: userSub, ttl: cacheTTL)
            isShowingCachedData = false
        case .failure:
            break
        }
    }

    private func fetchRemoteCalendars(
        client: AthleteTrainingClientProtocol,
        monthKeys: [String],
    ) async {
        await withTaskGroup(of: (String, AthleteCalendarResponse?).self) { group in
            for month in monthKeys {
                group.addTask {
                    let result = await client.calendar(month: month)
                    switch result {
                    case let .success(calendar):
                        return (month, calendar)
                    case .failure:
                        return (month, nil)
                    }
                }
            }

            for await (month, response) in group {
                guard let response else { continue }
                calendarByMonth[month] = response
                await cacheStore.set(CacheKeys.calendar(month: month), value: response, namespace: userSub, ttl: cacheTTL)
                isShowingCachedData = false
            }
        }
    }

    private func fetchRemoteNextAction(client: AthleteTrainingClientProtocol) async {
        let result = await client.activeEnrollmentProgress()
        if case let .success(progress) = result {
            activeEnrollmentProgress = progress
            await cacheStore.set(
                CacheKeys.activeEnrollmentProgress,
                value: progress,
                namespace: userSub,
                ttl: cacheTTL,
            )
            isShowingCachedData = false
        }
    }

    private func loadLocalPlans(monthKeys: [String]) async -> [String: [TrainingDayPlan]] {
        var result: [String: [TrainingDayPlan]] = [:]

        for month in monthKeys {
            guard let monthDate = Self.monthIDFormatter.date(from: month) else { continue }
            let plans = await trainingStore.plans(userSub: userSub, month: monthDate)
            if !plans.isEmpty {
                result[month] = plans
            }
        }

        return result
    }

    private func rebuildDerivedState() {
        rebuildOverview()
        rebuildNextAction()
        rebuildExerciseItems()
        rebuildHistoryGroups()
    }

    private func rebuildOverview() {
        let fallbackStreak = computeLocalStreakDays(history: localHistory)
        let fallbackWorkouts7d = workouts(inLast: 7, history: localHistory)
        let fallbackTotalMinutes7d = minutes(inLast: 7, history: localHistory)

        let summary = statsSummary
        let adherence = adherenceSnapshot(for: selectedPeriod)

        overview = ProgressOverviewSnapshot(
            streakDays: max(0, summary?.streakDays ?? fallbackStreak),
            workouts7d: max(0, summary?.workouts7d ?? fallbackWorkouts7d),
            totalWorkouts: max(0, summary?.totalWorkouts ?? localHistory.count),
            totalMinutes7d: max(0, summary?.totalMinutes7d ?? fallbackTotalMinutes7d),
            totalVolume7d: max(0, volume(inLast: 7, history: localHistory)),
            adherence: adherence,
        )

        let groupedPRs = Dictionary(grouping: personalRecords) { record in
            (record.exerciseId?.trimmedNilIfEmpty ?? "name:\((record.exerciseName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
        }

        let recentPRCandidate = groupedPRs
            .compactMap { _, records -> (record: AthletePersonalRecord, date: Date)? in
                guard let best = records.max(by: { ($0.achievedAtDate ?? .distantPast) < ($1.achievedAtDate ?? .distantPast) }),
                      let date = best.achievedAtDate
                else {
                    return nil
                }
                return (best, date)
            }
            .max(by: { $0.date < $1.date })

        let context = ProgressInsightContext(
            workouts7d: overview.workouts7d,
            missedCount: overview.adherence.missed,
            recentPRExerciseId: recentPRCandidate?.record.exerciseId,
            recentPRExerciseName: recentPRCandidate?.record.exerciseName,
            recentPRDate: recentPRCandidate?.date,
            lastWorkoutDate: summary?.lastWorkoutAtDate ?? localHistory.first?.finishedAt,
        )

        insight = ProgressInsightEngine.resolve(context: context, now: Date(), calendar: calendar)
        weeklyHighlight = resolveWeeklyHighlight(from: groupedPRs)
    }

    private func rebuildNextAction() {
        guard let progress = activeEnrollmentProgress else {
            nextAction = .startWorkout
            return
        }

        let nextWorkoutId = progress.nextWorkoutId?.trimmedNilIfEmpty
        let nextWorkoutTitle = progress.nextWorkoutTitle?.trimmedNilIfEmpty
        let hasNext = nextWorkoutId != nil
        nextAction = ProgressNextActionSnapshot(
            hasNextWorkout: hasNext,
            nextWorkoutId: nextWorkoutId,
            nextWorkoutTitle: nextWorkoutTitle,
        )
    }

    private func rebuildExerciseItems() {
        let grouped = Dictionary(grouping: personalRecords) { record in
            record.exerciseId?.trimmedNilIfEmpty ?? "name:\((record.exerciseName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }

        let formatter = Self.listDateFormatter

        allExerciseItems = grouped.map { key, records in
            let exerciseID = records.compactMap { $0.exerciseId?.trimmedNilIfEmpty }.first
            let exerciseName = records.compactMap { $0.exerciseName?.trimmedNilIfEmpty }.first ?? "Упражнение"
            let best = records.max { lhs, rhs in
                (lhs.value ?? 0) < (rhs.value ?? 0)
            }

            let prText: String
            if let best {
                prText = best.displayValue
            } else {
                prText = "—"
            }

            let recentPRDate = records.compactMap(\ .achievedAtDate).max()
            let meta = exerciseID.flatMap { exerciseHistoryMetaById[$0] }
            let lastPerformedAt = meta?.lastPerformedAt ?? recentPRDate
            let lastPerformedText = if let lastPerformedAt {
                formatter.string(from: lastPerformedAt)
            } else {
                "—"
            }

            return ExerciseProgressListItem(
                id: key,
                exerciseId: exerciseID,
                name: exerciseName,
                prText: prText,
                lastPerformedText: lastPerformedText,
                trendLabel: meta?.trendLabel,
                lastPerformedAt: lastPerformedAt,
                recentPRAt: recentPRDate,
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func rebuildHistoryGroups() {
        let periodFiltered = filterByPeriod(records: localHistory, period: selectedPeriod)
        let sourceFiltered = periodFiltered.filter { record in
            switch selectedHistoryFilter {
            case .all:
                true
            case .program:
                record.source == .program
            case .custom:
                record.source != .program
            }
        }

        let groups = Dictionary(grouping: sourceFiltered) { record in
            calendar.date(from: calendar.dateComponents([.year, .month], from: record.finishedAt)) ?? record.finishedAt
        }

        let formatter = Self.groupDateFormatter

        historyGroups = groups
            .map { key, records in
                ProgressHistoryGroup(
                    id: Self.monthIDFormatter.string(from: key),
                    title: formatter.string(from: key),
                    records: records.sorted(by: { $0.finishedAt > $1.finishedAt }),
                )
            }
            .sorted(by: { $0.id > $1.id })
    }

    private func filterByPeriod(records: [CompletedWorkoutRecord], period: ProgressPeriod) -> [CompletedWorkoutRecord] {
        guard let days = period.days else { return records }

        let lowerBound = calendar
            .date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast

        return records.filter { $0.finishedAt >= lowerBound }
    }

    private func adherenceSnapshot(for period: ProgressPeriod) -> ProgressAdherenceSnapshot {
        var planned = 0
        var completed = 0
        var missed = 0

        let workouts = requiredMonthKeys(for: period)
            .compactMap { calendarByMonth[$0] }
            .flatMap(\ .workouts)

        let filteredWorkouts = workouts.filter { workout in
            guard let workoutDate = dateForWorkout(workout) else { return false }
            return isDateInPeriod(workoutDate, period: period)
        }

        for workout in filteredWorkouts {
            switch workout.status {
            case .planned:
                planned += 1
            case .completed:
                completed += 1
            case .missed:
                missed += 1
            case .inProgress, .abandoned, .none:
                continue
            }
        }

        if planned == 0, completed == 0, missed == 0 {
            for month in requiredMonthKeys(for: period) {
                for plan in localPlansByMonth[month] ?? [] where isDateInPeriod(plan.day, period: period) {
                    switch plan.status {
                    case .planned:
                        planned += 1
                    case .completed:
                        completed += 1
                    case .missed:
                        missed += 1
                    }
                }
            }
        }

        return ProgressAdherenceSnapshot(planned: planned, completed: completed, missed: missed)
    }

    private func computeLocalStreakDays(history: [CompletedWorkoutRecord]) -> Int {
        let uniqueDays = Set(history.map { calendar.startOfDay(for: $0.finishedAt) })
        guard !uniqueDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: Date())

        while uniqueDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        return streak
    }

    private func workouts(inLast days: Int, history: [CompletedWorkoutRecord]) -> Int {
        let lowerBound = calendar
            .date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        return history.count(where: { $0.finishedAt >= lowerBound })
    }

    private func minutes(inLast days: Int, history: [CompletedWorkoutRecord]) -> Int {
        let lowerBound = calendar
            .date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        return history
            .filter { $0.finishedAt >= lowerBound }
            .reduce(0) { partial, item in
                partial + max(1, item.durationSeconds / 60)
            }
    }

    private func volume(inLast days: Int, history: [CompletedWorkoutRecord]) -> Double {
        let lowerBound = calendar
            .date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        return history
            .filter { $0.finishedAt >= lowerBound }
            .reduce(0) { partial, item in
                partial + max(0, item.volume)
            }
    }

    private func requiredMonthKeys(for period: ProgressPeriod) -> [String] {
        let monthCount: Int = switch period {
        case .days7:
            2
        case .days30:
            2
        case .days90:
            4
        case .all:
            12
        }

        return (0 ..< monthCount).compactMap { index in
            guard let date = calendar.date(byAdding: .month, value: -index, to: Date()) else { return nil }
            return Self.monthIDFormatter.string(from: date)
        }
    }

    private func dateForWorkout(_ workout: AthleteWorkoutInstance) -> Date? {
        if let scheduled = workout.scheduledDate,
           let parsed = Self.dayOnlyFormatter.date(from: scheduled)
        {
            return parsed
        }

        if let parsed = ProgressDateParser.parse(workout.completedAt) {
            return parsed
        }
        if let parsed = ProgressDateParser.parse(workout.startedAt) {
            return parsed
        }
        return nil
    }

    private func isDateInPeriod(_ date: Date, period: ProgressPeriod) -> Bool {
        guard let days = period.days else { return true }

        let lowerBound = calendar
            .date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        return date >= lowerBound
    }

    private func resolveWeeklyHighlight(from groupedPRs: [String: [AthletePersonalRecord]]) -> WeeklyHighlightSnapshot? {
        let weekStart = calendar
            .date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date.distantPast

        var candidate: (record: AthletePersonalRecord, previous: AthletePersonalRecord?)?

        for records in groupedPRs.values {
            let sorted = records.sorted { ($0.achievedAtDate ?? .distantPast) < ($1.achievedAtDate ?? .distantPast) }
            guard let latest = sorted.last,
                  let achievedAt = latest.achievedAtDate,
                  achievedAt >= weekStart
            else {
                continue
            }

            let previous = sorted.dropLast().last

            if let current = candidate {
                let currentDate = current.record.achievedAtDate ?? .distantPast
                if achievedAt > currentDate {
                    candidate = (latest, previous)
                }
            } else {
                candidate = (latest, previous)
            }
        }

        guard let candidate else { return nil }

        let exerciseName = candidate.record.exerciseName?.trimmedNilIfEmpty ?? "Упражнение"
        let contextDate = candidate.record.achievedAtDate ?? Date()
        let contextText = "Обновлено \(Self.listDateFormatter.string(from: contextDate))"

        let improvementText: String
        if let currentValue = candidate.record.value,
           let previousValue = candidate.previous?.value
        {
            let delta = currentValue - previousValue
            if delta > 0.01 {
                let deltaText = formatSigned(delta)
                let unit = candidate.record.unit?.trimmedNilIfEmpty ?? ""
                improvementText = "\(deltaText)\(unit.isEmpty ? "" : " \(unit)") — личный рекорд"
            } else {
                improvementText = "Новый личный рекорд"
            }
        } else {
            improvementText = "Новый личный рекорд"
        }

        return WeeklyHighlightSnapshot(
            id: candidate.record.id,
            exerciseName: exerciseName,
            improvementText: improvementText,
            contextText: contextText,
        )
    }

    private func formatSigned(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        let absValue = abs(value)
        if floor(absValue) == absValue {
            return "\(sign)\(Int(absValue))"
        }
        return "\(sign)\(String(format: "%.1f", absValue))"
    }

    func preloadVisibleExerciseMetadata(limit: Int) async {
        let visibleIDs = exerciseItems
            .compactMap(\ .exerciseId)
            .filter { !loadedExerciseMetaIds.contains($0) }

        let targetIDs = Array(visibleIDs.prefix(max(1, limit)))
        guard !targetIDs.isEmpty else { return }

        let canFetchRemote = networkMonitor.currentStatus
        let cacheStore = self.cacheStore
        let athleteTrainingClient = self.athleteTrainingClient
        let userSub = self.userSub
        let cacheTTL = self.cacheTTL

        await withTaskGroup(of: (String, [AthleteExerciseHistoryEntry]?).self) { group in
            for exerciseID in targetIDs {
                group.addTask {
                    let cacheKey = CacheKeys.exerciseHistory(exerciseId: exerciseID)
                    if let cached = await cacheStore.get(cacheKey, as: [AthleteExerciseHistoryEntry].self, namespace: userSub) {
                        return (exerciseID, cached)
                    }

                    guard canFetchRemote, let athleteTrainingClient else {
                        return (exerciseID, nil)
                    }

                    let result = await athleteTrainingClient.exerciseHistory(exerciseId: exerciseID, page: 0, size: 10)
                    switch result {
                    case let .success(response):
                        let entries = Array(response.entries.prefix(10))
                        await cacheStore.set(cacheKey, value: entries, namespace: userSub, ttl: cacheTTL)
                        return (exerciseID, entries)
                    case .failure:
                        return (exerciseID, nil)
                    }
                }
            }

            for await (exerciseID, entries) in group {
                loadedExerciseMetaIds.insert(exerciseID)
                guard let entries, !entries.isEmpty else { continue }
                exerciseHistoryMetaById[exerciseID] = Self.historyMeta(from: entries)
            }
        }

        rebuildExerciseItems()
    }

    private static func historyMeta(from entries: [AthleteExerciseHistoryEntry]) -> ExerciseHistoryMeta {
        let sorted = entries.sorted { lhs, rhs in
            (lhs.performedAtDate ?? .distantPast) > (rhs.performedAtDate ?? .distantPast)
        }

        let lastPerformedAt = sorted.first?.performedAtDate

        guard sorted.count >= 2 else {
            return ExerciseHistoryMeta(lastPerformedAt: lastPerformedAt, trendLabel: nil)
        }

        let latestVolume = sorted.first?.volume ?? 0
        let oldestVolume = sorted.last?.volume ?? 0
        let trendLabel: String?

        if latestVolume > oldestVolume + 1 {
            trendLabel = "↑"
        } else if latestVolume + 1 < oldestVolume {
            trendLabel = "↓"
        } else {
            trendLabel = "→"
        }

        return ExerciseHistoryMeta(lastPerformedAt: lastPerformedAt, trendLabel: trendLabel)
    }

    private static let monthIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let dayOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let listDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let groupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

struct TrainingInsightsView: View {
    @State var viewModel: TrainingInsightsViewModel

    var isOnline: Bool = true
    var onOpenPlan: () -> Void = {}
    var onStartNextWorkout: () -> Void = {}

    @State private var selectedExercise: ExerciseProgressListItem?
    @State private var trackedHighlightID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isOffline {
                    FFCard {
                        Text("Нет сети — показаны сохранённые данные")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                if viewModel.isShowingCachedData {
                    FFCard {
                        Text("Часть данных показана из кэша")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                sectionContent
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Прогресс")
        .refreshable {
            await viewModel.reload()
        }
        .task {
            viewModel.updateNetworkStatus(isOnline)
            await viewModel.onAppear()
            ClientAnalytics.track(.progressScreenOpened)
        }
        .onChange(of: isOnline) { _, online in
            viewModel.updateNetworkStatus(online)
        }
        .onChange(of: viewModel.weeklyHighlight?.id) { _, newValue in
            guard let newValue, trackedHighlightID != newValue else { return }
            trackedHighlightID = newValue
            ClientAnalytics.track(
                .progressWeeklyHighlightShown,
                properties: ["highlight_id": newValue],
            )
        }
        .navigationDestination(item: $selectedExercise) { item in
            ExerciseProgressDetailsView(viewModel: viewModel.makeExerciseDetailsViewModel(for: item))
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if viewModel.isLoading, !viewModel.didInitialLoad {
            FFLoadingState(title: "Загружаем прогресс")
        } else if let errorMessage = viewModel.errorMessage,
                  viewModel.overview.totalWorkouts == 0,
                  viewModel.exerciseItems.isEmpty,
                  viewModel.historyGroups.isEmpty
        {
            FFErrorState(
                title: "Прогресс недоступен",
                message: errorMessage,
                retryTitle: "Обновить",
                onRetry: { Task { await viewModel.reload() } },
            )
        } else if viewModel.overview.totalWorkouts == 0, viewModel.exerciseItems.isEmpty {
            FFCard {
                VStack(alignment: .center, spacing: FFSpacing.sm) {
                    Text("Пока нет тренировок")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Завершите первую тренировку, и здесь появятся ваши достижения и история.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                        .multilineTextAlignment(.center)
                    FFButton(title: "Начать тренировку", variant: .primary) {
                        ClientAnalytics.track(.progressNextWorkoutTapped, properties: ["type": "empty"])
                        onStartNextWorkout()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ProgressOverviewView(
                overview: viewModel.overview,
                weeklyHighlight: viewModel.weeklyHighlight,
                selectedPeriod: viewModel.selectedPeriod,
                searchQuery: viewModel.searchQuery,
                exercises: viewModel.exerciseItems,
                nextAction: viewModel.nextAction,
                onSelectPeriod: { period in
                    Task { await viewModel.selectPeriod(period) }
                },
                onSearchChanged: { query in
                    Task { await viewModel.updateSearchQuery(query) }
                },
                onSelectExercise: { item in
                    ClientAnalytics.track(
                        .exerciseHistoryOpened,
                        properties: ["exercise_id": item.exerciseId ?? item.id],
                    )
                    selectedExercise = item
                },
                onStartNextAction: {
                    ClientAnalytics.track(
                        .progressNextWorkoutTapped,
                        properties: ["has_next": viewModel.nextAction.hasNextWorkout ? "1" : "0"],
                    )
                    onStartNextWorkout()
                },
            )
        }
    }
}

struct ProgressOverviewView: View {
    let overview: ProgressOverviewSnapshot
    let weeklyHighlight: WeeklyHighlightSnapshot?
    let selectedPeriod: ProgressPeriod
    let searchQuery: String
    let exercises: [ExerciseProgressListItem]
    let nextAction: ProgressNextActionSnapshot

    let onSelectPeriod: (ProgressPeriod) -> Void
    let onSearchChanged: (String) -> Void
    let onSelectExercise: (ExerciseProgressListItem) -> Void
    let onStartNextAction: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    HStack {
                        Text("Главное достижение недели")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                    }

                    if let weeklyHighlight {
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(weeklyHighlight.exerciseName)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(weeklyHighlight.improvementText)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.accent)
                            Text(weeklyHighlight.contextText)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    } else {
                        Text("Завершите тренировку, и здесь появятся ваши рекорды.")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }
            }

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    HStack {
                        Text("Сводка недели")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Spacer(minLength: FFSpacing.sm)
                        periodMenu
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FFSpacing.sm) {
                        overviewCard(title: "Тренировок за 7 дней", value: "\(overview.workouts7d)")
                        overviewCard(title: "Время (мин)", value: "\(overview.totalMinutes7d)")
                        overviewCard(title: "Общий объём", value: "\(Int(overview.totalVolume7d)) кг")
                        overviewCard(title: "Серия тренировок", value: "\(overview.streakDays) дн")
                    }
                }
            }

            ExerciseProgressListView(
                searchQuery: searchQuery,
                items: exercises,
                onSearchChanged: onSearchChanged,
                onSelectExercise: onSelectExercise,
            )

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Следующее действие")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    if let nextWorkoutTitle = nextAction.nextWorkoutTitle {
                        Text(nextWorkoutTitle)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    FFButton(title: nextAction.primaryTitle, variant: .primary) {
                        onStartNextAction()
                    }
                }
            }
        }
    }

    private var periodMenu: some View {
        Menu {
            ForEach(ProgressPeriod.allCases, id: \.self) { period in
                Button(period.title) {
                    onSelectPeriod(period)
                }
            }
        } label: {
            Label(selectedPeriod.title, systemImage: "calendar.badge.clock")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.accent)
        }
    }

    private func overviewCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FFSpacing.sm)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }
}

struct ExerciseProgressListView: View {
    let searchQuery: String
    let items: [ExerciseProgressListItem]

    let onSearchChanged: (String) -> Void
    let onSelectExercise: (ExerciseProgressListItem) -> Void

    var body: some View {
        VStack(spacing: FFSpacing.sm) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Упражнения")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    TextField(
                        "Поиск упражнения",
                        text: Binding(
                            get: { searchQuery },
                            set: { onSearchChanged($0) },
                        ),
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textPrimary)
                }
            }

            if items.isEmpty {
                FFCard {
                    Text("Когда появятся рекорды и история, здесь будет список упражнений.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            } else {
                LazyVStack(spacing: FFSpacing.sm) {
                    ForEach(items) { item in
                        Button {
                            onSelectExercise(item)
                        } label: {
                            FFCard {
                                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                    HStack(alignment: .top, spacing: FFSpacing.xs) {
                                        Text(item.name)
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                        Spacer(minLength: FFSpacing.sm)
                                        if let trendLabel = item.trendLabel {
                                            Text(trendLabel)
                                                .font(FFTypography.caption.weight(.bold))
                                                .foregroundStyle(
                                                    trendLabel == "↑" ? FFColors.accent :
                                                        (trendLabel == "↓" ? FFColors.danger : FFColors.textSecondary),
                                                )
                                                .padding(.horizontal, FFSpacing.xs)
                                                .padding(.vertical, FFSpacing.xxs)
                                                .background(FFColors.gray700)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text("Личный рекорд: \(item.prText)")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)

                                    Text("Последняя тренировка: \(item.lastPerformedText)")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

@Observable
@MainActor
final class ExerciseProgressDetailsViewModel {
    let userSub: String
    let item: ExerciseProgressListItem

    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring

    private let cacheTTL: TimeInterval = 60 * 60 * 24

    var isLoading = false
    var isShowingCachedData = false
    var errorMessage: String?

    var prs: [AthletePersonalRecord]
    var historyEntries: [AthleteExerciseHistoryEntry] = []

    init(
        userSub: String,
        item: ExerciseProgressListItem,
        initialPRs: [AthletePersonalRecord],
        athleteTrainingClient: AthleteTrainingClientProtocol?,
        cacheStore: CacheStore,
        networkMonitor: NetworkMonitoring,
    ) {
        self.userSub = userSub
        self.item = item
        prs = initialPRs
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        isShowingCachedData = false

        guard let exerciseId = item.exerciseId?.trimmedNilIfEmpty else {
            errorMessage = "Для этого упражнения недоступен идентификатор истории."
            return
        }

        let cacheKey = "progress.exercise.history.\(exerciseId)"

        if let cachedHistory = await cacheStore.get(cacheKey, as: [AthleteExerciseHistoryEntry].self, namespace: userSub) {
            historyEntries = cachedHistory
            isShowingCachedData = true
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            if historyEntries.isEmpty {
                errorMessage = "Нет сети. Показана локальная история, если доступна."
            }
            return
        }

        async let prsResult = athleteTrainingClient.personalRecords(exerciseId: exerciseId)
        async let historyResult = athleteTrainingClient.exerciseHistory(exerciseId: exerciseId, page: 0, size: 10)

        let resolvedPRs = await prsResult
        if case let .success(response) = resolvedPRs {
            prs = response.records
        }

        let resolvedHistory = await historyResult
        switch resolvedHistory {
        case let .success(response):
            historyEntries = Array(response.entries.prefix(10))
            await cacheStore.set(cacheKey, value: historyEntries, namespace: userSub, ttl: cacheTTL)
            isShowingCachedData = false
        case .failure:
            if historyEntries.isEmpty {
                errorMessage = "Историю упражнения пока не удалось загрузить."
            }
        }
    }

    var lastTimeText: String {
        guard let first = historyEntries.sorted(by: { ($0.performedAtDate ?? .distantPast) > ($1.performedAtDate ?? .distantPast) }).first else {
            return "—"
        }
        return "\(first.bestSetText)"
    }

    var bestSetText: String {
        let best = historyEntries
            .compactMap { entry -> (weight: Double, reps: Int)? in
                guard let weight = entry.weight, let reps = entry.reps else { return nil }
                return (weight, reps)
            }
            .max { lhs, rhs in
                if abs(lhs.weight - rhs.weight) > 0.001 {
                    return lhs.weight < rhs.weight
                }
                return lhs.reps < rhs.reps
            }

        guard let best else { return "—" }
        if floor(best.weight) == best.weight {
            return "\(Int(best.weight)) × \(best.reps)"
        }
        return "\(String(format: "%.1f", best.weight)) × \(best.reps)"
    }

    var trendText: String? {
        let sorted = historyEntries.sorted { ($0.performedAtDate ?? .distantPast) > ($1.performedAtDate ?? .distantPast) }
        guard sorted.count >= 2 else { return nil }

        let latestVolume = sorted.first?.volume ?? volumeFallback(for: sorted.first)
        let oldestVolume = sorted.last?.volume ?? volumeFallback(for: sorted.last)
        guard let latestVolume, let oldestVolume else { return nil }

        if latestVolume > oldestVolume * 1.05 {
            return "Растёт"
        }
        if latestVolume < oldestVolume * 0.95 {
            return "Снижается"
        }
        return "Стабильный"
    }

    private func volumeFallback(for entry: AthleteExerciseHistoryEntry?) -> Double? {
        guard let entry, let weight = entry.weight, let reps = entry.reps else { return nil }
        return weight * Double(reps)
    }

    func loadWorkoutSummary(workoutInstanceId: String) async -> WorkoutSummaryState? {
        guard let athleteTrainingClient else { return nil }
        return await ProgressWorkoutSummaryBuilder.build(workoutInstanceId: workoutInstanceId, client: athleteTrainingClient)
    }
}

struct ExerciseProgressDetailsView: View {
    @State var viewModel: ExerciseProgressDetailsViewModel

    @State private var selectedWorkoutSummary: WorkoutSummaryState?

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                headerCard
                prsCard
                historyCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle(viewModel.item.name)
        .task {
            await viewModel.onAppear()
        }
        .navigationDestination(item: $selectedWorkoutSummary) { summary in
            WorkoutSummaryView(summary: summary)
        }
    }

    private var headerCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text(viewModel.item.name)
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)

                HStack(spacing: FFSpacing.xs) {
                    Text("Лучший подход:")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text(viewModel.bestSetText)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                }

                if let trendText = viewModel.trendText {
                    Text("Тренд: \(trendText)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }

                if viewModel.isShowingCachedData {
                    Text("Показаны кэшированные данные")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var prsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Личные рекорды")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if viewModel.prs.isEmpty {
                    Text("Личные рекорды пока не зафиксированы")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    ForEach(viewModel.prs.prefix(6)) { pr in
                        HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
                            Text(pr.metric?.trimmedNilIfEmpty ?? "Рекорд")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                            Spacer(minLength: FFSpacing.xs)
                            Text(pr.displayValue)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                HStack {
                    Text("Последние 10 выполнений")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer(minLength: FFSpacing.sm)
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FFColors.accent)
                    }
                }

                if let errorMessage = viewModel.errorMessage, viewModel.historyEntries.isEmpty {
                    Text(errorMessage)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                } else if viewModel.historyEntries.isEmpty {
                    Text("Истории пока нет")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    ForEach(viewModel.historyEntries.prefix(10)) { entry in
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(entry.performedAtDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Лучший подход: \(entry.bestSetText)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                            Text("Объём: \(Int(entry.volume ?? 0)) кг")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)

                            if let workoutInstanceId = entry.workoutInstanceId?.trimmedNilIfEmpty {
                                Button("Открыть тренировку") {
                                    Task {
                                        selectedWorkoutSummary = await viewModel.loadWorkoutSummary(
                                            workoutInstanceId: workoutInstanceId,
                                        )
                                    }
                                }
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.accent)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, FFSpacing.xxs)
                    }
                }
            }
        }
    }
}

struct ImprovedWorkoutHistoryView: View {
    let groups: [ProgressHistoryGroup]
    let selectedFilter: ProgressHistorySourceFilter

    let onFilterChanged: (ProgressHistorySourceFilter) -> Void
    let onSelectWorkout: (CompletedWorkoutRecord) -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                HStack {
                    Text("История тренировок")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer(minLength: FFSpacing.sm)
                    filterMenu
                }
            }

            if groups.isEmpty {
                FFEmptyState(
                    title: "История тренировок пуста",
                    message: "Завершите тренировку, чтобы увидеть историю по неделям и месяцам.",
                )
            } else {
                LazyVStack(spacing: FFSpacing.sm) {
                    ForEach(groups) { group in
                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                Text(group.title.capitalized)
                                    .font(FFTypography.h2)
                                    .foregroundStyle(FFColors.textPrimary)

                                ForEach(group.records) { record in
                                    Button {
                                        onSelectWorkout(record)
                                    } label: {
                                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                            HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
                                                Text(record.workoutTitle)
                                                    .font(FFTypography.body.weight(.semibold))
                                                    .foregroundStyle(FFColors.textPrimary)
                                                Spacer(minLength: FFSpacing.sm)
                                                Text(sourceLabel(for: record.source))
                                                    .font(FFTypography.caption.weight(.semibold))
                                                    .foregroundStyle(FFColors.textSecondary)
                                                    .padding(.horizontal, FFSpacing.xs)
                                                    .padding(.vertical, FFSpacing.xxs)
                                                    .background(FFColors.gray700)
                                                    .clipShape(Capsule())
                                            }

                                            Text(record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(FFTypography.caption)
                                                .foregroundStyle(FFColors.textSecondary)
                                            Text("\(record.completedSets)/\(record.totalSets) подходов • \(max(1, record.durationSeconds / 60)) мин")
                                                .font(FFTypography.caption)
                                                .foregroundStyle(FFColors.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, FFSpacing.xxs)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(ProgressHistorySourceFilter.allCases, id: \.self) { filter in
                Button(filter.title) {
                    onFilterChanged(filter)
                }
            }
        } label: {
            Label(selectedFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.accent)
        }
    }

    private func sourceLabel(for source: WorkoutSource) -> String {
        switch source {
        case .program:
            "ПРОГРАММА"
        case .freestyle, .template:
            "СВОЯ"
        }
    }
}

private enum ProgressWorkoutSummaryBuilder {
    static func build(workoutInstanceId: String, client: AthleteTrainingClientProtocol) async -> WorkoutSummaryState? {
        async let detailsResult = client.getWorkoutDetails(workoutInstanceId: workoutInstanceId)
        async let comparisonResult = client.workoutComparison(workoutInstanceId: workoutInstanceId)

        let details = await detailsResult
        let comparison = await comparisonResult

        var title = "Тренировка"
        var durationSeconds = 0
        var totalSets = 0
        var totalReps = 0
        var volume = 0.0
        var comparisonDelta: WorkoutSummaryState.ComparisonDelta?
        var hasPR = false
        var personalRecordHighlights: [String] = []

        if case let .success(detailsResponse) = details {
            title = detailsResponse.workout.title?.trimmedNilIfEmpty ?? title
            durationSeconds = detailsResponse.workout.durationSeconds ?? durationSeconds

            let allSets = detailsResponse.exercises.flatMap { $0.sets ?? [] }
            let completedSets = allSets.count(where: { $0.isCompleted })
            totalSets = completedSets > 0 ? completedSets : allSets.count
            totalReps = allSets.reduce(0) { $0 + max(0, $1.reps ?? 0) }
            volume = allSets.reduce(0) { partial, set in
                partial + Double(set.reps ?? 0) * max(0, set.weight ?? 0)
            }
        }

        if case let .success(comparisonResponse) = comparison {
            durationSeconds = comparisonResponse.durationSeconds ?? durationSeconds
            totalSets = comparisonResponse.totalSets ?? totalSets
            totalReps = comparisonResponse.totalReps ?? totalReps
            volume = comparisonResponse.volume ?? volume

            if let previousWorkoutId = comparisonResponse.previousWorkoutInstanceId?.trimmedNilIfEmpty {
                comparisonDelta = WorkoutSummaryState.ComparisonDelta(
                    previousWorkoutInstanceId: previousWorkoutId,
                    repsDelta: comparisonResponse.repsDelta,
                    volumeDelta: comparisonResponse.volumeDelta,
                    durationDeltaSeconds: comparisonResponse.durationDeltaSeconds,
                )
            }

            personalRecordHighlights = makePersonalRecordHighlights(comparisonResponse.personalRecords ?? [])
            hasPR = comparisonResponse.hasNewPersonalRecord == true || !personalRecordHighlights.isEmpty
        }

        if case .failure = details, case .failure = comparison {
            return nil
        }

        return WorkoutSummaryState(
            id: "progress-\(workoutInstanceId)",
            workoutTitle: title,
            durationSeconds: max(0, durationSeconds),
            totalSets: max(0, totalSets),
            totalReps: max(0, totalReps),
            volume: max(0, volume),
            comparison: comparisonDelta,
            nextWorkout: nil,
            hasNewPersonalRecord: hasPR,
            personalRecordHighlights: personalRecordHighlights,
        )
    }

    private static func makePersonalRecordHighlights(_ records: [AthletePersonalRecord]) -> [String] {
        records.prefix(3).map { record in
            let exerciseName = record.exerciseName?.trimmedNilIfEmpty ?? "Упражнение"
            return "\(exerciseName): \(record.displayValue) — личный рекорд"
        }
    }
}

private enum ProgressDateParser {
    private static let isoWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let parsed = isoWithFractions.date(from: value) {
            return parsed
        }
        return iso.date(from: value)
    }
}

private extension AthletePersonalRecord {
    var achievedAtDate: Date? {
        ProgressDateParser.parse(achievedAt)
    }

    var displayValue: String {
        guard let value else {
            return "—"
        }

        let metricLabel = metric?.trimmedNilIfEmpty ?? "Рекорд"
        let valueLabel: String
        if floor(value) == value {
            valueLabel = "\(Int(value))"
        } else {
            valueLabel = String(format: "%.1f", value)
        }

        let unitLabel = unit?.trimmedNilIfEmpty ?? ""
        if unitLabel.isEmpty {
            return "\(metricLabel): \(valueLabel)"
        }
        return "\(metricLabel): \(valueLabel) \(unitLabel)"
    }
}

private extension AthleteExerciseHistoryEntry {
    var performedAtDate: Date? {
        ProgressDateParser.parse(performedAt)
    }

    var bestSetText: String {
        let repsValue = reps ?? 0
        let weightValue = weight ?? 0

        let weightLabel: String
        if floor(weightValue) == weightValue {
            weightLabel = "\(Int(weightValue))"
        } else {
            weightLabel = String(format: "%.1f", weightValue)
        }

        return "\(weightLabel) × \(repsValue)"
    }
}

private extension AthleteStatsSummaryResponse {
    var lastWorkoutAtDate: Date? {
        ProgressDateParser.parse(lastWorkoutAt)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isUUID: Bool {
        UUID(uuidString: self) != nil
    }
}

#Preview {
    NavigationStack {
        TrainingInsightsView(viewModel: TrainingInsightsViewModel(userSub: "preview"))
    }
}
