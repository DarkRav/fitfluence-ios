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

    struct WeekCounts: Equatable {
        let planned: Int
        let completed: Int
        let missed: Int

        var total: Int {
            planned + completed + missed
        }

        static let empty = WeekCounts(planned: 0, completed: 0, missed: 0)
    }

    private let userSub: String
    private let trainingStore: TrainingStore
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let calendar: Calendar

    var selectedMonth: Date = .init()
    var selectedDay: Date = .init()
    var isLoading = false
    var monthPlans: [TrainingDayPlan] = []
    var contextPlans: [TrainingDayPlan] = []
    var upcomingPlans: [TrainingDayPlan] = []
    var weekCounts: WeekCounts = .empty

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
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

        let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        let enrollmentId = await resolveActiveEnrollmentId()

        async let previousPlans = plansForMonth(previousMonth, enrollmentId: enrollmentId)
        async let selectedPlans = plansForMonth(selectedMonth, enrollmentId: enrollmentId)
        async let nextPlans = plansForMonth(nextMonth, enrollmentId: enrollmentId)

        let prevMonthPlans = await previousPlans
        monthPlans = await selectedPlans
        let nextMonthPlans = await nextPlans
        contextPlans = prevMonthPlans + monthPlans + nextMonthPlans
        upcomingPlans = contextPlans
        recalculateWeekCounts()
    }

    func selectDay(_ day: Date) async {
        selectedDay = calendar.startOfDay(for: day)
        recalculateWeekCounts()
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
        let anchor = calendar.startOfDay(for: selectedDay)
        return (0 ..< 7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: anchor) else { return nil }
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

    private func recalculateWeekCounts() {
        let start = weekStart(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let items = contextPlans.filter { plan in
            let day = calendar.startOfDay(for: plan.day)
            return day >= start && day < end
        }

        weekCounts = WeekCounts(
            planned: items.count(where: { $0.status == .planned }),
            completed: items.count(where: { $0.status == .completed }),
            missed: items.count(where: { $0.status == .missed }),
        )
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

    private func resolveActiveEnrollmentId() async -> String? {
        if let cached = await cacheStore.get(
            cacheKeys.activeEnrollment,
            as: ActiveEnrollmentProgressResponse.self,
            namespace: userSub,
        ) {
            return cached.enrollmentId
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            return nil
        }

        let result = await athleteTrainingClient.activeEnrollmentProgress()
        guard case let .success(progress) = result else {
            return nil
        }

        await cacheStore.set(cacheKeys.activeEnrollment, value: progress, namespace: userSub, ttl: 60 * 5)
        return progress.enrollmentId
    }

    private func plansForMonth(_ month: Date, enrollmentId: String?) async -> [TrainingDayPlan] {
        let localPlans = await trainingStore.plans(userSub: userSub, month: month)
        let cacheKey = cacheKeys.month(monthKey(for: month))
        var resolved = localPlans

        if let cached = await cacheStore.get(cacheKey, as: [TrainingDayPlan].self, namespace: userSub),
           !cached.isEmpty
        {
            resolved = merge(local: localPlans, remote: cached)
        }

        guard networkMonitor.currentStatus, let athleteTrainingClient else {
            return resolved
        }

        async let calendarResult = athleteTrainingClient.calendar(month: monthKey(for: month))
        async let scheduleResult: Result<AthleteEnrollmentScheduleResponse, APIError> = {
            guard let enrollmentId else { return .failure(.invalidURL) }
            return await athleteTrainingClient.enrollmentSchedule(enrollmentId: enrollmentId)
        }()

        var remotePlans: [TrainingDayPlan] = []

        if case let .success(calendarResponse) = await calendarResult {
            remotePlans.append(contentsOf: mapWorkouts(calendarResponse.workouts, month: month))
        }

        if case let .success(scheduleResponse) = await scheduleResult {
            remotePlans.append(contentsOf: mapWorkouts(scheduleResponse.workouts, month: month))
        }

        remotePlans = deduplicate(remotePlans)
        if !remotePlans.isEmpty {
            resolved = merge(local: localPlans, remote: remotePlans)
            await cacheStore.set(cacheKey, value: resolved, namespace: userSub, ttl: 60 * 10)
        }

        return resolved.sorted { $0.day < $1.day }
    }

    private func mapWorkouts(_ workouts: [AthleteWorkoutInstance], month: Date) -> [TrainingDayPlan] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        return workouts.compactMap { workout in
            guard let date = parseDate(workout.scheduledDate ?? workout.startedAt ?? workout.completedAt),
                  monthInterval.contains(date)
            else {
                return nil
            }

            return TrainingDayPlan(
                id: "remote-\(workout.id)",
                userSub: userSub,
                day: calendar.startOfDay(for: date),
                status: mapStatus(workout.status),
                programId: workout.programId?.trimmedNilIfEmpty,
                workoutId: workout.id,
                title: workout.title?.trimmedNilIfEmpty ?? "Тренировка",
                source: mapSource(workout.source),
            )
        }
    }

    private func merge(local: [TrainingDayPlan], remote: [TrainingDayPlan]) -> [TrainingDayPlan] {
        guard !remote.isEmpty else {
            return local
        }

        var merged = remote
        var existing = Set(remote.map(planSignature))

        for item in local {
            let key = planSignature(item)
            guard !existing.contains(key) else { continue }
            existing.insert(key)
            merged.append(item)
        }

        return merged.sorted { $0.day < $1.day }
    }

    private func deduplicate(_ plans: [TrainingDayPlan]) -> [TrainingDayPlan] {
        var deduped: [TrainingDayPlan] = []
        var seen = Set<String>()
        for plan in plans.sorted(by: { $0.day < $1.day }) {
            let key = planSignature(plan)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(plan)
        }
        return deduped
    }

    private func planSignature(_ plan: TrainingDayPlan) -> String {
        let date = calendar.startOfDay(for: plan.day)
        let workoutID = plan.workoutId ?? plan.id
        return "\(date.timeIntervalSince1970)::\(workoutID)"
    }

    private func mapStatus(_ status: AthleteWorkoutInstanceStatus?) -> TrainingDayStatus {
        switch status {
        case .completed:
            return .completed
        case .missed:
            return .missed
        case .abandoned:
            return .missed
        case .planned, .inProgress, .none:
            return .planned
        }
    }

    private func mapSource(_ source: AthleteWorkoutSource) -> WorkoutSource {
        switch source {
        case .program:
            return .program
        case .custom:
            return .freestyle
        }
    }

    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        if let withFractions = Self.iso8601WithFractions.date(from: value) {
            return withFractions
        }
        if let dateTime = Self.iso8601.date(from: value) {
            return dateTime
        }
        return Self.dateOnly.date(from: value)
    }

    private var cacheKeys: CacheKeys {
        CacheKeys()
    }

    private static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct CacheKeys {
        let activeEnrollment = "athlete.enrollment.active"

        func month(_ month: String) -> String {
            "athlete.plan.month.\(month)"
        }
    }
}

struct PlanScheduleScreen: View {
    @State var viewModel: PlanScheduleViewModel

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
                        message: "Запустите тренировку во вкладке «Тренировка» или проверьте календарь позже.",
                    )
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
                        title: "Всего",
                        value: "\(viewModel.weekCounts.total)",
                    )
                    summaryMetric(
                        title: "Выполнено",
                        value: "\(viewModel.weekCounts.completed)",
                    )
                    summaryMetric(
                        title: "Пропущено",
                        value: "\(viewModel.weekCounts.missed)",
                    )
                }
            }
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 88)
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
                Text("Тренировки на 7 дней")
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
        )
        .navigationTitle("План")
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
