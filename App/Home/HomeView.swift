import Observation
import SwiftUI

enum HomePrimaryAction: Equatable {
    case continueSession(programId: String, workoutId: String)
    case startNext(programId: String, workoutId: String)
    case repeatLast(programId: String, workoutId: String)
    case openPicker
    case openTrainingHub
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
    let status: TrainingDayStatus
    let statusText: String
    let subtitle: String
    let source: WorkoutSource
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
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let userSub: String
    private let isOnline: Bool
    private let calendar: Calendar

    var isLoading = false
    var activeSession: ActiveWorkoutSession?
    var activeProgramId: String?
    var activeProgramTitle: String?
    var nextWorkout: WorkoutSummary?
    var lastWorkout: WorkoutSummary?
    var canLaunchPlannedWorkout = false
    var todayWorkout: HomeTodayWorkoutSnapshot?
    var plannedWorkoutToday: HomePlannedWorkoutSnapshot?
    var lastWorkoutSummary: String?

    init(
        userSub: String,
        sessionManager: WorkoutSessionManager,
        isOnline: Bool = true,
        trainingStore: TrainingStore = LocalTrainingStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        programsClient: ProgramsClientProtocol? = nil,
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.sessionManager = sessionManager
        self.trainingStore = trainingStore
        self.cacheStore = cacheStore
        self.progressStore = progressStore
        self.programsClient = programsClient
        self.athleteTrainingClient = athleteTrainingClient
        self.isOnline = isOnline
        self.calendar = calendar
    }

    var primaryTitle: String {
        if activeSession != nil {
            return "Продолжить тренировку"
        }
        if let plannedWorkoutToday,
           plannedWorkoutToday.source == .program,
           plannedWorkoutToday.status == .planned,
           canLaunchPlannedWorkout
        {
            return "Начать сегодняшнюю"
        }
        return "Открыть тренировку"
    }

    var primarySubtitle: String {
        if activeSession != nil {
            return "Продолжайте с места остановки"
        }
        if let plannedWorkoutToday {
            if plannedWorkoutToday.status == .completed {
                return "План дня выполнен. Можно перейти к дополнительной тренировке."
            }
            if plannedWorkoutToday.status == .missed {
                return "Тренировка на сегодня пропущена. Можно вернуть ритм во вкладке «Тренировка»."
            }
            if !canLaunchPlannedWorkout {
                return "Данные тренировки пока не загружены. Откройте тренировку из вкладки «Тренировка»."
            }
            return "\(plannedWorkoutToday.statusText): \(plannedWorkoutToday.title)"
        }
        return "Плана на сегодня нет. Во вкладке «Тренировка» доступны быстрый старт и шаблоны."
    }

    var primaryAction: HomePrimaryAction {
        if let activeSession {
            return .continueSession(programId: activeSession.programId, workoutId: activeSession.workoutId)
        }
        if let plannedWorkoutToday,
           plannedWorkoutToday.source == .program,
           plannedWorkoutToday.status == .planned,
           let programId = plannedWorkoutToday.programId,
           let workoutId = plannedWorkoutToday.workoutId,
           canLaunchPlannedWorkout
        {
            return .startNext(programId: programId, workoutId: workoutId)
        }
        return .openTrainingHub
    }

    func onAppear() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        if let session = await sessionManager.latestActiveSession(userSub: userSub),
           await canLaunch(session: session)
        {
            activeSession = session
        } else {
            activeSession = nil
        }
        await loadActiveEnrollmentContext()
        if plannedWorkoutToday == nil {
            await loadTodayPlan()
        }
        if let plannedWorkoutToday {
            canLaunchPlannedWorkout = await canLaunch(plannedWorkout: plannedWorkoutToday)
        } else {
            canLaunchPlannedWorkout = false
        }

        if let activeSession {
            activeProgramId = activeSession.programId
            if activeSession.programId.isUUID {
                await loadProgramContext(programId: activeSession.programId)
            }
            return
        }

        if let activeProgramId, activeProgramId.isUUID {
            await loadProgramContext(programId: activeProgramId)
            return
        }

        let lastCompleted = await sessionManager.lastCompletedWorkout(userSub: userSub)
        if let lastCompleted, lastCompleted.source == .program, lastCompleted.programId.isUUID {
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

    private func loadActiveEnrollmentContext() async {
        guard let athleteTrainingClient, isOnline else { return }

        let result = await athleteTrainingClient.activeEnrollmentProgress()
        switch result {
        case let .success(progress):
            guard let programId = progress.programId?.trimmedNilIfEmpty else { return }

            activeProgramId = programId
            activeProgramTitle = progress.programTitle?.trimmedNilIfEmpty

            if let nextWorkoutId = progress.nextWorkoutId?.trimmedNilIfEmpty {
                plannedWorkoutToday = HomePlannedWorkoutSnapshot(
                    title: progress.nextWorkoutTitle?.trimmedNilIfEmpty ?? "Следующая тренировка",
                    status: .planned,
                    statusText: "Запланирована",
                    subtitle: "Активная программа",
                    source: .program,
                    programId: programId,
                    workoutId: nextWorkoutId,
                )

                await loadWorkoutSnapshotFromInstance(workoutInstanceId: nextWorkoutId)
            } else {
                plannedWorkoutToday = nil
            }

            if let completed = progress.completedSessions, let total = progress.totalSessions, total > 0 {
                lastWorkoutSummary = "Прогресс программы: \(completed)/\(total)"
            }

        case .failure:
            break
        }
    }

    private func loadWorkoutSnapshotFromInstance(workoutInstanceId: String) async {
        guard let athleteTrainingClient else { return }

        let detailsResult = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId)
        guard case let .success(details) = detailsResult else { return }

        let exercises = details.exercises
        let durationFromServer = details.workout.durationSeconds.map { max(10, $0 / 60) }
        let estimatedDuration = durationFromServer ?? estimateDuration(exercises: exercises)
        let title = details.workout.title?.trimmedNilIfEmpty ?? "Тренировка"

        nextWorkout = WorkoutSummary(
            id: details.workout.id,
            title: title,
            dayOrder: 0,
            exerciseCount: exercises.count,
            estimatedDurationMinutes: estimatedDuration,
        )

        if let current = todayWorkout {
            todayWorkout = HomeTodayWorkoutSnapshot(
                title: title,
                exerciseCount: exercises.count,
                durationMinutes: estimatedDuration,
                focus: current.focus,
                difficulty: current.difficulty,
                equipment: current.equipment,
                lastCompletion: current.lastCompletion,
            )
        } else {
            todayWorkout = HomeTodayWorkoutSnapshot(
                title: title,
                exerciseCount: exercises.count,
                durationMinutes: estimatedDuration,
                focus: "По активной программе",
                difficulty: "Уровень уточняется",
                equipment: "Оборудование: уточняется",
                lastCompletion: "Ещё не выполняли",
            )
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
        case .inProgress:
            "В процессе"
        case .completed:
            "Выполнена"
        case .missed:
            "Пропущена"
        case .skipped:
            "Пропущена намеренно"
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
            status: plan.status,
            statusText: statusText,
            subtitle: sourceText,
            source: plan.source,
            programId: plan.programId,
            workoutId: plan.workoutId,
        )
    }

    private func loadProgramContext(programId: String) async {
        guard programId.isUUID else { return }

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

    private func estimateDuration(exercises: [AthleteExerciseExecution]) -> Int {
        let sets = exercises.reduce(0) { partial, exercise in
            partial + max(1, exercise.plannedSets ?? exercise.sets?.count ?? 1)
        }
        return max(10, (sets * 90) / 60)
    }

    private func canLaunch(session: ActiveWorkoutSession) async -> Bool {
        if session.source == .program, session.programId.isUUID, isOnline {
            return true
        }
        if await hasCachedWorkoutDetails(programId: session.programId, workoutId: session.workoutId) {
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

    private func canLaunch(plannedWorkout: HomePlannedWorkoutSnapshot) async -> Bool {
        guard plannedWorkout.source == .program,
              let programId = plannedWorkout.programId,
              let workoutId = plannedWorkout.workoutId,
              programId.isUUID
        else {
            return false
        }
        if programsClient != nil || athleteTrainingClient != nil, isOnline {
            return true
        }
        if await hasCachedWorkoutDetails(programId: programId, workoutId: workoutId) {
            return true
        }
        if let snapshot = await progressStore.load(userSub: userSub, programId: programId, workoutId: workoutId),
           snapshot.workoutDetails != nil
        {
            return true
        }
        return false
    }

    private func hasCachedWorkoutDetails(programId: String, workoutId: String) async -> Bool {
        await cacheStore.get(
            "workout.details:\(programId):\(workoutId)",
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) != nil
    }
}

struct HomeViewV2: View {
    @State var viewModel: HomeViewModel
    let onPrimaryAction: (HomePrimaryAction) -> Void
    let onOpenPlan: () -> Void
    let onOpenTraining: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                hero
                todayWorkoutCard
                focusCard
                trainingEntryCard
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

    @ViewBuilder
    private var focusCard: some View {
        if let todayWorkout = viewModel.todayWorkout {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Фокус следующей тренировки")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(todayWorkout.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(todayWorkout.focus)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text(todayWorkout.equipment)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var trainingEntryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Тренировка")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Быстрый старт, шаблоны, повтор и продолжение сессии находятся во вкладке «Тренировка».")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(title: "Открыть тренировку", variant: .secondary, action: onOpenTraining)
            }
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isUUID: Bool {
        UUID(uuidString: self) != nil
    }
}

#Preview("Home V2") {
    NavigationStack {
        HomeViewV2(
            viewModel: HomeViewModel(
                userSub: "athlete-1",
                sessionManager: WorkoutSessionManager(),
                isOnline: true,
            ),
            onPrimaryAction: { _ in },
            onOpenPlan: {},
            onOpenTraining: {},
        )
    }
}
