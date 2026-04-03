import Foundation
import Observation

@Observable
@MainActor
final class WorkoutHomeViewModel {
    struct RemoteWorkoutTarget: Equatable, Identifiable {
        let programId: String
        let workoutId: String
        let title: String

        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    struct ResumeWorkout: Equatable {
        enum Source: Equatable {
            case local(ActiveWorkoutSession)
            case remote(RemoteWorkoutTarget)
        }

        let source: Source
        let workoutName: String
        let completedExercisesCount: Int
        let totalExercisesCount: Int
        let startedAt: Date?

        var metricsText: String {
            "Выполнено: \(completedExercisesCount) из \(totalExercisesCount) упражнений"
        }
    }

    struct PresetWorkoutTarget: Equatable {
        let workout: WorkoutDetailsModel
        let source: WorkoutSource
        let programId: String?
    }

    struct TodayWorkout: Equatable {
        enum LaunchTarget: Equatable {
            case remote(RemoteWorkoutTarget)
            case preset(PresetWorkoutTarget)
        }

        let title: String
        let subtitle: String
        let detailText: String
        let status: TrainingDayStatus
        let source: WorkoutSource
        let launchTarget: LaunchTarget?

        var buttonTitle: String {
            launchTarget == nil ? "Открыть план" : "Начать тренировку на сегодня"
        }
    }

    enum PrimaryActionKind: Equatable {
        case resume
        case startToday
        case startWorkout
    }

    struct ProgramProgress: Equatable {
        let programId: String
        let title: String
        let detailsLine: String
        let completedWorkouts: Int
        let totalWorkouts: Int
        let lastCompletedAt: Date?
        let updatedAt: Date?

        var progressText: String {
            "\(completedWorkouts) / \(totalWorkouts) тренировок"
        }

        var progressValue: Double {
            guard totalWorkouts > 0 else { return 0 }
            let value = Double(completedWorkouts) / Double(totalWorkouts)
            return min(max(value, 0), 1)
        }

        var isCompleted: Bool {
            totalWorkouts > 0 && completedWorkouts >= totalWorkouts
        }

        var completionReferenceDate: Date? {
            lastCompletedAt ?? updatedAt
        }

        var actionTitle: String {
            isCompleted ? "Выбрать следующую программу" : "Продолжить программу"
        }
    }

    typealias SyncIndicatorState = SyncStatusKind

    private let userSub: String
    private let trainingStore: TrainingStore
    private let progressStore: WorkoutProgressStore
    private let resumeStore: WorkoutResumeStore
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let calendar: Calendar
    private let syncCoordinator: SyncCoordinator
    private let completedProgramVisibilityDays = 14

    var isLoading = false
    var isShowingCachedData = false
    var isOffline = false
    var resumeWorkout: ResumeWorkout?
    var todayWorkout: TodayWorkout?
    var startWorkoutTarget: RemoteWorkoutTarget?
    var programProgress: ProgramProgress?
    var recentWorkouts: [CompletedWorkoutRecord] = []
    var lastCompleted: CompletedWorkoutRecord?
    var noActiveProgram = true
    var noRecentWorkouts = true
    var syncIndicator: SyncIndicatorState = .savedLocally

    var hasResumeWorkout: Bool {
        resumeWorkout != nil
    }

    var hasTodayWorkout: Bool {
        todayWorkout != nil
    }

    var hasActiveProgram: Bool {
        guard let programProgress else { return false }
        return shouldShowProgramProgress(programProgress)
    }

    var primaryActionKind: PrimaryActionKind {
        if hasResumeWorkout {
            return .resume
        }
        if hasTodayWorkout {
            return .startToday
        }
        return .startWorkout
    }

    var isProgramCompleted: Bool {
        programProgress?.isCompleted == true
    }

    var canContinueProgram: Bool {
        serverInProgressWorkout != nil || startWorkoutTarget != nil || isProgramCompleted
    }

    private var localResumeCandidate: ResumeWorkout?
    private var remoteResumeCandidate: ResumeWorkout?
    private var serverInProgressWorkout: RemoteWorkoutTarget?
    private var localTodayCandidates: [TodayWorkout] = []
    private var remoteTodayCandidates: [TodayWorkout] = []

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        resumeStore: WorkoutResumeStore = LocalWorkoutResumeStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        calendar: Calendar = .current,
        syncCoordinator: SyncCoordinator = .shared,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.progressStore = progressStore
        self.resumeStore = resumeStore
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.athleteTrainingClient = athleteTrainingClient
        self.calendar = calendar
        self.syncCoordinator = syncCoordinator
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        guard !userSub.isEmpty else { return }

        isLoading = true
        isOffline = !networkMonitor.currentStatus
        remoteTodayCandidates = []

        await syncCoordinator.activate(namespace: userSub)
        await loadLocalContext()
        await loadCachedRemoteContext()

        if networkMonitor.currentStatus, let athleteTrainingClient {
            async let summaryResult = athleteTrainingClient.homeSummary()
            async let syncResult = athleteTrainingClient.syncStatus()

            await applyHomeSummary(await summaryResult, cacheTTL: 60 * 5)
            await applySyncStatus(await syncResult, cacheTTL: 60 * 2)
        } else {
            syncIndicator = .savedLocally
        }

        finalizeStates()
        await persistResumeState()
        isLoading = false
    }

    func startNextWorkout() async -> RemoteWorkoutTarget? {
        guard let startWorkoutTarget else { return nil }
        if !(await canLaunchRemotely(target: startWorkoutTarget)) {
            await reload()
            return nil
        }
        _ = await syncCoordinator.enqueueStartWorkout(
            namespace: userSub,
            workoutInstanceId: startWorkoutTarget.workoutId,
            startedAt: Date(),
        )
        return startWorkoutTarget
    }

    func continueProgram() async -> RemoteWorkoutTarget? {
        if let serverInProgressWorkout {
            return serverInProgressWorkout
        }
        return await startNextWorkout()
    }

    private func loadLocalContext() async {
        async let active = progressStore.latestActiveSession(userSub: userSub)
        async let history = trainingStore.history(userSub: userSub, source: nil, limit: 8)
        async let monthPlans = trainingStore.plans(userSub: userSub, month: Date())
        let storedResume = await resumeStore.latest(userSub: userSub)

        if let activeCandidate = await active,
           await canLaunch(session: activeCandidate)
        {
            let snapshot = await progressStore.load(
                userSub: activeCandidate.userSub,
                programId: activeCandidate.programId,
                workoutId: activeCandidate.workoutId,
            )

            let storedMatch = storedResume?.matching(
                programId: activeCandidate.programId,
                workoutId: activeCandidate.workoutId,
            )

            let completed = max(
                completedExercisesCount(
                    snapshot: snapshot,
                    fallbackCurrentExerciseIndex: activeCandidate.currentExerciseIndex,
                ),
                storedMatch?.completedExercisesCount ?? 0,
            )
            let total = max(
                totalExercisesCount(snapshot: snapshot, fallbackCompletedCount: completed),
                storedMatch?.totalExercisesCount ?? 0,
                completed,
                1,
            )

            localResumeCandidate = ResumeWorkout(
                source: .local(activeCandidate),
                workoutName: snapshot?.workoutDetails?.title.trimmedNilIfEmpty
                    ?? storedMatch?.workoutName
                    ?? "Незавершённая тренировка",
                completedExercisesCount: completed,
                totalExercisesCount: total,
                startedAt: snapshot?.startedAt ?? storedMatch?.startedAt,
            )
        } else {
            localResumeCandidate = nil
        }

        let allHistory = await history
        recentWorkouts = allHistory
        lastCompleted = allHistory.first
        localTodayCandidates = await resolveLocalTodayCandidates(from: await monthPlans)
        rebuildResume()
        rebuildTodayWorkout()
    }

    private func loadCachedRemoteContext() async {
        isShowingCachedData = false

        if let cachedSummary = await cacheStore.get(
            cacheKeys.homeSummary,
            as: AthleteHomeSummaryResponse.self,
            namespace: userSub,
        ) {
            isShowingCachedData = true
            await apply(summary: cachedSummary)
        }

        if let cachedSync = await cacheStore.get(
            cacheKeys.syncStatus,
            as: AthleteSyncStatusResponse.self,
            namespace: userSub,
        ) {
            isShowingCachedData = true
            syncIndicator = mapSyncState(cachedSync)
        }

        let diagnostics = await syncCoordinator.diagnostics(namespace: userSub)
        if diagnostics.pendingCount > 0 || diagnostics.hasDelayedRetries {
            isShowingCachedData = true
            syncIndicator = diagnostics.hasDelayedRetries ? .delayed : .savedLocally
        }
    }

    private func applyHomeSummary(
        _ result: Result<AthleteHomeSummaryResponse, APIError>,
        cacheTTL: TimeInterval,
    ) async {
        switch result {
        case let .success(summary):
            await apply(summary: summary)
            await cacheStore.set(
                cacheKeys.homeSummary,
                value: summary,
                namespace: userSub,
                ttl: cacheTTL,
            )
            isShowingCachedData = false
        case .failure:
            break
        }
    }

    private func applySyncStatus(
        _ result: Result<AthleteSyncStatusResponse, APIError>,
        cacheTTL: TimeInterval,
    ) async {
        let diagnostics = await syncCoordinator.diagnostics(namespace: userSub)
        if diagnostics.pendingCount > 0 {
            syncIndicator = diagnostics.hasDelayedRetries ? .delayed : .savedLocally
            return
        }

        switch result {
        case let .success(sync):
            syncIndicator = mapSyncState(sync)
            await cacheStore.set(cacheKeys.syncStatus, value: sync, namespace: userSub, ttl: cacheTTL)
            isShowingCachedData = false
        case .failure:
            if !networkMonitor.currentStatus {
                syncIndicator = .savedLocally
            }
        }
    }

    private func apply(summary: AthleteHomeSummaryResponse) async {
        if let activeWorkout = summary.activeWorkout,
           !(await syncCoordinator.hasPendingAbandon(
               namespace: userSub,
               workoutInstanceId: activeWorkout.workoutInstanceId
           ))
        {
            serverInProgressWorkout = remoteWorkoutTarget(from: activeWorkout)
        } else {
            serverInProgressWorkout = nil
        }

        startWorkoutTarget = remoteStartTarget(from: summary)

        if let activeProgram = summary.activeProgram {
            let lastCompletedAt = parseISODate(activeProgram.lastCompletedAt)
                ?? recentWorkouts.first(where: { $0.programId == activeProgram.programId })?.finishedAt
            programProgress = ProgramProgress(
                programId: activeProgram.programId,
                title: activeProgram.title,
                detailsLine: activeProgram.summaryLine?.trimmedNilIfEmpty ?? "Активная программа",
                completedWorkouts: min(activeProgram.completedWorkouts, activeProgram.totalWorkouts),
                totalWorkouts: max(activeProgram.totalWorkouts, 1),
                lastCompletedAt: lastCompletedAt,
                updatedAt: parseISODate(summary.generatedAt),
            )
        } else {
            programProgress = nil
        }

        let remoteRecent = summary.recentActivity.recentWorkouts.compactMap(makeCompletedWorkoutRecord)
        if !remoteRecent.isEmpty {
            for record in remoteRecent {
                await trainingStore.appendHistory(record)
            }
            recentWorkouts = remoteRecent
            lastCompleted = remoteRecent.first
        }

        if let todayWorkout = summary.todayWorkout {
            let pendingAbandon = await syncCoordinator.hasPendingAbandon(
                namespace: userSub,
                workoutInstanceId: todayWorkout.workoutInstanceId
            )
            if pendingAbandon, mapStatus(todayWorkout.status) == .inProgress {
                remoteTodayCandidates = []
            } else {
                remoteTodayCandidates = makeRemoteTodayWorkout(from: todayWorkout, programTitle: summary.activeProgram?.title)
                    .map { [$0] } ?? []
            }
        } else {
            remoteTodayCandidates = []
        }

        await updateRemoteResumeCandidate()
        rebuildTodayWorkout()
    }

    private func updateRemoteResumeCandidate() async {
        guard let serverInProgressWorkout else {
            remoteResumeCandidate = nil
            rebuildResume()
            return
        }

        let snapshot = await progressStore.load(
            userSub: userSub,
            programId: serverInProgressWorkout.programId,
            workoutId: serverInProgressWorkout.workoutId,
        )
        let storedResume = await resumeStore.latest(userSub: userSub)
        let storedMatch = storedResume?.matching(
            programId: serverInProgressWorkout.programId,
            workoutId: serverInProgressWorkout.workoutId,
        )

        let completed = max(
            completedExercisesCount(snapshot: snapshot, fallbackCurrentExerciseIndex: nil),
            storedMatch?.completedExercisesCount ?? 0,
        )
        let total = max(
            totalExercisesCount(snapshot: snapshot, fallbackCompletedCount: completed),
            storedMatch?.totalExercisesCount ?? 0,
            completed,
            1,
        )

        remoteResumeCandidate = ResumeWorkout(
            source: .remote(serverInProgressWorkout),
            workoutName: serverInProgressWorkout.title.trimmedNilIfEmpty
                ?? storedMatch?.workoutName
                ?? "Незавершённая тренировка",
            completedExercisesCount: completed,
            totalExercisesCount: total,
            startedAt: snapshot?.startedAt ?? storedMatch?.startedAt,
        )
        rebuildResume()
    }

    private func rebuildResume() {
        resumeWorkout = remoteResumeCandidate ?? localResumeCandidate
    }

    private func rebuildTodayWorkout() {
        todayWorkout = selectBestTodayWorkout(from: localTodayCandidates + remoteTodayCandidates)
    }

    private func finalizeStates() {
        noActiveProgram = !hasActiveProgram
        noRecentWorkouts = recentWorkouts.isEmpty
    }

    private func persistResumeState() async {
        guard let resumeWorkout else {
            await resumeStore.clear(userSub: userSub)
            return
        }

        let sessionIDs = resolveSessionIDs(from: resumeWorkout.source)
        let stored = StoredResumeWorkout(
            userSub: userSub,
            programId: sessionIDs.programId,
            workoutId: sessionIDs.workoutId,
            workoutName: resumeWorkout.workoutName,
            completedExercisesCount: resumeWorkout.completedExercisesCount,
            totalExercisesCount: max(resumeWorkout.totalExercisesCount, resumeWorkout.completedExercisesCount, 1),
            startedAt: resumeWorkout.startedAt,
        )
        await resumeStore.save(stored)
    }

    private func resolveSessionIDs(from source: ResumeWorkout.Source) -> (programId: String, workoutId: String) {
        switch source {
        case let .local(session):
            return (session.programId, session.workoutId)
        case let .remote(target):
            return (target.programId, target.workoutId)
        }
    }

    private func totalExercisesCount(snapshot: WorkoutProgressSnapshot?, fallbackCompletedCount: Int) -> Int {
        if let total = snapshot?.workoutDetails?.exercises.count, total > 0 {
            return total
        }

        if let total = snapshot?.exercises.count, total > 0 {
            return total
        }

        return max(fallbackCompletedCount, 1)
    }

    private func completedExercisesCount(
        snapshot: WorkoutProgressSnapshot?,
        fallbackCurrentExerciseIndex: Int?,
    ) -> Int {
        if let snapshot {
            let completed = snapshot.exercises.values.reduce(0) { partial, exercise in
                let hasProgress = exercise.sets.contains { set in
                    set.isCompleted
                        || !set.repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !set.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !set.rpeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return partial + (hasProgress ? 1 : 0)
            }
            if completed > 0 {
                return completed
            }
        }

        if let fallbackCurrentExerciseIndex {
            return max(0, fallbackCurrentExerciseIndex)
        }

        return 0
    }

    private func mapSyncState(_ response: AthleteSyncStatusResponse) -> SyncIndicatorState {
        if response.isDelayed == true {
            return .delayed
        }
        if let status = response.status {
            switch status {
            case .synced:
                return .synced
            case .savedLocally:
                return .savedLocally
            case .delayed:
                return .delayed
            case .unknown:
                break
            }
        }
        if response.hasPendingLocalChanges == true || (response.pendingOperations ?? 0) > 0 {
            return .savedLocally
        }
        if !networkMonitor.currentStatus {
            return .savedLocally
        }
        return .synced
    }

    private func canLaunch(session: ActiveWorkoutSession) async -> Bool {
        let hasCachedWorkoutDetails = await cacheStore.get(
            "workout.details:\(session.programId):\(session.workoutId)",
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) != nil
        let snapshot = await progressStore.load(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
        )
        let hasSnapshotDetails = snapshot?.workoutDetails != nil
        return WorkoutDomainRules.canLaunchSession(
            session: session,
            isOnline: networkMonitor.currentStatus,
            hasCachedWorkoutDetails: hasCachedWorkoutDetails,
            hasSnapshotDetails: hasSnapshotDetails,
        )
    }

    private func shouldShowProgramProgress(_ progress: ProgramProgress, now: Date = Date()) -> Bool {
        guard progress.isCompleted else { return true }
        guard let completionDate = progress.completionReferenceDate else { return true }

        let completionDay = calendar.startOfDay(for: completionDate)
        let currentDay = calendar.startOfDay(for: now)
        let elapsed = calendar.dateComponents([.day], from: completionDay, to: currentDay).day ?? 0
        return elapsed < completedProgramVisibilityDays
    }

    private func resolveLocalTodayCandidates(from plans: [TrainingDayPlan]) async -> [TodayWorkout] {
        let today = calendar.startOfDay(for: Date())
        var resolved: [TodayWorkout] = []

        for plan in plans where calendar.isDate(plan.day, inSameDayAs: today) {
            guard let status = todayWorkoutStatus(for: plan.status) else { continue }

            let launchTarget = await resolveLaunchTarget(for: plan)
            resolved.append(
                TodayWorkout(
                    title: plan.title,
                    subtitle: localTodaySubtitle(for: plan),
                    detailText: statusDetailText(status, source: plan.source),
                    status: status,
                    source: plan.source,
                    launchTarget: launchTarget,
                ),
            )
        }

        return resolved
    }

    private func makeRemoteTodayWorkout(
        from workout: AthleteHomeWorkoutSummary,
        programTitle: String?,
    ) -> TodayWorkout? {
        let source: WorkoutSource = workout.source == .custom ? .freestyle : .program
        guard let status = todayWorkoutStatus(for: mapStatus(workout.status)) else {
            return nil
        }
        let title = workout.title.trimmedNilIfEmpty ?? "Тренировка"
        let subtitle: String
        if source == .program {
            subtitle = programTitle?.trimmedNilIfEmpty.map { "Сегодня • \($0)" } ?? "Сегодня • По программе"
        } else {
            subtitle = "Сегодня • Своя тренировка"
        }

        return TodayWorkout(
            title: title,
            subtitle: subtitle,
            detailText: statusDetailText(status, source: source),
            status: status,
            source: source,
            launchTarget: .remote(
                RemoteWorkoutTarget(
                    programId: workout.programId?.trimmedNilIfEmpty ?? source.rawValue,
                    workoutId: workout.workoutInstanceId,
                    title: title,
                ),
            ),
        )
    }

    private func selectBestTodayWorkout(from candidates: [TodayWorkout]) -> TodayWorkout? {
        candidates.max { lhs, rhs in
            todayWorkoutPriority(lhs) < todayWorkoutPriority(rhs)
        }
    }

    private func todayWorkoutPriority(_ candidate: TodayWorkout) -> Int {
        var score = 0
        switch candidate.status {
        case .inProgress:
            score += 100
        case .planned:
            score += 80
        case .completed:
            score += 20
        case .missed, .skipped:
            score += 10
        }

        switch candidate.source {
        case .program:
            score += 30
        case .template:
            score += 20
        case .freestyle:
            score += 10
        }

        if candidate.launchTarget != nil {
            score += 5
        }

        return score
    }

    private func todayWorkoutStatus(for status: TrainingDayStatus) -> TrainingDayStatus? {
        switch status {
        case .planned, .inProgress:
            return status
        case .completed, .missed, .skipped:
            return nil
        }
    }

    private func localTodaySubtitle(for plan: TrainingDayPlan) -> String {
        if let programTitle = plan.programTitle?.trimmedNilIfEmpty {
            return "Сегодня • \(programTitle)"
        }

        switch plan.source {
        case .program:
            return "Сегодня • По программе"
        case .freestyle:
            return "Сегодня • Своя тренировка"
        case .template:
            return "Сегодня • По шаблону"
        }
    }

    private func statusDetailText(_ status: TrainingDayStatus, source: WorkoutSource) -> String {
        let statusTitle = switch status {
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

        let sourceTitle = switch source {
        case .program:
            "программа"
        case .freestyle:
            "ручной старт"
        case .template:
            "шаблон"
        }

        return "\(statusTitle) • \(sourceTitle)"
    }

    private func resolveLaunchTarget(for plan: TrainingDayPlan) async -> TodayWorkout.LaunchTarget? {
        if plan.source == .program,
           !plan.id.hasPrefix("remote-"),
           let workoutDetails = plan.workoutDetails
        {
            return .preset(
                PresetWorkoutTarget(
                    workout: workoutDetails,
                    source: .program,
                    programId: plan.programId,
                ),
            )
        }

        if plan.source == .program,
           let programId = plan.programId?.trimmedNilIfEmpty,
           let workoutId = plan.workoutId?.trimmedNilIfEmpty
        {
            return .remote(
                RemoteWorkoutTarget(
                    programId: programId,
                    workoutId: workoutId,
                    title: plan.title,
                ),
            )
        }

        guard let workoutDetails = await resolveWorkoutDetails(for: plan) else {
            return nil
        }

        return .preset(
            PresetWorkoutTarget(
                workout: workoutDetails,
                source: plan.source,
                programId: plan.programId,
            ),
        )
    }

    private func resolveWorkoutDetails(for plan: TrainingDayPlan) async -> WorkoutDetailsModel? {
        if let workoutDetails = plan.workoutDetails {
            return workoutDetails
        }

        if let cached = await cacheStore.get(
            workoutCacheKey(programId: plan.programId, source: plan.source, workoutId: plan.workoutId),
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) {
            return cached
        }

        if plan.source == .freestyle,
           let workoutId = plan.workoutId?.trimmedNilIfEmpty,
           UUID(uuidString: workoutId) != nil,
           let athleteTrainingClient
        {
            if case let .success(detailsResponse) = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutId) {
                let details = detailsResponse.asWorkoutDetailsModel()
                await cacheStore.set(
                    workoutCacheKey(programId: plan.programId, source: plan.source, workoutId: plan.workoutId),
                    value: details,
                    namespace: userSub,
                    ttl: 60 * 60 * 24,
                )
                return details
            }
        }

        if plan.source == .freestyle {
            return WorkoutDetailsModel(
                id: plan.workoutId?.trimmedNilIfEmpty ?? "quick-\(UUID().uuidString)",
                title: plan.title,
                dayOrder: 0,
                coachNote: "Быстрая тренировка",
                exercises: [],
            )
        }

        return nil
    }

    private func parseISODate(_ value: String?) -> Date? {
        guard let value = value?.trimmedNilIfEmpty else { return nil }
        if let withFractions = Self.iso8601WithFractions.date(from: value) {
            return withFractions
        }
        return Self.iso8601.date(from: value)
    }

    private func parseScheduledDate(_ value: String?) -> Date? {
        guard let value = value?.trimmedNilIfEmpty else { return nil }
        if let withFractions = Self.iso8601WithFractions.date(from: value) {
            return withFractions
        }
        if let dateTime = Self.iso8601.date(from: value) {
            return dateTime
        }
        return Self.dateOnly.date(from: value)
    }

    private func remoteWorkoutTarget(from workout: AthleteHomeWorkoutSummary) -> RemoteWorkoutTarget {
        RemoteWorkoutTarget(
            programId: workout.programId?.trimmedNilIfEmpty ?? workout.source.rawValue,
            workoutId: workout.workoutInstanceId,
            title: workout.title,
        )
    }

    private func remoteStartTarget(from summary: AthleteHomeSummaryResponse) -> RemoteWorkoutTarget? {
        switch summary.primaryAction.type {
        case .continueProgram, .startTodaysWorkout:
            if let target = remoteStartTarget(from: summary.primaryAction.workout) {
                return target
            }
            return remoteStartTarget(from: summary.activeProgram?.nextWorkout)
        case .continueActiveWorkout, .startWorkout:
            if let target = remoteStartTarget(from: summary.primaryAction.workout) {
                return target
            }
            return remoteStartTarget(from: summary.activeProgram?.nextWorkout)
        }
    }

    private func remoteStartTarget(from workout: AthleteHomeWorkoutSummary?) -> RemoteWorkoutTarget? {
        guard let workout, isRemoteWorkoutStartable(workout.status) else {
            return nil
        }
        return remoteWorkoutTarget(from: workout)
    }

    private func isRemoteWorkoutStartable(_ status: AthleteWorkoutInstanceStatus?) -> Bool {
        switch status {
        case .planned, .inProgress, .missed, .none:
            return true
        case .completed, .abandoned:
            return false
        }
    }

    private func canLaunchRemotely(target: RemoteWorkoutTarget) async -> Bool {
        guard networkMonitor.currentStatus,
              let athleteTrainingClient
        else {
            return true
        }

        switch await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: target.workoutId) {
        case let .success(detailsResponse):
            return isRemoteWorkoutStartable(detailsResponse.workout.status)
        case .failure:
            return true
        }
    }

    private func makeCompletedWorkoutRecord(_ workout: AthleteHomeRecentWorkoutSummary) -> CompletedWorkoutRecord? {
        guard let finishedAt = parseISODate(workout.completedAt) else { return nil }
        let duration = max(0, workout.durationSeconds ?? 0)
        let startedAt = finishedAt.addingTimeInterval(TimeInterval(-duration))
        return CompletedWorkoutRecord(
            id: workout.workoutInstanceId,
            userSub: userSub,
            programId: workout.programId ?? workout.source.rawValue,
            workoutId: workout.workoutInstanceId,
            workoutTitle: workout.title,
            source: workout.source == .custom ? .freestyle : .program,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationSeconds: duration,
            completedSets: 0,
            totalSets: 0,
            volume: 0,
            workoutDetails: nil,
            notes: nil,
            overallRPE: nil,
        )
    }

    private func mapStatus(_ status: AthleteWorkoutInstanceStatus?) -> TrainingDayStatus {
        switch status {
        case .planned:
            return .planned
        case .inProgress:
            return .inProgress
        case .none:
            return .planned
        case .completed:
            return .completed
        case .missed:
            return .missed
        case .abandoned:
            return .skipped
        }
    }

    private func workoutCacheKey(programId: String?, source: WorkoutSource, workoutId: String?) -> String {
        let resolvedProgramID = programId?.trimmedNilIfEmpty ?? source.rawValue
        let resolvedWorkoutID = workoutId?.trimmedNilIfEmpty ?? "unknown"
        return "workout.details:\(resolvedProgramID):\(resolvedWorkoutID)"
    }

    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private var cacheKeys: CacheKeys {
        CacheKeys()
    }

    private struct CacheKeys {
        let homeSummary = "athlete.home.summary"
        let syncStatus = "athlete.sync.status"
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
}

private extension StoredResumeWorkout {
    func matching(programId: String, workoutId: String) -> StoredResumeWorkout? {
        guard self.programId == programId, self.workoutId == workoutId else { return nil }
        return self
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
