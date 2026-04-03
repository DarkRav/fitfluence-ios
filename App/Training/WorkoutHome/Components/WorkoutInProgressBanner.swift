import SwiftUI

struct WorkoutInProgressBanner: View {
    let workoutName: String?
    let detailsText: String?
    var iconSystemName: String = "figure.strengthtraining.traditional"
    let onContinue: () -> Void

    var body: some View {
        FFCard(padding: FFSpacing.sm) {
            HStack(alignment: .top, spacing: FFSpacing.sm) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FFColors.accent)
                    .frame(width: 24, height: 24, alignment: .center)

                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Тренировка в процессе")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)

                    if let workoutName = normalized(workoutName) {
                        Text(workoutName)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(2)
                    }

                    if let detailsText = normalized(detailsText) {
                        Text(detailsText)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: FFSpacing.sm)

                FFButton(title: "Продолжить", variant: .secondary, action: onContinue)
                    .frame(maxWidth: 156)
            }
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
