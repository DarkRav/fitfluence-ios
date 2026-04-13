import ComposableArchitecture
import SwiftUI

extension Notification.Name {
    static let fitfluenceWorkoutDidComplete = Notification.Name("fitfluence.workout.didComplete")
    static let fitfluenceTrainingPlanDidChange = Notification.Name("fitfluence.trainingPlan.didChange")
}

enum AthleteShellTab: String, CaseIterable, Hashable, Sendable {
    case today
    case programs
    case plan
    case progress
    case profile

    static let defaultTab: Self = .today

    var title: String {
        switch self {
        case .today:
            "Сегодня"
        case .programs:
            "Программы"
        case .plan:
            "План"
        case .progress:
            "Прогресс"
        case .profile:
            "Профиль"
        }
    }

    var navigationTitle: String {
        title
    }

    var systemImage: String {
        switch self {
        case .today:
            "figure.run"
        case .programs:
            "square.grid.2x2"
        case .plan:
            "calendar"
        case .progress:
            "chart.line.uptrend.xyaxis"
        case .profile:
            "person.crop.circle"
        }
    }
}

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
                        FFScreenSpinner()

                    case .needsOnboarding:
                        if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                            OnboardingView(store: onboardingStore)
                                .padding(.horizontal, FFSpacing.md)
                        } else {
                            FFScreenSpinner()
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
            .ffScreenBackground()
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
                    Text("Войдите, чтобы начать тренировки.")
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

    @State private var selectedTab: AthleteShellTab = .defaultTab
    @State private var resumeSession: ActiveWorkoutSession?
    @State private var resumeSessionTitle: String?
    @State private var pendingResumeRequest: ActiveWorkoutSession?
    @State private var isTrainingFlowPresented = false
    @State private var restTimer = RestTimerModel.shared
    @State private var suppressedCompletedSessionIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if let session = resumeSession, shouldShowResumeBanner {
                WorkoutInProgressBanner(
                    workoutName: resumeSessionTitle,
                    detailsText: resumeBannerDetailsText,
                    iconSystemName: resumeBannerIconName,
                    onContinue: {
                        restTimer.dismissCompletionMessage()
                        ClientAnalytics.track(
                            .workoutContinueButtonTapped,
                            properties: ["source": "other_tab_banner"],
                        )
                        pendingResumeRequest = session
                        if selectedTab != .today {
                            selectedTab = .today
                        }
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
                        store: store,
                        environment: environment,
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
                        onRoutePresentationChanged: { isPresented in
                            isTrainingFlowPresented = isPresented
                        },
                    )
                    .navigationTitle(AthleteShellTab.today.navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                }
                .tabItem {
                    Label(AthleteShellTab.today.title, systemImage: AthleteShellTab.today.systemImage)
                }
                .tag(AthleteShellTab.today)

                NavigationStack {
                    CatalogTabContent(
                        store: store,
                        environment: environment,
                        apiClient: apiClient,
                        userSub: me.subject ?? "anonymous",
                        onOpenPlanTab: {
                            selectedTab = .plan
                        },
                        onOpenWorkoutHubTab: {
                            selectedTab = .today
                        },
                    )
                    .navigationTitle(AthleteShellTab.programs.navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                }
                .tabItem {
                    Label(AthleteShellTab.programs.title, systemImage: AthleteShellTab.programs.systemImage)
                }
                .tag(AthleteShellTab.programs)

                NavigationStack {
                    PlanTabContent(
                        apiClient: apiClient,
                        userSub: me.subject ?? "anonymous",
                    )
                    .navigationTitle(AthleteShellTab.plan.navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                }
                .tabItem {
                    Label(AthleteShellTab.plan.title, systemImage: AthleteShellTab.plan.systemImage)
                }
                .tag(AthleteShellTab.plan)

                NavigationStack {
                    TrainingInsightsView(
                        viewModel: TrainingInsightsViewModel(
                            userSub: me.subject ?? "anonymous",
                            athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                        ),
                        isOnline: isOnline,
                        onOpenPlan: { selectedTab = .plan },
                        onStartNextWorkout: { selectedTab = .today },
                    )
                    .navigationTitle(AthleteShellTab.progress.navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                }
                .tabItem {
                    Label(AthleteShellTab.progress.title, systemImage: AthleteShellTab.progress.systemImage)
                }
                .tag(AthleteShellTab.progress)

                NavigationStack {
                    ProfileTabView(
                        me: me,
                        userSub: me.subject ?? "anonymous",
                        isOnline: isOnline,
                        apiClient: apiClient,
                        onLogout: onLogout,
                    )
                    .navigationTitle(AthleteShellTab.profile.navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                }
                .tabItem {
                    Label(AthleteShellTab.profile.title, systemImage: AthleteShellTab.profile.systemImage)
                }
                .tag(AthleteShellTab.profile)
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
        .onReceive(NotificationCenter.default.publisher(for: .fitfluenceWorkoutDidComplete)) { notification in
            handleWorkoutDidComplete(notification)
        }
    }

    private var shouldShowResumeBanner: Bool {
        if selectedTab != .today {
            return true
        }
        return !isTrainingFlowPresented
    }

    private var resumeBannerDetailsText: String? {
        if restTimer.isVisible {
            let time = formatRestTimer(restTimer.remainingSeconds)
            if let exerciseName = normalized(restTimer.exerciseName) {
                return "Отдых: \(time) • \(exerciseName)"
            }
            return "Отдых: \(time)"
        }
        return normalized(restTimer.completionMessage)
    }

    private var resumeBannerIconName: String {
        if restTimer.isVisible || normalized(restTimer.completionMessage) != nil {
            return "timer"
        }
        return "figure.strengthtraining.traditional"
    }

    private func refreshResumeSession() async {
        let userSub = me.subject ?? "anonymous"
        guard !userSub.isEmpty, userSub != "anonymous" else {
            resumeSession = nil
            resumeSessionTitle = nil
            return
        }
        let progressStore = LocalWorkoutProgressStore()
        let resumeStore = LocalWorkoutResumeStore()
        var latest = await progressStore.latestActiveSession(userSub: userSub)
        var remoteWorkoutTitle: String?

        if let currentLatest = latest,
           !(await canLaunchResumeSession(currentLatest, progressStore: progressStore))
        {
            self.resumeSession = nil
            self.resumeSessionTitle = nil
            latest = nil
        }

        if isOnline,
           let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol
        {
            let result = await athleteTrainingClient.activeEnrollmentProgress()
            if case let .success(progress) = result {
                if let enrollment = WorkoutDomainRules.resolveActiveEnrollment(progress) {
                    remoteWorkoutTitle = enrollment.resumeWorkout?.title
                }
                if let remoteSession = WorkoutDomainRules.remoteInProgressSession(userSub: userSub, progress: progress) {
                    latest = remoteSession
                }
            }
        }

        if let latest, suppressedCompletedSessionIDs.contains(sessionMarker(for: latest)) {
            resumeSession = nil
            resumeSessionTitle = nil
            return
        }

        resumeSession = latest
        guard let latest else {
            resumeSessionTitle = nil
            return
        }

        resumeSessionTitle = await resolveResumeWorkoutTitle(
            for: latest,
            userSub: userSub,
            progressStore: progressStore,
            resumeStore: resumeStore,
            remoteWorkoutTitle: remoteWorkoutTitle,
        )
    }

    private func canLaunchResumeSession(
        _ session: ActiveWorkoutSession,
        progressStore: WorkoutProgressStore,
    ) async -> Bool {
        let cacheStore = CompositeCacheStore()
        let hasCachedWorkoutDetails = await cacheStore.get(
            "workout.details:\(session.programId):\(session.workoutId)",
            as: WorkoutDetailsModel.self,
            namespace: session.userSub,
        ) != nil
        let snapshot = await progressStore.load(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
        )
        return WorkoutDomainRules.canLaunchSession(
            session: session,
            isOnline: isOnline,
            hasCachedWorkoutDetails: hasCachedWorkoutDetails,
            hasSnapshotDetails: snapshot?.workoutDetails != nil,
        )
    }

    private func formatRestTimer(_ totalSeconds: Int) -> String {
        let value = max(0, totalSeconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveResumeWorkoutTitle(
        for session: ActiveWorkoutSession,
        userSub: String,
        progressStore: WorkoutProgressStore,
        resumeStore: WorkoutResumeStore,
        remoteWorkoutTitle: String?,
    ) async -> String? {
        if let remoteWorkoutTitle = normalizedWorkoutTitle(remoteWorkoutTitle) {
            return remoteWorkoutTitle
        }

        if let localResume = await resumeStore.latest(userSub: userSub),
           localResume.programId == session.programId,
           localResume.workoutId == session.workoutId,
           let resumeTitle = normalizedWorkoutTitle(localResume.workoutName)
        {
            return resumeTitle
        }

        if let snapshot = await progressStore.load(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
        ),
            let snapshotTitle = normalizedWorkoutTitle(snapshot.workoutDetails?.title)
        {
            return snapshotTitle
        }

        return nil
    }

    private func normalizedWorkoutTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func handleWorkoutDidComplete(_ notification: Notification) {
        guard let workoutId = notification.userInfo?["workoutId"] as? String,
              let programId = notification.userInfo?["programId"] as? String
        else {
            return
        }

        let marker = sessionMarker(programId: programId, workoutId: workoutId)
        suppressedCompletedSessionIDs.insert(marker)
        pendingResumeRequest = nil

        if let resumeSession, sessionMarker(for: resumeSession) == marker {
            self.resumeSession = nil
            resumeSessionTitle = nil
        }
    }

    private func sessionMarker(for session: ActiveWorkoutSession) -> String {
        sessionMarker(programId: session.programId, workoutId: session.workoutId)
    }

    private func sessionMarker(programId: String, workoutId: String) -> String {
        "\(programId)::\(workoutId)"
    }
}

struct ProgramWorkoutRoute: Identifiable, Hashable {
    let programId: String
    let workoutId: String

    var id: String {
        "\(programId)::\(workoutId)"
    }
}

struct PresetWorkoutRoute: Identifiable, Equatable {
    let programId: String?
    let workout: WorkoutDetailsModel
    let source: WorkoutSource

    var id: String {
        "\(programId ?? source.rawValue)::\(source.rawValue)::\(workout.id)"
    }
}

private struct RecentWorkoutDetailsRoute: Identifiable {
    let record: CompletedWorkoutRecord

    var id: String {
        record.id
    }
}

private struct RepeatWorkoutPlanningRoute: Identifiable, Equatable {
    let workout: WorkoutDetailsModel
    let source: WorkoutSource

    var id: String {
        "\(source.rawValue)::\(workout.id)"
    }
}

enum RepeatWorkoutTemplateFallback {
    case quickBuilder
    case templateLibrary
}

enum RepeatWorkoutNavigationTarget: Equatable {
    case program(ProgramWorkoutRoute)
    case preset(PresetWorkoutRoute)
    case quickBuilder
    case templateLibrary
}

func resolveRepeatWorkoutTarget(
    for record: CompletedWorkoutRecord,
    progressStore: any WorkoutProgressStore = LocalWorkoutProgressStore(),
    templateFallback: RepeatWorkoutTemplateFallback,
    preferredWorkout: WorkoutDetailsModel? = nil,
) async -> RepeatWorkoutNavigationTarget {
    let storedWorkout: WorkoutDetailsModel?
    if let preferredWorkout {
        storedWorkout = preferredWorkout
    } else if let recordWorkout = record.workoutDetails {
        storedWorkout = recordWorkout
    } else {
        storedWorkout = await progressStore.load(
            userSub: record.userSub,
            programId: record.programId,
            workoutId: record.workoutId
        )?.workoutDetails
    }

    switch record.source {
    case .program:
        if UUID(uuidString: record.programId) != nil {
            return .program(ProgramWorkoutRoute(programId: record.programId, workoutId: record.workoutId))
        }
        if let storedWorkout {
            return .preset(PresetWorkoutRoute(programId: record.programId, workout: storedWorkout, source: .program))
        }
        return .quickBuilder
    case .template:
        if let storedWorkout {
            return .preset(
                PresetWorkoutRoute(
                    programId: nil,
                    workout: makeRepeatableWorkoutCopy(from: storedWorkout, prefix: "template-repeat"),
                    source: .template,
                )
            )
        }
        switch templateFallback {
        case .quickBuilder:
            return .quickBuilder
        case .templateLibrary:
            return .templateLibrary
        }
    case .freestyle:
        if let storedWorkout {
            return .preset(
                PresetWorkoutRoute(
                    programId: nil,
                    workout: makeRepeatableWorkoutCopy(from: storedWorkout, prefix: "quick-repeat"),
                    source: .freestyle,
                )
            )
        }
        return .quickBuilder
    }
}

private func makeRepeatableWorkoutCopy(from workout: WorkoutDetailsModel, prefix: String) -> WorkoutDetailsModel {
    workout.asRepeatableCopy(prefix: prefix)
}

private struct PlanTabContent: View {
    let apiClient: APIClientProtocol?
    let userSub: String
    private let trainingStore: any TrainingStore
    private let templateRepository: any WorkoutTemplateRepository
    private let exerciseCatalogRepository: any ExerciseCatalogRepository
    private let exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding

    @State private var planViewModel: PlanScheduleViewModel
    @State private var programWorkoutRoute: ProgramWorkoutRoute?
    @State private var presetWorkoutRoute: PresetWorkoutRoute?
    @State private var recentWorkoutDetailsRoute: RecentWorkoutDetailsRoute?
    @State private var repeatWorkoutPlanningRoute: RepeatWorkoutPlanningRoute?
    @State private var isQuickBuilderPresented = false

    init(
        apiClient: APIClientProtocol?,
        userSub: String,
    ) {
        self.apiClient = apiClient
        self.userSub = userSub
        trainingStore = LocalTrainingStore()
        templateRepository = BackendWorkoutTemplateRepository(
            apiClient: apiClient as? AthleteWorkoutTemplatesAPIClientProtocol,
            cacheStore: trainingStore,
        )
        exerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: apiClient as? ExerciseCatalogAPIClientProtocol,
            userSub: userSub,
            templateRepository: templateRepository,
        )
        exercisePickerSuggestionsProvider = TrainingStoreExercisePickerSuggestionsProvider(
            userSub: userSub,
            athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            templateRepository: templateRepository,
            trainingStore: trainingStore,
        )
        _planViewModel = State(
            initialValue: PlanScheduleViewModel(
                userSub: userSub,
                trainingStore: trainingStore,
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            ),
        )
    }

    var body: some View {
        PlanScheduleScreen(
            viewModel: planViewModel,
            exerciseCatalogRepository: exerciseCatalogRepository,
            exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
            onOpenProgramWorkout: { programId, workoutId in
                programWorkoutRoute = ProgramWorkoutRoute(programId: programId, workoutId: workoutId)
            },
            onOpenPresetWorkout: { workout, source, programId in
                presetWorkoutRoute = PresetWorkoutRoute(programId: programId, workout: workout, source: source)
            },
            onOpenQuickWorkoutBuilder: {
                isQuickBuilderPresented = true
            },
            onOpenCompletedWorkout: { record in
                recentWorkoutDetailsRoute = RecentWorkoutDetailsRoute(record: record)
            },
        )
        .navigationDestination(item: $programWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.programId,
                workoutId: route.workoutId,
                apiClient: apiClient,
                onOpenPlan: {},
            )
            .navigationBarBackButtonHidden(false)
        }
        .navigationDestination(item: $presetWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.programId ?? route.source.rawValue,
                workoutId: route.workout.id,
                apiClient: apiClient,
                presetWorkout: route.workout,
                source: route.source,
                onOpenPlan: {},
            )
            .navigationBarBackButtonHidden(false)
        }
        .navigationDestination(item: $recentWorkoutDetailsRoute) { route in
            RecentWorkoutDetailsView(
                record: route.record,
                onRepeat: { workout in
                    Task {
                        await openRepeatWorkout(route.record, preferredWorkout: workout)
                    }
                },
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            )
            .navigationBarBackButtonHidden(false)
        }
        .sheet(item: $repeatWorkoutPlanningRoute) { route in
            RepeatWorkoutPlanningSheet(
                userSub: userSub,
                workout: route.workout,
                source: route.source,
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                onClose: {
                    repeatWorkoutPlanningRoute = nil
                },
                onSaved: { day in
                    repeatWorkoutPlanningRoute = nil
                    recentWorkoutDetailsRoute = nil
                    Task {
                        await planViewModel.focus(on: day)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $isQuickBuilderPresented) {
            NavigationStack {
                QuickWorkoutBuilderView(
                    exerciseCatalogRepository: exerciseCatalogRepository,
                    exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
                ) { workout in
                    Task {
                        await openBuiltCustomWorkout(workout)
                    }
                }
            }
        }
    }

    private func openRepeatWorkout(_ record: CompletedWorkoutRecord, preferredWorkout: WorkoutDetailsModel? = nil) async {
        switch await resolveRepeatWorkoutTarget(
            for: record,
            templateFallback: .quickBuilder,
            preferredWorkout: preferredWorkout,
        ) {
        case let .program(route):
            programWorkoutRoute = route
        case let .preset(route):
            repeatWorkoutPlanningRoute = RepeatWorkoutPlanningRoute(
                workout: route.workout,
                source: route.source,
            )
        case .quickBuilder:
            isQuickBuilderPresented = true
        case .templateLibrary:
            isQuickBuilderPresented = true
        }
    }

    @MainActor
    private func presentBuiltWorkout(_ workout: WorkoutDetailsModel) {
        presetWorkoutRoute = PresetWorkoutRoute(programId: nil, workout: workout, source: .freestyle)
    }

    private func openBuiltCustomWorkout(_ workout: WorkoutDetailsModel) async {
        if let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol {
            let result = await athleteTrainingClient.createCustomWorkout(
                request: workout.asCreateCustomWorkoutRequest(),
            )
            if case let .success(detailsResponse) = result {
                await MainActor.run {
                    presentBuiltWorkout(detailsResponse.asWorkoutDetailsModel())
                }
                return
            }
        }

        await MainActor.run {
            presentBuiltWorkout(workout)
        }
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
    @State private var myProgramsViewModel: MyProgramsViewModel
    @State private var athletesShowcaseViewModel: AthletesShowcaseViewModel
    @State private var athletesSearchViewModel: AthleteSearchViewModel
    @State private var followingViewModel: FollowingAthletesViewModel

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
        _myProgramsViewModel = State(
            initialValue: MyProgramsViewModel(
                userSub: userSub,
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: unauthorizedHandler,
            ),
        )
        _athletesShowcaseViewModel = State(
            initialValue: AthletesShowcaseViewModel(
                userSub: userSub,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: unauthorizedHandler,
            ),
        )
        _athletesSearchViewModel = State(
            initialValue: AthleteSearchViewModel(
                userSub: userSub,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: unauthorizedHandler,
            ),
        )
        _followingViewModel = State(
            initialValue: FollowingAthletesViewModel(
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
            CatalogScreen(
                programsViewModel: viewModel,
                myProgramsViewModel: myProgramsViewModel,
                athletesShowcaseViewModel: athletesShowcaseViewModel,
                athletesSearchViewModel: athletesSearchViewModel,
                followingViewModel: followingViewModel,
                userSub: userSub,
                environment: environment,
                onProgramTap: { programID, displayMode in
                    store.send(.openProgram(programId: programID, userSub: userSub, displayMode: displayMode))
                },
                onOpenPlan: {
                    onOpenPlanTab()
                },
                onOpenWorkoutHub: {
                    onOpenWorkoutHubTab()
                },
                onUnauthorized: {
                    store.send(.logoutTapped)
                },
            )
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
                        displayMode: selectedProgram.displayMode,
                        onOpenProgramPlan: {
                            store.send(.programDetailsDismissed)
                            onOpenPlanTab()
                        },
                        onOpenWorkoutHub: {
                            store.send(.programDetailsDismissed)
                            onOpenWorkoutHubTab()
                        },
                        onOpenProgram: { programID, displayMode in
                            store.send(.openProgram(programId: programID, userSub: userSub, displayMode: displayMode))
                        },
                    )
                    .navigationTitle("Программа")
                    .navigationBarBackButtonHidden(false)
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
    let personalRecordHighlights: [String]
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
    var displayMode: ProgramDetailsDisplayMode = .active
    var isFirstWorkoutInProgramFlow = false
    var allowsImmediateStart = true
    var plannedDay: Date? = nil
    var plannedDateText: String? = nil
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
    @State private var conflictingSessionRoute: ActiveWorkoutSession?
    @State private var resolvedSource: WorkoutSource?
    @State private var isWorkoutDatePlanningPresented = false
    @State private var plannedDateOverride: PlannedDateOverride?
    @State private var remoteScheduledDay: Date?
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeletingPlannedWorkout = false
    @State private var deleteError: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    private struct NextWorkoutRoute: Identifiable, Hashable {
        let programId: String
        let workoutId: String

        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    private struct PlannedDateOverride {
        let day: Date
        let dateText: String
    }

    var body: some View {
        Group {
            if isLoading {
                FFScreenSpinner()
            } else if !allowsImmediateStart, let details {
                workoutPreviewState(details: details)
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
                    onOpenPlan: {
                        dismiss()
                        onOpenPlan?()
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
                        source: currentSource,
                        athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                        networkMonitor: NetworkMonitor(),
                        executionContext: executionContext,
                        exerciseCatalogRepository: BackendExerciseCatalogRepository(
                            apiClient: apiClient as? ExerciseCatalogAPIClientProtocol,
                            userSub: userSub,
                            templateRepository: BackendWorkoutTemplateRepository(
                                apiClient: apiClient as? AthleteWorkoutTemplatesAPIClientProtocol,
                            ),
                        ),
                        exercisePickerSuggestionsProvider: TrainingStoreExercisePickerSuggestionsProvider(
                            userSub: userSub,
                            athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                            templateRepository: BackendWorkoutTemplateRepository(
                                apiClient: apiClient as? AthleteWorkoutTemplatesAPIClientProtocol,
                            ),
                        ),
                        restTimer: RestTimerModel.shared,
                    ),
                    onExit: {
                        isExitConfirmationPresented = true
                    },
                    onFinish: { summary in
                        Task { await handleCompletion(summary) }
                    },
                    onResumeExisting: { session in
                        conflictingSessionRoute = session
                    },
                    onBlockedBack: {
                        dismiss()
                    }
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
        .ffScreenBackground()
        .sheet(isPresented: $isWorkoutDatePlanningPresented) {
            if let details {
                WorkoutDatePlanningSheet(
                    userSub: userSub,
                    programId: programId,
                    workoutId: workoutId,
                    workout: details,
                    plannedDay: effectivePlannedDay,
                    onClose: {
                        isWorkoutDatePlanningPresented = false
                    },
                    onSaved: { day, dateText in
                        plannedDateOverride = PlannedDateOverride(day: day, dateText: dateText)
                        isWorkoutDatePlanningPresented = false
                    }
                )
            }
        }
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canDeletePlannedCustomWorkout {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Удалить тренировку", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Действия с тренировкой")
                }
            }
        }
        .task {
            await load()
        }
        .navigationDestination(item: $conflictingSessionRoute) { session in
            WorkoutLaunchView(
                userSub: session.userSub,
                programId: session.programId,
                workoutId: session.workoutId,
                apiClient: apiClient,
                source: session.source,
                onBackToWorkoutHub: onBackToWorkoutHub,
                onOpenPlan: onOpenPlan,
            )
        }
        .alert("Завершить тренировку?", isPresented: $isExitConfirmationPresented) {
            Button("Продолжить тренировку", role: .cancel) {}
            Button("Сохранить и выйти") {
                ClientAnalytics.track(
                    .workoutSaveAndExit,
                    properties: [
                        "program_id": programId,
                        "workout_id": workoutId,
                    ],
                )
                dismiss()
            }
            Button("Отменить тренировку", role: .destructive) {
                Task { await abandonWorkoutAndExit() }
            }
        } message: {
            Text("Прогресс сохранён на устройстве.")
        }
        .alert("Удалить тренировку?", isPresented: $isDeleteConfirmationPresented) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task { await deletePlannedWorkout() }
            }
        } message: {
            Text("Тренировка будет удалена из плана.")
        }
        .alert(
            deleteError?.title ?? "Не удалось удалить тренировку",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteError = nil
                    }
                }
            )
        ) {
            Button("Понятно") {
                deleteError = nil
            }
        } message: {
            Text(deleteError?.message ?? "")
        }
        .overlay {
            if isCompletingWorkout {
                ZStack {
                    FFColors.background.opacity(0.72).ignoresSafeArea()
                    FFLoadingState(title: "Сохраняем тренировку")
                        .padding(.horizontal, FFSpacing.md)
                }
            } else if isDeletingPlannedWorkout {
                ZStack {
                    FFColors.background.opacity(0.72).ignoresSafeArea()
                    FFLoadingState(title: "Удаляем тренировку")
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
                onOpenPlan: {
                    workoutSummary = nil
                    dismiss()
                    onOpenPlan?()
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
            .navigationBarBackButtonHidden(false)
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
        let localSnapshot = await progressStore.load(
            userSub: userSub,
            programId: programId,
            workoutId: workoutId,
        )
        resolvedSource = source

        if let presetWorkout,
           !(currentSource != .template && UUID(uuidString: workoutId) != nil && athleteTrainingClient != nil)
        {
            details = presetWorkout
            error = nil
            routeState = .resume
            await cacheStore.set(cacheKey, value: presetWorkout, namespace: userSub, ttl: 60 * 60 * 24)
            return
        }

        if let localSnapshot,
           localSnapshot.status == .completed,
           let restored = localSnapshot.workoutDetails
        {
            details = restored
            error = nil
            routeState = .completed
            readOnlySummary = await buildLocalCompletedSummary(from: localSnapshot, fallbackTitle: restored.title)
            await cacheStore.set(cacheKey, value: restored, namespace: userSub, ttl: 60 * 60 * 24)
            return
        }

        let canLoadFromProgramAPI = currentSource == .program && UUID(uuidString: programId) != nil

        if UUID(uuidString: workoutId) != nil,
           let athleteTrainingClient
        {
            let athleteResult = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutId)
            switch athleteResult {
            case let .success(workoutDetails):
                await applyRemoteWorkoutDetails(
                    workoutDetails,
                    cacheStore: cacheStore,
                    cacheKey: cacheKey,
                    contextCacheKey: contextCacheKey,
                )
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
        } else if let snapshot = localSnapshot,
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
        var personalRecordHighlights: [String] = []

        if currentSource != .template, UUID(uuidString: workoutId) != nil {
            _ = await SyncCoordinator.shared.enqueueCompleteWorkout(
                namespace: userSub,
                workoutInstanceId: workoutId,
                completedAt: Date(),
            )
        }

        if currentSource != .template,
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

                personalRecordHighlights = makePersonalRecordHighlights(comparisonResponse.personalRecords ?? [])
                hasNewPersonalRecord = comparisonResponse.hasNewPersonalRecord == true ||
                    !personalRecordHighlights.isEmpty
            }

            if currentSource == .program {
                let activeEnrollmentResult = await athleteTrainingClient.activeEnrollmentProgress()
                if case let .success(progress) = activeEnrollmentResult,
                   let target = WorkoutDomainRules.nextWorkoutTarget(
                       from: progress,
                       fallbackProgramId: programId,
                       excludingWorkoutId: workoutId,
                   )
                {
                    nextWorkout = WorkoutSummaryState.NextWorkout(
                        programId: target.programId,
                        workoutId: target.workoutId,
                        title: target.title,
                    )
                }
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
            personalRecordHighlights: personalRecordHighlights,
        )
    }

    private func startNextWorkout(from summary: WorkoutSummaryState) async {
        guard let nextWorkout = summary.nextWorkout else {
            workoutSummary = nil
            dismiss()
            onBackToWorkoutHub?()
            return
        }

        if let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol,
           let decision = await validateRemoteStartDecision(
               programId: nextWorkout.programId,
               workoutInstanceId: nextWorkout.workoutId,
               athleteTrainingClient: athleteTrainingClient,
               updatesCurrentRoute: false,
            )
        {
            switch decision {
            case .start:
                break
            case .openExisting:
                workoutSummary = nil
                nextWorkoutRoute = NextWorkoutRoute(programId: nextWorkout.programId, workoutId: nextWorkout.workoutId)
                return
            case .blocked:
                workoutSummary = nil
                dismiss()
                if let onOpenPlan {
                    onOpenPlan()
                } else {
                    onBackToWorkoutHub?()
                }
                return
            }
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
        guard currentSource != .template, UUID(uuidString: workoutId) != nil else {
            routeState = .resume
            return
        }

        isStartingPlannedWorkout = true
        defer { isStartingPlannedWorkout = false }

        if let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol,
           let decision = await validateRemoteStartDecision(
               programId: programId,
               workoutInstanceId: workoutId,
               athleteTrainingClient: athleteTrainingClient,
               updatesCurrentRoute: true,
            )
        {
            switch decision {
            case .start:
                break
            case .openExisting:
                routeState = .resume
                return
            case .blocked:
                return
            }
        }

        _ = await SyncCoordinator.shared.enqueueStartWorkout(
            namespace: userSub,
            workoutInstanceId: workoutId,
            startedAt: Date(),
        )
        routeState = .resume
    }

    private func deletePlannedWorkout() async {
        guard canDeletePlannedCustomWorkout else { return }
        guard let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol else {
            deleteError = UserFacingError(
                kind: .server,
                title: "Удаление недоступно",
                message: "Не удалось удалить тренировку без соединения с сервером.",
            )
            return
        }

        isDeletingPlannedWorkout = true
        defer { isDeletingPlannedWorkout = false }

        let deleteResult = await athleteTrainingClient.deleteCustomWorkout(workoutInstanceId: workoutId)
        switch deleteResult {
        case .success:
            break
        case let .failure(apiError):
            if case let .httpError(statusCode, _) = apiError, statusCode == 404 {
                break
            }
            deleteError = deleteError(for: apiError)
            return
        }

        let progressStore = LocalWorkoutProgressStore()
        let cacheStore = CompositeCacheStore()
        await progressStore.remove(
            userSub: userSub,
            programId: programId,
            workoutId: workoutId,
        )
        await cacheStore.remove("workout.details:\(programId):\(workoutId)", namespace: userSub)
        await cacheStore.remove("workout.execution.context:\(programId):\(workoutId)", namespace: userSub)
        if currentSource == .freestyle {
            await cacheStore.remove("workout.details:\(WorkoutSource.freestyle.rawValue):\(workoutId)", namespace: userSub)
        }
        RestTimerModel.shared.clearIfMatches(workoutId: workoutId)

        if let scheduledDay = effectivePlannedDay {
            await LocalTrainingStore().deletePlan(
                userSub: userSub,
                day: scheduledDay,
                planId: "remote-\(workoutId)",
                workoutId: workoutId,
                title: details?.title ?? "Тренировка",
                source: .freestyle,
            )
            NotificationCenter.default.post(name: .fitfluenceTrainingPlanDidChange, object: scheduledDay)
        } else {
            NotificationCenter.default.post(name: .fitfluenceTrainingPlanDidChange, object: nil)
        }

        dismiss()
    }

    private func abandonWorkoutAndExit() async {
        ClientAnalytics.track(
            .workoutCancelled,
            properties: [
                "program_id": programId,
                "workout_id": workoutId,
            ],
        )

        isAbandoningOnExit = true
        defer { isAbandoningOnExit = false }

        let progressStore = LocalWorkoutProgressStore()
        let cacheStore = CompositeCacheStore()
        let cacheKey = "workout.details:\(programId):\(workoutId)"
        let contextCacheKey = "workout.execution.context:\(programId):\(workoutId)"

        await progressStore.remove(
            userSub: userSub,
            programId: programId,
            workoutId: workoutId,
        )
        await cacheStore.remove(cacheKey, namespace: userSub)
        await cacheStore.remove(contextCacheKey, namespace: userSub)
        RestTimerModel.shared.clearIfMatches(workoutId: workoutId)

        if currentSource != .template, UUID(uuidString: workoutId) != nil {
            _ = await SyncCoordinator.shared.enqueueAbandonWorkout(
                namespace: userSub,
                workoutInstanceId: workoutId,
                abandonedAt: Date(),
            )
        }

        dismiss()
        onBackToWorkoutHub?()
    }

    private func deleteError(for apiError: APIError) -> UserFacingError {
        switch apiError {
        case .offline:
            return UserFacingError(
                kind: .offline,
                title: "Нет подключения к интернету",
                message: "Удалить уже созданную тренировку можно только после восстановления соединения.",
            )
        case .httpError(let statusCode, _):
            return UserFacingError(
                kind: .server,
                title: "Не удалось удалить тренировку",
                message: "Сервер вернул код \(statusCode). Повторите попытку позже.",
            )
        case .unauthorized, .forbidden:
            return apiError.userFacing(context: .workoutPlayer)
        case .timeout, .transportError, .serverError, .decodingError, .invalidURL, .cancelled, .unknown:
            return UserFacingError(
                kind: .server,
                title: "Не удалось удалить тренировку",
                message: "Повторите попытку позже.",
            )
        }
    }

    private func scheduledDay(from workout: AthleteWorkoutInstance) -> Date? {
        if let scheduledAt = workout.scheduledAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           let date = AthleteWorkoutDetailsResponse.parseScheduledDateValue(scheduledAt)
        {
            return date
        }
        if let scheduledDate = workout.scheduledDate?.trimmingCharacters(in: .whitespacesAndNewlines),
           let date = AthleteWorkoutDetailsResponse.parseScheduledDateValue(scheduledDate)
        {
            return date
        }
        return nil
    }

    private func formattedPlannedDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
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
        var personalRecordHighlights: [String] = []

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

                personalRecordHighlights = makePersonalRecordHighlights(comparisonResponse.personalRecords ?? [])
                hasNewPersonalRecord = comparisonResponse.hasNewPersonalRecord == true ||
                    !personalRecordHighlights.isEmpty
            }

            if currentSource == .program {
                let activeEnrollmentResult = await athleteTrainingClient.activeEnrollmentProgress()
                if case let .success(progress) = activeEnrollmentResult,
                   let target = WorkoutDomainRules.nextWorkoutTarget(
                       from: progress,
                       fallbackProgramId: programId,
                       excludingWorkoutId: workoutDetails.workout.id,
                   )
                {
                    nextWorkout = WorkoutSummaryState.NextWorkout(
                        programId: target.programId,
                        workoutId: target.workoutId,
                        title: target.title,
                    )
                }
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
            personalRecordHighlights: personalRecordHighlights,
        )
    }

    private enum RemoteStartDecision {
        case start
        case openExisting
        case blocked
    }

    private func validateRemoteStartDecision(
        programId: String,
        workoutInstanceId: String,
        athleteTrainingClient: AthleteTrainingClientProtocol,
        updatesCurrentRoute: Bool,
    ) async -> RemoteStartDecision? {
        switch await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: workoutInstanceId) {
        case let .success(workoutDetails):
            if updatesCurrentRoute {
                let cacheStore = CompositeCacheStore()
                let cacheKey = "workout.details:\(programId):\(workoutInstanceId)"
                let contextCacheKey = "workout.execution.context:\(programId):\(workoutInstanceId)"
                await applyRemoteWorkoutDetails(
                    workoutDetails,
                    cacheStore: cacheStore,
                    cacheKey: cacheKey,
                    contextCacheKey: contextCacheKey,
                )
            }

            switch workoutDetails.workout.status {
            case .planned, .missed, .none:
                return .start
            case .inProgress:
                return .openExisting
            case .completed, .abandoned:
                return .blocked
            }
        case .failure:
            return nil
        }
    }

    private func applyRemoteWorkoutDetails(
        _ workoutDetails: AthleteWorkoutDetailsResponse,
        cacheStore: CacheStore,
        cacheKey: String,
        contextCacheKey: String,
    ) async {
        let mapped = workoutDetails.asWorkoutDetailsModel()
        details = mapped
        error = nil
        routeState = resolveWorkoutInstanceRouteState(workoutDetails.workout.status)
        resolvedSource = workoutDetails.workout.source == .custom ? .freestyle : .program
        remoteScheduledDay = scheduledDay(from: workoutDetails.workout)
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
    }

    private func buildLocalCompletedSummary(
        from snapshot: WorkoutProgressSnapshot,
        fallbackTitle: String,
    ) async -> WorkoutSummaryState {
        let completedSets = snapshot.exercises.values.flatMap(\.sets).filter(\.isCompleted)
        let derivedSetCount = completedSets.count
        let derivedReps = completedSets.reduce(0) { partial, set in
            partial + max(0, Int(Double(set.repsText) ?? 0))
        }
        let derivedVolume = completedSets.reduce(0.0) { partial, set in
            let reps = Double(set.repsText) ?? 0
            let weight = Double(set.weightText) ?? 0
            return partial + reps * weight
        }
        let derivedDuration = max(
            0,
            Int(snapshot.lastUpdated.timeIntervalSince(snapshot.startedAt ?? snapshot.lastUpdated)),
        )

        let matchingRecord = await LocalTrainingStore()
            .history(userSub: userSub, source: nil, limit: 20)
            .first(where: { $0.programId == programId && $0.workoutId == workoutId })

        return WorkoutSummaryState(
            id: "local-completed-\(workoutId)",
            workoutTitle: matchingRecord?.workoutTitle ?? fallbackTitle,
            durationSeconds: matchingRecord?.durationSeconds ?? derivedDuration,
            totalSets: matchingRecord?.completedSets ?? derivedSetCount,
            totalReps: derivedReps,
            volume: matchingRecord?.volume ?? derivedVolume,
            comparison: nil,
            nextWorkout: nil,
            hasNewPersonalRecord: false,
            personalRecordHighlights: [],
        )
    }

    private func makePersonalRecordHighlights(_ records: [AthletePersonalRecord]) -> [String] {
        records
            .prefix(3)
            .map { record in
                let exerciseName = record.exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (exerciseName?.isEmpty == false ? exerciseName! : "Упражнение")
                return "\(title): \(formattedPersonalRecordValue(record)) — личный рекорд"
            }
    }

    private func formattedPersonalRecordValue(_ record: AthletePersonalRecord) -> String {
        guard let value = record.value else {
            return "новое значение"
        }
        let valueText: String
        if floor(value) == value {
            valueText = "\(Int(value))"
        } else {
            valueText = String(format: "%.1f", value)
        }
        let unit = record.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if unit.isEmpty {
            return valueText
        }
        return "\(valueText) \(unit)"
    }

    private var currentSource: WorkoutSource {
        resolvedSource ?? source
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
        WorkoutIntroView(
            workout: details,
            primaryActionTitle: "Начать",
            dateBadgeText: effectivePlannedDateText,
            onPrimaryAction: {
                Task { await startPlannedWorkout() }
            },
        )
    }

    @ViewBuilder
    private func workoutPreviewState(details: WorkoutDetailsModel) -> some View {
        WorkoutIntroView(
            workout: details,
            primaryActionTitle: effectivePlannedDay != nil ? "Изменить дату" : "Назначить дату",
            dateBadgeText: effectivePlannedDateText,
            showsPrimaryAction: displayMode == .active,
            onPrimaryAction: {
                isWorkoutDatePlanningPresented = true
            },
        )
    }

    private var effectivePlannedDay: Date? {
        plannedDateOverride?.day ?? plannedDay ?? remoteScheduledDay
    }

    private var effectivePlannedDateText: String? {
        plannedDateOverride?.dateText ?? plannedDateText ?? remoteScheduledDay.map(formattedPlannedDateText)
    }

    private var canDeletePlannedCustomWorkout: Bool {
        routeState == .requiresStart && currentSource == .freestyle && UUID(uuidString: workoutId) != nil
    }

    @ViewBuilder
    private var abandonedWorkoutState: some View {
        if let details {
            WorkoutIntroView(
                workout: details,
                primaryActionTitle: effectivePlannedDay != nil ? "Изменить дату" : "Назначить дату",
                dateBadgeText: effectivePlannedDateText,
                helperText: "Тренировка была прервана. Назначьте новую дату, чтобы вернуться к ней позже.",
                onPrimaryAction: {
                    isWorkoutDatePlanningPresented = true
                },
            )
        } else {
            FFEmptyState(title: "Тренировка прервана", message: "Назначьте новую дату, чтобы вернуться к ней позже.")
                .padding(.horizontal, FFSpacing.md)
        }
    }
}

private struct WorkoutDatePlanningSheet: View {
    let userSub: String
    let programId: String
    let workoutId: String
    let workout: WorkoutDetailsModel
    let plannedDay: Date?
    let onClose: () -> Void
    let onSaved: (Date, String) -> Void

    @State private var viewModel: PlanScheduleViewModel
    @State private var targetDay: Date
    @State private var isConflictAlertPresented = false

    init(
        userSub: String,
        programId: String,
        workoutId: String,
        workout: WorkoutDetailsModel,
        plannedDay: Date?,
        onClose: @escaping () -> Void,
        onSaved: @escaping (Date, String) -> Void,
    ) {
        self.userSub = userSub
        self.programId = programId
        self.workoutId = workoutId
        self.workout = workout
        self.plannedDay = plannedDay
        self.onClose = onClose
        self.onSaved = onSaved

        let today = Date()
        let initialDay = max(plannedDay ?? today, today)
        _viewModel = State(initialValue: PlanScheduleViewModel(userSub: userSub))
        _targetDay = State(initialValue: initialDay)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()

                VStack(spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(workout.title)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(plannedItem == nil ? "Выберите дату для этой тренировки." : "Выберите новую дату для этой тренировки.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            DatePicker(
                                plannedItem == nil ? "Дата тренировки" : "Новая дата",
                                selection: $targetDay,
                                in: minimumSelectableDay...,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .tint(FFColors.accent)

                            if let orderingErrorText {
                                Text(orderingErrorText)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.danger)
                            }

                            let conflicts = viewModel.conflictCount(on: targetDay, excluding: plannedItem)
                            if conflicts > 0, orderingErrorText == nil {
                                Text("На выбранную дату уже есть \(conflicts) тренировок.")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.danger)
                            }
                        }
                    }

                    HStack(spacing: FFSpacing.sm) {
                        FFButton(title: "Отмена", variant: .secondary, action: onClose)
                        FFButton(
                            title: plannedItem == nil ? "Сохранить дату" : "Перенести",
                            variant: orderingErrorText == nil ? .primary : .disabled
                        ) {
                            guard orderingErrorText == nil else { return }
                            let conflicts = viewModel.conflictCount(on: targetDay, excluding: plannedItem)
                            if conflicts > 0 {
                                isConflictAlertPresented = true
                            } else {
                                applyDateChange()
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .navigationTitle(plannedItem == nil ? "Назначить дату" : "Изменить дату")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.onAppear()
            }
            .alert("Конфликт по дате", isPresented: $isConflictAlertPresented) {
                Button("Отмена", role: .cancel) {}
                Button("Продолжить") {
                    applyDateChange()
                }
            } message: {
                let conflicts = viewModel.conflictCount(on: targetDay, excluding: plannedItem)
                Text("На выбранную дату уже есть \(conflicts) тренировок. Продолжить?")
            }
        }
    }

    private var plannedItem: PlanScheduleViewModel.DayScheduleItem? {
        guard let plannedDay else { return nil }
        return viewModel.dayItems(for: plannedDay).first {
            guard $0.programId == programId else { return false }
            if $0.workoutId == workoutId {
                return true
            }
            return $0.workoutDetails?.id == workoutId
        }
    }

    private var minimumSelectableDay: Date {
        dateWindow?.earliest ?? Calendar.current.startOfDay(for: Date())
    }

    private var dateWindow: PlanScheduleViewModel.ProgramWorkoutDateWindow? {
        viewModel.allowedDateWindow(
            forProgramWorkout: programId,
            workoutId: workoutId,
            dayOrder: workout.dayOrder,
            excluding: plannedItem,
        )
    }

    private var orderingErrorText: String? {
        let normalizedTarget = Calendar.current.startOfDay(for: targetDay)
        guard let window = dateWindow else { return nil }

        if normalizedTarget < window.earliest {
            return "Эта тренировка должна идти после предыдущей по программе."
        }

        if let latest = window.latest, normalizedTarget > latest {
            return "Эта тренировка должна идти раньше следующей по программе."
        }

        if let latest = window.latest, window.earliest > latest {
            return "Сначала измените соседние тренировки в программе, затем вернитесь к этой."
        }

        return nil
    }

    private func applyDateChange() {
        Task {
            if let plannedItem {
                if plannedItem.status.isMissedLike {
                    await viewModel.replanMissed(plannedItem, on: targetDay)
                } else {
                    await viewModel.movePlan(plannedItem, to: targetDay)
                }
            } else {
                await viewModel.scheduleProgramWorkout(
                    programId: programId,
                    workoutId: workoutId,
                    title: workout.title,
                    workoutDetails: workout,
                    on: targetDay,
                )
            }

            let dateText = targetDay.formatted(
                Date.FormatStyle()
                    .weekday(.wide)
                    .day(.defaultDigits)
                    .month(.wide)
            )
            onSaved(targetDay, dateText)
        }
    }
}

private struct RepeatWorkoutPlanningSheet: View {
    let userSub: String
    let workout: WorkoutDetailsModel
    let source: WorkoutSource
    let athleteTrainingClient: AthleteTrainingClientProtocol?
    let onClose: () -> Void
    let onSaved: (Date) -> Void

    @State private var viewModel: PlanScheduleViewModel
    @State private var targetDay: Date
    @State private var isConflictAlertPresented = false

    init(
        userSub: String,
        workout: WorkoutDetailsModel,
        source: WorkoutSource,
        athleteTrainingClient: AthleteTrainingClientProtocol?,
        onClose: @escaping () -> Void,
        onSaved: @escaping (Date) -> Void,
    ) {
        self.userSub = userSub
        self.workout = workout
        self.source = source
        self.athleteTrainingClient = athleteTrainingClient
        self.onClose = onClose
        self.onSaved = onSaved

        let now = Date()
        _viewModel = State(
            initialValue: PlanScheduleViewModel(
                userSub: userSub,
                athleteTrainingClient: athleteTrainingClient,
            ),
        )
        _targetDay = State(initialValue: now)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background.ignoresSafeArea()

                VStack(spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(workout.title)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(helperText)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            DatePicker(
                                "Дата тренировки",
                                selection: $targetDay,
                                in: minimumSelectableDay...,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .tint(FFColors.accent)

                            DatePicker(
                                "Время",
                                selection: $targetDay,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxHeight: 110)
                            .colorScheme(.light)

                            let conflicts = viewModel.conflictCount(on: targetDay, excluding: nil)
                            if conflicts > 0 {
                                Text("На выбранную дату уже есть \(conflicts) тренировок.")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.danger)
                            }
                        }
                    }

                    HStack(spacing: FFSpacing.sm) {
                        FFButton(title: "Отмена", variant: .secondary, action: onClose)
                        FFButton(title: "Запланировать", variant: .primary) {
                            let conflicts = viewModel.conflictCount(on: targetDay, excluding: nil)
                            if conflicts > 0 {
                                isConflictAlertPresented = true
                            } else {
                                applyDateChange()
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .navigationTitle("Повторить тренировку")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.onAppear()
            }
            .alert("Конфликт по дате", isPresented: $isConflictAlertPresented) {
                Button("Отмена", role: .cancel) {}
                Button("Продолжить") {
                    applyDateChange()
                }
            } message: {
                let conflicts = viewModel.conflictCount(on: targetDay, excluding: nil)
                Text("На выбранную дату уже есть \(conflicts) тренировок. Продолжить?")
            }
            .alert(
                "Не удалось запланировать тренировку",
                isPresented: Binding(
                    get: { viewModel.repeatSchedulingErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.dismissRepeatSchedulingError()
                        }
                    }
                )
            ) {
                Button("Понятно") {
                    viewModel.dismissRepeatSchedulingError()
                }
            } message: {
                Text(viewModel.repeatSchedulingErrorMessage ?? "")
            }
        }
    }

    private var helperText: String {
        switch source {
        case .program:
            return "Выберите дату для копии этой тренировки."
        case .freestyle:
            return "Выберите дату, и тренировка появится в календаре и плане."
        case .template:
            return "Выберите дату, и копия тренировки из шаблона появится в календаре и плане."
        }
    }

    private var minimumSelectableDay: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func applyDateChange() {
        Task {
            let didSchedule = await viewModel.scheduleRepeatedWorkout(
                workout,
                source: source,
                on: targetDay,
            )
            guard didSchedule else { return }
            onSaved(targetDay)
        }
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
    var onOpenPlan: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(summary.workoutTitle)
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(3)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Сводка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        metricRow(title: "Длительность", value: formattedDuration(summary.durationSeconds))
                        metricRow(title: "Выполнено подходов", value: "\(summary.totalSets)")
                        metricRow(title: "Общий объём", value: "\(Int(summary.volume)) кг")
                    }
                }

                if let comparison = summary.comparison {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Сравнение")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            deltaRow(title: "Объём", value: volumeComparisonText(comparison: comparison))
                            if let repsDelta = comparison.repsDelta {
                                deltaRow(title: "Повторы", value: signed(repsDelta))
                            }
                            if let durationDelta = comparison.durationDeltaSeconds {
                                deltaRow(title: "Длительность", value: signed(durationDelta))
                            }
                        }
                    }
                }

                if !summary.personalRecordHighlights.isEmpty {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Личные рекорды")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            ForEach(summary.personalRecordHighlights, id: \.self) { item in
                                Text(item)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.accent)
                            }
                        }
                    }
                }

                if let onOpenPlan {
                    FFButton(title: "Перейти в план", variant: .secondary) {
                        onOpenPlan()
                    }
                } else if let onStartNextWorkout {
                    FFButton(title: "Начать следующую тренировку", variant: .secondary) {
                        ClientAnalytics.track(
                            .summaryNextWorkoutTapped,
                            properties: ["workout_id": summary.id],
                        )
                        onStartNextWorkout()
                    }
                } else if let onBackToWorkoutHub {
                    FFButton(title: "Вернуться к тренировкам", variant: .secondary) {
                        onBackToWorkoutHub()
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .ffScreenBackground()
        .task {
            ClientAnalytics.track(
                .workoutSummaryScreenOpened,
                properties: ["workout_id": summary.id],
            )
        }
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

    private func volumeComparisonText(comparison: WorkoutSummaryState.ComparisonDelta) -> String {
        guard let volumeDelta = comparison.volumeDelta else { return "—" }
        let previousVolume = summary.volume - volumeDelta
        if previousVolume > 0.1 {
            let percent = Int((volumeDelta / previousVolume) * 100)
            return "\(percent > 0 ? "+" : "")\(percent)%"
        }
        return signed(Int(volumeDelta))
    }
}

private struct TrainingTabContent: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let userSub: String
    let apiClient: APIClientProtocol?
    let onOpenPlan: () -> Void
    @Binding var resumeSessionRequest: ActiveWorkoutSession?
    let onResumeHandled: () -> Void
    let onRoutePresentationChanged: (Bool) -> Void
    private let trainingStore: any TrainingStore
    private let templateRepository: any WorkoutTemplateRepository
    private let exerciseCatalogRepository: any ExerciseCatalogRepository
    private let exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding

    @State private var sessionRoute: ActiveWorkoutSession?
    @State private var programWorkoutRoute: ProgramWorkoutRoute?
    @State private var programHistoryRoute: ProgramHistoryRoute?
    @State private var presetWorkoutRoute: PresetWorkoutRoute?
    @State private var recentWorkoutDetailsRoute: RecentWorkoutDetailsRoute?
    @State private var repeatWorkoutPlanningRoute: RepeatWorkoutPlanningRoute?
    @State private var modalRoute: TrainingModalRoute?
    @State private var activePresentationMarkers: Set<String> = []

    private struct ProgramHistoryRoute: Identifiable, Hashable {
        let programId: String
        let programTitle: String

        var id: String {
            programId
        }
    }

    private enum TrainingModalRoute: Identifiable, Equatable {
        case quickBuilder
        case templateLibrary

        var id: String {
            switch self {
            case .quickBuilder:
                return "quick_builder"
            case .templateLibrary:
                return "template_library"
            }
        }
    }

    init(
        store: StoreOf<RootFeature>,
        environment: AppEnvironment,
        userSub: String,
        apiClient: APIClientProtocol?,
        onOpenPlan: @escaping () -> Void,
        resumeSessionRequest: Binding<ActiveWorkoutSession?>,
        onResumeHandled: @escaping () -> Void,
        onRoutePresentationChanged: @escaping (Bool) -> Void,
    ) {
        self.store = store
        self.environment = environment
        self.userSub = userSub
        self.apiClient = apiClient
        self.onOpenPlan = onOpenPlan
        _resumeSessionRequest = resumeSessionRequest
        self.onResumeHandled = onResumeHandled
        self.onRoutePresentationChanged = onRoutePresentationChanged
        trainingStore = LocalTrainingStore()
        templateRepository = BackendWorkoutTemplateRepository(
            apiClient: apiClient as? AthleteWorkoutTemplatesAPIClientProtocol,
            cacheStore: trainingStore,
        )
        exerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: apiClient as? ExerciseCatalogAPIClientProtocol,
            userSub: userSub,
            templateRepository: templateRepository,
        )
        exercisePickerSuggestionsProvider = TrainingStoreExercisePickerSuggestionsProvider(
            userSub: userSub,
            athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            templateRepository: templateRepository,
            trainingStore: trainingStore,
        )
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
            onOpenPresetWorkout: { target in
                presetWorkoutRoute = PresetWorkoutRoute(
                    programId: target.programId,
                    workout: target.workout,
                    source: target.source,
                )
            },
            onStartQuickWorkout: {
                modalRoute = .quickBuilder
            },
            onOpenTemplates: {
                modalRoute = .templateLibrary
            },
            onRepeatWorkout: { record in
                Task {
                    await openRepeatWorkout(record)
                }
            },
            onOpenRecentWorkout: { record in
                recentWorkoutDetailsRoute = RecentWorkoutDetailsRoute(record: record)
            },
            onOpenPlan: {
                PlanNavigationCoordinator.shared.request(day: Date())
                onOpenPlan()
            },
            onOpenProgramHistory: { programId, programTitle in
                programHistoryRoute = ProgramHistoryRoute(programId: programId, programTitle: programTitle)
            },
        )
        .navigationDestination(item: $sessionRoute) { session in
            WorkoutLaunchView(
                userSub: session.userSub,
                programId: session.programId,
                workoutId: session.workoutId,
                apiClient: apiClient,
                source: session.source,
                onOpenPlan: {
                    sessionRoute = nil
                    onOpenPlan()
                },
            )
            .navigationBarBackButtonHidden(false)
            .onAppear {
                updatePresentationMarker("session:\(session.programId)::\(session.workoutId)", isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker("session:\(session.programId)::\(session.workoutId)", isPresented: false)
            }
        }
        .navigationDestination(item: $programWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.programId,
                workoutId: route.workoutId,
                apiClient: apiClient,
                onOpenPlan: {
                    programWorkoutRoute = nil
                    onOpenPlan()
                },
            )
            .navigationBarBackButtonHidden(false)
            .onAppear {
                updatePresentationMarker("program:\(route.id)", isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker("program:\(route.id)", isPresented: false)
            }
        }
        .navigationDestination(item: $presetWorkoutRoute) { route in
            WorkoutLaunchView(
                userSub: userSub,
                programId: route.programId ?? route.source.rawValue,
                workoutId: route.workout.id,
                apiClient: apiClient,
                presetWorkout: route.workout,
                source: route.source,
                onOpenPlan: {
                    presetWorkoutRoute = nil
                    onOpenPlan()
                },
            )
            .navigationBarBackButtonHidden(false)
            .onAppear {
                updatePresentationMarker("preset:\(route.id)", isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker("preset:\(route.id)", isPresented: false)
            }
        }
        .navigationDestination(item: $programHistoryRoute) { route in
            ProgramWorkoutHistoryScreen(
                viewModel: ProgramWorkoutHistoryViewModel(
                    programId: route.programId,
                    programTitle: route.programTitle,
                    userSub: userSub,
                    workoutsClient: makeWorkoutsClient(),
                ),
                onOpenWorkout: { workoutId in
                    programWorkoutRoute = ProgramWorkoutRoute(programId: route.programId, workoutId: workoutId)
                },
                onOpenCompletedWorkout: { record in
                    recentWorkoutDetailsRoute = RecentWorkoutDetailsRoute(record: record)
                },
            )
            .navigationBarBackButtonHidden(false)
            .onAppear {
                updatePresentationMarker("history:\(route.id)", isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker("history:\(route.id)", isPresented: false)
            }
        }
        .navigationDestination(item: $recentWorkoutDetailsRoute) { route in
            RecentWorkoutDetailsView(
                record: route.record,
                onRepeat: { workout in
                    Task {
                        await openRepeatWorkout(route.record, preferredWorkout: workout)
                    }
                },
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
            )
            .navigationBarBackButtonHidden(false)
            .onAppear {
                updatePresentationMarker("recent:\(route.id)", isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker("recent:\(route.id)", isPresented: false)
            }
        }
        .sheet(item: $repeatWorkoutPlanningRoute) { route in
            RepeatWorkoutPlanningSheet(
                userSub: userSub,
                workout: route.workout,
                source: route.source,
                athleteTrainingClient: apiClient as? AthleteTrainingClientProtocol,
                onClose: {
                    repeatWorkoutPlanningRoute = nil
                },
                onSaved: { day in
                    repeatWorkoutPlanningRoute = nil
                    recentWorkoutDetailsRoute = nil
                    PlanNavigationCoordinator.shared.request(day: day)
                    onOpenPlan()
                }
            )
        }
        .fullScreenCover(item: $modalRoute) { route in
            trainingModal(route)
        }
        .task {
            handleExternalResumeRequest()
            onRoutePresentationChanged(isRoutePresentationActive)
        }
        .onChange(of: resumeSessionRequest?.workoutId) { _, _ in
            handleExternalResumeRequest()
        }
        .onChange(of: hasActivePresentation) { _, _ in
            onRoutePresentationChanged(isRoutePresentationActive)
        }
        .onChange(of: activePresentationMarkers.count) { _, _ in
            onRoutePresentationChanged(isRoutePresentationActive)
        }
    }

    private var isRoutePresentationActive: Bool {
        hasActivePresentation || !activePresentationMarkers.isEmpty
    }

    private var hasActivePresentation: Bool {
        sessionRoute != nil
            || programWorkoutRoute != nil
            || programHistoryRoute != nil
            || presetWorkoutRoute != nil
            || recentWorkoutDetailsRoute != nil
            || repeatWorkoutPlanningRoute != nil
            || modalRoute != nil
    }

    private func updatePresentationMarker(_ marker: String, isPresented: Bool) {
        if isPresented {
            activePresentationMarkers.insert(marker)
            return
        }
        activePresentationMarkers.remove(marker)
    }

    private func handleExternalResumeRequest() {
        guard let requested = resumeSessionRequest else { return }
        sessionRoute = requested
        resumeSessionRequest = nil
        onResumeHandled()
    }

    private func openRepeatWorkout(_ record: CompletedWorkoutRecord, preferredWorkout: WorkoutDetailsModel? = nil) async {
        switch await resolveRepeatWorkoutTarget(
            for: record,
            templateFallback: .templateLibrary,
            preferredWorkout: preferredWorkout,
        ) {
        case let .program(route):
            programWorkoutRoute = route
        case let .preset(route):
            repeatWorkoutPlanningRoute = RepeatWorkoutPlanningRoute(
                workout: route.workout,
                source: route.source,
            )
        case .quickBuilder:
            modalRoute = .quickBuilder
        case .templateLibrary:
            modalRoute = .templateLibrary
        }
    }

    @ViewBuilder
    private func trainingModal(_ route: TrainingModalRoute) -> some View {
        switch route {
        case .quickBuilder:
            NavigationStack {
                QuickWorkoutBuilderView(
                    exerciseCatalogRepository: exerciseCatalogRepository,
                    exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
                ) { workout in
                    Task {
                        await openBuiltCustomWorkout(workout)
                    }
                }
            }
            .onAppear {
                updatePresentationMarker(route.id, isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker(route.id, isPresented: false)
                if modalRoute == route {
                    modalRoute = nil
                }
            }
        case .templateLibrary:
            NavigationStack {
                TemplateLibraryView(
                    viewModel: TemplateLibraryViewModel(
                        userSub: userSub,
                        templateRepository: templateRepository,
                    ),
                    exerciseCatalogRepository: exerciseCatalogRepository,
                    exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
                    onStartTemplate: { workout in
                        presetWorkoutRoute = PresetWorkoutRoute(programId: nil, workout: workout, source: .template)
                    },
                )
            }
            .onAppear {
                updatePresentationMarker(route.id, isPresented: true)
            }
            .onDisappear {
                updatePresentationMarker(route.id, isPresented: false)
                if modalRoute == route {
                    modalRoute = nil
                }
            }
        }
    }

    private func makeWorkoutsClient() -> any WorkoutsClientProtocol {
        if let programsClient = apiClient as? ProgramsClientProtocol {
            return WorkoutsClient(programsClient: programsClient)
        }
        return UnavailableWorkoutsClient()
    }

    @MainActor
    private func presentBuiltWorkout(_ workout: WorkoutDetailsModel) {
        presetWorkoutRoute = PresetWorkoutRoute(programId: nil, workout: workout, source: .freestyle)
    }

    private func openBuiltCustomWorkout(_ workout: WorkoutDetailsModel) async {
        if let athleteTrainingClient = apiClient as? AthleteTrainingClientProtocol {
            let result = await athleteTrainingClient.createCustomWorkout(
                request: workout.asCreateCustomWorkoutRequest(),
            )
            if case let .success(detailsResponse) = result {
                await MainActor.run {
                    presentBuiltWorkout(detailsResponse.asWorkoutDetailsModel())
                }
                return
            }
        }

        await MainActor.run {
            presentBuiltWorkout(workout)
        }
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
            .navigationBarBackButtonHidden(false)
        }
    }
}

extension ActiveWorkoutSession: Identifiable {
    var id: String {
        "\(userSub)::\(programId)::\(workoutId)"
    }
}
