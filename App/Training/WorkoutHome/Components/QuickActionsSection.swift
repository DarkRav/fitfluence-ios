import SwiftUI

struct QuickActionsSection: View {
    let canRepeatLast: Bool
    let onQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatLast: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        WorkoutCardContainer(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Быстрые действия")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                LazyVGrid(columns: columns, spacing: 8) {
                    QuickActionCard(
                        title: "Быстрая тренировка",
                        subtitle: "без программы",
                        systemImage: "bolt.fill",
                        action: onQuickWorkout,
                    )

                    QuickActionCard(
                        title: "Шаблоны",
                        subtitle: "ваши сохранённые",
                        systemImage: "square.stack.3d.up.fill",
                        action: onOpenTemplates,
                    )

                    QuickActionCard(
                        title: "Повторить последнюю",
                        subtitle: "последняя тренировка",
                        systemImage: "arrow.uturn.backward.circle.fill",
                        isEnabled: canRepeatLast,
                        action: onRepeatLast,
                    )
                }
            }
        }
    }
}
