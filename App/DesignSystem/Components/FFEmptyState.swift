import SwiftUI

struct FFEmptyState: View {
    var title: String = "Пока пусто"
    var message: String = "Контент появится чуть позже"

    var body: some View {
        FFCard {
            VStack(spacing: FFSpacing.xs) {
                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(message)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.md)
        }
    }
}
