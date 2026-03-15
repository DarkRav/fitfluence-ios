import SwiftUI

struct StartWorkoutCard: View {
    var isLoading = false
    let syncStatus: SyncStatusKind
    let showsCacheTag: Bool
    let onStartWorkout: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Тренировка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)

                        Text("Один главный вход в тренировку: начните сейчас и логируйте без лишних шагов.")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    Spacer(minLength: 8)

                    SyncStatusIndicator(
                        status: syncStatus,
                        compact: true,
                    )
                }

                if showsCacheTag {
                    cacheTag
                }

                WorkoutPrimaryButton(
                    title: "Начать тренировку",
                    isLoading: isLoading,
                    action: onStartWorkout,
                )
            }
        }
    }

    private var cacheTag: some View {
        Text("Показываем сохранённые данные")
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(FFColors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(FFColors.primary.opacity(0.14))
            .clipShape(Capsule())
    }
}

struct TodayWorkoutCard: View {
    let title: String
    let subtitle: String
    let detailText: String
    let buttonTitle: String
    let syncStatus: SyncStatusKind
    let showsCacheTag: Bool
    let onStartWorkout: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Тренировка на сегодня")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)

                        Text(title)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(2)

                        Text(subtitle)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    SyncStatusIndicator(
                        status: syncStatus,
                        compact: true,
                    )
                }

                Text(detailText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                if showsCacheTag {
                    Text("Показываем сохранённые данные")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(FFColors.primary.opacity(0.14))
                        .clipShape(Capsule())
                }

                WorkoutPrimaryButton(
                    title: buttonTitle,
                    action: onStartWorkout,
                )
            }
        }
    }
}
