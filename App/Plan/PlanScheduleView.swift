import Observation
import SwiftUI

enum PlanEntryOwnership: Equatable, Sendable {
    case remoteProgram
    case localProgramOverlay
    case remoteCustom
    case pendingCustom
    case localFreestyle
    case localTemplate

    var isProgram: Bool {
        switch self {
        case .remoteProgram, .localProgramOverlay:
            true
        case .remoteCustom, .pendingCustom, .localFreestyle, .localTemplate:
            false
        }
    }
}

enum PlanEntryDetailsState: Equatable, Sendable {
    case hydrated
    case placeholder
    case missing

    var isHydrated: Bool {
        self == .hydrated
    }

    static func resolve(
        workoutDetails: WorkoutDetailsModel?,
        source: WorkoutSource,
        fallbackTitle: String,
    ) -> Self {
        guard let workoutDetails else { return .missing }

        if !workoutDetails.exercises.isEmpty {
            return .hydrated
        }

        let trimmedCoachNote = workoutDetails.coachNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCoachNote.isEmpty {
            return .hydrated
        }

        if source == .program, workoutDetails.dayOrder > 0 {
            return .hydrated
        }

        let normalizedTitle = workoutDetails.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFallbackTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty,
           normalizedTitle.caseInsensitiveCompare(normalizedFallbackTitle) != .orderedSame
        {
            return .hydrated
        }

        return .placeholder
    }
}

enum PlanEntrySyncState: Equatable, Sendable {
    case none
    case pendingCreateCustomWorkout(operationId: UUID?)

    var pendingOperationId: UUID? {
        switch self {
        case .none:
            nil
        case .pendingCreateCustomWorkout(let operationId):
            operationId
        }
    }

    var isPendingCreateCustomWorkout: Bool {
        switch self {
        case .none:
            false
        case .pendingCreateCustomWorkout:
            true
        }
    }
}

struct PlanEntryStatus: Equatable, Sendable {
    let canonical: TrainingDayStatus
    let display: TrainingDayStatus
}

struct PlanEntry: Equatable, Sendable, Identifiable {
    let id: String
    let day: Date
    let title: String
    let source: WorkoutSource
    let programId: String?
    let programTitle: String?
    let workoutId: String?
    let workoutDetails: WorkoutDetailsModel?
    let ownership: PlanEntryOwnership
    let detailsState: PlanEntryDetailsState
    let syncState: PlanEntrySyncState
    let status: PlanEntryStatus

    var canonicalStatus: TrainingDayStatus {
        status.canonical
    }

    var displayStatus: TrainingDayStatus {
        status.display
    }

    func refreshingDisplayStatus(
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> PlanEntry {
        let refreshedDisplay = Self.resolveDisplayStatus(
            canonicalStatus,
            day: day,
            calendar: calendar,
            now: now,
        )
        guard refreshedDisplay != displayStatus else { return self }

        return PlanEntry(
            id: id,
            day: day,
            title: title,
            source: source,
            programId: programId,
            programTitle: programTitle,
            workoutId: workoutId,
            workoutDetails: workoutDetails,
            ownership: ownership,
            detailsState: detailsState,
            syncState: syncState,
            status: PlanEntryStatus(canonical: canonicalStatus, display: refreshedDisplay),
        )
    }

    fileprivate static func resolveDisplayStatus(
        _ canonicalStatus: TrainingDayStatus,
        day: Date,
        calendar: Calendar,
        now: Date,
    ) -> TrainingDayStatus {
        let normalizedDay = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if normalizedDay >= today, canonicalStatus.isMissedLike {
            return .planned
        }
        return canonicalStatus
    }
}

extension TrainingDayStatus {
    var planStatusTitle: String {
        switch self {
        case .planned:
            "Запланирована"
        case .inProgress:
            "В процессе"
        case .completed:
            "Выполнена"
        case .missed:
            "Пропущена"
        case .skipped:
            "Пропущена намеренно"
        }
    }
}

extension PlanEntry {
    static func canonicalStatus(from remoteStatus: AthleteWorkoutInstanceStatus?) -> TrainingDayStatus {
        switch remoteStatus {
        case .completed:
            return .completed
        case .missed:
            return .missed
        case .abandoned:
            return .skipped
        case .inProgress:
            return .inProgress
        case .planned, .none:
            return .planned
        }
    }

    static func source(from remoteSource: AthleteWorkoutSource) -> WorkoutSource {
        switch remoteSource {
        case .program:
            return .program
        case .custom:
            return .freestyle
        }
    }

    var scheduleReferenceWorkoutId: String? {
        workoutDetails?.id.trimmedNilIfEmpty ?? workoutId?.trimmedNilIfEmpty
    }

    var templateAnchorDayOrder: Int? {
        guard let dayOrder = workoutDetails?.dayOrder, dayOrder > 0 else { return nil }
        return dayOrder
    }
}

extension TrainingDayPlan {
    func asPlanEntry(
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> PlanEntry {
        let ownership = PlanEntryOwnership.resolve(
            planId: id,
            source: source,
            workoutId: workoutId,
            pendingSyncState: pendingSyncState,
        )
        let syncState = PlanEntrySyncState.resolve(
            pendingSyncState: pendingSyncState,
            pendingSyncOperationId: pendingSyncOperationId,
        )
        let detailsState = PlanEntryDetailsState.resolve(
            workoutDetails: workoutDetails,
            source: source,
            fallbackTitle: title,
        )
        return PlanEntry(
            id: id,
            day: day,
            title: title,
            source: source,
            programId: programId,
            programTitle: programTitle,
            workoutId: workoutId,
            workoutDetails: workoutDetails,
            ownership: ownership,
            detailsState: detailsState,
            syncState: syncState,
            status: PlanEntryStatus(
                canonical: status,
                display: PlanEntry.resolveDisplayStatus(
                    status,
                    day: day,
                    calendar: calendar,
                    now: now,
                )
            ),
        )
    }
}

private extension PlanEntryOwnership {
    static func resolve(
        planId: String,
        source: WorkoutSource,
        workoutId: String?,
        pendingSyncState: TrainingDayPendingSyncState?,
    ) -> PlanEntryOwnership {
        if pendingSyncState == .createCustomWorkout {
            return .pendingCustom
        }

        switch source {
        case .program:
            return planId.hasPrefix("remote-") ? .remoteProgram : .localProgramOverlay
        case .template:
            return .localTemplate
        case .freestyle:
            let hasWorkoutId = workoutId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            return planId.hasPrefix("remote-") && hasWorkoutId ? .remoteCustom : .localFreestyle
        }
    }
}

private extension PlanEntrySyncState {
    static func resolve(
        pendingSyncState: TrainingDayPendingSyncState?,
        pendingSyncOperationId: UUID?,
    ) -> PlanEntrySyncState {
        switch pendingSyncState {
        case .createCustomWorkout:
            return .pendingCreateCustomWorkout(operationId: pendingSyncOperationId)
        case nil:
            return .none
        }
    }
}

struct PlanReadModelMonthAssembly: Equatable, Sendable {
    let monthPlans: [PlanEntry]
    let contextPlans: [PlanEntry]
}

struct PlanScheduleReferenceSelection: Equatable, Sendable {
    let workoutId: String
    let day: Date
    let status: TrainingDayStatus
}

struct PlanTemplateAnchorSelection: Equatable, Sendable {
    let workoutId: String
    let dayOrder: Int
    let day: Date
    let status: TrainingDayStatus
}

enum PlanSharedSelectors {
    static func firstTodayEntry(
        from entries: [PlanEntry],
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> PlanEntry? {
        let today = calendar.startOfDay(for: now)
        return entries.first { calendar.isDate($0.day, inSameDayAs: today) }
    }

    static func todayEntries(
        from entries: [PlanEntry],
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> [PlanEntry] {
        let today = calendar.startOfDay(for: now)
        return entries.filter { calendar.isDate($0.day, inSameDayAs: today) }
    }

    static func workoutHomeStatus(for entry: PlanEntry) -> TrainingDayStatus? {
        workoutHomeStatus(for: entry.canonicalStatus)
    }

    static func workoutHomeStatus(for canonicalStatus: TrainingDayStatus) -> TrainingDayStatus? {
        switch canonicalStatus {
        case .planned, .inProgress:
            return canonicalStatus
        case .completed, .missed, .skipped:
            return nil
        }
    }

    static func scheduleReferences(
        from entries: [PlanEntry],
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> [String: PlanScheduleReferenceSelection] {
        let today = calendar.startOfDay(for: now)
        var references: [String: PlanScheduleReferenceSelection] = [:]
        var priorities: [String: Int] = [:]

        for entry in entries {
            guard let workoutId = entry.scheduleReferenceWorkoutId else { continue }
            let displayStatus = entry.refreshingDisplayStatus(calendar: calendar, now: now).displayStatus
            let priority = scheduleReferencePriority(
                for: displayStatus,
                day: entry.day,
                today: today,
                calendar: calendar,
            )

            if let existingPriority = priorities[workoutId], existingPriority > priority {
                continue
            }

            if let existingPriority = priorities[workoutId],
               existingPriority == priority,
               let existing = references[workoutId],
               existing.day > entry.day
            {
                continue
            }

            priorities[workoutId] = priority
            references[workoutId] = PlanScheduleReferenceSelection(
                workoutId: workoutId,
                day: entry.day,
                status: displayStatus,
            )
        }

        return references
    }

    static func templatePlanAnchors(
        from entries: [PlanEntry],
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> [String: PlanTemplateAnchorSelection] {
        var anchors: [String: PlanTemplateAnchorSelection] = [:]

        for entry in entries {
            guard let workoutId = entry.scheduleReferenceWorkoutId else { continue }
            guard let dayOrder = entry.templateAnchorDayOrder else { continue }
            let displayStatus = entry.refreshingDisplayStatus(calendar: calendar, now: now).displayStatus
            let candidate = PlanTemplateAnchorSelection(
                workoutId: workoutId,
                dayOrder: dayOrder,
                day: calendar.startOfDay(for: entry.day),
                status: displayStatus,
            )

            if let existing = anchors[workoutId] {
                if candidate.day > existing.day {
                    anchors[workoutId] = candidate
                }
            } else {
                anchors[workoutId] = candidate
            }
        }

        return anchors
    }

    private static func scheduleReferencePriority(
        for status: TrainingDayStatus,
        day: Date,
        today: Date,
        calendar: Calendar,
    ) -> Int {
        let normalizedDay = calendar.startOfDay(for: day)
        switch status {
        case .inProgress:
            return 5
        case .planned:
            return normalizedDay >= today ? 4 : 3
        case .completed:
            return 2
        case .missed, .skipped:
            return 1
        }
    }
}

struct PlanReadModelRepository {
    private let userSub: String
    private let trainingStore: TrainingStore
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let calendar: Calendar

    init(
        userSub: String,
        trainingStore: TrainingStore,
        athleteTrainingClient: AthleteTrainingClientProtocol?,
        cacheStore: CacheStore,
        networkMonitor: NetworkMonitoring,
        calendar: Calendar,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.calendar = calendar
    }

    func loadMonthAssembly(
        selectedMonth: Date,
        suppressedPlanSignatures: Set<String>,
    ) async -> PlanReadModelMonthAssembly {
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        let activeEnrollment = await activeEnrollmentProgress()

        async let previousPlans = plansForMonth(
            previousMonth,
            activeEnrollment: activeEnrollment,
            suppressedPlanSignatures: suppressedPlanSignatures,
        )
        async let selectedPlans = plansForMonth(
            selectedMonth,
            activeEnrollment: activeEnrollment,
            suppressedPlanSignatures: suppressedPlanSignatures,
        )
        async let nextPlans = plansForMonth(
            nextMonth,
            activeEnrollment: activeEnrollment,
            suppressedPlanSignatures: suppressedPlanSignatures,
        )

        let prevMonthPlans = await previousPlans
        let monthPlans = await selectedPlans
        let nextMonthPlans = await nextPlans
        let now = Date()
        return PlanReadModelMonthAssembly(
            monthPlans: monthPlans.map { $0.asPlanEntry(calendar: calendar, now: now) },
            contextPlans: (prevMonthPlans + monthPlans + nextMonthPlans)
                .map { $0.asPlanEntry(calendar: calendar, now: now) },
        )
    }

    func activeEnrollmentProgress() async -> ActiveEnrollmentProgressResponse? {
        if let cached = await cacheStore.get(
            cacheKeys.activeEnrollment,
            as: ActiveEnrollmentProgressResponse.self,
            namespace: userSub,
        ) {
            return cached
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            return nil
        }

        let result = await athleteTrainingClient.activeEnrollmentProgress()
        guard case let .success(progress) = result else {
            return nil
        }

        await cacheStore.set(cacheKeys.activeEnrollment, value: progress, namespace: userSub, ttl: 60 * 5)
        return progress
    }

    func deduplicateEntries(_ entries: [PlanEntry]) -> [PlanEntry] {
        var deduped: [PlanEntry] = []
        var seen = Set<String>()
        for entry in entries.sorted(by: { $0.day < $1.day }) {
            let key = entrySignature(entry)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(entry)
        }
        return deduped
    }

    func localEntries(
        month: Date,
        now: Date = Date(),
    ) async -> [PlanEntry] {
        await trainingStore.plans(userSub: userSub, month: month)
            .map { $0.asPlanEntry(calendar: calendar, now: now) }
    }

    func localEntries(
        months: [Date],
        now: Date = Date(),
    ) async -> [PlanEntry] {
        var entries: [PlanEntry] = []
        for month in months {
            let monthPlans = await trainingStore.plans(userSub: userSub, month: month)
            entries.append(contentsOf: monthPlans.map { $0.asPlanEntry(calendar: calendar, now: now) })
        }
        return deduplicateEntries(entries)
    }

    private func deduplicatePlans(_ plans: [TrainingDayPlan]) -> [TrainingDayPlan] {
        var deduped: [TrainingDayPlan] = []
        var seen = Set<String>()
        for plan in plans.sorted(by: { $0.day < $1.day }) {
            let key = planSignature(plan)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(plan)
        }
        return deduped
    }

    func hasHydratedWorkoutDetails(
        _ workoutDetails: WorkoutDetailsModel?,
        source: WorkoutSource,
        fallbackTitle: String,
    ) -> Bool {
        PlanEntryDetailsState.resolve(
            workoutDetails: workoutDetails,
            source: source,
            fallbackTitle: fallbackTitle,
        ).isHydrated
    }

    func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func plansForMonth(
        _ month: Date,
        activeEnrollment: ActiveEnrollmentProgressResponse?,
        suppressedPlanSignatures: Set<String>,
    ) async -> [TrainingDayPlan] {
        let localPlans = await trainingStore.plans(userSub: userSub, month: month)
        let cacheKey = cacheKeys.month(monthKey(for: month))
        var resolved = localPlans

        if let cached = await cacheStore.get(cacheKey, as: [TrainingDayPlan].self, namespace: userSub) {
            let cachedRemotePlans = cachedRemotePlansOnly(cached)
            if !cachedRemotePlans.isEmpty {
                resolved = merge(
                    local: localPlans,
                    remote: cachedRemotePlans,
                    suppressedPlanSignatures: suppressedPlanSignatures,
                )
            }
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            return resolved
        }

        let enrollmentId = activeEnrollment?.enrollmentId
        async let calendarResult = athleteTrainingClient.calendar(month: monthKey(for: month))
        async let scheduleResult: Result<AthleteEnrollmentScheduleResponse, APIError> = {
            guard let enrollmentId else { return .failure(.invalidURL) }
            return await athleteTrainingClient.enrollmentSchedule(enrollmentId: enrollmentId)
        }()

        var remotePlans: [TrainingDayPlan] = []

        if case let .success(calendarResponse) = await calendarResult {
            remotePlans.append(contentsOf: mapWorkouts(
                calendarResponse.workouts,
                month: month,
                activeEnrollment: activeEnrollment,
            ))
        }

        if case let .success(scheduleResponse) = await scheduleResult {
            remotePlans.append(contentsOf: mapWorkouts(
                scheduleResponse.workouts,
                month: month,
                activeEnrollment: activeEnrollment,
            ))
        }

        remotePlans = deduplicatePlans(remotePlans)
        if !remotePlans.isEmpty {
            resolved = merge(
                local: localPlans,
                remote: remotePlans,
                suppressedPlanSignatures: suppressedPlanSignatures,
            )
            await cacheStore.set(cacheKey, value: remotePlans, namespace: userSub, ttl: 60 * 10)
        }

        return resolved.sorted { $0.day < $1.day }
    }

    private func cachedRemotePlansOnly(_ plans: [TrainingDayPlan]) -> [TrainingDayPlan] {
        plans.filter { $0.id.hasPrefix("remote-") }
    }

    private func mapWorkouts(
        _ workouts: [AthleteWorkoutInstance],
        month: Date,
        activeEnrollment: ActiveEnrollmentProgressResponse?,
    ) -> [TrainingDayPlan] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        return workouts.compactMap { workout in
            guard let date = parseDate(workout.scheduledAt ?? workout.scheduledDate ?? workout.startedAt ?? workout.completedAt),
                  monthInterval.contains(date)
            else {
                return nil
            }

            return TrainingDayPlan(
                id: "remote-\(workout.id)",
                userSub: userSub,
                day: date,
                status: PlanEntry.canonicalStatus(from: workout.status),
                programId: workout.programId?.trimmedNilIfEmpty,
                programTitle: resolvedProgramTitle(for: workout, activeEnrollment: activeEnrollment),
                workoutId: workout.id,
                title: workout.title?.trimmedNilIfEmpty ?? "Тренировка",
                source: PlanEntry.source(from: workout.source),
                workoutDetails: nil,
            )
        }
    }

    private func resolvedProgramTitle(
        for workout: AthleteWorkoutInstance,
        activeEnrollment: ActiveEnrollmentProgressResponse?,
    ) -> String? {
        let workoutProgramID = workout.programId?.trimmedNilIfEmpty
        let activeProgramID = activeEnrollment?.programId?.trimmedNilIfEmpty
        guard workoutProgramID == activeProgramID else { return nil }
        return activeEnrollment?.programTitle?.trimmedNilIfEmpty
    }

    private func merge(
        local: [TrainingDayPlan],
        remote: [TrainingDayPlan],
        suppressedPlanSignatures: Set<String>,
    ) -> [TrainingDayPlan] {
        guard !remote.isEmpty else {
            return local
        }

        let filteredRemote = remote.filter { plan in
            guard let signature = remoteSuppressionSignature(plan) else { return true }
            return !suppressedPlanSignatures.contains(signature)
        }
        var merged = filteredRemote

        for item in local {
            guard let remoteIndex = merged.firstIndex(where: { remotePlan in
                remotePlan.id == item.id
            }) else {
                continue
            }
            merged[remoteIndex] = mergedRemotePlanPreservingLocalSchedule(remote: merged[remoteIndex], local: item)
        }

        var existing = Set(merged.map(planSignature))

        for item in local {
            if item.source == .program,
               merged.contains(where: { remote in
                   isRemoteEquivalent(remote: remote, toLocalProgramPlan: item)
               })
            {
                continue
            }
            let key = planSignature(item)
            guard !existing.contains(key) else { continue }
            existing.insert(key)
            merged.append(item)
        }

        return merged.sorted { $0.day < $1.day }
    }

    private func mergedRemotePlanPreservingLocalSchedule(remote: TrainingDayPlan, local: TrainingDayPlan) -> TrainingDayPlan {
        guard remote.id == local.id else { return remote }

        let sameDay = calendar.startOfDay(for: remote.day) == calendar.startOfDay(for: local.day)
        let remoteHasExplicitTime = sameDay && scheduledTimeText(for: remote.day) != nil
        let localHasExplicitTime = scheduledTimeText(for: local.day) != nil
        let resolvedDay: Date
        if sameDay {
            resolvedDay = !remoteHasExplicitTime && localHasExplicitTime ? local.day : remote.day
        } else {
            resolvedDay = local.day
        }

        return TrainingDayPlan(
            id: remote.id,
            userSub: remote.userSub,
            day: resolvedDay,
            status: sameDay ? remote.status : local.status,
            programId: remote.programId ?? local.programId,
            programTitle: local.programTitle ?? remote.programTitle,
            workoutId: remote.workoutId ?? local.workoutId,
            title: local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? remote.title : local.title,
            source: remote.source,
            workoutDetails: preferredWorkoutDetails(remote: remote, local: local),
            pendingSyncState: local.pendingSyncState,
            pendingSyncOperationId: local.pendingSyncOperationId,
        )
    }

    private func preferredWorkoutDetails(remote: TrainingDayPlan, local: TrainingDayPlan) -> WorkoutDetailsModel? {
        if hasHydratedWorkoutDetails(remote.workoutDetails, source: remote.source, fallbackTitle: remote.title) {
            return remote.workoutDetails
        }
        if hasHydratedWorkoutDetails(local.workoutDetails, source: local.source, fallbackTitle: local.title) {
            return local.workoutDetails
        }
        return nil
    }

    private func isRemoteEquivalent(remote: TrainingDayPlan, toLocalProgramPlan local: TrainingDayPlan) -> Bool {
        guard remote.id.hasPrefix("remote-"), remote.source == .program, local.source == .program else {
            return false
        }
        guard calendar.startOfDay(for: remote.day) == calendar.startOfDay(for: local.day) else {
            return false
        }
        guard remote.programId?.trimmedNilIfEmpty == local.programId?.trimmedNilIfEmpty else {
            return false
        }
        return remote.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(local.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func planSignature(_ plan: TrainingDayPlan) -> String {
        let date = calendar.startOfDay(for: plan.day)
        return "\(date.timeIntervalSince1970)::\(plan.id)"
    }

    private func entrySignature(_ entry: PlanEntry) -> String {
        let date = calendar.startOfDay(for: entry.day)
        return "\(date.timeIntervalSince1970)::\(entry.id)"
    }

    private func remoteSuppressionSignature(_ plan: TrainingDayPlan) -> String? {
        guard plan.id.hasPrefix("remote-"), let workoutId = plan.workoutId else { return nil }
        let date = calendar.startOfDay(for: plan.day)
        return "\(date.timeIntervalSince1970)::\(workoutId)"
    }

    private func scheduledTimeText(for date: Date) -> String? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        guard hour != 0 || minute != 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        if let withFractions = Self.iso8601WithFractions.date(from: value) {
            return withFractions
        }
        if let dateTime = Self.iso8601.date(from: value) {
            return dateTime
        }
        return Self.dateOnly.date(from: value)
    }

    private var cacheKeys: CacheKeys {
        CacheKeys()
    }

    private static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct CacheKeys {
        let activeEnrollment = "athlete.enrollment.active"

        func month(_ month: String) -> String {
            "athlete.plan.month.\(month)"
        }
    }
}

private func planWorkoutCacheKey(
    programId: String?,
    source: WorkoutSource,
    workoutId: String?,
) -> String {
    let resolvedProgramID = programId?.trimmedNilIfEmpty ?? source.rawValue
    let resolvedWorkoutID = workoutId?.trimmedNilIfEmpty ?? "unknown"
    return "workout.details:\(resolvedProgramID):\(resolvedWorkoutID)"
}

enum PlanMutationErrorKind: Sendable {
    case repeatScheduling
    case delete
    case plannedWorkoutUpdate
}

struct PlanMutationUserError: Sendable {
    let kind: PlanMutationErrorKind
    let message: String
}

struct PlanMutationOutcome: Sendable {
    let didMutate: Bool
    let focusDay: Date?
    let shouldReload: Bool
    let retrySyncAfterReload: Bool
    let broadcastDay: Date?
    let suppressedPlanSignatures: [String]
    let userError: PlanMutationUserError?

    static let noOp = PlanMutationOutcome(
        didMutate: false,
        focusDay: nil,
        shouldReload: false,
        retrySyncAfterReload: false,
        broadcastDay: nil,
        suppressedPlanSignatures: [],
        userError: nil,
    )
}

struct PlanMutationItem: Equatable, Sendable {
    let planId: String
    let day: Date
    let title: String
    let source: WorkoutSource
    let ownership: PlanEntryOwnership
    let detailsState: PlanEntryDetailsState
    let syncState: PlanEntrySyncState
    let canonicalStatus: TrainingDayStatus
    let programId: String?
    let programTitle: String?
    let workoutId: String?
    let workoutDetails: WorkoutDetailsModel?

    var isPendingRemoteCreation: Bool {
        syncState.isPendingCreateCustomWorkout
    }

    var pendingRemoteCreationOperationId: UUID? {
        syncState.pendingOperationId
    }

    var isRemoteCustomWorkout: Bool {
        ownership == .remoteCustom
    }

    var isManual: Bool {
        !ownership.isProgram
    }

    init(
        planId: String,
        day: Date,
        title: String,
        source: WorkoutSource,
        ownership: PlanEntryOwnership,
        detailsState: PlanEntryDetailsState,
        syncState: PlanEntrySyncState,
        canonicalStatus: TrainingDayStatus,
        programId: String?,
        programTitle: String?,
        workoutId: String?,
        workoutDetails: WorkoutDetailsModel?,
    ) {
        self.planId = planId
        self.day = day
        self.title = title
        self.source = source
        self.ownership = ownership
        self.detailsState = detailsState
        self.syncState = syncState
        self.canonicalStatus = canonicalStatus
        self.programId = programId
        self.programTitle = programTitle
        self.workoutId = workoutId
        self.workoutDetails = workoutDetails
    }

    init(entry: PlanEntry) {
        planId = entry.id
        day = entry.day
        title = entry.title
        source = entry.source
        ownership = entry.ownership
        detailsState = entry.detailsState
        syncState = entry.syncState
        canonicalStatus = entry.canonicalStatus
        programId = entry.programId
        programTitle = entry.programTitle
        workoutId = entry.workoutId
        workoutDetails = entry.workoutDetails
    }
}

struct PlanScheduleMutationRequest: Sendable {
    let day: Date
    let title: String
    let source: WorkoutSource
    let programId: String?
    let programTitle: String?
    let workoutId: String?
    let status: TrainingDayStatus
    let workoutDetails: WorkoutDetailsModel?
    let planId: String?
}

struct PlanRepeatWorkoutMutationRequest: Sendable {
    let workout: WorkoutDetailsModel
    let source: WorkoutSource
    let day: Date
}

struct PlanMoveMutationRequest: Sendable {
    let item: PlanMutationItem
    let targetDay: Date
    let statusOverride: TrainingDayStatus?
}

struct PlanReplanMutationRequest: Sendable {
    let item: PlanMutationItem
    let targetDay: Date
    let contextEntries: [PlanEntry]
}

struct PlanUpdateManualWorkoutMutationRequest: Sendable {
    let item: PlanMutationItem
    let workout: WorkoutDetailsModel
}

struct PlanDeleteMutationRequest: Sendable {
    let item: PlanMutationItem
}

struct PlanStatusMutationRequest: Sendable {
    let item: PlanMutationItem
    let status: TrainingDayStatus
}

struct PlanMutationService {
    private let userSub: String
    private let trainingStore: TrainingStore
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let calendar: Calendar

    init(
        userSub: String,
        trainingStore: TrainingStore,
        athleteTrainingClient: AthleteTrainingClientProtocol?,
        cacheStore: CacheStore,
        networkMonitor: NetworkMonitoring,
        calendar: Calendar,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.calendar = calendar
    }

    func schedule(_ request: PlanScheduleMutationRequest) async -> PlanMutationOutcome {
        let scheduledDay = normalizedScheduledDate(request.day)
        guard canSchedule(on: scheduledDay) else { return .noOp }

        let resolvedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TrainingDayPlan(
            id: request.planId ?? UUID().uuidString,
            userSub: userSub,
            day: scheduledDay,
            status: request.status,
            programId: request.programId,
            programTitle: request.programTitle?.trimmedNilIfEmpty,
            workoutId: request.workoutId,
            title: resolvedTitle.isEmpty ? "Тренировка" : resolvedTitle,
            source: request.source,
            workoutDetails: request.workoutDetails,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.schedule(plan)
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: scheduledDay,
            shouldReload: true,
            retrySyncAfterReload: false,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: nil,
        )
    }

    func repeatWorkout(_ request: PlanRepeatWorkoutMutationRequest) async -> PlanMutationOutcome {
        let scheduledDay = normalizedScheduledDate(request.day)
        guard canSchedule(on: scheduledDay) else { return .noOp }

        if request.source == .program {
            return await schedule(
                PlanScheduleMutationRequest(
                    day: scheduledDay,
                    title: request.workout.title,
                    source: .program,
                    programId: nil,
                    programTitle: nil,
                    workoutId: request.workout.id,
                    status: .planned,
                    workoutDetails: request.workout,
                    planId: nil,
                )
            )
        }

        let pendingPlanId = "pending-custom-\(UUID().uuidString)"

        if !networkMonitor.currentStatus {
            return await enqueuePendingRepeatedWorkout(
                request.workout,
                source: request.source,
                planId: pendingPlanId,
                on: scheduledDay,
            )
        }

        guard let athleteTrainingClient else {
            return failure(
                kind: .repeatScheduling,
                message: "Не удалось отправить запрос на сервер. Повторите попытку позже."
            )
        }

        let result = await athleteTrainingClient.createCustomWorkout(
            request: request.workout.asCreateCustomWorkoutRequest(scheduledDate: scheduledDay),
            idempotencyKey: SyncOperation.customWorkoutCreationIdempotencyKey(planId: pendingPlanId),
        )
        switch result {
        case let .success(detailsResponse):
            let expectedScheduledDate = scheduledDateTimeString(scheduledDay)
            guard detailsResponse.isValidFreshCustomWorkout(
                expectedScheduledDate: expectedScheduledDate
            ) else {
                let validationReason = detailsResponse.validationErrorForFreshCustomWorkout(
                    expectedScheduledDate: expectedScheduledDate
                ) ?? "unknown"
                print(
                    "[app] repeat-create-invalid-response workoutId=\(detailsResponse.workout.id) " +
                        "status=\(detailsResponse.workout.status?.rawValue ?? "nil") " +
                        "source=\(detailsResponse.workout.source.rawValue) " +
                        "scheduledDate=\(detailsResponse.workout.scheduledDate ?? "nil") " +
                        "scheduledAt=\(detailsResponse.workout.scheduledAt ?? "nil") " +
                        "reason=\(validationReason)"
                )
                return failure(
                    kind: .repeatScheduling,
                    message: "Сервер вернул некорректную копию тренировки. Новая тренировка не создана."
                )
            }
            return await storeRemoteRepeatedWorkout(detailsResponse, scheduledDay: scheduledDay)

        case let .failure(error):
            if shouldQueuePendingRepeatedWorkout(for: error) {
                return await enqueuePendingRepeatedWorkout(
                    request.workout,
                    source: request.source,
                    planId: pendingPlanId,
                    on: scheduledDay,
                )
            }
            return failure(
                kind: .repeatScheduling,
                message: repeatSchedulingErrorMessage(for: error)
            )
        }
    }

    func repeatCompleted(
        item: PlanMutationItem,
        on targetDay: Date,
        resolveWorkoutDetails: @escaping @Sendable (PlanMutationItem) async -> WorkoutDetailsModel?,
    ) async -> PlanMutationOutcome {
        guard item.canonicalStatus == .completed, item.isManual else { return .noOp }
        guard let resolvedWorkout = await resolveWorkoutDetails(item) ?? item.workoutDetails else {
            return .noOp
        }
        let repeatPrefix = item.source == .template ? "template-repeat" : "quick-repeat"
        let repeatedWorkout = resolvedWorkout.asRepeatableCopy(prefix: repeatPrefix)
        return await repeatWorkout(
            PlanRepeatWorkoutMutationRequest(
                workout: repeatedWorkout,
                source: item.source,
                day: targetDay,
            )
        )
    }

    func resolveRepeatableWorkout(
        for record: CompletedWorkoutRecord,
        templateWorkoutDetails: @escaping @Sendable (String) async -> WorkoutDetailsModel?,
    ) async -> WorkoutDetailsModel? {
        let cacheKey = planWorkoutCacheKey(
            programId: record.programId.trimmedNilIfEmpty,
            source: record.source,
            workoutId: record.workoutId.trimmedNilIfEmpty,
        )

        if let cachedDetails = await cacheStore.get(
            cacheKey,
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) {
            return cachedDetails
        }

        if let workoutDetails = record.workoutDetails {
            await cacheStore.set(
                cacheKey,
                value: workoutDetails,
                namespace: userSub,
                ttl: 60 * 60 * 24,
            )
            return workoutDetails
        }

        if record.source == .template,
           let templateID = record.workoutId.trimmedNilIfEmpty,
           let templateDetails = await templateWorkoutDetails(templateID)
        {
            await cacheStore.set(
                cacheKey,
                value: templateDetails,
                namespace: userSub,
                ttl: 60 * 60 * 24,
            )
            return templateDetails
        }

        if record.source != .template,
           let workoutInstanceId = record.workoutId.trimmedNilIfEmpty,
           UUID(uuidString: workoutInstanceId) != nil,
           let athleteTrainingClient,
           case let .success(detailsResponse) = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId)
        {
            let details = detailsResponse.asWorkoutDetailsModel()
            await cacheStore.set(
                cacheKey,
                value: details,
                namespace: userSub,
                ttl: 60 * 60 * 24,
            )
            return details
        }

        return nil
    }

    func replan(_ request: PlanReplanMutationRequest) async -> PlanMutationOutcome {
        let normalizedTarget = calendar.startOfDay(for: request.targetDay)
        guard canSchedule(on: normalizedTarget) else { return .noOp }

        var collectedSuppressions: [String] = []
        var surfacedError: PlanMutationUserError?
        let existingReplacement = existingReplannedCopy(for: request.item, in: request.contextEntries)

        if let existingReplacement {
            let deleteOutcome = await delete(
                PlanDeleteMutationRequest(item: existingReplacement),
                shouldBroadcast: false
            )
            collectedSuppressions.append(contentsOf: deleteOutcome.suppressedPlanSignatures)
            if let error = deleteOutcome.userError {
                surfacedError = error
            }
        }

        let moveOutcome = await move(
            PlanMoveMutationRequest(
                item: request.item,
                targetDay: request.targetDay,
                statusOverride: .planned,
            )
        )

        collectedSuppressions.append(contentsOf: moveOutcome.suppressedPlanSignatures)
        return PlanMutationOutcome(
            didMutate: moveOutcome.didMutate,
            focusDay: moveOutcome.focusDay,
            shouldReload: moveOutcome.shouldReload,
            retrySyncAfterReload: moveOutcome.retrySyncAfterReload,
            broadcastDay: moveOutcome.broadcastDay ?? existingReplacement?.day,
            suppressedPlanSignatures: collectedSuppressions,
            userError: moveOutcome.userError ?? surfacedError,
        )
    }

    func move(_ request: PlanMoveMutationRequest) async -> PlanMutationOutcome {
        let normalizedCurrent = calendar.startOfDay(for: request.item.day)
        let normalizedTarget = calendar.startOfDay(for: request.targetDay)
        guard normalizedCurrent != normalizedTarget else { return .noOp }
        guard canSchedule(on: normalizedTarget) else { return .noOp }

        let resolvedStatus = request.statusOverride ?? request.item.canonicalStatus
        if request.item.isPendingRemoteCreation {
            let workout = request.item.workoutDetails ?? editableDraft(for: request.item)
            return await updatePendingCustomWorkoutPlan(
                request.item,
                workout: workout,
                scheduledDay: request.targetDay,
            )
        }

        if request.item.isRemoteCustomWorkout,
           let workoutId = request.item.workoutId?.trimmedNilIfEmpty,
           let athleteTrainingClient
        {
            let result = await athleteTrainingClient.updateCustomWorkout(
                workoutInstanceId: workoutId,
                request: AthleteUpdateCustomWorkoutRequest(
                    title: nil,
                    scheduledDate: scheduledDayString(request.targetDay),
                    scheduledAt: scheduledDateTimeString(request.targetDay),
                    notes: request.item.workoutDetails?.coachNote?.trimmedNilIfEmpty,
                ),
            )
            if case .success = result {
                return PlanMutationOutcome(
                    didMutate: true,
                    focusDay: normalizedTarget,
                    shouldReload: true,
                    retrySyncAfterReload: false,
                    broadcastDay: nil,
                    suppressedPlanSignatures: [],
                    userError: nil,
                )
            }
        }

        let suppression = suppressionSignature(
            day: request.item.day,
            workoutId: request.item.workoutId,
            planId: request.item.planId,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.movePlan(
                    userSub: userSub,
                    from: request.item.day,
                    to: request.targetDay,
                    planId: request.item.planId,
                    workoutId: request.item.workoutId,
                    title: request.item.title,
                    source: request.item.source,
                    status: resolvedStatus,
                    programId: request.item.programId,
                    programTitle: request.item.programTitle,
                    workoutDetails: request.item.workoutDetails,
                )
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: normalizedTarget,
            shouldReload: true,
            retrySyncAfterReload: false,
            broadcastDay: nil,
            suppressedPlanSignatures: suppression.map { [$0] } ?? [],
            userError: nil,
        )
    }

    func updatePlannedManualWorkout(_ request: PlanUpdateManualWorkoutMutationRequest) async -> PlanMutationOutcome {
        guard request.item.canonicalStatus == .planned, request.item.isManual else { return .noOp }

        if request.item.isPendingRemoteCreation {
            return await updatePendingCustomWorkoutPlan(
                request.item,
                workout: request.workout,
                scheduledDay: request.item.day,
            )
        }

        if request.item.isRemoteCustomWorkout,
           let workoutId = request.item.workoutId?.trimmedNilIfEmpty,
           let athleteTrainingClient
        {
            let updateResult = await athleteTrainingClient.updateCustomWorkout(
                workoutInstanceId: workoutId,
                request: request.workout.asUpdateCustomWorkoutRequest(scheduledDate: request.item.day),
            )
            switch updateResult {
            case let .success(detailsResponse):
                let details = detailsResponse.asWorkoutDetailsModel()
                let updatedPlan = TrainingDayPlan(
                    id: request.item.planId,
                    userSub: userSub,
                    day: request.item.day,
                    status: request.item.canonicalStatus,
                    programId: request.item.programId,
                    programTitle: request.item.programTitle,
                    workoutId: workoutId,
                    title: details.title,
                    source: request.item.source,
                    workoutDetails: details,
                )

                await performMutationSideEffects(
                    persistence: {
                        await trainingStore.schedule(updatedPlan)
                    },
                    cache: {
                        await cacheStore.set(
                            planWorkoutCacheKey(
                                programId: request.item.programId,
                                source: request.item.source,
                                workoutId: workoutId,
                            ),
                            value: details,
                            namespace: userSub,
                            ttl: 60 * 60 * 24,
                        )
                    }
                )

                return PlanMutationOutcome(
                    didMutate: true,
                    focusDay: request.item.day,
                    shouldReload: true,
                    retrySyncAfterReload: false,
                    broadcastDay: nil,
                    suppressedPlanSignatures: [],
                    userError: nil,
                )
            case let .failure(error):
                return failure(
                    kind: .plannedWorkoutUpdate,
                    message: plannedWorkoutUpdateErrorMessage(for: error)
                )
            }
        }

        let resolvedTitle = request.workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWorkoutId = request.item.workoutId ?? request.workout.id
        let updated = TrainingDayPlan(
            id: request.item.planId,
            userSub: userSub,
            day: calendar.startOfDay(for: request.item.day),
            status: request.item.canonicalStatus,
            programId: request.item.programId,
            programTitle: request.item.programTitle,
            workoutId: resolvedWorkoutId,
            title: resolvedTitle.isEmpty ? request.item.title : resolvedTitle,
            source: request.item.source,
            workoutDetails: request.workout,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.schedule(updated)
            },
            cache: {
                await cacheStore.set(
                    planWorkoutCacheKey(
                        programId: request.item.programId,
                        source: request.item.source,
                        workoutId: resolvedWorkoutId,
                    ),
                    value: request.workout,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: request.item.day,
            shouldReload: true,
            retrySyncAfterReload: false,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: nil,
        )
    }

    func delete(_ request: PlanDeleteMutationRequest) async -> PlanMutationOutcome {
        await delete(request, shouldBroadcast: true)
    }

    func updateStatus(_ request: PlanStatusMutationRequest) async -> PlanMutationOutcome {
        let updated = TrainingDayPlan(
            id: request.item.planId,
            userSub: userSub,
            day: request.item.day,
            status: request.status,
            programId: request.item.programId,
            programTitle: request.item.programTitle,
            workoutId: request.item.workoutId,
            title: request.item.title,
            source: request.item.source,
            workoutDetails: request.item.workoutDetails,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.schedule(updated)
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: request.item.day,
            shouldReload: true,
            retrySyncAfterReload: false,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: nil,
        )
    }

    func cancelInProgress(_ item: PlanMutationItem) async -> PlanMutationOutcome {
        if item.source != .template,
           let workoutInstanceId = item.workoutId?.trimmedNilIfEmpty,
           UUID(uuidString: workoutInstanceId) != nil
        {
            let updated = TrainingDayPlan(
                id: item.planId,
                userSub: userSub,
                day: item.day,
                status: .skipped,
                programId: item.programId,
                programTitle: item.programTitle,
                workoutId: item.workoutId,
                title: item.title,
                source: item.source,
                workoutDetails: item.workoutDetails,
            )
            let suppression = suppressionSignature(day: item.day, workoutId: item.workoutId, planId: item.planId)

            await performMutationSideEffects(
                persistence: {
                    await trainingStore.schedule(updated)
                },
                sync: {
                    _ = await SyncCoordinator.shared.enqueueAbandonWorkout(
                        namespace: userSub,
                        workoutInstanceId: workoutInstanceId,
                        abandonedAt: Date(),
                    )
                },
                cache: {
                    await invalidateWorkoutCaches(for: item)
                },
                cleanup: {
                    await clearLocalWorkoutProgress(for: item)
                }
            )

            return PlanMutationOutcome(
                didMutate: true,
                focusDay: item.day,
                shouldReload: true,
                retrySyncAfterReload: false,
                broadcastDay: nil,
                suppressedPlanSignatures: suppression.map { [$0] } ?? [],
                userError: nil,
            )
        }

        return await updateStatus(
            PlanStatusMutationRequest(
                item: item,
                status: .skipped,
            )
        )
    }

    private func delete(
        _ request: PlanDeleteMutationRequest,
        shouldBroadcast: Bool,
    ) async -> PlanMutationOutcome {
        if request.item.isRemoteCustomWorkout {
            guard let workoutId = request.item.workoutId?.trimmedNilIfEmpty else {
                return failure(
                    kind: .delete,
                    message: "Не удалось определить тренировку для удаления."
                )
            }
            guard let athleteTrainingClient else {
                return failure(
                    kind: .delete,
                    message: "Не удалось удалить тренировку без соединения с сервером."
                )
            }

            let deleteResult = await athleteTrainingClient.deleteCustomWorkout(workoutInstanceId: workoutId)
            switch deleteResult {
            case .success:
                break
            case let .failure(error):
                if case let .httpError(statusCode, _) = error, statusCode == 404 {
                    break
                }
                return failure(
                    kind: .delete,
                    message: deleteErrorMessage(for: error)
                )
            }
        }

        let suppression = suppressionSignature(
            day: request.item.day,
            workoutId: request.item.workoutId,
            planId: request.item.planId,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.deletePlan(
                    userSub: userSub,
                    day: request.item.day,
                    planId: request.item.planId,
                    workoutId: request.item.workoutId,
                    title: request.item.title,
                    source: request.item.source,
                )
            },
            sync: {
                if request.item.isPendingRemoteCreation {
                    await SyncCoordinator.shared.cancelPendingCreateCustomWorkout(
                        namespace: userSub,
                        planId: request.item.planId,
                    )
                }
            },
            cache: {
                await invalidateWorkoutCaches(for: request.item)
            },
            cleanup: {
                await clearLocalWorkoutProgress(for: request.item)
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: request.item.day,
            shouldReload: true,
            retrySyncAfterReload: false,
            broadcastDay: shouldBroadcast ? request.item.day : nil,
            suppressedPlanSignatures: suppression.map { [$0] } ?? [],
            userError: nil,
        )
    }

    private func enqueuePendingRepeatedWorkout(
        _ workout: WorkoutDetailsModel,
        source: WorkoutSource,
        planId: String,
        on scheduledDay: Date,
    ) async -> PlanMutationOutcome {
        let normalizedSource: WorkoutSource = source == .template ? .template : .freestyle
        let queueResult = await SyncCoordinator.shared.enqueueCreateCustomWorkout(
            namespace: userSub,
            planId: planId,
            source: normalizedSource,
            workout: workout,
            scheduledDay: scheduledDay,
            processImmediately: false,
        )
        let pendingPlan = TrainingDayPlan(
            id: planId,
            userSub: userSub,
            day: scheduledDay,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: workout.id,
            title: workout.title,
            source: normalizedSource,
            workoutDetails: workout,
            pendingSyncState: .createCustomWorkout,
            pendingSyncOperationId: queueResult.operation?.id,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.schedule(pendingPlan)
            },
            cache: {
                await cacheStore.set(
                    planWorkoutCacheKey(programId: nil, source: normalizedSource, workoutId: workout.id),
                    value: workout,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: scheduledDay,
            shouldReload: true,
            retrySyncAfterReload: networkMonitor.currentStatus,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: nil,
        )
    }

    private func storeRemoteRepeatedWorkout(
        _ detailsResponse: AthleteWorkoutDetailsResponse,
        scheduledDay: Date,
    ) async -> PlanMutationOutcome {
        let details = detailsResponse.asWorkoutDetailsModel()
        let remoteMirror = TrainingDayPlan(
            id: "remote-\(details.id)",
            userSub: userSub,
            day: scheduledDay,
            status: .planned,
            programId: nil,
            programTitle: nil,
            workoutId: details.id,
            title: details.title,
            source: .freestyle,
            workoutDetails: details,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.schedule(remoteMirror)
            },
            cache: {
                await cacheStore.set(
                    planWorkoutCacheKey(programId: nil, source: .freestyle, workoutId: details.id),
                    value: details,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: scheduledDay,
            shouldReload: true,
            retrySyncAfterReload: false,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: nil,
        )
    }

    private func updatePendingCustomWorkoutPlan(
        _ item: PlanMutationItem,
        workout: WorkoutDetailsModel,
        scheduledDay: Date,
    ) async -> PlanMutationOutcome {
        let normalizedDay = normalizedScheduledDate(scheduledDay)
        let resolvedTitle = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let queueResult = await SyncCoordinator.shared.enqueueCreateCustomWorkout(
            namespace: userSub,
            planId: item.planId,
            source: item.source,
            workout: workout,
            scheduledDay: normalizedDay,
            processImmediately: false,
        )
        let updatedPlan = TrainingDayPlan(
            id: item.planId,
            userSub: userSub,
            day: normalizedDay,
            status: .planned,
            programId: item.programId,
            programTitle: item.programTitle,
            workoutId: workout.id,
            title: resolvedTitle.isEmpty ? item.title : resolvedTitle,
            source: item.source,
            workoutDetails: workout,
            pendingSyncState: .createCustomWorkout,
            pendingSyncOperationId: queueResult.operation?.id ?? item.pendingRemoteCreationOperationId,
        )

        await performMutationSideEffects(
            persistence: {
                await trainingStore.schedule(updatedPlan)
            },
            sync: {},
            cache: {
                await cacheStore.set(
                    planWorkoutCacheKey(programId: item.programId, source: item.source, workoutId: workout.id),
                    value: workout,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
            }
        )

        return PlanMutationOutcome(
            didMutate: true,
            focusDay: normalizedDay,
            shouldReload: true,
            retrySyncAfterReload: networkMonitor.currentStatus,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: nil,
        )
    }

    private func existingReplannedCopy(
        for item: PlanMutationItem,
        in entries: [PlanEntry],
    ) -> PlanMutationItem? {
        entries
            .filter { candidate in
                guard candidate.id != item.planId else { return false }
                guard candidate.canonicalStatus == .planned || candidate.canonicalStatus == .inProgress else {
                    return false
                }
                guard candidate.source == item.source else { return false }
                guard candidate.programId?.trimmedNilIfEmpty == item.programId?.trimmedNilIfEmpty else { return false }
                guard candidate.workoutId?.trimmedNilIfEmpty == item.workoutId?.trimmedNilIfEmpty else { return false }
                return true
            }
            .sorted { $0.day < $1.day }
            .map(PlanMutationItem.init(entry:))
            .first
    }

    private func editableDraft(for item: PlanMutationItem) -> WorkoutDetailsModel {
        if item.detailsState == .hydrated, let workoutDetails = item.workoutDetails {
            return workoutDetails
        }

        return WorkoutDetailsModel(
            id: item.workoutId?.trimmedNilIfEmpty ?? "manual-\(item.planId)",
            title: item.title,
            dayOrder: 0,
            coachNote: "Ручная тренировка",
            exercises: [],
        )
    }

    private func clearLocalWorkoutProgress(for item: PlanMutationItem) async {
        guard let workoutId = item.workoutId?.trimmedNilIfEmpty else { return }
        await LocalWorkoutProgressStore().remove(
            userSub: userSub,
            programId: item.programId?.trimmedNilIfEmpty ?? "",
            workoutId: workoutId,
        )
    }

    private func invalidateWorkoutCaches(for item: PlanMutationItem) async {
        guard let workoutId = item.workoutId?.trimmedNilIfEmpty else { return }
        await cacheStore.remove(
            planWorkoutCacheKey(programId: item.programId, source: item.source, workoutId: item.workoutId),
            namespace: userSub,
        )
        await cacheStore.remove(
            "workout.execution.context:\(item.programId?.trimmedNilIfEmpty ?? ""):\(workoutId)",
            namespace: userSub,
        )
    }

    private func performMutationSideEffects(
        persistence: @escaping @Sendable () async -> Void,
        sync: (@Sendable () async -> Void)? = nil,
        cache: (@Sendable () async -> Void)? = nil,
        cleanup: (@Sendable () async -> Void)? = nil,
    ) async {
        await persistence()
        if let sync {
            await sync()
        }
        if let cache {
            await cache()
        }
        if let cleanup {
            await cleanup()
        }
    }

    private func canSchedule(on day: Date) -> Bool {
        calendar.startOfDay(for: day) >= calendar.startOfDay(for: Date())
    }

    private func normalizedScheduledDate(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    private func suppressionSignature(day: Date, workoutId: String?, planId: String) -> String? {
        guard planId.hasPrefix("remote-"), let workoutId else { return nil }
        let normalizedDay = calendar.startOfDay(for: day)
        return "\(normalizedDay.timeIntervalSince1970)::\(workoutId)"
    }

    private func shouldQueuePendingRepeatedWorkout(for error: APIError) -> Bool {
        switch error {
        case .offline:
            return true
        case .timeout, .cancelled, .transportError, .serverError, .decodingError, .unknown, .httpError, .unauthorized, .forbidden, .invalidURL:
            return false
        }
    }

    private func repeatSchedulingErrorMessage(for error: APIError) -> String {
        switch error {
        case .timeout, .transportError, .serverError, .decodingError, .unknown:
            return "Не удалось создать тренировку на сервере. Проверьте план и повторите попытку."
        case .httpError(let statusCode, _):
            return "Сервер не создал тренировку. Код ответа: \(statusCode)."
        case .unauthorized, .forbidden:
            return "Сессия устарела. Войдите снова и повторите попытку."
        case .invalidURL:
            return "Не удалось сформировать запрос на сервер."
        case .offline:
            return "Нет интернета. Тренировка сохранена локально и будет создана после синхронизации."
        case .cancelled:
            return "Создание тренировки было отменено."
        }
    }

    private func deleteErrorMessage(for error: APIError) -> String {
        switch error {
        case .offline:
            return "Нет интернета. Удалить уже созданную тренировку можно только после восстановления соединения."
        case .timeout, .transportError, .serverError, .decodingError, .unknown:
            return "Не удалось удалить тренировку на сервере. Повторите попытку позже."
        case .httpError(let statusCode, _):
            return "Сервер не удалил тренировку. Код ответа: \(statusCode)."
        case .unauthorized, .forbidden:
            return "Сессия устарела. Войдите снова и повторите попытку."
        case .invalidURL:
            return "Не удалось сформировать запрос на удаление."
        case .cancelled:
            return "Удаление тренировки было отменено."
        }
    }

    private func plannedWorkoutUpdateErrorMessage(for error: APIError) -> String {
        switch error {
        case .offline:
            return "Нет интернета. Изменения в уже созданной тренировке можно сохранить только после восстановления соединения."
        case .timeout, .transportError, .serverError, .decodingError, .unknown:
            return "Не удалось сохранить изменения тренировки на сервере. Повторите попытку позже."
        case .httpError(let statusCode, _):
            return "Сервер не сохранил изменения тренировки. Код ответа: \(statusCode)."
        case .unauthorized, .forbidden:
            return "Сессия устарела. Войдите снова и повторите попытку."
        case .invalidURL:
            return "Не удалось сформировать запрос на сохранение."
        case .cancelled:
            return "Сохранение изменений было отменено."
        }
    }

    private func failure(kind: PlanMutationErrorKind, message: String) -> PlanMutationOutcome {
        PlanMutationOutcome(
            didMutate: false,
            focusDay: nil,
            shouldReload: false,
            retrySyncAfterReload: false,
            broadcastDay: nil,
            suppressedPlanSignatures: [],
            userError: PlanMutationUserError(kind: kind, message: message),
        )
    }
}

@Observable
@MainActor
final class PlanScheduleViewModel {
    enum SourceKind: String {
        case program = "PROGRAM"
        case manual = "MANUAL"
    }

    struct DayScheduleItem: Identifiable, Equatable {
        let id: String
        let planId: String
        let day: Date
        let title: String
        let sourceTitle: String
        let programTitle: String?
        let source: WorkoutSource
        let ownership: PlanEntryOwnership
        let detailsState: PlanEntryDetailsState
        let syncState: PlanEntrySyncState
        let canonicalStatus: TrainingDayStatus
        let displayStatus: TrainingDayStatus
        let programId: String?
        let workoutId: String?
        let workoutDetails: WorkoutDetailsModel?
        let scheduledTimeText: String?

        var sourceKind: SourceKind {
            ownership.isProgram ? .program : .manual
        }

        var status: TrainingDayStatus {
            displayStatus
        }

        var isPendingRemoteCreation: Bool {
            syncState.isPendingCreateCustomWorkout
        }

        var pendingRemoteCreationOperationId: UUID? {
            syncState.pendingOperationId
        }
    }

    struct ProgramWorkoutDateWindow: Equatable {
        let earliest: Date
        let latest: Date?
    }

    private let userSub: String
    private let trainingStore: TrainingStore
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let calendar: Calendar
    private let readModel: PlanReadModelRepository
    private let mutationService: PlanMutationService

    var selectedMonth: Date = .init()
    var selectedDay: Date = .init()
    var isLoading = false
    var monthPlans: [PlanEntry] = []
    var contextPlans: [PlanEntry] = []
    var lastCompletedRecord: CompletedWorkoutRecord?
    var lastRepeatableRecord: CompletedWorkoutRecord?
    var repeatSchedulingErrorMessage: String?
    var deleteErrorMessage: String?
    var plannedWorkoutUpdateErrorMessage: String?
    private var suppressedPlanSignatures: Set<String> = []

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.calendar = calendar
        readModel = PlanReadModelRepository(
            userSub: userSub,
            trainingStore: trainingStore,
            athleteTrainingClient: athleteTrainingClient,
            cacheStore: cacheStore,
            networkMonitor: networkMonitor,
            calendar: calendar,
        )
        mutationService = PlanMutationService(
            userSub: userSub,
            trainingStore: trainingStore,
            athleteTrainingClient: athleteTrainingClient,
            cacheStore: cacheStore,
            networkMonitor: networkMonitor,
            calendar: calendar,
        )
        selectedMonth = calendar.startOfDay(for: Date())
        selectedDay = calendar.startOfDay(for: Date())
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let assembly = await readModel.loadMonthAssembly(
            selectedMonth: selectedMonth,
            suppressedPlanSignatures: suppressedPlanSignatures,
        )
        monthPlans = assembly.monthPlans
        contextPlans = assembly.contextPlans
        let history = await trainingStore.history(userSub: userSub, source: nil, limit: 180)
        lastCompletedRecord = history.first
        lastRepeatableRecord = history.first(where: { $0.source != .program })
    }

    func selectDay(_ day: Date) async {
        selectedDay = calendar.startOfDay(for: day)
    }

    func selectDayFromAdjacentMonth(_ day: Date) async {
        guard let targetMonth = calendar.dateInterval(of: .month, for: day)?.start else { return }
        selectedMonth = calendar.startOfDay(for: targetMonth)
        selectedDay = calendar.startOfDay(for: day)
        await reload()
    }

    func goToPreviousMonth() async {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else { return }
        selectedMonth = previous
        selectedDay = calendar.startOfDay(for: selectedMonth)
        await reload()
    }

    func goToNextMonth() async {
        guard let next = calendar.date(byAdding: .month, value: 1, to: selectedMonth) else { return }
        selectedMonth = next
        selectedDay = calendar.startOfDay(for: selectedMonth)
        await reload()
    }

    func jumpToToday() async {
        selectedMonth = calendar.startOfDay(for: Date())
        selectedDay = calendar.startOfDay(for: Date())
        await reload()
    }

    func focus(on day: Date) async {
        let normalizedDay = calendar.startOfDay(for: day)
        selectedMonth = calendar.dateInterval(of: .month, for: normalizedDay)?.start ?? normalizedDay
        selectedDay = normalizedDay
        await reload()
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: selectedMonth).capitalized
    }

    var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        let base = formatter.shortStandaloneWeekdaySymbols
            ?? formatter.shortWeekdaySymbols
            ?? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        guard !base.isEmpty else { return [] }
        let shift = max(0, calendar.firstWeekday - 1)
        let boundedShift = min(shift, base.count - 1)
        return Array(base[boundedShift...]) + Array(base[..<boundedShift])
    }

    var monthGrid: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        return (0 ..< 42).compactMap { index in
            calendar.date(byAdding: .day, value: index, to: firstWeek.start)
        }
    }

    func isInCurrentMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: selectedMonth, toGranularity: .month)
    }

    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    func isFutureDay(_ day: Date) -> Bool {
        calendar.startOfDay(for: day) > calendar.startOfDay(for: Date())
    }

    func canSchedule(on day: Date) -> Bool {
        calendar.startOfDay(for: day) >= calendar.startOfDay(for: Date())
    }

    func dayStatus(_ day: Date) -> TrainingDayStatus? {
        let plans = plansForDay(in: contextPlans, day: day)
        return dayStatus(for: plans)
    }

    func dayItems(for day: Date) -> [DayScheduleItem] {
        let plans = plansForDay(in: contextPlans, day: day)
        let items = plans.map(makeDayScheduleItem(from:))
        return items.sorted { lhs, rhs in
            if lhs.day != rhs.day {
                return lhs.day < rhs.day
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func scheduledTimeText(for date: Date) -> String? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        guard hour != 0 || minute != 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func makeDayScheduleItem(from plan: PlanEntry) -> DayScheduleItem {
        let entry = plan.refreshingDisplayStatus(calendar: calendar)
        return DayScheduleItem(
            id: "\(entry.day.timeIntervalSince1970)::\(entry.id)",
            planId: entry.id,
            day: entry.day,
            title: entry.title,
            sourceTitle: sourceTitle(for: entry),
            programTitle: entry.programTitle,
            source: entry.source,
            ownership: entry.ownership,
            detailsState: entry.detailsState,
            syncState: entry.syncState,
            canonicalStatus: entry.canonicalStatus,
            displayStatus: entry.displayStatus,
            programId: entry.programId,
            workoutId: entry.workoutId,
            workoutDetails: entry.workoutDetails,
            scheduledTimeText: scheduledTimeText(for: entry.day),
        )
    }

    func statusTitle(_ status: TrainingDayStatus?) -> String {
        switch status {
        case .planned:
            "Запланирована"
        case .inProgress:
            "В процессе"
        case .completed:
            "Выполнена"
        case .missed:
            "Пропущена"
        case .skipped:
            "Пропущена намеренно"
        case nil:
            "Нет статуса"
        }
    }

    func sourceTitle(_ source: WorkoutSource) -> String {
        switch source {
        case .program:
            "Программа"
        case .freestyle:
            "Ручная"
        case .template:
            "Шаблон"
        }
    }

    private func sourceTitle(for entry: PlanEntry) -> String {
        let baseTitle: String
        switch entry.ownership {
        case .remoteProgram, .localProgramOverlay:
            if let programTitle = entry.programTitle?.trimmedNilIfEmpty {
                baseTitle = "Программа: \(programTitle)"
            } else {
                baseTitle = "Программа"
            }
        case .remoteCustom, .pendingCustom, .localFreestyle, .localTemplate:
            switch entry.source {
            case .template:
                baseTitle = "Ручная: шаблон"
            case .freestyle:
                baseTitle = "Ручная: одноразовая"
            case .program:
                baseTitle = "Ручная"
            }
        }
        if entry.syncState.isPendingCreateCustomWorkout {
            return "\(baseTitle) • ждёт синхронизации"
        }
        return baseTitle
    }

    func scheduleQuickWorkout(on day: Date) async {
        let outcome = await mutationService.schedule(
            PlanScheduleMutationRequest(
                day: day,
                title: "Быстрая тренировка",
                source: .freestyle,
                programId: nil,
                programTitle: nil,
                workoutId: "quick-\(UUID().uuidString)",
                status: .planned,
                workoutDetails: nil,
                planId: nil,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    func scheduleConfiguredQuickWorkout(_ workout: WorkoutDetailsModel, on day: Date) async {
        let outcome = await mutationService.schedule(
            PlanScheduleMutationRequest(
                day: day,
                title: workout.title,
                source: .freestyle,
                programId: nil,
                programTitle: nil,
                workoutId: workout.id,
                status: .planned,
                workoutDetails: workout,
                planId: nil,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    func scheduleTemplate(_ template: WorkoutTemplateDraft, on day: Date) async {
        let mappedWorkout = template.asWorkoutDetailsModel()
        let outcome = await mutationService.schedule(
            PlanScheduleMutationRequest(
                day: day,
                title: template.name,
                source: .template,
                programId: nil,
                programTitle: nil,
                workoutId: template.id,
                status: .planned,
                workoutDetails: mappedWorkout,
                planId: nil,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    @discardableResult
    func scheduleRepeatedWorkout(
        _ workout: WorkoutDetailsModel,
        source: WorkoutSource,
        on day: Date,
    ) async -> Bool {
        repeatSchedulingErrorMessage = nil
        let outcome = await mutationService.repeatWorkout(
            PlanRepeatWorkoutMutationRequest(
                workout: workout,
                source: source,
                day: day,
            )
        )
        return await applyMutationOutcome(outcome)
    }

    func scheduleRepeatLastWorkout(on day: Date) async {
        let resolvedRecord: CompletedWorkoutRecord?
        if let lastRepeatableRecord {
            resolvedRecord = lastRepeatableRecord
        } else {
            let history = await trainingStore.history(userSub: userSub, source: nil, limit: 180)
            lastCompletedRecord = history.first
            lastRepeatableRecord = history.first(where: { $0.source != .program })
            resolvedRecord = lastRepeatableRecord
        }
        guard let resolvedRecord else { return }
        guard resolvedRecord.source != .program else { return }
        guard let resolvedWorkout = await mutationService.resolveRepeatableWorkout(
            for: resolvedRecord,
            templateWorkoutDetails: { [weak self] templateID in
                await self?.templateWorkoutDetails(templateID: templateID)
            }
        ) else {
            repeatSchedulingErrorMessage = "Не удалось загрузить последнюю тренировку для повтора."
            return
        }
        let repeatPrefix = resolvedRecord.source == .template ? "template-repeat" : "quick-repeat"
        let repeatedWorkout = resolvedWorkout.asRepeatableCopy(prefix: repeatPrefix)
        _ = await scheduleRepeatedWorkout(
            repeatedWorkout,
            source: resolvedRecord.source,
            on: day,
        )
    }

    func dismissRepeatSchedulingError() {
        repeatSchedulingErrorMessage = nil
    }

    func dismissDeleteError() {
        deleteErrorMessage = nil
    }

    func dismissPlannedWorkoutUpdateError() {
        plannedWorkoutUpdateErrorMessage = nil
    }

    func ensureLastCompletedRecordLoaded() async {
        guard lastCompletedRecord == nil || lastRepeatableRecord == nil else { return }
        let history = await trainingStore.history(userSub: userSub, source: nil, limit: 180)
        if lastCompletedRecord == nil {
            lastCompletedRecord = history.first
        }
        if lastRepeatableRecord == nil {
            lastRepeatableRecord = history.first(where: { $0.source != .program })
        }
    }

    func templates() async -> [WorkoutTemplateDraft] {
        let local = await trainingStore.templates(userSub: userSub)
        let remote = await remoteTemplateCandidates()

        var seen = Set<String>()
        var merged: [WorkoutTemplateDraft] = []

        for template in (local + remote) {
            guard seen.insert(template.id).inserted else { continue }
            merged.append(template)
        }

        return merged.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    func templateWorkoutDetails(templateID: String) async -> WorkoutDetailsModel? {
        let allTemplates = await templates()
        guard let template = allTemplates.first(where: { $0.id == templateID }) else { return nil }
        return template.asWorkoutDetailsModel()
    }

    func completedRecord(for item: DayScheduleItem) async -> CompletedWorkoutRecord? {
        let history = await trainingStore.history(userSub: userSub, source: nil, limit: 720)
        guard !history.isEmpty else { return nil }

        let normalizedDay = calendar.startOfDay(for: item.day)
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorkoutId = item.workoutId?.trimmedNilIfEmpty
        let normalizedProgramId = item.programId?.trimmedNilIfEmpty

        var bestMatch: CompletedWorkoutRecord?
        var bestScore = Int.min

        for record in history {
            guard record.source == item.source else { continue }

            var score = 0
            if let normalizedWorkoutId, record.workoutId == normalizedWorkoutId {
                score += 100
            }
            if let normalizedProgramId, record.programId == normalizedProgramId {
                score += 40
            }
            if calendar.isDate(record.finishedAt, inSameDayAs: normalizedDay) {
                score += 25
            }
            if !normalizedTitle.isEmpty,
               record.workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                   .caseInsensitiveCompare(normalizedTitle) == .orderedSame
            {
                score += 20
            }
            score += completedRecordRichnessScore(record)

            guard score > bestScore else { continue }
            bestScore = score
            bestMatch = record

            if score >= 165 {
                break
            }
        }

        return bestScore > 0 ? bestMatch : nil
    }

    private func completedRecordRichnessScore(_ record: CompletedWorkoutRecord) -> Int {
        var score = 0

        if record.workoutDetails != nil {
            score += 80
        }

        if record.totalSets > 0 || record.completedSets > 0 {
            score += 30
        }

        if record.volume > 0 {
            score += 10
        }

        if record.overallRPE != nil {
            score += 5
        }

        return score
    }

    func conflictCount(on day: Date, excluding item: DayScheduleItem?) -> Int {
        let normalized = calendar.startOfDay(for: day)
        return dayItems(for: normalized).count { candidate in
            guard let item else { return true }
            return candidate.id != item.id
        }
    }

    func allowedDateWindow(
        forProgramWorkout programId: String,
        workoutId: String?,
        dayOrder: Int,
        excluding item: DayScheduleItem?,
    ) -> ProgramWorkoutDateWindow? {
        guard dayOrder > 0 else { return nil }

        let relevantPlans = contextPlans.filter { plan in
            guard plan.source == .program, plan.programId == programId else { return false }
            if let item, plan.id == item.planId {
                return false
            }
            if let workoutId, let planWorkoutId = plan.workoutId, planWorkoutId == workoutId {
                return false
            }
            return true
        }

        let orderedPlans = relevantPlans.compactMap { plan -> (dayOrder: Int, day: Date)? in
            guard let order = plan.workoutDetails?.dayOrder, order > 0 else { return nil }
            return (order, calendar.startOfDay(for: plan.day))
        }

        let previousDay = orderedPlans
            .filter { $0.dayOrder < dayOrder }
            .map(\.day)
            .max()

        let nextDay = orderedPlans
            .filter { $0.dayOrder > dayOrder }
            .map(\.day)
            .min()

        let today = calendar.startOfDay(for: Date())
        let earliest = max(today, previousDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? today)
        let latest = nextDay.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        return ProgramWorkoutDateWindow(earliest: earliest, latest: latest)
    }

    func markSkipped(_ item: DayScheduleItem) async {
        let outcome = await mutationService.updateStatus(
            PlanStatusMutationRequest(
                item: item.asMutationItem,
                status: .skipped,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    func cancelInProgress(_ item: DayScheduleItem) async {
        let outcome = await mutationService.cancelInProgress(item.asMutationItem)
        _ = await applyMutationOutcome(outcome)
    }

    func repeatCompleted(_ item: DayScheduleItem, on targetDay: Date) async {
        let outcome = await mutationService.repeatCompleted(
            item: item.asMutationItem,
            on: targetDay,
            resolveWorkoutDetails: { [weak self] mutationItem in
                await self?.resolveWorkoutDetails(for: mutationItem)
            }
        )
        _ = await applyMutationOutcome(outcome)
    }

    func replanMissed(_ item: DayScheduleItem, on targetDay: Date) async {
        let outcome = await mutationService.replan(
            PlanReplanMutationRequest(
                item: item.asMutationItem,
                targetDay: targetDay,
                contextEntries: contextPlans,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    func movePlan(
        _ item: DayScheduleItem,
        to targetDay: Date,
        statusOverride: TrainingDayStatus? = nil,
    ) async {
        let outcome = await mutationService.move(
            PlanMoveMutationRequest(
                item: item.asMutationItem,
                targetDay: targetDay,
                statusOverride: statusOverride,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    func scheduleProgramWorkout(
        programId: String,
        workoutId: String,
        title: String,
        workoutDetails: WorkoutDetailsModel,
        on targetDay: Date,
    ) async {
        let outcome = await mutationService.schedule(
            PlanScheduleMutationRequest(
                day: targetDay,
                title: title,
                source: .program,
                programId: programId,
                programTitle: nil,
                workoutId: workoutId,
                status: .planned,
                workoutDetails: workoutDetails,
                planId: nil,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    func deletePlan(_ item: DayScheduleItem) async {
        deleteErrorMessage = nil
        let outcome = await mutationService.delete(
            PlanDeleteMutationRequest(item: item.asMutationItem)
        )
        _ = await applyMutationOutcome(outcome)
    }

    func resolveWorkoutDetails(for item: DayScheduleItem) async -> WorkoutDetailsModel? {
        await resolveWorkoutDetails(for: item.asMutationItem)
    }

    private func resolveWorkoutDetails(for item: PlanMutationItem) async -> WorkoutDetailsModel? {
        let cacheKey = workoutCacheKey(programId: item.programId, source: item.source, workoutId: item.workoutId)

        if item.detailsState == .hydrated, let workoutDetails = item.workoutDetails {
            await cacheStore.set(
                cacheKey,
                value: workoutDetails,
                namespace: userSub,
                ttl: 60 * 60 * 24,
            )
            return workoutDetails
        }

        if item.source == .template, let templateID = item.workoutId?.trimmedNilIfEmpty {
            if let templateDetails = await templateWorkoutDetails(templateID: templateID) {
                await cacheStore.set(
                    cacheKey,
                    value: templateDetails,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
                return templateDetails
            }
        }

        if let cached = await cacheStore.get(
            cacheKey,
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ), hasHydratedWorkoutDetails(cached, source: item.source, fallbackTitle: item.title) {
            return cached
        }

        if item.source == .program,
           let workoutInstanceId = item.workoutId?.trimmedNilIfEmpty,
           let athleteTrainingClient
        {
            if case let .success(detailsResponse) = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId) {
                let details = detailsResponse.asWorkoutDetailsModel()
                await cacheStore.set(
                    cacheKey,
                    value: details,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
                return details
            }
        }

        if item.source == .freestyle,
           let workoutInstanceId = item.workoutId?.trimmedNilIfEmpty,
           UUID(uuidString: workoutInstanceId) != nil,
           let athleteTrainingClient
        {
            if case let .success(detailsResponse) = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId) {
                let details = detailsResponse.asWorkoutDetailsModel()
                await cacheStore.set(
                    cacheKey,
                    value: details,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
                return details
            }
        }

        if item.source == .freestyle {
            return WorkoutDetailsModel(
                id: item.workoutId?.trimmedNilIfEmpty ?? "quick-\(UUID().uuidString)",
                title: item.title,
                dayOrder: 0,
                coachNote: "Быстрая тренировка",
                exercises: [],
            )
        }

        return nil
    }

    private func applyMutationOutcome(_ outcome: PlanMutationOutcome) async -> Bool {
        if let userError = outcome.userError {
            switch userError.kind {
            case .repeatScheduling:
                repeatSchedulingErrorMessage = userError.message
            case .delete:
                deleteErrorMessage = userError.message
            case .plannedWorkoutUpdate:
                plannedWorkoutUpdateErrorMessage = userError.message
            }
        }

        for signature in outcome.suppressedPlanSignatures {
            suppressedPlanSignatures.insert(signature)
        }

        if let focusDay = outcome.focusDay {
            selectedDay = calendar.startOfDay(for: focusDay)
            selectedMonth = calendar.dateInterval(of: .month, for: focusDay)?.start ?? selectedDay
        }

        if outcome.shouldReload {
            await reload()
            if outcome.retrySyncAfterReload {
                await SyncCoordinator.shared.retryNow(namespace: userSub)
                await reload()
            }
            if let broadcastDay = outcome.broadcastDay {
                NotificationCenter.default.post(name: .fitfluenceTrainingPlanDidChange, object: broadcastDay)
            }
        }

        return outcome.didMutate
    }

    func canEditPlannedWorkout(_ item: DayScheduleItem, details _: WorkoutDetailsModel?) -> Bool {
        guard item.canonicalStatus == .planned else { return false }
        guard item.sourceKind == .manual else { return false }
        return true
    }

    func canDeletePlannedWorkout(_ item: DayScheduleItem) -> Bool {
        guard item.canonicalStatus == .planned else { return false }
        return item.sourceKind == .manual
    }

    func canRepeat(_ item: DayScheduleItem) -> Bool {
        item.canonicalStatus == .completed && item.sourceKind == .manual
    }

    func editableDraft(for item: DayScheduleItem) -> WorkoutDetailsModel {
        if hasHydratedWorkoutDetails(item.workoutDetails, for: item) {
            let workoutDetails = item.workoutDetails!
            return workoutDetails
        }

        return WorkoutDetailsModel(
            id: item.workoutId?.trimmedNilIfEmpty ?? "manual-\(item.planId)",
            title: item.title,
            dayOrder: 0,
            coachNote: "Ручная тренировка",
            exercises: [],
        )
    }

    func updatePlannedManualWorkout(_ item: DayScheduleItem, with workout: WorkoutDetailsModel) async {
        guard canEditPlannedWorkout(item, details: workout) else { return }
        plannedWorkoutUpdateErrorMessage = nil
        let outcome = await mutationService.updatePlannedManualWorkout(
            PlanUpdateManualWorkoutMutationRequest(
                item: item.asMutationItem,
                workout: workout,
            )
        )
        _ = await applyMutationOutcome(outcome)
    }

    private func plansForDay(in plans: [PlanEntry], day: Date) -> [PlanEntry] {
        let normalized = calendar.startOfDay(for: day)
        return plans.filter { calendar.isDate($0.day, inSameDayAs: normalized) }
    }

    private func dayStatus(for plans: [PlanEntry]) -> TrainingDayStatus? {
        if plans.contains(where: { $0.canonicalStatus == .inProgress }) {
            return .inProgress
        }
        if plans.contains(where: { $0.canonicalStatus == .completed }) {
            return .completed
        }
        if plans.contains(where: { $0.canonicalStatus.isMissedLike }) {
            return .missed
        }
        if plans.contains(where: { $0.canonicalStatus == .planned }) {
            return .planned
        }
        return nil
    }

    private func hasHydratedWorkoutDetails(_ workoutDetails: WorkoutDetailsModel?, for item: DayScheduleItem) -> Bool {
        hasHydratedWorkoutDetails(
            workoutDetails,
            source: item.source,
            fallbackTitle: item.title,
        )
    }

    private func hasHydratedWorkoutDetails(
        _ workoutDetails: WorkoutDetailsModel?,
        source: WorkoutSource,
        fallbackTitle: String,
    ) -> Bool {
        readModel.hasHydratedWorkoutDetails(
            workoutDetails,
            source: source,
            fallbackTitle: fallbackTitle,
        )
    }

    private func workoutCacheKey(programId: String?, source: WorkoutSource, workoutId: String?) -> String {
        let resolvedProgramID = programId?.trimmedNilIfEmpty ?? source.rawValue
        let resolvedWorkoutID = workoutId?.trimmedNilIfEmpty ?? "unknown"
        return "workout.details:\(resolvedProgramID):\(resolvedWorkoutID)"
    }

    private func remoteTemplateCandidates() async -> [WorkoutTemplateDraft] {
        let cacheKey = "plan.templates.remote"
        if let cached = await cacheStore.get(cacheKey, as: [WorkoutTemplateDraft].self, namespace: userSub) {
            return cached
        }
        guard networkMonitor.currentStatus, let athleteTrainingClient else { return [] }

        var monthCandidates: [Date] = [selectedMonth]
        if let next = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
            monthCandidates.append(next)
        }

        var workoutCandidates: [(id: String, programId: String?)] = []
        var seenWorkoutIDs = Set<String>()

        let localCandidatePlans = readModel.deduplicateEntries(contextPlans + monthPlans)
        for plan in localCandidatePlans {
            guard plan.source == .program,
                  let workoutID = plan.workoutId?.trimmedNilIfEmpty
            else { continue }
            guard seenWorkoutIDs.insert(workoutID).inserted else { continue }
            workoutCandidates.append((id: workoutID, programId: plan.programId?.trimmedNilIfEmpty))
        }

        for month in monthCandidates {
            let monthToken = readModel.monthKey(for: month)
            if case let .success(calendarResponse) = await athleteTrainingClient.calendar(month: monthToken) {
                for workout in calendarResponse.workouts {
                    guard let normalized = workout.id.trimmedNilIfEmpty else { continue }
                    guard seenWorkoutIDs.insert(normalized).inserted else { continue }
                    workoutCandidates.append((id: normalized, programId: workout.programId?.trimmedNilIfEmpty))
                }
            }
        }

        if let enrollmentId = await readModel.activeEnrollmentProgress()?.enrollmentId,
           case let .success(scheduleResponse) = await athleteTrainingClient.enrollmentSchedule(enrollmentId: enrollmentId)
        {
            for workout in scheduleResponse.workouts {
                guard let normalized = workout.id.trimmedNilIfEmpty else { continue }
                guard seenWorkoutIDs.insert(normalized).inserted else { continue }
                workoutCandidates.append((id: normalized, programId: workout.programId?.trimmedNilIfEmpty))
            }
        }

        guard !workoutCandidates.isEmpty else { return [] }
        let candidateWorkouts = Array(workoutCandidates.prefix(12))
        var templates: [WorkoutTemplateDraft] = []
        templates.reserveCapacity(candidateWorkouts.count)

        for candidate in candidateWorkouts {
            let resolvedWorkout: WorkoutDetailsModel?

            if let cachedDetails = await cacheStore.get(
                workoutCacheKey(programId: candidate.programId, source: .program, workoutId: candidate.id),
                as: WorkoutDetailsModel.self,
                namespace: userSub,
            ) {
                resolvedWorkout = cachedDetails
            } else if case let .success(detailsResponse) = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: candidate.id) {
                let mapped = detailsResponse.asWorkoutDetailsModel()
                await cacheStore.set(
                    workoutCacheKey(programId: candidate.programId, source: .program, workoutId: candidate.id),
                    value: mapped,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
                resolvedWorkout = mapped
            } else {
                resolvedWorkout = nil
            }

            guard let workout = resolvedWorkout, !workout.exercises.isEmpty else { continue }
            let exercises = workout.exercises.map { exercise in
                TemplateExerciseDraft(
                    id: exercise.id,
                    name: exercise.name,
                    sets: max(1, exercise.sets),
                    repsMin: exercise.repsMin,
                    repsMax: exercise.repsMax,
                    restSeconds: exercise.restSeconds,
                    targetRpe: exercise.targetRpe,
                    notes: exercise.notes,
                )
            }
            templates.append(
                WorkoutTemplateDraft(
                    id: "remote-\(workout.id)",
                    userSub: "remote",
                    name: workout.title,
                    exercises: exercises,
                    updatedAt: Date(),
                ),
            )
        }

        if !templates.isEmpty {
            await cacheStore.set(cacheKey, value: templates, namespace: userSub, ttl: 60 * 10)
        }
        return templates
    }

}

private extension PlanScheduleViewModel.DayScheduleItem {
    var asMutationItem: PlanMutationItem {
        PlanMutationItem(
            planId: planId,
            day: day,
            title: title,
            source: source,
            ownership: ownership,
            detailsState: detailsState,
            syncState: syncState,
            canonicalStatus: canonicalStatus,
            programId: programId,
            programTitle: programTitle,
            workoutId: workoutId,
            workoutDetails: workoutDetails,
        )
    }
}

struct PlanScheduleScreen: View {
    private struct DateActionFlow: Identifiable {
        let id: String
        let item: PlanScheduleViewModel.DayScheduleItem
        let mode: PlanDateActionMode
    }

    private struct WorkoutDetailsFlow: Identifiable {
        let id: String
        let item: PlanScheduleViewModel.DayScheduleItem
        let workoutDetails: WorkoutDetailsModel?
    }

    private struct EditManualWorkoutFlow: Identifiable {
        let id: String
        let item: PlanScheduleViewModel.DayScheduleItem
        let workoutDetails: WorkoutDetailsModel
    }

    private enum AlertFlow: Identifiable {
        case delete(PlanScheduleViewModel.DayScheduleItem)
        case skip(PlanScheduleViewModel.DayScheduleItem)
        case pastSchedule

        var id: String {
            switch self {
            case let .delete(item):
                "delete-\(item.id)"
            case let .skip(item):
                "skip-\(item.id)"
            case .pastSchedule:
                "past-schedule"
            }
        }
    }

    @State var viewModel: PlanScheduleViewModel
    let onOpenProgramWorkout: (_ programId: String, _ workoutId: String) -> Void
    let onOpenPresetWorkout: (_ workout: WorkoutDetailsModel, _ source: WorkoutSource, _ programId: String?, _ planId: String?) -> Void
    let onOpenQuickWorkoutBuilder: () -> Void
    let onOpenCompletedWorkout: (_ record: CompletedWorkoutRecord) -> Void
    let exerciseCatalogRepository: any ExerciseCatalogRepository
    let exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding

    @State private var scheduleTargetDay: Date?
    @State private var isScheduleDialogPresented = false
    @State private var isTemplatePickerPresented = false
    @State private var scheduleTemplates: [WorkoutTemplateDraft] = []
    @State private var dateActionFlow: DateActionFlow?
    @State private var workoutDetailsFlow: WorkoutDetailsFlow?
    @State private var editManualWorkoutFlow: EditManualWorkoutFlow?
    @State private var alertFlow: AlertFlow?
    @State private var isQuickScheduleBuilderPresented = false

    init(
        viewModel: PlanScheduleViewModel,
        exerciseCatalogRepository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        onOpenProgramWorkout: @escaping (_ programId: String, _ workoutId: String) -> Void = { _, _ in },
        onOpenPresetWorkout: @escaping (_ workout: WorkoutDetailsModel, _ source: WorkoutSource, _ programId: String?, _ planId: String?) -> Void = { _, _, _, _ in },
        onOpenQuickWorkoutBuilder: @escaping () -> Void = {},
        onOpenCompletedWorkout: @escaping (_ record: CompletedWorkoutRecord) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.exerciseCatalogRepository = exerciseCatalogRepository
        self.exercisePickerSuggestionsProvider = exercisePickerSuggestionsProvider
        self.onOpenProgramWorkout = onOpenProgramWorkout
        self.onOpenPresetWorkout = onOpenPresetWorkout
        self.onOpenQuickWorkoutBuilder = onOpenQuickWorkoutBuilder
        self.onOpenCompletedWorkout = onOpenCompletedWorkout
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                calendarCard
                dayScheduleCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .ffScreenBackground()
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.onAppear()
            await applyPendingPlanFocusIfNeeded()
        }
        .onAppear {
            Task {
                await applyPendingPlanFocusIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitfluenceTrainingPlanDidChange)) { notification in
            Task {
                if let day = notification.object as? Date {
                    await viewModel.focus(on: day)
                } else {
                    await viewModel.reload()
                }
            }
        }
        .sheet(isPresented: $isScheduleDialogPresented) {
            PlanScheduleConfigurationSheet(
                scheduledAt: Binding(
                    get: { scheduleTargetDay ?? defaultScheduleDate(for: viewModel.selectedDay) },
                    set: { scheduleTargetDay = $0 }
                ),
                selectedDay: viewModel.selectedDay,
                hasLastWorkout: viewModel.lastRepeatableRecord != nil,
                onClose: {
                    isScheduleDialogPresented = false
                },
                onQuickWorkout: {
                    isScheduleDialogPresented = false
                    isQuickScheduleBuilderPresented = true
                },
                onTemplate: {
                    isScheduleDialogPresented = false
                    Task {
                        scheduleTemplates = await viewModel.templates()
                        isTemplatePickerPresented = true
                    }
                },
                onRepeatLast: {
                    guard let day = scheduleTargetDay else { return }
                    isScheduleDialogPresented = false
                    Task { await viewModel.scheduleRepeatLastWorkout(on: day) }
                },
            )
        }
        .fullScreenCover(isPresented: $isQuickScheduleBuilderPresented) {
            NavigationStack {
                QuickWorkoutBuilderView(
                    submitTitle: "Создать",
                    exerciseCatalogRepository: exerciseCatalogRepository,
                    exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
                ) { workout in
                    guard let day = scheduleTargetDay else { return }
                    Task {
                        await viewModel.scheduleConfiguredQuickWorkout(workout, on: day)
                    }
                }
            }
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            PlanTemplatePickerSheet(
                templates: scheduleTemplates,
                loadTemplates: { await viewModel.templates() },
                onPick: { template in
                    guard let day = scheduleTargetDay else { return }
                    isTemplatePickerPresented = false
                    Task { await viewModel.scheduleTemplate(template, on: day) }
                },
            )
        }
        .sheet(item: $dateActionFlow) { flow in
            PlanMoveWorkoutSheet(
                item: flow.item,
                mode: flow.mode,
                conflictsCount: { day in
                    viewModel.conflictCount(on: day, excluding: flow.mode == .move ? flow.item : nil)
                },
                onCancel: {
                    dateActionFlow = nil
                },
                onApply: { targetDay in
                    dateActionFlow = nil
                    Task {
                        switch flow.mode {
                        case .move:
                            await viewModel.movePlan(flow.item, to: targetDay)
                        case .repeatWorkout:
                            await viewModel.repeatCompleted(flow.item, on: targetDay)
                        case .replan:
                            await viewModel.replanMissed(flow.item, on: targetDay)
                        }
                    }
                },
            )
        }
        .fullScreenCover(item: $workoutDetailsFlow) { flow in
            PlanWorkoutDetailsSheet(
                item: flow.item,
                statusTitle: viewModel.statusTitle(flow.item.status),
                workoutDetails: flow.workoutDetails,
                canEdit: viewModel.canEditPlannedWorkout(flow.item, details: flow.workoutDetails),
                canDelete: viewModel.canDeletePlannedWorkout(flow.item),
                pendingSyncMessage: flow.item.isPendingRemoteCreation
                    ? "Тренировка сохранена локально и будет создана на сервере после синхронизации. Запуск станет доступен после этого."
                    : nil,
                onEdit: {
                    let workoutDetails = flow.workoutDetails ?? viewModel.editableDraft(for: flow.item)
                    workoutDetailsFlow = nil
                    editManualWorkoutFlow = EditManualWorkoutFlow(
                        id: flow.id,
                        item: flow.item,
                        workoutDetails: workoutDetails,
                    )
                },
                onDelete: {
                    workoutDetailsFlow = nil
                    presentDeleteConfirmation(for: flow.item)
                },
            )
        }
        .fullScreenCover(item: $editManualWorkoutFlow) { flow in
            NavigationStack {
                QuickWorkoutBuilderView(
                    initialWorkout: flow.workoutDetails,
                    submitTitle: "Сохранить изменения",
                    exerciseCatalogRepository: exerciseCatalogRepository,
                    exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
                ) { updatedWorkout in
                    Task {
                        await viewModel.updatePlannedManualWorkout(flow.item, with: updatedWorkout)
                    }
                }
            }
        }
        .alert(item: $alertFlow) { flow in
            switch flow {
            case let .delete(item):
                Alert(
                    title: Text("Удалить тренировку?"),
                    message: Text("Тренировка «\(item.title)» будет удалена из плана."),
                    primaryButton: .destructive(Text("Удалить")) {
                        Task { await viewModel.deletePlan(item) }
                    },
                    secondaryButton: .cancel(),
                )
            case let .skip(item):
                Alert(
                    title: Text("Отметить как пропущенную?"),
                    message: Text("Тренировка «\(item.title)» останется в истории как пропущенная."),
                    primaryButton: .destructive(Text("Пропустить")) {
                        Task {
                            if item.status == .inProgress {
                                await viewModel.cancelInProgress(item)
                            } else {
                                await viewModel.markSkipped(item)
                            }
                        }
                    },
                    secondaryButton: .cancel(),
                )
            case .pastSchedule:
                Alert(
                    title: Text("Нельзя запланировать тренировку"),
                    message: Text("Планирование доступно только на сегодня и будущие даты."),
                    dismissButton: .cancel(Text("Понятно")),
                )
            }
        }
        .alert(
            "Не удалось запланировать тренировку",
            isPresented: Binding(
                get: { viewModel.repeatSchedulingErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissRepeatSchedulingError()
                    }
                }
            )
        ) {
            Button("Понятно") {
                viewModel.dismissRepeatSchedulingError()
            }
        } message: {
            Text(viewModel.repeatSchedulingErrorMessage ?? "")
        }
        .alert(
            "Не удалось удалить тренировку",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissDeleteError()
                    }
                }
            )
        ) {
            Button("Понятно") {
                viewModel.dismissDeleteError()
            }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        .alert(
            "Не удалось сохранить изменения",
            isPresented: Binding(
                get: { viewModel.plannedWorkoutUpdateErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissPlannedWorkoutUpdateError()
                    }
                }
            )
        ) {
            Button("Понятно") {
                viewModel.dismissPlannedWorkoutUpdateError()
            }
        } message: {
            Text(viewModel.plannedWorkoutUpdateErrorMessage ?? "")
        }
    }

    private var calendarCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("Календарь")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    headerControl(title: "Сегодня") {
                        Task { await viewModel.jumpToToday() }
                    }
                }

                HStack {
                    iconControl(systemName: "chevron.left") {
                        Task { await viewModel.goToPreviousMonth() }
                    }
                    Spacer()
                    Text(viewModel.monthTitle)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    iconControl(systemName: "chevron.right") {
                        Task { await viewModel.goToNextMonth() }
                    }
                }

                HStack(spacing: FFSpacing.xs) {
                    ForEach(Array(viewModel.weekdaySymbols.enumerated()), id: \.offset) { _, weekday in
                        Text(weekday)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: FFSpacing.xs), count: 7),
                    spacing: FFSpacing.xs,
                ) {
                    ForEach(viewModel.monthGrid, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: viewModel.selectedDay)
        let isToday = viewModel.isToday(day)
        let status = viewModel.dayStatus(day)
        let isSchedulable = viewModel.canSchedule(on: day)

        return VStack(spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(viewModel.isInCurrentMonth(day) ? FFColors.textPrimary : FFColors.gray500)
            Circle()
                .fill(calendarStatusColor(status))
                .frame(width: 8, height: 8)
                .opacity(status == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 4)
        .background(cellBackgroundColor(isSelected: isSelected, isToday: isToday))
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(cellBorderColor(isSelected: isSelected, isToday: isToday), lineWidth: isSelected ? 1.5 : 1)
        }
        .opacity(viewModel.isInCurrentMonth(day) ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .onTapGesture {
            handleCalendarDayTap(day)
        }
        .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 20) {
            guard isSchedulable else { return }
            handleCalendarDayLongPress(day)
        }
        .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
        .accessibilityHint(calendarDayAccessibilityHint(status: status, isSchedulable: isSchedulable))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleCalendarDayTap(day)
        }
        .accessibilityAction(named: Text("Запланировать тренировку")) {
            guard isSchedulable else { return }
            handleCalendarDayLongPress(day)
        }
    }

    private func calendarStatusColor(_ status: TrainingDayStatus?) -> Color {
        switch status {
        case .planned:
            planStatusColor(.planned)
        case .inProgress:
            planStatusColor(.inProgress)
        case .completed:
            planStatusColor(.completed)
        case .missed, .skipped:
            planStatusColor(.skipped)
        case nil:
            .clear
        }
    }

    private var dayScheduleCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text(selectedDayTitle)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                let items = viewModel.dayItems(for: viewModel.selectedDay)
                if items.isEmpty {
                    infoRowContainer {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            Text("Нет тренировок на этот день")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            if viewModel.canSchedule(on: viewModel.selectedDay) {
                                scheduleSelectedDayButton
                            } else {
                                Text("Нельзя планировать на прошедшую дату")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                    }
                } else {
                    ForEach(items) { item in
                        workoutDayCard(item)
                    }
                    if viewModel.canSchedule(on: viewModel.selectedDay) {
                        scheduleSelectedDayButton
                    }
                }
            }
        }
    }

    private var scheduleSelectedDayButton: some View {
        FFButton(title: "+ Запланировать тренировку", variant: .secondary) {
            openScheduleDialog(for: viewModel.selectedDay)
        }
    }

    private func workoutDayCard(_ item: PlanScheduleViewModel.DayScheduleItem) -> some View {
        infoRowContainer {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                HStack(alignment: .top, spacing: FFSpacing.xs) {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text(item.title)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(1)
                        Text(item.sourceTitle)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(1)
                        if let scheduledTimeText = item.scheduledTimeText {
                            Text("Время: \(scheduledTimeText)")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.accent)
                        }
                    }
                    Spacer(minLength: FFSpacing.xs)
                    if hasSecondaryActions(for: item) {
                        secondaryMenu(for: item)
                    }
                }
                statusBadge(for: item)
                primaryActionButton(for: item)
            }
            .frame(minHeight: 88, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openCard(item)
        }
    }

    private func statusBadge(for item: PlanScheduleViewModel.DayScheduleItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon(for: item.status))
                .font(.system(size: 11, weight: .semibold))
            Text(statusBadgeTitle(for: item))
                .font(FFTypography.caption.weight(.semibold))
        }
        .foregroundStyle(pillColor(item.status))
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.xxs)
        .background(pillColor(item.status).opacity(0.22))
        .clipShape(Capsule())
    }

    private var selectedDayTitle: String {
        relativeDayTitle(viewModel.selectedDay)
    }

    private func statusIcon(for status: TrainingDayStatus) -> String {
        switch status {
        case .completed:
            "checkmark.circle.fill"
        case .inProgress:
            "play.circle.fill"
        case .missed, .skipped:
            "xmark.circle.fill"
        case .planned:
            "calendar"
        }
    }

    private func statusBadgeTitle(for item: PlanScheduleViewModel.DayScheduleItem) -> String {
        switch item.status {
        case .planned:
            if Calendar.current.isDateInToday(item.day) {
                return "Сегодня"
            }
            if Calendar.current.isDateInTomorrow(item.day) {
                return "Завтра"
            }
            return "Запланирована"
        case .inProgress:
            return "В процессе"
        case .completed:
            return "Выполнена"
        case .missed:
            return "Пропущена"
        case .skipped:
            return "Пропущена намеренно"
        }
    }

    @ViewBuilder
    private func primaryActionButton(for item: PlanScheduleViewModel.DayScheduleItem) -> some View {
        switch item.status {
        case .planned:
            if item.isPendingRemoteCreation, viewModel.isToday(item.day) {
                FFButton(title: "Ждёт синхронизации", variant: .disabled) {}
            } else if viewModel.isToday(item.day) {
                FFButton(title: "Начать тренировку", variant: .primary) {
                    handleOpenWorkout(item, preferDetailsForFutureDate: false)
                }
            } else {
                EmptyView()
            }
        case .inProgress:
            FFButton(title: "Продолжить тренировку", variant: .primary) {
                handleOpenWorkout(item, preferDetailsForFutureDate: false)
            }
        case .completed:
            EmptyView()
        case .missed, .skipped:
            FFButton(title: "Перепланировать", variant: .primary) {
                dateActionFlow = DateActionFlow(
                    id: "replan-\(item.id)",
                    item: item,
                    mode: .replan,
                )
            }
        }
    }

    private func hasSecondaryActions(for item: PlanScheduleViewModel.DayScheduleItem) -> Bool {
        switch item.status {
        case .planned, .inProgress:
            true
        case .completed:
            viewModel.canRepeat(item)
        case .missed, .skipped:
            false
        }
    }

    @ViewBuilder
    private func secondaryMenu(for item: PlanScheduleViewModel.DayScheduleItem) -> some View {
        Menu {
            secondaryMenuContent(for: item)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FFColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(FFColors.background.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        }
    }

    @ViewBuilder
    private func secondaryMenuContent(for item: PlanScheduleViewModel.DayScheduleItem) -> some View {
        switch item.status {
        case .planned:
            if viewModel.canEditPlannedWorkout(item, details: item.workoutDetails) {
                Button("Редактировать") {
                    openEdit(item)
                }
            }
            Button("Перенести") {
                dateActionFlow = DateActionFlow(
                    id: "move-\(item.id)",
                    item: item,
                    mode: .move,
                )
            }
            if viewModel.canDeletePlannedWorkout(item) {
                Button("Удалить", role: .destructive) {
                    presentDeleteConfirmation(for: item)
                }
            } else {
                Button("Пропустить", role: .destructive) {
                    presentSkipConfirmation(for: item)
                }
            }
        case .inProgress:
            Button("Отменить", role: .destructive) {
                presentSkipConfirmation(for: item)
            }
        case .completed:
            if viewModel.canRepeat(item) {
                Button("Повторить") {
                    dateActionFlow = DateActionFlow(
                        id: "repeat-\(item.id)",
                        item: item,
                        mode: .repeatWorkout,
                    )
                }
            }
        case .missed, .skipped:
            EmptyView()
        }
    }

    private func iconControl(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func headerControl(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(minHeight: 44)
                .padding(.horizontal, FFSpacing.sm)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func infoRowContainer(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
    }

    private func openScheduleDialog(for day: Date) {
        let normalized = Calendar.current.startOfDay(for: day)
        guard viewModel.canSchedule(on: normalized) else {
            alertFlow = .pastSchedule
            return
        }
        scheduleTargetDay = defaultScheduleDate(for: day)
        Task { @MainActor in
            await viewModel.ensureLastCompletedRecordLoaded()
            isScheduleDialogPresented = true
        }
    }

    private func handleCalendarDayTap(_ day: Date) {
        Task { @MainActor in
            await selectCalendarDay(day)
        }
    }

    private func handleCalendarDayLongPress(_ day: Date) {
        Task { @MainActor in
            await selectCalendarDay(day)
            openScheduleDialog(for: day)
        }
    }

    private func selectCalendarDay(_ day: Date) async {
        if viewModel.isInCurrentMonth(day) {
            await viewModel.selectDay(day)
        } else {
            await viewModel.selectDayFromAdjacentMonth(day)
        }
    }

    private func calendarDayAccessibilityHint(status: TrainingDayStatus?, isSchedulable: Bool) -> String {
        let statusTitle = viewModel.statusTitle(status)
        guard isSchedulable else { return statusTitle }
        return "\(statusTitle). Нажмите и удерживайте, чтобы запланировать тренировку."
    }

    private func defaultScheduleDate(for day: Date) -> Date {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)
        let defaultHour = calendar.isDateInToday(normalizedDay) ? max(currentRoundedHourMinute.hour, 6) : 18
        let defaultMinute = calendar.isDateInToday(normalizedDay) ? currentRoundedHourMinute.minute : 0
        let components = calendar.dateComponents([.year, .month, .day], from: normalizedDay)
        return calendar.date(
            from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: defaultHour,
                minute: defaultMinute
            )
        ) ?? normalizedDay
    }

    private var currentRoundedHourMinute: (hour: Int, minute: Int) {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 18
        let minute = components.minute ?? 0
        let roundedMinute = minute <= 30 ? 30 : 0
        let resolvedHour = minute <= 30 ? hour : min(hour + 1, 23)
        components.hour = resolvedHour
        components.minute = roundedMinute
        return (resolvedHour, roundedMinute)
    }

    private func relativeDayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: day)
        if calendar.isDateInToday(normalized) {
            return "Сегодня"
        }
        if calendar.isDateInTomorrow(normalized) {
            return "Завтра"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: normalized)
    }

    private func cellBackgroundColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return FFColors.surface
        }
        if isToday {
            return FFColors.surface.opacity(0.55)
        }
        return .clear
    }

    private func cellBorderColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return FFColors.accent
        }
        if isToday {
            return FFColors.gray500
        }
        return FFColors.gray700.opacity(0.2)
    }

    private func pillColor(_ status: TrainingDayStatus) -> Color {
        switch status {
        case .planned:
            planStatusColor(.planned)
        case .inProgress:
            planStatusColor(.inProgress)
        case .completed:
            planStatusColor(.completed)
        case .missed, .skipped:
            planStatusColor(.skipped)
        }
    }

    private func planStatusColor(_ status: PlanStatusPalette) -> Color {
        switch status {
        case .planned:
            Color(red: 0.18, green: 0.45, blue: 0.86)
        case .inProgress:
            Color(red: 0.84, green: 0.47, blue: 0.12)
        case .completed:
            Color(red: 0.18, green: 0.62, blue: 0.35)
        case .skipped:
            Color(red: 0.79, green: 0.22, blue: 0.22)
        }
    }

    private enum PlanStatusPalette {
        case planned
        case inProgress
        case completed
        case skipped
    }

    private func applyPendingPlanFocusIfNeeded() async {
        guard let requestedDay = await MainActor.run(body: { PlanNavigationCoordinator.shared.consumePendingDay() }) else {
            return
        }
        await viewModel.focus(on: requestedDay)
    }

    private func isLocalProgramTemplate(_ item: PlanScheduleViewModel.DayScheduleItem) -> Bool {
        item.source == .program && !item.planId.hasPrefix("remote-") && item.workoutDetails != nil
    }

    private func handleOpenWorkout(
        _ item: PlanScheduleViewModel.DayScheduleItem,
        preferDetailsForFutureDate: Bool,
    ) {
        if item.isPendingRemoteCreation {
            presentDetails(item)
            return
        }
        if preferDetailsForFutureDate, viewModel.isFutureDay(item.day) {
            presentDetails(item)
            return
        }

        switch item.source {
        case .program:
            if isLocalProgramTemplate(item) {
                Task {
                    if let details = await viewModel.resolveWorkoutDetails(for: item) {
                        await MainActor.run {
                            onOpenPresetWorkout(details, .program, item.programId, item.planId)
                        }
                    } else {
                        await MainActor.run {
                            presentDetails(item)
                        }
                    }
                }
                return
            }
            guard let programId = item.programId?.trimmedNilIfEmpty,
                  let workoutId = item.workoutId?.trimmedNilIfEmpty
            else {
                presentDetails(item)
                return
            }
            onOpenProgramWorkout(programId, workoutId)

        case .freestyle:
            Task {
                if let details = await viewModel.resolveWorkoutDetails(for: item) {
                    await MainActor.run {
                        onOpenPresetWorkout(details, .freestyle, nil, item.planId)
                    }
                } else {
                    await MainActor.run {
                        onOpenQuickWorkoutBuilder()
                    }
                }
            }

        case .template:
            Task {
                if let templateWorkout = await viewModel.resolveWorkoutDetails(for: item) {
                    await MainActor.run {
                        onOpenPresetWorkout(templateWorkout, .template, nil, item.planId)
                    }
                } else {
                    await MainActor.run {
                        presentDetails(item)
                    }
                }
            }
        }
    }

    private func presentDeleteConfirmation(for item: PlanScheduleViewModel.DayScheduleItem) {
        Task { @MainActor in
            await Task.yield()
            alertFlow = .delete(item)
        }
    }

    private func presentSkipConfirmation(for item: PlanScheduleViewModel.DayScheduleItem) {
        Task { @MainActor in
            await Task.yield()
            alertFlow = .skip(item)
        }
    }

    private func handleOpenResult(_ item: PlanScheduleViewModel.DayScheduleItem) {
        switch item.source {
        case .program:
            if isLocalProgramTemplate(item) {
                presentDetails(item)
                return
            }
            guard let programId = item.programId?.trimmedNilIfEmpty,
                  let workoutId = item.workoutId?.trimmedNilIfEmpty
            else {
                presentDetails(item)
                return
            }
            onOpenProgramWorkout(programId, workoutId)
        case .freestyle, .template:
            presentDetails(item)
        }
    }

    private func openCompletedItem(_ item: PlanScheduleViewModel.DayScheduleItem) {
        Task {
            if let record = await viewModel.completedRecord(for: item) {
                await MainActor.run {
                    onOpenCompletedWorkout(record)
                }
                return
            }
            await MainActor.run {
                handleOpenResult(item)
            }
        }
    }

    private func openInProgressItemFromList(_ item: PlanScheduleViewModel.DayScheduleItem) {
        switch item.source {
        case .program:
            handleOpenWorkout(item, preferDetailsForFutureDate: false)
        case .template:
            handleOpenWorkout(item, preferDetailsForFutureDate: false)
        case .freestyle:
            Task {
                if let details = await viewModel.resolveWorkoutDetails(for: item) {
                    await MainActor.run {
                        onOpenPresetWorkout(details, .freestyle, nil, item.planId)
                    }
                } else {
                    await MainActor.run {
                        onOpenQuickWorkoutBuilder()
                    }
                }
            }
        }
    }

    private func openCard(_ item: PlanScheduleViewModel.DayScheduleItem) {
        switch item.status {
        case .completed:
            openCompletedItem(item)
        case .planned:
            presentDetails(item)
        case .inProgress:
            openInProgressItemFromList(item)
        case .missed, .skipped:
            presentDetails(item)
        }
    }

    private func presentDetails(_ item: PlanScheduleViewModel.DayScheduleItem) {
        Task {
            let workoutDetails = await viewModel.resolveWorkoutDetails(for: item)
            await MainActor.run {
                workoutDetailsFlow = WorkoutDetailsFlow(
                    id: item.id,
                    item: item,
                    workoutDetails: workoutDetails,
                )
            }
        }
    }

    private func openEdit(_ item: PlanScheduleViewModel.DayScheduleItem) {
        guard viewModel.canEditPlannedWorkout(item, details: item.workoutDetails) else { return }
        Task {
            let resolvedDetails = await viewModel.resolveWorkoutDetails(for: item)
            let editableWorkout = resolvedDetails ?? viewModel.editableDraft(for: item)
            await MainActor.run {
                editManualWorkoutFlow = EditManualWorkoutFlow(
                    id: "menu-edit-\(item.id)",
                    item: item,
                    workoutDetails: editableWorkout,
                )
            }
        }
    }
}

private enum PlanDateActionMode {
    case move
    case repeatWorkout
    case replan

    var title: String {
        switch self {
        case .move:
            "Перенести тренировку"
        case .repeatWorkout:
            "Запланировать повтор"
        case .replan:
            "Перепланировать тренировку"
        }
    }

    var actionTitle: String {
        switch self {
        case .move:
            "Перенести"
        case .repeatWorkout, .replan:
            "Запланировать"
        }
    }

    var dateLabel: String {
        switch self {
        case .move:
            "Новая дата"
        case .repeatWorkout:
            "Дата повтора"
        case .replan:
            "Новая дата плана"
        }
    }
}

private struct PlanScheduleConfigurationSheet: View {
    @Binding var scheduledAt: Date
    let selectedDay: Date
    let hasLastWorkout: Bool
    let onClose: () -> Void
    let onQuickWorkout: () -> Void
    let onTemplate: () -> Void
    let onRepeatLast: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            FFColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: FFSpacing.md) {
                    HStack(alignment: .top, spacing: FFSpacing.sm) {
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text("План на \(formattedDay)")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Выберите время и добавьте тренировку в выбранный день.")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: FFSpacing.sm)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FFColors.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(FFColors.surface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Закрыть")
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            HStack(alignment: .center) {
                                Text("Время")
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                Spacer()
                                Text(formattedTime)
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.accent)
                                    .padding(.horizontal, FFSpacing.sm)
                                    .padding(.vertical, FFSpacing.xs)
                                    .background(FFColors.accent.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            HStack(spacing: FFSpacing.xs) {
                                ForEach(timeOptions, id: \.label) { option in
                                    timeChip(option: option)
                                }
                            }

                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text("Точное время")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                                DatePicker(
                                    "Время",
                                    selection: $scheduledAt,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .datePickerStyle(.wheel)
                                .frame(maxHeight: 140)
                                .clipped()
                                .colorScheme(.light)
                            }
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            Text("Что запланировать")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)

                            FFButton(title: "Быстрая тренировка", variant: .primary, action: onQuickWorkout)
                            FFButton(title: "Шаблон", variant: .secondary, action: onTemplate)
                            if hasLastWorkout {
                                FFButton(title: "Повторить последнюю", variant: .secondary, action: onRepeatLast)
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.top, FFSpacing.lg)
                .padding(.bottom, FFSpacing.lg)
            }
        }
        .presentationDetents([.fraction(0.72), .large])
    }

    private var formattedDay: String {
        selectedDay.formatted(
            Date.FormatStyle()
                .day(.defaultDigits)
                .month(.abbreviated)
                .year()
        )
    }

    private var formattedTime: String {
        scheduledAt.formatted(date: .omitted, time: .shortened)
    }

    private var timeOptions: [TimeOption] {
        let hourValues: [Int]
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDay) {
            let rounded = roundedCurrentHour(calendar: calendar)
            hourValues = Array(Set([rounded, max(rounded + 2, 18), 20])).sorted()
        } else {
            hourValues = [7, 12, 18]
        }

        return hourValues.map { hour in
            TimeOption(
                label: String(format: "%02d:00", hour),
                date: applyingTime(hour: hour, minute: 0)
            )
        }
    }

    private func timeChip(option: TimeOption) -> some View {
        let isSelected = Calendar.current.component(.hour, from: scheduledAt) == Calendar.current.component(.hour, from: option.date)
            && Calendar.current.component(.minute, from: scheduledAt) == Calendar.current.component(.minute, from: option.date)

        return Button {
            scheduledAt = option.date
        } label: {
            Text(option.label)
                .font(FFTypography.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, FFSpacing.sm)
                .ffSelectableSurface(isSelected: isSelected, emphasis: .accent)
        }
        .buttonStyle(.plain)
    }

    private func applyingTime(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDay)
        return calendar.date(
            from: DateComponents(
                year: dayComponents.year,
                month: dayComponents.month,
                day: dayComponents.day,
                hour: hour,
                minute: minute
            )
        ) ?? scheduledAt
    }

    private func roundedCurrentHour(calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let hour = components.hour ?? 18
        let minute = components.minute ?? 0
        return minute > 0 ? min(hour + 1, 22) : hour
    }

    private struct TimeOption {
        let label: String
        let date: Date
    }
}

private struct PlanTemplatePickerSheet: View {
    let templates: [WorkoutTemplateDraft]
    let loadTemplates: () async -> [WorkoutTemplateDraft]
    let onPick: (WorkoutTemplateDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var resolvedTemplates: [WorkoutTemplateDraft]
    @State private var isLoading = false

    init(
        templates: [WorkoutTemplateDraft],
        loadTemplates: @escaping () async -> [WorkoutTemplateDraft],
        onPick: @escaping (WorkoutTemplateDraft) -> Void,
    ) {
        self.templates = templates
        self.loadTemplates = loadTemplates
        self.onPick = onPick
        _resolvedTemplates = State(initialValue: templates)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()
                if isLoading, resolvedTemplates.isEmpty {
                    FFScreenSpinner()
                } else if resolvedTemplates.isEmpty {
                    FFEmptyState(
                        title: "Шаблонов пока нет",
                        message: "Создайте шаблон во вкладке «Тренировка», затем он появится здесь.",
                    )
                    .padding(.horizontal, FFSpacing.md)
                } else {
                    ScrollView {
                        VStack(spacing: FFSpacing.sm) {
                            ForEach(resolvedTemplates) { template in
                                Button {
                                    onPick(template)
                                } label: {
                                    infoRow(template: template)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.vertical, FFSpacing.md)
                    }
                }
            }
            .navigationTitle("Выберите шаблон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Закрыть")
                }
            }
            .task {
                await reloadTemplates()
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func reloadTemplates() async {
        isLoading = true
        let latest = await loadTemplates()
        resolvedTemplates = latest
        isLoading = false
    }

    private func infoRow(template: WorkoutTemplateDraft) -> some View {
        HStack(spacing: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text(template.name)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Text("Упражнений: \(template.exercises.count)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FFColors.textSecondary)
        }
        .padding(FFSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }
}

private struct PlanMoveWorkoutSheet: View {
    let item: PlanScheduleViewModel.DayScheduleItem
    let mode: PlanDateActionMode
    let conflictsCount: (Date) -> Int
    let onCancel: () -> Void
    let onApply: (Date) -> Void

    @State private var targetDay: Date
    @State private var isConflictAlertPresented = false
    @State private var pendingTargetDay: Date?

    init(
        item: PlanScheduleViewModel.DayScheduleItem,
        mode: PlanDateActionMode,
        conflictsCount: @escaping (Date) -> Int,
        onCancel: @escaping () -> Void,
        onApply: @escaping (Date) -> Void,
    ) {
        self.item = item
        self.mode = mode
        self.conflictsCount = conflictsCount
        self.onCancel = onCancel
        self.onApply = onApply
        let baseDay = mode == .move ? item.day : Calendar.current.date(byAdding: .day, value: 1, to: item.day) ?? item.day
        let minimumDay = Calendar.current.startOfDay(for: Date())
        _targetDay = State(initialValue: max(baseDay, minimumDay))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()
                VStack(spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(item.title)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(descriptionText)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                            if item.sourceKind == .program, mode == .move {
                                Text("Режим: перенести только эту тренировку")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            DatePicker(
                                mode.dateLabel,
                                selection: $targetDay,
                                in: minimumSelectableDay...,
                                displayedComponents: .date,
                            )
                            .datePickerStyle(.graphical)
                            .tint(FFColors.accent)

                            DatePicker(
                                "Время",
                                selection: $targetDay,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxHeight: 110)
                            .colorScheme(.light)
                        }

                        let conflicts = conflictsCount(targetDay)
                        if conflicts > 0 {
                            Text("На выбранную дату уже есть \(conflicts) тренировок.")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.danger)
                                .padding(.top, FFSpacing.xs)
                        }
                    }

                    HStack(spacing: FFSpacing.sm) {
                        FFButton(title: "Отмена", variant: .secondary, action: onCancel)
                        FFButton(title: mode.actionTitle, variant: .primary) {
                            let conflicts = conflictsCount(targetDay)
                            if conflicts > 0 {
                                pendingTargetDay = targetDay
                                isConflictAlertPresented = true
                            } else {
                                onApply(targetDay)
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Конфликт по дате", isPresented: $isConflictAlertPresented) {
                Button("Отмена", role: .cancel) {}
                Button("Продолжить") {
                    guard let pendingTargetDay else { return }
                    onApply(pendingTargetDay)
                }
            } message: {
                let conflicts = conflictsCount(pendingTargetDay ?? targetDay)
                Text("На выбранную дату уже есть \(conflicts) тренировок. Продолжить?")
            }
        }
    }

    private var descriptionText: String {
        switch mode {
        case .move:
            "Выберите новую дату тренировки"
        case .repeatWorkout:
            "Создайте повтор тренировки на удобную дату"
        case .replan:
            "Создайте новую запланированную тренировку для этого дня"
        }
    }

    private var minimumSelectableDay: Date {
        Calendar.current.startOfDay(for: Date())
    }
}

private struct PlanWorkoutDetailsSheet: View {
    let item: PlanScheduleViewModel.DayScheduleItem
    let statusTitle: String
    let workoutDetails: WorkoutDetailsModel?
    let canEdit: Bool
    let canDelete: Bool
    let pendingSyncMessage: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: FFSpacing.md) {
                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                Text(item.title)
                                    .font(FFTypography.h2)
                                    .foregroundStyle(FFColors.textPrimary)
                                Text(item.day.formatted(date: .abbreviated, time: .shortened))
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                Text(item.sourceTitle)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                                Text("Статус: \(statusTitle.lowercased())")
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                            }
                        }

                        if let pendingSyncMessage {
                            FFCard {
                                Text(pendingSyncMessage)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        if let workoutDetails {
                            if let coachNote = workoutDetails.coachNote?.trimmingCharacters(in: .whitespacesAndNewlines), !coachNote.isEmpty {
                                FFCard {
                                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                        Text("Комментарий")
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                        Text(coachNote)
                                            .font(FFTypography.body)
                                            .foregroundStyle(FFColors.textSecondary)
                                    }
                                }
                            }

                            if !workoutDetails.exercises.isEmpty {
                                FFCard {
                                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                        Text("Упражнения")
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                        ForEach(workoutDetails.exercises.sorted(by: { $0.orderIndex < $1.orderIndex })) { exercise in
                                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                                Text(exercise.name)
                                                    .font(FFTypography.body.weight(.semibold))
                                                    .foregroundStyle(FFColors.textPrimary)
                                                    .lineLimit(2)
                                                Text("\(max(1, exercise.sets)) подхода • \(repsLabel(for: exercise)) повторов")
                                                    .font(FFTypography.caption)
                                                    .foregroundStyle(FFColors.textSecondary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.bottom, FFSpacing.xxs)
                                        }
                                    }
                                }
                            }
                        }

                        if canEdit || canDelete {
                            VStack(spacing: FFSpacing.sm) {
                                if canEdit {
                                    FFButton(title: "Редактировать тренировку", variant: .primary, action: onEdit)
                                }
                                if canDelete {
                                    Button("Удалить тренировку", role: .destructive, action: onDelete)
                                        .font(FFTypography.body.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(FFColors.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                                .stroke(FFColors.gray700, lineWidth: 1)
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.md)
                }
            }
            .navigationTitle("Детали тренировки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func repsLabel(for exercise: WorkoutExercise) -> String {
        if let repsMin = exercise.repsMin, let repsMax = exercise.repsMax {
            return "\(repsMin)-\(repsMax)"
        }
        if let repsMin = exercise.repsMin {
            return "\(repsMin)"
        }
        return "по самочувствию"
    }
}

#Preview("План") {
    NavigationStack {
        PlanScheduleScreen(
            viewModel: PlanScheduleViewModel(userSub: "preview-athlete"),
        )
        .navigationTitle("План")
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension WorkoutTemplateDraft {
    func asWorkoutDetailsModel() -> WorkoutDetailsModel {
        let exercises = exercises.enumerated().map { index, item in
            WorkoutExercise(
                id: "template-\(id)-\(item.id)-\(index)",
                name: item.name,
                sets: max(1, item.sets),
                repsMin: item.repsMin,
                repsMax: item.repsMax,
                targetRpe: item.targetRpe,
                restSeconds: item.restSeconds,
                notes: item.notes,
                orderIndex: index,
            )
        }

        return WorkoutDetailsModel(
            id: id,
            title: name,
            dayOrder: 0,
            coachNote: "Тренировка из шаблона",
            exercises: exercises,
        )
    }
}
