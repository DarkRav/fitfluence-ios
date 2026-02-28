import SwiftUI

struct FFEmptyState: View {
    var title: String = "Пока пусто"
    var message: String = "Контент появится чуть позже"

    var body: some View {
        FFCard {
            VStack(spacing: FFSpacing.sm) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FFColors.gray300)
                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .padding(.vertical, FFSpacing.md)
        }
    }
}
