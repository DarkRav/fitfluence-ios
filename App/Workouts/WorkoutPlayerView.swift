import AVKit
import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

enum SyncStatusKind: String, Codable, Equatable, Sendable {
    case synced
    case savedLocally
    case delayed

    var title: String {
        switch self {
        case .synced:
            "Синхронизировано"
        case .savedLocally:
            "Сохранено на устройстве"
        case .delayed:
            "Ошибка синхронизации"
        }
    }

    var defaultSubtitle: String {
        switch self {
        case .synced:
            "Все изменения на сервере"
        case .savedLocally:
            "Данные сохранены локально"
        case .delayed:
            "Попробуйте повторить синхронизацию"
        }
    }

    var iconName: String {
        switch self {
        case .synced:
            "checkmark.icloud.fill"
        case .savedLocally:
            "externaldrive.fill.badge.timemachine"
        case .delayed:
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }

    var tint: Color {
        switch self {
        case .synced:
            FFColors.accent
        case .savedLocally:
            FFColors.primary
        case .delayed:
            FFColors.danger
        }
    }
}

struct SyncStatusIndicator: View {
    let status: SyncStatusKind
    var subtitle: String? = nil
    var compact = false
    var showsCacheTag = false

    var body: some View {
        if compact {
            HStack(spacing: FFSpacing.xxs) {
                Image(systemName: status.iconName)
                    .font(.system(size: 12, weight: .semibold))
                Text(status.title)
                    .font(FFTypography.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(status.tint)
            .padding(.horizontal, FFSpacing.xs)
            .padding(.vertical, FFSpacing.xxs)
            .background(status.tint.opacity(0.14))
            .clipShape(Capsule())
        } else {
            HStack(spacing: FFSpacing.sm) {
                Image(systemName: status.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(status.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text(status.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(subtitle ?? status.defaultSubtitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }

                Spacer(minLength: FFSpacing.xs)

                if showsCacheTag {
                    Text("кэш")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.primary)
                        .padding(.horizontal, FFSpacing.xs)
                        .padding(.vertical, FFSpacing.xxs)
                        .background(FFColors.primary.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct ExerciseInsightPill: View {
    let title: String
    let value: String
    var systemImage = "sparkles"
    var tint: Color = FFColors.textSecondary
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: FFSpacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.xxs)
        .background(FFColors.surface)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.38), lineWidth: 1)
        }
    }
}

struct HistoryBottomSheet: View {
    let exerciseName: String
    let entries: [AthleteExerciseHistoryEntry]
    let isLoading: Bool
    let errorMessage: String?
    var onRetry: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    FFLoadingState(title: "Загружаем историю")
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.vertical, FFSpacing.md)
                } else if let errorMessage {
                    FFErrorState(
                        title: "История недоступна",
                        message: errorMessage,
                        retryTitle: onRetry == nil ? "Закрыть" : "Повторить",
                        onRetry: { onRetry?() },
                    )
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.md)
                } else if entries.isEmpty {
                    FFEmptyState(title: "Истории пока нет", message: "Появится после выполненных тренировок.")
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.vertical, FFSpacing.md)
                } else {
                    List {
                        if let trend = volumeTrendText {
                            Section("Тренд") {
                                Text(trend)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        Section("Последние 10") {
                            ForEach(entries) { item in
                                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                    Text(entryTitle(item))
                                        .font(FFTypography.body.weight(.semibold))
                                        .foregroundStyle(FFColors.textPrimary)
                                    Text(entrySubtitle(item))
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                                .padding(.vertical, FFSpacing.xxs)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(FFColors.background)
                }
            }
            .navigationTitle(exerciseName)
        }
    }

    private var volumeTrendText: String? {
        guard entries.count >= 2,
              let latest = entries.first?.volume,
              let earliest = entries.last?.volume
        else {
            return nil
        }

        let delta = latest - earliest
        if abs(delta) < 0.1 {
            return "Объём стабилен"
        }
        return delta > 0 ? "Объём растёт: +\(Int(delta)) кг" : "Объём снизился: \(Int(delta)) кг"
    }

    private func entryTitle(_ entry: AthleteExerciseHistoryEntry) -> String {
        let reps = entry.reps.map { "\($0) повторов" } ?? "— повторов"
        let weight = entry.weight.map { "@ \(formatWeight($0)) кг" } ?? "@ — кг"
        return "\(reps) \(weight)"
    }

    private func entrySubtitle(_ entry: AthleteExerciseHistoryEntry) -> String {
        let dateText: String
        if let performedAt = parseDate(entry.performedAt) {
            dateText = performedAt.formatted(date: .abbreviated, time: .omitted)
        } else {
            dateText = "Дата неизвестна"
        }

        let volumeText = entry.volume.map { " • объём \(Int($0)) кг" } ?? ""
        return "\(dateText)\(volumeText)"
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let withFraction = Self.iso8601WithFractions.date(from: value) {
            return withFraction
        }
        return Self.iso8601.date(from: value)
    }

    private func formatWeight(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
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
}

@Observable
final class RestTimerModel {
    static let shared = RestTimerModel(notificationsEnabled: true)

    private static let notificationIdentifier = "fitfluence.rest.timer"

    private var task: Task<Void, Never>?
    private var completionMessageTask: Task<Void, Never>?
    private var initialSeconds = 0
    private var finishDate: Date?
    private var pausedSeconds: Int?
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationsEnabled: Bool

    var isVisible = false
    var isRunning = false
    var remainingSeconds = 0
    var onCompleted: (() -> Void)?
    var workoutId: String?
    var workoutTitle: String?
    var exerciseName: String?
    var completionMessage: String?
    var timerSoundEnabled = ProfileSettings.default.timerSoundEnabled

    init(notificationsEnabled: Bool = false) {
        self.notificationsEnabled = notificationsEnabled
    }

    deinit {
        task?.cancel()
        completionMessageTask?.cancel()
    }

    func start(seconds: Int) {
        start(seconds: seconds, updateInitial: true)
    }

    func setContext(
        workoutId: String,
        workoutTitle: String,
        exerciseName: String?,
        timerSoundEnabled: Bool,
    ) {
        self.workoutId = workoutId
        self.workoutTitle = workoutTitle
        self.exerciseName = exerciseName
        self.timerSoundEnabled = timerSoundEnabled
        if isVisible, isRunning {
            scheduleCompletionNotification()
        }
    }

    func pauseOrResume() {
        if isRunning {
            pausedSeconds = max(0, remainingSeconds)
            isRunning = false
            finishDate = nil
            task?.cancel()
            task = nil
            cancelCompletionNotification()
        } else {
            let resumeValue = pausedSeconds ?? remainingSeconds
            guard resumeValue > 0 else { return }
            start(seconds: resumeValue, updateInitial: false)
        }
    }

    func add(seconds: Int) {
        guard seconds > 0 else { return }
        if !isVisible {
            start(seconds: seconds, updateInitial: true)
            return
        }

        if isRunning {
            let base = finishDate ?? Date().addingTimeInterval(Double(remainingSeconds))
            finishDate = base.addingTimeInterval(Double(seconds))
            recalculateRemaining()
            scheduleCompletionNotification()
        } else {
            let next = max(0, (pausedSeconds ?? remainingSeconds) + seconds)
            pausedSeconds = next
            remainingSeconds = next
            isVisible = true
        }
    }

    func reset() {
        guard initialSeconds > 0 else {
            skip()
            return
        }
        start(seconds: initialSeconds, updateInitial: false)
    }

    func skip() {
        task?.cancel()
        task = nil
        finishDate = nil
        pausedSeconds = nil
        isVisible = false
        isRunning = false
        remainingSeconds = 0
        completionMessageTask?.cancel()
        cancelCompletionNotification()
    }

    func clearIfMatches(workoutId: String) {
        guard self.workoutId == workoutId else { return }
        skip()
        self.workoutId = nil
        workoutTitle = nil
        exerciseName = nil
        completionMessage = nil
    }

    func dismissCompletionMessage() {
        completionMessageTask?.cancel()
        completionMessage = nil
    }

    func handleWillEnterForeground() {
        guard isVisible, isRunning else { return }
        recalculateRemaining()
        if remainingSeconds > 0 {
            scheduleTicker()
            scheduleCompletionNotification()
        }
    }

    private func start(seconds: Int, updateInitial: Bool) {
        guard seconds > 0 else { return }
        task?.cancel()
        if updateInitial {
            initialSeconds = seconds
        }
        pausedSeconds = nil
        finishDate = Date().addingTimeInterval(Double(seconds))
        remainingSeconds = seconds
        isVisible = true
        isRunning = true
        completionMessageTask?.cancel()
        completionMessage = nil
        scheduleTicker()
        scheduleCompletionNotification()
    }

    private func scheduleTicker() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.remainingSeconds > 0, self.isRunning, self.isVisible {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || !self.isRunning || !self.isVisible { break }
                self.recalculateRemaining()
            }
        }
    }

    private func recalculateRemaining() {
        guard isRunning else { return }
        guard let finishDate else { return }
        let seconds = max(0, Int(ceil(finishDate.timeIntervalSinceNow)))
        remainingSeconds = seconds
        if seconds == 0 {
            complete()
        }
    }

    private func complete() {
        task?.cancel()
        task = nil
        finishDate = nil
        pausedSeconds = nil
        isVisible = false
        isRunning = false
        remainingSeconds = 0
        cancelCompletionNotification()
        if let exerciseName, !exerciseName.isEmpty {
            completionMessage = "Отдых завершён: \(exerciseName)"
        } else {
            completionMessage = "Отдых завершён. Можно возвращаться к подходу."
        }
        completionMessageTask?.cancel()
        completionMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run {
                self?.completionMessage = nil
            }
        }
        onCompleted?()
    }

    private func scheduleCompletionNotification() {
        guard notificationsEnabled else { return }
        guard isVisible, isRunning, remainingSeconds > 0 else {
            cancelCompletionNotification()
            return
        }

        Task {
            let settings = await notificationCenter.notificationSettings()
            let isAuthorized = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                true
            case .notDetermined:
                (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
            case .denied:
                false
            @unknown default:
                false
            }

            guard isAuthorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Отдых завершён"
            if let exerciseName, !exerciseName.isEmpty {
                content.body = "Пора вернуться к упражнению: \(exerciseName)"
            } else if let workoutTitle, !workoutTitle.isEmpty {
                content.body = "Пора вернуться к тренировке: \(workoutTitle)"
            } else {
                content.body = "Можно начинать следующий подход."
            }
            if timerSoundEnabled {
                content.sound = .default
            }

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, Double(remainingSeconds)),
                repeats: false,
            )
            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: trigger,
            )

            notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
            try? await notificationCenter.add(request)
        }
    }

    private func cancelCompletionNotification() {
        guard notificationsEnabled else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
}

struct WorkoutExecutionContext: Codable, Equatable, Sendable {
    let workoutInstanceId: String
    let exerciseExecutionIDsByExerciseID: [String: String]
}

struct AutoAdvanceUndoState: Equatable, Sendable, Identifiable {
    let id: String
    let message: String
    let includesExerciseMove: Bool
}

@Observable
@MainActor
final class WorkoutPlayerViewModel {
    struct ExerciseProgressItem: Equatable, Identifiable {
        let id: String
        let title: String
        let completedSets: Int
        let totalSets: Int
        let isCurrent: Bool
        let isSkipped: Bool
    }

    struct CompletionSummary: Equatable, Sendable {
        let workoutTitle: String
        let completedExercises: Int
        let totalExercises: Int
        let completedSets: Int
        let totalSets: Int
        let durationSeconds: Int
        let totalReps: Int
        let volume: Double
    }

    private(set) var session: WorkoutSessionState?
    private let sessionManager: WorkoutSessionManager
    private let workout: WorkoutDetailsModel
    private let userSub: String
    private let programId: String
    private let source: WorkoutSource
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let executionContext: WorkoutExecutionContext?
    private let syncCoordinator: SyncCoordinator
    private let profileSettingsStore: ProfileSettingsStore
    let restTimer: RestTimerModel

    private var autoAdvanceUndoTask: Task<Void, Never>?
    private var networkObserverTask: Task<Void, Never>?

    private var lastPerformanceByExerciseId: [String: AthleteExerciseLastPerformanceResponse] = [:]
    private var personalRecordByExerciseId: [String: AthletePersonalRecord] = [:]
    private var insightsLoadedExerciseIDs: Set<String> = []
    private var startedExerciseEvents: Set<String> = []
    private var weightStep: Double = ProfileSettings.default.weightStep
    private var defaultRestSeconds: Int = ProfileSettings.default.defaultRestSeconds
    private var timerSoundEnabledValue = ProfileSettings.default.timerSoundEnabled

    var isLoading = false
    var isFinishEarlyConfirmationPresented = false
    var isFinishConfirmationPresented = false
    var isSubmittingFinish = false
    var isFinished = false
    var toastMessage: String?
    var completionSummary: CompletionSummary?
    var syncStatus: SyncStatusKind = .savedLocally
    var pendingSyncCount = 0

    var isHistoryPresented = false
    var isHistoryLoading = false
    var historyErrorMessage: String?
    var historyEntries: [AthleteExerciseHistoryEntry] = []

    var autoAdvanceUndoState: AutoAdvanceUndoState?
    var isJumpNavigationActive = false
    var focusedSetIndex: Int?

    init(
        userSub: String,
        programId: String,
        workout: WorkoutDetailsModel,
        source: WorkoutSource = .program,
        sessionManager: WorkoutSessionManager = WorkoutSessionManager(),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        executionContext: WorkoutExecutionContext? = nil,
        syncCoordinator: SyncCoordinator = .shared,
        profileSettingsStore: ProfileSettingsStore = LocalProfileSettingsStore(),
        restTimer: RestTimerModel = RestTimerModel(),
    ) {
        self.userSub = userSub
        self.programId = programId
        self.workout = workout
        self.source = source
        self.sessionManager = sessionManager
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.executionContext = executionContext
        self.syncCoordinator = syncCoordinator
        self.profileSettingsStore = profileSettingsStore
        self.restTimer = restTimer

        restTimer.onCompleted = { [weak self] in
            self?.toastMessage = "Отдых завершён. Можно начинать следующий подход."
        }
    }

    @MainActor
    deinit {
        autoAdvanceUndoTask?.cancel()
        networkObserverTask?.cancel()
    }

    var title: String {
        workout.title
    }

    var currentExerciseIndex: Int {
        session?.currentExerciseIndex ?? 0
    }

    var currentExercise: WorkoutExercise? {
        guard workout.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return workout.exercises[currentExerciseIndex]
    }

    var currentExerciseState: SessionExerciseState? {
        guard let exercise = currentExercise else { return nil }
        return session?.exercises.first(where: { $0.exerciseId == exercise.id })
    }

    var progressLabel: String {
        let current = min(workout.exercises.count, currentExerciseIndex + 1)
        return "Упражнение \(max(1, current)) из \(max(1, workout.exercises.count))"
    }

    var isLastExercise: Bool {
        workout.exercises.isEmpty || currentExerciseIndex >= workout.exercises.count - 1
    }

    var primaryBottomTitle: String {
        isLastExercise ? "Завершить тренировку" : "Следующее упражнение"
    }

    var isPrimaryBottomActionEnabled: Bool {
        !isSubmittingFinish && !isFinished
    }

    var progressItems: [ExerciseProgressItem] {
        workout.exercises.map { exercise in
            let state = session?.exercises.first(where: { $0.exerciseId == exercise.id })
            let completed = state?.sets.filter(\.isCompleted).count ?? 0
            let total = state?.sets.count ?? max(1, exercise.sets)
            return ExerciseProgressItem(
                id: exercise.id,
                title: exercise.name,
                completedSets: completed,
                totalSets: total,
                isCurrent: exercise.id == currentExercise?.id,
                isSkipped: state?.isSkipped ?? false,
            )
        }
    }

    var currentLastTimeText: String? {
        guard let exerciseId = currentExercise?.id,
              let lastPerformance = lastPerformanceByExerciseId[exerciseId]
        else {
            return nil
        }
        return compactLastTimeLine(from: lastPerformance)
    }

    var currentLastSets: [String] {
        guard let exerciseId = currentExercise?.id,
              let lastPerformance = lastPerformanceByExerciseId[exerciseId]
        else {
            return []
        }
        return lastPerformanceLines(from: lastPerformance)
    }

    var currentPRText: String? {
        guard let exerciseId = currentExercise?.id,
              let record = personalRecordByExerciseId[exerciseId]
        else {
            return nil
        }
        return compactPRLine(from: record)
    }

    var canUseLastPerformance: Bool {
        guard let exerciseId = currentExercise?.id else { return false }
        return !(lastPerformanceByExerciseId[exerciseId]?.sets ?? []).isEmpty
    }

    var canRetrySync: Bool {
        syncStatus == .delayed
    }

    var quickActionSetIndex: Int? {
        guard let exerciseState = currentExerciseState else { return nil }
        if let focusedSetIndex, exerciseState.sets.indices.contains(focusedSetIndex) {
            return focusedSetIndex
        }
        if let next = firstUncompletedSetIndex(in: exerciseState) {
            return next
        }
        return exerciseState.sets.indices.last
    }

    var canUseQuickCopyAction: Bool {
        guard let quickActionSetIndex else { return false }
        return canCopyPreviousSet(setIndex: quickActionSetIndex)
    }

    var canSkipCurrentExercise: Bool {
        workout.exercises.count > 1
    }

    var quickActionSetTitle: String {
        guard let quickActionSetIndex, quickActionSetIndex > 0 else {
            return "Из предыдущего подхода"
        }
        return "Из подхода \(quickActionSetIndex)"
    }

    var weightStepLabel: String {
        formatStep(weightStep, suffix: "кг")
    }

    var currentExerciseIsBodyweight: Bool {
        currentExercise?.isBodyweight == true
    }

    func onAppear() async {
        isLoading = true
        let settings = await profileSettingsStore.load(userSub: userSub)
        weightStep = max(0.5, settings.weightStep)
        defaultRestSeconds = max(15, settings.defaultRestSeconds)
        timerSoundEnabledValue = settings.timerSoundEnabled
        session = await sessionManager.loadOrCreateSession(
            userSub: userSub,
            programId: programId,
            workout: workout,
            source: source,
        )
        isLoading = false
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0

        await syncCoordinator.activate(namespace: userSub)
        await ensureCurrentExerciseContext()
        await flushPendingSetSyncOperations()
        await refreshSyncStatusIndicator()
        startNetworkObserverIfNeeded()
    }

    func flushPendingSyncNow() async {
        await flushPendingSetSyncOperations()
        await refreshSyncStatusIndicator()
    }

    func setJumpNavigationActive(_ active: Bool) {
        isJumpNavigationActive = active
    }

    func toggleSetComplete(setIndex: Int) async {
        guard let currentExercise, let session else { return }
        let wasCompleted = currentExerciseState?.sets[safe: setIndex]?.isCompleted ?? false

        self.session = await sessionManager.toggleSetComplete(
            session,
            exerciseId: currentExercise.id,
            setIndex: setIndex,
        )

        await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: setIndex)

        let isNowCompleted = currentExerciseState?.sets[safe: setIndex]?.isCompleted ?? false
        if !wasCompleted, isNowCompleted {
            let rest = currentExercise.restSeconds ?? defaultRestSeconds
            restTimer.start(seconds: max(15, rest))
            ClientAnalytics.track(
                .setCompleted,
                properties: analyticsExerciseProperties(exerciseId: currentExercise.id),
            )
            await handleAutoAdvanceIfNeeded(exerciseId: currentExercise.id, completedSetIndex: setIndex)
        } else if wasCompleted, !isNowCompleted {
            focusedSetIndex = setIndex
        }
    }

    func incrementWeight(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: weightStep)
    }

    func decrementWeight(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: -weightStep)
    }

    func incrementReps(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.repsText, step: 1)
    }

    func decrementReps(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.repsText, step: -1)
    }

    func nextExercise() async {
        guard let session else { return }
        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex + 1)
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        await ensureCurrentExerciseContext()
    }

    func prevExercise() async {
        guard let session else { return }
        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex - 1)
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        await ensureCurrentExerciseContext()
    }

    func skipExercise() async {
        guard let currentExercise, let session else { return }
        let skippedExerciseID = currentExercise.id
        let shouldAdvance = !isLastExercise
        var updatedSession = await sessionManager.skipExercise(session, exerciseId: skippedExerciseID)
        if shouldAdvance {
            updatedSession = await sessionManager.moveExercise(updatedSession, to: currentExerciseIndex + 1)
        }
        self.session = updatedSession
        toastMessage = shouldAdvance ? "Упражнение пропущено, открыто следующее" : "Упражнение пропущено"
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        await ensureCurrentExerciseContext()
        ClientAnalytics.track(
            .exerciseSkipped,
            properties: analyticsExerciseProperties(exerciseId: skippedExerciseID),
        )
    }

    func undoLastChange() async {
        guard let session else { return }
        self.session = await sessionManager.undo(session)
        autoAdvanceUndoTask?.cancel()
        autoAdvanceUndoTask = nil
        autoAdvanceUndoState = nil
        toastMessage = "Последнее действие отменено"
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? focusedSetIndex
        await ensureCurrentExerciseContext()
    }

    func undoAutoAdvance() async {
        guard let state = autoAdvanceUndoState else {
            await undoLastChange()
            return
        }

        guard let session else { return }
        var updated = await sessionManager.undo(session)
        if state.includesExerciseMove {
            updated = await sessionManager.undo(updated)
        }

        self.session = updated
        autoAdvanceUndoTask?.cancel()
        autoAdvanceUndoTask = nil
        autoAdvanceUndoState = nil
        toastMessage = "Изменение отменено"
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? focusedSetIndex
        await ensureCurrentExerciseContext()
    }

    func jumpToExercise(_ exerciseID: String) async {
        guard let targetIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let session
        else {
            return
        }
        self.session = await sessionManager.moveExercise(session, to: targetIndex)
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        await ensureCurrentExerciseContext()
    }

    func copyPreviousSet(setIndex: Int) async {
        guard let currentExercise,
              let session,
              let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return
        }

        if setIndex > 0, exerciseState.sets.indices.contains(setIndex - 1) {
            let previous = exerciseState.sets[setIndex - 1]
            let defaults = Array(
                repeating: SessionSetDefaults(repsText: nil, weightText: nil, rpeText: nil),
                count: setIndex + 1,
            )
            var mutableDefaults = defaults
            mutableDefaults[setIndex] = SessionSetDefaults(
                repsText: previous.repsText,
                weightText: previous.weightText,
                rpeText: previous.rpeText,
            )
            self.session = await sessionManager.applySetDefaults(
                session,
                exerciseId: currentExercise.id,
                defaults: mutableDefaults,
                overwriteExisting: true,
            )
            toastMessage = "Скопированы значения из прошлого подхода"
            focusedSetIndex = setIndex
            await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: setIndex)
            return
        }

        if let set = resolveLastPerformanceSet(for: currentExercise.id, setIndex: 0) {
            let defaults = [
                SessionSetDefaults(
                    repsText: set.reps.map(String.init),
                    weightText: set.weight.map(formatDouble),
                    rpeText: set.rpe.map(String.init),
                ),
            ]
            self.session = await sessionManager.applySetDefaults(
                session,
                exerciseId: currentExercise.id,
                defaults: defaults,
                overwriteExisting: true,
            )
            toastMessage = "Первый подход заполнен из прошлого выполнения"
            focusedSetIndex = 0
            await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: 0)
        }
    }

    func useLastPerformance() async {
        guard let currentExercise,
              let session,
              let last = lastPerformanceByExerciseId[currentExercise.id],
              !last.sets.isEmpty
        else {
            return
        }

        let defaults = (0 ..< max(1, currentExercise.sets)).map { setIndex in
            let sourceSet = resolveLastPerformanceSet(for: currentExercise.id, setIndex: setIndex)
            return SessionSetDefaults(
                repsText: sourceSet?.reps.map(String.init),
                weightText: sourceSet?.weight.map(formatDouble),
                rpeText: sourceSet?.rpe.map(String.init),
            )
        }

        self.session = await sessionManager.applySetDefaults(
            session,
            exerciseId: currentExercise.id,
            defaults: defaults,
            overwriteExisting: true,
        )

        for index in defaults.indices {
            await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: index)
        }

        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        toastMessage = "Подходы заполнены из прошлого выполнения"
    }

    func openHistory() {
        isHistoryPresented = true
        Task { await loadHistoryForCurrentExercise(forceRemote: false) }
    }

    func retryHistory() {
        Task { await loadHistoryForCurrentExercise(forceRemote: true) }
    }

    func addRest(seconds: Int) {
        restTimer.add(seconds: seconds)
    }

    func resetRestTimer() {
        restTimer.reset()
    }

    func onAppWillEnterForeground() async {
        restTimer.handleWillEnterForeground()
        await flushPendingSyncNow()
    }

    func copyPreviousSetQuickAction() async {
        guard let setIndex = quickActionSetIndex else { return }
        await copyPreviousSet(setIndex: setIndex)
    }

    func canCopyPreviousSet(setIndex: Int) -> Bool {
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex),
              setIndex > 0
        else {
            return false
        }
        return !exerciseState.sets[setIndex].isCompleted
    }

    func primaryBottomAction() async {
        if isLastExercise {
            isFinishConfirmationPresented = true
        } else {
            await nextExercise()
        }
    }

    func confirmFinish() async {
        guard !isSubmittingFinish, !isFinished else { return }
        isSubmittingFinish = true
        defer { isSubmittingFinish = false }
        await finish()
    }

    func finish() async {
        guard !isFinished else { return }
        guard let session else { return }
        let completedExercises = session.exercises.count(where: { exercise in
            !exercise.isSkipped && exercise.sets.contains(where: \.isCompleted)
        })
        let completedSets = session.exercises.flatMap(\.sets).filter(\.isCompleted)
        let totalReps = completedSets.reduce(0) { partial, set in
            let repsValue = Int(Double(set.repsText) ?? 0)
            return partial + max(0, repsValue)
        }
        let volume = completedSets.reduce(0.0) { partial, set in
            let reps = Double(set.repsText) ?? 0
            let weight = Double(set.weightText) ?? 0
            return partial + reps * weight
        }
        let finishedAt = Date()
        completionSummary = CompletionSummary(
            workoutTitle: workout.title,
            completedExercises: completedExercises,
            totalExercises: workout.exercises.count,
            completedSets: session.completedSetsCount,
            totalSets: session.totalSetsCount,
            durationSeconds: max(0, Int(finishedAt.timeIntervalSince(session.startedAt))),
            totalReps: totalReps,
            volume: volume,
        )
        await sessionManager.finish(session)
        restTimer.clearIfMatches(workoutId: workout.id)
        isFinishConfirmationPresented = false
        isFinishEarlyConfirmationPresented = false
        isFinished = true
        NotificationCenter.default.post(
            name: .fitfluenceWorkoutDidComplete,
            object: nil,
            userInfo: [
                "programId": programId,
                "workoutId": workout.id,
            ],
        )
        ClientAnalytics.track(
            .workoutFinished,
            properties: [
                "workout_id": workout.id,
                "program_id": programId,
            ],
        )
    }

    private func ensureCurrentExerciseContext() async {
        guard let exercise = currentExercise else { return }
        restTimer.setContext(
            workoutId: workout.id,
            workoutTitle: workout.title,
            exerciseName: exercise.name,
            timerSoundEnabled: timerSoundEnabled,
        )
        await ensureInsightsLoaded(for: exercise.id)
        await applySmartDefaultsIfNeeded(for: exercise)
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        trackExerciseStartedIfNeeded(exerciseId: exercise.id)
    }

    private func ensureInsightsLoaded(for exerciseId: String) async {
        if insightsLoadedExerciseIDs.contains(exerciseId) {
            return
        }

        var shouldMarkAsLoaded = false

        if let cachedLast = await cacheStore.get(
            cacheKeys.lastPerformance(exerciseId: exerciseId),
            as: AthleteExerciseLastPerformanceResponse.self,
            namespace: userSub,
        ) {
            lastPerformanceByExerciseId[exerciseId] = cachedLast
            shouldMarkAsLoaded = true
        }

        if let cachedPR = await cacheStore.get(
            cacheKeys.personalRecord(exerciseId: exerciseId),
            as: AthletePersonalRecord.self,
            namespace: userSub,
        ) {
            personalRecordByExerciseId[exerciseId] = cachedPR
            shouldMarkAsLoaded = true
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            if shouldMarkAsLoaded {
                insightsLoadedExerciseIDs.insert(exerciseId)
            }
            return
        }

        shouldMarkAsLoaded = true

        if lastPerformanceByExerciseId[exerciseId] == nil {
            let lastResult = await athleteTrainingClient.lastPerformance(exerciseId: exerciseId)
            if case let .success(last) = lastResult {
                lastPerformanceByExerciseId[exerciseId] = last
                await cacheStore.set(
                    cacheKeys.lastPerformance(exerciseId: exerciseId),
                    value: last,
                    namespace: userSub,
                    ttl: 60 * 10,
                )
            }
        }

        if personalRecordByExerciseId[exerciseId] == nil {
            var bestRecord: AthletePersonalRecord?
            let scopedResult = await athleteTrainingClient.personalRecords(exerciseId: exerciseId)
            if case let .success(records) = scopedResult {
                bestRecord = bestPRRecord(for: exerciseId, records: records.records)
            } else {
                let allResult = await athleteTrainingClient.personalRecords(exerciseId: nil)
                if case let .success(records) = allResult {
                    bestRecord = bestPRRecord(for: exerciseId, records: records.records)
                }
            }

            if let bestRecord {
                personalRecordByExerciseId[exerciseId] = bestRecord
                await cacheStore.set(
                    cacheKeys.personalRecord(exerciseId: exerciseId),
                    value: bestRecord,
                    namespace: userSub,
                    ttl: 60 * 30,
                )
            }
        }

        if shouldMarkAsLoaded {
            insightsLoadedExerciseIDs.insert(exerciseId)
        }
    }

    private func applySmartDefaultsIfNeeded(for exercise: WorkoutExercise) async {
        guard let session,
              let exerciseState = session.exercises.first(where: { $0.exerciseId == exercise.id })
        else {
            return
        }

        let hasUserInput = exerciseState.sets.contains { set in
            set.isCompleted ||
                !set.repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !set.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !set.rpeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !hasUserInput else { return }

        let defaults = (0 ..< max(1, exercise.sets)).map { setIndex in
            if let sourceSet = resolveLastPerformanceSet(for: exercise.id, setIndex: setIndex) {
                return SessionSetDefaults(
                    repsText: sourceSet.reps.map(String.init),
                    weightText: sourceSet.weight.map(formatDouble),
                    rpeText: sourceSet.rpe.map(String.init),
                )
            }

            let plannedReps = exercise.repsMin ?? exercise.repsMax
            return SessionSetDefaults(
                repsText: plannedReps.map(String.init),
                weightText: nil,
                rpeText: exercise.targetRpe.map(String.init),
            )
        }

        self.session = await sessionManager.applySetDefaults(
            session,
            exerciseId: exercise.id,
            defaults: defaults,
            overwriteExisting: false,
        )
    }

    private func updateNumericField(
        setIndex: Int,
        keyPath: WritableKeyPath<SessionSetState, String>,
        step: Double,
    ) async {
        guard let currentExercise,
              let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return
        }

        let currentValue = Double(exerciseState.sets[setIndex][keyPath: keyPath]) ?? 0
        let next = max(0, currentValue + step)
        let nextString = if abs(step).truncatingRemainder(dividingBy: 1) > 0 {
            String(format: "%.1f", next)
        } else {
            String(Int(next))
        }

        guard let session else { return }
        if keyPath == \.weightText {
            self.session = await sessionManager.updateSetWeight(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                weight: nextString,
            )
        } else {
            self.session = await sessionManager.updateSetReps(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                reps: nextString,
            )
        }
        focusedSetIndex = setIndex

        if keyPath == \.weightText {
            ClientAnalytics.track(
                .weightChanged,
                properties: analyticsExerciseProperties(exerciseId: currentExercise.id),
            )
        } else {
            ClientAnalytics.track(
                .repsChanged,
                properties: analyticsExerciseProperties(exerciseId: currentExercise.id),
            )
        }

        await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: setIndex)
    }

    private func handleAutoAdvanceIfNeeded(exerciseId: String, completedSetIndex: Int) async {
        guard !isJumpNavigationActive else {
            if let exerciseState = session?.exercises.first(where: { $0.exerciseId == exerciseId }) {
                focusedSetIndex = firstUncompletedSetIndex(in: exerciseState)
            }
            presentAutoAdvanceUndo(message: "Подход отмечен выполненным", includesExerciseMove: false)
            return
        }

        guard let session,
              let exerciseState = session.exercises.first(where: { $0.exerciseId == exerciseId })
        else {
            return
        }

        let isLastSet = completedSetIndex >= exerciseState.sets.count - 1
        if !isLastSet {
            focusedSetIndex = firstUncompletedSetIndex(in: exerciseState)
            presentAutoAdvanceUndo(
                message: "Подход выполнен",
                includesExerciseMove: false,
            )
            return
        }

        if isLastExercise {
            focusedSetIndex = firstUncompletedSetIndex(in: exerciseState)
            presentAutoAdvanceUndo(message: "Упражнение завершено", includesExerciseMove: false)
            return
        }

        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex + 1)
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        await ensureCurrentExerciseContext()
        presentAutoAdvanceUndo(message: "Упражнение завершено", includesExerciseMove: true)
    }

    private func presentAutoAdvanceUndo(message: String, includesExerciseMove: Bool) {
        autoAdvanceUndoTask?.cancel()
        autoAdvanceUndoState = AutoAdvanceUndoState(
            id: UUID().uuidString,
            message: message,
            includesExerciseMove: includesExerciseMove,
        )

        autoAdvanceUndoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard let self else { return }
            if !Task.isCancelled {
                self.autoAdvanceUndoState = nil
            }
        }
    }

    private func syncCurrentSetIfNeeded(exerciseId: String, setIndex: Int) async {
        guard let executionContext,
              let exerciseExecutionId = executionContext.exerciseExecutionIDsByExerciseID[exerciseId],
              let set = currentSetState(exerciseId: exerciseId, setIndex: setIndex)
        else {
            return
        }

        _ = await syncCoordinator.enqueueUpsertSet(
            namespace: userSub,
            workoutInstanceId: executionContext.workoutInstanceId,
            exerciseExecutionId: exerciseExecutionId,
            setNumber: setIndex + 1,
            weight: parseDouble(set.weightText),
            reps: parseInt(set.repsText),
            rpe: parseInt(set.rpeText),
            isCompleted: set.isCompleted,
        )
        await refreshSyncStatusIndicator()
    }

    private func flushPendingSetSyncOperations() async {
        await syncCoordinator.retryNow(namespace: userSub)
        await refreshSyncStatusIndicator()
    }

    private func refreshSyncStatusIndicator() async {
        let diagnostics = await syncCoordinator.diagnostics(namespace: userSub)
        pendingSyncCount = diagnostics.pendingCount

        if diagnostics.pendingCount > 0 {
            syncStatus = diagnostics.hasDelayedRetries ? .delayed : .savedLocally
            return
        }

        syncStatus = await syncCoordinator.resolveSyncIndicator(namespace: userSub)
    }

    private func loadHistoryForCurrentExercise(forceRemote: Bool) async {
        guard let exercise = currentExercise else { return }

        historyErrorMessage = nil
        if !forceRemote,
           let cached = await cacheStore.get(
               cacheKeys.history(exerciseId: exercise.id),
               as: [AthleteExerciseHistoryEntry].self,
               namespace: userSub,
           )
        {
            historyEntries = cached
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            if historyEntries.isEmpty {
                historyErrorMessage = "Нет сети. Показать историю можно после синхронизации."
            }
            return
        }

        isHistoryLoading = true
        defer { isHistoryLoading = false }

        let result = await athleteTrainingClient.exerciseHistory(exerciseId: exercise.id, page: 0, size: 10)
        switch result {
        case let .success(history):
            let top = Array(history.entries.prefix(10))
            historyEntries = top
            await cacheStore.set(
                cacheKeys.history(exerciseId: exercise.id),
                value: top,
                namespace: userSub,
                ttl: 60 * 10,
            )
        case let .failure(error):
            if historyEntries.isEmpty {
                historyErrorMessage = error.userFacing(context: .workoutPlayer).message
            }
        }
    }

    private func bestPRRecord(for exerciseId: String, records: [AthletePersonalRecord]) -> AthletePersonalRecord? {
        let filtered = records.filter { $0.exerciseId == exerciseId }
        guard !filtered.isEmpty else { return nil }
        return filtered.max(by: { ($0.value ?? 0) < ($1.value ?? 0) })
    }

    private func resolveLastPerformanceSet(for exerciseId: String, setIndex: Int) -> AthleteExerciseLastPerformanceSet? {
        guard let sets = lastPerformanceByExerciseId[exerciseId]?.sets,
              !sets.isEmpty
        else {
            return nil
        }

        if let exact = sets.first(where: { $0.setNumber == setIndex + 1 }) {
            return exact
        }
        if sets.indices.contains(setIndex) {
            return sets[setIndex]
        }
        return sets.last
    }

    private func compactLastTimeLine(from response: AthleteExerciseLastPerformanceResponse) -> String? {
        guard !response.sets.isEmpty else { return nil }
        let sorted = response.sets.sorted(by: { $0.setNumber < $1.setNumber })
        let repsValues = sorted.compactMap(\.reps)
        let weightValues = sorted.compactMap(\.weight)

        if let reps = repsValues.first,
           repsValues.allSatisfy({ $0 == reps }),
           let weight = weightValues.first,
           weightValues.allSatisfy({ abs($0 - weight) < 0.01 })
        {
            return "\(sorted.count)×\(reps) @ \(formatDouble(weight)) кг"
        }

        if let first = sorted.first {
            let reps = first.reps.map(String.init) ?? "—"
            let weight = first.weight.map(formatDouble) ?? "—"
            return "\(sorted.count) подходов • \(reps) повторов @ \(weight) кг"
        }

        return nil
    }

    private func lastPerformanceLines(from response: AthleteExerciseLastPerformanceResponse) -> [String] {
        let sorted = response.sets.sorted(by: { $0.setNumber < $1.setNumber })
        return sorted.compactMap { set in
            guard let reps = set.reps,
                  let weight = set.weight
            else {
                return nil
            }
            return "\(formatDouble(weight)) × \(reps)"
        }
    }

    private func compactPRLine(from record: AthletePersonalRecord) -> String {
        let metric = record.metric?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let valueText = record.value.map(formatDouble) ?? "—"
        let unit = record.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if metric.contains("E1RM") {
            return "1ПМ: \(valueText)\(unit.isEmpty ? "" : " \(unit)")"
        }
        return "\(valueText)\(unit.isEmpty ? "" : " \(unit)")"
    }

    private func currentSetState(exerciseId: String, setIndex: Int) -> SessionSetState? {
        guard let exerciseState = session?.exercises.first(where: { $0.exerciseId == exerciseId }),
              exerciseState.sets.indices.contains(setIndex)
        else {
            return nil
        }
        return exerciseState.sets[setIndex]
    }

    private func firstUncompletedSetIndex(in exerciseState: SessionExerciseState?) -> Int? {
        exerciseState?.sets.firstIndex(where: { !$0.isCompleted })
    }

    private func trackExerciseStartedIfNeeded(exerciseId: String) {
        guard !startedExerciseEvents.contains(exerciseId) else { return }
        startedExerciseEvents.insert(exerciseId)
        ClientAnalytics.track(
            .exerciseStarted,
            properties: analyticsExerciseProperties(exerciseId: exerciseId),
        )
    }

    private func analyticsExerciseProperties(exerciseId: String) -> [String: String] {
        [
            "exercise_id": exerciseId,
            "workout_id": workout.id,
            "program_id": programId,
        ]
    }

    private func parseInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = Double(trimmed) else { return nil }
        let intValue = Int(parsed)
        return intValue >= 0 ? intValue : nil
    }

    private func parseDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatDouble(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private var timerSoundEnabled: Bool {
        timerSoundEnabledValue
    }

    private func formatStep(_ value: Double, suffix: String) -> String {
        if value.rounded(.towardZero) == value {
            return "\(Int(value)) \(suffix)"
        }
        if abs(value * 10 - (value * 10).rounded()) < 0.001 {
            return String(format: "%.1f %@", value, suffix)
        }
        return String(format: "%.2f %@", value, suffix)
    }

    private var cacheKeys: CacheKeys {
        CacheKeys()
    }

    private func startNetworkObserverIfNeeded() {
        guard networkObserverTask == nil else { return }
        networkObserverTask = Task { [weak self] in
            guard let self else { return }
            for await isOnline in self.networkMonitor.statusUpdates() {
                if Task.isCancelled { return }
                if isOnline {
                    await self.flushPendingSetSyncOperations()
                    await self.refreshSyncStatusIndicator()
                } else {
                    self.syncStatus = .savedLocally
                }
            }
        }
    }

    private struct CacheKeys {
        func lastPerformance(exerciseId: String) -> String {
            "exercise.last-performance.\(exerciseId)"
        }

        func personalRecord(exerciseId: String) -> String {
            "exercise.pr.\(exerciseId)"
        }

        func history(exerciseId: String) -> String {
            "exercise.history.\(exerciseId)"
        }
    }
}

struct WorkoutPlayerViewV2: View {
    @State var viewModel: WorkoutPlayerViewModel
    let onExit: () -> Void
    let onFinish: (WorkoutPlayerViewModel.CompletionSummary) -> Void

    @State private var isRestTimerExpanded = false
    @State private var isJumpListPresented = false
    @State private var isExerciseDetailsPresented = false

    var body: some View {
        ZStack {
            FFColors.background.ignoresSafeArea()

            if viewModel.isLoading {
                FFScreenSpinner()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: FFSpacing.md) {
                            topPanel
                            exerciseCard
                            setsCard
                        }
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.top, FFSpacing.md)
                        .padding(.bottom, FFSpacing.xl)
                    }
                    .onChange(of: viewModel.focusedSetIndex) { _, index in
                        guard let index else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(setRowID(index), anchor: .center)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if viewModel.restTimer.isVisible {
                restTimerBanner
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task { await viewModel.onAppear() }
        .alert("Завершить раньше?", isPresented: $viewModel.isFinishEarlyConfirmationPresented) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить", role: .destructive) {
                Task { await viewModel.confirmFinish() }
            }
        } message: {
            Text("Текущий прогресс сохранится в историю тренировки.")
        }
        .alert("Завершить тренировку?", isPresented: $viewModel.isFinishConfirmationPresented) {
            Button("Продолжить тренировку", role: .cancel) {}
            Button("Завершить", role: .destructive) {
                Task { await viewModel.confirmFinish() }
            }
        } message: {
            Text("Тренировка будет завершена, а текущий прогресс сохранится в историю.")
        }
        .onChange(of: viewModel.isFinished) { _, isFinished in
            if isFinished, let summary = viewModel.completionSummary {
                onFinish(summary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.onAppWillEnterForeground() }
        }
        .sheet(isPresented: $viewModel.isHistoryPresented) {
            HistoryBottomSheet(
                exerciseName: viewModel.currentExercise?.name ?? "История",
                entries: viewModel.historyEntries,
                isLoading: viewModel.isHistoryLoading,
                errorMessage: viewModel.historyErrorMessage,
                onRetry: {
                    viewModel.retryHistory()
                },
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isJumpListPresented) {
            WorkoutExerciseJumpListSheet(
                items: viewModel.progressItems,
                onSelect: { item in
                    Task { await viewModel.jumpToExercise(item.id) }
                    isJumpListPresented = false
                },
            )
        }
        .sheet(isPresented: $isExerciseDetailsPresented) {
            if let exercise = viewModel.currentExercise {
                ExerciseDetailsSheet(exercise: exercise)
            }
        }
        .onChange(of: isJumpListPresented) { _, isPresented in
            viewModel.setJumpNavigationActive(isPresented)
        }
        .overlay(alignment: .top) {
            if let message = viewModel.toastMessage {
                Text(message)
                    .font(FFTypography.caption.weight(.semibold))
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.xs)
                    .background(FFColors.gray700)
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                    .padding(.top, FFSpacing.md)
                    .task {
                        try? await Task.sleep(for: .seconds(1.2))
                        viewModel.toastMessage = nil
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let undoState = viewModel.autoAdvanceUndoState {
                HStack(spacing: FFSpacing.sm) {
                    Text(undoState.message)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer(minLength: FFSpacing.xs)
                    Button("Отменить") {
                        Task { await viewModel.undoAutoAdvance() }
                    }
                    .font(FFTypography.caption.weight(.bold))
                    .foregroundStyle(FFColors.accent)
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(FFColors.gray700)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .padding(.horizontal, FFSpacing.md)
                .padding(.bottom, 90)
            }
        }
    }

    private var topPanel: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text(viewModel.title)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(viewModel.progressLabel)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                    Spacer(minLength: FFSpacing.sm)
                    Button {
                        onExit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(FFColors.danger)
                            .frame(width: 44, height: 44)
                            .background(FFColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                    .stroke(FFColors.gray700, lineWidth: 1)
                            }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Выйти из тренировки")
                }

                HStack(spacing: FFSpacing.xs) {
                    SyncStatusIndicator(status: viewModel.syncStatus, compact: true)
                    if viewModel.pendingSyncCount > 0 {
                        Text("\(viewModel.pendingSyncCount)")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.primary)
                            .padding(.horizontal, FFSpacing.xs)
                            .padding(.vertical, FFSpacing.xxs)
                            .background(FFColors.primary.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    if viewModel.canRetrySync {
                        compactActionButton(title: "Повторить", systemImage: "arrow.clockwise") {
                            Task { await viewModel.flushPendingSyncNow() }
                        }
                    }
                }
            }
        }
    }

    private var exerciseCard: some View {
        FFCard {
            if let exercise = viewModel.currentExercise {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text(exercise.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(FFColors.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !viewModel.currentLastSets.isEmpty {
                        lastTimeBlock(lines: viewModel.currentLastSets)
                    }

                    Text(prescription(for: exercise))
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FFSpacing.xs) {
                            if let prText = viewModel.currentPRText {
                                ExerciseInsightPill(
                                    title: "Рекорд",
                                    value: prText,
                                    systemImage: "bolt.fill",
                                    tint: FFColors.accent,
                                )
                            }
                        }
                    }

                    HStack(spacing: FFSpacing.xs) {
                        compactActionButton(title: "Детали", systemImage: "info.circle") {
                            isExerciseDetailsPresented = true
                        }

                        if viewModel.canUseLastPerformance {
                            compactActionButton(title: "Заполнить как в прошлый раз", systemImage: "arrow.down.circle.fill") {
                                Task { await viewModel.useLastPerformance() }
                            }
                        }

                        compactActionButton(title: "История", systemImage: "clock") {
                            viewModel.openHistory()
                        }
                    }
                }
            }
        }
    }

    private var setsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Подходы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(
                    viewModel.currentExerciseIsBodyweight
                        ? "Это упражнение с собственным весом, поэтому вводить вес не нужно."
                        : "Подтвердите подход. Дальше приложение подскажет следующий шаг автоматически.",
                )
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                if let exerciseState = viewModel.currentExerciseState {
                    ForEach(Array(exerciseState.sets.enumerated()), id: \.offset) { index, set in
                        SetRowView(
                            index: index,
                            set: set,
                            isBodyweight: viewModel.currentExerciseIsBodyweight,
                            showsCopyAction: viewModel.canCopyPreviousSet(setIndex: index),
                            weightStepLabel: viewModel.weightStepLabel,
                            isFocused: viewModel.focusedSetIndex == index,
                            onToggleComplete: { Task { await viewModel.toggleSetComplete(setIndex: index) } },
                            onCopy: { Task { await viewModel.copyPreviousSet(setIndex: index) } },
                            onDecreaseWeight: { Task { await viewModel.decrementWeight(setIndex: index) } },
                            onIncreaseWeight: { Task { await viewModel.incrementWeight(setIndex: index) } },
                            onDecreaseReps: { Task { await viewModel.decrementReps(setIndex: index) } },
                            onIncreaseReps: { Task { await viewModel.incrementReps(setIndex: index) } },
                        )
                        .id(setRowID(index))
                    }
                }
            }
        }
    }

    private var restTimerBanner: some View {
        RestTimerBanner(
            remainingSeconds: viewModel.restTimer.remainingSeconds,
            isRunning: viewModel.restTimer.isRunning,
            isExpanded: $isRestTimerExpanded,
            onPauseResume: { viewModel.restTimer.pauseOrResume() },
            onSkip: { viewModel.restTimer.skip() },
            onAddTime: { viewModel.addRest(seconds: $0) },
            onReset: { viewModel.resetRestTimer() },
        )
    }

    private var bottomBar: some View {
        FFCard(padding: FFSpacing.sm) {
            VStack(spacing: FFSpacing.xs) {
                QuickActionsBar(
                    showsCopyAction: viewModel.canUseQuickCopyAction,
                    showsSkipAction: viewModel.canSkipCurrentExercise,
                    copyTitle: "Скопировать",
                    copySubtitle: viewModel.quickActionSetTitle,
                    onCopy: { Task { await viewModel.copyPreviousSetQuickAction() } },
                    onSkipExercise: { Task { await viewModel.skipExercise() } },
                    onUndo: { Task { await viewModel.undoLastChange() } },
                )

                HStack(spacing: FFSpacing.xs) {
                    compactBottomButton(title: "Список упражнений", systemImage: "list.bullet") {
                        isJumpListPresented = true
                    }

                    Menu {
                        Button("Завершить раньше", systemImage: "flag.checkered", role: .destructive) {
                            viewModel.isFinishEarlyConfirmationPresented = true
                        }
                    } label: {
                        HStack(spacing: FFSpacing.xxs) {
                            Image(systemName: "ellipsis.circle")
                            Text("Ещё")
                        }
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(FFColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                .stroke(FFColors.gray700, lineWidth: 1)
                        }
                    }
                }

                bottomActionButton(title: viewModel.primaryBottomTitle, variant: .primary) {
                    Task { await viewModel.primaryBottomAction() }
                }
                .disabled(!viewModel.isPrimaryBottomActionEnabled)
                .opacity(viewModel.isPrimaryBottomActionEnabled ? 1 : 0.55)
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .padding(.bottom, FFSpacing.sm)
        .background(FFColors.background.opacity(0.96))
    }

    private func setRowID(_ index: Int) -> String {
        "set-row-\(index)"
    }

    private func lastTimeBlock(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text("В прошлый раз")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textSecondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(1)
            }
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

    private func compactActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
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

    private func compactBottomButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: FFSpacing.xxs) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(FFColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func bottomActionButton(
        title: String,
        variant: FFButton.Variant,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(variant == .primary ? FFColors.background : FFColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, FFSpacing.sm)
                .background(variant == .primary ? FFColors.primary : FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    if variant == .secondary {
                        RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                            .stroke(FFColors.gray700, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func prescription(for exercise: WorkoutExercise) -> String {
        let reps = if let min = exercise.repsMin, let max = exercise.repsMax {
            "\(min)-\(max)"
        } else if let min = exercise.repsMin {
            "\(min)"
        } else {
            "по самочувствию"
        }
        let rest = exercise.restSeconds.map { "\($0) сек" } ?? "без таймера"
        return "\(exercise.sets) подходов • \(reps) повторов • отдых \(rest)"
    }
}

private struct WorkoutExerciseJumpListSheet: View {
    let items: [WorkoutPlayerViewModel.ExerciseProgressItem]
    let onSelect: (WorkoutPlayerViewModel.ExerciseProgressItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: FFSpacing.sm) {
                        ForEach(items) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(spacing: FFSpacing.sm) {
                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text(item.title)
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                            .lineLimit(2)
                                        Text("Подходы: \(item.completedSets)/\(item.totalSets)")
                                            .font(FFTypography.caption)
                                            .foregroundStyle(FFColors.textSecondary)
                                    }
                                    Spacer(minLength: FFSpacing.sm)
                                    if item.isCurrent {
                                        FFBadge(status: .inProgress)
                                    } else if item.isSkipped {
                                        Text("Пропущено")
                                            .font(FFTypography.caption.weight(.semibold))
                                            .foregroundStyle(FFColors.textSecondary)
                                            .padding(.horizontal, FFSpacing.xs)
                                            .padding(.vertical, FFSpacing.xxs)
                                            .background(FFColors.gray700)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(FFSpacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(FFColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                                .overlay {
                                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                        .stroke(item.isCurrent ? FFColors.primary : FFColors.gray700, lineWidth: item.isCurrent ? 1.4 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.md)
                }
            }
            .navigationTitle("Список упражнений")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SetRowView: View {
    let index: Int
    let set: SessionSetState
    let isBodyweight: Bool
    let showsCopyAction: Bool
    let weightStepLabel: String
    let isFocused: Bool
    let onToggleComplete: () -> Void
    let onCopy: () -> Void
    let onDecreaseWeight: () -> Void
    let onIncreaseWeight: () -> Void
    let onDecreaseReps: () -> Void
    let onIncreaseReps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack(spacing: FFSpacing.xs) {
                Button(action: onToggleComplete) {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(set.isCompleted ? FFColors.accent : FFColors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отметить подход \(index + 1) выполненным")

                Text("Подход \(index + 1)")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Spacer(minLength: FFSpacing.xs)

                if set.isCompleted {
                    completedSetBadge
                }

                if showsCopyAction {
                    Button("Копировать") {
                        onCopy()
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
                    .frame(minHeight: 44)
                }
            }

            HStack(spacing: FFSpacing.sm) {
                if !isBodyweight {
                    metricStepper(
                        title: "Вес",
                        value: set.weightText.isEmpty ? "0" : set.weightText,
                        stepText: weightStepLabel,
                        onMinus: onDecreaseWeight,
                        onPlus: onIncreaseWeight,
                    )
                }
                metricStepper(
                    title: "Повторы",
                    value: set.repsText.isEmpty ? "0" : set.repsText,
                    stepText: "1",
                    onMinus: onDecreaseReps,
                    onPlus: onIncreaseReps,
                )
            }
        }
        .padding(FFSpacing.sm)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(isFocused ? FFColors.primary : FFColors.gray700, lineWidth: isFocused ? 1.6 : 1)
        }
    }

    private var completedSetBadge: some View {
        Text("Завершен")
            .font(FFTypography.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(FFColors.background)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.primary)
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private func metricStepper(
        title: String,
        value: String,
        stepText: String,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void,
    ) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            HStack(spacing: FFSpacing.xs) {
                stepControlButton(systemName: "minus", action: onMinus)
                Text(value)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(FFColors.background.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                stepControlButton(systemName: "plus", action: onPlus)
            }
            Text("Шаг: \(stepText)")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepControlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(FFColors.gray700)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionsBar: View {
    let showsCopyAction: Bool
    let showsSkipAction: Bool
    let copyTitle: String
    let copySubtitle: String
    let onCopy: () -> Void
    let onSkipExercise: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: FFSpacing.xs) {
            if showsCopyAction {
                compactButton(
                    title: copyTitle,
                    subtitle: copySubtitle,
                    systemImage: "doc.on.doc",
                    action: onCopy,
                )
            }
            if showsSkipAction {
                compactButton(
                    title: "Пропустить",
                    subtitle: nil,
                    systemImage: "forward.fill",
                    action: onSkipExercise,
                )
            }
            compactButton(
                title: "Отменить",
                subtitle: nil,
                systemImage: "arrow.uturn.backward",
                action: onUndo,
            )
        }
    }

    private func compactButton(
        title: String,
        subtitle: String?,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(FFTypography.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(FFColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .foregroundStyle(FFColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, FFSpacing.xxs)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ExerciseDetailsSheet: View {
    let exercise: WorkoutExercise
    @Environment(\.dismiss) private var dismiss
    private let environment = AppEnvironment.from()

    private var resolvedMedia: [ResolvedExerciseMedia] {
        (exercise.media ?? []).compactMap { item in
            guard let url = item.resolvedURL(baseURL: environment.backendBaseURL) else { return nil }
            return ResolvedExerciseMedia(id: item.id, type: item.type, url: url)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: FFSpacing.md) {
                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                Text(exercise.name)
                                    .font(FFTypography.h2)
                                    .foregroundStyle(FFColors.textPrimary)
                                Text(exerciseSummary)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        if let description = exercise.description {
                            detailsBlock(title: "Об упражнении", text: description)
                        }

                        if let notes = exercise.notes {
                            detailsBlock(title: "Подсказка тренера", text: notes)
                        }

                        if !resolvedMedia.isEmpty {
                            FFCard {
                                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                    Text("Медиа")
                                        .font(FFTypography.h2)
                                        .foregroundStyle(FFColors.textPrimary)

                                    ForEach(resolvedMedia) { item in
                                        ExerciseMediaCard(media: item)
                                    }
                                }
                            }
                        }

                        if exercise.description == nil, exercise.notes == nil, resolvedMedia.isEmpty {
                            FFEmptyState(
                                title: "Подробности скоро появятся",
                                message: "Для этого упражнения пока не добавлены описание и медиа.",
                            )
                        }
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.md)
                }
            }
            .navigationTitle("Детали упражнения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var exerciseSummary: String {
        let reps = if let min = exercise.repsMin, let max = exercise.repsMax {
            "\(min)-\(max)"
        } else if let min = exercise.repsMin {
            "\(min)"
        } else {
            "по самочувствию"
        }
        let rest = exercise.restSeconds.map { "\($0) сек" } ?? "без таймера"
        let load = exercise.isBodyweight ? "с собственным весом" : "с отягощением"
        return "\(exercise.sets) подходов • \(reps) повторов • отдых \(rest) • \(load)"
    }

    private func detailsBlock(title: String, text: String) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(text)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ResolvedExerciseMedia: Identifiable {
    let id: String
    let type: ContentMediaType
    let url: URL
}

private struct ExerciseMediaCard: View {
    let media: ResolvedExerciseMedia

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            switch media.type {
            case .image:
                AsyncImage(url: media.url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        mediaPlaceholder(systemImage: "photo", title: "Изображение недоступно")
                    case .empty:
                        ZStack {
                            FFColors.surface
                            ProgressView()
                                .tint(FFColors.accent)
                        }
                    @unknown default:
                        mediaPlaceholder(systemImage: "photo", title: "Изображение недоступно")
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))

            case .video:
                ExerciseVideoCard(url: media.url)
            }

            Link(destination: media.url) {
                Label("Открыть медиа", systemImage: media.type == .video ? "play.rectangle" : "arrow.up.right.square")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
            }
        }
    }

    private func mediaPlaceholder(systemImage: String, title: String) -> some View {
        ZStack {
            FFColors.surface
            VStack(spacing: FFSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FFColors.textSecondary)
                Text(title)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
    }
}

private struct ExerciseVideoCard: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .onDisappear {
                player.pause()
            }
    }
}

private struct RestTimerBanner: View {
    let remainingSeconds: Int
    let isRunning: Bool
    @Binding var isExpanded: Bool
    let onPauseResume: () -> Void
    let onSkip: () -> Void
    let onAddTime: (Int) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.xs) {
            FFCard(padding: FFSpacing.sm) {
                VStack(spacing: FFSpacing.xs) {
                    ViewThatFits(in: .horizontal) {
                        regularHeaderRow
                        compactHeaderLayout
                    }

                    if isExpanded {
                        HStack(spacing: FFSpacing.xs) {
                            timerChip(title: "+15") { onAddTime(15) }
                            timerChip(title: "+30") { onAddTime(30) }
                            timerChip(title: "+60") { onAddTime(60) }
                            timerChip(title: "Сброс", action: onReset)
                            Spacer(minLength: 0)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .background(FFColors.background.opacity(0.96))
    }

    private var regularHeaderRow: some View {
        HStack(spacing: FFSpacing.xs) {
            titleLabel

            Spacer(minLength: FFSpacing.xs)

            timeValue

            capsuleButton(title: isRunning ? "Пауза" : "Продолжить", tint: FFColors.gray700, action: onPauseResume)
            capsuleButton(title: "Пропустить", tint: FFColors.danger, action: onSkip)
            expandButton
        }
    }

    private var compactHeaderLayout: some View {
        VStack(spacing: FFSpacing.xs) {
            HStack(spacing: FFSpacing.xs) {
                titleLabel
                Spacer(minLength: FFSpacing.xs)
                timeValue
                expandButton
            }

            HStack(spacing: FFSpacing.xs) {
                capsuleButton(title: isRunning ? "Пауза" : "Продолжить", tint: FFColors.gray700, action: onPauseResume)
                capsuleButton(title: "Пропустить", tint: FFColors.danger, action: onSkip)
            }
        }
    }

    private var titleLabel: some View {
        Label("Отдых", systemImage: "timer")
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(FFColors.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private var timeValue: some View {
        Text(formattedTime(remainingSeconds))
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(FFColors.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FFColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(FFColors.surface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func capsuleButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, FFSpacing.xs)
                .frame(minHeight: 36)
                .background(tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func timerChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .padding(.horizontal, FFSpacing.sm)
                .frame(minHeight: 38)
                .background(FFColors.gray700)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        }
        .buttonStyle(.plain)
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct WorkoutCompletionViewV2: View {
    let summary: WorkoutPlayerViewModel.CompletionSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Тренировка завершена")
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(summary.workoutTitle)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Итог")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Упражнений: \(summary.completedExercises) из \(summary.totalExercises)")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Подходов: \(summary.completedSets) из \(summary.totalSets)")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Готово", variant: .primary, action: onDone)
            Spacer()
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.md)
        .background(FFColors.background)
    }
}

#Preview("Плеер тренировки 2") {
    NavigationStack {
        WorkoutPlayerViewV2(
            viewModel: WorkoutPlayerViewModel(
                userSub: "athlete-1",
                programId: "program-1",
                workout: WorkoutDetailsModel(
                    id: "w1",
                    title: "Силовая A",
                    dayOrder: 1,
                    coachNote: nil,
                    exercises: [
                        WorkoutExercise(
                            id: "e1",
                            name: "Жим лёжа",
                            sets: 4,
                            repsMin: 6,
                            repsMax: 8,
                            targetRpe: 8,
                            restSeconds: 90,
                            notes: nil,
                            orderIndex: 0,
                        ),
                    ],
                ),
            ),
            onExit: {},
            onFinish: { _ in },
        )
    }
}
