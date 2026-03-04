import ComposableArchitecture
import SwiftUI

struct RootView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let apiClient: APIClientProtocol?

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 0) {
                if !viewStore.isOnline {
                    OfflineBannerView()
                }

                Group {
                    switch viewStore.sessionState {
                    case .unauthenticated:
                        AuthEntryView {
                            viewStore.send(.loginTapped(.login))
                        } onCreateAccount: {
                            viewStore.send(.loginTapped(.createAccount))
                        }

                    case .authenticating:
                        FFLoadingState(title: "Проверяем сессию")
                            .padding(.horizontal, FFSpacing.md)

                    case .needsOnboarding:
                        if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                            OnboardingView(store: onboardingStore)
                                .padding(.horizontal, FFSpacing.md)
                        } else {
                            FFLoadingState(title: "Подготавливаем профиль")
                                .padding(.horizontal, FFSpacing.md)
                        }

                    case let .authenticated(userContext):
                        MainTabsView(
                            store: store,
                            environment: environment,
                            apiClient: apiClient,
                            me: userContext.me,
                            isOnline: viewStore.isOnline,
                            onLogout: { viewStore.send(.logoutTapped) },
                        )

                    case let .error(error):
                        FFErrorState(
                            title: error.title,
                            message: error.message,
                            retryTitle: "Повторить",
                        ) {
                            viewStore.send(.retryBootstrapTapped)
                        }
                        .padding(.horizontal, FFSpacing.md)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FFColors.background)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}

private struct OfflineBannerView: View {
    var body: some View {
        Text("Нет подключения. Показаны сохранённые данные.")
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(FFColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.primary)
            .accessibilityLabel("Оффлайн режим")
    }
}

private struct AuthEntryView: View {
    let onLogin: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Добро пожаловать")
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Войдите, чтобы начать тренировки в Fitfluence.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Войти", variant: .primary, action: onLogin)

            FFButton(title: "Создать аккаунт", variant: .secondary, action: onCreateAccount)

            Spacer()
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.lg)
    }
}

private struct MainTabsView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let apiClient: APIClientProtocol?
    let me: MeResponse
    let isOnline: Bool
    let onLogout: () -> Void

    var body: some View {
        AthleteShellView(
            store: store,
            environment: environment,
            apiClient: apiClient,
            me: me,
            isOnline: isOnline,
            onLogout: onLogout,
        )
    }
}

private struct AthleteShellView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let apiClient: APIClientProtocol?
    let me: MeResponse
    let isOnline: Bool
    let onLogout: () -> Void

    @State private var selectedTab: ShellTab = .training
    @State private var resumeSession: ActiveWorkoutSession?
    @State private var pendingResumeRequest: ActiveWorkoutSession?

    enum ShellTab: Hashable {
        case training
        case catalog
        case plan
        case progress
        case profile
    }

    var body: some View {
        VStack(spacing: 0) {
            if let session = resumeSession, selectedTab != .training {
                ResumeWorkoutBannerView(
                    session: session,
                    onResume: {
                        ClientAnalytics.track(
                            .workoutContinueButtonTapped,
                            properties: ["source": "other_tab_banner"],
                        )
                        pendingResumeRequest = session
                        selectedTab = .training
                    },
                )
                .padding(.horizontal, FFSpacing.md)
                .padding(.top, FFSpacing.xs)
                .padding(.bottom, FFSpacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView(selection: $selectedTab) {
                NavigationStack {
                    TrainingTabContent(
                        userSub: me.subject ?? "anonymous",
                        apiClient: apiClient,
                        onOpenPlan: { selectedTab = .plan },
                        resumeSessionRequest: $pendingResumeRequest,
                        onResumeHandled: {
                            pendingResumeRequest = nil
                            Task {
                                await refreshResumeSession()
                            }
                        },
                    )
                }
                .tabItem {
                    Label("Тренировка", systemImage: "dumbbell.fill")
                }
                .tag(ShellTab.training)

                NavigationStack {
                    CatalogTabContent(
                        store: store,
                        environment: environment,
                        apiClient: apiClient,
                        userSub: me.subject ?? "anonymous",
                        onOpenPlanTab: { selectedTab = .plan },
                        onOpenWorkoutHubTab: { selectedTab = .training },
                    )
                }
                .tabItem {
                    Label("Каталог", systemImage: "square.grid.2x2")
                }
                .tag(ShellTab.catalog)

                NavigationStack {
                    PlanTabContent(
                        apiClient: apiClient,
                        userSub: me.subject ?? "anonymous",
                    )
                }
                .tabItem {
                    Label("План", systemImage: "calendar")
                }
                .tag(ShellTab.plan)

                NavigationStack {
                    TrainingInsightsView(
                        viewModel: TrainingInsightsViewModel(
                            userSub: me.subject ?? "anonymous",
                            athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                        ),
                        isOnline: isOnline,
                        onOpenPlan: { selectedTab = .plan },
                        onStartNextWorkout: { selectedTab = .training },
                    )
                }
                .tabItem {
                    Label("Прогресс", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(ShellTab.progress)

                NavigationStack {
                    ProfileTabView(
                        me: me,
                        userSub: me.subject ?? "anonymous",
                        isOnline: isOnline,
                        apiClient: apiClient,
                        onLogout: onLogout,
                    )
                }
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle")
                }
                .tag(ShellTab.profile)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: resumeSession?.workoutId)
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .tint(FFColors.accent)
        .task(id: me.subject ?? "anonymous") {
            await SyncCoordinator.shared.activate(namespace: me.subject ?? "anonymous")
            await refreshResumeSession()
        }
        .onChange(of: selectedTab) { _, _ in
            Task {
                await refreshResumeSession()
            }
        }
    }

    private func refreshResumeSession() async {
        let userSub = me.subject ?? "anonymous"
        guard !userSub.isEmpty, userSub != "anonymous" else {
            resumeSession = nil
            return
        }
        var latest = await LocalWorkoutProgressStore().latestActiveSession(userSub: userSub)

        if latest == nil,
           isOnline,
           let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol
        {
            let result = await athleteTrainingClient.activeEnrollmentProgress()
            if case let .success(progress) = result {
                let programId = progress.programId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let currentInProgress = progress.currentWorkoutStatus == .inProgress
                let nextInProgress = progress.nextWorkoutStatus == .inProgress

                if currentInProgress,
                   let workoutId = progress.currentWorkoutId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let programId,
                   !workoutId.isEmpty,
                   !programId.isEmpty
                {
                    latest = ActiveWorkoutSession(
                        userSub: userSub,
                        programId: programId,
                        workoutId: workoutId,
                        source: .program,
                        status: .inProgress,
                        currentExerciseIndex: nil,
                        lastUpdated: Date(),
                    )
                } else if nextInProgress,
                          let workoutId = progress.nextWorkoutId?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let programId,
                          !workoutId.isEmpty,
                          !programId.isEmpty
                {
                    latest = ActiveWorkoutSession(
                        userSub: userSub,
                        programId: programId,
                        workoutId: workoutId,
                        source: .program,
                        status: .inProgress,
                        currentExerciseIndex: nil,
                        lastUpdated: Date(),
                    )
                }
            }
        }

        resumeSession = latest
    }
}

private struct ResumeWorkoutBannerView: View {
    let session: ActiveWorkoutSession
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text("Тренировка в процессе")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Text(startedText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }

            Spacer(minLength: FFSpacing.sm)

            FFButton(title: "Продолжить", variant: .secondary, action: onResume)
        }
        .padding(.horizontal, FFSpacing.sm)
        .padding(.vertical, FFSpacing.xs)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private var startedText: String {
        let minutes = max(1, Int(Date().timeIntervalSince(session.lastUpdated) / 60))
        return "Начата \(minutes) мин назад"
    }
}

private struct PlanTabContent: View {
    let apiClient: APIClientProtocol?
    let userSub: String

    @State private var planViewModel: PlanScheduleViewModel

    init(
        apiClient: APIClientProtocol?,
        userSub: String,
    ) {
        self.apiClient = apiClient
        self.userSub = userSub
        _planViewModel = State(
            initialValue: PlanScheduleViewModel(
                userSub: userSub,
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            ),
        )
    }

    var body: some View {
        PlanScheduleScreen(viewModel: planViewModel)
            .navigationTitle("План")
    }
}

private struct CatalogTabContent: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let apiClient: APIClientProtocol?
    let userSub: String
    let onOpenPlanTab: () -> Void
    let onOpenWorkoutHubTab: () -> Void

    @State private var viewModel: CatalogViewModel
    @State private var creatorsViewModel: CreatorsDiscoveryViewModel
    @State private var followingViewModel: FollowingCreatorsViewModel

    init(
        store: StoreOf<RootFeature>,
        environment: AppEnvironment,
        apiClient: APIClientProtocol?,
        userSub: String,
        onOpenPlanTab: @escaping () -> Void,
        onOpenWorkoutHubTab: @escaping () -> Void,
    ) {
        self.store = store
        self.environment = environment
        self.apiClient = apiClient
        self.userSub = userSub
        self.onOpenPlanTab = onOpenPlanTab
        self.onOpenWorkoutHubTab = onOpenWorkoutHubTab
        let unauthorizedHandler: () -> Void = {
            _ = store.send(.logoutTapped)
        }
        _viewModel = State(
            initialValue: CatalogViewModel(
                userSub: userSub,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: unauthorizedHandler,
            ),
        )
        _creatorsViewModel = State(
            initialValue: CreatorsDiscoveryViewModel(
                userSub: userSub,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: unauthorizedHandler,
            ),
        )
        _followingViewModel = State(
            initialValue: FollowingCreatorsViewModel(
                userSub: userSub,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: unauthorizedHandler,
            ),
        )
    }

    var body: some View {
        WithViewStore(
            store,
            observe: \.selectedProgram,
        ) { viewStore in
            CatalogHubScreen(
                programsViewModel: viewModel,
                creatorsViewModel: creatorsViewModel,
                followingViewModel: followingViewModel,
                userSub: userSub,
                environment: environment,
                onProgramTap: { programID in
                    store.send(.openProgram(programId: programID, userSub: userSub))
                },
                onUnauthorized: {
                    store.send(.logoutTapped)
                },
            )
            .navigationTitle("Каталог")
            .navigationDestination(
                isPresented: Binding(
                    get: { viewStore.state != nil },
                    set: { isPresented in
                        if !isPresented {
                            store.send(.programDetailsDismissed)
                        }
                    },
                ),
            ) {
                if let selectedProgram = viewStore.state {
                    ProgramDetailsScreen(
                        viewModel: ProgramDetailsViewModel(
                            programId: selectedProgram.programId,
                            userSub: selectedProgram.userSub,
                            programsClient: apiClient as? ProgramsClientProtocol,
                            athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                            onUnauthorized: {
                                store.send(.logoutTapped)
                            },
                        ),
                        apiClient: apiClient,
                        environment: environment,
                        onOpenProgramPlan: {
                            store.send(.programDetailsDismissed)
                            onOpenPlanTab()
                        },
                        onOpenWorkoutHub: {
                            store.send(.programDetailsDismissed)
                            onOpenWorkoutHubTab()
                        },
                        onOpenProgram: { programID in
                            store.send(.openProgram(programId: programID, userSub: userSub))
                        },
                    )
                    .navigationTitle("Программа")
                }
            }
        }
    }
}

struct WorkoutSummaryState: Equatable, Identifiable {
    struct ComparisonDelta: Equatable {
        let previousWorkoutInstanceId: String
        let repsDelta: Int?
        let volumeDelta: Double?
        let durationDeltaSeconds: Int?
    }

    struct NextWorkout: Equatable {
        let programId: String
        let workoutId: String
        let title: String
    }

    let id: String
    let workoutTitle: String
    let durationSeconds: Int
    let totalSets: Int
    let totalReps: Int
    let volume: Double
    let comparison: ComparisonDelta?
    let nextWorkout: NextWorkout?
    let hasNewPersonalRecord: Bool
}

enum WorkoutInstanceRouteState: Equatable {
    case requiresStart
    case resume
    case completed
    case abandoned
}

func resolveWorkoutInstanceRouteState(_ status: AthleteWorkoutInstanceStatus?) -> WorkoutInstanceRouteState {
    switch status {
    case .planned:
        return .requiresStart
    case .missed:
        return .requiresStart
    case .completed:
        return .completed
    case .abandoned:
        return .abandoned
    case .inProgress, .none:
        return .resume
    }
}

struct WorkoutLaunchView: View {
    let userSub: String
    let programId: String
    let workoutId: String
    let apiClient: APIClientProtocol?
    var presetWorkout: WorkoutDetailsModel?
    var source: WorkoutSource = .program
    var isFirstWorkoutInProgramFlow = false
    var onBackToWorkoutHub: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @State private var details: WorkoutDetailsModel?
    @State private var error: UserFacingError?
    @State private var isLoading = false
    @State private var isCompletingWorkout = false
    @State private var isStartingPlannedWorkout = false
    @State private var isExitConfirmationPresented = false
    @State private var isAbandoningOnExit = false
    @State private var routeState: WorkoutInstanceRouteState = .resume
    @State private var readOnlySummary: WorkoutSummaryState?
    @State private var executionContext: WorkoutExecutionContext?
    @State private var workoutSummary: WorkoutSummaryState?
    @State private var nextWorkoutRoute: NextWorkoutRoute?
    @Environment(\.dismiss) private var dismiss

    private struct NextWorkoutRoute: Identifiable, Hashable {
        let programId: String
        let workoutId: String

        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    var body: some View {
        Group {
            if isLoading {
                FFLoadingState(title: "Открываем тренировку")
                    .padding(.horizontal, FFSpacing.md)
            } else if routeState == .requiresStart, let details {
                plannedWorkoutState(details: details)
            } else if routeState == .completed, let summary = readOnlySummary {
                WorkoutSummaryView(
                    summary: summary,
                    onStartNextWorkout: summary.nextWorkout == nil ? nil : {
                        Task { await startNextWorkout(from: summary) }
                    },
                    onBackToWorkoutHub: {
                        dismiss()
                        onBackToWorkoutHub?()
                    },
                )
            } else if routeState == .abandoned {
                abandonedWorkoutState
            } else if let details {
                WorkoutPlayerViewV2(
                    viewModel: WorkoutPlayerViewModel(
                        userSub: userSub,
                        programId: programId,
                        workout: details,
                        source: source,
                        athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                        networkMonitor: NetworkMonitor(),
                        executionContext: executionContext,
                    ),
                    onExit: {
                        isExitConfirmationPresented = true
                    },
                    onFinish: { summary in
                        Task { await handleCompletion(summary) }
                    },
                )
            } else if let error {
                FFErrorState(
                    title: error.title,
                    message: error.message,
                    retryTitle: "Повторить",
                ) {
                    Task { await load() }
                }
                .padding(.horizontal, FFSpacing.md)
            } else {
                FFEmptyState(title: "Тренировка не найдена", message: "Выберите другую тренировку в плане.")
                    .padding(.horizontal, FFSpacing.md)
            }
        }
        .background(FFColors.background)
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .alert("Выйти из тренировки?", isPresented: $isExitConfirmationPresented) {
            Button("Отмена", role: .cancel) {}
            if source == .program,
               UUID(uuidString: workoutId) != nil,
               routeState == .resume
            {
                Button("Сохранить и выйти") {
                    dismiss()
                }
                Button("Прервать тренировку", role: .destructive) {
                    Task { await abandonWorkoutAndExit() }
                }
            } else {
                Button("Выйти", role: .destructive) {
                    dismiss()
                }
            }
        } message: {
            if source == .program,
               UUID(uuidString: workoutId) != nil,
               routeState == .resume
            {
                Text("Действие «Сохранить и выйти» оставит тренировку в статусе «В процессе».")
            } else {
                Text("Прогресс сохранится на устройстве.")
            }
        }
        .overlay {
            if isCompletingWorkout {
                ZStack {
                    FFColors.background.opacity(0.72).ignoresSafeArea()
                    FFLoadingState(title: "Сохраняем тренировку")
                        .padding(.horizontal, FFSpacing.md)
                }
            } else if isStartingPlannedWorkout {
                ZStack {
                    FFColors.background.opacity(0.72).ignoresSafeArea()
                    FFLoadingState(title: "Запускаем тренировку")
                        .padding(.horizontal, FFSpacing.md)
                }
            } else if isAbandoningOnExit {
                ZStack {
                    FFColors.background.opacity(0.72).ignoresSafeArea()
                    FFLoadingState(title: "Прерываем тренировку")
                        .padding(.horizontal, FFSpacing.md)
                }
            }
        }
        .sheet(item: $workoutSummary) { summary in
            WorkoutSummaryView(
                summary: summary,
                onStartNextWorkout: {
                    Task { await startNextWorkout(from: summary) }
                },
                onBackToWorkoutHub: {
                    workoutSummary = nil
                    dismiss()
                    onBackToWorkoutHub?()
                },
            )
        }
        .navigationDestination(item: $nextWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.programId,
                workoutId: route.workoutId,
                apiClient: apiClient,
                source: .program,
                isFirstWorkoutInProgramFlow: false,
                onBackToWorkoutHub: onBackToWorkoutHub,
                onOpenPlan: onOpenPlan,
            )
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let cacheStore = CompositeCacheStore()
        let progressStore = LocalWorkoutProgressStore()
        let cacheKey = "workout.details:\(programId):\(workoutId)"
        let contextCacheKey = "workout.execution.context:\(programId):\(workoutId)"
        let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol

        if let presetWorkout {
            details = presetWorkout
            error = nil
            routeState = .resume
            await cacheStore.set(cacheKey, value: presetWorkout, namespace: userSub, ttl: 60 * 60 * 24)
            return
        }

        let canLoadFromProgramAPI = source == .program && UUID(uuidString: programId) != nil

        if source == .program,
           UUID(uuidString: workoutId) != nil,
           let athleteTrainingClient
        {
            let athleteResult = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutId)
            switch athleteResult {
            case let .success(workoutDetails):
                let mapped = workoutDetails.asWorkoutDetailsModel()
                details = mapped
                error = nil
                routeState = resolveWorkoutInstanceRouteState(workoutDetails.workout.status)
                executionContext = WorkoutExecutionContext(
                    workoutInstanceId: workoutDetails.workout.id,
                    exerciseExecutionIDsByExerciseID: Dictionary(
                        uniqueKeysWithValues: workoutDetails.exercises.map { ($0.exerciseId, $0.id) },
                    ),
                )
                if let executionContext {
                    await cacheStore.set(contextCacheKey, value: executionContext, namespace: userSub, ttl: 60 * 60 * 24)
                }
                await cacheStore.set(cacheKey, value: mapped, namespace: userSub, ttl: 60 * 60 * 24)
                if routeState == .completed {
                    readOnlySummary = await buildReadOnlySummary(from: workoutDetails, fallbackTitle: mapped.title)
                } else {
                    readOnlySummary = nil
                }
                return

            case let .failure(apiError):
                if case let .httpError(statusCode, _) = apiError, statusCode == 404 {
                    // Fallback to template-based loading for non-instance workout ids.
                } else {
                    error = apiError.userFacing(context: .workoutPlayer)
                }
            }
        }

        if canLoadFromProgramAPI, let apiClient, let programsClient = apiClient as? ProgramsClientProtocol {
            let workoutsClient = WorkoutsClient(programsClient: programsClient)
            let result = await workoutsClient.getWorkoutDetails(programId: programId, workoutId: workoutId)
            switch result {
            case let .success(details):
                self.details = details
                self.error = nil
                self.routeState = .resume
                await cacheStore.set(cacheKey, value: details, namespace: userSub, ttl: 60 * 60 * 24)
                return
            case let .failure(apiError):
                self.error = apiError.userFacing(context: .workoutPlayer)
            }
        }

        if let cached = await cacheStore.get(cacheKey, as: WorkoutDetailsModel.self, namespace: userSub) {
            details = cached
            error = nil
            routeState = .resume
            if let cachedContext = await cacheStore.get(
                contextCacheKey,
                as: WorkoutExecutionContext.self,
                namespace: userSub,
            ) {
                executionContext = cachedContext
            }
        } else if let snapshot = await progressStore.load(
            userSub: userSub,
            programId: programId,
            workoutId: workoutId,
        ),
            let restored = snapshot.workoutDetails
        {
            details = restored
            error = nil
            routeState = .resume
            await cacheStore.set(cacheKey, value: restored, namespace: userSub, ttl: 60 * 60 * 24)
        } else if error == nil {
            error = UserFacingError(
                title: "Нет сохранённых данных",
                message: "Откройте тренировку заново во вкладке «Тренировка».",
            )
        }
    }

    private func handleCompletion(_ summary: WorkoutPlayerViewModel.CompletionSummary) async {
        guard !isCompletingWorkout else { return }
        isCompletingWorkout = true
        defer { isCompletingWorkout = false }

        var durationSeconds = summary.durationSeconds
        var totalSets = summary.completedSets
        var totalReps = summary.totalReps
        var volume = summary.volume
        var comparison: WorkoutSummaryState.ComparisonDelta?
        var nextWorkout: WorkoutSummaryState.NextWorkout?
        var hasNewPersonalRecord = false

        if source == .program, UUID(uuidString: workoutId) != nil {
            _ = await SyncCoordinator.shared.enqueueCompleteWorkout(
                namespace: userSub,
                workoutInstanceId: workoutId,
                completedAt: Date(),
            )
        }

        if source == .program,
           UUID(uuidString: workoutId) != nil,
           let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol
        {

            let comparisonResult = await athleteTrainingClient.workoutComparison(workoutInstanceId: workoutId)
            if case let .success(comparisonResponse) = comparisonResult {
                durationSeconds = comparisonResponse.durationSeconds ?? durationSeconds
                totalSets = comparisonResponse.totalSets ?? totalSets
                totalReps = comparisonResponse.totalReps ?? totalReps
                volume = comparisonResponse.volume ?? volume

                if let previousWorkoutInstanceId = comparisonResponse.previousWorkoutInstanceId?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !previousWorkoutInstanceId.isEmpty
                {
                    comparison = WorkoutSummaryState.ComparisonDelta(
                        previousWorkoutInstanceId: previousWorkoutInstanceId,
                        repsDelta: comparisonResponse.repsDelta,
                        volumeDelta: comparisonResponse.volumeDelta,
                        durationDeltaSeconds: comparisonResponse.durationDeltaSeconds,
                    )
                }

                hasNewPersonalRecord = comparisonResponse.hasNewPersonalRecord == true ||
                    !(comparisonResponse.personalRecords ?? []).isEmpty
            }

            let activeEnrollmentResult = await athleteTrainingClient.activeEnrollmentProgress()
            if case let .success(progress) = activeEnrollmentResult,
               let nextWorkoutIdRaw = progress.nextWorkoutId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nextWorkoutIdRaw.isEmpty,
               nextWorkoutIdRaw != workoutId
            {
                let nextProgramId = progress.programId?.trimmingCharacters(in: .whitespacesAndNewlines)
                nextWorkout = WorkoutSummaryState.NextWorkout(
                    programId: (nextProgramId?.isEmpty == false ? nextProgramId! : programId),
                    workoutId: nextWorkoutIdRaw,
                    title: progress.nextWorkoutTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? progress.nextWorkoutTitle! : "Следующая тренировка",
                )
            }
        }

        if isFirstWorkoutInProgramFlow {
            ClientAnalytics.track(
                .firstWorkoutCompleted,
                properties: [
                    "program_id": programId,
                    "workout_id": workoutId,
                ],
            )
        }

        workoutSummary = WorkoutSummaryState(
            id: "\(workoutId)-\(Date().timeIntervalSince1970)",
            workoutTitle: summary.workoutTitle,
            durationSeconds: max(0, durationSeconds),
            totalSets: max(0, totalSets),
            totalReps: max(0, totalReps),
            volume: max(0, volume),
            comparison: comparison,
            nextWorkout: nextWorkout,
            hasNewPersonalRecord: hasNewPersonalRecord,
        )
    }

    private func startNextWorkout(from summary: WorkoutSummaryState) async {
        guard let nextWorkout = summary.nextWorkout else {
            workoutSummary = nil
            dismiss()
            onBackToWorkoutHub?()
            return
        }

        _ = await SyncCoordinator.shared.enqueueStartWorkout(
            namespace: userSub,
            workoutInstanceId: nextWorkout.workoutId,
            startedAt: Date(),
        )

        workoutSummary = nil
        nextWorkoutRoute = NextWorkoutRoute(programId: nextWorkout.programId, workoutId: nextWorkout.workoutId)
    }

    private func startPlannedWorkout() async {
        guard source == .program, UUID(uuidString: workoutId) != nil else {
            routeState = .resume
            return
        }

        isStartingPlannedWorkout = true
        defer { isStartingPlannedWorkout = false }

        _ = await SyncCoordinator.shared.enqueueStartWorkout(
            namespace: userSub,
            workoutInstanceId: workoutId,
            startedAt: Date(),
        )
        routeState = .resume
    }

    private func abandonWorkoutAndExit() async {
        guard source == .program, UUID(uuidString: workoutId) != nil else {
            dismiss()
            return
        }

        isAbandoningOnExit = true
        defer { isAbandoningOnExit = false }

        _ = await SyncCoordinator.shared.enqueueAbandonWorkout(
            namespace: userSub,
            workoutInstanceId: workoutId,
            abandonedAt: Date(),
        )

        dismiss()
        onBackToWorkoutHub?()
    }

    private func buildReadOnlySummary(
        from workoutDetails: AthleteWorkoutDetailsResponse,
        fallbackTitle: String,
    ) async -> WorkoutSummaryState {
        let metrics = deriveMetrics(from: workoutDetails.exercises)
        var durationSeconds = max(0, workoutDetails.workout.durationSeconds ?? metrics.derivedDurationSeconds)
        var totalSets = max(0, metrics.totalSets)
        var totalReps = max(0, metrics.totalReps)
        var volume = max(0, metrics.volume)
        var comparison: WorkoutSummaryState.ComparisonDelta?
        var nextWorkout: WorkoutSummaryState.NextWorkout?
        var hasNewPersonalRecord = false

        if let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol {
            let comparisonResult = await athleteTrainingClient.workoutComparison(workoutInstanceId: workoutDetails.workout.id)
            if case let .success(comparisonResponse) = comparisonResult {
                durationSeconds = comparisonResponse.durationSeconds ?? durationSeconds
                totalSets = comparisonResponse.totalSets ?? totalSets
                totalReps = comparisonResponse.totalReps ?? totalReps
                volume = comparisonResponse.volume ?? volume

                if let previousWorkoutInstanceId = comparisonResponse.previousWorkoutInstanceId?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !previousWorkoutInstanceId.isEmpty
                {
                    comparison = WorkoutSummaryState.ComparisonDelta(
                        previousWorkoutInstanceId: previousWorkoutInstanceId,
                        repsDelta: comparisonResponse.repsDelta,
                        volumeDelta: comparisonResponse.volumeDelta,
                        durationDeltaSeconds: comparisonResponse.durationDeltaSeconds,
                    )
                }

                hasNewPersonalRecord = comparisonResponse.hasNewPersonalRecord == true ||
                    !(comparisonResponse.personalRecords ?? []).isEmpty
            }

            let activeEnrollmentResult = await athleteTrainingClient.activeEnrollmentProgress()
            if case let .success(progress) = activeEnrollmentResult,
               let nextWorkoutIdRaw = progress.nextWorkoutId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nextWorkoutIdRaw.isEmpty,
               nextWorkoutIdRaw != workoutDetails.workout.id
            {
                let nextProgramId = progress.programId?.trimmingCharacters(in: .whitespacesAndNewlines)
                nextWorkout = WorkoutSummaryState.NextWorkout(
                    programId: (nextProgramId?.isEmpty == false ? nextProgramId! : programId),
                    workoutId: nextWorkoutIdRaw,
                    title: progress.nextWorkoutTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? progress.nextWorkoutTitle! : "Следующая тренировка",
                )
            }
        }

        return WorkoutSummaryState(
            id: "readonly-\(workoutDetails.workout.id)",
            workoutTitle: workoutDetails.workout.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? workoutDetails.workout.title! : fallbackTitle,
            durationSeconds: durationSeconds,
            totalSets: totalSets,
            totalReps: totalReps,
            volume: volume,
            comparison: comparison,
            nextWorkout: nextWorkout,
            hasNewPersonalRecord: hasNewPersonalRecord,
        )
    }

    private func deriveMetrics(from exercises: [AthleteExerciseExecution]) -> (totalSets: Int, totalReps: Int, volume: Double, derivedDurationSeconds: Int) {
        let completedSets = exercises
            .flatMap { $0.sets ?? [] }
            .filter(\.isCompleted)

        let totalSets = completedSets.count
        let totalReps = completedSets.reduce(0) { partial, set in
            partial + max(0, set.reps ?? 0)
        }
        let volume = completedSets.reduce(0.0) { partial, set in
            partial + (Double(set.reps ?? 0) * (set.weight ?? 0))
        }
        let derivedDurationSeconds = max(0, totalSets * 90)
        return (totalSets, totalReps, volume, derivedDurationSeconds)
    }

    @ViewBuilder
    private func plannedWorkoutState(details: WorkoutDetailsModel) -> some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Тренировка запланирована")
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(details.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Нажмите «Начать», чтобы перевести тренировку в статус «В процессе».")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Начать", variant: .primary) {
                Task { await startPlannedWorkout() }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.md)
    }

    private var abandonedWorkoutState: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Тренировка прервана")
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Эта сессия помечена как прерванная.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Открыть план", variant: .secondary) {
                dismiss()
                if let onOpenPlan {
                    onOpenPlan()
                } else {
                    onBackToWorkoutHub?()
                }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.md)
    }
}

extension WorkoutPlayerViewModel.CompletionSummary: Identifiable {
    var id: String {
        "\(workoutTitle)-\(completedSets)-\(totalSets)-\(durationSeconds)"
    }
}

struct WorkoutSummaryView: View {
    let summary: WorkoutSummaryState
    var onStartNextWorkout: (() -> Void)? = nil
    var onBackToWorkoutHub: (() -> Void)? = nil

    private let isPRPlaceholderEnabled = false

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Итоги тренировки")
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(summary.workoutTitle)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        metricRow(title: "Длительность", value: formattedDuration(summary.durationSeconds))
                        metricRow(title: "Подходов", value: "\(summary.totalSets)")
                        metricRow(title: "Повторений", value: "\(summary.totalReps)")
                        metricRow(title: "Объём", value: "\(Int(summary.volume))")
                    }
                }

                if let comparison = summary.comparison {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Сравнение с прошлой тренировкой")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            deltaRow(title: "Изменение повторений", value: comparison.repsDelta.map { signed($0) } ?? "—")
                            deltaRow(title: "Изменение объёма", value: comparison.volumeDelta.map { signed(Int($0)) } ?? "—")
                            deltaRow(
                                title: "Изменение длительности",
                                value: comparison.durationDeltaSeconds.map { signed($0) } ?? "—",
                            )
                        }
                    }
                }

                if isPRPlaceholderEnabled, summary.hasNewPersonalRecord {
                    FFCard {
                        Text("Новый личный рекорд")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.accent)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Следующая тренировка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(summary.nextWorkout?.title ?? "Следующая тренировка появится после синхронизации.")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                if summary.nextWorkout != nil, let onStartNextWorkout {
                    FFButton(
                        title: "Начать следующую тренировку",
                        variant: .primary,
                        action: onStartNextWorkout,
                    )
                }
                if let onBackToWorkoutHub {
                    FFButton(title: "Вернуться в хаб тренировок", variant: .secondary, action: onBackToWorkoutHub)
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
    }

    private func metricRow(title: String, value: String) -> some View {
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

    private func deltaRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Spacer(minLength: FFSpacing.xs)
            Text(value)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(value.hasPrefix("+") ? FFColors.accent : FFColors.textSecondary)
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let minutes = total / 60
        if minutes > 0 {
            return "\(minutes) мин"
        }
        return "\(total) сек"
    }
}

private struct TrainingTabContent: View {
    let userSub: String
    let apiClient: APIClientProtocol?
    let onOpenPlan: () -> Void
    @Binding var resumeSessionRequest: ActiveWorkoutSession?
    let onResumeHandled: () -> Void

    @State private var sessionRoute: ActiveWorkoutSession?
    @State private var programWorkoutRoute: ProgramWorkoutRoute?
    @State private var presetWorkoutRoute: PresetWorkoutRoute?
    @State private var isQuickBuilderPresented = false
    @State private var isTemplateLibraryPresented = false

    private struct ProgramWorkoutRoute: Identifiable, Hashable {
        let programId: String
        let workoutId: String
        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    private struct PresetWorkoutRoute: Identifiable {
        let workout: WorkoutDetailsModel
        let source: WorkoutSource
        var id: String {
            "\(source.rawValue)::\(workout.id)"
        }
    }

    var body: some View {
        TrainingHubView(
            viewModel: TrainingHubViewModel(
                userSub: userSub,
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            ),
            onContinueSession: { session in
                sessionRoute = session
            },
            onOpenRemoteWorkout: { route in
                programWorkoutRoute = ProgramWorkoutRoute(programId: route.programId, workoutId: route.workoutId)
            },
            onStartQuickWorkout: {
                isQuickBuilderPresented = true
            },
            onOpenTemplates: {
                isTemplateLibraryPresented = true
            },
            onRepeatWorkout: { record in
                switch record.source {
                case .program:
                    guard UUID(uuidString: record.programId) != nil else {
                        isQuickBuilderPresented = true
                        return
                    }
                    programWorkoutRoute = ProgramWorkoutRoute(programId: record.programId, workoutId: record.workoutId)
                case .template:
                    isTemplateLibraryPresented = true
                case .freestyle:
                    isQuickBuilderPresented = true
                }
            },
        )
        .navigationDestination(item: $sessionRoute) { session in
            WorkoutLaunchView(
                userSub: session.userSub,
                programId: session.programId,
                workoutId: session.workoutId,
                apiClient: apiClient,
                source: session.source,
                onOpenPlan: onOpenPlan,
            )
        }
        .navigationDestination(item: $programWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.programId,
                workoutId: route.workoutId,
                apiClient: apiClient,
                onOpenPlan: onOpenPlan,
            )
        }
        .navigationDestination(item: $presetWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.source.rawValue,
                workoutId: route.workout.id,
                apiClient: apiClient,
                presetWorkout: route.workout,
                source: route.source,
                onOpenPlan: onOpenPlan,
            )
        }
        .fullScreenCover(isPresented: $isQuickBuilderPresented) {
            NavigationStack {
                QuickWorkoutBuilderView { workout in
                    presetWorkoutRoute = PresetWorkoutRoute(workout: workout, source: .freestyle)
                }
            }
        }
        .fullScreenCover(isPresented: $isTemplateLibraryPresented) {
            NavigationStack {
                TemplateLibraryView(
                    viewModel: TemplateLibraryViewModel(userSub: userSub),
                    onStartTemplate: { workout in
                        presetWorkoutRoute = PresetWorkoutRoute(workout: workout, source: .template)
                    },
                )
            }
        }
        .task {
            handleExternalResumeRequest()
        }
        .onChange(of: resumeSessionRequest?.workoutId) { _, _ in
            handleExternalResumeRequest()
        }
    }

    private func handleExternalResumeRequest() {
        guard let requested = resumeSessionRequest else { return }
        sessionRoute = requested
        resumeSessionRequest = nil
        onResumeHandled()
    }
}

private struct ProfileTabView: View {
    let me: MeResponse
    let userSub: String
    let isOnline: Bool
    let apiClient: APIClientProtocol?
    let onLogout: () -> Void
    @State private var viewModel: ProfileViewModel
    @State private var selectedSession: ActiveWorkoutSession?

    init(
        me: MeResponse,
        userSub: String,
        isOnline: Bool,
        apiClient: APIClientProtocol?,
        onLogout: @escaping () -> Void,
    ) {
        self.me = me
        self.userSub = userSub
        self.isOnline = isOnline
        self.apiClient = apiClient
        self.onLogout = onLogout
        _viewModel = State(
            initialValue: ProfileViewModel(
                me: me,
                userSub: userSub,
                isOnline: isOnline,
            ),
        )
    }

    var body: some View {
        ProfileScreen(
            viewModel: viewModel,
            onLogout: onLogout,
            onOpenActiveSession: { session in
                selectedSession = session
            },
        )
        .onChange(of: isOnline) { _, online in
            viewModel.updateNetworkStatus(online)
        }
        .navigationDestination(item: $selectedSession) { session in
            WorkoutLaunchView(
                userSub: session.userSub,
                programId: session.programId,
                workoutId: session.workoutId,
                apiClient: apiClient,
            )
        }
    }
}

extension ActiveWorkoutSession: Identifiable {
    var id: String {
        "\(userSub)::\(programId)::\(workoutId)"
    }
}
