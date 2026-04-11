import Observation
import SwiftUI

@Observable
final class WorkoutsListViewModel {
    enum SortMode: String, CaseIterable {
        case plan = "По плану"
        case title = "По названию"
        case duration = "По длительности"
    }

    private let programId: String
    private let userSub: String
    private let workoutsClient: WorkoutsClientProtocol
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore
    private let trainingStore: TrainingStore

    var workouts: [WorkoutSummary] = []
    var workoutStatuses: [String: WorkoutProgressStatus] = [:]
    var lastCompletionByWorkout: [String: Date] = [:]
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var sortMode: SortMode = .plan

    init(
        programId: String,
        userSub: String,
        workoutsClient: WorkoutsClientProtocol,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        trainingStore: TrainingStore = LocalTrainingStore(),
    ) {
        self.programId = programId
        self.userSub = userSub
        self.workoutsClient = workoutsClient
        self.progressStore = progressStore
        self.cacheStore = cacheStore
        self.trainingStore = trainingStore
    }

    @MainActor
    func onAppear() async {
        guard workouts.isEmpty, !isLoading else { return }
        isLoading = true
        error = nil
        await load(cachedFirst: true)
        isLoading = false
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        await load(cachedFirst: true)
        isRefreshing = false
    }

    @MainActor
    func retry() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        await load(cachedFirst: true)
        isLoading = false
    }

    @MainActor
    private func load(cachedFirst: Bool) async {
        if cachedFirst, let cached = await cacheStore.get(cacheKey, as: [WorkoutSummary].self, namespace: userSub) {
            workouts = cached
            isShowingCachedData = true
            await loadStatuses(for: cached)
        }

        let result = await workoutsClient.listWorkouts(for: programId)
        switch result {
        case let .success(workouts):
            self.workouts = workouts
            self.error = nil
            self.isShowingCachedData = false
            await cacheStore.set(cacheKey, value: workouts, namespace: userSub, ttl: 60 * 30)
            await loadStatuses(for: workouts)

        case let .failure(apiError):
            if apiError == .offline, !workouts.isEmpty {
                error = nil
                isShowingCachedData = true
                return
            }
            error = apiError.userFacing(context: .workoutsList)
        }
    }

    @MainActor
    private func loadStatuses(for workouts: [WorkoutSummary]) async {
        workoutStatuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: workouts.map(\.id),
        )
        let history = await trainingStore.history(userSub: userSub, source: nil, limit: 120)
            .filter { $0.programId == programId }
        lastCompletionByWorkout = Dictionary(
            history.map { ($0.workoutId, $0.finishedAt) },
            uniquingKeysWith: { lhs, rhs in
                max(lhs, rhs)
            },
        )
    }

    private var cacheKey: String {
        "workouts.list:\(programId)"
    }

    var sortedWorkouts: [WorkoutSummary] {
        switch sortMode {
        case .plan:
            workouts.sorted(by: { $0.dayOrder < $1.dayOrder })
        case .title:
            workouts.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        case .duration:
            workouts.sorted(by: { ($0.estimatedDurationMinutes ?? 0) > ($1.estimatedDurationMinutes ?? 0) })
        }
    }
}

struct WorkoutsListScreen: View {
    @State var viewModel: WorkoutsListViewModel
    let onWorkoutTap: (String) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.workouts.isEmpty {
                FFScreenStateLayout {
                    FFLoadingState(title: "Загружаем тренировки")
                        .frame(maxHeight: .infinity)
                }
            } else if let error = viewModel.error, viewModel.workouts.isEmpty {
                FFScreenStateLayout {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        fillsAvailableHeight: true,
                    ) {
                        Task { await viewModel.retry() }
                    }
                }
            } else if viewModel.workouts.isEmpty {
                FFScreenStateLayout {
                    FFEmptyState(
                        title: "В этой программе пока нет тренировок",
                        message: "Как только тренировки появятся, они будут доступны на этом экране.",
                        fillsAvailableHeight: true,
                    )
                }
            } else {
                ScrollView {
                    VStack(spacing: FFSpacing.sm) {
                        FFCard {
                            Text("Здесь можно посмотреть состав программы. Запуск тренировки доступен из календарного плана, чтобы порядок дней не ломался.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }

                        if viewModel.isShowingCachedData {
                            FFCard {
                                Text("Оффлайн. Показаны сохранённые данные.")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.primary)
                            }
                        }

                        ForEach(viewModel.sortedWorkouts) { workout in
                            workoutCard(workout, status: workoutStatus(for: workout)) {
                                onWorkoutTap(workout.id)
                            }
                        }
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.md)
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(WorkoutsListViewModel.SortMode.allCases, id: \.self) { mode in
                                Button(mode.rawValue) {
                                    viewModel.sortMode = mode
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .foregroundStyle(FFColors.accent)
                        }
                    }
                }
            }
        }
        .ffScreenBackground()
        .task {
            await viewModel.onAppear()
        }
    }

    private func workoutCard(
        _ workout: WorkoutSummary,
        status: WorkoutProgressStatus,
        onTap: @escaping () -> Void,
    ) -> some View {
        Button(action: onTap) {
            FFCard {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("День \(workout.dayOrder)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)

                        Text(workout.title)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .multilineTextAlignment(.leading)

                        Text(detailsText(workout: workout))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                        if let lastDate = viewModel.lastCompletionByWorkout[workout.id] {
                            Text("Последнее выполнение: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.accent)
                        }
                    }

                    Spacer(minLength: FFSpacing.xs)
                    FFBadge(status: badgeStatus(for: status))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Тренировка \(workout.title)")
        .accessibilityHint("Посмотреть список упражнений")
    }

    private func detailsText(workout: WorkoutSummary) -> String {
        if let duration = workout.estimatedDurationMinutes {
            return "Упражнений: \(workout.exerciseCount) • ~\(duration) мин"
        }
        return "Упражнений: \(workout.exerciseCount)"
    }

    private func workoutStatus(for workout: WorkoutSummary) -> WorkoutProgressStatus {
        viewModel.workoutStatuses[workout.id] ?? .notStarted
    }

    private func badgeStatus(for status: WorkoutProgressStatus) -> FFBadge.Status {
        switch status {
        case .notStarted:
            .notStarted
        case .inProgress:
            .inProgress
        case .completed:
            .completed
        }
    }
}
