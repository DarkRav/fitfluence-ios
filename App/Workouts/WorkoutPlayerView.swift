import Foundation
import Observation
import SwiftUI
import UIKit

enum SyncStatusKind: String, Codable, Equatable, Sendable {
    case synced
    case savedLocally
    case delayed

    var title: String {
        switch self {
        case .synced:
            "Synced"
        case .savedLocally:
            "Saved locally"
        case .delayed:
            "Sync delayed"
        }
    }

    var defaultSubtitle: String {
        switch self {
        case .synced:
            "Все изменения на сервере"
        case .savedLocally:
            "Данные сохранены локально"
        case .delayed:
            "Синхронизация задерживается"
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
                    Text("cache")
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
                            Section("Trend") {
                                Text(trend)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        Section("Last 10") {
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
        let reps = entry.reps.map { "\($0) reps" } ?? "— reps"
        let weight = entry.weight.map { "@ \(formatWeight($0))kg" } ?? "@ —kg"
        return "\(reps) \(weight)"
    }

    private func entrySubtitle(_ entry: AthleteExerciseHistoryEntry) -> String {
        let dateText: String
        if let performedAt = parseDate(entry.performedAt) {
            dateText = performedAt.formatted(date: .abbreviated, time: .omitted)
        } else {
            dateText = "Дата неизвестна"
        }

        let volumeText = entry.volume.map { " • volume \(Int($0))" } ?? ""
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
    private var task: Task<Void, Never>?
    private var initialSeconds = 0

    var isVisible = false
    var isRunning = false
    var remainingSeconds = 0
    var onCompleted: (() -> Void)?

    deinit {
        task?.cancel()
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        task?.cancel()
        initialSeconds = seconds
        remainingSeconds = seconds
        isVisible = true
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.remainingSeconds > 0, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || !self.isRunning { break }
                self.remainingSeconds -= 1
            }
            if self.remainingSeconds == 0 {
                self.isVisible = false
                self.isRunning = false
                self.onCompleted?()
            }
        }
    }

    func pauseOrResume() {
        if isRunning {
            isRunning = false
            task?.cancel()
            task = nil
        } else {
            start(seconds: remainingSeconds)
        }
    }

    func add(seconds: Int) {
        guard seconds > 0 else { return }
        if !isVisible {
            start(seconds: seconds)
            return
        }

        task?.cancel()
        initialSeconds += seconds
        remainingSeconds += seconds
        isVisible = true
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.remainingSeconds > 0, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || !self.isRunning { break }
                self.remainingSeconds -= 1
            }
            if self.remainingSeconds == 0 {
                self.isVisible = false
                self.isRunning = false
                self.onCompleted?()
            }
        }
    }

    func skip() {
        task?.cancel()
        task = nil
        isVisible = false
        isRunning = false
        remainingSeconds = 0
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

    private var autoAdvanceUndoTask: Task<Void, Never>?
    private var networkObserverTask: Task<Void, Never>?

    private var lastPerformanceByExerciseId: [String: AthleteExerciseLastPerformanceResponse] = [:]
    private var personalRecordByExerciseId: [String: AthletePersonalRecord] = [:]
    private var insightsLoadedExerciseIDs: Set<String> = []

    var restTimer = RestTimerModel()
    var isLoading = false
    var isFinishEarlyConfirmationPresented = false
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
        isLastExercise ? "Complete workout" : "Next"
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

    func onAppear() async {
        isLoading = true
        session = await sessionManager.loadOrCreateSession(
            userSub: userSub,
            programId: programId,
            workout: workout,
            source: source,
        )
        isLoading = false

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
            if let rest = currentExercise.restSeconds {
                restTimer.start(seconds: rest)
            }
            await handleAutoAdvanceIfNeeded(exerciseId: currentExercise.id, completedSetIndex: setIndex)
        }
    }

    func incrementWeight(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: 2.5)
    }

    func decrementWeight(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: -2.5)
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
        await ensureCurrentExerciseContext()
    }

    func prevExercise() async {
        guard let session else { return }
        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex - 1)
        await ensureCurrentExerciseContext()
    }

    func skipExercise() async {
        guard let currentExercise, let session else { return }
        self.session = await sessionManager.skipExercise(session, exerciseId: currentExercise.id)
        toastMessage = "Упражнение пропущено"
    }

    func undoLastChange() async {
        guard let session else { return }
        self.session = await sessionManager.undo(session)
        autoAdvanceUndoTask?.cancel()
        autoAdvanceUndoTask = nil
        autoAdvanceUndoState = nil
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
        toastMessage = "Изменение отменено"
        await ensureCurrentExerciseContext()
    }

    func jumpToExercise(_ exerciseID: String) async {
        guard let targetIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let session
        else {
            return
        }
        self.session = await sessionManager.moveExercise(session, to: targetIndex)
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
            toastMessage = "Первый подход заполнен из Last time"
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

        toastMessage = "Подходы заполнены из Last time"
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

    func primaryBottomAction() async {
        if isLastExercise {
            await finish()
        } else {
            await nextExercise()
        }
    }

    func finish() async {
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
        isFinished = true
    }

    private func ensureCurrentExerciseContext() async {
        guard let exercise = currentExercise else { return }
        await ensureInsightsLoaded(for: exercise.id)
        await applySmartDefaultsIfNeeded(for: exercise)
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

        await syncCurrentSetIfNeeded(exerciseId: currentExercise.id, setIndex: setIndex)
    }

    private func handleAutoAdvanceIfNeeded(exerciseId: String, completedSetIndex: Int) async {
        guard !isJumpNavigationActive else {
            presentAutoAdvanceUndo(message: "Set marked complete", includesExerciseMove: false)
            return
        }

        guard let session,
              let exerciseState = session.exercises.first(where: { $0.exerciseId == exerciseId })
        else {
            return
        }

        let isLastSet = completedSetIndex >= exerciseState.sets.count - 1
        if !isLastSet {
            let nextSetNumber = completedSetIndex + 2
            presentAutoAdvanceUndo(
                message: "Set marked complete · Next set \(nextSetNumber)",
                includesExerciseMove: false,
            )
            return
        }

        if isLastExercise {
            presentAutoAdvanceUndo(message: "Set marked complete", includesExerciseMove: false)
            return
        }

        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex + 1)
        await ensureCurrentExerciseContext()
        presentAutoAdvanceUndo(message: "Set marked complete · Next exercise", includesExerciseMove: true)
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
            return "\(sorted.count)x\(reps) @ \(formatDouble(weight))kg"
        }

        if let first = sorted.first {
            let reps = first.reps.map(String.init) ?? "—"
            let weight = first.weight.map(formatDouble) ?? "—"
            return "\(sorted.count) sets • \(reps) reps @ \(weight)kg"
        }

        return nil
    }

    private func compactPRLine(from record: AthletePersonalRecord) -> String {
        let metric = record.metric?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "PR"
        let valueText = record.value.map(formatDouble) ?? "—"
        let unit = record.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if metric.contains("E1RM") {
            return "e1RM: \(valueText)\(unit.isEmpty ? "" : " \(unit)")"
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

    var body: some View {
        ZStack {
            FFColors.background.ignoresSafeArea()

            if viewModel.isLoading {
                FFLoadingState(title: "Открываем тренировку")
            } else {
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
                Task { await viewModel.finish() }
            }
        } message: {
            Text("Текущий прогресс сохранится в историю тренировки.")
        }
        .onChange(of: viewModel.isFinished) { _, isFinished in
            if isFinished, let summary = viewModel.completionSummary {
                onFinish(summary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.flushPendingSyncNow() }
        }
        .sheet(isPresented: $viewModel.isHistoryPresented) {
            HistoryBottomSheet(
                exerciseName: viewModel.currentExercise?.name ?? "History",
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
            NavigationStack {
                List(viewModel.progressItems) { item in
                    Button {
                        Task { await viewModel.jumpToExercise(item.id) }
                        isJumpListPresented = false
                    } label: {
                        HStack(spacing: FFSpacing.sm) {
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text(item.title)
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                Text("\(item.completedSets)/\(item.totalSets)")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                            Spacer(minLength: FFSpacing.sm)
                            if item.isCurrent {
                                FFBadge(status: .inProgress)
                            } else if item.isSkipped {
                                Text("Skipped")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.textSecondary)
                                    .padding(.horizontal, FFSpacing.xs)
                                    .padding(.vertical, FFSpacing.xxs)
                                    .background(FFColors.gray700)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Jump list")
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
                    Button("Undo") {
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

                    Text(prescription(for: exercise))
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FFSpacing.xs) {
                            if let lastTime = viewModel.currentLastTimeText {
                                ExerciseInsightPill(
                                    title: "Last time",
                                    value: lastTime,
                                    systemImage: "clock.arrow.circlepath",
                                    tint: FFColors.primary,
                                )
                            }

                            if let prText = viewModel.currentPRText {
                                ExerciseInsightPill(
                                    title: "PR",
                                    value: prText,
                                    systemImage: "bolt.fill",
                                    tint: FFColors.accent,
                                )
                            }
                        }
                    }

                    HStack(spacing: FFSpacing.xs) {
                        if viewModel.canUseLastPerformance {
                            compactActionButton(title: "Use last", systemImage: "arrow.down.circle.fill") {
                                Task { await viewModel.useLastPerformance() }
                            }
                        }

                        compactActionButton(title: "History", systemImage: "clock") {
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
                Text("Подтвердите подход. Дальше приложение подскажет следующий шаг автоматически.")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                if let exerciseState = viewModel.currentExerciseState {
                    ForEach(Array(exerciseState.sets.enumerated()), id: \.offset) { index, set in
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            HStack(spacing: FFSpacing.xs) {
                                Button {
                                    Task { await viewModel.toggleSetComplete(setIndex: index) }
                                } label: {
                                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(set.isCompleted ? FFColors.accent : FFColors.textSecondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Complete set \(index + 1)")

                                Text("Подход \(index + 1)")
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)

                                Spacer()

                                if set.isCompleted {
                                    FFBadge(status: .completed)
                                }

                                Button("Copy") {
                                    Task { await viewModel.copyPreviousSet(setIndex: index) }
                                }
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.accent)
                                .frame(minHeight: 44)
                            }

                            HStack(spacing: FFSpacing.sm) {
                                metricStepper(
                                    title: "Вес",
                                    value: set.weightText.isEmpty ? "0" : set.weightText,
                                    stepText: "2.5 кг",
                                    onMinus: { Task { await viewModel.decrementWeight(setIndex: index) } },
                                    onPlus: { Task { await viewModel.incrementWeight(setIndex: index) } },
                                )
                                metricStepper(
                                    title: "Повторы",
                                    value: set.repsText.isEmpty ? "0" : set.repsText,
                                    stepText: "1",
                                    onMinus: { Task { await viewModel.decrementReps(setIndex: index) } },
                                    onPlus: { Task { await viewModel.incrementReps(setIndex: index) } },
                                )
                            }
                        }
                        .padding(FFSpacing.sm)
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
    }

    private var restTimerBanner: some View {
        VStack(spacing: FFSpacing.xs) {
            FFCard(padding: FFSpacing.sm) {
                VStack(spacing: FFSpacing.xs) {
                    HStack(spacing: FFSpacing.xs) {
                        Label("Rest", systemImage: "timer")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textSecondary)

                        Spacer(minLength: FFSpacing.xs)

                        Text(formattedTime(viewModel.restTimer.remainingSeconds))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(FFColors.textPrimary)

                        Button {
                            viewModel.restTimer.pauseOrResume()
                        } label: {
                            Text(viewModel.restTimer.isRunning ? "Pause" : "Resume")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                                .padding(.horizontal, FFSpacing.xs)
                                .frame(minHeight: 36)
                                .background(FFColors.gray700)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.restTimer.skip()
                        } label: {
                            Text("Skip")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                                .padding(.horizontal, FFSpacing.xs)
                                .frame(minHeight: 36)
                                .background(FFColors.danger)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRestTimerExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isRestTimerExpanded ? "chevron.up" : "chevron.down")
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

                    if isRestTimerExpanded {
                        HStack(spacing: FFSpacing.xs) {
                            numericChip(title: "+15") { viewModel.addRest(seconds: 15) }
                            numericChip(title: "+30") { viewModel.addRest(seconds: 30) }
                            numericChip(title: "+60") { viewModel.addRest(seconds: 60) }
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

    private var bottomBar: some View {
        FFCard(padding: FFSpacing.sm) {
            VStack(spacing: FFSpacing.xs) {
                HStack(spacing: FFSpacing.xs) {
                    compactBottomButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                        Task { await viewModel.undoLastChange() }
                    }

                    compactBottomButton(title: "Jump list", systemImage: "list.bullet") {
                        isJumpListPresented = true
                    }

                    Menu {
                        Button("Skip exercise", systemImage: "forward.fill") {
                            Task { await viewModel.skipExercise() }
                        }

                        Button("Finish early", systemImage: "flag.checkered", role: .destructive) {
                            viewModel.isFinishEarlyConfirmationPresented = true
                        }
                    } label: {
                        HStack(spacing: FFSpacing.xxs) {
                            Image(systemName: "ellipsis.circle")
                            Text("More")
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
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .padding(.bottom, FFSpacing.sm)
        .background(FFColors.background.opacity(0.96))
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

    private func formattedTime(_ totalSeconds: Int) -> String {
        String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func numericChip(title: String, action: @escaping () -> Void) -> some View {
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

#Preview("Workout Player V2") {
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
