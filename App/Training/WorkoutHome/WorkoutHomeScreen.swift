import SwiftUI

struct WorkoutHomeScreen: View {
    @State var viewModel: WorkoutHomeViewModel

    let onContinueSession: (ActiveWorkoutSession) -> Void
    let onOpenRemoteWorkout: (WorkoutHomeViewModel.RemoteWorkoutTarget) -> Void
    let onStartQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatWorkout: (CompletedWorkoutRecord) -> Void
    let onOpenRecentWorkout: (CompletedWorkoutRecord) -> Void
    let onOpenCatalog: () -> Void
    let onOpenProgramHistory: (_ programId: String, _ programTitle: String) -> Void

    private let sectionSpacing: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(spacing: sectionSpacing) {
                if viewModel.isOffline {
                    offlineBanner
                }

                if !viewModel.hasResumeWorkout {
                    StartWorkoutCard(
                        isLoading: false,
                        onStartWorkout: runStartWorkout,
                    )
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
                    canRepeatLast: viewModel.lastCompleted != nil,
                    onQuickWorkout: {
                        ClientAnalytics.track(.workoutQuickButtonTapped)
                        onStartQuickWorkout()
                    },
                    onOpenTemplates: {
                        ClientAnalytics.track(.workoutTemplatesButtonTapped)
                        onOpenTemplates()
                    },
                    onRepeatLast: {
                        guard let lastCompleted = viewModel.lastCompleted else { return }
                        ClientAnalytics.track(.workoutRepeatLastButtonTapped)
                        onRepeatWorkout(lastCompleted)
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
            onStartQuickWorkout: {},
            onOpenTemplates: {},
            onRepeatWorkout: { _ in },
            onOpenRecentWorkout: { _ in },
            onOpenCatalog: {},
            onOpenProgramHistory: { _, _ in },
        )
    }
}
