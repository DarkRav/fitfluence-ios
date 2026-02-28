import SwiftUI

struct FFLoadingState: View {
    var title: String = "Загрузка"

    var body: some View {
        FFCard {
            VStack(spacing: FFSpacing.sm) {
                ProgressView()
                    .tint(FFColors.accent)
                    .controlSize(.regular)
                Text(title)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.md)
        }
    }
}
