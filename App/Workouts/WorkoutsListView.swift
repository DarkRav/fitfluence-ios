import Observation
import SwiftUI

@Observable
final class WorkoutsListViewModel {
    private let programId: String
    private let userSub: String
    private let workoutsClient: WorkoutsClientProtocol
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore

    var workouts: [WorkoutSummary] = []
    var workoutStatuses: [String: WorkoutProgressStatus] = [:]
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?

    init(
        programId: String,
        userSub: String,
        workoutsClient: WorkoutsClientProtocol,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore()
    ) {
        self.programId = programId
        self.userSub = userSub
        self.workoutsClient = workoutsClient
        self.progressStore = progressStore
        self.cacheStore = cacheStore
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
            workoutIds: workouts.map(\.id)
        )
    }

    private var cacheKey: String {
        "workouts.list:\(programId)"
    }
}

struct WorkoutsListScreen: View {
    @State var viewModel: WorkoutsListViewModel
    let onWorkoutTap: (String) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.workouts.isEmpty {
                FFLoadingState(title: "Загружаем тренировки")
                    .padding(.horizontal, FFSpacing.md)
            } else if let error = viewModel.error, viewModel.workouts.isEmpty {
                FFErrorState(
                    title: error.title,
                    message: error.message,
                    retryTitle: "Повторить"
                ) {
                    Task { await viewModel.retry() }
                }
                .padding(.horizontal, FFSpacing.md)
            } else if viewModel.workouts.isEmpty {
                FFEmptyState(
                    title: "В этой программе пока нет тренировок",
                    message: "Как только тренировки появятся, они будут доступны на этом экране."
                )
                .padding(.horizontal, FFSpacing.md)
            } else {
                ScrollView {
                    VStack(spacing: FFSpacing.sm) {
                        if viewModel.isShowingCachedData {
                            FFCard {
                                Text("Оффлайн. Показаны сохранённые данные.")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.primary)
                            }
                        }

                        ForEach(viewModel.workouts) { workout in
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
            }
        }
        .background(FFColors.background)
        .task {
            await viewModel.onAppear()
        }
    }

    private func workoutCard(
        _ workout: WorkoutSummary,
        status: WorkoutProgressStatus,
        onTap: @escaping () -> Void
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
                    }

                    Spacer(minLength: FFSpacing.xs)
                    FFBadge(status: badgeStatus(for: status))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Тренировка \(workout.title)")
        .accessibilityHint("Открыть тренировку")
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
