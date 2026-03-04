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

    struct EnrollmentConfirmationRoute: Equatable, Identifiable {
        let id: String
        let programId: String
        let programTitle: String
        let frequencyPerWeek: Int?
        let level: String?
        let estimatedDurationMinutes: Int?
        let firstWorkoutTitle: String?
        let firstWorkoutEstimatedDurationMinutes: Int?
        let firstWorkoutInstanceId: String?
        let fallbackWorkoutTemplateId: String?
        let fallbackWorkoutTitles: [String]
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
    var enrollmentConfirmation: EnrollmentConfirmationRoute?
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

        await startProgram()
    }

    var primaryProgramActionTitle: String {
        if isStartingProgram {
            return "Запускаем программу..."
        }
        if isProgramAlreadyActive {
            return nextWorkoutInstanceId == nil ? "Программа уже активна" : "Продолжить программу"
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

        if let firstWorkoutInstanceId = route.firstWorkoutInstanceId,
           let intro = await prepareRemoteWorkoutIntro(
               workoutInstanceId: firstWorkoutInstanceId,
               programId: route.programId,
               isFirstWorkoutAfterEnrollment: true,
           )
        {
            error = nil
            workoutIntro = intro
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
            workoutIntro = intro
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
        let fallbackDuration = fallbackWorkout.flatMap { estimateDurationMinutes(exercises: $0.exercises ?? []) }

        let firstWorkoutInstanceId = nextWorkoutInstanceId?.trimmedNilIfEmpty
        let firstWorkoutTitle = nextWorkoutInstanceTitle?.trimmedNilIfEmpty ?? fallbackTitle

        enrollmentConfirmation = EnrollmentConfirmationRoute(
            id: "enrollment-confirmation-\(programId)-\(Date().timeIntervalSince1970)",
            programId: programId,
            programTitle: details.title,
            frequencyPerWeek: details.currentPublishedVersion?.frequencyPerWeek,
            level: localizedLevel(details.currentPublishedVersion?.level),
            estimatedDurationMinutes: estimatedProgramDurationMinutes(details: details),
            firstWorkoutTitle: firstWorkoutTitle,
            firstWorkoutEstimatedDurationMinutes: firstWorkoutInstanceId == nil ? fallbackDuration : nil,
            firstWorkoutInstanceId: firstWorkoutInstanceId,
            fallbackWorkoutTemplateId: firstWorkoutInstanceId == nil ? fallbackWorkout?.id : nil,
            fallbackWorkoutTitles: sortedWorkouts.map { workout in
                workout.title?.trimmedNilIfEmpty ?? "День \(workout.dayOrder)"
            },
            isPendingEnrollment: isPendingEnrollment,
        )
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
            creatorInfoMessage = "Войдите, чтобы подписываться на авторов."
            return
        }
        guard networkMonitor.currentStatus else {
            creatorInfoMessage = "Нет сети. Follow недоступен в оффлайн-режиме."
            return
        }
        guard let programsClient else {
            creatorInfoMessage = "Follow сейчас недоступен."
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
                ClientAnalytics.track(.creatorFollowed, properties: ["creator_id": creatorCard.id.uuidString])
            } else {
                ClientAnalytics.track(.creatorUnfollowed, properties: ["creator_id": creatorCard.id.uuidString])
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
                        Text("Оффлайн. Показаны сохранённые данные.")
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
                    if let creator = viewModel.creatorCard {
                        creatorSection(creator: creator)
                    }
                    progress(details: details)
                    about(details: details)
                    workouts(details: details)
                    startProgramBlock(details: details)
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
        .task {
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
            EnrollmentConfirmationView(
                route: route,
                isPreparingFirstWorkout: viewModel.isPreparingFirstWorkout,
                onStartFirstWorkout: {
                    Task { await viewModel.handleEnrollmentPrimaryAction() }
                },
                onOpenProgramPlan: {
                    viewModel.dismissEnrollmentConfirmation()
                    onOpenProgramPlan?()
                },
            )
            .navigationTitle("Program Started")
        }
        .navigationDestination(item: $viewModel.workoutIntro) { route in
            WorkoutIntroView(
                workout: route.workout,
                onStartWorkout: {
                    viewModel.launchWorkoutFromIntro(route)
                },
            )
            .navigationTitle("Workout intro")
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
            .navigationTitle("Creator")
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
            FFLoadingState(title: "Загружаем описание программы")
            FFLoadingState(title: "Подготавливаем структуру тренировок")
        }
    }

    private func header(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                if let imageURL = resolveImageURL(details.cover?.url ?? details.media?.first?.url) {
                    FFRemoteImage(url: imageURL) {
                        placeholderImage
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                } else {
                    placeholderImage
                }

                HStack(alignment: .center) {
                    Text(details.title)
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: FFSpacing.sm)
                    FFBadge(status: .published)
                }

                if let shortDescription = details.description, !shortDescription.isEmpty {
                    Text(shortDescription)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private func creatorSection(creator: InfluencerPublicCard) -> some View {
        VStack(spacing: FFSpacing.xs) {
            CreatorCardView(
                creator: creator,
                environment: environment,
                followButtonState: viewModel.isCreatorFollowLoading ? .loading : (creator.isFollowedByMe ? .following : .follow),
                isFollowEnabled: viewModel.canToggleCreatorFollow,
                onTap: {
                    viewModel.openCreatorProfile()
                },
                onFollowTap: {
                    Task { await viewModel.toggleCreatorFollow() }
                },
            )

            if let infoMessage = viewModel.creatorInfoMessage {
                FFCard {
                    Text(infoMessage)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private func about(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("О программе")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if let version = details.currentPublishedVersion {
                    Text("\(version.levelTitle) • \(version.frequencyTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text(version.equipmentTitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
                Text(details.description ?? "Описание программы пока недоступно.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func progress(details _: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Ваш прогресс")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if viewModel.totalWorkoutsCount > 0 {
                    Text("Пройдено \(viewModel.completedWorkoutsCount) из \(viewModel.totalWorkoutsCount) тренировок")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textPrimary)
                } else {
                    Text("Прогресс появится после загрузки списка тренировок.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
                if let upcomingWorkoutTitle = viewModel.upcomingWorkoutTitle {
                    Text("Следующая: \(upcomingWorkoutTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
                if let lastCompletionTitle = viewModel.lastCompletionTitle {
                    Text("Последнее выполнение: \(lastCompletionTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.accent)
                }
            }
        }
    }

    private func workouts(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Тренировки")
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
                    Text("Состав тренировок будет доступен после начала программы.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func startProgramBlock(details: ProgramDetails) -> some View {
        if details.currentPublishedVersion?.id != nil {
            FFButton(
                title: viewModel.primaryProgramActionTitle,
                variant: viewModel.isPrimaryProgramActionEnabled ? .primary : .disabled,
                action: { Task { await viewModel.handlePrimaryProgramAction() } },
            )
            .accessibilityLabel("Начать программу")
            .accessibilityHint("Создаст активное прохождение программы для вашего профиля")
            if viewModel.isProgramAlreadyActive {
                FFCard {
                    Text("Активная программа найдена. Продолжайте по серверному расписанию.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        } else {
            FFCard {
                Text("Скоро можно будет начать программу в приложении.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
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

    private func resolveImageURL(_ pathOrURL: String?) -> URL? {
        guard let pathOrURL, !pathOrURL.isEmpty else { return nil }
        if let absolute = URL(string: pathOrURL), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL = viewModel.details?.media?.first?.url else {
            return URL(string: pathOrURL)
        }
        if let absolute = URL(string: baseURL), absolute.scheme != nil {
            return absolute.deletingLastPathComponent().appendingPathComponent(pathOrURL)
        }
        return URL(string: pathOrURL)
    }
}

struct EnrollmentConfirmationView: View {
    let route: ProgramDetailsViewModel.EnrollmentConfirmationRoute
    let isPreparingFirstWorkout: Bool
    let onStartFirstWorkout: () -> Void
    let onOpenProgramPlan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Program Started")
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(route.programTitle)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Program overview")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        detailRow(title: "frequencyPerWeek", value: route.frequencyPerWeek.map(String.init) ?? "—")
                        detailRow(title: "level", value: route.level ?? "—")
                        detailRow(
                            title: "estimatedDurationMinutes",
                            value: route.estimatedDurationMinutes.map { "\($0) мин" } ?? "—",
                        )
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("First workout")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(route.firstWorkoutTitle ?? "Подберём после синхронизации")
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                        if let duration = route.firstWorkoutEstimatedDurationMinutes {
                            Text("Estimated duration: ~\(duration) мин")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                        if route.isPendingEnrollment {
                            Text("Оффлайн: enrollment сохранён локально и будет отправлен при появлении сети.")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.primary)
                        }
                        if route.firstWorkoutInstanceId == nil, !route.fallbackWorkoutTitles.isEmpty {
                            Divider()
                            Text("Workouts from ProgramDetails")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textSecondary)
                            ForEach(Array(route.fallbackWorkoutTitles.prefix(3).enumerated()), id: \.offset) { index, title in
                                Text("\(index + 1). \(title)")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                    }
                }

                if route.canStartFirstWorkout {
                    FFButton(
                        title: route.firstWorkoutInstanceId == nil ? "Start first workout" : "Start workout",
                        variant: .primary,
                        isLoading: isPreparingFirstWorkout,
                        action: onStartFirstWorkout,
                    )
                } else {
                    FFButton(
                        title: "Open program plan",
                        variant: .secondary,
                        action: onOpenProgramPlan,
                    )
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
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
                        Text("Workout intro")
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

                FFButton(title: "Start workout", variant: .primary, action: onStartWorkout)
                FFButton(title: "View exercises", variant: .secondary) {
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
