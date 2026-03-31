import SwiftUI

struct WorkoutCardContainer<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    var minHeight: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FFColors.gray700.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: FFTheme.Shadow.color, radius: FFTheme.Shadow.radius, x: 0, y: FFTheme.Shadow.y)
    }

    private var cardBackground: some View {
        FFColors.surface
    }
}
