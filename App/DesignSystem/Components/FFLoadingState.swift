import SwiftUI

struct FFLoadingState: View {
    var title: String = "Загрузка"

    var body: some View {
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
        .frame(minHeight: 140)
        .padding(.vertical, FFSpacing.md)
    }
}

struct FFScreenSpinner: View {
    var body: some View {
        ZStack {
            FFColors.background
            ProgressView()
                .tint(FFColors.accent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
