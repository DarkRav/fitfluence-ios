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
    enum EditableInputField: Equatable, Sendable {
        case weight
        case reps
    }

    struct EditingTarget: Equatable, Sendable {
        let setIndex: Int
        let field: EditableInputField
        let requestID: UUID
    }

    struct ExerciseRestTimerPreference: Equatable, Sendable {
        var isEnabled: Bool
        var seconds: Int
    }

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
    private var executionContext: WorkoutExecutionContext?
    private let syncCoordinator: SyncCoordinator
    private let profileSettingsStore: ProfileSettingsStore
    private let exerciseCatalogRepository: any ExerciseCatalogRepository
    private let exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding
    let restTimer: RestTimerModel

    private var autoAdvanceUndoTask: Task<Void, Never>?
    private var networkObserverTask: Task<Void, Never>?
    private var pendingSetSyncFlushTask: Task<Void, Never>?
    private var primaryActionHoldMode: PrimaryActionMode?

    private var lastPerformanceByExerciseId: [String: AthleteExerciseLastPerformanceResponse] = [:]
    private var personalRecordByExerciseId: [String: AthletePersonalRecord] = [:]
    private var insightsLoadedExerciseIDs: Set<String> = []
    private var startedExerciseEvents: Set<String> = []
    private var exerciseRestTimerPreferences: [String: ExerciseRestTimerPreference] = [:]
    private var weightStep: Double = ProfileSettings.default.weightStep
    private var defaultRestSeconds: Int = ProfileSettings.default.defaultRestSeconds
    private var showRPEValue = ProfileSettings.default.showRPE
    private var timerSoundEnabledValue = ProfileSettings.default.timerSoundEnabled

    var isLoading = false
    var isFinishEarlyConfirmationPresented = false
    var isFinishConfirmationPresented = false
    var isSubmittingFinish = false
    var isFinished = false
    var blockedByActiveSession: ActiveWorkoutSession?
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
    var exercisePickerFlow: WorkoutExercisePickerFlow?
    var editingTarget: EditingTarget?
    var inlineEditingSetIndex: Int?
    var secondaryEditingSetIndex: Int?
    var pendingInlineCommitCount = 0

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
        exerciseCatalogRepository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
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
        self.exerciseCatalogRepository = exerciseCatalogRepository
        self.exercisePickerSuggestionsProvider = exercisePickerSuggestionsProvider
        self.restTimer = restTimer

        restTimer.onCompleted = { [weak self] in
            self?.toastMessage = "Отдых завершён. Можно начинать следующий подход."
        }
    }

    @MainActor
    deinit {
        autoAdvanceUndoTask?.cancel()
        networkObserverTask?.cancel()
        pendingSetSyncFlushTask?.cancel()
    }

    var title: String {
        activeWorkout.title
    }

    var activeWorkout: WorkoutDetailsModel {
        session?.workoutDetails ?? workout
    }

    var currentExerciseIndex: Int {
        session?.currentExerciseIndex ?? 0
    }

    var currentExercise: WorkoutExercise? {
        guard activeWorkout.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return activeWorkout.exercises[currentExerciseIndex]
    }

    var currentExerciseState: SessionExerciseState? {
        guard let exercise = currentExercise else { return nil }
        return session?.exercises.first(where: { $0.exerciseId == exercise.id })
    }

    var progressLabel: String {
        let current = min(activeWorkout.exercises.count, currentExerciseIndex + 1)
        return "Упражнение \(max(1, current)) из \(max(1, activeWorkout.exercises.count))"
    }

    var progressSummary: String {
        let completedExercises = progressItems.count { item in
            item.isSkipped || (item.totalSets > 0 && item.completedSets >= item.totalSets)
        }
        let totalExercises = max(1, activeWorkout.exercises.count)
        let totalSets = max(1, session?.totalSetsCount ?? activeWorkout.exercises.reduce(0) { $0 + max(1, $1.sets) })
        return "\(completedExercises) из \(totalExercises) упражнений закрыто • \(session?.completedSetsCount ?? 0) из \(totalSets) подходов"
    }

    var isLastExercise: Bool {
        activeWorkout.exercises.isEmpty || currentExerciseIndex >= activeWorkout.exercises.count - 1
    }

    var canMoveToPreviousExercise: Bool {
        currentExerciseIndex > 0
    }

    var canMoveToNextExercise: Bool {
        !isLastExercise && activeWorkout.exercises.indices.contains(currentExerciseIndex + 1)
    }

    var previousExerciseTitle: String? {
        guard canMoveToPreviousExercise else { return nil }
        return activeWorkout.exercises[currentExerciseIndex - 1].name
    }

    var nextExerciseTitle: String? {
        guard canMoveToNextExercise else { return nil }
        return activeWorkout.exercises[currentExerciseIndex + 1].name
    }

    var primaryBottomTitle: String {
        isLastExercise ? "Завершить тренировку" : "Следующее упражнение"
    }

    var nextLoggableSetIndex: Int? {
        firstUncompletedSetIndex(in: currentExerciseState)
    }

    var activeSetIndex: Int? {
        nextLoggableSetIndex
    }

    var selectedLoggableSetIndex: Int? {
        activeSetIndex
    }

    var effectiveEditingSetIndex: Int? {
        editingTarget?.setIndex ?? inlineEditingSetIndex ?? secondaryEditingSetIndex
    }

    var isEditingNonLoggableSet: Bool {
        guard let effectiveEditingSetIndex else { return false }
        return effectiveEditingSetIndex != activeSetIndex
    }

    var isInlineEditingOrCommitting: Bool {
        editingTarget != nil || pendingInlineCommitCount > 0
    }

    private var activeSetEntryState: SetEntryState {
        guard let activeSetIndex else { return .unavailable }
        return entryState(for: activeSetIndex)
    }

    var hasUncompletedSetsInCurrentExercise: Bool {
        nextLoggableSetIndex != nil
    }

    private var calculatedPrimaryActionMode: PrimaryActionMode {
        guard hasUncompletedSetsInCurrentExercise else {
            return .advance
        }

        if let inlineEditingSetIndex {
            if inlineEditingSetIndex != activeSetIndex {
                return .done
            }

            if isInlineEditingOrCommitting {
                return .done
            }

            switch entryState(for: inlineEditingSetIndex) {
            case .complete:
                return .log
            case .partial, .empty, .unavailable:
                return .done
            }
        }

        if isInlineEditingOrCommitting {
            return .done
        }

        switch activeSetEntryState {
        case .complete:
            return .log
        case .partial:
            return .done
        case .empty, .unavailable:
            return .log
        }
    }

    private var resolvedPrimaryActionMode: PrimaryActionMode {
        primaryActionHoldMode ?? calculatedPrimaryActionMode
    }

    var primaryActionTitle: String {
        switch resolvedPrimaryActionMode {
        case .done:
            return "Готово"
        case .log:
            return "Логировать подход"
        case .advance:
            return primaryBottomTitle
        }
    }

    var secondaryActionTitle: String {
        if hasUncompletedSetsInCurrentExercise {
            return "Логировать все"
        }
        return "Добавить подход"
    }

    var isPrimaryBottomActionEnabled: Bool {
        guard !isSubmittingFinish, !isFinished else { return false }
        switch resolvedPrimaryActionMode {
        case .done:
            return true
        case .advance:
            return true
        case .log:
            guard hasUncompletedSetsInCurrentExercise else { return true }
            guard let setIndex = selectedLoggableSetIndex else { return false }
            return canLogSet(setIndex: setIndex)
        }
    }

    var isSecondaryBottomActionEnabled: Bool {
        guard !isSubmittingFinish, !isFinished else { return false }
        guard hasUncompletedSetsInCurrentExercise,
              let exerciseState = currentExerciseState
        else {
            return true
        }

        let incompleteIndexes = exerciseState.sets.enumerated().compactMap { index, set in
            set.isCompleted ? nil : index
        }
        guard !incompleteIndexes.isEmpty else { return false }
        return incompleteIndexes.allSatisfy(canLogSet(setIndex:))
    }

    var progressItems: [ExerciseProgressItem] {
        activeWorkout.exercises.map { exercise in
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
        if let activeSetIndex, exerciseState.sets.indices.contains(activeSetIndex) {
            return activeSetIndex
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
        activeWorkout.exercises.count > 1
    }

    var canDuplicateLastSet: Bool {
        (currentExerciseState?.sets.isEmpty == false)
    }

    var restStatusTitle: String {
        restTimer.isRunning ? "Идёт отдых" : "Отдых на паузе"
    }

    var nextStepSummary: String {
        guard let currentExercise else {
            return "Следующий шаг появится после выбора упражнения."
        }

        if let exerciseState = currentExerciseState,
           let nextSetIndex = firstUncompletedSetIndex(in: exerciseState)
        {
            return "Дальше подход \(nextSetIndex + 1) в упражнении \(currentExercise.name)."
        }

        if let nextExerciseTitle {
            return "Дальше упражнение \(nextExerciseTitle)."
        }

        return "После этого можно завершать тренировку."
    }

    var restCompletionTitle: String {
        if let message = restTimer.completionMessage,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return message
        }
        return "Отдых завершён"
    }

    var restCompletionDetail: String {
        nextStepSummary
    }

    var restPresetOptions: [Int] {
        let base = max(15, currentExercise?.restSeconds ?? defaultRestSeconds)
        let candidates = [max(15, base - 30), base, min(600, base + 30)]
        var unique: [Int] = []
        for value in candidates where !unique.contains(value) {
            unique.append(value)
        }
        return unique
    }

    var currentRestTimerPreference: ExerciseRestTimerPreference {
        restTimerPreference(for: currentExercise)
    }

    var currentRestTimerEnabled: Bool {
        currentRestTimerPreference.isEnabled
    }

    var currentRestTimerChipTitle: String {
        currentRestTimerEnabled
            ? "Таймер: \(formattedRestDuration(currentRestTimerPreference.seconds))"
            : "Таймер: выкл"
    }

    var showsLocalStructureNotice: Bool {
        session?.hasLocalOnlyStructuralChanges == true
    }

    var exercisePickerRepository: any ExerciseCatalogRepository {
        exerciseCatalogRepository
    }

    var exercisePickerSuggestions: any ExercisePickerSuggestionsProviding {
        exercisePickerSuggestionsProvider
    }

    var quickActionSetTitle: String {
        guard let quickActionSetIndex, quickActionSetIndex > 0 else {
            return "Из предыдущего подхода"
        }
        return "Из подхода \(quickActionSetIndex)"
    }

    var weightStepLabel: String {
        WorkoutSetInputFormatting.formatStep(weightStep, suffix: "кг")
    }

    var currentExerciseIsBodyweight: Bool {
        currentExercise?.isBodyweight == true
    }

    var currentExerciseSummaryLine: String {
        guard let currentExercise else { return progressSummary }
        let reps = if let min = currentExercise.repsMin, let max = currentExercise.repsMax {
            "\(min)-\(max)"
        } else if let min = currentExercise.repsMin {
            "\(min)"
        } else {
            "по самочувствию"
        }
        let rest = currentExercise.restSeconds.map { "\($0) сек" } ?? "таймер опционален"
        return "\(currentExercise.sets) подходов • \(reps) повторов • \(rest)"
    }

    var showsRPEControl: Bool {
        guard currentExercise != nil else { return false }
        if showRPEValue {
            return true
        }
        if currentExercise?.targetRpe != nil {
            return true
        }
        return currentExerciseState?.sets.contains {
            !$0.rpeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } == true
    }

    func onAppear() async {
        isLoading = true
        let settings = await profileSettingsStore.load(userSub: userSub)
        weightStep = max(0.5, settings.weightStep)
        defaultRestSeconds = max(15, settings.defaultRestSeconds)
        showRPEValue = settings.showRPE
        timerSoundEnabledValue = settings.timerSoundEnabled
        let result = await sessionManager.loadOrCreateSession(
            userSub: userSub,
            programId: programId,
            workout: workout,
            source: source,
        )
        switch result {
        case let .session(resolvedSession):
            blockedByActiveSession = nil
            session = resolvedSession
        case let .blockedByActiveSession(activeSession):
            blockedByActiveSession = activeSession
            session = nil
        }
        isLoading = false
        guard blockedByActiveSession == nil else { return }
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
        guard !currentExerciseIsBodyweight else { return }
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: weightStep)
    }

    func decrementWeight(setIndex: Int) async {
        guard !currentExerciseIsBodyweight else { return }
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: -weightStep)
    }

    func incrementReps(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.repsText, step: 1)
    }

    func decrementReps(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.repsText, step: -1)
    }

    func updateWeight(setIndex: Int, input: String) async {
        guard !currentExerciseIsBodyweight else { return }
        await updateSetField(setIndex: setIndex, field: .weight, rawValue: input)
    }

    func updateReps(setIndex: Int, input: String) async {
        await updateSetField(setIndex: setIndex, field: .reps, rawValue: input)
    }

    func updateRPE(setIndex: Int, rpe: Int?) async {
        await updateSetField(setIndex: setIndex, field: .rpe, rawValue: rpe.map(String.init) ?? "")
    }

    func canRemoveSet(setIndex: Int) -> Bool {
        guard let exerciseState = currentExerciseState else { return false }
        return exerciseState.sets.indices.contains(setIndex) && exerciseState.sets.count > 1
    }

    func selectSet(_ setIndex: Int) {
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return
        }
        if editingTarget?.setIndex != setIndex {
            editingTarget = nil
        }
        if setIndex == activeSetIndex {
            secondaryEditingSetIndex = nil
            focusedSetIndex = setIndex
        }
    }

    func selectSetAndEditReps(_ setIndex: Int) {
        requestEditing(setIndex: setIndex, field: .reps)
    }

    func requestEditWeight(_ setIndex: Int) {
        requestEditing(setIndex: setIndex, field: .weight)
    }

    func requestEditReps(_ setIndex: Int) {
        requestEditing(setIndex: setIndex, field: .reps)
    }

    func beginInlineCommit() {
        pendingInlineCommitCount += 1
    }

    func finishInlineCommit() {
        pendingInlineCommitCount = max(0, pendingInlineCommitCount - 1)
    }

    func endEditing(requestID: UUID) {
        guard editingTarget?.requestID == requestID else { return }
        editingTarget = nil
    }

    func beginPrimaryActionInteraction() {
        primaryActionHoldMode = calculatedPrimaryActionMode
    }

    func endPrimaryActionInteraction() {
        primaryActionHoldMode = nil
    }

    func toggleWarmup(setIndex: Int) async {
        guard let currentExercise, let session else { return }
        beginSecondaryEditingModeIfNeeded(for: setIndex)
        self.session = await sessionManager.toggleSetWarmup(
            session,
            exerciseId: currentExercise.id,
            setIndex: setIndex,
        )
        focusedSetIndex = setIndex
        toastMessage = currentExerciseState?.sets[safe: setIndex]?.isWarmup == true
            ? "Подход отмечен как разминка"
            : "Подход переведён в рабочий"
        await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: setIndex)
        await refreshSyncStatusIndicator()
    }

    func addSet(duplicateLast: Bool) async {
        guard let currentExercise, let session else { return }
        self.session = await sessionManager.addSet(
            session,
            exerciseId: currentExercise.id,
            duplicateLast: duplicateLast,
        )
        let newIndex = max(0, (currentExerciseState?.sets.count ?? 1) - 1)
        secondaryEditingSetIndex = nil
        focusedSetIndex = newIndex
        toastMessage = duplicateLast
            ? "Добавлен дубликат последнего подхода"
            : "Добавлен новый подход"
        inlineEditingSetIndex = nil
        await ensureCurrentExerciseContext()
        await syncCanonicalWorkoutIfNeeded()
        await refreshSyncStatusIndicator()
    }

    func removeSet(setIndex: Int) async {
        guard canRemoveSet(setIndex: setIndex),
              let currentExercise,
              let session
        else {
            return
        }
        self.session = await sessionManager.removeSet(
            session,
            exerciseId: currentExercise.id,
            setIndex: setIndex,
        )
        focusedSetIndex = min(setIndex, max(0, (currentExerciseState?.sets.count ?? 1) - 1))
        editingTarget = nil
        if secondaryEditingSetIndex == setIndex {
            secondaryEditingSetIndex = nil
        } else if let secondaryEditingSetIndex, secondaryEditingSetIndex > setIndex {
            self.secondaryEditingSetIndex = secondaryEditingSetIndex - 1
        }
        if inlineEditingSetIndex == setIndex {
            inlineEditingSetIndex = nil
        } else if let inlineEditingSetIndex, inlineEditingSetIndex > setIndex {
            self.inlineEditingSetIndex = inlineEditingSetIndex - 1
        }
        toastMessage = "Подход удалён"
        await ensureCurrentExerciseContext()
        await syncCanonicalWorkoutIfNeeded()
        await refreshSyncStatusIndicator()
    }

    func presentAddExerciseFlow() {
        exercisePickerFlow = .addAfterCurrent
    }

    func presentReplaceCurrentExerciseFlow() {
        guard currentExercise != nil else { return }
        exercisePickerFlow = .replaceCurrent
    }

    func reorderExercises(draggedId: String, targetId: String) async {
        guard let session, draggedId != targetId else { return }
        self.session = await sessionManager.reorderExercises(
            session,
            sourceExerciseId: draggedId,
            targetExerciseId: targetId,
        )
        toastMessage = "Порядок упражнений обновлён"
        await ensureCurrentExerciseContext()
        await syncCanonicalWorkoutIfNeeded()
        await refreshSyncStatusIndicator()
    }

    func dismissExercisePickerFlow() {
        exercisePickerFlow = nil
    }

    func selectedExerciseIDs(for flow: WorkoutExercisePickerFlow) -> Set<String> {
        var ids = Set(activeWorkout.exercises.map(\.id))
        if flow == .replaceCurrent, let currentId = currentExercise?.id {
            ids.remove(currentId)
        }
        return ids
    }

    func applyPickedExercise(_ exercise: ExerciseCatalogItem, flow: WorkoutExercisePickerFlow) async {
        guard let session else { return }
        if flow == .addAfterCurrent,
           activeWorkout.exercises.contains(where: { $0.id == exercise.id })
        {
            toastMessage = "Это упражнение уже есть в тренировке"
            exercisePickerFlow = nil
            return
        }

        if flow == .replaceCurrent, currentExercise?.id == exercise.id {
            toastMessage = "Текущее упражнение уже выбрано"
            exercisePickerFlow = nil
            return
        }

        let newExercise = workoutExercise(from: exercise, orderIndex: currentExerciseIndex)

        switch flow {
        case .addAfterCurrent:
            self.session = await sessionManager.addExercise(
                session,
                exercise: newExercise,
                afterExerciseId: currentExercise?.id,
            )
            toastMessage = "Упражнение добавлено в тренировку"
        case .replaceCurrent:
            guard let currentExercise else { return }
            self.session = await sessionManager.replaceExercise(
                session,
                exerciseId: currentExercise.id,
                with: newExercise,
            )
            toastMessage = "Текущее упражнение заменено"
        }

        restTimer.dismissCompletionMessage()
        exercisePickerFlow = nil
        focusedSetIndex = 0
        await ensureCurrentExerciseContext()
        await syncCanonicalWorkoutIfNeeded()
        await refreshSyncStatusIndicator()
    }

    func nextExercise() async {
        guard let session else { return }
        restTimer.dismissCompletionMessage()
        clearInlineEditingState()
        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex + 1)
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
        await ensureCurrentExerciseContext()
    }

    func prevExercise() async {
        guard let session else { return }
        restTimer.dismissCompletionMessage()
        clearInlineEditingState()
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
        restTimer.dismissCompletionMessage()
        clearInlineEditingState()
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
        clearInlineEditingState()
        toastMessage = "Последнее действие отменено"
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
        clearInlineEditingState()
        toastMessage = "Изменение отменено"
        await ensureCurrentExerciseContext()
    }

    func jumpToExercise(_ exerciseID: String) async {
        guard let targetIndex = activeWorkout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let session
        else {
            return
        }
        restTimer.dismissCompletionMessage()
        clearInlineEditingState()
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
                    weightText: set.weight.map(WorkoutSetInputFormatting.formatWeight),
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
                weightText: sourceSet?.weight.map(WorkoutSetInputFormatting.formatWeight),
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

    func restartRest(seconds: Int) {
        restTimer.start(seconds: seconds)
    }

    func resetRestTimer() {
        restTimer.reset()
    }

    func dismissRestCompletion() {
        restTimer.dismissCompletionMessage()
    }

    func onAppWillEnterForeground() async {
        restTimer.handleWillEnterForeground()
        await flushPendingSyncNow()
    }

    func copyPreviousSetQuickAction() async {
        guard let setIndex = quickActionSetIndex else { return }
        await copyPreviousSet(setIndex: setIndex)
    }

    func completeFocusedSet() async {
        guard let exerciseState = currentExerciseState else { return }
        let targetIndex: Int
        if let selectedLoggableSetIndex {
            targetIndex = selectedLoggableSetIndex
        } else {
            if let focusedSetIndex, exerciseState.sets.indices.contains(focusedSetIndex) {
                self.focusedSetIndex = focusedSetIndex
            }
            toastMessage = "Выберите незавершённый подход"
            return
        }

        guard canLogSet(setIndex: targetIndex) else {
            focusedSetIndex = targetIndex
            editingTarget = EditingTarget(
                setIndex: targetIndex,
                field: preferredEditingField(for: targetIndex),
                requestID: UUID()
            )
            toastMessage = validationMessage(for: targetIndex, scope: .singleSet)
            return
        }

        await toggleSetComplete(setIndex: targetIndex)
        clearInlineEditingState()
        startRestTimerForCurrentExerciseIfEnabled()
    }

    func completeAllSets() async {
        guard let currentExercise,
              let session,
              let exerciseState = currentExerciseState
        else {
            return
        }

        let incompleteIndexes = exerciseState.sets.enumerated().compactMap { index, set in
            set.isCompleted ? nil : index
        }

        guard !incompleteIndexes.isEmpty else {
            toastMessage = "Все подходы уже отмечены"
            return
        }

        if let firstInvalidIndex = incompleteIndexes.first(where: { !canLogSet(setIndex: $0) }) {
            focusedSetIndex = firstInvalidIndex
            editingTarget = EditingTarget(
                setIndex: firstInvalidIndex,
                field: preferredEditingField(for: firstInvalidIndex),
                requestID: UUID()
            )
            toastMessage = validationMessage(for: firstInvalidIndex, scope: .allSets)
            return
        }

        var updatedSession = session
        for index in incompleteIndexes {
            updatedSession = await sessionManager.toggleSetComplete(
                updatedSession,
                exerciseId: currentExercise.id,
                setIndex: index,
            )
        }

        self.session = updatedSession

        for index in incompleteIndexes {
            await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: index)
        }

        clearInlineEditingState()
        focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState)
        toastMessage = incompleteIndexes.count == 1
            ? "Подход отмечен"
            : "Все подходы отмечены"
        presentAutoAdvanceUndo(
            message: incompleteIndexes.count == 1
                ? "Подход выполнен"
                : "Упражнение отмечено целиком",
            includesExerciseMove: false,
        )
        startRestTimerForCurrentExerciseIfEnabled()
        await refreshSyncStatusIndicator()
    }

    func toggleCurrentExerciseRestTimer() {
        guard let exercise = currentExercise else { return }
        var preference = restTimerPreference(for: exercise)
        preference.isEnabled.toggle()
        exerciseRestTimerPreferences[exercise.id] = preference
        if !preference.isEnabled {
            restTimer.reset()
            restTimer.dismissCompletionMessage()
        }
    }

    func setCurrentExerciseRestTimer(seconds: Int) {
        guard let exercise = currentExercise else { return }
        var preference = restTimerPreference(for: exercise)
        preference.seconds = max(15, seconds)
        exerciseRestTimerPreferences[exercise.id] = preference
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
        let mode = resolvedPrimaryActionMode
        restTimer.dismissCompletionMessage()
        switch mode {
        case .done:
            clearInlineEditingState()
        case .log:
            await completeFocusedSet()
        case .advance:
            if isLastExercise {
                isFinishConfirmationPresented = true
            } else {
                await nextExercise()
            }
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
            workoutTitle: activeWorkout.title,
            completedExercises: completedExercises,
            totalExercises: activeWorkout.exercises.count,
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
        if exerciseRestTimerPreferences[exercise.id] == nil {
            exerciseRestTimerPreferences[exercise.id] = ExerciseRestTimerPreference(
                isEnabled: false,
                seconds: max(15, exercise.restSeconds ?? defaultRestSeconds),
            )
        }
        restTimer.setContext(
            workoutId: workout.id,
            workoutTitle: activeWorkout.title,
            exerciseName: exercise.name,
            timerSoundEnabled: timerSoundEnabled,
        )
        await ensureInsightsLoaded(for: exercise.id)
        await applySmartDefaultsIfNeeded(for: exercise)
        if let currentExerciseState, !currentExerciseState.sets.isEmpty {
            if let focusedSetIndex,
               currentExerciseState.sets.indices.contains(focusedSetIndex)
            {
                self.focusedSetIndex = focusedSetIndex
            } else if let focusedSetIndex {
                self.focusedSetIndex = min(max(0, focusedSetIndex), currentExerciseState.sets.count - 1)
            } else {
                focusedSetIndex = firstUncompletedSetIndex(in: currentExerciseState) ?? 0
            }
            if let secondaryEditingSetIndex,
               (!currentExerciseState.sets.indices.contains(secondaryEditingSetIndex) || secondaryEditingSetIndex == activeSetIndex)
            {
                self.secondaryEditingSetIndex = nil
            }
            if let inlineEditingSetIndex,
               !currentExerciseState.sets.indices.contains(inlineEditingSetIndex)
            {
                self.inlineEditingSetIndex = nil
            }
        }
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
                    weightText: sourceSet.weight.map(WorkoutSetInputFormatting.formatWeight),
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
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return
        }

        beginSecondaryEditingModeIfNeeded(for: setIndex)

        let currentValue = Double(exerciseState.sets[setIndex][keyPath: keyPath]) ?? 0
        let next = max(0, currentValue + step)
        let nextString = keyPath == \.weightText
            ? WorkoutSetInputFormatting.formatWeight(next)
            : String(Int(next.rounded()))

        if keyPath == \.weightText {
            await updateWeight(setIndex: setIndex, input: nextString)
        } else {
            await updateReps(setIndex: setIndex, input: nextString)
        }
    }

    private func handleAutoAdvanceIfNeeded(exerciseId: String, completedSetIndex: Int) async {
        guard !isJumpNavigationActive else {
            if let exerciseState = session?.exercises.first(where: { $0.exerciseId == exerciseId }) {
                focusedSetIndex = nextFocusIndex(afterCompleting: completedSetIndex, in: exerciseState)
            }
            presentAutoAdvanceUndo(message: "Подход выполнен", includesExerciseMove: false)
            return
        }

        guard let session,
              let exerciseState = session.exercises.first(where: { $0.exerciseId == exerciseId })
        else {
            return
        }

        let isLastSet = completedSetIndex >= exerciseState.sets.count - 1
        if !isLastSet {
            focusedSetIndex = nextFocusIndex(afterCompleting: completedSetIndex, in: exerciseState)
            presentAutoAdvanceUndo(
                message: "Подход выполнен, открыт следующий",
                includesExerciseMove: false,
            )
            return
        }

        if isLastExercise {
            focusedSetIndex = nextFocusIndex(afterCompleting: completedSetIndex, in: exerciseState)
            presentAutoAdvanceUndo(message: "Упражнение завершено, можно финишировать", includesExerciseMove: false)
            return
        }

        focusedSetIndex = nextFocusIndex(afterCompleting: completedSetIndex, in: exerciseState)
        presentAutoAdvanceUndo(message: "Упражнение завершено, можно перейти дальше", includesExerciseMove: false)
    }

    private func restTimerPreference(for exercise: WorkoutExercise?) -> ExerciseRestTimerPreference {
        guard let exercise else {
            return ExerciseRestTimerPreference(isEnabled: false, seconds: max(15, defaultRestSeconds))
        }
        if let stored = exerciseRestTimerPreferences[exercise.id] {
            return stored
        }
        return ExerciseRestTimerPreference(
            isEnabled: false,
            seconds: max(15, exercise.restSeconds ?? defaultRestSeconds),
        )
    }

    private func startRestTimerForCurrentExerciseIfEnabled() {
        let preference = currentRestTimerPreference
        guard preference.isEnabled else { return }
        restTimer.start(seconds: max(15, preference.seconds))
    }

    private func formattedRestDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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

    private func syncCurrentSetIfNeeded(
        exerciseId: String,
        setIndex: Int,
        processImmediately: Bool = true,
    ) async {
        guard let session else {
            return
        }

        if session.hasLocalOnlyStructuralChanges {
            await syncCanonicalWorkoutIfNeeded()
            await refreshSyncStatusIndicator()
            return
        }

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
            weight: WorkoutSetInputFormatting.parseWeight(set.weightText),
            reps: WorkoutSetInputFormatting.parseWholeNumber(set.repsText),
            rpe: WorkoutSetInputFormatting.parseWholeNumber(set.rpeText),
            isCompleted: set.isCompleted,
            isWarmup: set.isWarmup,
            restSecondsActual: nil,
            processImmediately: processImmediately,
        )
        await refreshSyncStatusIndicator()
        if !processImmediately {
            schedulePendingSetSyncFlush()
        }
    }

    private func syncCanonicalWorkoutIfNeeded() async {
        guard let session,
              session.hasLocalOnlyStructuralChanges,
              let workoutInstanceId = UUID(uuidString: session.workoutId).map({ _ in session.workoutId }),
              let athleteTrainingClient
        else {
            return
        }

        let request = buildSyncRequest(from: session)
        let result = await athleteTrainingClient.syncActiveWorkout(
            workoutInstanceId: workoutInstanceId,
            request: request,
        )

        guard case let .success(detailsResponse) = result else {
            return
        }

        executionContext = WorkoutExecutionContext(
            workoutInstanceId: detailsResponse.workout.id,
            exerciseExecutionIDsByExerciseID: Dictionary(
                uniqueKeysWithValues: detailsResponse.exercises.map { ($0.exerciseId, $0.id) }
            ),
        )

        let refreshedSession = makeCanonicalSession(from: session, detailsResponse: detailsResponse)
        self.session = await sessionManager.replaceSession(refreshedSession)
    }

    private func buildSyncRequest(from session: WorkoutSessionState) -> ActiveWorkoutSyncRequest {
        let exercises = session.workoutDetails.exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .enumerated()
            .compactMap { _, workoutExercise -> ActiveWorkoutSyncExerciseRequest? in
                guard let exerciseState = session.exercises.first(where: { $0.exerciseId == workoutExercise.id }) else {
                    return nil
                }

                return ActiveWorkoutSyncExerciseRequest(
                    id: executionContext?.exerciseExecutionIDsByExerciseID[workoutExercise.id],
                    exerciseId: workoutExercise.id,
                    repsMin: workoutExercise.repsMin,
                    repsMax: workoutExercise.repsMax,
                    targetRpe: workoutExercise.targetRpe,
                    restSeconds: workoutExercise.restSeconds,
                    notes: workoutExercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    progressionPolicyId: nil,
                    sets: exerciseState.sets.map { set in
                        ActiveWorkoutSyncSetRequest(
                            id: nil,
                            weight: WorkoutSetInputFormatting.parseWeight(set.weightText),
                            reps: WorkoutSetInputFormatting.parseWholeNumber(set.repsText),
                            rpe: WorkoutSetInputFormatting.parseWholeNumber(set.rpeText),
                            isCompleted: set.isCompleted,
                            isWarmup: set.isWarmup,
                            restSecondsActual: nil,
                        )
                    },
                )
            }

        return ActiveWorkoutSyncRequest(exercises: exercises)
    }

    private func makeCanonicalSession(
        from session: WorkoutSessionState,
        detailsResponse: AthleteWorkoutDetailsResponse,
    ) -> WorkoutSessionState {
        let canonicalWorkout = detailsResponse.asWorkoutDetailsModel()
        let canonicalExercises = canonicalWorkout.exercises.map { workoutExercise in
            let existingState = session.exercises.first(where: { $0.exerciseId == workoutExercise.id })
            return SessionExerciseState(
                exerciseId: workoutExercise.id,
                sets: detailsResponse.exercises
                    .first(where: { $0.exerciseId == workoutExercise.id })?
                    .sets?
                    .sorted(by: { $0.setNumber < $1.setNumber })
                    .map { set in
                        SessionSetState(
                            isCompleted: set.isCompleted,
                            repsText: set.reps.map(String.init) ?? "",
                            weightText: set.weight.map(WorkoutSetInputFormatting.formatWeight) ?? "",
                            rpeText: set.rpe.map(String.init) ?? "",
                            isWarmup: set.isWarmup ?? false,
                        )
                    }
                    ?? existingState?.sets
                    ?? Array(
                        repeating: SessionSetState(
                            isCompleted: false,
                            repsText: "",
                            weightText: "",
                            rpeText: "",
                            isWarmup: false,
                        ),
                        count: max(1, workoutExercise.sets),
                    ),
                isSkipped: existingState?.isSkipped ?? false,
            )
        }

        let resolvedCurrentIndex: Int = {
            guard let currentExercise = session.workoutDetails.exercises[safe: session.currentExerciseIndex] else {
                return min(session.currentExerciseIndex, max(0, canonicalWorkout.exercises.count - 1))
            }
            return canonicalWorkout.exercises.firstIndex(where: { $0.id == currentExercise.id })
                ?? min(session.currentExerciseIndex, max(0, canonicalWorkout.exercises.count - 1))
        }()

        return WorkoutSessionState(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
            workoutTitle: canonicalWorkout.title,
            workoutDetails: canonicalWorkout,
            source: session.source,
            startedAt: session.startedAt,
            currentExerciseIndex: resolvedCurrentIndex,
            lastUpdated: Date(),
            exercises: canonicalExercises,
            hasLocalOnlyStructuralChanges: false,
        )
    }

    private func flushPendingSetSyncOperations() async {
        pendingSetSyncFlushTask?.cancel()
        pendingSetSyncFlushTask = nil
        await syncCoordinator.retryNow(namespace: userSub)
        await refreshSyncStatusIndicator()
    }

    private func schedulePendingSetSyncFlush() {
        pendingSetSyncFlushTask?.cancel()
        pendingSetSyncFlushTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.flushPendingSetSyncOperations()
        }
    }

    private func refreshSyncStatusIndicator() async {
        if session?.hasLocalOnlyStructuralChanges == true {
            pendingSyncCount = 0
            syncStatus = .savedLocally
            FFLog.info(
                "workout-sync-indicator source=local_structure_only status=\(syncStatus.rawValue) pendingSyncCount=\(pendingSyncCount)",
            )
            return
        }

        let diagnostics = await syncCoordinator.diagnostics(namespace: userSub)
        pendingSyncCount = diagnostics.pendingCount

        if diagnostics.pendingCount > 0 {
            syncStatus = diagnostics.hasDelayedRetries ? .delayed : .savedLocally
            FFLog.info(
                "workout-sync-indicator source=local_outbox status=\(syncStatus.rawValue) pendingSyncCount=\(pendingSyncCount) hasDelayedRetries=\(diagnostics.hasDelayedRetries) lastSyncError=\(diagnostics.lastSyncError ?? "-")",
            )
            return
        }

        syncStatus = await syncCoordinator.resolveSyncIndicator(namespace: userSub)
        FFLog.info(
            "workout-sync-indicator source=resolved status=\(syncStatus.rawValue) pendingSyncCount=\(pendingSyncCount) hasDelayedRetries=\(diagnostics.hasDelayedRetries) lastSyncError=\(diagnostics.lastSyncError ?? "-")",
        )
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
        return WorkoutExerciseDisplayFormatting.compactLastPerformanceLine(
            setCount: sorted.count,
            repsValues: repsValues,
            weightValues: weightValues,
            isBodyweight: currentExerciseIsBodyweight,
        )
    }

    private func lastPerformanceLines(from response: AthleteExerciseLastPerformanceResponse) -> [String] {
        let sorted = response.sets.sorted(by: { $0.setNumber < $1.setNumber })
        return sorted.compactMap { set in
            WorkoutExerciseDisplayFormatting.detailedLastPerformanceLine(
                reps: set.reps,
                weight: set.weight,
                isBodyweight: currentExerciseIsBodyweight,
            )
        }
    }

    private func compactPRLine(from record: AthletePersonalRecord) -> String {
        let metric = record.metric?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let valueText = record.value.map(WorkoutSetInputFormatting.formatWeight) ?? "—"
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

    private func workoutExercise(from catalogItem: ExerciseCatalogItem, orderIndex: Int) -> WorkoutExercise {
        let defaults = catalogItem.draftDefaults ?? .standard
        return WorkoutExercise(
            id: catalogItem.id,
            name: catalogItem.name,
            description: catalogItem.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sets: max(1, defaults.sets),
            repsMin: defaults.repsMin,
            repsMax: defaults.repsMax,
            targetRpe: defaults.targetRpe,
            restSeconds: defaults.restSeconds,
            notes: defaults.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            orderIndex: orderIndex,
            isBodyweight: catalogItem.resolvedIsBodyweight,
            media: catalogItem.media,
        )
    }

    private var timerSoundEnabled: Bool {
        timerSoundEnabledValue
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

    private enum EditableSetField {
        case weight
        case reps
        case rpe
    }

    private func updateSetField(
        setIndex: Int,
        field: EditableSetField,
        rawValue: String,
    ) async {
        guard let currentExercise,
              let currentState = currentExerciseState?.sets[safe: setIndex],
              let session
        else {
            return
        }

        guard let normalizedValue = normalizedSetFieldValue(field: field, rawValue: rawValue) else {
            return
        }

        beginSecondaryEditingModeIfNeeded(for: setIndex)

        let previousValue: String = switch field {
        case .weight:
            currentState.weightText
        case .reps:
            currentState.repsText
        case .rpe:
            currentState.rpeText
        }

        guard previousValue != normalizedValue else { return }

        switch field {
        case .weight:
            self.session = await sessionManager.updateSetWeight(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                weight: normalizedValue,
            )
            ClientAnalytics.track(
                .weightChanged,
                properties: analyticsExerciseProperties(exerciseId: currentExercise.id),
            )
        case .reps:
            self.session = await sessionManager.updateSetReps(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                reps: normalizedValue,
            )
            if normalizedValue.isEmpty, currentState.isCompleted, let updatedSession = self.session {
                self.session = await sessionManager.toggleSetComplete(
                    updatedSession,
                    exerciseId: currentExercise.id,
                    setIndex: setIndex,
                )
                toastMessage = "Повторы очищены, подход снят с выполнения"
            }
            ClientAnalytics.track(
                .repsChanged,
                properties: analyticsExerciseProperties(exerciseId: currentExercise.id),
            )
        case .rpe:
            self.session = await sessionManager.updateSetRPE(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                rpe: normalizedValue,
            )
        }

        await syncCurrentSetIfNeeded(
            exerciseId: currentExercise.id,
            setIndex: setIndex,
            processImmediately: false,
        )
    }

    private func canLogSet(setIndex: Int) -> Bool {
        entryState(for: setIndex) == .complete
    }

    private func entryState(for setIndex: Int) -> SetEntryState {
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return .unavailable
        }

        let set = exerciseState.sets[setIndex]
        let hasReps = !set.repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if currentExerciseIsBodyweight {
            return hasReps ? .complete : .empty
        }

        let hasWeight = !set.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (hasWeight, hasReps) {
        case (true, true):
            return .complete
        case (false, false):
            return .empty
        default:
            return .partial
        }
    }

    private func requestEditing(setIndex: Int, field: EditableInputField) {
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return
        }

        beginSecondaryEditingModeIfNeeded(for: setIndex)
        editingTarget = EditingTarget(setIndex: setIndex, field: field, requestID: UUID())
    }

    private func beginSecondaryEditingModeIfNeeded(for setIndex: Int) {
        inlineEditingSetIndex = setIndex
        if setIndex == activeSetIndex {
            secondaryEditingSetIndex = nil
        } else {
            secondaryEditingSetIndex = setIndex
        }
    }

    private func clearInlineEditingState() {
        editingTarget = nil
        inlineEditingSetIndex = nil
        secondaryEditingSetIndex = nil
    }

    private enum LoggingValidationScope {
        case singleSet
        case allSets
    }

    private enum PrimaryActionMode {
        case done
        case log
        case advance
    }

    private enum SetEntryState {
        case unavailable
        case empty
        case partial
        case complete
    }

    private func preferredEditingField(for setIndex: Int) -> EditableInputField {
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return .reps
        }

        let set = exerciseState.sets[setIndex]
        let hasReps = !set.repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasWeight = !set.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !currentExerciseIsBodyweight, !hasWeight {
            return .weight
        }
        if !hasReps {
            return .reps
        }
        return .reps
    }

    private func validationMessage(for setIndex: Int, scope: LoggingValidationScope) -> String {
        guard let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return scope == .singleSet
                ? "Заполните подход перед логгированием"
                : "Заполните все подходы перед массовым логгированием"
        }

        let set = exerciseState.sets[setIndex]
        let hasReps = !set.repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasWeight = !set.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch (currentExerciseIsBodyweight, hasWeight, hasReps, scope) {
        case (true, _, false, .singleSet):
            return "Введите повторы перед логгированием"
        case (true, _, false, .allSets):
            return "Заполните повторы у всех подходов перед массовым логгированием"
        case (false, false, false, .singleSet):
            return "Введите вес и повторы перед логгированием"
        case (false, false, false, .allSets):
            return "Заполните вес и повторы у всех подходов перед массовым логгированием"
        case (false, false, true, .singleSet):
            return "Введите вес перед логгированием"
        case (false, false, true, .allSets):
            return "Заполните вес у всех подходов перед массовым логгированием"
        case (_, _, false, .singleSet):
            return "Введите повторы перед логгированием"
        case (_, _, false, .allSets):
            return "Заполните повторы у всех подходов перед массовым логгированием"
        default:
            return scope == .singleSet
                ? "Заполните подход перед логгированием"
                : "Заполните все подходы перед массовым логгированием"
        }
    }

    private func nextFocusIndex(afterCompleting setIndex: Int, in exerciseState: SessionExerciseState) -> Int? {
        if let nextForward = exerciseState.sets.indices.first(where: { $0 > setIndex && !exerciseState.sets[$0].isCompleted }) {
            return nextForward
        }
        return exerciseState.sets.indices.first(where: { !exerciseState.sets[$0].isCompleted })
    }

    private func normalizedSetFieldValue(field: EditableSetField, rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch field {
        case .weight:
            return WorkoutSetInputFormatting.normalizedWeightText(from: rawValue)
        case .reps:
            return WorkoutSetInputFormatting.normalizedRepsText(from: rawValue)
        case .rpe:
            return WorkoutSetInputFormatting.normalizedRPEText(from: rawValue)
        }
    }
}

struct WorkoutPlayerViewV2: View {
    @State var viewModel: WorkoutPlayerViewModel
    let onExit: () -> Void
    let onFinish: (WorkoutPlayerViewModel.CompletionSummary) -> Void
    var onResumeExisting: (ActiveWorkoutSession) -> Void = { _ in }
    var onBlockedBack: () -> Void = {}
    private let environment = AppEnvironment.from()

    @State private var isExerciseLoggingPresented = false
    @State private var isRestTimerExpanded = false
    @State private var isJumpListPresented = false
    @State private var isExerciseDetailsPresented = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FFColors.background,
                    FFColors.background.opacity(0.96),
                    FFColors.surface.opacity(0.9),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            if viewModel.isLoading {
                FFScreenSpinner()
            } else if let blockedSession = viewModel.blockedByActiveSession {
                blockedSessionCard(blockedSession)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FFSpacing.md) {
                        topPanel
                        workoutOverviewHero
                        exerciseQueueCard
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.top, FFSpacing.xs)
                    .padding(.bottom, FFSpacing.lg)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
        .fullScreenCover(item: $viewModel.exercisePickerFlow) { flow in
            NavigationStack {
                ExercisePickerView(
                    repository: viewModel.exercisePickerRepository,
                    suggestionsProvider: viewModel.exercisePickerSuggestions,
                    selectedExerciseIDs: viewModel.selectedExerciseIDs(for: flow),
                ) { exercises in
                    guard let exercise = exercises.first else { return }
                    Task { await viewModel.applyPickedExercise(exercise, flow: flow) }
                }
            }
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
                WorkoutExerciseDetailsSheet(exercise: exercise)
            }
        }
        .sheet(isPresented: $isExerciseLoggingPresented) {
            exerciseLoggingSheet
        }
        .onChange(of: isJumpListPresented) { _, isPresented in
            viewModel.setJumpNavigationActive(isPresented)
        }
        .overlay(alignment: .top) {
            if let message = viewModel.toastMessage {
                Text(message)
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
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

    private func blockedSessionCard(_ session: ActiveWorkoutSession) -> some View {
        VStack(spacing: FFSpacing.md) {
            Spacer()

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Уже есть активная тренировка")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Нельзя открыть вторую тренировку, пока текущая не завершена или не отменена.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            VStack(spacing: FFSpacing.sm) {
                FFButton(title: "Продолжить текущую", variant: .primary) {
                    onResumeExisting(session)
                }
                FFButton(title: "Назад", variant: .secondary) {
                    onBlockedBack()
                }
            }

            Spacer()
        }
        .padding(.horizontal, FFSpacing.md)
    }

    private var topPanel: some View {
        HStack(spacing: FFSpacing.sm) {
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(FFColors.surface.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FFColors.gray700.opacity(0.55), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть тренировку")

            Spacer(minLength: 0)

            headerMenu
        }
        .padding(.vertical, FFSpacing.xs)
    }

    private var workoutOverviewHero: some View {
        WorkoutOverviewHeroView(
            title: viewModel.title,
            subtitle: workoutOverviewSubtitle,
            durationChipTitle: estimatedWorkoutDurationMinutes.map { "~\($0) мин" },
        )
    }

    private var headerMenu: some View {
        Menu {
            Button("Добавить упражнение", systemImage: "plus.rectangle.on.rectangle") {
                viewModel.presentAddExerciseFlow()
            }

            Button("Завершить раньше", systemImage: "flag.checkered", role: .destructive) {
                viewModel.isFinishEarlyConfirmationPresented = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(width: 36, height: 36)
                .background(FFColors.surface.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FFColors.gray700.opacity(0.55), lineWidth: 1)
                }
        }
    }

    private var navigationCard: some View {
        VStack(spacing: FFSpacing.sm) {
            if viewModel.syncStatus == .delayed || viewModel.canRetrySync {
                FFCard {
                    HStack(spacing: FFSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FFColors.danger)
                        Text("Ошибка синхронизации")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                        Spacer(minLength: 0)
                        if viewModel.canRetrySync {
                            compactActionButton(title: "Повторить", systemImage: "arrow.clockwise") {
                                Task { await viewModel.flushPendingSyncNow() }
                            }
                        }
                    }
                }
            }

            WorkoutFlowNavigationView(
                progressLabel: viewModel.progressLabel,
                progressSummary: viewModel.progressSummary,
                items: viewModel.progressItems,
                previousTitle: viewModel.previousExerciseTitle,
                nextTitle: viewModel.nextExerciseTitle,
                canMoveToPrevious: viewModel.canMoveToPreviousExercise,
                canMoveToNext: viewModel.canMoveToNextExercise,
                onPrevious: { Task { await viewModel.prevExercise() } },
                onShowAll: { isJumpListPresented = true },
                onNext: { Task { await viewModel.nextExercise() } },
                onJumpToExercise: { exerciseID in
                    Task { await viewModel.jumpToExercise(exerciseID) }
                },
            )
        }
    }

    private var structureCard: some View {
        VStack(spacing: FFSpacing.sm) {
            WorkoutStructureActionsView(
                onAddExercise: viewModel.presentAddExerciseFlow,
                onReplaceExercise: viewModel.presentReplaceCurrentExerciseFlow,
            )

            if viewModel.showsLocalStructureNotice {
                FFCard {
                    Text("Структурные правки текущей сессии сохраняются локально и переживают возобновление, но серверный контракт пока не описывает их полную синхронизацию.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var setsCard: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack(spacing: FFSpacing.sm) {
                Text("ПОДХОД")
                    .frame(width: 72, alignment: .leading)

                if !viewModel.currentExerciseIsBodyweight {
                    Text("ВЕС (КГ)")
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Text("ПОВТОРЫ")
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .font(FFTypography.caption.weight(.bold))
            .foregroundStyle(FFColors.textSecondary)
            .padding(.horizontal, FFSpacing.sm)

            if let exerciseState = viewModel.currentExerciseState {
                VStack(spacing: FFSpacing.sm) {
                    ForEach(Array(exerciseState.sets.enumerated()), id: \.offset) { index, set in
                        WorkoutSetRowView(
                            editingTarget: viewModel.editingTarget,
                            index: index,
                            set: set,
                            isBodyweight: viewModel.currentExerciseIsBodyweight,
                            showsCopyAction: viewModel.canCopyPreviousSet(setIndex: index),
                            weightStepLabel: viewModel.weightStepLabel,
                            isFocused: viewModel.activeSetIndex == index,
                            showsRPE: viewModel.showsRPEControl && viewModel.activeSetIndex == index,
                            targetRPE: viewModel.currentExercise?.targetRpe,
                            canRemove: viewModel.canRemoveSet(setIndex: index),
                            onSelect: { viewModel.selectSet(index) },
                            onCopy: { Task { await viewModel.copyPreviousSet(setIndex: index) } },
                            onToggleWarmup: { Task { await viewModel.toggleWarmup(setIndex: index) } },
                            onRemove: { Task { await viewModel.removeSet(setIndex: index) } },
                            onRequestWeightEdit: { viewModel.requestEditWeight(index) },
                            onRequestRepsEdit: { viewModel.requestEditReps(index) },
                            onEditingEnded: { requestID in
                                viewModel.endEditing(requestID: requestID)
                            },
                            onWeightCommit: { value in
                                viewModel.beginInlineCommit()
                                Task {
                                    await viewModel.updateWeight(setIndex: index, input: value)
                                    await MainActor.run {
                                        viewModel.finishInlineCommit()
                                    }
                                }
                            },
                            onDecreaseWeight: { Task { await viewModel.decrementWeight(setIndex: index) } },
                            onIncreaseWeight: { Task { await viewModel.incrementWeight(setIndex: index) } },
                            onRepsCommit: { value in
                                viewModel.beginInlineCommit()
                                Task {
                                    await viewModel.updateReps(setIndex: index, input: value)
                                    await MainActor.run {
                                        viewModel.finishInlineCommit()
                                    }
                                }
                            },
                            onDecreaseReps: { Task { await viewModel.decrementReps(setIndex: index) } },
                            onIncreaseReps: { Task { await viewModel.incrementReps(setIndex: index) } },
                            onSelectRPE: { value in
                                viewModel.beginInlineCommit()
                                Task {
                                    await viewModel.updateRPE(setIndex: index, rpe: value)
                                    await MainActor.run {
                                        viewModel.finishInlineCommit()
                                    }
                                }
                            },
                            onInvalidInput: { field in
                                switch field {
                                case .weight:
                                    viewModel.toastMessage = "Проверьте значение веса"
                                case .reps:
                                    viewModel.toastMessage = "Введите целое число повторов"
                                }
                            },
                        )
                        .id(setRowID(index))
                    }
                }
            }

            WorkoutSetListActionsView(
                canDuplicateLastSet: viewModel.canDuplicateLastSet,
                onAddSet: { Task { await viewModel.addSet(duplicateLast: false) } },
                onDuplicateLastSet: { Task { await viewModel.addSet(duplicateLast: true) } },
            )
        }
    }

    private var exerciseQueueCard: some View {
        WorkoutExerciseQueueView(
            items: viewModel.progressItems,
            subtitlesByID: exerciseSubtitlesByID,
            thumbnailURLsByID: exerciseThumbnailURLsByID,
            onSelect: { exerciseID in
                Task {
                    await viewModel.jumpToExercise(exerciseID)
                    isExerciseLoggingPresented = true
                }
            },
            onReplace: { exerciseID in
                Task {
                    await viewModel.jumpToExercise(exerciseID)
                    viewModel.presentReplaceCurrentExerciseFlow()
                }
            },
            onReorder: { draggedId, targetId in
                Task {
                    await viewModel.reorderExercises(draggedId: draggedId, targetId: targetId)
                }
            }
        )
    }

    private var currentExerciseCard: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            if let last = viewModel.currentLastTimeText ?? viewModel.currentLastSets.first {
                Text("Прошлый раз: \(last)")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FFSpacing.xs) {
                    compactActionButton(title: "Как выполнять", systemImage: "play.fill") {
                        isExerciseDetailsPresented = true
                    }

                    Menu {
                        Button(viewModel.currentRestTimerEnabled ? "Выключить таймер" : "Включить таймер") {
                            viewModel.toggleCurrentExerciseRestTimer()
                        }
                        Divider()
                        ForEach(viewModel.restPresetOptions, id: \.self) { seconds in
                            Button(formattedRestTime(seconds)) {
                                viewModel.setCurrentExerciseRestTimer(seconds: seconds)
                            }
                        }
                    } label: {
                        compactActionLabel(title: viewModel.currentRestTimerChipTitle, systemImage: "timer")
                    }

                    compactActionButton(title: "История", systemImage: "clock") {
                        viewModel.openHistory()
                    }

                    compactActionButton(title: "Добавить", systemImage: "plus.rectangle.on.rectangle") {
                        viewModel.presentAddExerciseFlow()
                    }

                    compactActionButton(title: "Заменить", systemImage: "arrow.triangle.2.circlepath") {
                        viewModel.presentReplaceCurrentExerciseFlow()
                    }

                    if viewModel.canUseLastPerformance {
                        compactActionButton(title: "Как в прошлый раз", systemImage: "arrow.down.circle.fill") {
                            Task { await viewModel.useLastPerformance() }
                        }
                    }
                }
            }
        }
    }

    private var exerciseLoggingSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        FFColors.background,
                        FFColors.background.opacity(0.96),
                        FFColors.surface.opacity(0.9),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
                .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: FFSpacing.md) {
                            loggingHeader
                            currentExerciseCard
                            setsCard
                        }
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.top, FFSpacing.md)
                        .padding(.bottom, 104)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.activeSetIndex) { _, index in
                        guard let index else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(setRowID(index), anchor: .center)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                if viewModel.restTimer.isVisible {
                    restTimerBanner
                } else if viewModel.restTimer.completionMessage != nil {
                    restReadyBanner
                }
            }
            .safeAreaInset(edge: .bottom) { loggingBottomBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var loggingHeader: some View {
        HStack(spacing: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ЛОГГИРОВАНИЕ")
                    .font(FFTypography.caption.weight(.bold))
                    .foregroundStyle(FFColors.textSecondary)
                Text(viewModel.currentExercise?.name ?? "Упражнение")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(2)
            }

            Spacer(minLength: FFSpacing.sm)

            Button {
                isExerciseLoggingPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(FFColors.surface.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FFColors.gray700.opacity(0.55), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть логгирование упражнения")
        }
    }

    private var restTimerBanner: some View {
        WorkoutRestTimerControlsView(
            title: viewModel.restStatusTitle,
            detail: viewModel.nextStepSummary,
            remainingSeconds: viewModel.restTimer.remainingSeconds,
            isRunning: viewModel.restTimer.isRunning,
            isExpanded: $isRestTimerExpanded,
            presetSeconds: viewModel.restPresetOptions,
            onPauseResume: { viewModel.restTimer.pauseOrResume() },
            onSkip: { viewModel.restTimer.skip() },
            onAddTime: { viewModel.addRest(seconds: $0) },
            onReset: { viewModel.resetRestTimer() },
            onRestartWithPreset: { viewModel.restartRest(seconds: $0) },
        )
    }

    private var restReadyBanner: some View {
        WorkoutRestReadyView(
            title: viewModel.restCompletionTitle,
            detail: viewModel.restCompletionDetail,
            presetSeconds: viewModel.restPresetOptions,
            onAddTime: { viewModel.restartRest(seconds: $0) },
            onDismiss: viewModel.dismissRestCompletion,
        )
    }

    private var loggingBottomBar: some View {
        WorkoutPrimaryActionStrip(
            secondaryTitle: viewModel.secondaryActionTitle,
            primaryTitle: viewModel.primaryActionTitle,
            isSecondaryEnabled: viewModel.isSecondaryBottomActionEnabled,
            isPrimaryEnabled: viewModel.isPrimaryBottomActionEnabled,
            onSecondary: {
                performLoggingAction {
                    if viewModel.hasUncompletedSetsInCurrentExercise {
                        await viewModel.completeAllSets()
                    } else {
                        await viewModel.addSet(duplicateLast: false)
                    }
                }
            },
            onPrimary: {
                performPrimaryLoggingAction()
            },
        )
        .padding(.horizontal, FFSpacing.sm)
        .padding(.top, FFSpacing.sm)
        .padding(.bottom, FFSpacing.sm)
        .background(FFColors.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FFColors.gray700.opacity(0.45))
                .frame(height: 1)
        }
    }

    private func setRowID(_ index: Int) -> String {
        "set-row-\(index)"
    }

    private var workoutOverviewSubtitle: String {
        let exerciseCount = viewModel.activeWorkout.exercises.count
        let exerciseLabel = "\(exerciseCount) " + (exerciseCount == 1 ? "упражнение" : "упражнений")
        if let minutes = estimatedWorkoutDurationMinutes {
            return "\(exerciseLabel) • примерно \(minutes) мин"
        }
        return exerciseLabel
    }

    private var estimatedWorkoutDurationMinutes: Int? {
        let exercises = viewModel.activeWorkout.exercises
        guard !exercises.isEmpty else { return nil }

        let totalSeconds = exercises.reduce(0) { partialResult, exercise in
            let sets = max(1, exercise.sets)
            let restSeconds = max(0, exercise.restSeconds ?? 0)
            let executionSeconds = sets * 90
            let betweenSetsRest = max(0, sets - 1) * restSeconds
            return partialResult + executionSeconds + betweenSetsRest
        }

        guard totalSeconds > 0 else { return nil }
        return max(1, Int(ceil(Double(totalSeconds) / 60.0)))
    }

    private var exerciseSubtitlesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.activeWorkout.exercises.map { exercise in
            (exercise.id, queueSubtitle(for: exercise))
        })
    }

    private var exerciseThumbnailURLsByID: [String: URL] {
        Dictionary(uniqueKeysWithValues: viewModel.activeWorkout.exercises.compactMap { exercise in
            guard let url = (exercise.media ?? []).compactMap({ $0.resolvedURL(baseURL: environment.backendBaseURL) }).first else {
                return nil
            }
            return (exercise.id, url)
        })
    }

    private func formattedRestTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func performLoggingAction(_ action: @escaping @MainActor () async -> Void) {
        dismissKeyboard()
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            while await MainActor.run(body: { viewModel.pendingInlineCommitCount > 0 }) {
                try? await Task.sleep(for: .milliseconds(20))
            }
            await action()
        }
    }

    private func performPrimaryLoggingAction() {
        viewModel.beginPrimaryActionInteraction()
        dismissKeyboard()
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            while await MainActor.run(body: { viewModel.pendingInlineCommitCount > 0 }) {
                try? await Task.sleep(for: .milliseconds(20))
            }
            await viewModel.primaryBottomAction()
            await MainActor.run {
                viewModel.endPrimaryActionInteraction()
            }
        }
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
        FFCompactActionButton(title: title, systemImage: systemImage, action: action)
    }

    private func compactActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(FFColors.textPrimary)
            .frame(minHeight: 44)
            .padding(.horizontal, FFSpacing.sm)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control, style: .continuous)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
    }

    private func compactBottomButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        FFCompactActionButton(title: title, systemImage: systemImage, action: action)
    }

    private func bottomActionButton(
        title: String,
        variant: FFButton.Variant,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.body.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(variant == .primary ? FFColors.textOnEmphasis : FFColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, FFSpacing.sm)
                .background(
                    variant == .primary
                        ? LinearGradient(colors: [FFColors.primary, FFColors.primary.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [FFColors.surface, FFColors.surface], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    if variant == .secondary {
                        RoundedRectangle(cornerRadius: 18)
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

    private func queueSubtitle(for exercise: WorkoutExercise) -> String {
        var parts: [String] = ["\(max(1, exercise.sets)) подхода"]

        if let repsText = repsRangeText(for: exercise) {
            parts.append(repsText)
        }

        if !exercise.isBodyweight,
           let weightText = firstLoggedWeightText(for: exercise.id) {
            parts.append("\(weightText) кг")
        }

        return parts.joined(separator: " • ")
    }

    private func repsRangeText(for exercise: WorkoutExercise) -> String? {
        if let min = exercise.repsMin, let max = exercise.repsMax {
            return min == max ? "\(min) повторов" : "\(min)-\(max) повторов"
        }
        if let min = exercise.repsMin {
            return "\(min) повторов"
        }
        if let max = exercise.repsMax {
            return "\(max) повторов"
        }
        return nil
    }

    private func firstLoggedWeightText(for exerciseID: String) -> String? {
        guard let exerciseState = viewModel.session?.exercises.first(where: { $0.exerciseId == exerciseID }) else {
            return nil
        }

        return exerciseState.sets
            .map(\.weightText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
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
        FFCompactActionButton(title: title, subtitle: subtitle, systemImage: systemImage, action: action)
    }
}

struct WorkoutExerciseDetailsSheet: View {
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
    @State private var presentedMedia: ResolvedExerciseMedia?

    var body: some View {
        Button {
            presentedMedia = media
        } label: {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                switch media.type {
                case .image:
                    AsyncImage(url: media.url) { phase in
                        switch phase {
                        case let .success(image):
                            ZStack {
                                FFColors.surface
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(FFSpacing.xs)
                            }
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
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))

                case .video:
                    ExerciseVideoCard(url: media.url, showsExpandHint: true)
                }

                HStack(spacing: FFSpacing.xs) {
                    Image(systemName: media.type == .video ? "play.rectangle" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text(media.type == .video ? "Открыть видео" : "Открыть изображение")
                        .font(FFTypography.caption.weight(.semibold))
                }
                .foregroundStyle(FFColors.accent)
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $presentedMedia) { item in
            ExerciseMediaViewer(media: item)
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
    var showsExpandHint = false
    @State private var player: AVPlayer

    init(url: URL, showsExpandHint: Bool = false) {
        self.url = url
        self.showsExpandHint = showsExpandHint
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))

            if showsExpandHint {
                Label("Развернуть", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, FFSpacing.sm)
                    .padding(.vertical, FFSpacing.xs)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(FFSpacing.sm)
            }
        }
        .onDisappear {
            player.pause()
        }
    }
}

private struct ExerciseMediaViewer: View {
    let media: ResolvedExerciseMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch media.type {
                case .image:
                    ZoomableExerciseImage(url: media.url)
                case .video:
                    ExerciseVideoCard(url: media.url)
                        .padding(.horizontal, FFSpacing.md)
                }
            }
            .navigationTitle(media.type == .video ? "Видео" : "Изображение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ZoomableExerciseImage: View {
    let url: URL

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: proxy.size.width,
                                maxHeight: proxy.size.height
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        ZStack {
                            Color.black
                            VStack(spacing: FFSpacing.xs) {
                                Image(systemName: "photo")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("Изображение недоступно")
                                    .font(FFTypography.body)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    case .empty:
                        ZStack {
                            Color.black
                            ProgressView()
                                .tint(.white)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
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
            capsuleButton(title: "Пропустить", tint: FFColors.danger, usesEmphasisForeground: true, action: onSkip)
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
                capsuleButton(title: "Пропустить", tint: FFColors.danger, usesEmphasisForeground: true, action: onSkip)
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

    private func capsuleButton(
        title: String,
        tint: Color,
        usesEmphasisForeground: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        FFCapsuleButton(
            title: title,
            style: .filled(tint),
            foreground: usesEmphasisForeground ? FFColors.textOnEmphasis : FFColors.textPrimary,
            action: action,
        )
    }

    private func timerChip(title: String, action: @escaping () -> Void) -> some View {
        FFCapsuleButton(
            title: title,
            style: .subtle(FFColors.gray500),
            minHeight: 38,
            horizontalPadding: FFSpacing.sm,
            action: action,
        )
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
        .ffScreenBackground()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
