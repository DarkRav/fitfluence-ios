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
    private let userSub: String
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
    var todayCompletedWorkouts = 0
    var todayCompletedMinutes = 0
    var todayVolume: Int?
    var weekCompleted = 0
    var weekPlannedTotal = 0
    var streakDays = 0

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
        await loadTodayPlan()
        if let plannedWorkoutToday {
            canLaunchPlannedWorkout = await canLaunch(plannedWorkout: plannedWorkoutToday)
        } else {
            canLaunchPlannedWorkout = false
        }
        await loadTodayMetrics()

        if let activeSession {
            activeProgramId = activeSession.programId
            if activeSession.programId.isUUID {
                await loadProgramContext(programId: activeSession.programId)
            }
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
            status: plan.status,
            statusText: statusText,
            subtitle: sourceText,
            source: plan.source,
            programId: plan.programId,
            workoutId: plan.workoutId,
        )
    }

    private func loadTodayMetrics() async {
        let records = await trainingStore.history(userSub: userSub, source: nil, limit: 180)
        let today = calendar.startOfDay(for: Date())
        let todayRecords = records.filter { calendar.isDate($0.finishedAt, inSameDayAs: today) }

        todayCompletedWorkouts = todayRecords.count
        todayCompletedMinutes = todayRecords.reduce(0) { partial, record in
            partial + max(1, record.durationSeconds / 60)
        }
        let todayVolumeValue = Int(todayRecords.reduce(0) { $0 + $1.volume })
        todayVolume = todayVolumeValue > 0 ? todayVolumeValue : nil

        if let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start {
            let week = await trainingStore.weeklySummary(userSub: userSub, weekStart: weekStart)
            weekCompleted = week.completed
            weekPlannedTotal = week.completed + week.planned + week.missed
            streakDays = week.streakDays
        }
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

    private func canLaunch(session: ActiveWorkoutSession) async -> Bool {
        if session.source == .program, session.programId.isUUID {
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
        if programsClient != nil {
            return true
        }
        return await hasCachedWorkoutDetails(programId: programId, workoutId: workoutId)
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
                summaryCard
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

    private var summaryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Статус дня")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FFSpacing.xs) {
                    summaryMetric(
                        title: "Сегодня",
                        value: "\(viewModel.todayCompletedWorkouts)",
                        subtitle: "тренировок",
                    )
                    summaryMetric(
                        title: "Минуты",
                        value: "\(viewModel.todayCompletedMinutes)",
                        subtitle: "за день",
                    )
                    summaryMetric(
                        title: "Неделя",
                        value: viewModel
                            .weekPlannedTotal > 0 ? "\(viewModel.weekCompleted)/\(viewModel.weekPlannedTotal)" : "—",
                        subtitle: "выполнено",
                    )
                    summaryMetric(
                        title: "Серия",
                        value: "\(viewModel.streakDays)",
                        subtitle: "дней",
                    )
                }

                if let todayVolume = viewModel.todayVolume {
                    Text("Объём за сегодня: \(todayVolume) кг")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
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

    private func summaryMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(subtitle)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FFSpacing.sm)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
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
            ),
            onPrimaryAction: { _ in },
            onOpenPlan: {},
            onOpenTraining: {},
        )
    }
}
