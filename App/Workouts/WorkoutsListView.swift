import ComposableArchitecture
import SwiftUI

struct WorkoutsListView: View {
    let store: StoreOf<WorkoutsListFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                if viewStore.isLoading, viewStore.workouts.isEmpty {
                    FFLoadingState(title: "Загружаем тренировки")
                        .padding(.horizontal, FFSpacing.md)
                } else if let error = viewStore.error, viewStore.workouts.isEmpty {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                    ) {
                        viewStore.send(.retry)
                    }
                    .padding(.horizontal, FFSpacing.md)
                } else if viewStore.workouts.isEmpty {
                    FFEmptyState(
                        title: "В этой программе пока нет тренировок",
                        message: "Как только тренировки появятся, они будут доступны на этом экране.",
                    )
                    .padding(.horizontal, FFSpacing.md)
                } else {
                    ScrollView {
                        VStack(spacing: FFSpacing.sm) {
                            ForEach(viewStore.workouts) { workout in
                                workoutCard(
                                    workout,
                                    status: workoutStatus(for: workout, viewStore: viewStore),
                                ) {
                                    viewStore.send(.workoutTapped(workout.id))
                                }
                            }
                        }
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.vertical, FFSpacing.md)
                    }
                    .refreshable {
                        viewStore.send(.refresh)
                    }
                }
            }
            .background(FFColors.background)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    private func workoutCard(
        _ workout: WorkoutSummary,
        status: WorkoutProgressStatus,
        onTap: @escaping () -> Void,
    ) -> some View {
        Button(action: onTap) {
            FFCard {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("День \(workout.dayOrder)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)

                        Text(workout.title)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .multilineTextAlignment(.leading)

                        Text(detailsText(workout: workout))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    Spacer(minLength: FFSpacing.xs)

                    statusBadge(status: status)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Тренировка \(workout.title)")
        .accessibilityHint("Открыть тренировку")
    }

    private func detailsText(workout: WorkoutSummary) -> String {
        if let duration = workout.estimatedDurationMinutes {
            return "Упражнений: \(workout.exerciseCount) • ~\(duration) мин"
        }
        return "Упражнений: \(workout.exerciseCount)"
    }

    private func workoutStatus(
        for workout: WorkoutSummary,
        viewStore: ViewStore<WorkoutsListFeature.State, WorkoutsListFeature.Action>,
    ) -> WorkoutProgressStatus {
        viewStore.workoutStatuses[workout.id] ?? .notStarted
    }

    private func statusBadge(status: WorkoutProgressStatus) -> some View {
        Text(status.title)
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(statusColor(status).opacity(0.16))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: WorkoutProgressStatus) -> Color {
        switch status {
        case .notStarted:
            FFColors.gray300
        case .inProgress:
            FFColors.accent
        case .completed:
            FFColors.primary
        }
    }
}
