import Observation
import SwiftUI

@Observable
@MainActor
final class ProgramDetailsViewModel {
    struct SelectedWorkout: Equatable, Identifiable {
        let userSub: String
        let programId: String
        let workoutId: String
        let presetWorkout: WorkoutDetailsModel?
        let source: WorkoutSource
        let isFirstWorkoutAfterEnrollment: Bool

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
        let fallbackWorkoutTemplateId: String?
        let isPendingEnrollment: Bool

        var canStartFirstWorkout: Bool {
            firstWorkoutInstanceId != nil || fallbackWorkoutTemplateId != nil
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
    var lastCompletionTitle: String?
    var isProgramAlreadyActive = false
    var nextWorkoutInstanceId: String?
    var nextWorkoutInstanceTitle: String?
    var enrollmentConfirmation: ProgramOnboardingRoute?
    var workoutIntro: WorkoutIntroRoute?
    var isPreparingFirstWorkout = false
    var creatorCard: InfluencerPublicCard?
    var isCreatorFollowLoading = false
    var creatorInfoMessage: String?
    var creatorProfileRoute: InfluencerPublicCard?

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
        if isProgramAlreadyActive, let nextWorkoutInstanceId {
            selectedWorkout = SelectedWorkout(
                userSub: userSub,
                programId: programId,
                workoutId: nextWorkoutInstanceId,
                presetWorkout: nil,
                source: .program,
                isFirstWorkoutAfterEnrollment: false,
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
        if isProgramAlreadyActive {
            return "Продолжить программу"
        }
        return "Начать программу"
    }

    var isPrimaryProgramActionEnabled: Bool {
        if isStartingProgram {
            return false
        }
        if isProgramAlreadyActive {
            return nextWorkoutInstanceId != nil
        }
        return details?.currentPublishedVersion?.id != nil
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
        isWorkoutsPresented = true
    }

    func workoutPicked(_ workoutID: String) {
        selectedWorkout = SelectedWorkout(
            userSub: userSub,
            programId: programId,
            workoutId: workoutID,
            presetWorkout: nil,
            source: .program,
            isFirstWorkoutAfterEnrollment: false,
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
            isFirstWorkoutAfterEnrollment: route.isFirstWorkoutAfterEnrollment,
        )
    }

    func dismissEnrollmentConfirmation() {
        enrollmentConfirmation = nil
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

        if let fallbackWorkoutTemplateId = route.fallbackWorkoutTemplateId,
           let intro = prepareTemplateWorkoutIntro(
               templateWorkoutId: fallbackWorkoutTemplateId,
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
                    "workout_id": fallbackWorkoutTemplateId,
                    "source": "template_fallback",
                ],
            )
            return
        }

        error = UserFacingError(
            kind: .unknown,
            title: "Не удалось подготовить тренировку",
            message: "Откройте план программы и выберите тренировку вручную.",
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
        completedWorkoutsCount = statuses.values.count(where: { $0 == .completed })
        upcomingWorkoutTitle = workouts
            .sorted(by: { $0.dayOrder < $1.dayOrder })
            .first(where: { statuses[$0.id] != .completed })?
            .title ?? workouts.sorted(by: { $0.dayOrder < $1.dayOrder }).first?.title

        if let last = await trainingStore.history(userSub: userSub, source: nil, limit: 40)
            .first(where: { $0.programId == programId })
        {
            let minutes = max(1, last.durationSeconds / 60)
            let volume = last.volume > 0 ? " • объём \(Int(last.volume)) кг" : ""
            lastCompletionTitle = "\(last.finishedAt.formatted(date: .abbreviated, time: .shortened)) • \(minutes) мин\(volume)"
        } else {
            lastCompletionTitle = nil
        }
    }

    private var cacheKey: String {
        "program.details:\(programId)"
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
        guard let details else { return }
        let sortedWorkouts = (details.workouts ?? []).sorted(by: { $0.dayOrder < $1.dayOrder })
        let fallbackWorkout = sortedWorkouts.first
        let fallbackTitle = fallbackWorkout?.title?.trimmedNilIfEmpty ?? fallbackWorkout.map { "День \($0.dayOrder)" }
        let preview = onboardingPreview(for: sortedWorkouts)
        let frequencyPerWeek = details.currentPublishedVersion?.frequencyPerWeek
        let level = localizedLevel(details.currentPublishedVersion?.level)
        let estimatedDurationMinutes = estimatedProgramDurationMinutes(details: details)
        let authorName = creatorCard?.displayName ?? details.influencer?.displayName.trimmedNilIfEmpty
        let authorAvatar = creatorCard?.avatar ?? details.influencer?.avatar.flatMap { URL(string: $0.url) }

        let firstWorkoutInstanceId = nextWorkoutInstanceId?.trimmedNilIfEmpty
        let firstWorkoutTitle = nextWorkoutInstanceTitle?.trimmedNilIfEmpty ?? fallbackTitle

        enrollmentConfirmation = ProgramOnboardingRoute(
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
            fallbackWorkoutTemplateId: firstWorkoutInstanceId == nil ? fallbackWorkout?.id : nil,
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

        _ = await SyncCoordinator.shared.enqueueStartWorkout(
            namespace: userSub,
            workoutInstanceId: workoutInstanceId,
            startedAt: Date(),
        )

        if networkMonitor.currentStatus, let athleteTrainingClient {

            let detailsResult = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId)
            switch detailsResult {
            case let .success(details):
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

    private func prepareTemplateWorkoutIntro(
        templateWorkoutId: String,
        programId: String,
        isFirstWorkoutAfterEnrollment: Bool,
    ) -> WorkoutIntroRoute? {
        guard let template = details?.workouts?.first(where: { $0.id == templateWorkoutId }) else {
            return nil
        }

        let mapped = mapTemplateWorkout(template)
        return WorkoutIntroRoute(
            userSub: userSub,
            programId: programId,
            workoutId: templateWorkoutId,
            source: .program,
            workout: mapped,
            isFirstWorkoutAfterEnrollment: isFirstWorkoutAfterEnrollment,
        )
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

        let result: Result<Void, APIError> = switch action {
        case .follow:
            await programsClient.followCreator(influencerId: creatorCard.id)
        case .unfollow:
            await programsClient.unfollowCreator(influencerId: creatorCard.id)
        }

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

        let result = await athleteTrainingClient.activeEnrollmentProgress()
        switch result {
        case let .success(progress):
            let isCurrentProgram = progress.programId == programId
            isProgramAlreadyActive = isCurrentProgram

            guard isCurrentProgram else {
                nextWorkoutInstanceId = nil
                nextWorkoutInstanceTitle = nil
                return
            }

            nextWorkoutInstanceId = progress.nextWorkoutId
            nextWorkoutInstanceTitle = progress.nextWorkoutTitle

            if let completed = progress.completedSessions {
                completedWorkoutsCount = completed
            }
            if let total = progress.totalSessions {
                totalWorkoutsCount = total
            }
            if let nextWorkoutTitle = progress.nextWorkoutTitle?.trimmedNilIfEmpty {
                upcomingWorkoutTitle = nextWorkoutTitle
            }

        case let .failure(apiError):
            if apiError == .offline {
                return
            }
        }
    }

    private struct PendingEnrollmentSnapshot: Codable, Equatable, Sendable {
        let id: String
        let programId: String
        let programVersionId: String
        let createdAt: Date
    }
}

struct ProgramDetailsScreen: View {
    @State var viewModel: ProgramDetailsViewModel
    @State private var isProgramScreenOpenTracked = false
    let apiClient: APIClientProtocol?
    let environment: AppEnvironment?
    let onOpenProgramPlan: (() -> Void)?
    let onOpenWorkoutHub: (() -> Void)?
    let onOpenProgram: ((String) -> Void)?

    init(
        viewModel: ProgramDetailsViewModel,
        apiClient: APIClientProtocol?,
        environment: AppEnvironment? = nil,
        onOpenProgramPlan: (() -> Void)? = nil,
        onOpenWorkoutHub: (() -> Void)? = nil,
        onOpenProgram: ((String) -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.apiClient = apiClient
        self.environment = environment
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
                    header(details: details)
                    authorCard(details: details)
                    parametersCard(details: details)
                    benefitsCard(details: details)
                    workouts(details: details)
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
        .background(FFColors.background)
        .safeAreaInset(edge: .bottom) {
            if let details = viewModel.details {
                stickyPrimaryAction(details: details)
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
                .navigationTitle("Тренировки")
            } else {
                FFErrorState(
                    title: "Тренировки недоступны",
                    message: "Проверьте конфигурацию API-клиента для загрузки тренировок.",
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
                onOpenProgramPlan: {
                    ClientAnalytics.track(
                        .programOnboardingOpenPlanTapped,
                        properties: ["program_id": route.programId],
                    )
                    viewModel.dismissEnrollmentConfirmation()
                    onOpenProgramPlan?()
                },
            )
            .navigationTitle("Программа активирована")
        }
        .navigationDestination(item: $viewModel.workoutIntro) { route in
            WorkoutIntroView(
                workout: route.workout,
                onStartWorkout: {
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
                    onOpenProgram?(programID)
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
                isFirstWorkoutInProgramFlow: selectedWorkout.isFirstWorkoutAfterEnrollment,
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

    private func header(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text(details.title)
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.leading)

                if let shortDescription = details.description?.trimmedNilIfEmpty {
                    Text(shortDescription)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }

                if let imageURL = resolveImageURL(details.cover?.url ?? details.media?.first?.url) {
                    FFRemoteImage(url: imageURL) {
                        placeholderImage
                    }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                }
            }
        }
    }

    private func authorCard(details: ProgramDetails) -> some View {
        let creatorName = viewModel.creatorCard?.displayName
            ?? details.influencer?.displayName.trimmedNilIfEmpty
            ?? "Атлет не указан"
        let creatorTag = details.goals?.first?.trimmedNilIfEmpty
        let trustLine = viewModel.creatorCard?.bio?.trimmedNilIfEmpty
            ?? details.influencer?.bio?.trimmedNilIfEmpty
        let canOpenProfile = viewModel.creatorCard != nil

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Атлет программы")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textSecondary)

                Button {
                    if canOpenProfile {
                        viewModel.openCreatorProfile()
                    }
                } label: {
                    HStack(spacing: FFSpacing.sm) {
                        authorAvatar(details: details)

                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(creatorName)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                                .lineLimit(1)

                            if let creatorTag {
                                Text(creatorTag)
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.accent)
                                    .padding(.horizontal, FFSpacing.xs)
                                    .padding(.vertical, FFSpacing.xxs)
                                    .background(FFColors.accent.opacity(0.14))
                                    .clipShape(Capsule())
                            }

                            if let trustLine {
                                Text(trustLine)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: FFSpacing.sm)

                        if canOpenProfile {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canOpenProfile)

                if let infoMessage = viewModel.creatorInfoMessage {
                    Text(infoMessage)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private func authorAvatar(details: ProgramDetails) -> some View {
        Group {
            if let creatorURL = resolvedCreatorAvatarURL(details: details) {
                FFRemoteImage(url: creatorURL) {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(FFColors.gray700)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FFColors.gray300)
            }
    }

    private func parametersCard(details: ProgramDetails) -> some View {
        let parameters = parameterItems(details: details)

        guard !parameters.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Параметры программы")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FFSpacing.xs) {
                        ForEach(parameters, id: \.title) { item in
                            parameterChip(title: item.title, value: item.value)
                        }
                    }
                }
            },
        )
    }

    private func benefitsCard(details: ProgramDetails) -> some View {
        let benefits = benefitItems(details: details)

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Что вы получите")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(Array(benefits.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: FFSpacing.xs) {
                        Circle()
                            .fill(FFColors.accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(text)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }

    private func workouts(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Тренировки программы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if let workouts = details.workouts, !workouts.isEmpty {
                    FFButton(
                        title: "Открыть тренировки",
                        variant: .secondary,
                        action: { viewModel.openWorkouts() },
                    )

                    ForEach(workouts.sorted(by: { $0.dayOrder < $1.dayOrder })) { workout in
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("День \(workout.dayOrder)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.accent)
                            Text(workout.title ?? "Тренировка")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            if let workoutTitle = viewModel.upcomingWorkoutTitle,
                               workoutTitle == (workout.title ?? "Тренировка")
                            {
                                Text("Следующая по плану")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.accent)
                            }
                            if let note = workout.coachNote, !note.isEmpty {
                                Text(note)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                        .padding(.vertical, FFSpacing.xs)
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
    private func stickyPrimaryAction(details: ProgramDetails) -> some View {
        if details.currentPublishedVersion?.id != nil {
            VStack(spacing: FFSpacing.xs) {
                Divider()
                if viewModel.isProgramAlreadyActive {
                    Text("Программа уже активна. Можно продолжить с ближайшей тренировки.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                FFButton(
                    title: viewModel.primaryProgramActionTitle,
                    variant: viewModel.isPrimaryProgramActionEnabled ? .primary : .disabled,
                    action: { Task { await viewModel.handlePrimaryProgramAction() } },
                )
                .accessibilityLabel(viewModel.primaryProgramActionTitle)
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.xs)
            .padding(.bottom, FFSpacing.xs)
            .background(FFColors.background.opacity(0.96))
        } else {
            EmptyView()
        }
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

    private func parameterItems(details: ProgramDetails) -> [(title: String, value: String)] {
        var items: [(String, String)] = []

        if let goal = details.goals?.compactMap(\.trimmedNilIfEmpty).first {
            items.append(("Цель", goal))
        }

        if let level = localizedLevel(details.currentPublishedVersion?.level) {
            items.append(("Уровень", level))
        }

        if let frequencyPerWeek = details.currentPublishedVersion?.frequencyPerWeek, frequencyPerWeek > 0 {
            items.append(("Тренировок в неделю", "\(frequencyPerWeek)"))
            if let workoutsCount = details.workouts?.count, workoutsCount > 0 {
                let weeks = Int(ceil(Double(workoutsCount) / Double(frequencyPerWeek)))
                items.append(("Длительность", "\(weeks) \(pluralizedWeeks(weeks))"))
            }
        }

        if let equipment = equipmentSummary(details: details) {
            items.append(("Оборудование", equipment))
        }

        return items
    }

    private func benefitItems(details: ProgramDetails) -> [String] {
        if let description = details.description?.trimmedNilIfEmpty {
            let separators = CharacterSet(charactersIn: ".!\n•")
            let lines = description
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                return Array(lines.prefix(3))
            }
        }

        if let goals = details.goals?.compactMap(\.trimmedNilIfEmpty), !goals.isEmpty {
            return Array(goals.prefix(3))
        }

        return ["Структурированная программа тренировок от атлета."]
    }

    private func equipmentSummary(details: ProgramDetails) -> String? {
        guard let requirements = details.currentPublishedVersion?.requirements else {
            return nil
        }

        if case let .array(values)? = requirements["equipment"] {
            let equipment = values.compactMap { value -> String? in
                guard case let .string(text) = value else { return nil }
                return text.trimmedNilIfEmpty
            }
            if !equipment.isEmpty {
                return equipment.prefix(3).joined(separator: ", ")
            }
        }

        if case let .string(value)? = requirements["equipment"] {
            return value.trimmedNilIfEmpty
        }

        return nil
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

    private func resolvedCreatorAvatarURL(details: ProgramDetails) -> URL? {
        if let avatar = viewModel.creatorCard?.avatar {
            return resolveURL(avatar.absoluteString)
        }
        if let influencerAvatar = details.influencer?.avatar?.url {
            return resolveURL(influencerAvatar)
        }
        return nil
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
    let onOpenProgramPlan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Программа активирована")
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

                if route.canStartFirstWorkout {
                    FFButton(
                        title: "Начать первую тренировку",
                        variant: .primary,
                        isLoading: isPreparingFirstWorkout,
                        action: onStartFirstWorkout,
                    )
                }
                FFButton(
                    title: "Посмотреть план",
                    variant: .secondary,
                    action: onOpenProgramPlan,
                )
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .task {
            ClientAnalytics.track(
                .programOnboardingScreenOpened,
                properties: ["program_id": route.programId],
            )
        }
    }
}

struct WorkoutIntroView: View {
    let workout: WorkoutDetailsModel
    let onStartWorkout: () -> Void
    @State private var isExercisesPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Вводная тренировки")
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(workout.title)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        detailRow(title: "Упражнений", value: "\(workout.exercises.count)")
                        detailRow(
                            title: "Оценка длительности",
                            value: "~\(estimatedDurationMinutes(workout: workout)) мин",
                        )
                    }
                }

                FFButton(title: "Начать тренировку", variant: .primary, action: onStartWorkout)
                FFButton(title: "Показать упражнения", variant: .secondary) {
                    isExercisesPresented = true
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .sheet(isPresented: $isExercisesPresented) {
            NavigationStack {
                List {
                    ForEach(Array(workout.exercises.enumerated()), id: \.offset) { index, exercise in
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text("\(index + 1). \(exercise.name)")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text("\(exercise.sets) подходов")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                        .padding(.vertical, FFSpacing.xxs)
                    }
                }
                .navigationTitle("Упражнения")
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Spacer(minLength: FFSpacing.xs)
            Text(value)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
        }
    }

    private func estimatedDurationMinutes(workout: WorkoutDetailsModel) -> Int {
        let totalSets = workout.exercises.reduce(0) { $0 + max(1, $1.sets) }
        let totalRest = workout.exercises.reduce(0) { partial, exercise in
            partial + (exercise.restSeconds ?? 45) * max(0, exercise.sets - 1)
        }
        let totalSeconds = totalSets * 90 + totalRest
        return max(10, totalSeconds / 60)
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
