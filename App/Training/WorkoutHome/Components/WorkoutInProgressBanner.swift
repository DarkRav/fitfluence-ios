import SwiftUI

struct WorkoutInProgressBanner: View {
    let subtitle: String
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text("Тренировка в процессе")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Text(subtitle)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: FFSpacing.sm)

            FFButton(title: "Продолжить", variant: .secondary, action: onContinue)
                .frame(maxWidth: 164)
        }
        .padding(.horizontal, FFSpacing.sm)
        .padding(.vertical, FFSpacing.xs)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }
}

