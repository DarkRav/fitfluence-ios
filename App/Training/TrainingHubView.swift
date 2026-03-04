import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class TrainingHubViewModel {
    struct RemoteWorkoutTarget: Equatable, Identifiable {
        let programId: String
        let workoutId: String
        let title: String

        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    struct TodayScheduleItem: Equatable, Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let status: AthleteWorkoutInstanceStatus
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
    var activeSession: ActiveWorkoutSession?
    var serverInProgressWorkout: RemoteWorkoutTarget?
    var nextWorkout: RemoteWorkoutTarget?
    var nextWorkoutProgressText: String?
    var todaySchedule: [TodayScheduleItem] = []
    var lastCompleted: CompletedWorkoutRecord?
    var syncIndicator: SyncIndicatorState = .savedLocally

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
        defer { isLoading = false }

        await syncCoordinator.activate(namespace: userSub)
        await loadLocalContext()
        await loadCachedRemoteContext()

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            syncIndicator = .savedLocally
            await ensureTodayScheduleFallback()
            return
        }

        async let progressResult = athleteTrainingClient.activeEnrollmentProgress()
        async let calendarResult = athleteTrainingClient.calendar(month: monthKey(for: Date()))
        async let syncResult = athleteTrainingClient.syncStatus()

        await applyActiveEnrollment(await progressResult, cacheTTL: 60 * 5)
        await applyCalendar(await calendarResult, cacheTTL: 60 * 5)
        await applySyncStatus(await syncResult, cacheTTL: 60 * 2)

        await ensureTodayScheduleFallback()
    }

    func startNextWorkout() async -> RemoteWorkoutTarget? {
        guard let nextWorkout else { return nil }
        _ = await syncCoordinator.enqueueStartWorkout(
            namespace: userSub,
            workoutInstanceId: nextWorkout.workoutId,
            startedAt: Date(),
        )
        return nextWorkout
    }

    private func loadLocalContext() async {
        async let active = progressStore.latestActiveSession(userSub: userSub)
        async let history = trainingStore.history(userSub: userSub, source: nil, limit: 180)

        let activeCandidate = await active
        if let activeCandidate, await canLaunch(session: activeCandidate) {
            activeSession = activeCandidate
        } else {
            activeSession = nil
        }

        let allHistory = await history
        lastCompleted = allHistory.first
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
            apply(progress: cachedEnrollment)
        }

        if let cachedCalendar = await cacheStore.get(
            cacheKeys.calendar(month: month),
            as: AthleteCalendarResponse.self,
            namespace: userSub,
        ) {
            isShowingCachedData = true
            apply(calendar: cachedCalendar)
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
            apply(progress: progress)
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
            apply(calendar: calendarResponse)
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

    private func ensureTodayScheduleFallback() async {
        guard todaySchedule.isEmpty else { return }
        let localPlans = await trainingStore.plans(userSub: userSub, month: Date())
        let today = calendar.startOfDay(for: Date())
        let mapped = localPlans
            .filter { calendar.isDate($0.day, inSameDayAs: today) }
            .map { plan in
                TodayScheduleItem(
                    id: "local-\(plan.id)",
                    title: plan.title,
                    subtitle: statusSubtitle(for: plan.status),
                    status: status(for: plan.status),
                )
            }
        todaySchedule = Array(mapped.prefix(1))
    }

    private func apply(progress: ActiveEnrollmentProgressResponse) {
        let programId = progress.programId?.trimmedNilIfEmpty ?? "program"
        let nextWorkoutId = progress.nextWorkoutId?.trimmedNilIfEmpty
        let nextWorkoutTitle = progress.nextWorkoutTitle?.trimmedNilIfEmpty ?? "Следующая тренировка"

        if let currentWorkoutId = progress.currentWorkoutId?.trimmedNilIfEmpty,
           progress.currentWorkoutStatus == .inProgress
        {
            serverInProgressWorkout = RemoteWorkoutTarget(
                programId: programId,
                workoutId: currentWorkoutId,
                title: progress.currentWorkoutTitle?.trimmedNilIfEmpty ?? "Текущая тренировка",
            )
        } else if let nextWorkoutId,
                  progress.nextWorkoutStatus == .inProgress
        {
            serverInProgressWorkout = RemoteWorkoutTarget(
                programId: programId,
                workoutId: nextWorkoutId,
                title: nextWorkoutTitle,
            )
        } else {
            serverInProgressWorkout = nil
        }

        if let nextWorkoutId, serverInProgressWorkout?.workoutId != nextWorkoutId {
            nextWorkout = RemoteWorkoutTarget(
                programId: programId,
                workoutId: nextWorkoutId,
                title: nextWorkoutTitle,
            )
        } else {
            nextWorkout = nil
        }

        if let completed = progress.completedSessions, let total = progress.totalSessions, total > 0 {
            nextWorkoutProgressText = "\(completed)/\(total) сессий"
        } else {
            nextWorkoutProgressText = nil
        }
    }

    private func apply(calendar response: AthleteCalendarResponse) {
        let today = calendar.startOfDay(for: Date())
        let todaysWorkouts = response.workouts
            .filter { workout in
                guard let date = parseDate(workout.scheduledDate ?? workout.startedAt ?? workout.completedAt) else {
                    return false
                }
                return calendar.isDate(date, inSameDayAs: today)
            }
            .sorted { lhs, rhs in
                let left = parseDate(lhs.scheduledDate ?? lhs.startedAt ?? lhs.completedAt) ?? .distantFuture
                let right = parseDate(rhs.scheduledDate ?? rhs.startedAt ?? rhs.completedAt) ?? .distantFuture
                return left < right
            }

        todaySchedule = todaysWorkouts.prefix(1).map { workout in
            let status = workout.status ?? .planned
            let time = parseDate(workout.scheduledDate ?? workout.startedAt)?.formatted(date: .omitted, time: .shortened)
            let subtitle = [statusTitle(status), time].compactMap { $0 }.joined(separator: " • ")

            return TodayScheduleItem(
                id: workout.id,
                title: workout.title?.trimmedNilIfEmpty ?? "Тренировка",
                subtitle: subtitle.isEmpty ? "Без времени" : subtitle,
                status: status,
            )
        }

        guard activeSession == nil, serverInProgressWorkout == nil else { return }
        if let inProgress = response.workouts.first(where: { $0.status == .inProgress }) {
            serverInProgressWorkout = RemoteWorkoutTarget(
                programId: inProgress.programId?.trimmedNilIfEmpty ?? "program",
                workoutId: inProgress.id,
                title: inProgress.title?.trimmedNilIfEmpty ?? "Текущая тренировка",
            )
        }
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

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        if let date = Self.iso8601WithFractions.date(from: value) {
            return date
        }
        if let date = Self.iso8601.date(from: value) {
            return date
        }
        if let dateOnly = Self.dateOnly.date(from: value) {
            return dateOnly
        }
        return nil
    }

    private func statusTitle(_ status: AthleteWorkoutInstanceStatus) -> String {
        switch status {
        case .planned:
            "Запланирована"
        case .inProgress:
            "В процессе"
        case .completed:
            "Завершена"
        case .missed:
            "Пропущена"
        case .abandoned:
            "Прервана"
        }
    }

    private func statusSubtitle(for status: TrainingDayStatus) -> String {
        switch status {
        case .planned:
            "Запланирована"
        case .completed:
            "Завершена"
        case .missed:
            "Пропущена"
        }
    }

    private func status(for status: TrainingDayStatus) -> AthleteWorkoutInstanceStatus {
        switch status {
        case .planned:
            .planned
        case .completed:
            .completed
        case .missed:
            .abandoned
        }
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
        let enrollment = "athlete.enrollment.active"
        let syncStatus = "athlete.sync.status"

        func calendar(month: String) -> String {
            "athlete.calendar.\(month)"
        }
    }
}

struct TrainingHubView: View {
    @State var viewModel: TrainingHubViewModel

    let onContinueSession: (ActiveWorkoutSession) -> Void
    let onOpenRemoteWorkout: (TrainingHubViewModel.RemoteWorkoutTarget) -> Void
    let onStartQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatWorkout: (CompletedWorkoutRecord) -> Void

    private enum PrimaryAction {
        case continueLocal(ActiveWorkoutSession)
        case continueRemote(TrainingHubViewModel.RemoteWorkoutTarget)
        case startNext(TrainingHubViewModel.RemoteWorkoutTarget)
        case startQuickWorkout
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                primaryCTACard
                nextWorkoutCard
                programProgressCard
                quickActionsCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Тренировка")
        .refreshable {
            await viewModel.reload()
        }
        .task {
            ClientAnalytics.track(.workoutHubScreenOpened)
            await viewModel.onAppear()
        }
    }

    private var primaryCTACard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .center, spacing: FFSpacing.sm) {
                    Text(primaryTitle)
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer(minLength: FFSpacing.xs)
                    syncIndicatorPill
                }

                if let subtitle = primarySubtitle {
                    Text(subtitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                        .lineLimit(2)
                }

                FFButton(title: primaryButtonTitle, variant: .primary, action: runPrimaryAction)

                if let continueStartedText {
                    Text(continueStartedText)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var quickActionsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Быстрые действия")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                HStack(spacing: FFSpacing.xs) {
                    compactActionButton(
                        title: "Быстрая тренировка",
                        systemImage: "bolt.fill",
                        isEnabled: true,
                        action: {
                            ClientAnalytics.track(.workoutQuickButtonTapped)
                            onStartQuickWorkout()
                        },
                    )
                    compactActionButton(
                        title: "Шаблоны",
                        systemImage: "square.stack.3d.up.fill",
                        isEnabled: true,
                        action: {
                            ClientAnalytics.track(.workoutTemplatesButtonTapped)
                            onOpenTemplates()
                        },
                    )
                    compactActionButton(
                        title: "Повторить последнюю",
                        systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                        isEnabled: viewModel.lastCompleted != nil,
                        action: {
                            guard let lastCompleted = viewModel.lastCompleted else { return }
                            ClientAnalytics.track(.workoutRepeatLastButtonTapped)
                            onRepeatWorkout(lastCompleted)
                        },
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var nextWorkoutCard: some View {
        if let nextWorkout = viewModel.nextWorkout {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Следующая тренировка")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                    Text(nextWorkout.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                        .lineLimit(1)
                    Text("По активной программе")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var programProgressCard: some View {
        if let progress = viewModel.nextWorkoutProgressText {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Прогресс программы")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                    Text(progress)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                }
            }
        }
    }

    private var primaryAction: PrimaryAction {
        if let activeSession = viewModel.activeSession {
            return .continueLocal(activeSession)
        }
        if let inProgress = viewModel.serverInProgressWorkout {
            return .continueRemote(inProgress)
        }
        if let nextWorkout = viewModel.nextWorkout {
            return .startNext(nextWorkout)
        }
        return .startQuickWorkout
    }

    private var primaryTitle: String {
        switch primaryAction {
        case .continueLocal, .continueRemote:
            return "Продолжить тренировку"
        case .startNext:
            return "Начать следующую тренировку"
        case .startQuickWorkout:
            return "Начать тренировку"
        }
    }

    private var primarySubtitle: String? {
        switch primaryAction {
        case .continueLocal:
            return "Текущая незавершённая тренировка"
        case let .continueRemote(target):
            return target.title
        case let .startNext(target):
            return target.title
        case .startQuickWorkout:
            return "Выберите формат тренировки и начните в один тап."
        }
    }

    private var primaryButtonTitle: String {
        switch primaryAction {
        case .continueLocal, .continueRemote:
            return "Продолжить тренировку"
        case .startNext:
            return "Начать следующую тренировку"
        case .startQuickWorkout:
            return "Начать тренировку"
        }
    }

    private var continueStartedText: String? {
        switch primaryAction {
        case let .continueLocal(activeSession):
            let minutes = max(1, Int(Date().timeIntervalSince(activeSession.lastUpdated) / 60))
            return "Начата \(minutes) мин назад"
        case .continueRemote:
            return "Начата недавно"
        case .startNext, .startQuickWorkout:
            return nil
        }
    }

    private var syncIndicatorPill: some View {
        HStack(spacing: FFSpacing.xxs) {
            Circle()
                .fill(syncTint)
                .frame(width: 8, height: 8)
            Text(syncTitle)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(syncTint)
        }
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.xxs)
        .background(syncTint.opacity(0.14))
        .clipShape(Capsule())
    }

    private var syncTitle: String {
        switch viewModel.syncIndicator {
        case .synced:
            return "Синхронизировано"
        case .savedLocally:
            return "Сохранено на устройстве"
        case .delayed:
            return "Ошибка синхронизации"
        }
    }

    private var syncTint: Color {
        switch viewModel.syncIndicator {
        case .synced:
            return FFColors.accent
        case .savedLocally:
            return FFColors.primary
        case .delayed:
            return FFColors.danger
        }
    }

    private func runPrimaryAction() {
        switch primaryAction {
        case let .continueLocal(activeSession):
            ClientAnalytics.track(
                .workoutContinueButtonTapped,
                properties: ["source": "hub_primary"],
            )
            onContinueSession(activeSession)
        case let .continueRemote(target):
            ClientAnalytics.track(
                .workoutContinueButtonTapped,
                properties: ["source": "hub_primary"],
            )
            onOpenRemoteWorkout(target)
        case .startQuickWorkout:
            ClientAnalytics.track(.workoutStartButtonTapped)
            onStartQuickWorkout()
        case .startNext:
            ClientAnalytics.track(.workoutStartNextButtonTapped)
            Task {
                if let target = await viewModel.startNextWorkout() {
                    onOpenRemoteWorkout(target)
                }
            }
        }
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            VStack(spacing: FFSpacing.xxs) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(FFTypography.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(isEnabled ? FFColors.textPrimary : FFColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.horizontal, FFSpacing.xs)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint("Быстрое действие")
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
        TrainingHubView(
            viewModel: TrainingHubViewModel(userSub: "preview"),
            onContinueSession: { _ in },
            onOpenRemoteWorkout: { _ in },
            onStartQuickWorkout: {},
            onOpenTemplates: {},
            onRepeatWorkout: { _ in },
        )
    }
}
