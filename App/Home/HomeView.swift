import ComposableArchitecture
import Observation
import SwiftUI

struct HomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    hero(viewStore)

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Ваш фокус")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            if let programTitle = viewStore.programTitle, !programTitle.isEmpty {
                                Text("Программа: \(programTitle)")
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }

                            Text(viewStore.subtitle)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Режим данных")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Оффлайн: изменения тренировки сохраняются на устройстве.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .background(FFColors.background)
            .onAppear { viewStore.send(.onAppear) }
        }
    }

    private func hero(_ viewStore: ViewStore<HomeFeature.State, HomeFeature.Action>) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                Text("Сегодня")
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)

                if viewStore.isLoading {
                    FFLoadingState(title: "Проверяем прогресс")
                } else {
                    FFButton(title: viewStore.primaryTitle, variant: .primary) {
                        viewStore.send(.primaryTapped)
                    }
                    .accessibilityLabel(viewStore.primaryTitle)

                    Text(viewStore.activeSession == nil
                        ? "Главный сценарий: выбрать программу и начать тренировку."
                        : "Главный сценарий: продолжить тренировку без потери прогресса.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }
            }
        }
    }
}

enum HomePrimaryAction: Equatable {
    case continueSession(programId: String, workoutId: String)
    case startNext(programId: String, workoutId: String)
    case repeatLast(programId: String, workoutId: String)
    case openPicker
}

@Observable
final class HomeViewModel {
    private let sessionManager: WorkoutSessionManager
    private let cacheStore: CacheStore
    private let userSub: String

    var isLoading = false
    var activeSession: ActiveWorkoutSession?
    var activeProgramId: String?
    var nextWorkout: WorkoutSummary?
    var lastWorkout: WorkoutSummary?

    init(
        userSub: String,
        sessionManager: WorkoutSessionManager,
        cacheStore: CacheStore = CompositeCacheStore(),
    ) {
        self.userSub = userSub
        self.sessionManager = sessionManager
        self.cacheStore = cacheStore
    }

    var primaryTitle: String {
        if activeSession != nil {
            return "Продолжить тренировку"
        }
        if nextWorkout != nil {
            return "Начать тренировку"
        }
        if lastWorkout != nil {
            return "Повторить последнюю"
        }
        return "Выбрать тренировку"
    }

    var primaryAction: HomePrimaryAction {
        if let activeSession {
            return .continueSession(programId: activeSession.programId, workoutId: activeSession.workoutId)
        }
        if let nextWorkout, let activeProgramId {
            return .startNext(programId: activeProgramId, workoutId: nextWorkout.id)
        }
        if let lastWorkout, let activeProgramId {
            return .repeatLast(programId: activeProgramId, workoutId: lastWorkout.id)
        }
        return .openPicker
    }

    @MainActor
    func onAppear() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        let resolvedSession = await sessionManager.latestActiveSession(userSub: userSub)
        activeSession = resolvedSession

        if let resolvedSession {
            activeProgramId = resolvedSession.programId
            let workouts = await cacheStore.get(
                "workouts.list:\(resolvedSession.programId)",
                as: [WorkoutSummary].self,
                namespace: userSub,
            ) ?? []
            nextWorkout = workouts.sorted(by: { $0.dayOrder < $1.dayOrder }).first
            lastWorkout = workouts.sorted(by: { $0.dayOrder > $1.dayOrder }).first
        } else {
            activeProgramId = nil
            nextWorkout = nil
            lastWorkout = nil
        }
        isLoading = false
    }
}

struct HomeViewV2: View {
    @State var viewModel: HomeViewModel
    let onPrimaryAction: (HomePrimaryAction) -> Void
    let onOpenPlan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                hero
                nextWorkoutCard
                lastWorkoutCard
                summaryCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .task {
            await viewModel.onAppear()
        }
        .navigationTitle("Сегодня")
    }

    private var hero: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                Text("Тренировка на сегодня")
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)
                if viewModel.isLoading {
                    FFLoadingState(title: "Готовим план")
                } else {
                    FFButton(title: viewModel.primaryTitle, variant: .primary) {
                        onPrimaryAction(viewModel.primaryAction)
                    }
                }
            }
        }
    }

    private var nextWorkoutCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Следующая тренировка")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if let nextWorkout = viewModel.nextWorkout {
                    Text(nextWorkout.title)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("\(nextWorkout.exerciseCount) упражнений")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    Text("Выберите тренировку в плане.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
                FFButton(title: "Открыть план", variant: .secondary) {
                    onOpenPlan()
                }
            }
        }
    }

    private var lastWorkoutCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Последняя тренировка")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if let lastWorkout = viewModel.lastWorkout {
                    Text(lastWorkout.title)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textPrimary)
                    FFButton(title: "Повторить", variant: .secondary) {
                        if let programId = viewModel.activeProgramId {
                            onPrimaryAction(.repeatLast(programId: programId, workoutId: lastWorkout.id))
                        }
                    }
                } else {
                    Text("Пока нет завершённых тренировок.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var summaryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Режим данных")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Оффлайн: тренировка и прогресс сохраняются на устройстве.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }
}

private extension HomePrimaryAction {
    var programId: String? {
        switch self {
        case let .continueSession(programId, _): return programId
        case let .startNext(programId, _): return programId
        case let .repeatLast(programId, _): return programId
        case .openPicker: return nil
        }
    }
}

#Preview("Home V2") {
    NavigationStack {
        HomeViewV2(
            viewModel: HomeViewModel(
                userSub: "athlete-1",
                sessionManager: WorkoutSessionManager(),
            ),
            onPrimaryAction: { _ in },
            onOpenPlan: {},
        )
    }
}
