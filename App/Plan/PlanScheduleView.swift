import Observation
import SwiftUI

@Observable
@MainActor
final class PlanScheduleViewModel {
    struct DayScheduleItem: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let source: WorkoutSource
        let status: TrainingDayStatus
    }

    struct UpcomingDayItem: Identifiable, Equatable {
        let id: Date
        let day: Date
        let status: TrainingDayStatus?
        let title: String
    }

    private let userSub: String
    private let trainingStore: TrainingStore
    private let calendar: Calendar

    var selectedMonth: Date = .init()
    var selectedDay: Date = .init()
    var isLoading = false
    var monthPlans: [TrainingDayPlan] = []
    var upcomingPlans: [TrainingDayPlan] = []
    var weekSummary: WeeklyTrainingSummary?

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.calendar = calendar
        selectedMonth = calendar.startOfDay(for: Date())
        selectedDay = calendar.startOfDay(for: Date())
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let today = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today

        async let selectedPlans = trainingStore.plans(userSub: userSub, month: selectedMonth)
        async let currentPlans = trainingStore.plans(userSub: userSub, month: today)
        async let nextPlans = trainingStore.plans(userSub: userSub, month: nextMonth)
        async let week = trainingStore.weeklySummary(
            userSub: userSub,
            weekStart: weekStart(for: selectedDay),
        )

        monthPlans = await selectedPlans
        upcomingPlans = await (currentPlans) + nextPlans
        weekSummary = await week
    }

    func selectDay(_ day: Date) async {
        selectedDay = calendar.startOfDay(for: day)
        weekSummary = await trainingStore.weeklySummary(
            userSub: userSub,
            weekStart: weekStart(for: selectedDay),
        )
    }

    func selectDayFromAdjacentMonth(_ day: Date) async {
        guard let targetMonth = calendar.dateInterval(of: .month, for: day)?.start else { return }
        selectedMonth = calendar.startOfDay(for: targetMonth)
        selectedDay = calendar.startOfDay(for: day)
        await reload()
    }

    func goToPreviousMonth() async {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else { return }
        selectedMonth = previous
        selectedDay = calendar.startOfDay(for: selectedMonth)
        await reload()
    }

    func goToNextMonth() async {
        guard let next = calendar.date(byAdding: .month, value: 1, to: selectedMonth) else { return }
        selectedMonth = next
        selectedDay = calendar.startOfDay(for: selectedMonth)
        await reload()
    }

    func jumpToToday() async {
        selectedMonth = calendar.startOfDay(for: Date())
        selectedDay = calendar.startOfDay(for: Date())
        await reload()
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: selectedMonth).capitalized
    }

    var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        let base = formatter.shortStandaloneWeekdaySymbols
            ?? formatter.shortWeekdaySymbols
            ?? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        guard !base.isEmpty else { return [] }
        let shift = max(0, calendar.firstWeekday - 1)
        let boundedShift = min(shift, base.count - 1)
        return Array(base[boundedShift...]) + Array(base[..<boundedShift])
    }

    var monthGrid: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        return (0 ..< 42).compactMap { index in
            calendar.date(byAdding: .day, value: index, to: firstWeek.start)
        }
    }

    func isInCurrentMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: selectedMonth, toGranularity: .month)
    }

    func dayStatus(_ day: Date) -> TrainingDayStatus? {
        let plans = plansForDay(in: monthPlans, day: day)
        return dayStatus(for: plans)
    }

    func dayItems(for day: Date) -> [DayScheduleItem] {
        let plans = plansForDay(in: monthPlans, day: day)
        let items = plans.map { plan in
            DayScheduleItem(
                id: "plan-\(plan.id)",
                title: plan.title,
                subtitle: sourceTitle(plan.source),
                source: plan.source,
                status: plan.status,
            )
        }
        return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var upcomingDays: [UpcomingDayItem] {
        let today = calendar.startOfDay(for: Date())
        return (0 ..< 7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let plans = plansForDay(in: upcomingPlans, day: day)
            guard !plans.isEmpty else { return nil }
            let status = dayStatus(for: plans)
            return UpcomingDayItem(
                id: day,
                day: day,
                status: status,
                title: upcomingTitle(from: plans),
            )
        }
    }

    func statusTitle(_ status: TrainingDayStatus?) -> String {
        switch status {
        case .planned:
            "Запланирована"
        case .completed:
            "Выполнена"
        case .missed:
            "Пропущена"
        case nil:
            "Нет статуса"
        }
    }

    func sourceTitle(_ source: WorkoutSource) -> String {
        switch source {
        case .program:
            "Программа"
        case .freestyle:
            "Своя тренировка"
        case .template:
            "Шаблон"
        }
    }

    private func weekStart(for date: Date) -> Date {
        let normalized = calendar.startOfDay(for: date)
        return calendar.dateInterval(of: .weekOfYear, for: normalized)?.start ?? normalized
    }

    private func plansForDay(in plans: [TrainingDayPlan], day: Date) -> [TrainingDayPlan] {
        let normalized = calendar.startOfDay(for: day)
        return plans.filter { calendar.isDate($0.day, inSameDayAs: normalized) }
    }

    private func dayStatus(for plans: [TrainingDayPlan]) -> TrainingDayStatus? {
        if plans.contains(where: { $0.status == .completed }) {
            return .completed
        }
        if plans.contains(where: { $0.status == .missed }) {
            return .missed
        }
        if plans.contains(where: { $0.status == .planned }) {
            return .planned
        }
        return nil
    }

    private func upcomingTitle(from plans: [TrainingDayPlan]) -> String {
        let sorted = plans.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        guard let first = sorted.first else { return "Тренировка" }
        let remaining = sorted.count - 1
        if remaining > 0 {
            return "\(first.title) + ещё \(remaining)"
        }
        return first.title
    }
}

struct PlanScheduleScreen: View {
    @State var viewModel: PlanScheduleViewModel
    let onOpenCatalog: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                calendarCard
                dayScheduleCard
                weekSummaryCard
                if !viewModel.upcomingDays.isEmpty {
                    upcomingCard
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.reload()
        }
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
                    headerControl(title: "Сегодня") {
                        Task { await viewModel.jumpToToday() }
                    }
                }

                HStack {
                    iconControl(systemName: "chevron.left") {
                        Task { await viewModel.goToPreviousMonth() }
                    }
                    Spacer()
                    Text(viewModel.monthTitle)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    iconControl(systemName: "chevron.right") {
                        Task { await viewModel.goToNextMonth() }
                    }
                }

                HStack(spacing: FFSpacing.xs) {
                    ForEach(Array(viewModel.weekdaySymbols.enumerated()), id: \.offset) { _, weekday in
                        Text(weekday)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: FFSpacing.xs), count: 7),
                    spacing: FFSpacing.xs,
                ) {
                    ForEach(viewModel.monthGrid, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: viewModel.selectedDay)
        let status = viewModel.dayStatus(day)

        return Button {
            Task {
                if viewModel.isInCurrentMonth(day) {
                    await viewModel.selectDay(day)
                } else {
                    await viewModel.selectDayFromAdjacentMonth(day)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(viewModel.isInCurrentMonth(day) ? FFColors.textPrimary : FFColors.gray500)
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .background(isSelected ? FFColors.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(isSelected ? FFColors.accent : FFColors.gray700.opacity(0.2), lineWidth: 1)
            }
            .opacity(viewModel.isInCurrentMonth(day) ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
        .accessibilityHint(viewModel.statusTitle(status))
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

    private var dayScheduleCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Расписание на \(viewModel.selectedDay.formatted(date: .abbreviated, time: .omitted))")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                let items = viewModel.dayItems(for: viewModel.selectedDay)
                if items.isEmpty {
                    FFEmptyState(
                        title: "На этот день тренировок нет",
                        message: "Добавьте программу из каталога или запустите тренировку во вкладке «Тренировка».",
                    )

                    FFButton(title: "Открыть каталог программ", variant: .secondary, action: onOpenCatalog)
                } else {
                    ForEach(items) { item in
                        infoRowContainer {
                            HStack(alignment: .top, spacing: FFSpacing.sm) {
                                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                    Text(item.title)
                                        .font(FFTypography.body.weight(.semibold))
                                        .foregroundStyle(FFColors.textPrimary)
                                    Text("\(item.subtitle) • \(viewModel.sourceTitle(item.source))")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                                Spacer(minLength: FFSpacing.xs)
                                statusPill(item.status)
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusPill(_ status: TrainingDayStatus) -> some View {
        Text(viewModel.statusTitle(status))
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(status == .completed ? FFColors.background : FFColors.textPrimary)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(statusColor(status).opacity(status == .completed ? 1 : 0.2))
            .clipShape(Capsule())
    }

    private var weekSummaryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Неделя")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                HStack(spacing: FFSpacing.sm) {
                    summaryMetric(
                        title: "Запланировано",
                        value: "\(viewModel.weekSummary?.planned ?? 0)",
                    )
                    summaryMetric(
                        title: "Выполнено",
                        value: "\(viewModel.weekSummary?.completed ?? 0)",
                    )
                    summaryMetric(
                        title: "Пропущено",
                        value: "\(viewModel.weekSummary?.missed ?? 0)",
                    )
                }
            }
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    private var upcomingCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Ближайшие 7 дней")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(viewModel.upcomingDays) { item in
                    infoRowContainer {
                        HStack(spacing: FFSpacing.sm) {
                            Text(item.day.formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textSecondary)
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text(item.title)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textPrimary)
                                    .lineLimit(1)
                                Text(viewModel.statusTitle(item.status))
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                            Spacer()
                            Circle()
                                .fill(statusColor(item.status))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
    }

    private func iconControl(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func headerControl(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(minHeight: 44)
                .padding(.horizontal, FFSpacing.sm)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func infoRowContainer(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
    }
}

#Preview("План") {
    NavigationStack {
        PlanScheduleScreen(
            viewModel: PlanScheduleViewModel(userSub: "preview-athlete"),
            onOpenCatalog: {},
        )
        .navigationTitle("План")
    }
}
