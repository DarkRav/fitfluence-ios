import SwiftUI

struct WorkoutInProgressBanner: View {
    let workoutName: String?
    let detailsText: String?
    var iconSystemName: String = "figure.strengthtraining.traditional"
    let onContinue: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: FFSpacing.sm) {
            HStack(alignment: .top, spacing: FFSpacing.xs) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(FFColors.accent)
                    .frame(width: 22, height: 22, alignment: .center)

                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Тренировка в процессе")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)

                    if let workoutName = normalized(workoutName) {
                        Text(workoutName)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(1)
                    }

                    if let detailsText = normalized(detailsText) {
                        Text(detailsText)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: FFSpacing.sm)

            FFButton(title: "Продолжить", variant: .secondary, action: onContinue)
                .frame(maxWidth: 164)
        }
        .frame(minHeight: 110)
        .padding(.horizontal, FFSpacing.sm)
        .padding(.vertical, FFSpacing.xs)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
