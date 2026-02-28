import Observation
import SwiftUI

enum HomePrimaryAction: Equatable {
    case continueSession(programId: String, workoutId: String)
    case startNext(programId: String, workoutId: String)
    case repeatLast(programId: String, workoutId: String)
    case openPicker
    case quickWorkout
}

struct HomeTodayWorkoutSnapshot: Equatable {
    let title: String
    let exerciseCount: Int
    let durationMinutes: Int?
    let focus: String
    let difficulty: String
    let equipment: String
    let lastCompletion: String
}

@Observable
@MainActor
final class HomeViewModel {
    private let sessionManager: WorkoutSessionManager
    private let cacheStore: CacheStore
    private let progressStore: WorkoutProgressStore
    private let programsClient: ProgramsClientProtocol?
    private let userSub: String
    private let calendar: Calendar

    var isLoading = false
    var activeSession: ActiveWorkoutSession?
    var activeProgramId: String?
    var activeProgramTitle: String?
    var nextWorkout: WorkoutSummary?
    var lastWorkout: WorkoutSummary?
    var todayWorkout: HomeTodayWorkoutSnapshot?
    var weeklySummary: WeeklyTrainingSummary?
    var completedWorkoutsCount = 0
    var totalWorkoutsCount = 0

    init(
        userSub: String,
        sessionManager: WorkoutSessionManager,
        cacheStore: CacheStore = CompositeCacheStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        programsClient: ProgramsClientProtocol? = nil,
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.sessionManager = sessionManager
        self.cacheStore = cacheStore
        self.progressStore = progressStore
        self.programsClient = programsClient
        self.calendar = calendar
    }

    var primaryTitle: String {
        if activeSession != nil {
            return "Продолжить тренировку"
        }
        if nextWorkout != nil {
            return "Начать следующую"
        }
        if lastWorkout != nil {
            return "Повторить последнюю"
        }
        return "Открыть каталог"
    }

    var primaryAction: HomePrimaryAction {
        if let activeSession {
            return .continueSession(programId: activeSession.programId, workoutId: activeSession.workoutId)
        }
        if let nextWorkout, let activeProgramId {
            return .startNext(programId: activeProgramId, workoutId: nextWorkout.id)
        }
        if let lastWorkout, let activeProgramId {
            return .repeatLast(programId: activeProgramId, workoutId: lastWorkout.id)
        }
        return .openPicker
    }

    var weeklyProgressTitle: String {
        guard let weeklySummary else {
            return "План недели недоступен"
        }
        return "\(weeklySummary.completed)/\(max(weeklySummary.planned + weeklySummary.completed, 1)) тренировок"
    }

    var streakTitle: String {
        "Серия: \(weeklySummary?.streakDays ?? 0) дн"
    }

    var programProgressTitle: String {
        guard totalWorkoutsCount > 0 else { return "Прогресс появится после старта программы" }
        return "Пройдено \(completedWorkoutsCount) из \(totalWorkoutsCount) тренировок"
    }

    func onAppear() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        activeSession = await sessionManager.latestActiveSession(userSub: userSub)
        let weekStart = startOfWeek(Date())
        weeklySummary = await sessionManager.weeklySummary(userSub: userSub, weekStart: weekStart)

        if let activeSession {
            activeProgramId = activeSession.programId
            await loadProgramContext(programId: activeSession.programId)
            return
        }

        let lastCompleted = await sessionManager.lastCompletedWorkout(userSub: userSub)
        if let lastCompleted {
            activeProgramId = lastCompleted.programId
            await loadProgramContext(programId: lastCompleted.programId)
            return
        }

        let cachedFirstPage = await cacheStore.get(
            "programs.list?q=&page=0",
            as: CatalogViewModel.CachedCatalogPage.self,
            namespace: userSub,
        )
        if let programId = cachedFirstPage?.cards.first?.id {
            activeProgramId = programId
            activeProgramTitle = cachedFirstPage?.cards.first?.title
            await loadProgramContext(programId: programId)
        }
    }

    private func loadProgramContext(programId: String) async {
        let cachedWorkouts = await cacheStore.get(
            "workouts.list:\(programId)",
            as: [WorkoutSummary].self,
            namespace: userSub,
        ) ?? []

        if !cachedWorkouts.isEmpty {
            await applyWorkouts(programId: programId, workouts: cachedWorkouts)
        }

        let cachedDetails = await cacheStore.get(
            "program.details:\(programId)",
            as: ProgramDetails.self,
            namespace: userSub,
        )
        if let cachedDetails {
            applyProgramDetails(cachedDetails)
        }

        if let programsClient {
            let detailsResult = await programsClient.getProgramDetails(programId: programId)
            if case let .success(details) = detailsResult {
                applyProgramDetails(details)
                await cacheStore.set("program.details:\(programId)", value: details, namespace: userSub, ttl: 60 * 30)

                let workouts = (details.workouts ?? [])
                    .sorted(by: { $0.dayOrder < $1.dayOrder })
                    .map { template in
                        WorkoutSummary(
                            id: template.id,
                            title: template.title?.trimmedNilIfEmpty ?? "Тренировка \(template.dayOrder)",
                            dayOrder: template.dayOrder,
                            exerciseCount: template.exercises?.count ?? 0,
                            estimatedDurationMinutes: estimateDuration(exercises: template.exercises ?? []),
                        )
                    }
                if !workouts.isEmpty {
                    await applyWorkouts(programId: programId, workouts: workouts)
                    await cacheStore.set(
                        "workouts.list:\(programId)",
                        value: workouts,
                        namespace: userSub,
                        ttl: 60 * 30,
                    )
                }
            }
        }
    }

    private func applyProgramDetails(_ details: ProgramDetails) {
        activeProgramTitle = details.title

        let goalsText = details.goals?.prefix(2).joined(separator: " • ") ?? "Силовая адаптация"
        let difficulty = details.currentPublishedVersion?.level?.trimmedNilIfEmpty ?? "Базовый"
        let equipment = details.currentPublishedVersion?.requirements?.equipmentSummary ?? "Оборудование: не указано"

        if let nextWorkout {
            let duration = nextWorkout.estimatedDurationMinutes
            todayWorkout = HomeTodayWorkoutSnapshot(
                title: nextWorkout.title,
                exerciseCount: nextWorkout.exerciseCount,
                durationMinutes: duration,
                focus: goalsText,
                difficulty: difficulty,
                equipment: equipment,
                lastCompletion: todayWorkout?.lastCompletion ?? "Ещё не выполняли",
            )
        } else {
            todayWorkout = HomeTodayWorkoutSnapshot(
                title: "Выберите тренировку",
                exerciseCount: 0,
                durationMinutes: nil,
                focus: goalsText,
                difficulty: difficulty,
                equipment: equipment,
                lastCompletion: "Ещё не выполняли",
            )
        }
    }

    private func applyWorkouts(programId: String, workouts: [WorkoutSummary]) async {
        guard !workouts.isEmpty else { return }

        let statuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: workouts.map(\.id),
        )

        completedWorkoutsCount = statuses.values.count(where: { $0 == .completed })
        totalWorkoutsCount = workouts.count

        if let inProgress = activeSession,
           let inProgressWorkout = workouts.first(where: { $0.id == inProgress.workoutId })
        {
            nextWorkout = inProgressWorkout
        } else if let planned = workouts.first(where: { (statuses[$0.id] ?? .notStarted) != .completed }) {
            nextWorkout = planned
        } else {
            nextWorkout = workouts.first
        }

        if let recent = await sessionManager.lastCompletedWorkout(userSub: userSub),
           let workout = workouts.first(where: { $0.id == recent.workoutId })
        {
            lastWorkout = workout
            let duration = max(1, recent.durationSeconds / 60)
            let volumeText = recent.volume > 0 ? " • объём \(Int(recent.volume)) кг" : ""
            todayWorkout = HomeTodayWorkoutSnapshot(
                title: nextWorkout?.title ?? workout.title,
                exerciseCount: nextWorkout?.exerciseCount ?? workout.exerciseCount,
                durationMinutes: nextWorkout?.estimatedDurationMinutes,
                focus: todayWorkout?.focus ?? "Силовая адаптация",
                difficulty: todayWorkout?.difficulty ?? "Базовый",
                equipment: todayWorkout?.equipment ?? "Оборудование: не указано",
                lastCompletion: "\(duration) мин\(volumeText)",
            )
        } else {
            lastWorkout = workouts.last
        }
    }

    private func estimateDuration(exercises: [ExerciseTemplate]) -> Int {
        let sets = exercises.reduce(0) { $0 + max(1, $1.sets) }
        return max(10, (sets * 90) / 60)
    }

    private func startOfWeek(_ date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}

struct HomeViewV2: View {
    @State var viewModel: HomeViewModel
    let onPrimaryAction: (HomePrimaryAction) -> Void
    let onOpenPlan: () -> Void
    let onOpenTemplates: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                hero
                todayWorkoutCard
                weekPlanCard
                activeProgramCard
                summaryCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .task {
            await viewModel.onAppear()
        }
        .navigationTitle("Сегодня")
    }

    private var hero: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                Text("Готово к тренировке")
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)

                if viewModel.isLoading {
                    FFLoadingState(title: "Готовим план")
                } else {
                    FFButton(title: viewModel.primaryTitle, variant: .primary) {
                        onPrimaryAction(viewModel.primaryAction)
                    }
                    FFButton(title: "Быстрая тренировка", variant: .secondary) {
                        onPrimaryAction(.quickWorkout)
                    }
                }
            }
        }
    }

    private var todayWorkoutCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Сегодняшняя тренировка")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if let snapshot = viewModel.todayWorkout {
                    Text(snapshot.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)

                    Text("Упражнений: \(snapshot.exerciseCount)\(durationText(snapshot.durationMinutes))")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Фокус: \(snapshot.focus)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Сложность: \(snapshot.difficulty)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text(snapshot.equipment)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Последнее выполнение: \(snapshot.lastCompletion)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.accent)
                } else {
                    Text("Подготовьте тренировку в плане или запустите быструю тренировку.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var weekPlanCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("План недели")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.weeklyProgressTitle)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.streakTitle)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.accent)
                if let summary = viewModel.weeklySummary {
                    Text("Пропущено: \(summary.missed)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var activeProgramCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Активная программа")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.activeProgramTitle ?? "Пока не выбрана")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.programProgressTitle)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(title: "Открыть план", variant: .secondary) {
                    onOpenPlan()
                }
                FFButton(title: "Шаблоны тренировок", variant: .secondary) {
                    onOpenTemplates()
                }
            }
        }
    }

    private var summaryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Режим данных")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Оффлайн: тренировка и прогресс сохраняются на устройстве.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func durationText(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        return " • ~\(minutes) мин"
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension [String: JSONValue] {
    var equipmentSummary: String {
        if case let .array(values)? = self["equipment"] {
            let equipment = values.compactMap { value -> String? in
                if case let .string(text) = value {
                    return text
                }
                return nil
            }
            if !equipment.isEmpty {
                return "Оборудование: " + equipment.joined(separator: ", ")
            }
        }

        if case let .string(value)? = self["equipment"] {
            return "Оборудование: \(value)"
        }

        return "Оборудование: не указано"
    }
}

#Preview("Home V2") {
    NavigationStack {
        HomeViewV2(
            viewModel: HomeViewModel(
                userSub: "athlete-1",
                sessionManager: WorkoutSessionManager(),
            ),
            onPrimaryAction: { _ in },
            onOpenPlan: {},
            onOpenTemplates: {},
        )
    }
}
