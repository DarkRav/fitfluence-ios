import Observation
import SwiftUI

@Observable
@MainActor
final class TrainingInsightsViewModel {
    enum RangeFilter: String, CaseIterable, Equatable, Sendable {
        case days30
        case days90
        case all

        var title: String {
            switch self {
            case .days30:
                "30 дн"
            case .days90:
                "90 дн"
            case .all:
                "Все"
            }
        }

        var days: Int? {
            switch self {
            case .days30:
                30
            case .days90:
                90
            case .all:
                nil
            }
        }
    }

    private let userSub: String
    private let trainingStore: TrainingStore
    private let calendar: Calendar

    var isLoading = false
    var allHistory: [CompletedWorkoutRecord] = []
    var selectedSource: WorkoutSource?
    var selectedRange: RangeFilter = .days90

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.calendar = calendar
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        allHistory = await trainingStore.history(userSub: userSub, source: selectedSource, limit: 365)
    }

    func selectSource(_ source: WorkoutSource?) async {
        selectedSource = source
        await reload()
    }

    func selectRange(_ range: RangeFilter) {
        selectedRange = range
    }

    var history: [CompletedWorkoutRecord] {
        guard let days = selectedRange.days else {
            return allHistory
        }
        let lowerBound = calendar
            .date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        return allHistory.filter { $0.finishedAt >= lowerBound }
    }

    var heatmapDays: [(Date, Int)] {
        let today = calendar.startOfDay(for: Date())
        let lookup = Dictionary(grouping: history) { calendar.startOfDay(for: $0.finishedAt) }
            .mapValues(\.count)

        return (0 ..< 84).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, lookup[day] ?? 0)
        }
        .reversed()
    }

    var totalWorkouts: Int {
        history.count
    }

    var totalMinutes: Int {
        history.reduce(0) { $0 + max(1, $1.durationSeconds / 60) }
    }

    var workoutsLast7Days: Int {
        let lowerBound = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
        return history.count(where: { $0.finishedAt >= lowerBound })
    }

    var totalVolume: Int {
        Int(history.reduce(0.0) { $0 + $1.volume })
    }
}

struct TrainingInsightsView: View {
    @State var viewModel: TrainingInsightsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                summaryCard
                heatmapCard
                historyCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Прогресс")
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private var summaryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("Сводка")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    rangeMenu
                }

                HStack(spacing: FFSpacing.sm) {
                    metricView(title: "Тренировок", value: "\(viewModel.totalWorkouts)")
                    metricView(title: "За 7 дней", value: "\(viewModel.workoutsLast7Days)")
                    metricView(title: "Минут", value: "\(viewModel.totalMinutes)")
                }

                if viewModel.totalVolume > 0 {
                    Text("Общий объём: \(viewModel.totalVolume) кг")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)
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

    private var heatmapCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Активность")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                    ForEach(viewModel.heatmapDays, id: \.0) { day, count in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(heatColor(for: count))
                            .frame(height: 16)
                            .accessibilityLabel(
                                "\(day.formatted(date: .numeric, time: .omitted)) — \(count) тренировок",
                            )
                    }
                }
            }
        }
    }

    private func heatColor(for count: Int) -> Color {
        switch count {
        case 0:
            FFColors.gray700
        case 1:
            FFColors.primary.opacity(0.45)
        case 2:
            FFColors.primary.opacity(0.7)
        default:
            FFColors.accent
        }
    }

    private var historyCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("История")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    sourcePicker
                }

                if viewModel.history.isEmpty {
                    FFEmptyState(
                        title: "Пока нет завершённых тренировок",
                        message: "Завершите первую тренировку, чтобы увидеть историю.",
                    )
                } else {
                    ForEach(viewModel.history) { item in
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(item.workoutTitle)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(
                                "\(sourceTitle(item.source)) • \(item.finishedAt.formatted(date: .abbreviated, time: .shortened))",
                            )
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            Text(
                                "\(item.completedSets)/\(item.totalSets) подходов • \(max(1, item.durationSeconds / 60)) мин",
                            )
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, FFSpacing.xxs)
                    }
                }
            }
        }
    }

    private var sourcePicker: some View {
        Menu {
            Button("Все") { Task { await viewModel.selectSource(nil) } }
            Button("По программе") { Task { await viewModel.selectSource(.program) } }
            Button("Своя тренировка") { Task { await viewModel.selectSource(.freestyle) } }
            Button("По шаблону") { Task { await viewModel.selectSource(.template) } }
        } label: {
            Label("Фильтр", systemImage: "line.3.horizontal.decrease.circle")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.accent)
        }
    }

    private var rangeMenu: some View {
        Menu {
            ForEach(TrainingInsightsViewModel.RangeFilter.allCases, id: \.self) { range in
                Button(range.title) {
                    viewModel.selectRange(range)
                }
            }
        } label: {
            Label(viewModel.selectedRange.title, systemImage: "calendar.badge.clock")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.accent)
        }
    }

    private func sourceTitle(_ source: WorkoutSource) -> String {
        switch source {
        case .program:
            "Программа"
        case .freestyle:
            "Своя тренировка"
        case .template:
            "Шаблон"
        }
    }
}

#Preview {
    NavigationStack {
        TrainingInsightsView(viewModel: TrainingInsightsViewModel(userSub: "preview"))
    }
}
