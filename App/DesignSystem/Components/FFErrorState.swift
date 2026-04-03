import SwiftUI

struct FFErrorState: View {
    var title: String = "Что-то пошло не так"
    var message: String = "Попробуйте обновить экран"
    var retryTitle: String = "Повторить"
    var fillsAvailableHeight = false
    var onRetry: () -> Void = {}

    var body: some View {
        FFCard {
            VStack(spacing: FFSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FFColors.danger)
                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.center)
                FFButton(title: retryTitle, variant: .secondary, action: onRetry)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            .padding(.vertical, FFSpacing.md)
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
    }
}
