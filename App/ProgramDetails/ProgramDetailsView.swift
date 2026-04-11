import Observation
import SwiftUI

enum ProgramDetailsDisplayMode: Equatable, Sendable {
    case discovery
    case active
}

enum ProgramScheduleWeekday: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .monday: "Пн"
        case .tuesday: "Вт"
        case .wednesday: "Ср"
        case .thursday: "Чт"
        case .friday: "Пт"
        case .saturday: "Сб"
        case .sunday: "Вс"
        }
    }

    var title: String {
        switch self {
        case .monday: "Понедельник"
        case .tuesday: "Вторник"
        case .wednesday: "Среда"
        case .thursday: "Четверг"
        case .friday: "Пятница"
        case .saturday: "Суббота"
        case .sunday: "Воскресенье"
        }
    }

    var calendarWeekday: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }

    static func from(date: Date, calendar: Calendar) -> Self? {
        let weekday = calendar.component(.weekday, from: date)
        return allCases.first(where: { $0.calendarWeekday == weekday })
    }

    static func recommended(for frequency: Int) -> [Self] {
        switch max(1, min(7, frequency)) {
        case 1:
            [.monday]
        case 2:
            [.monday, .thursday]
        case 3:
            [.monday, .wednesday, .friday]
        case 4:
            [.monday, .tuesday, .thursday, .saturday]
        case 5:
            [.monday, .tuesday, .wednesday, .friday, .saturday]
        case 6:
            [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        default:
            allCases
        }
    }
}

@MainActor
final class PlanNavigationCoordinator {
    static let shared = PlanNavigationCoordinator()

    private(set) var pendingDay: Date?

    func request(day: Date?) {
        pendingDay = day
    }

    func consumePendingDay() -> Date? {
        defer { pendingDay = nil }
        return pendingDay
    }
}

@Observable
@MainActor
final class ProgramDetailsViewModel {
    struct TemplatePlanAnchor: Equatable, Sendable {
        let workoutId: String
        let dayOrder: Int
        let day: Date
        let status: TrainingDayStatus
    }

    struct ScheduleValidationResult: Equatable, Sendable {
        let dates: [Date]
        let message: String?
    }

    struct UpcomingWorkout: Equatable, Identifiable {
        let id: String
        let title: String
        let dateText: String
    }

    struct WorkoutScheduleReference: Equatable {
        let day: Date
        let dateText: String
        let status: TrainingDayStatus
    }

    struct PlannableWorkout: Equatable, Identifiable {
        let id: String
        let dayOrder: Int
        let title: String
        let workout: WorkoutDetailsModel
    }

    struct SelectedWorkout: Equatable, Identifiable {
        let userSub: String
        let programId: String
        let workoutId: String
        let presetWorkout: WorkoutDetailsModel?
        let source: WorkoutSource
        let displayMode: ProgramDetailsDisplayMode
        let isFirstWorkoutAfterEnrollment: Bool
        let allowsImmediateStart: Bool
        let plannedDay: Date?
        let plannedDateText: String?

        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    struct ProgramOnboardingRoute: Equatable, Identifiable {
        let id: String
        let programId: String
        let programTitle: String
        let authorName: String?
        let authorAvatarURL: URL?
        let summaryLine: String?
        let previewSectionTitle: String
        let previewItems: [String]
        let frequencyPerWeek: Int?
        let level: String?
        let estimatedDurationMinutes: Int?
        let firstWorkoutTitle: String?
        let firstWorkoutInstanceId: String?
        let plannableWorkouts: [PlannableWorkout]
        let fixedAnchors: [TemplatePlanAnchor]
        let isPendingEnrollment: Bool

        var canStartFirstWorkout: Bool {
            firstWorkoutInstanceId != nil
        }

        var canPlanProgram: Bool {
            !plannableWorkouts.isEmpty
        }
    }

    struct WorkoutIntroRoute: Equatable, Identifiable {
        let userSub: String
        let programId: String
        let workoutId: String
        let source: WorkoutSource
        let workout: WorkoutDetailsModel
        let isFirstWorkoutAfterEnrollment: Bool

        var id: String {
            "\(programId)::\(workoutId)::intro"
        }
    }

    let programId: String
    let userSub: String

    private let programsClient: ProgramsClientProtocol?
    private let athleteTrainingClient: AthleteTrainingClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let progressStore: WorkoutProgressStore
    private let trainingStore: TrainingStore
    private let onUnauthorized: (() -> Void)?

    var details: ProgramDetails?
    var isShowingCachedData = false
    var isLoading = false
    var isStartingProgram = false
    var error: UserFacingError?
    var successMessage: String?
    var isWorkoutsPresented = false
    var selectedWorkout: SelectedWorkout?
    var completedWorkoutsCount = 0
    var totalWorkoutsCount = 0
    var upcomingWorkoutTitle: String?
    var upcomingWorkouts: [UpcomingWorkout] = []
    var remainingPlannableWorkouts: [PlannableWorkout] = []
    var templatePlanAnchors: [String: TemplatePlanAnchor] = [:]
    var workoutScheduleReferences: [String: WorkoutScheduleReference] = [:]
    var firstScheduledDay: Date?
    var scheduledWeekdays: Set<ProgramScheduleWeekday> = []
    var nextTemplateWorkoutId: String?
    var lastCompletionTitle: String?
    var isProgramAlreadyActive = false
    var hasResumableWorkout = false
    var hasTodayWorkout = false
    var isProgramScheduled = false
    var currentEnrollmentId: String?
    var nextWorkoutInstanceId: String?
    var nextWorkoutInstanceTitle: String?
    var enrollmentConfirmation: ProgramOnboardingRoute?
    var workoutIntro: WorkoutIntroRoute?
    var isPreparingFirstWorkout = false
    var creatorCard: InfluencerPublicCard?
    var isCreatorFollowLoading = false
    var creatorInfoMessage: String?
    var creatorProfileRoute: InfluencerPublicCard?

    var canAdjustSchedule: Bool {
        if !isProgramAlreadyActive {
            return false
        }
        if !isProgramScheduled {
            return true
        }
        return !remainingPlannableWorkouts.isEmpty
    }

    var canAccessProgramWorkouts: Bool {
        isProgramAlreadyActive
            && isProgramScheduled
    }

    var canToggleCreatorFollow: Bool {
        !isCreatorFollowLoading
            && networkMonitor.currentStatus
            && !userSub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && userSub.lowercased() != "anonymous"
    }

    init(
        programId: String,
        userSub: String,
        programsClient: ProgramsClientProtocol?,
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        trainingStore: TrainingStore = LocalTrainingStore(),
        onUnauthorized: (() -> Void)? = nil,
    ) {
        self.programId = programId
        self.userSub = userSub
        self.programsClient = programsClient
        self.athleteTrainingClient = athleteTrainingClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.progressStore = progressStore
        self.trainingStore = trainingStore
        self.onUnauthorized = onUnauthorized
    }

    func onAppear() async {
        guard details == nil, !isLoading else { return }
        await load()
    }

    func retry() async {
        await load()
    }

    func handlePrimaryProgramAction() async {
        if isProgramAlreadyActive, !isProgramScheduled {
            openPlanningFlow()
            return
        }

        if isProgramAlreadyActive, let nextWorkoutInstanceId {
            selectedWorkout = SelectedWorkout(
                userSub: userSub,
                programId: programId,
                workoutId: nextWorkoutInstanceId,
                presetWorkout: nil,
                source: .program,
                displayMode: .active,
                isFirstWorkoutAfterEnrollment: false,
                allowsImmediateStart: true,
                plannedDay: nil,
                plannedDateText: nil,
            )
            return
        }

        ClientAnalytics.track(
            .programStartButtonTapped,
            properties: ["program_id": programId],
        )
        await startProgram()
    }

    var primaryProgramActionTitle: String {
        if isStartingProgram {
            return "Запускаем программу..."
        }
        if hasResumableWorkout {
            return "Продолжить"
        }
        if isProgramAlreadyActive, hasTodayWorkout {
            return "Начать сегодня"
        }
        if isProgramAlreadyActive, !isProgramScheduled {
            return "Распланировать"
        }
        return "Начать"
    }

    var isPrimaryProgramActionEnabled: Bool {
        if isStartingProgram {
            return false
        }
        if isProgramAlreadyActive, hasTodayWorkout {
            return nextWorkoutInstanceId != nil
        }
        if isProgramAlreadyActive, !isProgramScheduled {
            return true
        }
        return details?.currentPublishedVersion?.id != nil
    }

    var shouldShowPrimaryProgramAction: Bool {
        if isStartingProgram {
            return true
        }
        if hasResumableWorkout {
            return true
        }
        if isProgramAlreadyActive, !isProgramScheduled {
            return true
        }
        if isProgramAlreadyActive {
            return hasTodayWorkout
        }
        return true
    }

    var primaryProgramActionHint: String? {
        if isStartingProgram {
            return "Подключаем программу."
        }
        if hasResumableWorkout {
            if let title = nextWorkoutInstanceTitle?.trimmedNilIfEmpty {
                return title
            }
            return "Текущая тренировка"
        }
        if isProgramAlreadyActive, hasTodayWorkout {
            if let title = nextWorkoutInstanceTitle?.trimmedNilIfEmpty {
                return title
            }
            return "Тренировка на сегодня"
        }
        if isProgramAlreadyActive, !isProgramScheduled {
            return "Сначала сохраните расписание."
        }
        if isProgramAlreadyActive {
            return "Посмотрите ближайшие даты ниже или измените расписание."
        }
        return "После старта откроем следующий шаг."
    }

    private func startProgram() async {
        guard let versionID = details?.currentPublishedVersion?.id, !isStartingProgram else { return }
        isStartingProgram = true
        defer { isStartingProgram = false }

        let result: Result<ProgramEnrollment, APIError> = if let programsClient {
            await programsClient.startProgram(programVersionId: versionID)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case .success:
            successMessage = "Программа подключена."
            error = nil
            ClientAnalytics.track(
                .programActivated,
                properties: [
                    "program_id": programId,
                    "activation_mode": "remote",
                ],
            )
            ClientAnalytics.track(
                .programEnrolled,
                properties: [
                    "program_id": programId,
                    "enrollment_mode": "remote",
                ],
            )
            if let creatorID = creatorCard?.id.uuidString {
                ClientAnalytics.track(
                    .creatorProgramEnrolled,
                    properties: [
                        "program_id": programId,
                        "creator_id": creatorID,
                    ],
                )
            }
            await refreshEnrollmentContext()
            openEnrollmentConfirmation(isPendingEnrollment: false)
        case let .failure(apiError):
            if case .httpError(409, _) = apiError {
                successMessage = "Программа уже активна."
                error = nil
                ClientAnalytics.track(
                    .programActivated,
                    properties: [
                        "program_id": programId,
                        "activation_mode": "already_active",
                    ],
                )
                await refreshEnrollmentContext()
                openEnrollmentConfirmation(isPendingEnrollment: false)
                return
            }
            if apiError == .offline || !networkMonitor.currentStatus {
                await persistPendingEnrollment(programVersionId: versionID)
                successMessage = "Программа будет подключена после синхронизации."
                error = nil
                ClientAnalytics.track(
                    .programEnrolled,
                    properties: [
                        "program_id": programId,
                        "enrollment_mode": "pending_offline",
                    ],
                )
                if let creatorID = creatorCard?.id.uuidString {
                    ClientAnalytics.track(
                        .creatorProgramEnrolled,
                        properties: [
                            "program_id": programId,
                            "creator_id": creatorID,
                        ],
                    )
                }
                openEnrollmentConfirmation(isPendingEnrollment: true)
                return
            }
            error = apiError.userFacing(context: .programDetails)
        }
    }

    func openWorkouts() {
        guard canAccessProgramWorkouts else { return }
        isWorkoutsPresented = true
    }

    func canInteractWithWorkoutStructureItem(_ workoutID: String) -> Bool {
        if isProgramAlreadyActive {
            return true
        }
        return canAccessProgramWorkouts && !workoutID.isEmpty
    }

    func scheduleReference(for workoutID: String) -> WorkoutScheduleReference? {
        workoutScheduleReferences[workoutID]
    }

    var scheduleActionTitle: String {
        isProgramScheduled ? "Изменить расписание" : "Распланировать"
    }

    var structureHint: String {
        if isProgramAlreadyActive, !isProgramScheduled {
            return "Сначала распланируйте даты."
        }
        if isProgramAlreadyActive {
            return "Нажмите на тренировку."
        }
        return "Список тренировок откроется после старта программы."
    }

    func shouldLaunchWorkoutDirectly(for workoutID: String) -> Bool {
        guard nextWorkoutInstanceId?.trimmedNilIfEmpty != nil else { return false }
        guard workoutID == nextTemplateWorkoutId else { return false }
        if hasResumableWorkout {
            return true
        }
        guard let reference = scheduleReference(for: workoutID) else { return false }
        return reference.status == .inProgress || Calendar.current.isDateInToday(reference.day)
    }

    func launchNextWorkoutIfPossible() {
        guard let nextWorkoutInstanceId else { return }
        selectedWorkout = SelectedWorkout(
            userSub: userSub,
            programId: programId,
            workoutId: nextWorkoutInstanceId,
            presetWorkout: nil,
            source: .program,
            displayMode: .active,
            isFirstWorkoutAfterEnrollment: false,
            allowsImmediateStart: true,
            plannedDay: nil,
            plannedDateText: nil,
        )
    }

    func workoutPicked(_ workoutID: String) {
        guard canAccessProgramWorkouts else { return }
        selectedWorkout = SelectedWorkout(
            userSub: userSub,
            programId: programId,
            workoutId: workoutID,
            presetWorkout: nil,
            source: .program,
            displayMode: .active,
            isFirstWorkoutAfterEnrollment: false,
            allowsImmediateStart: false,
            plannedDay: nil,
            plannedDateText: nil,
        )
    }

    func dismissSelectedWorkout() {
        selectedWorkout = nil
    }

    func launchWorkoutFromIntro(_ route: WorkoutIntroRoute) {
        workoutIntro = nil
        enrollmentConfirmation = nil
        selectedWorkout = SelectedWorkout(
            userSub: route.userSub,
            programId: route.programId,
            workoutId: route.workoutId,
            presetWorkout: route.workout,
            source: route.source,
            displayMode: .active,
            isFirstWorkoutAfterEnrollment: route.isFirstWorkoutAfterEnrollment,
            allowsImmediateStart: true,
            plannedDay: nil,
            plannedDateText: nil,
        )
    }

    func previewWorkoutFromStructure(
        _ workoutID: String,
        plannedDay: Date?,
        plannedDateText: String?,
        displayMode: ProgramDetailsDisplayMode = .active
    ) {
        guard canInteractWithWorkoutStructureItem(workoutID) else { return }
        selectedWorkout = SelectedWorkout(
            userSub: userSub,
            programId: programId,
            workoutId: workoutID,
            presetWorkout: nil,
            source: .program,
            displayMode: displayMode,
            isFirstWorkoutAfterEnrollment: false,
            allowsImmediateStart: false,
            plannedDay: plannedDay,
            plannedDateText: plannedDateText,
        )
    }

    func dismissEnrollmentConfirmation() {
        enrollmentConfirmation = nil
    }

    func openPlanningFlow() {
        openEnrollmentConfirmation(isPendingEnrollment: false)
    }

    func dismissWorkoutIntro() {
        workoutIntro = nil
    }

    func handleEnrollmentPrimaryAction() async {
        guard let route = enrollmentConfirmation, route.canStartFirstWorkout, !isPreparingFirstWorkout else { return }
        isPreparingFirstWorkout = true
        defer { isPreparingFirstWorkout = false }

        ClientAnalytics.track(
            .programOnboardingStartFirstWorkoutTapped,
            properties: ["program_id": route.programId],
        )

        if let firstWorkoutInstanceId = route.firstWorkoutInstanceId,
           let intro = await prepareRemoteWorkoutIntro(
               workoutInstanceId: firstWorkoutInstanceId,
               programId: route.programId,
               isFirstWorkoutAfterEnrollment: true,
           )
        {
            error = nil
            launchWorkoutFromIntro(intro)
            ClientAnalytics.track(
                .firstWorkoutStarted,
                properties: [
                    "program_id": route.programId,
                    "workout_id": firstWorkoutInstanceId,
                    "source": "instance",
                ],
            )
            return
        }

        error = UserFacingError(
            kind: .unknown,
            title: "Не удалось подготовить тренировку",
            message: "Сервер ещё не подготовил тренировку. Обновите экран или откройте план программы позже.",
        )
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        if let cached = await cacheStore.get(cacheKey, as: ProgramDetails.self, namespace: userSub) {
            details = cached
            syncCreatorCard(from: cached.influencer)
            isShowingCachedData = true
        }

        let result: Result<ProgramDetails, APIError> = if let programsClient {
            await programsClient.getProgramDetails(programId: programId)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(details):
            self.details = details
            syncCreatorCard(from: details.influencer)
            isShowingCachedData = false
            error = nil
            await cacheStore.set(cacheKey, value: details, namespace: userSub, ttl: 60 * 30)
            await refreshProgress(with: details)
            await refreshEnrollmentContext()

        case let .failure(apiError):
            if apiError == .offline || !networkMonitor.currentStatus, details != nil {
                error = nil
                isShowingCachedData = true
                if let details {
                    await refreshProgress(with: details)
                }
                await refreshEnrollmentContext()
                return
            }
            error = apiError.userFacing(context: .programDetails)
        }
    }

    private func refreshProgress(with details: ProgramDetails) async {
        let workouts = details.workouts ?? []
        totalWorkoutsCount = workouts.count

        let statuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: workouts.map(\.id),
        )
        let templatePlanAnchors = await resolveTemplatePlanAnchors()
        self.templatePlanAnchors = templatePlanAnchors
        completedWorkoutsCount = statuses.values.count(where: { $0 == .completed })
        let sortedWorkouts = workouts.sorted(by: { $0.dayOrder < $1.dayOrder })
        let nextTemplateWorkout = sortedWorkouts.first(where: { statuses[$0.id] != .completed }) ?? sortedWorkouts.first
        upcomingWorkoutTitle = nextTemplateWorkout?.title
        nextTemplateWorkoutId = nextTemplateWorkout?.id
        remainingPlannableWorkouts = sortedWorkouts
            .filter {
                templateIsReplannable(
                    $0.id,
                    progressStatuses: statuses,
                    templatePlanAnchors: templatePlanAnchors,
                    allTemplates: sortedWorkouts
                )
            }
            .map { template in
                PlannableWorkout(
                    id: template.id,
                    dayOrder: template.dayOrder,
                    title: template.title?.trimmedNilIfEmpty ?? "Тренировка \(template.dayOrder)",
                    workout: mapTemplateWorkout(template),
                )
            }

        if let last = await trainingStore.history(userSub: userSub, source: nil, limit: 40)
            .first(where: { $0.programId == programId })
        {
            let minutes = max(1, last.durationSeconds / 60)
            let volume = last.volume > 0 ? " • объём \(Int(last.volume)) кг" : ""
            lastCompletionTitle = "\(last.finishedAt.formatted(date: .abbreviated, time: .shortened)) • \(minutes) мин\(volume)"
        } else {
            lastCompletionTitle = nil
        }

        let scheduleContext = await resolveScheduleContext()
        upcomingWorkouts = scheduleContext.upcomingWorkouts
        workoutScheduleReferences = scheduleContext.references
        firstScheduledDay = scheduleContext.firstDay
        scheduledWeekdays = scheduleContext.weekdays
    }

    private var cacheKey: String {
        "program.details:\(programId)"
    }

    private struct ScheduleContext {
        let upcomingWorkouts: [UpcomingWorkout]
        let references: [String: WorkoutScheduleReference]
        let firstDay: Date?
        let weekdays: Set<ProgramScheduleWeekday>
    }

    private func resolveScheduleContext() async -> ScheduleContext {
        let today = Calendar.current.startOfDay(for: Date())

        if let remotePlans = await remoteProgramSchedulePlans(), !remotePlans.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")

            let normalizedRemotePlans: [(plan: TrainingDayPlan, status: TrainingDayStatus)] = remotePlans.map { plan in
                (
                    plan: plan,
                    status: normalizedDisplayStatus(plan.status, day: plan.day)
                )
            }
            let relevantPlans = normalizedRemotePlans
                .filter { $0.status == .planned || $0.status == .inProgress }
                .sorted { $0.plan.day < $1.plan.day }

            let references = makeWorkoutScheduleReferences(
                from: normalizedRemotePlans,
                formatter: formatter,
                today: today
            )

            let weekdays = Set(
                relevantPlans.compactMap { plan in
                    ProgramScheduleWeekday.from(date: plan.plan.day, calendar: Calendar.current)
                }
            )

            let upcoming = relevantPlans
                .filter { Calendar.current.startOfDay(for: $0.plan.day) >= today }
                .prefix(3)
                .map { plan in
                    UpcomingWorkout(
                        id: plan.plan.id,
                        title: plan.plan.title,
                        dateText: formatter.string(from: plan.plan.day).capitalized
                    )
                }

            return ScheduleContext(
                upcomingWorkouts: upcoming,
                references: references,
                firstDay: relevantPlans.first?.plan.day,
                weekdays: weekdays
            )
        }

        var plans: [TrainingDayPlan] = []
        let targetCount = max(1, details?.workouts?.count ?? 0)
        for monthOffset in 0..<6 {
            let month = Calendar.current.date(byAdding: .month, value: monthOffset, to: today) ?? today
            let monthPlans = await trainingStore.plans(userSub: userSub, month: month)
            plans.append(contentsOf: monthPlans)
            let matchedTemplateIDs = Set(
                plans
                    .filter { $0.programId == programId }
                    .compactMap { $0.workoutId?.trimmedNilIfEmpty }
            )
            if matchedTemplateIDs.count >= targetCount {
                break
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")

        let programPlans = plans.filter { $0.programId == programId }
        let normalizedPlans: [(plan: TrainingDayPlan, status: TrainingDayStatus)] = programPlans.map { plan in
            (
                plan: plan,
                status: normalizedDisplayStatus(plan.status, day: plan.day)
            )
        }
        let relevantPlans = normalizedPlans
            .filter { $0.status == .planned || $0.status == .inProgress }
            .sorted { $0.plan.day < $1.plan.day }

        let references = makeWorkoutScheduleReferences(
            from: normalizedPlans,
            formatter: formatter,
            today: today
        )

        let weekdays = Set(
            relevantPlans.compactMap { plan in
                ProgramScheduleWeekday.from(date: plan.plan.day, calendar: Calendar.current)
            }
        )

        let upcoming = relevantPlans
            .filter { Calendar.current.startOfDay(for: $0.plan.day) >= today }
            .prefix(3)
            .map { plan in
                UpcomingWorkout(
                    id: plan.plan.id,
                    title: plan.plan.title,
                    dateText: formatter.string(from: plan.plan.day).capitalized
                )
            }

        return ScheduleContext(
            upcomingWorkouts: upcoming,
            references: references,
            firstDay: relevantPlans.first?.plan.day,
            weekdays: weekdays
        )
    }

    private func makeWorkoutScheduleReferences(
        from plans: [(plan: TrainingDayPlan, status: TrainingDayStatus)],
        formatter: DateFormatter,
        today: Date
    ) -> [String: WorkoutScheduleReference] {
        var references: [String: WorkoutScheduleReference] = [:]
        var priorities: [String: Int] = [:]

        for candidate in plans {
            let scheduleKey = candidate.plan.workoutDetails?.id.trimmedNilIfEmpty
                ?? candidate.plan.workoutId?.trimmedNilIfEmpty
            guard let workoutID = scheduleKey else { continue }

            let priority = scheduleReferencePriority(
                for: candidate.status,
                day: candidate.plan.day,
                today: today
            )

            if let existingPriority = priorities[workoutID], existingPriority > priority {
                continue
            }

            if let existingPriority = priorities[workoutID],
               existingPriority == priority,
               let existing = references[workoutID],
               existing.day > candidate.plan.day {
                continue
            }

            priorities[workoutID] = priority
            references[workoutID] = WorkoutScheduleReference(
                day: candidate.plan.day,
                dateText: formatter.string(from: candidate.plan.day).capitalized,
                status: candidate.status
            )
        }

        return references
    }

    private func scheduleReferencePriority(
        for status: TrainingDayStatus,
        day: Date,
        today: Date
    ) -> Int {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        switch status {
        case .inProgress:
            return 5
        case .planned:
            return normalizedDay >= today ? 4 : 3
        case .completed:
            return 2
        case .missed, .skipped:
            return 1
        }
    }

    private func resolveTemplatePlanAnchors() async -> [String: TemplatePlanAnchor] {
        if let remotePlans = await remoteProgramSchedulePlans(), !remotePlans.isEmpty {
            var anchors: [String: TemplatePlanAnchor] = [:]
            for plan in remotePlans where plan.programId == programId {
                guard let workoutID = plan.workoutDetails?.id.trimmedNilIfEmpty ?? plan.workoutId?.trimmedNilIfEmpty else { continue }
                guard let dayOrder = plan.workoutDetails?.dayOrder, dayOrder > 0 else { continue }

                let candidate = TemplatePlanAnchor(
                    workoutId: workoutID,
                    dayOrder: dayOrder,
                    day: Calendar.current.startOfDay(for: plan.day),
                    status: normalizedDisplayStatus(plan.status, day: plan.day),
                )

                if let existing = anchors[workoutID] {
                    if candidate.day > existing.day {
                        anchors[workoutID] = candidate
                    }
                } else {
                    anchors[workoutID] = candidate
                }
            }
            return anchors
        }

        let today = Calendar.current.startOfDay(for: Date())
        var plans: [TrainingDayPlan] = []

        for monthOffset in -6..<6 {
            let month = Calendar.current.date(byAdding: .month, value: monthOffset, to: today) ?? today
            let monthPlans = await trainingStore.plans(userSub: userSub, month: month)
            plans.append(contentsOf: monthPlans)
        }

        var anchors: [String: TemplatePlanAnchor] = [:]
        for plan in plans where plan.programId == programId {
            guard let workoutID = plan.workoutId?.trimmedNilIfEmpty else { continue }
            guard let dayOrder = plan.workoutDetails?.dayOrder, dayOrder > 0 else { continue }

            let candidate = TemplatePlanAnchor(
                workoutId: workoutID,
                dayOrder: dayOrder,
                day: Calendar.current.startOfDay(for: plan.day),
                status: normalizedDisplayStatus(plan.status, day: plan.day),
            )

            if let existing = anchors[workoutID] {
                if candidate.day > existing.day {
                    anchors[workoutID] = candidate
                }
            } else {
                anchors[workoutID] = candidate
            }
        }

        return anchors
    }

    private func remoteProgramSchedulePlans() async -> [TrainingDayPlan]? {
        guard let athleteTrainingClient,
              networkMonitor.currentStatus,
              let enrollmentId = currentEnrollmentId?.trimmedNilIfEmpty,
              let details
        else {
            return nil
        }

        let result = await athleteTrainingClient.enrollmentSchedule(enrollmentId: enrollmentId)
        guard case let .success(response) = result else {
            return nil
        }

        let templatesById = Dictionary(uniqueKeysWithValues: (details.workouts ?? []).map { ($0.id, $0) })

        return response.workouts.compactMap { workout in
            guard workout.programId?.trimmedNilIfEmpty == programId else { return nil }
            guard let rawDate = workout.scheduledDate?.trimmedNilIfEmpty
                    ?? workout.startedAt?.trimmedNilIfEmpty
                    ?? workout.completedAt?.trimmedNilIfEmpty,
                  let day = Self.scheduleDateFormatter.date(from: rawDate)
                    ?? ISO8601DateFormatter().date(from: rawDate)
            else {
                return nil
            }

            let templateId = workout.workoutTemplateId?.trimmedNilIfEmpty
            let template = templateId.flatMap { templatesById[$0] }
            let mappedWorkout = template.map(mapTemplateWorkout)

            return TrainingDayPlan(
                id: "remote-schedule-\(workout.id)",
                userSub: userSub,
                day: Calendar.current.startOfDay(for: day),
                status: mapWorkoutInstanceStatus(workout.status),
                programId: programId,
                programTitle: details.title.trimmedNilIfEmpty,
                workoutId: templateId ?? workout.id,
                title: workout.title?.trimmedNilIfEmpty ?? template?.title?.trimmedNilIfEmpty ?? "Тренировка",
                source: .program,
                workoutDetails: mappedWorkout
            )
        }
    }

    private func mapWorkoutInstanceStatus(_ status: AthleteWorkoutInstanceStatus?) -> TrainingDayStatus {
        switch status {
        case .completed:
            return .completed
        case .missed:
            return .missed
        case .abandoned:
            return .skipped
        case .inProgress:
            return .inProgress
        case .planned, .none:
            return .planned
        }
    }

    private func templateIsReplannable(
        _ workoutID: String,
        progressStatuses: [String: WorkoutProgressStatus],
        templatePlanAnchors: [String: TemplatePlanAnchor],
        allTemplates: [WorkoutTemplate]
    ) -> Bool {
        if progressStatuses[workoutID] == .completed {
            return false
        }

        guard let planStatus = templatePlanAnchors[workoutID]?.status else {
            return true
        }

        switch planStatus {
        case .planned:
            return true
        case .missed, .skipped:
            return !hasLockedProgressAfterWorkout(
                workoutID,
                progressStatuses: progressStatuses,
                templatePlanAnchors: templatePlanAnchors,
                allTemplates: allTemplates
            )
        case .inProgress, .completed:
            return false
        }
    }

    private func hasLockedProgressAfterWorkout(
        _ workoutID: String,
        progressStatuses: [String: WorkoutProgressStatus],
        templatePlanAnchors: [String: TemplatePlanAnchor],
        allTemplates: [WorkoutTemplate]
    ) -> Bool {
        guard let currentDayOrder = allTemplates.first(where: { $0.id == workoutID })?.dayOrder else {
            return false
        }

        for template in allTemplates where template.dayOrder > currentDayOrder {
            if progressStatuses[template.id] == .completed {
                return true
            }

            switch templatePlanAnchors[template.id]?.status {
            case .inProgress, .completed:
                return true
            default:
                continue
            }
        }

        return false
    }

    private func normalizedDisplayStatus(_ status: TrainingDayStatus, day: Date) -> TrainingDayStatus {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        let today = Calendar.current.startOfDay(for: Date())
        if normalizedDay >= today, status.isMissedLike {
            return .planned
        }
        return status
    }

    private func persistPendingEnrollment(programVersionId: String) async {
        let pending = PendingEnrollmentSnapshot(
            id: UUID().uuidString,
            programId: programId,
            programVersionId: programVersionId,
            createdAt: Date(),
        )
        await cacheStore.set(
            "enrollment.pending:\(programId)",
            value: pending,
            namespace: userSub,
            ttl: 60 * 60 * 24 * 7,
        )
    }

    private func openEnrollmentConfirmation(isPendingEnrollment: Bool) {
        guard let route = makePlanningRoute(isPendingEnrollment: isPendingEnrollment) else { return }
        enrollmentConfirmation = route
    }

    func planningSetupRoute() -> ProgramOnboardingRoute? {
        guard canAdjustSchedule else { return nil }
        return makePlanningRoute(isPendingEnrollment: false)
    }

    private func makePlanningRoute(isPendingEnrollment: Bool) -> ProgramOnboardingRoute? {
        guard let details else { return nil }
        let sortedWorkouts = (details.workouts ?? []).sorted(by: { $0.dayOrder < $1.dayOrder })
        let planningWorkouts = isProgramScheduled && !remainingPlannableWorkouts.isEmpty
            ? remainingPlannableWorkouts
            : sortedWorkouts.map { template in
                PlannableWorkout(
                    id: template.id,
                    dayOrder: template.dayOrder,
                    title: template.title?.trimmedNilIfEmpty ?? "Тренировка \(template.dayOrder)",
                    workout: mapTemplateWorkout(template),
                )
            }
        let previewTemplates = planningWorkouts.map { workout in
            WorkoutTemplate(
                id: workout.id,
                dayOrder: workout.dayOrder,
                title: workout.title,
                coachNote: workout.workout.coachNote,
                exercises: nil,
                media: nil
            )
        }
        let fallbackWorkout = planningWorkouts.first
        let fallbackTitle = fallbackWorkout?.title.trimmedNilIfEmpty ?? fallbackWorkout.map { "День \($0.dayOrder)" }
        let preview = onboardingPreview(for: previewTemplates)
        let frequencyPerWeek = details.currentPublishedVersion?.frequencyPerWeek
        let level = localizedLevel(details.currentPublishedVersion?.level)
        let estimatedDurationMinutes = estimatedProgramDurationMinutes(details: details)
        let authorName = creatorCard?.displayName ?? details.influencer?.displayName.trimmedNilIfEmpty
        let authorAvatar = creatorCard?.avatar ?? details.influencer?.avatar.flatMap { URL(string: $0.url) }

        let firstWorkoutInstanceId = nextWorkoutInstanceId?.trimmedNilIfEmpty
        let firstWorkoutTitle = nextWorkoutInstanceTitle?.trimmedNilIfEmpty ?? fallbackTitle
        let fixedAnchors = templatePlanAnchors.values
            .filter { anchor in
                !planningWorkouts.contains(where: { $0.id == anchor.workoutId })
            }
            .sorted(by: { $0.dayOrder < $1.dayOrder })

        return ProgramOnboardingRoute(
            id: "enrollment-confirmation-\(programId)-\(Date().timeIntervalSince1970)",
            programId: programId,
            programTitle: details.title,
            authorName: authorName,
            authorAvatarURL: authorAvatar,
            summaryLine: programSummaryLine(
                workoutsCount: sortedWorkouts.count,
                frequencyPerWeek: frequencyPerWeek,
            ),
            previewSectionTitle: preview.title,
            previewItems: preview.items,
            frequencyPerWeek: frequencyPerWeek,
            level: level,
            estimatedDurationMinutes: estimatedDurationMinutes,
            firstWorkoutTitle: firstWorkoutTitle,
            firstWorkoutInstanceId: firstWorkoutInstanceId,
            plannableWorkouts: planningWorkouts,
            fixedAnchors: fixedAnchors,
            isPendingEnrollment: isPendingEnrollment,
        )
    }

    private func onboardingPreview(for workouts: [WorkoutTemplate]) -> (title: String, items: [String]) {
        guard !workouts.isEmpty else {
            return ("Ближайшие тренировки", [])
        }

        let firstWeek = workouts
            .filter { $0.dayOrder > 0 && $0.dayOrder <= 7 }
            .sorted(by: { $0.dayOrder < $1.dayOrder })

        if firstWeek.count >= 2 {
            let items = firstWeek.prefix(7).map { workout in
                "День \(workout.dayOrder) — \(workout.title?.trimmedNilIfEmpty ?? "Тренировка")"
            }
            return ("Первая неделя", items)
        }

        let nearest = workouts
            .sorted(by: { $0.dayOrder < $1.dayOrder })
            .prefix(5)
            .map { workout in
                if workout.dayOrder > 0 {
                    return "День \(workout.dayOrder) — \(workout.title?.trimmedNilIfEmpty ?? "Тренировка")"
                }
                return workout.title?.trimmedNilIfEmpty ?? "Тренировка"
            }
        return ("Ближайшие тренировки", Array(nearest))
    }

    private func programSummaryLine(workoutsCount: Int, frequencyPerWeek: Int?) -> String? {
        var chunks: [String] = []

        if let frequencyPerWeek, frequencyPerWeek > 0 {
            chunks.append("\(frequencyPerWeek) \(pluralizedWorkoutsPerWeek(frequencyPerWeek))")
            let weeks = Int(ceil(Double(max(1, workoutsCount)) / Double(frequencyPerWeek)))
            if weeks > 0 {
                chunks.insert("\(weeks) \(pluralizedWeeks(weeks))", at: 0)
            }
        } else if workoutsCount > 0 {
            chunks.append("\(workoutsCount) \(pluralizedWorkouts(workoutsCount))")
        }

        return chunks.isEmpty ? nil : chunks.joined(separator: " • ")
    }

    private func pluralizedWeeks(_ value: Int) -> String {
        let remainder10 = value % 10
        let remainder100 = value % 100
        if remainder10 == 1, remainder100 != 11 {
            return "неделя"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "недели"
        }
        return "недель"
    }

    private func pluralizedWorkouts(_ value: Int) -> String {
        let remainder10 = value % 10
        let remainder100 = value % 100
        if remainder10 == 1, remainder100 != 11 {
            return "тренировка"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "тренировки"
        }
        return "тренировок"
    }

    private func pluralizedWorkoutsPerWeek(_ value: Int) -> String {
        "\(pluralizedWorkouts(value)) в неделю"
    }

    private func prepareRemoteWorkoutIntro(
        workoutInstanceId: String,
        programId: String,
        isFirstWorkoutAfterEnrollment: Bool,
    ) async -> WorkoutIntroRoute? {
        let cacheKey = "workout.details:\(programId):\(workoutInstanceId)"

        if networkMonitor.currentStatus, let athleteTrainingClient {
            let detailsResult = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId)
            switch detailsResult {
            case let .success(details):
                switch details.workout.status {
                case .completed, .abandoned:
                    error = UserFacingError(
                        title: details.workout.status == .completed ? "Тренировка уже завершена" : "Тренировка прервана",
                        message: "Откройте актуальную тренировку программы.",
                    )
                    return nil
                case .inProgress:
                    break
                case .planned, .missed, .none:
                    _ = await SyncCoordinator.shared.enqueueStartWorkout(
                        namespace: userSub,
                        workoutInstanceId: workoutInstanceId,
                        startedAt: Date(),
                    )
                }

                let mapped = details.asWorkoutDetailsModel()
                await cacheStore.set(cacheKey, value: mapped, namespace: userSub, ttl: 60 * 60 * 24)
                return WorkoutIntroRoute(
                    userSub: userSub,
                    programId: programId,
                    workoutId: workoutInstanceId,
                    source: .program,
                    workout: mapped,
                    isFirstWorkoutAfterEnrollment: isFirstWorkoutAfterEnrollment,
                )
            case let .failure(apiError):
                if apiError != .offline {
                    error = apiError.userFacing(context: .workoutPlayer)
                }
            }
        } else {
            _ = await SyncCoordinator.shared.enqueueStartWorkout(
                namespace: userSub,
                workoutInstanceId: workoutInstanceId,
                startedAt: Date(),
            )
        }

        if let cached = await cacheStore.get(cacheKey, as: WorkoutDetailsModel.self, namespace: userSub) {
            return WorkoutIntroRoute(
                userSub: userSub,
                programId: programId,
                workoutId: workoutInstanceId,
                source: .program,
                workout: cached,
                isFirstWorkoutAfterEnrollment: isFirstWorkoutAfterEnrollment,
            )
        }

        return nil
    }

    private func mapTemplateWorkout(_ template: WorkoutTemplate) -> WorkoutDetailsModel {
        let mappedExercises = (template.exercises ?? [])
            .enumerated()
            .map { index, exercise in
                WorkoutExercise(
                    id: exercise.id,
                    name: exercise.exercise.name,
                    sets: max(1, exercise.sets),
                    repsMin: exercise.repsMin,
                    repsMax: exercise.repsMax,
                    targetRpe: exercise.targetRpe,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes,
                    orderIndex: exercise.orderIndex ?? index,
                )
            }
            .sorted(by: { $0.orderIndex < $1.orderIndex })

        return WorkoutDetailsModel(
            id: template.id,
            title: template.title?.trimmedNilIfEmpty ?? "Тренировка \(template.dayOrder)",
            dayOrder: template.dayOrder,
            coachNote: template.coachNote?.trimmedNilIfEmpty,
            exercises: mappedExercises,
        )
    }

    private func estimateDurationMinutes(exercises: [ExerciseTemplate]) -> Int? {
        guard !exercises.isEmpty else { return nil }
        let totalSets = exercises.reduce(0) { $0 + max(1, $1.sets) }
        let restSeconds = exercises.reduce(0) { partial, exercise in
            partial + (exercise.restSeconds ?? 45) * max(0, exercise.sets - 1)
        }
        let estimatedSeconds = totalSets * 90 + restSeconds
        return max(10, estimatedSeconds / 60)
    }

    private func estimatedProgramDurationMinutes(details: ProgramDetails) -> Int? {
        let estimates = (details.workouts ?? [])
            .compactMap { estimateDurationMinutes(exercises: $0.exercises ?? []) }
        guard !estimates.isEmpty else { return nil }
        let total = estimates.reduce(0, +)
        return max(10, total / estimates.count)
    }

    func scheduleProgramWorkouts(
        startDate: Date,
        weekdays: Set<ProgramScheduleWeekday>,
    ) async -> Date? {
        if athleteTrainingClient != nil {
            return await persistRemoteSchedule(
                startDate: startDate,
                weekdays: weekdays,
            )
        }

        guard athleteTrainingClient == nil else {
            return nil
        }

        guard let details else { return nil }
        let templates = (details.workouts ?? []).sorted(by: { $0.dayOrder < $1.dayOrder })
        guard !templates.isEmpty else { return nil }
        let statuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: templates.map(\.id),
        )
        let templatePlanAnchors = await resolveTemplatePlanAnchors()
        let remainingTemplates = templates.filter {
            templateIsReplannable(
                $0.id,
                progressStatuses: statuses,
                templatePlanAnchors: templatePlanAnchors,
                allTemplates: templates
            )
        }
        guard !remainingTemplates.isEmpty else { return nil }

        let recommended = ProgramScheduleWeekday.recommended(
            for: details.currentPublishedVersion?.frequencyPerWeek ?? min(templates.count, 3)
        )
        let resolvedDays = weekdays.isEmpty ? Set(recommended) : weekdays
        guard let validation = Self.validateSchedule(
            startDate: startDate,
            weekdays: resolvedDays,
            plannableWorkouts: remainingTemplates.map { template in
                PlannableWorkout(
                    id: template.id,
                    dayOrder: template.dayOrder,
                    title: template.title?.trimmedNilIfEmpty ?? "Тренировка \(template.dayOrder)",
                    workout: mapTemplateWorkout(template),
                )
            },
            fixedAnchors: templatePlanAnchors.values.sorted(by: { $0.dayOrder < $1.dayOrder }),
        ) else {
            successMessage = nil
            error = UserFacingError(
                title: "Не удалось изменить расписание",
                message: "Выбранные дни не помещаются между уже зафиксированными тренировками программы.",
            )
            return nil
        }

        error = nil
        successMessage = validation.message?.trimmedNilIfEmpty

        let scheduledDays = validation.dates

        for (index, template) in remainingTemplates.enumerated() {
            let workout = mapTemplateWorkout(template)
            let plan = TrainingDayPlan(
                id: localProgramPlanID(workoutId: template.id),
                userSub: userSub,
                day: scheduledDays[index],
                status: .planned,
                programId: programId,
                programTitle: details.title.trimmedNilIfEmpty,
                workoutId: template.id,
                title: workout.title,
                source: .program,
                workoutDetails: workout,
            )
            await trainingStore.schedule(plan)
        }

        isProgramScheduled = true
        await refreshProgress(with: details)
        return scheduledDays.first
    }

    private func persistRemoteSchedule(
        startDate: Date,
        weekdays: Set<ProgramScheduleWeekday>,
    ) async -> Date? {
        guard networkMonitor.currentStatus,
              let athleteTrainingClient,
              let enrollmentId = currentEnrollmentId?.trimmedNilIfEmpty
        else {
            return nil
        }

        let frequency = details?.currentPublishedVersion?.frequencyPerWeek ?? max(1, (details?.workouts ?? []).count)
        let resolvedDays = weekdays.isEmpty
            ? Set(ProgramScheduleWeekday.recommended(for: frequency))
            : weekdays
        let request = AthleteEnrollmentScheduleUpdateRequest(
            startDate: Self.scheduleDateFormatter.string(from: startDate),
            weekdays: resolvedDays
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map(\.apiValue),
        )

        let result = await athleteTrainingClient.updateEnrollmentSchedule(
            enrollmentId: enrollmentId,
            request: request,
        )
        guard case let .success(response) = result else {
            return nil
        }

        await trainingStore.deleteProgramPlans(
            userSub: userSub,
            programId: programId,
            statuses: [.planned, .inProgress]
        )

        await refreshEnrollmentContext()
        isProgramScheduled = hasScheduledWorkout(in: response.workouts)
        if let details {
            await refreshProgress(with: details)
        }

        return response.workouts
            .compactMap { workout in
                guard let rawDate = workout.scheduledDate?.trimmedNilIfEmpty else { return nil }
                return Self.scheduleDateFormatter.date(from: rawDate)
            }
            .sorted()
            .first
    }

    static func validateSchedule(
        startDate: Date,
        weekdays: Set<ProgramScheduleWeekday>,
        plannableWorkouts: [PlannableWorkout],
        fixedAnchors: [TemplatePlanAnchor]? = nil,
    ) -> ScheduleValidationResult? {
        guard !plannableWorkouts.isEmpty, !weekdays.isEmpty else { return nil }

        let calendar = Calendar.current
        let minimumDay = calendar.startOfDay(for: Date())
        let anchors = fixedAnchors ?? []
        let normalizedStart = max(calendar.startOfDay(for: startDate), minimumDay)
        var result: [Date] = []
        let sortedWorkouts = plannableWorkouts.sorted(by: { $0.dayOrder < $1.dayOrder })

        for workout in sortedWorkouts {
            let previousGenerated = result.last
            let previousAnchor = anchors
                .filter { $0.dayOrder < workout.dayOrder }
                .map(\.day)
                .max()
            let nextAnchor = anchors
                .filter { $0.dayOrder > workout.dayOrder }
                .map(\.day)
                .min()

            let earliest = [
                normalizedStart,
                previousGenerated.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) },
                previousAnchor.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) },
            ]
            .compactMap { $0 }
            .max() ?? normalizedStart

            guard let scheduledDay = nextMatchingDate(
                onOrAfter: earliest,
                weekdays: weekdays,
                before: nextAnchor
            ) else {
                return nil
            }

            result.append(scheduledDay)
        }

        if result.isEmpty {
            return nil
        }

        return ScheduleValidationResult(
            dates: result,
            message: anchors.isEmpty ? nil : "Мы перестроим только оставшиеся тренировки и сохраним уже зафиксированные даты."
        )
    }

    private static func nextMatchingDate(
        onOrAfter day: Date,
        weekdays: Set<ProgramScheduleWeekday>,
        before limitDay: Date?,
    ) -> Date? {
        let calendar = Calendar.current
        let minimumDay = calendar.startOfDay(for: day)
        let normalizedLimit = limitDay.map { calendar.startOfDay(for: $0) }
        var cursor = minimumDay
        var attempts = 0

        while attempts < 365 {
            attempts += 1
            if let normalizedLimit, cursor >= normalizedLimit {
                return nil
            }

            if let weekday = ProgramScheduleWeekday.from(date: cursor, calendar: calendar),
               weekdays.contains(weekday)
            {
                return cursor
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return nil
    }

    private func localProgramPlanID(workoutId: String) -> String {
        "local-program-plan::\(programId)::\(workoutId)"
    }

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func localizedLevel(_ value: String?) -> String? {
        guard let value = value?.trimmedNilIfEmpty else { return nil }
        switch value.uppercased() {
        case "BEGINNER":
            return "Начинающий"
        case "INTERMEDIATE":
            return "Средний"
        case "ADVANCED":
            return "Продвинутый"
        default:
            return value.capitalized
        }
    }

    func openCreatorProfile() {
        guard let creatorCard else { return }
        creatorProfileRoute = creatorCard
    }

    func dismissCreatorProfile() {
        creatorProfileRoute = nil
    }

    func handleUnauthorized() {
        onUnauthorized?()
    }

    func applyCreatorUpdate(_ card: InfluencerPublicCard) {
        guard creatorCard?.id == card.id else {
            return
        }
        creatorCard = card
        creatorProfileRoute = card
    }

    func toggleCreatorFollow() async {
        guard let creatorCard else { return }
        guard !isCreatorFollowLoading else { return }
        guard !userSub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, userSub.lowercased() != "anonymous" else {
            creatorInfoMessage = "Войдите, чтобы подписываться на атлетов."
            return
        }
        guard networkMonitor.currentStatus else {
            creatorInfoMessage = "Нужен интернет"
            return
        }
        guard let programsClient else {
            creatorInfoMessage = "Подписка сейчас недоступна."
            return
        }

        let action: FollowMutationAction = creatorCard.isFollowedByMe ? .unfollow : .follow
        let before = creatorCard
        self.creatorCard = FollowStateMachine.apply(action, to: creatorCard)
        isCreatorFollowLoading = true
        creatorInfoMessage = nil

        let result = await FollowMutationExecutor.perform(
            action: action,
            influencerId: creatorCard.id,
            programsClient: programsClient,
        )

        isCreatorFollowLoading = false

        switch result {
        case .success:
            if self.creatorCard?.isFollowedByMe == true {
                ClientAnalytics.track(.athleteFollowed, properties: ["influencer_id": creatorCard.id.uuidString])
            } else {
                ClientAnalytics.track(.athleteUnfollowed, properties: ["influencer_id": creatorCard.id.uuidString])
            }
            if let updated = self.creatorCard {
                creatorProfileRoute = updated
            }
        case let .failure(apiError):
            self.creatorCard = before
            if apiError == .unauthorized {
                onUnauthorized?()
                return
            }
            if isCreatorFollowForbidden(apiError) {
                creatorInfoMessage = "Создайте профиль атлета, чтобы подписываться."
                return
            }
            error = apiError.userFacing(context: .programDetails)
        }
    }

    private func syncCreatorCard(from influencer: InfluencerBrief?) {
        guard let influencer else {
            creatorCard = nil
            creatorInfoMessage = nil
            return
        }
        if let resolved = influencer.asPublicCard {
            creatorInfoMessage = nil
            if let current = creatorCard, current.id == resolved.id {
                creatorCard = InfluencerPublicCard(
                    id: resolved.id,
                    displayName: resolved.displayName,
                    bio: resolved.bio,
                    avatar: resolved.avatar,
                    socialLinks: resolved.socialLinks ?? current.socialLinks,
                    followersCount: resolved.followersCount == 0 ? current.followersCount : resolved.followersCount,
                    programsCount: resolved.programsCount == 0 ? current.programsCount : resolved.programsCount,
                    isFollowedByMe: resolved.isFollowedByMe,
                )
            } else {
                creatorCard = resolved
            }
        }
    }

    private func refreshEnrollmentContext() async {
        guard let athleteTrainingClient else { return }

        let result = await athleteTrainingClient.programStatus(programId: programId)
        switch result {
        case let .success(status):
            currentEnrollmentId = status.enrollment?.id
            let isActive = status.enrollment?.status.uppercased() == EnrollmentStatus.active.rawValue
            isProgramAlreadyActive = isActive
            hasResumableWorkout = isActive && status.resumeWorkout != nil
            hasTodayWorkout = isActive && status.todayWorkout != nil && status.resumeWorkout == nil
            isProgramScheduled = isActive && hasScheduledWorkout(in: status)
            nextWorkoutInstanceId = isActive ? status.launchWorkout?.workoutInstanceId : nil
            nextWorkoutInstanceTitle = isActive ? status.launchWorkout?.title?.trimmedNilIfEmpty : nil
            upcomingWorkoutTitle = isActive
                ? status.todayWorkout?.title?.trimmedNilIfEmpty ?? status.nextWorkout?.title?.trimmedNilIfEmpty
                : nil
            completedWorkoutsCount = max(0, status.completedSessions ?? 0)
            totalWorkoutsCount = max(completedWorkoutsCount, status.totalSessions ?? 0)

        case let .failure(apiError):
            if apiError == .offline {
                return
            }
            // If enrollment context cannot be confirmed, block workout execution paths.
            currentEnrollmentId = nil
            isProgramAlreadyActive = false
            hasResumableWorkout = false
            hasTodayWorkout = false
            isProgramScheduled = false
            nextWorkoutInstanceId = nil
            nextWorkoutInstanceTitle = nil
        }
    }

    private func hasScheduledWorkout(in status: AthleteProgramStatusResponse) -> Bool {
        let targets = [
            status.resumeWorkout,
            status.currentWorkout,
            status.todayWorkout,
            status.nextWorkout,
            status.launchWorkout,
        ]

        return targets.contains { target in
            guard let target else { return false }
            if target.status == .inProgress {
                return true
            }
            return target.scheduledDate?.trimmedNilIfEmpty != nil
        }
    }

    private func hasScheduledWorkout(in workouts: [AthleteWorkoutInstance]) -> Bool {
        workouts.contains { workout in
            workout.scheduledDate?.trimmedNilIfEmpty != nil
        }
    }

    private struct PendingEnrollmentSnapshot: Codable, Equatable, Sendable {
        let id: String
        let programId: String
        let programVersionId: String
        let createdAt: Date
    }
}

private extension ProgramScheduleWeekday {
    var apiValue: String {
        switch self {
        case .monday: "MONDAY"
        case .tuesday: "TUESDAY"
        case .wednesday: "WEDNESDAY"
        case .thursday: "THURSDAY"
        case .friday: "FRIDAY"
        case .saturday: "SATURDAY"
        case .sunday: "SUNDAY"
        }
    }
}

struct ProgramDetailsScreen: View {
    @State var viewModel: ProgramDetailsViewModel
    @State private var isProgramScreenOpenTracked = false
    @State private var isPlanningSetupPresented = false
    let apiClient: APIClientProtocol?
    let environment: AppEnvironment?
    let displayMode: ProgramDetailsDisplayMode
    let onOpenProgramPlan: (() -> Void)?
    let onOpenWorkoutHub: (() -> Void)?
    let onOpenProgram: ((String, ProgramDetailsDisplayMode) -> Void)?

    init(
        viewModel: ProgramDetailsViewModel,
        apiClient: APIClientProtocol?,
        environment: AppEnvironment? = nil,
        displayMode: ProgramDetailsDisplayMode = .discovery,
        onOpenProgramPlan: (() -> Void)? = nil,
        onOpenWorkoutHub: (() -> Void)? = nil,
        onOpenProgram: ((String, ProgramDetailsDisplayMode) -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.apiClient = apiClient
        self.environment = environment
        self.displayMode = displayMode
        self.onOpenProgramPlan = onOpenProgramPlan
        self.onOpenWorkoutHub = onOpenWorkoutHub
        self.onOpenProgram = onOpenProgram
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    FFCard {
                        Text("Нет сети — показаны сохранённые данные")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.primary)
                    }
                }

                if viewModel.isLoading, viewModel.details == nil {
                    loadingState
                } else if let error = viewModel.error, viewModel.details == nil {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if let details = viewModel.details {
                    heroCard(details: details)
                    if displayMode == .discovery {
                        discoverySections(details: details)
                    } else {
                        workouts(details: details)
                    }
                    if let error = viewModel.error {
                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text(error.title)
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.danger)
                                Text(error.message)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                    }
                    if let successMessage = viewModel.successMessage {
                        FFCard {
                            Text(successMessage)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.accent)
                                .multilineTextAlignment(.leading)
                        }
                    }
                } else {
                    FFEmptyState(title: "Программа не найдена", message: "Попробуйте открыть другую программу.")
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .ffScreenBackground()
        .sheet(isPresented: $isPlanningSetupPresented) {
            if let route = viewModel.planningSetupRoute() {
                ProgramPlanningSetupView(
                    route: route,
                    title: viewModel.isProgramScheduled ? "Изменить расписание" : "Распланировать программу",
                    description: viewModel.isProgramScheduled
                        ? (viewModel.completedWorkoutsCount > 0
                            ? "Завершённые тренировки останутся на своих датах. Пропущенные тоже попадут в перенос, если цикл ещё не ушёл дальше выполненными тренировками."
                            : "Выберите новые дни недели и дату старта. Мы перестроим оставшиеся тренировки.")
                        : "Выберите дни недели. Мы равномерно разложим все тренировки программы по календарю.",
                    buttonTitle: viewModel.isProgramScheduled ? "Сохранить расписание" : "Сохранить в план",
                    initialSelectedDays: viewModel.scheduledWeekdays,
                    initialStartDate: viewModel.firstScheduledDay,
                    onClose: {
                        isPlanningSetupPresented = false
                    },
                    onApply: { startDate, weekdays in
                        Task {
                            _ = await viewModel.scheduleProgramWorkouts(
                                startDate: startDate,
                                weekdays: weekdays,
                            )
                            await MainActor.run {
                                isPlanningSetupPresented = false
                            }
                        }
                    },
                )
            }
        }
        .task {
            if !isProgramScreenOpenTracked {
                isProgramScreenOpenTracked = true
                ClientAnalytics.track(
                    .programDetailsScreenOpened,
                    properties: ["program_id": viewModel.programId],
                )
            }
            await viewModel.onAppear()
        }
        .navigationDestination(isPresented: $viewModel.isWorkoutsPresented) {
            if let programsClient = apiClient as? ProgramsClientProtocol {
                WorkoutsListScreen(
                    viewModel: WorkoutsListViewModel(
                        programId: viewModel.programId,
                        userSub: viewModel.userSub,
                        workoutsClient: WorkoutsClient(programsClient: programsClient),
                    ),
                    onWorkoutTap: { workoutID in
                        viewModel.workoutPicked(workoutID)
                    },
                )
                .navigationTitle("Тренировки программы")
            } else {
                FFErrorState(
                    title: "Тренировки недоступны",
                    message: "Проверьте конфигурацию клиента сервера для загрузки тренировок.",
                    retryTitle: "Назад",
                ) {
                    viewModel.isWorkoutsPresented = false
                }
            }
        }
        .navigationDestination(item: $viewModel.enrollmentConfirmation) { route in
            ProgramOnboardingView(
                route: route,
                isPreparingFirstWorkout: viewModel.isPreparingFirstWorkout,
                onStartFirstWorkout: {
                    Task { await viewModel.handleEnrollmentPrimaryAction() }
                },
                onPlanProgram: { startDate, weekdays in
                    Task {
                        let firstDay = await viewModel.scheduleProgramWorkouts(
                            startDate: startDate,
                            weekdays: weekdays,
                        )
                        await MainActor.run {
                            PlanNavigationCoordinator.shared.request(day: firstDay)
                            viewModel.dismissEnrollmentConfirmation()
                            onOpenProgramPlan?()
                        }
                    }
                },
                onOpenProgramPlan: {
                    ClientAnalytics.track(
                        .programOnboardingOpenPlanTapped,
                        properties: ["program_id": route.programId],
                    )
                    viewModel.dismissEnrollmentConfirmation()
                    onOpenProgramPlan?()
                },
            )
            .navigationTitle("Что дальше")
        }
        .navigationDestination(item: $viewModel.workoutIntro) { route in
            WorkoutIntroView(
                workout: route.workout,
                onPrimaryAction: {
                    viewModel.launchWorkoutFromIntro(route)
                },
            )
            .navigationTitle("Вводная тренировки")
        }
        .navigationDestination(item: $viewModel.creatorProfileRoute) { creator in
            CreatorProfileView(
                viewModel: CreatorProfileViewModel(
                    userSub: viewModel.userSub,
                    creator: creator,
                    programsClient: apiClient as? ProgramsClientProtocol,
                    onUnauthorized: {
                        viewModel.handleUnauthorized()
                    },
                ),
                environment: environment,
                onProgramTap: { programID in
                    onOpenProgram?(programID, .discovery)
                },
                onCreatorUpdated: { updated in
                    viewModel.applyCreatorUpdate(updated)
                },
            )
            .navigationTitle("Атлет")
        }
        .navigationDestination(item: $viewModel.selectedWorkout) { selectedWorkout in
            WorkoutLaunchView(
                userSub: selectedWorkout.userSub,
                programId: selectedWorkout.programId,
                workoutId: selectedWorkout.workoutId,
                apiClient: apiClient,
                presetWorkout: selectedWorkout.presetWorkout,
                source: selectedWorkout.source,
                displayMode: selectedWorkout.displayMode,
                isFirstWorkoutInProgramFlow: selectedWorkout.isFirstWorkoutAfterEnrollment,
                allowsImmediateStart: selectedWorkout.allowsImmediateStart,
                plannedDay: selectedWorkout.plannedDay,
                plannedDateText: selectedWorkout.plannedDateText,
                onBackToWorkoutHub: onOpenWorkoutHub,
                onOpenPlan: onOpenProgramPlan,
            )
            .navigationTitle("Тренировка")
        }
    }

    private var loadingState: some View {
        VStack(spacing: FFSpacing.sm) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    skeletonLine(width: 180)
                    skeletonLine(width: nil)
                    skeletonLine(width: 220)
                }
            }
            FFCard {
                HStack(spacing: FFSpacing.xs) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                            .fill(FFColors.gray700.opacity(0.65))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }

    private func skeletonLine(width: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: FFTheme.Radius.control)
            .fill(FFColors.gray700.opacity(0.65))
            .frame(width: width, height: 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroCard(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                Text(details.title)
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.leading)

                if displayMode == .discovery {
                    if let authorLine = discoveryAuthorLine(details: details) {
                        Text(authorLine)
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    if let descriptionLine = programDescriptionLine(details: details) {
                        Text(descriptionLine)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(4)
                    }

                    let facts = quickFactItems(details: details)
                    if !facts.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: FFSpacing.sm), count: 2), spacing: FFSpacing.sm) {
                            ForEach(Array(facts.enumerated()), id: \.offset) { _, item in
                                FFCard {
                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text(item.title)
                                            .font(FFTypography.caption)
                                            .foregroundStyle(FFColors.textSecondary)
                                        Text(item.value)
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text(programStatusTitle)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)

                        if let statusLine = programStatusLine(details: details) {
                            Text(statusLine)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .lineLimit(2)
                        }

                        if let referenceLine = programReferenceLine(details: details) {
                            Text(referenceLine)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                                .lineLimit(2)
                        }

                        if let descriptionLine = programDescriptionLine(details: details) {
                            Text(descriptionLine)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }

                if displayMode == .active, let progressText = progressSummary {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(progressText)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(FFColors.gray700.opacity(0.9))

                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(FFColors.accent)
                                    .frame(width: max(8, proxy.size.width * progressValue))
                            }
                        }
                        .frame(height: 8)
                    }
                }

                if displayMode == .active, !viewModel.upcomingWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        Text("Ближайшие")
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)

                        ForEach(viewModel.upcomingWorkouts) { workout in
                            HStack(alignment: .firstTextBaseline, spacing: FFSpacing.sm) {
                                Text(workout.dateText)
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.textSecondary)
                                    .frame(width: 88, alignment: .leading)

                                Text(workout.title)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: FFSpacing.xs)
                            }
                        }
                    }
                }

                if displayMode == .discovery {
                    discoveryActionBlock(details: details)
                } else if viewModel.shouldShowPrimaryProgramAction {
                    FFButton(
                        title: viewModel.primaryProgramActionTitle,
                        variant: viewModel.isPrimaryProgramActionEnabled ? .primary : .disabled,
                        action: {
                            if viewModel.isProgramAlreadyActive, !viewModel.isProgramScheduled {
                                isPlanningSetupPresented = true
                            } else {
                                Task { await viewModel.handlePrimaryProgramAction() }
                            }
                        }
                    )
                }

                if displayMode == .active, viewModel.canAdjustSchedule, viewModel.isProgramScheduled {
                    FFButton(
                        title: viewModel.scheduleActionTitle,
                        variant: .secondary,
                        action: {
                            isPlanningSetupPresented = true
                        }
                    )
                }
            }
        }
    }

    private func discoverySections(details: ProgramDetails) -> some View {
        VStack(spacing: FFSpacing.md) {
            discoveryValueCard(details: details)
            discoveryFormatCard(details: details)
            if discoveryHasCoachInfo(details: details) {
                discoveryCoachCard(details: details)
            }
        }
    }

    private func workouts(details: ProgramDetails) -> some View {
        let sortedWorkouts = (details.workouts ?? []).sorted(by: { $0.dayOrder < $1.dayOrder })

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Тренировки")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text(viewModel.structureHint)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                if !sortedWorkouts.isEmpty {
                    ForEach(sortedWorkouts) { workout in
                        Button {
                            handleWorkoutSelection(workout)
                        } label: {
                            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                HStack(alignment: .top, spacing: FFSpacing.sm) {
                                    Text("День \(workout.dayOrder)")
                                        .font(FFTypography.caption.weight(.semibold))
                                        .foregroundStyle(FFColors.textSecondary)

                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text(workout.title?.trimmedNilIfEmpty ?? "Тренировка")
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)

                                        let metadata = workoutMetadata(workout)
                                        if !metadata.isEmpty {
                                            Text(metadata.joined(separator: " • "))
                                                .font(FFTypography.caption)
                                                .foregroundStyle(FFColors.textSecondary)
                                        }

                                        if let scheduleLine = workoutScheduleLine(for: workout) {
                                            Text(scheduleLine)
                                                .font(FFTypography.caption.weight(.semibold))
                                                .foregroundStyle(FFColors.accent)
                                        }
                                    }

                                    Spacer(minLength: FFSpacing.xs)

                                    if viewModel.canInteractWithWorkoutStructureItem(workout.id) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(FFColors.textSecondary)
                                    }
                                }

                                if let note = workout.coachNote?.trimmedNilIfEmpty {
                                    Text(note)
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canInteractWithWorkoutStructureItem(workout.id))

                        if workout.id != sortedWorkouts.last?.id {
                            Divider()
                        }
                    }
                } else {
                    Text("Пока нет тренировок в программе")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func discoveryActionBlock(details _: ProgramDetails) -> some View {
        if viewModel.isProgramAlreadyActive {
            FFButton(
                title: "Программа уже получена",
                variant: .disabled,
                action: {}
            )
        } else {
            FFButton(
                title: "Получить программу",
                variant: viewModel.isPrimaryProgramActionEnabled ? .primary : .disabled,
                action: {
                    Task { await viewModel.handlePrimaryProgramAction() }
                }
            )
        }
    }

    private func discoveryValueCard(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Для кого")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text(audienceSummary(details: details))
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                let goals = discoveryGoals(details: details)
                if !goals.isEmpty {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        ForEach(goals, id: \.self) { goal in
                            HStack(alignment: .top, spacing: FFSpacing.xs) {
                                Circle()
                                    .fill(FFColors.accent)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)

                                Text(goal)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func discoveryFormatCard(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Как устроена программа")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                let rows = discoveryFormatRows(details: details)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text(row.title)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                        Text(row.value)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func discoveryCoachCard(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Автор программы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Button {
                    viewModel.openCreatorProfile()
                } label: {
                    HStack(spacing: FFSpacing.sm) {
                        if let avatarURL = viewModel.creatorCard?.avatar ?? details.influencer?.avatar.flatMap({ URL(string: $0.url) }) {
                            FFRemoteImage(url: avatarURL) {
                                Circle()
                                    .fill(FFColors.gray700)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(FFColors.gray700)
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                        }

                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(discoveryCoachName(details: details))
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)

                            if let bio = discoveryCoachBio(details: details) {
                                Text(bio)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                                    .lineLimit(3)
                            }
                        }

                        Spacer(minLength: FFSpacing.xs)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FFColors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func overviewCard(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("О программе")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(Array(overviewRows(details: details).enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: FFSpacing.sm) {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FFColors.textSecondary)
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(row.title)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                            Text(row.value)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textPrimary)
                        }

                        Spacer(minLength: FFSpacing.xs)
                    }

                    if index < overviewRows(details: details).count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var programStatusTitle: String {
        if viewModel.hasResumableWorkout {
            return "Тренировка в процессе"
        }
        if viewModel.isProgramAlreadyActive, !viewModel.isProgramScheduled {
            return "Программа не распланирована"
        }
        if viewModel.isProgramAlreadyActive, viewModel.hasTodayWorkout {
            return "Тренировка сегодня"
        }
        if viewModel.isProgramAlreadyActive {
            return "Следующая тренировка"
        }
        return "Программа ещё не начата"
    }

    private func programStatusLine(details: ProgramDetails) -> String? {
        if let hint = viewModel.primaryProgramActionHint?.trimmedNilIfEmpty {
            return hint
        }
        if let summary = programSummaryLine(
            workoutsCount: details.workouts?.count ?? 0,
            frequencyPerWeek: details.currentPublishedVersion?.frequencyPerWeek
        ) {
            return summary
        }
        return details.description?.trimmedNilIfEmpty
    }

    private var progressSummary: String? {
        guard viewModel.totalWorkoutsCount > 0 else { return nil }
        return "\(viewModel.completedWorkoutsCount) из \(viewModel.totalWorkoutsCount) тренировок"
    }

    private var progressValue: Double {
        guard viewModel.totalWorkoutsCount > 0 else { return 0 }
        return min(max(Double(viewModel.completedWorkoutsCount) / Double(viewModel.totalWorkoutsCount), 0), 1)
    }

    private func programSummaryLine(workoutsCount: Int, frequencyPerWeek: Int?) -> String? {
        var chunks: [String] = []

        if let frequencyPerWeek, frequencyPerWeek > 0 {
            chunks.append("\(frequencyPerWeek) \(pluralizedWorkoutsPerWeek(frequencyPerWeek))")
            let weeks = Int(ceil(Double(max(1, workoutsCount)) / Double(frequencyPerWeek)))
            if weeks > 0 {
                chunks.insert("\(weeks) \(pluralizedWeeks(weeks))", at: 0)
            }
        } else if workoutsCount > 0 {
            chunks.append("\(workoutsCount) \(pluralizedWorkouts(workoutsCount))")
        }

        return chunks.isEmpty ? nil : chunks.joined(separator: " • ")
    }

    private func programReferenceLine(details: ProgramDetails) -> String? {
        var parts: [String] = []

        if let summary = programSummaryLine(
            workoutsCount: details.workouts?.count ?? 0,
            frequencyPerWeek: details.currentPublishedVersion?.frequencyPerWeek
        ) {
            parts.append(summary)
        }

        if let level = localizedLevel(details.currentPublishedVersion?.level) {
            parts.append(level)
        }

        if let equipment = resolvedEquipment(details: details), !equipment.isEmpty {
            parts.append(equipment.prefix(2).joined(separator: ", "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func programDescriptionLine(details: ProgramDetails) -> String? {
        guard let description = details.description?.trimmedNilIfEmpty else { return nil }
        if description == programStatusLine(details: details) {
            return nil
        }
        return description
    }

    private func discoveryAuthorLine(details: ProgramDetails) -> String? {
        let authorName = viewModel.creatorCard?.displayName.trimmedNilIfEmpty ?? details.influencer?.displayName.trimmedNilIfEmpty
        let summary = programReferenceLine(details: details)

        if let authorName, let summary, !summary.isEmpty {
            return "Автор: \(authorName) • \(summary)"
        }
        if let authorName {
            return "Автор: \(authorName)"
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return nil
    }

    private func discoveryPreviewLine(details: ProgramDetails) -> String? {
        if let summary = programSummaryLine(
            workoutsCount: details.workouts?.count ?? 0,
            frequencyPerWeek: details.currentPublishedVersion?.frequencyPerWeek
        ) {
            return summary
        }
        if let duration = estimatedProgramDurationMinutes(details: details) {
            return "Средняя тренировка занимает около \(duration) мин."
        }
        return nil
    }

    private func discoveryGoals(details: ProgramDetails) -> [String] {
        let goals = details.goals?
            .compactMap(\.trimmedNilIfEmpty)
            .prefix(3)
            .map { $0 } ?? []

        if !goals.isEmpty {
            return goals
        }

        if let description = details.description?.trimmedNilIfEmpty {
            return [description]
        }

        return []
    }

    private func discoveryFormatRows(details: ProgramDetails) -> [(title: String, value: String)] {
        var rows: [(String, String)] = []

        if let summary = programSummaryLine(
            workoutsCount: details.workouts?.count ?? 0,
            frequencyPerWeek: details.currentPublishedVersion?.frequencyPerWeek
        ) {
            rows.append(("Ритм", summary))
        }

        if let duration = estimatedProgramDurationMinutes(details: details) {
            rows.append(("Длительность сессии", "Около \(duration) мин"))
        }

        if let level = localizedLevel(details.currentPublishedVersion?.level) {
            rows.append(("Уровень", level))
        }

        let equipment = equipmentFullSummary(details: details)
        if equipment != "Требования к оборудованию пока не указаны." {
            rows.append(("Оборудование", equipment))
        }

        return Array(rows.prefix(4))
    }

    private func discoveryHasCoachInfo(details: ProgramDetails) -> Bool {
        discoveryCoachName(details: details).isEmpty == false
    }

    private func discoveryCoachName(details: ProgramDetails) -> String {
        viewModel.creatorCard?.displayName.trimmedNilIfEmpty
            ?? details.influencer?.displayName.trimmedNilIfEmpty
            ?? "Атлет Fitfluence"
    }

    private func discoveryCoachBio(details: ProgramDetails) -> String? {
        viewModel.creatorCard?.bio?.trimmedNilIfEmpty
            ?? details.influencer?.bio?.trimmedNilIfEmpty
    }

    private func workoutScheduleLine(for workout: WorkoutTemplate) -> String? {
        if let reference = viewModel.scheduleReference(for: workout.id) {
            switch reference.status {
            case .inProgress:
                if Calendar.current.isDateInToday(reference.day) {
                    return "Сегодня"
                }
                return reference.dateText
            case .planned:
                if Calendar.current.isDateInToday(reference.day) {
                    return "Сегодня"
                }
                return reference.dateText
            case .completed:
                return reference.dateText
            case .missed, .skipped:
                return reference.dateText
            }
        }

        if viewModel.nextTemplateWorkoutId == workout.id, viewModel.hasResumableWorkout {
            return "В процессе"
        }

        return nil
    }

    private func handleWorkoutSelection(_ workout: WorkoutTemplate) {
        if displayMode == .discovery {
            let reference = viewModel.scheduleReference(for: workout.id)
            viewModel.previewWorkoutFromStructure(
                workout.id,
                plannedDay: reference?.day,
                plannedDateText: reference?.dateText,
                displayMode: .discovery
            )
            return
        }

        if viewModel.isProgramAlreadyActive, !viewModel.isProgramScheduled {
            isPlanningSetupPresented = true
            return
        }

        if viewModel.shouldLaunchWorkoutDirectly(for: workout.id) {
            viewModel.launchNextWorkoutIfPossible()
            return
        }

        if let reference = viewModel.scheduleReference(for: workout.id) {
            viewModel.previewWorkoutFromStructure(
                workout.id,
                plannedDay: reference.day,
                plannedDateText: reference.dateText,
                displayMode: .active
            )
            return
        }

        if viewModel.isProgramAlreadyActive {
            viewModel.previewWorkoutFromStructure(
                workout.id,
                plannedDay: viewModel.firstScheduledDay,
                plannedDateText: nil,
                displayMode: .active
            )
        }
    }

    private func openProgramSchedule(focusedDay: Date?) {
        PlanNavigationCoordinator.shared.request(day: focusedDay)
        onOpenProgramPlan?()
    }

    private func quickFactItems(details: ProgramDetails) -> [(title: String, value: String)] {
        var items: [(String, String)] = []

        if let level = localizedLevel(details.currentPublishedVersion?.level) {
            items.append(("Уровень", level))
        }

        items.append(("Частота", shortFrequencySummary(details: details)))

        if let duration = estimatedProgramDurationMinutes(details: details) {
            items.append(("Сессия", "~\(duration) мин"))
        }

        let equipment = equipmentHeroSummary(details: details)
        if equipment != "Не указано" {
            items.append(("Оборудование", equipment))
        }

        return Array(items.prefix(3))
    }

    private func overviewRows(details: ProgramDetails) -> [(title: String, value: String, systemImage: String)] {
        [
            ("Для кого", audienceSummary(details: details), "person.2.fill"),
            ("Частота", frequencySummary(details: details), "calendar"),
            ("Формат", formatSummary(details: details), "list.bullet.rectangle"),
            ("Оборудование", equipmentFullSummary(details: details), "dumbbell.fill"),
            ("После записи", postEnrollmentSummary(details: details), "arrow.triangle.branch"),
        ]
    }

    private func audienceSummary(details: ProgramDetails) -> String {
        let goals = details.goals?.compactMap(\.trimmedNilIfEmpty) ?? []
        let level = localizedLevel(details.currentPublishedVersion?.level)

        if let level, !goals.isEmpty {
            return "Подойдёт для уровня \(level.lowercased()) с фокусом на \(goals.prefix(2).joined(separator: ", "))."
        }
        if let level {
            return "Подойдёт для уровня \(level.lowercased())."
        }
        if !goals.isEmpty {
            return "Фокус программы: \(goals.prefix(3).joined(separator: ", "))."
        }
        if let description = details.description?.trimmedNilIfEmpty {
            return description
        }
        return "Кому именно подходит программа, автор отдельно не уточнил."
    }

    private func shortFrequencySummary(details: ProgramDetails) -> String {
        if let frequency = details.currentPublishedVersion?.frequencyPerWeek, frequency > 0 {
            return "\(frequency) дн/нед"
        }
        if let workoutsCount = details.workouts?.count, workoutsCount > 0 {
            return "\(workoutsCount) тренировок"
        }
        return "Не указана"
    }

    private func frequencySummary(details: ProgramDetails) -> String {
        if let frequency = details.currentPublishedVersion?.frequencyPerWeek, frequency > 0 {
            let workoutsCount = details.workouts?.count ?? 0
            if workoutsCount > 0 {
                let weeks = Int(ceil(Double(workoutsCount) / Double(frequency)))
                return "\(frequency) \(pluralizedWeeklyWorkouts(frequency)) в неделю. Полный цикл примерно на \(weeks) \(pluralizedWeeks(weeks))."
            }
            return "\(frequency) \(pluralizedWeeklyWorkouts(frequency)) в неделю."
        }
        if let workoutsCount = details.workouts?.count, workoutsCount > 0 {
            return "Частота занятий отдельно не указана. Сейчас видно \(workoutsCount) \(pluralizedWorkouts(workoutsCount)) в составе программы."
        }
        return "Частота тренировок пока не указана."
    }

    private func shortFormatSummary(details: ProgramDetails) -> String {
        let workoutsCount = details.workouts?.count ?? 0
        if workoutsCount > 0 {
            return "\(workoutsCount) \(pluralizedWorkouts(workoutsCount))"
        }
        if let duration = estimatedProgramDurationMinutes(details: details) {
            return "~\(duration) мин"
        }
        return "Структурированный план"
    }

    private func formatSummary(details: ProgramDetails) -> String {
        var parts: [String] = []
        let workoutsCount = details.workouts?.count ?? 0

        if workoutsCount > 0 {
            parts.append("Структурированный план из \(workoutsCount) \(pluralizedWorkouts(workoutsCount)).")
        } else {
            parts.append("Список тренировок пока не раскрыт в карточке программы.")
        }

        if let duration = estimatedProgramDurationMinutes(details: details) {
            parts.append("Средняя сессия занимает около \(duration) мин.")
        }

        return parts.joined(separator: " ")
    }

    private func equipmentHeroSummary(details: ProgramDetails) -> String {
        if let equipment = resolvedEquipment(details: details), !equipment.isEmpty {
            if equipment.count <= 2 {
                return equipment.joined(separator: ", ")
            }
            return "\(equipment.prefix(2).joined(separator: ", ")) +\(equipment.count - 2)"
        }
        return "Не указано"
    }

    private func equipmentFullSummary(details: ProgramDetails) -> String {
        if let equipment = resolvedEquipment(details: details), !equipment.isEmpty {
            return equipment.joined(separator: ", ")
        }
        return "Требования к оборудованию пока не указаны."
    }

    private func postEnrollmentSummary(details: ProgramDetails) -> String {
        if viewModel.hasResumableWorkout {
            return "Программа уже активна. Основная кнопка вернёт к текущей тренировке, а дополнительная поможет разложить оставшиеся дни по плану."
        }
        if viewModel.isProgramAlreadyActive, !viewModel.isProgramScheduled {
            return "Программа подключена, но тренировки ещё не разложены по дням. Сначала сохраните расписание, затем откроем доступные сессии."
        }
        if viewModel.isProgramAlreadyActive {
            return "Программа уже активна. Основная кнопка откроет ближайшую тренировку, затем при желании можно сохранить весь цикл в календарь."
        }
        if details.currentPublishedVersion?.id != nil {
            return "После записи предложим сразу начать первую тренировку и, если нужно, разложить программу по плану."
        }
        return "Старт недоступен, пока у программы нет опубликованной версии."
    }

    private func detailLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.body)
                .foregroundStyle(FFColors.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }

    private func workoutMetadata(_ workout: WorkoutTemplate) -> [String] {
        var items: [String] = []

        let exercisesCount = workout.exercises?.count ?? 0
        if exercisesCount > 0 {
            items.append("\(exercisesCount) \(pluralizedExercises(exercisesCount))")
        }

        if let duration = estimatedDurationMinutes(template: workout) {
            items.append("~\(duration) мин")
        }

        return items
    }

    private func estimatedProgramDurationMinutes(details: ProgramDetails) -> Int? {
        let estimates = (details.workouts ?? [])
            .compactMap { estimatedDurationMinutes(template: $0) }
        guard !estimates.isEmpty else { return nil }
        return max(10, estimates.reduce(0, +) / estimates.count)
    }

    private func estimatedDurationMinutes(template: WorkoutTemplate) -> Int? {
        let exercises = template.exercises ?? []
        guard !exercises.isEmpty else { return nil }

        let totalSets = exercises.reduce(0) { $0 + max(1, $1.sets) }
        let totalRest = exercises.reduce(0) { partial, exercise in
            partial + (exercise.restSeconds ?? 45) * max(0, exercise.sets - 1)
        }
        return max(10, (totalSets * 90 + totalRest) / 60)
    }

    private func resolvedEquipment(details: ProgramDetails) -> [String]? {
        guard let requirements = details.currentPublishedVersion?.requirements else {
            return nil
        }

        if case let .array(values)? = requirements["equipment"] {
            let equipment = values.compactMap { value -> String? in
                guard case let .string(text) = value else { return nil }
                return text.trimmedNilIfEmpty
            }
            if !equipment.isEmpty {
                return equipment
            }
        }

        if case let .string(value)? = requirements["equipment"] {
            let items = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                return items
            }
        }

        return nil
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .fill(FFColors.gray700)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(FFColors.primary)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }

    private func parameterChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(2)
        }
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

    private func localizedLevel(_ value: String?) -> String? {
        guard let value = value?.trimmedNilIfEmpty else { return nil }
        switch value.uppercased() {
        case "BEGINNER":
            return "Начинающий"
        case "INTERMEDIATE":
            return "Средний"
        case "ADVANCED":
            return "Продвинутый"
        default:
            return value
        }
    }

    private func pluralizedWeeks(_ value: Int) -> String {
        let remainder10 = value % 10
        let remainder100 = value % 100
        if remainder10 == 1, remainder100 != 11 {
            return "неделя"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "недели"
        }
        return "недель"
    }

    private func pluralizedWorkouts(_ value: Int) -> String {
        let remainder10 = value % 10
        let remainder100 = value % 100
        if remainder10 == 1, remainder100 != 11 {
            return "тренировка"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "тренировки"
        }
        return "тренировок"
    }

    private func pluralizedWeeklyWorkouts(_ value: Int) -> String {
        pluralizedWorkouts(value)
    }

    private func pluralizedWorkoutsPerWeek(_ value: Int) -> String {
        switch value {
        case 1:
            return "тренировка в неделю"
        case 2 ... 4:
            return "тренировки в неделю"
        default:
            return "тренировок в неделю"
        }
    }

    private func pluralizedExercises(_ value: Int) -> String {
        let remainder10 = value % 10
        let remainder100 = value % 100
        if remainder10 == 1, remainder100 != 11 {
            return "упражнение"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "упражнения"
        }
        return "упражнений"
    }

    private func resolveURL(_ pathOrURL: String) -> URL? {
        if let absolute = URL(string: pathOrURL), absolute.scheme != nil {
            return absolute
        }

        guard let baseURL = environment?.backendBaseURL else {
            return URL(string: pathOrURL)
        }
        let normalizedPath = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL
        return baseURL.appendingPathComponent(normalizedPath)
    }

    private func resolveImageURL(_ pathOrURL: String?) -> URL? {
        guard let pathOrURL, !pathOrURL.isEmpty else { return nil }
        return resolveURL(pathOrURL)
    }
}

struct ProgramOnboardingView: View {
    let route: ProgramDetailsViewModel.ProgramOnboardingRoute
    let isPreparingFirstWorkout: Bool
    let onStartFirstWorkout: () -> Void
    let onPlanProgram: (Date, Set<ProgramScheduleWeekday>) -> Void
    let onOpenProgramPlan: () -> Void
    @State private var isPlanningPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Программа подключена")
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(route.programTitle)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                        if let summaryLine = route.summaryLine {
                            Text(summaryLine)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                if let authorName = route.authorName?.trimmedNilIfEmpty {
                    FFCard {
                        HStack(spacing: FFSpacing.sm) {
                            if let avatarURL = route.authorAvatarURL {
                                FFRemoteImage(url: avatarURL) {
                                    Circle()
                                        .fill(FFColors.gray700)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(FFColors.gray700)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(FFColors.gray300)
                                    }
                            }
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text("Атлет программы")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                                Text(authorName)
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                            }
                            Spacer(minLength: FFSpacing.xs)
                        }
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Что делать дальше")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(nextStepSummaryText)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(route.previewSectionTitle)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        if route.previewItems.isEmpty {
                            Text("Список тренировок появится после синхронизации.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        } else {
                            ForEach(Array(route.previewItems.prefix(5).enumerated()), id: \.offset) { index, item in
                                Text("\(index + 1). \(item)")
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                        if route.isPendingEnrollment {
                            Text("Оффлайн: запись в программу сохранена локально и отправится при появлении сети.")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.primary)
                        }
                        if let firstWorkoutTitle = route.firstWorkoutTitle?.trimmedNilIfEmpty {
                            Divider()
                            Text("Первая тренировка: \(firstWorkoutTitle)")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                if route.canPlanProgram {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Распланируйте программу")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text(planningSummaryText)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                if route.canStartFirstWorkout {
                    FFButton(
                        title: "Начать первую тренировку",
                        variant: .primary,
                        isLoading: isPreparingFirstWorkout,
                        action: onStartFirstWorkout,
                    )
                }
                if route.canPlanProgram {
                    FFButton(
                        title: "Распланировать тренировки",
                        variant: route.canStartFirstWorkout ? .secondary : .primary,
                        action: {
                            isPlanningPresented = true
                        },
                    )
                }
                FFButton(
                    title: "Открыть календарный план",
                    variant: .secondary,
                    action: onOpenProgramPlan,
                )
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .ffScreenBackground()
        .sheet(isPresented: $isPlanningPresented) {
            ProgramPlanningSetupView(
                route: route,
                onClose: {
                    isPlanningPresented = false
                },
                onApply: { startDate, weekdays in
                    isPlanningPresented = false
                    onPlanProgram(startDate, weekdays)
                },
            )
        }
        .task {
            ClientAnalytics.track(
                .programOnboardingScreenOpened,
                properties: ["program_id": route.programId],
            )
        }
    }

    private var planningSummaryText: String {
        let recommendedDays = ProgramScheduleWeekday.recommended(for: recommendedFrequency)
            .map(\.shortTitle)
            .joined(separator: " • ")
        return "Мы предложим удобные дни недели, покажем первые тренировки и сразу сохраним всё в ваш календарь. Рекомендация: \(recommendedDays)."
    }

    private var nextStepSummaryText: String {
        if route.isPendingEnrollment {
            return "Запись сохранена локально. Как только сеть появится, программа синхронизируется. Следующий обязательный шаг после подключения: выбрать дни и сохранить расписание."
        }
        if route.canStartFirstWorkout {
            return "Самый прямой путь: сразу запустить первую тренировку. Если хотите сначала разложить весь цикл по календарю, это остаётся вторым шагом."
        }
        if route.canPlanProgram {
            return "Сначала сохраните расписание. После этого тренировки будут открываться в понятном порядке из плана, а не из общего списка."
        }
        return "Откройте календарный план, чтобы посмотреть ближайшие тренировки и выбрать следующий шаг."
    }

    private var recommendedFrequency: Int {
        route.frequencyPerWeek ?? max(1, min(route.plannableWorkouts.count, 3))
    }
}

private struct ProgramPlanningSetupView: View {
    let route: ProgramDetailsViewModel.ProgramOnboardingRoute
    let title: String
    let description: String
    let buttonTitle: String
    let onClose: () -> Void
    let onApply: (Date, Set<ProgramScheduleWeekday>) -> Void

    @State private var selectedDays: Set<ProgramScheduleWeekday>
    @State private var startDate: Date

    init(
        route: ProgramDetailsViewModel.ProgramOnboardingRoute,
        title: String = "Настроим расписание",
        description: String = "Выберите дни недели. Мы равномерно разложим все тренировки программы по календарю.",
        buttonTitle: String = "Сохранить в план",
        initialSelectedDays: Set<ProgramScheduleWeekday> = [],
        initialStartDate: Date? = nil,
        onClose: @escaping () -> Void,
        onApply: @escaping (Date, Set<ProgramScheduleWeekday>) -> Void,
    ) {
        self.route = route
        self.title = title
        self.description = description
        self.buttonTitle = buttonTitle
        self.onClose = onClose
        self.onApply = onApply
        let recommendedDays = initialSelectedDays.isEmpty ? Set(
            ProgramScheduleWeekday.recommended(
                for: route.frequencyPerWeek ?? max(1, min(route.plannableWorkouts.count, 3))
            )
        ) : initialSelectedDays
        _selectedDays = State(initialValue: recommendedDays)
        _startDate = State(initialValue: initialStartDate ?? Self.initialStartDate(for: recommendedDays))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: FFSpacing.md) {
                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                Text(title)
                                    .font(FFTypography.h2)
                                    .foregroundStyle(FFColors.textPrimary)
                                Text(description)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                Text("Дни тренировок")
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: FFSpacing.xs), count: 4), spacing: FFSpacing.xs) {
                                    ForEach(ProgramScheduleWeekday.allCases) { day in
                                        weekdayChip(day)
                                    }
                                }
                                Text(daySelectionHint)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }

                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                Text("Дата старта")
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                DatePicker(
                                    "Начать с",
                                    selection: $startDate,
                                    in: Calendar.current.startOfDay(for: Date())...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .tint(FFColors.accent)
                            }
                        }

                        FFCard {
                            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                                Text("Предпросмотр")
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                if let validationErrorText {
                                    Text(validationErrorText)
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.danger)
                                }

                                ForEach(Array(previewRows.enumerated()), id: \.offset) { _, row in
                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text(row.dateText)
                                            .font(FFTypography.caption.weight(.semibold))
                                            .foregroundStyle(FFColors.accent)
                                        Text(row.title)
                                            .font(FFTypography.body)
                                            .foregroundStyle(FFColors.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, FFSpacing.xxs)
                                }
                            }
                        }

                        FFButton(
                            title: buttonTitle,
                            variant: validationResult == nil ? .disabled : .primary,
                            action: {
                                guard validationResult != nil else { return }
                                onApply(startDate, selectedDays)
                            },
                        )
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.md)
                }
            }
            .navigationTitle("План программы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func weekdayChip(_ day: ProgramScheduleWeekday) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            if isSelected {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
        } label: {
            Text(day.shortTitle)
                .font(FFTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, FFSpacing.sm)
                .ffSelectableSurface(isSelected: isSelected, emphasis: .accent)
        }
        .buttonStyle(.plain)
    }

    private var previewRows: [(dateText: String, title: String)] {
        guard let validationResult else { return [] }
        let dates = validationResult.dates.prefix(min(route.plannableWorkouts.count, 4))
        return Array(zip(dates, route.plannableWorkouts.prefix(4))).map { date, workout in
            (
                date.formatted(date: .abbreviated, time: .omitted),
                "День \(workout.dayOrder) • \(workout.title)"
            )
        }
    }

    private var validationResult: ProgramDetailsViewModel.ScheduleValidationResult? {
        ProgramDetailsViewModel.validateSchedule(
            startDate: startDate,
            weekdays: selectedDays,
            plannableWorkouts: route.plannableWorkouts,
            fixedAnchors: route.fixedAnchors,
        )
    }

    private var validationErrorText: String? {
        guard !selectedDays.isEmpty else { return nil }
        guard !route.plannableWorkouts.isEmpty else {
            return "Оставшихся тренировок для перепланирования нет."
        }
        guard validationResult == nil else { return nil }
        return "Выбранные дни не помещаются между уже зафиксированными тренировками программы."
    }

    private var daySelectionHint: String {
        if selectedDays.isEmpty {
            return "Выберите хотя бы один день недели."
        }
        let selected = selectedDays.count
        let recommended = route.frequencyPerWeek ?? max(1, min(route.plannableWorkouts.count, 3))
        if selected == recommended {
            return "Выбран рекомендованный ритм: \(selected) \(selected == 1 ? "день" : "дня") в неделю."
        }
        return "Сейчас выбрано \(selected) \(selected == 1 ? "день" : "дня") в неделю."
    }

    private static func initialStartDate(for weekdays: Set<ProgramScheduleWeekday>) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        var cursor = today
        for _ in 0 ..< 14 {
            if let weekday = ProgramScheduleWeekday.from(date: cursor, calendar: Calendar.current),
               weekdays.contains(weekday)
            {
                return cursor
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return today
    }
}

struct WorkoutIntroView: View {
    let workout: WorkoutDetailsModel
    var primaryActionTitle: String = "Начать тренировку"
    var dateBadgeText: String? = nil
    var helperText: String? = nil
    var showsPrimaryAction = true
    let onPrimaryAction: () -> Void

    @State private var selectedExercise: WorkoutExercise?

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(workout.title)
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)

                        if let dateBadgeText = dateBadgeText?.trimmedNilIfEmpty {
                            Text(dateBadgeText)
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                                .padding(.horizontal, FFSpacing.sm)
                                .padding(.vertical, FFSpacing.xs)
                                .background(FFColors.surface)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(FFColors.gray700, lineWidth: 1)
                                }
                        }

                        if let helperText = helperText?.trimmedNilIfEmpty {
                            Text(helperText)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        Text("Упражнения")
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)

                        ForEach(Array(workout.exercises.enumerated()), id: \.offset) { index, exercise in
                            Button {
                                selectedExercise = exercise
                            } label: {
                                HStack(alignment: .top, spacing: FFSpacing.sm) {
                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text("\(index + 1). \(exercise.name)")
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)

                                        Text(exerciseSummary(exercise))
                                            .font(FFTypography.caption)
                                            .foregroundStyle(FFColors.textSecondary)

                                        if let notes = exercise.notes?.trimmedNilIfEmpty {
                                            Text(notes)
                                                .font(FFTypography.caption)
                                                .foregroundStyle(FFColors.textSecondary)
                                        }
                                    }

                                    Spacer(minLength: FFSpacing.xs)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(FFColors.textSecondary.opacity(0.8))
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if index < workout.exercises.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

                if showsPrimaryAction {
                    FFButton(title: primaryActionTitle, variant: .primary, action: onPrimaryAction)
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .ffScreenBackground()
        .sheet(item: $selectedExercise) { exercise in
            WorkoutExerciseDetailsSheet(exercise: exercise)
        }
    }

    private func exerciseSummary(_ exercise: WorkoutExercise) -> String {
        var parts: [String] = ["\(exercise.sets) подходов"]

        if let repsRange = repsRangeText(for: exercise) {
            parts.append(repsRange)
        }

        if let restSeconds = exercise.restSeconds {
            parts.append("отдых \(restSeconds) сек")
        }

        if let targetRpe = exercise.targetRpe {
            parts.append("RPE \(targetRpe)")
        }

        return parts.joined(separator: " • ")
    }

    private func repsRangeText(for exercise: WorkoutExercise) -> String? {
        switch (exercise.repsMin, exercise.repsMax) {
        case let (min?, max?) where min == max:
            return "\(min) повторений"
        case let (min?, max?):
            return "\(min)-\(max) повторений"
        case let (min?, nil):
            return "от \(min) повторений"
        case let (nil, max?):
            return "до \(max) повторений"
        case (nil, nil):
            return nil
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func isCreatorFollowForbidden(_ apiError: APIError) -> Bool {
    if apiError == .forbidden {
        return true
    }
    if case let .httpError(statusCode, _) = apiError {
        return statusCode == 403
    }
    return false
}
