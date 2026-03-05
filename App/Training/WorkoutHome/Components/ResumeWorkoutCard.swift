import SwiftUI

struct ResumeWorkoutCard: View {
    let workoutName: String
    let metricsText: String
    let onContinue: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 20, padding: 16, minHeight: 110) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Продолжить тренировку")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Text(workoutName)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(1)

                Text(metricsText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                WorkoutSecondaryButton(
                    title: "Продолжить",
                    height: 44,
                    cornerRadius: 14,
                    action: onContinue,
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
    }
}
