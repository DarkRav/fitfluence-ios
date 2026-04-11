import Observation
import SwiftUI

@Observable
@MainActor
final class ProgramWorkoutHistoryViewModel {
    struct WorkoutTimelineItem: Identifiable {
        let workout: WorkoutSummary
        let status: WorkoutProgressStatus
        let completionRecords: [CompletedWorkoutRecord]

        var id: String {
            workout.id
        }

        var completionCount: Int {
            completionRecords.count
        }

        var lastCompletion: CompletedWorkoutRecord? {
            completionRecords.first
        }
    }

    private let programId: String
    let programTitle: String
    private let userSub: String
    private let workoutsClient: any WorkoutsClientProtocol
    private let progressStore: WorkoutProgressStore
    private let trainingStore: TrainingStore
    private let cacheStore: CacheStore

    var items: [WorkoutTimelineItem] = []
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?

    init(
        programId: String,
        programTitle: String,
        userSub: String,
        workoutsClient: any WorkoutsClientProtocol,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        trainingStore: TrainingStore = LocalTrainingStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
    ) {
        self.programId = programId
        self.programTitle = programTitle
        self.userSub = userSub
        self.workoutsClient = workoutsClient
        self.progressStore = progressStore
        self.trainingStore = trainingStore
        self.cacheStore = cacheStore
    }

    func onAppear() async {
        guard items.isEmpty, !isLoading else { return }
        isLoading = true
        error = nil
        await load(cachedFirst: true)
        isLoading = false
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        await load(cachedFirst: true)
        isRefreshing = false
    }

    func retry() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        await load(cachedFirst: true)
        isLoading = false
    }

    var completedCount: Int {
        items.count(where: { $0.status == .completed })
    }

    private func load(cachedFirst: Bool) async {
        if cachedFirst,
           let cached = await cacheStore.get(cacheKey, as: [WorkoutSummary].self, namespace: userSub)
        {
            await apply(workouts: cached)
            isShowingCachedData = true
        }

        let result = await workoutsClient.listWorkouts(for: programId)
        switch result {
        case let .success(workouts):
            await apply(workouts: workouts)
            await cacheStore.set(cacheKey, value: workouts, namespace: userSub, ttl: 60 * 30)
            isShowingCachedData = false
            error = nil

        case let .failure(apiError):
            if apiError == .offline, !items.isEmpty {
                isShowingCachedData = true
                error = nil
                return
            }
            error = apiError.userFacing(context: .workoutsList)
        }
    }

    private func apply(workouts: [WorkoutSummary]) async {
        let sorted = workouts.sorted(by: { $0.dayOrder < $1.dayOrder })
        let statuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: sorted.map(\.id),
        )
        let history = await trainingStore.history(userSub: userSub, source: .program, limit: 400)
            .filter { $0.programId == programId }
            .sorted(by: { $0.finishedAt > $1.finishedAt })
        let recordsByWorkout = Dictionary(grouping: history, by: \.workoutId)

        items = sorted.map { workout in
            let records = recordsByWorkout[workout.id] ?? []
            let status: WorkoutProgressStatus = records.isEmpty ? (statuses[workout.id] ?? .notStarted) : .completed
            return WorkoutTimelineItem(
                workout: workout,
                status: status,
                completionRecords: records,
            )
        }
    }

    private var cacheKey: String {
        "workouts.list:\(programId)"
    }
}

struct ProgramWorkoutHistoryScreen: View {
    @State var viewModel: ProgramWorkoutHistoryViewModel
    let onOpenWorkout: (String) -> Void
    let onOpenCompletedWorkout: (CompletedWorkoutRecord) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.items.isEmpty {
                FFLoadingState(title: "Загружаем прогресс программы")
                    .padding(.horizontal, FFSpacing.md)
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                FFErrorState(
                    title: error.title,
                    message: error.message,
                    retryTitle: "Повторить",
                ) {
                    Task { await viewModel.retry() }
                }
                .padding(.horizontal, FFSpacing.md)
            } else if viewModel.items.isEmpty {
                FFEmptyState(
                    title: "Тренировки не найдены",
                    message: "Когда программа загрузится, здесь появятся завершённые и предстоящие тренировки.",
                )
                .padding(.horizontal, FFSpacing.md)
            } else {
                ScrollView {
                    VStack(spacing: FFSpacing.sm) {
                        summaryCard

                        if viewModel.isShowingCachedData {
                            FFCard {
                                Text("Оффлайн. Показаны сохранённые данные.")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.primary)
                            }
                        }

                        ForEach(viewModel.items) { item in
                            workoutRow(item)
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
        .ffScreenBackground()
        .navigationTitle("Прогресс программы")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
        }
    }

    private var summaryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text(viewModel.programTitle)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(2)

                Text("\(viewModel.completedCount) / \(viewModel.items.count) тренировок")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(FFColors.gray700)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(FFColors.accent)
                            .frame(width: max(8, proxy.size.width * progressValue))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private func workoutRow(_ item: ProgramWorkoutHistoryViewModel.WorkoutTimelineItem) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("День \(item.workout.dayOrder)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)

                        Text(item.workout.title)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .multilineTextAlignment(.leading)

                        Text(detailsText(for: item))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: FFSpacing.xs)

                    FFBadge(status: badgeStatus(for: item.status))
                }

                if item.completionRecords.isEmpty {
                    Button {
                        onOpenWorkout(item.workout.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.status == .inProgress ? "Продолжить тренировку" : "Открыть тренировку")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(FFColors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Rectangle()
                        .fill(FFColors.gray700)
                        .frame(height: 1)
                        .padding(.vertical, FFSpacing.xxs)

                    ForEach(Array(item.completionRecords.enumerated()), id: \.element.id) { index, record in
                        Button {
                            onOpenCompletedWorkout(record)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
                                Text(record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)

                                Spacer(minLength: FFSpacing.xs)

                                Text("\(formattedDuration(record.durationSeconds)) • \(formattedVolume(record.volume)) кг")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < item.completionRecords.count - 1 {
                            Rectangle()
                                .fill(FFColors.gray700.opacity(0.7))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let totalSeconds = max(0, seconds)
        let minutes = totalSeconds / 60
        if minutes > 0 {
            return "\(minutes) мин"
        }
        return "\(totalSeconds) сек"
    }

    private func formattedVolume(_ volume: Double) -> String {
        if floor(volume) == volume {
            return "\(Int(volume))"
        }
        return String(format: "%.1f", volume)
    }
    
    private func detailsText(for item: ProgramWorkoutHistoryViewModel.WorkoutTimelineItem) -> String {
        let base: String
        if let duration = item.workout.estimatedDurationMinutes {
            base = "Упражнений: \(item.workout.exerciseCount) • ~\(duration) мин"
        } else {
            base = "Упражнений: \(item.workout.exerciseCount)"
        }

        if let latest = item.lastCompletion {
            return "\(base) • Выполнений: \(item.completionCount) • Последняя: \(shortDate(latest.finishedAt))"
        }

        return base
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

    private var progressValue: Double {
        guard !viewModel.items.isEmpty else { return 0 }
        let value = Double(viewModel.completedCount) / Double(viewModel.items.count)
        return min(max(value, 0), 1)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
