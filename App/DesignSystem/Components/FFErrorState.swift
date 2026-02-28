import SwiftUI

struct FFErrorState: View {
    var title: String = "Что-то пошло не так"
    var message: String = "Попробуйте обновить экран"
    var retryTitle: String = "Повторить"
    var onRetry: () -> Void = {}

    var body: some View {
        FFCard {
            VStack(spacing: FFSpacing.sm) {
                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(message)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.center)
                FFButton(title: retryTitle, variant: .secondary, action: onRetry)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.md)
        }
    }
}
