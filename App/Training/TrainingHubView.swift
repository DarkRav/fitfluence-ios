import Foundation
import Observation
import SwiftUI

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
        let title: String
        let completedExercises: Int
    }

    struct ProgramProgress: Equatable {
        let programId: String
        let title: String
        let completedWorkouts: Int
        let totalWorkouts: Int

        var progressText: String {
            "\(completedWorkouts) / \(totalWorkouts) тренировок"
        }

        var progressValue: Double {
            guard totalWorkouts > 0 else { return 0 }
            let value = Double(completedWorkouts) / Double(totalWorkouts)
            return min(max(value, 0), 1)
        }
    }

    typealias SyncIndicatorState = SyncStatusKind

    private let userSub: String
    private let trainingStore: TrainingStore
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let calendar: Calendar
    private let syncCoordinator: SyncCoordinator

    var isLoading = false
    var isShowingCachedData = false
    var isOffline = false
    var resumeWorkout: ResumeWorkout?
    var startWorkoutTarget: RemoteWorkoutTarget?
    var programProgress: ProgramProgress?
    var recentWorkouts: [CompletedWorkoutRecord] = []
    var lastCompleted: CompletedWorkoutRecord?
    var noActiveProgram = true
    var noRecentWorkouts = true
    var syncIndicator: SyncIndicatorState = .savedLocally

    private var localResumeCandidate: ResumeWorkout?
    private var remoteResumeCandidate: ResumeWorkout?
    private var serverInProgressWorkout: RemoteWorkoutTarget?

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        calendar: Calendar = .current,
        syncCoordinator: SyncCoordinator = .shared,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.progressStore = progressStore
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
        defer {
            isLoading = false
            finalizeStates()
        }

        await syncCoordinator.activate(namespace: userSub)
        await loadLocalContext()
        await loadCachedRemoteContext()

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            syncIndicator = .savedLocally
            return
        }

        async let progressResult = athleteTrainingClient.activeEnrollmentProgress()
        async let calendarResult = athleteTrainingClient.calendar(month: monthKey(for: Date()))
        async let syncResult = athleteTrainingClient.syncStatus()

        await applyActiveEnrollment(await progressResult, cacheTTL: 60 * 5)
        await applyCalendar(await calendarResult, cacheTTL: 60 * 5)
        await applySyncStatus(await syncResult, cacheTTL: 60 * 2)
    }

    func startNextWorkout() async -> RemoteWorkoutTarget? {
        guard let startWorkoutTarget else { return nil }
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
        async let history = trainingStore.history(userSub: userSub, source: nil, limit: 10)

        if let activeCandidate = await active,
           await canLaunch(session: activeCandidate)
        {
            let snapshot = await progressStore.load(
                userSub: activeCandidate.userSub,
                programId: activeCandidate.programId,
                workoutId: activeCandidate.workoutId,
            )
            localResumeCandidate = ResumeWorkout(
                source: .local(activeCandidate),
                title: snapshot?.workoutDetails?.title.trimmedNilIfEmpty ?? "Незавершённая тренировка",
                completedExercises: completedExercisesCount(
                    snapshot: snapshot,
                    fallbackCurrentExerciseIndex: activeCandidate.currentExerciseIndex,
                ),
            )
        } else {
            localResumeCandidate = nil
        }

        let allHistory = await history
        recentWorkouts = allHistory
        lastCompleted = allHistory.first
        rebuildResume()
    }

    private func loadCachedRemoteContext() async {
        isShowingCachedData = false
        let month = monthKey(for: Date())

        if let cachedEnrollment = await cacheStore.get(
            cacheKeys.enrollment,
            as: ActiveEnrollmentProgressResponse.self,
            namespace: userSub,
        ) {
            isShowingCachedData = true
            await apply(progress: cachedEnrollment)
        }

        if let cachedCalendar = await cacheStore.get(
            cacheKeys.calendar(month: month),
            as: AthleteCalendarResponse.self,
            namespace: userSub,
        ) {
            isShowingCachedData = true
            await apply(calendar: cachedCalendar)
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

    private func applyActiveEnrollment(
        _ result: Result<ActiveEnrollmentProgressResponse, APIError>,
        cacheTTL: TimeInterval,
    ) async {
        switch result {
        case let .success(progress):
            await apply(progress: progress)
            await cacheStore.set(cacheKeys.enrollment, value: progress, namespace: userSub, ttl: cacheTTL)
            isShowingCachedData = false
        case .failure:
            break
        }
    }

    private func applyCalendar(
        _ result: Result<AthleteCalendarResponse, APIError>,
        cacheTTL: TimeInterval,
    ) async {
        switch result {
        case let .success(calendarResponse):
            await apply(calendar: calendarResponse)
            await cacheStore.set(
                cacheKeys.calendar(month: monthKey(for: Date())),
                value: calendarResponse,
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

    private func apply(progress: ActiveEnrollmentProgressResponse) async {
        let programId = progress.programId?.trimmedNilIfEmpty
        let nextWorkoutId = progress.nextWorkoutId?.trimmedNilIfEmpty
        let nextWorkoutTitle = progress.nextWorkoutTitle?.trimmedNilIfEmpty ?? "Следующая тренировка"

        if let currentWorkoutId = progress.currentWorkoutId?.trimmedNilIfEmpty,
           progress.currentWorkoutStatus == .inProgress,
           let resolvedProgramId = programId
        {
            serverInProgressWorkout = RemoteWorkoutTarget(
                programId: resolvedProgramId,
                workoutId: currentWorkoutId,
                title: progress.currentWorkoutTitle?.trimmedNilIfEmpty ?? "Текущая тренировка",
            )
        } else if let nextWorkoutId,
                  progress.nextWorkoutStatus == .inProgress,
                  let resolvedProgramId = programId
        {
            serverInProgressWorkout = RemoteWorkoutTarget(
                programId: resolvedProgramId,
                workoutId: nextWorkoutId,
                title: nextWorkoutTitle,
            )
        } else {
            serverInProgressWorkout = nil
        }

        if let nextWorkoutId,
           let resolvedProgramId = programId,
           serverInProgressWorkout?.workoutId != nextWorkoutId
        {
            startWorkoutTarget = RemoteWorkoutTarget(
                programId: resolvedProgramId,
                workoutId: nextWorkoutId,
                title: nextWorkoutTitle,
            )
        } else {
            startWorkoutTarget = nil
        }

        if let resolvedProgramId = programId {
            let completed = max(0, progress.completedSessions ?? 0)
            let total = max(1, progress.totalSessions ?? completed)
            programProgress = ProgramProgress(
                programId: resolvedProgramId,
                title: progress.programTitle?.trimmedNilIfEmpty ?? "Активная программа",
                completedWorkouts: min(completed, total),
                totalWorkouts: total,
            )
        } else {
            programProgress = nil
        }

        await updateRemoteResumeCandidate()
    }

    private func apply(calendar response: AthleteCalendarResponse) async {
        guard serverInProgressWorkout == nil,
              let inProgress = response.workouts.first(where: { $0.status == .inProgress })
        else {
            return
        }

        serverInProgressWorkout = RemoteWorkoutTarget(
            programId: inProgress.programId?.trimmedNilIfEmpty ?? "program",
            workoutId: inProgress.id,
            title: inProgress.title?.trimmedNilIfEmpty ?? "Текущая тренировка",
        )

        await updateRemoteResumeCandidate()
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

        remoteResumeCandidate = ResumeWorkout(
            source: .remote(serverInProgressWorkout),
            title: serverInProgressWorkout.title,
            completedExercises: completedExercisesCount(snapshot: snapshot, fallbackCurrentExerciseIndex: nil),
        )
        rebuildResume()
    }

    private func rebuildResume() {
        resumeWorkout = localResumeCandidate ?? remoteResumeCandidate
    }

    private func finalizeStates() {
        noActiveProgram = programProgress == nil
        noRecentWorkouts = recentWorkouts.isEmpty
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
        if session.source == .program,
           UUID(uuidString: session.programId) != nil,
           networkMonitor.currentStatus
        {
            return true
        }
        if await cacheStore.get(
            "workout.details:\(session.programId):\(session.workoutId)",
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) != nil {
            return true
        }
        if let snapshot = await progressStore.load(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
        ),
            snapshot.workoutDetails != nil
        {
            return true
        }
        return false
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
        let enrollment = "athlete.enrollment.active"
        let syncStatus = "athlete.sync.status"

        func calendar(month: String) -> String {
            "athlete.calendar.\(month)"
        }
    }
}

struct WorkoutHomeScreen: View {
    @State var viewModel: WorkoutHomeViewModel

    let onContinueSession: (ActiveWorkoutSession) -> Void
    let onOpenRemoteWorkout: (WorkoutHomeViewModel.RemoteWorkoutTarget) -> Void
    let onStartQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatWorkout: (CompletedWorkoutRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isOffline {
                    offlineStateCard
                }

                if let resumeWorkout = viewModel.resumeWorkout {
                    ResumeWorkoutCard(
                        title: resumeWorkout.title,
                        completedExercises: resumeWorkout.completedExercises,
                        onContinue: {
                            runResumeAction(resumeWorkout)
                        },
                    )
                }

                StartWorkoutCard(
                    isLoading: false,
                    onStartWorkout: runStartWorkout,
                )

                if let progress = viewModel.programProgress {
                    ProgramProgressCard(
                        programTitle: progress.title,
                        progressText: progress.progressText,
                        progressValue: progress.progressValue,
                        isEnabled: programContinueIsEnabled,
                        onContinueProgram: runContinueProgram,
                    )
                } else if viewModel.noActiveProgram {
                    noActiveProgramCard
                }

                QuickActionsSection(
                    canRepeatLast: viewModel.lastCompleted != nil,
                    onQuickWorkout: {
                        ClientAnalytics.track(.workoutQuickButtonTapped)
                        onStartQuickWorkout()
                    },
                    onOpenTemplates: {
                        ClientAnalytics.track(.workoutTemplatesButtonTapped)
                        onOpenTemplates()
                    },
                    onRepeatLast: {
                        guard let lastCompleted = viewModel.lastCompleted else { return }
                        ClientAnalytics.track(.workoutRepeatLastButtonTapped)
                        onRepeatWorkout(lastCompleted)
                    },
                )

                RecentWorkoutsSection(
                    workouts: viewModel.recentWorkouts,
                    isLoading: viewModel.isLoading,
                    isEmpty: viewModel.noRecentWorkouts,
                    onOpenWorkout: { workout in
                        onRepeatWorkout(workout)
                    },
                )
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.xs)
            .padding(.bottom, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.reload()
        }
        .task {
            ClientAnalytics.track(.workoutHubScreenOpened)
            await viewModel.onAppear()
        }
    }

    private var offlineStateCard: some View {
        FFCard {
            HStack(spacing: FFSpacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FFColors.primary)
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Вы офлайн")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Показываем локальные данные. Обновление будет после подключения.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: FFSpacing.xs)
            }
        }
    }

    private var noActiveProgramCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text("Активной программы нет")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Text("Начните быструю тренировку или используйте шаблоны.")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private var programContinueIsEnabled: Bool {
        viewModel.startWorkoutTarget != nil || viewModel.continueProgramTargetAvailable
    }

    private func runResumeAction(_ resumeWorkout: WorkoutHomeViewModel.ResumeWorkout) {
        ClientAnalytics.track(
            .workoutContinueButtonTapped,
            properties: ["source": "hub_resume"],
        )

        switch resumeWorkout.source {
        case let .local(activeSession):
            onContinueSession(activeSession)
        case let .remote(target):
            onOpenRemoteWorkout(target)
        }
    }

    private func runStartWorkout() {
        guard viewModel.startWorkoutTarget != nil else {
            ClientAnalytics.track(.workoutStartButtonTapped)
            onStartQuickWorkout()
            return
        }

        ClientAnalytics.track(.workoutStartNextButtonTapped)
        Task {
            if let target = await viewModel.startNextWorkout() {
                onOpenRemoteWorkout(target)
            } else {
                onStartQuickWorkout()
            }
        }
    }

    private func runContinueProgram() {
        guard programContinueIsEnabled else { return }

        ClientAnalytics.track(
            .workoutStartNextButtonTapped,
            properties: ["source": "hub_program"],
        )

        Task {
            if let target = await viewModel.continueProgram() {
                onOpenRemoteWorkout(target)
            }
        }
    }
}

struct ResumeWorkoutCard: View {
    let title: String
    let completedExercises: Int
    let onContinue: () -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Продолжить тренировку")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text(title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                        .lineLimit(2)

                    Text("\(completedExercises) \(exerciseWord(for: completedExercises)) выполнено")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }

                FFButton(
                    title: "Продолжить",
                    variant: .secondary,
                    action: onContinue,
                )
            }
        }
    }

    private func exerciseWord(for count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100

        if mod10 == 1, mod100 != 11 {
            return "упражнение"
        }

        if (2 ... 4).contains(mod10), !(12 ... 14).contains(mod100) {
            return "упражнения"
        }

        return "упражнений"
    }
}

struct StartWorkoutCard: View {
    var isLoading = false
    let onStartWorkout: () -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Начать тренировку")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Выберите формат и начните тренировку")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(
                    title: "Начать тренировку",
                    variant: .primary,
                    isLoading: isLoading,
                    action: onStartWorkout,
                )
            }
        }
    }
}

struct ProgramProgressCard: View {
    let programTitle: String
    let progressText: String
    let progressValue: Double
    var isEnabled = true
    let onContinueProgram: () -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Прогресс программы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text(programTitle)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(2)

                Text(progressText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                ProgressView(value: progressValue)
                    .tint(FFColors.accent)

                FFButton(
                    title: "Продолжить программу",
                    variant: isEnabled ? .secondary : .disabled,
                    action: onContinueProgram,
                )
            }
        }
    }
}

struct QuickActionsSection: View {
    let canRepeatLast: Bool
    let onQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatLast: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: FFSpacing.xs),
        GridItem(.flexible(), spacing: FFSpacing.xs),
        GridItem(.flexible(), spacing: FFSpacing.xs),
    ]

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Быстрые действия")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                LazyVGrid(columns: columns, spacing: FFSpacing.xs) {
                    QuickActionCard(
                        title: "Быстрая тренировка",
                        subtitle: "без программы",
                        systemImage: "bolt.fill",
                        isEnabled: true,
                        action: onQuickWorkout,
                    )

                    QuickActionCard(
                        title: "Шаблоны",
                        subtitle: "ваши сохранённые",
                        systemImage: "square.stack.3d.up.fill",
                        isEnabled: true,
                        action: onOpenTemplates,
                    )

                    QuickActionCard(
                        title: "Повторить последнюю",
                        subtitle: "последняя тренировка",
                        systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                        isEnabled: canRepeatLast,
                        action: onRepeatLast,
                    )
                }
            }
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnabled ? FFColors.primary : FFColors.gray500)

                Spacer(minLength: FFSpacing.xxs)

                Text(title)
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(isEnabled ? FFColors.textPrimary : FFColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .padding(FFSpacing.sm)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct RecentWorkoutsSection: View {
    let workouts: [CompletedWorkoutRecord]
    let isLoading: Bool
    let isEmpty: Bool
    let onOpenWorkout: (CompletedWorkoutRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text("Последние тренировки")
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)

            if isLoading, workouts.isEmpty {
                FFLoadingState(title: "Загружаем последние тренировки")
            } else if isEmpty {
                FFEmptyState(
                    title: "Пока нет тренировок",
                    message: "Завершите первую тренировку, и она появится здесь.",
                )
            } else {
                FFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                            Button {
                                onOpenWorkout(workout)
                            } label: {
                                HStack(spacing: FFSpacing.sm) {
                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text(workout.workoutTitle)
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                            .lineLimit(2)

                                        Text(dateFormatter.string(from: workout.finishedAt))
                                            .font(FFTypography.caption)
                                            .foregroundStyle(FFColors.textSecondary)
                                    }
                                    Spacer(minLength: FFSpacing.xs)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                                .padding(.horizontal, FFSpacing.md)
                                .padding(.vertical, FFSpacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < workouts.count - 1 {
                                Divider()
                                    .overlay(FFColors.gray700)
                                    .padding(.leading, FFSpacing.md)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        return formatter
    }
}

typealias TrainingHubViewModel = WorkoutHomeViewModel
typealias TrainingHubView = WorkoutHomeScreen

private extension WorkoutHomeViewModel {
    var continueProgramTargetAvailable: Bool {
        serverInProgressWorkout != nil || startWorkoutTarget != nil
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Экран тренировки") {
    NavigationStack {
        WorkoutHomeScreen(
            viewModel: WorkoutHomeViewModel(userSub: "preview"),
            onContinueSession: { _ in },
            onOpenRemoteWorkout: { _ in },
            onStartQuickWorkout: {},
            onOpenTemplates: {},
            onRepeatWorkout: { _ in },
        )
    }
}
