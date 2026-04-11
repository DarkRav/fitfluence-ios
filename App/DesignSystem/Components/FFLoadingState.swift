import SwiftUI

private struct FFScreenBackgroundModifier: ViewModifier {
    let alignment: Alignment

    func body(content: Content) -> some View {
        ZStack(alignment: alignment) {
            FFColors.background.ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

extension View {
    func ffScreenBackground(alignment: Alignment = .top) -> some View {
        modifier(FFScreenBackgroundModifier(alignment: alignment))
    }
}

struct FFLoadingState: View {
    var title: String = "Загрузка"
    var fillsAvailableHeight = false

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
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
        .padding(.vertical, FFSpacing.md)
    }
}

struct FFScreenSpinner: View {
    var body: some View {
        ProgressView()
            .tint(FFColors.accent)
            .controlSize(.large)
            .ffScreenBackground(alignment: .center)
    }
}
