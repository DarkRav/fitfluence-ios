import Observation
import SwiftUI

@Observable
@MainActor
final class TrainingInsightsViewModel {
    private let userSub: String
    private let trainingStore: TrainingStore
    private let calendar: Calendar

    var isLoading = false
    var history: [CompletedWorkoutRecord] = []
    var selectedSource: WorkoutSource?
    var monthPlans: [TrainingDayPlan] = []
    var selectedMonth: Date = .init()

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

        history = await trainingStore.history(userSub: userSub, source: selectedSource, limit: 60)
        monthPlans = await trainingStore.plans(userSub: userSub, month: selectedMonth)
    }

    func selectSource(_ source: WorkoutSource?) async {
        selectedSource = source
        await reload()
    }

    var heatmapDays: [(Date, Int)] {
        let today = calendar.startOfDay(for: Date())
        let lookup = Dictionary(grouping: history) { calendar.startOfDay(for: $0.finishedAt) }
            .mapValues(\.count)

        return (0 ..< 84).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, lookup[day] ?? 0)
        }.reversed()
    }

    var monthGrid: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        return (0 ..< 42).compactMap { idx in
            calendar.date(byAdding: .day, value: idx, to: firstWeek.start)
        }
    }

    func dayStatus(_ date: Date) -> TrainingDayStatus? {
        let day = calendar.startOfDay(for: date)
        return monthPlans.first(where: { calendar.isDate($0.day, inSameDayAs: day) })?.status
    }
}

struct TrainingInsightsView: View {
    @State var viewModel: TrainingInsightsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                calendarCard
                heatmapCard
                historyCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Прогресс")
        .task {
            await viewModel.onAppear()
        }
    }

    private var calendarCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("Календарь")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    Button("Обновить") {
                        Task { await viewModel.reload() }
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: FFSpacing.xs) {
                    ForEach(viewModel.monthGrid, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let status = viewModel.dayStatus(day)
        return Text(day.formatted(.dateTime.day()))
            .font(FFTypography.caption)
            .foregroundStyle(FFColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(statusColor(status).opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted))")
    }

    private func statusColor(_ status: TrainingDayStatus?) -> Color {
        switch status {
        case .planned:
            FFColors.primary
        case .completed:
            FFColors.accent
        case .missed:
            FFColors.danger
        case nil:
            FFColors.gray700
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
                    Text("Пока нет завершённых тренировок.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    ForEach(viewModel.history.prefix(15)) { item in
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(item.workoutTitle)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(item.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                            Text(
                                "\(item.completedSets)/\(item.totalSets) подходов • \(max(1, item.durationSeconds / 60)) мин",
                            )
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var sourcePicker: some View {
        Menu {
            Button("Все") { Task { await viewModel.selectSource(nil) } }
            Button("По программе") { Task { await viewModel.selectSource(.program) } }
            Button("Freestyle") { Task { await viewModel.selectSource(.freestyle) } }
            Button("Шаблоны") { Task { await viewModel.selectSource(.template) } }
        } label: {
            Label("Фильтр", systemImage: "line.3.horizontal.decrease.circle")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.accent)
        }
    }
}

#Preview {
    NavigationStack {
        TrainingInsightsView(viewModel: TrainingInsightsViewModel(userSub: "preview"))
    }
}
