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

    @State private var selectedTab: ShellTab = .today

    enum ShellTab: Hashable {
        case today
        case plan
        case progress
        case profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayHubView(
                    me: me,
                    apiClient: apiClient,
                    onOpenPlan: { selectedTab = .plan },
                )
            }
            .tabItem {
                Label("Сегодня", systemImage: "sun.max")
            }
            .tag(ShellTab.today)

            NavigationStack {
                PlanTabContent(
                    store: store,
                    environment: environment,
                    apiClient: apiClient,
                    userSub: me.subject ?? "anonymous",
                )
            }
            .tabItem {
                Label("План", systemImage: "list.bullet.rectangle")
            }
            .tag(ShellTab.plan)

            NavigationStack {
                ProgressTabView(userSub: me.subject ?? "anonymous")
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
        .tint(FFColors.accent)
    }
}

private struct PlanTabContent: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let apiClient: APIClientProtocol?
    let userSub: String

    @State private var viewModel: CatalogViewModel

    private struct ViewState: Equatable {
        var isProgramDetailsPresented: Bool
        var selectedProgram: RootFeature.State.SelectedProgram?
    }

    init(
        store: StoreOf<RootFeature>,
        environment: AppEnvironment,
        apiClient: APIClientProtocol?,
        userSub: String,
    ) {
        self.store = store
        self.environment = environment
        self.apiClient = apiClient
        self.userSub = userSub
        _viewModel = State(
            initialValue: CatalogViewModel(
                userSub: userSub,
                programsClient: apiClient as? ProgramsClientProtocol,
                onUnauthorized: {
                    store.send(.logoutTapped)
                },
            ),
        )
    }

    var body: some View {
        WithViewStore(
            store,
            observe: { ViewState(
                isProgramDetailsPresented: $0.selectedProgram != nil,
                selectedProgram: $0.selectedProgram,
            ) },
        ) { viewStore in
            CatalogScreen(
                viewModel: viewModel,
                environment: environment,
                onProgramTap: { programID in
                    store.send(.openProgram(programId: programID, userSub: userSub))
                },
            )
            .navigationTitle("План")
            .navigationDestination(
                isPresented: Binding(
                    get: { viewStore.isProgramDetailsPresented },
                    set: { isPresented in
                        if !isPresented {
                            store.send(.programDetailsDismissed)
                        }
                    },
                ),
            ) {
                if let selectedProgram = viewStore.selectedProgram {
                    ProgramDetailsScreen(
                        viewModel: ProgramDetailsViewModel(
                            programId: selectedProgram.programId,
                            userSub: selectedProgram.userSub,
                            programsClient: apiClient as? ProgramsClientProtocol,
                        ),
                        apiClient: apiClient,
                    )
                    .navigationTitle("Программа")
                }
            }
        }
    }
}

private struct TodayHubView: View {
    let me: MeResponse
    let apiClient: APIClientProtocol?
    let onOpenPlan: () -> Void

    @State private var route: WorkoutRoute?
    @State private var isQuickBuilderPresented = false
    @State private var isTemplateLibraryPresented = false
    @State private var quickWorkout: QuickWorkoutRoute?

    private struct WorkoutRoute: Identifiable, Hashable {
        let programId: String
        let workoutId: String
        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    private struct QuickWorkoutRoute: Identifiable {
        let workout: WorkoutDetailsModel
        var id: String {
            workout.id
        }
    }

    var body: some View {
        HomeViewV2(
            viewModel: HomeViewModel(
                userSub: me.subject ?? "anonymous",
                sessionManager: WorkoutSessionManager(),
                programsClient: apiClient as? ProgramsClientProtocol,
            ),
            onPrimaryAction: { action in
                switch action {
                case let .continueSession(programId, workoutId),
                     let .startNext(programId, workoutId),
                     let .repeatLast(programId, workoutId):
                    route = WorkoutRoute(programId: programId, workoutId: workoutId)
                case .openPicker:
                    onOpenPlan()
                case .quickWorkout:
                    isQuickBuilderPresented = true
                }
            },
            onOpenPlan: onOpenPlan,
            onOpenTemplates: {
                isTemplateLibraryPresented = true
            },
        )
        .navigationDestination(item: $route) { route in
            WorkoutLaunchView(
                userSub: me.subject ?? "anonymous",
                programId: route.programId,
                workoutId: route.workoutId,
                apiClient: apiClient,
            )
        }
        .navigationDestination(item: $quickWorkout) { route in
            WorkoutLaunchView(
                userSub: me.subject ?? "anonymous",
                programId: "freestyle",
                workoutId: route.workout.id,
                apiClient: apiClient,
                presetWorkout: route.workout,
                source: .freestyle,
            )
        }
        .fullScreenCover(isPresented: $isQuickBuilderPresented) {
            NavigationStack {
                QuickWorkoutBuilderView { workout in
                    quickWorkout = QuickWorkoutRoute(workout: workout)
                }
            }
        }
        .fullScreenCover(isPresented: $isTemplateLibraryPresented) {
            NavigationStack {
                TemplateLibraryView(
                    viewModel: TemplateLibraryViewModel(userSub: me.subject ?? "anonymous"),
                    onStartTemplate: { workout in
                        quickWorkout = QuickWorkoutRoute(workout: workout)
                    },
                )
            }
        }
    }
}

struct WorkoutLaunchView: View {
    let userSub: String
    let programId: String
    let workoutId: String
    let apiClient: APIClientProtocol?
    var presetWorkout: WorkoutDetailsModel?
    var source: WorkoutSource = .program

    @State private var details: WorkoutDetailsModel?
    @State private var error: UserFacingError?
    @State private var isLoading = false
    @State private var completionSummary: WorkoutPlayerViewModel.CompletionSummary?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                FFLoadingState(title: "Открываем тренировку")
                    .padding(.horizontal, FFSpacing.md)
            } else if let details {
                WorkoutPlayerViewV2(
                    viewModel: WorkoutPlayerViewModel(
                        userSub: userSub,
                        programId: programId,
                        workout: details,
                        source: source,
                    ),
                    onExit: { dismiss() },
                    onFinish: { summary in
                        completionSummary = summary
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
        .sheet(item: $completionSummary) { summary in
            WorkoutCompletionViewV2(summary: summary) {
                completionSummary = nil
                dismiss()
            }
            .presentationDetents([.medium])
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let presetWorkout {
            details = presetWorkout
            error = nil
            return
        }

        if let apiClient, let programsClient = apiClient as? ProgramsClientProtocol {
            let workoutsClient = WorkoutsClient(programsClient: programsClient)
            let result = await workoutsClient.getWorkoutDetails(programId: programId, workoutId: workoutId)
            switch result {
            case let .success(details):
                self.details = details
                self.error = nil
                return
            case let .failure(apiError):
                self.error = apiError.userFacing(context: .workoutPlayer)
            }
        }

        let cacheStore = CompositeCacheStore()
        if let cached = await cacheStore.get(
            "workout.details:\(programId):\(workoutId)",
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) {
            details = cached
            error = nil
        } else if error == nil {
            error = UserFacingError(
                title: "Нет данных тренировки",
                message: "Откройте тренировку из плана при подключении к сети.",
            )
        }
    }
}

extension WorkoutPlayerViewModel.CompletionSummary: Identifiable {
    var id: String {
        "\(workoutTitle)-\(completedSets)-\(totalSets)"
    }
}

private struct ProgressTabView: View {
    let userSub: String

    var body: some View {
        TrainingInsightsView(viewModel: TrainingInsightsViewModel(userSub: userSub))
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
