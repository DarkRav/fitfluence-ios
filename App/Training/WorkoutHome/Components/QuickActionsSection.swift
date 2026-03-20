import SwiftUI

struct QuickActionsSection: View {
    let onBuildTodayWorkout: () -> Void
    let onStartEmptyWorkout: () -> Void
    let onBrowsePrograms: () -> Void
    let onOpenPlan: () -> Void
    let onOpenTemplates: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        WorkoutCardContainer(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Другие действия")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                LazyVGrid(columns: columns, spacing: 8) {
                    QuickActionCard(
                        title: "Собрать на сегодня",
                        subtitle: "быстрый planning",
                        systemImage: "target",
                        action: onBuildTodayWorkout,
                    )

                    QuickActionCard(
                        title: "Пустая тренировка",
                        subtitle: "ручной старт",
                        systemImage: "bolt.fill",
                        action: onStartEmptyWorkout,
                    )

                    QuickActionCard(
                        title: "Программы",
                        subtitle: "от атлетов",
                        systemImage: "figure.strengthtraining.traditional",
                        action: onBrowsePrograms,
                    )

                    QuickActionCard(
                        title: "План",
                        subtitle: "сегодня и дальше",
                        systemImage: "calendar",
                        action: onOpenPlan,
                    )
                }

                Button(action: onOpenTemplates) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Открыть шаблоны")
                            .font(FFTypography.caption.weight(.semibold))
                    }
                    .foregroundStyle(FFColors.textSecondary)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
