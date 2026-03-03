import Foundation
import Observation

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
    private let calendar: Calendar

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

    var metrics: [ProfileMetricItem] = []
    var activeProgram: ProfileActiveProgramSnapshot?
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
        calendar: Calendar = .current,
    ) {
        self.me = me
        self.userSub = userSub
        self.isOnline = isOnline
        self.trainingStore = trainingStore
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.settingsStore = settingsStore
        self.diagnosticsProvider = diagnosticsProvider
        self.calendar = calendar
    }

    var hasActiveSession: Bool {
        activeSession != nil
    }

    var syncStatusTitle: String {
        if isOnline {
            return "Онлайн"
        }
        return "Оффлайн"
    }

    var diagnosticsText: String {
        """
        Fitfluence iOS
        Пользователь: \(userSub)
        Статус сети: \(syncStatusTitle)
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

            let history = await trainingStore.history(userSub: userSub, source: nil, limit: 365)
            let localBytes = await trainingStore.storageSizeBytes(userSub: userSub)
            let cacheBytes = await diagnosticsProvider.cacheSizeBytes(userSub: userSub)
            let activeSessionValue = await progressStore.latestActiveSession(userSub: userSub)

            let programId = activeSessionValue?.programId ?? history.first?.programId
            let details = await resolvedProgramDetails(programId: programId)

            displayName = resolvedDisplayName()
            email = me.email ?? "Email не указан"
            avatarInitials = initials(from: displayName)
            syncStatus = isOnline ? "Синхронизация включена" : "Локальные данные на устройстве"

            metrics = buildMetrics(history: history)
            activeProgram = await buildActiveProgram(programId: programId, details: details)
            activeSession = buildActiveSession(activeSessionValue)

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

    private func buildMetrics(history: [CompletedWorkoutRecord]) -> [ProfileMetricItem] {
        let total = history.count
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekItems = history.filter { $0.finishedAt >= weekAgo }
        let minutesInWeek = weekItems.reduce(0) { $0 + max(1, $1.durationSeconds / 60) }
        let streak = streakDays(history: history)

        return [
            ProfileMetricItem(id: "streak", title: "Серия", value: "\(streak)", subtitle: "дней подряд"),
            ProfileMetricItem(id: "week", title: "За 7 дней", value: "\(weekItems.count)", subtitle: "тренировок"),
            ProfileMetricItem(id: "total", title: "Всего", value: "\(total)", subtitle: "тренировок"),
            ProfileMetricItem(id: "time", title: "Время 7 дней", value: "\(minutesInWeek)", subtitle: "минут"),
        ]
    }

    private func streakDays(history: [CompletedWorkoutRecord]) -> Int {
        guard !history.isEmpty else { return 0 }
        let days = Set(history.map { calendar.startOfDay(for: $0.finishedAt) })
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func buildActiveSession(_ session: ActiveWorkoutSession?) -> ProfileSessionSnapshot? {
        guard let session else { return nil }
        let subtitle = "Обновлено \(session.lastUpdated.formatted(date: .abbreviated, time: .shortened))"
        return ProfileSessionSnapshot(session: session, subtitle: subtitle)
    }

    private func buildActiveProgram(
        programId: String?,
        details: ProgramDetails?,
    ) async -> ProfileActiveProgramSnapshot? {
        guard let details else {
            if let programId {
                return ProfileActiveProgramSnapshot(
                    programId: programId,
                    title: "Программа \(programId.prefix(6))",
                    completedWorkouts: nil,
                    totalWorkouts: nil,
                    nextWorkoutTitle: nil,
                    nextWorkoutSubtitle: nil,
                )
            }
            return nil
        }

        let workouts = (details.workouts ?? []).sorted(by: { $0.dayOrder < $1.dayOrder })
        guard let programId = programId ?? details.id as String? else {
            return ProfileActiveProgramSnapshot(
                programId: nil,
                title: details.title,
                completedWorkouts: nil,
                totalWorkouts: workouts.count,
                nextWorkoutTitle: workouts.first?.title,
                nextWorkoutSubtitle: nil,
            )
        }

        let statuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: workouts.map(\.id),
        )
        let completed = statuses.values.count(where: { $0 == .completed })
        let next = workouts.first(where: { statuses[$0.id] != .completed }) ?? workouts.first
        let nextDuration = estimatedDuration(for: next)

        return ProfileActiveProgramSnapshot(
            programId: programId,
            title: details.title,
            completedWorkouts: workouts.isEmpty ? nil : completed,
            totalWorkouts: workouts.isEmpty ? nil : workouts.count,
            nextWorkoutTitle: next?.title,
            nextWorkoutSubtitle: nextDuration,
        )
    }

    private func estimatedDuration(for workout: WorkoutTemplate?) -> String? {
        guard let workout else { return nil }
        let exerciseCount = workout.exercises?.count ?? 0
        guard exerciseCount > 0 else { return "Упражнения появятся после загрузки программы"
        }
        let minutes = max(10, exerciseCount * 4)
        return "\(exerciseCount) упражнений • ~\(minutes) мин"
    }

    private func resolvedProgramDetails(programId: String?) async -> ProgramDetails? {
        guard let programId else { return nil }
        return await cacheStore.get("program.details:\(programId)", as: ProgramDetails.self, namespace: userSub)
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
