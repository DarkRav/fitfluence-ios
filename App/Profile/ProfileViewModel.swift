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

    let userSub: String
    var isOnline: Bool
    var loadState: LoadState = .loading
    var isClearingCache = false
    var infoMessage: String?
    var settings: ProfileSettings = .default

    var displayName = "Атлет"
    var email = "Email не указан"
    var avatarInitials = "AT"
    var syncStatus = "Локальные данные на устройстве"
    var activeSession: ProfileSessionSnapshot?
    var diagnostics = ProfileDiagnosticsSnapshot(
        isOnline: false,
        cacheSizeLabel: "0.00 МБ",
        localStorageLabel: "0.00 МБ",
        versionLabel: "—",
        buildLabel: "—",
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
    ) {
        self.me = me
        self.userSub = userSub
        self.isOnline = isOnline
        self.trainingStore = trainingStore
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.settingsStore = settingsStore
        self.diagnosticsProvider = diagnosticsProvider
    }

    var syncStatusTitle: String {
        isOnline ? "Онлайн" : "Оффлайн"
    }

    var diagnosticsText: String {
        """
        Fitfluence iOS
        Пользователь: \(userSub)
        Статус сети: \(syncStatusTitle)
        Устройство: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        Версия: \(diagnostics.versionLabel) (\(diagnostics.buildLabel))
        Кэш: \(diagnostics.cacheSizeLabel)
        Локальные данные: \(diagnostics.localStorageLabel)
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

        do {
            settings = await settingsStore.load(userSub: userSub)
            settings.weightUnit = .kilograms
            await settingsStore.save(settings, userSub: userSub)

            let localBytes = await trainingStore.storageSizeBytes(userSub: userSub)
            let cacheBytes = await diagnosticsProvider.cacheSizeBytes(userSub: userSub)
            let activeSessionValue = await progressStore.latestActiveSession(userSub: userSub)

            displayName = resolvedDisplayName()
            email = me.email ?? "Email не указан"
            avatarInitials = initials(from: displayName)
            syncStatus = isOnline ? "Синхронизация включена" : "Локальные данные на устройстве"
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
            )

            loadState = .loaded
        } catch {
            loadState = .error(
                UserFacingError(
                    title: "Не удалось загрузить профиль",
                    message: "Повторите попытку. Локальные данные останутся на устройстве.",
                ),
            )
        }
    }

    func updateNetworkStatus(_ online: Bool) {
        isOnline = online
        syncStatus = online ? "Синхронизация включена" : "Локальные данные на устройстве"
        diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: online,
            cacheSizeLabel: diagnostics.cacheSizeLabel,
            localStorageLabel: diagnostics.localStorageLabel,
            versionLabel: diagnostics.versionLabel,
            buildLabel: diagnostics.buildLabel,
        )
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
        )
        infoMessage = "Кэш очищен. Прогресс тренировок сохранён."
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
        if session.source == .program, UUID(uuidString: session.programId) != nil, isOnline {
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

    private func resolvedDisplayName() -> String {
        if let email = me.email, !email.isEmpty {
            let username = email.split(separator: "@").first.map(String.init) ?? email
            return username.capitalized
        }
        if let subject = me.subject, !subject.isEmpty {
            return "Атлет \(subject.prefix(6))"
        }
        return "Атлет"
    }

    private func initials(from value: String) -> String {
        let parts = value
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        if parts.isEmpty {
            return "AT"
        }
        return parts.joined()
    }

    private func formatBytes(_ bytes: Int) -> String {
        let value = Double(bytes) / (1024 * 1024)
        return String(format: "%.2f МБ", value)
    }
}
