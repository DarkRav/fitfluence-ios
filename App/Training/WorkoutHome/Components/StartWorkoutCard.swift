import SwiftUI

struct StartWorkoutCard: View {
    var isLoading = false
    let onStartWorkout: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Начать тренировку")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Text("Выберите формат и начните тренировку")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                WorkoutPrimaryButton(
                    title: "Начать тренировку",
                    isLoading: isLoading,
                    action: onStartWorkout,
                )
            }
        }
    }
}
