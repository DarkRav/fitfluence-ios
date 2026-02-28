import ComposableArchitecture
import SwiftUI

struct WorkoutCompletionView: View {
    let store: StoreOf<WorkoutCompletionFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        Text("Тренировка завершена")
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)

                        Text("Отличная работа. Краткая сводка по выполнению:")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)

                        Text(
                            "Упражнений выполнено: \(viewStore.summary.completedExercises) из \(viewStore.summary.totalExercises)",
                        )
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textPrimary)

                        Text("Отмечено подходов: \(viewStore.summary.completedSets)")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                    }
                }

                FFButton(title: "Готово", variant: .primary) {
                    viewStore.send(.doneTapped)
                }
                .accessibilityLabel("Готово")
                .accessibilityHint("Закрыть экран завершения тренировки")

                Spacer()
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
            .background(FFColors.background)
        }
    }
}
