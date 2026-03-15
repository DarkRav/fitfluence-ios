import SwiftUI

struct WorkoutHomeScreen: View {
    @State var viewModel: WorkoutHomeViewModel

    let onContinueSession: (ActiveWorkoutSession) -> Void
    let onOpenRemoteWorkout: (WorkoutHomeViewModel.RemoteWorkoutTarget) -> Void
    let onOpenPresetWorkout: (WorkoutHomeViewModel.PresetWorkoutTarget) -> Void
    let onStartQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatWorkout: (CompletedWorkoutRecord) -> Void
    let onOpenRecentWorkout: (CompletedWorkoutRecord) -> Void
    let onOpenPlan: () -> Void
    let onOpenCatalog: () -> Void
    let onOpenProgramHistory: (_ programId: String, _ programTitle: String) -> Void

    private let sectionSpacing: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(spacing: sectionSpacing) {
                if viewModel.isOffline {
                    offlineBanner
                }

                if let resumeWorkout = viewModel.resumeWorkout {
                    ResumeWorkoutCard(
                        workoutName: resumeWorkout.workoutName,
                        metricsText: resumeWorkout.metricsText,
                        onContinue: runResumeWorkout,
                    )
                } else if let todayWorkout = viewModel.todayWorkout {
                    TodayWorkoutCard(
                        title: todayWorkout.title,
                        subtitle: todayWorkout.subtitle,
                        detailText: todayWorkout.detailText,
                        buttonTitle: todayWorkout.buttonTitle,
                        syncStatus: viewModel.syncIndicator,
                        showsCacheTag: viewModel.isShowingCachedData,
                        onStartWorkout: runTodayWorkout,
                    )
                } else {
                    StartWorkoutCard(
                        isLoading: false,
                        syncStatus: viewModel.syncIndicator,
                        showsCacheTag: viewModel.isShowingCachedData,
                        onStartWorkout: runStartWorkout,
                    )
                }

                if viewModel.hasResumeWorkout,
                   (viewModel.syncIndicator != .synced || viewModel.isShowingCachedData)
                {
                    syncStatusCard
                }

                if let progress = viewModel.programProgress,
                   viewModel.hasActiveProgram
                {
                    ProgramProgressCard(
                        programTitle: progress.title,
                        detailsLine: progress.detailsLine,
                        progressText: progress.progressText,
                        progressValue: progress.progressValue,
                        isCompleted: progress.isCompleted,
                        isActionEnabled: true,
                        onAction: runProgramAction,
                        onOpenHistory: {
                            onOpenProgramHistory(progress.programId, progress.title)
                        }
                    )
                }

                QuickActionsSection(
                    onStartEmptyWorkout: {
                        ClientAnalytics.track(.workoutQuickButtonTapped)
                        onStartQuickWorkout()
                    },
                    onBrowsePrograms: {
                        onOpenCatalog()
                    },
                    onOpenPlan: {
                        onOpenPlan()
                    },
                    onOpenTemplates: {
                        ClientAnalytics.track(.workoutTemplatesButtonTapped)
                        onOpenTemplates()
                    },
                )

                RecentWorkoutsSection(
                    workouts: viewModel.recentWorkouts,
                    isLoading: viewModel.isLoading,
                    onOpenWorkout: { workout in
                        onOpenRecentWorkout(workout)
                    },
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.reload()
        }
        .task {
            ClientAnalytics.track(.workoutHubScreenOpened)
            await viewModel.onAppear()
        }
    }

    private var offlineBanner: some View {
        WorkoutCardContainer(cornerRadius: 18, padding: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FFColors.primary)

                Text("Вы офлайн. Показываем локальные данные")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(2)

                Spacer(minLength: 4)
            }
        }
    }

    private var syncStatusCard: some View {
        WorkoutCardContainer(cornerRadius: 18, padding: 12) {
            SyncStatusIndicator(
                status: viewModel.syncIndicator,
                showsCacheTag: viewModel.isShowingCachedData,
            )
        }
    }

    private func runResumeWorkout() {
        guard let resumeWorkout = viewModel.resumeWorkout else { return }

        switch resumeWorkout.source {
        case let .local(session):
            onContinueSession(session)
        case let .remote(target):
            onOpenRemoteWorkout(target)
        }
    }

    private func runTodayWorkout() {
        guard let todayWorkout = viewModel.todayWorkout else {
            onOpenPlan()
            return
        }

        guard let launchTarget = todayWorkout.launchTarget else {
            onOpenPlan()
            return
        }

        switch launchTarget {
        case let .remote(target):
            onOpenRemoteWorkout(target)
        case let .preset(target):
            onOpenPresetWorkout(target)
        }
    }

    private func runStartWorkout() {
        guard viewModel.startWorkoutTarget != nil else {
            ClientAnalytics.track(.workoutStartButtonTapped)
            onStartQuickWorkout()
            return
        }

        ClientAnalytics.track(.workoutStartNextButtonTapped)
        Task {
            if let target = await viewModel.startNextWorkout() {
                onOpenRemoteWorkout(target)
            } else {
                onStartQuickWorkout()
            }
        }
    }

    private func runProgramAction() {
        if viewModel.isProgramCompleted {
            ClientAnalytics.track(
                .workoutStartButtonTapped,
                properties: ["source": "hub_program_completed"],
            )
            onOpenCatalog()
            return
        }

        guard viewModel.canContinueProgram else {
            onStartQuickWorkout()
            return
        }

        ClientAnalytics.track(
            .workoutStartNextButtonTapped,
            properties: ["source": "hub_program"],
        )

        Task {
            if let target = await viewModel.continueProgram() {
                onOpenRemoteWorkout(target)
            }
        }
    }

}

#Preview("Экран тренировки") {
    NavigationStack {
        WorkoutHomeScreen(
            viewModel: WorkoutHomeViewModel(userSub: "preview"),
            onContinueSession: { _ in },
            onOpenRemoteWorkout: { _ in },
            onOpenPresetWorkout: { _ in },
            onStartQuickWorkout: {},
            onOpenTemplates: {},
            onRepeatWorkout: { _ in },
            onOpenRecentWorkout: { _ in },
            onOpenPlan: {},
            onOpenCatalog: {},
            onOpenProgramHistory: { _, _ in },
        )
    }
}
