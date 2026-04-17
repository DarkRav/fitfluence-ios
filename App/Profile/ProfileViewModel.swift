import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ProfileViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case error(UserFacingError)
    }

    private let me: MeResponse
    private let trainingStore: TrainingStore
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore
    private let settingsStore: ProfileSettingsStore
    private let diagnosticsProvider: DiagnosticsProviding
    private let syncCoordinator: SyncCoordinator

    let userSub: String
    var isOnline: Bool
    var loadState: LoadState = .loading
    var isClearingCache = false
    var infoMessage: String?
    var settings: ProfileSettings = .default

    var displayName = "Атлет"
    var email = "Электронная почта не указана"
    var avatarInitials = "АТ"
    var syncStatus = SyncStatusKind.savedLocally.title
    var activeSession: ProfileSessionSnapshot?
    var diagnostics = ProfileDiagnosticsSnapshot(
        isOnline: false,
        cacheSizeLabel: "0.00 МБ",
        localStorageLabel: "0.00 МБ",
        versionLabel: "—",
        buildLabel: "—",
        pendingSyncOperations: 0,
        lastSyncAttemptLabel: "—",
        lastSyncError: nil,
    )

    init(
        me: MeResponse,
        userSub: String,
        isOnline: Bool,
        trainingStore: TrainingStore = LocalTrainingStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        settingsStore: ProfileSettingsStore = LocalProfileSettingsStore(),
        diagnosticsProvider: DiagnosticsProviding = DiagnosticsProvider(),
        syncCoordinator: SyncCoordinator = .shared,
    ) {
        self.me = me
        self.userSub = userSub
        self.isOnline = isOnline
        self.trainingStore = trainingStore
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.settingsStore = settingsStore
        self.diagnosticsProvider = diagnosticsProvider
        self.syncCoordinator = syncCoordinator
    }

    var syncStatusTitle: String {
        isOnline ? "Онлайн" : "Оффлайн"
    }

    var diagnosticsText: String {
        """
        Приложение тренировок
        Пользователь: \(userSub)
        Статус сети: \(syncStatusTitle)
        Устройство: \(UIDevice.current.model)
        Версия системы: \(UIDevice.current.systemVersion)
        Версия: \(diagnostics.versionLabel) (\(diagnostics.buildLabel))
        Кэш: \(diagnostics.cacheSizeLabel)
        Локальные данные: \(diagnostics.localStorageLabel)
        Операций в очереди синхронизации: \(diagnostics.pendingSyncOperations)
        Последняя попытка синхронизации: \(diagnostics.lastSyncAttemptLabel)
        Последняя ошибка синхронизации: \(diagnostics.lastSyncError ?? "—")
        """
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        loadState = .loading
        infoMessage = nil

        guard !userSub.isEmpty else {
            loadState = .error(
                UserFacingError(
                    title: "Профиль недоступен",
                    message: "Не удалось определить пользователя. Перезапустите сессию.",
                ),
            )
            return
        }

        settings = await settingsStore.load(userSub: userSub)
        settings.weightUnit = .kilograms
        await settingsStore.save(settings, userSub: userSub)

        let localBytes = await trainingStore.storageSizeBytes(userSub: userSub)
        let cacheBytes = await diagnosticsProvider.cacheSizeBytes(userSub: userSub)
        let activeSessionValue = await progressStore.latestActiveSession(userSub: userSub)

        displayName = resolvedDisplayName()
        email = me.email ?? "Электронная почта не указана"
        avatarInitials = initials(from: displayName)
        syncStatus = isOnline ? SyncStatusKind.synced.title : SyncStatusKind.savedLocally.title
        if let activeSessionValue, await canLaunch(session: activeSessionValue) {
            activeSession = buildActiveSession(activeSessionValue)
        } else {
            activeSession = nil
        }

        diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: isOnline,
            cacheSizeLabel: formatBytes(cacheBytes),
            localStorageLabel: formatBytes(localBytes),
            versionLabel: diagnosticsProvider.appVersion(),
            buildLabel: diagnosticsProvider.appBuild(),
            pendingSyncOperations: diagnostics.pendingSyncOperations,
            lastSyncAttemptLabel: diagnostics.lastSyncAttemptLabel,
            lastSyncError: diagnostics.lastSyncError,
        )
        await refreshSyncDiagnostics()

        loadState = .loaded
    }

    func updateNetworkStatus(_ online: Bool) {
        isOnline = online
        syncStatus = online ? SyncStatusKind.synced.title : SyncStatusKind.savedLocally.title
        diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: online,
            cacheSizeLabel: diagnostics.cacheSizeLabel,
            localStorageLabel: diagnostics.localStorageLabel,
            versionLabel: diagnostics.versionLabel,
            buildLabel: diagnostics.buildLabel,
            pendingSyncOperations: diagnostics.pendingSyncOperations,
            lastSyncAttemptLabel: diagnostics.lastSyncAttemptLabel,
            lastSyncError: diagnostics.lastSyncError,
        )
        Task {
            await refreshSyncDiagnostics()
        }
    }

    func persistSettings() async {
        settings.weightUnit = .kilograms
        await settingsStore.save(settings, userSub: userSub)
        infoMessage = "Настройки сохранены"
    }

    func clearCache() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        defer { isClearingCache = false }
        await diagnosticsProvider.clearCache(userSub: userSub)
        let cacheBytes = await diagnosticsProvider.cacheSizeBytes(userSub: userSub)
        diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: diagnostics.isOnline,
            cacheSizeLabel: formatBytes(cacheBytes),
            localStorageLabel: diagnostics.localStorageLabel,
            versionLabel: diagnostics.versionLabel,
            buildLabel: diagnostics.buildLabel,
            pendingSyncOperations: diagnostics.pendingSyncOperations,
            lastSyncAttemptLabel: diagnostics.lastSyncAttemptLabel,
            lastSyncError: diagnostics.lastSyncError,
        )
        infoMessage = "Кэш очищен. Прогресс тренировок сохранён."
    }

    func retrySyncNow() async {
        await syncCoordinator.retryNow(namespace: userSub)
        await refreshSyncDiagnostics()
        infoMessage = "Синхронизация запущена"
    }

    func exportSyncLog() async {
        let logText = await syncCoordinator.exportSyncLog(namespace: userSub)
        UIPasteboard.general.string = logText
        infoMessage = "Журнал синхронизации скопирован"
    }

    func resetActiveSession() async {
        guard let session = activeSession?.session else { return }
        guard var snapshot = await progressStore.load(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
        ) else {
            activeSession = nil
            return
        }

        snapshot.isFinished = true
        snapshot.currentExerciseIndex = nil
        snapshot.lastUpdated = Date()
        await progressStore.save(snapshot)
        activeSession = nil
        infoMessage = "Активная сессия сброшена"
    }

    private func buildActiveSession(_ session: ActiveWorkoutSession?) -> ProfileSessionSnapshot? {
        guard let session else { return nil }
        let subtitle = "Обновлено \(session.lastUpdated.formatted(date: .abbreviated, time: .shortened))"
        return ProfileSessionSnapshot(session: session, subtitle: subtitle)
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
            isOnline: isOnline,
            hasCachedWorkoutDetails: hasCachedWorkoutDetails,
            hasSnapshotDetails: hasSnapshotDetails,
        )
    }

    private func resolvedDisplayName() -> String {
        if let displayName = me.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        return "Атлет"
    }

    private func initials(from value: String) -> String {
        let parts = value
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        if parts.isEmpty {
            return "АТ"
        }
        return parts.joined()
    }

    private func formatBytes(_ bytes: Int) -> String {
        let value = Double(bytes) / (1024 * 1024)
        return String(format: "%.2f МБ", value)
    }

    private func refreshSyncDiagnostics() async {
        await syncCoordinator.activate(namespace: userSub)
        let snapshot = await syncCoordinator.diagnostics(namespace: userSub)
        let lastSyncAttemptLabel = snapshot.lastSyncAttemptAt.map {
            $0.formatted(
                date: Date.FormatStyle.DateStyle.abbreviated,
                time: Date.FormatStyle.TimeStyle.shortened,
            )
        } ?? "—"

        diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: diagnostics.isOnline,
            cacheSizeLabel: diagnostics.cacheSizeLabel,
            localStorageLabel: diagnostics.localStorageLabel,
            versionLabel: diagnostics.versionLabel,
            buildLabel: diagnostics.buildLabel,
            pendingSyncOperations: snapshot.pendingCount,
            lastSyncAttemptLabel: lastSyncAttemptLabel,
            lastSyncError: snapshot.lastSyncError,
        )
        if snapshot.pendingCount > 0 {
            syncStatus = snapshot.hasDelayedRetries ? SyncStatusKind.delayed.title : SyncStatusKind.savedLocally.title
            return
        }
        syncStatus = (await syncCoordinator.resolveSyncIndicator(namespace: userSub)).title
    }
}
