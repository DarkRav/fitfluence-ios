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

struct HomePlannedWorkoutSnapshot: Equatable {
    let title: String
    let statusText: String
    let subtitle: String
    let programId: String?
    let workoutId: String?
}

@Observable
@MainActor
final class HomeViewModel {
    private let sessionManager: WorkoutSessionManager
    private let trainingStore: TrainingStore
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
    var plannedWorkoutToday: HomePlannedWorkoutSnapshot?
    var lastWorkoutSummary: String?

    init(
        userSub: String,
        sessionManager: WorkoutSessionManager,
        trainingStore: TrainingStore = LocalTrainingStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        programsClient: ProgramsClientProtocol? = nil,
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.sessionManager = sessionManager
        self.trainingStore = trainingStore
        self.cacheStore = cacheStore
        self.progressStore = progressStore
        self.programsClient = programsClient
        self.calendar = calendar
    }

    var primaryTitle: String {
        if activeSession != nil {
            return "Продолжить тренировку"
        }
        if plannedWorkoutToday?.workoutId != nil, plannedWorkoutToday?.programId != nil {
            return "Начать сегодняшнюю"
        }
        if nextWorkout != nil {
            return "Начать следующую"
        }
        if lastWorkout != nil {
            return "Повторить последнюю"
        }
        return "Быстрая тренировка"
    }

    var primarySubtitle: String {
        if activeSession != nil {
            return "Продолжайте с места остановки"
        }
        if let plannedWorkoutToday {
            return "\(plannedWorkoutToday.statusText): \(plannedWorkoutToday.title)"
        }
        if let nextWorkout {
            return "Следующая по программе: \(nextWorkout.title)"
        }
        return "Нет обязательных задач на сегодня"
    }

    var primaryAction: HomePrimaryAction {
        if let activeSession {
            return .continueSession(programId: activeSession.programId, workoutId: activeSession.workoutId)
        }
        if let plannedWorkoutToday,
           let programId = plannedWorkoutToday.programId,
           let workoutId = plannedWorkoutToday.workoutId
        {
            return .startNext(programId: programId, workoutId: workoutId)
        }
        if let nextWorkout, let activeProgramId {
            return .startNext(programId: activeProgramId, workoutId: nextWorkout.id)
        }
        if let lastWorkout, let activeProgramId {
            return .repeatLast(programId: activeProgramId, workoutId: lastWorkout.id)
        }
        return .quickWorkout
    }

    func onAppear() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        activeSession = await sessionManager.latestActiveSession(userSub: userSub)
        await loadTodayPlan()

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

    private func loadTodayPlan() async {
        let monthPlans = await trainingStore.plans(userSub: userSub, month: Date())
        let today = calendar.startOfDay(for: Date())
        guard let plan = monthPlans.first(where: { calendar.isDate($0.day, inSameDayAs: today) }) else {
            plannedWorkoutToday = nil
            return
        }

        let statusText = switch plan.status {
        case .planned:
            "Запланирована"
        case .completed:
            "Выполнена"
        case .missed:
            "Пропущена"
        }
        let sourceText = switch plan.source {
        case .program:
            "По программе"
        case .freestyle:
            "Своя тренировка"
        case .template:
            "По шаблону"
        }

        plannedWorkoutToday = HomePlannedWorkoutSnapshot(
            title: plan.title,
            statusText: statusText,
            subtitle: sourceText,
            programId: plan.programId,
            workoutId: plan.workoutId,
        )
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
        let equipment = "Оборудование: \(details.currentPublishedVersion?.requirements?.equipmentSummaryText ?? "не указано")"

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
            lastWorkoutSummary = "\(duration) мин\(volumeText)"
            todayWorkout = HomeTodayWorkoutSnapshot(
                title: nextWorkout?.title ?? workout.title,
                exerciseCount: nextWorkout?.exerciseCount ?? workout.exerciseCount,
                durationMinutes: nextWorkout?.estimatedDurationMinutes,
                focus: todayWorkout?.focus ?? "Силовая адаптация",
                difficulty: todayWorkout?.difficulty ?? "Базовый",
                equipment: todayWorkout?.equipment ?? "Оборудование: не указано",
                lastCompletion: lastWorkoutSummary ?? "Ещё не выполняли",
            )
        } else {
            lastWorkout = workouts.last
            lastWorkoutSummary = nil
        }
    }

    private func estimateDuration(exercises: [ExerciseTemplate]) -> Int {
        let sets = exercises.reduce(0) { $0 + max(1, $1.sets) }
        return max(10, (sets * 90) / 60)
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
                lastActivityCard
                quickActionsCard
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
                Text("Сегодня")
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.primarySubtitle)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                if viewModel.isLoading {
                    FFLoadingState(title: "Готовим экран")
                } else {
                    FFButton(title: viewModel.primaryTitle, variant: .primary) {
                        onPrimaryAction(viewModel.primaryAction)
                    }
                }
            }
        }
    }

    private var todayWorkoutCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Сегодня по плану")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if let planned = viewModel.plannedWorkoutToday {
                    Text(planned.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text("\(planned.statusText) • \(planned.subtitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    Text("На сегодня нет запланированной тренировки.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }

                FFButton(title: "Открыть план", variant: .secondary) {
                    onOpenPlan()
                }
            }
        }
    }

    private var lastActivityCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Последняя активность")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if let lastWorkout = viewModel.lastWorkout {
                    Text(lastWorkout.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(viewModel.lastWorkoutSummary ?? "Детали будут после первой тренировки")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)

                    if let programId = viewModel.activeProgramId {
                        FFButton(title: "Повторить последнюю", variant: .secondary) {
                            onPrimaryAction(.repeatLast(programId: programId, workoutId: lastWorkout.id))
                        }
                    }
                } else {
                    Text("После первой завершённой тренировки здесь появится быстрый повтор.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var quickActionsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Быстрый доступ")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                FFButton(title: "Быстрая тренировка", variant: .secondary) {
                    onPrimaryAction(.quickWorkout)
                }
                FFButton(title: "Шаблоны тренировок", variant: .secondary) {
                    onOpenTemplates()
                }
            }
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
