import SwiftUI

struct StartWorkoutCard: View {
    var isLoading = false
    let syncStatus: SyncStatusKind
    let showsCacheTag: Bool
    let onStartWorkout: () -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Начните тренировку")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Быстрый вход в текущую сессию. Планирование и шаблоны доступны ниже.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(title: "Начать тренировку", variant: .primary, isLoading: isLoading, action: onStartWorkout)
            }
        }
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
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
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

                Text(detailText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(title: buttonTitle, variant: .primary, action: onStartWorkout)
            }
        }
    }
}
