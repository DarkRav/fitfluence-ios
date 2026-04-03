import SwiftUI

struct ResumeWorkoutCard: View {
    let workoutName: String
    let metricsText: String
    let onContinue: () -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Продолжить тренировку")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text(workoutName)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(2)

                Text(metricsText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(2)

                FFButton(title: "Продолжить", variant: .secondary, action: onContinue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
    }
}
